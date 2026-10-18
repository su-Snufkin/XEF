/* CoreGraphics-lite for xef-osx: the display-management and event-source entry points GLFW's Cocoa backend uses.
 * The host has one screen (X11) that is reported as the single online display with ID 1, one display mode, a linear
 * gamma ramp and no display fading. Geometry comes from the host (xef_host_screen_info). Entries marked "HLE:" are
 * behaviourally no-ops on X11 (checked against the Mac: GLFW's windowed rendering does not depend on them). */
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdlib.h>
#include <string.h>

extern void xef_host_screen_info(int *w, int *h, int *mm_w, int *mm_h);
extern void xef_host_pointer_warp(int x, int y);

/* ---- CF classes (the open-source CF in the rootfs exposes the runtime SPI) ---------------------------------- */
typedef struct { uintptr_t _cfisa; uint8_t _cfinfo[4]; uint32_t _rc; } XBase;
typedef struct { CFIndex version; const char *className; void *init; void *copy; void *finalize; void *equal; void *hash;
                 void *copyFormattingDesc; void *copyDebugDesc; void *reclaim; void *refcount; } XClass;
extern CFTypeID _CFRuntimeRegisterClass(const XClass *cls);
extern CFTypeRef _CFRuntimeCreateInstance(CFAllocatorRef a, CFTypeID id, CFIndex extra, unsigned char *category);

typedef struct { XBase b; size_t w, h; double refresh; uint32_t flags; } XMode;
typedef struct { XBase b; double suppression; int state; } XEventSource;
static CFTypeID mode_id, source_id;
static void classes_init(void) {
  if (mode_id) return;
  static XClass m = { 0, "CGDisplayMode" }, s = { 0, "CGEventSource" };   /* CF keeps the pointer */
  mode_id = _CFRuntimeRegisterClass(&m); source_id = _CFRuntimeRegisterClass(&s);
}

#define DISPLAY_ID 1u
static void screen(int *w, int *h, int *mw, int *mh) { xef_host_screen_info(w, h, mw, mh); }

CGDirectDisplayID CGMainDisplayID(void) { return DISPLAY_ID; }
CGError CGGetOnlineDisplayList(uint32_t max, CGDirectDisplayID *ids, uint32_t *count) {
  if (ids && max >= 1) ids[0] = DISPLAY_ID;
  if (count) *count = (ids && max < 1) ? 0 : 1;
  return kCGErrorSuccess; }
boolean_t CGDisplayIsAsleep(CGDirectDisplayID d) { return 0; }
uint32_t CGDisplayUnitNumber(CGDirectDisplayID d) { return 0; }
uint32_t CGDisplayVendorNumber(CGDirectDisplayID d) { return 0xFFFFFFFFu; }   /* kCGDisplayVendorUnknown */
uint32_t CGDisplayModelNumber(CGDirectDisplayID d) { return 0xFFFFFFFFu; }    /* kCGDisplayModelUnknown */
CGRect CGDisplayBounds(CGDirectDisplayID d) { int w, h; screen(&w, &h, 0, 0); return CGRectMake(0, 0, w, h); }
CGSize CGDisplayScreenSize(CGDirectDisplayID d) { int mw, mh; screen(0, 0, &mw, &mh); return CGSizeMake(mw, mh); }
uint32_t CGOpenGLDisplayMaskToDisplayID(uint32_t mask) { return (mask & 1) ? DISPLAY_ID : 0; }
extern void *MTLCreateSystemDefaultDevice(void);
void *CGDirectDisplayCopyCurrentMetalDevice(CGDirectDisplayID d) { return MTLCreateSystemDefaultDevice(); }

/* ---- display modes: exactly one (the host screen), 60 Hz assumed (X11 core protocol has no refresh rate) ----- */
static CGDisplayModeRef make_mode(void) {
  classes_init(); int w, h; screen(&w, &h, 0, 0);
  XMode *m = (XMode *)_CFRuntimeCreateInstance(kCFAllocatorDefault, mode_id, sizeof(XMode) - sizeof(XBase), NULL);
  if (!m) return NULL;
  m->w = w; m->h = h; m->refresh = 60.0; m->flags = 0x1 /*valid*/ | 0x2 /*safe*/ | 0x4 /*default*/;
  return (CGDisplayModeRef)m; }
CGDisplayModeRef CGDisplayCopyDisplayMode(CGDirectDisplayID d) { return make_mode(); }
CFArrayRef CGDisplayCopyAllDisplayModes(CGDirectDisplayID d, CFDictionaryRef opts) {
  CGDisplayModeRef m = make_mode(); if (!m) return NULL;
  const void *v[1] = { m }; CFArrayRef a = CFArrayCreate(kCFAllocatorDefault, v, 1, &kCFTypeArrayCallBacks); CFRelease(m); return a; }
void CGDisplayModeRelease(CGDisplayModeRef m) { if (m) CFRelease(m); }
size_t CGDisplayModeGetWidth(CGDisplayModeRef m) { return ((XMode *)m)->w; }
size_t CGDisplayModeGetHeight(CGDisplayModeRef m) { return ((XMode *)m)->h; }
double CGDisplayModeGetRefreshRate(CGDisplayModeRef m) { return ((XMode *)m)->refresh; }
uint32_t CGDisplayModeGetIOFlags(CGDisplayModeRef m) { return ((XMode *)m)->flags; }
CGError CGDisplaySetDisplayMode(CGDirectDisplayID d, CGDisplayModeRef m, CFDictionaryRef opts) {
  int w, h; screen(&w, &h, 0, 0);   /* the only mode is the current one: switching to it is a no-op, anything else is impossible */
  return (CGDisplayModeGetWidth(m) == (size_t)w && CGDisplayModeGetHeight(m) == (size_t)h) ? kCGErrorSuccess : kCGErrorFailure; }

/* ---- gamma: identity ramp, read-only ----------------------------------------------------------------------------- */
uint32_t CGDisplayGammaTableCapacity(CGDirectDisplayID d) { return 256; }
CGError CGGetDisplayTransferByTable(CGDirectDisplayID d, uint32_t cap, CGGammaValue *r, CGGammaValue *g, CGGammaValue *b, uint32_t *n) {
  uint32_t c = cap < 256 ? cap : 256;
  for (uint32_t i = 0; i < c; i++) { CGGammaValue v = c > 1 ? (CGGammaValue)i / (CGGammaValue)(c - 1) : 0; if (r) r[i] = v; if (g) g[i] = v; if (b) b[i] = v; }
  if (n) *n = c; return kCGErrorSuccess; }
CGError CGSetDisplayTransferByTable(CGDirectDisplayID d, uint32_t n, const CGGammaValue *r, const CGGammaValue *g, const CGGammaValue *b) {
  return kCGErrorCannotComplete; }   /* the host server's gamma ramp is not exposed */

/* ---- fades (HLE: no-ops; they only dim the screen around a video-mode switch, which never happens here) ----------- */
CGError CGAcquireDisplayFadeReservation(CGDisplayReservationInterval s, CGDisplayFadeReservationToken *t) { if (t) *t = 1; return kCGErrorSuccess; }
CGError CGDisplayFade(CGDisplayFadeReservationToken t, CGDisplayFadeInterval s, CGDisplayBlendFraction a, CGDisplayBlendFraction b,
                      float r, float g, float bl, boolean_t wait) { return kCGErrorSuccess; }
CGError CGReleaseDisplayFadeReservation(CGDisplayFadeReservationToken t) { return kCGErrorSuccess; }

/* ---- pointer ------------------------------------------------------------------------------------------------------ */
CGError CGWarpMouseCursorPosition(CGPoint p) { xef_host_pointer_warp((int)p.x, (int)p.y); return kCGErrorSuccess; }
CGError CGDisplayMoveCursorToPoint(CGDirectDisplayID d, CGPoint p) { xef_host_pointer_warp((int)p.x, (int)p.y); return kCGErrorSuccess; }
/* HLE: X11 cannot detach the pointer from the cursor; cursor-disabled mode still gets motion deltas from the warp-to-centre loop */
CGError CGAssociateMouseAndMouseCursorPosition(boolean_t connected) { return kCGErrorSuccess; }

/* ---- event source: a plain object, GLFW only stores it and sets the suppression interval --------------------------- */
CGEventSourceRef CGEventSourceCreate(CGEventSourceStateID state) {
  classes_init();
  XEventSource *s = (XEventSource *)_CFRuntimeCreateInstance(kCFAllocatorDefault, source_id, sizeof(XEventSource) - sizeof(XBase), NULL);
  if (s) s->state = state;
  return (CGEventSourceRef)s; }
void CGEventSourceSetLocalEventsSuppressionInterval(CGEventSourceRef s, CFTimeInterval i) { if (s) ((XEventSource *)s)->suppression = i; }

/* ---- more display queries (SDL2's Cocoa video backend) ------------------------------------------------------------ */
boolean_t CGDisplayIsMain(CGDirectDisplayID d) { return d == DISPLAY_ID; }
CGError CGGetActiveDisplayList(uint32_t max, CGDirectDisplayID *ids, uint32_t *count) { return CGGetOnlineDisplayList(max, ids, count); }
size_t CGDisplayPixelsWide(CGDirectDisplayID d) { int w, h; screen(&w, &h, 0, 0); return w; }
size_t CGDisplayPixelsHigh(CGDirectDisplayID d) { int w, h; screen(&w, &h, 0, 0); return h; }
CGDirectDisplayID CGDisplayMirrorsDisplay(CGDirectDisplayID d) { return 0; }   /* kCGNullDirectDisplay */
uint32_t CGDisplayIDToOpenGLDisplayMask(CGDirectDisplayID d) { return d == DISPLAY_ID ? 1u : 0u; }
uint32_t CGDisplayIOServicePort(CGDirectDisplayID d) { return 0; }   /* MACH_PORT_NULL: no IORegistry entry */
size_t CGDisplayModeGetPixelWidth(CGDisplayModeRef m) { return ((XMode *)m)->w; }
size_t CGDisplayModeGetPixelHeight(CGDisplayModeRef m) { return ((XMode *)m)->h; }
bool CGDisplayModeIsUsableForDesktopGUI(CGDisplayModeRef m) { return true; }
CFStringRef CGDisplayModeCopyPixelEncoding(CGDisplayModeRef m) { return CFStringCreateCopy(kCFAllocatorDefault, CFSTR("--------RRRRRRRRGGGGGGGGBBBBBBBB")); }
const CFStringRef kCGDisplayShowDuplicateLowResolutionModes = CFSTR("kCGDisplayShowDuplicateLowResolutionModes");

/* HLE: exclusive display capture does not exist on X11; fullscreen goes through the window frame instead */
CGError CGDisplayCapture(CGDirectDisplayID d) { return kCGErrorSuccess; }
CGError CGDisplayRelease(CGDirectDisplayID d) { return kCGErrorSuccess; }
CGError CGCaptureAllDisplays(void) { return kCGErrorSuccess; }
CGError CGReleaseAllDisplays(void) { return kCGErrorSuccess; }
int32_t CGShieldingWindowLevel(void) { return 2147483630; }
/* HLE: cursor visibility follows NSCursor hide/unhide in AppKit-lite */
CGError CGDisplayHideCursor(CGDirectDisplayID d) { return kCGErrorSuccess; }
CGError CGDisplayShowCursor(CGDirectDisplayID d) { return kCGErrorSuccess; }
/* synthetic events: only used by SDL to nudge the pointer after a warp; posting is a no-op */
CGEventRef CGEventCreateMouseEvent(CGEventSourceRef s, CGEventType t, CGPoint p, CGMouseButton b) {
  return (CGEventRef)CFStringCreateCopy(kCFAllocatorDefault, CFSTR("CGEvent")); }
void CGEventPost(CGEventTapLocation tap, CGEventRef e) {}
bool CGRectIntersectsRect(CGRect a, CGRect b) {
  if (a.size.width < 0) { a.origin.x += a.size.width; a.size.width = -a.size.width; }
  if (a.size.height < 0) { a.origin.y += a.size.height; a.size.height = -a.size.height; }
  if (b.size.width < 0) { b.origin.x += b.size.width; b.size.width = -b.size.width; }
  if (b.size.height < 0) { b.origin.y += b.size.height; b.size.height = -b.size.height; }
  if (a.size.width == 0 || a.size.height == 0 || b.size.width == 0 || b.size.height == 0) return false;
  return a.origin.x < b.origin.x + b.size.width && b.origin.x < a.origin.x + a.size.width &&
         a.origin.y < b.origin.y + b.size.height && b.origin.y < a.origin.y + a.size.height; }
const CFStringRef kCGColorBlack = CFSTR("kCGColorBlack");
CGColorRef CGColorGetConstantColor(CFStringRef name) { return (CGColorRef)name; }   /* opaque token: only passed back to AppKit-lite */
CGColorSpaceRef CGColorSpaceCreateWithName(CFStringRef name) { return (CGColorSpaceRef)name; }
void CGColorSpaceRelease(CGColorSpaceRef space) {}
typedef void (*CGDisplayReconfigurationCallBack)(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void *userInfo);
CGError CGDisplayRegisterReconfigurationCallback(CGDisplayReconfigurationCallBack proc, void *userInfo) { return kCGErrorSuccess; }
CGError CGDisplayRemoveReconfigurationCallback(CGDisplayReconfigurationCallBack proc, void *userInfo) { return kCGErrorSuccess; }
