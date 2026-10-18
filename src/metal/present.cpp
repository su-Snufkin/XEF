// CAMetalLayer drawables and presentation through a Vulkan swapchain on the AppKit-lite X11 window.
#include "mtl_engine.h"
#include "common/common.h"
#include <cstring>
#include <unistd.h>

namespace xef {
void* darwin_gl_host_x(const char* n);
bool darwin_gl_host_libs();
}
extern "C" unsigned long xef_host_window_xid(int h);

namespace xef::mtl {

using namespace mtlabi;

static Display* g_wsi_dpy = nullptr;

static Display* wsi_display() {
    if (g_wsi_dpy) return g_wsi_dpy;
    if (!darwin_gl_host_libs()) return nullptr;
    auto open = (Display * (*)(const char*)) darwin_gl_host_x("XOpenDisplay");
    if (open) g_wsi_dpy = open(nullptr);
    return g_wsi_dpy;
}

static Layer* layer(uint32_t id) { return id < g.layers.size() ? g.layers[id].get() : nullptr; }

uint32_t layer_create(int window) {
    auto l = std::make_unique<Layer>();
    l->window = window;
    g.layers.push_back(std::move(l));
    return (uint32_t)g.layers.size() - 1;
}

static void destroy_drawables(Layer* l) {
    for (uint32_t t : l->drawables) texture_destroy(t);
    l->drawables.clear();
    l->busy.clear();
}

void layer_configure(uint32_t id, uint32_t w, uint32_t h, uint32_t fmt, uint32_t flags) {
    Layer* l = layer(id);
    if (!l) return;
    if (!w) w = 1;
    if (!h) h = 1;
    if (l->width != w || l->height != h || l->pixel_format != fmt) {
        // wait until the old drawables are idle before replacing them
        for (auto& q : g.queues) if (q) { vk.QueueWaitIdle(g.queue); retire(q.get()); }
        destroy_drawables(l);
        l->width = w; l->height = h; l->pixel_format = fmt;
        l->dirty = true;
    }
    l->flags = flags;
}

static void make_drawables(Layer* l) {
    if (!l->drawables.empty()) return;
    for (int i = 0; i < 3; i++) {
        xef_mtl_texture_desc d{};
        d.type = 2;
        d.pixel_format = l->pixel_format ? l->pixel_format : 80;
        d.width = l->width ? l->width : 1;
        d.height = l->height ? l->height : 1;
        d.depth = 1; d.mip_levels = 1; d.array_length = 1; d.sample_count = 1;
        d.usage = 1 | 2 | 4;
        d.swizzle[0] = 2; d.swizzle[1] = 3; d.swizzle[2] = 4; d.swizzle[3] = 5;
        uint64_t rid;
        uint32_t t = texture_create(&d, &rid);
        if (Texture* tx = texture(t)) tx->drawable = true;
        l->drawables.push_back(t);
        l->busy.push_back(false);
    }
}

uint32_t layer_next_drawable(uint32_t id, uint32_t* tex, uint64_t* rid) {
    Layer* l = layer(id);
    if (!l) return 0;
    make_drawables(l);
    for (int spin = 0; spin < 2000; spin++) {
        for (size_t i = 0; i < l->drawables.size(); i++)
            if (!l->busy[i]) {
                l->busy[i] = true;
                Texture* t = texture(l->drawables[i]);
                if (tex) *tex = l->drawables[i];
                if (rid) *rid = t ? t->resource_id : 0;
                return (uint32_t)i + 1;
            }
        // all drawables are queued for presentation: wait for the GPU
        for (auto& q : g.queues)
            if (q && !q->inflight.empty()) {
                uint64_t seq = q->inflight.front().seq;
                VkSemaphoreWaitInfo wi{VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO};
                wi.semaphoreCount = 1;
                wi.pSemaphores = &q->timeline;
                wi.pValues = &seq;
                vk.WaitSemaphores(g.dev, &wi, 1000000ull);
                retire(q.get());
            }
    }
    return 0;
}

void release_drawable(uint32_t key) {
    Layer* l = layer(key >> 16);
    uint32_t i = key & 0xffff;
    if (l && i < l->busy.size()) l->busy[i] = false;
}

static void destroy_swapchain(Layer* l);

void layer_destroy(uint32_t id) {
    Layer* l = layer(id);
    if (!l) return;
    for (auto& q : g.queues) if (q) { vk.QueueWaitIdle(g.queue); retire(q.get()); }
    destroy_drawables(l);
    destroy_swapchain(l);
    if (l->surface && g.instance) {
        vk.DestroySurfaceKHR(g.instance, l->surface, nullptr);
        l->surface = VK_NULL_HANDLE;
    }
    if (id < g.layers.size()) g.layers[id].reset();
}

static void destroy_swapchain(Layer* l) {
    if (l->swapchain) {
        vk.DeviceWaitIdle(g.dev);
        vk.DestroySwapchainKHR(g.dev, l->swapchain, nullptr);
        l->swapchain = VK_NULL_HANDLE;
    }
    for (VkSemaphore s : l->acquire_sems) vk.DestroySemaphore(g.dev, s, nullptr);
    for (VkSemaphore s : l->present_sems) vk.DestroySemaphore(g.dev, s, nullptr);
    l->acquire_sems.clear();
    l->present_sems.clear();
    l->sc_images.clear();
}

static bool ensure_swapchain(Layer* l) {
    if (l->swapchain && !l->dirty) return true;
    if (!g.has_xlib_surface) return false;
    if (!l->surface) {
        Display* dpy = wsi_display();
        unsigned long xid = xef_host_window_xid(l->window);
        if (!dpy || !xid) return false;
        VkXlibSurfaceCreateInfoKHR sci{VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR};
        sci.dpy = dpy;
        sci.window = xid;
        if (vk.CreateXlibSurfaceKHR(g.instance, &sci, nullptr, &l->surface) != VK_SUCCESS) return false;
        VkBool32 sup = VK_FALSE;
        vk.GetPhysicalDeviceSurfaceSupportKHR(g.pd, g.qfamily, l->surface, &sup);
        if (!sup) { XEF_LOG(1, "metal: queue cannot present to the window"); return false; }
    }
    VkSurfaceCapabilitiesKHR caps;
    vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(g.pd, l->surface, &caps);
    uint32_t n = 0;
    vk.GetPhysicalDeviceSurfaceFormatsKHR(g.pd, l->surface, &n, nullptr);
    std::vector<VkSurfaceFormatKHR> fmts(n);
    vk.GetPhysicalDeviceSurfaceFormatsKHR(g.pd, l->surface, &n, fmts.data());
    const PixelFormatInfo* pf = pixel_format(l->pixel_format);
    bool srgb = pf && (pf->flags & FMT_SRGB);
    VkSurfaceFormatKHR chosen = fmts.empty() ? VkSurfaceFormatKHR{VK_FORMAT_B8G8R8A8_UNORM, VK_COLOR_SPACE_SRGB_NONLINEAR_KHR} : fmts[0];
    for (auto& f : fmts)
        if (f.format == (srgb ? VK_FORMAT_B8G8R8A8_SRGB : VK_FORMAT_B8G8R8A8_UNORM)) { chosen = f; break; }
    VkExtent2D ext = caps.currentExtent;
    if (ext.width == 0xFFFFFFFFu) ext = {l->width, l->height};
    if (ext.width == 0 || ext.height == 0) return false;   // minimized
    vk.GetPhysicalDeviceSurfacePresentModesKHR(g.pd, l->surface, &n, nullptr);
    std::vector<VkPresentModeKHR> modes(n);
    vk.GetPhysicalDeviceSurfacePresentModesKHR(g.pd, l->surface, &n, modes.data());
    VkPresentModeKHR pm = VK_PRESENT_MODE_FIFO_KHR;
    bool vsync = !(l->flags & 1);   // flag 1: displaySyncEnabled == NO
    if (getenv("XEF_MTL_NOVSYNC")) vsync = false;
    if (!vsync)
        for (VkPresentModeKHR m : modes) if (m == VK_PRESENT_MODE_IMMEDIATE_KHR || m == VK_PRESENT_MODE_MAILBOX_KHR) { pm = m; if (m == VK_PRESENT_MODE_MAILBOX_KHR) break; }
    VkSwapchainKHR old = l->swapchain;
    VkSwapchainCreateInfoKHR ci{VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR};
    ci.surface = l->surface;
    ci.minImageCount = std::max(caps.minImageCount, 3u);
    if (caps.maxImageCount) ci.minImageCount = std::min(ci.minImageCount, caps.maxImageCount);
    ci.imageFormat = chosen.format;
    ci.imageColorSpace = chosen.colorSpace;
    ci.imageExtent = ext;
    ci.imageArrayLayers = 1;
    ci.imageUsage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    ci.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    ci.preTransform = caps.currentTransform;
    ci.compositeAlpha = (caps.supportedCompositeAlpha & VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR) ? VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR
                                                                                          : VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR;
    ci.presentMode = pm;
    ci.clipped = VK_TRUE;
    ci.oldSwapchain = old;
    if (old) vk.DeviceWaitIdle(g.dev);
    VkSwapchainKHR sc = VK_NULL_HANDLE;
    if (vk.CreateSwapchainKHR(g.dev, &ci, nullptr, &sc) != VK_SUCCESS) { XEF_LOG(1, "metal: swapchain creation failed"); return false; }
    l->swapchain = old;
    destroy_swapchain(l);
    l->swapchain = sc;
    l->sc_format = chosen.format;
    l->sc_extent = ext;
    vk.GetSwapchainImagesKHR(g.dev, sc, &n, nullptr);
    l->sc_images.resize(n);
    vk.GetSwapchainImagesKHR(g.dev, sc, &n, l->sc_images.data());
    VkSemaphoreCreateInfo si{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
    for (uint32_t i = 0; i < n + 1; i++) { VkSemaphore s; vk.CreateSemaphore(g.dev, &si, nullptr, &s); l->acquire_sems.push_back(s); }
    for (uint32_t i = 0; i < n; i++) { VkSemaphore s; vk.CreateSemaphore(g.dev, &si, nullptr, &s); l->present_sems.push_back(s); }
    l->dirty = false;
    XEF_LOG(1, "metal: swapchain %ux%u (%d images, mode %d)", ext.width, ext.height, (int)n, (int)pm);
    return true;
}

void present_record(VkCommandBuffer cb, uint32_t layer_id, uint32_t drawable, std::vector<PendingPresent>& to_present) {
    Layer* l = layer(layer_id);
    if (!l || drawable >= l->drawables.size()) return;
    Texture* t = texture(l->drawables[drawable]);
    if (!t) return;
    for (int attempt = 0; attempt < 2; attempt++) {
        if (!ensure_swapchain(l)) return;
        uint32_t idx = 0;
        VkSemaphore acq = l->acquire_sems[l->frame % l->acquire_sems.size()];
        VkResult r = vk.AcquireNextImageKHR(g.dev, l->swapchain, 2000000000ull, acq, VK_NULL_HANDLE, &idx);
        if (r == VK_ERROR_OUT_OF_DATE_KHR) { l->dirty = true; continue; }
        if (r != VK_SUCCESS && r != VK_SUBOPTIMAL_KHR) return;
        if (r == VK_SUBOPTIMAL_KHR) l->dirty = true;
        VkImage img = l->sc_images[idx];
        auto barrier = [&](VkImageLayout from, VkImageLayout to) {
            VkImageMemoryBarrier2 b{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2};
            b.srcStageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;
            b.srcAccessMask = VK_ACCESS_2_MEMORY_WRITE_BIT;
            b.dstStageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;
            b.dstAccessMask = VK_ACCESS_2_MEMORY_READ_BIT | VK_ACCESS_2_MEMORY_WRITE_BIT;
            b.oldLayout = from;
            b.newLayout = to;
            b.srcQueueFamilyIndex = b.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
            b.image = img;
            b.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
            VkDependencyInfo di{VK_STRUCTURE_TYPE_DEPENDENCY_INFO};
            di.imageMemoryBarrierCount = 1;
            di.pImageMemoryBarriers = &b;
            vk.CmdPipelineBarrier2(cb, &di);
        };
        image_barrier_all(cb);
        barrier(VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
        Texture* root = texture_root(t);
        VkImageBlit bl{};
        bl.srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
        bl.dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
        bl.srcOffsets[1] = {(int32_t)t->width, (int32_t)t->height, 1};
        bl.dstOffsets[1] = {(int32_t)l->sc_extent.width, (int32_t)l->sc_extent.height, 1};
        bool same = t->width == l->sc_extent.width && t->height == l->sc_extent.height;
        vk.CmdBlitImage(cb, root->img, VK_IMAGE_LAYOUT_GENERAL, img, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &bl, same ? VK_FILTER_NEAREST : VK_FILTER_LINEAR);
        barrier(VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);
        // the submission waits on `acq` and signals present_sems[idx]
        to_present.push_back({l, layer_id, drawable, idx, acq, l->present_sems[idx]});
        l->frame++;
        return;
    }
}

// XEF_MTL_SHOT=out.ppm [XEF_MTL_SHOT_FRAME=n]: write presented frame n (default 60) of the first layer
static void maybe_screenshot(PendingPresent& p) {
    static const char* path = getenv("XEF_MTL_SHOT");
    if (!path) return;
    static long want = getenv("XEF_MTL_SHOT_FRAME") ? atol(getenv("XEF_MTL_SHOT_FRAME")) : 60;
    static long count = 0;
    if (++count != want) return;
    Texture* t = texture(p.layer->drawables[p.drawable]);
    if (!t) return;
    vk.QueueWaitIdle(g.queue);
    std::vector<uint8_t> px((size_t)t->width * t->height * 4);
    uint32_t reg[6] = {0, 0, 0, t->width, t->height, 1};
    texture_get_bytes(p.layer->drawables[p.drawable], 0, 0, reg, px.data(), t->width * 4, 0);
    FILE* f = fopen(path, "wb");
    if (!f) return;
    fprintf(f, "P6\n%u %u\n255\n", t->width, t->height);
    bool bgra = t->vkfmt == VK_FORMAT_B8G8R8A8_UNORM || t->vkfmt == VK_FORMAT_B8G8R8A8_SRGB;
    for (size_t i = 0; i < (size_t)t->width * t->height; i++) {
        uint8_t* q = &px[i * 4];
        uint8_t rgb[3] = {bgra ? q[2] : q[0], q[1], bgra ? q[0] : q[2]};
        fwrite(rgb, 1, 3, f);
    }
    fclose(f);
    XEF_LOG(1, "metal: screenshot of frame %ld -> %s", want, path);
    fprintf(stderr, "xef-metal: screenshot frame %ld -> %s\n", want, path);
    if (getenv("XEF_MTL_SHOT_EXIT")) _exit(0);   // scripted runs: stop once the frame is saved
}

void present_after_submit(std::vector<PendingPresent>& to_present) {
    for (PendingPresent& p : to_present) {
        maybe_screenshot(p);
        Layer* l = p.layer;
        VkPresentInfoKHR pi{VK_STRUCTURE_TYPE_PRESENT_INFO_KHR};
        pi.waitSemaphoreCount = 1;
        pi.pWaitSemaphores = &p.present;
        pi.swapchainCount = 1;
        pi.pSwapchains = &l->swapchain;
        pi.pImageIndices = &p.image;
        VkResult r = vk.QueuePresentKHR(g.queue, &pi);
        if (r == VK_ERROR_OUT_OF_DATE_KHR || r == VK_SUBOPTIMAL_KHR) l->dirty = true;
    }
}

} // namespace xef::mtl
