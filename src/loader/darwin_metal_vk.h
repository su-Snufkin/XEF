#pragma once
#include <cstdint>
#include <cstddef>

#ifndef XEF_HOST_H
#include "../../rootfs-src/appkit/xef_host.h"
#endif

namespace xef::metal_vk {

bool        init();
void        finit();
bool        is_available();
const char* get_device_name();

uint32_t    sampler_create(int min_filter, int mag_filter, int mip_filter,
                           int s_address_mode, int t_address_mode, int r_address_mode,
                           int max_aniso, int compare_fn, int border_color,
                           float lod_min, float lod_max, int normalized_coords);
void        sampler_destroy(uint32_t sampler_id);

uint32_t    tex_create(int w, int h, int fmt, int is_render_target);
uint32_t    tex_create_ex(int w, int h, int depth, int layers, int texture_type, int fmt, int is_render_target);
uint32_t    tex_create_view(uint32_t parent_id, int fmt,
                            int swizzle_r, int swizzle_g, int swizzle_b, int swizzle_a,
                            int base_mip, int mip_count, int base_layer, int layer_count);
void        tex_update(uint32_t tex_id, int x, int y, int w, int h, const void* data, int pitch);
void        tex_update_ex(uint32_t tex_id, int slice, int level, int x, int y, int z, int w, int h, int d, const void* data, int pitch, int image_pitch);
void        tex_copy(uint32_t src_tex_id, int sx, int sy, int sw, int sh, uint32_t dst_tex_id, int dx, int dy);
void        tex_copy_ex(uint32_t src_tex_id, int src_slice, int src_level, int sx, int sy, int sz,
                        uint32_t dst_tex_id, int dst_slice, int dst_level, int dx, int dy, int dz,
                        int sw, int sh, int sd);
void        tex_readback(uint32_t tex_id, int x, int y, int w, int h, void* out_data, int pitch);
void        tex_readback_ex(uint32_t tex_id, int slice, int level, int x, int y, int z, int w, int h, int d, void* out_data, int pitch, int image_pitch);
void        tex_generate_mipmaps(uint32_t tex_id);
void        tex_destroy(uint32_t tex_id);

void        pass_begin(int handle, uint32_t rt_tex_id, int clear, float r, float g, float b, float a);
void        pass_begin_ex(int handle, uint32_t rt_tex_id, uint32_t depth_tex_id, int clear, float r, float g, float b, float a, float clear_depth);
void        pass_end(int handle, uint32_t rt_tex_id);

void        draw(int handle,
                 const xef_host_metal_pipeline_t* pipe,
                 int prim_type,
                 const xef_host_metal_vertex_t* vertices,
                 int vertex_count,
                 const uint32_t* indices,
                 int index_count);

void        present(int handle, uint32_t tex_id);

void*       shader_translate_metallib(const void* data, size_t size, size_t* out_size);
void        shader_free(void* ptr);

} // namespace xef::metal_vk
