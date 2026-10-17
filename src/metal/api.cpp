// Guest-facing entry points (xef_mtl_*), resolved by the Mach-O loader through HLE stubs.
#include "mtl_engine.h"
#include "common/common.h"
#include "loader/darwin_hle.h"
#include <cstring>

using namespace xef::mtl;

namespace {

void copy_err(const std::string& e, char* out, uint32_t len) {
    if (!out || !len) return;
    size_t n = std::min<size_t>(e.size(), len - 1);
    memcpy(out, e.data(), n);
    out[n] = 0;
}

Library* library(uint32_t id) { return id < g.libraries.size() ? g.libraries[id].get() : nullptr; }

} // namespace

extern "C" {

int xef_mtl_init(xef_mtl_device_info* out) {
    if (!engine_init()) return 0;
    if (out) {
        memset(out, 0, sizeof(*out));
        snprintf(out->name, sizeof(out->name), "%s", g.device_name.c_str());
        uint64_t heap = 0;
        for (uint32_t i = 0; i < g.memprops.memoryHeapCount; i++)
            if (g.memprops.memoryHeaps[i].flags & VK_MEMORY_HEAP_DEVICE_LOCAL_BIT) heap = std::max<uint64_t>(heap, g.memprops.memoryHeaps[i].size);
        out->recommended_max_working_set = heap ? heap : (4ull << 30);
        out->max_buffer_length = std::min<uint64_t>(heap ? heap / 2 : (1ull << 30), 1ull << 32);
        out->max_threads_per_threadgroup = g.max_tg_threads;
        out->max_texture_2d = g.props.limits.maxImageDimension2D;
        out->has_unified_memory = g.props.deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU;
        out->simd_width = 32;
        out->vendor_id = g.props.vendorID;
    }
    return 1;
}

uint32_t xef_mtl_buffer_create(uint64_t length, uint32_t options, void** out_contents, uint64_t* out_gpu) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    if (!engine_init()) return 0;
    return buffer_create(length, options, out_contents, out_gpu);
}

uint32_t xef_mtl_buffer_create_nocopy(void* pointer, uint64_t length, uint32_t options, uint64_t* out_gpu) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    if (!engine_init()) return 0;
    return buffer_create_nocopy(pointer, length, options, out_gpu);
}

void xef_mtl_buffer_destroy(uint32_t id) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    buffer_destroy(id);
}

uint32_t xef_mtl_texture_create(const xef_mtl_texture_desc* d, uint64_t* rid) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    if (!engine_init() || !d) return 0;
    return texture_create(d, rid);
}

uint32_t xef_mtl_texture_view(uint32_t parent, const xef_mtl_view_desc* d, uint64_t* rid) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    if (!d) return 0;
    return texture_view(parent, d, rid);
}

void xef_mtl_texture_replace(uint32_t t, uint32_t level, uint32_t slice, const uint32_t* region6, const void* bytes, uint64_t bpr, uint64_t bpi) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    texture_replace(t, level, slice, region6, bytes, bpr, bpi);
}

void xef_mtl_texture_get_bytes(uint32_t t, uint32_t level, uint32_t slice, const uint32_t* region6, void* bytes, uint64_t bpr, uint64_t bpi) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    texture_get_bytes(t, level, slice, region6, bytes, bpr, bpi);
}

void xef_mtl_texture_destroy(uint32_t t) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    texture_destroy(t);
}

uint32_t xef_mtl_sampler_create(const xef_mtl_sampler_desc* d, uint64_t* rid) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    if (!engine_init() || !d) return 0;
    return sampler_create(d, rid);
}

void xef_mtl_sampler_destroy(uint32_t s) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    sampler_destroy(s);
}

uint32_t xef_mtl_library_create(const void* data, uint64_t size, char* err, uint32_t err_len) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    auto lib = std::make_unique<Library>();
    lib->data.assign((const uint8_t*)data, (const uint8_t*)data + size);
    if (const char* dir = getenv("XEF_MTL_DUMP_LIBS")) {   // debugging: keep a copy of every library
        static int n = 0;
        char path[1024];
        snprintf(path, sizeof path, "%s/lib%03d.metallib", dir, n++);
        if (FILE* f = fopen(path, "wb")) { fwrite(data, 1, size, f); fclose(f); }
    }
    std::string e;
    if (!xef::metallib::parse(lib->data.data(), lib->data.size(), lib->fns, &e)) {
        copy_err(e, err, err_len);
        return 0;
    }
    g.libraries.push_back(std::move(lib));
    return (uint32_t)g.libraries.size() - 1;
}

// options: NUL-terminated list of "NAME" / "NAME=VALUE" preprocessor macros separated by newlines, or NULL
uint32_t xef_mtl_library_create_source(const char* source, const void* options, char* err, uint32_t err_len) {
    xef::mtlabi::SourceRequest req;
    req.source = source ? source : "";
    if (const char* o = (const char*)options) {
        while (*o) {
            const char* e = strchr(o, '\n');
            size_t n = e ? (size_t)(e - o) : strlen(o);
            if (n) req.defines.emplace_back(o, n);
            o += n + (e ? 1 : 0);
        }
    }
    if (const char* dir = getenv("XEF_MTL_DUMP_LIBS")) {
        static int n = 0;
        char path[1024];
        snprintf(path, sizeof path, "%s/src%03d.metal", dir, n++);
        if (FILE* f = fopen(path, "wb")) { fputs(req.source.c_str(), f); fclose(f); }
    }
    xef::mtlabi::SourceResult res;
    if (!compile_source(req, res)) {
        copy_err(res.log.empty() ? std::string("MSL compilation failed") : res.log, err, err_len);
        return 0;
    }
    uint32_t id = xef_mtl_library_create(res.metallib.data(), res.metallib.size(), err, err_len);
    if (id) {
        std::lock_guard<std::recursive_mutex> lk(g.mtx);
        if (Library* l = library(id)) l->source = req.source;
    }
    return id;
}

uint32_t xef_mtl_library_function_count(uint32_t id) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    Library* l = library(id);
    return l ? (uint32_t)l->fns.size() : 0;
}

uint32_t xef_mtl_library_function_info(uint32_t id, uint32_t index, char* name, uint32_t name_len) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    Library* l = library(id);
    if (!l || index >= l->fns.size()) return 0;
    const xef::metallib::Function& f = l->fns[index];
    copy_err(f.name, name, name_len);
    // MTLFunctionType: vertex 1, fragment 2, kernel 3, visible 5, intersection 6, mesh 7, object 8
    switch (f.type) {
    case xef::metallib::FN_VERTEX: return 1 + 1;
    case xef::metallib::FN_FRAGMENT: return 2 + 1;
    case xef::metallib::FN_KERNEL: return 3 + 1;
    case xef::metallib::FN_VISIBLE: return 5 + 1;
    case xef::metallib::FN_INTERSECTION: return 6 + 1;
    case xef::metallib::FN_MESH: return 7 + 1;
    case xef::metallib::FN_OBJECT: return 8 + 1;
    default: return 5 + 1;
    }
}

void xef_mtl_library_destroy(uint32_t id) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    if (id < g.libraries.size()) g.libraries[id].reset();
}

uint32_t xef_mtl_render_pipeline_create(const xef_mtl_render_pipeline_desc* d, char* err, uint32_t err_len) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    if (!engine_init() || !d) return 0;
    std::string e;
    uint32_t id = create_render_pipeline(d, e);
    if (!id) copy_err(e, err, err_len);
    return id;
}

uint32_t xef_mtl_compute_pipeline_create(const xef_mtl_compute_pipeline_desc* d, xef_mtl_pipeline_info* info, char* err, uint32_t err_len) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    if (!engine_init() || !d) return 0;
    std::string e;
    uint32_t id = create_compute_pipeline(d, info, e);
    if (!id) copy_err(e, err, err_len);
    return id;
}

void xef_mtl_pipeline_destroy(uint32_t id) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    (void)id;   // pipelines may still be referenced by in-flight command buffers; kept alive
}

uint32_t xef_mtl_queue_create(void) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    if (!engine_init()) return 0;
    return queue_create();
}

uint64_t xef_mtl_commit(uint32_t queue, const void* stream, uint64_t length) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    return commit(queue, (const uint8_t*)stream, length);
}

uint64_t xef_mtl_completed(uint32_t queue) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    if (queue >= g.queues.size() || !g.queues[queue]) return 0;
    retire(g.queues[queue].get());
    return g.queues[queue]->completed;
}

uint64_t xef_mtl_wait(uint32_t queue, uint64_t submission, int64_t timeout_ns) {
    return wait_queue(queue, submission, timeout_ns);
}

uint32_t xef_mtl_layer_create(int host_window) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    if (!engine_init()) return 0;
    return layer_create(host_window);
}

void xef_mtl_layer_configure(uint32_t layer, uint32_t width, uint32_t height, uint32_t pixel_format, uint32_t flags) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    layer_configure(layer, width, height, pixel_format, flags);
}

uint32_t xef_mtl_layer_next_drawable(uint32_t layer, uint32_t* out_texture, uint64_t* out_rid) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    return layer_next_drawable(layer, out_texture, out_rid);
}

void xef_mtl_layer_release_drawable(uint32_t layer, uint32_t drawable) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    release_drawable((layer << 16) | drawable);
}

void xef_mtl_layer_destroy(uint32_t layer) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    (void)layer;
}

uint32_t xef_mtl_event_create(void) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    if (!engine_init()) return 0;
    auto e = std::make_unique<Event>();
    VkSemaphoreTypeCreateInfo tci{VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO};
    tci.semaphoreType = VK_SEMAPHORE_TYPE_TIMELINE;
    VkSemaphoreCreateInfo sci{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
    sci.pNext = &tci;
    vk.CreateSemaphore(g.dev, &sci, nullptr, &e->timeline);
    g.events.push_back(std::move(e));
    return (uint32_t)g.events.size() - 1;
}

uint64_t xef_mtl_event_value(uint32_t id) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    if (id >= g.events.size() || !g.events[id]) return 0;
    uint64_t v = 0;
    vk.GetSemaphoreCounterValue(g.dev, g.events[id]->timeline, &v);
    return v;
}

void xef_mtl_event_signal(uint32_t id, uint64_t value) {
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    if (id >= g.events.size() || !g.events[id]) return;
    uint64_t cur = 0;
    vk.GetSemaphoreCounterValue(g.dev, g.events[id]->timeline, &cur);
    if (value <= cur) return;   // timeline values only grow
    VkSemaphoreSignalInfo si{VK_STRUCTURE_TYPE_SEMAPHORE_SIGNAL_INFO};
    si.semaphore = g.events[id]->timeline;
    si.value = value;
    vk.SignalSemaphore(g.dev, &si);
}

int xef_mtl_event_wait(uint32_t id, uint64_t value, int64_t timeout_ns) {
    VkSemaphore s;
    {
        std::lock_guard<std::recursive_mutex> lk(g.mtx);
        if (id >= g.events.size() || !g.events[id]) return 0;
        s = g.events[id]->timeline;
    }
    VkSemaphoreWaitInfo wi{VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO};
    wi.semaphoreCount = 1;
    wi.pSemaphores = &s;
    wi.pValues = &value;
    return vk.WaitSemaphores(g.dev, &wi, timeout_ns < 0 ? UINT64_MAX : (uint64_t)timeout_ns) == VK_SUCCESS;
}

void xef_mtl_event_destroy(uint32_t id) { (void)id; }

} // extern "C"

namespace xef {

uint64_t darwin_metal_resolve(const char* name) {
    struct Fn { const char* n; void* f; };
    static const Fn fns[] = {
#define F(x) {"_" #x, (void*)&x}
        F(xef_mtl_init), F(xef_mtl_buffer_create), F(xef_mtl_buffer_create_nocopy), F(xef_mtl_buffer_destroy),
        F(xef_mtl_texture_create), F(xef_mtl_texture_view), F(xef_mtl_texture_replace), F(xef_mtl_texture_get_bytes),
        F(xef_mtl_texture_destroy), F(xef_mtl_sampler_create), F(xef_mtl_sampler_destroy), F(xef_mtl_library_create),
        F(xef_mtl_library_create_source), F(xef_mtl_library_function_count), F(xef_mtl_library_function_info),
        F(xef_mtl_library_destroy), F(xef_mtl_render_pipeline_create), F(xef_mtl_compute_pipeline_create),
        F(xef_mtl_pipeline_destroy), F(xef_mtl_queue_create), F(xef_mtl_commit), F(xef_mtl_completed), F(xef_mtl_wait),
        F(xef_mtl_layer_create), F(xef_mtl_layer_configure), F(xef_mtl_layer_next_drawable), F(xef_mtl_layer_release_drawable),
        F(xef_mtl_layer_destroy), F(xef_mtl_event_create), F(xef_mtl_event_value), F(xef_mtl_event_signal),
        F(xef_mtl_event_wait), F(xef_mtl_event_destroy),
#undef F
    };
    for (const Fn& f : fns)
        if (!strcmp(name, f.n)) return darwin_hle_register_function(name, f.f);
    return 0;
}

} // namespace xef
