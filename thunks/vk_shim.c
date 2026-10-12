// XEF guest shim for --host-gl: libvulkan.so.1 (AArch64). The generated stubs (vk_stubs.S) forward
// Vulkan commands to the host loader; this file answers vkGet*ProcAddr with our own stubs (only
// for functions the host provides) and fakes debug messengers, whose callbacks are guest code.
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define DECL(n) void n(void);
typedef struct { const char* name; void* fn; } Proc;
#include "vk_decls.inc"
static const Proc kProcs[] = {
#include "vk_names.inc"
};
static int cmp(const void* k, const void* e) { return strcmp((const char*)k, ((const Proc*)e)->name); }
static void* find(const char* name) {
    const Proc* p = bsearch(name, kProcs, sizeof kProcs / sizeof kProcs[0], sizeof kProcs[0], cmp);
    return p ? p->fn : 0;
}

void* xef_raw_vkGetInstanceProcAddr(void* instance, const char* name);
void* xef_raw_vkGetDeviceProcAddr(void* device, const char* name);
void* vkGetInstanceProcAddr(void* instance, const char* name);
void* vkGetDeviceProcAddr(void* device, const char* name);

static uint64_t g_next_handle = 0x7e100000;
int vkCreateDebugUtilsMessengerEXT(void* i, const void* info, const void* alloc, uint64_t* out) {
    *out = __atomic_add_fetch(&g_next_handle, 1, __ATOMIC_RELAXED);
    return 0;
}
void vkDestroyDebugUtilsMessengerEXT(void* i, uint64_t m, const void* alloc) {}
int vkCreateDebugReportCallbackEXT(void* i, const void* info, const void* alloc, uint64_t* out) {
    *out = __atomic_add_fetch(&g_next_handle, 1, __ATOMIC_RELAXED);
    return 0;
}
void vkDestroyDebugReportCallbackEXT(void* i, uint64_t c, const void* alloc) {}

static void* own(const char* name) {
    if (!strcmp(name, "vkGetInstanceProcAddr")) return (void*)vkGetInstanceProcAddr;
    if (!strcmp(name, "vkGetDeviceProcAddr")) return (void*)vkGetDeviceProcAddr;
    if (!strcmp(name, "vkCreateDebugUtilsMessengerEXT")) return (void*)vkCreateDebugUtilsMessengerEXT;
    if (!strcmp(name, "vkDestroyDebugUtilsMessengerEXT")) return (void*)vkDestroyDebugUtilsMessengerEXT;
    if (!strcmp(name, "vkCreateDebugReportCallbackEXT")) return (void*)vkCreateDebugReportCallbackEXT;
    if (!strcmp(name, "vkDestroyDebugReportCallbackEXT")) return (void*)vkDestroyDebugReportCallbackEXT;
    return 0;
}

void* vkGetInstanceProcAddr(void* instance, const char* name) {
    if (!name) return 0;
    void* o = own(name);
    if (o) return (o == (void*)vkGetInstanceProcAddr || o == (void*)vkGetDeviceProcAddr ||
                   xef_raw_vkGetInstanceProcAddr(instance, name)) ? o : 0;
    void* p = find(name);
    return p && xef_raw_vkGetInstanceProcAddr(instance, name) ? p : 0;
}

void* vkGetDeviceProcAddr(void* device, const char* name) {
    if (!name) return 0;
    void* o = own(name);
    if (o) return o;
    void* p = find(name);
    return p && xef_raw_vkGetDeviceProcAddr(device, name) ? p : 0;
}
