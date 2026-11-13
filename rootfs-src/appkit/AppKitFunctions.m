/* AppKit-lite: the exported C functions (alert panels, window lists, tiled-rect and image drawing helpers, depth queries, accessibility helpers, services). */
#import "AppKitLite.h"
#import "AppKitGraphics.h"
#import "AppKitControls.h"
#include <stdarg.h>
#include <objc/message.h>
typedef int NSWindowDepth;
typedef unsigned int NSGlyph;

/* ---- alert panels: the old function API on top of NSAlert (the first button is the default) ---- */
static NSInteger XEFRunAlert(NSString *title, NSString *msg, NSString *def, NSString *alt, NSString *other, NSInteger style, NSWindow *win, id delegate, SEL didEnd, void *ctx) {
  NSAlert *a = [[[NSAlert alloc] init] autorelease]; [a setMessageText:title ?: @""]; [a setInformativeText:msg ?: @""]; [a setAlertStyle:style];
  [a addButtonWithTitle:def ?: @"OK"]; if (alt) [a addButtonWithTitle:alt]; if (other) [a addButtonWithTitle:other];
  NSInteger r = [a runModal]; NSInteger mapped = r == 1000 ? 1 : r == 1001 ? 0 : -1;   /* NSAlertDefault / Alternate / OtherReturn */
  if (delegate && didEnd) ((void (*)(id, SEL, id, NSInteger, void *))objc_msgSend)(delegate, didEnd, a, mapped, ctx);
  return mapped; }
static NSString *XEFFormat(NSString *f, va_list ap) { return f ? [[[NSString alloc] initWithFormat:f arguments:ap] autorelease] : nil; }
NSInteger NSRunAlertPanel(NSString *t, NSString *f, NSString *d, NSString *a, NSString *o, ...) { va_list ap; va_start(ap, o); NSString *m = XEFFormat(f, ap); va_end(ap); return XEFRunAlert(t, m, d, a, o, 0, nil, nil, NULL, NULL); }
NSInteger NSRunInformationalAlertPanel(NSString *t, NSString *f, NSString *d, NSString *a, NSString *o, ...) { va_list ap; va_start(ap, o); NSString *m = XEFFormat(f, ap); va_end(ap); return XEFRunAlert(t, m, d, a, o, 1, nil, nil, NULL, NULL); }
NSInteger NSRunCriticalAlertPanel(NSString *t, NSString *f, NSString *d, NSString *a, NSString *o, ...) { va_list ap; va_start(ap, o); NSString *m = XEFFormat(f, ap); va_end(ap); return XEFRunAlert(t, m, d, a, o, 2, nil, nil, NULL, NULL); }
NSInteger NSRunAlertPanelRelativeToWindow(NSString *t, NSString *f, NSString *d, NSString *a, NSString *o, NSWindow *w, ...) { va_list ap; va_start(ap, w); NSString *m = XEFFormat(f, ap); va_end(ap); return XEFRunAlert(t, m, d, a, o, 0, w, nil, NULL, NULL); }
NSInteger NSRunInformationalAlertPanelRelativeToWindow(NSString *t, NSString *f, NSString *d, NSString *a, NSString *o, NSWindow *w, ...) { va_list ap; va_start(ap, w); NSString *m = XEFFormat(f, ap); va_end(ap); return XEFRunAlert(t, m, d, a, o, 1, w, nil, NULL, NULL); }
NSInteger NSRunCriticalAlertPanelRelativeToWindow(NSString *t, NSString *f, NSString *d, NSString *a, NSString *o, NSWindow *w, ...) { va_list ap; va_start(ap, w); NSString *m = XEFFormat(f, ap); va_end(ap); return XEFRunAlert(t, m, d, a, o, 2, w, nil, NULL, NULL); }
void NSBeginAlertSheet(NSString *t, NSString *d, NSString *a, NSString *o, NSWindow *w, id md, SEL didEnd, SEL didDismiss, void *ctx, NSString *f, ...) { va_list ap; va_start(ap, f); NSString *m = XEFFormat(f, ap); va_end(ap); XEFRunAlert(t, m, d, a, o, 0, w, md, didEnd, ctx); }
void NSBeginInformationalAlertSheet(NSString *t, NSString *d, NSString *a, NSString *o, NSWindow *w, id md, SEL didEnd, SEL didDismiss, void *ctx, NSString *f, ...) { va_list ap; va_start(ap, f); NSString *m = XEFFormat(f, ap); va_end(ap); XEFRunAlert(t, m, d, a, o, 1, w, md, didEnd, ctx); }
void NSBeginCriticalAlertSheet(NSString *t, NSString *d, NSString *a, NSString *o, NSWindow *w, id md, SEL didEnd, SEL didDismiss, void *ctx, NSString *f, ...) { va_list ap; va_start(ap, f); NSString *m = XEFFormat(f, ap); va_end(ap); XEFRunAlert(t, m, d, a, o, 2, w, md, didEnd, ctx); }
id NSGetAlertPanel(NSString *t, NSString *f, NSString *d, NSString *a, NSString *o, ...) { return nil; } id NSGetInformationalAlertPanel(NSString *t, NSString *f, NSString *d, NSString *a, NSString *o, ...) { return nil; } id NSGetCriticalAlertPanel(NSString *t, NSString *f, NSString *d, NSString *a, NSString *o, ...) { return nil; }
void NSReleaseAlertPanel(id panel) {}

/* ---- window lists and screen updates ---- */
void NSCountWindows(NSInteger *count) { NSInteger n = 0; for (NSWindow *w in [NSApp windows]) if ([w isVisible]) n++; if (count) *count = n; }
void NSCountWindowsForContext(NSInteger ctx, NSInteger *count) { NSCountWindows(count); }
void NSWindowList(NSInteger size, NSInteger list[]) { NSInteger i = 0; for (NSWindow *w in [[NSApp windows] reverseObjectEnumerator]) if ([w isVisible] && i < size) list[i++] = [w windowNumber]; }
void NSWindowListForContext(NSInteger ctx, NSInteger size, NSInteger list[]) { NSWindowList(size, list); }
void NSDisableScreenUpdates(void) {} void NSEnableScreenUpdates(void) {} BOOL NSApplicationLoad(void) { return YES; }
NSInteger NSGetWindowServerMemory(NSInteger ctx, NSInteger *vm, NSInteger *wm, NSString **dump) { if (vm) *vm = 0; if (wm) *wm = 0; if (dump) *dump = @""; return 0; }

/* ---- depths and interface style ---- */
static const NSWindowDepth kDepths[] = { 0x2200 /* 24-bit RGB */, 0x2220 /* 32-bit RGB */, 0 };
const NSWindowDepth *NSAvailableWindowDepths(void) { return kDepths; }
NSWindowDepth NSBestDepth(NSString *cs, NSInteger bps, NSInteger bpp, BOOL planar, BOOL *exact) { if (exact) *exact = YES; return bps > 8 ? 0x2220 : 0x2200; }
NSInteger NSInterfaceStyleForKey(NSString *key, NSResponder *r) { return 3; }
BOOL NSIsControllerMarker(id o) { return o && ([o isKindOfClass:NSClassFromString(@"NSBindingSelectionMarker")] || [o isEqual:@"NSMultipleValuesMarker"] || [o isEqual:@"NSNoSelectionMarker"] || [o isEqual:@"NSNotApplicableMarker"] || [[o description] hasPrefix:@"NSControllerMarker"]); }

/* ---- pasteboard type helpers ---- */
NSString *NSCreateFilenamePboardType(NSString *t) { return t ? [@"NSTypedFilenamesPboardType:" stringByAppendingString:t] : nil; }
NSString *NSCreateFileContentsPboardType(NSString *t) { return t ? [@"NXTypedFileContentsPboardType:" stringByAppendingString:t] : nil; }
NSString *NSGetFileType(NSString *p) { for (NSString *pre in @[@"NSTypedFilenamesPboardType:", @"NXTypedFileContentsPboardType:"]) if ([p hasPrefix:pre]) return [p substringFromIndex:[pre length]]; return nil; }
NSArray *NSGetFileTypes(NSArray *ps) { NSMutableArray *r = [NSMutableArray array]; for (NSString *p in ps) { NSString *t = NSGetFileType(p); if (t && ![r containsObject:t]) [r addObject:t]; } return [r count] ? r : nil; }

/* ---- drawing helpers ---- */
NSRect NSDrawTiledRects(NSRect b, NSRect clip, const NSRectEdge *sides, const CGFloat *grays, NSInteger count) {
  NSRect r = b;
  for (NSInteger i = 0; i < count; i++) {
    NSRect line, rest; NSDivideRect(r, &line, &rest, 1, sides[i]); NSRect d = NSIntersectionRect(line, clip);
    if (!NSIsEmptyRect(d)) { [[NSColor colorWithCalibratedWhite:grays[i] alpha:1] set]; NSRectFill(d); } r = rest; }
  return r; }
NSRect NSDrawColorTiledRects(NSRect b, NSRect clip, const NSRectEdge *sides, NSColor **colors, NSInteger count) {
  NSRect r = b;
  for (NSInteger i = 0; i < count; i++) {
    NSRect line, rest; NSDivideRect(r, &line, &rest, 1, sides[i]); NSRect d = NSIntersectionRect(line, clip);
    if (!NSIsEmptyRect(d)) { [colors[i] set]; NSRectFill(d); } r = rest; }
  return r; }
void NSRectFillListWithGrays(const NSRect *rects, const CGFloat *grays, NSInteger n) { for (NSInteger i = 0; i < n; i++) { [[NSColor colorWithCalibratedWhite:grays[i] alpha:1] set]; NSRectFill(rects[i]); } }
void NSRectFillListWithColorsUsingOperation(const NSRect *rects, NSColor *const *colors, NSInteger n, NSUInteger op) { for (NSInteger i = 0; i < n; i++) { [colors[i] set]; NSRectFillUsingOperation(rects[i], op); } }
static void XEFDrawImage(NSImage *i, NSRect r, NSUInteger op, CGFloat f, BOOL flipped) { if (i && !NSIsEmptyRect(r)) [i drawInRect:r fromRect:NSZeroRect operation:op fraction:f respectFlipped:flipped hints:nil]; }
void NSDrawThreePartImage(NSRect frame, NSImage *start, NSImage *center, NSImage *end, BOOL vertical, NSUInteger op, CGFloat alpha, BOOL flipped) {
  NSSize s = start ? [start size] : NSZeroSize, e = end ? [end size] : NSZeroSize;
  if (vertical) { CGFloat sh = s.height, eh = e.height; NSRect a = NSMakeRect(frame.origin.x, frame.origin.y, frame.size.width, sh), c = NSMakeRect(frame.origin.x, frame.origin.y + sh, frame.size.width, frame.size.height - sh - eh), b = NSMakeRect(frame.origin.x, NSMaxY(frame) - eh, frame.size.width, eh);
    if (flipped) { XEFDrawImage(start, a, op, alpha, flipped); XEFDrawImage(end, b, op, alpha, flipped); } else { XEFDrawImage(start, b, op, alpha, flipped); XEFDrawImage(end, a, op, alpha, flipped); } XEFDrawImage(center, c, op, alpha, flipped); }
  else { CGFloat sw = s.width, ew = e.width; NSRect a = NSMakeRect(frame.origin.x, frame.origin.y, sw, frame.size.height), c = NSMakeRect(frame.origin.x + sw, frame.origin.y, frame.size.width - sw - ew, frame.size.height), b = NSMakeRect(NSMaxX(frame) - ew, frame.origin.y, ew, frame.size.height);
    XEFDrawImage(start, a, op, alpha, flipped); XEFDrawImage(center, c, op, alpha, flipped); XEFDrawImage(end, b, op, alpha, flipped); } }
void NSDrawNinePartImage(NSRect f, NSImage *tl, NSImage *te, NSImage *tr, NSImage *le, NSImage *ce, NSImage *re, NSImage *bl, NSImage *be, NSImage *br, NSUInteger op, CGFloat alpha, BOOL flipped) {
  CGFloat lw = tl ? [tl size].width : (le ? [le size].width : 0), rw = tr ? [tr size].width : (re ? [re size].width : 0), th = tl ? [tl size].height : (te ? [te size].height : 0), bh = bl ? [bl size].height : (be ? [be size].height : 0);
  CGFloat topY = flipped ? f.origin.y : NSMaxY(f) - th, botY = flipped ? NSMaxY(f) - bh : f.origin.y, midY = flipped ? f.origin.y + th : f.origin.y + bh, midH = f.size.height - th - bh, midX = f.origin.x + lw, midW = f.size.width - lw - rw;
  XEFDrawImage(tl, NSMakeRect(f.origin.x, topY, lw, th), op, alpha, flipped); XEFDrawImage(te, NSMakeRect(midX, topY, midW, th), op, alpha, flipped); XEFDrawImage(tr, NSMakeRect(NSMaxX(f) - rw, topY, rw, th), op, alpha, flipped);
  XEFDrawImage(le, NSMakeRect(f.origin.x, midY, lw, midH), op, alpha, flipped); XEFDrawImage(ce, NSMakeRect(midX, midY, midW, midH), op, alpha, flipped); XEFDrawImage(re, NSMakeRect(NSMaxX(f) - rw, midY, rw, midH), op, alpha, flipped);
  XEFDrawImage(bl, NSMakeRect(f.origin.x, botY, lw, bh), op, alpha, flipped); XEFDrawImage(be, NSMakeRect(midX, botY, midW, bh), op, alpha, flipped); XEFDrawImage(br, NSMakeRect(NSMaxX(f) - rw, botY, rw, bh), op, alpha, flipped); }
void NSDrawBitmap(NSRect r, NSInteger w, NSInteger h, NSInteger bps, NSInteger spp, NSInteger bpp, NSInteger bpr, BOOL planar, BOOL alpha, NSString *cs, const unsigned char *const data[5]) {
  if (planar || !data || !data[0] || bps != 8) return;
  NSBitmapImageRep *b = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:(unsigned char **)data pixelsWide:w pixelsHigh:h bitsPerSample:bps samplesPerPixel:spp hasAlpha:alpha isPlanar:NO colorSpaceName:cs bitmapFormat:alpha ? NSBitmapFormatAlphaNonpremultiplied : 0 bytesPerRow:bpr bitsPerPixel:bpp];
  [b drawInRect:r]; [b release]; }
void NSCopyBits(NSInteger gstate, NSRect src, NSPoint dest) {}
NSColor *NSReadPixel(NSPoint p) {
  CGContextRef c = XEFCurrentCGContext(); if (!c) return nil; unsigned char *d = CGBitmapContextGetData(c); if (!d) return nil;
  size_t w = CGBitmapContextGetWidth(c), h = CGBitmapContextGetHeight(c), bpr = CGBitmapContextGetBytesPerRow(c); if (p.x < 0 || p.y < 0 || p.x >= w || p.y >= h) return nil;
  CGContextFlush(c); const unsigned char *q = d + (size_t)(h - 1 - (size_t)p.y) * bpr + (size_t)p.x * 4; CGFloat a = q[3] / 255.0; if (a <= 0) return [NSColor clearColor];
  return [NSColor colorWithCalibratedRed:MIN(1, q[0] / 255.0 / a) green:MIN(1, q[1] / 255.0 / a) blue:MIN(1, q[2] / 255.0 / a) alpha:a]; }
NSInteger NSConvertGlyphsToPackedGlyphs(NSGlyph *gl, NSInteger count, NSInteger packing, char *out) { NSInteger n = 0; for (NSInteger i = 0; i < count; i++) { out[n++] = (char)(gl[i] >> 8); out[n++] = (char)gl[i]; } return n; }

/* ---- OpenGL global options and services ---- */
static int g_gl_options[2048];
void NSOpenGLSetOption(int pname, int param) { if (pname >= 0 && pname < 2048) g_gl_options[pname] = param; } void NSOpenGLGetOption(int pname, int *param) { if (param) *param = (pname >= 0 && pname < 2048) ? g_gl_options[pname] : 0; }
void NSOpenGLGetVersion(int *major, int *minor) { if (major) *major = 1; if (minor) *minor = 2; }
static NSMutableDictionary *g_service_items;
NSInteger NSSetShowsServicesMenuItem(NSString *n, BOOL f) { if (!g_service_items) g_service_items = [[NSMutableDictionary alloc] init]; g_service_items[n] = [NSNumber numberWithBool:f]; return 0; }
BOOL NSShowsServicesMenuItem(NSString *n) { NSNumber *v = g_service_items[n]; return v ? [v boolValue] : YES; }
void NSRegisterServicesProvider(id p, NSString *name) {} void NSUnregisterServicesProvider(NSString *name) {} void NSUpdateDynamicServices(void) {} BOOL NSPerformService(NSString *n, NSPasteboard *pb) { return NO; }

/* ---- accessibility helpers ---- */
static NSString *XEFAXWords(NSString *s) {
  if ([s hasPrefix:@"AX"]) s = [s substringFromIndex:2]; NSMutableString *r = [NSMutableString string];
  for (NSUInteger i = 0; i < [s length]; i++) { unichar c = [s characterAtIndex:i]; if (isupper(c) && i > 0) [r appendString:@" "]; [r appendFormat:@"%C", (unichar)tolower(c)]; }
  return r; }
NSString *NSAccessibilityRoleDescription(NSString *role, NSString *sub) { return role ? XEFAXWords(sub ?: role) : nil; }
NSString *NSAccessibilityRoleDescriptionForUIElement(id e) { return [e respondsToSelector:@selector(accessibilityRole)] ? XEFAXWords([e accessibilityRole]) : nil; }
NSString *NSAccessibilityActionDescription(NSString *a) { return a ? XEFAXWords(a) : nil; }
NSRect NSAccessibilityFrameInView(NSView *v, NSRect f) { return v ? [v convertRect:f toView:nil] : f; } NSPoint NSAccessibilityPointInView(NSView *v, NSPoint p) { return v ? [v convertPoint:p toView:nil] : p; }
void NSAccessibilityPostNotification(id e, NSString *n) {} void NSAccessibilityPostNotificationWithUserInfo(id e, NSString *n, NSDictionary *u) {}
void NSAccessibilityRaiseBadArgumentException(id e, NSString *a, id v) { [NSException raise:NSInvalidArgumentException format:@"bad argument for attribute %@", a]; }
BOOL NSAccessibilitySetMayContainProtectedContent(BOOL f) { return NO; }
static BOOL XEFIsAXElement(id o) { return [o isKindOfClass:[NSView class]] || [o isKindOfClass:[NSCell class]] || [o isKindOfClass:[NSWindow class]] || [o isKindOfClass:[NSApplication class]]; }
id NSAccessibilityUnignoredAncestor(id e) { return XEFIsAXElement(e) ? e : nil; } id NSAccessibilityUnignoredDescendant(id e) { return XEFIsAXElement(e) ? e : nil; }
NSArray *NSAccessibilityUnignoredChildren(NSArray *a) { NSMutableArray *r = [NSMutableArray array]; for (id o in a) if (XEFIsAXElement(o)) [r addObject:o]; return r; }
NSArray *NSAccessibilityUnignoredChildrenForOnlyChild(id c) { return XEFIsAXElement(c) ? @[c] : @[]; }
