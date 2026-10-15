// XEF-OSX — host OpenGL bridge (see darwin_gl.h). libGL/libX11 are dlopen'ed lazily so xef-osx keeps no
// link-time dependency on them (same approach as src/thunks/thunks.cpp).
#include "loader/darwin_gl.h"
#include "loader/darwin_hle.h"
#include "common/common.h"
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

int xef_win_create(int w, int h, const char* title) {
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
    XVisualInfo* vi = chooseVisual(dpy, scr, attr);
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

    void* ctx = createContext(dpy, vi, nullptr, 1);   // legacy (compat) context, direct rendering
    if (XFree_) XFree_(vi);
    if (!ctx || !makeCurrent(dpy, win, ctx)) { XEF_LOG(1, "xef_win_create: GLX context failed"); return -1; }
    XSync_(dpy, 0);
    g_win.dpy = dpy; g_win.win = win; g_win.ctx = ctx; g_win.wm_delete = del; g_win.w = w; g_win.h = h;
    return 0;
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

struct WinFn { const char* name; void* fn; };
const WinFn kWinFns[] = {
    {"_xef_win_create", (void*)&xef_win_create}, {"_xef_win_swap", (void*)&xef_win_swap},
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
    return darwin_hle_register_function(name, f);
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
