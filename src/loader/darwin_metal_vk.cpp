/* MetalVK: Native Metal-on-Vulkan backend for XEF-OSX.
 * Implements Metal GPU acceleration directly via Vulkan 1.3 / 1.4.
 */

#include "darwin_metal_vk.h"
#include <vulkan/vulkan.h>
#include <dlfcn.h>
#include <vector>
#include <unordered_map>
#include <string>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <mutex>
#include <algorithm>

extern "C" void xef_host_present_pixels(int handle, const void *pixels, int w, int h, int format);

namespace xef::metal_vk {

// Embedded SPIR-V shader bytecodes
#include "darwin_metal_vk_spv.h"

// Vulkan dynamic dispatch table
static void* g_vk_lib = nullptr;
static PFN_vkGetInstanceProcAddr vkGetInstanceProcAddr = nullptr;
static PFN_vkCreateInstance vkCreateInstance = nullptr;
static PFN_vkDestroyInstance vkDestroyInstance = nullptr;
static PFN_vkEnumeratePhysicalDevices vkEnumeratePhysicalDevices = nullptr;
static PFN_vkGetPhysicalDeviceProperties vkGetPhysicalDeviceProperties = nullptr;
static PFN_vkGetPhysicalDeviceQueueFamilyProperties vkGetPhysicalDeviceQueueFamilyProperties = nullptr;
static PFN_vkGetPhysicalDeviceMemoryProperties vkGetPhysicalDeviceMemoryProperties = nullptr;
static PFN_vkCreateDevice vkCreateDevice = nullptr;
static PFN_vkDestroyDevice vkDestroyDevice = nullptr;
static PFN_vkGetDeviceQueue vkGetDeviceQueue = nullptr;
static PFN_vkCreateCommandPool vkCreateCommandPool = nullptr;
static PFN_vkDestroyCommandPool vkDestroyCommandPool = nullptr;
static PFN_vkAllocateCommandBuffers vkAllocateCommandBuffers = nullptr;
static PFN_vkFreeCommandBuffers vkFreeCommandBuffers = nullptr;
static PFN_vkBeginCommandBuffer vkBeginCommandBuffer = nullptr;
static PFN_vkEndCommandBuffer vkEndCommandBuffer = nullptr;
static PFN_vkQueueSubmit vkQueueSubmit = nullptr;
static PFN_vkQueueWaitIdle vkQueueWaitIdle = nullptr;
static PFN_vkCreateBuffer vkCreateBuffer = nullptr;
static PFN_vkDestroyBuffer vkDestroyBuffer = nullptr;
static PFN_vkGetBufferMemoryRequirements vkGetBufferMemoryRequirements = nullptr;
static PFN_vkAllocateMemory vkAllocateMemory = nullptr;
static PFN_vkFreeMemory vkFreeMemory = nullptr;
static PFN_vkBindBufferMemory vkBindBufferMemory = nullptr;
static PFN_vkMapMemory vkMapMemory = nullptr;
static PFN_vkUnmapMemory vkUnmapMemory = nullptr;
static PFN_vkCreateImage vkCreateImage = nullptr;
static PFN_vkDestroyImage vkDestroyImage = nullptr;
static PFN_vkGetImageMemoryRequirements vkGetImageMemoryRequirements = nullptr;
static PFN_vkBindImageMemory vkBindImageMemory = nullptr;
static PFN_vkCreateImageView vkCreateImageView = nullptr;
static PFN_vkDestroyImageView vkDestroyImageView = nullptr;
static PFN_vkCreateSampler vkCreateSampler = nullptr;
static PFN_vkDestroySampler vkDestroySampler = nullptr;
static PFN_vkCreateRenderPass vkCreateRenderPass = nullptr;
static PFN_vkDestroyRenderPass vkDestroyRenderPass = nullptr;
static PFN_vkCreateFramebuffer vkCreateFramebuffer = nullptr;
static PFN_vkDestroyFramebuffer vkDestroyFramebuffer = nullptr;
static PFN_vkCreateShaderModule vkCreateShaderModule = nullptr;
static PFN_vkDestroyShaderModule vkDestroyShaderModule = nullptr;
static PFN_vkCreatePipelineLayout vkCreatePipelineLayout = nullptr;
static PFN_vkDestroyPipelineLayout vkDestroyPipelineLayout = nullptr;
static PFN_vkCreateGraphicsPipelines vkCreateGraphicsPipelines = nullptr;
static PFN_vkDestroyPipeline vkDestroyPipeline = nullptr;
static PFN_vkCmdBeginRenderPass vkCmdBeginRenderPass = nullptr;
static PFN_vkCmdEndRenderPass vkCmdEndRenderPass = nullptr;
static PFN_vkCmdBindPipeline vkCmdBindPipeline = nullptr;
static PFN_vkCmdSetViewport vkCmdSetViewport = nullptr;
static PFN_vkCmdSetScissor vkCmdSetScissor = nullptr;
static PFN_vkCmdBindVertexBuffers vkCmdBindVertexBuffers = nullptr;
static PFN_vkCmdBindIndexBuffer vkCmdBindIndexBuffer = nullptr;
static PFN_vkCmdDraw vkCmdDraw = nullptr;
static PFN_vkCmdDrawIndexed vkCmdDrawIndexed = nullptr;
static PFN_vkCmdPushConstants vkCmdPushConstants = nullptr;
static PFN_vkCmdPipelineBarrier vkCmdPipelineBarrier = nullptr;
static PFN_vkCmdCopyBufferToImage vkCmdCopyBufferToImage = nullptr;
static PFN_vkCmdCopyImageToBuffer vkCmdCopyImageToBuffer = nullptr;
static PFN_vkCmdCopyImage vkCmdCopyImage = nullptr;
static PFN_vkCmdBlitImage vkCmdBlitImage = nullptr;
static PFN_vkCreateDescriptorSetLayout vkCreateDescriptorSetLayout = nullptr;
static PFN_vkDestroyDescriptorSetLayout vkDestroyDescriptorSetLayout = nullptr;
static PFN_vkCreateDescriptorPool vkCreateDescriptorPool = nullptr;
static PFN_vkDestroyDescriptorPool vkDestroyDescriptorPool = nullptr;
static PFN_vkAllocateDescriptorSets vkAllocateDescriptorSets = nullptr;
static PFN_vkUpdateDescriptorSets vkUpdateDescriptorSets = nullptr;
static PFN_vkCmdBindDescriptorSets vkCmdBindDescriptorSets = nullptr;

// State
static std::mutex g_metal_vk_lock;
static bool g_initialized = false;
static bool g_available = false;
static std::string g_device_name;
static VkInstance g_instance = VK_NULL_HANDLE;
static VkPhysicalDevice g_physical_device = VK_NULL_HANDLE;
static VkPhysicalDeviceProperties g_device_props;
static VkPhysicalDeviceMemoryProperties g_mem_props;
static VkDevice g_device = VK_NULL_HANDLE;
static VkQueue g_queue = VK_NULL_HANDLE;
static uint32_t g_queue_family = 0;
static VkCommandPool g_cmd_pool = VK_NULL_HANDLE;
static VkCommandBuffer g_active_cmd = VK_NULL_HANDLE;
static uint32_t g_active_rt_id = 0;

struct PendingBuffer {
    VkBuffer buffer;
    VkDeviceMemory memory;
};
static std::vector<PendingBuffer> g_pending_buffers;

static VkDescriptorSetLayout g_desc_layout = VK_NULL_HANDLE;
static VkDescriptorPool g_desc_pool = VK_NULL_HANDLE;
static VkPipelineLayout g_pipeline_layout = VK_NULL_HANDLE;
static VkShaderModule g_vs_module = VK_NULL_HANDLE;
static VkShaderModule g_fs_module = VK_NULL_HANDLE;
static VkSampler g_sampler_linear = VK_NULL_HANDLE;
static VkSampler g_sampler_nearest = VK_NULL_HANDLE;

struct PushConstants {
    float u_target_size[2];
    int   u_frag_mode;
    float u_color_scale;
    float u_uv_left_top[2];
    float u_uv_dims[2];
    int   u_flip_y;
};

struct MetalVkTex {
    uint32_t id = 0;
    int w = 0, h = 0;
    int fmt = 0;
    int mip_levels = 1;
    bool is_rt = false;
    VkFormat vk_fmt = VK_FORMAT_B8G8R8A8_UNORM;
    VkImage image = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    VkImageView view = VK_NULL_HANDLE;
    VkRenderPass render_pass_clear = VK_NULL_HANDLE;
    VkRenderPass render_pass_load = VK_NULL_HANDLE;
    VkFramebuffer framebuffer_clear = VK_NULL_HANDLE;
    VkFramebuffer framebuffer_load = VK_NULL_HANDLE;
    VkImageLayout layout = VK_IMAGE_LAYOUT_UNDEFINED;
    VkDescriptorSet desc_set_linear = VK_NULL_HANDLE;
    VkDescriptorSet desc_set_nearest = VK_NULL_HANDLE;
};

static std::unordered_map<uint32_t, MetalVkTex> g_textures;
static uint32_t g_next_tex_id = 1;
static uint32_t g_white_tex_id = 0;

// Pipeline caching
struct PipelineKey {
    int blend_enable;
    int src_rgb, dst_rgb, rgb_op;
    int src_a, dst_a, a_op;
    int write_mask;
    int prim_type;
    VkFormat rt_format;
    VkFormat depth_format;
    int depth_test_enable;
    int depth_write_enable;
    int depth_compare_op;
    int stencil_test_enable;
    int stencil_compare_op;
    int stencil_fail_op;
    int stencil_depth_fail_op;
    int stencil_pass_op;
    uint32_t stencil_read_mask;
    uint32_t stencil_write_mask;
    int cull_mode;
    int front_face;

    bool operator==(const PipelineKey& o) const {
        return blend_enable == o.blend_enable &&
               src_rgb == o.src_rgb && dst_rgb == o.dst_rgb && rgb_op == o.rgb_op &&
               src_a == o.src_a && dst_a == o.dst_a && a_op == o.a_op &&
               write_mask == o.write_mask && prim_type == o.prim_type &&
               rt_format == o.rt_format &&
               depth_format == o.depth_format &&
               depth_test_enable == o.depth_test_enable &&
               depth_write_enable == o.depth_write_enable &&
               depth_compare_op == o.depth_compare_op &&
               stencil_test_enable == o.stencil_test_enable &&
               stencil_compare_op == o.stencil_compare_op &&
               stencil_fail_op == o.stencil_fail_op &&
               stencil_depth_fail_op == o.stencil_depth_fail_op &&
               stencil_pass_op == o.stencil_pass_op &&
               stencil_read_mask == o.stencil_read_mask &&
               stencil_write_mask == o.stencil_write_mask &&
               cull_mode == o.cull_mode &&
               front_face == o.front_face;
    }
};

struct PipelineKeyHash {
    size_t operator()(const PipelineKey& k) const {
        size_t h = 0;
        h ^= std::hash<int>()(k.blend_enable) + 0x9e3779b9 + (h << 6) + (h >> 2);
        h ^= std::hash<int>()(k.src_rgb) + 0x9e3779b9 + (h << 6) + (h >> 2);
        h ^= std::hash<int>()(k.dst_rgb) + 0x9e3779b9 + (h << 6) + (h >> 2);
        h ^= std::hash<int>()(k.write_mask) + 0x9e3779b9 + (h << 6) + (h >> 2);
        h ^= std::hash<int>()(k.prim_type) + 0x9e3779b9 + (h << 6) + (h >> 2);
        h ^= std::hash<int>()((int)k.rt_format) + 0x9e3779b9 + (h << 6) + (h >> 2);
        h ^= std::hash<int>()((int)k.depth_format) + 0x9e3779b9 + (h << 6) + (h >> 2);
        h ^= std::hash<int>()(k.depth_test_enable) + 0x9e3779b9 + (h << 6) + (h >> 2);
        h ^= std::hash<int>()(k.depth_write_enable) + 0x9e3779b9 + (h << 6) + (h >> 2);
        h ^= std::hash<int>()(k.depth_compare_op) + 0x9e3779b9 + (h << 6) + (h >> 2);
        h ^= std::hash<int>()(k.stencil_test_enable) + 0x9e3779b9 + (h << 6) + (h >> 2);
        h ^= std::hash<int>()(k.cull_mode) + 0x9e3779b9 + (h << 6) + (h >> 2);
        h ^= std::hash<int>()(k.front_face) + 0x9e3779b9 + (h << 6) + (h >> 2);
        return h;
    }
};

struct FramebufferCacheKey {
    uint32_t color_tex_id;
    uint32_t depth_tex_id;
    int clear;
    bool operator==(const FramebufferCacheKey& o) const {
        return color_tex_id == o.color_tex_id && depth_tex_id == o.depth_tex_id && clear == o.clear;
    }
};

struct FramebufferCacheKeyHash {
    size_t operator()(const FramebufferCacheKey& k) const {
        return (std::hash<uint64_t>()(((uint64_t)k.color_tex_id << 32) | k.depth_tex_id)) ^ std::hash<int>()(k.clear);
    }
};

struct CachedTarget {
    VkRenderPass render_pass = VK_NULL_HANDLE;
    VkFramebuffer framebuffer = VK_NULL_HANDLE;
};

static std::unordered_map<FramebufferCacheKey, CachedTarget, FramebufferCacheKeyHash> g_fb_cache;
static VkRenderPass g_active_render_pass = VK_NULL_HANDLE;

static std::unordered_map<PipelineKey, VkPipeline, PipelineKeyHash> g_pipelines;

// Helpers
static uint32_t find_memory_type(uint32_t typeFilter, VkMemoryPropertyFlags properties) {
    for (uint32_t i = 0; i < g_mem_props.memoryTypeCount; i++) {
        if ((typeFilter & (1 << i)) && (g_mem_props.memoryTypes[i].propertyFlags & properties) == properties) {
            return i;
        }
    }
    return 0;
}

// Map Metal pixel formats to Vulkan formats
static VkFormat map_metal_fmt_to_vk(int fmt) {
    switch (fmt) {
    case 1:   /* A8Unorm */      return VK_FORMAT_R8_UNORM;
    case 10:  /* R8Unorm */      return VK_FORMAT_R8_UNORM;
    case 11:  /* R8Unorm_sRGB */ return VK_FORMAT_R8_SRGB;
    case 30:  /* RG8Unorm */     return VK_FORMAT_R8G8_UNORM;
    case 31:  /* RG8Unorm_sRGB */return VK_FORMAT_R8G8_SRGB;
    case 70:  /* RGBA8Unorm */   return VK_FORMAT_R8G8B8A8_UNORM;
    case 71:  /* RGBA8Unorm_sRGB */return VK_FORMAT_R8G8B8A8_SRGB;
    case 80:  /* BGRA8Unorm */   return VK_FORMAT_B8G8R8A8_UNORM;
    case 81:  /* BGRA8Unorm_sRGB */return VK_FORMAT_B8G8R8A8_SRGB;
    case 115: /* RGBA16Float */  return VK_FORMAT_R16G16B16A16_SFLOAT;
    case 125: /* RGBA32Float */  return VK_FORMAT_R32G32B32A32_SFLOAT;
    case 251: /* Depth16Unorm */ return VK_FORMAT_D16_UNORM;
    case 252: /* Depth32Float */ return VK_FORMAT_D32_SFLOAT;
    default:  return VK_FORMAT_B8G8R8A8_UNORM;
    }
}

static VkBlendFactor map_vk_blend_factor(int factor) {
    switch (factor) {
    case 0: return VK_BLEND_FACTOR_ZERO;
    case 1: return VK_BLEND_FACTOR_ONE;
    case 2: return VK_BLEND_FACTOR_SRC_COLOR;
    case 3: return VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR;
    case 4: return VK_BLEND_FACTOR_SRC_ALPHA;
    case 5: return VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    case 6: return VK_BLEND_FACTOR_DST_COLOR;
    case 7: return VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR;
    case 8: return VK_BLEND_FACTOR_DST_ALPHA;
    case 9: return VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA;
    case 10: return VK_BLEND_FACTOR_SRC_ALPHA_SATURATE;
    case 11: return VK_BLEND_FACTOR_CONSTANT_COLOR;
    case 12: return VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_COLOR;
    case 13: return VK_BLEND_FACTOR_CONSTANT_ALPHA;
    case 14: return VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_ALPHA;
    default: return VK_BLEND_FACTOR_ONE;
    }
}

static VkBlendOp map_vk_blend_op(int op) {
    switch (op) {
    case 0: return VK_BLEND_OP_ADD;
    case 1: return VK_BLEND_OP_SUBTRACT;
    case 2: return VK_BLEND_OP_REVERSE_SUBTRACT;
    case 3: return VK_BLEND_OP_MIN;
    case 4: return VK_BLEND_OP_MAX;
    default: return VK_BLEND_OP_ADD;
    }
}

static VkPrimitiveTopology map_vk_prim_topology(int prim_type) {
    switch (prim_type) {
    case 0: return VK_PRIMITIVE_TOPOLOGY_POINT_LIST;
    case 1: return VK_PRIMITIVE_TOPOLOGY_LINE_LIST;
    case 2: return VK_PRIMITIVE_TOPOLOGY_LINE_STRIP;
    case 3: return VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    case 4: return VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP;
    default: return VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    }
}

static VkCompareOp map_vk_compare_op(int op) {
    switch (op) {
    case 0: return VK_COMPARE_OP_NEVER;
    case 1: return VK_COMPARE_OP_LESS;
    case 2: return VK_COMPARE_OP_EQUAL;
    case 3: return VK_COMPARE_OP_LESS_OR_EQUAL;
    case 4: return VK_COMPARE_OP_GREATER;
    case 5: return VK_COMPARE_OP_NOT_EQUAL;
    case 6: return VK_COMPARE_OP_GREATER_OR_EQUAL;
    case 7: return VK_COMPARE_OP_ALWAYS;
    default: return VK_COMPARE_OP_ALWAYS;
    }
}

static VkStencilOp map_vk_stencil_op(int op) {
    switch (op) {
    case 0: return VK_STENCIL_OP_KEEP;
    case 1: return VK_STENCIL_OP_ZERO;
    case 2: return VK_STENCIL_OP_REPLACE;
    case 3: return VK_STENCIL_OP_INCREMENT_AND_CLAMP;
    case 4: return VK_STENCIL_OP_DECREMENT_AND_CLAMP;
    case 5: return VK_STENCIL_OP_INVERT;
    case 6: return VK_STENCIL_OP_INCREMENT_AND_WRAP;
    case 7: return VK_STENCIL_OP_DECREMENT_AND_WRAP;
    default: return VK_STENCIL_OP_KEEP;
    }
}

static VkCommandBuffer begin_single_time_commands() {
    VkCommandBufferAllocateInfo allocInfo = { VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO };
    allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    allocInfo.commandPool = g_cmd_pool;
    allocInfo.commandBufferCount = 1;

    VkCommandBuffer commandBuffer = VK_NULL_HANDLE;
    vkAllocateCommandBuffers(g_device, &allocInfo, &commandBuffer);

    VkCommandBufferBeginInfo beginInfo = { VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(commandBuffer, &beginInfo);
    return commandBuffer;
}

static void end_single_time_commands(VkCommandBuffer commandBuffer) {
    vkEndCommandBuffer(commandBuffer);

    VkSubmitInfo submitInfo = { VK_STRUCTURE_TYPE_SUBMIT_INFO };
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &commandBuffer;

    vkQueueSubmit(g_queue, 1, &submitInfo, VK_NULL_HANDLE);
    vkQueueWaitIdle(g_queue);

    vkFreeCommandBuffers(g_device, g_cmd_pool, 1, &commandBuffer);
}

static void transition_image_layout(VkCommandBuffer cmd, VkImage image, VkFormat format, VkImageLayout oldLayout, VkImageLayout newLayout) {
    VkImageMemoryBarrier barrier = { VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER };
    barrier.oldLayout = oldLayout;
    barrier.newLayout = newLayout;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = image;
    barrier.subresourceRange.aspectMask = (format == VK_FORMAT_D32_SFLOAT || format == VK_FORMAT_D16_UNORM) ? VK_IMAGE_ASPECT_DEPTH_BIT : VK_IMAGE_ASPECT_COLOR_BIT;
    barrier.subresourceRange.baseMipLevel = 0;
    barrier.subresourceRange.levelCount = 1;
    barrier.subresourceRange.baseArrayLayer = 0;
    barrier.subresourceRange.layerCount = 1;

    VkPipelineStageFlags sourceStage = VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
    VkPipelineStageFlags destinationStage = VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;

    if (oldLayout == VK_IMAGE_LAYOUT_UNDEFINED && newLayout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        sourceStage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        destinationStage = VK_PIPELINE_STAGE_TRANSFER_BIT;
    } else if (oldLayout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL && newLayout == VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        sourceStage = VK_PIPELINE_STAGE_TRANSFER_BIT;
        destinationStage = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    } else if (oldLayout == VK_IMAGE_LAYOUT_UNDEFINED && newLayout == VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL) {
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        sourceStage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        destinationStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    } else if (oldLayout == VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL && newLayout == VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL) {
        barrier.srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        barrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        sourceStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        destinationStage = VK_PIPELINE_STAGE_TRANSFER_BIT;
    } else if (oldLayout == VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL && newLayout == VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL) {
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        barrier.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        sourceStage = VK_PIPELINE_STAGE_TRANSFER_BIT;
        destinationStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    } else {
        barrier.srcAccessMask = VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT;
        barrier.dstAccessMask = VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT;
    }

    vkCmdPipelineBarrier(cmd, sourceStage, destinationStage, 0, 0, nullptr, 0, nullptr, 1, &barrier);
}

static VkRenderPass create_render_pass(VkFormat colorFormat, VkFormat depthFormat, bool clearColor, bool clearDepth = true) {
    VkAttachmentDescription attachments[2] = {};
    uint32_t attachmentCount = 1;

    attachments[0].format = colorFormat;
    attachments[0].samples = VK_SAMPLE_COUNT_1_BIT;
    attachments[0].loadOp = clearColor ? VK_ATTACHMENT_LOAD_OP_CLEAR : VK_ATTACHMENT_LOAD_OP_LOAD;
    attachments[0].storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    attachments[0].stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    attachments[0].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    attachments[0].initialLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    attachments[0].finalLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

    VkAttachmentReference colorAttachmentRef = {};
    colorAttachmentRef.attachment = 0;
    colorAttachmentRef.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

    VkAttachmentReference depthAttachmentRef = {};
    bool has_depth = (depthFormat != VK_FORMAT_UNDEFINED);
    if (has_depth) {
        attachmentCount = 2;
        attachments[1].format = depthFormat;
        attachments[1].samples = VK_SAMPLE_COUNT_1_BIT;
        attachments[1].loadOp = clearDepth ? VK_ATTACHMENT_LOAD_OP_CLEAR : VK_ATTACHMENT_LOAD_OP_LOAD;
        attachments[1].storeOp = VK_ATTACHMENT_STORE_OP_STORE;
        attachments[1].stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
        attachments[1].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
        attachments[1].initialLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
        attachments[1].finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

        depthAttachmentRef.attachment = 1;
        depthAttachmentRef.layout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
    }

    VkSubpassDescription subpass = {};
    subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = 1;
    subpass.pColorAttachments = &colorAttachmentRef;
    subpass.pDepthStencilAttachment = has_depth ? &depthAttachmentRef : nullptr;

    VkSubpassDependency dependency = {};
    dependency.srcSubpass = VK_SUBPASS_EXTERNAL;
    dependency.dstSubpass = 0;
    dependency.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | (has_depth ? (VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT | VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT) : 0);
    dependency.srcAccessMask = 0;
    dependency.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | (has_depth ? (VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT | VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT) : 0);
    dependency.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | (has_depth ? VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT : 0);

    VkRenderPassCreateInfo renderPassInfo = { VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO };
    renderPassInfo.attachmentCount = attachmentCount;
    renderPassInfo.pAttachments = attachments;
    renderPassInfo.subpassCount = 1;
    renderPassInfo.pSubpasses = &subpass;
    renderPassInfo.dependencyCount = 1;
    renderPassInfo.pDependencies = &dependency;

    VkRenderPass rp = VK_NULL_HANDLE;
    vkCreateRenderPass(g_device, &renderPassInfo, nullptr, &rp);
    return rp;
}

static VkPipeline get_or_create_pipeline(const PipelineKey& key, VkRenderPass renderPass) {
    auto it = g_pipelines.find(key);
    if (it != g_pipelines.end()) return it->second;

    VkPipelineShaderStageCreateInfo shaderStages[2] = {};
    shaderStages[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    shaderStages[0].stage = VK_SHADER_STAGE_VERTEX_BIT;
    shaderStages[0].module = g_vs_module;
    shaderStages[0].pName = "main";

    shaderStages[1].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    shaderStages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT;
    shaderStages[1].module = g_fs_module;
    shaderStages[1].pName = "main";

    VkVertexInputBindingDescription bindingDesc = {};
    bindingDesc.binding = 0;
    bindingDesc.stride = sizeof(xef_host_metal_vertex_t);
    bindingDesc.inputRate = VK_VERTEX_INPUT_RATE_VERTEX;

    VkVertexInputAttributeDescription attribDescs[3] = {};
    attribDescs[0].binding = 0;
    attribDescs[0].location = 0;
    attribDescs[0].format = VK_FORMAT_R32G32B32_SFLOAT;
    attribDescs[0].offset = offsetof(xef_host_metal_vertex_t, sx);

    attribDescs[1].binding = 0;
    attribDescs[1].location = 1;
    attribDescs[1].format = VK_FORMAT_R32G32_SFLOAT;
    attribDescs[1].offset = offsetof(xef_host_metal_vertex_t, u);

    attribDescs[2].binding = 0;
    attribDescs[2].location = 2;
    attribDescs[2].format = VK_FORMAT_R32G32B32A32_SFLOAT;
    attribDescs[2].offset = offsetof(xef_host_metal_vertex_t, r);

    VkPipelineVertexInputStateCreateInfo vertexInputInfo = { VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO };
    vertexInputInfo.vertexBindingDescriptionCount = 1;
    vertexInputInfo.pVertexBindingDescriptions = &bindingDesc;
    vertexInputInfo.vertexAttributeDescriptionCount = 3;
    vertexInputInfo.pVertexAttributeDescriptions = attribDescs;

    VkPipelineInputAssemblyStateCreateInfo inputAssembly = { VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO };
    inputAssembly.topology = map_vk_prim_topology(key.prim_type);
    inputAssembly.primitiveRestartEnable = VK_FALSE;

    VkPipelineViewportStateCreateInfo viewportState = { VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO };
    viewportState.viewportCount = 1;
    viewportState.scissorCount = 1;

    VkPipelineRasterizationStateCreateInfo rasterizer = { VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO };
    rasterizer.depthClampEnable = VK_FALSE;
    rasterizer.rasterizerDiscardEnable = VK_FALSE;
    rasterizer.polygonMode = VK_POLYGON_MODE_FILL;
    rasterizer.lineWidth = 1.0f;
    rasterizer.cullMode = (key.cull_mode == 1) ? VK_CULL_MODE_FRONT_BIT :
                          (key.cull_mode == 2) ? VK_CULL_MODE_BACK_BIT : VK_CULL_MODE_NONE;
    rasterizer.frontFace = (key.front_face == 1) ? VK_FRONT_FACE_COUNTER_CLOCKWISE : VK_FRONT_FACE_CLOCKWISE;

    VkPipelineMultisampleStateCreateInfo multisampling = { VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO };
    multisampling.sampleShadingEnable = VK_FALSE;
    multisampling.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;

    VkPipelineColorBlendAttachmentState colorBlendAttachment = {};
    colorBlendAttachment.colorWriteMask = 0;
    if (key.write_mask & 8) colorBlendAttachment.colorWriteMask |= VK_COLOR_COMPONENT_R_BIT;
    if (key.write_mask & 4) colorBlendAttachment.colorWriteMask |= VK_COLOR_COMPONENT_G_BIT;
    if (key.write_mask & 2) colorBlendAttachment.colorWriteMask |= VK_COLOR_COMPONENT_B_BIT;
    if (key.write_mask & 1) colorBlendAttachment.colorWriteMask |= VK_COLOR_COMPONENT_A_BIT;

    if (key.blend_enable) {
        colorBlendAttachment.blendEnable = VK_TRUE;
        colorBlendAttachment.srcColorBlendFactor = map_vk_blend_factor(key.src_rgb);
        colorBlendAttachment.dstColorBlendFactor = map_vk_blend_factor(key.dst_rgb);
        colorBlendAttachment.colorBlendOp        = map_vk_blend_op(key.rgb_op);
        colorBlendAttachment.srcAlphaBlendFactor = map_vk_blend_factor(key.src_a);
        colorBlendAttachment.dstAlphaBlendFactor = map_vk_blend_factor(key.dst_a);
        colorBlendAttachment.alphaBlendOp        = map_vk_blend_op(key.a_op);
    } else {
        colorBlendAttachment.blendEnable = VK_FALSE;
    }

    VkPipelineColorBlendStateCreateInfo colorBlending = { VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO };
    colorBlending.logicOpEnable = VK_FALSE;
    colorBlending.attachmentCount = 1;
    colorBlending.pAttachments = &colorBlendAttachment;

    VkDynamicState dynamicStates[] = { VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR };
    VkPipelineDepthStencilStateCreateInfo depthStencil = { VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO };
    depthStencil.depthTestEnable = key.depth_test_enable ? VK_TRUE : VK_FALSE;
    depthStencil.depthWriteEnable = key.depth_write_enable ? VK_TRUE : VK_FALSE;
    depthStencil.depthCompareOp = map_vk_compare_op(key.depth_compare_op);
    depthStencil.depthBoundsTestEnable = VK_FALSE;
    depthStencil.stencilTestEnable = key.stencil_test_enable ? VK_TRUE : VK_FALSE;
    if (key.stencil_test_enable) {
        depthStencil.front.failOp = map_vk_stencil_op(key.stencil_fail_op);
        depthStencil.front.passOp = map_vk_stencil_op(key.stencil_pass_op);
        depthStencil.front.depthFailOp = map_vk_stencil_op(key.stencil_depth_fail_op);
        depthStencil.front.compareOp = map_vk_compare_op(key.stencil_compare_op);
        depthStencil.front.compareMask = key.stencil_read_mask;
        depthStencil.front.writeMask = key.stencil_write_mask;
        depthStencil.front.reference = 0; // overridden by dynamic or static
        depthStencil.back = depthStencil.front;
    }

    VkPipelineDynamicStateCreateInfo dynamicState = { VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO };
    dynamicState.dynamicStateCount = 2;
    dynamicState.pDynamicStates = dynamicStates;

    VkGraphicsPipelineCreateInfo pipelineInfo = { VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO };
    pipelineInfo.stageCount = 2;
    pipelineInfo.pStages = shaderStages;
    pipelineInfo.pVertexInputState = &vertexInputInfo;
    pipelineInfo.pInputAssemblyState = &inputAssembly;
    pipelineInfo.pViewportState = &viewportState;
    pipelineInfo.pRasterizationState = &rasterizer;
    pipelineInfo.pMultisampleState = &multisampling;
    pipelineInfo.pDepthStencilState = &depthStencil;
    pipelineInfo.pColorBlendState = &colorBlending;
    pipelineInfo.pDynamicState = &dynamicState;
    pipelineInfo.layout = g_pipeline_layout;
    pipelineInfo.renderPass = renderPass;
    pipelineInfo.subpass = 0;

    VkPipeline pipeline = VK_NULL_HANDLE;
    VkResult res = vkCreateGraphicsPipelines(g_device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &pipeline);
    if (res == VK_SUCCESS) {
        g_pipelines[key] = pipeline;
    } else {
        fprintf(stderr, "[xef-metal] vkCreateGraphicsPipelines failed with rc=%d\n", res);
    }
    return pipeline;
}

static void update_texture_descriptor(MetalVkTex& tex, VkSampler sampler, VkDescriptorSet& dset) {
    if (dset == VK_NULL_HANDLE) {
        VkDescriptorSetAllocateInfo allocInfo = { VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO };
        allocInfo.descriptorPool = g_desc_pool;
        allocInfo.descriptorSetCount = 1;
        allocInfo.pSetLayouts = &g_desc_layout;
        vkAllocateDescriptorSets(g_device, &allocInfo, &dset);
    }
    VkDescriptorImageInfo imageInfo = {};
    imageInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    imageInfo.imageView = tex.view;
    imageInfo.sampler = sampler;

    VkWriteDescriptorSet descriptorWrite = { VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET };
    descriptorWrite.dstSet = dset;
    descriptorWrite.dstBinding = 0;
    descriptorWrite.dstArrayElement = 0;
    descriptorWrite.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    descriptorWrite.descriptorCount = 1;
    descriptorWrite.pImageInfo = &imageInfo;
    vkUpdateDescriptorSets(g_device, 1, &descriptorWrite, 0, nullptr);
}

bool init() {
    std::lock_guard<std::mutex> lk(g_metal_vk_lock);
    if (g_initialized) return g_available;
    g_initialized = true;

    const char* force = getenv("XEF_METAL_BACKEND");
    if (force && (strcmp(force, "gl") == 0 || strcmp(force, "opengl") == 0 || strcmp(force, "sw") == 0)) {
        return false;
    }

    g_vk_lib = dlopen("libvulkan.so.1", RTLD_NOW | RTLD_LOCAL);
    if (!g_vk_lib) g_vk_lib = dlopen("libvulkan.so", RTLD_NOW | RTLD_LOCAL);
    if (!g_vk_lib) return false;

    vkGetInstanceProcAddr = (PFN_vkGetInstanceProcAddr)dlsym(g_vk_lib, "vkGetInstanceProcAddr");
    if (!vkGetInstanceProcAddr) return false;

    vkCreateInstance = (PFN_vkCreateInstance)vkGetInstanceProcAddr(NULL, "vkCreateInstance");
    if (!vkCreateInstance) return false;

    VkApplicationInfo appInfo = { VK_STRUCTURE_TYPE_APPLICATION_INFO };
    appInfo.pApplicationName = "XEFMetalVK";
    appInfo.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.pEngineName = "XEFMetalVK";
    appInfo.engineVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.apiVersion = VK_API_VERSION_1_3;

    VkInstanceCreateInfo ici = { VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO };
    ici.pApplicationInfo = &appInfo;

    if (vkCreateInstance(&ici, nullptr, &g_instance) != VK_SUCCESS) {
        appInfo.apiVersion = VK_API_VERSION_1_1;
        if (vkCreateInstance(&ici, nullptr, &g_instance) != VK_SUCCESS) return false;
    }

    #define LOAD_VK_INST(fn) fn = (PFN_ ## fn)vkGetInstanceProcAddr(g_instance, #fn); if (!fn) return false;
    LOAD_VK_INST(vkDestroyInstance);
    LOAD_VK_INST(vkEnumeratePhysicalDevices);
    LOAD_VK_INST(vkGetPhysicalDeviceProperties);
    LOAD_VK_INST(vkGetPhysicalDeviceQueueFamilyProperties);
    LOAD_VK_INST(vkGetPhysicalDeviceMemoryProperties);
    LOAD_VK_INST(vkCreateDevice);
    LOAD_VK_INST(vkDestroyDevice);
    LOAD_VK_INST(vkGetDeviceQueue);
    #undef LOAD_VK_INST

    uint32_t deviceCount = 0;
    vkEnumeratePhysicalDevices(g_instance, &deviceCount, nullptr);
    if (deviceCount == 0) return false;

    std::vector<VkPhysicalDevice> pdevs(deviceCount);
    vkEnumeratePhysicalDevices(g_instance, &deviceCount, pdevs.data());

    // Prefer discrete GPU
    for (auto pd : pdevs) {
        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(pd, &props);
        if (props.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
            g_physical_device = pd;
            g_device_props = props;
            break;
        }
    }
    if (!g_physical_device && !pdevs.empty()) {
        g_physical_device = pdevs[0];
        vkGetPhysicalDeviceProperties(g_physical_device, &g_device_props);
    }
    vkGetPhysicalDeviceMemoryProperties(g_physical_device, &g_mem_props);
    g_device_name = std::string(g_device_props.deviceName);

    // Queue family
    uint32_t qCount = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(g_physical_device, &qCount, nullptr);
    std::vector<VkQueueFamilyProperties> qProps(qCount);
    vkGetPhysicalDeviceQueueFamilyProperties(g_physical_device, &qCount, qProps.data());

    bool foundQueue = false;
    for (uint32_t i = 0; i < qCount; i++) {
        if (qProps[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) {
            g_queue_family = i;
            foundQueue = true;
            break;
        }
    }
    if (!foundQueue) return false;

    float priority = 1.0f;
    VkDeviceQueueCreateInfo qci = { VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO };
    qci.queueFamilyIndex = g_queue_family;
    qci.queueCount = 1;
    qci.pQueuePriorities = &priority;

    VkDeviceCreateInfo dci = { VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO };
    dci.queueCreateInfoCount = 1;
    dci.pQueueCreateInfos = &qci;

    if (vkCreateDevice(g_physical_device, &dci, nullptr, &g_device) != VK_SUCCESS) return false;
    vkGetDeviceQueue(g_device, g_queue_family, 0, &g_queue);

    #define LOAD_VK_DEV(fn) fn = (PFN_ ## fn)vkGetInstanceProcAddr(g_instance, #fn); if (!fn) return false;
    LOAD_VK_DEV(vkCreateCommandPool);
    LOAD_VK_DEV(vkDestroyCommandPool);
    LOAD_VK_DEV(vkAllocateCommandBuffers);
    LOAD_VK_DEV(vkFreeCommandBuffers);
    LOAD_VK_DEV(vkBeginCommandBuffer);
    LOAD_VK_DEV(vkEndCommandBuffer);
    LOAD_VK_DEV(vkQueueSubmit);
    LOAD_VK_DEV(vkQueueWaitIdle);
    LOAD_VK_DEV(vkCreateBuffer);
    LOAD_VK_DEV(vkDestroyBuffer);
    LOAD_VK_DEV(vkGetBufferMemoryRequirements);
    LOAD_VK_DEV(vkAllocateMemory);
    LOAD_VK_DEV(vkFreeMemory);
    LOAD_VK_DEV(vkBindBufferMemory);
    LOAD_VK_DEV(vkMapMemory);
    LOAD_VK_DEV(vkUnmapMemory);
    LOAD_VK_DEV(vkCreateImage);
    LOAD_VK_DEV(vkDestroyImage);
    LOAD_VK_DEV(vkGetImageMemoryRequirements);
    LOAD_VK_DEV(vkBindImageMemory);
    LOAD_VK_DEV(vkCreateImageView);
    LOAD_VK_DEV(vkDestroyImageView);
    LOAD_VK_DEV(vkCreateSampler);
    LOAD_VK_DEV(vkDestroySampler);
    LOAD_VK_DEV(vkCreateRenderPass);
    LOAD_VK_DEV(vkDestroyRenderPass);
    LOAD_VK_DEV(vkCreateFramebuffer);
    LOAD_VK_DEV(vkDestroyFramebuffer);
    LOAD_VK_DEV(vkCreateShaderModule);
    LOAD_VK_DEV(vkDestroyShaderModule);
    LOAD_VK_DEV(vkCreatePipelineLayout);
    LOAD_VK_DEV(vkDestroyPipelineLayout);
    LOAD_VK_DEV(vkCreateGraphicsPipelines);
    LOAD_VK_DEV(vkDestroyPipeline);
    LOAD_VK_DEV(vkCmdBeginRenderPass);
    LOAD_VK_DEV(vkCmdEndRenderPass);
    LOAD_VK_DEV(vkCmdBindPipeline);
    LOAD_VK_DEV(vkCmdSetViewport);
    LOAD_VK_DEV(vkCmdSetScissor);
    LOAD_VK_DEV(vkCmdBindVertexBuffers);
    LOAD_VK_DEV(vkCmdBindIndexBuffer);
    LOAD_VK_DEV(vkCmdDraw);
    LOAD_VK_DEV(vkCmdDrawIndexed);
    LOAD_VK_DEV(vkCmdPushConstants);
    LOAD_VK_DEV(vkCmdPipelineBarrier);
    LOAD_VK_DEV(vkCmdCopyBufferToImage);
    LOAD_VK_DEV(vkCmdCopyImageToBuffer);
    LOAD_VK_DEV(vkCmdCopyImage);
    LOAD_VK_DEV(vkCmdBlitImage);
    LOAD_VK_DEV(vkCreateDescriptorSetLayout);
    LOAD_VK_DEV(vkDestroyDescriptorSetLayout);
    LOAD_VK_DEV(vkCreateDescriptorPool);
    LOAD_VK_DEV(vkDestroyDescriptorPool);
    LOAD_VK_DEV(vkAllocateDescriptorSets);
    LOAD_VK_DEV(vkUpdateDescriptorSets);
    LOAD_VK_DEV(vkCmdBindDescriptorSets);
    #undef LOAD_VK_DEV

    VkCommandPoolCreateInfo cpci = { VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO };
    cpci.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    cpci.queueFamilyIndex = g_queue_family;
    if (vkCreateCommandPool(g_device, &cpci, nullptr, &g_cmd_pool) != VK_SUCCESS) return false;

    // Descriptor set layout: binding 0 = combined image sampler
    VkDescriptorSetLayoutBinding binding = {};
    binding.binding = 0;
    binding.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    binding.descriptorCount = 1;
    binding.stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT;

    VkDescriptorSetLayoutCreateInfo dslci = { VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO };
    dslci.bindingCount = 1;
    dslci.pBindings = &binding;
    if (vkCreateDescriptorSetLayout(g_device, &dslci, nullptr, &g_desc_layout) != VK_SUCCESS) return false;

    // Descriptor pool
    VkDescriptorPoolSize poolSize = { VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 2048 };
    VkDescriptorPoolCreateInfo dpci = { VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO };
    dpci.flags = VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT;
    dpci.maxSets = 2048;
    dpci.poolSizeCount = 1;
    dpci.pPoolSizes = &poolSize;
    if (vkCreateDescriptorPool(g_device, &dpci, nullptr, &g_desc_pool) != VK_SUCCESS) return false;

    // Pipeline layout with push constants
    VkPushConstantRange pcr = {};
    pcr.stageFlags = VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT;
    pcr.offset = 0;
    pcr.size = sizeof(PushConstants);

    VkPipelineLayoutCreateInfo plci = { VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO };
    plci.setLayoutCount = 1;
    plci.pSetLayouts = &g_desc_layout;
    plci.pushConstantRangeCount = 1;
    plci.pPushConstantRanges = &pcr;
    if (vkCreatePipelineLayout(g_device, &plci, nullptr, &g_pipeline_layout) != VK_SUCCESS) return false;

    // Shaders
    VkShaderModuleCreateInfo vsInfo = { VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO };
    vsInfo.codeSize = sizeof(metal_vk_vert_spv);
    vsInfo.pCode = metal_vk_vert_spv;
    if (vkCreateShaderModule(g_device, &vsInfo, nullptr, &g_vs_module) != VK_SUCCESS) return false;

    VkShaderModuleCreateInfo fsInfo = { VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO };
    fsInfo.codeSize = sizeof(metal_vk_frag_spv);
    fsInfo.pCode = metal_vk_frag_spv;
    if (vkCreateShaderModule(g_device, &fsInfo, nullptr, &g_fs_module) != VK_SUCCESS) return false;

    // Samplers
    VkSamplerCreateInfo sci = { VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO };
    sci.magFilter = VK_FILTER_LINEAR;
    sci.minFilter = VK_FILTER_LINEAR;
    sci.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    sci.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    sci.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    vkCreateSampler(g_device, &sci, nullptr, &g_sampler_linear);

    sci.magFilter = VK_FILTER_NEAREST;
    sci.minFilter = VK_FILTER_NEAREST;
    vkCreateSampler(g_device, &sci, nullptr, &g_sampler_nearest);

    // Create a 1x1 white dummy texture for color-only draws
    g_white_tex_id = tex_create(1, 1, 70 /*RGBA8*/, 0);
    uint32_t white_pixel = 0xFFFFFFFF;
    tex_update(g_white_tex_id, 0, 0, 1, 1, &white_pixel, 4);

    g_available = true;
    fprintf(stderr, "[xef-metal] MetalVK: Vulkan 1.3/1.4 hardware backend initialized on %s\n", g_device_name.c_str());
    return true;
}

void finit() {
    std::lock_guard<std::mutex> lk(g_metal_vk_lock);
    if (!g_available) return;
    vkQueueWaitIdle(g_queue);

    for (auto& kv : g_pipelines) vkDestroyPipeline(g_device, kv.second, nullptr);
    g_pipelines.clear();

    for (auto& kv : g_textures) {
        MetalVkTex& t = kv.second;
        if (t.framebuffer_clear) vkDestroyFramebuffer(g_device, t.framebuffer_clear, nullptr);
        if (t.framebuffer_load) vkDestroyFramebuffer(g_device, t.framebuffer_load, nullptr);
        if (t.render_pass_clear) vkDestroyRenderPass(g_device, t.render_pass_clear, nullptr);
        if (t.render_pass_load) vkDestroyRenderPass(g_device, t.render_pass_load, nullptr);
        if (t.view) vkDestroyImageView(g_device, t.view, nullptr);
        if (t.image) vkDestroyImage(g_device, t.image, nullptr);
        if (t.memory) vkFreeMemory(g_device, t.memory, nullptr);
    }
    g_textures.clear();

    if (g_sampler_linear) vkDestroySampler(g_device, g_sampler_linear, nullptr);
    if (g_sampler_nearest) vkDestroySampler(g_device, g_sampler_nearest, nullptr);
    if (g_vs_module) vkDestroyShaderModule(g_device, g_vs_module, nullptr);
    if (g_fs_module) vkDestroyShaderModule(g_device, g_fs_module, nullptr);
    if (g_pipeline_layout) vkDestroyPipelineLayout(g_device, g_pipeline_layout, nullptr);
    if (g_desc_pool) vkDestroyDescriptorPool(g_device, g_desc_pool, nullptr);
    if (g_desc_layout) vkDestroyDescriptorSetLayout(g_device, g_desc_layout, nullptr);
    if (g_cmd_pool) vkDestroyCommandPool(g_device, g_cmd_pool, nullptr);
    if (g_device) vkDestroyDevice(g_device, nullptr);
    if (g_instance) vkDestroyInstance(g_instance, nullptr);
    if (g_vk_lib) dlclose(g_vk_lib);

    g_available = false;
    g_initialized = false;
}

bool is_available() {
    if (!g_initialized) init();
    return g_available;
}

const char* get_device_name() {
    return g_device_name.empty() ? "MetalVK Vulkan Device" : g_device_name.c_str();
}

uint32_t tex_create(int w, int h, int fmt, int is_render_target) {
    if (!is_available()) return 0;
    std::lock_guard<std::mutex> lk(g_metal_vk_lock);

    uint32_t id = g_next_tex_id++;
    MetalVkTex t;
    t.id = id;
    t.w = w > 0 ? w : 1;
    t.h = h > 0 ? h : 1;
    t.fmt = fmt;
    t.is_rt = (is_render_target != 0);
    t.vk_fmt = map_metal_fmt_to_vk(fmt);

    VkImageCreateInfo ici = { VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO };
    ici.imageType = VK_IMAGE_TYPE_2D;
    ici.format = t.vk_fmt;
    ici.extent.width = t.w;
    ici.extent.height = t.h;
    ici.extent.depth = 1;
    bool is_depth = (t.vk_fmt == VK_FORMAT_D32_SFLOAT || t.vk_fmt == VK_FORMAT_D16_UNORM);
    int mipLevels = 1;
    if (!is_depth && t.w > 1 && t.h > 1) {
        int maxDim = std::max(t.w, t.h);
        while (maxDim > 1) {
            maxDim >>= 1;
            mipLevels++;
        }
    }
    t.mip_levels = mipLevels;
    ici.mipLevels = mipLevels;
    ici.arrayLayers = 1;
    ici.samples = VK_SAMPLE_COUNT_1_BIT;
    ici.tiling = VK_IMAGE_TILING_OPTIMAL;
    ici.usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    if (t.is_rt) ici.usage |= is_depth ? VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT : VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    ici.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    ici.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

    if (vkCreateImage(g_device, &ici, nullptr, &t.image) != VK_SUCCESS) return 0;

    VkMemoryRequirements memReq;
    vkGetImageMemoryRequirements(g_device, t.image, &memReq);

    VkMemoryAllocateInfo mai = { VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO };
    mai.allocationSize = memReq.size;
    mai.memoryTypeIndex = find_memory_type(memReq.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (vkAllocateMemory(g_device, &mai, nullptr, &t.memory) != VK_SUCCESS) {
        vkDestroyImage(g_device, t.image, nullptr);
        return 0;
    }
    vkBindImageMemory(g_device, t.image, t.memory, 0);

    VkImageViewCreateInfo ivci = { VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO };
    ivci.image = t.image;
    ivci.viewType = VK_IMAGE_VIEW_TYPE_2D;
    ivci.format = t.vk_fmt;
    ivci.subresourceRange.aspectMask = is_depth ? VK_IMAGE_ASPECT_DEPTH_BIT : VK_IMAGE_ASPECT_COLOR_BIT;
    ivci.subresourceRange.baseMipLevel = 0;
    ivci.subresourceRange.levelCount = mipLevels;
    ivci.subresourceRange.baseArrayLayer = 0;
    ivci.subresourceRange.layerCount = 1;

    if (vkCreateImageView(g_device, &ivci, nullptr, &t.view) != VK_SUCCESS) {
        vkFreeMemory(g_device, t.memory, nullptr);
        vkDestroyImage(g_device, t.image, nullptr);
        return 0;
    }

    // Transition image to initial layout
    VkCommandBuffer cmd = begin_single_time_commands();
    VkImageLayout target_layout = t.is_rt ? (is_depth ? VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL : VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL) : VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    transition_image_layout(cmd, t.image, t.vk_fmt, VK_IMAGE_LAYOUT_UNDEFINED, target_layout);
    end_single_time_commands(cmd);
    t.layout = target_layout;

    if (t.is_rt && !is_depth) {
        t.render_pass_clear = create_render_pass(t.vk_fmt, VK_FORMAT_UNDEFINED, true);
        t.render_pass_load  = create_render_pass(t.vk_fmt, VK_FORMAT_UNDEFINED, false);

        VkFramebufferCreateInfo fbInfo = { VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO };
        fbInfo.attachmentCount = 1;
        fbInfo.pAttachments = &t.view;
        fbInfo.width = t.w;
        fbInfo.height = t.h;
        fbInfo.layers = 1;

        fbInfo.renderPass = t.render_pass_clear;
        vkCreateFramebuffer(g_device, &fbInfo, nullptr, &t.framebuffer_clear);

        fbInfo.renderPass = t.render_pass_load;
        vkCreateFramebuffer(g_device, &fbInfo, nullptr, &t.framebuffer_load);
    }

    update_texture_descriptor(t, g_sampler_linear, t.desc_set_linear);
    update_texture_descriptor(t, g_sampler_nearest, t.desc_set_nearest);

    g_textures[id] = t;
    return id;
}

void tex_update(uint32_t tex_id, int x, int y, int w, int h, const void* data, int pitch) {
    if (!is_available() || !data || w <= 0 || h <= 0) return;
    std::lock_guard<std::mutex> lk(g_metal_vk_lock);
    auto it = g_textures.find(tex_id);
    if (it == g_textures.end()) return;
    MetalVkTex& tex = it->second;

    size_t bpp = 4;
    size_t row_size = (size_t)w * bpp;
    size_t upload_size = row_size * h;

    VkBuffer stagingBuffer = VK_NULL_HANDLE;
    VkDeviceMemory stagingMemory = VK_NULL_HANDLE;

    VkBufferCreateInfo bci = { VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO };
    bci.size = upload_size;
    bci.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    bci.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    if (vkCreateBuffer(g_device, &bci, nullptr, &stagingBuffer) != VK_SUCCESS) return;

    VkMemoryRequirements memReq;
    vkGetBufferMemoryRequirements(g_device, stagingBuffer, &memReq);

    VkMemoryAllocateInfo mai = { VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO };
    mai.allocationSize = memReq.size;
    mai.memoryTypeIndex = find_memory_type(memReq.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    if (vkAllocateMemory(g_device, &mai, nullptr, &stagingMemory) != VK_SUCCESS) {
        vkDestroyBuffer(g_device, stagingBuffer, nullptr);
        return;
    }
    vkBindBufferMemory(g_device, stagingBuffer, stagingMemory, 0);

    void* mapped = nullptr;
    vkMapMemory(g_device, stagingMemory, 0, upload_size, 0, &mapped);
    const uint8_t* src = (const uint8_t*)data;
    uint8_t* dst = (uint8_t*)mapped;
    int src_pitch = (pitch > 0) ? pitch : (int)row_size;

    for (int r = 0; r < h; r++) {
        memcpy(dst + r * row_size, src + r * src_pitch, row_size);
    }
    vkUnmapMemory(g_device, stagingMemory);

    VkCommandBuffer cmd = begin_single_time_commands();
    transition_image_layout(cmd, tex.image, tex.vk_fmt, tex.layout, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);

    VkBufferImageCopy region = {};
    region.bufferOffset = 0;
    region.bufferRowLength = 0;
    region.bufferImageHeight = 0;
    region.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    region.imageSubresource.mipLevel = 0;
    region.imageSubresource.baseArrayLayer = 0;
    region.imageSubresource.layerCount = 1;
    region.imageOffset = { x, y, 0 };
    region.imageExtent = { (uint32_t)w, (uint32_t)h, 1 };

    vkCmdCopyBufferToImage(cmd, stagingBuffer, tex.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

    VkImageLayout final_layout = tex.is_rt ? VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL : VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    transition_image_layout(cmd, tex.image, tex.vk_fmt, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, final_layout);
    end_single_time_commands(cmd);
    tex.layout = final_layout;

    vkFreeMemory(g_device, stagingMemory, nullptr);
    vkDestroyBuffer(g_device, stagingBuffer, nullptr);
}

void tex_copy(uint32_t src_tex_id, int sx, int sy, int sw, int sh, uint32_t dst_tex_id, int dx, int dy) {
    if (!is_available() || sw <= 0 || sh <= 0) return;
    std::lock_guard<std::mutex> lk(g_metal_vk_lock);
    auto it_src = g_textures.find(src_tex_id);
    auto it_dst = g_textures.find(dst_tex_id);
    if (it_src == g_textures.end() || it_dst == g_textures.end()) return;

    MetalVkTex& src = it_src->second;
    MetalVkTex& dst = it_dst->second;

    VkCommandBuffer cmd = begin_single_time_commands();
    transition_image_layout(cmd, src.image, src.vk_fmt, src.layout, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
    transition_image_layout(cmd, dst.image, dst.vk_fmt, dst.layout, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);

    VkImageCopy copyRegion = {};
    copyRegion.srcSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    copyRegion.srcSubresource.layerCount = 1;
    copyRegion.srcOffset = { sx, sy, 0 };
    copyRegion.dstSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    copyRegion.dstSubresource.layerCount = 1;
    copyRegion.dstOffset = { dx, dy, 0 };
    copyRegion.extent = { (uint32_t)sw, (uint32_t)sh, 1 };

    vkCmdCopyImage(cmd, src.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                        dst.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                        1, &copyRegion);

    VkImageLayout src_final = src.is_rt ? VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL : VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    VkImageLayout dst_final = dst.is_rt ? VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL : VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    transition_image_layout(cmd, src.image, src.vk_fmt, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, src_final);
    transition_image_layout(cmd, dst.image, dst.vk_fmt, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, dst_final);
    end_single_time_commands(cmd);

    src.layout = src_final;
    dst.layout = dst_final;
}

void tex_readback(uint32_t tex_id, int x, int y, int w, int h, void* out_data, int pitch) {
    if (!is_available() || !out_data || w <= 0 || h <= 0) return;
    std::lock_guard<std::mutex> lk(g_metal_vk_lock);
    auto it = g_textures.find(tex_id);
    if (it == g_textures.end()) return;
    MetalVkTex& tex = it->second;

    size_t bpp = 4;
    size_t row_size = (size_t)w * bpp;
    size_t read_size = row_size * h;

    VkBuffer stagingBuffer = VK_NULL_HANDLE;
    VkDeviceMemory stagingMemory = VK_NULL_HANDLE;

    VkBufferCreateInfo bci = { VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO };
    bci.size = read_size;
    bci.usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    bci.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    if (vkCreateBuffer(g_device, &bci, nullptr, &stagingBuffer) != VK_SUCCESS) return;

    VkMemoryRequirements memReq;
    vkGetBufferMemoryRequirements(g_device, stagingBuffer, &memReq);

    VkMemoryAllocateInfo mai = { VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO };
    mai.allocationSize = memReq.size;
    mai.memoryTypeIndex = find_memory_type(memReq.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    if (vkAllocateMemory(g_device, &mai, nullptr, &stagingMemory) != VK_SUCCESS) {
        vkDestroyBuffer(g_device, stagingBuffer, nullptr);
        return;
    }
    vkBindBufferMemory(g_device, stagingBuffer, stagingMemory, 0);

    VkCommandBuffer cmd = begin_single_time_commands();
    transition_image_layout(cmd, tex.image, tex.vk_fmt, tex.layout, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);

    VkBufferImageCopy region = {};
    region.bufferOffset = 0;
    region.bufferRowLength = 0;
    region.bufferImageHeight = 0;
    region.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    region.imageSubresource.mipLevel = 0;
    region.imageSubresource.baseArrayLayer = 0;
    region.imageSubresource.layerCount = 1;
    region.imageOffset = { x, y, 0 };
    region.imageExtent = { (uint32_t)w, (uint32_t)h, 1 };

    vkCmdCopyImageToBuffer(cmd, tex.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, stagingBuffer, 1, &region);

    VkImageLayout final_layout = tex.is_rt ? VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL : VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    transition_image_layout(cmd, tex.image, tex.vk_fmt, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, final_layout);
    end_single_time_commands(cmd);
    tex.layout = final_layout;

    void* mapped = nullptr;
    vkMapMemory(g_device, stagingMemory, 0, read_size, 0, &mapped);
    const uint8_t* src = (const uint8_t*)mapped;
    uint8_t* dst = (uint8_t*)out_data;
    int dst_pitch = (pitch > 0) ? pitch : (int)row_size;

    for (int r = 0; r < h; r++) {
        memcpy(dst + r * dst_pitch, src + r * row_size, row_size);
    }
    vkUnmapMemory(g_device, stagingMemory);

    vkFreeMemory(g_device, stagingMemory, nullptr);
    vkDestroyBuffer(g_device, stagingBuffer, nullptr);
}

void tex_generate_mipmaps(uint32_t tex_id) {
    if (!is_available() || tex_id == 0) return;
    std::lock_guard<std::mutex> lk(g_metal_vk_lock);
    auto it = g_textures.find(tex_id);
    if (it == g_textures.end()) return;
    MetalVkTex& tex = it->second;
    if (tex.mip_levels <= 1) return;

    VkCommandBuffer cmd = begin_single_time_commands();

    // 1. Transition all mip levels to TRANSFER_DST_OPTIMAL
    VkImageMemoryBarrier barrier = { VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER };
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = tex.image;
    barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    barrier.subresourceRange.baseArrayLayer = 0;
    barrier.subresourceRange.layerCount = 1;
    barrier.subresourceRange.baseMipLevel = 0;
    barrier.subresourceRange.levelCount = tex.mip_levels;
    barrier.oldLayout = tex.layout;
    barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.srcAccessMask = VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;

    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    int32_t mipWidth = tex.w;
    int32_t mipHeight = tex.h;

    barrier.subresourceRange.levelCount = 1;

    for (int i = 1; i < tex.mip_levels; ++i) {
        // Transition mip (i - 1) from DST to SRC
        barrier.subresourceRange.baseMipLevel = i - 1;
        barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;

        vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

        int32_t nextWidth = (mipWidth > 1) ? (mipWidth / 2) : 1;
        int32_t nextHeight = (mipHeight > 1) ? (mipHeight / 2) : 1;

        VkImageBlit blit = {};
        blit.srcOffsets[0] = { 0, 0, 0 };
        blit.srcOffsets[1] = { mipWidth, mipHeight, 1 };
        blit.srcSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        blit.srcSubresource.mipLevel = (uint32_t)(i - 1);
        blit.srcSubresource.baseArrayLayer = 0;
        blit.srcSubresource.layerCount = 1;

        blit.dstOffsets[0] = { 0, 0, 0 };
        blit.dstOffsets[1] = { nextWidth, nextHeight, 1 };
        blit.dstSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        blit.dstSubresource.mipLevel = (uint32_t)i;
        blit.dstSubresource.baseArrayLayer = 0;
        blit.dstSubresource.layerCount = 1;

        vkCmdBlitImage(cmd, tex.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                            tex.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                            1, &blit, VK_FILTER_LINEAR);

        // Transition mip (i - 1) to final layout
        VkImageLayout final_layout = tex.is_rt ? VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL : VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        barrier.newLayout = final_layout;
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;

        vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

        mipWidth = nextWidth;
        mipHeight = nextHeight;
    }

    // Transition last mip level to final layout
    VkImageLayout final_layout = tex.is_rt ? VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL : VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    barrier.subresourceRange.baseMipLevel = tex.mip_levels - 1;
    barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.newLayout = final_layout;
    barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;

    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    end_single_time_commands(cmd);
    tex.layout = final_layout;
}

void tex_destroy(uint32_t tex_id) {
    if (!is_available() || tex_id == 0) return;
    std::lock_guard<std::mutex> lk(g_metal_vk_lock);
    auto it = g_textures.find(tex_id);
    if (it == g_textures.end()) return;
    MetalVkTex& t = it->second;

    vkQueueWaitIdle(g_queue);
    if (t.framebuffer_clear) vkDestroyFramebuffer(g_device, t.framebuffer_clear, nullptr);
    if (t.framebuffer_load) vkDestroyFramebuffer(g_device, t.framebuffer_load, nullptr);
    if (t.render_pass_clear) vkDestroyRenderPass(g_device, t.render_pass_clear, nullptr);
    if (t.render_pass_load) vkDestroyRenderPass(g_device, t.render_pass_load, nullptr);
    if (t.view) vkDestroyImageView(g_device, t.view, nullptr);
    if (t.image) vkDestroyImage(g_device, t.image, nullptr);
    if (t.memory) vkFreeMemory(g_device, t.memory, nullptr);

    for (auto it_fb = g_fb_cache.begin(); it_fb != g_fb_cache.end(); ) {
        if (it_fb->first.color_tex_id == tex_id || it_fb->first.depth_tex_id == tex_id) {
            if (it_fb->second.framebuffer) vkDestroyFramebuffer(g_device, it_fb->second.framebuffer, nullptr);
            if (it_fb->second.render_pass) vkDestroyRenderPass(g_device, it_fb->second.render_pass, nullptr);
            it_fb = g_fb_cache.erase(it_fb);
        } else {
            ++it_fb;
        }
    }

    g_textures.erase(it);
}

void pass_begin_ex(int handle, uint32_t rt_tex_id, uint32_t depth_tex_id, int clear, float r, float g, float b, float a, float clear_depth) {
    if (!is_available()) return;
    std::lock_guard<std::mutex> lk(g_metal_vk_lock);
    auto it = g_textures.find(rt_tex_id);
    if (it == g_textures.end()) return;
    MetalVkTex& tex = it->second;

    auto it_depth = g_textures.find(depth_tex_id);
    bool has_depth = (depth_tex_id > 0 && it_depth != g_textures.end());

    if (g_active_cmd != VK_NULL_HANDLE) {
        vkCmdEndRenderPass(g_active_cmd);
        vkEndCommandBuffer(g_active_cmd);
        VkSubmitInfo si = { VK_STRUCTURE_TYPE_SUBMIT_INFO };
        si.commandBufferCount = 1;
        si.pCommandBuffers = &g_active_cmd;
        vkQueueSubmit(g_queue, 1, &si, VK_NULL_HANDLE);
        vkQueueWaitIdle(g_queue);
        for (auto& pb : g_pending_buffers) {
            vkFreeMemory(g_device, pb.memory, nullptr);
            vkDestroyBuffer(g_device, pb.buffer, nullptr);
        }
        g_pending_buffers.clear();
        vkFreeCommandBuffers(g_device, g_cmd_pool, 1, &g_active_cmd);
        g_active_cmd = VK_NULL_HANDLE;
    }

    VkCommandBufferAllocateInfo allocInfo = { VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO };
    allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    allocInfo.commandPool = g_cmd_pool;
    allocInfo.commandBufferCount = 1;
    vkAllocateCommandBuffers(g_device, &allocInfo, &g_active_cmd);

    VkCommandBufferBeginInfo beginInfo = { VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
    vkBeginCommandBuffer(g_active_cmd, &beginInfo);

    if (tex.layout != VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL) {
        transition_image_layout(g_active_cmd, tex.image, tex.vk_fmt, tex.layout, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);
        tex.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    }

    if (has_depth) {
        MetalVkTex& dtex = it_depth->second;
        if (dtex.layout != VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL) {
            transition_image_layout(g_active_cmd, dtex.image, dtex.vk_fmt, dtex.layout, VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL);
            dtex.layout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
        }
    }

    VkRenderPass rp = VK_NULL_HANDLE;
    VkFramebuffer fb = VK_NULL_HANDLE;

    if (!has_depth) {
        rp = clear ? tex.render_pass_clear : tex.render_pass_load;
        fb = clear ? tex.framebuffer_clear : tex.framebuffer_load;
    } else {
        FramebufferCacheKey fbKey = { rt_tex_id, depth_tex_id, clear };
        auto it_fb = g_fb_cache.find(fbKey);
        if (it_fb != g_fb_cache.end()) {
            rp = it_fb->second.render_pass;
            fb = it_fb->second.framebuffer;
        } else {
            MetalVkTex& dtex = it_depth->second;
            rp = create_render_pass(tex.vk_fmt, dtex.vk_fmt, clear != 0, clear != 0);
            VkImageView views[2] = { tex.view, dtex.view };
            VkFramebufferCreateInfo fbInfo = { VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO };
            fbInfo.renderPass = rp;
            fbInfo.attachmentCount = 2;
            fbInfo.pAttachments = views;
            fbInfo.width = tex.w;
            fbInfo.height = tex.h;
            fbInfo.layers = 1;
            vkCreateFramebuffer(g_device, &fbInfo, nullptr, &fb);
            g_fb_cache[fbKey] = { rp, fb };
        }
    }

    VkClearValue clearValues[2] = {};
    clearValues[0].color.float32[0] = r;
    clearValues[0].color.float32[1] = g;
    clearValues[0].color.float32[2] = b;
    clearValues[0].color.float32[3] = a;
    clearValues[1].depthStencil.depth = clear_depth;
    clearValues[1].depthStencil.stencil = 0;

    VkRenderPassBeginInfo rpBegin = { VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO };
    rpBegin.renderPass = rp;
    rpBegin.framebuffer = fb;
    rpBegin.renderArea.offset = { 0, 0 };
    rpBegin.renderArea.extent = { (uint32_t)tex.w, (uint32_t)tex.h };
    rpBegin.clearValueCount = has_depth ? 2 : 1;
    rpBegin.pClearValues = clearValues;

    vkCmdBeginRenderPass(g_active_cmd, &rpBegin, VK_SUBPASS_CONTENTS_INLINE);
    g_active_rt_id = rt_tex_id;
    g_active_render_pass = rp;
}

void pass_begin(int handle, uint32_t rt_tex_id, int clear, float r, float g, float b, float a) {
    pass_begin_ex(handle, rt_tex_id, 0, clear, r, g, b, a, 1.0f);
}

void pass_end(int handle, uint32_t rt_tex_id) {
    if (!is_available() || g_active_cmd == VK_NULL_HANDLE) return;
    std::lock_guard<std::mutex> lk(g_metal_vk_lock);

    vkCmdEndRenderPass(g_active_cmd);
    vkEndCommandBuffer(g_active_cmd);

    VkSubmitInfo submitInfo = { VK_STRUCTURE_TYPE_SUBMIT_INFO };
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &g_active_cmd;

    vkQueueSubmit(g_queue, 1, &submitInfo, VK_NULL_HANDLE);
    vkQueueWaitIdle(g_queue);

    for (auto& pb : g_pending_buffers) {
        vkFreeMemory(g_device, pb.memory, nullptr);
        vkDestroyBuffer(g_device, pb.buffer, nullptr);
    }
    g_pending_buffers.clear();

    vkFreeCommandBuffers(g_device, g_cmd_pool, 1, &g_active_cmd);
    g_active_cmd = VK_NULL_HANDLE;
    g_active_rt_id = 0;
    g_active_render_pass = VK_NULL_HANDLE;
}

void draw(int handle,
          const xef_host_metal_pipeline_t* pipe,
          int prim_type,
          const xef_host_metal_vertex_t* vertices,
          int vertex_count,
          const uint32_t* indices,
          int index_count) {
    if (!is_available() || !pipe || !vertices || vertex_count <= 0) return;
    std::lock_guard<std::mutex> lk(g_metal_vk_lock);

    auto it_rt = g_textures.find(pipe->rt_tex_id);
    if (it_rt == g_textures.end()) return;
    MetalVkTex& rt = it_rt->second;

    if (g_active_cmd == VK_NULL_HANDLE || g_active_rt_id != pipe->rt_tex_id) {
        pass_begin_ex(handle, pipe->rt_tex_id, pipe->depth_tex_id, 0, 0, 0, 0, 0, 1.0f);
    }
    if (g_active_cmd == VK_NULL_HANDLE) return;

    auto it_depth = g_textures.find(pipe->depth_tex_id);
    bool has_depth = (pipe->depth_tex_id > 0 && it_depth != g_textures.end());

    PipelineKey key;
    key.blend_enable = pipe->blend_enable;
    key.src_rgb = pipe->src_rgb;
    key.dst_rgb = pipe->dst_rgb;
    key.rgb_op  = pipe->rgb_op;
    key.src_a   = pipe->src_a;
    key.dst_a   = pipe->dst_a;
    key.a_op    = pipe->a_op;
    key.write_mask = pipe->write_mask;
    key.prim_type = prim_type;
    key.rt_format = rt.vk_fmt;
    key.depth_format = has_depth ? it_depth->second.vk_fmt : VK_FORMAT_UNDEFINED;
    key.depth_test_enable = pipe->depth_test_enable;
    key.depth_write_enable = pipe->depth_write_enable;
    key.depth_compare_op = pipe->depth_compare_op;
    key.stencil_test_enable = pipe->stencil_test_enable;
    key.stencil_compare_op = pipe->stencil_compare_op;
    key.stencil_fail_op = pipe->stencil_fail_op;
    key.stencil_depth_fail_op = pipe->stencil_depth_fail_op;
    key.stencil_pass_op = pipe->stencil_pass_op;
    key.stencil_read_mask = pipe->stencil_read_mask;
    key.stencil_write_mask = pipe->stencil_write_mask;
    key.cull_mode = pipe->cull_mode;
    key.front_face = pipe->front_facing_winding;

    VkRenderPass pass_for_pipeline = (g_active_render_pass != VK_NULL_HANDLE) ? g_active_render_pass : rt.render_pass_load;
    VkPipeline pipeline = get_or_create_pipeline(key, pass_for_pipeline);
    if (pipeline == VK_NULL_HANDLE) return;

    vkCmdBindPipeline(g_active_cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);

    // Push constants
    PushConstants pc;
    pc.u_target_size[0] = (float)rt.w;
    pc.u_target_size[1] = (float)rt.h;
    pc.u_frag_mode      = pipe->frag_mode;
    pc.u_color_scale    = pipe->color_scale > 0.0f ? pipe->color_scale : 1.0f;
    pc.u_uv_left_top[0] = pipe->uv_left_top[0];
    pc.u_uv_left_top[1] = pipe->uv_left_top[1];
    pc.u_uv_dims[0]     = pipe->uv_dims[0] > 0.0f ? pipe->uv_dims[0] : 1.0f;
    pc.u_uv_dims[1]     = pipe->uv_dims[1] > 0.0f ? pipe->uv_dims[1] : 1.0f;
    pc.u_flip_y         = 0;

    vkCmdPushConstants(g_active_cmd, g_pipeline_layout,
                       VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT,
                       0, sizeof(PushConstants), &pc);

    // Viewport & Scissor
    int vx = pipe->viewport[0];
    int vy = pipe->viewport[1];
    int vw = pipe->viewport[2] > 0 ? pipe->viewport[2] : rt.w;
    int vh = pipe->viewport[3] > 0 ? pipe->viewport[3] : rt.h;

    VkViewport vp = {};
    vp.x = (float)vx;
    vp.y = (float)vy;
    vp.width = (float)vw;
    vp.height = (float)vh;
    vp.minDepth = 0.0f;
    vp.maxDepth = 1.0f;
    vkCmdSetViewport(g_active_cmd, 0, 1, &vp);

    VkRect2D sc = {};
    if (pipe->clip_rect[2] > 0 && pipe->clip_rect[3] > 0) {
        sc.offset.x = std::max(0, pipe->clip_rect[0]);
        sc.offset.y = std::max(0, pipe->clip_rect[1]);
        sc.extent.width = (uint32_t)pipe->clip_rect[2];
        sc.extent.height = (uint32_t)pipe->clip_rect[3];
    } else {
        sc.offset.x = 0;
        sc.offset.y = 0;
        sc.extent.width = (uint32_t)rt.w;
        sc.extent.height = (uint32_t)rt.h;
    }
    vkCmdSetScissor(g_active_cmd, 0, 1, &sc);

    // Dynamic vertex buffer
    size_t vb_size = vertex_count * sizeof(xef_host_metal_vertex_t);
    VkBuffer vertexBuffer = VK_NULL_HANDLE;
    VkDeviceMemory vertexMemory = VK_NULL_HANDLE;

    VkBufferCreateInfo vbInfo = { VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO };
    vbInfo.size = vb_size;
    vbInfo.usage = VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
    vbInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    vkCreateBuffer(g_device, &vbInfo, nullptr, &vertexBuffer);

    VkMemoryRequirements vbMemReq;
    vkGetBufferMemoryRequirements(g_device, vertexBuffer, &vbMemReq);

    VkMemoryAllocateInfo vbMai = { VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO };
    vbMai.allocationSize = vbMemReq.size;
    vbMai.memoryTypeIndex = find_memory_type(vbMemReq.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    vkAllocateMemory(g_device, &vbMai, nullptr, &vertexMemory);
    vkBindBufferMemory(g_device, vertexBuffer, vertexMemory, 0);

    void* vb_map = nullptr;
    vkMapMemory(g_device, vertexMemory, 0, vb_size, 0, &vb_map);
    memcpy(vb_map, vertices, vb_size);
    vkUnmapMemory(g_device, vertexMemory);

    VkDeviceSize offsets[] = { 0 };
    vkCmdBindVertexBuffers(g_active_cmd, 0, 1, &vertexBuffer, offsets);

    // Texture binding
    uint32_t sample_tex_id = (pipe->tex_id != 0) ? pipe->tex_id : g_white_tex_id;
    auto it_sample = g_textures.find(sample_tex_id);
    if (it_sample != g_textures.end()) {
        VkDescriptorSet dset = pipe->filter_linear ? it_sample->second.desc_set_linear : it_sample->second.desc_set_nearest;
        vkCmdBindDescriptorSets(g_active_cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, g_pipeline_layout, 0, 1, &dset, 0, nullptr);
    }

    if (indices && index_count > 0) {
        size_t ib_size = index_count * sizeof(uint32_t);
        VkBuffer indexBuffer = VK_NULL_HANDLE;
        VkDeviceMemory indexMemory = VK_NULL_HANDLE;

        VkBufferCreateInfo ibInfo = { VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO };
        ibInfo.size = ib_size;
        ibInfo.usage = VK_BUFFER_USAGE_INDEX_BUFFER_BIT;
        ibInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
        vkCreateBuffer(g_device, &ibInfo, nullptr, &indexBuffer);

        VkMemoryRequirements ibMemReq;
        vkGetBufferMemoryRequirements(g_device, indexBuffer, &ibMemReq);

        VkMemoryAllocateInfo ibMai = { VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO };
        ibMai.allocationSize = ibMemReq.size;
        ibMai.memoryTypeIndex = find_memory_type(ibMemReq.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
        vkAllocateMemory(g_device, &ibMai, nullptr, &indexMemory);
        vkBindBufferMemory(g_device, indexBuffer, indexMemory, 0);

        void* ib_map = nullptr;
        vkMapMemory(g_device, indexMemory, 0, ib_size, 0, &ib_map);
        memcpy(ib_map, indices, ib_size);
        vkUnmapMemory(g_device, indexMemory);

        vkCmdBindIndexBuffer(g_active_cmd, indexBuffer, 0, VK_INDEX_TYPE_UINT32);
        vkCmdDrawIndexed(g_active_cmd, (uint32_t)index_count, 1, 0, 0, 0);

        g_pending_buffers.push_back({ indexBuffer, indexMemory });
    } else {
        vkCmdDraw(g_active_cmd, (uint32_t)vertex_count, 1, 0, 0);
    }

    g_pending_buffers.push_back({ vertexBuffer, vertexMemory });
}

void present(int handle, uint32_t tex_id) {
    if (!is_available() || tex_id == 0) return;
    auto it = g_textures.find(tex_id);
    if (it == g_textures.end()) return;
    MetalVkTex& tex = it->second;

    std::vector<uint32_t> pixels(tex.w * tex.h);
    tex_readback(tex_id, 0, 0, tex.w, tex.h, pixels.data(), tex.w * 4);

    int host_fmt = (tex.fmt == 80 || tex.fmt == 81) ? 80 : 70;
    xef_host_present_pixels(handle, pixels.data(), tex.w, tex.h, host_fmt);
}

} // namespace xef::metal_vk
