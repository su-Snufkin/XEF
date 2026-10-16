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
typedef struct { int type; int keycode; int x; int y; int flags; int handle; } xef_host_event_t;
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

/* Metal hardware GPU acceleration interface */
typedef struct {
    uint32_t rt_tex_id;
    uint32_t tex_id;
    int      frag_mode;       /* 0=auto/tex_rgba, 1=color_only, 2=tex_rgb, 3=blit2d, 4=const_color */
    int      blend_enable;
    int      src_rgb, dst_rgb, rgb_op;
    int      src_a, dst_a, a_op;
    int      write_mask;
    int      clip_rect[4];    /* x, y, w, h */
    int      viewport[4];     /* x, y, w, h */
    float    color_scale;
    float    uv_left_top[2];
    float    uv_dims[2];
    int      filter_linear;   /* 1=linear, 0=nearest */
    int      clamp_to_edge;   /* 1=clamp, 0=repeat */
    int      depth_test_enable;
    int      depth_write_enable;
    int      depth_compare_op;
    int      stencil_test_enable;
    int      stencil_compare_op;
    int      stencil_fail_op;
    int      stencil_depth_fail_op;
    int      stencil_pass_op;
    uint32_t stencil_read_mask;
    uint32_t stencil_write_mask;
    uint32_t stencil_ref;
    uint32_t depth_tex_id;
} xef_host_metal_pipeline_t;

typedef struct {
    float sx, sy, sz;
    float u, v;
    float r, g, b, a;
} xef_host_metal_vertex_t;

uint32_t xef_host_metal_tex_create(int w, int h, int fmt, int is_render_target);
void     xef_host_metal_tex_update(uint32_t tex_id, int x, int y, int w, int h, const void *data, int pitch);
void     xef_host_metal_tex_copy(uint32_t src_tex_id, int sx, int sy, int sw, int sh, uint32_t dst_tex_id, int dx, int dy);
void     xef_host_metal_tex_readback(uint32_t tex_id, int x, int y, int w, int h, void *out_data, int pitch);
void     xef_host_metal_tex_destroy(uint32_t tex_id);

void     xef_host_metal_pass_begin(int handle, uint32_t rt_tex_id, int clear, float r, float g, float b, float a);
void     xef_host_metal_pass_end(int handle, uint32_t rt_tex_id);

void     xef_host_metal_draw(int handle,
                             const xef_host_metal_pipeline_t *pipe,
                             int prim_type,
                             const xef_host_metal_vertex_t *vertices,
                             int vertex_count,
                             const uint32_t *indices,
                             int index_count);

void     xef_host_metal_present_gpu(int handle, uint32_t tex_id);
const char *xef_host_metal_backend_name(void);
#ifdef __cplusplus
}
#endif
#endif
