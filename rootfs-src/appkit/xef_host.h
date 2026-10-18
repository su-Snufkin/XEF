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
 *   alt 1<<19, cmd 1<<20).
 * Screen coordinates (screen_info, pointer, pointer_warp, window_set_frame): host screen pixels, origin top-left. */
#ifndef XEF_HOST_H
#define XEF_HOST_H
#define XEF_EV_CLOSE  1000
#define XEF_EV_RESIZE 1001
#define XEF_EV_FOCUS_IN  1002
#define XEF_EV_FOCUS_OUT 1003
/* NSEventType 8 / 9 (MouseEntered / MouseExited) are also delivered; x,y = pointer inside the content area. */
/* ch: for key-down events, the typed character (Unicode code point after shift/AltGr; 0 = none). keycode 0xffff = a key
 * without a macOS virtual key code that still typed a character. */
typedef struct { int type; int keycode; int x; int y; int flags; int handle; int ch; } xef_host_event_t;
#ifdef __cplusplus
extern "C" {
#endif
int  xef_host_window_create(int x, int y, int w, int h, const char *title);
void xef_host_window_show(int handle);
void xef_host_window_hide(int handle);     /* unmap; show maps again */
void xef_host_window_set_title(int handle, const char *title);
void xef_host_window_close(int handle);
void xef_host_window_set_fullscreen(int handle, int enable);
int  xef_host_pump(void *ev_out);          /* xef_host_event_t*; 0 = no event */
void xef_host_gl_make_current(int handle); /* 0 releases */
void xef_host_swap(int handle);
/* Requests the OpenGL profile of the window's context (NSOpenGLPixelFormat NSOpenGLPFAOpenGLProfile value:
 * 0x1000 legacy = compatibility context, 0x3200 = 3.2 core, 0x4100 = 4.1 core). Replaces the window's context when
 * the profile differs; call before the context is made current. */
void xef_host_gl_set_profile(int handle, int profile);
/* Host screen size in pixels and physical size in mm (falls back to 1440x900 when no display is available). */
void xef_host_screen_info(int *w, int *h, int *mm_w, int *mm_h);
/* Moves/resizes the window so that its CONTENT area is x,y,w,h. */
void xef_host_window_set_frame(int handle, int x, int y, int w, int h);
/* Pointer position in screen pixels and relative to the window's content area; returns 0 if unavailable. */
int  xef_host_pointer(int handle, int *screen_x, int *screen_y, int *win_x, int *win_y);
void xef_host_pointer_warp(int screen_x, int screen_y);
int  xef_host_mouse_buttons(void);
int  xef_host_window_get_geometry(int handle, int *rx, int *ry, int *rw, int *rh);
int  xef_host_file_dialog(const char *title, const char *initial_path, int is_save, int is_dir, int allow_multi, char *out_buf, int out_len);
void xef_host_present_pixels(int handle, const void *pixels, int w, int h, int format);
/* pop-up windows (menus): override-redirect, undecorated; takes effect on the next show */
void xef_host_window_set_popup(int handle, int popup);
/* pointer grab while a menu tracks the mouse; returns 1 on success. grab = 0 releases */
int  xef_host_grab_pointer(int handle, int grab);

/* ---- 2D drawing (src/loader/darwin_cg_host.cpp: cairo + pango on the host) ----
 * Contexts draw into a guest buffer of premultiplied BGRA (cairo ARGB32). Matrices are CG affine (a b c d tx ty).
 * Text objects are pango layouts over UTF-8; ranges are byte offsets, start < 0 = whole text. Layout coordinates are
 * y-down from the top-left of the text. Image/convert layouts: bits 0-7 bits per pixel, 8-15 bits per component,
 * 16-18 CGImageAlphaInfo, 19 32-bit little-endian, 20 16-bit little-endian, 21 gray. */
int  xef_host_cg_create(void *data, int w, int h, int stride);
void xef_host_cg_destroy(int c);
void xef_host_cg_flush(int c);
void xef_host_cg_mark_dirty(int c);
void xef_host_cg_save(int c);
void xef_host_cg_restore(int c);
void xef_host_cg_concat(int c, double a, double b, double cc, double d, double tx, double ty);
void xef_host_cg_set_matrix(int c, double a, double b, double cc, double d, double tx, double ty);
void xef_host_cg_get_matrix(int c, double *out6);
void xef_host_cg_new_path(int c);
void xef_host_cg_move(int c, double x, double y);
void xef_host_cg_line(int c, double x, double y);
void xef_host_cg_curve(int c, double x1, double y1, double x2, double y2, double x3, double y3);
void xef_host_cg_close(int c);
void xef_host_cg_rect(int c, double x, double y, double w, double h);
void xef_host_cg_arc(int c, double x, double y, double r, double a0, double a1, int negative);
void xef_host_cg_path_extents(int c, double *out4);    /* x0 y0 x1 y1, user space */
int  xef_host_cg_in_fill(int c, double x, double y);
void xef_host_cg_source_rgba(int c, double r, double g, double b, double a);
void xef_host_cg_fill(int c, int evenodd, int preserve);
void xef_host_cg_stroke(int c, int preserve);
void xef_host_cg_clip(int c, int evenodd);
void xef_host_cg_reset_clip(int c);
void xef_host_cg_clip_extents(int c, double *out4);
void xef_host_cg_line_style(int c, double width, int cap, int join, double miter);
void xef_host_cg_dash(int c, const double *d, int n, double phase);
void xef_host_cg_operator(int c, int cairo_operator);
void xef_host_cg_antialias(int c, int on);
void xef_host_cg_image(int c, const void *px, int w, int h, int stride, int layout, double alpha, int interpolate);   /* unit square */
void xef_host_cg_convert(void *argb, int argb_stride, void *px, int stride, int w, int h, int layout, int to_native);
void xef_host_cg_gradient(int c, int radial, double x0, double y0, double r0, double x1, double y1, double r1, const double *stops, int n, int extend);
int  xef_host_text_create(const char *utf8, int len);
void xef_host_text_destroy(int t);
void xef_host_text_set_width(int t, double width);   /* < 0: no wrapping */
void xef_host_text_set_align(int t, int align);      /* 0 left 1 center 2 right 3 justified */
void xef_host_text_set_spacing(int t, double extra);
void xef_host_text_font(int t, int start, int end, const char *family, double size, int weight, int italic);
void xef_host_text_color(int t, int start, int end, double r, double g, double b, double a);
void xef_host_text_background(int t, int start, int end, double r, double g, double b, double a);
void xef_host_text_decoration(int t, int start, int end, int underline, int strike);
void xef_host_text_kern(int t, int start, int end, double kern);
void xef_host_text_size(int t, double *out4);        /* width, height, first baseline, line count */
void xef_host_text_draw(int c, int t, double x, double y);
int  xef_host_text_hit(int t, double x, double y, int *trailing);
void xef_host_text_cursor(int t, int index, double *out4);      /* x, y, height, line */
void xef_host_text_char_rect(int t, int index, double *out4);   /* x, y, w, h */
int  xef_host_text_lines(int t, double *out, int max);          /* per line: start byte, top, height, baseline */
void xef_host_font_metrics(const char *family, double size, int weight, int italic, double *out4, char *family_out, int family_len);

#ifdef __cplusplus
}
#endif
#endif
