// Render and compute pipeline states.
#include "mtl_engine.h"
#include "common/common.h"
#include <cstring>

namespace xef::mtl {

using namespace mtlabi;

static Library* library(uint32_t id) { return id < g.libraries.size() ? g.libraries[id].get() : nullptr; }

// parses the guest constant blob: { u32 index, u32 type, u32 size, u32 name_len, name (pad 4), value (pad 4) }*
static void parse_constants(const void* blob, uint32_t size, std::vector<FnConstant>& out) {
    const uint8_t* p = (const uint8_t*)blob;
    const uint8_t* end = p + size;
    while (p && p + 16 <= end) {
        uint32_t h[4];
        memcpy(h, p, 16);
        p += 16;
        FnConstant c;
        c.index = h[0];
        c.type = h[1];
        uint32_t nl = h[3], vs = h[2];
        if (p + ((nl + 3) & ~3u) + ((vs + 3) & ~3u) > end) break;
        c.name.assign((const char*)p, nl);
        p += (nl + 3) & ~3u;
        c.value.assign(p, p + vs);
        p += (vs + 3) & ~3u;
        out.push_back(std::move(c));
    }
}

bool function_source(const xef_mtl_function_ref& ref, uint32_t stage, CompileRequest& req, std::string& err) {
    Library* lib = library(ref.library);
    if (!lib || !ref.name) { err = "invalid library"; return false; }
    for (const metallib::Function& f : lib->fns) {
        if (f.name != ref.name) continue;
        if (!f.bitcode) { err = "function has no bitcode"; return false; }
        StageSource s;
        s.stage = stage;
        s.function = f.name;
        s.bitcode.assign(f.bitcode, f.bitcode + f.bitcode_size);
        if (ref.constants && ref.constants_size) parse_constants(ref.constants, ref.constants_size, s.constants);
        req.stages.push_back(std::move(s));
        return true;
    }
    err = std::string("function '") + ref.name + "' not found";
    return false;
}

static VkBlendFactor blend_factor(uint32_t f) {
    static const VkBlendFactor t[] = {
        VK_BLEND_FACTOR_ZERO, VK_BLEND_FACTOR_ONE, VK_BLEND_FACTOR_SRC_COLOR, VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR,
        VK_BLEND_FACTOR_SRC_ALPHA, VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA, VK_BLEND_FACTOR_DST_COLOR, VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR,
        VK_BLEND_FACTOR_DST_ALPHA, VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA, VK_BLEND_FACTOR_SRC_ALPHA_SATURATE,
        VK_BLEND_FACTOR_CONSTANT_COLOR, VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_COLOR, VK_BLEND_FACTOR_CONSTANT_ALPHA,
        VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_ALPHA, VK_BLEND_FACTOR_SRC1_COLOR, VK_BLEND_FACTOR_ONE_MINUS_SRC1_COLOR,
        VK_BLEND_FACTOR_SRC1_ALPHA, VK_BLEND_FACTOR_ONE_MINUS_SRC1_ALPHA,
    };
    return f < sizeof(t) / sizeof(t[0]) ? t[f] : VK_BLEND_FACTOR_ONE;
}

static VkColorComponentFlags write_mask(uint32_t m) {
    VkColorComponentFlags r = 0;
    if (m & 8) r |= VK_COLOR_COMPONENT_R_BIT;
    if (m & 4) r |= VK_COLOR_COMPONENT_G_BIT;
    if (m & 2) r |= VK_COLOR_COMPONENT_B_BIT;
    if (m & 1) r |= VK_COLOR_COMPONENT_A_BIT;
    return r;
}

static VkPipelineShaderStageCreateInfo stage_info(VkShaderStageFlagBits st, VkShaderModule m) {
    VkPipelineShaderStageCreateInfo s{VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO};
    s.stage = st;
    s.module = m;
    s.pName = "main";
    return s;
}

VkPipeline render_pipeline_for(RenderPipeline* p, uint32_t cls) {
    if (cls > 2) cls = 2;
    if (p->pipes[cls]) return p->pipes[cls];
    const xef_mtl_render_pipeline_desc& d = p->desc;
    VkPipelineShaderStageCreateInfo stages[2] = {stage_info(VK_SHADER_STAGE_VERTEX_BIT, p->vs.mod)};
    uint32_t nstages = 1;
    if (p->has_fs) stages[nstages++] = stage_info(VK_SHADER_STAGE_FRAGMENT_BIT, p->fs.mod);

    // vertex input: one Vulkan binding per Metal buffer index used by the vertex descriptor
    std::vector<VkVertexInputBindingDescription> bindings;
    std::vector<VkVertexInputAttributeDescription> attrs;
    std::vector<VkVertexInputBindingDivisorDescriptionKHR> divisors;
    bool dummy = false;
    std::vector<uint32_t> used_buffers;
    for (const VertexAttrib& va : p->vs.refl.attribs) {
        uint32_t loc = va.location;
        VkFormat vf = VK_FORMAT_UNDEFINED;
        if (d.has_vertex_descriptor && loc < XEF_MTL_MAX_VERTEX_ATTRIBS && d.attribs[loc].format) vf = vertex_format(d.attribs[loc].format);
        if (vf == VK_FORMAT_UNDEFINED) {
            dummy = true;
            VkFormat df = va.base == BT_INT || va.base == BT_SHORT || va.base == BT_CHAR ? VK_FORMAT_R32G32B32A32_SINT
                        : va.base == BT_UINT || va.base == BT_USHORT || va.base == BT_UCHAR || va.base == BT_BOOL ? VK_FORMAT_R32G32B32A32_UINT
                        : VK_FORMAT_R32G32B32A32_SFLOAT;
            attrs.push_back({loc, XEF_MTL_MAX_BUFFERS, df, 0});
            continue;
        }
        uint32_t bi = d.attribs[loc].buffer_index;
        attrs.push_back({loc, bi, vf, d.attribs[loc].offset});
        bool seen = false;
        for (uint32_t u : used_buffers) if (u == bi) seen = true;
        if (!seen) used_buffers.push_back(bi);
    }
    for (uint32_t bi : used_buffers) {
        const xef_mtl_vertex_layout& l = d.layouts[bi < XEF_MTL_MAX_BUFFERS ? bi : 0];
        VkVertexInputBindingDescription b{bi, l.stride, VK_VERTEX_INPUT_RATE_VERTEX};
        if (l.step_function == 0) {   // constant
            b.inputRate = VK_VERTEX_INPUT_RATE_INSTANCE;
            divisors.push_back({bi, 0});
        } else if (l.step_function == 2) {
            b.inputRate = VK_VERTEX_INPUT_RATE_INSTANCE;
            if (l.step_rate != 1) divisors.push_back({bi, l.step_rate});
        }
        bindings.push_back(b);
    }
    if (dummy) bindings.push_back({XEF_MTL_MAX_BUFFERS, 0, VK_VERTEX_INPUT_RATE_VERTEX});
    p->vertex_bindings = used_buffers;
    p->needs_dummy_binding = dummy;
    VkPipelineVertexInputDivisorStateCreateInfoKHR div{VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_DIVISOR_STATE_CREATE_INFO_KHR};
    div.vertexBindingDivisorCount = (uint32_t)divisors.size();
    div.pVertexBindingDivisors = divisors.data();
    VkPipelineVertexInputStateCreateInfo vi{VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
    vi.pNext = divisors.empty() ? nullptr : &div;
    vi.vertexBindingDescriptionCount = (uint32_t)bindings.size();
    vi.pVertexBindingDescriptions = bindings.data();
    vi.vertexAttributeDescriptionCount = (uint32_t)attrs.size();
    vi.pVertexAttributeDescriptions = attrs.data();

    VkPipelineInputAssemblyStateCreateInfo ia{VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO};
    ia.topology = cls == 0 ? VK_PRIMITIVE_TOPOLOGY_POINT_LIST : cls == 1 ? VK_PRIMITIVE_TOPOLOGY_LINE_LIST : VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    VkPipelineViewportStateCreateInfo vp{VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO};
    vp.viewportCount = 1;
    vp.scissorCount = 1;
    VkPipelineRasterizationStateCreateInfo rs{VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO};
    rs.polygonMode = VK_POLYGON_MODE_FILL;
    rs.lineWidth = 1.0f;
    rs.rasterizerDiscardEnable = d.rasterization_enabled ? VK_FALSE : VK_TRUE;
    VkPipelineMultisampleStateCreateInfo ms{VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO};
    ms.rasterizationSamples = (VkSampleCountFlagBits)std::max(1u, d.sample_count);
    ms.alphaToCoverageEnable = d.alpha_to_coverage ? VK_TRUE : VK_FALSE;
    ms.alphaToOneEnable = VK_FALSE;
    VkPipelineDepthStencilStateCreateInfo ds{VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO};
    ds.depthTestEnable = p->vk_depth != VK_FORMAT_UNDEFINED;
    ds.depthCompareOp = VK_COMPARE_OP_ALWAYS;
    ds.minDepthBounds = 0;
    ds.maxDepthBounds = 1;
    VkPipelineColorBlendAttachmentState cbs[XEF_MTL_MAX_COLOR] = {};
    uint32_t ncolor = 0;
    for (uint32_t i = 0; i < XEF_MTL_MAX_COLOR; i++) if (p->vk_colors[i] != VK_FORMAT_UNDEFINED) ncolor = i + 1;
    for (uint32_t i = 0; i < ncolor; i++) {
        const xef_mtl_color_attachment& c = d.colors[i];
        VkPipelineColorBlendAttachmentState& b = cbs[i];
        b.colorWriteMask = write_mask(c.write_mask);
        b.blendEnable = c.blending ? VK_TRUE : VK_FALSE;
        b.srcColorBlendFactor = blend_factor(c.src_rgb);
        b.dstColorBlendFactor = blend_factor(c.dst_rgb);
        b.colorBlendOp = (VkBlendOp)c.rgb_op;
        b.srcAlphaBlendFactor = blend_factor(c.src_alpha);
        b.dstAlphaBlendFactor = blend_factor(c.dst_alpha);
        b.alphaBlendOp = (VkBlendOp)c.alpha_op;
        // fragment shaders that do not write this target: keep the attachment untouched
        bool written = false;
        for (const ColorOutput& co : p->fs.refl.colors) if (co.location == i) written = true;
        if (!written && p->has_fs) b.colorWriteMask = 0;
    }
    VkPipelineColorBlendStateCreateInfo cb{VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};
    cb.attachmentCount = ncolor;
    cb.pAttachments = cbs;
    std::vector<VkDynamicState> dyn = {
        VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR, VK_DYNAMIC_STATE_CULL_MODE, VK_DYNAMIC_STATE_FRONT_FACE,
        VK_DYNAMIC_STATE_PRIMITIVE_TOPOLOGY, VK_DYNAMIC_STATE_PRIMITIVE_RESTART_ENABLE, VK_DYNAMIC_STATE_DEPTH_TEST_ENABLE,
        VK_DYNAMIC_STATE_DEPTH_WRITE_ENABLE, VK_DYNAMIC_STATE_DEPTH_COMPARE_OP, VK_DYNAMIC_STATE_STENCIL_TEST_ENABLE,
        VK_DYNAMIC_STATE_STENCIL_OP, VK_DYNAMIC_STATE_STENCIL_COMPARE_MASK, VK_DYNAMIC_STATE_STENCIL_WRITE_MASK,
        VK_DYNAMIC_STATE_STENCIL_REFERENCE, VK_DYNAMIC_STATE_DEPTH_BIAS, VK_DYNAMIC_STATE_DEPTH_BIAS_ENABLE,
        VK_DYNAMIC_STATE_BLEND_CONSTANTS,
    };
    if (g.has_eds3_polygon) dyn.push_back(VK_DYNAMIC_STATE_POLYGON_MODE_EXT);
    if (g.has_eds3_clamp) dyn.push_back(VK_DYNAMIC_STATE_DEPTH_CLAMP_ENABLE_EXT);
    VkPipelineDynamicStateCreateInfo dy{VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO};
    dy.dynamicStateCount = (uint32_t)dyn.size();
    dy.pDynamicStates = dyn.data();
    VkPipelineRenderingCreateInfo ri{VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO};
    ri.colorAttachmentCount = ncolor;
    ri.pColorAttachmentFormats = p->vk_colors;
    ri.depthAttachmentFormat = p->vk_depth;
    ri.stencilAttachmentFormat = p->vk_stencil;
    VkGraphicsPipelineCreateInfo gci{VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO};
    gci.pNext = &ri;
    gci.stageCount = nstages;
    gci.pStages = stages;
    gci.pVertexInputState = &vi;
    gci.pInputAssemblyState = &ia;
    gci.pViewportState = &vp;
    gci.pRasterizationState = &rs;
    gci.pMultisampleState = &ms;
    gci.pDepthStencilState = &ds;
    gci.pColorBlendState = &cb;
    gci.pDynamicState = &dy;
    gci.layout = g.pipe_layout;
    VkPipeline pipe = VK_NULL_HANDLE;
    VkResult r = vk.CreateGraphicsPipelines(g.dev, g.pipe_cache, 1, &gci, nullptr, &pipe);
    if (r != VK_SUCCESS) { XEF_LOG(1, "metal: vkCreateGraphicsPipelines failed (%d)", (int)r); return VK_NULL_HANDLE; }
    p->pipes[cls] = pipe;
    return pipe;
}

uint32_t create_render_pipeline(const xef_mtl_render_pipeline_desc* d, std::string& err) {
    CompileRequest req;
    if (!function_source(d->vertex, STAGE_VERTEX, req, err)) return 0;
    bool has_fs = d->fragment.library && d->rasterization_enabled;
    if (has_fs && !function_source(d->fragment, STAGE_FRAGMENT, req, err)) return 0;
    if (!d->rasterization_enabled) req.flags |= REQ_RASTER_DISABLED;
    if (getenv("XEF_MTL_VALIDATE_SPIRV")) req.flags |= REQ_VALIDATE;
    CompileResult res;
    if (!compile_shaders(req, res)) { err = res.log; return 0; }
    auto p = std::make_unique<RenderPipeline>();
    p->desc = *d;
    p->desc.vertex.name = nullptr; p->desc.vertex.constants = nullptr;
    p->desc.fragment.name = nullptr; p->desc.fragment.constants = nullptr;
    p->has_fs = has_fs;
    for (auto& s : res.stages) {
        StageModule& m = s.stage == STAGE_FRAGMENT ? p->fs : p->vs;
        if (!make_stage(s, m, err)) return 0;
    }
    for (uint32_t i = 0; i < XEF_MTL_MAX_COLOR; i++) {
        const PixelFormatInfo* f = d->colors[i].pixel_format ? pixel_format(d->colors[i].pixel_format) : nullptr;
        p->vk_colors[i] = f ? f->vk : VK_FORMAT_UNDEFINED;
        p->color_formats[i] = d->colors[i].pixel_format;
    }
    if (const PixelFormatInfo* f = d->depth_format ? pixel_format(d->depth_format) : nullptr)
        if (f->flags & FMT_DEPTH) p->vk_depth = resolve_depth_format(g.pd, f->vk);
    if (const PixelFormatInfo* f = d->stencil_format ? pixel_format(d->stencil_format) : nullptr)
        if (f->flags & FMT_STENCIL) p->vk_stencil = resolve_depth_format(g.pd, f->vk);
    if (p->vk_depth != VK_FORMAT_UNDEFINED && p->vk_stencil != VK_FORMAT_UNDEFINED && p->vk_depth != p->vk_stencil) p->vk_stencil = p->vk_depth;
    if (p->vk_stencil != VK_FORMAT_UNDEFINED && p->vk_depth == VK_FORMAT_UNDEFINED &&
        (p->vk_stencil == VK_FORMAT_D32_SFLOAT_S8_UINT || p->vk_stencil == VK_FORMAT_D24_UNORM_S8_UINT)) p->vk_depth = p->vk_stencil;
    uint32_t cls = d->input_topology == 1 ? 0 : d->input_topology == 2 ? 1 : 2;
    if (!render_pipeline_for(p.get(), cls)) { err = "Vulkan pipeline creation failed"; return 0; }
    auto pp = std::make_unique<Pipeline>();
    pp->render = std::move(p);
    for (size_t i = 1; i < g.pipelines.size(); i++)
        if (!g.pipelines[i]) { g.pipelines[i] = std::move(pp); return (uint32_t)i; }
    g.pipelines.push_back(std::move(pp));
    return (uint32_t)g.pipelines.size() - 1;
}

ComputeVariant* compute_variant(ComputePipeline* p, const uint32_t tg[3], const std::vector<uint32_t>& tg_mem, std::string& err) {
    std::vector<uint32_t> key{tg[0], tg[1], tg[2]};
    key.insert(key.end(), tg_mem.begin(), tg_mem.end());
    auto it = p->variants.find(key);
    if (it != p->variants.end()) return it->second.get();
    CompileRequest req = p->req;
    memcpy(req.tg_size, tg, sizeof(req.tg_size));
    req.tg_mem = tg_mem;
    CompileResult res;
    if (!compile_shaders(req, res)) { err = res.log; return nullptr; }
    auto v = std::make_unique<ComputeVariant>();
    if (!make_stage(res.stages[0], v->cs, err)) return nullptr;
    VkComputePipelineCreateInfo ci{VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO};
    ci.stage = stage_info(VK_SHADER_STAGE_COMPUTE_BIT, v->cs.mod);
    VkPipelineShaderStageRequiredSubgroupSizeCreateInfo rss{VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_REQUIRED_SUBGROUP_SIZE_CREATE_INFO};
    rss.requiredSubgroupSize = 32;
    uint32_t threads = tg[0] * tg[1] * tg[2];
    if (g.has_subgroup_size_control && g.subgroup_size != 32 && threads % 32 == 0) {
        ci.stage.pNext = &rss;
        ci.stage.flags |= VK_PIPELINE_SHADER_STAGE_CREATE_REQUIRE_FULL_SUBGROUPS_BIT;
    }
    ci.layout = g.pipe_layout;
    VkResult r = vk.CreateComputePipelines(g.dev, g.pipe_cache, 1, &ci, nullptr, &v->pipe);
    if (r != VK_SUCCESS) { err = "vkCreateComputePipelines failed"; return nullptr; }
    ComputeVariant* raw = v.get();
    p->variants[key] = std::move(v);
    return raw;
}

uint32_t create_compute_pipeline(const xef_mtl_compute_pipeline_desc* d, xef_mtl_pipeline_info* info, std::string& err) {
    auto p = std::make_unique<ComputePipeline>();
    if (!function_source(d->function, STAGE_KERNEL, p->req, err)) return 0;
    if (getenv("XEF_MTL_VALIDATE_SPIRV")) p->req.flags |= REQ_VALIDATE;
    p->max_threads = d->max_total_threads ? std::min(d->max_total_threads, g.max_tg_threads) : g.max_tg_threads;
    uint32_t tg[3] = {32, 1, 1};
    ComputeVariant* v = compute_variant(p.get(), tg, {}, err);
    if (!v) return 0;
    if (info) {
        info->max_total_threads = p->max_threads;
        info->execution_width = 32;
        info->static_threadgroup_memory = v->cs.refl.tg_mem_size;
    }
    auto pp = std::make_unique<Pipeline>();
    pp->compute = std::move(p);
    for (size_t i = 1; i < g.pipelines.size(); i++)
        if (!g.pipelines[i]) { g.pipelines[i] = std::move(pp); return (uint32_t)i; }
    g.pipelines.push_back(std::move(pp));
    return (uint32_t)g.pipelines.size() - 1;
}

} // namespace xef::mtl
