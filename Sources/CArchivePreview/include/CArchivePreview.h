#ifndef CARCHIVEPREVIEW_H
#define CARCHIVEPREVIEW_H
#include <stdint.h>
#include <stddef.h>
typedef int (*sa_preview_callback)(const char *path, int64_t size, int is_directory, int is_link, int encrypted, void *context);
int sa_preview_list(const char *path, size_t max_entries, sa_preview_callback callback, void *context, char *error_buffer, size_t error_capacity);
/* Header callback: 0 aborts, 1 reads data, 2 skips data. No archive paths are written by C.
 * mtime seconds/nanoseconds are meaningful only when has_mtime is nonzero. */
typedef int (*sa_zip_header_callback)(const char *path, int64_t size, int is_directory, int is_link, int encrypted, int permissions, int has_mtime, int64_t mtime_seconds, int64_t mtime_nanoseconds, void *context);
typedef int (*sa_zip_data_callback)(const void *bytes, size_t length, void *context);
int sa_zip_read(const char *path, const char *charset, const char *password, size_t max_entries,
                sa_zip_header_callback header, sa_zip_data_callback data, void *context,
                char *error_buffer, size_t error_capacity);
#endif
