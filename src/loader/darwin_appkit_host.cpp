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
#include <unordered_map>
#include "../../rootfs-src/appkit/xef_host.h"
#include "darwin_metal_vk.h"

namespace xef {
namespace {

#define XEF_EV_CLOSE 1000
#define XEF_EV_RESIZE 1001
#define XEF_EV_FOCUS_IN 1002
#define XEF_EV_FOCUS_OUT 1003
struct HostEvent { int type, keycode, x, y, flags, handle; };

struct HWin { ::Window win = 0; void* ctx = nullptr; int w = 0, h = 0, x = 0, y = 0; unsigned long visid = 0; bool core = false; unsigned int metal_tex = 0; int metal_tex_w = 0, metal_tex_h = 0; };
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

extern "C" void xef_host_present_pixels(int h, const void* pixels, int pw, int ph, int format) {
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
    static auto glTexSubImage2D_fn = G<void (*)(unsigned int, int, int, int, int, int, unsigned int, unsigned int, const void*)>("glTexSubImage2D");
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
    if (w->metal_tex && glBindTexture_fn) {
        glBindTexture_fn(0x0DE1 /*GL_TEXTURE_2D*/, w->metal_tex);
        if (glPixelStorei_fn) {
            glPixelStorei_fn(0x0CF5 /*GL_UNPACK_ALIGNMENT*/, 1);
            glPixelStorei_fn(0x0CF2 /*GL_UNPACK_ROW_LENGTH*/, 0);
        }
        unsigned int gl_fmt = (format == 80 || format == 81) ? 0x80E1 /*GL_BGRA*/ : 0x1908 /*GL_RGBA*/;
        if (w->metal_tex_w != pw || w->metal_tex_h != ph) {
            if (glTexParameteri_fn) {
                glTexParameteri_fn(0x0DE1, 0x2801 /*GL_TEXTURE_MIN_FILTER*/, 0x2601 /*GL_LINEAR*/);
                glTexParameteri_fn(0x0DE1, 0x2800 /*GL_TEXTURE_MAG_FILTER*/, 0x2601 /*GL_LINEAR*/);
                glTexParameteri_fn(0x0DE1, 0x2802 /*GL_TEXTURE_WRAP_S*/, 0x812F /*GL_CLAMP_TO_EDGE*/);
                glTexParameteri_fn(0x0DE1, 0x2803 /*GL_TEXTURE_WRAP_T*/, 0x812F /*GL_CLAMP_TO_EDGE*/);
            }
            if (glTexImage2D_fn) {
                glTexImage2D_fn(0x0DE1 /*GL_TEXTURE_2D*/, 0, 0x1908 /*GL_RGBA*/, pw, ph, 0, gl_fmt, 0x1401 /*GL_UNSIGNED_BYTE*/, pixels);
            }
            w->metal_tex_w = pw;
            w->metal_tex_h = ph;
        } else if (glTexSubImage2D_fn) {
            glTexSubImage2D_fn(0x0DE1 /*GL_TEXTURE_2D*/, 0, 0, 0, pw, ph, gl_fmt, 0x1401 /*GL_UNSIGNED_BYTE*/, pixels);
        }
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

// ---- Metal hardware GPU acceleration -------------------------------------------------------------------

struct HostTex {
    unsigned int tex = 0;
    unsigned int fbo = 0;
    int w = 0, h = 0;
    int fmt = 0;
    bool is_rt = false;
};
static std::unordered_map<uint32_t, HostTex> g_host_texs;
static uint32_t g_next_tex_id = 1;

static bool ensure_gl_context(int handle) {
    if (!g_dpy && !open_display()) return false;
    static auto mc = G<int (*)(Display*, unsigned long, void*)>("glXMakeCurrent");
    if (!mc) return false;
    int h = handle;
    if (!h) {
        if (g_cur && find(g_cur)) h = g_cur;
        else if (!g_wins.empty()) h = g_wins.begin()->first;
    }
    HWin* w = h ? find(h) : nullptr;
    if (!w) return false;
    if (g_cur != h) {
        if (mc(g_dpy, w->win, w->ctx)) g_cur = h;
        else return false;
    }
    return true;
}

static void ensure_tex_gl(HostTex& ht) {
    if (ht.tex != 0) return;
    static auto glGenTextures_fn = G<void (*)(int, unsigned int*)>("glGenTextures");
    static auto glBindTexture_fn = G<void (*)(unsigned int, unsigned int)>("glBindTexture");
    static auto glTexParameteri_fn = G<void (*)(unsigned int, unsigned int, int)>("glTexParameteri");
    static auto glTexImage2D_fn = G<void (*)(unsigned int, int, int, int, int, int, unsigned int, unsigned int, const void*)>("glTexImage2D");

    if (!glGenTextures_fn || !glBindTexture_fn || !glTexImage2D_fn) return;
    glGenTextures_fn(1, &ht.tex);
    glBindTexture_fn(0x0DE1 /*GL_TEXTURE_2D*/, ht.tex);
    if (glTexParameteri_fn) {
        glTexParameteri_fn(0x0DE1, 0x2801 /*GL_TEXTURE_MIN_FILTER*/, 0x2601 /*GL_LINEAR*/);
        glTexParameteri_fn(0x0DE1, 0x2800 /*GL_TEXTURE_MAG_FILTER*/, 0x2601 /*GL_LINEAR*/);
        glTexParameteri_fn(0x0DE1, 0x2802 /*GL_TEXTURE_WRAP_S*/, 0x812F /*GL_CLAMP_TO_EDGE*/);
        glTexParameteri_fn(0x0DE1, 0x2803 /*GL_TEXTURE_WRAP_T*/, 0x812F /*GL_CLAMP_TO_EDGE*/);
    }
    unsigned int gl_fmt = (ht.fmt == 80 || ht.fmt == 81) ? 0x80E1 /*GL_BGRA*/ : 0x1908 /*GL_RGBA*/;
    glTexImage2D_fn(0x0DE1 /*GL_TEXTURE_2D*/, 0, 0x8058 /*GL_RGBA8*/, ht.w, ht.h, 0, gl_fmt, 0x1401 /*GL_UNSIGNED_BYTE*/, nullptr);
}

static unsigned int compile_shader(unsigned int type, const char* src) {
    static auto glCreateShader_fn = G<unsigned int (*)(unsigned int)>("glCreateShader");
    static auto glShaderSource_fn = G<void (*)(unsigned int, int, const char* const*, const int*)>("glShaderSource");
    static auto glCompileShader_fn = G<void (*)(unsigned int)>("glCompileShader");
    static auto glGetShaderiv_fn = G<void (*)(unsigned int, unsigned int, int*)>("glGetShaderiv");
    static auto glGetShaderInfoLog_fn = G<void (*)(unsigned int, int, int*, char*)>("glGetShaderInfoLog");
    static auto glDeleteShader_fn = G<void (*)(unsigned int)>("glDeleteShader");

    if (!glCreateShader_fn || !glShaderSource_fn || !glCompileShader_fn) return 0;
    unsigned int shader = glCreateShader_fn(type);
    glShaderSource_fn(shader, 1, &src, nullptr);
    glCompileShader_fn(shader);
    int status = 0;
    if (glGetShaderiv_fn) glGetShaderiv_fn(shader, 0x8B81 /*GL_COMPILE_STATUS*/, &status);
    if (!status) {
        char log[512] = {0};
        if (glGetShaderInfoLog_fn) glGetShaderInfoLog_fn(shader, sizeof(log), nullptr, log);
        XEF_LOG(1, "xef_metal_host: shader compile failed: %s", log);
        if (glDeleteShader_fn) glDeleteShader_fn(shader);
        return 0;
    }
    return shader;
}

static unsigned int link_program(unsigned int vs, unsigned int fs, const std::vector<std::pair<int, const char*>>& attribs) {
    static auto glCreateProgram_fn = G<unsigned int (*)()>("glCreateProgram");
    static auto glAttachShader_fn = G<void (*)(unsigned int, unsigned int)>("glAttachShader");
    static auto glBindAttribLocation_fn = G<void (*)(unsigned int, unsigned int, const char*)>("glBindAttribLocation");
    static auto glLinkProgram_fn = G<void (*)(unsigned int)>("glLinkProgram");
    static auto glGetProgramiv_fn = G<void (*)(unsigned int, unsigned int, int*)>("glGetProgramiv");
    static auto glGetProgramInfoLog_fn = G<void (*)(unsigned int, int, int*, char*)>("glGetProgramInfoLog");

    if (!glCreateProgram_fn || !glAttachShader_fn || !glLinkProgram_fn) return 0;
    unsigned int prog = glCreateProgram_fn();
    glAttachShader_fn(prog, vs);
    glAttachShader_fn(prog, fs);
    if (glBindAttribLocation_fn) {
        for (const auto& a : attribs) {
            glBindAttribLocation_fn(prog, a.first, a.second);
        }
    }
    glLinkProgram_fn(prog);
    int status = 0;
    if (glGetProgramiv_fn) glGetProgramiv_fn(prog, 0x8B82 /*GL_LINK_STATUS*/, &status);
    if (!status) {
        char log[512] = {0};
        if (glGetProgramInfoLog_fn) glGetProgramInfoLog_fn(prog, sizeof(log), nullptr, log);
        XEF_LOG(1, "xef_metal_host: program link failed: %s", log);
        return 0;
    }
    return prog;
}

static unsigned int g_metal_prog = 0;
static int g_u_target_size = -1;
static int g_u_frag_mode = -1;
static int g_u_color_scale = -1;
static int g_u_uv_left_top = -1;
static int g_u_uv_dims = -1;
static int g_u_tex = -1;
static int g_u_flip_y = -1;

static unsigned int g_metal_vao = 0;
static unsigned int g_metal_vbo = 0;
static unsigned int g_metal_ibo = 0;

static unsigned int g_present_prog = 0;
static int g_present_u_tex = -1;
static unsigned int g_present_vao = 0;
static unsigned int g_present_vbo = 0;

static void ensure_metal_program() {
    if (g_metal_prog != 0) return;
    static auto glGetUniformLocation_fn = G<int (*)(unsigned int, const char*)>("glGetUniformLocation");

    const char* vs_src =
        "#version 130\n"
        "in vec3 in_pos;\n"
        "in vec2 in_uv;\n"
        "in vec4 in_col;\n"
        "uniform vec2 u_target_size;\n"
        "out vec2 v_uv;\n"
        "out vec4 v_col;\n"
        "void main() {\n"
        "    float ndc_x = (in_pos.x / u_target_size.x) * 2.0 - 1.0;\n"
        "    float ndc_y = 1.0 - (in_pos.y / u_target_size.y) * 2.0;\n"
        "    gl_Position = vec4(ndc_x, ndc_y, in_pos.z, 1.0);\n"
        "    v_uv = in_uv;\n"
        "    v_col = in_col;\n"
        "}\n";

    const char* fs_src =
        "#version 130\n"
        "uniform sampler2D u_tex;\n"
        "uniform int u_frag_mode;\n"
        "uniform float u_color_scale;\n"
        "uniform vec2 u_uv_left_top;\n"
        "uniform vec2 u_uv_dims;\n"
        "uniform int u_flip_y;\n"
        "in vec2 v_uv;\n"
        "in vec4 v_col;\n"
        "out vec4 fragColor;\n"
        "void main() {\n"
        "    if (u_frag_mode == 1) {\n"
        "        fragColor = vec4(v_col.rgb * u_color_scale, v_col.a);\n"
        "    } else if (u_frag_mode == 5) {\n"
        "        fragColor = v_col;\n"
        "    } else {\n"
        "        vec2 tc = v_uv;\n"
        "        if (u_frag_mode == 4) {\n"
        "            tc = v_uv * u_uv_dims + u_uv_left_top;\n"
        "        }\n"
        "        if (u_flip_y != 0) {\n"
        "            tc.y = 1.0 - tc.y;\n"
        "        }\n"
        "        if (u_frag_mode == 4) {\n"
        "            fragColor = texture(u_tex, tc);\n"
        "        } else if (u_frag_mode == 3) {\n"
        "            vec4 t = texture(u_tex, tc);\n"
        "            fragColor = vec4(t.rgb * v_col.rgb * u_color_scale, v_col.a);\n"
        "        } else {\n"
        "            vec4 t = texture(u_tex, tc);\n"
        "            fragColor = vec4(t.rgb * v_col.rgb * u_color_scale, t.a * v_col.a);\n"
        "        }\n"
        "    }\n"
        "}\n";

    unsigned int vs = compile_shader(0x8B31 /*GL_VERTEX_SHADER*/, vs_src);
    unsigned int fs = compile_shader(0x8B30 /*GL_FRAGMENT_SHADER*/, fs_src);
    if (!vs || !fs) return;

    std::vector<std::pair<int, const char*>> attribs = {
        {0, "in_pos"},
        {1, "in_uv"},
        {2, "in_col"}
    };
    g_metal_prog = link_program(vs, fs, attribs);
    if (g_metal_prog && glGetUniformLocation_fn) {
        g_u_target_size = glGetUniformLocation_fn(g_metal_prog, "u_target_size");
        g_u_frag_mode   = glGetUniformLocation_fn(g_metal_prog, "u_frag_mode");
        g_u_color_scale = glGetUniformLocation_fn(g_metal_prog, "u_color_scale");
        g_u_uv_left_top = glGetUniformLocation_fn(g_metal_prog, "u_uv_left_top");
        g_u_uv_dims     = glGetUniformLocation_fn(g_metal_prog, "u_uv_dims");
        g_u_flip_y      = glGetUniformLocation_fn(g_metal_prog, "u_flip_y");
        g_u_tex         = glGetUniformLocation_fn(g_metal_prog, "u_tex");
    }
}

static void ensure_present_program() {
    if (g_present_prog != 0) return;
    static auto glGetUniformLocation_fn = G<int (*)(unsigned int, const char*)>("glGetUniformLocation");

    const char* vs_src =
        "#version 130\n"
        "in vec2 in_pos;\n"
        "in vec2 in_uv;\n"
        "out vec2 v_uv;\n"
        "void main() {\n"
        "    gl_Position = vec4(in_pos, 0.0, 1.0);\n"
        "    v_uv = in_uv;\n"
        "}\n";

    const char* fs_src =
        "#version 130\n"
        "uniform sampler2D u_tex;\n"
        "in vec2 v_uv;\n"
        "out vec4 fragColor;\n"
        "void main() {\n"
        "    fragColor = texture(u_tex, v_uv);\n"
        "}\n";

    unsigned int vs = compile_shader(0x8B31, vs_src);
    unsigned int fs = compile_shader(0x8B30, fs_src);
    if (!vs || !fs) return;

    std::vector<std::pair<int, const char*>> attribs = {
        {0, "in_pos"},
        {1, "in_uv"}
    };
    g_present_prog = link_program(vs, fs, attribs);
    if (g_present_prog && glGetUniformLocation_fn) {
        g_present_u_tex = glGetUniformLocation_fn(g_present_prog, "u_tex");
    }
}

static void ensure_buffers() {
    static auto glGenVertexArrays_fn = G<void (*)(int, unsigned int*)>("glGenVertexArrays");
    static auto glGenBuffers_fn = G<void (*)(int, unsigned int*)>("glGenBuffers");
    if (glGenVertexArrays_fn && !g_metal_vao) glGenVertexArrays_fn(1, &g_metal_vao);
    if (glGenBuffers_fn && !g_metal_vbo) glGenBuffers_fn(1, &g_metal_vbo);
    if (glGenBuffers_fn && !g_metal_ibo) glGenBuffers_fn(1, &g_metal_ibo);
}

static void ensure_present_buffers() {
    static auto glGenVertexArrays_fn = G<void (*)(int, unsigned int*)>("glGenVertexArrays");
    static auto glGenBuffers_fn = G<void (*)(int, unsigned int*)>("glGenBuffers");
    static auto glBindVertexArray_fn = G<void (*)(unsigned int)>("glBindVertexArray");
    static auto glBindBuffer_fn = G<void (*)(unsigned int, unsigned int)>("glBindBuffer");
    static auto glBufferData_fn = G<void (*)(unsigned int, size_t, const void*, unsigned int)>("glBufferData");
    static auto glEnableVertexAttribArray_fn = G<void (*)(unsigned int)>("glEnableVertexAttribArray");
    static auto glVertexAttribPointer_fn = G<void (*)(unsigned int, int, unsigned int, unsigned char, int, const void*)>("glVertexAttribPointer");

    if (g_present_vbo != 0) return;
    if (glGenVertexArrays_fn) glGenVertexArrays_fn(1, &g_present_vao);
    if (glGenBuffers_fn) glGenBuffers_fn(1, &g_present_vbo);

    float quad_data[24] = {
        -1.0f,  1.0f, 0.0f, 1.0f,
         1.0f,  1.0f, 1.0f, 1.0f,
         1.0f, -1.0f, 1.0f, 0.0f,
        -1.0f,  1.0f, 0.0f, 1.0f,
         1.0f, -1.0f, 1.0f, 0.0f,
        -1.0f, -1.0f, 0.0f, 0.0f,
    };

    if (glBindVertexArray_fn && g_present_vao) glBindVertexArray_fn(g_present_vao);
    if (glBindBuffer_fn && g_present_vbo) {
        glBindBuffer_fn(0x8892 /*GL_ARRAY_BUFFER*/, g_present_vbo);
        if (glBufferData_fn) glBufferData_fn(0x8892, sizeof(quad_data), quad_data, 0x88E4 /*GL_STATIC_DRAW*/);
        if (glVertexAttribPointer_fn && glEnableVertexAttribArray_fn) {
            glEnableVertexAttribArray_fn(0);
            glVertexAttribPointer_fn(0, 2, 0x1406 /*GL_FLOAT*/, 0, 4 * sizeof(float), (void*)0);
            glEnableVertexAttribArray_fn(1);
            glVertexAttribPointer_fn(1, 2, 0x1406 /*GL_FLOAT*/, 0, 4 * sizeof(float), (void*)(2 * sizeof(float)));
        }
    }
}

static inline unsigned int map_blend_factor(int factor) {
    switch (factor) {
    case 0: return 0;          /* GL_ZERO */
    case 1: return 1;          /* GL_ONE */
    case 2: return 0x0300;     /* GL_SRC_COLOR */
    case 3: return 0x0301;     /* GL_ONE_MINUS_SRC_COLOR */
    case 4: return 0x0302;     /* GL_SRC_ALPHA */
    case 5: return 0x0303;     /* GL_ONE_MINUS_SRC_ALPHA */
    case 6: return 0x0306;     /* GL_DST_COLOR */
    case 7: return 0x0307;     /* GL_ONE_MINUS_DST_COLOR */
    case 8: return 0x0304;     /* GL_DST_ALPHA */
    case 9: return 0x0305;     /* GL_ONE_MINUS_DST_ALPHA */
    case 10: return 0x0308;    /* GL_SRC_ALPHA_SATURATE */
    case 11: return 0x8001;    /* GL_CONSTANT_COLOR */
    case 12: return 0x8002;    /* GL_ONE_MINUS_CONSTANT_COLOR */
    case 13: return 0x8003;    /* GL_CONSTANT_ALPHA */
    case 14: return 0x8004;    /* GL_ONE_MINUS_CONSTANT_ALPHA */
    default: return 1;
    }
}

static inline unsigned int map_blend_op(int op) {
    switch (op) {
    case 0: return 0x8006;     /* GL_FUNC_ADD */
    case 1: return 0x800A;     /* GL_FUNC_SUBTRACT */
    case 2: return 0x800B;     /* GL_FUNC_REVERSE_SUBTRACT */
    case 3: return 0x8007;     /* GL_MIN */
    case 4: return 0x8008;     /* GL_MAX */
    default: return 0x8006;
    }
}

uint32_t xef_host_metal_sampler_create(int min_filter, int mag_filter, int mip_filter,
                                       int s_address_mode, int t_address_mode, int r_address_mode,
                                       int max_aniso, int compare_fn, int border_color,
                                       float lod_min, float lod_max, int normalized_coords) {
    if (xef::metal_vk::is_available()) {
        return xef::metal_vk::sampler_create(min_filter, mag_filter, mip_filter,
                                             s_address_mode, t_address_mode, r_address_mode,
                                             max_aniso, compare_fn, border_color,
                                             lod_min, lod_max, normalized_coords);
    }
    return 1;
}

void xef_host_metal_sampler_destroy(uint32_t sampler_id) {
    if (xef::metal_vk::is_available()) {
        xef::metal_vk::sampler_destroy(sampler_id);
    }
}

uint32_t xef_host_metal_tex_create(int w, int h, int fmt, int is_render_target) {
    if (xef::metal_vk::is_available()) {
        return xef::metal_vk::tex_create(w, h, fmt, is_render_target);
    }
    std::lock_guard<std::mutex> lk(g_lock);
    uint32_t id = g_next_tex_id++;
    HostTex ht;
    ht.w = w > 0 ? w : 1;
    ht.h = h > 0 ? h : 1;
    ht.fmt = fmt;
    ht.is_rt = (is_render_target != 0);

    if (ensure_gl_context(0)) {
        ensure_tex_gl(ht);
        if (ht.is_rt) {
            static auto glGenFramebuffers_fn = G<void (*)(int, unsigned int*)>("glGenFramebuffers");
            static auto glBindFramebuffer_fn = G<void (*)(unsigned int, unsigned int)>("glBindFramebuffer");
            static auto glFramebufferTexture2D_fn = G<void (*)(unsigned int, unsigned int, unsigned int, unsigned int, int)>("glFramebufferTexture2D");
            if (glGenFramebuffers_fn && glBindFramebuffer_fn && glFramebufferTexture2D_fn) {
                glGenFramebuffers_fn(1, &ht.fbo);
                glBindFramebuffer_fn(0x8D40 /*GL_FRAMEBUFFER*/, ht.fbo);
                glFramebufferTexture2D_fn(0x8D40, 0x8CE0 /*GL_COLOR_ATTACHMENT0*/, 0x0DE1 /*GL_TEXTURE_2D*/, ht.tex, 0);
                glBindFramebuffer_fn(0x8D40, 0);
            }
        }
    }
    g_host_texs[id] = ht;
    return id;
}

uint32_t xef_host_metal_tex_create_ex(int w, int h, int depth, int layers, int texture_type, int fmt, int is_render_target) {
    if (xef::metal_vk::is_available()) {
        return xef::metal_vk::tex_create_ex(w, h, depth, layers, texture_type, fmt, is_render_target);
    }
    return xef_host_metal_tex_create(w, h, fmt, is_render_target);
}

uint32_t xef_host_metal_tex_create_view(uint32_t parent_id, int fmt,
                                        int swizzle_r, int swizzle_g, int swizzle_b, int swizzle_a,
                                        int base_mip, int mip_count, int base_layer, int layer_count) {
    if (xef::metal_vk::is_available()) {
        return xef::metal_vk::tex_create_view(parent_id, fmt, swizzle_r, swizzle_g, swizzle_b, swizzle_a,
                                             base_mip, mip_count, base_layer, layer_count);
    }
    return xef_host_metal_tex_create(64, 64, fmt, 0);
}

void xef_host_metal_tex_update_ex(uint32_t tex_id, int slice, int level, int x, int y, int z, int w, int h, int d, const void* data, int pitch, int image_pitch) {
    if (xef::metal_vk::is_available()) {
        xef::metal_vk::tex_update_ex(tex_id, slice, level, x, y, z, w, h, d, data, pitch, image_pitch);
        return;
    }
    if (!data || w <= 0 || h <= 0) return;
    std::lock_guard<std::mutex> lk(g_lock);
    auto it = g_host_texs.find(tex_id);
    if (it == g_host_texs.end()) return;
    if (!ensure_gl_context(0)) return;
    ensure_tex_gl(it->second);

    static auto glBindTexture_fn = G<void (*)(unsigned int, unsigned int)>("glBindTexture");
    static auto glTexSubImage2D_fn = G<void (*)(unsigned int, int, int, int, int, int, unsigned int, unsigned int, const void*)>("glTexSubImage2D");
    static auto glPixelStorei_fn = G<void (*)(unsigned int, int)>("glPixelStorei");

    if (!glBindTexture_fn || !glTexSubImage2D_fn) return;
    glBindTexture_fn(0x0DE1 /*GL_TEXTURE_2D*/, it->second.tex);

    unsigned int gl_fmt = (it->second.fmt == 80 || it->second.fmt == 81) ? 0x80E1 /*GL_BGRA*/ : 0x1908 /*GL_RGBA*/;

    if (glPixelStorei_fn) {
        glPixelStorei_fn(0x0CF5 /*GL_UNPACK_ALIGNMENT*/, 1);
        int bpp = 4;
        if (pitch > 0 && pitch != w * bpp) {
            glPixelStorei_fn(0x0CF2 /*GL_UNPACK_ROW_LENGTH*/, pitch / bpp);
        } else {
            glPixelStorei_fn(0x0CF2 /*GL_UNPACK_ROW_LENGTH*/, 0);
        }
    }

    glTexSubImage2D_fn(0x0DE1 /*GL_TEXTURE_2D*/, level, x, y, w, h, gl_fmt, 0x1401 /*GL_UNSIGNED_BYTE*/, data);

    if (glPixelStorei_fn) {
        glPixelStorei_fn(0x0CF2 /*GL_UNPACK_ROW_LENGTH*/, 0);
    }
}

void xef_host_metal_tex_update(uint32_t tex_id, int x, int y, int w, int h, const void* data, int pitch) {
    xef_host_metal_tex_update_ex(tex_id, 0, 0, x, y, 0, w, h, 1, data, pitch, 0);
}

void xef_host_metal_tex_copy(uint32_t src_tex_id, int sx, int sy, int sw, int sh, uint32_t dst_tex_id, int dx, int dy) {
    if (xef::metal_vk::is_available()) {
        xef::metal_vk::tex_copy(src_tex_id, sx, sy, sw, sh, dst_tex_id, dx, dy);
        return;
    }
    std::lock_guard<std::mutex> lk(g_lock);
    auto it_s = g_host_texs.find(src_tex_id);
    auto it_d = g_host_texs.find(dst_tex_id);
    if (it_s == g_host_texs.end() || it_d == g_host_texs.end()) return;
    if (!ensure_gl_context(0)) return;
    ensure_tex_gl(it_s->second);
    ensure_tex_gl(it_d->second);

    static auto glGenFramebuffers_fn = G<void (*)(int, unsigned int*)>("glGenFramebuffers");
    static auto glBindFramebuffer_fn = G<void (*)(unsigned int, unsigned int)>("glBindFramebuffer");
    static auto glFramebufferTexture2D_fn = G<void (*)(unsigned int, unsigned int, unsigned int, unsigned int, int)>("glFramebufferTexture2D");
    static auto glBlitFramebuffer_fn = G<void (*)(int, int, int, int, int, int, int, int, unsigned int, unsigned int)>("glBlitFramebuffer");

    if (!glBlitFramebuffer_fn || !glBindFramebuffer_fn || !glGenFramebuffers_fn || !glFramebufferTexture2D_fn) return;

    if (it_s->second.fbo == 0) {
        glGenFramebuffers_fn(1, &it_s->second.fbo);
        glBindFramebuffer_fn(0x8D40, it_s->second.fbo);
        glFramebufferTexture2D_fn(0x8D40, 0x8CE0, 0x0DE1, it_s->second.tex, 0);
    }
    if (it_d->second.fbo == 0) {
        glGenFramebuffers_fn(1, &it_d->second.fbo);
        glBindFramebuffer_fn(0x8D40, it_d->second.fbo);
        glFramebufferTexture2D_fn(0x8D40, 0x8CE0, 0x0DE1, it_d->second.tex, 0);
    }

    glBindFramebuffer_fn(0x8CA8 /*GL_READ_FRAMEBUFFER*/, it_s->second.fbo);
    glBindFramebuffer_fn(0x8CA9 /*GL_DRAW_FRAMEBUFFER*/, it_d->second.fbo);

    int s_y0 = it_s->second.h - (sy + sh);
    int s_y1 = it_s->second.h - sy;
    int d_y0 = it_d->second.h - (dy + sh);
    int d_y1 = it_d->second.h - dy;

    glBlitFramebuffer_fn(sx, s_y0, sx + sw, s_y1, dx, d_y0, dx + sw, d_y1, 0x00004000 /*GL_COLOR_BUFFER_BIT*/, 0x2600 /*GL_NEAREST*/);
    glBindFramebuffer_fn(0x8D40, 0);
}

void xef_host_metal_tex_copy_ex(uint32_t src_tex_id, int src_slice, int src_level, int sx, int sy, int sz,
                                uint32_t dst_tex_id, int dst_slice, int dst_level, int dx, int dy, int dz,
                                int sw, int sh, int sd) {
    if (xef::metal_vk::is_available()) {
        xef::metal_vk::tex_copy_ex(src_tex_id, src_slice, src_level, sx, sy, sz,
                                   dst_tex_id, dst_slice, dst_level, dx, dy, dz,
                                   sw, sh, sd);
        return;
    }
    xef_host_metal_tex_copy(src_tex_id, sx, sy, sw, sh, dst_tex_id, dx, dy);
}

void xef_host_metal_tex_readback_ex(uint32_t tex_id, int slice, int level, int x, int y, int z, int w, int h, int d, void* out_data, int pitch, int image_pitch) {
    if (xef::metal_vk::is_available()) {
        xef::metal_vk::tex_readback_ex(tex_id, slice, level, x, y, z, w, h, d, out_data, pitch, image_pitch);
        return;
    }
    if (!out_data || w <= 0 || h <= 0) return;
    std::lock_guard<std::mutex> lk(g_lock);
    auto it = g_host_texs.find(tex_id);
    if (it == g_host_texs.end()) return;
    if (!ensure_gl_context(0)) return;
    ensure_tex_gl(it->second);

    static auto glBindFramebuffer_fn = G<void (*)(unsigned int, unsigned int)>("glBindFramebuffer");
    static auto glReadPixels_fn = G<void (*)(int, int, int, int, unsigned int, unsigned int, void*)>("glReadPixels");
    static auto glPixelStorei_fn = G<void (*)(unsigned int, int)>("glPixelStorei");

    if (it->second.fbo && glBindFramebuffer_fn && glReadPixels_fn) {
        glBindFramebuffer_fn(0x8D40 /*GL_FRAMEBUFFER*/, it->second.fbo);
        if (glPixelStorei_fn) {
            glPixelStorei_fn(0x0D05 /*GL_PACK_ALIGNMENT*/, 1);
            if (pitch > 0 && pitch != w * 4) glPixelStorei_fn(0x0D02 /*GL_PACK_ROW_LENGTH*/, pitch / 4);
            else glPixelStorei_fn(0x0D02, 0);
        }
        unsigned int gl_fmt = (it->second.fmt == 80 || it->second.fmt == 81) ? 0x80E1 /*GL_BGRA*/ : 0x1908 /*GL_RGBA*/;
        int gl_y = it->second.h - (y + h);
        if (gl_y < 0) gl_y = 0;
        glReadPixels_fn(x, gl_y, w, h, gl_fmt, 0x1401 /*GL_UNSIGNED_BYTE*/, out_data);
        if (glPixelStorei_fn) glPixelStorei_fn(0x0D02, 0);
        glBindFramebuffer_fn(0x8D40, 0);
    }
}

void xef_host_metal_tex_readback(uint32_t tex_id, int x, int y, int w, int h, void* out_data, int pitch) {
    xef_host_metal_tex_readback_ex(tex_id, 0, 0, x, y, 0, w, h, 1, out_data, pitch, 0);
}

void xef_host_metal_tex_generate_mipmaps(uint32_t tex_id) {
    if (xef::metal_vk::is_available()) {
        xef::metal_vk::tex_generate_mipmaps(tex_id);
        return;
    }
}

void xef_host_metal_tex_destroy(uint32_t tex_id) {
    if (xef::metal_vk::is_available()) {
        xef::metal_vk::tex_destroy(tex_id);
        return;
    }
    std::lock_guard<std::mutex> lk(g_lock);
    auto it = g_host_texs.find(tex_id);
    if (it == g_host_texs.end()) return;
    if (ensure_gl_context(0)) {
        static auto glDeleteTextures_fn = G<void (*)(int, const unsigned int*)>("glDeleteTextures");
        static auto glDeleteFramebuffers_fn = G<void (*)(int, const unsigned int*)>("glDeleteFramebuffers");
        if (it->second.fbo && glDeleteFramebuffers_fn) glDeleteFramebuffers_fn(1, &it->second.fbo);
        if (it->second.tex && glDeleteTextures_fn) glDeleteTextures_fn(1, &it->second.tex);
    }
    g_host_texs.erase(it);
}

void xef_host_metal_pass_begin(int handle, uint32_t rt_tex_id, int clear, float r, float g, float b, float a) {
    if (xef::metal_vk::is_available()) {
        xef::metal_vk::pass_begin(handle, rt_tex_id, clear, r, g, b, a);
        return;
    }
    std::lock_guard<std::mutex> lk(g_lock);
    if (!ensure_gl_context(handle)) return;
    auto it = g_host_texs.find(rt_tex_id);
    if (it == g_host_texs.end()) return;
    ensure_tex_gl(it->second);

    static auto glGenFramebuffers_fn = G<void (*)(int, unsigned int*)>("glGenFramebuffers");
    static auto glBindFramebuffer_fn = G<void (*)(unsigned int, unsigned int)>("glBindFramebuffer");
    static auto glFramebufferTexture2D_fn = G<void (*)(unsigned int, unsigned int, unsigned int, unsigned int, int)>("glFramebufferTexture2D");
    static auto glClearColor_fn = G<void (*)(float, float, float, float)>("glClearColor");
    static auto glClear_fn = G<void (*)(unsigned int)>("glClear");
    static auto glColorMask_fn = G<void (*)(unsigned char, unsigned char, unsigned char, unsigned char)>("glColorMask");
    static auto glDisable_fn = G<void (*)(unsigned int)>("glDisable");

    if (it->second.fbo == 0 && glGenFramebuffers_fn && glBindFramebuffer_fn && glFramebufferTexture2D_fn) {
        glGenFramebuffers_fn(1, &it->second.fbo);
        glBindFramebuffer_fn(0x8D40 /*GL_FRAMEBUFFER*/, it->second.fbo);
        glFramebufferTexture2D_fn(0x8D40, 0x8CE0 /*GL_COLOR_ATTACHMENT0*/, 0x0DE1 /*GL_TEXTURE_2D*/, it->second.tex, 0);
    } else if (glBindFramebuffer_fn) {
        glBindFramebuffer_fn(0x8D40 /*GL_FRAMEBUFFER*/, it->second.fbo);
    }

    if (clear && glClearColor_fn && glClear_fn) {
        if (glDisable_fn) glDisable_fn(0x0C11 /*GL_SCISSOR_TEST*/);
        if (glColorMask_fn) glColorMask_fn(1, 1, 1, 1);
        glClearColor_fn(r, g, b, a);
        glClear_fn(0x00004000 /*GL_COLOR_BUFFER_BIT*/);
    }
}

void xef_host_metal_pass_begin_ex(int handle, uint32_t rt_tex_id, uint32_t depth_tex_id, int clear, float r, float g, float b, float a, float clear_depth) {
    if (xef::metal_vk::is_available()) {
        xef::metal_vk::pass_begin_ex(handle, rt_tex_id, depth_tex_id, clear, r, g, b, a, clear_depth);
        return;
    }
    xef_host_metal_pass_begin(handle, rt_tex_id, clear, r, g, b, a);
}

void xef_host_metal_pass_end(int handle, uint32_t rt_tex_id) {
    if (xef::metal_vk::is_available()) {
        xef::metal_vk::pass_end(handle, rt_tex_id);
        return;
    }
    std::lock_guard<std::mutex> lk(g_lock);
    static auto glBindFramebuffer_fn = G<void (*)(unsigned int, unsigned int)>("glBindFramebuffer");
    if (glBindFramebuffer_fn) glBindFramebuffer_fn(0x8D40 /*GL_FRAMEBUFFER*/, 0);
}

void xef_host_metal_draw(int handle,
                         const xef_host_metal_pipeline_t* pipe,
                         int prim_type,
                         const xef_host_metal_vertex_t* vertices,
                         int vertex_count,
                         const uint32_t* indices,
                         int index_count) {
    if (xef::metal_vk::is_available()) {
        xef::metal_vk::draw(handle, pipe, prim_type, vertices, vertex_count, indices, index_count);
        return;
    }
    if (!pipe || !vertices || vertex_count <= 0) return;
    std::lock_guard<std::mutex> lk(g_lock);
    if (!ensure_gl_context(handle)) return;

    auto it_rt = g_host_texs.find(pipe->rt_tex_id);
    if (it_rt == g_host_texs.end()) return;
    ensure_tex_gl(it_rt->second);

    static auto glGenFramebuffers_fn = G<void (*)(int, unsigned int*)>("glGenFramebuffers");
    static auto glBindFramebuffer_fn = G<void (*)(unsigned int, unsigned int)>("glBindFramebuffer");
    static auto glFramebufferTexture2D_fn = G<void (*)(unsigned int, unsigned int, unsigned int, unsigned int, int)>("glFramebufferTexture2D");
    static auto glViewport_fn = G<void (*)(int, int, int, int)>("glViewport");
    static auto glEnable_fn = G<void (*)(unsigned int)>("glEnable");
    static auto glDisable_fn = G<void (*)(unsigned int)>("glDisable");
    static auto glScissor_fn = G<void (*)(int, int, int, int)>("glScissor");
    static auto glColorMask_fn = G<void (*)(unsigned char, unsigned char, unsigned char, unsigned char)>("glColorMask");
    static auto glBlendFunc_fn = G<void (*)(unsigned int, unsigned int)>("glBlendFunc");
    static auto glBlendFuncSeparate_fn = G<void (*)(unsigned int, unsigned int, unsigned int, unsigned int)>("glBlendFuncSeparate");
    static auto glBlendEquation_fn = G<void (*)(unsigned int)>("glBlendEquation");
    static auto glBlendEquationSeparate_fn = G<void (*)(unsigned int, unsigned int)>("glBlendEquationSeparate");
    static auto glUseProgram_fn = G<void (*)(unsigned int)>("glUseProgram");
    static auto glUniform1i_fn = G<void (*)(int, int)>("glUniform1i");
    static auto glUniform1f_fn = G<void (*)(int, float)>("glUniform1f");
    static auto glUniform2f_fn = G<void (*)(int, float, float)>("glUniform2f");
    static auto glActiveTexture_fn = G<void (*)(unsigned int)>("glActiveTexture");
    static auto glBindTexture_fn = G<void (*)(unsigned int, unsigned int)>("glBindTexture");
    static auto glTexParameteri_fn = G<void (*)(unsigned int, unsigned int, int)>("glTexParameteri");
    static auto glBindVertexArray_fn = G<void (*)(unsigned int)>("glBindVertexArray");
    static auto glBindBuffer_fn = G<void (*)(unsigned int, unsigned int)>("glBindBuffer");
    static auto glBufferData_fn = G<void (*)(unsigned int, size_t, const void*, unsigned int)>("glBufferData");
    static auto glEnableVertexAttribArray_fn = G<void (*)(unsigned int)>("glEnableVertexAttribArray");
    static auto glVertexAttribPointer_fn = G<void (*)(unsigned int, int, unsigned int, unsigned char, int, const void*)>("glVertexAttribPointer");
    static auto glDrawArrays_fn = G<void (*)(unsigned int, int, int)>("glDrawArrays");
    static auto glDrawElements_fn = G<void (*)(unsigned int, int, unsigned int, const void*)>("glDrawElements");

    if (it_rt->second.fbo == 0 && glGenFramebuffers_fn && glBindFramebuffer_fn && glFramebufferTexture2D_fn) {
        glGenFramebuffers_fn(1, &it_rt->second.fbo);
        glBindFramebuffer_fn(0x8D40 /*GL_FRAMEBUFFER*/, it_rt->second.fbo);
        glFramebufferTexture2D_fn(0x8D40, 0x8CE0 /*GL_COLOR_ATTACHMENT0*/, 0x0DE1 /*GL_TEXTURE_2D*/, it_rt->second.tex, 0);
    } else if (glBindFramebuffer_fn) {
        glBindFramebuffer_fn(0x8D40 /*GL_FRAMEBUFFER*/, it_rt->second.fbo);
    }

    int tw = it_rt->second.w;
    int th = it_rt->second.h;

    if (glViewport_fn) {
        int vx = pipe->viewport[0];
        int vy = pipe->viewport[1];
        int vw = pipe->viewport[2] > 0 ? pipe->viewport[2] : tw;
        int vh = pipe->viewport[3] > 0 ? pipe->viewport[3] : th;
        glViewport_fn(vx, vy, vw, vh);
    }

    if (glEnable_fn && glDisable_fn && glScissor_fn) {
        if (pipe->clip_rect[2] > 0 && pipe->clip_rect[3] > 0 &&
            (pipe->clip_rect[2] < tw || pipe->clip_rect[3] < th || pipe->clip_rect[0] > 0 || pipe->clip_rect[1] > 0)) {
            glEnable_fn(0x0C11 /*GL_SCISSOR_TEST*/);
            int sc_y = th - (pipe->clip_rect[1] + pipe->clip_rect[3]);
            if (sc_y < 0) sc_y = 0;
            glScissor_fn(pipe->clip_rect[0], sc_y, pipe->clip_rect[2], pipe->clip_rect[3]);
        } else {
            glDisable_fn(0x0C11 /*GL_SCISSOR_TEST*/);
        }
    }

    if (glEnable_fn && glDisable_fn) {
        if (pipe->blend_enable) {
            glEnable_fn(0x0BE2 /*GL_BLEND*/);
            unsigned int s_rgb = map_blend_factor(pipe->src_rgb);
            unsigned int d_rgb = map_blend_factor(pipe->dst_rgb);
            unsigned int s_a   = map_blend_factor(pipe->src_a);
            unsigned int d_a   = map_blend_factor(pipe->dst_a);
            unsigned int o_rgb = map_blend_op(pipe->rgb_op);
            unsigned int o_a   = map_blend_op(pipe->a_op);

            if (glBlendFuncSeparate_fn) glBlendFuncSeparate_fn(s_rgb, d_rgb, s_a, d_a);
            else if (glBlendFunc_fn) glBlendFunc_fn(s_rgb, d_rgb);

            if (glBlendEquationSeparate_fn) glBlendEquationSeparate_fn(o_rgb, o_a);
            else if (glBlendEquation_fn) glBlendEquation_fn(o_rgb);
        } else {
            glDisable_fn(0x0BE2 /*GL_BLEND*/);
        }
    }

    if (glColorMask_fn) {
        glColorMask_fn((pipe->write_mask & 8) != 0,
                       (pipe->write_mask & 4) != 0,
                       (pipe->write_mask & 2) != 0,
                       (pipe->write_mask & 1) != 0);
    }

    ensure_metal_program();
    if (!g_metal_prog || !glUseProgram_fn) return;
    glUseProgram_fn(g_metal_prog);

    if (glUniform2f_fn && g_u_target_size >= 0) glUniform2f_fn(g_u_target_size, (float)tw, (float)th);
    if (glUniform1i_fn && g_u_frag_mode >= 0) glUniform1i_fn(g_u_frag_mode, pipe->frag_mode);
    float cscale = pipe->color_scale > 0.0f ? pipe->color_scale : 1.0f;
    if (glUniform1f_fn && g_u_color_scale >= 0) glUniform1f_fn(g_u_color_scale, cscale);
    if (glUniform2f_fn && g_u_uv_left_top >= 0) glUniform2f_fn(g_u_uv_left_top, pipe->uv_left_top[0], pipe->uv_left_top[1]);
    if (glUniform2f_fn && g_u_uv_dims >= 0) glUniform2f_fn(g_u_uv_dims, pipe->uv_dims[0], pipe->uv_dims[1]);

    int flip_y = 0;
    if (pipe->tex_id > 0) {
        auto it_tex = g_host_texs.find(pipe->tex_id);
        if (it_tex != g_host_texs.end()) {
            ensure_tex_gl(it_tex->second);
            if (it_tex->second.is_rt) {
                flip_y = 1;
            }
            if (glActiveTexture_fn) glActiveTexture_fn(0x84C0 /*GL_TEXTURE0*/);
            if (glBindTexture_fn) {
                glBindTexture_fn(0x0DE1 /*GL_TEXTURE_2D*/, it_tex->second.tex);
                if (glTexParameteri_fn) {
                    glTexParameteri_fn(0x0DE1, 0x2801, pipe->filter_linear ? 0x2601 /*GL_LINEAR*/ : 0x2600 /*GL_NEAREST*/);
                    glTexParameteri_fn(0x0DE1, 0x2800, pipe->filter_linear ? 0x2601 /*GL_LINEAR*/ : 0x2600 /*GL_NEAREST*/);
                    glTexParameteri_fn(0x0DE1, 0x2802, pipe->clamp_to_edge ? 0x812F /*GL_CLAMP_TO_EDGE*/ : 0x2901 /*GL_REPEAT*/);
                    glTexParameteri_fn(0x0DE1, 0x2803, pipe->clamp_to_edge ? 0x812F /*GL_CLAMP_TO_EDGE*/ : 0x2901 /*GL_REPEAT*/);
                }
            }
            if (glUniform1i_fn && g_u_tex >= 0) glUniform1i_fn(g_u_tex, 0);
        }
    }
    if (glUniform1i_fn && g_u_flip_y >= 0) glUniform1i_fn(g_u_flip_y, flip_y);

    ensure_buffers();
    if (glBindVertexArray_fn && g_metal_vao) glBindVertexArray_fn(g_metal_vao);
    if (glBindBuffer_fn && g_metal_vbo) {
        glBindBuffer_fn(0x8892 /*GL_ARRAY_BUFFER*/, g_metal_vbo);
        if (glBufferData_fn) glBufferData_fn(0x8892, vertex_count * sizeof(xef_host_metal_vertex_t), vertices, 0x88E0 /*GL_STREAM_DRAW*/);
    }

    if (glVertexAttribPointer_fn && glEnableVertexAttribArray_fn) {
        glEnableVertexAttribArray_fn(0);
        glVertexAttribPointer_fn(0, 3, 0x1406 /*GL_FLOAT*/, 0, sizeof(xef_host_metal_vertex_t), (const void*)offsetof(xef_host_metal_vertex_t, sx));
        glEnableVertexAttribArray_fn(1);
        glVertexAttribPointer_fn(1, 2, 0x1406 /*GL_FLOAT*/, 0, sizeof(xef_host_metal_vertex_t), (const void*)offsetof(xef_host_metal_vertex_t, u));
        glEnableVertexAttribArray_fn(2);
        glVertexAttribPointer_fn(2, 4, 0x1406 /*GL_FLOAT*/, 0, sizeof(xef_host_metal_vertex_t), (const void*)offsetof(xef_host_metal_vertex_t, r));
    }

    unsigned int gl_prim = (prim_type == 0) ? 0x0004 /*GL_TRIANGLES*/ :
                           (prim_type == 1) ? 0x0005 /*GL_TRIANGLE_STRIP*/ :
                           (prim_type == 2) ? 0x0001 /*GL_LINES*/ :
                           (prim_type == 3) ? 0x0003 /*GL_LINE_STRIP*/ : 0x0000 /*GL_POINTS*/;

    if (indices && index_count > 0) {
        if (glBindBuffer_fn && g_metal_ibo) {
            glBindBuffer_fn(0x8893 /*GL_ELEMENT_ARRAY_BUFFER*/, g_metal_ibo);
            if (glBufferData_fn) glBufferData_fn(0x8893, index_count * sizeof(uint32_t), indices, 0x88E0 /*GL_STREAM_DRAW*/);
        }
        if (glDrawElements_fn) glDrawElements_fn(gl_prim, index_count, 0x1405 /*GL_UNSIGNED_INT*/, nullptr);
    } else {
        if (glDrawArrays_fn) glDrawArrays_fn(gl_prim, 0, vertex_count);
    }

    if (glColorMask_fn) glColorMask_fn(1, 1, 1, 1);
}

void xef_host_metal_present_gpu(int handle, uint32_t tex_id) {
    if (xef::metal_vk::is_available()) {
        xef::metal_vk::present(handle, tex_id);
        return;
    }
    std::lock_guard<std::mutex> lk(g_lock);
    HWin* w = find(handle);
    if (!w || !g_dpy) return;
    if (!ensure_gl_context(handle)) return;

    auto it = g_host_texs.find(tex_id);
    if (it == g_host_texs.end()) return;
    ensure_tex_gl(it->second);

    static auto glBindFramebuffer_fn = G<void (*)(unsigned int, unsigned int)>("glBindFramebuffer");
    static auto glViewport_fn = G<void (*)(int, int, int, int)>("glViewport");
    static auto glDisable_fn = G<void (*)(unsigned int)>("glDisable");
    static auto glEnable_fn = G<void (*)(unsigned int)>("glEnable");
    static auto glUseProgram_fn = G<void (*)(unsigned int)>("glUseProgram");
    static auto glActiveTexture_fn = G<void (*)(unsigned int)>("glActiveTexture");
    static auto glBindTexture_fn = G<void (*)(unsigned int, unsigned int)>("glBindTexture");
    static auto glTexParameteri_fn = G<void (*)(unsigned int, unsigned int, int)>("glTexParameteri");
    static auto glUniform1i_fn = G<void (*)(int, int)>("glUniform1i");
    static auto glBindVertexArray_fn = G<void (*)(unsigned int)>("glBindVertexArray");
    static auto glDrawArrays_fn = G<void (*)(unsigned int, int, int)>("glDrawArrays");
    static auto glColorMask_fn = G<void (*)(unsigned char, unsigned char, unsigned char, unsigned char)>("glColorMask");
    static auto swap = G<void (*)(Display*, unsigned long)>("glXSwapBuffers");

    if (glBindFramebuffer_fn) glBindFramebuffer_fn(0x8D40 /*GL_FRAMEBUFFER*/, 0);

    int vw = w->w > 0 ? w->w : it->second.w;
    int vh = w->h > 0 ? w->h : it->second.h;
    if (glViewport_fn) glViewport_fn(0, 0, vw, vh);

    if (glDisable_fn) {
        glDisable_fn(0x0B71 /*GL_DEPTH_TEST*/);
        glDisable_fn(0x0C11 /*GL_SCISSOR_TEST*/);
        glDisable_fn(0x0B44 /*GL_CULL_FACE*/);
        glDisable_fn(0x0BE2 /*GL_BLEND*/);
    }
    if (glColorMask_fn) glColorMask_fn(1, 1, 1, 1);

    ensure_present_program();
    ensure_present_buffers();

    if (glUseProgram_fn && g_present_prog) {
        glUseProgram_fn(g_present_prog);
        if (glActiveTexture_fn) glActiveTexture_fn(0x84C0 /*GL_TEXTURE0*/);
        if (glBindTexture_fn) {
            glBindTexture_fn(0x0DE1 /*GL_TEXTURE_2D*/, it->second.tex);
            if (glTexParameteri_fn) {
                glTexParameteri_fn(0x0DE1, 0x2801, 0x2601 /*GL_LINEAR*/);
                glTexParameteri_fn(0x0DE1, 0x2800, 0x2601 /*GL_LINEAR*/);
                glTexParameteri_fn(0x0DE1, 0x2802, 0x812F /*GL_CLAMP_TO_EDGE*/);
                glTexParameteri_fn(0x0DE1, 0x2803, 0x812F /*GL_CLAMP_TO_EDGE*/);
            }
        }
        if (glUniform1i_fn && g_present_u_tex >= 0) glUniform1i_fn(g_present_u_tex, 0);

        if (glBindVertexArray_fn && g_present_vao) glBindVertexArray_fn(g_present_vao);
        if (glDrawArrays_fn) glDrawArrays_fn(0x0004 /*GL_TRIANGLES*/, 0, 6);
    } else {
        // Compatibility mode fallback
        static auto glMatrixMode_fn = G<void (*)(unsigned int)>("glMatrixMode");
        static auto glLoadIdentity_fn = G<void (*)()>("glLoadIdentity");
        static auto glColor4f_fn = G<void (*)(float, float, float, float)>("glColor4f");
        static auto glBegin_fn = G<void (*)(unsigned int)>("glBegin");
        static auto glEnd_fn = G<void (*)()>("glEnd");
        static auto glTexCoord2f_fn = G<void (*)(float, float)>("glTexCoord2f");
        static auto glVertex2f_fn = G<void (*)(float, float)>("glVertex2f");

        if (glUseProgram_fn) glUseProgram_fn(0);
        if (glEnable_fn) glEnable_fn(0x0DE1 /*GL_TEXTURE_2D*/);
        if (glBindTexture_fn) glBindTexture_fn(0x0DE1, it->second.tex);
        if (glMatrixMode_fn && glLoadIdentity_fn) {
            glMatrixMode_fn(0x1701 /*GL_PROJECTION*/); glLoadIdentity_fn();
            glMatrixMode_fn(0x1700 /*GL_MODELVIEW*/);  glLoadIdentity_fn();
        }
        if (glColor4f_fn) glColor4f_fn(1.0f, 1.0f, 1.0f, 1.0f);
        if (glBegin_fn && glEnd_fn && glTexCoord2f_fn && glVertex2f_fn) {
            glBegin_fn(0x0007 /*GL_QUADS*/);
            glTexCoord2f_fn(0.0f, 1.0f); glVertex2f_fn(-1.0f,  1.0f);
            glTexCoord2f_fn(1.0f, 1.0f); glVertex2f_fn( 1.0f,  1.0f);
            glTexCoord2f_fn(1.0f, 0.0f); glVertex2f_fn( 1.0f, -1.0f);
            glTexCoord2f_fn(0.0f, 0.0f); glVertex2f_fn(-1.0f, -1.0f);
            glEnd_fn();
        }
        if (glDisable_fn) glDisable_fn(0x0DE1);
    }

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
    if (!hw) return 0;
    if (!g_dpy) return 0;
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

const char* xef_host_metal_backend_name() {
    if (xef::metal_vk::is_available()) {
        return xef::metal_vk::get_device_name();
    }
    return "Host OpenGL 3.3";
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
    {"_xef_host_metal_sampler_create", (void*)&xef_host_metal_sampler_create},
    {"_xef_host_metal_sampler_destroy", (void*)&xef_host_metal_sampler_destroy},
    {"_xef_host_metal_tex_create", (void*)&xef_host_metal_tex_create},
    {"_xef_host_metal_tex_create_ex", (void*)&xef_host_metal_tex_create_ex},
    {"_xef_host_metal_tex_create_view", (void*)&xef_host_metal_tex_create_view},
    {"_xef_host_metal_tex_update", (void*)&xef_host_metal_tex_update},
    {"_xef_host_metal_tex_update_ex", (void*)&xef_host_metal_tex_update_ex},
    {"_xef_host_metal_tex_copy", (void*)&xef_host_metal_tex_copy},
    {"_xef_host_metal_tex_copy_ex", (void*)&xef_host_metal_tex_copy_ex},
    {"_xef_host_metal_tex_readback", (void*)&xef_host_metal_tex_readback},
    {"_xef_host_metal_tex_readback_ex", (void*)&xef_host_metal_tex_readback_ex},
    {"_xef_host_metal_tex_generate_mipmaps", (void*)&xef_host_metal_tex_generate_mipmaps},
    {"_xef_host_metal_tex_destroy", (void*)&xef_host_metal_tex_destroy},
    {"_xef_host_metal_pass_begin", (void*)&xef_host_metal_pass_begin},
    {"_xef_host_metal_pass_begin_ex", (void*)&xef_host_metal_pass_begin_ex},
    {"_xef_host_metal_pass_end", (void*)&xef_host_metal_pass_end},
    {"_xef_host_metal_draw", (void*)&xef_host_metal_draw},
    {"_xef_host_metal_present_gpu", (void*)&xef_host_metal_present_gpu},
    {"_xef_host_metal_backend_name", (void*)&xef_host_metal_backend_name},
    {"xef_host_metal_sampler_create", (void*)&xef_host_metal_sampler_create},
    {"xef_host_metal_sampler_destroy", (void*)&xef_host_metal_sampler_destroy},
    {"xef_host_metal_tex_create", (void*)&xef_host_metal_tex_create},
    {"xef_host_metal_tex_create_ex", (void*)&xef_host_metal_tex_create_ex},
    {"xef_host_metal_tex_create_view", (void*)&xef_host_metal_tex_create_view},
    {"xef_host_metal_tex_update", (void*)&xef_host_metal_tex_update},
    {"xef_host_metal_tex_update_ex", (void*)&xef_host_metal_tex_update_ex},
    {"xef_host_metal_tex_copy", (void*)&xef_host_metal_tex_copy},
    {"xef_host_metal_tex_copy_ex", (void*)&xef_host_metal_tex_copy_ex},
    {"xef_host_metal_tex_readback", (void*)&xef_host_metal_tex_readback},
    {"xef_host_metal_tex_readback_ex", (void*)&xef_host_metal_tex_readback_ex},
    {"xef_host_metal_tex_generate_mipmaps", (void*)&xef_host_metal_tex_generate_mipmaps},
    {"xef_host_metal_tex_destroy", (void*)&xef_host_metal_tex_destroy},
    {"xef_host_metal_pass_begin", (void*)&xef_host_metal_pass_begin},
    {"xef_host_metal_pass_begin_ex", (void*)&xef_host_metal_pass_begin_ex},
    {"xef_host_metal_pass_end", (void*)&xef_host_metal_pass_end},
    {"xef_host_metal_draw", (void*)&xef_host_metal_draw},
    {"xef_host_metal_present_gpu", (void*)&xef_host_metal_present_gpu},
    {"xef_host_metal_backend_name", (void*)&xef_host_metal_backend_name},
};

} // namespace

uint64_t darwin_appkit_host_resolve(const char* name) {
    for (const Fn& f : kFns)
        if (!strcmp(name, f.name)) return darwin_hle_register_function(name, f.fn);
    return 0;
}

} // namespace xef
