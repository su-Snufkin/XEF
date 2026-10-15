/* Host (loader) interface of AppKit-lite. Plain C functions, imported flat
 * (-undefined dynamic_lookup) and provided by src/loader/darwin_appkit_host.cpp.
 *
 * handle: > 0 valid host window, 0 = none / "release current" for gl_make_current.
 * Coordinates: window_create x,y,w,h describe the CONTENT area in host screen
 *   pixels, origin top-left of the screen (AppKit-lite converts from Cocoa's
 *   bottom-left screen space, screen = 1440x900 points, scale 1.0).
 * Event x,y: pixels inside the content area, origin TOP-left (X11 style);
 *   AppKit-lite flips y to Cocoa's bottom-left.
 * Event type = NSEventType value (1 LMouseDown, 2 LMouseUp, 3 RMouseDown,
 *   4 RMouseUp, 5 MouseMoved, 6 LMouseDragged, 7 RMouseDragged, 10 KeyDown,
 *   11 KeyUp, 22 ScrollWheel [keycode = vertical delta in lines, signed],
 *   25 OtherMouseDown, 26 OtherMouseUp, 27 OtherMouseDragged)
 *   or XEF_EV_CLOSE (WM_DELETE_WINDOW) / XEF_EV_RESIZE (x=w, y=h).
 * keycode = macOS virtual key code (kVK_*) for key events.
 * flags = NSEventModifierFlags bits (caps 1<<16, shift 1<<17, ctrl 1<<18,
 *   alt 1<<19, cmd 1<<20). */
#ifndef XEF_HOST_H
#define XEF_HOST_H
#define XEF_EV_CLOSE  1000
#define XEF_EV_RESIZE 1001
typedef struct { int type; int keycode; int x; int y; int flags; } xef_host_event_t;
#ifdef __cplusplus
extern "C" {
#endif
int  xef_host_window_create(int x, int y, int w, int h, const char *title);
void xef_host_window_show(int handle);
void xef_host_window_set_title(int handle, const char *title);
void xef_host_window_close(int handle);
int  xef_host_pump(void *ev_out);          /* xef_host_event_t*; 0 = no event */
void xef_host_gl_make_current(int handle); /* 0 releases */
void xef_host_swap(int handle);
#ifdef __cplusplus
}
#endif
#endif
