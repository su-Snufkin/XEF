// XEF-OSX — host side of CoreGraphics-lite / AppKit-lite 2D drawing (rootfs-src/appkit/xef_host.h, "2D drawing"):
// guest bitmap contexts are cairo image surfaces over the guest's own pixel buffer (shared address space, premultiplied
// BGRA = CAIRO_FORMAT_ARGB32 on little-endian), text is laid out and drawn with pango. libcairo / libpango(cairo) are
// dlopen'ed on first use, so the loader keeps no link-time dependency on them. Only scalar arguments cross the HLE
// bridge (ints/pointers in x0.., doubles in d0..), results come back through out-pointers.
#include "loader/darwin_appkit_host.h"
#include "loader/darwin_hle.h"
#include "common/common.h"
#include <dlfcn.h>
#include <string.h>
#include <stdlib.h>
#include <mutex>
#include <unordered_map>
#include <stdint.h>

namespace xef {
namespace {

// ---- minimal cairo / pango declarations (ABI-stable public API) ----------------------------------------------------
struct cairo_t; struct cairo_surface_t; struct cairo_pattern_t;
struct cairo_matrix_t { double xx, yx, xy, yy, x0, y0; };
struct PangoFontMap; struct PangoContext; struct PangoLayout; struct PangoAttrList; struct PangoFontDescription;
struct PangoFontMetrics; struct PangoFont; struct PangoLayoutIter;
struct PangoAttribute { const void* klass; unsigned start_index, end_index; };
struct PangoRectangle { int x, y, width, height; };
constexpr int PANGO_SCALE = 1024;

struct Api {
    cairo_surface_t* (*image_surface_create_for_data)(unsigned char*, int, int, int, int);
    cairo_surface_t* (*image_surface_create)(int, int, int);
    unsigned char* (*image_surface_get_data)(cairo_surface_t*);
    int (*image_surface_get_stride)(cairo_surface_t*);
    void (*surface_destroy)(cairo_surface_t*);
    void (*surface_flush)(cairo_surface_t*);
    void (*surface_mark_dirty)(cairo_surface_t*);
    cairo_t* (*create)(cairo_surface_t*);
    void (*destroy)(cairo_t*);
    void (*save)(cairo_t*);
    void (*restore)(cairo_t*);
    void (*transform)(cairo_t*, const cairo_matrix_t*);
    void (*set_matrix)(cairo_t*, const cairo_matrix_t*);
    void (*get_matrix)(cairo_t*, cairo_matrix_t*);
    void (*new_path)(cairo_t*);
    void (*move_to)(cairo_t*, double, double);
    void (*line_to)(cairo_t*, double, double);
    void (*curve_to)(cairo_t*, double, double, double, double, double, double);
    void (*close_path)(cairo_t*);
    void (*rectangle)(cairo_t*, double, double, double, double);
    void (*arc)(cairo_t*, double, double, double, double, double);
    void (*arc_negative)(cairo_t*, double, double, double, double, double);
    void (*set_source_rgba)(cairo_t*, double, double, double, double);
    void (*set_source_surface)(cairo_t*, cairo_surface_t*, double, double);
    cairo_pattern_t* (*get_source)(cairo_t*);
    void (*pattern_set_filter)(cairo_pattern_t*, int);
    void (*fill)(cairo_t*);
    void (*fill_preserve)(cairo_t*);
    void (*stroke)(cairo_t*);
    void (*stroke_preserve)(cairo_t*);
    void (*clip)(cairo_t*);
    void (*reset_clip)(cairo_t*);
    void (*paint_with_alpha)(cairo_t*, double);
    void (*set_fill_rule)(cairo_t*, int);
    void (*set_line_width)(cairo_t*, double);
    void (*set_line_cap)(cairo_t*, int);
    void (*set_line_join)(cairo_t*, int);
    void (*set_miter_limit)(cairo_t*, double);
    void (*set_dash)(cairo_t*, const double*, int, double);
    void (*clip_extents)(cairo_t*, double*, double*, double*, double*);
    void (*path_extents)(cairo_t*, double*, double*, double*, double*);
    int (*in_fill)(cairo_t*, double, double);
    void (*set_operator)(cairo_t*, int);
    void (*set_antialias)(cairo_t*, int);
    cairo_pattern_t* (*pattern_create_linear)(double, double, double, double);
    cairo_pattern_t* (*pattern_create_radial)(double, double, double, double, double, double);
    void (*pattern_add_color_stop_rgba)(cairo_pattern_t*, double, double, double, double, double);
    void (*pattern_set_extend)(cairo_pattern_t*, int);
    void (*pattern_destroy)(cairo_pattern_t*);
    void (*set_source)(cairo_t*, cairo_pattern_t*);
    void (*paint)(cairo_t*);

    PangoFontMap* (*font_map_get_default)();
    PangoContext* (*font_map_create_context)(PangoFontMap*);
    void (*context_set_resolution)(PangoContext*, double);
    PangoLayout* (*layout_new)(PangoContext*);
    void (*layout_set_text)(PangoLayout*, const char*, int);
    void (*layout_set_width)(PangoLayout*, int);
    void (*layout_set_wrap)(PangoLayout*, int);
    void (*layout_set_alignment)(PangoLayout*, int);
    void (*layout_set_justify)(PangoLayout*, int);
    void (*layout_set_attributes)(PangoLayout*, PangoAttrList*);
    void (*layout_set_font_description)(PangoLayout*, const PangoFontDescription*);
    void (*layout_set_spacing)(PangoLayout*, int);
    void (*layout_get_extents)(PangoLayout*, PangoRectangle*, PangoRectangle*);
    int (*layout_get_baseline)(PangoLayout*);
    int (*layout_xy_to_index)(PangoLayout*, int, int, int*, int*);
    void (*layout_get_cursor_pos)(PangoLayout*, int, PangoRectangle*, PangoRectangle*);
    void (*layout_index_to_pos)(PangoLayout*, int, PangoRectangle*);
    int (*layout_get_line_count)(PangoLayout*);
    void (*layout_index_to_line_x)(PangoLayout*, int, int, int*, int*);
    PangoLayoutIter* (*layout_get_iter)(PangoLayout*);
    int (*layout_iter_next_line)(PangoLayoutIter*);
    void (*layout_iter_get_line_yrange)(PangoLayoutIter*, int*, int*);
    int (*layout_iter_get_baseline)(PangoLayoutIter*);
    int (*layout_iter_get_index)(PangoLayoutIter*);
    void (*layout_iter_free)(PangoLayoutIter*);
    void (*show_layout)(cairo_t*, PangoLayout*);
    void (*update_context)(cairo_t*, PangoContext*);
    void (*layout_context_changed)(PangoLayout*);
    PangoAttrList* (*attr_list_new)();
    void (*attr_list_insert)(PangoAttrList*, PangoAttribute*);
    void (*attr_list_unref)(PangoAttrList*);
    PangoAttribute* (*attr_font_desc_new)(const PangoFontDescription*);
    PangoAttribute* (*attr_foreground_new)(unsigned short, unsigned short, unsigned short);
    PangoAttribute* (*attr_foreground_alpha_new)(unsigned short);
    PangoAttribute* (*attr_background_new)(unsigned short, unsigned short, unsigned short);
    PangoAttribute* (*attr_background_alpha_new)(unsigned short);
    PangoAttribute* (*attr_underline_new)(int);
    PangoAttribute* (*attr_strikethrough_new)(int);
    PangoAttribute* (*attr_letter_spacing_new)(int);
    PangoFontDescription* (*font_description_new)();
    void (*font_description_set_family)(PangoFontDescription*, const char*);
    void (*font_description_set_absolute_size)(PangoFontDescription*, double);
    void (*font_description_set_weight)(PangoFontDescription*, int);
    void (*font_description_set_style)(PangoFontDescription*, int);
    void (*font_description_free)(PangoFontDescription*);
    const char* (*font_description_get_family)(const PangoFontDescription*);
    PangoFontMetrics* (*context_get_metrics)(PangoContext*, const PangoFontDescription*, void*);
    int (*font_metrics_get_ascent)(PangoFontMetrics*);
    int (*font_metrics_get_descent)(PangoFontMetrics*);
    int (*font_metrics_get_approximate_char_width)(PangoFontMetrics*);
    int (*font_metrics_get_height)(PangoFontMetrics*);
    void (*font_metrics_unref)(PangoFontMetrics*);
    PangoFont* (*context_load_font)(PangoContext*, const PangoFontDescription*);
    PangoFontDescription* (*font_describe)(PangoFont*);
    void (*g_object_unref)(void*);
};

std::mutex g_lock;
Api A;
int g_state = 0;   // 0 not tried, 1 ok, -1 unavailable
PangoContext* g_pctx = nullptr;

struct Ctx { cairo_t* cr; cairo_surface_t* surf; };
std::unordered_map<int, Ctx> g_ctx;
std::unordered_map<int, PangoLayout*> g_text;
std::unordered_map<int, PangoAttrList*> g_attrs;
int g_next_ctx = 1, g_next_text = 1;

template <class T> bool sym(void* lib, const char* n, T& out) { out = (T)dlsym(lib, n); if (!out) XEF_LOG(1, "xef_cg: missing %s", n); return out != nullptr; }

bool load() {
    if (g_state) return g_state > 0;
    g_state = -1;
    void* c = dlopen("libcairo.so.2", RTLD_NOW | RTLD_GLOBAL);
    void* p = dlopen("libpango-1.0.so.0", RTLD_NOW | RTLD_GLOBAL);
    void* pc = dlopen("libpangocairo-1.0.so.0", RTLD_NOW | RTLD_GLOBAL);
    void* go = dlopen("libgobject-2.0.so.0", RTLD_NOW | RTLD_GLOBAL);
    if (!c || !p || !pc || !go) { XEF_LOG(1, "xef_cg: cairo/pango not available on the host (2D drawing disabled)"); return false; }
    bool ok = true;
#define C(f, n) ok &= sym(c, n, A.f)
#define P(f, n) ok &= sym(p, n, A.f)
#define PC(f, n) ok &= sym(pc, n, A.f)
    C(image_surface_create_for_data, "cairo_image_surface_create_for_data"); C(image_surface_create, "cairo_image_surface_create");
    C(image_surface_get_data, "cairo_image_surface_get_data"); C(image_surface_get_stride, "cairo_image_surface_get_stride");
    C(surface_destroy, "cairo_surface_destroy"); C(surface_flush, "cairo_surface_flush"); C(surface_mark_dirty, "cairo_surface_mark_dirty");
    C(create, "cairo_create"); C(destroy, "cairo_destroy"); C(save, "cairo_save"); C(restore, "cairo_restore");
    C(transform, "cairo_transform"); C(set_matrix, "cairo_set_matrix"); C(get_matrix, "cairo_get_matrix");
    C(new_path, "cairo_new_path"); C(move_to, "cairo_move_to"); C(line_to, "cairo_line_to"); C(curve_to, "cairo_curve_to");
    C(close_path, "cairo_close_path"); C(rectangle, "cairo_rectangle"); C(arc, "cairo_arc"); C(arc_negative, "cairo_arc_negative");
    C(set_source_rgba, "cairo_set_source_rgba"); C(set_source_surface, "cairo_set_source_surface"); C(get_source, "cairo_get_source");
    C(pattern_set_filter, "cairo_pattern_set_filter");
    C(fill, "cairo_fill"); C(fill_preserve, "cairo_fill_preserve"); C(stroke, "cairo_stroke"); C(stroke_preserve, "cairo_stroke_preserve");
    C(clip, "cairo_clip"); C(reset_clip, "cairo_reset_clip"); C(paint_with_alpha, "cairo_paint_with_alpha");
    C(set_fill_rule, "cairo_set_fill_rule"); C(set_line_width, "cairo_set_line_width"); C(set_line_cap, "cairo_set_line_cap");
    C(set_line_join, "cairo_set_line_join"); C(set_miter_limit, "cairo_set_miter_limit"); C(set_dash, "cairo_set_dash");
    C(clip_extents, "cairo_clip_extents"); C(path_extents, "cairo_path_extents"); C(in_fill, "cairo_in_fill");
    C(set_operator, "cairo_set_operator"); C(set_antialias, "cairo_set_antialias");
    C(pattern_create_linear, "cairo_pattern_create_linear"); C(pattern_create_radial, "cairo_pattern_create_radial");
    C(pattern_add_color_stop_rgba, "cairo_pattern_add_color_stop_rgba"); C(pattern_set_extend, "cairo_pattern_set_extend");
    C(pattern_destroy, "cairo_pattern_destroy"); C(set_source, "cairo_set_source"); C(paint, "cairo_paint");
    PC(font_map_get_default, "pango_cairo_font_map_get_default"); P(font_map_create_context, "pango_font_map_create_context");
    PC(context_set_resolution, "pango_cairo_context_set_resolution"); PC(show_layout, "pango_cairo_show_layout");
    PC(update_context, "pango_cairo_update_context");
    P(layout_new, "pango_layout_new"); P(layout_set_text, "pango_layout_set_text"); P(layout_set_width, "pango_layout_set_width");
    P(layout_set_wrap, "pango_layout_set_wrap"); P(layout_set_alignment, "pango_layout_set_alignment");
    P(layout_set_justify, "pango_layout_set_justify"); P(layout_set_attributes, "pango_layout_set_attributes");
    P(layout_set_font_description, "pango_layout_set_font_description"); P(layout_set_spacing, "pango_layout_set_spacing");
    P(layout_get_extents, "pango_layout_get_extents"); P(layout_get_baseline, "pango_layout_get_baseline");
    P(layout_xy_to_index, "pango_layout_xy_to_index"); P(layout_get_cursor_pos, "pango_layout_get_cursor_pos");
    P(layout_index_to_pos, "pango_layout_index_to_pos"); P(layout_get_line_count, "pango_layout_get_line_count");
    P(layout_index_to_line_x, "pango_layout_index_to_line_x"); P(layout_context_changed, "pango_layout_context_changed");
    P(layout_get_iter, "pango_layout_get_iter"); P(layout_iter_next_line, "pango_layout_iter_next_line");
    P(layout_iter_get_line_yrange, "pango_layout_iter_get_line_yrange"); P(layout_iter_get_baseline, "pango_layout_iter_get_baseline");
    P(layout_iter_get_index, "pango_layout_iter_get_index"); P(layout_iter_free, "pango_layout_iter_free");
    P(attr_list_new, "pango_attr_list_new"); P(attr_list_insert, "pango_attr_list_insert"); P(attr_list_unref, "pango_attr_list_unref");
    P(attr_font_desc_new, "pango_attr_font_desc_new"); P(attr_foreground_new, "pango_attr_foreground_new");
    P(attr_foreground_alpha_new, "pango_attr_foreground_alpha_new"); P(attr_background_new, "pango_attr_background_new");
    P(attr_background_alpha_new, "pango_attr_background_alpha_new");
    P(attr_underline_new, "pango_attr_underline_new"); P(attr_strikethrough_new, "pango_attr_strikethrough_new");
    P(attr_letter_spacing_new, "pango_attr_letter_spacing_new");
    P(font_description_new, "pango_font_description_new"); P(font_description_set_family, "pango_font_description_set_family");
    P(font_description_set_absolute_size, "pango_font_description_set_absolute_size");
    P(font_description_set_weight, "pango_font_description_set_weight"); P(font_description_set_style, "pango_font_description_set_style");
    P(font_description_free, "pango_font_description_free"); P(font_description_get_family, "pango_font_description_get_family");
    P(context_get_metrics, "pango_context_get_metrics"); P(font_metrics_get_ascent, "pango_font_metrics_get_ascent");
    P(font_metrics_get_descent, "pango_font_metrics_get_descent");
    P(font_metrics_get_approximate_char_width, "pango_font_metrics_get_approximate_char_width");
    P(font_metrics_get_height, "pango_font_metrics_get_height"); P(font_metrics_unref, "pango_font_metrics_unref");
    P(context_load_font, "pango_context_load_font"); P(font_describe, "pango_font_describe");
#undef C
#undef P
#undef PC
    ok &= sym(go, "g_object_unref", A.g_object_unref);
    if (!ok) return false;
    g_pctx = A.font_map_create_context(A.font_map_get_default());
    A.context_set_resolution(g_pctx, 72.0);   // 1 pt = 1 px: macOS at backing scale 1
    g_state = 1;
    return true;
}

cairo_t* cr_of(int h) { auto it = g_ctx.find(h); return it == g_ctx.end() ? nullptr : it->second.cr; }
PangoLayout* layout_of(int h) { auto it = g_text.find(h); return it == g_text.end() ? nullptr : it->second; }

#define CR(h) std::lock_guard<std::mutex> lk(g_lock); cairo_t* cr = cr_of(h); if (!cr) return
#define LAYOUT(h) std::lock_guard<std::mutex> lk(g_lock); PangoLayout* l = layout_of(h); if (!l) return

PangoFontDescription* make_desc(const char* family, double size, int weight, int italic) {
    PangoFontDescription* d = A.font_description_new();
    A.font_description_set_family(d, family && *family ? family : "Sans");
    A.font_description_set_absolute_size(d, (size > 0 ? size : 13.0) * PANGO_SCALE);
    A.font_description_set_weight(d, weight > 0 ? weight : 400);
    A.font_description_set_style(d, italic ? 2 /*PANGO_STYLE_ITALIC*/ : 0);
    return d;
}

void add_attr(int t, PangoAttribute* a, int start, int end) {
    if (!a) return;
    a->start_index = (unsigned)(start < 0 ? 0 : start);
    a->end_index = end < 0 ? 0xffffffffu : (unsigned)end;
    PangoAttrList*& list = g_attrs[t];
    if (!list) list = A.attr_list_new();
    A.attr_list_insert(list, a);
    A.layout_set_attributes(g_text[t], list);
}

unsigned short c16(double v) { v = v < 0 ? 0 : v > 1 ? 1 : v; return (unsigned short)(v * 65535.0 + 0.5); }

} // namespace

// ---- bitmap contexts ------------------------------------------------------------------------------------------------
extern "C" int xef_host_cg_create(void* data, int w, int h, int stride) {
    std::lock_guard<std::mutex> lk(g_lock);
    if (!load() || !data || w <= 0 || h <= 0) return 0;
    cairo_surface_t* s = A.image_surface_create_for_data((unsigned char*)data, 0 /*CAIRO_FORMAT_ARGB32*/, w, h, stride);
    cairo_t* cr = A.create(s);
    int id = g_next_ctx++;
    g_ctx[id] = {cr, s};
    return id;
}
extern "C" void xef_host_cg_destroy(int h) {
    std::lock_guard<std::mutex> lk(g_lock);
    auto it = g_ctx.find(h);
    if (it == g_ctx.end()) return;
    A.surface_flush(it->second.surf);
    A.destroy(it->second.cr);
    A.surface_destroy(it->second.surf);
    g_ctx.erase(it);
}
extern "C" void xef_host_cg_flush(int h) { std::lock_guard<std::mutex> lk(g_lock); auto it = g_ctx.find(h); if (it != g_ctx.end()) A.surface_flush(it->second.surf); }
// the guest wrote to the buffer directly: cairo must drop any cached copy
extern "C" void xef_host_cg_mark_dirty(int h) { std::lock_guard<std::mutex> lk(g_lock); auto it = g_ctx.find(h); if (it != g_ctx.end()) A.surface_mark_dirty(it->second.surf); }
extern "C" void xef_host_cg_save(int h) { CR(h); A.save(cr); }
extern "C" void xef_host_cg_restore(int h) { CR(h); A.restore(cr); }
// CG affine (a b c d tx ty): x' = a*x + c*y + tx, y' = b*x + d*y + ty
extern "C" void xef_host_cg_concat(int h, double a, double b, double c, double d, double tx, double ty) {
    CR(h); cairo_matrix_t m{a, b, c, d, tx, ty}; A.transform(cr, &m); }
extern "C" void xef_host_cg_set_matrix(int h, double a, double b, double c, double d, double tx, double ty) {
    CR(h); cairo_matrix_t m{a, b, c, d, tx, ty}; A.set_matrix(cr, &m); }
extern "C" void xef_host_cg_get_matrix(int h, double* out) {
    CR(h); cairo_matrix_t m; A.get_matrix(cr, &m); out[0] = m.xx; out[1] = m.yx; out[2] = m.xy; out[3] = m.yy; out[4] = m.x0; out[5] = m.y0; }

// ---- paths ------------------------------------------------------------------------------------------------------------
extern "C" void xef_host_cg_new_path(int h) { CR(h); A.new_path(cr); }
extern "C" void xef_host_cg_move(int h, double x, double y) { CR(h); A.move_to(cr, x, y); }
extern "C" void xef_host_cg_line(int h, double x, double y) { CR(h); A.line_to(cr, x, y); }
extern "C" void xef_host_cg_curve(int h, double x1, double y1, double x2, double y2, double x3, double y3) { CR(h); A.curve_to(cr, x1, y1, x2, y2, x3, y3); }
extern "C" void xef_host_cg_close(int h) { CR(h); A.close_path(cr); }
extern "C" void xef_host_cg_rect(int h, double x, double y, double w, double hh) { CR(h); A.rectangle(cr, x, y, w, hh); }
extern "C" void xef_host_cg_arc(int h, double x, double y, double r, double a0, double a1, int negative) {
    CR(h); if (negative) A.arc_negative(cr, x, y, r, a0, a1); else A.arc(cr, x, y, r, a0, a1); }
extern "C" void xef_host_cg_path_extents(int h, double* out) { CR(h); A.path_extents(cr, &out[0], &out[1], &out[2], &out[3]); }
extern "C" int xef_host_cg_in_fill(int h, double x, double y) { std::lock_guard<std::mutex> lk(g_lock); cairo_t* cr = cr_of(h); return cr ? A.in_fill(cr, x, y) : 0; }

// ---- painting ---------------------------------------------------------------------------------------------------------
extern "C" void xef_host_cg_source_rgba(int h, double r, double g, double b, double a) { CR(h); A.set_source_rgba(cr, r, g, b, a); }
extern "C" void xef_host_cg_fill(int h, int evenodd, int preserve) {
    CR(h); A.set_fill_rule(cr, evenodd ? 1 : 0); if (preserve) A.fill_preserve(cr); else A.fill(cr); }
extern "C" void xef_host_cg_stroke(int h, int preserve) { CR(h); if (preserve) A.stroke_preserve(cr); else A.stroke(cr); }
extern "C" void xef_host_cg_clip(int h, int evenodd) { CR(h); A.set_fill_rule(cr, evenodd ? 1 : 0); A.clip(cr); }
extern "C" void xef_host_cg_reset_clip(int h) { CR(h); A.reset_clip(cr); }
extern "C" void xef_host_cg_clip_extents(int h, double* out) { CR(h); A.clip_extents(cr, &out[0], &out[1], &out[2], &out[3]); }
extern "C" void xef_host_cg_line_style(int h, double width, int cap, int join, double miter) {
    CR(h); A.set_line_width(cr, width); A.set_line_cap(cr, cap); A.set_line_join(cr, join); A.set_miter_limit(cr, miter); }
extern "C" void xef_host_cg_dash(int h, const double* d, int n, double phase) { CR(h); A.set_dash(cr, n > 0 ? d : nullptr, n > 0 ? n : 0, phase); }
// CGBlendMode / NSCompositingOperation subset, mapped to cairo_operator_t by the guest
extern "C" void xef_host_cg_operator(int h, int op) { CR(h); A.set_operator(cr, op); }
extern "C" void xef_host_cg_antialias(int h, int on) { CR(h); A.set_antialias(cr, on ? 0 /*DEFAULT*/ : 1 /*NONE*/); }

// Pixel layouts of guest bitmaps (CGImage / CGBitmapContext), packed by the guest:
//   bits 0-7 bits per pixel, 8-15 bits per component (8 or 16), 16-18 CGImageAlphaInfo, bit 19 32-bit little-endian,
//   bit 20 16-bit little-endian, bit 21 gray (1 colour component, else RGB).
namespace {
struct Layout { int bpp, bpc, alpha, little32, little16, gray; };
Layout unpack(int v) { return {v & 0xff, (v >> 8) & 0xff, (v >> 16) & 7, (v >> 19) & 1, (v >> 20) & 1, (v >> 21) & 1}; }
// one pixel -> premultiplied ARGB32
uint32_t read_px(const unsigned char* p, const Layout& L) {
    int ncol = L.gray ? 1 : 3;
    bool has_a = L.alpha >= 1 && L.alpha <= 4, skip = L.alpha == 5 || L.alpha == 6, first = L.alpha == 2 || L.alpha == 4 || L.alpha == 6;
    int ncomp = L.alpha == 7 ? 1 : ncol + (has_a || skip ? 1 : 0);
    unsigned comp[4] = {0, 0, 0, 255};
    int bytes = L.bpc / 8;
    unsigned char tmp[8];
    if (L.bpp == 32 && L.bpc == 8 && L.little32) { tmp[0] = p[3]; tmp[1] = p[2]; tmp[2] = p[1]; tmp[3] = p[0]; p = tmp; }
    for (int i = 0; i < ncomp && i < 4; i++) {
        const unsigned char* q = p + i * bytes;
        comp[i] = bytes == 2 ? (L.little16 ? q[1] : q[0]) : q[0];
    }
    unsigned r, g, b, a = 255;
    if (L.alpha == 7) { a = comp[0]; r = g = b = 0; }
    else {
        int c0 = (first && (has_a || skip)) ? 1 : 0;
        if (has_a) a = first ? comp[0] : comp[ncol];
        r = comp[c0]; g = L.gray ? r : comp[c0 + 1]; b = L.gray ? r : comp[c0 + 2];
        if (L.alpha == 3 || L.alpha == 4) { r = r * a / 255; g = g * a / 255; b = b * a / 255; }
    }
    return (a << 24) | (r << 16) | (g << 8) | b;
}
// premultiplied ARGB32 -> one pixel of the layout (8 bits per component only)
void write_px(unsigned char* p, uint32_t v, const Layout& L) {
    unsigned a = v >> 24, r = (v >> 16) & 0xff, g = (v >> 8) & 0xff, b = v & 0xff;
    if ((L.alpha == 3 || L.alpha == 4) && a && a != 255) { r = r * 255 / a; g = g * 255 / a; b = b * 255 / a; }
    if (L.alpha == 7) { p[0] = (unsigned char)a; return; }
    int ncol = L.gray ? 1 : 3;
    bool has_a = L.alpha >= 1 && L.alpha <= 4, skip = L.alpha == 5 || L.alpha == 6, first = L.alpha == 2 || L.alpha == 4 || L.alpha == 6;
    unsigned col[3] = {r, g, b};
    if (L.gray) col[0] = (r * 77 + g * 151 + b * 28) >> 8;
    unsigned char out[4]; int n = 0;
    if (first && (has_a || skip)) out[n++] = skip ? 255 : (unsigned char)a;
    for (int i = 0; i < ncol; i++) out[n++] = (unsigned char)col[i];
    if (!first && (has_a || skip)) out[n++] = skip ? 255 : (unsigned char)a;
    if (L.bpp == 32 && L.little32) { for (int i = 0; i < 4; i++) p[i] = out[3 - i]; return; }
    for (int i = 0; i < n && i * 8 < L.bpp; i++) p[i] = out[i];
}
}  // namespace

// Converts between a native premultiplied ARGB32 buffer and a guest layout (to_native: guest -> ARGB, else ARGB -> guest).
extern "C" void xef_host_cg_convert(void* argb, int argb_stride, void* px, int stride, int w, int h, int layout, int to_native) {
    if (!argb || !px) return;
    Layout L = unpack(layout);
    int pb = L.bpp / 8;
    for (int y = 0; y < h; y++) {
        uint32_t* a = (uint32_t*)((unsigned char*)argb + (size_t)y * argb_stride);
        unsigned char* g = (unsigned char*)px + (size_t)y * stride;
        if (to_native) for (int x = 0; x < w; x++) a[x] = read_px(g + x * pb, L);
        else for (int x = 0; x < w; x++) write_px(g + x * pb, a[x], L);
    }
}

// Draws a w x h image into the unit square of the current user space (the guest sets up the image transform; rows go
// top to bottom along +y).
extern "C" void xef_host_cg_image(int h, const void* px, int w, int hh, int stride, int layout, double alpha, int interpolate) {
    CR(h);
    if (!px || w <= 0 || hh <= 0) return;
    cairo_surface_t* s = A.image_surface_create(0, w, hh);
    A.surface_flush(s);
    Layout L = unpack(layout);
    int pb = L.bpp / 8;
    unsigned char* dst = A.image_surface_get_data(s);
    int ds = A.image_surface_get_stride(s);
    for (int y = 0; y < hh; y++) {
        const unsigned char* sr = (const unsigned char*)px + (size_t)y * stride;
        uint32_t* dr = (uint32_t*)(dst + (size_t)y * ds);
        for (int x = 0; x < w; x++) dr[x] = read_px(sr + x * pb, L);
    }
    A.surface_mark_dirty(s);
    A.save(cr);
    cairo_matrix_t m{1.0 / w, 0, 0, 1.0 / hh, 0, 0};
    A.transform(cr, &m);
    A.set_source_surface(cr, s, 0, 0);
    A.pattern_set_filter(A.get_source(cr), interpolate ? 1 /*GOOD*/ : 3 /*NEAREST*/);
    A.new_path(cr);
    A.rectangle(cr, 0, 0, w, hh);
    A.clip(cr);
    A.paint_with_alpha(cr, alpha);
    A.restore(cr);
    A.surface_destroy(s);
}

// Gradients fill the current clip. stops: n x (offset, r, g, b, a). extend: bit 0 before start, bit 1 after end.
// radial: (x0, y0, r0) -> (x1, y1, r1); linear ignores the radii.
extern "C" void xef_host_cg_gradient(int h, int radial, double x0, double y0, double r0, double x1, double y1, double r1,
                                     const double* stops, int n, int extend) {
    CR(h);
    if (!stops || n <= 0) return;
    cairo_pattern_t* p = radial ? A.pattern_create_radial(x0, y0, r0, x1, y1, r1) : A.pattern_create_linear(x0, y0, x1, y1);
    for (int i = 0; i < n; i++) A.pattern_add_color_stop_rgba(p, stops[i * 5], stops[i * 5 + 1], stops[i * 5 + 2], stops[i * 5 + 3], stops[i * 5 + 4]);
    // cairo cannot extend one side only: CG's "draws before/after" options become PAD when either is set
    A.pattern_set_extend(p, extend ? 3 /*PAD*/ : 0 /*NONE*/);
    A.save(cr);
    A.set_source(cr, p);
    A.paint(cr);
    A.restore(cr);
    A.pattern_destroy(p);
}

// ---- text (pango) -------------------------------------------------------------------------------------------------------
// A text object is a pango layout over UTF-8; ranges are byte offsets (the guest maps UTF-16 indices).
extern "C" int xef_host_text_create(const char* utf8, int len) {
    std::lock_guard<std::mutex> lk(g_lock);
    if (!load()) return 0;
    PangoLayout* l = A.layout_new(g_pctx);
    A.layout_set_text(l, utf8 ? utf8 : "", utf8 ? len : 0);
    A.layout_set_wrap(l, 2 /*PANGO_WRAP_WORD_CHAR*/);
    int id = g_next_text++;
    g_text[id] = l;
    return id;
}
extern "C" void xef_host_text_destroy(int t) {
    std::lock_guard<std::mutex> lk(g_lock);
    auto it = g_text.find(t);
    if (it == g_text.end()) return;
    A.g_object_unref(it->second);
    g_text.erase(it);
    auto at = g_attrs.find(t);
    if (at != g_attrs.end()) { A.attr_list_unref(at->second); g_attrs.erase(at); }
}
// width < 0: no wrapping
extern "C" void xef_host_text_set_width(int t, double width) { LAYOUT(t); A.layout_set_width(l, width < 0 ? -1 : (int)(width * PANGO_SCALE)); }
// align: 0 left, 1 center, 2 right, 3 justified (NSTextAlignment order on macOS)
extern "C" void xef_host_text_set_align(int t, int align) {
    LAYOUT(t); A.layout_set_alignment(l, align == 1 ? 1 : align == 2 ? 2 : 0); A.layout_set_justify(l, align == 3); }
extern "C" void xef_host_text_set_spacing(int t, double extra) { LAYOUT(t); A.layout_set_spacing(l, (int)(extra * PANGO_SCALE)); }
extern "C" void xef_host_text_font(int t, int start, int end, const char* family, double size, int weight, int italic) {
    LAYOUT(t);
    PangoFontDescription* d = make_desc(family, size, weight, italic);
    if (start < 0) A.layout_set_font_description(l, d);
    else add_attr(t, A.attr_font_desc_new(d), start, end);
    A.font_description_free(d);
}
extern "C" void xef_host_text_color(int t, int start, int end, double r, double g, double b, double a) {
    LAYOUT(t); (void)l;
    add_attr(t, A.attr_foreground_new(c16(r), c16(g), c16(b)), start, end);
    if (a < 1.0) add_attr(t, A.attr_foreground_alpha_new(c16(a)), start, end);
}
extern "C" void xef_host_text_background(int t, int start, int end, double r, double g, double b, double a) {
    LAYOUT(t); (void)l;
    add_attr(t, A.attr_background_new(c16(r), c16(g), c16(b)), start, end);
    if (a < 1.0) add_attr(t, A.attr_background_alpha_new(c16(a)), start, end);
}
// style: 0 none, 1 single, 2 double; strike: 0/1
extern "C" void xef_host_text_decoration(int t, int start, int end, int underline, int strike) {
    LAYOUT(t); (void)l;
    if (underline) add_attr(t, A.attr_underline_new(underline == 2 ? 2 : 1), start, end);
    if (strike) add_attr(t, A.attr_strikethrough_new(1), start, end);
}
extern "C" void xef_host_text_kern(int t, int start, int end, double kern) { LAYOUT(t); (void)l; add_attr(t, A.attr_letter_spacing_new((int)(kern * PANGO_SCALE)), start, end); }
// out: logical width, height, first-line baseline, line count
extern "C" void xef_host_text_size(int t, double* out) {
    LAYOUT(t);
    PangoRectangle ink, log;
    A.layout_get_extents(l, &ink, &log);
    out[0] = (double)(log.x + log.width) / PANGO_SCALE;
    out[1] = (double)(log.y + log.height) / PANGO_SCALE;
    out[2] = (double)A.layout_get_baseline(l) / PANGO_SCALE;
    out[3] = A.layout_get_line_count(l);
}
// draws the layout with its top-left corner at (x, y) of the current user space (y grows downwards there)
extern "C" void xef_host_text_draw(int c, int t, double x, double y) {
    std::lock_guard<std::mutex> lk(g_lock);
    cairo_t* cr = cr_of(c); PangoLayout* l = layout_of(t);
    if (!cr || !l) return;
    A.save(cr);
    A.move_to(cr, x, y);
    A.show_layout(cr, l);
    A.new_path(cr);
    A.restore(cr);
}
// byte index under (x, y) in layout coordinates; *trailing = number of characters past the index (0/1)
extern "C" int xef_host_text_hit(int t, double x, double y, int* trailing) {
    std::lock_guard<std::mutex> lk(g_lock);
    PangoLayout* l = layout_of(t);
    if (!l) return 0;
    int idx = 0, tr = 0;
    A.layout_xy_to_index(l, (int)(x * PANGO_SCALE), (int)(y * PANGO_SCALE), &idx, &tr);
    if (trailing) *trailing = tr;
    return idx;
}
// caret rectangle (x, y, height) and line number at byte index
extern "C" void xef_host_text_cursor(int t, int index, double* out) {
    LAYOUT(t);
    PangoRectangle s, w;
    A.layout_get_cursor_pos(l, index, &s, &w);
    int line = 0, xp = 0;
    A.layout_index_to_line_x(l, index, 0, &line, &xp);
    out[0] = (double)s.x / PANGO_SCALE; out[1] = (double)s.y / PANGO_SCALE; out[2] = (double)s.height / PANGO_SCALE; out[3] = line;
}
// glyph box of the character at byte index
extern "C" void xef_host_text_char_rect(int t, int index, double* out) {
    LAYOUT(t);
    PangoRectangle r;
    A.layout_index_to_pos(l, index, &r);
    out[0] = (double)r.x / PANGO_SCALE; out[1] = (double)r.y / PANGO_SCALE; out[2] = (double)r.width / PANGO_SCALE; out[3] = (double)r.height / PANGO_SCALE;
}
// per line: out[i*4..] = first byte index, top y, height, baseline; returns the number of lines (at most max)
extern "C" int xef_host_text_lines(int t, double* out, int max) {
    std::lock_guard<std::mutex> lk(g_lock);
    PangoLayout* l = layout_of(t);
    if (!l) return 0;
    PangoLayoutIter* it = A.layout_get_iter(l);
    int n = 0;
    do {
        if (n >= max) break;
        int y0 = 0, y1 = 0;
        A.layout_iter_get_line_yrange(it, &y0, &y1);
        out[n * 4] = A.layout_iter_get_index(it);
        out[n * 4 + 1] = (double)y0 / PANGO_SCALE;
        out[n * 4 + 2] = (double)(y1 - y0) / PANGO_SCALE;
        out[n * 4 + 3] = (double)A.layout_iter_get_baseline(it) / PANGO_SCALE;
        n++;
    } while (A.layout_iter_next_line(it));
    A.layout_iter_free(it);
    return n;
}
// font metrics: out = ascent, descent, line height, average char width; family_out receives the resolved family name
extern "C" void xef_host_font_metrics(const char* family, double size, int weight, int italic, double* out, char* family_out, int family_len) {
    std::lock_guard<std::mutex> lk(g_lock);
    out[0] = size * 0.8; out[1] = size * 0.2; out[2] = size * 1.2; out[3] = size * 0.5;
    if (family_out && family_len > 0) family_out[0] = 0;
    if (!load()) return;
    PangoFontDescription* d = make_desc(family, size, weight, italic);
    PangoFontMetrics* m = A.context_get_metrics(g_pctx, d, nullptr);
    if (m) {
        out[0] = (double)A.font_metrics_get_ascent(m) / PANGO_SCALE;
        out[1] = (double)A.font_metrics_get_descent(m) / PANGO_SCALE;
        int hgt = A.font_metrics_get_height(m);
        out[2] = hgt > 0 ? (double)hgt / PANGO_SCALE : out[0] + out[1];
        out[3] = (double)A.font_metrics_get_approximate_char_width(m) / PANGO_SCALE;
        A.font_metrics_unref(m);
    }
    if (family_out && family_len > 0) {
        if (PangoFont* f = A.context_load_font(g_pctx, d)) {
            PangoFontDescription* fd = A.font_describe(f);
            const char* fam = fd ? A.font_description_get_family(fd) : nullptr;
            if (fam) { strncpy(family_out, fam, family_len - 1); family_out[family_len - 1] = 0; }
            if (fd) A.font_description_free(fd);
            A.g_object_unref(f);
        }
    }
    A.font_description_free(d);
}

namespace {
struct Fn { const char* name; void* fn; };
const Fn kFns[] = {
#define F(n) {"_" #n, (void*)&n}
    F(xef_host_cg_create), F(xef_host_cg_destroy), F(xef_host_cg_flush), F(xef_host_cg_mark_dirty), F(xef_host_cg_save),
    F(xef_host_cg_restore), F(xef_host_cg_concat), F(xef_host_cg_set_matrix), F(xef_host_cg_get_matrix), F(xef_host_cg_new_path),
    F(xef_host_cg_move), F(xef_host_cg_line), F(xef_host_cg_curve), F(xef_host_cg_close), F(xef_host_cg_rect), F(xef_host_cg_arc),
    F(xef_host_cg_path_extents), F(xef_host_cg_in_fill), F(xef_host_cg_source_rgba), F(xef_host_cg_fill), F(xef_host_cg_stroke),
    F(xef_host_cg_clip), F(xef_host_cg_reset_clip), F(xef_host_cg_clip_extents), F(xef_host_cg_line_style), F(xef_host_cg_dash),
    F(xef_host_cg_operator), F(xef_host_cg_antialias), F(xef_host_cg_image), F(xef_host_cg_convert), F(xef_host_cg_gradient),
    F(xef_host_text_create), F(xef_host_text_destroy), F(xef_host_text_set_width), F(xef_host_text_set_align),
    F(xef_host_text_set_spacing), F(xef_host_text_font), F(xef_host_text_color), F(xef_host_text_background),
    F(xef_host_text_decoration), F(xef_host_text_kern), F(xef_host_text_size), F(xef_host_text_draw), F(xef_host_text_hit),
    F(xef_host_text_cursor), F(xef_host_text_char_rect), F(xef_host_text_lines), F(xef_host_font_metrics),
#undef F
};
} // namespace

uint64_t darwin_cg_host_resolve(const char* name) {
    for (const Fn& f : kFns)
        if (!strcmp(name, f.name)) return darwin_hle_register_function(name, f.fn);
    return 0;
}

} // namespace xef
