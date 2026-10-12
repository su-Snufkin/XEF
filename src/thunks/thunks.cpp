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

#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

#include <unistd.h>

#include <mutex>
#include <string>

#include "runtime/cpu_state.h"

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
void* (*g_getproc)(const unsigned char*);
void* (*g_XOpenDisplay)(const char*);
char* (*g_XDisplayString)(void*);

struct DpyMap { void* guest; void* host; };
DpyMap g_dpy[16];
int g_ndpy;

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
    g_XOpenDisplay = (void* (*)(const char*))dlsym(g_libx11, "XOpenDisplay");
    g_XDisplayString = (char* (*)(void*))dlsym(g_libx11, "XDisplayString");
    if (auto seh = (void* (*)(int (*)(void*, void*)))dlsym(g_libx11, "XSetErrorHandler")) seh(host_x_error);
}

void* resolve(int id) {
    std::lock_guard<std::mutex> lk(g_lock);
    if (g_fn[id]) return g_fn[id];
    load_libs();
    const char* name = kTable[id].name;
    void* f = nullptr;
    if (!strncmp(name, "xef_host_", 9)) f = dlsym(g_libx11, name + 9);
    else {
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
    for (int i = 0; i < g_ndpy; i++) if (g_dpy[i].guest == guest) return g_dpy[i].host;
    const char* name = g_XDisplayString(guest);
    void* h = g_XOpenDisplay(name);
    if (!h) fatal("--host-gl: cannot open display %s on the host", name ? name : "(null)");
    if (g_ndpy < 16) g_dpy[g_ndpy++] = {guest, h};
    return h;
}

}  // namespace

// --host-gl: the guest's GL libraries are replaced by the thunk shim (built next to the xef binary).
const char* thunk_lib_redirect(const char* path) {
    if (!g_host_gl || !path) return nullptr;
    const char* b = strrchr(path, '/');
    b = b ? b + 1 : path;
    if (strcmp(b, "libGL.so.1") && strcmp(b, "libGLX.so.0") && strcmp(b, "libOpenGL.so.0") && strcmp(b, "libGL.so"))
        return nullptr;
    static std::string shim;
    static std::once_flag once;
    std::call_once(once, [] {
        char exe[4096];
        ssize_t n = readlink("/proc/self/exe", exe, sizeof exe - 1);
        if (n <= 0) return;
        exe[n] = 0;
        std::string dir(exe);
        dir.resize(dir.rfind('/'));
        shim = dir + "/thunks/libGL.so.1";
        if (access(shim.c_str(), R_OK) != 0) fatal("--host-gl: guest shim %s not built (tools/build_thunks.sh)", shim.c_str());
    });
    return shim.c_str();
}

void thunk_dispatch(CpuState* st) {
    u64 id = st->x[17];
    if (id >= (u64)kCount) fatal("bad host thunk id %lu at %#lx", (unsigned long)id, (unsigned long)st->pc);
    const Entry& e = kTable[id];
    if (e.flags & 1) { st->x[0] = 0; return; }   // callbacks into the guest are not forwarded
    void* fn = __atomic_load_n(&g_fn[id], __ATOMIC_ACQUIRE);
    if (!fn) fn = resolve((int)id);
    u64 ir[6] = {}, fr[8] = {}, stk[32];
    int ni = 0, nf = 0, ns = 0, gi = 0, gf = 0, gs = 0;
    const u64* gstack = (const u64*)st->x[kGuestSP];
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
            switch (c) {   // AAPCS64 leaves the upper bits of small arguments unspecified
            case 'b': v = (u8)v; break;
            case 'c': v = (u64)(i64)(i8)v; break;
            case 's': v = (u64)(i64)(i16)v; break;
            case 'S': v = (u16)v; break;
            case 'i': v = (u32)v; break;
            case 'D': v = (u64)host_display((void*)v); break;
            default: break;
            }
        }
        if (fp ? nf < 8 : ni < 6) (fp ? fr[nf++] : ir[ni++]) = v;
        else if (ns < 32) stk[ns++] = v;
        else fatal("host thunk %s: too many arguments", e.name);
    }
    u64 xmm0 = 0;
    static int trace = getenv("XEF_TRACE_THUNKS") ? 1 : 0;
    u64 r = xef_call_sysv(fn, ir, fr, stk, (u64)ns, &xmm0);
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
