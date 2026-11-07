#include "CArchivePreview.h"
#include "archive.h"
#include "archive_entry.h"
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <xlocale.h>

int sa_zip_read(const char *path, const char *charset, const char *password, size_t max_entries,
                sa_zip_header_callback header, sa_zip_data_callback data, void *context,
                char *error_buffer, size_t error_capacity) {
    locale_t utf8 = newlocale(LC_CTYPE_MASK,"en_US.UTF-8",NULL);
    locale_t previous = utf8 ? uselocale(utf8):(locale_t)0;
    struct archive *reader = archive_read_new();
    int status = -1;
    if (!reader) goto finished;
    archive_read_support_format_zip(reader);
    if (archive_read_set_format_option(reader,"zip","hdrcharset",charset) != ARCHIVE_OK) goto failed;
    if (password && archive_read_add_passphrase(reader,password) != ARCHIVE_OK) goto failed;
    if (archive_read_open_filename(reader,path,65536) != ARCHIVE_OK) goto failed;
    struct archive_entry *entry = NULL;
    size_t count = 0;
    while ((status = archive_read_next_header(reader,&entry)) == ARCHIVE_OK || status == ARCHIVE_WARN) {
        if (++count > max_entries) { status = -3; goto finished; }
        const char *name = archive_entry_pathname_utf8(entry);
        if (!name) goto failed;
        const int type = archive_entry_filetype(entry);
        int action = header(name,archive_entry_size_is_set(entry) ? archive_entry_size(entry):0,type == S_IFDIR,
                            (type != S_IFREG && type != S_IFDIR) || archive_entry_hardlink(entry) != NULL,
                            archive_entry_is_encrypted(entry) == 1,archive_entry_perm(entry) & 0777,
                            archive_entry_mtime_is_set(entry), (int64_t)archive_entry_mtime(entry),
                            (int64_t)archive_entry_mtime_nsec(entry),context);
        if (action == 0) { status = -2; goto finished; }
        if (action == 2) { if (archive_read_data_skip(reader) < ARCHIVE_WARN) goto failed; continue; }
        char buffer[65536];
        la_ssize_t length;
        while ((length = archive_read_data(reader,buffer,sizeof(buffer))) > 0) {
            if (!data(buffer,(size_t)length,context)) { status = -2; goto finished; }
        }
        if (length < 0) goto failed;
    }
    if (status == ARCHIVE_EOF) { status = 0; goto finished; }
failed:
    if (error_buffer && error_capacity) snprintf(error_buffer,error_capacity,"%s",archive_error_string(reader) ? archive_error_string(reader):"ZIP okunamadı.");
    status = -1;
finished:
    if (reader) archive_read_free(reader);
    if (utf8) { uselocale(previous); freelocale(utf8); }
    return status;
}


struct preview_input {
    FILE *file;
    unsigned char buffer[65536];
    int64_t bytes_read;
    int64_t maximum_bytes;
    int limited;
    sa_preview_poll_callback poll;
    void *context;
};

static int preview_permitted(struct archive *reader, struct preview_input *input) {
    if (input->poll && !input->poll(input->context)) {
        archive_set_error(reader, ECANCELED, "Preview cancelled or timed out");
        return 0;
    }
    /* Check the innermost filter, not just the compressed input size. This also
     * bounds TAR data that libarchive must decompress to reach later headers. */
    if (input->bytes_read > input->maximum_bytes ||
        (archive_filter_code(reader, 0) != ARCHIVE_FILTER_NONE && archive_filter_bytes(reader, 0) > input->maximum_bytes)) {
        input->limited = 1;
        archive_set_error(reader, EFBIG, "Preview stream budget exceeded");
        return 0;
    }
    return 1;
}

static la_ssize_t preview_read(struct archive *reader, void *opaque, const void **buffer) {
    struct preview_input *input = opaque;
    if (!preview_permitted(reader, input)) return -1;
    size_t room = (size_t)(input->maximum_bytes - input->bytes_read);
    /* One extra byte distinguishes an exact-budget EOF from oversized input. */
    size_t amount = room < sizeof(input->buffer) ? room + 1 : sizeof(input->buffer);
    size_t count = fread(input->buffer, 1, amount, input->file);
    if (ferror(input->file)) { archive_set_error(reader, errno, "Preview input read failed"); return -1; }
    input->bytes_read += (int64_t)count;
    if (!preview_permitted(reader, input)) return -1;
    *buffer = input->buffer;
    return (la_ssize_t)count;
}

static la_int64_t preview_seek(struct archive *reader, void *opaque, la_int64_t offset, int whence) {
    struct preview_input *input = opaque;
    if (!preview_permitted(reader, input)) return ARCHIVE_FATAL;
    if (fseeko(input->file, (off_t)offset, whence) != 0) {
        archive_set_error(reader, errno, "Preview input seek failed");
        return ARCHIVE_FATAL;
    }
    return (la_int64_t)ftello(input->file);
}

int sa_preview_list_bounded(const char *path, size_t max_entries, size_t max_path_bytes,
                            size_t max_name_bytes, int64_t max_stream_bytes,
                            sa_preview_callback callback, sa_preview_poll_callback poll,
                            void *context, char *error_buffer, size_t error_capacity) {
    locale_t utf8 = newlocale(LC_CTYPE_MASK,"en_US.UTF-8",NULL);
    locale_t previous = utf8 ? uselocale(utf8):(locale_t)0;
    struct archive *reader = archive_read_new();
    struct preview_input input = { .file = NULL, .bytes_read = 0, .maximum_bytes = max_stream_bytes,
                                   .limited = 0, .poll = poll, .context = context };
    int status = -1;
    if (!reader) goto finished;
    if (!max_path_bytes || max_path_bytes == SIZE_MAX || !max_name_bytes || max_stream_bytes <= 0) {
        archive_set_error(reader, EINVAL, "Invalid preview budget"); goto failed;
    }
    int descriptor = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (descriptor < 0) { archive_set_error(reader, errno, "Preview input open failed"); goto failed; }
    struct stat information;
    if (fstat(descriptor, &information) != 0 || !S_ISREG(information.st_mode)) {
        close(descriptor); archive_set_error(reader, EINVAL, "Preview requires a regular file"); goto failed;
    }
    input.file = fdopen(descriptor, "rb");
    if (!input.file) { close(descriptor); archive_set_error(reader, errno, "Preview input open failed"); goto failed; }
    archive_read_support_filter_all(reader);
    archive_read_support_format_all(reader);
    archive_read_set_seek_callback(reader, preview_seek);
    status = archive_read_open(reader, &input, NULL, preview_read, NULL);
    if (status != ARCHIVE_OK) goto failed;
    struct archive_entry *entry = NULL;
    size_t count = 0, name_bytes = 0;
    for (;;) {
        if (!preview_permitted(reader, &input)) goto failed;
        status = archive_read_next_header(reader, &entry);
        if (!preview_permitted(reader, &input)) goto failed;
        if (status != ARCHIVE_OK && status != ARCHIVE_WARN) break;
        if (++count > max_entries) { status = -3; goto finished; }
        const char *name = archive_entry_pathname_utf8(entry);
        if (!name) name = archive_entry_pathname(entry);
        if (!name) { status = -1; goto failed; }
        size_t length = strnlen(name, max_path_bytes + 1);
        if (length > max_path_bytes || length >= max_name_bytes - name_bytes) {
            input.limited = 1;
            archive_set_error(reader, EFBIG, "Preview filename budget exceeded"); goto failed;
        }
        name_bytes += length + 1;
        const int type = archive_entry_filetype(entry);
        if (!callback(name,archive_entry_size_is_set(entry) ? archive_entry_size(entry):0,type == S_IFDIR,
                      (type != S_IFREG && type != S_IFDIR) || archive_entry_hardlink(entry) != NULL,
                      archive_entry_is_encrypted(entry) == 1,context)) {
            status = -2; goto finished;
        }
    }
    if (status == ARCHIVE_EOF) { status = 0; goto finished; }
failed:
    if (error_buffer && error_capacity) snprintf(error_buffer,error_capacity,"%s",archive_error_string(reader) ? archive_error_string(reader):"Arşiv okunamadı.");
    status = input.limited ? -4 : -1;
finished:
    if (reader) archive_read_free(reader);
    if (input.file) fclose(input.file);
    if (utf8) { uselocale(previous); freelocale(utf8); }
    return status;
}

int sa_preview_list(const char *path, size_t max_entries, sa_preview_callback callback, void *context, char *error_buffer, size_t error_capacity) {
    return sa_preview_list_bounded(path, max_entries, 4096, 4 * 1024 * 1024, 64 * 1024 * 1024,
                                   callback, NULL, context, error_buffer, error_capacity);
}
