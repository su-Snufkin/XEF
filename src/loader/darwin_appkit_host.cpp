// XEF-OSX — host side of AppKit-lite: one X11 window with a GLX context per handle (Xlib/GLX are reached through
// the lazy dlopen helpers of darwin_gl.cpp). The window is created unmapped; a GLX context on an unmapped window
// renders fine (Mesa), so the HIDDEN mode (never ordered front) still has a working GL context.
#include "loader/darwin_appkit_host.h"
#include "loader/darwin_gl.h"
#include "loader/darwin_hle.h"
#include "common/common.h"
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>
#include <X11/XKBlib.h>
#include <string.h>
#include <stdlib.h>
#include <mutex>
#include <map>

namespace xef {
namespace {

#define XEF_EV_CLOSE 1000
#define XEF_EV_RESIZE 1001
struct HostEvent { int type, keycode, x, y, flags; };

struct HWin { ::Window win = 0; void* ctx = nullptr; int w = 0, h = 0; };
std::mutex g_lock;
Display* g_dpy = nullptr;
Atom g_wm_delete = 0;
std::map<int, HWin> g_wins;
int g_next = 1;
int g_cur = 0;
int g_buttons = 0;   // held X buttons bitmask (1 left, 2 middle, 4 right)

template <class T> T X(const char* n) { return (T)darwin_gl_host_x(n); }
template <class T> T G(const char* n) { return (T)darwin_gl_host_gl(n); }

bool open_display() {
    if (g_dpy) return true;
    if (!darwin_gl_host_libs()) return false;
    auto open = X<Display* (*)(const char*)>("XOpenDisplay");
    if (!open) return false;
    g_dpy = open(getenv("DISPLAY"));
    if (!g_dpy) { XEF_LOG(1, "xef_host: cannot open display %s", getenv("DISPLAY") ? getenv("DISPLAY") : "(null)"); return false; }
    g_wm_delete = X<Atom (*)(Display*, const char*, int)>("XInternAtom")(g_dpy, "WM_DELETE_WINDOW", 0);
    return true;
}

HWin* find(int h) { auto it = g_wins.find(h); return it == g_wins.end() ? nullptr : &it->second; }

// X keysym -> macOS virtual key code (kVK_*); -1 = unknown
int mac_key(KeySym ks) {
    if (ks >= 'A' && ks <= 'Z') ks += 32;
    switch (ks) {
    case 'a': return 0;  case 's': return 1;  case 'd': return 2;  case 'f': return 3;  case 'h': return 4;
    case 'g': return 5;  case 'z': return 6;  case 'x': return 7;  case 'c': return 8;  case 'v': return 9;
    case 'b': return 11; case 'q': return 12; case 'w': return 13; case 'e': return 14; case 'r': return 15;
    case 'y': return 16; case 't': return 17; case '1': return 18; case '2': return 19; case '3': return 20;
    case '4': return 21; case '6': return 22; case '5': return 23; case '=': return 24; case '9': return 25;
    case '7': return 26; case '-': return 27; case '8': return 28; case '0': return 29; case ']': return 30;
    case 'o': return 31; case 'u': return 32; case '[': return 33; case 'i': return 34; case 'p': return 35;
    case 'l': return 37; case 'j': return 38; case '\'': return 39; case 'k': return 40; case ';': return 41;
    case '\\': return 42; case ',': return 43; case '/': return 44; case 'n': return 45; case 'm': return 46;
    case '.': return 47; case '`': return 50;
    case XK_Return: case XK_KP_Enter: return 36; case XK_Tab: return 48; case XK_space: return 49;
    case XK_BackSpace: return 51; case XK_Escape: return 53; case XK_Delete: return 117;
    case XK_Left: return 123; case XK_Right: return 124; case XK_Down: return 125; case XK_Up: return 126;
    case XK_Home: return 115; case XK_End: return 119; case XK_Page_Up: return 116; case XK_Page_Down: return 121;
    case XK_F1: return 122; case XK_F2: return 120; case XK_F3: return 99; case XK_F4: return 118;
    case XK_F5: return 96; case XK_F6: return 97; case XK_F7: return 98; case XK_F8: return 100;
    case XK_F9: return 101; case XK_F10: return 109; case XK_F11: return 103; case XK_F12: return 111;
    case XK_Shift_L: return 56; case XK_Shift_R: return 60; case XK_Control_L: return 59; case XK_Control_R: return 62;
    case XK_Alt_L: return 58; case XK_Alt_R: return 61; case XK_Super_L: case XK_Meta_L: return 55;
    case XK_Super_R: case XK_Meta_R: return 54; case XK_Caps_Lock: return 57;
    case XK_KP_0: return 82; case XK_KP_1: return 83; case XK_KP_2: return 84; case XK_KP_3: return 85;
    case XK_KP_4: return 86; case XK_KP_5: return 87; case XK_KP_6: return 88; case XK_KP_7: return 89;
    case XK_KP_8: return 91; case XK_KP_9: return 92;
    default: return -1;
    }
}

int mac_flags(unsigned st) {
    int f = 0;
    if (st & LockMask) f |= 1 << 16;
    if (st & ShiftMask) f |= 1 << 17;
    if (st & ControlMask) f |= 1 << 18;
    if (st & Mod1Mask) f |= 1 << 19;
    if (st & Mod4Mask) f |= 1 << 20;
    return f;
}

int xef_host_window_create(int x, int y, int w, int h, const char* title) {
    std::lock_guard<std::mutex> lk(g_lock);
    if (!open_display()) return 0;
    auto chooseVisual = G<XVisualInfo* (*)(Display*, int, int*)>("glXChooseVisual");
    auto createContext = G<void* (*)(Display*, XVisualInfo*, void*, int)>("glXCreateContext");
    if (!chooseVisual || !createContext) return 0;
    int scr = X<int (*)(Display*)>("XDefaultScreen")(g_dpy);
    int attr[] = { 4 /*RGBA*/, 5 /*DOUBLEBUFFER*/, 12 /*DEPTH*/, 24, 0 };
    XVisualInfo* vi = chooseVisual(g_dpy, scr, attr);
    if (!vi) { XEF_LOG(1, "xef_host: no double-buffered RGBA depth-24 visual"); return 0; }
    ::Window root = X<::Window (*)(Display*, int)>("XRootWindow")(g_dpy, scr);
    XSetWindowAttributes swa;
    memset(&swa, 0, sizeof swa);
    swa.colormap = X<Colormap (*)(Display*, ::Window, Visual*, int)>("XCreateColormap")(g_dpy, root, vi->visual, AllocNone);
    swa.event_mask = StructureNotifyMask | ExposureMask | KeyPressMask | KeyReleaseMask | ButtonPressMask |
                     ButtonReleaseMask | PointerMotionMask;
    if (w < 1) w = 1;
    if (h < 1) h = 1;
    // AppKit-lite assumes a 1440x900 screen: keep the window on the real (possibly smaller) host screen
    int sw = X<int (*)(Display*, int)>("XDisplayWidth")(g_dpy, scr), sh_ = X<int (*)(Display*, int)>("XDisplayHeight")(g_dpy, scr);
    if (x + w > sw) x = sw - w;
    if (y + h > sh_) y = sh_ - h;
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    ::Window win = X<::Window (*)(Display*, ::Window, int, int, unsigned, unsigned, unsigned, int, unsigned, Visual*,
                                  unsigned long, XSetWindowAttributes*)>("XCreateWindow")(
        g_dpy, root, x, y, (unsigned)w, (unsigned)h, 0, vi->depth, InputOutput, vi->visual, CWColormap | CWEventMask, &swa);
    void* ctx = win ? createContext(g_dpy, vi, nullptr, 1) : nullptr;
    X<int (*)(void*)>("XFree")(vi);
    if (!win || !ctx) { XEF_LOG(1, "xef_host: window/GLX context creation failed"); return 0; }
    X<int (*)(Display*, ::Window, const char*)>("XStoreName")(g_dpy, win, title && *title ? title : "xef");
    X<int (*)(Display*, ::Window, Atom*, int)>("XSetWMProtocols")(g_dpy, win, &g_wm_delete, 1);
    // position hint so a window manager honors x,y
    XSizeHints sh;
    memset(&sh, 0, sizeof sh);
    sh.flags = PPosition | PSize; sh.x = x; sh.y = y; sh.width = w; sh.height = h;
    X<void (*)(Display*, ::Window, XSizeHints*)>("XSetWMNormalHints")(g_dpy, win, &sh);
    X<int (*)(Display*, int)>("XSync")(g_dpy, 0);
    int id = g_next++;
    HWin hw; hw.win = win; hw.ctx = ctx; hw.w = w; hw.h = h;
    g_wins[id] = hw;
    return id;
}

void xef_host_window_show(int h) {
    std::lock_guard<std::mutex> lk(g_lock);
    if (HWin* w = find(h)) {
        X<int (*)(Display*, ::Window)>("XMapWindow")(g_dpy, w->win);
        X<int (*)(Display*, int)>("XSync")(g_dpy, 0);
        // wait for MapNotify so the first swap is not dropped by a not-yet-mapped drawable
        // (only this window's StructureNotify events are consumed; no other event kind)
        XEvent ev;
        do { X<int (*)(Display*, ::Window, long, XEvent*)>("XWindowEvent")(g_dpy, w->win, StructureNotifyMask, &ev); }
        while (ev.type != MapNotify);
    }
}

void xef_host_window_set_title(int h, const char* t) {
    std::lock_guard<std::mutex> lk(g_lock);
    if (HWin* w = find(h)) X<int (*)(Display*, ::Window, const char*)>("XStoreName")(g_dpy, w->win, t ? t : "");
}

void xef_host_window_close(int h) {
    std::lock_guard<std::mutex> lk(g_lock);
    HWin* w = find(h);
    if (!w) return;
    if (g_cur == h) { G<int (*)(Display*, unsigned long, void*)>("glXMakeCurrent")(g_dpy, 0, nullptr); g_cur = 0; }
    G<void (*)(Display*, void*)>("glXDestroyContext")(g_dpy, w->ctx);
    X<int (*)(Display*, ::Window)>("XDestroyWindow")(g_dpy, w->win);
    X<int (*)(Display*, int)>("XSync")(g_dpy, 0);
    g_wins.erase(h);
}

int xef_host_pump(void* out) {
    std::lock_guard<std::mutex> lk(g_lock);
    if (!g_dpy) return 0;
    static auto pending = X<int (*)(Display*)>("XPending");
    static auto next = X<int (*)(Display*, XEvent*)>("XNextEvent");
    static auto lookup = X<KeySym (*)(Display*, unsigned, int, int)>("XkbKeycodeToKeysym");
    HostEvent* o = (HostEvent*)out;
    while (pending(g_dpy) > 0) {
        XEvent ev;
        next(g_dpy, &ev);
        memset(o, 0, sizeof *o);
        switch (ev.type) {
        case ClientMessage:
            if ((Atom)ev.xclient.data.l[0] != g_wm_delete) continue;
            o->type = XEF_EV_CLOSE; return 1;
        case ConfigureNotify:
            for (auto& kv : g_wins)
                if (kv.second.win == ev.xconfigure.window && (kv.second.w != ev.xconfigure.width || kv.second.h != ev.xconfigure.height)) {
                    kv.second.w = ev.xconfigure.width; kv.second.h = ev.xconfigure.height;
                    o->type = XEF_EV_RESIZE; o->x = kv.second.w; o->y = kv.second.h; return 1;
                }
            continue;
        case KeyPress: case KeyRelease: {
            KeySym ks = lookup ? lookup(g_dpy, ev.xkey.keycode, 0, 0) : 0;
            int mk = mac_key(ks);
            if (mk < 0) continue;
            o->type = ev.type == KeyPress ? 10 : 11; o->keycode = mk; o->flags = mac_flags(ev.xkey.state);
            o->x = ev.xkey.x; o->y = ev.xkey.y; return 1;
        }
        case ButtonPress: case ButtonRelease: {
            unsigned b = ev.xbutton.button;
            bool dn = ev.type == ButtonPress;
            o->x = ev.xbutton.x; o->y = ev.xbutton.y; o->flags = mac_flags(ev.xbutton.state);
            if (b >= 4 && b <= 7) {   // wheel: 4 up, 5 down, (6/7 horizontal ignored)
                if (!dn || b > 5) continue;
                o->type = 22; o->keycode = b == 4 ? 1 : -1; return 1;
            }
            int bit = b == 1 ? 1 : b == 2 ? 2 : b == 3 ? 4 : 0;
            if (!bit) continue;
            if (dn) g_buttons |= bit; else g_buttons &= ~bit;
            o->type = b == 1 ? (dn ? 1 : 2) : b == 3 ? (dn ? 3 : 4) : (dn ? 25 : 26);
            return 1;
        }
        case MotionNotify:
            o->x = ev.xmotion.x; o->y = ev.xmotion.y; o->flags = mac_flags(ev.xmotion.state);
            o->type = (g_buttons & 1) ? 6 : (g_buttons & 4) ? 7 : (g_buttons & 2) ? 27 : 5;
            return 1;
        default: continue;
        }
    }
    return 0;
}

void xef_host_gl_make_current(int h) {
    std::lock_guard<std::mutex> lk(g_lock);
    if (!g_dpy) return;
    static auto mc = G<int (*)(Display*, unsigned long, void*)>("glXMakeCurrent");
    HWin* w = h ? find(h) : nullptr;
    if (w) { if (mc(g_dpy, w->win, w->ctx)) g_cur = h; else XEF_LOG(1, "xef_host: glXMakeCurrent failed"); }
    else { mc(g_dpy, 0, nullptr); g_cur = 0; }
}

void xef_host_swap(int h) {
    std::lock_guard<std::mutex> lk(g_lock);
    HWin* w = find(h);
    if (!w) return;
    static auto swap = G<void (*)(Display*, unsigned long)>("glXSwapBuffers");
    swap(g_dpy, w->win);
}

struct Fn { const char* name; void* fn; };
const Fn kFns[] = {
    {"_xef_host_window_create", (void*)&xef_host_window_create}, {"_xef_host_window_show", (void*)&xef_host_window_show},
    {"_xef_host_window_set_title", (void*)&xef_host_window_set_title}, {"_xef_host_window_close", (void*)&xef_host_window_close},
    {"_xef_host_pump", (void*)&xef_host_pump}, {"_xef_host_gl_make_current", (void*)&xef_host_gl_make_current},
    {"_xef_host_swap", (void*)&xef_host_swap},
};

} // namespace

uint64_t darwin_appkit_host_resolve(const char* name) {
    for (const Fn& f : kFns)
        if (!strcmp(name, f.name)) return darwin_hle_register_function(name, f.fn);
    return 0;
}

} // namespace xef
