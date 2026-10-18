/* Metal on Vulkan: interface between the guest Metal.framework (arm64, rootfs-src/appkit/Metal.m) and the
 * host engine (x86-64, src/metal/). Plain C, shared by both sides: keep layouts free of padding surprises
 * (explicit sizes, natural alignment, no pointers inside stream records).
 *
 * Objects live on the host and are referenced by 32-bit ids. Command buffers are recorded by the guest into a
 * byte stream of records (xef_mtl_cmd + payload) and handed to the host in one call at commit time. */
#ifndef XEF_MTL_H
#define XEF_MTL_H
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define XEF_MTL_MAX_COLOR 8
#define XEF_MTL_MAX_BUFFERS 31
#define XEF_MTL_MAX_TEXTURES 128
#define XEF_MTL_MAX_SAMPLERS 16
#define XEF_MTL_MAX_VERTEX_ATTRIBS 31

/* ---------------- device ---------------- */
typedef struct xef_mtl_device_info {
    char name[128];
    uint64_t recommended_max_working_set;
    uint64_t max_buffer_length;
    uint32_t max_threads_per_threadgroup;
    uint32_t max_texture_2d;
    uint32_t has_unified_memory;
    uint32_t simd_width;
    uint32_t vendor_id;
    uint32_t pad;
} xef_mtl_device_info;

/* ---------------- textures / samplers ---------------- */
typedef struct xef_mtl_texture_desc {
    uint32_t type;          /* MTLTextureType */
    uint32_t pixel_format;  /* MTLPixelFormat */
    uint32_t width, height, depth;
    uint32_t mip_levels, array_length, sample_count;
    uint32_t usage;         /* MTLTextureUsage */
    uint32_t storage_mode;  /* MTLStorageMode */
    uint8_t swizzle[4];     /* MTLTextureSwizzle r,g,b,a */
    uint32_t buffer;        /* texture backed by a buffer (0 = none) */
    uint64_t buffer_offset;
    uint32_t bytes_per_row;
    uint32_t pad;
} xef_mtl_texture_desc;

typedef struct xef_mtl_view_desc {
    uint32_t pixel_format, type;
    uint32_t level, levels, slice, slices;
    uint8_t swizzle[4];
    uint32_t pad;
} xef_mtl_view_desc;

typedef struct xef_mtl_sampler_desc {
    uint32_t min_filter, mag_filter, mip_filter;
    uint32_t s_address, t_address, r_address;
    uint32_t max_anisotropy;
    uint32_t compare;          /* MTLCompareFunction, 0 (never) = no compare when compare_enable == 0 */
    uint32_t compare_enable;
    uint32_t border_color;     /* MTLSamplerBorderColor */
    uint32_t normalized;
    uint32_t pad;
    float lod_min, lod_max, lod_bias, pad2;
} xef_mtl_sampler_desc;

/* ---------------- functions / pipelines ---------------- */
/* function constant values: packed records of { u32 index, u32 type (MTLDataType), u32 size, u32 name_len,
   name bytes (padded to 4), value bytes (padded to 4) } */
typedef struct xef_mtl_function_ref {
    uint32_t library;      /* host library id */
    uint32_t constants_size;
    const char* name;
    const void* constants;
} xef_mtl_function_ref;

typedef struct xef_mtl_vertex_attrib {
    uint32_t format;       /* MTLVertexFormat, 0 = unused */
    uint32_t offset;
    uint32_t buffer_index;
} xef_mtl_vertex_attrib;

typedef struct xef_mtl_vertex_layout {
    uint32_t stride;
    uint32_t step_function; /* MTLVertexStepFunction */
    uint32_t step_rate;
    uint32_t used;
} xef_mtl_vertex_layout;

typedef struct xef_mtl_color_attachment {
    uint32_t pixel_format;
    uint32_t blending;
    uint32_t src_rgb, dst_rgb, rgb_op;
    uint32_t src_alpha, dst_alpha, alpha_op;
    uint32_t write_mask;
} xef_mtl_color_attachment;

typedef struct xef_mtl_render_pipeline_desc {
    xef_mtl_function_ref vertex;
    xef_mtl_function_ref fragment;      /* library 0 = none */
    xef_mtl_vertex_attrib attribs[XEF_MTL_MAX_VERTEX_ATTRIBS];
    xef_mtl_vertex_layout layouts[XEF_MTL_MAX_BUFFERS];
    uint32_t has_vertex_descriptor;
    xef_mtl_color_attachment colors[XEF_MTL_MAX_COLOR];
    uint32_t depth_format, stencil_format;
    uint32_t sample_count;
    uint32_t alpha_to_coverage, alpha_to_one;
    uint32_t rasterization_enabled;
    uint32_t input_topology;            /* MTLPrimitiveTopologyClass */
    uint32_t linked_count;              /* [[visible]] functions available to both stages */
    const xef_mtl_function_ref* linked;
    const uint32_t* link_libraries;     /* preloaded dynamic libraries (library ids) */
    uint32_t link_library_count;
    uint32_t pad;
} xef_mtl_render_pipeline_desc;

typedef struct xef_mtl_compute_pipeline_desc {
    xef_mtl_function_ref function;
    uint32_t max_total_threads;         /* 0 = default */
    uint32_t threadgroup_size_multiple;
    const xef_mtl_function_ref* linked; /* linkedFunctions (functions, private and binary functions) */
    uint32_t linked_count;
    uint32_t link_library_count;        /* preloaded dynamic libraries (library ids) */
    const uint32_t* link_libraries;
} xef_mtl_compute_pipeline_desc;

typedef struct xef_mtl_pipeline_info {
    uint32_t max_total_threads;
    uint32_t execution_width;
    uint32_t static_threadgroup_memory;
    uint32_t pad;
} xef_mtl_pipeline_info;

/* ---------------- command stream ---------------- */
enum {
    XEF_MTL_CMD_NOP = 0,
    /* render encoder */
    XEF_MTL_CMD_BEGIN_RENDER = 1,
    XEF_MTL_CMD_END_ENCODER,
    XEF_MTL_CMD_SET_RENDER_PIPELINE,
    XEF_MTL_CMD_SET_BUFFER,        /* stage, index, buffer, offset */
    XEF_MTL_CMD_SET_BUFFER_OFFSET,
    XEF_MTL_CMD_SET_BYTES,         /* stage, index, length, data */
    XEF_MTL_CMD_SET_TEXTURE,
    XEF_MTL_CMD_SET_SAMPLER,
    XEF_MTL_CMD_SET_VIEWPORT,
    XEF_MTL_CMD_SET_SCISSOR,
    XEF_MTL_CMD_SET_RASTER_STATE,  /* cull, winding, fill, depth clip, depth bias */
    XEF_MTL_CMD_SET_DEPTH_STENCIL,
    XEF_MTL_CMD_SET_STENCIL_REF,
    XEF_MTL_CMD_SET_BLEND_COLOR,
    XEF_MTL_CMD_DRAW,
    XEF_MTL_CMD_DRAW_INDEXED,
    XEF_MTL_CMD_DRAW_INDIRECT,
    XEF_MTL_CMD_DRAW_INDEXED_INDIRECT,
    XEF_MTL_CMD_SET_VISIBILITY,    /* visibility result mode + offset */
    /* compute encoder */
    XEF_MTL_CMD_BEGIN_COMPUTE = 32,
    XEF_MTL_CMD_SET_COMPUTE_PIPELINE,
    XEF_MTL_CMD_SET_THREADGROUP_MEMORY,
    XEF_MTL_CMD_DISPATCH,          /* threadgroups or threads */
    XEF_MTL_CMD_DISPATCH_INDIRECT,
    XEF_MTL_CMD_MEMORY_BARRIER,
    /* blit encoder */
    XEF_MTL_CMD_BEGIN_BLIT = 48,
    XEF_MTL_CMD_COPY_BUFFER,
    XEF_MTL_CMD_COPY_BUFFER_TO_TEXTURE,
    XEF_MTL_CMD_COPY_TEXTURE_TO_BUFFER,
    XEF_MTL_CMD_COPY_TEXTURE,
    XEF_MTL_CMD_FILL_BUFFER,
    XEF_MTL_CMD_GENERATE_MIPMAPS,
    /* command buffer level */
    XEF_MTL_CMD_PRESENT = 64,
    XEF_MTL_CMD_SIGNAL_EVENT,
    XEF_MTL_CMD_WAIT_EVENT,
};

typedef struct xef_mtl_cmd { uint32_t op; uint32_t size; } xef_mtl_cmd;   /* size: payload bytes (multiple of 8) */

enum { XEF_MTL_STAGE_VERTEX = 0, XEF_MTL_STAGE_FRAGMENT = 1, XEF_MTL_STAGE_KERNEL = 2 };

typedef struct xef_mtl_rp_color {
    uint32_t texture, level, slice, depth_plane;
    uint32_t load_action, store_action;
    uint32_t resolve_texture, resolve_level, resolve_slice, resolve_depth_plane;
    float clear[4];
} xef_mtl_rp_color;

typedef struct xef_mtl_rp_depth {
    uint32_t texture, level, slice, depth_plane;
    uint32_t load_action, store_action;
    uint32_t resolve_texture, resolve_level, resolve_slice;
    uint32_t clear_stencil;
    float clear_depth;
    uint32_t pad;
} xef_mtl_rp_depth;

typedef struct xef_mtl_begin_render {
    xef_mtl_rp_color colors[XEF_MTL_MAX_COLOR];
    xef_mtl_rp_depth depth;
    xef_mtl_rp_depth stencil;
    uint32_t width, height;             /* render target size (0 = from attachments) */
    uint32_t layers;
    uint32_t default_samples;
    uint32_t visibility_buffer;
    uint32_t pad;
} xef_mtl_begin_render;

typedef struct xef_mtl_set_buffer { uint32_t stage, index, buffer, pad; uint64_t offset; } xef_mtl_set_buffer;
typedef struct xef_mtl_set_bytes { uint32_t stage, index, length, pad; /* data follows */ } xef_mtl_set_bytes;
typedef struct xef_mtl_set_texture { uint32_t stage, index, texture, pad; } xef_mtl_set_texture;
typedef struct xef_mtl_set_sampler { uint32_t stage, index, sampler, pad; } xef_mtl_set_sampler;
typedef struct xef_mtl_set_pipeline { uint32_t pipeline, pad; } xef_mtl_set_pipeline;
typedef struct xef_mtl_viewport { float x, y, w, h, znear, zfar; } xef_mtl_viewport;
typedef struct xef_mtl_scissor { uint32_t x, y, w, h; } xef_mtl_scissor;
typedef struct xef_mtl_raster_state {
    uint32_t cull_mode;        /* MTLCullMode */
    uint32_t winding;          /* MTLWinding */
    uint32_t fill_mode;        /* MTLTriangleFillMode */
    uint32_t depth_clip;       /* MTLDepthClipMode */
    float depth_bias, slope_scale, clamp;
    uint32_t pad;
} xef_mtl_raster_state;
typedef struct xef_mtl_stencil_face {
    uint32_t compare, fail_op, depth_fail_op, pass_op, read_mask, write_mask;
} xef_mtl_stencil_face;
typedef struct xef_mtl_depth_stencil {
    uint32_t depth_compare;    /* MTLCompareFunction */
    uint32_t depth_write;
    uint32_t stencil_enabled;
    uint32_t pad;
    xef_mtl_stencil_face front, back;
} xef_mtl_depth_stencil;
typedef struct xef_mtl_stencil_ref { uint32_t front, back; } xef_mtl_stencil_ref;
typedef struct xef_mtl_blend_color { float r, g, b, a; } xef_mtl_blend_color;
typedef struct xef_mtl_draw {
    uint32_t primitive;        /* MTLPrimitiveType */
    uint32_t vertex_start, vertex_count, instance_count, base_instance, pad;
} xef_mtl_draw;
typedef struct xef_mtl_draw_indexed {
    uint32_t primitive, index_count, index_type, index_buffer;
    uint64_t index_offset;
    uint32_t instance_count;
    int32_t base_vertex;
    uint32_t base_instance, pad;
} xef_mtl_draw_indexed;
typedef struct xef_mtl_draw_indirect {
    uint32_t primitive, buffer;
    uint64_t offset;
    uint32_t index_type, index_buffer;
    uint64_t index_offset;
} xef_mtl_draw_indirect;
typedef struct xef_mtl_visibility { uint32_t mode, pad; uint64_t offset; } xef_mtl_visibility;
typedef struct xef_mtl_tg_memory { uint32_t index, length; } xef_mtl_tg_memory;
typedef struct xef_mtl_dispatch {
    uint32_t groups[3];        /* threadgroups per grid (dispatchThreadgroups) or threads per grid (dispatchThreads) */
    uint32_t threads[3];       /* threads per threadgroup */
    uint32_t by_threads;       /* 1 = dispatchThreads */
    uint32_t pad;
} xef_mtl_dispatch;
typedef struct xef_mtl_dispatch_indirect { uint32_t buffer, pad; uint64_t offset; uint32_t threads[3], pad2; } xef_mtl_dispatch_indirect;
typedef struct xef_mtl_copy_buffer { uint32_t src, dst; uint64_t src_offset, dst_offset, size; } xef_mtl_copy_buffer;
typedef struct xef_mtl_copy_buf_tex {
    uint32_t buffer, texture;
    uint64_t buffer_offset;
    uint32_t bytes_per_row, bytes_per_image;
    uint32_t level, slice;
    uint32_t x, y, z, w, h, d;
    uint32_t options, pad;
} xef_mtl_copy_buf_tex;
typedef struct xef_mtl_copy_texture {
    uint32_t src, dst;
    uint32_t src_level, src_slice, dst_level, dst_slice;
    uint32_t sx, sy, sz, dx, dy, dz, w, h, d;
    uint32_t slice_count, level_count, whole;   /* whole = copyFromTexture:toTexture: */
} xef_mtl_copy_texture;
typedef struct xef_mtl_fill_buffer { uint32_t buffer, value; uint64_t offset, length; } xef_mtl_fill_buffer;
typedef struct xef_mtl_texture_ref { uint32_t texture, pad; } xef_mtl_texture_ref;
typedef struct xef_mtl_present { uint32_t layer, drawable; double at_time; } xef_mtl_present;
typedef struct xef_mtl_event_op { uint32_t event, pad; uint64_t value; } xef_mtl_event_op;

/* ---------------- host functions (resolved through HLE) ---------------- */
int      xef_mtl_init(xef_mtl_device_info* out);
uint32_t xef_mtl_buffer_create(uint64_t length, uint32_t options, void** out_contents, uint64_t* out_gpu_address);
uint32_t xef_mtl_buffer_create_nocopy(void* pointer, uint64_t length, uint32_t options, uint64_t* out_gpu_address);
void     xef_mtl_buffer_destroy(uint32_t buffer);
uint32_t xef_mtl_texture_create(const xef_mtl_texture_desc* desc, uint64_t* out_resource_id);
uint32_t xef_mtl_texture_view(uint32_t parent, const xef_mtl_view_desc* desc, uint64_t* out_resource_id);
void     xef_mtl_texture_replace(uint32_t texture, uint32_t level, uint32_t slice, const uint32_t* region6,
                                 const void* bytes, uint64_t bytes_per_row, uint64_t bytes_per_image);
void     xef_mtl_texture_get_bytes(uint32_t texture, uint32_t level, uint32_t slice, const uint32_t* region6,
                                   void* bytes, uint64_t bytes_per_row, uint64_t bytes_per_image);
void     xef_mtl_texture_destroy(uint32_t texture);
uint32_t xef_mtl_sampler_create(const xef_mtl_sampler_desc* desc, uint64_t* out_resource_id);
void     xef_mtl_sampler_destroy(uint32_t sampler);
uint32_t xef_mtl_library_create(const void* data, uint64_t size, char* err, uint32_t err_len);
uint32_t xef_mtl_library_create_source(const char* source, const void* options, char* err, uint32_t err_len);
uint32_t xef_mtl_library_function_count(uint32_t library);
uint32_t xef_mtl_library_function_info(uint32_t library, uint32_t index, char* name, uint32_t name_len);   /* returns MTLFunctionType+1, 0 = none */
void     xef_mtl_library_destroy(uint32_t library);
uint32_t xef_mtl_render_pipeline_create(const xef_mtl_render_pipeline_desc* desc, char* err, uint32_t err_len);
uint32_t xef_mtl_compute_pipeline_create(const xef_mtl_compute_pipeline_desc* desc, xef_mtl_pipeline_info* info, char* err, uint32_t err_len);
void     xef_mtl_pipeline_destroy(uint32_t pipeline);
uint32_t xef_mtl_queue_create(void);
uint64_t xef_mtl_commit(uint32_t queue, const void* stream, uint64_t length);   /* returns the submission number */
uint64_t xef_mtl_completed(uint32_t queue);                                      /* last finished submission */
uint64_t xef_mtl_wait(uint32_t queue, uint64_t submission, int64_t timeout_ns);  /* returns last finished */
uint32_t xef_mtl_layer_create(int host_window);
void     xef_mtl_layer_configure(uint32_t layer, uint32_t width, uint32_t height, uint32_t pixel_format, uint32_t flags);
uint32_t xef_mtl_layer_next_drawable(uint32_t layer, uint32_t* out_texture, uint64_t* out_resource_id);   /* drawable index + 1, 0 = timeout */
void     xef_mtl_layer_release_drawable(uint32_t layer, uint32_t drawable);   /* drawable dropped without present */
void     xef_mtl_layer_destroy(uint32_t layer);
uint32_t xef_mtl_event_create(void);
uint64_t xef_mtl_event_value(uint32_t event);
void     xef_mtl_event_signal(uint32_t event, uint64_t value);
int      xef_mtl_event_wait(uint32_t event, uint64_t value, int64_t timeout_ns);
void     xef_mtl_event_destroy(uint32_t event);

#ifdef __cplusplus
}
#endif
#endif
