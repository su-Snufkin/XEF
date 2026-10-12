// XEF guest shim for --host-gl (AArch64). The generated stubs (gl_stubs.S) forward every GL/GLX
// function to the host's libGL. The functions here need guest-side work: results the guest
// releases with XFree() are copied into guest malloc() memory, and glXGetProcAddress returns
// this library's own stubs.
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

// The host talks to the X server on its own connection: requests the guest queued on its
// connection (e.g. XCreateWindow) have to be processed first.
void xef_guest_xsync(void* dpy) {
    static int (*xsync)(void*, int);
    if (!xsync) xsync = (int (*)(void*, int))dlsym(RTLD_DEFAULT, "XSync");
    if (xsync && dpy) xsync(dpy, 0);
}

typedef struct {   // XVisualInfo (identical layout on every LP64 Xlib)
    void* visual;
    unsigned long visualid;
    int screen, depth, c_class;
    unsigned long red_mask, green_mask, blue_mask;
    int colormap_size, bits_per_rgb;
} XVisualInfo;

void* xef_raw_glXChooseVisual(void* dpy, int screen, int* attribs);
void* xef_raw_glXGetVisualFromFBConfig(void* dpy, void* config);
void* xef_raw_glXGetVisualFromFBConfigSGIX(void* dpy, void* config);
void** xef_raw_glXChooseFBConfig(void* dpy, int screen, const int* attribs, int* n);
void** xef_raw_glXChooseFBConfigSGIX(void* dpy, int screen, int* attribs, int* n);
void** xef_raw_glXGetFBConfigs(void* dpy, int screen, int* n);
int xef_host_XFree(void* p);

static XVisualInfo* guest_visual(XVisualInfo* h) {
    if (!h) return 0;
    XVisualInfo* g = malloc(sizeof *g);
    if (g) memcpy(g, h, sizeof *g);
    xef_host_XFree(h);
    return g;
}

static void** guest_configs(void** h, int* n) {
    if (!h) return 0;
    int k = n ? *n : 0;
    void** g = malloc(sizeof(void*) * (k ? k : 1));
    if (g) memcpy(g, h, sizeof(void*) * k);
    xef_host_XFree(h);
    return g;
}

XVisualInfo* glXChooseVisual(void* dpy, int screen, int* attribs) {
    return guest_visual(xef_raw_glXChooseVisual(dpy, screen, attribs));
}
XVisualInfo* glXGetVisualFromFBConfig(void* dpy, void* config) {
    return guest_visual(xef_raw_glXGetVisualFromFBConfig(dpy, config));
}
XVisualInfo* glXGetVisualFromFBConfigSGIX(void* dpy, void* config) {
    return guest_visual(xef_raw_glXGetVisualFromFBConfigSGIX(dpy, config));
}
void** glXChooseFBConfig(void* dpy, int screen, const int* attribs, int* n) {
    return guest_configs(xef_raw_glXChooseFBConfig(dpy, screen, attribs, n), n);
}
void** glXChooseFBConfigSGIX(void* dpy, int screen, int* attribs, int* n) {
    return guest_configs(xef_raw_glXChooseFBConfigSGIX(dpy, screen, attribs, n), n);
}
void** glXGetFBConfigs(void* dpy, int screen, int* n) {
    return guest_configs(xef_raw_glXGetFBConfigs(dpy, screen, n), n);
}

// ---- glXGetProcAddress: our own stubs, by name
void* glXGetProcAddress(const unsigned char* name);
void* eglGetDisplay(void* native);
void* eglGetPlatformDisplay(unsigned platform, void* native, const long* attribs);
void* eglGetPlatformDisplayEXT(unsigned platform, void* native, const int* attribs);
void* eglGetProcAddress(const char* name);
#define DECL(n) void n(void);
typedef struct { const char* name; void* fn; } Proc;
#include "gl_decls.inc"
static const Proc kProcs[] = {
#include "gl_names.inc"
};

static int cmp(const void* k, const void* e) { return strcmp((const char*)k, ((const Proc*)e)->name); }

void* glXGetProcAddressARB(const unsigned char* name) {
    if (!name) return 0;
    const Proc* p = bsearch(name, kProcs, sizeof kProcs / sizeof kProcs[0], sizeof kProcs[0], cmp);
    if (p) return p->fn;
    static const Proc kShim[] = {
        {"eglGetDisplay", (void*)eglGetDisplay},
        {"eglGetPlatformDisplay", (void*)eglGetPlatformDisplay},
        {"eglGetPlatformDisplayEXT", (void*)eglGetPlatformDisplayEXT},
        {"eglGetProcAddress", (void*)eglGetProcAddress},
        {"glXChooseFBConfig", (void*)glXChooseFBConfig},
        {"glXChooseFBConfigSGIX", (void*)glXChooseFBConfigSGIX},
        {"glXChooseVisual", (void*)glXChooseVisual},
        {"glXGetFBConfigs", (void*)glXGetFBConfigs},
        {"glXGetProcAddress", (void*)glXGetProcAddress},
        {"glXGetProcAddressARB", (void*)glXGetProcAddressARB},
        {"glXGetVisualFromFBConfig", (void*)glXGetVisualFromFBConfig},
        {"glXGetVisualFromFBConfigSGIX", (void*)glXGetVisualFromFBConfigSGIX},
    };
    for (unsigned i = 0; i < sizeof kShim / sizeof kShim[0]; i++)
        if (!strcmp((const char*)name, kShim[i].name)) return kShim[i].fn;
    return 0;
}
void* glXGetProcAddress(const unsigned char* name) { return glXGetProcAddressARB(name); }

// ---- EGL: remember the guest's X display so window-surface calls can XSync it first
static void* g_egl_xdpy;
void xef_guest_xsync_egl(void) { xef_guest_xsync(g_egl_xdpy); }

void* xef_raw_eglGetDisplay(void* native);
void* xef_raw_eglGetPlatformDisplay(unsigned platform, void* native, const long* attribs);
void* xef_raw_eglGetPlatformDisplayEXT(unsigned platform, void* native, const int* attribs);

void* eglGetDisplay(void* native) {
    if (native) g_egl_xdpy = native;
    return xef_raw_eglGetDisplay(native);
}
void* eglGetPlatformDisplay(unsigned platform, void* native, const long* attribs) {
    if (platform == 0x31D5 && native) g_egl_xdpy = native;
    return xef_raw_eglGetPlatformDisplay(platform, native, attribs);
}
void* eglGetPlatformDisplayEXT(unsigned platform, void* native, const int* attribs) {
    if (platform == 0x31D5 && native) g_egl_xdpy = native;
    return xef_raw_eglGetPlatformDisplayEXT(platform, native, attribs);
}
void* eglGetProcAddress(const char* name) { return glXGetProcAddressARB((const unsigned char*)name); }
