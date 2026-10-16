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
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>
#include <vector>
#include <string>
#include <mutex>
#include <map>

namespace xef {
namespace {

#define XEF_EV_CLOSE 1000
#define XEF_EV_RESIZE 1001
#define XEF_EV_FOCUS_IN 1002
#define XEF_EV_FOCUS_OUT 1003
struct HostEvent { int type, keycode, x, y, flags, handle; };

struct HWin { ::Window win = 0; void* ctx = nullptr; int w = 0, h = 0, x = 0, y = 0; unsigned long visid = 0; bool core = false; unsigned int metal_tex = 0; };
std::mutex g_lock;
Display* g_dpy = nullptr;
Atom g_wm_delete = 0;
Atom g_net_wm_state = 0;
Atom g_net_wm_state_fullscreen = 0;
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
    g_net_wm_state = X<Atom (*)(Display*, const char*, int)>("XInternAtom")(g_dpy, "_NET_WM_STATE", 0);
    g_net_wm_state_fullscreen = X<Atom (*)(Display*, const char*, int)>("XInternAtom")(g_dpy, "_NET_WM_STATE_FULLSCREEN", 0);
    return true;
}

HWin* find(int h) { auto it = g_wins.find(h); return it == g_wins.end() ? nullptr : &it->second; }
int find_handle(::Window w) {
    for (auto& kv : g_wins)
        if (kv.second.win == w) return kv.first;
    return 0;
}

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
                     ButtonReleaseMask | PointerMotionMask | EnterWindowMask | LeaveWindowMask | FocusChangeMask;
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
    unsigned long visid = vi->visualid;
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
    HWin hw; hw.win = win; hw.ctx = ctx; hw.w = w; hw.h = h; hw.x = x; hw.y = y; hw.visid = visid;
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

void xef_host_window_hide(int h) {
    std::lock_guard<std::mutex> lk(g_lock);
    if (HWin* w = find(h)) {
        X<int (*)(Display*, ::Window)>("XUnmapWindow")(g_dpy, w->win);
        X<int (*)(Display*, int)>("XSync")(g_dpy, 0);
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

void xef_host_window_set_fullscreen(int h, int enable) {
    std::lock_guard<std::mutex> lk(g_lock);
    HWin* hw = find(h);
    if (!hw || !g_dpy) return;
    int scr = X<int (*)(Display*)>("XDefaultScreen")(g_dpy);
    ::Window root = X<::Window (*)(Display*, int)>("XRootWindow")(g_dpy, scr);
    XClientMessageEvent ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = ClientMessage;
    ev.window = hw->win;
    ev.message_type = g_net_wm_state;
    ev.format = 32;
    ev.data.l[0] = enable ? 1 : 0;
    ev.data.l[1] = g_net_wm_state_fullscreen;
    ev.data.l[2] = 0;
    ev.data.l[3] = 1;
    X<int (*)(Display*, ::Window, int, long, XEvent*)>("XSendEvent")(
        g_dpy, root, False, SubstructureNotifyMask | SubstructureRedirectMask, (XEvent*)&ev);
    X<int (*)(Display*, int)>("XSync")(g_dpy, 0);
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
            o->type = XEF_EV_CLOSE;
            o->handle = find_handle(ev.xclient.window);
            return 1;
        case ConfigureNotify:
            for (auto& kv : g_wins) {
                if (kv.second.win == ev.xconfigure.window) {
                    int rx = 0, ry = 0;
                    ::Window child = 0;
                    int scr = X<int (*)(Display*)>("XDefaultScreen")(g_dpy);
                    ::Window root = X<::Window (*)(Display*, int)>("XRootWindow")(g_dpy, scr);
                    X<int (*)(Display*, ::Window, ::Window, int, int, int*, int*, ::Window*)>("XTranslateCoordinates")(
                        g_dpy, kv.second.win, root, 0, 0, &rx, &ry, &child);
                    if (kv.second.w != ev.xconfigure.width || kv.second.h != ev.xconfigure.height ||
                        kv.second.x != rx || kv.second.y != ry) {
                        kv.second.w = ev.xconfigure.width;
                        kv.second.h = ev.xconfigure.height;
                        kv.second.x = rx;
                        kv.second.y = ry;
                        o->type = XEF_EV_RESIZE;
                        o->x = kv.second.w;
                        o->y = kv.second.h;
                        o->handle = kv.first;
                        return 1;
                    }
                }
            }
            continue;
        case EnterNotify: case LeaveNotify:
            if (ev.xcrossing.mode != NotifyNormal) continue;
            o->type = ev.type == EnterNotify ? 8 : 9; o->x = ev.xcrossing.x; o->y = ev.xcrossing.y;
            o->flags = mac_flags(ev.xcrossing.state);
            o->handle = find_handle(ev.xcrossing.window);
            return 1;
        case FocusIn: case FocusOut:
            if (ev.xfocus.mode != NotifyNormal && ev.xfocus.mode != NotifyWhileGrabbed) continue;
            o->type = ev.type == FocusIn ? XEF_EV_FOCUS_IN : XEF_EV_FOCUS_OUT;
            o->handle = find_handle(ev.xfocus.window);
            return 1;
        case KeyPress: case KeyRelease: {
            KeySym ks = lookup ? lookup(g_dpy, ev.xkey.keycode, 0, 0) : 0;
            int mk = mac_key(ks);
            if (mk < 0) continue;
            o->type = ev.type == KeyPress ? 10 : 11; o->keycode = mk; o->flags = mac_flags(ev.xkey.state);
            o->x = ev.xkey.x; o->y = ev.xkey.y;
            o->handle = find_handle(ev.xkey.window);
            // modifier keys are NSEventTypeFlagsChanged on macOS, carrying the flags AFTER the change
            // (X reports the state from before the event)
            int bit = ks == XK_Shift_L || ks == XK_Shift_R ? 1 << 17 : ks == XK_Control_L || ks == XK_Control_R ? 1 << 18 :
                      ks == XK_Alt_L || ks == XK_Alt_R ? 1 << 19 : ks == XK_Super_L || ks == XK_Super_R || ks == XK_Meta_L || ks == XK_Meta_R ? 1 << 20 :
                      ks == XK_Caps_Lock ? 1 << 16 : 0;
            if (bit) {
                o->type = 12;
                if (bit == 1 << 16) o->flags ^= bit;
                else if (ev.type == KeyPress) o->flags |= bit;
                else o->flags &= ~bit;
            }
            return 1;
        }
        case ButtonPress: case ButtonRelease: {
            unsigned b = ev.xbutton.button;
            bool dn = ev.type == ButtonPress;
            o->x = ev.xbutton.x; o->y = ev.xbutton.y; o->flags = mac_flags(ev.xbutton.state);
            o->handle = find_handle(ev.xbutton.window);
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
            o->handle = find_handle(ev.xmotion.window);
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

void xef_host_present_pixels(int h, const void* pixels, int pw, int ph, int format) {
    std::lock_guard<std::mutex> lk(g_lock);
    HWin* w = find(h);
    if (!w || !g_dpy) return;
    static auto mc = G<int (*)(Display*, unsigned long, void*)>("glXMakeCurrent");
    static auto swap = G<void (*)(Display*, unsigned long)>("glXSwapBuffers");
    if (!pixels || pw <= 0 || ph <= 0) {
        if (swap) swap(g_dpy, w->win);
        return;
    }
    if (g_cur != h && mc) {
        if (mc(g_dpy, w->win, w->ctx)) g_cur = h;
    }
    static auto glViewport_fn = G<void (*)(int, int, int, int)>("glViewport");
    static auto glDisable_fn = G<void (*)(unsigned int)>("glDisable");
    static auto glEnable_fn = G<void (*)(unsigned int)>("glEnable");
    static auto glGenTextures_fn = G<void (*)(int, unsigned int*)>("glGenTextures");
    static auto glBindTexture_fn = G<void (*)(unsigned int, unsigned int)>("glBindTexture");
    static auto glTexParameteri_fn = G<void (*)(unsigned int, unsigned int, int)>("glTexParameteri");
    static auto glPixelStorei_fn = G<void (*)(unsigned int, int)>("glPixelStorei");
    static auto glTexImage2D_fn = G<void (*)(unsigned int, int, int, int, int, int, unsigned int, unsigned int, const void*)>("glTexImage2D");
    static auto glMatrixMode_fn = G<void (*)(unsigned int)>("glMatrixMode");
    static auto glLoadIdentity_fn = G<void (*)()>("glLoadIdentity");
    static auto glColor4f_fn = G<void (*)(float, float, float, float)>("glColor4f");
    static auto glBegin_fn = G<void (*)(unsigned int)>("glBegin");
    static auto glEnd_fn = G<void (*)()>("glEnd");
    static auto glTexCoord2f_fn = G<void (*)(float, float)>("glTexCoord2f");
    static auto glVertex2f_fn = G<void (*)(float, float)>("glVertex2f");
    static auto glBindProgram_fn = G<void (*)(unsigned int)>("glUseProgram");

    if (glBindProgram_fn) glBindProgram_fn(0);
    if (glViewport_fn) glViewport_fn(0, 0, w->w > 0 ? w->w : pw, w->h > 0 ? w->h : ph);
    if (glDisable_fn) {
        glDisable_fn(0x0B71 /*GL_DEPTH_TEST*/);
        glDisable_fn(0x0C11 /*GL_SCISSOR_TEST*/);
        glDisable_fn(0x0B44 /*GL_CULL_FACE*/);
        glDisable_fn(0x0BE2 /*GL_BLEND*/);
        glDisable_fn(0x0BC0 /*GL_ALPHA_TEST*/);
    }
    if (glEnable_fn) glEnable_fn(0x0DE1 /*GL_TEXTURE_2D*/);
    if (!w->metal_tex && glGenTextures_fn) glGenTextures_fn(1, &w->metal_tex);
    if (w->metal_tex && glBindTexture_fn && glTexImage2D_fn) {
        glBindTexture_fn(0x0DE1 /*GL_TEXTURE_2D*/, w->metal_tex);
        if (glTexParameteri_fn) {
            glTexParameteri_fn(0x0DE1, 0x2801 /*GL_TEXTURE_MIN_FILTER*/, 0x2601 /*GL_LINEAR*/);
            glTexParameteri_fn(0x0DE1, 0x2800 /*GL_TEXTURE_MAG_FILTER*/, 0x2601 /*GL_LINEAR*/);
            glTexParameteri_fn(0x0DE1, 0x2802 /*GL_TEXTURE_WRAP_S*/, 0x812F /*GL_CLAMP_TO_EDGE*/);
            glTexParameteri_fn(0x0DE1, 0x2803 /*GL_TEXTURE_WRAP_T*/, 0x812F /*GL_CLAMP_TO_EDGE*/);
        }
        if (glPixelStorei_fn) {
            glPixelStorei_fn(0x0CF5 /*GL_UNPACK_ALIGNMENT*/, 1);
            glPixelStorei_fn(0x0CF2 /*GL_UNPACK_ROW_LENGTH*/, 0);
        }
        unsigned int gl_fmt = (format == 80 || format == 81) ? 0x80E1 /*GL_BGRA*/ : 0x1908 /*GL_RGBA*/;
        glTexImage2D_fn(0x0DE1 /*GL_TEXTURE_2D*/, 0, 0x1908 /*GL_RGBA*/, pw, ph, 0, gl_fmt, 0x1401 /*GL_UNSIGNED_BYTE*/, pixels);
    }
    if (glMatrixMode_fn && glLoadIdentity_fn) {
        glMatrixMode_fn(0x1701 /*GL_PROJECTION*/);
        glLoadIdentity_fn();
        glMatrixMode_fn(0x1700 /*GL_MODELVIEW*/);
        glLoadIdentity_fn();
    }
    if (glColor4f_fn) glColor4f_fn(1.0f, 1.0f, 1.0f, 1.0f);
    if (glBegin_fn && glEnd_fn && glTexCoord2f_fn && glVertex2f_fn) {
        glBegin_fn(0x0007 /*GL_QUADS*/);
        glTexCoord2f_fn(0.0f, 0.0f); glVertex2f_fn(-1.0f,  1.0f);
        glTexCoord2f_fn(1.0f, 0.0f); glVertex2f_fn( 1.0f,  1.0f);
        glTexCoord2f_fn(1.0f, 1.0f); glVertex2f_fn( 1.0f, -1.0f);
        glTexCoord2f_fn(0.0f, 1.0f); glVertex2f_fn(-1.0f, -1.0f);
        glEnd_fn();
    }
    if (glDisable_fn) glDisable_fn(0x0DE1 /*GL_TEXTURE_2D*/);
    if (swap) swap(g_dpy, w->win);
}

// ---- profile / screen / frame / pointer ----------------------------------------------------------------
void xef_host_gl_set_profile(int h, int profile) {
    std::lock_guard<std::mutex> lk(g_lock);
    HWin* w = find(h);
    if (!w || !g_dpy) return;
    bool want_core = profile == 0x3200 || profile == 0x4100;
    if (want_core == w->core) return;
    void* newctx = nullptr;
    if (want_core) {
        auto chooseFB = G<void** (*)(Display*, int, const int*, int*)>("glXChooseFBConfig");
        auto getAttrib = G<int (*)(Display*, void*, int, int*)>("glXGetFBConfigAttrib");
        auto createAttribs = G<void* (*)(Display*, void*, void*, int, const int*)>("glXCreateContextAttribsARB");
        if (!chooseFB || !getAttrib || !createAttribs) { XEF_LOG(1, "xef_host: no glXCreateContextAttribsARB, keeping the compatibility context"); return; }
        int scr = X<int (*)(Display*)>("XDefaultScreen")(g_dpy);
        int fba[] = { 0x8010 /*DRAWABLE_TYPE*/, 1 /*WINDOW_BIT*/, 0x8011 /*RENDER_TYPE*/, 1, 5 /*DOUBLEBUFFER*/, 1, 12 /*DEPTH*/, 24, 0 };
        int n = 0;
        void** fbs = chooseFB(g_dpy, scr, fba, &n);
        void* fbc = nullptr;
        for (int i = 0; i < n && !fbc; i++) {
            int vid = 0;
            if (getAttrib(g_dpy, fbs[i], 0x800B /*GLX_VISUAL_ID*/, &vid) == 0 && (unsigned long)vid == w->visid) fbc = fbs[i];
        }
        if (fbs) X<int (*)(void*)>("XFree")(fbs);
        if (!fbc) { XEF_LOG(1, "xef_host: no FBConfig for the window visual"); return; }
        int major = profile == 0x4100 ? 4 : 3, minor = profile == 0x4100 ? 1 : 2;
        int ca[] = { 0x2091 /*MAJOR*/, major, 0x2092 /*MINOR*/, minor, 0x9126 /*PROFILE_MASK*/, 1 /*CORE*/,
                     0x2094 /*FLAGS*/, 2 /*FORWARD_COMPAT*/, 0 };
        newctx = createAttribs(g_dpy, fbc, nullptr, 1, ca);
        if (!newctx) { XEF_LOG(1, "xef_host: %d.%d core context not available", major, minor); return; }
    } else {
        auto chooseVisual = G<XVisualInfo* (*)(Display*, int, int*)>("glXChooseVisual");
        auto createContext = G<void* (*)(Display*, XVisualInfo*, void*, int)>("glXCreateContext");
        int scr = X<int (*)(Display*)>("XDefaultScreen")(g_dpy);
        int attr[] = { 4, 5, 12, 24, 0 };
        XVisualInfo* vi = chooseVisual(g_dpy, scr, attr);
        if (!vi) return;
        newctx = createContext(g_dpy, vi, nullptr, 1);
        X<int (*)(void*)>("XFree")(vi);
        if (!newctx) return;
    }
    bool was_cur = g_cur == h;
    if (was_cur) G<int (*)(Display*, unsigned long, void*)>("glXMakeCurrent")(g_dpy, 0, nullptr);
    G<void (*)(Display*, void*)>("glXDestroyContext")(g_dpy, w->ctx);
    w->ctx = newctx; w->core = want_core;
    if (was_cur) G<int (*)(Display*, unsigned long, void*)>("glXMakeCurrent")(g_dpy, w->win, w->ctx);
}

void xef_host_screen_info(int* sw, int* sh, int* mmw, int* mmh) {
    std::lock_guard<std::mutex> lk(g_lock);
    int w = 1440, h = 900, mw = 381, mh = 238;
    if (open_display()) {
        int scr = X<int (*)(Display*)>("XDefaultScreen")(g_dpy);
        w = X<int (*)(Display*, int)>("XDisplayWidth")(g_dpy, scr);
        h = X<int (*)(Display*, int)>("XDisplayHeight")(g_dpy, scr);
        mw = X<int (*)(Display*, int)>("XDisplayWidthMM")(g_dpy, scr);
        mh = X<int (*)(Display*, int)>("XDisplayHeightMM")(g_dpy, scr);
    } else { mw = (int)(w * 25.4 / 96); mh = (int)(h * 25.4 / 96); }
    if (sw) *sw = w;
    if (sh) *sh = h;
    if (mmw) *mmw = mw;
    if (mmh) *mmh = mh;
}

void xef_host_window_set_frame(int h, int x, int y, int w, int ht) {
    std::lock_guard<std::mutex> lk(g_lock);
    HWin* hw = find(h);
    if (!hw) return;
    if (w < 1) w = 1;
    if (ht < 1) ht = 1;
    X<int (*)(Display*, ::Window, int, int, unsigned, unsigned)>("XMoveResizeWindow")(g_dpy, hw->win, x, y, (unsigned)w, (unsigned)ht);
    X<int (*)(Display*, int)>("XSync")(g_dpy, 0);
    hw->w = w; hw->h = ht; hw->x = x; hw->y = y;   // already reported to the guest by its own setFrame; no ConfigureNotify echo
}

int xef_host_pointer(int h, int* sx, int* sy, int* wx, int* wy) {
    std::lock_guard<std::mutex> lk(g_lock);
    HWin* hw = find(h);
    if (!g_dpy) return 0;
    int scr = X<int (*)(Display*)>("XDefaultScreen")(g_dpy);
    ::Window root = X<::Window (*)(Display*, int)>("XRootWindow")(g_dpy, scr), r, c;
    int rx = 0, ry = 0, x = 0, y = 0;
    unsigned mask = 0;
    if (!X<int (*)(Display*, ::Window, ::Window*, ::Window*, int*, int*, int*, int*, unsigned*)>("XQueryPointer")(
            g_dpy, hw ? hw->win : root, &r, &c, &rx, &ry, &x, &y, &mask)) return 0;
    if (sx) *sx = rx;
    if (sy) *sy = ry;
    if (wx) *wx = x;
    if (wy) *wy = y;
    return 1;
}

void xef_host_pointer_warp(int x, int y) {
    std::lock_guard<std::mutex> lk(g_lock);
    if (!open_display()) return;
    int scr = X<int (*)(Display*)>("XDefaultScreen")(g_dpy);
    ::Window root = X<::Window (*)(Display*, int)>("XRootWindow")(g_dpy, scr);
    X<int (*)(Display*, ::Window, ::Window, int, int, unsigned, unsigned, int, int)>("XWarpPointer")(g_dpy, 0, root, 0, 0, 0, 0, x, y);
    X<int (*)(Display*, int)>("XSync")(g_dpy, 0);
}

int xef_host_mouse_buttons() {
    std::lock_guard<std::mutex> lk(g_lock);
    int mask = 0;
    if (g_buttons & 1) mask |= (1 << 0);
    if (g_buttons & 4) mask |= (1 << 1);
    if (g_buttons & 2) mask |= (1 << 2);
    return mask;
}

int xef_host_window_get_geometry(int h, int* rx, int* ry, int* rw, int* rh) {
    std::lock_guard<std::mutex> lk(g_lock);
    HWin* hw = find(h);
    if (!hw || !g_dpy) return 0;
    int scr = X<int (*)(Display*)>("XDefaultScreen")(g_dpy);
    ::Window root = X<::Window (*)(Display*, int)>("XRootWindow")(g_dpy, scr);
    ::Window child = 0;
    int x = 0, y = 0;
    if (!X<int (*)(Display*, ::Window, ::Window, int, int, int*, int*, ::Window*)>("XTranslateCoordinates")(
            g_dpy, hw->win, root, 0, 0, &x, &y, &child)) {
        return 0;
    }
    ::Window r = 0;
    int gx = 0, gy = 0;
    unsigned int gw = hw->w, gh = hw->h, bw = 0, depth = 0;
    if (X<int (*)(Display*, ::Window, ::Window*, int*, int*, unsigned int*, unsigned int*, unsigned int*, unsigned int*)>("XGetGeometry")(
            g_dpy, hw->win, &r, &gx, &gy, &gw, &gh, &bw, &depth)) {
        hw->w = gw;
        hw->h = gh;
    }
    hw->x = x;
    hw->y = y;
    if (rx) *rx = x;
    if (ry) *ry = y;
    if (rw) *rw = hw->w;
    if (rh) *rh = hw->h;
    return 1;
}

int xef_host_file_dialog(const char* title, const char* initial_path, int is_save, int is_dir, int allow_multi, char* out_buf, int out_len) {
    if (!out_buf || out_len <= 0) return 0;
    out_buf[0] = '\0';

    int pipefd[2];
    if (pipe(pipefd) != 0) return 0;

    pid_t pid = fork();
    if (pid < 0) {
        close(pipefd[0]);
        close(pipefd[1]);
        return 0;
    }

    if (pid == 0) {
        close(pipefd[0]);
        dup2(pipefd[1], STDOUT_FILENO);
        close(pipefd[1]);

        int devnull = open("/dev/null", O_WRONLY);
        if (devnull >= 0) {
            dup2(devnull, STDERR_FILENO);
            close(devnull);
        }

        std::vector<std::string> arg_strs;
        arg_strs.push_back("zenity");
        arg_strs.push_back("--file-selection");

        if (is_dir) {
            arg_strs.push_back("--directory");
        }
        if (is_save) {
            arg_strs.push_back("--save");
            arg_strs.push_back("--confirm-overwrite");
        }
        if (allow_multi) {
            arg_strs.push_back("--multiple");
            arg_strs.push_back("--separator=\n");
        }
        if (title && *title) {
            arg_strs.push_back(std::string("--title=") + title);
        }
        if (initial_path && *initial_path) {
            arg_strs.push_back(std::string("--filename=") + initial_path);
        }

        std::vector<char*> argv;
        for (auto& s : arg_strs) {
            argv.push_back(const_cast<char*>(s.c_str()));
        }
        argv.push_back(nullptr);

        execvp("zenity", argv.data());
        _exit(127);
    }

    close(pipefd[1]);
    int total_read = 0;
    while (total_read < out_len - 1) {
        ssize_t n = read(pipefd[0], out_buf + total_read, out_len - 1 - total_read);
        if (n <= 0) break;
        total_read += (int)n;
    }
    out_buf[total_read] = '\0';
    close(pipefd[0]);

    int status = 0;
    waitpid(pid, &status, 0);

    while (total_read > 0 && (out_buf[total_read - 1] == '\n' || out_buf[total_read - 1] == '\r')) {
        out_buf[--total_read] = '\0';
    }

    if (WIFEXITED(status) && WEXITSTATUS(status) == 0 && total_read > 0) {
        return 1;
    }
    return 0;
}

struct Fn { const char* name; void* fn; };
const Fn kFns[] = {
    {"_xef_host_window_create", (void*)&xef_host_window_create}, {"_xef_host_window_show", (void*)&xef_host_window_show}, {"_xef_host_window_hide", (void*)&xef_host_window_hide},
    {"_xef_host_window_set_title", (void*)&xef_host_window_set_title}, {"_xef_host_window_close", (void*)&xef_host_window_close},
    {"_xef_host_window_set_fullscreen", (void*)&xef_host_window_set_fullscreen},
    {"_xef_host_pump", (void*)&xef_host_pump}, {"_xef_host_gl_make_current", (void*)&xef_host_gl_make_current},
    {"_xef_host_swap", (void*)&xef_host_swap},
    {"_xef_host_gl_set_profile", (void*)&xef_host_gl_set_profile}, {"_xef_host_screen_info", (void*)&xef_host_screen_info},
    {"_xef_host_window_set_frame", (void*)&xef_host_window_set_frame}, {"_xef_host_pointer", (void*)&xef_host_pointer},
    {"_xef_host_pointer_warp", (void*)&xef_host_pointer_warp},
    {"_xef_host_mouse_buttons", (void*)&xef_host_mouse_buttons},
    {"_xef_host_window_get_geometry", (void*)&xef_host_window_get_geometry},
    {"_xef_host_file_dialog", (void*)&xef_host_file_dialog},
    {"_xef_host_present_pixels", (void*)&xef_host_present_pixels},
};

} // namespace

uint64_t darwin_appkit_host_resolve(const char* name) {
    for (const Fn& f : kFns)
        if (!strcmp(name, f.name)) return darwin_hle_register_function(name, f.fn);
    return 0;
}

} // namespace xef
