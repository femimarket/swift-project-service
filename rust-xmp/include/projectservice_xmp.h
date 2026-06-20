// ProjectService XMP FFI — Adobe XMP Toolkit (xmp-toolkit-rs) bindings.
//
// All read functions write a UTF-8 + NUL terminator to `buf` and return
// the number of bytes written (excluding the NUL), 0 if the property is
// absent, or -1 on error. All write functions return 0 on success or a
// negative error code.

#ifndef PROJECTSERVICE_XMP_H
#define PROJECTSERVICE_XMP_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t psxmp_embed(const char* path,
                    const char* prompt_or_null,
                    const char* model_or_null,
                    const char* const* subject_array_or_null,
                    int32_t subject_count);

int32_t psxmp_read_prompt(const char* path, char* buf, int32_t buf_len);

int32_t psxmp_read_model(const char* path, char* buf, int32_t buf_len);

int32_t psxmp_read_subject_count(const char* path);

int32_t psxmp_read_subject_at(const char* path, int32_t index, char* buf, int32_t buf_len);

int32_t psxmp_set_rating(const char* path, int32_t rating);

// Returns the rating, or -100 if absent.
int32_t psxmp_read_rating(const char* path);

int32_t psxmp_read_property(const char* path,
                            const char* namespace_uri,
                            const char* property_name,
                            char* buf,
                            int32_t buf_len);

#ifdef __cplusplus
}
#endif

#endif
