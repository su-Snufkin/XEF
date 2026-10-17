// Metal pixel / vertex formats -> Vulkan formats.
#pragma once
#include "vk_loader.h"
#include <cstdint>

namespace xef::mtl {

enum FmtFlags : uint32_t {
    FMT_DEPTH = 1, FMT_STENCIL = 2, FMT_COMPRESSED = 4, FMT_SRGB = 8, FMT_INT = 16, FMT_UINT = 32,
    FMT_ALPHA_ONLY = 64,   // A8Unorm: R8 with the alpha swizzle
};

struct PixelFormatInfo {
    uint32_t mtl;
    VkFormat vk;
    uint32_t block_bytes;     // bytes per texel, or per block for compressed formats
    uint8_t block_w, block_h;
    uint32_t flags;
};

const PixelFormatInfo* pixel_format(uint32_t mtl_format);
VkFormat vertex_format(uint32_t mtl_vertex_format);
VkImageAspectFlags aspect_of(const PixelFormatInfo* f);
// numeric class of the format for the shader image bindings (COMP_FLOAT/SINT/UINT)
uint32_t comp_class(const PixelFormatInfo* f);
// pick a supported depth/stencil format (D24S8 is optional in Vulkan)
VkFormat resolve_depth_format(VkPhysicalDevice pd, VkFormat want);

} // namespace xef::mtl
