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

uint32_t    tex_create(int w, int h, int fmt, int is_render_target);
void        tex_update(uint32_t tex_id, int x, int y, int w, int h, const void* data, int pitch);
void        tex_copy(uint32_t src_tex_id, int sx, int sy, int sw, int sh, uint32_t dst_tex_id, int dx, int dy);
void        tex_readback(uint32_t tex_id, int x, int y, int w, int h, void* out_data, int pitch);
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

} // namespace xef::metal_vk
