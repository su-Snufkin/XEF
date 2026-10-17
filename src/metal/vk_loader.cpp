#include "vk_loader.h"
#include "common/common.h"
#include <dlfcn.h>

namespace xef::mtl {

VkFns vk;

static void* g_lib = nullptr;

bool vk_load_global() {
    if (vk.GetInstanceProcAddr) return true;
    g_lib = dlopen("libvulkan.so.1", RTLD_NOW | RTLD_LOCAL);
    if (!g_lib) g_lib = dlopen("libvulkan.so", RTLD_NOW | RTLD_LOCAL);
    if (!g_lib) return false;
    vk.GetInstanceProcAddr = (PFN_vkGetInstanceProcAddr)dlsym(g_lib, "vkGetInstanceProcAddr");
    if (!vk.GetInstanceProcAddr) return false;
#define XEF_VK_LOAD(n) vk.n = (PFN_vk##n)vk.GetInstanceProcAddr(nullptr, "vk" #n);
    XEF_VK_GLOBAL_FNS(XEF_VK_LOAD)
#undef XEF_VK_LOAD
    return vk.CreateInstance != nullptr;
}

bool vk_load_instance(VkInstance inst) {
#define XEF_VK_LOAD(n) vk.n = (PFN_vk##n)vk.GetInstanceProcAddr(inst, "vk" #n);
    XEF_VK_INSTANCE_FNS(XEF_VK_LOAD)
#undef XEF_VK_LOAD
    return vk.CreateDevice != nullptr;
}

bool vk_load_device(VkDevice dev) {
    bool ok = true;
#define XEF_VK_LOAD(n) vk.n = (PFN_vk##n)vk.GetDeviceProcAddr(dev, "vk" #n); if (!vk.n) { XEF_LOG(1, "metal: missing vk" #n); ok = false; }
    XEF_VK_DEVICE_FNS(XEF_VK_LOAD)
#undef XEF_VK_LOAD
#define XEF_VK_LOAD_OPT(n) vk.n = (PFN_vk##n)vk.GetDeviceProcAddr(dev, "vk" #n);
    XEF_VK_DEVICE_OPT_FNS(XEF_VK_LOAD_OPT)
#undef XEF_VK_LOAD_OPT
    return ok;
}

} // namespace xef::mtl
