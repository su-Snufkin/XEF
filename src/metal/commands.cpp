// Command stream decoding: guest-recorded Metal command buffers -> Vulkan command buffers.
#include "mtl_engine.h"
#include "common/common.h"
#include <cstring>

namespace xef::mtl {

using namespace mtlabi;

// ---------------- ring allocator ----------------

static constexpr uint64_t kChunkSize = 4ull << 20;

RingChunk* ring_alloc(Queue* q, uint64_t size, uint64_t align, uint64_t& offset) {
    auto fits = [&](RingChunk* c) {
        uint64_t o = (c->used + align - 1) & ~(align - 1);
        return o + size <= c->size;
    };
    if (!q->cur || !fits(q->cur)) {
        q->cur = nullptr;
        for (auto& c : q->chunks)
            if (c->last_use <= q->completed && c->size >= size) { c->used = 0; q->cur = c.get(); break; }
        if (!q->cur) {
            auto c = std::make_unique<RingChunk>();
            c->size = std::max<uint64_t>(kChunkSize, (size + 4095) & ~(uint64_t)4095);
            VkBufferCreateInfo bci{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
            bci.size = c->size;
            bci.usage = VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT | VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT |
                        VK_BUFFER_USAGE_INDEX_BUFFER_BIT | VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
            vk.CreateBuffer(g.dev, &bci, nullptr, &c->buf);
            VkMemoryRequirements req;
            vk.GetBufferMemoryRequirements(g.dev, c->buf, &req);
            // device-local + host-visible (resizable BAR) when available, host memory otherwise
            c->mem = alloc_memory(req, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT | VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, true);
            if (!c->mem) c->mem = alloc_memory(req, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, true);
            vk.BindBufferMemory(g.dev, c->buf, c->mem, 0);
            vk.MapMemory(g.dev, c->mem, 0, VK_WHOLE_SIZE, 0, (void**)&c->map);
            VkBufferDeviceAddressInfo ai{VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO};
            ai.buffer = c->buf;
            c->addr = vk.GetBufferDeviceAddress(g.dev, &ai);
            q->chunks.push_back(std::move(c));
            q->cur = q->chunks.back().get();
        }
    }
    RingChunk* c = q->cur;
    offset = (c->used + align - 1) & ~(align - 1);
    c->used = offset + size;
    c->last_use = q->next_seq;
    return c;
}

// ---------------- recorder ----------------

namespace {

struct StageBind {
    uint32_t buffer[XEF_MTL_MAX_BUFFERS + 1] = {};
    uint64_t offset[XEF_MTL_MAX_BUFFERS + 1] = {};
    uint64_t bytes_addr[XEF_MTL_MAX_BUFFERS + 1] = {};      // setBytes data (ring address), 0 = buffer binding
    VkBuffer bytes_buf[XEF_MTL_MAX_BUFFERS + 1] = {};
    uint64_t bytes_off[XEF_MTL_MAX_BUFFERS + 1] = {};
    uint32_t bytes_len[XEF_MTL_MAX_BUFFERS + 1] = {};
    uint32_t texture[XEF_MTL_MAX_TEXTURES] = {};
    uint32_t sampler[XEF_MTL_MAX_SAMPLERS] = {};
};

struct Recorder {
    Queue* q;
    VkCommandBuffer cb;
    enum { NONE, RENDER, COMPUTE, BLIT } kind = NONE;
    StageBind st[3];
    RenderPipeline* rp = nullptr;
    ComputePipeline* cp = nullptr;
    VkPipeline bound_pipe = VK_NULL_HANDLE;
    uint32_t rt_w = 0, rt_h = 0;
    bool rendering = false;
    bool has_depth_att = false, has_stencil_att = false;
    // dynamic state
    xef_mtl_viewport viewport{};
    xef_mtl_scissor scissor{};
    xef_mtl_raster_state raster{};
    xef_mtl_depth_stencil dss{};
    xef_mtl_stencil_ref sref{};
    xef_mtl_blend_color blend{};
    bool dirty_vp = true, dirty_sc = true, dirty_rs = true, dirty_ds = true, dirty_sr = true, dirty_bc = true;
    int last_topology = -1, last_restart = -1;
    struct VB { VkBuffer buf = VK_NULL_HANDLE; uint64_t off = ~0ull; } vb[XEF_MTL_MAX_BUFFERS + 1];
    std::vector<uint32_t> tg_mem;
    bool barrier_pending = false;
    std::vector<PendingPresent> presents;
    std::vector<std::pair<uint32_t, uint64_t>> signals, waits;
    std::vector<uint32_t> release;
    std::string err;

    void barrier() { image_barrier_all(cb); }

    void bind_set(VkPipelineBindPoint bp) {
        vk.CmdBindDescriptorSets(cb, bp, g.pipe_layout, 0, 1, &g.set, 0, nullptr);
    }

    uint64_t buffer_addr(StageBind& s, uint32_t i) {
        if (i > XEF_MTL_MAX_BUFFERS) return 0;
        if (s.bytes_addr[i]) return s.bytes_addr[i];
        Buffer* b = buffer(s.buffer[i]);
        return b ? b->addr + s.offset[i] : 0;
    }

    // argument table for one stage -> ring address
    uint64_t build_table(StageBind& s, const StageModule& m) {
        const StageResult& r = m.refl;
        if (!r.table_size) return 0;
        uint64_t off;
        RingChunk* c = ring_alloc(q, r.table_size, 16, off);
        uint64_t* t = (uint64_t*)(c->map + off);
        for (const TableEntry& e : r.table) {
            uint64_t v = 0;
            switch (e.kind) {
            case BIND_BUFFER: v = buffer_addr(s, e.index); break;
            case BIND_TEXTURE: {
                Texture* tx = e.index < XEF_MTL_MAX_TEXTURES ? texture(s.texture[e.index]) : nullptr;
                v = tx ? tx->resource_id : 0;
                break;
            }
            case BIND_SAMPLER: {
                Sampler* sm = e.index < XEF_MTL_MAX_SAMPLERS ? sampler(s.sampler[e.index]) : nullptr;
                v = sm ? sm->resource_id : 0;
                break;
            }
            case BIND_CONST_SAMPLER: {
                Sampler* sm = e.index < m.const_samplers.size() ? sampler(m.const_samplers[e.index]) : nullptr;
                v = sm ? sm->resource_id : 0;
                break;
            }
            case BIND_CONST_DATA: {
                Buffer* b = buffer(m.const_buffer);
                v = b ? b->addr : 0;
                break;
            }
            case BIND_BUFFER_SIZE: {
                if (e.index <= XEF_MTL_MAX_BUFFERS) {
                    if (s.bytes_addr[e.index]) v = s.bytes_len[e.index];
                    else if (Buffer* b = buffer(s.buffer[e.index])) v = b->size - std::min(b->size, s.offset[e.index]);
                }
                break;
            }
            default: break;
            }
            t[e.offset / 8] = v;
        }
        return c->addr + off;
    }

    void set_bytes(uint32_t stage, uint32_t index, const void* data, uint32_t len) {
        if (stage > 2 || index > XEF_MTL_MAX_BUFFERS) return;
        uint64_t off;
        RingChunk* c = ring_alloc(q, std::max(len, 16u), 256, off);
        memcpy(c->map + off, data, len);
        StageBind& s = st[stage];
        s.bytes_addr[index] = c->addr + off;
        s.bytes_buf[index] = c->buf;
        s.bytes_off[index] = off;
        s.bytes_len[index] = len;
    }

    // ---------------- render ----------------
    void begin_render(const xef_mtl_begin_render* b) {
        end_encoder();
        kind = RENDER;
        barrier();
        VkRenderingAttachmentInfo colors[XEF_MTL_MAX_COLOR] = {};
        uint32_t ncolor = 0;
        uint32_t w = b->width, h = b->height;
        uint32_t layers = std::max(1u, b->layers);
        auto load_op = [](uint32_t a) { return a == 1 ? VK_ATTACHMENT_LOAD_OP_LOAD : a == 2 ? VK_ATTACHMENT_LOAD_OP_CLEAR : VK_ATTACHMENT_LOAD_OP_DONT_CARE; };
        auto store_op = [](uint32_t a) { return (a == 1 || a == 3 || a == 4) ? VK_ATTACHMENT_STORE_OP_STORE : VK_ATTACHMENT_STORE_OP_DONT_CARE; };
        auto extent = [&](Texture* t, uint32_t level) {
            uint32_t tw = std::max(1u, t->width >> level), th = std::max(1u, t->height >> level);
            if (!w || tw < w) w = tw;
            if (!h || th < h) h = th;
        };
        for (uint32_t i = 0; i < XEF_MTL_MAX_COLOR; i++) {
            const xef_mtl_rp_color& c = b->colors[i];
            VkRenderingAttachmentInfo& a = colors[i];
            a.sType = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO;
            Texture* t = texture(c.texture);
            if (!t) continue;
            ncolor = i + 1;
            uint32_t slice = t->type == 7 ? c.depth_plane : c.slice;
            a.imageView = attachment_view(t, c.level, slice, layers, VK_IMAGE_ASPECT_COLOR_BIT);
            a.imageLayout = VK_IMAGE_LAYOUT_GENERAL;
            a.loadOp = load_op(c.load_action);
            a.storeOp = store_op(c.store_action);
            if (t->fmt && (t->fmt->flags & (FMT_INT | FMT_UINT))) {
                for (int k = 0; k < 4; k++) {
                    if (t->fmt->flags & FMT_UINT) a.clearValue.color.uint32[k] = (uint32_t)c.clear[k];
                    else a.clearValue.color.int32[k] = (int32_t)c.clear[k];
                }
            } else memcpy(a.clearValue.color.float32, c.clear, 16);
            Texture* rt = texture(c.resolve_texture);
            if (rt && (c.store_action == 2 || c.store_action == 3)) {
                a.resolveImageView = attachment_view(rt, c.resolve_level, rt->type == 7 ? c.resolve_depth_plane : c.resolve_slice, layers, VK_IMAGE_ASPECT_COLOR_BIT);
                a.resolveImageLayout = VK_IMAGE_LAYOUT_GENERAL;
                a.resolveMode = (t->fmt && (t->fmt->flags & (FMT_INT | FMT_UINT))) ? VK_RESOLVE_MODE_SAMPLE_ZERO_BIT : VK_RESOLVE_MODE_AVERAGE_BIT;
            }
            extent(t, c.level);
        }
        VkRenderingAttachmentInfo depth{VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
        VkRenderingAttachmentInfo stencil{VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
        Texture* dt = texture(b->depth.texture);
        Texture* stt = texture(b->stencil.texture);
        has_depth_att = dt && dt->fmt && (dt->fmt->flags & FMT_DEPTH);
        has_stencil_att = stt && stt->fmt && (stt->fmt->flags & FMT_STENCIL) && (stt->vkfmt != VK_FORMAT_D32_SFLOAT || false);
        if (stt && (stt->vkfmt == VK_FORMAT_D32_SFLOAT || stt->vkfmt == VK_FORMAT_D16_UNORM)) has_stencil_att = false;
        if (has_depth_att) {
            depth.imageView = attachment_view(dt, b->depth.level, b->depth.slice, layers, VK_IMAGE_ASPECT_DEPTH_BIT);
            depth.imageLayout = VK_IMAGE_LAYOUT_GENERAL;
            depth.loadOp = load_op(b->depth.load_action);
            depth.storeOp = store_op(b->depth.store_action);
            depth.clearValue.depthStencil.depth = b->depth.clear_depth;
            Texture* rt = texture(b->depth.resolve_texture);
            if (rt && (b->depth.store_action == 2 || b->depth.store_action == 3)) {
                depth.resolveImageView = attachment_view(rt, b->depth.resolve_level, b->depth.resolve_slice, layers, VK_IMAGE_ASPECT_DEPTH_BIT);
                depth.resolveImageLayout = VK_IMAGE_LAYOUT_GENERAL;
                depth.resolveMode = VK_RESOLVE_MODE_SAMPLE_ZERO_BIT;
            }
            extent(dt, b->depth.level);
        }
        if (has_stencil_att) {
            stencil.imageView = attachment_view(stt, b->stencil.level, b->stencil.slice, layers, VK_IMAGE_ASPECT_STENCIL_BIT);
            stencil.imageLayout = VK_IMAGE_LAYOUT_GENERAL;
            stencil.loadOp = load_op(b->stencil.load_action);
            stencil.storeOp = store_op(b->stencil.store_action);
            stencil.clearValue.depthStencil.stencil = b->stencil.clear_stencil;
            // a combined depth/stencil texture bound to both: Vulkan wants the same view
            if (has_depth_att && dt == stt) {
                VkImageView v = attachment_view(dt, b->depth.level, b->depth.slice, layers, VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT);
                depth.imageView = v;
                stencil.imageView = v;
            }
            extent(stt, b->stencil.level);
        } else if (has_depth_att && (dt->vkfmt == VK_FORMAT_D32_SFLOAT_S8_UINT || dt->vkfmt == VK_FORMAT_D24_UNORM_S8_UINT)) {
            depth.imageView = attachment_view(dt, b->depth.level, b->depth.slice, layers, VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT);
        }
        if (!w) w = 1;
        if (!h) h = 1;
        rt_w = w; rt_h = h;
        VkRenderingInfo ri{VK_STRUCTURE_TYPE_RENDERING_INFO};
        ri.renderArea = {{0, 0}, {w, h}};
        ri.layerCount = layers;
        ri.colorAttachmentCount = ncolor;
        ri.pColorAttachments = colors;
        ri.pDepthAttachment = has_depth_att ? &depth : nullptr;
        ri.pStencilAttachment = has_stencil_att ? &stencil : nullptr;
        vk.CmdBeginRendering(cb, &ri);
        rendering = true;
        bind_set(VK_PIPELINE_BIND_POINT_GRAPHICS);
        bound_pipe = VK_NULL_HANDLE;
        rp = nullptr;
        viewport = {0, 0, (float)w, (float)h, 0, 1};
        scissor = {0, 0, w, h};
        raster = {};
        dss = {};
        dss.depth_compare = 7;
        dss.front.compare = dss.back.compare = 7;
        dss.front.read_mask = dss.back.read_mask = dss.front.write_mask = dss.back.write_mask = 0xff;
        sref = {};
        blend = {};
        dirty_vp = dirty_sc = dirty_rs = dirty_ds = dirty_sr = dirty_bc = true;
        last_topology = last_restart = -1;
        for (auto& v : vb) v = VB{};
        for (auto& s : st) s = StageBind{};
    }

    void flush_dynamic() {
        if (dirty_vp) {
            VkViewport v{viewport.x, viewport.y + viewport.h, viewport.w, -viewport.h, viewport.znear, viewport.zfar};
            if (v.width <= 0) v.width = 1;
            vk.CmdSetViewport(cb, 0, 1, &v);
            dirty_vp = false;
        }
        if (dirty_sc) {
            int32_t x = (int32_t)std::min(scissor.x, rt_w), y = (int32_t)std::min(scissor.y, rt_h);
            uint32_t sw = std::min(scissor.w, rt_w - (uint32_t)x), sh = std::min(scissor.h, rt_h - (uint32_t)y);
            VkRect2D r{{x, y}, {sw, sh}};
            vk.CmdSetScissor(cb, 0, 1, &r);
            dirty_sc = false;
        }
        if (dirty_rs) {
            vk.CmdSetCullMode(cb, raster.cull_mode == 1 ? VK_CULL_MODE_FRONT_BIT : raster.cull_mode == 2 ? VK_CULL_MODE_BACK_BIT : VK_CULL_MODE_NONE);
            vk.CmdSetFrontFace(cb, raster.winding == 1 ? VK_FRONT_FACE_COUNTER_CLOCKWISE : VK_FRONT_FACE_CLOCKWISE);
            bool bias = raster.depth_bias != 0 || raster.slope_scale != 0;
            vk.CmdSetDepthBiasEnable(cb, bias ? VK_TRUE : VK_FALSE);
            vk.CmdSetDepthBias(cb, raster.depth_bias, raster.clamp, raster.slope_scale);
            if (g.has_eds3_polygon && vk.CmdSetPolygonModeEXT)
                vk.CmdSetPolygonModeEXT(cb, raster.fill_mode == 1 && g.has_fill_mode_non_solid ? VK_POLYGON_MODE_LINE : VK_POLYGON_MODE_FILL);
            if (g.has_eds3_clamp && vk.CmdSetDepthClampEnableEXT) vk.CmdSetDepthClampEnableEXT(cb, raster.depth_clip == 1 ? VK_TRUE : VK_FALSE);
            dirty_rs = false;
        }
        if (dirty_ds) {
            vk.CmdSetDepthTestEnable(cb, has_depth_att ? VK_TRUE : VK_FALSE);
            vk.CmdSetDepthWriteEnable(cb, has_depth_att && dss.depth_write ? VK_TRUE : VK_FALSE);
            vk.CmdSetDepthCompareOp(cb, (VkCompareOp)dss.depth_compare);
            vk.CmdSetStencilTestEnable(cb, has_stencil_att && dss.stencil_enabled ? VK_TRUE : VK_FALSE);
            vk.CmdSetStencilOp(cb, VK_STENCIL_FACE_FRONT_BIT, (VkStencilOp)dss.front.fail_op, (VkStencilOp)dss.front.pass_op,
                               (VkStencilOp)dss.front.depth_fail_op, (VkCompareOp)dss.front.compare);
            vk.CmdSetStencilOp(cb, VK_STENCIL_FACE_BACK_BIT, (VkStencilOp)dss.back.fail_op, (VkStencilOp)dss.back.pass_op,
                               (VkStencilOp)dss.back.depth_fail_op, (VkCompareOp)dss.back.compare);
            vk.CmdSetStencilCompareMask(cb, VK_STENCIL_FACE_FRONT_BIT, dss.front.read_mask);
            vk.CmdSetStencilCompareMask(cb, VK_STENCIL_FACE_BACK_BIT, dss.back.read_mask);
            vk.CmdSetStencilWriteMask(cb, VK_STENCIL_FACE_FRONT_BIT, dss.front.write_mask);
            vk.CmdSetStencilWriteMask(cb, VK_STENCIL_FACE_BACK_BIT, dss.back.write_mask);
            dirty_ds = false;
        }
        if (dirty_sr) {
            vk.CmdSetStencilReference(cb, VK_STENCIL_FACE_FRONT_BIT, sref.front);
            vk.CmdSetStencilReference(cb, VK_STENCIL_FACE_BACK_BIT, sref.back);
            dirty_sr = false;
        }
        if (dirty_bc) {
            float c[4] = {blend.r, blend.g, blend.b, blend.a};
            vk.CmdSetBlendConstants(cb, c);
            dirty_bc = false;
        }
    }

    bool prepare_draw(uint32_t primitive) {
        if (!rp) { err = "draw without a render pipeline"; return false; }
        uint32_t cls = primitive == 0 ? 0 : primitive <= 2 ? 1 : 2;
        VkPipeline p = render_pipeline_for(rp, cls);
        if (!p) return false;
        if (p != bound_pipe) {
            vk.CmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, p);
            bound_pipe = p;
            // a new pipeline may use different vertex bindings
            for (auto& v : vb) v = VB{};
        }
        static const VkPrimitiveTopology topo[] = {VK_PRIMITIVE_TOPOLOGY_POINT_LIST, VK_PRIMITIVE_TOPOLOGY_LINE_LIST, VK_PRIMITIVE_TOPOLOGY_LINE_STRIP,
                                                   VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP};
        int t = (int)std::min(primitive, 4u);
        if (t != last_topology) { vk.CmdSetPrimitiveTopology(cb, topo[t]); last_topology = t; }
        int restart = (t == 2 || t == 4) ? 1 : 0;
        if (restart != last_restart) { vk.CmdSetPrimitiveRestartEnable(cb, restart ? VK_TRUE : VK_FALSE); last_restart = restart; }
        flush_dynamic();
        // vertex buffers
        StageBind& vs = st[XEF_MTL_STAGE_VERTEX];
        for (uint32_t bi : rp->vertex_bindings) {
            VkBuffer buf = VK_NULL_HANDLE;
            uint64_t off = 0;
            if (vs.bytes_addr[bi]) { buf = vs.bytes_buf[bi]; off = vs.bytes_off[bi]; }
            else if (Buffer* b = buffer(vs.buffer[bi])) { buf = b->buf; off = vs.offset[bi]; }
            else { Buffer* d = buffer(g.dummy_buffer); buf = d->buf; off = 0; }
            if (vb[bi].buf != buf || vb[bi].off != off) {
                vk.CmdBindVertexBuffers(cb, bi, 1, &buf, &off);
                vb[bi].buf = buf; vb[bi].off = off;
            }
        }
        if (rp->needs_dummy_binding && vb[XEF_MTL_MAX_BUFFERS].buf == VK_NULL_HANDLE) {
            Buffer* d = buffer(g.dummy_buffer);
            VkDeviceSize off = 0;
            vk.CmdBindVertexBuffers(cb, XEF_MTL_MAX_BUFFERS, 1, &d->buf, &off);
            vb[XEF_MTL_MAX_BUFFERS].buf = d->buf; vb[XEF_MTL_MAX_BUFFERS].off = 0;
        }
        PushConstants pc{};
        pc.table[0] = build_table(st[XEF_MTL_STAGE_VERTEX], rp->vs);
        if (rp->has_fs) pc.table[1] = build_table(st[XEF_MTL_STAGE_FRAGMENT], rp->fs);
        vk.CmdPushConstants(cb, g.pipe_layout, VK_SHADER_STAGE_ALL, 0, sizeof(pc), &pc);
        return true;
    }

    // ---------------- compute ----------------
    void begin_compute() {
        end_encoder();
        kind = COMPUTE;
        barrier();
        bind_set(VK_PIPELINE_BIND_POINT_COMPUTE);
        bound_pipe = VK_NULL_HANDLE;
        cp = nullptr;
        st[XEF_MTL_STAGE_KERNEL] = StageBind{};
        tg_mem.clear();
    }

    void dispatch(const xef_mtl_dispatch* d) {
        if (!cp) { err = "dispatch without a compute pipeline"; return; }
        uint32_t tg[3] = {std::max(1u, d->threads[0]), std::max(1u, d->threads[1]), std::max(1u, d->threads[2])};
        ComputeVariant* v = compute_variant(cp, tg, tg_mem, err);
        if (!v) return;
        if (v->pipe != bound_pipe) { vk.CmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, v->pipe); bound_pipe = v->pipe; }
        if (barrier_pending) barrier();
        PushConstants pc{};
        pc.table[0] = build_table(st[XEF_MTL_STAGE_KERNEL], v->cs);
        uint32_t groups[3];
        for (int i = 0; i < 3; i++) {
            if (d->by_threads) {
                groups[i] = (d->groups[i] + tg[i] - 1) / tg[i];
                pc.grid[i] = d->groups[i];
            } else {
                groups[i] = d->groups[i];
                pc.grid[i] = d->groups[i] * tg[i];
            }
        }
        if (d->by_threads && (v->cs.refl.flags & SF_GRID_BOUNDS)) pc.flags |= PC_FLAG_GRID_BOUNDS;
        vk.CmdPushConstants(cb, g.pipe_layout, VK_SHADER_STAGE_ALL, 0, sizeof(pc), &pc);
        if (groups[0] && groups[1] && groups[2]) vk.CmdDispatch(cb, groups[0], groups[1], groups[2]);
        barrier_pending = true;
    }

    // ---------------- blit ----------------
    VkImageAspectFlags copy_aspect(Texture* t) {
        VkImageAspectFlags a = aspect_of(t->fmt);
        if (a == (VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT)) a = VK_IMAGE_ASPECT_DEPTH_BIT;
        return a;
    }

    void copy_buf_tex(const xef_mtl_copy_buf_tex* c, bool to_texture) {
        Buffer* b = buffer(c->buffer);
        Texture* t = texture(c->texture);
        if (!b || !t) return;
        Texture* root = texture_root(t);
        VkBufferImageCopy r{};
        r.bufferOffset = c->buffer_offset;
        uint32_t bw = t->fmt->block_w, bh = t->fmt->block_h, bb = t->fmt->block_bytes;
        r.bufferRowLength = c->bytes_per_row ? (c->bytes_per_row / bb) * bw : 0;
        uint32_t rows = c->bytes_per_image && c->bytes_per_row ? c->bytes_per_image / c->bytes_per_row : 0;
        r.bufferImageHeight = rows ? rows * bh : 0;
        bool is3d = t->type == 7;
        r.imageSubresource = {copy_aspect(t), t->base_level + c->level, t->base_layer + (is3d ? 0 : c->slice), 1};
        r.imageOffset = {(int32_t)c->x, (int32_t)c->y, (int32_t)c->z};
        r.imageExtent = {c->w, c->h, std::max(1u, c->d)};
        if (to_texture) vk.CmdCopyBufferToImage(cb, b->buf, root->img, VK_IMAGE_LAYOUT_GENERAL, 1, &r);
        else vk.CmdCopyImageToBuffer(cb, root->img, VK_IMAGE_LAYOUT_GENERAL, b->buf, 1, &r);
    }

    void copy_texture(const xef_mtl_copy_texture* c) {
        Texture* s = texture(c->src);
        Texture* d = texture(c->dst);
        if (!s || !d) return;
        Texture* sr = texture_root(s);
        Texture* dr = texture_root(d);
        std::vector<VkImageCopy> regs;
        if (c->whole) {
            uint32_t levels = std::min(s->mips, d->mips);
            for (uint32_t l = 0; l < levels; l++) {
                VkImageCopy r{};
                r.srcSubresource = {copy_aspect(s), s->base_level + l, s->base_layer, std::min(s->layers, d->layers)};
                r.dstSubresource = {copy_aspect(d), d->base_level + l, d->base_layer, std::min(s->layers, d->layers)};
                r.extent = {std::max(1u, s->width >> l), std::max(1u, s->height >> l), s->type == 7 ? std::max(1u, s->depth >> l) : 1};
                regs.push_back(r);
            }
        } else {
            uint32_t slices = std::max(1u, c->slice_count), levels = std::max(1u, c->level_count);
            for (uint32_t l = 0; l < levels; l++) {
                VkImageCopy r{};
                r.srcSubresource = {copy_aspect(s), s->base_level + c->src_level + l, s->base_layer + c->src_slice, slices};
                r.dstSubresource = {copy_aspect(d), d->base_level + c->dst_level + l, d->base_layer + c->dst_slice, slices};
                r.srcOffset = {(int32_t)c->sx, (int32_t)c->sy, (int32_t)c->sz};
                r.dstOffset = {(int32_t)c->dx, (int32_t)c->dy, (int32_t)c->dz};
                uint32_t w = c->w ? c->w : std::max(1u, s->width >> (c->src_level + l));
                uint32_t h = c->h ? c->h : std::max(1u, s->height >> (c->src_level + l));
                r.extent = {w, h, std::max(1u, c->d)};
                regs.push_back(r);
            }
        }
        if (s->samples > 1 && d->samples == 1) {   // multisample -> single sample: resolve
            std::vector<VkImageResolve> rr;
            for (auto& r : regs) rr.push_back({r.srcSubresource, r.srcOffset, r.dstSubresource, r.dstOffset, r.extent});
            vk.CmdResolveImage(cb, sr->img, VK_IMAGE_LAYOUT_GENERAL, dr->img, VK_IMAGE_LAYOUT_GENERAL, (uint32_t)rr.size(), rr.data());
            return;
        }
        vk.CmdCopyImage(cb, sr->img, VK_IMAGE_LAYOUT_GENERAL, dr->img, VK_IMAGE_LAYOUT_GENERAL, (uint32_t)regs.size(), regs.data());
    }

    void generate_mipmaps(uint32_t id) {
        Texture* t = texture(id);
        if (!t || t->mips < 2) return;
        Texture* root = texture_root(t);
        VkImageAspectFlags a = copy_aspect(t);
        bool linear = !(t->fmt->flags & (FMT_INT | FMT_UINT | FMT_DEPTH | FMT_STENCIL));
        for (uint32_t l = 1; l < t->mips; l++) {
            VkImageBlit b{};
            b.srcSubresource = {a, t->base_level + l - 1, t->base_layer, t->layers};
            b.dstSubresource = {a, t->base_level + l, t->base_layer, t->layers};
            b.srcOffsets[1] = {(int32_t)std::max(1u, t->width >> (l - 1)), (int32_t)std::max(1u, t->height >> (l - 1)), t->type == 7 ? (int32_t)std::max(1u, t->depth >> (l - 1)) : 1};
            b.dstOffsets[1] = {(int32_t)std::max(1u, t->width >> l), (int32_t)std::max(1u, t->height >> l), t->type == 7 ? (int32_t)std::max(1u, t->depth >> l) : 1};
            vk.CmdBlitImage(cb, root->img, VK_IMAGE_LAYOUT_GENERAL, root->img, VK_IMAGE_LAYOUT_GENERAL, 1, &b, linear ? VK_FILTER_LINEAR : VK_FILTER_NEAREST);
            barrier();
        }
    }

    void fill_buffer(const xef_mtl_fill_buffer* f) {
        Buffer* b = buffer(f->buffer);
        if (!b || !f->length) return;
        uint32_t v = (f->value & 0xff) * 0x01010101u;
        // HLE: Vulkan fills whole 32-bit words; unaligned edges are rounded outwards (Metal buffer lengths are padded)
        uint64_t off = f->offset & ~3ull;
        uint64_t end = std::min<uint64_t>((f->offset + f->length + 3) & ~3ull, (b->size + 3) & ~3ull);
        if (end > off) vk.CmdFillBuffer(cb, b->buf, off, end - off, v);
    }

    void end_encoder() {
        if (rendering) { vk.CmdEndRendering(cb); rendering = false; }
        if (kind != NONE) barrier();
        kind = NONE;
        barrier_pending = false;
    }

    static bool trace_on() { static int t = getenv("XEF_MTL_TRACE") ? 1 : 0; return t; }
    void trace_op(uint32_t op, const uint8_t* d) {
        switch (op) {
        case XEF_MTL_CMD_DRAW: {
            auto* c = (const xef_mtl_draw*)d;
            fprintf(stderr, "mtl: draw prim %u v%u+%u i%u rp=%p rendering=%d\n", c->primitive, c->vertex_start, c->vertex_count, c->instance_count, (void*)rp, rendering);
            break;
        }
        case XEF_MTL_CMD_DRAW_INDEXED: {
            auto* c = (const xef_mtl_draw_indexed*)d;
            fprintf(stderr, "mtl: draw_indexed prim %u n%u i%u ib=%u rp=%p rendering=%d\n", c->primitive, c->index_count, c->instance_count, c->index_buffer, (void*)rp, rendering);
            break;
        }
        default: fprintf(stderr, "mtl: op %u size\n", op); break;
        }
    }

    bool run(const uint8_t* p, uint64_t len) {
        const uint8_t* end = p + len;
        while (p + sizeof(xef_mtl_cmd) <= end) {
            xef_mtl_cmd h;
            memcpy(&h, p, sizeof h);
            const uint8_t* d = p + sizeof h;
            if (d + h.size > end) { err = "truncated command stream"; return false; }
            p = d + h.size;
            if (trace_on()) trace_op(h.op, d);
            switch (h.op) {
            case XEF_MTL_CMD_BEGIN_RENDER: begin_render((const xef_mtl_begin_render*)d); break;
            case XEF_MTL_CMD_BEGIN_COMPUTE: begin_compute(); break;
            case XEF_MTL_CMD_BEGIN_BLIT: end_encoder(); kind = BLIT; barrier(); break;
            case XEF_MTL_CMD_END_ENCODER: end_encoder(); break;
            case XEF_MTL_CMD_SET_RENDER_PIPELINE: {
                auto* s = (const xef_mtl_set_pipeline*)d;
                Pipeline* pp = s->pipeline < g.pipelines.size() ? g.pipelines[s->pipeline].get() : nullptr;
                rp = pp ? pp->render.get() : nullptr;
                break;
            }
            case XEF_MTL_CMD_SET_COMPUTE_PIPELINE: {
                auto* s = (const xef_mtl_set_pipeline*)d;
                Pipeline* pp = s->pipeline < g.pipelines.size() ? g.pipelines[s->pipeline].get() : nullptr;
                cp = pp ? pp->compute.get() : nullptr;
                break;
            }
            case XEF_MTL_CMD_SET_BUFFER: case XEF_MTL_CMD_SET_BUFFER_OFFSET: {
                auto* s = (const xef_mtl_set_buffer*)d;
                if (s->stage > 2 || s->index > XEF_MTL_MAX_BUFFERS) break;
                StageBind& sb = st[s->stage];
                if (h.op == XEF_MTL_CMD_SET_BUFFER) sb.buffer[s->index] = s->buffer;
                sb.offset[s->index] = s->offset;
                sb.bytes_addr[s->index] = 0;
                break;
            }
            case XEF_MTL_CMD_SET_BYTES: {
                auto* s = (const xef_mtl_set_bytes*)d;
                set_bytes(s->stage, s->index, s + 1, s->length);
                break;
            }
            case XEF_MTL_CMD_SET_TEXTURE: {
                auto* s = (const xef_mtl_set_texture*)d;
                if (s->stage <= 2 && s->index < XEF_MTL_MAX_TEXTURES) st[s->stage].texture[s->index] = s->texture;
                break;
            }
            case XEF_MTL_CMD_SET_SAMPLER: {
                auto* s = (const xef_mtl_set_sampler*)d;
                if (s->stage <= 2 && s->index < XEF_MTL_MAX_SAMPLERS) st[s->stage].sampler[s->index] = s->sampler;
                break;
            }
            case XEF_MTL_CMD_SET_VIEWPORT: memcpy(&viewport, d, sizeof viewport); dirty_vp = true; break;
            case XEF_MTL_CMD_SET_SCISSOR: memcpy(&scissor, d, sizeof scissor); dirty_sc = true; break;
            case XEF_MTL_CMD_SET_RASTER_STATE: memcpy(&raster, d, sizeof raster); dirty_rs = true; break;
            case XEF_MTL_CMD_SET_DEPTH_STENCIL: memcpy(&dss, d, sizeof dss); dirty_ds = true; break;
            case XEF_MTL_CMD_SET_STENCIL_REF: memcpy(&sref, d, sizeof sref); dirty_sr = true; break;
            case XEF_MTL_CMD_SET_BLEND_COLOR: memcpy(&blend, d, sizeof blend); dirty_bc = true; break;
            case XEF_MTL_CMD_DRAW: {
                auto* c = (const xef_mtl_draw*)d;
                if (!rendering || !c->vertex_count || !c->instance_count) break;
                if (prepare_draw(c->primitive)) vk.CmdDraw(cb, c->vertex_count, c->instance_count, c->vertex_start, c->base_instance);
                break;
            }
            case XEF_MTL_CMD_DRAW_INDEXED: {
                auto* c = (const xef_mtl_draw_indexed*)d;
                Buffer* ib = buffer(c->index_buffer);
                if (!rendering || !ib || !c->index_count || !c->instance_count) break;
                if (!prepare_draw(c->primitive)) break;
                VkIndexType it = c->index_type == 1 ? VK_INDEX_TYPE_UINT32 : VK_INDEX_TYPE_UINT16;
                uint64_t isz = it == VK_INDEX_TYPE_UINT32 ? 4 : 2;
                vk.CmdBindIndexBuffer(cb, ib->buf, c->index_offset & ~(isz - 1), it);
                vk.CmdDrawIndexed(cb, c->index_count, c->instance_count, 0, c->base_vertex, c->base_instance);
                break;
            }
            case XEF_MTL_CMD_DRAW_INDIRECT: case XEF_MTL_CMD_DRAW_INDEXED_INDIRECT: {
                auto* c = (const xef_mtl_draw_indirect*)d;
                Buffer* b = buffer(c->buffer);
                if (!rendering || !b || !prepare_draw(c->primitive)) break;
                if (h.op == XEF_MTL_CMD_DRAW_INDIRECT) vk.CmdDrawIndirect(cb, b->buf, c->offset, 1, 16);
                else {
                    Buffer* ib = buffer(c->index_buffer);
                    if (!ib) break;
                    vk.CmdBindIndexBuffer(cb, ib->buf, c->index_offset, c->index_type == 1 ? VK_INDEX_TYPE_UINT32 : VK_INDEX_TYPE_UINT16);
                    vk.CmdDrawIndexedIndirect(cb, b->buf, c->offset, 1, 20);
                }
                break;
            }
            case XEF_MTL_CMD_SET_THREADGROUP_MEMORY: {
                auto* s = (const xef_mtl_tg_memory*)d;
                if (s->index < 32) {
                    if (tg_mem.size() <= s->index) tg_mem.resize(s->index + 1, 0);
                    tg_mem[s->index] = s->length;
                }
                break;
            }
            case XEF_MTL_CMD_DISPATCH: dispatch((const xef_mtl_dispatch*)d); break;
            case XEF_MTL_CMD_DISPATCH_INDIRECT: {
                auto* c = (const xef_mtl_dispatch_indirect*)d;
                Buffer* b = buffer(c->buffer);
                if (!cp || !b) break;
                uint32_t tg[3] = {std::max(1u, c->threads[0]), std::max(1u, c->threads[1]), std::max(1u, c->threads[2])};
                ComputeVariant* v = compute_variant(cp, tg, tg_mem, err);
                if (!v) break;
                if (v->pipe != bound_pipe) { vk.CmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, v->pipe); bound_pipe = v->pipe; }
                if (barrier_pending) barrier();
                PushConstants pc{};
                pc.table[0] = build_table(st[XEF_MTL_STAGE_KERNEL], v->cs);
                pc.grid[0] = pc.grid[1] = pc.grid[2] = 0x7fffffff;
                vk.CmdPushConstants(cb, g.pipe_layout, VK_SHADER_STAGE_ALL, 0, sizeof(pc), &pc);
                vk.CmdDispatchIndirect(cb, b->buf, c->offset);
                barrier_pending = true;
                break;
            }
            case XEF_MTL_CMD_MEMORY_BARRIER: barrier(); break;
            case XEF_MTL_CMD_COPY_BUFFER: {
                auto* c = (const xef_mtl_copy_buffer*)d;
                Buffer* s = buffer(c->src);
                Buffer* t = buffer(c->dst);
                if (!s || !t || !c->size) break;
                VkBufferCopy r{c->src_offset, c->dst_offset, c->size};
                vk.CmdCopyBuffer(cb, s->buf, t->buf, 1, &r);
                barrier();
                break;
            }
            case XEF_MTL_CMD_COPY_BUFFER_TO_TEXTURE: copy_buf_tex((const xef_mtl_copy_buf_tex*)d, true); barrier(); break;
            case XEF_MTL_CMD_COPY_TEXTURE_TO_BUFFER: copy_buf_tex((const xef_mtl_copy_buf_tex*)d, false); barrier(); break;
            case XEF_MTL_CMD_COPY_TEXTURE: copy_texture((const xef_mtl_copy_texture*)d); barrier(); break;
            case XEF_MTL_CMD_FILL_BUFFER: fill_buffer((const xef_mtl_fill_buffer*)d); barrier(); break;
            case XEF_MTL_CMD_GENERATE_MIPMAPS: generate_mipmaps(((const xef_mtl_texture_ref*)d)->texture); barrier(); break;
            case XEF_MTL_CMD_PRESENT: {
                auto* c = (const xef_mtl_present*)d;
                end_encoder();
                present_record(cb, c->layer, c->drawable, presents);
                break;
            }
            case XEF_MTL_CMD_SIGNAL_EVENT: { auto* c = (const xef_mtl_event_op*)d; signals.push_back({c->event, c->value}); break; }
            case XEF_MTL_CMD_WAIT_EVENT: { auto* c = (const xef_mtl_event_op*)d; waits.push_back({c->event, c->value}); break; }
            default: break;
            }
            if (!err.empty()) { XEF_LOG(1, "metal: %s", err.c_str()); err.clear(); }
        }
        end_encoder();
        return true;
    }
};

} // namespace

void retire(Queue* q) {
    uint64_t v = 0;
    vk.GetSemaphoreCounterValue(g.dev, q->timeline, &v);
    q->completed = std::max(q->completed, v);
    while (!q->inflight.empty() && q->inflight.front().seq <= q->completed) {
        Submission& s = q->inflight.front();
        q->free_cbs.push_back(s.cb);
        for (uint32_t k : s.release_drawables) release_drawable(k);
        q->inflight.pop_front();
    }
}

static Queue* queue_of(uint32_t id) { return id < g.queues.size() ? g.queues[id].get() : nullptr; }

uint32_t queue_create() {
    auto q = std::make_unique<Queue>();
    VkCommandPoolCreateInfo pci{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    pci.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    pci.queueFamilyIndex = g.qfamily;
    vk.CreateCommandPool(g.dev, &pci, nullptr, &q->pool);
    VkSemaphoreTypeCreateInfo tci{VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO};
    tci.semaphoreType = VK_SEMAPHORE_TYPE_TIMELINE;
    VkSemaphoreCreateInfo sci{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
    sci.pNext = &tci;
    vk.CreateSemaphore(g.dev, &sci, nullptr, &q->timeline);
    g.queues.push_back(std::move(q));
    return (uint32_t)g.queues.size() - 1;
}

uint64_t commit(uint32_t qid, const uint8_t* stream, uint64_t len) {
    Queue* q = queue_of(qid);
    if (!q) return 0;
    retire(q);
    VkCommandBuffer cb;
    if (!q->free_cbs.empty()) { cb = q->free_cbs.back(); q->free_cbs.pop_back(); vk.ResetCommandBuffer(cb, 0); }
    else {
        VkCommandBufferAllocateInfo ai{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
        ai.commandPool = q->pool;
        ai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        ai.commandBufferCount = 1;
        vk.AllocateCommandBuffers(g.dev, &ai, &cb);
    }
    VkCommandBufferBeginInfo bi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vk.BeginCommandBuffer(cb, &bi);
    auto rec = std::make_unique<Recorder>();
    rec->q = q;
    rec->cb = cb;
    rec->run(stream, len);
    vk.EndCommandBuffer(cb);

    uint64_t seq = q->next_seq++;
    std::vector<VkSemaphore> wait_sems, signal_sems;
    std::vector<uint64_t> wait_vals, signal_vals;
    std::vector<VkPipelineStageFlags> wait_stages;
    for (auto& [ev, val] : rec->waits) {
        if (ev < g.events.size() && g.events[ev]) {
            wait_sems.push_back(g.events[ev]->timeline); wait_vals.push_back(val);
            wait_stages.push_back(VK_PIPELINE_STAGE_ALL_COMMANDS_BIT);
        }
    }
    std::vector<PendingPresent> presents = std::move(rec->presents);
    for (PendingPresent& pp : presents) {
        wait_sems.push_back(pp.acquire);
        wait_vals.push_back(0);
        wait_stages.push_back(VK_PIPELINE_STAGE_ALL_COMMANDS_BIT);
        signal_sems.push_back(pp.present);
        signal_vals.push_back(0);
    }
    signal_sems.push_back(q->timeline);
    signal_vals.push_back(seq);
    for (auto& [ev, val] : rec->signals)
        if (ev < g.events.size() && g.events[ev]) { signal_sems.push_back(g.events[ev]->timeline); signal_vals.push_back(val); }
    VkTimelineSemaphoreSubmitInfo ts{VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO};
    ts.waitSemaphoreValueCount = (uint32_t)wait_vals.size();
    ts.pWaitSemaphoreValues = wait_vals.data();
    ts.signalSemaphoreValueCount = (uint32_t)signal_vals.size();
    ts.pSignalSemaphoreValues = signal_vals.data();
    VkSubmitInfo si{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    si.pNext = &ts;
    si.waitSemaphoreCount = (uint32_t)wait_sems.size();
    si.pWaitSemaphores = wait_sems.data();
    si.pWaitDstStageMask = wait_stages.data();
    si.commandBufferCount = 1;
    si.pCommandBuffers = &cb;
    si.signalSemaphoreCount = (uint32_t)signal_sems.size();
    si.pSignalSemaphores = signal_sems.data();
    VkResult r = vk.QueueSubmit(g.queue, 1, &si, VK_NULL_HANDLE);
    if (r != VK_SUCCESS) XEF_LOG(1, "metal: vkQueueSubmit failed (%d)", (int)r);
    Submission s;
    s.seq = seq;
    s.cb = cb;
    for (PendingPresent& pp : presents) s.release_drawables.push_back((pp.layer_id << 16) | pp.drawable);
    q->inflight.push_back(std::move(s));
    if (!presents.empty()) present_after_submit(presents);
    return seq;
}

uint64_t wait_queue(uint32_t qid, uint64_t seq, int64_t timeout_ns) {
    VkSemaphore sem;
    {
        std::lock_guard<std::recursive_mutex> lk(g.mtx);
        Queue* q = queue_of(qid);
        if (!q) return 0;
        retire(q);
        if (q->completed >= seq) return q->completed;
        sem = q->timeline;
    }
    VkSemaphoreWaitInfo wi{VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO};
    wi.semaphoreCount = 1;
    wi.pSemaphores = &sem;
    wi.pValues = &seq;
    vk.WaitSemaphores(g.dev, &wi, timeout_ns < 0 ? UINT64_MAX : (uint64_t)timeout_ns);
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    Queue* q = queue_of(qid);
    retire(q);
    return q->completed;
}

} // namespace xef::mtl
