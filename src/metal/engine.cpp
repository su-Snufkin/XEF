// Device setup and resources of the Metal -> Vulkan engine.
#include "mtl_engine.h"
#include "common/common.h"
#include <cstring>
#include <sys/mman.h>
#include <sys/stat.h>

namespace xef::mtl {

using namespace mtlabi;

Engine g;

static bool has_ext(const std::vector<VkExtensionProperties>& exts, const char* n) {
    for (auto& e : exts) if (!strcmp(e.extensionName, n)) return true;
    return false;
}

uint32_t find_memory_type(uint32_t bits, VkMemoryPropertyFlags want, VkMemoryPropertyFlags avoid) {
    for (uint32_t i = 0; i < g.memprops.memoryTypeCount; i++)
        if ((bits & (1u << i)) && (g.memprops.memoryTypes[i].propertyFlags & want) == want && !(g.memprops.memoryTypes[i].propertyFlags & avoid))
            return i;
    if (avoid) return find_memory_type(bits, want, 0);
    return ~0u;
}

VkDeviceMemory alloc_memory(VkMemoryRequirements req, VkMemoryPropertyFlags want, bool device_address, VkMemoryPropertyFlags avoid) {
    uint32_t type = find_memory_type(req.memoryTypeBits, want, avoid);
    if (type == ~0u) type = find_memory_type(req.memoryTypeBits, want & ~VK_MEMORY_PROPERTY_HOST_CACHED_BIT, avoid);
    if (type == ~0u) return VK_NULL_HANDLE;
    VkMemoryAllocateFlagsInfo fi{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_FLAGS_INFO};
    fi.flags = VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT;
    VkMemoryAllocateInfo ai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    ai.pNext = device_address ? &fi : nullptr;
    ai.allocationSize = req.size;
    ai.memoryTypeIndex = type;
    VkDeviceMemory mem = VK_NULL_HANDLE;
    if (vk.AllocateMemory(g.dev, &ai, nullptr, &mem) != VK_SUCCESS) return VK_NULL_HANDLE;
    return mem;
}

Buffer* buffer(uint32_t id) { return id < g.buffers.size() ? g.buffers[id].get() : nullptr; }
Texture* texture(uint32_t id) { return id < g.textures.size() ? g.textures[id].get() : nullptr; }
Sampler* sampler(uint32_t id) { return id < g.samplers.size() ? g.samplers[id].get() : nullptr; }
Texture* texture_root(Texture* t) {
    while (t && t->parent) t = texture(t->parent);
    return t;
}

template <class T> static uint32_t add_object(std::vector<std::unique_ptr<T>>& v, std::unique_ptr<T> o) {
    for (size_t i = 1; i < v.size(); i++)
        if (!v[i]) { v[i] = std::move(o); return (uint32_t)i; }
    v.push_back(std::move(o));
    return (uint32_t)v.size() - 1;
}

// ---------------- init ----------------

bool engine_init() {
    if (g.ok) return true;
    std::lock_guard<std::recursive_mutex> lk(g.mtx);
    if (g.ok) return true;
    if (!vk_load_global()) { XEF_LOG(1, "metal: libvulkan not found"); return false; }
    uint32_t n = 0;
    vk.EnumerateInstanceExtensionProperties(nullptr, &n, nullptr);
    std::vector<VkExtensionProperties> iexts(n);
    vk.EnumerateInstanceExtensionProperties(nullptr, &n, iexts.data());
    std::vector<const char*> ie;
    if (has_ext(iexts, VK_KHR_SURFACE_EXTENSION_NAME) && has_ext(iexts, VK_KHR_XLIB_SURFACE_EXTENSION_NAME)) {
        ie.push_back(VK_KHR_SURFACE_EXTENSION_NAME);
        ie.push_back(VK_KHR_XLIB_SURFACE_EXTENSION_NAME);
        g.has_xlib_surface = true;
    }
    VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
    app.pApplicationName = "xef-osx Metal";
    app.pEngineName = "xef-mtl";
    app.apiVersion = VK_API_VERSION_1_3;
    VkInstanceCreateInfo ici{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    ici.pApplicationInfo = &app;
    ici.enabledExtensionCount = (uint32_t)ie.size();
    ici.ppEnabledExtensionNames = ie.data();
    std::vector<const char*> layers;
    if (getenv("XEF_MTL_VALIDATION")) layers.push_back("VK_LAYER_KHRONOS_validation");
    ici.enabledLayerCount = (uint32_t)layers.size();
    ici.ppEnabledLayerNames = layers.data();
    if (vk.CreateInstance(&ici, nullptr, &g.instance) != VK_SUCCESS) { XEF_LOG(1, "metal: vkCreateInstance failed"); return false; }
    vk_load_instance(g.instance);

    // pick a device: XEF_MTL_DEVICE=<substring> or prefer discrete GPUs
    vk.EnumeratePhysicalDevices(g.instance, &n, nullptr);
    std::vector<VkPhysicalDevice> pds(n);
    vk.EnumeratePhysicalDevices(g.instance, &n, pds.data());
    const char* want = getenv("XEF_MTL_DEVICE");
    int best = -1, best_score = -1;
    for (uint32_t i = 0; i < n; i++) {
        VkPhysicalDeviceProperties p;
        vk.GetPhysicalDeviceProperties(pds[i], &p);
        if (p.apiVersion < VK_API_VERSION_1_3) continue;
        int score = p.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU ? 3 : p.deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU ? 2 : 1;
        if (want && strstr(p.deviceName, want)) score = 100;
        if (score > best_score) { best = (int)i; best_score = score; }
    }
    if (best < 0) { XEF_LOG(1, "metal: no Vulkan 1.3 device"); return false; }
    g.pd = pds[best];
    vk.GetPhysicalDeviceProperties(g.pd, &g.props);
    vk.GetPhysicalDeviceMemoryProperties(g.pd, &g.memprops);
    g.device_name = g.props.deviceName;

    vk.EnumerateDeviceExtensionProperties(g.pd, nullptr, &n, nullptr);
    std::vector<VkExtensionProperties> dexts(n);
    vk.EnumerateDeviceExtensionProperties(g.pd, nullptr, &n, dexts.data());

    // features
    VkPhysicalDeviceVulkan11Features f11{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES};
    VkPhysicalDeviceVulkan12Features f12{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES};
    VkPhysicalDeviceVulkan13Features f13{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES};
    VkPhysicalDeviceExtendedDynamicState3FeaturesEXT eds3{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_3_FEATURES_EXT};
    VkPhysicalDeviceShaderAtomicFloatFeaturesEXT af{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_ATOMIC_FLOAT_FEATURES_EXT};
    VkPhysicalDeviceVertexAttributeDivisorFeaturesKHR vad{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VERTEX_ATTRIBUTE_DIVISOR_FEATURES_KHR};
    VkPhysicalDeviceRobustness2FeaturesEXT rob{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT};
    VkPhysicalDeviceFeatures2 f2{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2};
    f2.pNext = &f11; f11.pNext = &f12; f12.pNext = &f13;
    void** tail = &f13.pNext;
    bool want_eds3 = has_ext(dexts, VK_EXT_EXTENDED_DYNAMIC_STATE_3_EXTENSION_NAME);
    bool want_af = has_ext(dexts, VK_EXT_SHADER_ATOMIC_FLOAT_EXTENSION_NAME);
    bool want_vad = has_ext(dexts, VK_KHR_VERTEX_ATTRIBUTE_DIVISOR_EXTENSION_NAME);
    bool want_rob = has_ext(dexts, VK_EXT_ROBUSTNESS_2_EXTENSION_NAME);
    if (want_eds3) { *tail = &eds3; tail = &eds3.pNext; }
    if (want_af) { *tail = &af; tail = &af.pNext; }
    if (want_vad) { *tail = &vad; tail = &vad.pNext; }
    if (want_rob) { *tail = &rob; tail = &rob.pNext; }
    vk.GetPhysicalDeviceFeatures2(g.pd, &f2);
    if (!f12.bufferDeviceAddress || !f12.descriptorIndexing || !f12.runtimeDescriptorArray || !f12.timelineSemaphore ||
        !f13.dynamicRendering || !f13.synchronization2) {
        XEF_LOG(1, "metal: %s lacks required Vulkan 1.2/1.3 features", g.props.deviceName);
        return false;
    }
    // enable what we use
    VkPhysicalDeviceFeatures2 e2{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2};
    VkPhysicalDeviceFeatures& ef = e2.features;
    const VkPhysicalDeviceFeatures& af0 = f2.features;
    ef.independentBlend = af0.independentBlend;
    ef.dualSrcBlend = af0.dualSrcBlend;
    ef.fillModeNonSolid = af0.fillModeNonSolid;
    ef.depthClamp = af0.depthClamp;
    ef.depthBiasClamp = af0.depthBiasClamp;
    ef.samplerAnisotropy = af0.samplerAnisotropy;
    ef.textureCompressionBC = af0.textureCompressionBC;
    ef.textureCompressionETC2 = af0.textureCompressionETC2;
    ef.textureCompressionASTC_LDR = af0.textureCompressionASTC_LDR;
    ef.imageCubeArray = af0.imageCubeArray;
    ef.sampleRateShading = af0.sampleRateShading;
    ef.shaderInt64 = af0.shaderInt64;
    ef.shaderInt16 = af0.shaderInt16;
    ef.shaderFloat64 = af0.shaderFloat64;
    ef.shaderClipDistance = af0.shaderClipDistance;
    ef.shaderImageGatherExtended = af0.shaderImageGatherExtended;
    ef.shaderStorageImageWriteWithoutFormat = af0.shaderStorageImageWriteWithoutFormat;
    ef.shaderStorageImageReadWithoutFormat = af0.shaderStorageImageReadWithoutFormat;
    ef.shaderStorageImageMultisample = af0.shaderStorageImageMultisample;
    ef.vertexPipelineStoresAndAtomics = af0.vertexPipelineStoresAndAtomics;
    ef.fragmentStoresAndAtomics = af0.fragmentStoresAndAtomics;
    ef.multiDrawIndirect = af0.multiDrawIndirect;
    ef.drawIndirectFirstInstance = af0.drawIndirectFirstInstance;
    ef.largePoints = af0.largePoints;
    ef.wideLines = af0.wideLines;
    ef.geometryShader = af0.geometryShader;   // gl_PrimitiveID / Layer in fragment shaders
    ef.multiViewport = af0.multiViewport;
    ef.depthBounds = af0.depthBounds;
    ef.occlusionQueryPrecise = af0.occlusionQueryPrecise;
    ef.shaderResourceMinLod = af0.shaderResourceMinLod;
    ef.robustBufferAccess = VK_FALSE;
    g.has_fill_mode_non_solid = af0.fillModeNonSolid;
    VkPhysicalDeviceVulkan11Features e11{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES};
    e11.storageBuffer16BitAccess = f11.storageBuffer16BitAccess;
    e11.uniformAndStorageBuffer16BitAccess = f11.uniformAndStorageBuffer16BitAccess;
    e11.shaderDrawParameters = f11.shaderDrawParameters;
    VkPhysicalDeviceVulkan12Features e12{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES};
    e12.bufferDeviceAddress = VK_TRUE;
    e12.descriptorIndexing = VK_TRUE;
    e12.runtimeDescriptorArray = VK_TRUE;
    e12.descriptorBindingPartiallyBound = VK_TRUE;
    e12.descriptorBindingUpdateUnusedWhilePending = f12.descriptorBindingUpdateUnusedWhilePending;
    e12.descriptorBindingSampledImageUpdateAfterBind = f12.descriptorBindingSampledImageUpdateAfterBind;
    e12.descriptorBindingStorageImageUpdateAfterBind = f12.descriptorBindingStorageImageUpdateAfterBind;
    e12.descriptorBindingUniformTexelBufferUpdateAfterBind = f12.descriptorBindingUniformTexelBufferUpdateAfterBind;
    e12.descriptorBindingStorageTexelBufferUpdateAfterBind = f12.descriptorBindingStorageTexelBufferUpdateAfterBind;
    e12.shaderSampledImageArrayNonUniformIndexing = f12.shaderSampledImageArrayNonUniformIndexing;
    e12.shaderStorageImageArrayNonUniformIndexing = f12.shaderStorageImageArrayNonUniformIndexing;
    e12.shaderUniformTexelBufferArrayNonUniformIndexing = f12.shaderUniformTexelBufferArrayNonUniformIndexing;
    e12.shaderStorageTexelBufferArrayNonUniformIndexing = f12.shaderStorageTexelBufferArrayNonUniformIndexing;
    e12.timelineSemaphore = VK_TRUE;
    e12.storageBuffer8BitAccess = f12.storageBuffer8BitAccess;
    e12.uniformAndStorageBuffer8BitAccess = f12.uniformAndStorageBuffer8BitAccess;
    e12.shaderInt8 = f12.shaderInt8;
    e12.shaderFloat16 = f12.shaderFloat16;
    e12.scalarBlockLayout = f12.scalarBlockLayout;
    e12.hostQueryReset = f12.hostQueryReset;
    e12.shaderSubgroupExtendedTypes = f12.shaderSubgroupExtendedTypes;
    e12.samplerMirrorClampToEdge = f12.samplerMirrorClampToEdge;
    e12.drawIndirectCount = f12.drawIndirectCount;
    e12.vulkanMemoryModel = f12.vulkanMemoryModel;
    e12.vulkanMemoryModelDeviceScope = f12.vulkanMemoryModelDeviceScope;
    VkPhysicalDeviceVulkan13Features e13{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES};
    e13.dynamicRendering = VK_TRUE;
    e13.synchronization2 = VK_TRUE;
    e13.shaderDemoteToHelperInvocation = f13.shaderDemoteToHelperInvocation;
    e13.subgroupSizeControl = f13.subgroupSizeControl;
    e13.computeFullSubgroups = f13.computeFullSubgroups;
    e13.maintenance4 = f13.maintenance4;
    e13.robustImageAccess = VK_FALSE;
    e13.shaderIntegerDotProduct = f13.shaderIntegerDotProduct;
    g.has_subgroup_size_control = f13.subgroupSizeControl && f13.computeFullSubgroups;
    e2.pNext = &e11; e11.pNext = &e12; e12.pNext = &e13;
    tail = &e13.pNext;
    std::vector<const char*> de;
    if (has_ext(dexts, VK_KHR_SWAPCHAIN_EXTENSION_NAME)) de.push_back(VK_KHR_SWAPCHAIN_EXTENSION_NAME);
    VkPhysicalDeviceExtendedDynamicState3FeaturesEXT ee3{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_3_FEATURES_EXT};
    if (want_eds3 && (eds3.extendedDynamicState3PolygonMode || eds3.extendedDynamicState3DepthClampEnable)) {
        de.push_back(VK_EXT_EXTENDED_DYNAMIC_STATE_3_EXTENSION_NAME);
        ee3.extendedDynamicState3PolygonMode = eds3.extendedDynamicState3PolygonMode;
        ee3.extendedDynamicState3DepthClampEnable = eds3.extendedDynamicState3DepthClampEnable;
        g.has_eds3_polygon = eds3.extendedDynamicState3PolygonMode;
        g.has_eds3_clamp = eds3.extendedDynamicState3DepthClampEnable;
        *tail = &ee3; tail = &ee3.pNext;
    }
    VkPhysicalDeviceShaderAtomicFloatFeaturesEXT eaf{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_ATOMIC_FLOAT_FEATURES_EXT};
    if (want_af) {
        de.push_back(VK_EXT_SHADER_ATOMIC_FLOAT_EXTENSION_NAME);
        eaf.shaderBufferFloat32AtomicAdd = af.shaderBufferFloat32AtomicAdd;
        eaf.shaderBufferFloat32Atomics = af.shaderBufferFloat32Atomics;
        eaf.shaderSharedFloat32AtomicAdd = af.shaderSharedFloat32AtomicAdd;
        eaf.shaderSharedFloat32Atomics = af.shaderSharedFloat32Atomics;
        *tail = &eaf; tail = &eaf.pNext;
    }
    VkPhysicalDeviceVertexAttributeDivisorFeaturesKHR evad{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VERTEX_ATTRIBUTE_DIVISOR_FEATURES_KHR};
    if (want_vad) {
        de.push_back(VK_KHR_VERTEX_ATTRIBUTE_DIVISOR_EXTENSION_NAME);
        evad.vertexAttributeInstanceRateDivisor = vad.vertexAttributeInstanceRateDivisor;
        evad.vertexAttributeInstanceRateZeroDivisor = vad.vertexAttributeInstanceRateZeroDivisor;
        *tail = &evad; tail = &evad.pNext;
    }
    VkPhysicalDeviceRobustness2FeaturesEXT erob{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT};
    if (want_rob && rob.nullDescriptor) {
        de.push_back(VK_EXT_ROBUSTNESS_2_EXTENSION_NAME);
        erob.nullDescriptor = VK_TRUE;
        *tail = &erob; tail = &erob.pNext;
    }
    if (has_ext(dexts, VK_EXT_EXTERNAL_MEMORY_HOST_EXTENSION_NAME)) {
        de.push_back(VK_EXT_EXTERNAL_MEMORY_HOST_EXTENSION_NAME);
        g.has_host_import = true;
        VkPhysicalDeviceExternalMemoryHostPropertiesEXT hp{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTERNAL_MEMORY_HOST_PROPERTIES_EXT};
        VkPhysicalDeviceProperties2 p2{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2};
        p2.pNext = &hp;
        vk.GetPhysicalDeviceProperties2(g.pd, &p2);
        g.host_import_align = hp.minImportedHostPointerAlignment;
    }
    for (const char* e : {VK_EXT_SHADER_STENCIL_EXPORT_EXTENSION_NAME, VK_KHR_FRAGMENT_SHADER_BARYCENTRIC_EXTENSION_NAME,
                          VK_EXT_SHADER_ATOMIC_FLOAT_2_EXTENSION_NAME})
        if (has_ext(dexts, e)) de.push_back(e);
    {
        VkPhysicalDeviceSubgroupProperties sp{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SUBGROUP_PROPERTIES};
        VkPhysicalDeviceProperties2 p2{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2};
        p2.pNext = &sp;
        vk.GetPhysicalDeviceProperties2(g.pd, &p2);
        g.subgroup_size = sp.subgroupSize;
    }
    // queue
    vk.GetPhysicalDeviceQueueFamilyProperties(g.pd, &n, nullptr);
    std::vector<VkQueueFamilyProperties> qf(n);
    vk.GetPhysicalDeviceQueueFamilyProperties(g.pd, &n, qf.data());
    g.qfamily = ~0u;
    for (uint32_t i = 0; i < n; i++)
        if ((qf[i].queueFlags & (VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT)) == (VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT)) { g.qfamily = i; break; }
    if (g.qfamily == ~0u) return false;
    float prio = 1.0f;
    VkDeviceQueueCreateInfo qci{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    qci.queueFamilyIndex = g.qfamily;
    qci.queueCount = 1;
    qci.pQueuePriorities = &prio;
    VkDeviceCreateInfo dci{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    dci.pNext = &e2;
    dci.queueCreateInfoCount = 1;
    dci.pQueueCreateInfos = &qci;
    dci.enabledExtensionCount = (uint32_t)de.size();
    dci.ppEnabledExtensionNames = de.data();
    VkResult r = vk.CreateDevice(g.pd, &dci, nullptr, &g.dev);
    if (r != VK_SUCCESS) { XEF_LOG(1, "metal: vkCreateDevice failed (%d)", (int)r); return false; }
    if (!vk_load_device(g.dev)) return false;
    vk.GetDeviceQueue(g.dev, g.qfamily, 0, &g.queue);
    g.max_tg_threads = std::min<uint32_t>(1024, g.props.limits.maxComputeWorkGroupInvocations);

    // bindless descriptor set
    std::vector<VkDescriptorSetLayoutBinding> b(kNumBindings);
    std::vector<VkDescriptorBindingFlags> bf(kNumBindings, VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT | VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT |
                                                            VK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT);
    if (!e12.descriptorBindingUpdateUnusedWhilePending)
        for (auto& x : bf) x &= ~VK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT;
    for (uint32_t i = 0; i < kNumBindings; i++) {
        b[i].binding = i;
        b[i].stageFlags = VK_SHADER_STAGE_ALL;
        if (i == kSamplerBinding || i == kCompareSamplerBinding) { b[i].descriptorType = VK_DESCRIPTOR_TYPE_SAMPLER; b[i].descriptorCount = kMaxSamplers; continue; }
        bool storage = i >= kNumImageBindings;
        uint32_t dim = (storage ? i - kNumImageBindings : i) / COMP_COUNT;
        if (dim == DIM_BUFFER) b[i].descriptorType = storage ? VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER : VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER;
        else b[i].descriptorType = storage ? VK_DESCRIPTOR_TYPE_STORAGE_IMAGE : VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE;
        b[i].descriptorCount = kMaxTextures;
    }
    VkDescriptorSetLayoutBindingFlagsCreateInfo bfi{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO};
    bfi.bindingCount = kNumBindings;
    bfi.pBindingFlags = bf.data();
    VkDescriptorSetLayoutCreateInfo lci{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    lci.pNext = &bfi;
    lci.flags = VK_DESCRIPTOR_SET_LAYOUT_CREATE_UPDATE_AFTER_BIND_POOL_BIT;
    lci.bindingCount = kNumBindings;
    lci.pBindings = b.data();
    if (vk.CreateDescriptorSetLayout(g.dev, &lci, nullptr, &g.set_layout) != VK_SUCCESS) { XEF_LOG(1, "metal: descriptor set layout failed"); return false; }
    VkDescriptorPoolSize ps[] = {
        {VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, kMaxTextures * (DIM_COUNT - 1) * COMP_COUNT},
        {VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, kMaxTextures * (DIM_COUNT - 1) * COMP_COUNT},
        {VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER, kMaxTextures * COMP_COUNT},
        {VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER, kMaxTextures * COMP_COUNT},
        {VK_DESCRIPTOR_TYPE_SAMPLER, 2 * kMaxSamplers},
    };
    VkDescriptorPoolCreateInfo pci{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
    pci.flags = VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT;
    pci.maxSets = 1;
    pci.poolSizeCount = 5;
    pci.pPoolSizes = ps;
    if (vk.CreateDescriptorPool(g.dev, &pci, nullptr, &g.desc_pool) != VK_SUCCESS) { XEF_LOG(1, "metal: descriptor pool failed"); return false; }
    VkDescriptorSetAllocateInfo dai{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
    dai.descriptorPool = g.desc_pool;
    dai.descriptorSetCount = 1;
    dai.pSetLayouts = &g.set_layout;
    if (vk.AllocateDescriptorSets(g.dev, &dai, &g.set) != VK_SUCCESS) { XEF_LOG(1, "metal: descriptor set failed"); return false; }
    VkPushConstantRange pcr{VK_SHADER_STAGE_ALL, 0, kPushConstantSize};
    VkPipelineLayoutCreateInfo plci{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    plci.setLayoutCount = 1;
    plci.pSetLayouts = &g.set_layout;
    plci.pushConstantRangeCount = 1;
    plci.pPushConstantRanges = &pcr;
    vk.CreatePipelineLayout(g.dev, &plci, nullptr, &g.pipe_layout);

    // Persistent pipeline cache in ~/.cache/xef-mtl/vk_pipeline_cache.bin
    std::string cache_path;
    std::vector<uint8_t> cache_data;
    if (const char* x = getenv("XDG_CACHE_HOME")) cache_path = std::string(x) + "/xef-mtl";
    else if (const char* h = getenv("HOME")) cache_path = std::string(h) + "/.cache/xef-mtl";
    if (!cache_path.empty()) {
        mkdir(cache_path.c_str(), 0755);
        char pcb[128];
        snprintf(pcb, sizeof pcb, "/vk_pipeline_cache_%04x_%04x.bin", g.props.vendorID, g.props.deviceID);
        cache_path += pcb;
        if (FILE* f = fopen(cache_path.c_str(), "rb")) {
            fseek(f, 0, SEEK_END);
            long sz = ftell(f);
            if (sz > 0) {
                fseek(f, 0, SEEK_SET);
                cache_data.resize((size_t)sz);
                if (fread(cache_data.data(), 1, cache_data.size(), f) != cache_data.size())
                    cache_data.clear();
            }
            fclose(f);
        }
    }

    VkPipelineCacheCreateInfo pcci{VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO};
    if (!cache_data.empty()) {
        pcci.initialDataSize = cache_data.size();
        pcci.pInitialData = cache_data.data();
    }
    vk.CreatePipelineCache(g.dev, &pcci, nullptr, &g.pipe_cache);

    static std::string s_cache_path = cache_path;
    static bool s_registered = false;
    if (!s_registered) {
        s_registered = true;
        atexit(save_pipeline_cache);
    }

    g.ok = true;
    // zero vertex data for attributes the vertex descriptor does not provide
    void* m = nullptr;
    g.dummy_buffer = create_buffer_internal(256, true, &m);
    if (m) memset(m, 0, 256);
    XEF_LOG(1, "metal: Vulkan device %s (subgroup %u, host import %d)", g.props.deviceName, g.subgroup_size, (int)g.has_host_import);
    return true;
}

// ---------------- buffers ----------------

static VkBufferUsageFlags kBufferUsage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                                         VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT |
                                         VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_INDEX_BUFFER_BIT |
                                         VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT |
                                         VK_BUFFER_USAGE_UNIFORM_TEXEL_BUFFER_BIT | VK_BUFFER_USAGE_STORAGE_TEXEL_BUFFER_BIT;

static uint64_t buffer_address(VkBuffer b) {
    VkBufferDeviceAddressInfo ai{VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO};
    ai.buffer = b;
    return vk.GetBufferDeviceAddress(g.dev, &ai);
}

uint32_t create_buffer_internal(uint64_t size, bool host_visible, void** map) {
    auto b = std::make_unique<Buffer>();
    if (size == 0) size = 16;
    VkBufferCreateInfo bci{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
    bci.size = size;
    bci.usage = kBufferUsage;
    if (vk.CreateBuffer(g.dev, &bci, nullptr, &b->buf) != VK_SUCCESS) return 0;
    VkMemoryRequirements req;
    vk.GetBufferMemoryRequirements(g.dev, b->buf, &req);
    VkMemoryPropertyFlags want = host_visible ? (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT | VK_MEMORY_PROPERTY_HOST_CACHED_BIT)
                                              : VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
    b->mem = alloc_memory(req, want, true);
    if (!b->mem && host_visible) b->mem = alloc_memory(req, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, true);
    if (!b->mem) { vk.DestroyBuffer(g.dev, b->buf, nullptr); return 0; }
    vk.BindBufferMemory(g.dev, b->buf, b->mem, 0);
    if (host_visible) vk.MapMemory(g.dev, b->mem, 0, VK_WHOLE_SIZE, 0, &b->map);
    b->size = size;
    b->addr = buffer_address(b->buf);
    if (map) *map = b->map;
    return add_object(g.buffers, std::move(b));
}

// newBuffer for the guest: shared/managed memory is host-visible and cached (the guest reads it back freely);
// private memory is device local.
uint32_t buffer_create(uint64_t length, uint32_t options, void** contents, uint64_t* gpu) {
    uint32_t storage = (options >> 4) & 0xf;
    void* map = nullptr;
    uint32_t id = create_buffer_internal(length, storage != 2, &map);
    if (!id) return 0;
    Buffer* b = buffer(id);
    b->options = options;
    if (map) memset(map, 0, length);
    if (contents) *contents = map;
    if (gpu) *gpu = b->addr;
    return id;
}

uint32_t buffer_create_nocopy(void* ptr, uint64_t length, uint32_t options, uint64_t* gpu) {
    if (!g.has_host_import || ((uintptr_t)ptr % g.host_import_align) || !length) return 0;
    auto b = std::make_unique<Buffer>();
    uint64_t size = (length + g.host_import_align - 1) & ~(g.host_import_align - 1);
    VkExternalMemoryBufferCreateInfo ext{VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_BUFFER_CREATE_INFO};
    ext.handleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_ALLOCATION_BIT_EXT;
    VkBufferCreateInfo bci{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
    bci.pNext = &ext;
    bci.size = size;
    bci.usage = kBufferUsage;
    if (vk.CreateBuffer(g.dev, &bci, nullptr, &b->buf) != VK_SUCCESS) return 0;
    VkMemoryHostPointerPropertiesEXT hpp{VK_STRUCTURE_TYPE_MEMORY_HOST_POINTER_PROPERTIES_EXT};
    if (!vk.GetMemoryHostPointerPropertiesEXT ||
        vk.GetMemoryHostPointerPropertiesEXT(g.dev, VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_ALLOCATION_BIT_EXT, ptr, &hpp) != VK_SUCCESS) {
        vk.DestroyBuffer(g.dev, b->buf, nullptr);
        return 0;
    }
    VkMemoryRequirements req;
    vk.GetBufferMemoryRequirements(g.dev, b->buf, &req);
    uint32_t type = find_memory_type(req.memoryTypeBits & hpp.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT);
    VkImportMemoryHostPointerInfoEXT imp{VK_STRUCTURE_TYPE_IMPORT_MEMORY_HOST_POINTER_INFO_EXT};
    imp.handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_ALLOCATION_BIT_EXT;
    imp.pHostPointer = ptr;
    VkMemoryAllocateFlagsInfo fi{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_FLAGS_INFO};
    fi.flags = VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT;
    fi.pNext = &imp;
    VkMemoryAllocateInfo ai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    ai.pNext = &fi;
    ai.allocationSize = size;
    ai.memoryTypeIndex = type;
    if (type == ~0u || vk.AllocateMemory(g.dev, &ai, nullptr, &b->mem) != VK_SUCCESS) {
        vk.DestroyBuffer(g.dev, b->buf, nullptr);
        return 0;
    }
    vk.BindBufferMemory(g.dev, b->buf, b->mem, 0);
    b->map = ptr;
    b->size = length;
    b->imported = true;
    b->options = options;
    b->addr = buffer_address(b->buf);
    if (gpu) *gpu = b->addr;
    return add_object(g.buffers, std::move(b));
}

void buffer_destroy(uint32_t id) {
    Buffer* b = buffer(id);
    if (!b) return;
    vk.DeviceWaitIdle(g.dev);   // TODO: deferred destruction tied to submissions
    vk.DestroyBuffer(g.dev, b->buf, nullptr);
    if (b->map && !b->imported) vk.UnmapMemory(g.dev, b->mem);
    vk.FreeMemory(g.dev, b->mem, nullptr);
    g.buffers[id].reset();
}

// ---------------- descriptors ----------------

static uint32_t alloc_tex_id() {
    if (!g.free_tex_ids.empty()) { uint32_t i = g.free_tex_ids.back(); g.free_tex_ids.pop_back(); return i; }
    if (g.next_tex_id >= kMaxTextures) return 0;
    return g.next_tex_id++;
}
static uint32_t alloc_sampler_id() {
    if (!g.free_sampler_ids.empty()) { uint32_t i = g.free_sampler_ids.back(); g.free_sampler_ids.pop_back(); return i; }
    if (g.next_sampler_id >= kMaxSamplers) return 0;
    return g.next_sampler_id++;
}

static void write_image_desc(uint32_t binding, uint32_t index, VkImageView view, bool storage) {
    VkDescriptorImageInfo ii{VK_NULL_HANDLE, view, VK_IMAGE_LAYOUT_GENERAL};
    VkWriteDescriptorSet w{VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET};
    w.dstSet = g.set;
    w.dstBinding = binding;
    w.dstArrayElement = index;
    w.descriptorCount = 1;
    w.descriptorType = storage ? VK_DESCRIPTOR_TYPE_STORAGE_IMAGE : VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE;
    w.pImageInfo = &ii;
    vk.UpdateDescriptorSets(g.dev, 1, &w, 0, nullptr);
}
static void write_texel_desc(uint32_t binding, uint32_t index, VkBufferView view, bool storage) {
    VkWriteDescriptorSet w{VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET};
    w.dstSet = g.set;
    w.dstBinding = binding;
    w.dstArrayElement = index;
    w.descriptorCount = 1;
    w.descriptorType = storage ? VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER : VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER;
    w.pTexelBufferView = &view;
    vk.UpdateDescriptorSets(g.dev, 1, &w, 0, nullptr);
}

// ---------------- textures ----------------

static uint32_t dim_of_type(uint32_t type) {
    switch (type) {
    case 0: return DIM_1D;
    case 1: return DIM_1D_ARRAY;
    case 2: return DIM_2D;
    case 3: return DIM_2D_ARRAY;
    case 4: return DIM_2D_MS;
    case 5: return DIM_CUBE;
    case 6: return DIM_CUBE_ARRAY;
    case 7: return DIM_3D;
    case 8: return DIM_2D_MS_ARRAY;
    case 9: return DIM_BUFFER;
    default: return DIM_2D;
    }
}
static VkImageViewType view_type_of(uint32_t type) {
    switch (type) {
    case 0: return VK_IMAGE_VIEW_TYPE_1D;
    case 1: return VK_IMAGE_VIEW_TYPE_1D_ARRAY;
    case 3: case 8: return VK_IMAGE_VIEW_TYPE_2D_ARRAY;
    case 5: return VK_IMAGE_VIEW_TYPE_CUBE;
    case 6: return VK_IMAGE_VIEW_TYPE_CUBE_ARRAY;
    case 7: return VK_IMAGE_VIEW_TYPE_3D;
    default: return VK_IMAGE_VIEW_TYPE_2D;
    }
}

static VkComponentMapping mapping_of(const Texture* t) {
    VkComponentMapping c;
    c.r = (VkComponentSwizzle)(t->swizzle[0] + 1);
    c.g = (VkComponentSwizzle)(t->swizzle[1] + 1);
    c.b = (VkComponentSwizzle)(t->swizzle[2] + 1);
    c.a = (VkComponentSwizzle)(t->swizzle[3] + 1);
    if (t->fmt && (t->fmt->flags & FMT_ALPHA_ONLY)) {   // A8: alpha from R, color 0
        auto pick = [](VkComponentSwizzle s) {
            switch (s) { case VK_COMPONENT_SWIZZLE_R: case VK_COMPONENT_SWIZZLE_G: case VK_COMPONENT_SWIZZLE_B: return VK_COMPONENT_SWIZZLE_ZERO;
                         case VK_COMPONENT_SWIZZLE_A: return VK_COMPONENT_SWIZZLE_R; default: return s; }
        };
        c.r = pick(c.r); c.g = pick(c.g); c.b = pick(c.b); c.a = pick(c.a);
    }
    return c;
}

static VkImageView make_view(Texture* root, VkFormat fmt, VkImageViewType vt, VkImageAspectFlags aspect, uint32_t level, uint32_t levels,
                             uint32_t layer, uint32_t layers, VkComponentMapping comp, VkImageUsageFlags usage) {
    VkImageViewUsageCreateInfo uci{VK_STRUCTURE_TYPE_IMAGE_VIEW_USAGE_CREATE_INFO};
    uci.usage = usage;
    VkImageViewCreateInfo vci{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    vci.pNext = usage ? &uci : nullptr;
    vci.image = root->img;
    vci.viewType = vt;
    vci.format = fmt;
    vci.components = comp;
    vci.subresourceRange = {aspect, level, levels, layer, layers};
    VkImageView v = VK_NULL_HANDLE;
    if (vk.CreateImageView(g.dev, &vci, nullptr, &v) != VK_SUCCESS) return VK_NULL_HANDLE;
    return v;
}

static VkFormat storage_format(VkFormat f) {
    switch (f) {   // sRGB formats cannot be storage images: write through the UNORM alias
    case VK_FORMAT_R8G8B8A8_SRGB: return VK_FORMAT_R8G8B8A8_UNORM;
    case VK_FORMAT_B8G8R8A8_SRGB: return VK_FORMAT_B8G8R8A8_UNORM;
    case VK_FORMAT_R8_SRGB: return VK_FORMAT_R8_UNORM;
    case VK_FORMAT_R8G8_SRGB: return VK_FORMAT_R8G8_UNORM;
    default: return f;
    }
}

static bool format_supports(VkFormat f, VkFormatFeatureFlags feat) {
    VkFormatProperties p{};
    vk.GetPhysicalDeviceFormatProperties(g.pd, f, &p);
    return (p.optimalTilingFeatures & feat) == feat;
}

// creates the sampled/storage views of `t` and writes its descriptors
static void publish_texture(Texture* t, Texture* root) {
    uint32_t dim = dim_of_type(t->type);
    uint32_t comp = comp_class(t->fmt);
    VkImageAspectFlags aspect = aspect_of(t->fmt);
    if ((aspect & VK_IMAGE_ASPECT_DEPTH_BIT) && (aspect & VK_IMAGE_ASPECT_STENCIL_BIT)) aspect = VK_IMAGE_ASPECT_DEPTH_BIT;
    if (t->fmt && (t->fmt->flags & FMT_STENCIL) && !(t->fmt->flags & FMT_DEPTH)) aspect = VK_IMAGE_ASPECT_STENCIL_BIT;
    uint32_t layers = t->layers;
    VkComponentMapping comp_map = mapping_of(t);
    if (aspect != VK_IMAGE_ASPECT_COLOR_BIT) comp_map = {};   // depth/stencil views take no swizzle on some drivers
    VkFormat vf = t->vkfmt;
    if (dim == DIM_BUFFER) {
        Buffer* b = buffer(t->buffer);
        if (!b) return;
        VkBufferViewCreateInfo bv{VK_STRUCTURE_TYPE_BUFFER_VIEW_CREATE_INFO};
        bv.buffer = b->buf;
        bv.format = vf;
        bv.offset = 0;
        bv.range = VK_WHOLE_SIZE;
        vk.CreateBufferView(g.dev, &bv, nullptr, &t->texel_view);
        if (t->texel_view) {
            write_texel_desc(sampled_image_binding(DIM_BUFFER, comp), t->resource_id, t->texel_view, false);
            if (comp != COMP_FLOAT) write_texel_desc(sampled_image_binding(DIM_BUFFER, COMP_FLOAT), t->resource_id, t->texel_view, false);
            if (t->usage & 0x22) write_texel_desc(storage_image_binding(DIM_BUFFER, comp), t->resource_id, t->texel_view, true);
        }
        return;
    }
    VkImageViewType vt = view_type_of(t->type);
    t->sampled_view = make_view(root, vf, vt, aspect, t->base_level, t->mips, t->base_layer, layers, comp_map, VK_IMAGE_USAGE_SAMPLED_BIT);
    if (t->sampled_view) {
        write_image_desc(sampled_image_binding(dim, comp), t->resource_id, t->sampled_view, false);
        if (comp != COMP_FLOAT) write_image_desc(sampled_image_binding(dim, COMP_FLOAT), t->resource_id, t->sampled_view, false);
    }
    // cube textures are read()/write() as 2D arrays
    if (dim == DIM_CUBE || dim == DIM_CUBE_ARRAY) {
        t->array_view = make_view(root, vf, VK_IMAGE_VIEW_TYPE_2D_ARRAY, aspect, t->base_level, t->mips, t->base_layer, layers, comp_map, VK_IMAGE_USAGE_SAMPLED_BIT);
        if (t->array_view) write_image_desc(sampled_image_binding(DIM_2D_ARRAY, comp), t->resource_id, t->array_view, false);
    }
    if ((t->usage & 0x22) && aspect == VK_IMAGE_ASPECT_COLOR_BIT) {
        VkFormat sf = storage_format(vf);
        if (format_supports(sf, VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT)) {
            // storage views are single-level
            VkImageViewType svt = (dim == DIM_CUBE || dim == DIM_CUBE_ARRAY) ? VK_IMAGE_VIEW_TYPE_2D_ARRAY : vt;
            t->storage_view = make_view(root, sf, svt, aspect, t->base_level, 1, t->base_layer, layers, VkComponentMapping{}, VK_IMAGE_USAGE_STORAGE_BIT);
            if (t->storage_view) {
                uint32_t sdim = (dim == DIM_CUBE || dim == DIM_CUBE_ARRAY) ? DIM_2D_ARRAY : dim;
                write_image_desc(storage_image_binding(sdim, comp), t->resource_id, t->storage_view, true);
                if (sdim != dim) write_image_desc(storage_image_binding(dim, comp), t->resource_id, t->storage_view, true);
            }
        }
    }
}

uint32_t texture_create(const xef_mtl_texture_desc* d, uint64_t* rid) {
    auto t = std::make_unique<Texture>();
    t->fmt = pixel_format(d->pixel_format);
    if (!t->fmt) { XEF_LOG(1, "metal: unsupported pixel format %u", d->pixel_format); return 0; }
    t->mtl_format = d->pixel_format;
    t->vkfmt = t->fmt->vk;
    if (t->fmt->flags & (FMT_DEPTH | FMT_STENCIL)) t->vkfmt = resolve_depth_format(g.pd, t->vkfmt);
    t->type = d->type;
    t->width = std::max(1u, d->width);
    t->height = std::max(1u, d->height);
    t->depth = std::max(1u, d->depth);
    t->mips = std::max(1u, d->mip_levels);
    t->samples = std::max(1u, d->sample_count);
    t->usage = d->usage ? d->usage : 1;
    memcpy(t->swizzle, d->swizzle, 4);
    if (!t->swizzle[0] && !t->swizzle[1] && !t->swizzle[2] && !t->swizzle[3]) { t->swizzle[0] = 2; t->swizzle[1] = 3; t->swizzle[2] = 4; t->swizzle[3] = 5; }
    uint32_t arr = std::max(1u, d->array_length);
    bool cube = d->type == 5 || d->type == 6;
    t->layers = cube ? 6 * arr : (d->type == 1 || d->type == 3 || d->type == 8) ? arr : 1;
    t->resource_id = alloc_tex_id();
    if (!t->resource_id) { XEF_LOG(1, "metal: out of texture ids"); return 0; }
    if (d->type == 9) {   // texture buffer
        t->buffer = d->buffer;
        if (!t->buffer) {
            uint64_t sz = (uint64_t)t->width * t->fmt->block_bytes;
            t->buffer = create_buffer_internal(sz, false, nullptr);
        }
        publish_texture(t.get(), t.get());
        if (rid) *rid = t->resource_id;
        return add_object(g.textures, std::move(t));
    }
    VkImageCreateInfo ici{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    ici.imageType = d->type == 0 || d->type == 1 ? VK_IMAGE_TYPE_1D : d->type == 7 ? VK_IMAGE_TYPE_3D : VK_IMAGE_TYPE_2D;
    ici.format = t->vkfmt;
    ici.extent = {t->width, ici.imageType == VK_IMAGE_TYPE_1D ? 1 : t->height, d->type == 7 ? t->depth : 1};
    ici.mipLevels = t->mips;
    ici.arrayLayers = t->layers;
    ici.samples = (VkSampleCountFlagBits)t->samples;
    ici.tiling = VK_IMAGE_TILING_OPTIMAL;
    ici.usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
    VkFormatFeatureFlags ff = 0;
    {
        VkFormatProperties p{};
        vk.GetPhysicalDeviceFormatProperties(g.pd, t->vkfmt, &p);
        ff = p.optimalTilingFeatures;
    }
    if (t->fmt->flags & (FMT_DEPTH | FMT_STENCIL)) {
        if (ff & VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT) ici.usage |= VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
    } else if (!(t->fmt->flags & FMT_COMPRESSED)) {
        if (ff & VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT) ici.usage |= VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
        if ((t->usage & 0x22) && format_supports(storage_format(t->vkfmt), VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT)) ici.usage |= VK_IMAGE_USAGE_STORAGE_BIT;
    }
    if (cube) ici.flags |= VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT;
    ici.flags |= VK_IMAGE_CREATE_MUTABLE_FORMAT_BIT | VK_IMAGE_CREATE_EXTENDED_USAGE_BIT;
    if (d->type == 7) ici.flags |= VK_IMAGE_CREATE_2D_ARRAY_COMPATIBLE_BIT;
    if (t->samples > 1) ici.usage &= ~VK_IMAGE_USAGE_STORAGE_BIT;
    ici.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    VkResult r = vk.CreateImage(g.dev, &ici, nullptr, &t->img);
    if (r != VK_SUCCESS) { XEF_LOG(1, "metal: vkCreateImage failed (%d) fmt %u %ux%u", (int)r, d->pixel_format, t->width, t->height); return 0; }
    VkMemoryRequirements req;
    vk.GetImageMemoryRequirements(g.dev, t->img, &req);
    t->mem = alloc_memory(req, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, false);
    if (!t->mem) { vk.DestroyImage(g.dev, t->img, nullptr); return 0; }
    vk.BindImageMemory(g.dev, t->img, t->mem, 0);
    // everything lives in GENERAL layout; clear to zero so uninitialized reads are deterministic
    VkImage img = t->img;
    VkImageAspectFlags aspect = aspect_of(t->fmt);
    if (t->vkfmt == VK_FORMAT_D32_SFLOAT_S8_UINT || t->vkfmt == VK_FORMAT_D24_UNORM_S8_UINT) aspect = VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT;
    uint32_t mips = t->mips, layers = t->layers;
    bool compressed = (t->fmt->flags & FMT_COMPRESSED) != 0;
    one_shot([&](VkCommandBuffer cb) {
        VkImageMemoryBarrier2 b{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2};
        b.srcStageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;
        b.dstStageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;
        b.dstAccessMask = VK_ACCESS_2_MEMORY_WRITE_BIT | VK_ACCESS_2_MEMORY_READ_BIT;
        b.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        b.newLayout = VK_IMAGE_LAYOUT_GENERAL;
        b.srcQueueFamilyIndex = b.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        b.image = img;
        b.subresourceRange = {aspect, 0, mips, 0, layers};
        VkDependencyInfo di{VK_STRUCTURE_TYPE_DEPENDENCY_INFO};
        di.imageMemoryBarrierCount = 1;
        di.pImageMemoryBarriers = &b;
        vk.CmdPipelineBarrier2(cb, &di);
        VkImageSubresourceRange rr{aspect, 0, mips, 0, layers};
        if (aspect & (VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT)) {
            VkClearDepthStencilValue z{0.0f, 0};
            vk.CmdClearDepthStencilImage(cb, img, VK_IMAGE_LAYOUT_GENERAL, &z, 1, &rr);
        } else if (!compressed) {
            VkClearColorValue z{};
            vk.CmdClearColorImage(cb, img, VK_IMAGE_LAYOUT_GENERAL, &z, 1, &rr);
        }
        image_barrier_all(cb);
    });
    publish_texture(t.get(), t.get());
    if (rid) *rid = t->resource_id;
    return add_object(g.textures, std::move(t));
}

uint32_t texture_view(uint32_t parent_id, const xef_mtl_view_desc* d, uint64_t* rid) {
    Texture* parent = texture(parent_id);
    if (!parent) return 0;
    Texture* root = texture_root(parent);
    auto t = std::make_unique<Texture>();
    t->fmt = pixel_format(d->pixel_format ? d->pixel_format : parent->mtl_format);
    if (!t->fmt) return 0;
    t->mtl_format = d->pixel_format ? d->pixel_format : parent->mtl_format;
    t->vkfmt = t->fmt->vk;
    if (t->fmt->flags & (FMT_DEPTH | FMT_STENCIL)) t->vkfmt = root->vkfmt;   // stencil views of depth/stencil textures
    t->type = d->type;
    t->width = std::max(1u, parent->width >> d->level);
    t->height = std::max(1u, parent->height >> d->level);
    t->depth = std::max(1u, parent->depth >> d->level);
    t->mips = std::max(1u, d->levels);
    t->base_level = parent->base_level + d->level;
    t->base_layer = parent->base_layer + d->slice;
    bool cube = d->type == 5 || d->type == 6;
    t->layers = std::max(1u, d->slices) * (cube && d->slices < 6 ? 6 : 1);
    if (cube && d->slices >= 6) t->layers = d->slices;
    t->samples = parent->samples;
    t->usage = parent->usage;
    t->parent = parent_id;
    memcpy(t->swizzle, d->swizzle, 4);
    if (!t->swizzle[0] && !t->swizzle[1] && !t->swizzle[2] && !t->swizzle[3]) memcpy(t->swizzle, parent->swizzle, 4);
    t->resource_id = alloc_tex_id();
    if (!t->resource_id) return 0;
    if (d->type == 9) t->buffer = parent->buffer;
    publish_texture(t.get(), root);
    if (rid) *rid = t->resource_id;
    return add_object(g.textures, std::move(t));
}

void texture_destroy(uint32_t id) {
    Texture* t = texture(id);
    if (!t) return;
    vk.DeviceWaitIdle(g.dev);
    for (VkImageView v : {t->sampled_view, t->storage_view, t->array_view}) if (v) vk.DestroyImageView(g.dev, v, nullptr);
    for (auto& [k, v] : t->attach_views) vk.DestroyImageView(g.dev, v, nullptr);
    if (t->texel_view) vk.DestroyBufferView(g.dev, t->texel_view, nullptr);
    if (!t->parent && t->img) {
        vk.DestroyImage(g.dev, t->img, nullptr);
        vk.FreeMemory(g.dev, t->mem, nullptr);
    }
    if (t->resource_id) g.free_tex_ids.push_back(t->resource_id);
    g.textures[id].reset();
}

VkImageView attachment_view(Texture* t, uint32_t level, uint32_t slice, uint32_t layers, VkImageAspectFlags aspect) {
    uint64_t key = ((uint64_t)level << 48) | ((uint64_t)slice << 24) | ((uint64_t)layers << 4) | aspect;
    auto it = t->attach_views.find(key);
    if (it != t->attach_views.end()) return it->second;
    Texture* root = texture_root(t);
    VkImageViewType vt = layers > 1 ? VK_IMAGE_VIEW_TYPE_2D_ARRAY : VK_IMAGE_VIEW_TYPE_2D;
    VkImageUsageFlags usage = (aspect & VK_IMAGE_ASPECT_COLOR_BIT) ? VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT : VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
    VkImageView v = make_view(root, t->vkfmt, vt, aspect, t->base_level + level, 1, t->base_layer + slice, layers, VkComponentMapping{}, usage);
    t->attach_views[key] = v;
    return v;
}

// ---------------- samplers ----------------

static VkSamplerAddressMode address_mode(uint32_t m) {
    switch (m) {
    case 0: return VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    case 1: return VK_SAMPLER_ADDRESS_MODE_MIRROR_CLAMP_TO_EDGE;
    case 2: return VK_SAMPLER_ADDRESS_MODE_REPEAT;
    case 3: return VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT;
    case 4: case 5: return VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER;
    default: return VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    }
}

uint32_t sampler_create(const xef_mtl_sampler_desc* d, uint64_t* rid) {
    auto s = std::make_unique<Sampler>();
    VkSamplerCreateInfo sci{VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO};
    sci.magFilter = d->mag_filter ? VK_FILTER_LINEAR : VK_FILTER_NEAREST;
    sci.minFilter = d->min_filter ? VK_FILTER_LINEAR : VK_FILTER_NEAREST;
    sci.mipmapMode = d->mip_filter == 2 ? VK_SAMPLER_MIPMAP_MODE_LINEAR : VK_SAMPLER_MIPMAP_MODE_NEAREST;
    sci.addressModeU = address_mode(d->s_address);
    sci.addressModeV = address_mode(d->t_address);
    sci.addressModeW = address_mode(d->r_address);
    sci.mipLodBias = d->lod_bias;
    sci.anisotropyEnable = d->max_anisotropy > 1 ? VK_TRUE : VK_FALSE;
    sci.maxAnisotropy = (float)std::min<uint32_t>(d->max_anisotropy, 16);
    sci.compareEnable = VK_FALSE;
    sci.compareOp = (VkCompareOp)d->compare;
    sci.minLod = d->lod_min;
    sci.maxLod = d->mip_filter == 0 ? 0.25f : d->lod_max;
    bool zero = d->s_address == 4 || d->t_address == 4 || d->r_address == 4;
    sci.borderColor = zero || d->border_color == 0 ? VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK
                    : d->border_color == 1 ? VK_BORDER_COLOR_FLOAT_OPAQUE_BLACK : VK_BORDER_COLOR_FLOAT_OPAQUE_WHITE;
    sci.unnormalizedCoordinates = d->normalized ? VK_FALSE : VK_TRUE;
    if (sci.unnormalizedCoordinates) {
        sci.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST;
        sci.minLod = sci.maxLod = 0;
        sci.anisotropyEnable = VK_FALSE;
        sci.compareEnable = VK_FALSE;
        sci.minFilter = sci.magFilter;
        auto fix = [](VkSamplerAddressMode m) { return m == VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER ? m : VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE; };
        sci.addressModeU = fix(sci.addressModeU); sci.addressModeV = fix(sci.addressModeV); sci.addressModeW = fix(sci.addressModeW);
    }
    if (vk.CreateSampler(g.dev, &sci, nullptr, &s->s) != VK_SUCCESS) return 0;
    if (!sci.unnormalizedCoordinates) {
        // sample_compare without a compare function compares with "never" like Metal's default
        sci.compareEnable = VK_TRUE;
        if (!d->compare_enable) sci.compareOp = VK_COMPARE_OP_NEVER;
        if (vk.CreateSampler(g.dev, &sci, nullptr, &s->cmp) != VK_SUCCESS) s->cmp = VK_NULL_HANDLE;
    }
    s->resource_id = alloc_sampler_id();
    if (!s->resource_id) {
        vk.DestroySampler(g.dev, s->s, nullptr);
        if (s->cmp) vk.DestroySampler(g.dev, s->cmp, nullptr);
        return 0;
    }
    VkDescriptorImageInfo ii[2] = {{s->s, VK_NULL_HANDLE, VK_IMAGE_LAYOUT_UNDEFINED}, {s->cmp ? s->cmp : s->s, VK_NULL_HANDLE, VK_IMAGE_LAYOUT_UNDEFINED}};
    VkWriteDescriptorSet w[2] = {{VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET}, {VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET}};
    for (int k = 0; k < 2; k++) {
        w[k].dstSet = g.set;
        w[k].dstBinding = k ? kCompareSamplerBinding : kSamplerBinding;
        w[k].dstArrayElement = s->resource_id;
        w[k].descriptorCount = 1;
        w[k].descriptorType = VK_DESCRIPTOR_TYPE_SAMPLER;
        w[k].pImageInfo = &ii[k];
    }
    vk.UpdateDescriptorSets(g.dev, 2, w, 0, nullptr);
    if (rid) *rid = s->resource_id;
    uint32_t id = add_object(g.samplers, std::move(s));
    if (getenv("XEF_MTL_TRACE"))
        fprintf(stderr, "mtl: sampler %u: min %u mag %u mip %u addr %u %u %u aniso %u cmp %u/%u border %u norm %u lod %g..%g bias %g\n", id,
                d->min_filter, d->mag_filter, d->mip_filter, d->s_address, d->t_address, d->r_address, d->max_anisotropy, d->compare_enable,
                d->compare, d->border_color, d->normalized, d->lod_min, d->lod_max, d->lod_bias);
    return id;
}

void sampler_destroy(uint32_t id) {
    Sampler* s = sampler(id);
    if (!s) return;
    vk.DeviceWaitIdle(g.dev);
    vk.DestroySampler(g.dev, s->s, nullptr);
    if (s->cmp) vk.DestroySampler(g.dev, s->cmp, nullptr);
    g.free_sampler_ids.push_back(s->resource_id);
    g.samplers[id].reset();
}

uint32_t const_sampler_id(const ConstSampler& cs) {
    std::vector<uint8_t> key((const uint8_t*)&cs, (const uint8_t*)&cs + sizeof(cs));
    auto it = g.const_sampler_cache.find(key);
    if (it != g.const_sampler_cache.end()) return it->second;
    xef_mtl_sampler_desc d{};
    d.min_filter = cs.min_filter; d.mag_filter = cs.mag_filter; d.mip_filter = cs.mip_filter;
    d.s_address = cs.s_address; d.t_address = cs.t_address; d.r_address = cs.r_address;
    d.max_anisotropy = cs.max_aniso; d.compare = cs.compare; d.compare_enable = cs.compare != 0;
    d.border_color = cs.border; d.normalized = cs.normalized;
    d.lod_min = cs.lod_min; d.lod_max = cs.lod_max;
    uint32_t id = sampler_create(&d, nullptr);
    g.const_sampler_cache[key] = id;
    return id;
}

// ---------------- one-shot command buffers (uploads, readbacks, init) ----------------

static VkCommandPool g_oneshot_pool = VK_NULL_HANDLE;

void one_shot(const std::function<void(VkCommandBuffer)>& rec) {
    if (!g_oneshot_pool) {
        VkCommandPoolCreateInfo pci{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
        pci.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
        pci.queueFamilyIndex = g.qfamily;
        vk.CreateCommandPool(g.dev, &pci, nullptr, &g_oneshot_pool);
    }
    VkCommandBufferAllocateInfo ai{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    ai.commandPool = g_oneshot_pool;
    ai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    ai.commandBufferCount = 1;
    VkCommandBuffer cb;
    vk.AllocateCommandBuffers(g.dev, &ai, &cb);
    VkCommandBufferBeginInfo bi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vk.BeginCommandBuffer(cb, &bi);
    rec(cb);
    vk.EndCommandBuffer(cb);
    VkFenceCreateInfo fci{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
    VkFence fence;
    vk.CreateFence(g.dev, &fci, nullptr, &fence);
    VkSubmitInfo si{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    si.commandBufferCount = 1;
    si.pCommandBuffers = &cb;
    vk.QueueSubmit(g.queue, 1, &si, fence);
    vk.WaitForFences(g.dev, 1, &fence, VK_TRUE, UINT64_MAX);
    vk.DestroyFence(g.dev, fence, nullptr);
    vk.FreeCommandBuffers(g.dev, g_oneshot_pool, 1, &cb);
}

void image_barrier_all(VkCommandBuffer cb) {
    VkMemoryBarrier2 mb{VK_STRUCTURE_TYPE_MEMORY_BARRIER_2};
    mb.srcStageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;
    mb.srcAccessMask = VK_ACCESS_2_MEMORY_WRITE_BIT;
    mb.dstStageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;
    mb.dstAccessMask = VK_ACCESS_2_MEMORY_READ_BIT | VK_ACCESS_2_MEMORY_WRITE_BIT;
    VkDependencyInfo di{VK_STRUCTURE_TYPE_DEPENDENCY_INFO};
    di.memoryBarrierCount = 1;
    di.pMemoryBarriers = &mb;
    vk.CmdPipelineBarrier2(cb, &di);
}

// ---------------- texture upload / readback ----------------

static void region_layout(Texture* t, uint32_t w, uint32_t h, uint32_t d, uint64_t& row_bytes, uint64_t& rows) {
    uint32_t bw = t->fmt->block_w, bh = t->fmt->block_h;
    row_bytes = (uint64_t)((w + bw - 1) / bw) * t->fmt->block_bytes;
    rows = (uint64_t)((h + bh - 1) / bh) * d;
}

void texture_replace(uint32_t id, uint32_t level, uint32_t slice, const uint32_t* reg, const void* bytes, uint64_t bpr, uint64_t bpi) {
    Texture* t = texture(id);
    if (!t || !bytes) return;
    if (t->type == 9) {   // texture buffer: write into the buffer
        Buffer* b = buffer(t->buffer);
        if (!b || !b->map) return;
        memcpy((uint8_t*)b->map + (uint64_t)reg[0] * t->fmt->block_bytes, bytes, (uint64_t)reg[3] * t->fmt->block_bytes);
        return;
    }
    Texture* root = texture_root(t);
    uint32_t x = reg[0], y = reg[1], z = reg[2], w = reg[3], h = reg[4], d = reg[5];
    if (!w || !h || !d) return;
    uint64_t row_bytes, rows;
    region_layout(t, w, h, 1, row_bytes, rows);
    uint32_t bh = t->fmt->block_h;
    uint64_t brows = (h + bh - 1) / bh;
    if (!bpr) bpr = row_bytes;
    if (!bpi) bpi = bpr * brows;
    uint64_t size = row_bytes * brows * d;
    void* map = nullptr;
    uint32_t staging = create_buffer_internal(size, true, &map);
    if (!staging) return;
    for (uint32_t k = 0; k < d; k++)
        for (uint64_t r = 0; r < brows; r++)
            memcpy((uint8_t*)map + (k * brows + r) * row_bytes, (const uint8_t*)bytes + k * bpi + r * bpr, row_bytes);
    Buffer* sb = buffer(staging);
    VkImageAspectFlags aspect = aspect_of(t->fmt);
    if (aspect == (VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT)) aspect = VK_IMAGE_ASPECT_DEPTH_BIT;
    bool is3d = t->type == 7;
    VkBufferImageCopy c{};
    c.bufferOffset = 0;
    c.imageSubresource = {aspect, t->base_level + level, t->base_layer + (is3d ? 0 : slice), is3d ? 1u : d};
    c.imageOffset = {(int32_t)x, (int32_t)y, (int32_t)(is3d ? z : 0)};
    c.imageExtent = {w, h, is3d ? d : 1};
    if (!is3d && d > 1) c.imageSubresource.layerCount = d;
    one_shot([&](VkCommandBuffer cb) {
        image_barrier_all(cb);
        vk.CmdCopyBufferToImage(cb, sb->buf, root->img, VK_IMAGE_LAYOUT_GENERAL, 1, &c);
        image_barrier_all(cb);
    });
    vk.DestroyBuffer(g.dev, sb->buf, nullptr);
    vk.UnmapMemory(g.dev, sb->mem);
    vk.FreeMemory(g.dev, sb->mem, nullptr);
    g.buffers[staging].reset();
}

void texture_get_bytes(uint32_t id, uint32_t level, uint32_t slice, const uint32_t* reg, void* bytes, uint64_t bpr, uint64_t bpi) {
    Texture* t = texture(id);
    if (!t || !bytes) return;
    if (t->type == 9) {
        Buffer* b = buffer(t->buffer);
        if (!b || !b->map) return;
        memcpy(bytes, (uint8_t*)b->map + (uint64_t)reg[0] * t->fmt->block_bytes, (uint64_t)reg[3] * t->fmt->block_bytes);
        return;
    }
    Texture* root = texture_root(t);
    uint32_t x = reg[0], y = reg[1], z = reg[2], w = reg[3], h = reg[4], d = reg[5];
    if (!w || !h || !d) return;
    uint64_t row_bytes, rows;
    region_layout(t, w, h, 1, row_bytes, rows);
    uint32_t bh = t->fmt->block_h;
    uint64_t brows = (h + bh - 1) / bh;
    if (!bpr) bpr = row_bytes;
    if (!bpi) bpi = bpr * brows;
    uint64_t size = row_bytes * brows * d;
    void* map = nullptr;
    uint32_t staging = create_buffer_internal(size, true, &map);
    if (!staging) return;
    Buffer* sb = buffer(staging);
    VkImageAspectFlags aspect = aspect_of(t->fmt);
    if (aspect == (VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT)) aspect = VK_IMAGE_ASPECT_DEPTH_BIT;
    bool is3d = t->type == 7;
    VkBufferImageCopy c{};
    c.imageSubresource = {aspect, t->base_level + level, t->base_layer + (is3d ? 0 : slice), is3d ? 1u : d};
    c.imageOffset = {(int32_t)x, (int32_t)y, (int32_t)(is3d ? z : 0)};
    c.imageExtent = {w, h, is3d ? d : 1};
    // wait for all queued GPU work touching the texture
    vk.QueueWaitIdle(g.queue);
    one_shot([&](VkCommandBuffer cb) {
        image_barrier_all(cb);
        vk.CmdCopyImageToBuffer(cb, root->img, VK_IMAGE_LAYOUT_GENERAL, sb->buf, 1, &c);
        image_barrier_all(cb);
    });
    for (uint32_t k = 0; k < d; k++)
        for (uint64_t r = 0; r < brows; r++)
            memcpy((uint8_t*)bytes + k * bpi + r * bpr, (const uint8_t*)map + (k * brows + r) * row_bytes, row_bytes);
    vk.DestroyBuffer(g.dev, sb->buf, nullptr);
    vk.UnmapMemory(g.dev, sb->mem);
    vk.FreeMemory(g.dev, sb->mem, nullptr);
    g.buffers[staging].reset();
}

void save_pipeline_cache() {
    if (!g.dev || !g.pipe_cache || !vk.GetPipelineCacheData) return;
    std::string cache_path;
    if (const char* x = getenv("XDG_CACHE_HOME")) cache_path = std::string(x) + "/xef-mtl";
    else if (const char* h = getenv("HOME")) cache_path = std::string(h) + "/.cache/xef-mtl";
    if (cache_path.empty()) return;
    mkdir(cache_path.c_str(), 0755);
    char pcb[128];
    snprintf(pcb, sizeof pcb, "/vk_pipeline_cache_%04x_%04x.bin", g.props.vendorID, g.props.deviceID);
    cache_path += pcb;
    size_t sz = 0;
    if (vk.GetPipelineCacheData(g.dev, g.pipe_cache, &sz, nullptr) == VK_SUCCESS && sz > 0) {
        std::vector<uint8_t> d(sz);
        if (vk.GetPipelineCacheData(g.dev, g.pipe_cache, &sz, d.data()) == VK_SUCCESS) {
            if (FILE* f = fopen(cache_path.c_str(), "wb")) {
                fwrite(d.data(), 1, sz, f);
                fclose(f);
            }
        }
    }
}

} // namespace xef::mtl
