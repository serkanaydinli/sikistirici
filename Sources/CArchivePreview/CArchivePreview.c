#include "CArchivePreview.h"
#include "archive.h"
#include "archive_entry.h"
#include <stdio.h>
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

int sa_preview_list(const char *path, size_t max_entries, sa_preview_callback callback, void *context, char *error_buffer, size_t error_capacity) {
    locale_t utf8 = newlocale(LC_CTYPE_MASK,"en_US.UTF-8",NULL);
    locale_t previous = utf8 ? uselocale(utf8):(locale_t)0;
    struct archive *reader = archive_read_new();
    if (!reader) { if (utf8) { uselocale(previous); freelocale(utf8); } return -1; }
    archive_read_support_filter_all(reader);
    archive_read_support_format_all(reader);
    int status = archive_read_open_filename(reader,path,65536);
    if (status != ARCHIVE_OK) goto failed;
    struct archive_entry *entry = NULL;
    size_t count = 0;
    while ((status = archive_read_next_header(reader,&entry)) == ARCHIVE_OK || status == ARCHIVE_WARN) {
        if (++count > max_entries) { status = -3; goto finished; }
        const char *name = archive_entry_pathname_utf8(entry);
        if (!name) name = archive_entry_pathname(entry);
        if (!name) { status = -1; goto failed; }
        const int type = archive_entry_filetype(entry);
        if (!callback(name,archive_entry_size_is_set(entry) ? archive_entry_size(entry):0,type == S_IFDIR,
                      type == S_IFLNK || archive_entry_hardlink(entry) != NULL,archive_entry_is_encrypted(entry) == 1,context)) {
            status = -2; goto finished;
        }
    }
    if (status == ARCHIVE_EOF) { status = 0; goto finished; }
failed:
    if (error_buffer && error_capacity) snprintf(error_buffer,error_capacity,"%s",archive_error_string(reader) ? archive_error_string(reader):"Arşiv okunamadı.");
    status = -1;
finished:
    archive_read_free(reader);
    if (utf8) { uselocale(previous); freelocale(utf8); }
    return status;
}
