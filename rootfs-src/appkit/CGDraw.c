/* CoreGraphics-lite 2D drawing (included by CoreGraphics.c): CGContext (bitmap contexts), CGPath, CGColor, CGColorSpace,
 * CGImage, CGDataProvider, CGGradient and the geometry helpers. Rasterization runs on the host (cairo, xef_host_cg_*):
 * a bitmap context is a host cairo context over the guest's pixel buffer. Premultiplied BGRA (kCGImageAlphaPremultiplied-
 * First | kCGBitmapByteOrder32Little) is the host's native format and is drawn in place; any other layout is rendered into
 * a private native buffer and converted into the caller's buffer when it can be observed (GetData, CreateImage, Flush,
 * DrawImage, Release). The CTM lives on the host; its base matrix flips the bitmap so that user space is y-up with the
 * origin at the bottom-left, like CG. Fill/stroke colours, alpha and text state are kept here. */
#include <math.h>
#include <pthread.h>
#include <stdio.h>

extern int  xef_host_cg_create(void *data, int w, int h, int stride);
extern void xef_host_cg_destroy(int h);
extern void xef_host_cg_flush(int h);
extern void xef_host_cg_mark_dirty(int h);
extern void xef_host_cg_save(int h);
extern void xef_host_cg_restore(int h);
extern void xef_host_cg_concat(int h, double a, double b, double c, double d, double tx, double ty);
extern void xef_host_cg_set_matrix(int h, double a, double b, double c, double d, double tx, double ty);
extern void xef_host_cg_get_matrix(int h, double *out);
extern void xef_host_cg_new_path(int h);
extern void xef_host_cg_move(int h, double x, double y);
extern void xef_host_cg_line(int h, double x, double y);
extern void xef_host_cg_curve(int h, double x1, double y1, double x2, double y2, double x3, double y3);
extern void xef_host_cg_close(int h);
extern void xef_host_cg_rect(int h, double x, double y, double w, double hh);
extern void xef_host_cg_path_extents(int h, double *out);
extern int  xef_host_cg_in_fill(int h, double x, double y);
extern void xef_host_cg_source_rgba(int h, double r, double g, double b, double a);
extern void xef_host_cg_fill(int h, int evenodd, int preserve);
extern void xef_host_cg_stroke(int h, int preserve);
extern void xef_host_cg_clip(int h, int evenodd);
extern void xef_host_cg_reset_clip(int h);
extern void xef_host_cg_clip_extents(int h, double *out);
extern void xef_host_cg_line_style(int h, double width, int cap, int join, double miter);
extern void xef_host_cg_dash(int h, const double *d, int n, double phase);
extern void xef_host_cg_operator(int h, int op);
extern void xef_host_cg_antialias(int h, int on);
extern void xef_host_cg_image(int h, const void *px, int w, int hh, int stride, int layout, double alpha, int interpolate);
extern void xef_host_cg_convert(void *argb, int argb_stride, void *px, int stride, int w, int h, int layout, int to_native);
extern void xef_host_cg_gradient(int h, int radial, double x0, double y0, double r0, double x1, double y1, double r1,
                                 const double *stops, int n, int extend);

/* ---- geometry ---------------------------------------------------------------------------------------------------- */
/* the SDK maps these to inline __CG* versions; the exported functions keep the public names */
#undef CGPointEqualToPoint
#undef CGSizeEqualToSize
#undef CGAffineTransformMake
#undef CGPointApplyAffineTransform
#undef CGSizeApplyAffineTransform
const CGPoint CGPointZero = {0, 0};
const CGSize CGSizeZero = {0, 0};
const CGRect CGRectZero = {{0, 0}, {0, 0}};
const CGRect CGRectNull = {{INFINITY, INFINITY}, {0, 0}};
const CGRect CGRectInfinite = {{-8.98846567431158e307, -8.98846567431158e307}, {1.7976931348623157e308, 1.7976931348623157e308}};
const CGAffineTransform CGAffineTransformIdentity = {1, 0, 0, 1, 0, 0};

static CGRect std_rect(CGRect r) {
  if (r.size.width < 0) { r.origin.x += r.size.width; r.size.width = -r.size.width; }
  if (r.size.height < 0) { r.origin.y += r.size.height; r.size.height = -r.size.height; }
  return r; }
CGRect CGRectStandardize(CGRect r) { return CGRectIsNull(r) ? r : std_rect(r); }
CGFloat CGRectGetMinX(CGRect r) { return std_rect(r).origin.x; }
CGFloat CGRectGetMinY(CGRect r) { return std_rect(r).origin.y; }
CGFloat CGRectGetMaxX(CGRect r) { r = std_rect(r); return r.origin.x + r.size.width; }
CGFloat CGRectGetMaxY(CGRect r) { r = std_rect(r); return r.origin.y + r.size.height; }
CGFloat CGRectGetMidX(CGRect r) { r = std_rect(r); return r.origin.x + r.size.width / 2; }
CGFloat CGRectGetMidY(CGRect r) { r = std_rect(r); return r.origin.y + r.size.height / 2; }
CGFloat CGRectGetWidth(CGRect r) { return fabs(r.size.width); }
CGFloat CGRectGetHeight(CGRect r) { return fabs(r.size.height); }
bool CGRectIsNull(CGRect r) { return isinf(r.origin.x) || isinf(r.origin.y); }
bool CGRectIsEmpty(CGRect r) { return CGRectIsNull(r) || r.size.width == 0 || r.size.height == 0; }
bool CGRectIsInfinite(CGRect r) { return r.size.width >= 1e300 && r.size.height >= 1e300; }
bool CGPointEqualToPoint(CGPoint a, CGPoint b) { return a.x == b.x && a.y == b.y; }
bool CGSizeEqualToSize(CGSize a, CGSize b) { return a.width == b.width && a.height == b.height; }
bool CGRectEqualToRect(CGRect a, CGRect b) {
  if (CGRectIsNull(a) || CGRectIsNull(b)) return CGRectIsNull(a) && CGRectIsNull(b);
  a = std_rect(a); b = std_rect(b);
  return CGPointEqualToPoint(a.origin, b.origin) && CGSizeEqualToSize(a.size, b.size); }
bool CGRectContainsPoint(CGRect r, CGPoint p) {
  if (CGRectIsNull(r)) return false; r = std_rect(r);
  return p.x >= r.origin.x && p.x < r.origin.x + r.size.width && p.y >= r.origin.y && p.y < r.origin.y + r.size.height; }
bool CGRectContainsRect(CGRect a, CGRect b) {
  if (CGRectIsNull(a) || CGRectIsNull(b)) return false; a = std_rect(a); b = std_rect(b);
  return b.origin.x >= a.origin.x && b.origin.y >= a.origin.y && b.origin.x + b.size.width <= a.origin.x + a.size.width &&
         b.origin.y + b.size.height <= a.origin.y + a.size.height; }
CGRect CGRectIntersection(CGRect a, CGRect b) {
  if (CGRectIsNull(a) || CGRectIsNull(b)) return CGRectNull;
  a = std_rect(a); b = std_rect(b);
  CGFloat x0 = fmax(a.origin.x, b.origin.x), y0 = fmax(a.origin.y, b.origin.y);
  CGFloat x1 = fmin(a.origin.x + a.size.width, b.origin.x + b.size.width), y1 = fmin(a.origin.y + a.size.height, b.origin.y + b.size.height);
  if (x1 < x0 || y1 < y0) return CGRectNull;
  return CGRectMake(x0, y0, x1 - x0, y1 - y0); }
CGRect CGRectUnion(CGRect a, CGRect b) {
  if (CGRectIsNull(a)) return CGRectStandardize(b); if (CGRectIsNull(b)) return std_rect(a);
  a = std_rect(a); b = std_rect(b);
  CGFloat x0 = fmin(a.origin.x, b.origin.x), y0 = fmin(a.origin.y, b.origin.y);
  CGFloat x1 = fmax(a.origin.x + a.size.width, b.origin.x + b.size.width), y1 = fmax(a.origin.y + a.size.height, b.origin.y + b.size.height);
  return CGRectMake(x0, y0, x1 - x0, y1 - y0); }
CGRect CGRectInset(CGRect r, CGFloat dx, CGFloat dy) {
  if (CGRectIsNull(r)) return r; r = std_rect(r);
  r.origin.x += dx; r.origin.y += dy; r.size.width -= 2 * dx; r.size.height -= 2 * dy;
  return (r.size.width < 0 || r.size.height < 0) ? CGRectNull : r; }
CGRect CGRectOffset(CGRect r, CGFloat dx, CGFloat dy) { if (CGRectIsNull(r)) return r; r = std_rect(r); r.origin.x += dx; r.origin.y += dy; return r; }
CGRect CGRectIntegral(CGRect r) {
  if (CGRectIsNull(r) || CGRectIsEmpty(r)) return CGRectIsNull(r) ? r : std_rect(r);
  r = std_rect(r);
  CGFloat x0 = floor(r.origin.x), y0 = floor(r.origin.y), x1 = ceil(r.origin.x + r.size.width), y1 = ceil(r.origin.y + r.size.height);
  return CGRectMake(x0, y0, x1 - x0, y1 - y0); }
void CGRectDivide(CGRect r, CGRect *slice, CGRect *rem, CGFloat amount, CGRectEdge edge) {
  r = std_rect(r); CGRect s = r, m = r;
  switch (edge) {
  case CGRectMinXEdge: amount = fmin(amount, r.size.width); s.size.width = amount; m.origin.x += amount; m.size.width -= amount; break;
  case CGRectMaxXEdge: amount = fmin(amount, r.size.width); s.origin.x += r.size.width - amount; s.size.width = amount; m.size.width -= amount; break;
  case CGRectMinYEdge: amount = fmin(amount, r.size.height); s.size.height = amount; m.origin.y += amount; m.size.height -= amount; break;
  case CGRectMaxYEdge: amount = fmin(amount, r.size.height); s.origin.y += r.size.height - amount; s.size.height = amount; m.size.height -= amount; break;
  }
  if (slice) *slice = s; if (rem) *rem = m; }

CGAffineTransform CGAffineTransformMake(CGFloat a, CGFloat b, CGFloat c, CGFloat d, CGFloat tx, CGFloat ty) {
  CGAffineTransform t = {a, b, c, d, tx, ty}; return t; }
CGAffineTransform CGAffineTransformMakeTranslation(CGFloat tx, CGFloat ty) { return CGAffineTransformMake(1, 0, 0, 1, tx, ty); }
CGAffineTransform CGAffineTransformMakeScale(CGFloat sx, CGFloat sy) { return CGAffineTransformMake(sx, 0, 0, sy, 0, 0); }
CGAffineTransform CGAffineTransformMakeRotation(CGFloat a) { CGFloat c = cos(a), s = sin(a); return CGAffineTransformMake(c, s, -s, c, 0, 0); }
/* t1 then t2 */
CGAffineTransform CGAffineTransformConcat(CGAffineTransform t1, CGAffineTransform t2) {
  return CGAffineTransformMake(t1.a * t2.a + t1.b * t2.c, t1.a * t2.b + t1.b * t2.d, t1.c * t2.a + t1.d * t2.c, t1.c * t2.b + t1.d * t2.d,
                               t1.tx * t2.a + t1.ty * t2.c + t2.tx, t1.tx * t2.b + t1.ty * t2.d + t2.ty); }
CGAffineTransform CGAffineTransformTranslate(CGAffineTransform t, CGFloat tx, CGFloat ty) { return CGAffineTransformConcat(CGAffineTransformMakeTranslation(tx, ty), t); }
CGAffineTransform CGAffineTransformScale(CGAffineTransform t, CGFloat sx, CGFloat sy) { return CGAffineTransformConcat(CGAffineTransformMakeScale(sx, sy), t); }
CGAffineTransform CGAffineTransformRotate(CGAffineTransform t, CGFloat a) { return CGAffineTransformConcat(CGAffineTransformMakeRotation(a), t); }
CGAffineTransform CGAffineTransformInvert(CGAffineTransform t) {
  CGFloat det = t.a * t.d - t.b * t.c;
  if (det == 0) return t;
  return CGAffineTransformMake(t.d / det, -t.b / det, -t.c / det, t.a / det, (t.c * t.ty - t.d * t.tx) / det, (t.b * t.tx - t.a * t.ty) / det); }
bool CGAffineTransformIsIdentity(CGAffineTransform t) { return t.a == 1 && t.b == 0 && t.c == 0 && t.d == 1 && t.tx == 0 && t.ty == 0; }
bool CGAffineTransformEqualToTransform(CGAffineTransform x, CGAffineTransform y) {
  return x.a == y.a && x.b == y.b && x.c == y.c && x.d == y.d && x.tx == y.tx && x.ty == y.ty; }
CGPoint CGPointApplyAffineTransform(CGPoint p, CGAffineTransform t) { return CGPointMake(t.a * p.x + t.c * p.y + t.tx, t.b * p.x + t.d * p.y + t.ty); }
CGSize CGSizeApplyAffineTransform(CGSize s, CGAffineTransform t) { return CGSizeMake(t.a * s.width + t.c * s.height, t.b * s.width + t.d * s.height); }
CGRect CGRectApplyAffineTransform(CGRect r, CGAffineTransform t) {
  if (CGRectIsNull(r)) return r; r = std_rect(r);
  CGPoint p[4] = { {r.origin.x, r.origin.y}, {r.origin.x + r.size.width, r.origin.y}, {r.origin.x, r.origin.y + r.size.height},
                   {r.origin.x + r.size.width, r.origin.y + r.size.height} };
  CGFloat x0 = INFINITY, y0 = INFINITY, x1 = -INFINITY, y1 = -INFINITY;
  for (int i = 0; i < 4; i++) { CGPoint q = CGPointApplyAffineTransform(p[i], t); x0 = fmin(x0, q.x); y0 = fmin(y0, q.y); x1 = fmax(x1, q.x); y1 = fmax(y1, q.y); }
  return CGRectMake(x0, y0, x1 - x0, y1 - y0); }

CFDictionaryRef CGRectCreateDictionaryRepresentation(CGRect r) {
  const void *k[4] = { CFSTR("X"), CFSTR("Y"), CFSTR("Width"), CFSTR("Height") };
  double v[4] = { r.origin.x, r.origin.y, r.size.width, r.size.height };
  const void *n[4];
  for (int i = 0; i < 4; i++) n[i] = CFNumberCreate(NULL, kCFNumberDoubleType, &v[i]);
  CFDictionaryRef d = CFDictionaryCreate(NULL, k, n, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  for (int i = 0; i < 4; i++) CFRelease(n[i]);
  return d; }
bool CGRectMakeWithDictionaryRepresentation(CFDictionaryRef d, CGRect *r) {
  if (!d || !r) return false;
  const CFStringRef k[4] = { CFSTR("X"), CFSTR("Y"), CFSTR("Width"), CFSTR("Height") };
  double v[4];
  for (int i = 0; i < 4; i++) { CFNumberRef n = CFDictionaryGetValue(d, k[i]); if (!n || !CFNumberGetValue(n, kCFNumberDoubleType, &v[i])) return false; }
  *r = CGRectMake(v[0], v[1], v[2], v[3]); return true; }

/* ---- CF classes ----------------------------------------------------------------------------------------------------- */
struct CGColorSpace { XBase b; int model; size_t n; CFStringRef name; };
struct CGColor { XBase b; CGColorSpaceRef cs; size_t n; CGFloat c[6]; };   /* n components incl. alpha */
typedef struct { int type; CGPoint p[3]; } PEl;
struct CGPath { XBase b; size_t n, cap; PEl *e; CGPoint cur, start; };
struct CGDataProvider { XBase b; const unsigned char *bytes; size_t size; CFDataRef cf; void *info; CGDataProviderReleaseDataCallback release; };
struct CGImage { XBase b; size_t w, h, bpc, bpp, bpr; CGBitmapInfo info; CGColorSpaceRef cs; CGDataProviderRef prov; bool mask, interp; };
struct CGGradient { XBase b; size_t n; double *stops; /* n x (offset r g b a) */ };

typedef struct {
  double fill[4], stroke[4], alpha; double lw, miter; int cap, join; int blend; bool aa;
  CGColorSpaceRef fillcs, strokecs; CGAffineTransform textm; CGFloat fontsize, charspace; CGTextDrawingMode textmode; CGFontRef font;
  CGInterpolationQuality interp;
} GState;
#define GS_MAX 64
struct CGContext {
  XBase b; int h; unsigned char *data; size_t w, hgt, bpr; int layout; bool native, owns;
  unsigned char *argb; size_t argb_stride; CGColorSpaceRef cs; CGBitmapInfo info; size_t bpc, bpp;
  GState gs[GS_MAX]; int depth; bool empty; CGPoint cur, start; CGPoint textpos;
};

static CFTypeID cs_id, color_id, path_id, provider_id, image_id, ctx_id, gradient_id;
static void cs_fin(CFTypeRef o) { struct CGColorSpace *c = (void *)o; if (c->name) CFRelease(c->name); }
static void color_fin(CFTypeRef o) { struct CGColor *c = (void *)o; if (c->cs) CFRelease(c->cs); }
static void path_fin(CFTypeRef o) { free(((struct CGPath *)o)->e); }
static void provider_fin(CFTypeRef o) {
  struct CGDataProvider *p = (void *)o;
  if (p->cf) CFRelease(p->cf);
  if (p->release) p->release(p->info, p->bytes, p->size); }
static void image_fin(CFTypeRef o) { struct CGImage *i = (void *)o; if (i->cs) CFRelease(i->cs); if (i->prov) CFRelease(i->prov); }
static void ctx_sync(struct CGContext *c);
static void ctx_fin(CFTypeRef o) {
  struct CGContext *c = (void *)o;
  ctx_sync(c);
  if (c->h) xef_host_cg_destroy(c->h);
  for (int i = 0; i <= c->depth; i++) { if (c->gs[i].fillcs) CFRelease(c->gs[i].fillcs); if (c->gs[i].strokecs) CFRelease(c->gs[i].strokecs); }
  if (c->cs) CFRelease(c->cs);
  free(c->argb);
  if (c->owns) free(c->data); }
static void gradient_fin(CFTypeRef o) { free(((struct CGGradient *)o)->stops); }

static void draw_classes_once(void) {
  static XClass cs = { 0, "CGColorSpace", 0, 0, (void *)cs_fin }, col = { 0, "CGColor", 0, 0, (void *)color_fin },
                pa = { 0, "CGPath", 0, 0, (void *)path_fin }, pr = { 0, "CGDataProvider", 0, 0, (void *)provider_fin },
                im = { 0, "CGImage", 0, 0, (void *)image_fin }, cx = { 0, "CGContext", 0, 0, (void *)ctx_fin },
                gr = { 0, "CGGradient", 0, 0, (void *)gradient_fin };
  cs_id = _CFRuntimeRegisterClass(&cs); color_id = _CFRuntimeRegisterClass(&col); path_id = _CFRuntimeRegisterClass(&pa);
  provider_id = _CFRuntimeRegisterClass(&pr); image_id = _CFRuntimeRegisterClass(&im); ctx_id = _CFRuntimeRegisterClass(&cx);
  gradient_id = _CFRuntimeRegisterClass(&gr); }
static void *cg_new(CFTypeID *id, size_t size) {
  static pthread_once_t once = PTHREAD_ONCE_INIT;
  pthread_once(&once, draw_classes_once);
  return (void *)_CFRuntimeCreateInstance(kCFAllocatorDefault, *id, size - sizeof(XBase), NULL); }

/* ---- colour spaces ---------------------------------------------------------------------------------------------------- */
const CFStringRef kCGColorSpaceGenericGray = CFSTR("kCGColorSpaceGenericGray");
const CFStringRef kCGColorSpaceGenericRGB = CFSTR("kCGColorSpaceGenericRGB");
const CFStringRef kCGColorSpaceGenericCMYK = CFSTR("kCGColorSpaceGenericCMYK");
const CFStringRef kCGColorSpaceGenericRGBLinear = CFSTR("kCGColorSpaceGenericRGBLinear");
const CFStringRef kCGColorSpaceGenericGrayGamma2_2 = CFSTR("kCGColorSpaceGenericGrayGamma2_2");
const CFStringRef kCGColorSpaceSRGB = CFSTR("kCGColorSpaceSRGB");
const CFStringRef kCGColorSpaceExtendedSRGB = CFSTR("kCGColorSpaceExtendedSRGB");
const CFStringRef kCGColorSpaceLinearSRGB = CFSTR("kCGColorSpaceLinearSRGB");
const CFStringRef kCGColorSpaceExtendedLinearSRGB = CFSTR("kCGColorSpaceExtendedLinearSRGB");
const CFStringRef kCGColorSpaceDisplayP3 = CFSTR("kCGColorSpaceDisplayP3");
const CFStringRef kCGColorSpaceExtendedDisplayP3 = CFSTR("kCGColorSpaceExtendedDisplayP3");
const CFStringRef kCGColorSpaceITUR_709 = CFSTR("kCGColorSpaceITUR_709");
const CFStringRef kCGColorSpaceITUR_2020 = CFSTR("kCGColorSpaceITUR_2020");
const CFStringRef kCGColorSpaceITUR_2100_PQ = CFSTR("kCGColorSpaceITUR_2100_PQ");
const CFStringRef kCGColorSpaceITUR_2100_HLG = CFSTR("kCGColorSpaceITUR_2100_HLG");
const CFStringRef kCGColorSpaceLinearGray = CFSTR("kCGColorSpaceLinearGray");
const CFStringRef kCGColorSpaceExtendedGray = CFSTR("kCGColorSpaceExtendedGray");
const CFStringRef kCGColorSpaceExtendedLinearGray = CFSTR("kCGColorSpaceExtendedLinearGray");
const CFStringRef kCGColorSpaceAdobeRGB1998 = CFSTR("kCGColorSpaceAdobeRGB1998");

static CGColorSpaceRef cs_make(int model, size_t n, CFStringRef name) {
  struct CGColorSpace *c = cg_new(&cs_id, sizeof *c);
  if (!c) return NULL;
  c->model = model; c->n = n; c->name = name ? CFStringCreateCopy(NULL, name) : NULL;
  return c; }
CFTypeID CGColorSpaceGetTypeID(void) { static pthread_once_t o = PTHREAD_ONCE_INIT; pthread_once(&o, draw_classes_once); return cs_id; }
CGColorSpaceRef CGColorSpaceCreateDeviceRGB(void) { return cs_make(kCGColorSpaceModelRGB, 3, kCGColorSpaceSRGB); }
CGColorSpaceRef CGColorSpaceCreateDeviceGray(void) { return cs_make(kCGColorSpaceModelMonochrome, 1, kCGColorSpaceGenericGrayGamma2_2); }
CGColorSpaceRef CGColorSpaceCreateDeviceCMYK(void) { return cs_make(kCGColorSpaceModelCMYK, 4, kCGColorSpaceGenericCMYK); }
CGColorSpaceRef CGColorSpaceCreateWithName(CFStringRef name) {
  if (!name) return NULL;
  if (CFStringFind(name, CFSTR("Gray"), 0).location != kCFNotFound) return cs_make(kCGColorSpaceModelMonochrome, 1, name);
  if (CFStringFind(name, CFSTR("CMYK"), 0).location != kCFNotFound) return cs_make(kCGColorSpaceModelCMYK, 4, name);
  return cs_make(kCGColorSpaceModelRGB, 3, name); }
CGColorSpaceRef CGColorSpaceCreatePattern(CGColorSpaceRef base) { return cs_make(kCGColorSpaceModelPattern, base ? CGColorSpaceGetNumberOfComponents(base) : 0, NULL); }
CGColorSpaceRef CGColorSpaceCreateWithICCData(CFTypeRef data) { return CGColorSpaceCreateDeviceRGB(); }
CGColorSpaceRef CGColorSpaceCreateCalibratedRGB(const CGFloat wp[3], const CGFloat bp[3], const CGFloat g[3], const CGFloat m[9]) { return CGColorSpaceCreateDeviceRGB(); }
CGColorSpaceRef CGColorSpaceCreateCalibratedGray(const CGFloat wp[3], const CGFloat bp[3], CGFloat g) { return CGColorSpaceCreateDeviceGray(); }
CGColorSpaceRef CGColorSpaceRetain(CGColorSpaceRef s) { if (s) CFRetain(s); return s; }
void CGColorSpaceRelease(CGColorSpaceRef s) { if (s) CFRelease(s); }
/* older builds handed out CFStrings as colour spaces: treat anything that is not ours as sRGB */
static const struct CGColorSpace *cs_of(CGColorSpaceRef s) {
  if (!s) return NULL;
  CGColorSpaceGetTypeID();
  return CFGetTypeID(s) == cs_id ? (const struct CGColorSpace *)s : NULL; }
size_t CGColorSpaceGetNumberOfComponents(CGColorSpaceRef s) { const struct CGColorSpace *c = cs_of(s); return c ? c->n : 3; }
CGColorSpaceModel CGColorSpaceGetModel(CGColorSpaceRef s) { const struct CGColorSpace *c = cs_of(s); return c ? c->model : kCGColorSpaceModelRGB; }
CFStringRef CGColorSpaceGetName(CGColorSpaceRef s) { const struct CGColorSpace *c = cs_of(s); return c ? c->name : NULL; }
CFStringRef CGColorSpaceCopyName(CGColorSpaceRef s) { CFStringRef n = CGColorSpaceGetName(s); return n ? CFStringCreateCopy(NULL, n) : NULL; }
CFDataRef CGColorSpaceCopyICCData(CGColorSpaceRef s) { return NULL; }
bool CGColorSpaceSupportsOutput(CGColorSpaceRef s) { return true; }
bool CGColorSpaceIsWideGamutRGB(CGColorSpaceRef s) { return false; }
bool CGColorSpaceUsesExtendedRange(CGColorSpaceRef s) { return false; }
CGColorSpaceRef CGColorSpaceGetBaseColorSpace(CGColorSpaceRef s) { return NULL; }

/* ---- colours ------------------------------------------------------------------------------------------------------------ */
const CFStringRef kCGColorWhite = CFSTR("kCGColorWhite");
const CFStringRef kCGColorClear = CFSTR("kCGColorClear");
CFTypeID CGColorGetTypeID(void) { CGColorSpaceGetTypeID(); return color_id; }
CGColorRef CGColorCreate(CGColorSpaceRef space, const CGFloat *comps) {
  struct CGColor *c = cg_new(&color_id, sizeof *c);
  if (!c) return NULL;
  c->cs = space ? CGColorSpaceRetain(space) : CGColorSpaceCreateDeviceRGB();
  c->n = CGColorSpaceGetNumberOfComponents(c->cs) + 1;
  if (c->n > 6) c->n = 6;
  for (size_t i = 0; i < c->n; i++) c->c[i] = comps ? comps[i] : (i + 1 == c->n ? 1 : 0);
  return c; }
CGColorRef CGColorCreateGenericRGB(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
  CGColorSpaceRef s = CGColorSpaceCreateDeviceRGB(); CGFloat v[4] = {r, g, b, a}; CGColorRef c = CGColorCreate(s, v); CGColorSpaceRelease(s); return c; }
CGColorRef CGColorCreateSRGB(CGFloat r, CGFloat g, CGFloat b, CGFloat a) { return CGColorCreateGenericRGB(r, g, b, a); }
CGColorRef CGColorCreateGenericGray(CGFloat g, CGFloat a) {
  CGColorSpaceRef s = CGColorSpaceCreateDeviceGray(); CGFloat v[2] = {g, a}; CGColorRef c = CGColorCreate(s, v); CGColorSpaceRelease(s); return c; }
CGColorRef CGColorCreateGenericGrayGamma2_2(CGFloat g, CGFloat a) { return CGColorCreateGenericGray(g, a); }
CGColorRef CGColorCreateGenericCMYK(CGFloat c, CGFloat m, CGFloat y, CGFloat k, CGFloat a) {
  return CGColorCreateGenericRGB((1 - c) * (1 - k), (1 - m) * (1 - k), (1 - y) * (1 - k), a); }
CGColorRef CGColorCreateCopy(CGColorRef c) { return c ? CGColorCreate(c->cs, c->c) : NULL; }
CGColorRef CGColorCreateCopyWithAlpha(CGColorRef c, CGFloat a) {
  if (!c) return NULL; CGColorRef r = CGColorCreate(c->cs, c->c); ((struct CGColor *)r)->c[r->n - 1] = a; return r; }
CGColorRef CGColorCreateCopyByMatchingToColorSpace(CGColorSpaceRef s, CGColorRenderingIntent i, CGColorRef c, CFDictionaryRef o);
CGColorRef CGColorRetain(CGColorRef c) { if (c) CFRetain(c); return c; }
void CGColorRelease(CGColorRef c) { if (c) CFRelease(c); }
static bool is_color(CGColorRef c) { return c && CFGetTypeID(c) == CGColorGetTypeID(); }
size_t CGColorGetNumberOfComponents(CGColorRef c) { return is_color(c) ? c->n : 4; }
const CGFloat *CGColorGetComponents(CGColorRef c) { static const CGFloat black[4] = {0, 0, 0, 1}; return is_color(c) ? c->c : black; }
CGFloat CGColorGetAlpha(CGColorRef c) { return is_color(c) ? c->c[c->n - 1] : 1; }
CGColorSpaceRef CGColorGetColorSpace(CGColorRef c) { return is_color(c) ? c->cs : NULL; }
CGPatternRef CGColorGetPattern(CGColorRef c) { return NULL; }
bool CGColorEqualToColor(CGColorRef a, CGColorRef b) {
  if (a == b) return true; if (!is_color(a) || !is_color(b) || a->n != b->n) return false;
  for (size_t i = 0; i < a->n; i++) if (a->c[i] != b->c[i]) return false; return true; }
/* any colour -> RGBA */
static void color_rgba(CGColorRef c, double out[4]) {
  out[0] = out[1] = out[2] = 0; out[3] = 1;
  if (!is_color(c)) return;
  CGColorSpaceModel m = CGColorSpaceGetModel(c->cs);
  if (m == kCGColorSpaceModelMonochrome) { out[0] = out[1] = out[2] = c->c[0]; out[3] = c->c[1]; }
  else if (m == kCGColorSpaceModelCMYK) { double k = c->c[3]; out[0] = (1 - c->c[0]) * (1 - k); out[1] = (1 - c->c[1]) * (1 - k); out[2] = (1 - c->c[2]) * (1 - k); out[3] = c->c[4]; }
  else { out[0] = c->c[0]; out[1] = c->c[1]; out[2] = c->c[2]; out[3] = c->c[c->n - 1]; } }
CGColorRef CGColorCreateCopyByMatchingToColorSpace(CGColorSpaceRef s, CGColorRenderingIntent i, CGColorRef c, CFDictionaryRef o) {
  double v[4]; color_rgba(c, v);
  if (CGColorSpaceGetModel(s) == kCGColorSpaceModelMonochrome) { CGFloat g[2] = {(v[0] + v[1] + v[2]) / 3, v[3]}; return CGColorCreate(s, g); }
  CGFloat r[4] = {v[0], v[1], v[2], v[3]}; return CGColorCreate(s, r); }
CGColorRef CGColorGetConstantColor(CFStringRef name) {
  static CGColorRef white, black, clear;
  if (name && CFEqual(name, kCGColorWhite)) { if (!white) white = CGColorCreateGenericGray(1, 1); return white; }
  if (name && CFEqual(name, kCGColorClear)) { if (!clear) clear = CGColorCreateGenericGray(0, 0); return clear; }
  if (!black) black = CGColorCreateGenericGray(0, 1);
  return black; }

/* ---- paths -------------------------------------------------------------------------------------------------------------- */
CFTypeID CGPathGetTypeID(void) { CGColorSpaceGetTypeID(); return path_id; }
CGMutablePathRef CGPathCreateMutable(void) { struct CGPath *p = cg_new(&path_id, sizeof *p); return p; }
static void path_add(struct CGPath *p, int type, const CGPoint *pts, int n) {
  if (!p) return;
  if (p->n == p->cap) { p->cap = p->cap ? p->cap * 2 : 16; p->e = realloc(p->e, p->cap * sizeof *p->e); }
  PEl *e = &p->e[p->n++]; e->type = type;
  for (int i = 0; i < n; i++) e->p[i] = pts[i];
  if (type == kCGPathElementMoveToPoint) p->start = p->cur = pts[0];
  else if (type == kCGPathElementCloseSubpath) p->cur = p->start;
  else p->cur = pts[n - 1]; }
static CGPoint xf(const CGAffineTransform *m, CGFloat x, CGFloat y) { CGPoint p = CGPointMake(x, y); return m ? CGPointApplyAffineTransform(p, *m) : p; }
CGMutablePathRef CGPathCreateMutableCopy(CGPathRef src) {
  struct CGPath *p = CGPathCreateMutable();
  if (src && p) { p->cap = p->n = src->n; p->e = malloc((p->cap ? p->cap : 1) * sizeof *p->e); memcpy(p->e, src->e, src->n * sizeof *p->e); p->cur = src->cur; p->start = src->start; }
  return p; }
CGMutablePathRef CGPathCreateMutableCopyByTransformingPath(CGPathRef src, const CGAffineTransform *m) {
  struct CGPath *p = CGPathCreateMutableCopy(src);
  if (p && m) {
    for (size_t i = 0; i < p->n; i++) for (int k = 0; k < 3; k++) p->e[i].p[k] = CGPointApplyAffineTransform(p->e[i].p[k], *m);
    p->cur = CGPointApplyAffineTransform(p->cur, *m); p->start = CGPointApplyAffineTransform(p->start, *m); }
  return p; }
CGPathRef CGPathCreateCopy(CGPathRef src) { return CGPathCreateMutableCopy(src); }
CGPathRef CGPathCreateCopyByTransformingPath(CGPathRef src, const CGAffineTransform *m) { return CGPathCreateMutableCopyByTransformingPath(src, m); }
CGPathRef CGPathRetain(CGPathRef p) { if (p) CFRetain(p); return p; }
void CGPathRelease(CGPathRef p) { if (p) CFRelease(p); }
void CGPathMoveToPoint(CGMutablePathRef p, const CGAffineTransform *m, CGFloat x, CGFloat y) { CGPoint q = xf(m, x, y); path_add(p, kCGPathElementMoveToPoint, &q, 1); }
static void path_ensure_start(CGMutablePathRef p, CGPoint q) { if (p && !p->n) path_add(p, kCGPathElementMoveToPoint, &q, 1); }
void CGPathAddLineToPoint(CGMutablePathRef p, const CGAffineTransform *m, CGFloat x, CGFloat y) {
  CGPoint q = xf(m, x, y); path_ensure_start(p, q); path_add(p, kCGPathElementAddLineToPoint, &q, 1); }
void CGPathAddQuadCurveToPoint(CGMutablePathRef p, const CGAffineTransform *m, CGFloat cx, CGFloat cy, CGFloat x, CGFloat y) {
  CGPoint q[2] = { xf(m, cx, cy), xf(m, x, y) }; path_ensure_start(p, q[0]); path_add(p, kCGPathElementAddQuadCurveToPoint, q, 2); }
void CGPathAddCurveToPoint(CGMutablePathRef p, const CGAffineTransform *m, CGFloat c1x, CGFloat c1y, CGFloat c2x, CGFloat c2y, CGFloat x, CGFloat y) {
  CGPoint q[3] = { xf(m, c1x, c1y), xf(m, c2x, c2y), xf(m, x, y) }; path_ensure_start(p, q[0]); path_add(p, kCGPathElementAddCurveToPoint, q, 3); }
void CGPathCloseSubpath(CGMutablePathRef p) { if (p && p->n) path_add(p, kCGPathElementCloseSubpath, NULL, 0); }
void CGPathAddRect(CGMutablePathRef p, const CGAffineTransform *m, CGRect r) {
  CGPathMoveToPoint(p, m, r.origin.x, r.origin.y);
  CGPathAddLineToPoint(p, m, r.origin.x + r.size.width, r.origin.y);
  CGPathAddLineToPoint(p, m, r.origin.x + r.size.width, r.origin.y + r.size.height);
  CGPathAddLineToPoint(p, m, r.origin.x, r.origin.y + r.size.height);
  CGPathCloseSubpath(p); }
void CGPathAddRects(CGMutablePathRef p, const CGAffineTransform *m, const CGRect *r, size_t n) { for (size_t i = 0; i < n; i++) CGPathAddRect(p, m, r[i]); }
void CGPathAddLines(CGMutablePathRef p, const CGAffineTransform *m, const CGPoint *pts, size_t n) {
  for (size_t i = 0; i < n; i++) { if (i == 0) CGPathMoveToPoint(p, m, pts[i].x, pts[i].y); else CGPathAddLineToPoint(p, m, pts[i].x, pts[i].y); } }
/* arc as cubic Béziers (at most 90° each), in the path's own space before m */
static void arc_beziers(CGMutablePathRef p, const CGAffineTransform *m, CGFloat cx, CGFloat cy, CGFloat r, CGFloat a0, CGFloat a1, bool cw, bool join) {
  CGFloat sweep;
  if (cw) { while (a1 > a0) a1 -= 2 * M_PI; sweep = a1 - a0; if (sweep < -2 * M_PI) sweep = -2 * M_PI; }
  else { while (a1 < a0) a1 += 2 * M_PI; sweep = a1 - a0; if (sweep > 2 * M_PI) sweep = 2 * M_PI; }
  CGFloat sx = cx + r * cos(a0), sy = cy + r * sin(a0);
  if (join && p->n) CGPathAddLineToPoint(p, m, sx, sy); else CGPathMoveToPoint(p, m, sx, sy);
  int segs = (int)ceil(fabs(sweep) / (M_PI / 2) - 1e-9); if (segs < 1) segs = 1;
  CGFloat step = sweep / segs, a = a0;
  for (int i = 0; i < segs; i++) {
    CGFloat b = a + step, k = 4.0 / 3.0 * tan((b - a) / 4);
    CGFloat x0 = cos(a), y0 = sin(a), x3 = cos(b), y3 = sin(b);
    CGPathAddCurveToPoint(p, m, cx + r * (x0 - k * y0), cy + r * (y0 + k * x0), cx + r * (x3 + k * y3), cy + r * (y3 - k * x3), cx + r * x3, cy + r * y3);
    a = b; } }
void CGPathAddArc(CGMutablePathRef p, const CGAffineTransform *m, CGFloat x, CGFloat y, CGFloat r, CGFloat a0, CGFloat a1, bool cw) {
  if (p) arc_beziers(p, m, x, y, r, a0, a1, cw, true); }
void CGPathAddRelativeArc(CGMutablePathRef p, const CGAffineTransform *m, CGFloat x, CGFloat y, CGFloat r, CGFloat a0, CGFloat delta) {
  if (p) arc_beziers(p, m, x, y, r, a0, a0 + delta, delta < 0, true); }
/* tangent arc from the current point (in path space: m is inverted to get it back) */
void CGPathAddArcToPoint(CGMutablePathRef p, const CGAffineTransform *m, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, CGFloat r) {
  if (!p) return;
  CGPoint c0 = p->cur;
  if (m) c0 = CGPointApplyAffineTransform(c0, CGAffineTransformInvert(*m));
  if (!p->n) { CGPathMoveToPoint(p, m, x1, y1); return; }
  double dx0 = c0.x - x1, dy0 = c0.y - y1, dx2 = x2 - x1, dy2 = y2 - y1;
  double l0 = hypot(dx0, dy0), l2 = hypot(dx2, dy2);
  if (l0 < 1e-9 || l2 < 1e-9 || r <= 0) { CGPathAddLineToPoint(p, m, x1, y1); return; }
  dx0 /= l0; dy0 /= l0; dx2 /= l2; dy2 /= l2;
  double cosang = dx0 * dx2 + dy0 * dy2, ang = acos(fmax(-1, fmin(1, cosang)));
  if (fabs(sin(ang)) < 1e-9) { CGPathAddLineToPoint(p, m, x1, y1); return; }
  double dist = r / tan(ang / 2);
  double tx0 = x1 + dx0 * dist, ty0 = y1 + dy0 * dist, tx2 = x1 + dx2 * dist, ty2 = y1 + dy2 * dist;
  double bx = dx0 + dx2, by = dy0 + dy2, bl = hypot(bx, by); bx /= bl; by /= bl;
  double cd = r / sin(ang / 2), ccx = x1 + bx * cd, ccy = y1 + by * cd;
  double s = atan2(ty0 - ccy, tx0 - ccx), e = atan2(ty2 - ccy, tx2 - ccx);
  bool cw = (dx0 * dy2 - dy0 * dx2) > 0;
  (void)tx2;
  arc_beziers(p, m, ccx, ccy, r, s, e, cw, true); }
void CGPathAddEllipseInRect(CGMutablePathRef p, const CGAffineTransform *m, CGRect r) {
  r = std_rect(r);
  CGFloat k = 0.5522847498, cx = r.origin.x + r.size.width / 2, cy = r.origin.y + r.size.height / 2, rx = r.size.width / 2, ry = r.size.height / 2;
  CGPathMoveToPoint(p, m, cx + rx, cy);
  CGPathAddCurveToPoint(p, m, cx + rx, cy + k * ry, cx + k * rx, cy + ry, cx, cy + ry);
  CGPathAddCurveToPoint(p, m, cx - k * rx, cy + ry, cx - rx, cy + k * ry, cx - rx, cy);
  CGPathAddCurveToPoint(p, m, cx - rx, cy - k * ry, cx - k * rx, cy - ry, cx, cy - ry);
  CGPathAddCurveToPoint(p, m, cx + k * rx, cy - ry, cx + rx, cy - k * ry, cx + rx, cy);
  CGPathCloseSubpath(p); }
void CGPathAddRoundedRect(CGMutablePathRef p, const CGAffineTransform *m, CGRect r, CGFloat rw, CGFloat rh) {
  r = std_rect(r);
  rw = fmin(rw, r.size.width / 2); rh = fmin(rh, r.size.height / 2);
  if (rw <= 0 || rh <= 0) { CGPathAddRect(p, m, r); return; }
  CGFloat k = 0.5522847498, x0 = r.origin.x, y0 = r.origin.y, x1 = x0 + r.size.width, y1 = y0 + r.size.height;
  CGPathMoveToPoint(p, m, x0 + rw, y0);
  CGPathAddLineToPoint(p, m, x1 - rw, y0);
  CGPathAddCurveToPoint(p, m, x1 - rw + k * rw, y0, x1, y0 + rh - k * rh, x1, y0 + rh);
  CGPathAddLineToPoint(p, m, x1, y1 - rh);
  CGPathAddCurveToPoint(p, m, x1, y1 - rh + k * rh, x1 - rw + k * rw, y1, x1 - rw, y1);
  CGPathAddLineToPoint(p, m, x0 + rw, y1);
  CGPathAddCurveToPoint(p, m, x0 + rw - k * rw, y1, x0, y1 - rh + k * rh, x0, y1 - rh);
  CGPathAddLineToPoint(p, m, x0, y0 + rh);
  CGPathAddCurveToPoint(p, m, x0, y0 + rh - k * rh, x0 + rw - k * rw, y0, x0 + rw, y0);
  CGPathCloseSubpath(p); }
void CGPathAddPath(CGMutablePathRef p, const CGAffineTransform *m, CGPathRef src) {
  if (!p || !src) return;
  for (size_t i = 0; i < src->n; i++) {
    const PEl *e = &src->e[i]; CGPoint q[3]; int n = e->type == kCGPathElementAddCurveToPoint ? 3 : e->type == kCGPathElementAddQuadCurveToPoint ? 2 : e->type == kCGPathElementCloseSubpath ? 0 : 1;
    for (int k = 0; k < n; k++) q[k] = m ? CGPointApplyAffineTransform(e->p[k], *m) : e->p[k];
    path_add(p, e->type, q, n); } }
CGPathRef CGPathCreateWithRect(CGRect r, const CGAffineTransform *m) { CGMutablePathRef p = CGPathCreateMutable(); CGPathAddRect(p, m, r); return p; }
CGPathRef CGPathCreateWithEllipseInRect(CGRect r, const CGAffineTransform *m) { CGMutablePathRef p = CGPathCreateMutable(); CGPathAddEllipseInRect(p, m, r); return p; }
CGPathRef CGPathCreateWithRoundedRect(CGRect r, CGFloat rw, CGFloat rh, const CGAffineTransform *m) { CGMutablePathRef p = CGPathCreateMutable(); CGPathAddRoundedRect(p, m, r, rw, rh); return p; }
bool CGPathIsEmpty(CGPathRef p) { return !p || !p->n; }
CGPoint CGPathGetCurrentPoint(CGPathRef p) { return p && p->n ? p->cur : CGPointZero; }
bool CGPathEqualToPath(CGPathRef a, CGPathRef b) {
  if (a == b) return true; if (!a || !b || a->n != b->n) return false;
  return !memcmp(a->e, b->e, a->n * sizeof *a->e); }
static CGRect path_bounds(CGPathRef p, bool control) {
  if (!p || !p->n) return CGRectNull;
  CGFloat x0 = INFINITY, y0 = INFINITY, x1 = -INFINITY, y1 = -INFINITY;
  for (size_t i = 0; i < p->n; i++) {
    const PEl *e = &p->e[i]; int n = e->type == kCGPathElementAddCurveToPoint ? 3 : e->type == kCGPathElementAddQuadCurveToPoint ? 2 : e->type == kCGPathElementCloseSubpath ? 0 : 1;
    for (int k = 0; k < n; k++) {
      if (!control && k + 1 < n) continue;   /* path bounding box: end points only (a slight under-estimate of curves) */
      x0 = fmin(x0, e->p[k].x); y0 = fmin(y0, e->p[k].y); x1 = fmax(x1, e->p[k].x); y1 = fmax(y1, e->p[k].y); } }
  return CGRectMake(x0, y0, x1 - x0, y1 - y0); }
CGRect CGPathGetBoundingBox(CGPathRef p) { return path_bounds(p, true); }
CGRect CGPathGetPathBoundingBox(CGPathRef p) { return path_bounds(p, false); }
bool CGPathIsRect(CGPathRef p, CGRect *r) {
  if (!p || p->n < 4 || p->n > 6 || p->e[0].type != kCGPathElementMoveToPoint) return false;
  for (size_t i = 1; i < p->n; i++) if (p->e[i].type != kCGPathElementAddLineToPoint && p->e[i].type != kCGPathElementCloseSubpath) return false;
  CGRect b = path_bounds(p, true);
  for (size_t i = 0; i < p->n; i++) {
    if (p->e[i].type == kCGPathElementCloseSubpath) continue;
    CGPoint q = p->e[i].p[0];
    if ((q.x != b.origin.x && q.x != b.origin.x + b.size.width) || (q.y != b.origin.y && q.y != b.origin.y + b.size.height)) return false; }
  if (r) *r = b; return true; }
void CGPathApply(CGPathRef p, void *info, CGPathApplierFunction fn) {
  if (!p || !fn) return;
  for (size_t i = 0; i < p->n; i++) { CGPathElement e = { (CGPathElementType)p->e[i].type, (CGPoint *)p->e[i].p }; fn(info, &e); } }
/* flattened winding / even-odd test */
bool CGPathContainsPoint(CGPathRef p, const CGAffineTransform *m, CGPoint pt, bool eo) {
  if (!p || !p->n) return false;
  if (m) pt = CGPointApplyAffineTransform(pt, CGAffineTransformInvert(*m));
  int wind = 0; CGPoint cur = CGPointZero, start = CGPointZero;
  #define EDGE(a, b) do { CGPoint A_ = (a), B_ = (b); \
    if (A_.y <= pt.y) { if (B_.y > pt.y && (B_.x - A_.x) * (pt.y - A_.y) - (pt.x - A_.x) * (B_.y - A_.y) > 0) wind++; } \
    else if (B_.y <= pt.y && (B_.x - A_.x) * (pt.y - A_.y) - (pt.x - A_.x) * (B_.y - A_.y) < 0) wind--; } while (0)
  for (size_t i = 0; i < p->n; i++) {
    const PEl *e = &p->e[i];
    switch (e->type) {
    case kCGPathElementMoveToPoint: if (cur.x != start.x || cur.y != start.y) EDGE(cur, start); cur = start = e->p[0]; break;
    case kCGPathElementAddLineToPoint: EDGE(cur, e->p[0]); cur = e->p[0]; break;
    case kCGPathElementAddQuadCurveToPoint: case kCGPathElementAddCurveToPoint: {
      CGPoint c1, c2, end = e->type == kCGPathElementAddCurveToPoint ? e->p[2] : e->p[1];
      if (e->type == kCGPathElementAddCurveToPoint) { c1 = e->p[0]; c2 = e->p[1]; }
      else { c1 = CGPointMake(cur.x + 2.0 / 3 * (e->p[0].x - cur.x), cur.y + 2.0 / 3 * (e->p[0].y - cur.y));
             c2 = CGPointMake(end.x + 2.0 / 3 * (e->p[0].x - end.x), end.y + 2.0 / 3 * (e->p[0].y - end.y)); }
      CGPoint prev = cur;
      for (int k = 1; k <= 16; k++) {
        double t = k / 16.0, u = 1 - t;
        CGPoint q = CGPointMake(u * u * u * cur.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * end.x,
                                u * u * u * cur.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * end.y);
        EDGE(prev, q); prev = q; }
      cur = end; break; }
    case kCGPathElementCloseSubpath: EDGE(cur, start); cur = start; break; } }
  if (cur.x != start.x || cur.y != start.y) EDGE(cur, start);
  #undef EDGE
  return eo ? (wind & 1) != 0 : wind != 0; }

/* ---- data providers ------------------------------------------------------------------------------------------------------- */
CFTypeID CGDataProviderGetTypeID(void) { CGColorSpaceGetTypeID(); return provider_id; }
CGDataProviderRef CGDataProviderCreateWithData(void *info, const void *data, size_t size, CGDataProviderReleaseDataCallback rel) {
  struct CGDataProvider *p = cg_new(&provider_id, sizeof *p);
  if (!p) return NULL;
  p->bytes = data; p->size = size; p->info = info; p->release = rel; return p; }
CGDataProviderRef CGDataProviderCreateWithCFData(CFDataRef d) {
  if (!d) return NULL;
  struct CGDataProvider *p = cg_new(&provider_id, sizeof *p);
  if (!p) return NULL;
  p->cf = CFDataCreateCopy(NULL, d); p->bytes = CFDataGetBytePtr(p->cf); p->size = CFDataGetLength(p->cf); return p; }
CGDataProviderRef CGDataProviderCreateWithURL(CFURLRef url) {
  char path[4096];
  if (!url || !CFURLGetFileSystemRepresentation(url, true, (UInt8 *)path, sizeof path)) return NULL;
  FILE *f = fopen(path, "rb"); if (!f) return NULL;
  fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
  unsigned char *buf = malloc(n > 0 ? n : 1); size_t got = fread(buf, 1, n > 0 ? n : 0, f); fclose(f);
  CFDataRef d = CFDataCreateWithBytesNoCopy(NULL, buf, got, kCFAllocatorMalloc);
  CGDataProviderRef p = CGDataProviderCreateWithCFData(d); CFRelease(d); return p; }
CGDataProviderRef CGDataProviderCreateWithFilename(const char *fn) {
  CFURLRef u = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)fn, strlen(fn), false);
  CGDataProviderRef p = CGDataProviderCreateWithURL(u); if (u) CFRelease(u); return p; }
CGDataProviderRef CGDataProviderRetain(CGDataProviderRef p) { if (p) CFRetain(p); return p; }
void CGDataProviderRelease(CGDataProviderRef p) { if (p) CFRelease(p); }
CFDataRef CGDataProviderCopyData(CGDataProviderRef p) { return p ? CFDataCreate(NULL, p->bytes, p->size) : NULL; }
void *CGDataProviderGetInfo(CGDataProviderRef p) { return p ? p->info : NULL; }

/* ---- images ---------------------------------------------------------------------------------------------------------------- */
CFTypeID CGImageGetTypeID(void) { CGColorSpaceGetTypeID(); return image_id; }
static int pack_layout(size_t bpc, size_t bpp, CGBitmapInfo info, CGColorSpaceRef cs, bool mask) {
  int alpha = info & kCGBitmapAlphaInfoMask, order = info & kCGBitmapByteOrderMask;
  bool gray = mask || (cs ? CGColorSpaceGetModel(cs) == kCGColorSpaceModelMonochrome : bpp == bpc || bpp == 2 * bpc);
  if (mask) alpha = 0;
  return (int)(bpp & 0xff) | (int)((bpc & 0xff) << 8) | (alpha << 16) | ((order == kCGBitmapByteOrder32Little) << 19) |
         ((order == kCGBitmapByteOrder16Little) << 20) | (gray << 21); }
CGImageRef CGImageCreate(size_t w, size_t h, size_t bpc, size_t bpp, size_t bpr, CGColorSpaceRef cs, CGBitmapInfo info,
                         CGDataProviderRef prov, const CGFloat *decode, bool interp, CGColorRenderingIntent intent) {
  if (!w || !h || !prov || (bpc != 8 && bpc != 16) || (info & kCGBitmapFloatComponents)) return NULL;
  struct CGImage *i = cg_new(&image_id, sizeof *i);
  if (!i) return NULL;
  i->w = w; i->h = h; i->bpc = bpc; i->bpp = bpp; i->bpr = bpr ? bpr : w * bpp / 8; i->info = info;
  i->cs = cs ? CGColorSpaceRetain(cs) : NULL; i->prov = CGDataProviderRetain(prov); i->interp = interp;
  return i; }
CGImageRef CGImageMaskCreate(size_t w, size_t h, size_t bpc, size_t bpp, size_t bpr, CGDataProviderRef prov, const CGFloat *decode, bool interp) {
  struct CGImage *i = (struct CGImage *)CGImageCreate(w, h, bpc, bpp, bpr, NULL, kCGImageAlphaNone, prov, decode, interp, kCGRenderingIntentDefault);
  if (i) i->mask = true;
  return i; }
CGImageRef CGImageCreateCopy(CGImageRef i) { if (i) CFRetain(i); return i; }   /* images are immutable */
CGImageRef CGImageCreateCopyWithColorSpace(CGImageRef i, CGColorSpaceRef cs) {
  return i ? CGImageCreate(i->w, i->h, i->bpc, i->bpp, i->bpr, cs, i->info, i->prov, NULL, i->interp, kCGRenderingIntentDefault) : NULL; }
CGImageRef CGImageCreateWithImageInRect(CGImageRef i, CGRect r) {
  if (!i) return NULL;
  r = CGRectIntegral(CGRectIntersection(std_rect(r), CGRectMake(0, 0, i->w, i->h)));
  if (CGRectIsEmpty(r)) return NULL;
  size_t x = (size_t)r.origin.x, y = (size_t)r.origin.y, w = (size_t)r.size.width, h = (size_t)r.size.height, pb = i->bpp / 8;
  size_t bpr = w * pb; unsigned char *buf = malloc(bpr * h);
  for (size_t row = 0; row < h; row++) memcpy(buf + row * bpr, i->prov->bytes + (y + row) * i->bpr + x * pb, bpr);
  CFDataRef d = CFDataCreateWithBytesNoCopy(NULL, buf, bpr * h, kCFAllocatorMalloc);
  CGDataProviderRef p = CGDataProviderCreateWithCFData(d); CFRelease(d);
  CGImageRef o = CGImageCreate(w, h, i->bpc, i->bpp, bpr, i->cs, i->info, p, NULL, i->interp, kCGRenderingIntentDefault);
  if (o) ((struct CGImage *)o)->mask = i->mask;
  CGDataProviderRelease(p); return o; }
CGImageRef CGImageCreateWithMask(CGImageRef i, CGImageRef mask) { return CGImageCreateCopy(i); }   /* mask ignored */
CGImageRef CGImageRetain(CGImageRef i) { if (i) CFRetain(i); return i; }
void CGImageRelease(CGImageRef i) { if (i) CFRelease(i); }
size_t CGImageGetWidth(CGImageRef i) { return i ? i->w : 0; }
size_t CGImageGetHeight(CGImageRef i) { return i ? i->h : 0; }
size_t CGImageGetBitsPerComponent(CGImageRef i) { return i ? i->bpc : 0; }
size_t CGImageGetBitsPerPixel(CGImageRef i) { return i ? i->bpp : 0; }
size_t CGImageGetBytesPerRow(CGImageRef i) { return i ? i->bpr : 0; }
CGBitmapInfo CGImageGetBitmapInfo(CGImageRef i) { return i ? i->info : 0; }
CGImageAlphaInfo CGImageGetAlphaInfo(CGImageRef i) { return i ? (CGImageAlphaInfo)(i->info & kCGBitmapAlphaInfoMask) : kCGImageAlphaNone; }
CGImageByteOrderInfo CGImageGetByteOrderInfo(CGImageRef i) { return i ? (CGImageByteOrderInfo)(i->info & kCGBitmapByteOrderMask) : 0; }
CGImagePixelFormatInfo CGImageGetPixelFormatInfo(CGImageRef i) { return kCGImagePixelFormatPacked; }
CGColorSpaceRef CGImageGetColorSpace(CGImageRef i) { return i && !i->mask ? i->cs : NULL; }
CGDataProviderRef CGImageGetDataProvider(CGImageRef i) { return i ? i->prov : NULL; }
bool CGImageIsMask(CGImageRef i) { return i && i->mask; }
bool CGImageGetShouldInterpolate(CGImageRef i) { return i && i->interp; }
const CGFloat *CGImageGetDecode(CGImageRef i) { return NULL; }
CGColorRenderingIntent CGImageGetRenderingIntent(CGImageRef i) { return kCGRenderingIntentDefault; }
CFStringRef CGImageGetUTType(CGImageRef i) { return NULL; }

/* ---- gradients ---------------------------------------------------------------------------------------------------------------- */
CFTypeID CGGradientGetTypeID(void) { CGColorSpaceGetTypeID(); return gradient_id; }
static CGGradientRef gradient_make(size_t n) {
  struct CGGradient *g = cg_new(&gradient_id, sizeof *g);
  if (!g) return NULL;
  g->n = n; g->stops = calloc(n ? n * 5 : 5, sizeof(double)); return g; }
CGGradientRef CGGradientCreateWithColorComponents(CGColorSpaceRef cs, const CGFloat *comps, const CGFloat *locs, size_t n) {
  struct CGGradient *g = (struct CGGradient *)gradient_make(n);
  if (!g) return NULL;
  size_t nc = CGColorSpaceGetNumberOfComponents(cs) + 1;
  for (size_t i = 0; i < n; i++) {
    CGColorRef c = CGColorCreate(cs, comps + i * nc); double v[4]; color_rgba(c, v); CGColorRelease(c);
    g->stops[i * 5] = locs ? locs[i] : (n > 1 ? (double)i / (n - 1) : 0);
    for (int k = 0; k < 4; k++) g->stops[i * 5 + 1 + k] = v[k]; }
  return g; }
CGGradientRef CGGradientCreateWithColors(CGColorSpaceRef cs, CFArrayRef colors, const CGFloat *locs) {
  size_t n = colors ? CFArrayGetCount(colors) : 0;
  struct CGGradient *g = (struct CGGradient *)gradient_make(n);
  if (!g) return NULL;
  for (size_t i = 0; i < n; i++) {
    double v[4]; color_rgba((CGColorRef)CFArrayGetValueAtIndex(colors, i), v);
    g->stops[i * 5] = locs ? locs[i] : (n > 1 ? (double)i / (n - 1) : 0);
    for (int k = 0; k < 4; k++) g->stops[i * 5 + 1 + k] = v[k]; }
  return g; }
CGGradientRef CGGradientRetain(CGGradientRef g) { if (g) CFRetain(g); return g; }
void CGGradientRelease(CGGradientRef g) { if (g) CFRelease(g); }

/* ---- contexts ------------------------------------------------------------------------------------------------------------------ */
CFTypeID CGContextGetTypeID(void) { CGColorSpaceGetTypeID(); return ctx_id; }
#define GS(c) (&(c)->gs[(c)->depth])
static void ctx_sync(struct CGContext *c) {
  if (!c || !c->h) return;
  xef_host_cg_flush(c->h);
  if (!c->native && c->argb) xef_host_cg_convert(c->argb, (int)c->argb_stride, c->data, (int)c->bpr, (int)c->w, (int)c->hgt, c->layout, 0); }

CGContextRef CGBitmapContextCreateWithData(void *data, size_t w, size_t h, size_t bpc, size_t bpr, CGColorSpaceRef cs, uint32_t info,
                                           CGBitmapContextReleaseDataCallback rel, void *relinfo) {
  if (!w || !h || bpc != 8 || (info & kCGBitmapFloatComponents)) { fprintf(stderr, "CoreGraphics-lite: unsupported bitmap context (%zu bpc, info %#x)\n", bpc, info); return NULL; }
  int alpha = info & kCGBitmapAlphaInfoMask, order = info & kCGBitmapByteOrderMask;
  size_t ncomp = cs ? CGColorSpaceGetNumberOfComponents(cs) : 0;   /* NULL colour space: alpha-only */
  if (ncomp > 3) ncomp = 3;
  size_t bpp = bpc * (ncomp + (alpha != kCGImageAlphaNone ? 1 : 0));
  if (alpha == kCGImageAlphaOnly) bpp = 8;
  if (!bpr) bpr = w * bpp / 8;
  struct CGContext *c = cg_new(&ctx_id, sizeof *c);
  if (!c) return NULL;
  c->w = w; c->hgt = h; c->bpr = bpr; c->bpc = bpc; c->bpp = bpp; c->info = info;
  c->cs = cs ? CGColorSpaceRetain(cs) : NULL;
  c->data = data;
  if (!data) { c->data = calloc(bpr, h); c->owns = true; }
  c->native = bpp == 32 && ncomp == 3 && order == kCGBitmapByteOrder32Little &&
              (alpha == kCGImageAlphaPremultipliedFirst || alpha == kCGImageAlphaNoneSkipFirst) && !(bpr & 3);
  c->layout = pack_layout(bpc, bpp, info, cs, false);
  if (!cs) c->layout = (c->layout & ~(7 << 16)) | (kCGImageAlphaOnly << 16);
  if (c->native) c->h = xef_host_cg_create(c->data, (int)w, (int)h, (int)bpr);
  else {
    c->argb_stride = w * 4; c->argb = calloc(c->argb_stride, h);
    if (data) xef_host_cg_convert(c->argb, (int)c->argb_stride, c->data, (int)bpr, (int)w, (int)h, c->layout, 1);
    c->h = xef_host_cg_create(c->argb, (int)w, (int)h, (int)c->argb_stride); }
  if (!c->h) { CFRelease(c); return NULL; }
  xef_host_cg_set_matrix(c->h, 1, 0, 0, -1, 0, (double)h);   /* base CTM: y-up */
  GState *g = GS(c);
  g->fill[3] = g->stroke[3] = 1; g->alpha = 1; g->lw = 1; g->miter = 10; g->aa = true; g->textm = CGAffineTransformIdentity;
  g->fontsize = 12; g->interp = kCGInterpolationDefault;
  xef_host_cg_line_style(c->h, 1, 0, 0, 10);
  c->empty = true;
  return c; }
CGContextRef CGBitmapContextCreate(void *data, size_t w, size_t h, size_t bpc, size_t bpr, CGColorSpaceRef cs, uint32_t info) {
  return CGBitmapContextCreateWithData(data, w, h, bpc, bpr, cs, info, NULL, NULL); }
static bool is_ctx(CGContextRef c) { return c && CFGetTypeID(c) == CGContextGetTypeID() && c->h; }
#define CTX(c) if (!is_ctx(c)) return
void *CGBitmapContextGetData(CGContextRef c) { if (!is_ctx(c)) return NULL; ctx_sync(c); return c->data; }
size_t CGBitmapContextGetWidth(CGContextRef c) { return is_ctx(c) ? c->w : 0; }
size_t CGBitmapContextGetHeight(CGContextRef c) { return is_ctx(c) ? c->hgt : 0; }
size_t CGBitmapContextGetBytesPerRow(CGContextRef c) { return is_ctx(c) ? c->bpr : 0; }
size_t CGBitmapContextGetBitsPerComponent(CGContextRef c) { return is_ctx(c) ? c->bpc : 0; }
size_t CGBitmapContextGetBitsPerPixel(CGContextRef c) { return is_ctx(c) ? c->bpp : 0; }
CGBitmapInfo CGBitmapContextGetBitmapInfo(CGContextRef c) { return is_ctx(c) ? c->info : 0; }
CGImageAlphaInfo CGBitmapContextGetAlphaInfo(CGContextRef c) { return is_ctx(c) ? (CGImageAlphaInfo)(c->info & kCGBitmapAlphaInfoMask) : 0; }
CGColorSpaceRef CGBitmapContextGetColorSpace(CGContextRef c) { return is_ctx(c) ? c->cs : NULL; }
CGImageRef CGBitmapContextCreateImage(CGContextRef c) {
  if (!is_ctx(c)) return NULL;
  ctx_sync(c);
  CFDataRef d = CFDataCreate(NULL, c->data, c->bpr * c->hgt);
  CGDataProviderRef p = CGDataProviderCreateWithCFData(d); CFRelease(d);
  CGImageRef i = CGImageCreate(c->w, c->hgt, c->bpc, c->bpp, c->bpr, c->cs, c->info, p, NULL, true, kCGRenderingIntentDefault);
  CGDataProviderRelease(p); return i; }
CGContextRef CGContextRetain(CGContextRef c) { if (c) CFRetain(c); return c; }
void CGContextRelease(CGContextRef c) { if (c) CFRelease(c); }
void CGContextFlush(CGContextRef c) { CTX(c); ctx_sync(c); }
void CGContextSynchronize(CGContextRef c) { CTX(c); ctx_sync(c); }
/* AppKit-lite: the host cairo context behind a CGContext (text is drawn there directly) */
int XEFCGContextGetHostHandle(CGContextRef c) { return is_ctx(c) ? c->h : 0; }
void XEFCGContextSetFillRGBA(CGContextRef c, double r, double g, double b, double a);

/* graphics state */
void CGContextSaveGState(CGContextRef c) {
  CTX(c);
  if (c->depth + 1 >= GS_MAX) return;
  c->gs[c->depth + 1] = c->gs[c->depth];
  c->depth++;
  if (GS(c)->fillcs) CFRetain(GS(c)->fillcs); if (GS(c)->strokecs) CFRetain(GS(c)->strokecs);
  xef_host_cg_save(c->h); }
void CGContextRestoreGState(CGContextRef c) {
  CTX(c);
  if (c->depth <= 0) return;
  if (GS(c)->fillcs) CFRelease(GS(c)->fillcs); if (GS(c)->strokecs) CFRelease(GS(c)->strokecs);
  c->depth--;
  xef_host_cg_restore(c->h); }
static CGAffineTransform host_ctm(CGContextRef c) { double m[6]; xef_host_cg_get_matrix(c->h, m); return CGAffineTransformMake(m[0], m[1], m[2], m[3], m[4], m[5]); }
static CGAffineTransform base_ctm(CGContextRef c) { return CGAffineTransformMake(1, 0, 0, -1, 0, (CGFloat)c->hgt); }
CGAffineTransform CGContextGetCTM(CGContextRef c) {
  if (!is_ctx(c)) return CGAffineTransformIdentity;
  return CGAffineTransformConcat(host_ctm(c), CGAffineTransformInvert(base_ctm(c))); }
void CGContextConcatCTM(CGContextRef c, CGAffineTransform t) { CTX(c); xef_host_cg_concat(c->h, t.a, t.b, t.c, t.d, t.tx, t.ty); }
void CGContextTranslateCTM(CGContextRef c, CGFloat x, CGFloat y) { CGContextConcatCTM(c, CGAffineTransformMakeTranslation(x, y)); }
void CGContextScaleCTM(CGContextRef c, CGFloat x, CGFloat y) { CGContextConcatCTM(c, CGAffineTransformMakeScale(x, y)); }
void CGContextRotateCTM(CGContextRef c, CGFloat a) { CGContextConcatCTM(c, CGAffineTransformMakeRotation(a)); }
void CGContextSetCTM(CGContextRef c, CGAffineTransform t) {
  CTX(c); CGAffineTransform m = CGAffineTransformConcat(t, base_ctm(c)); xef_host_cg_set_matrix(c->h, m.a, m.b, m.c, m.d, m.tx, m.ty); }
CGAffineTransform CGContextGetUserSpaceToDeviceSpaceTransform(CGContextRef c) { return CGContextGetCTM(c); }
CGPoint CGContextConvertPointToDeviceSpace(CGContextRef c, CGPoint p) { return CGPointApplyAffineTransform(p, CGContextGetCTM(c)); }
CGPoint CGContextConvertPointToUserSpace(CGContextRef c, CGPoint p) { return CGPointApplyAffineTransform(p, CGAffineTransformInvert(CGContextGetCTM(c))); }
CGSize CGContextConvertSizeToDeviceSpace(CGContextRef c, CGSize s) { return CGSizeApplyAffineTransform(s, CGContextGetCTM(c)); }
CGSize CGContextConvertSizeToUserSpace(CGContextRef c, CGSize s) { return CGSizeApplyAffineTransform(s, CGAffineTransformInvert(CGContextGetCTM(c))); }
CGRect CGContextConvertRectToDeviceSpace(CGContextRef c, CGRect r) { return CGRectApplyAffineTransform(r, CGContextGetCTM(c)); }
CGRect CGContextConvertRectToUserSpace(CGContextRef c, CGRect r) { return CGRectApplyAffineTransform(r, CGAffineTransformInvert(CGContextGetCTM(c))); }

void CGContextSetLineWidth(CGContextRef c, CGFloat w) { CTX(c); GS(c)->lw = w; xef_host_cg_line_style(c->h, w, GS(c)->cap, GS(c)->join, GS(c)->miter); }
void CGContextSetLineCap(CGContextRef c, CGLineCap v) { CTX(c); GS(c)->cap = v; xef_host_cg_line_style(c->h, GS(c)->lw, v, GS(c)->join, GS(c)->miter); }
void CGContextSetLineJoin(CGContextRef c, CGLineJoin v) { CTX(c); GS(c)->join = v; xef_host_cg_line_style(c->h, GS(c)->lw, GS(c)->cap, v, GS(c)->miter); }
void CGContextSetMiterLimit(CGContextRef c, CGFloat v) { CTX(c); GS(c)->miter = v; xef_host_cg_line_style(c->h, GS(c)->lw, GS(c)->cap, GS(c)->join, v); }
void CGContextSetLineDash(CGContextRef c, CGFloat phase, const CGFloat *l, size_t n) {
  CTX(c); double d[32]; size_t k = n > 32 ? 32 : n; for (size_t i = 0; i < k; i++) d[i] = l[i]; xef_host_cg_dash(c->h, d, l ? (int)k : 0, phase); }
void CGContextSetFlatness(CGContextRef c, CGFloat f) {}
void CGContextSetAlpha(CGContextRef c, CGFloat a) { CTX(c); GS(c)->alpha = a; }
void CGContextSetShouldAntialias(CGContextRef c, bool f) { CTX(c); GS(c)->aa = f; xef_host_cg_antialias(c->h, f); }
void CGContextSetAllowsAntialiasing(CGContextRef c, bool f) {}
void CGContextSetShouldSmoothFonts(CGContextRef c, bool f) {}
void CGContextSetAllowsFontSmoothing(CGContextRef c, bool f) {}
void CGContextSetShouldSubpixelPositionFonts(CGContextRef c, bool f) {}
void CGContextSetAllowsFontSubpixelPositioning(CGContextRef c, bool f) {}
void CGContextSetShouldSubpixelQuantizeFonts(CGContextRef c, bool f) {}
void CGContextSetAllowsFontSubpixelQuantization(CGContextRef c, bool f) {}
void CGContextSetRenderingIntent(CGContextRef c, CGColorRenderingIntent i) {}
void CGContextSetInterpolationQuality(CGContextRef c, CGInterpolationQuality q) { CTX(c); GS(c)->interp = q; }
CGInterpolationQuality CGContextGetInterpolationQuality(CGContextRef c) { return is_ctx(c) ? GS(c)->interp : kCGInterpolationDefault; }
void CGContextSetShadow(CGContextRef c, CGSize off, CGFloat blur) {}               /* shadows are not rendered */
void CGContextSetShadowWithColor(CGContextRef c, CGSize off, CGFloat blur, CGColorRef col) {}
void CGContextBeginTransparencyLayer(CGContextRef c, CFDictionaryRef aux) { CGContextSaveGState(c); }   /* no group compositing */
void CGContextBeginTransparencyLayerWithRect(CGContextRef c, CGRect r, CFDictionaryRef aux) { CGContextSaveGState(c); }
void CGContextEndTransparencyLayer(CGContextRef c) { CGContextRestoreGState(c); }
void CGContextSetBlendMode(CGContextRef c, CGBlendMode m) {
  static const int op[] = { 2, 14, 15, 16, 17, 18, 19, 20, 22, 21, 23, 24, 25, 26, 27, 28, 0, 1, 3, 4, 5, 7, 8, 9, 10, 11, 2, 12 };
  CTX(c); GS(c)->blend = m; xef_host_cg_operator(c->h, (unsigned)m < sizeof op / sizeof *op ? op[m] : 2); }

/* colours */
static void set_rgba(double *dst, double r, double g, double b, double a) { dst[0] = r; dst[1] = g; dst[2] = b; dst[3] = a; }
void CGContextSetRGBFillColor(CGContextRef c, CGFloat r, CGFloat g, CGFloat b, CGFloat a) { CTX(c); set_rgba(GS(c)->fill, r, g, b, a); }
void CGContextSetRGBStrokeColor(CGContextRef c, CGFloat r, CGFloat g, CGFloat b, CGFloat a) { CTX(c); set_rgba(GS(c)->stroke, r, g, b, a); }
void CGContextSetGrayFillColor(CGContextRef c, CGFloat g, CGFloat a) { CTX(c); set_rgba(GS(c)->fill, g, g, g, a); }
void CGContextSetGrayStrokeColor(CGContextRef c, CGFloat g, CGFloat a) { CTX(c); set_rgba(GS(c)->stroke, g, g, g, a); }
void CGContextSetCMYKFillColor(CGContextRef c, CGFloat cy, CGFloat m, CGFloat y, CGFloat k, CGFloat a) {
  CTX(c); set_rgba(GS(c)->fill, (1 - cy) * (1 - k), (1 - m) * (1 - k), (1 - y) * (1 - k), a); }
void CGContextSetCMYKStrokeColor(CGContextRef c, CGFloat cy, CGFloat m, CGFloat y, CGFloat k, CGFloat a) {
  CTX(c); set_rgba(GS(c)->stroke, (1 - cy) * (1 - k), (1 - m) * (1 - k), (1 - y) * (1 - k), a); }
void CGContextSetFillColorWithColor(CGContextRef c, CGColorRef col) { CTX(c); color_rgba(col, GS(c)->fill); }
void CGContextSetStrokeColorWithColor(CGContextRef c, CGColorRef col) { CTX(c); color_rgba(col, GS(c)->stroke); }
void CGContextSetFillColorSpace(CGContextRef c, CGColorSpaceRef s) {
  CTX(c); if (s) CFRetain(s); if (GS(c)->fillcs) CFRelease(GS(c)->fillcs); GS(c)->fillcs = s; set_rgba(GS(c)->fill, 0, 0, 0, 1); }
void CGContextSetStrokeColorSpace(CGContextRef c, CGColorSpaceRef s) {
  CTX(c); if (s) CFRetain(s); if (GS(c)->strokecs) CFRelease(GS(c)->strokecs); GS(c)->strokecs = s; set_rgba(GS(c)->stroke, 0, 0, 0, 1); }
static void comps_rgba(CGColorSpaceRef s, const CGFloat *v, double *out) {
  CGColorRef col = CGColorCreate(s, v); color_rgba(col, out); CGColorRelease(col); }
void CGContextSetFillColor(CGContextRef c, const CGFloat *v) { CTX(c); if (v) comps_rgba(GS(c)->fillcs, v, GS(c)->fill); }
void CGContextSetStrokeColor(CGContextRef c, const CGFloat *v) { CTX(c); if (v) comps_rgba(GS(c)->strokecs, v, GS(c)->stroke); }
void XEFCGContextSetFillRGBA(CGContextRef c, double r, double g, double b, double a) { CGContextSetRGBFillColor(c, r, g, b, a); }

/* path construction */
void CGContextBeginPath(CGContextRef c) { CTX(c); xef_host_cg_new_path(c->h); c->empty = true; }
void CGContextMoveToPoint(CGContextRef c, CGFloat x, CGFloat y) { CTX(c); xef_host_cg_move(c->h, x, y); c->empty = false; c->cur = c->start = CGPointMake(x, y); }
void CGContextAddLineToPoint(CGContextRef c, CGFloat x, CGFloat y) {
  CTX(c); if (c->empty) CGContextMoveToPoint(c, x, y); xef_host_cg_line(c->h, x, y); c->cur = CGPointMake(x, y); }
void CGContextAddCurveToPoint(CGContextRef c, CGFloat c1x, CGFloat c1y, CGFloat c2x, CGFloat c2y, CGFloat x, CGFloat y) {
  CTX(c); if (c->empty) CGContextMoveToPoint(c, c1x, c1y); xef_host_cg_curve(c->h, c1x, c1y, c2x, c2y, x, y); c->cur = CGPointMake(x, y); }
void CGContextAddQuadCurveToPoint(CGContextRef c, CGFloat cx, CGFloat cy, CGFloat x, CGFloat y) {
  CTX(c); if (c->empty) CGContextMoveToPoint(c, cx, cy);
  CGPoint p0 = c->cur;
  CGContextAddCurveToPoint(c, p0.x + 2.0 / 3 * (cx - p0.x), p0.y + 2.0 / 3 * (cy - p0.y), x + 2.0 / 3 * (cx - x), y + 2.0 / 3 * (cy - y), x, y); }
void CGContextClosePath(CGContextRef c) { CTX(c); if (!c->empty) { xef_host_cg_close(c->h); c->cur = c->start; } }
/* replays a CGPath into the context */
void CGContextAddPath(CGContextRef c, CGPathRef p) {
  CTX(c); if (!p) return;
  for (size_t i = 0; i < p->n; i++) {
    const PEl *e = &p->e[i];
    switch (e->type) {
    case kCGPathElementMoveToPoint: CGContextMoveToPoint(c, e->p[0].x, e->p[0].y); break;
    case kCGPathElementAddLineToPoint: CGContextAddLineToPoint(c, e->p[0].x, e->p[0].y); break;
    case kCGPathElementAddQuadCurveToPoint: CGContextAddQuadCurveToPoint(c, e->p[0].x, e->p[0].y, e->p[1].x, e->p[1].y); break;
    case kCGPathElementAddCurveToPoint: CGContextAddCurveToPoint(c, e->p[0].x, e->p[0].y, e->p[1].x, e->p[1].y, e->p[2].x, e->p[2].y); break;
    case kCGPathElementCloseSubpath: CGContextClosePath(c); break; } } }
static void add_tmp_path(CGContextRef c, CGMutablePathRef p) { CGContextAddPath(c, p); CGPathRelease(p); }
void CGContextAddRect(CGContextRef c, CGRect r) { CTX(c); xef_host_cg_rect(c->h, r.origin.x, r.origin.y, r.size.width, r.size.height); c->empty = false; c->cur = c->start = r.origin; }
void CGContextAddRects(CGContextRef c, const CGRect *r, size_t n) { for (size_t i = 0; i < n; i++) CGContextAddRect(c, r[i]); }
void CGContextAddLines(CGContextRef c, const CGPoint *p, size_t n) {
  for (size_t i = 0; i < n; i++) { if (i == 0) CGContextMoveToPoint(c, p[i].x, p[i].y); else CGContextAddLineToPoint(c, p[i].x, p[i].y); } }
void CGContextAddEllipseInRect(CGContextRef c, CGRect r) { CTX(c); CGMutablePathRef p = CGPathCreateMutable(); CGPathAddEllipseInRect(p, NULL, r); add_tmp_path(c, p); }
void CGContextAddArc(CGContextRef c, CGFloat x, CGFloat y, CGFloat r, CGFloat a0, CGFloat a1, int cw) {
  CTX(c); CGMutablePathRef p = CGPathCreateMutable();
  arc_beziers(p, NULL, x, y, r, a0, a1, cw != 0, false);
  if (!c->empty && p->n) p->e[0].type = kCGPathElementAddLineToPoint;   /* joined to the current point */
  add_tmp_path(c, p); }
void CGContextAddArcToPoint(CGContextRef c, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, CGFloat r) {
  CTX(c); CGMutablePathRef p = CGPathCreateMutable();
  CGPathMoveToPoint(p, NULL, c->cur.x, c->cur.y);
  CGPathAddArcToPoint(p, NULL, x1, y1, x2, y2, r);
  if (!c->empty) p->e[0].type = kCGPathElementAddLineToPoint;
  add_tmp_path(c, p); }
bool CGContextIsPathEmpty(CGContextRef c) { return !is_ctx(c) || c->empty; }
CGPoint CGContextGetPathCurrentPoint(CGContextRef c) { return is_ctx(c) && !c->empty ? c->cur : CGPointZero; }
CGRect CGContextGetPathBoundingBox(CGContextRef c) {
  if (!is_ctx(c) || c->empty) return CGRectNull;
  double e[4]; xef_host_cg_path_extents(c->h, e); return CGRectMake(e[0], e[1], e[2] - e[0], e[3] - e[1]); }
bool CGContextPathContainsPoint(CGContextRef c, CGPoint p, CGPathDrawingMode m) {
  return is_ctx(c) && !c->empty && xef_host_cg_in_fill(c->h, p.x, p.y); }
void CGContextReplacePathWithStrokedPath(CGContextRef c) {}   /* not supported: the path stays as it is */

/* painting */
static void src(CGContextRef c, const double *col) { xef_host_cg_source_rgba(c->h, col[0], col[1], col[2], col[3] * GS(c)->alpha); }
void CGContextDrawPath(CGContextRef c, CGPathDrawingMode m) {
  CTX(c);
  bool fill = m == kCGPathFill || m == kCGPathEOFill || m == kCGPathFillStroke || m == kCGPathEOFillStroke;
  bool stroke = m == kCGPathStroke || m == kCGPathFillStroke || m == kCGPathEOFillStroke;
  bool eo = m == kCGPathEOFill || m == kCGPathEOFillStroke;
  if (fill) { src(c, GS(c)->fill); xef_host_cg_fill(c->h, eo, stroke); }
  if (stroke) { src(c, GS(c)->stroke); xef_host_cg_stroke(c->h, 0); }
  c->empty = true; }
void CGContextFillPath(CGContextRef c) { CGContextDrawPath(c, kCGPathFill); }
void CGContextEOFillPath(CGContextRef c) { CGContextDrawPath(c, kCGPathEOFill); }
void CGContextStrokePath(CGContextRef c) { CGContextDrawPath(c, kCGPathStroke); }
void CGContextFillRect(CGContextRef c, CGRect r) { CGContextBeginPath(c); CGContextAddRect(c, r); CGContextFillPath(c); }
void CGContextFillRects(CGContextRef c, const CGRect *r, size_t n) { CGContextBeginPath(c); CGContextAddRects(c, r, n); CGContextFillPath(c); }
void CGContextStrokeRect(CGContextRef c, CGRect r) { CGContextBeginPath(c); CGContextAddRect(c, r); CGContextStrokePath(c); }
void CGContextStrokeRectWithWidth(CGContextRef c, CGRect r, CGFloat w) {
  CTX(c); CGContextSaveGState(c); CGContextSetLineWidth(c, w); CGContextStrokeRect(c, r); CGContextRestoreGState(c); }
void CGContextFillEllipseInRect(CGContextRef c, CGRect r) { CGContextBeginPath(c); CGContextAddEllipseInRect(c, r); CGContextFillPath(c); }
void CGContextStrokeEllipseInRect(CGContextRef c, CGRect r) { CGContextBeginPath(c); CGContextAddEllipseInRect(c, r); CGContextStrokePath(c); }
void CGContextStrokeLineSegments(CGContextRef c, const CGPoint *p, size_t n) {
  CGContextBeginPath(c);
  for (size_t i = 0; i + 1 < n; i += 2) { CGContextMoveToPoint(c, p[i].x, p[i].y); CGContextAddLineToPoint(c, p[i + 1].x, p[i + 1].y); }
  CGContextStrokePath(c); }
void CGContextClearRect(CGContextRef c, CGRect r) {
  CTX(c);
  xef_host_cg_save(c->h); xef_host_cg_operator(c->h, 0 /*CLEAR*/); xef_host_cg_new_path(c->h);
  xef_host_cg_rect(c->h, r.origin.x, r.origin.y, r.size.width, r.size.height); xef_host_cg_fill(c->h, 0, 0); xef_host_cg_restore(c->h);
  c->empty = true; }

/* clipping */
void CGContextClip(CGContextRef c) { CTX(c); if (!c->empty) xef_host_cg_clip(c->h, 0); c->empty = true; }
void CGContextEOClip(CGContextRef c) { CTX(c); if (!c->empty) xef_host_cg_clip(c->h, 1); c->empty = true; }
void CGContextClipToRect(CGContextRef c, CGRect r) {
  CTX(c); xef_host_cg_new_path(c->h); xef_host_cg_rect(c->h, r.origin.x, r.origin.y, r.size.width, r.size.height); xef_host_cg_clip(c->h, 0); c->empty = true; }
void CGContextClipToRects(CGContextRef c, const CGRect *r, size_t n) {
  CTX(c); xef_host_cg_new_path(c->h);
  for (size_t i = 0; i < n; i++) xef_host_cg_rect(c->h, r[i].origin.x, r[i].origin.y, r[i].size.width, r[i].size.height);
  xef_host_cg_clip(c->h, 0); c->empty = true; }
void CGContextClipToMask(CGContextRef c, CGRect r, CGImageRef mask) { CGContextClipToRect(c, r); }   /* mask approximated by its rect */
CGRect CGContextGetClipBoundingBox(CGContextRef c) {
  if (!is_ctx(c)) return CGRectNull;
  double e[4]; xef_host_cg_clip_extents(c->h, e); return CGRectMake(e[0], e[1], e[2] - e[0], e[3] - e[1]); }

/* images and gradients */
static void draw_image(CGContextRef c, CGRect r, CGImageRef img) {
  if (!img || !img->prov || !img->prov->bytes) return;
  xef_host_cg_save(c->h);
  xef_host_cg_concat(c->h, r.size.width, 0, 0, -r.size.height, r.origin.x, r.origin.y + r.size.height);   /* row 0 at the top */
  int layout = pack_layout(img->bpc, img->bpp, img->info, img->cs, img->mask);
  if (img->mask) {
    /* stencil mask (0 = paint): drawn as fill colour with the mask's inverse as alpha */
    size_t n = img->w * img->h; unsigned char *a = malloc(n * 4);
    for (size_t y = 0; y < img->h; y++) for (size_t x = 0; x < img->w; x++) {
      unsigned v = img->prov->bytes[y * img->bpr + x * (img->bpp / 8)], al = (unsigned)((255 - v) * GS(c)->fill[3]);
      unsigned char *p = a + (y * img->w + x) * 4;
      p[0] = (unsigned char)(GS(c)->fill[2] * al); p[1] = (unsigned char)(GS(c)->fill[1] * al); p[2] = (unsigned char)(GS(c)->fill[0] * al); p[3] = (unsigned char)al; }
    xef_host_cg_image(c->h, a, (int)img->w, (int)img->h, (int)img->w * 4, 32 | (8 << 8) | (kCGImageAlphaPremultipliedFirst << 16) | (1 << 19), GS(c)->alpha, 1);
    free(a);
  } else
    xef_host_cg_image(c->h, img->prov->bytes, (int)img->w, (int)img->h, (int)img->bpr, layout, GS(c)->alpha,
                      GS(c)->interp != kCGInterpolationNone && img->interp);
  xef_host_cg_restore(c->h); }
void CGContextDrawImage(CGContextRef c, CGRect r, CGImageRef img) { CTX(c); draw_image(c, r, img); if (!c->native) ctx_sync(c); }
void CGContextDrawTiledImage(CGContextRef c, CGRect r, CGImageRef img) {
  CTX(c); if (!img || r.size.width <= 0 || r.size.height <= 0) return;
  CGRect clip = CGContextGetClipBoundingBox(c);
  if (CGRectIsNull(clip) || CGRectIsInfinite(clip)) { draw_image(c, r, img); return; }
  double x0 = r.origin.x + floor((clip.origin.x - r.origin.x) / r.size.width) * r.size.width;
  double y0 = r.origin.y + floor((clip.origin.y - r.origin.y) / r.size.height) * r.size.height;
  for (double y = y0; y < clip.origin.y + clip.size.height; y += r.size.height)
    for (double x = x0; x < clip.origin.x + clip.size.width; x += r.size.width) draw_image(c, CGRectMake(x, y, r.size.width, r.size.height), img);
  if (!c->native) ctx_sync(c); }
void CGContextDrawLinearGradient(CGContextRef c, CGGradientRef g, CGPoint s, CGPoint e, CGGradientDrawingOptions o) {
  CTX(c); if (!g) return;
  xef_host_cg_gradient(c->h, 0, s.x, s.y, 0, e.x, e.y, 0, g->stops, (int)g->n, (int)o); }
void CGContextDrawRadialGradient(CGContextRef c, CGGradientRef g, CGPoint s, CGFloat sr, CGPoint e, CGFloat er, CGGradientDrawingOptions o) {
  CTX(c); if (!g) return;
  xef_host_cg_gradient(c->h, 1, s.x, s.y, sr, e.x, e.y, er, g->stops, (int)g->n, (int)o); }

/* text state (glyph drawing goes through CoreText-lite / AppKit-lite, which use the host's text layout) */
void CGContextSetTextMatrix(CGContextRef c, CGAffineTransform t) { CTX(c); GS(c)->textm = t; }
CGAffineTransform CGContextGetTextMatrix(CGContextRef c) { return is_ctx(c) ? GS(c)->textm : CGAffineTransformIdentity; }
void CGContextSetTextPosition(CGContextRef c, CGFloat x, CGFloat y) { CTX(c); c->textpos = CGPointMake(x, y); }
CGPoint CGContextGetTextPosition(CGContextRef c) { return is_ctx(c) ? c->textpos : CGPointZero; }
void CGContextSetTextDrawingMode(CGContextRef c, CGTextDrawingMode m) { CTX(c); GS(c)->textmode = m; }
void CGContextSetCharacterSpacing(CGContextRef c, CGFloat s) { CTX(c); GS(c)->charspace = s; }
void CGContextSetFontSize(CGContextRef c, CGFloat s) { CTX(c); GS(c)->fontsize = s; }
void CGContextSetFont(CGContextRef c, CGFontRef f) { CTX(c); GS(c)->font = f; }
