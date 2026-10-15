// XEF — guest -> host library thunks (OpenGL / GLX).
//
// A guest shim library (thunks/, built for AArch64) exports one stub per function:
//     mov x17, #id ; hlt #0x5846 ; ret
// HLT #0x5846 leaves the translated code like a syscall; thunk_dispatch() then calls the native
// host function with the arguments moved from AAPCS64 (x0-x7, v0-v7, stack) to SysV x86-64
// (rdi..r9, xmm0-7, stack). Guest and host share the address space, and GL/GLX types have the
// same layout on both LP64 ABIs, so pointers are passed through unchanged. Display* arguments
// are replaced by a host Xlib connection to the same X server (window XIDs are server-side).
#include "thunks/thunks.h"
#include "os/syscalls.h"

#include <dlfcn.h>
#include <sys/mman.h>
#include <stdlib.h>
#include <string.h>

#include <unistd.h>

#include <mutex>
#include <string>
#include <vector>

#include "os/signals.h"
#include "os/thread.h"
#include "runtime/cpu_state.h"
#include "runtime/dispatch.h"
#include "loader/darwin_hle.h"
#include "os/darwin/darwin_syscalls.h"

extern "C" xef::u64 xef_call_sysv(void* fn, const xef::u64* iregs, const xef::u64* fregs, const xef::u64* stack,
                                  xef::u64 nstack, xef::u64* xmm0_out);

namespace xef {

bool g_host_gl = false;

namespace {

struct Entry {
    const char* name;
    const char* sig;
    int flags;
};
const Entry kTable[] = {
#define X(name, sig, flags) {#name, sig, flags},
#include "thunks/gl_table.inc"
#undef X
};
constexpr int kCount = sizeof kTable / sizeof kTable[0];
void* g_fn[kCount];
std::mutex g_lock;
void* g_libgl;
void* g_libx11;
void* g_libegl;
void* (*g_eglproc)(const char*);
// Vulkan: the host loader, and the last instance / device for extension entry points
void* g_libvk;
void* (*g_vkGetInstanceProcAddr)(void*, const char*);
void* (*g_vkGetDeviceProcAddr)(void*, const char*);
void* g_vk_instance;
void* g_vk_device;
void* g_xcb_conn;
void* (*g_getproc)(const unsigned char*);
void* (*g_XOpenDisplay)(const char*);
char* (*g_XDisplayString)(void*);

struct DpyMap { void* guest; void* host; };
std::vector<DpyMap> g_dpy;   // unbounded: an unknown guest Display opens a host connection

// Errors on the host connection must not kill the process (Xlib's default handler exits): guest
// code probes with requests expected to fail (e.g. context versions) and checks the results.
int host_x_error(void*, void* ev) {
    if (getenv("XEF_TRACE_THUNKS")) {
        const unsigned char* e = (const unsigned char*)ev;   // XErrorEvent: error_code at offset 32
        log_msg("host X error %u (request %u.%u)", e[32], e[33], e[34]);
    }
    return 0;
}

void load_libs() {
    if (g_libgl) return;
    g_libgl = dlopen("libGL.so.1", RTLD_NOW | RTLD_GLOBAL);
    if (!g_libgl) fatal("--host-gl: cannot load the host libGL.so.1: %s", dlerror());
    g_libx11 = dlopen("libX11.so.6", RTLD_NOW | RTLD_GLOBAL);
    if (!g_libx11) fatal("--host-gl: cannot load the host libX11.so.6: %s", dlerror());
    g_getproc = (void* (*)(const unsigned char*))dlsym(g_libgl, "glXGetProcAddressARB");
    g_libegl = dlopen("libEGL.so.1", RTLD_NOW | RTLD_GLOBAL);   // optional
    if (g_libegl) g_eglproc = (void* (*)(const char*))dlsym(g_libegl, "eglGetProcAddress");
    g_XOpenDisplay = (void* (*)(const char*))dlsym(g_libx11, "XOpenDisplay");
    g_XDisplayString = (char* (*)(void*))dlsym(g_libx11, "XDisplayString");
    if (auto seh = (void* (*)(int (*)(void*, void*)))dlsym(g_libx11, "XSetErrorHandler")) seh(host_x_error);
}

// tests/guest/t_thunk_abi.c: every argument class, register and stack positions on both sides
extern "C" double xef_selftest_mix(int a, float b, double c, long d, unsigned char e, signed char f, short g,
                                   unsigned short h, float i, double j, int k, int l, int m, int n, int o, float p,
                                   float q, float r, float s, float t, double u, long v) {
    return a * 1.0 + b * 2.0 + c * 3.0 + (double)d * 4.0 + e * 5.0 + f * 6.0 + g * 7.0 + h * 8.0 + i * 9.0 +
           j * 10.0 + k * 11.0 + l * 12.0 + m * 13.0 + n * 14.0 + o * 15.0 + p * 16.0 + q * 17.0 + r * 18.0 +
           s * 19.0 + t * 20.0 + u * 21.0 + (double)v * 22.0;
}

void* resolve(int id) {
    std::lock_guard<std::mutex> lk(g_lock);
    if (g_fn[id]) return g_fn[id];
    if (strncmp(kTable[id].name, "xef_selftest_", 13)) load_libs();
    const char* name = kTable[id].name;
    void* f = nullptr;
    if (!strcmp(name, "xef_selftest_mix")) f = (void*)&xef_selftest_mix;
    else if (!strncmp(name, "xef_host_", 9)) f = dlsym(g_libx11, name + 9);
    else if (!strncmp(name, "vk", 2)) {
        if (!g_libvk) {
            g_libvk = dlopen("libvulkan.so.1", RTLD_NOW | RTLD_GLOBAL);
            if (!g_libvk) fatal("--host-gl: cannot load the host libvulkan.so.1: %s", dlerror());
            g_vkGetInstanceProcAddr = (void* (*)(void*, const char*))dlsym(g_libvk, "vkGetInstanceProcAddr");
            g_vkGetDeviceProcAddr = (void* (*)(void*, const char*))dlsym(g_libvk, "vkGetDeviceProcAddr");
        }
        f = dlsym(g_libvk, name);
        if (!f && g_vk_device) f = g_vkGetDeviceProcAddr(g_vk_device, name);
        if (!f && g_vkGetInstanceProcAddr) f = g_vkGetInstanceProcAddr(g_vk_instance, name);
    }
    else if (!strncmp(name, "egl", 3)) {
        if (!g_libegl) fatal("--host-gl: the host has no libEGL.so.1 (needed for %s)", name);
        f = dlsym(g_libegl, name);
        if (!f && g_eglproc) f = g_eglproc(name);
    } else {
        f = dlsym(g_libgl, name);
        if (!f && g_getproc) f = g_getproc((const unsigned char*)name);
    }
    if (!f) fatal("--host-gl: host has no %s", name);
    __atomic_store_n(&g_fn[id], f, __ATOMIC_RELEASE);
    return f;
}

// The guest's Display* -> a host connection to the same display. Xlib's Display has the same
// layout on both sides, so the host XDisplayString() can read the guest structure.
void* host_display(void* guest) {
    if (!guest) return nullptr;
    std::lock_guard<std::mutex> lk(g_lock);
    for (const DpyMap& d : g_dpy) if (d.guest == guest) return d.host;
    const char* name = g_XDisplayString(guest);
    void* h = g_XOpenDisplay(name);
    if (!h) fatal("--host-gl: cannot open display %s on the host", name ? name : "(null)");
    static auto conn_number = (int (*)(void*))dlsym(g_libx11, "XConnectionNumber");
    if (conn_number) protect_host_fd(conn_number(h));
    g_dpy.push_back({guest, h});
    return h;
}

void* host_xcb() {
    std::lock_guard<std::mutex> lk(g_lock);
    if (g_xcb_conn) return g_xcb_conn;
    void* lib = dlopen("libxcb.so.1", RTLD_NOW | RTLD_GLOBAL);
    auto conn = lib ? (void* (*)(const char*, int*))dlsym(lib, "xcb_connect") : nullptr;
    if (!conn) fatal("--host-gl: cannot load the host libxcb.so.1");
    g_xcb_conn = conn(nullptr, nullptr);   // $DISPLAY: the same server as the guest's
    auto get_fd = (int (*)(void*))dlsym(lib, "xcb_get_file_descriptor");
    if (get_fd && g_xcb_conn) protect_host_fd(get_fd(g_xcb_conn));
    return g_xcb_conn;
}

// vkCreateInstance: debug callbacks in the pNext chain point at guest code; unlink them for the call
struct VkChainEdit { u64* link; u64 node; };
int vk_strip_debug(u64 create_info, VkChainEdit* edits, int max) {
    int n = 0;
    u64* link = (u64*)(create_info + 8);   // VkInstanceCreateInfo::pNext
    while (*link && n < max) {
        u64 node = *link;
        u32 stype = *(u32*)node;
        if (stype == 1000128004u || stype == 1000011000u) {   // DEBUG_UTILS_MESSENGER / DEBUG_REPORT_CALLBACK
            edits[n++] = {link, node};
            *link = *(u64*)(node + 8);
            continue;
        }
        link = (u64*)(node + 8);
    }
    return n;
}

// glDebugMessageCallback: the host calls this, which calls the guest's callback
struct GuestCallback { u64 fn, user; };
void host_gl_debug(u32 source, u32 type, u32 id, u32 severity, i32 length, const char* message, const void* user) {
    const GuestCallback* cb = (const GuestCallback*)user;
    u64 a[7] = {source, type, id, severity, (u64)(u32)length, (u64)message, cb->user};
    guest_call(cb->fn, 7, a);
}

}  // namespace

// Host -> guest call on the current guest thread. The guest frame is placed below the guest stack
// pointer of the interrupted thunk call; the guest returns to a trampoline (HLT #0x5847) that ends
// the nested run, and the thread's state is restored afterwards.
u64 guest_call(u64 fn, int nargs, const u64* args) {
    ThreadCtx* t = tls_thread;
    if (!t || !fn) return 0;
    static u64 tramp = [] {
        void* p = mmap(nullptr, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (p == MAP_FAILED) fatal("guest_call: cannot map the return trampoline");
        *(u32*)p = 0xD4400000u | (kCallbackRetHlt << 5);   // hlt #0x5847
        mprotect(p, 4096, PROT_READ | PROT_EXEC);
        return (u64)p;
    }();
    CpuState* st = t->st;
    CpuState* saved = (CpuState*)aligned_alloc(alignof(CpuState), sizeof(CpuState));
    memcpy(saved, st, sizeof(CpuState));
    u64 sp = (st->x[kGuestSP] - 256) & ~15ull;
    int nstack = nargs > 8 ? nargs - 8 : 0;
    sp -= ((u64)nstack * 8 + 15) & ~15ull;
    for (int i = 0; i < nargs; i++) {
        if (i < 8) st->x[i] = args[i];
        else ((u64*)sp)[i - 8] = args[i];
    }
    st->x[kGuestSP] = sp;
    st->x[30] = tramp;
    st->pc = fn;
    cpu_run_nested(t);
    u64 r = st->x[0];
    u32 pend = st->pending_signal;
    memcpy(st, saved, sizeof(CpuState));
    free(saved);
    if (pend) st->pending_signal = pend;
    return r;
}

// --host-gl: the guest's GL libraries are replaced by the thunk shim (built next to the xef binary).
const char* thunk_lib_redirect(const char* path) {
    if (!g_host_gl || !path) return nullptr;
    const char* b = strrchr(path, '/');
    b = b ? b + 1 : path;
    static const char* const kLibs[] = {"libGL.so.1", "libGLX.so.0", "libOpenGL.so.0", "libGL.so", "libEGL.so.1",
                                        "libGLESv2.so.2", "libGLESv1_CM.so.1", "libEGL.so", "libGLESv2.so"};
    bool match = false;
    for (const char* l : kLibs) match |= !strcmp(b, l);
    bool vk = !strcmp(b, "libvulkan.so.1") || !strcmp(b, "libvulkan.so");
    if (!match && !vk) return nullptr;
    static std::string shim, vkshim;
    static std::once_flag once;
    std::call_once(once, [] {
        char exe[4096];
        ssize_t n = readlink("/proc/self/exe", exe, sizeof exe - 1);
        if (n <= 0) return;
        exe[n] = 0;
        std::string dir(exe);
        dir.resize(dir.rfind('/'));
        shim = dir + "/thunks/libGL.so.1";
        vkshim = dir + "/thunks/libvulkan.so.1";
        if (access(shim.c_str(), R_OK) != 0) fatal("--host-gl: guest shim %s not built (tools/build_thunks.sh)", shim.c_str());
    });
    return vk ? vkshim.c_str() : shim.c_str();
}

void thunk_dispatch(CpuState* st) {
    if (g_is_darwin) {
        darwin_hle_dispatch(st);
        return;
    }
    u64 id = st->x[17];
    if (id >= (u64)kCount) fatal("bad host thunk id %lu at %#lx", (unsigned long)id, (unsigned long)st->pc);
    const Entry& e = kTable[id];
    if (e.flags & 1) {   // takes a guest callback
        if (!strncmp(e.name, "glDebugMessageCallback", 22) && strcmp(e.name, "glDebugMessageCallbackAMD")) {
            using Fn = void (*)(void*, const void*);
            Fn host = (Fn)(__atomic_load_n(&g_fn[id], __ATOMIC_ACQUIRE) ?: resolve((int)id));
            GuestCallback* cb = nullptr;
            if (st->x[0]) cb = new GuestCallback{st->x[0], st->x[1]};   // leaked: callbacks may stay installed
            host(cb ? (void*)&host_gl_debug : nullptr, cb);
        }
        st->x[0] = 0;
        return;
    }
    void* fn = __atomic_load_n(&g_fn[id], __ATOMIC_ACQUIRE);
    if (!fn) fn = resolve((int)id);
    u64 ir[6] = {}, fr[8] = {}, stk[32];
    int ni = 0, nf = 0, ns = 0, gi = 0, gf = 0, gs = 0;
    const u64* gstack = (const u64*)st->x[kGuestSP];
    u64 x1_override = 0;
    bool have_override = false;
    if ((e.flags & 8) && (u32)st->x[0] == 0x31D5) {   // EGL_PLATFORM_X11_KHR: native display is a Display*
        x1_override = (u64)host_display((void*)st->x[1]);
        have_override = true;
    }
    const char* p = strchr(e.sig, ':') + 1;
    for (; *p; p++) {
        char c = *p;
        u64 v;
        bool fp = c == 'f' || c == 'd';
        if (fp) {
            if (gf < 8) memcpy(&v, st->v[gf++], 8);
            else v = gstack[gs++];
            if (c == 'f') v &= 0xffffffffull;
        } else {
            v = gi < 8 ? st->x[gi++] : gstack[gs++];
            if (have_override && gi == 2) v = x1_override;
            switch (c) {   // AAPCS64 leaves the upper bits of small arguments unspecified
            case 'b': v = (u8)v; break;
            case 'c': v = (u64)(i64)(i8)v; break;
            case 's': v = (u64)(i64)(i16)v; break;
            case 'S': v = (u16)v; break;
            case 'i': v = (u32)v; break;
            case 'D': v = (u64)host_display((void*)v); break;
            case 'X': v = (u64)host_xcb(); break;        // the guest's xcb_connection_t -> the host's
            case 'A': v = 0; break;                      // VkAllocationCallbacks: guest functions, dropped
            default: break;
            }
        }
        if (fp ? nf < 8 : ni < 6) (fp ? fr[nf++] : ir[ni++]) = v;
        else if (ns < 32) stk[ns++] = v;
        else fatal("host thunk %s: too many arguments", e.name);
    }
    // Vulkan structures that carry host-incompatible pointers: patched for the call, restored after
    u64 saved = 0, *patched = nullptr;
    VkChainEdit edits[8];
    int nedits = 0;
    if (e.flags & 16) { patched = (u64*)(st->x[1] + 24); saved = *patched; *patched = (u64)host_display((void*)saved); }
    if (e.flags & 32) { patched = (u64*)(st->x[1] + 24); saved = *patched; *patched = (u64)host_xcb(); }
    if (e.flags & 64) nedits = vk_strip_debug(st->x[0], edits, 8);
    u64 xmm0 = 0;
    static int trace = getenv("XEF_TRACE_THUNKS") ? 1 : 0;
    u64 r = xef_call_sysv(fn, ir, fr, stk, (u64)ns, &xmm0);
    if (patched) *patched = saved;
    while (nedits > 0) { nedits--; *edits[nedits].link = edits[nedits].node; }
    if ((e.flags & 64) && (i32)r == 0) g_vk_instance = *(void**)st->x[2];
    if ((e.flags & 128) && (i32)r == 0) g_vk_device = *(void**)st->x[3];
    if (trace)
        log_msg("thunk %s(%#lx, %#lx, %#lx, %#lx) = %#lx", e.name, (unsigned long)ir[0], (unsigned long)ir[1],
                (unsigned long)ir[2], (unsigned long)ir[3], (unsigned long)r);
    switch (e.sig[0]) {
    case 'v': break;
    case 'f': memset(st->v[0], 0, 16); memcpy(st->v[0], &xmm0, 4); break;
    case 'd': memset(st->v[0], 0, 16); memcpy(st->v[0], &xmm0, 8); break;
    case 'b': st->x[0] = (u8)r; break;
    case 'c': st->x[0] = (u64)(i64)(i8)r; break;
    case 's': st->x[0] = (u64)(i64)(i16)r; break;
    case 'S': st->x[0] = (u16)r; break;
    case 'i': st->x[0] = (u32)r; break;
    default: st->x[0] = r; break;
    }
}

}  // namespace xef
