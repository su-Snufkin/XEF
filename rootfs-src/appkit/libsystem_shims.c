/*
 * Common system libraries shims for XEF
 * libcompression, libcache, libDiagnosticMessagesClient, libMobileGestalt, libsandbox
 */

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

/* ---- libcompression ---- */
typedef enum {
    COMPRESSION_LZ4 = 0x100,
    COMPRESSION_ZLIB = 0x205,
    COMPRESSION_LZMA = 0x306,
    COMPRESSION_LZ4_RAW = 0x101,
    COMPRESSION_LZFSE = 0x801
} compression_algorithm;

typedef enum {
    COMPRESSION_STREAM_CONTINUE = 0,
    COMPRESSION_STREAM_END = 1,
    COMPRESSION_STREAM_ERROR = -1
} compression_status;

typedef enum {
    COMPRESSION_STREAM_ENCODE = 0,
    COMPRESSION_STREAM_DECODE = 1
} compression_stream_operation;

typedef struct {
    uint8_t *dst_ptr;
    size_t dst_size;
    const uint8_t *src_ptr;
    size_t src_size;
    void *state;
} compression_stream;

size_t compression_encode_scratch_buffer_size(compression_algorithm algorithm) { return 0; }
size_t compression_encode_buffer(uint8_t *dst_buffer, size_t dst_size, const uint8_t *src_buffer, size_t src_size, void *scratch_buffer, compression_algorithm algorithm) {
    if (!dst_buffer || !src_buffer || dst_size < src_size) return 0;
    memcpy(dst_buffer, src_buffer, src_size);
    return src_size;
}

size_t compression_decode_scratch_buffer_size(compression_algorithm algorithm) { return 0; }
size_t compression_decode_buffer(uint8_t *dst_buffer, size_t dst_size, const uint8_t *src_buffer, size_t src_size, void *scratch_buffer, compression_algorithm algorithm) {
    if (!dst_buffer || !src_buffer || dst_size < src_size) return 0;
    memcpy(dst_buffer, src_buffer, src_size);
    return src_size;
}

compression_status compression_stream_init(compression_stream *stream, compression_stream_operation operation, compression_algorithm algorithm) {
    return COMPRESSION_STREAM_CONTINUE;
}
compression_status compression_stream_process(compression_stream *stream, int flags) {
    if (!stream) return COMPRESSION_STREAM_ERROR;
    size_t copy_bytes = stream->src_size < stream->dst_size ? stream->src_size : stream->dst_size;
    if (copy_bytes > 0 && stream->dst_ptr && stream->src_ptr) {
        memcpy(stream->dst_ptr, stream->src_ptr, copy_bytes);
        stream->dst_ptr += copy_bytes;
        stream->dst_size -= copy_bytes;
        stream->src_ptr += copy_bytes;
        stream->src_size -= copy_bytes;
    }
    return COMPRESSION_STREAM_END;
}
compression_status compression_stream_destroy(compression_stream *stream) {
    return COMPRESSION_STREAM_CONTINUE;
}

/* ---- libcache ---- */
typedef struct _cache_s *cache_t;
typedef void (*cache_release_cb_t)(void *key, void *value);

int cache_create(const char *name, void *attributes, cache_t *cache_out) {
    if (cache_out) *cache_out = (cache_t)calloc(1, 64);
    return 0;
}
int cache_destroy(cache_t cache) {
    if (cache) free(cache);
    return 0;
}
int cache_set_and_retain(cache_t cache, void *key, void *value, size_t cost) { return 0; }
int cache_get_and_retain(cache_t cache, void *key, void **value_out) {
    if (value_out) *value_out = NULL;
    return 1;
}
int cache_release_value(cache_t cache, void *value) { return 0; }
int cache_remove(cache_t cache, void *key) { return 0; }

/* ---- libDiagnosticMessagesClient ---- */
int msgtracer_log(const char *domain, const char *msg) { return 0; }
int msgtracer_log_with_keys(const char *domain, const char *msg, ...) { return 0; }

/* ---- libMobileGestalt ---- */
void *MGCopyAnswer(void *property, void *options) { return NULL; }
int32_t MGGetBoolAnswer(void *property) { return 0; }
int32_t MGGetSInt32Answer(void *property, int32_t default_value) { return default_value; }

/* ---- libsandbox ---- */
int sandbox_init(const char *profile, uint64_t flags, char **errorbuf) {
    if (errorbuf) *errorbuf = NULL;
    return 0;
}
int sandbox_init_with_parameters(const char *profile, uint64_t flags, const char *const parameters[], char **errorbuf) {
    if (errorbuf) *errorbuf = NULL;
    return 0;
}
int sandbox_free_error(char *errorbuf) {
    if (errorbuf) free(errorbuf);
    return 0;
}

