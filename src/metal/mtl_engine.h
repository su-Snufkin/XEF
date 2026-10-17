// Metal -> Vulkan engine (host side). One Vulkan device, bindless descriptor set 0, buffer device addresses.
#pragma once
#include "metallib.h"
#include "mtl_formats.h"
#include "mtl_shader_proto.h"
#include "vk_loader.h"
#include "../../rootfs-src/appkit/xef_mtl.h"
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace xef::mtl {

struct Buffer {
    VkBuffer buf = VK_NULL_HANDLE;
    VkDeviceMemory mem = VK_NULL_HANDLE;
    void* map = nullptr;
    uint64_t size = 0;
    uint64_t addr = 0;
    uint32_t options = 0;
    bool imported = false;
    void* raw = nullptr;        // mmap'ed host memory (imported allocations)
    size_t raw_size = 0;
};

struct Texture {
    VkImage img = VK_NULL_HANDLE;
    VkDeviceMemory mem = VK_NULL_HANDLE;
    const PixelFormatInfo* fmt = nullptr;
    VkFormat vkfmt = VK_FORMAT_UNDEFINED;
    uint32_t mtl_format = 0;
    uint32_t type = 2;          // MTLTextureType
    uint32_t width = 1, height = 1, depth = 1;
    uint32_t mips = 1;
    uint32_t layers = 1;        // Vulkan array layers (cube faces included)
    uint32_t samples = 1;
    uint32_t usage = 0;
    uint32_t base_level = 0, base_layer = 0;   // views
    uint32_t parent = 0;        // view parent (owns img/mem)
    uint32_t resource_id = 0;   // index in the bindless image arrays
    VkImageView sampled_view = VK_NULL_HANDLE, storage_view = VK_NULL_HANDLE, array_view = VK_NULL_HANDLE;
    VkBufferView texel_view = VK_NULL_HANDLE, storage_texel_view = VK_NULL_HANDLE;
    uint32_t buffer = 0;        // texture buffers
    std::map<uint64_t, VkImageView> attach_views;
    uint8_t swizzle[4] = {2, 3, 4, 5};
    bool drawable = false;
};

struct Sampler {
    VkSampler s = VK_NULL_HANDLE;
    uint32_t resource_id = 0;
};

struct Library {
    std::vector<uint8_t> data;
    std::vector<metallib::Function> fns;
};

struct StageModule {
    VkShaderModule mod = VK_NULL_HANDLE;
    mtlabi::StageResult refl;
    uint32_t const_buffer = 0;          // pipeline constant data (BIND_CONST_DATA)
    std::vector<uint32_t> const_samplers;   // engine sampler ids for BIND_CONST_SAMPLER
};

struct RenderPipeline {
    xef_mtl_render_pipeline_desc desc{};
    StageModule vs, fs;
    bool has_fs = false;
    VkPipeline pipes[4] = {};           // per primitive class: 0 point, 1 line, 2 triangle (created lazily)
    std::vector<uint32_t> vertex_bindings;   // Metal buffer indices bound as vertex buffers
    bool needs_dummy_binding = false;
    uint32_t color_formats[XEF_MTL_MAX_COLOR] = {};
    VkFormat vk_colors[XEF_MTL_MAX_COLOR] = {};
    VkFormat vk_depth = VK_FORMAT_UNDEFINED, vk_stencil = VK_FORMAT_UNDEFINED;
};

struct ComputeVariant {
    VkPipeline pipe = VK_NULL_HANDLE;
    StageModule cs;
};

struct ComputePipeline {
    mtlabi::CompileRequest req;          // template (stage + constants)
    std::map<std::vector<uint32_t>, std::unique_ptr<ComputeVariant>> variants;   // key: tg size + tg memory
    uint32_t max_threads = 1024;
};

struct Pipeline {
    std::unique_ptr<RenderPipeline> render;
    std::unique_ptr<ComputePipeline> compute;
};

// GPU-visible linear allocator for argument tables and setBytes data
struct RingChunk {
    VkBuffer buf = VK_NULL_HANDLE;
    VkDeviceMemory mem = VK_NULL_HANDLE;
    uint8_t* map = nullptr;
    uint64_t addr = 0;
    uint64_t size = 0, used = 0;
    uint64_t last_use = 0;              // submission number that last used the chunk
};

struct Submission {
    uint64_t seq = 0;
    VkCommandBuffer cb = VK_NULL_HANDLE;
    std::vector<uint32_t> release_drawables;   // (layer << 16 | index)
};

struct Queue {
    VkCommandPool pool = VK_NULL_HANDLE;
    VkSemaphore timeline = VK_NULL_HANDLE;
    uint64_t next_seq = 1;
    uint64_t completed = 0;
    std::deque<Submission> inflight;
    std::vector<VkCommandBuffer> free_cbs;
    std::vector<std::unique_ptr<RingChunk>> chunks;
    RingChunk* cur = nullptr;
};

struct Layer;

struct Event {
    VkSemaphore timeline = VK_NULL_HANDLE;
};

struct Engine {
    bool ok = false;
    std::string device_name;
    VkInstance instance = VK_NULL_HANDLE;
    VkPhysicalDevice pd = VK_NULL_HANDLE;
    VkDevice dev = VK_NULL_HANDLE;
    uint32_t qfamily = 0;
    VkQueue queue = VK_NULL_HANDLE;
    VkPhysicalDeviceProperties props{};
    VkPhysicalDeviceMemoryProperties memprops{};
    VkDescriptorSetLayout set_layout = VK_NULL_HANDLE;
    VkDescriptorPool desc_pool = VK_NULL_HANDLE;
    VkDescriptorSet set = VK_NULL_HANDLE;
    VkPipelineLayout pipe_layout = VK_NULL_HANDLE;
    VkPipelineCache pipe_cache = VK_NULL_HANDLE;
    bool has_host_import = false;
    uint64_t host_import_align = 4096;
    bool has_eds3_polygon = false, has_eds3_clamp = false;
    bool has_fill_mode_non_solid = false;
    bool has_xlib_surface = false;
    uint32_t subgroup_size = 32;
    bool has_subgroup_size_control = false;
    uint32_t max_tg_threads = 1024;

    // object tables (id 0 = none)
    std::vector<std::unique_ptr<Buffer>> buffers{1};
    std::vector<std::unique_ptr<Texture>> textures{1};
    std::vector<std::unique_ptr<Sampler>> samplers{1};
    std::vector<std::unique_ptr<Library>> libraries{1};
    std::vector<std::unique_ptr<Pipeline>> pipelines{1};
    std::vector<std::unique_ptr<Queue>> queues{1};
    std::vector<std::unique_ptr<Layer>> layers{1};
    std::vector<std::unique_ptr<Event>> events{1};
    std::vector<uint32_t> free_tex_ids, free_sampler_ids;
    uint32_t next_tex_id = 1, next_sampler_id = 1;
    uint32_t dummy_buffer = 0;          // zero-filled vertex data for attributes missing from the vertex descriptor
    uint32_t null_texture = 0;
    std::map<std::vector<uint8_t>, uint32_t> const_sampler_cache;

    std::recursive_mutex mtx;
    std::condition_variable_any cv;
};

extern Engine g;

// engine.cpp
bool engine_init();
uint32_t find_memory_type(uint32_t bits, VkMemoryPropertyFlags want, VkMemoryPropertyFlags avoid = 0);
VkDeviceMemory alloc_memory(VkMemoryRequirements req, VkMemoryPropertyFlags want, bool device_address, VkMemoryPropertyFlags avoid = 0);
Buffer* buffer(uint32_t id);
Texture* texture(uint32_t id);
Texture* texture_root(Texture* t);
Sampler* sampler(uint32_t id);
uint32_t create_buffer_internal(uint64_t size, bool host_visible, void** map);
uint32_t buffer_create(uint64_t length, uint32_t options, void** contents, uint64_t* gpu);
uint32_t buffer_create_nocopy(void* ptr, uint64_t length, uint32_t options, uint64_t* gpu);
void buffer_destroy(uint32_t id);
uint32_t texture_create(const xef_mtl_texture_desc* d, uint64_t* rid);
uint32_t texture_view(uint32_t parent_id, const xef_mtl_view_desc* d, uint64_t* rid);
void texture_destroy(uint32_t id);
void texture_replace(uint32_t id, uint32_t level, uint32_t slice, const uint32_t* reg, const void* bytes, uint64_t bpr, uint64_t bpi);
void texture_get_bytes(uint32_t id, uint32_t level, uint32_t slice, const uint32_t* reg, void* bytes, uint64_t bpr, uint64_t bpi);
uint32_t sampler_create(const xef_mtl_sampler_desc* d, uint64_t* rid);
void sampler_destroy(uint32_t id);
VkImageView attachment_view(Texture* t, uint32_t level, uint32_t slice, uint32_t layers, VkImageAspectFlags aspect);
uint32_t const_sampler_id(const mtlabi::ConstSampler& cs);
void one_shot(const std::function<void(VkCommandBuffer)>& rec);
void image_barrier_all(VkCommandBuffer cb);

// shaders.cpp
bool compile_shaders(const mtlabi::CompileRequest& req, mtlabi::CompileResult& res);
bool make_stage(const mtlabi::StageResult& r, StageModule& out, std::string& err);

// pipelines.cpp
uint32_t create_render_pipeline(const xef_mtl_render_pipeline_desc* d, std::string& err);
uint32_t create_compute_pipeline(const xef_mtl_compute_pipeline_desc* d, xef_mtl_pipeline_info* info, std::string& err);
VkPipeline render_pipeline_for(RenderPipeline* p, uint32_t prim_class);
ComputeVariant* compute_variant(ComputePipeline* p, const uint32_t tg[3], const std::vector<uint32_t>& tg_mem, std::string& err);
bool function_source(const xef_mtl_function_ref& ref, uint32_t stage, mtlabi::CompileRequest& req, std::string& err);

// commands.cpp
uint32_t queue_create();
uint64_t commit(uint32_t queue, const uint8_t* stream, uint64_t len);
void retire(Queue* q);
uint64_t wait_queue(uint32_t queue, uint64_t seq, int64_t timeout_ns);
RingChunk* ring_alloc(Queue* q, uint64_t size, uint64_t align, uint64_t& offset);

// present.cpp
struct Layer {
    int window = 0;
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    VkSwapchainKHR swapchain = VK_NULL_HANDLE;
    std::vector<VkImage> sc_images;
    VkFormat sc_format = VK_FORMAT_UNDEFINED;
    VkExtent2D sc_extent{};
    uint32_t width = 0, height = 0, pixel_format = 80, flags = 0;
    std::vector<uint32_t> drawables;    // texture ids
    std::vector<bool> busy;
    std::vector<VkSemaphore> acquire_sems, present_sems;
    uint32_t frame = 0;
    bool dirty = true;
};
uint32_t layer_create(int window);
void layer_configure(uint32_t id, uint32_t w, uint32_t h, uint32_t fmt, uint32_t flags);
uint32_t layer_next_drawable(uint32_t id, uint32_t* tex, uint64_t* rid);
struct PendingPresent {
    Layer* layer;
    uint32_t layer_id;
    uint32_t drawable;
    uint32_t image;
    VkSemaphore acquire, present;
};
void present_record(VkCommandBuffer cb, uint32_t layer, uint32_t drawable, std::vector<PendingPresent>& to_present);
void present_after_submit(std::vector<PendingPresent>& to_present);
void release_drawable(uint32_t key);

} // namespace xef::mtl
