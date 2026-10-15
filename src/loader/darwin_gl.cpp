// XEF-OSX — host OpenGL bridge (see darwin_gl.h). libGL/libX11 are dlopen'ed lazily so xef-osx keeps no
// link-time dependency on them (same approach as src/thunks/thunks.cpp).
#include "loader/darwin_gl.h"
#include "loader/darwin_hle.h"
#include "common/common.h"
#include "thunks/thunks.h"
#include <unordered_map>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <dlfcn.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <string>
#include <mutex>
#include <vector>

namespace xef {

namespace {

std::mutex g_gl_lock;
void* g_libgl = nullptr;
void* g_libx11 = nullptr;
void* (*g_getproc)(const unsigned char*) = nullptr;

bool load_libs() {
    if (g_libgl && g_libx11) return true;
    if (!g_libgl) g_libgl = dlopen("libGL.so.1", RTLD_NOW | RTLD_GLOBAL);
    if (!g_libgl) { XEF_LOG(1, "xef-osx: cannot load host libGL.so.1: %s", dlerror()); return false; }
    if (!g_libx11) g_libx11 = dlopen("libX11.so.6", RTLD_NOW | RTLD_GLOBAL);
    if (!g_libx11) { XEF_LOG(1, "xef-osx: cannot load host libX11.so.6: %s", dlerror()); return false; }
    g_getproc = (void* (*)(const unsigned char*))dlsym(g_libgl, "glXGetProcAddressARB");
    return true;
}

void* gl_sym(const char* n) {
    void* f = g_getproc ? g_getproc((const unsigned char*)n) : nullptr;
    if (!f) f = dlsym(g_libgl, n);
    return f;
}

template <class T> T xs(const char* n) { return (T)dlsym(g_libx11, n); }
template <class T> T gs(const char* n) { return (T)gl_sym(n); }

// ---- window shim ----------------------------------------------------------------------------
struct Win {
    Display* dpy = nullptr;
    ::Window win = 0;
    void* ctx = nullptr;     // GLXContext
    Atom wm_delete = 0;
    bool close = false;
    int w = 0, h = 0;
};
Win g_win;

const int kGlxRgba = 4, kGlxDouble = 5, kGlxDepth = 12;

int win_create(int w, int h, const char* title, int major, int minor) {   // major==0: legacy context
    std::lock_guard<std::mutex> lk(g_gl_lock);
    if (!load_libs() || g_win.dpy) return -1;
    auto XOpenDisplay_ = xs<Display* (*)(const char*)>("XOpenDisplay");
    auto XDefaultScreen_ = xs<int (*)(Display*)>("XDefaultScreen");
    auto XRootWindow_ = xs<::Window (*)(Display*, int)>("XRootWindow");
    auto XCreateColormap_ = xs<Colormap (*)(Display*, ::Window, Visual*, int)>("XCreateColormap");
    auto XCreateWindow_ = xs<::Window (*)(Display*, ::Window, int, int, unsigned, unsigned, unsigned, int,
                                          unsigned, Visual*, unsigned long, XSetWindowAttributes*)>("XCreateWindow");
    auto XMapWindow_ = xs<int (*)(Display*, ::Window)>("XMapWindow");
    auto XStoreName_ = xs<int (*)(Display*, ::Window, const char*)>("XStoreName");
    auto XInternAtom_ = xs<Atom (*)(Display*, const char*, int)>("XInternAtom");
    auto XSetWMProtocols_ = xs<int (*)(Display*, ::Window, Atom*, int)>("XSetWMProtocols");
    auto XWindowEvent_ = xs<int (*)(Display*, ::Window, long, XEvent*)>("XWindowEvent");
    auto XSync_ = xs<int (*)(Display*, int)>("XSync");
    auto XFree_ = xs<int (*)(void*)>("XFree");
    auto chooseVisual = gs<XVisualInfo* (*)(Display*, int, int*)>("glXChooseVisual");
    auto createContext = gs<void* (*)(Display*, XVisualInfo*, void*, int)>("glXCreateContext");
    auto makeCurrent = gs<int (*)(Display*, unsigned long, void*)>("glXMakeCurrent");
    if (!XOpenDisplay_ || !XCreateWindow_ || !chooseVisual || !createContext || !makeCurrent) return -1;

    Display* dpy = XOpenDisplay_(getenv("DISPLAY"));
    if (!dpy) { XEF_LOG(1, "xef_win_create: cannot open display %s", getenv("DISPLAY") ? getenv("DISPLAY") : "(null)"); return -1; }
    int scr = XDefaultScreen_(dpy);
    int attr[] = { kGlxRgba, kGlxDouble, kGlxDepth, 24, 0 };
    void* fbc = nullptr;
    XVisualInfo* vi = nullptr;
    if (major) {
        auto chooseFB = gs<void** (*)(Display*, int, const int*, int*)>("glXChooseFBConfig");
        auto visFromFB = gs<XVisualInfo* (*)(Display*, void*)>("glXGetVisualFromFBConfig");
        int fba[] = { 0x8010 /*DRAWABLE_TYPE*/, 1 /*WINDOW_BIT*/, 0x8011 /*RENDER_TYPE*/, 1, 5 /*DOUBLEBUFFER*/, 1,
                      8 /*RED*/, 8, 9, 8, 10, 8, 12 /*DEPTH*/, 24, 0 };
        int n = 0;
        void** fbs = chooseFB && visFromFB ? chooseFB(dpy, scr, fba, &n) : nullptr;
        if (fbs && n > 0) { fbc = fbs[0]; vi = visFromFB(dpy, fbc); }
        if (fbs && XFree_) XFree_(fbs);
    } else {
        vi = chooseVisual(dpy, scr, attr);
    }
    if (!vi) { XEF_LOG(1, "xef_win_create: no double-buffered RGBA depth-24 visual"); return -1; }

    ::Window root = XRootWindow_(dpy, scr);
    XSetWindowAttributes swa;
    memset(&swa, 0, sizeof swa);
    swa.colormap = XCreateColormap_(dpy, root, vi->visual, AllocNone);
    swa.event_mask = StructureNotifyMask | ExposureMask | KeyPressMask | KeyReleaseMask;
    ::Window win = XCreateWindow_(dpy, root, 0, 0, (unsigned)w, (unsigned)h, 0, vi->depth, InputOutput, vi->visual,
                                  CWColormap | CWEventMask, &swa);
    if (!win) return -1;
    XStoreName_(dpy, win, title ? title : "xef");
    Atom del = XInternAtom_(dpy, "WM_DELETE_WINDOW", 0);
    XSetWMProtocols_(dpy, win, &del, 1);
    XMapWindow_(dpy, win);
    XEvent ev;
    do { XWindowEvent_(dpy, win, StructureNotifyMask, &ev); } while (ev.type != MapNotify);

    void* ctx = nullptr;
    if (major) {
        auto createAttribs = gs<void* (*)(Display*, void*, void*, int, const int*)>("glXCreateContextAttribsARB");
        if (!createAttribs) { XEF_LOG(1, "xef_win_create_core: no glXCreateContextAttribsARB"); return -1; }
        int ca[] = { 0x2091 /*MAJOR*/, major, 0x2092 /*MINOR*/, minor,
                     0x9126 /*PROFILE_MASK*/, 1 /*CORE*/, 0x2094 /*FLAGS*/, 2 /*FORWARD_COMPAT*/, 0 };
        ctx = createAttribs(dpy, fbc, nullptr, 1, ca);
        if (!ctx) XEF_LOG(1, "xef_win_create_core: %d.%d core context not available", major, minor);
    } else {
        ctx = createContext(dpy, vi, nullptr, 1);   // legacy (compat) context, direct rendering
    }
    if (XFree_) XFree_(vi);
    if (!ctx || !makeCurrent(dpy, win, ctx)) { XEF_LOG(1, "xef_win_create: GLX context failed"); return -1; }
    XSync_(dpy, 0);
    g_win.dpy = dpy; g_win.win = win; g_win.ctx = ctx; g_win.wm_delete = del; g_win.w = w; g_win.h = h;
    return 0;
}

int xef_win_create(int w, int h, const char* title) { return win_create(w, h, title, 0, 0); }

// Core-profile (forward-compatible) context; Mesa hands out the highest version it supports (llvmpipe: 4.5),
// which satisfies a 3.2 request just like Apple's 3.2 core.
int xef_win_create_core(int w, int h, const char* title, int major, int minor) {
    return win_create(w, h, title, major > 0 ? major : 3, major > 0 ? minor : 2);
}

void xef_win_swap(void) {
    std::lock_guard<std::mutex> lk(g_gl_lock);
    if (!g_win.dpy) return;
    static auto swap = gs<void (*)(Display*, unsigned long)>("glXSwapBuffers");
    static auto XPending_ = xs<int (*)(Display*)>("XPending");
    static auto XNextEvent_ = xs<int (*)(Display*, XEvent*)>("XNextEvent");
    swap(g_win.dpy, g_win.win);
    while (XPending_(g_win.dpy) > 0) {
        XEvent ev;
        XNextEvent_(g_win.dpy, &ev);
        if (ev.type == ClientMessage && (Atom)ev.xclient.data.l[0] == g_win.wm_delete) g_win.close = true;
        else if (ev.type == DestroyNotify) g_win.close = true;
    }
}

int xef_win_poll(void) { return g_win.close ? 1 : 0; }

int xef_win_dump(const char* path) {
    std::lock_guard<std::mutex> lk(g_gl_lock);
    if (!g_win.dpy || !path) return -1;
    auto readPixels = gs<void (*)(int, int, int, int, unsigned, unsigned, void*)>("glReadPixels");
    auto pixelStore = gs<void (*)(unsigned, int)>("glPixelStorei");
    auto finish = gs<void (*)()>("glFinish");
    if (!readPixels || !pixelStore) return -1;
    int w = g_win.w, h = g_win.h;
    std::vector<unsigned char> px((size_t)w * h * 3);
    finish();
    pixelStore(0x0D05 /*GL_PACK_ALIGNMENT*/, 1);
    readPixels(0, 0, w, h, 0x1907 /*GL_RGB*/, 0x1401 /*GL_UNSIGNED_BYTE*/, px.data());
    FILE* f = fopen(path, "wb");
    if (!f) return -1;
    fprintf(f, "P6\n%d %d\n255\n", w, h);
    for (int y = h - 1; y >= 0; y--) fwrite(&px[(size_t)y * w * 3], 3, (size_t)w, f);   // GL origin is bottom-left
    fclose(f);
    return 0;
}

// host fn -> signature, only for functions whose Darwin calls spill arguments to the stack
std::unordered_map<void*, const char*> g_stack_sig;

int arg_size(char c) {
    switch (c) {
    case 'b': case 'c': return 1;
    case 's': case 'S': return 2;
    case 'i': case 'f': return 4;
    default: return 8;
    }
}

void note_stack_sig(const char* gl_name, void* fn) {
    const char* sig = thunk_gl_sig(gl_name);
    if (!sig || !(sig = strchr(sig, ':'))) return;
    int ni = 0, nf = 0;
    for (const char* p = sig + 1; *p; p++) (*p == 'f' || *p == 'd') ? nf++ : ni++;
    if (ni > 8 || nf > 8) g_stack_sig[fn] = sig + 1;
}

struct WinFn { const char* name; void* fn; };
const WinFn kWinFns[] = {
    {"_xef_win_create", (void*)&xef_win_create}, {"_xef_win_create_core", (void*)&xef_win_create_core}, {"_xef_win_swap", (void*)&xef_win_swap},
    {"_xef_win_poll", (void*)&xef_win_poll},     {"_xef_win_dump", (void*)&xef_win_dump},
};

// Apple's VAO entry points are the core functions under another name
const char* apple_alias(const char* n) {
    if (!strcmp(n, "glGenVertexArraysAPPLE")) return "glGenVertexArrays";
    if (!strcmp(n, "glBindVertexArrayAPPLE")) return "glBindVertexArray";
    if (!strcmp(n, "glDeleteVertexArraysAPPLE")) return "glDeleteVertexArrays";
    if (!strcmp(n, "glIsVertexArrayAPPLE")) return "glIsVertexArray";
    return n;
}

} // namespace

uint64_t darwin_gl_resolve(const char* name) {
    if (!name) return 0;
    for (const WinFn& w : kWinFns)
        if (!strcmp(name, w.name)) return darwin_hle_register_function(name, w.fn);
    if (!(name[0] == '_' && name[1] == 'g' && name[2] == 'l' && name[3] >= 'A' && name[3] <= 'Z')) return 0;
    void* f;
    {
        std::lock_guard<std::mutex> lk(g_gl_lock);
        if (!load_libs()) return 0;
        f = gl_sym(apple_alias(name + 1));
    }
    if (!f) { XEF_LOG(1, "xef-osx: host libGL has no %s", name + 1); return 0; }
    {
        std::lock_guard<std::mutex> lk(g_gl_lock);
        note_stack_sig(name + 1, f);
    }
    return darwin_hle_register_function(name, f);
}

bool darwin_gl_repack(void* host_fn, const uint64_t* x, const uint64_t* v_lo, const uint64_t* guest_sp,
                      uint64_t* iregs, uint64_t* fregs, uint64_t* hstack, uint64_t* nstack) {
    const char* sig;
    {
        std::lock_guard<std::mutex> lk(g_gl_lock);
        auto it = g_stack_sig.find(host_fn);
        if (it == g_stack_sig.end()) return false;
        sig = it->second;
    }
    const unsigned char* gsp = (const unsigned char*)guest_sp;
    size_t off = 0;
    int gi = 0, gf = 0, ni = 0, nf = 0, ns = 0;
    for (const char* p = sig; *p; p++) {
        char c = *p;
        bool fp = c == 'f' || c == 'd';
        int sz = arg_size(c);
        uint64_t v = 0;
        if (fp ? gf < 8 : gi < 8) v = fp ? v_lo[gf++] : x[gi++];
        else {
            off = (off + sz - 1) & ~(size_t)(sz - 1);
            memcpy(&v, gsp + off, sz);   // zero-extended; sign handled below
            off += sz;
            if (c == 'c') v = (uint64_t)(int64_t)(int8_t)v;
            if (c == 's') v = (uint64_t)(int64_t)(int16_t)v;
        }
        if (fp) { if (c == 'f') v &= 0xffffffffull; }
        else switch (c) {
            case 'b': v = (uint8_t)v; break;
            case 'c': v = (uint64_t)(int64_t)(int8_t)v; break;
            case 's': v = (uint64_t)(int64_t)(int16_t)v; break;
            case 'S': v = (uint16_t)v; break;
            case 'i': v = (uint32_t)v; break;
            default: break;
        }
        if (fp ? nf < 8 : ni < 6) (fp ? fregs[nf++] : iregs[ni++]) = v;
        else if (ns < 32) hstack[ns++] = v;
        else return false;
    }
    *nstack = ns;
    return true;
}

uint64_t darwin_gl_fix_ret(const char* name, uint64_t ret) {
    if (!(name[0] == '_' && name[1] == 'g' && name[2] == 'l')) return ret;
    const char* n = name + 3;
    if (n[0] == 'I' && n[1] == 's' && n[2] >= 'A' && n[2] <= 'Z') return ret & 0xff;   // GLboolean
    static const char* const k32[] = { "GetError", "CheckFramebufferStatus", "CreateShader", "CreateProgram",
                                       "GetUniformLocation", "GetAttribLocation", "RenderMode", "GenLists",
                                       "GetUniformBlockIndex", "GetFragDataLocation", "ClientWaitSync" };
    for (const char* k : k32)
        if (!strncmp(n, k, strlen(k))) return ret & 0xffffffffu;
    return ret;
}

} // namespace xef
