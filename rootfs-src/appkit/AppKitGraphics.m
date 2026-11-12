/* AppKit-lite 2D drawing: NSGraphicsContext, NSBezierPath, NSColor/NSFont/NSParagraphStyle, string drawing, NSImage
 * drawing, view geometry (flipped coordinates, bounds) and the window backing store.
 *
 * A window without GL/Metal content is presented from a premultiplied-BGRA CGBitmapContext (CoreGraphics-lite, drawn by
 * the host's cairo): -[NSWindow _xefRedraw] paints the background, walks the view tree (frame/bounds/flipped transforms,
 * clip to bounds, drawRect:) and hands the pixels to xef_host_present_pixels. Text is laid out by the host (pango) through
 * XEFTextLayout, which maps NSAttributedString attributes and UTF-16 indices to the host's UTF-8 layout. */
#import "AppKitLite.h"
#import "AppKitGraphics.h"
#include "xef_host.h"
#include <objc/runtime.h>
#include <objc/message.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* CALayer properties AppKit-lite draws (QuartzCore-lite) */
@protocol XEFLayerLike
- (CGColorRef)backgroundColor; - (CGFloat)cornerRadius; - (CGFloat)borderWidth; - (CGColorRef)borderColor;
@end

/* ---- text attribute names ----------------------------------------------------------------------------------------- */
NSString *const NSFontAttributeName = @"NSFont";
NSString *const NSForegroundColorAttributeName = @"NSColor";
NSString *const NSBackgroundColorAttributeName = @"NSBackgroundColor";
NSString *const NSParagraphStyleAttributeName = @"NSParagraphStyle";
NSString *const NSUnderlineStyleAttributeName = @"NSUnderline";
NSString *const NSUnderlineColorAttributeName = @"NSUnderlineColor";
NSString *const NSStrikethroughStyleAttributeName = @"NSStrikethrough";
NSString *const NSStrikethroughColorAttributeName = @"NSStrikethroughColor";
NSString *const NSKernAttributeName = @"NSKern";
NSString *const NSLigatureAttributeName = @"NSLigature";
NSString *const NSBaselineOffsetAttributeName = @"NSBaselineOffset";
NSString *const NSSuperscriptAttributeName = @"NSSuperScript";
NSString *const NSLinkAttributeName = @"NSLink";
NSString *const NSAttachmentAttributeName = @"NSAttachment";
NSString *const NSShadowAttributeName = @"NSShadow";
NSString *const NSObliquenessAttributeName = @"NSObliqueness";
NSString *const NSExpansionAttributeName = @"NSExpansion";
NSString *const NSStrokeWidthAttributeName = @"NSStrokeWidth";
NSString *const NSStrokeColorAttributeName = @"NSStrokeColor";
NSString *const NSToolTipAttributeName = @"NSToolTip";
NSString *const NSCursorAttributeName = @"NSCursor";
NSString *const NSTextEffectAttributeName = @"NSTextEffect";
NSString *const NSWritingDirectionAttributeName = @"NSWritingDirection";
NSString *const NSVerticalGlyphFormAttributeName = @"CTVerticalForms";
NSString *const NSMarkedClauseSegmentAttributeName = @"NSMarkedClauseSegment";
NSString *const NSSpellingStateAttributeName = @"NSSpellingState";
NSString *const NSGlyphInfoAttributeName = @"NSGlyphInfo";
NSString *const NSTextAlternativesAttributeName = @"NSTextAlternatives";
NSString *const NSTextEffectLetterpressStyle = @"_UIKitNewLetterpressStyle";
NSString *const NSFontFamilyAttribute = @"NSFontFamilyAttribute";
NSString *const NSFontNameAttribute = @"NSFontNameAttribute";
NSString *const NSFontFaceAttribute = @"NSFontFaceAttribute";
NSString *const NSFontSizeAttribute = @"NSFontSizeAttribute";
NSString *const NSFontTraitsAttribute = @"NSCTFontTraitsAttribute";
NSString *const NSFontWeightTrait = @"NSCTFontWeightTrait";
NSString *const NSFontSymbolicTrait = @"NSCTFontSymbolicTrait";
NSString *const NSFontFixedAdvanceAttribute = @"NSCTFontFixedAdvanceAttribute";
NSString *const NSFontFeatureSettingsAttribute = @"NSCTFontFeatureSettingsAttribute";
NSString *const NSFontColorAttribute = @"NSColor";
NSString *const NSFontVisibleNameAttribute = @"NSFontVisibleNameAttribute";
NSString *const NSFontMatrixAttribute = @"NSFontMatrixAttribute";
const CGFloat NSFontWeightUltraLight = -0.8, NSFontWeightThin = -0.6, NSFontWeightLight = -0.4, NSFontWeightRegular = 0,
              NSFontWeightMedium = 0.23, NSFontWeightSemibold = 0.3, NSFontWeightBold = 0.4, NSFontWeightHeavy = 0.56, NSFontWeightBlack = 0.62;

/* ================================================================== NSGraphicsContext */
@implementation NSGraphicsContext
static NSGraphicsContext *g_gc;
static NSMutableArray *g_gc_stack;
+ (NSGraphicsContext *)currentContext { return g_gc; }
+ (void)setCurrentContext:(NSGraphicsContext *)c { [c retain]; [g_gc release]; g_gc = c; }
+ (BOOL)currentContextDrawingToScreen { return YES; }
+ (NSGraphicsContext *)graphicsContextWithCGContext:(CGContextRef)c flipped:(BOOL)f {
  NSGraphicsContext *g = [[[self alloc] init] autorelease];
  g->_cg = c ? CGContextRetain(c) : NULL; g->_flipped = f; g->_op = 2; g->_aa = YES; return g; }
+ (NSGraphicsContext *)graphicsContextWithGraphicsPort:(void *)p flipped:(BOOL)f { return [self graphicsContextWithCGContext:(CGContextRef)p flipped:f]; }
+ (NSGraphicsContext *)graphicsContextWithWindow:(NSWindow *)w {
  [w _xefBacking]; return [self graphicsContextWithCGContext:(CGContextRef)w->_backing flipped:NO]; }
+ (NSGraphicsContext *)graphicsContextWithBitmapImageRep:(NSBitmapImageRep *)r {
  CGContextRef c = [r _xefCreateContext];
  NSGraphicsContext *g = [self graphicsContextWithCGContext:c flipped:NO];
  objc_setAssociatedObject(g, "xef.bitmapgc", @YES, OBJC_ASSOCIATION_RETAIN);   /* flushed into the rep's pixels when it stops being current */
  CGContextRelease(c); return g; }
+ (NSGraphicsContext *)graphicsContextWithAttributes:(NSDictionary *)a { return nil; }
+ (void)saveGraphicsState {
  if (!g_gc_stack) g_gc_stack = [[NSMutableArray alloc] init];
  [g_gc_stack addObject:g_gc ? (id)g_gc : (id)[NSNull null]];
  [g_gc saveGraphicsState]; }
+ (void)restoreGraphicsState {
  if (![g_gc_stack count]) return;
  if (g_gc && g_gc->_cg && objc_getAssociatedObject(g_gc, "xef.bitmapgc")) CGContextFlush(g_gc->_cg);
  id top = [[[g_gc_stack lastObject] retain] autorelease]; [g_gc_stack removeLastObject];
  [self setCurrentContext:top == [NSNull null] ? nil : top];
  [g_gc restoreGraphicsState]; }
- (CGContextRef)CGContext { return _cg; }
- (void *)graphicsPort { return _cg; }
- (BOOL)isFlipped { return _flipped; }
- (BOOL)isDrawingToScreen { return YES; }
- (NSDictionary *)attributes { return nil; }
- (void)saveGraphicsState { CGContextSaveGState(_cg); }
- (void)restoreGraphicsState { CGContextRestoreGState(_cg); }
- (void)flushGraphics { CGContextFlush(_cg); }
- (NSUInteger)compositingOperation { return _op; }
- (void)setCompositingOperation:(NSUInteger)o { _op = o; CGContextSetBlendMode(_cg, XEFBlendModeForOperation(o)); }
- (NSInteger)imageInterpolation { return _interp; }
- (void)setImageInterpolation:(NSInteger)i { _interp = i; CGContextSetInterpolationQuality(_cg, (CGInterpolationQuality)i); }
- (BOOL)shouldAntialias { return _aa; }
- (void)setShouldAntialias:(BOOL)f { _aa = f; CGContextSetShouldAntialias(_cg, f); }
- (NSInteger)colorRenderingIntent { return 0; } - (void)setColorRenderingIntent:(NSInteger)i {}
- (NSPoint)patternPhase { return NSZeroPoint; } - (void)setPatternPhase:(NSPoint)p {}
- (id)focusStack { return nil; } - (void)setFocusStack:(id)s {}
- (void)dealloc { if (_cg) CGContextRelease(_cg); [super dealloc]; }
@end

CGBlendMode XEFBlendModeForOperation(NSUInteger op) {
  switch (op) {   /* NSCompositingOperation -> CGBlendMode */
  case 0: return kCGBlendModeClear; case 1: return kCGBlendModeCopy; case 2: return kCGBlendModeNormal;
  case 3: return kCGBlendModeSourceIn; case 4: return kCGBlendModeSourceOut; case 5: return kCGBlendModeSourceAtop;
  case 6: return kCGBlendModeDestinationOver; case 7: return kCGBlendModeDestinationIn; case 8: return kCGBlendModeDestinationOut;
  case 9: return kCGBlendModeDestinationAtop; case 10: return kCGBlendModeXOR; case 11: return kCGBlendModePlusDarker;
  case 13: return kCGBlendModePlusLighter; case 14: return kCGBlendModeMultiply; case 15: return kCGBlendModeScreen;
  case 16: return kCGBlendModeOverlay; case 17: return kCGBlendModeDarken; case 18: return kCGBlendModeLighten;
  case 19: return kCGBlendModeColorDodge; case 20: return kCGBlendModeColorBurn; case 21: return kCGBlendModeSoftLight;
  case 22: return kCGBlendModeHardLight; case 23: return kCGBlendModeDifference; case 24: return kCGBlendModeExclusion;
  case 25: return kCGBlendModeHue; case 26: return kCGBlendModeSaturation; case 27: return kCGBlendModeColor;
  case 28: return kCGBlendModeLuminosity;
  default: return kCGBlendModeNormal; } }

CGContextRef XEFCurrentCGContext(void) { return g_gc ? g_gc->_cg : NULL; }

/* ---- NSRect drawing functions ---------------------------------------------------------------------------------------- */
void NSRectFillUsingOperation(NSRect r, NSUInteger op) {
  CGContextRef c = XEFCurrentCGContext(); if (!c) return;
  CGContextSaveGState(c); CGContextSetBlendMode(c, XEFBlendModeForOperation(op)); CGContextFillRect(c, r); CGContextRestoreGState(c); }
void NSRectFill(NSRect r) { NSRectFillUsingOperation(r, 1 /*copy*/); }
void NSRectFillList(const NSRect *r, NSInteger n) { for (NSInteger i = 0; i < n; i++) NSRectFill(r[i]); }
void NSRectFillListUsingOperation(const NSRect *r, NSInteger n, NSUInteger op) { for (NSInteger i = 0; i < n; i++) NSRectFillUsingOperation(r[i], op); }
void NSRectFillListWithColors(const NSRect *r, NSColor *const *c, NSInteger n) { for (NSInteger i = 0; i < n; i++) { [c[i] setFill]; NSRectFill(r[i]); } }
void NSFrameRectWithWidthUsingOperation(NSRect r, CGFloat w, NSUInteger op) {
  if (r.size.width <= 0 || r.size.height <= 0) return;
  NSRect s[4] = { NSMakeRect(r.origin.x, r.origin.y, r.size.width, w), NSMakeRect(r.origin.x, r.origin.y + r.size.height - w, r.size.width, w),
                  NSMakeRect(r.origin.x, r.origin.y + w, w, r.size.height - 2 * w), NSMakeRect(r.origin.x + r.size.width - w, r.origin.y + w, w, r.size.height - 2 * w) };
  for (int i = 0; i < 4; i++) NSRectFillUsingOperation(s[i], op); }
void NSFrameRectWithWidth(NSRect r, CGFloat w) { NSFrameRectWithWidthUsingOperation(r, w, 2); }
void NSFrameRect(NSRect r) { NSFrameRectWithWidth(r, 1); }
void NSEraseRect(NSRect r) { CGContextRef c = XEFCurrentCGContext(); if (!c) return; CGContextSaveGState(c); CGContextSetRGBFillColor(c, 1, 1, 1, 1); CGContextFillRect(c, r); CGContextRestoreGState(c); }
void NSRectClip(NSRect r) { CGContextRef c = XEFCurrentCGContext(); if (c) CGContextClipToRect(c, r); }
void NSRectClipList(const NSRect *r, NSInteger n) { CGContextRef c = XEFCurrentCGContext(); if (c) CGContextClipToRects(c, (const CGRect *)r, n); }
void NSDrawWindowBackground(NSRect r) { [[NSColor windowBackgroundColor] setFill]; NSRectFill(r); }
void NSDottedFrameRect(NSRect r) { NSFrameRect(r); }
void NSDrawGroove(NSRect r, NSRect clip) { [[NSColor gridColor] setFill]; NSFrameRect(r); }
void NSDrawWhiteBezel(NSRect r, NSRect clip) { [[NSColor whiteColor] setFill]; NSRectFill(r); [[NSColor gridColor] setFill]; NSFrameRect(r); }
void NSDrawButton(NSRect r, NSRect clip) { [[NSColor controlColor] setFill]; NSRectFill(r); [[NSColor gridColor] setFill]; NSFrameRect(r); }
void NSDrawGrayBezel(NSRect r, NSRect clip) { NSDrawButton(r, clip); }
void NSDrawLightBezel(NSRect r, NSRect clip) { NSDrawWhiteBezel(r, clip); }
void NSDrawDarkBezel(NSRect r, NSRect clip) { NSDrawButton(r, clip); }
void NSHighlightRect(NSRect r) { [[NSColor selectedControlColor] setFill]; NSRectFillUsingOperation(r, 2); }
void NSSetFocusRingStyle(NSUInteger placement) {}
void NSShowAnimationEffect(NSUInteger e, NSPoint p, NSSize s, id d, SEL sel, void *ctx) {}

/* ================================================================== NSColor drawing / more colours */
@implementation NSColor (XEFDrawing)
+ (BOOL)supportsSecureCoding { return YES; }
- (void)set { [self setFill]; [self setStroke]; }
- (void)setFill { CGContextRef c = XEFCurrentCGContext(); if (c) CGContextSetRGBFillColor(c, r, g, b, a); }
- (void)setStroke { CGContextRef c = XEFCurrentCGContext(); if (c) CGContextSetRGBStrokeColor(c, r, g, b, a); }
- (CGColorRef)CGColor {
  CGColorRef c = (CGColorRef)objc_getAssociatedObject(self, "xef.cgcolor");
  if (!c) { c = CGColorCreateGenericRGB(r, g, b, a); objc_setAssociatedObject(self, "xef.cgcolor", (id)c, OBJC_ASSOCIATION_RETAIN); CGColorRelease(c); }
  return c; }
+ (NSColor *)colorWithCGColor:(CGColorRef)c {
  const CGFloat *v = CGColorGetComponents(c); size_t n = CGColorGetNumberOfComponents(c);
  if (n == 2) return [self colorWithCalibratedRed:v[0] green:v[0] blue:v[0] alpha:v[1]];
  if (n >= 4) return [self colorWithCalibratedRed:v[0] green:v[1] blue:v[2] alpha:v[n - 1]];
  return [self blackColor]; }
+ (NSColor *)colorWithSRGBRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a { return [self colorWithCalibratedRed:r green:g blue:b alpha:a]; }
+ (NSColor *)colorWithDeviceRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a { return [self colorWithCalibratedRed:r green:g blue:b alpha:a]; }
+ (NSColor *)colorWithDisplayP3Red:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a { return [self colorWithCalibratedRed:r green:g blue:b alpha:a]; }
+ (NSColor *)colorWithDeviceWhite:(CGFloat)w alpha:(CGFloat)a { return [self colorWithCalibratedRed:w green:w blue:w alpha:a]; }
+ (NSColor *)colorWithGenericGamma22White:(CGFloat)w alpha:(CGFloat)a { return [self colorWithCalibratedRed:w green:w blue:w alpha:a]; }
+ (NSColor *)colorWithDeviceCyan:(CGFloat)c magenta:(CGFloat)m yellow:(CGFloat)y black:(CGFloat)k alpha:(CGFloat)a {
  NSColor *col = [self colorWithCalibratedRed:(1 - c) * (1 - k) green:(1 - m) * (1 - k) blue:(1 - y) * (1 - k) alpha:a];
  objc_setAssociatedObject(col, "xef.cmyk", @[@(c), @(m), @(y), @(k)], OBJC_ASSOCIATION_RETAIN); return col; }
+ (NSColor *)colorWithCalibratedHue:(CGFloat)h saturation:(CGFloat)s brightness:(CGFloat)v alpha:(CGFloat)a {
  h = fmod(h, 1.0); if (h < 0) h += 1; h *= 6; int i = (int)floor(h); CGFloat f = h - i, p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f));
  CGFloat rr, gg, bb;
  switch (i) { case 0: rr = v; gg = t; bb = p; break; case 1: rr = q; gg = v; bb = p; break; case 2: rr = p; gg = v; bb = t; break;
               case 3: rr = p; gg = q; bb = v; break; case 4: rr = t; gg = p; bb = v; break; default: rr = v; gg = p; bb = q; break; }
  return [self colorWithCalibratedRed:rr green:gg blue:bb alpha:a]; }
+ (NSColor *)colorWithHue:(CGFloat)h saturation:(CGFloat)s brightness:(CGFloat)v alpha:(CGFloat)a { return [self colorWithCalibratedHue:h saturation:s brightness:v alpha:a]; }
+ (NSColor *)colorWithDeviceHue:(CGFloat)h saturation:(CGFloat)s brightness:(CGFloat)v alpha:(CGFloat)a { return [self colorWithCalibratedHue:h saturation:s brightness:v alpha:a]; }
+ (NSColor *)colorWithColorSpace:(id)space components:(const CGFloat *)c count:(NSInteger)n {
  if (n == 2) return [self colorWithCalibratedRed:c[0] green:c[0] blue:c[0] alpha:c[1]];
  if (n >= 4) return [self colorWithCalibratedRed:c[0] green:c[1] blue:c[2] alpha:c[3]];
  return [self blackColor]; }
+ (NSColor *)colorWithName:(NSString *)n dynamicProvider:(NSColor *(^)(id))p { NSColor *c = p ? p(nil) : nil; return c ? c : [self blackColor]; }
+ (NSColor *)redColor { return [self colorWithCalibratedRed:1 green:0 blue:0 alpha:1]; }
+ (NSColor *)greenColor { return [self colorWithCalibratedRed:0 green:1 blue:0 alpha:1]; }
+ (NSColor *)blueColor { return [self colorWithCalibratedRed:0 green:0 blue:1 alpha:1]; }
+ (NSColor *)yellowColor { return [self colorWithCalibratedRed:1 green:1 blue:0 alpha:1]; }
+ (NSColor *)cyanColor { return [self colorWithCalibratedRed:0 green:1 blue:1 alpha:1]; }
+ (NSColor *)magentaColor { return [self colorWithCalibratedRed:1 green:0 blue:1 alpha:1]; }
+ (NSColor *)orangeColor { return [self colorWithCalibratedRed:1 green:0.5 blue:0 alpha:1]; }
+ (NSColor *)purpleColor { return [self colorWithCalibratedRed:0.5 green:0 blue:0.5 alpha:1]; }
+ (NSColor *)brownColor { return [self colorWithCalibratedRed:0.6 green:0.4 blue:0.2 alpha:1]; }
+ (NSColor *)grayColor { return [self colorWithCalibratedWhite:0.5 alpha:1]; }
+ (NSColor *)lightGrayColor { return [self colorWithCalibratedWhite:2.0 / 3 alpha:1]; }
+ (NSColor *)darkGrayColor { return [self colorWithCalibratedWhite:1.0 / 3 alpha:1]; }
+ (NSColor *)systemRedColor { return [self colorWithCalibratedRed:1 green:0.23 blue:0.19 alpha:1]; }
+ (NSColor *)systemGreenColor { return [self colorWithCalibratedRed:0.16 green:0.8 blue:0.25 alpha:1]; }
+ (NSColor *)systemBlueColor { return [self colorWithCalibratedRed:0 green:0.48 blue:1 alpha:1]; }
+ (NSColor *)systemOrangeColor { return [self colorWithCalibratedRed:1 green:0.58 blue:0 alpha:1]; }
+ (NSColor *)systemYellowColor { return [self colorWithCalibratedRed:1 green:0.8 blue:0 alpha:1]; }
+ (NSColor *)systemPinkColor { return [self colorWithCalibratedRed:1 green:0.18 blue:0.33 alpha:1]; }
+ (NSColor *)systemPurpleColor { return [self colorWithCalibratedRed:0.69 green:0.32 blue:0.87 alpha:1]; }
+ (NSColor *)systemGrayColor { return [self colorWithCalibratedRed:0.56 green:0.56 blue:0.58 alpha:1]; }
+ (NSColor *)systemBrownColor { return [self colorWithCalibratedRed:0.64 green:0.52 blue:0.37 alpha:1]; }
+ (NSColor *)systemTealColor { return [self colorWithCalibratedRed:0.35 green:0.78 blue:0.98 alpha:1]; }
+ (NSColor *)systemIndigoColor { return [self colorWithCalibratedRed:0.35 green:0.34 blue:0.84 alpha:1]; }
+ (NSColor *)systemMintColor { return [self colorWithCalibratedRed:0 green:0.78 blue:0.75 alpha:1]; }
+ (NSColor *)systemCyanColor { return [self colorWithCalibratedRed:0.2 green:0.68 blue:0.9 alpha:1]; }
+ (NSColor *)controlAccentColor { return [self systemBlueColor]; }
+ (NSColor *)textBackgroundColor { return [self whiteColor]; }
+ (NSColor *)selectedTextBackgroundColor { return [self colorWithCalibratedRed:0.7 green:0.84 blue:1 alpha:1]; }
+ (NSColor *)unemphasizedSelectedTextBackgroundColor { return [self colorWithCalibratedWhite:0.86 alpha:1]; }
+ (NSColor *)selectedTextColor { return [self blackColor]; }
+ (NSColor *)unemphasizedSelectedTextColor { return [self blackColor]; }
+ (NSColor *)alternateSelectedControlColor { return [self colorWithCalibratedRed:0 green:0.39 blue:0.88 alpha:1]; }
+ (NSColor *)selectedContentBackgroundColor { return [self alternateSelectedControlColor]; }
+ (NSColor *)unemphasizedSelectedContentBackgroundColor { return [self colorWithCalibratedWhite:0.86 alpha:1]; }
+ (NSColor *)alternateSelectedControlTextColor { return [self whiteColor]; }
+ (NSColor *)keyboardFocusIndicatorColor { return [self colorWithCalibratedRed:0.23 green:0.51 blue:0.96 alpha:0.5]; }
+ (NSColor *)windowFrameColor { return [self colorWithCalibratedWhite:0.67 alpha:1]; }
+ (NSColor *)windowFrameTextColor { return [self blackColor]; }
+ (NSColor *)headerColor { return [self colorWithCalibratedWhite:0.9 alpha:1]; }
+ (NSColor *)headerTextColor { return [self blackColor]; }
+ (NSColor *)highlightColor { return [self whiteColor]; }
+ (NSColor *)shadowColor { return [self blackColor]; }
+ (NSColor *)scrollBarColor { return [self colorWithCalibratedWhite:0.9 alpha:1]; }
+ (NSColor *)knobColor { return [self colorWithCalibratedWhite:0.55 alpha:1]; }
+ (NSColor *)selectedKnobColor { return [self colorWithCalibratedWhite:0.45 alpha:1]; }
+ (NSColor *)controlShadowColor { return [self colorWithCalibratedWhite:0.5 alpha:1]; }
+ (NSColor *)controlDarkShadowColor { return [self colorWithCalibratedWhite:0.2 alpha:1]; }
+ (NSColor *)controlHighlightColor { return [self colorWithCalibratedWhite:0.85 alpha:1]; }
+ (NSColor *)controlLightHighlightColor { return [self whiteColor]; }
+ (NSColor *)underPageBackgroundColor { return [self colorWithCalibratedWhite:0.6 alpha:1]; }
+ (NSColor *)findHighlightColor { return [self yellowColor]; }
+ (NSColor *)quinaryLabelColor { return [self colorWithCalibratedWhite:0 alpha:0.05]; }
+ (NSColor *)systemFillColor { return [self colorWithCalibratedWhite:0 alpha:0.1]; }
+ (NSColor *)secondarySystemFillColor { return [self colorWithCalibratedWhite:0 alpha:0.08]; }
+ (NSColor *)tertiarySystemFillColor { return [self colorWithCalibratedWhite:0 alpha:0.05]; }
+ (NSColor *)quaternarySystemFillColor { return [self colorWithCalibratedWhite:0 alpha:0.03]; }
+ (NSColor *)disabledControlTextColor { return [self colorWithCalibratedWhite:0 alpha:0.25]; }
+ (NSColor *)secondarySelectedControlColor { return [self colorWithCalibratedWhite:0.86 alpha:1]; }
+ (NSArray *)alternatingContentBackgroundColors { return @[[self whiteColor], [self colorWithCalibratedWhite:0.96 alpha:1]]; }
+ (NSArray *)controlAlternatingRowBackgroundColors { return [self alternatingContentBackgroundColors]; }
+ (BOOL)ignoresAlpha { return NO; } + (void)setIgnoresAlpha:(BOOL)f {}
- (NSColor *)colorUsingColorSpaceName:(NSString *)n { return self; }
- (NSColor *)colorUsingColorSpaceName:(NSString *)n device:(NSDictionary *)d { return self; }
- (NSColor *)colorUsingType:(NSInteger)t { return self; }
- (NSInteger)type { return objc_getAssociatedObject(self, "xef.pattern") ? 1 : 0; }
- (NSColor *)colorWithSystemEffect:(NSInteger)e { return self; }
- (NSString *)colorSpaceName { return @"NSCalibratedRGBColorSpace"; }
- (id)colorSpace { return [NSColorSpace sRGBColorSpace]; }
- (NSInteger)numberOfComponents { return 4; }
- (void)getComponents:(CGFloat *)c { c[0] = r; c[1] = g; c[2] = b; c[3] = a; }
- (void)getRed:(CGFloat *)rr green:(CGFloat *)gg blue:(CGFloat *)bb alpha:(CGFloat *)aa { if (rr) *rr = r; if (gg) *gg = g; if (bb) *bb = b; if (aa) *aa = a; }
- (void)getWhite:(CGFloat *)w alpha:(CGFloat *)aa { if (w) *w = (r + g + b) / 3; if (aa) *aa = a; }
- (CGFloat)whiteComponent { return (r + g + b) / 3; }
- (void)getHue:(CGFloat *)h saturation:(CGFloat *)s brightness:(CGFloat *)v alpha:(CGFloat *)aa {
  CGFloat mx = fmax(r, fmax(g, b)), mn = fmin(r, fmin(g, b)), d = mx - mn, hh = 0;
  if (d > 0) { if (mx == r) hh = fmod((g - b) / d, 6); else if (mx == g) hh = (b - r) / d + 2; else hh = (r - g) / d + 4; hh /= 6; if (hh < 0) hh += 1; }
  if (h) *h = hh; if (s) *s = mx > 0 ? d / mx : 0; if (v) *v = mx; if (aa) *aa = a; }
- (CGFloat)hueComponent { CGFloat h; [self getHue:&h saturation:NULL brightness:NULL alpha:NULL]; return h; }
- (CGFloat)saturationComponent { CGFloat s; [self getHue:NULL saturation:&s brightness:NULL alpha:NULL]; return s; }
- (CGFloat)brightnessComponent { CGFloat v; [self getHue:NULL saturation:NULL brightness:&v alpha:NULL]; return v; }
- (NSColor *)blendedColorWithFraction:(CGFloat)f ofColor:(NSColor *)o {
  if (!o) return self; return [NSColor colorWithCalibratedRed:r + (o->r - r) * f green:g + (o->g - g) * f blue:b + (o->b - b) * f alpha:a + (o->a - a) * f]; }
- (NSColor *)highlightWithLevel:(CGFloat)l { return [self blendedColorWithFraction:l ofColor:[NSColor whiteColor]]; }
- (NSColor *)shadowWithLevel:(CGFloat)l { return [self blendedColorWithFraction:l ofColor:[NSColor blackColor]]; }
- (BOOL)isEqual:(id)o {
  if (o == self) return YES; if (![o isKindOfClass:[NSColor class]]) return NO;
  NSColor *c = o; return c->r == r && c->g == g && c->b == b && c->a == a; }
- (NSUInteger)hash { return (NSUInteger)(r * 255) << 24 ^ (NSUInteger)(g * 255) << 16 ^ (NSUInteger)(b * 255) << 8 ^ (NSUInteger)(a * 255); }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSString *)description { return [NSString stringWithFormat:@"NSCalibratedRGBColorSpace %g %g %g %g", r, g, b, a]; }
- (void)encodeWithCoder:(NSCoder *)c {
  [c encodeInt:1 forKey:@"NSColorSpace"];
  NSString *s = [NSString stringWithFormat:@"%g %g %g %g", r, g, b, a];
  NSData *d = [s dataUsingEncoding:NSASCIIStringEncoding];
  [c encodeBytes:[d bytes] length:[d length] forKey:@"NSRGB"]; }
/* keyed archives (nibs, NSKeyedArchiver): NSColorSpace 1/2 RGB ("NSRGB"), 3/4 white ("NSWhite"), 5 CMYK, 6 named */
- (id)initWithCoder:(NSCoder *)c {
  if (![c allowsKeyedCoding]) { [self release]; return [[NSColor blackColor] retain]; }
  int space = [c decodeIntForKey:@"NSColorSpace"];
  NSUInteger len = 0; const uint8_t *bytes = NULL;
  CGFloat v[5] = {0, 0, 0, 1, 1};
  if (space == 1 || space == 2) bytes = [c decodeBytesForKey:@"NSRGB" returnedLength:&len];
  else if (space == 3 || space == 4) bytes = [c decodeBytesForKey:@"NSWhite" returnedLength:&len];
  else if (space == 5) bytes = [c decodeBytesForKey:@"NSCMYK" returnedLength:&len];
  else if (space == 6) {
    NSColor *fallback = [c decodeObjectForKey:@"NSColor"];
    NSString *name = [c decodeObjectForKey:@"NSColorName"];
    NSColor *named = nil;
    SEL sel = name ? NSSelectorFromString(name) : NULL;
    if (sel && [NSColor respondsToSelector:sel] && ![name hasPrefix:@"_"]) named = [NSColor performSelector:sel];
    [self release];
    return [(named ? named : fallback ? fallback : [NSColor blackColor]) retain];
  }
  if (bytes && len) {
    char buf[256]; size_t n = len < sizeof buf - 1 ? len : sizeof buf - 1; memcpy(buf, bytes, n); buf[n] = 0;
    char *p = buf; for (int i = 0; i < 5 && *p; i++) { char *e; double d = strtod(p, &e); if (e == p) break; v[i] = d; p = e; }
  }
  CGFloat rr, gg, bb, aa;
  if (space == 3 || space == 4) { rr = gg = bb = v[0]; aa = len ? (bytes && strchr((const char *)bytes, ' ') ? v[1] : 1) : 1; }
  else if (space == 5) { rr = (1 - v[0]) * (1 - v[3]); gg = (1 - v[1]) * (1 - v[3]); bb = (1 - v[2]) * (1 - v[3]); aa = v[4]; }
  else { rr = v[0]; gg = v[1]; bb = v[2]; aa = v[3]; }
  if ((self = [super init])) { r = rr; g = gg; b = bb; a = aa; }
  return self; }
- (void)drawSwatchInRect:(NSRect)rect { [self setFill]; NSRectFillUsingOperation(rect, 2); }
@end

/* ================================================================== NSBezierPath */
static CGFloat g_default_line_width = 1;
@implementation NSBezierPath
+ (NSBezierPath *)bezierPath { return [[[self alloc] init] autorelease]; }
+ (NSBezierPath *)bezierPathWithRect:(NSRect)r { NSBezierPath *p = [self bezierPath]; [p appendBezierPathWithRect:r]; return p; }
+ (NSBezierPath *)bezierPathWithOvalInRect:(NSRect)r { NSBezierPath *p = [self bezierPath]; [p appendBezierPathWithOvalInRect:r]; return p; }
+ (NSBezierPath *)bezierPathWithRoundedRect:(NSRect)r xRadius:(CGFloat)x yRadius:(CGFloat)y {
  NSBezierPath *p = [self bezierPath]; [p appendBezierPathWithRoundedRect:r xRadius:x yRadius:y]; return p; }
+ (NSBezierPath *)bezierPathWithCGPath:(CGPathRef)cg { NSBezierPath *p = [self bezierPath]; CGPathAddPath(p->_path, NULL, cg); return p; }
+ (void)fillRect:(NSRect)r { CGContextRef c = XEFCurrentCGContext(); if (c) CGContextFillRect(c, r); }
+ (void)strokeRect:(NSRect)r { [[self bezierPathWithRect:r] stroke]; }
+ (void)clipRect:(NSRect)r { NSRectClip(r); }
+ (void)strokeLineFromPoint:(NSPoint)a toPoint:(NSPoint)b { NSBezierPath *p = [self bezierPath]; [p moveToPoint:a]; [p lineToPoint:b]; [p stroke]; }
+ (void)setDefaultLineWidth:(CGFloat)w { g_default_line_width = w; } + (CGFloat)defaultLineWidth { return g_default_line_width; }
+ (void)setDefaultLineCapStyle:(NSInteger)s {} + (void)setDefaultLineJoinStyle:(NSInteger)s {} + (void)setDefaultMiterLimit:(CGFloat)l {}
+ (void)setDefaultFlatness:(CGFloat)f {} + (void)setDefaultWindingRule:(NSInteger)r {}
- (id)init { if ((self = [super init])) { _path = CGPathCreateMutable(); _lineWidth = g_default_line_width; _miter = 10; _flatness = 0.6; } return self; }
- (void)dealloc { CGPathRelease(_path); free(_dash); [super dealloc]; }
- (id)copyWithZone:(NSZone *)z {
  NSBezierPath *p = [[NSBezierPath allocWithZone:z] init];
  CGPathRelease(p->_path); p->_path = CGPathCreateMutableCopy(_path);
  p->_lineWidth = _lineWidth; p->_cap = _cap; p->_join = _join; p->_miter = _miter; p->_winding = _winding; p->_flatness = _flatness;
  if (_ndash) { p->_dash = malloc(_ndash * sizeof(CGFloat)); memcpy(p->_dash, _dash, _ndash * sizeof(CGFloat)); p->_ndash = _ndash; p->_phase = _phase; }
  return p; }
- (CGPathRef)CGPath { return _path; }
- (void)setCGPath:(CGPathRef)p { CGPathRelease(_path); _path = CGPathCreateMutableCopy(p); }
- (void)moveToPoint:(NSPoint)p { CGPathMoveToPoint(_path, NULL, p.x, p.y); }
- (void)lineToPoint:(NSPoint)p { CGPathAddLineToPoint(_path, NULL, p.x, p.y); }
- (void)curveToPoint:(NSPoint)e controlPoint1:(NSPoint)c1 controlPoint2:(NSPoint)c2 { CGPathAddCurveToPoint(_path, NULL, c1.x, c1.y, c2.x, c2.y, e.x, e.y); }
- (void)curveToPoint:(NSPoint)e controlPoint:(NSPoint)c { CGPathAddQuadCurveToPoint(_path, NULL, c.x, c.y, e.x, e.y); }
- (void)closePath { CGPathCloseSubpath(_path); }
- (void)relativeMoveToPoint:(NSPoint)p { NSPoint c = [self currentPoint]; [self moveToPoint:NSMakePoint(c.x + p.x, c.y + p.y)]; }
- (void)relativeLineToPoint:(NSPoint)p { NSPoint c = [self currentPoint]; [self lineToPoint:NSMakePoint(c.x + p.x, c.y + p.y)]; }
- (void)relativeCurveToPoint:(NSPoint)e controlPoint1:(NSPoint)c1 controlPoint2:(NSPoint)c2 {
  NSPoint c = [self currentPoint];
  [self curveToPoint:NSMakePoint(c.x + e.x, c.y + e.y) controlPoint1:NSMakePoint(c.x + c1.x, c.y + c1.y) controlPoint2:NSMakePoint(c.x + c2.x, c.y + c2.y)]; }
- (void)removeAllPoints { CGPathRelease(_path); _path = CGPathCreateMutable(); }
- (void)appendBezierPath:(NSBezierPath *)p { if (p) CGPathAddPath(_path, NULL, p->_path); }
- (void)appendBezierPathWithRect:(NSRect)r { CGPathAddRect(_path, NULL, r); }
- (void)appendBezierPathWithRects:(const NSRect *)r count:(NSInteger)n { CGPathAddRects(_path, NULL, (const CGRect *)r, n); }
- (void)appendBezierPathWithOvalInRect:(NSRect)r { CGPathAddEllipseInRect(_path, NULL, r); }
- (void)appendBezierPathWithRoundedRect:(NSRect)r xRadius:(CGFloat)x yRadius:(CGFloat)y { CGPathAddRoundedRect(_path, NULL, r, x, y); }
- (void)appendBezierPathWithPoints:(const NSPoint *)p count:(NSInteger)n {
  for (NSInteger i = 0; i < n; i++) { if (i == 0 && CGPathIsEmpty(_path)) [self moveToPoint:p[i]]; else [self lineToPoint:p[i]]; } }
/* angles in degrees; NSBezierPath's "clockwise" is the CG flag */
- (void)appendBezierPathWithArcWithCenter:(NSPoint)c radius:(CGFloat)r startAngle:(CGFloat)a0 endAngle:(CGFloat)a1 clockwise:(BOOL)cw {
  CGPathAddArc(_path, NULL, c.x, c.y, r, a0 * M_PI / 180, a1 * M_PI / 180, cw); }
- (void)appendBezierPathWithArcWithCenter:(NSPoint)c radius:(CGFloat)r startAngle:(CGFloat)a0 endAngle:(CGFloat)a1 {
  [self appendBezierPathWithArcWithCenter:c radius:r startAngle:a0 endAngle:a1 clockwise:NO]; }
- (void)appendBezierPathWithArcFromPoint:(NSPoint)p1 toPoint:(NSPoint)p2 radius:(CGFloat)r { CGPathAddArcToPoint(_path, NULL, p1.x, p1.y, p2.x, p2.y, r); }
- (BOOL)isEmpty { return CGPathIsEmpty(_path); }
- (NSPoint)currentPoint { return CGPathGetCurrentPoint(_path); }
- (NSRect)bounds { CGRect r = CGPathGetPathBoundingBox(_path); return CGRectIsNull(r) ? NSZeroRect : r; }
- (NSRect)controlPointBounds { CGRect r = CGPathGetBoundingBox(_path); return CGRectIsNull(r) ? NSZeroRect : r; }
- (BOOL)containsPoint:(NSPoint)p { return CGPathContainsPoint(_path, NULL, p, _winding == 1); }
- (void)transformUsingAffineTransform:(NSAffineTransform *)t {
  NSAffineTransformStruct s = [t transformStruct];
  CGAffineTransform m = CGAffineTransformMake(s.m11, s.m12, s.m21, s.m22, s.tX, s.tY);
  CGMutablePathRef n = CGPathCreateMutableCopyByTransformingPath(_path, &m); CGPathRelease(_path); _path = n; }
- (NSBezierPath *)bezierPathByFlatteningPath { return [[self copy] autorelease]; }
- (NSBezierPath *)bezierPathByReversingPath { return [[self copy] autorelease]; }
static void count_el(void *info, const CGPathElement *e) { (*(NSInteger *)info)++; }
- (NSInteger)elementCount { NSInteger n = 0; CGPathApply(_path, &n, count_el); return n; }
struct el_find { NSInteger want, at; NSInteger type; NSPoint pts[3]; };
static void find_el(void *info, const CGPathElement *e) {
  struct el_find *f = info;
  if (f->at++ != f->want) return;
  int n = e->type == kCGPathElementAddCurveToPoint ? 3 : e->type == kCGPathElementCloseSubpath ? 0 : e->type == kCGPathElementAddQuadCurveToPoint ? 2 : 1;
  for (int i = 0; i < n; i++) f->pts[i] = e->points[i];
  f->type = e->type == kCGPathElementMoveToPoint ? 0 : e->type == kCGPathElementAddLineToPoint ? 1 : e->type == kCGPathElementCloseSubpath ? 3 : 2; }
- (NSInteger)elementAtIndex:(NSInteger)i associatedPoints:(NSPoint *)pts {
  struct el_find f = { i, 0, 3, {{0, 0}} }; CGPathApply(_path, &f, find_el);
  if (pts) { int n = f.type == 2 ? 3 : f.type == 3 ? 0 : 1; for (int k = 0; k < n; k++) pts[k] = f.pts[k]; }
  return f.type; }
- (NSInteger)elementAtIndex:(NSInteger)i { return [self elementAtIndex:i associatedPoints:NULL]; }
- (CGFloat)lineWidth { return _lineWidth; } - (void)setLineWidth:(CGFloat)w { _lineWidth = w; }
- (NSInteger)lineCapStyle { return _cap; } - (void)setLineCapStyle:(NSInteger)s { _cap = s; }
- (NSInteger)lineJoinStyle { return _join; } - (void)setLineJoinStyle:(NSInteger)s { _join = s; }
- (CGFloat)miterLimit { return _miter; } - (void)setMiterLimit:(CGFloat)l { _miter = l; }
- (NSInteger)windingRule { return _winding; } - (void)setWindingRule:(NSInteger)r { _winding = r; }
- (CGFloat)flatness { return _flatness; } - (void)setFlatness:(CGFloat)f { _flatness = f; }
- (void)setLineDash:(const CGFloat *)d count:(NSInteger)n phase:(CGFloat)ph {
  free(_dash); _dash = NULL; _ndash = 0;
  if (d && n > 0) { _dash = malloc(n * sizeof(CGFloat)); memcpy(_dash, d, n * sizeof(CGFloat)); _ndash = n; } _phase = ph; }
- (void)getLineDash:(CGFloat *)d count:(NSInteger *)n phase:(CGFloat *)ph {
  if (d && _dash) memcpy(d, _dash, _ndash * sizeof(CGFloat)); if (n) *n = _ndash; if (ph) *ph = _phase; }
- (void)setAssociatedPoints:(NSPoint *)p atIndex:(NSInteger)i {}
- (void)fill {
  CGContextRef c = XEFCurrentCGContext(); if (!c) return;
  CGContextBeginPath(c); CGContextAddPath(c, _path); if (_winding == 1) CGContextEOFillPath(c); else CGContextFillPath(c); }
- (void)stroke {
  CGContextRef c = XEFCurrentCGContext(); if (!c) return;
  CGContextSaveGState(c);
  CGContextSetLineWidth(c, _lineWidth); CGContextSetLineCap(c, (CGLineCap)_cap); CGContextSetLineJoin(c, (CGLineJoin)_join);
  CGContextSetMiterLimit(c, _miter); if (_ndash) CGContextSetLineDash(c, _phase, _dash, _ndash);
  CGContextBeginPath(c); CGContextAddPath(c, _path); CGContextStrokePath(c);
  CGContextRestoreGState(c); }
- (void)addClip { CGContextRef c = XEFCurrentCGContext(); if (!c) return; CGContextBeginPath(c); CGContextAddPath(c, _path); if (_winding == 1) CGContextEOClip(c); else CGContextClip(c); }
- (void)setClip { [self addClip]; }   /* no clip replacement: nested clips only shrink */
@end

@implementation NSAffineTransform (XEFAppKitAdditions)
- (void)concat {
  CGContextRef c = XEFCurrentCGContext(); if (!c) return;
  NSAffineTransformStruct s = [self transformStruct]; CGContextConcatCTM(c, CGAffineTransformMake(s.m11, s.m12, s.m21, s.m22, s.tX, s.tY)); }
- (void)set {
  CGContextRef c = XEFCurrentCGContext(); if (!c) return;
  NSAffineTransformStruct s = [self transformStruct]; CGContextSetCTM(c, CGAffineTransformMake(s.m11, s.m12, s.m21, s.m22, s.tX, s.tY)); }
- (NSBezierPath *)transformBezierPath:(NSBezierPath *)p { NSBezierPath *n = [[p copy] autorelease]; [n transformUsingAffineTransform:self]; return n; }
@end

/* ================================================================== NSFont */
/* macOS font names -> fontconfig family / weight / italic. Names the host does not know fall back to fontconfig's default. */
static void font_resolve(NSString *name, NSString **family, int *weight, int *italic) {
  NSString *n = [name lowercaseString];
  *weight = 400; *italic = 0;
  if ([n rangeOfString:@"bold"].location != NSNotFound || [n rangeOfString:@"heavy"].location != NSNotFound || [n rangeOfString:@"black"].location != NSNotFound) *weight = 700;
  else if ([n rangeOfString:@"semibold"].location != NSNotFound || [n rangeOfString:@"demi"].location != NSNotFound) *weight = 600;
  else if ([n rangeOfString:@"medium"].location != NSNotFound) *weight = 500;
  else if ([n rangeOfString:@"light"].location != NSNotFound || [n rangeOfString:@"thin"].location != NSNotFound) *weight = 300;
  if ([n rangeOfString:@"italic"].location != NSNotFound || [n rangeOfString:@"oblique"].location != NSNotFound) *italic = 1;
  NSString *base = [[n componentsSeparatedByString:@"-"] objectAtIndex:0];
  if ([n hasPrefix:@"."] || [base hasPrefix:@"sf"] || [base hasPrefix:@"helvetica"] || [base hasPrefix:@"lucidagrande"] || [base hasPrefix:@"lucida grande"] ||
      [base hasPrefix:@"applesystem"] || [base isEqualToString:@"system"] || [base hasPrefix:@"arial"] || [base hasPrefix:@"geneva"] || [base hasPrefix:@"verdana"])
    *family = ([base hasPrefix:@"sfmono"] || [base hasPrefix:@"sf mono"] || [n hasPrefix:@".sfnsmono"] || [n hasPrefix:@".applesystemuifontmonospaced"]) ? @"monospace" : @"sans-serif";
  else if ([base hasPrefix:@"menlo"] || [base hasPrefix:@"monaco"] || [base hasPrefix:@"courier"] || [base hasPrefix:@"andalemono"] || [base hasPrefix:@"sfmono"])
    *family = @"monospace";
  else if ([base hasPrefix:@"times"] || [base hasPrefix:@"georgia"] || [base hasPrefix:@"newyork"] || [base hasPrefix:@"palatino"] || [base hasPrefix:@"baskerville"] || [base hasPrefix:@"hoefler"])
    *family = @"serif";
  else if ([base hasPrefix:@"markerfelt"] || [base hasPrefix:@"marker felt"] || [base hasPrefix:@"noteworthy"] || [base hasPrefix:@"chalkboard"] || [base hasPrefix:@"comic"])
    *family = @"cursive";
  else {
    NSString *fam = [[name componentsSeparatedByString:@"-"] objectAtIndex:0];
    *family = [fam length] ? fam : @"sans-serif"; } }

@implementation NSFont
+ (BOOL)supportsSecureCoding { return YES; }
static NSMutableDictionary *g_fonts;
+ (NSFont *)fontWithName:(NSString *)name size:(CGFloat)size {
  if (!name) return nil;
  if (size <= 0) size = 12;
  NSString *key = [NSString stringWithFormat:@"%@/%g", name, size];
  @synchronized ([NSFont class]) {
    if (!g_fonts) g_fonts = [[NSMutableDictionary alloc] init];
    NSFont *f = [g_fonts objectForKey:key];
    if (f) return f;
    f = [[NSFont alloc] init];
    f->_name = [name copy]; f->_size = size;
    NSString *fam; int w, it; font_resolve(name, &fam, &w, &it);
    f->_family = [fam copy]; f->_weight = w; f->_italic = it;
    double m[4]; char resolved[256];
    xef_host_font_metrics([fam UTF8String], size, w, it, m, resolved, sizeof resolved);
    f->_ascent = m[0]; f->_descent = m[1]; f->_lineHeight = m[2]; f->_avgWidth = m[3];
    f->_hostFamily = resolved[0] ? [[NSString alloc] initWithUTF8String:resolved] : [fam copy];
    [g_fonts setObject:f forKey:key];
    [f release];
    return f; } }
+ (NSFont *)systemFontOfSize:(CGFloat)s { return [self fontWithName:@".AppleSystemUIFont" size:s > 0 ? s : 13]; }
+ (NSFont *)boldSystemFontOfSize:(CGFloat)s { return [self fontWithName:@".AppleSystemUIFontBold" size:s > 0 ? s : 13]; }
+ (NSFont *)systemFontOfSize:(CGFloat)s weight:(CGFloat)w {
  NSString *n = w >= 0.4 ? @".AppleSystemUIFontBold" : w >= 0.3 ? @".AppleSystemUIFontSemibold" : w >= 0.2 ? @".AppleSystemUIFontMedium" : w < -0.3 ? @".AppleSystemUIFontLight" : @".AppleSystemUIFont";
  return [self fontWithName:n size:s > 0 ? s : 13]; }
+ (NSFont *)monospacedSystemFontOfSize:(CGFloat)s weight:(CGFloat)w { return [self fontWithName:w >= 0.4 ? @"Menlo-Bold" : @"Menlo-Regular" size:s > 0 ? s : 13]; }
+ (NSFont *)monospacedDigitSystemFontOfSize:(CGFloat)s weight:(CGFloat)w { return [self systemFontOfSize:s weight:w]; }
+ (NSFont *)labelFontOfSize:(CGFloat)s { return [self systemFontOfSize:s > 0 ? s : 10]; }
+ (NSFont *)messageFontOfSize:(CGFloat)s { return [self systemFontOfSize:s]; }
+ (NSFont *)menuFontOfSize:(CGFloat)s { return [self systemFontOfSize:s > 0 ? s : 14]; }
+ (NSFont *)menuBarFontOfSize:(CGFloat)s { return [self systemFontOfSize:s > 0 ? s : 14]; }
+ (NSFont *)titleBarFontOfSize:(CGFloat)s { return [self boldSystemFontOfSize:s]; }
+ (NSFont *)paletteFontOfSize:(CGFloat)s { return [self systemFontOfSize:s]; }
+ (NSFont *)toolTipsFontOfSize:(CGFloat)s { return [self systemFontOfSize:s > 0 ? s : 11]; }
+ (NSFont *)controlContentFontOfSize:(CGFloat)s { return [self systemFontOfSize:s]; }
+ (NSFont *)userFontOfSize:(CGFloat)s { return [self fontWithName:@"Helvetica" size:s > 0 ? s : 12]; }
+ (NSFont *)userFixedPitchFontOfSize:(CGFloat)s { return [self fontWithName:@"Menlo-Regular" size:s > 0 ? s : 11]; }
+ (void)setUserFont:(NSFont *)f {} + (void)setUserFixedPitchFont:(NSFont *)f {}
+ (CGFloat)systemFontSize { return 13; } + (CGFloat)smallSystemFontSize { return 11; } + (CGFloat)labelFontSize { return 10; }
+ (CGFloat)systemFontSizeForControlSize:(NSUInteger)cs { return cs == 1 ? 11 : cs == 2 ? 9 : cs == 3 ? 15 : 13; }
+ (NSFont *)fontWithDescriptor:(NSFontDescriptor *)d size:(CGFloat)s {
  NSString *n = [d objectForKey:NSFontNameAttribute] ?: [d objectForKey:NSFontFamilyAttribute] ?: @"Helvetica";
  if (s <= 0) s = [[d objectForKey:NSFontSizeAttribute] doubleValue];
  return [self fontWithName:n size:s]; }
+ (NSFont *)fontWithDescriptor:(NSFontDescriptor *)d textTransform:(NSAffineTransform *)t { return [self fontWithDescriptor:d size:0]; }
- (NSString *)fontName { return _name; }
- (NSString *)familyName { return [_name hasPrefix:@"."] ? @"System Font" : [[_name componentsSeparatedByString:@"-"] objectAtIndex:0]; }
- (NSString *)displayName { return [self familyName]; }
- (CGFloat)pointSize { return _size; }
- (CGFloat)ascender { return _ascent; }
- (CGFloat)descender { return -_descent; }
- (CGFloat)leading { CGFloat l = _lineHeight - _ascent - _descent; return l > 0 ? l : 0; }
- (CGFloat)capHeight { return _ascent * 0.7; }
- (CGFloat)xHeight { return _ascent * 0.5; }
- (CGFloat)italicAngle { return _italic ? -12 : 0; }
- (CGFloat)underlinePosition { return -_descent / 2; }
- (CGFloat)underlineThickness { return _size / 14; }
- (NSRect)boundingRectForFont { return NSMakeRect(0, -_descent, _avgWidth * 2, _ascent + _descent); }
- (NSSize)maximumAdvancement { return NSMakeSize(_avgWidth * 2, 0); }
- (BOOL)isFixedPitch { return [_family isEqualToString:@"monospace"]; }
- (BOOL)isVertical { return NO; }
- (NSFont *)verticalFont { return self; }
- (NSFont *)screenFont { return self; } - (NSFont *)printerFont { return self; }
- (NSFont *)screenFontWithRenderingMode:(NSInteger)m { return self; }
- (NSInteger)renderingMode { return 0; }
- (NSUInteger)numberOfGlyphs { return 65535; }
- (NSSize)advancementForGlyph:(NSUInteger)g { return NSMakeSize(_avgWidth, 0); }
- (NSRect)boundingRectForGlyph:(NSUInteger)g { return NSMakeRect(0, -_descent, _avgWidth, _ascent + _descent); }
- (const CGFloat *)matrix { static CGFloat m[6]; m[0] = _size; m[1] = 0; m[2] = 0; m[3] = _size; m[4] = 0; m[5] = 0; return m; }
- (NSAffineTransform *)textTransform { NSAffineTransform *t = [NSAffineTransform transform]; [t scaleBy:_size]; return t; }
- (NSCharacterSet *)coveredCharacterSet { return [[NSCharacterSet characterSetWithRange:NSMakeRange(0, 0x10000)] invertedSet]; }
- (NSStringEncoding)mostCompatibleStringEncoding { return NSUnicodeStringEncoding; }
- (NSFontDescriptor *)fontDescriptor {
  return [NSFontDescriptor fontDescriptorWithFontAttributes:@{ NSFontNameAttribute: _name, NSFontFamilyAttribute: [self familyName], NSFontSizeAttribute: @(_size) }]; }
- (void)set { [self setInContext:[NSGraphicsContext currentContext]]; }
- (void)setInContext:(NSGraphicsContext *)c {}
- (BOOL)isEqual:(id)o { return o == self || ([o isKindOfClass:[NSFont class]] && [((NSFont *)o)->_name isEqualToString:_name] && ((NSFont *)o)->_size == _size); }
- (NSUInteger)hash { return [_name hash] ^ (NSUInteger)(_size * 16); }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (id)retain { return [super retain]; }
- (NSString *)description { return [NSString stringWithFormat:@"\"%@ %gpt.\"", _name, _size]; }
- (void)encodeWithCoder:(NSCoder *)c { [c encodeObject:_name forKey:@"NSName"]; [c encodeDouble:_size forKey:@"NSSize"]; [c encodeInt:16 forKey:@"NSfFlags"]; }
- (id)initWithCoder:(NSCoder *)c {
  NSString *n = [c decodeObjectForKey:@"NSName"]; CGFloat s = [c decodeDoubleForKey:@"NSSize"];
  NSFont *f = [NSFont fontWithName:n ?: @".AppleSystemUIFont" size:s];
  [self release]; return [f retain]; }
/* AppKit-lite: host font description */
- (NSString *)_xefFamily { return _family; }
- (int)_xefWeight { return _weight; }
- (int)_xefItalic { return _italic; }
- (CGFloat)_xefLineHeight { return _lineHeight; }
@end

@implementation NSFontDescriptor
+ (BOOL)supportsSecureCoding { return YES; }
+ (NSFontDescriptor *)fontDescriptorWithFontAttributes:(NSDictionary *)a { NSFontDescriptor *d = [[[self alloc] init] autorelease]; d->_attrs = [a copy] ?: [[NSDictionary alloc] init]; return d; }
+ (NSFontDescriptor *)fontDescriptorWithName:(NSString *)n size:(CGFloat)s { return [self fontDescriptorWithFontAttributes:@{ NSFontNameAttribute: n ?: @"Helvetica", NSFontSizeAttribute: @(s) }]; }
+ (NSFontDescriptor *)preferredFontDescriptorForTextStyle:(NSString *)style options:(NSDictionary *)o { return [self fontDescriptorWithName:@".AppleSystemUIFont" size:13]; }
- (NSDictionary *)fontAttributes { return _attrs; }
- (id)objectForKey:(NSString *)k { return [_attrs objectForKey:k]; }
- (CGFloat)pointSize { return [[_attrs objectForKey:NSFontSizeAttribute] doubleValue]; }
- (NSString *)postscriptName { return [_attrs objectForKey:NSFontNameAttribute]; }
- (NSUInteger)symbolicTraits { return [[[_attrs objectForKey:NSFontTraitsAttribute] objectForKey:NSFontSymbolicTrait] unsignedIntegerValue]; }
- (NSFontDescriptor *)fontDescriptorByAddingAttributes:(NSDictionary *)a {
  NSMutableDictionary *m = [[_attrs mutableCopy] autorelease]; [m addEntriesFromDictionary:a]; return [NSFontDescriptor fontDescriptorWithFontAttributes:m]; }
- (NSFontDescriptor *)fontDescriptorWithSize:(CGFloat)s { return [self fontDescriptorByAddingAttributes:@{ NSFontSizeAttribute: @(s) }]; }
- (NSFontDescriptor *)fontDescriptorWithSymbolicTraits:(NSUInteger)t { return self; }
- (NSFontDescriptor *)fontDescriptorWithFamily:(NSString *)f { return [self fontDescriptorByAddingAttributes:@{ NSFontFamilyAttribute: f }]; }
- (NSFontDescriptor *)fontDescriptorWithDesign:(NSString *)d { return self; }
- (NSFontDescriptor *)fontDescriptorWithFace:(NSString *)f { return self; }
- (NSArray *)matchingFontDescriptorsWithMandatoryKeys:(NSSet *)k { return @[self]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (void)encodeWithCoder:(NSCoder *)c { [c encodeObject:_attrs forKey:@"NSFontDescriptorAttributes"]; }
- (id)initWithCoder:(NSCoder *)c { if ((self = [super init])) _attrs = [[c decodeObjectForKey:@"NSFontDescriptorAttributes"] retain] ?: [[NSDictionary alloc] init]; return self; }
- (void)dealloc { [_attrs release]; [super dealloc]; }
@end

/* ================================================================== NSParagraphStyle */
@implementation NSTextTab
+ (BOOL)supportsSecureCoding { return YES; }
- (id)initWithType:(NSUInteger)t location:(CGFloat)l { if ((self = [super init])) { _loc = l; _align = t == 1 ? 2 : t == 2 ? 1 : 0; } return self; }
- (id)initWithTextAlignment:(NSInteger)a location:(CGFloat)l options:(NSDictionary *)o { if ((self = [super init])) { _loc = l; _align = a; _options = [o copy]; } return self; }
- (CGFloat)location { return _loc; } - (NSInteger)alignment { return _align; } - (NSDictionary *)options { return _options ?: @{}; }
- (NSUInteger)tabStopType { return _align == 2 ? 1 : _align == 1 ? 2 : 0; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[NSTextTab class]] && ((NSTextTab *)o)->_loc == _loc && ((NSTextTab *)o)->_align == _align; }
- (void)encodeWithCoder:(NSCoder *)c { [c encodeDouble:_loc forKey:@"NSLocation"]; }
- (id)initWithCoder:(NSCoder *)c { if ((self = [super init])) { _loc = [c decodeDoubleForKey:@"NSLocation"]; _align = [c decodeIntegerForKey:@"NSAlignment"]; } return self; }
- (void)dealloc { [_options release]; [super dealloc]; }
@end

@implementation NSParagraphStyle
+ (BOOL)supportsSecureCoding { return YES; }
+ (NSParagraphStyle *)defaultParagraphStyle { static NSParagraphStyle *s; if (!s) s = [[NSParagraphStyle alloc] init]; return s; }
+ (NSInteger)defaultWritingDirectionForLanguage:(NSString *)l { return 0; }
- (id)init { if ((self = [super init])) { _align = 4 /*natural*/; _lineBreak = 0; _tabInterval = 0; _hyphen = 0; } return self; }
- (NSInteger)alignment { return _align; }
- (NSInteger)lineBreakMode { return _lineBreak; }
- (CGFloat)lineSpacing { return _lineSpacing; }
- (CGFloat)paragraphSpacing { return _paraSpacing; }
- (CGFloat)paragraphSpacingBefore { return _paraSpacingBefore; }
- (CGFloat)firstLineHeadIndent { return _firstIndent; }
- (CGFloat)headIndent { return _headIndent; }
- (CGFloat)tailIndent { return _tailIndent; }
- (CGFloat)minimumLineHeight { return _minLine; }
- (CGFloat)maximumLineHeight { return _maxLine; }
- (CGFloat)lineHeightMultiple { return _lineMultiple; }
- (NSInteger)baseWritingDirection { return _direction; }
- (NSArray *)tabStops { return _tabs ?: @[]; }
- (CGFloat)defaultTabInterval { return _tabInterval; }
- (float)hyphenationFactor { return _hyphen; }
- (BOOL)usesDefaultHyphenation { return NO; }
- (float)tighteningFactorForTruncation { return 0.05f; }
- (BOOL)allowsDefaultTighteningForTruncation { return NO; }
- (NSArray *)textBlocks { return @[]; } - (NSArray *)textLists { return @[]; }
- (NSInteger)headerLevel { return 0; }
- (id)copyWithZone:(NSZone *)z { NSParagraphStyle *p = [[NSParagraphStyle allocWithZone:z] init]; [p _xefCopyFrom:self]; return p; }
- (id)mutableCopyWithZone:(NSZone *)z { NSMutableParagraphStyle *p = [[NSMutableParagraphStyle allocWithZone:z] init]; [p _xefCopyFrom:self]; return p; }
- (void)_xefCopyFrom:(NSParagraphStyle *)o {
  _align = o->_align; _lineBreak = o->_lineBreak; _lineSpacing = o->_lineSpacing; _paraSpacing = o->_paraSpacing; _paraSpacingBefore = o->_paraSpacingBefore;
  _firstIndent = o->_firstIndent; _headIndent = o->_headIndent; _tailIndent = o->_tailIndent; _minLine = o->_minLine; _maxLine = o->_maxLine;
  _lineMultiple = o->_lineMultiple; _direction = o->_direction; [_tabs release]; _tabs = [o->_tabs copy]; _tabInterval = o->_tabInterval; _hyphen = o->_hyphen; }
- (BOOL)isEqual:(id)o {
  if (o == self) return YES; if (![o isKindOfClass:[NSParagraphStyle class]]) return NO;
  NSParagraphStyle *p = o;
  return p->_align == _align && p->_lineBreak == _lineBreak && p->_lineSpacing == _lineSpacing && p->_paraSpacing == _paraSpacing &&
         p->_firstIndent == _firstIndent && p->_headIndent == _headIndent && p->_tailIndent == _tailIndent && p->_minLine == _minLine &&
         p->_maxLine == _maxLine && p->_lineMultiple == _lineMultiple; }
- (NSUInteger)hash { return _align ^ (_lineBreak << 4) ^ (NSUInteger)(_lineSpacing * 8); }
- (void)encodeWithCoder:(NSCoder *)c { [c encodeInteger:_align forKey:@"NSAlignment"]; }
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [self init])) {
    if ([c containsValueForKey:@"NSAlignment"]) _align = [c decodeIntegerForKey:@"NSAlignment"];
    _lineBreak = [c decodeIntegerForKey:@"NSLineBreakMode"]; _lineSpacing = [c decodeDoubleForKey:@"NSLineSpacing"];
    _paraSpacing = [c decodeDoubleForKey:@"NSParagraphSpacing"]; _firstIndent = [c decodeDoubleForKey:@"NSFirstLineHeadIndent"];
    _headIndent = [c decodeDoubleForKey:@"NSHeadIndent"]; _tailIndent = [c decodeDoubleForKey:@"NSTailIndent"];
    _minLine = [c decodeDoubleForKey:@"NSMinLineHeight"]; _maxLine = [c decodeDoubleForKey:@"NSMaxLineHeight"];
    _lineMultiple = [c decodeDoubleForKey:@"NSLineHeightMultiple"]; _tabInterval = [c decodeDoubleForKey:@"NSDefaultTabInterval"];
    id tabs = [c decodeObjectForKey:@"NSTabStops"]; if ([tabs isKindOfClass:[NSArray class]]) _tabs = [tabs copy]; }
  return self; }
- (void)dealloc { [_tabs release]; [super dealloc]; }
@end

@implementation NSMutableParagraphStyle
- (void)setAlignment:(NSInteger)v { _align = v; }
- (void)setLineBreakMode:(NSInteger)v { _lineBreak = v; }
- (void)setLineSpacing:(CGFloat)v { _lineSpacing = v; }
- (void)setParagraphSpacing:(CGFloat)v { _paraSpacing = v; }
- (void)setParagraphSpacingBefore:(CGFloat)v { _paraSpacingBefore = v; }
- (void)setFirstLineHeadIndent:(CGFloat)v { _firstIndent = v; }
- (void)setHeadIndent:(CGFloat)v { _headIndent = v; }
- (void)setTailIndent:(CGFloat)v { _tailIndent = v; }
- (void)setMinimumLineHeight:(CGFloat)v { _minLine = v; }
- (void)setMaximumLineHeight:(CGFloat)v { _maxLine = v; }
- (void)setLineHeightMultiple:(CGFloat)v { _lineMultiple = v; }
- (void)setBaseWritingDirection:(NSInteger)v { _direction = v; }
- (void)setTabStops:(NSArray *)t { [_tabs release]; _tabs = [t copy]; }
- (void)addTabStop:(NSTextTab *)t { NSMutableArray *a = [[_tabs mutableCopy] autorelease] ?: [NSMutableArray array]; [a addObject:t]; [self setTabStops:a]; }
- (void)removeTabStop:(NSTextTab *)t { NSMutableArray *a = [[_tabs mutableCopy] autorelease]; [a removeObject:t]; [self setTabStops:a]; }
- (void)setDefaultTabInterval:(CGFloat)v { _tabInterval = v; }
- (void)setHyphenationFactor:(float)v { _hyphen = v; }
- (void)setUsesDefaultHyphenation:(BOOL)f {}
- (void)setTighteningFactorForTruncation:(float)v {}
- (void)setAllowsDefaultTighteningForTruncation:(BOOL)f {}
- (void)setTextBlocks:(NSArray *)a {} - (void)setTextLists:(NSArray *)a {} - (void)setHeaderLevel:(NSInteger)l {}
- (void)setParagraphStyle:(NSParagraphStyle *)p { if (p) [self _xefCopyFrom:p]; }
- (id)copyWithZone:(NSZone *)z { NSParagraphStyle *p = [[NSParagraphStyle allocWithZone:z] init]; [p _xefCopyFrom:self]; return p; }
@end

@implementation NSShadow
+ (BOOL)supportsSecureCoding { return YES; }
- (id)init { if ((self = [super init])) { _offset = NSMakeSize(0, -3); _blur = 0; } return self; }
- (NSSize)shadowOffset { return _offset; } - (void)setShadowOffset:(NSSize)s { _offset = s; }
- (CGFloat)shadowBlurRadius { return _blur; } - (void)setShadowBlurRadius:(CGFloat)b { _blur = b; }
- (NSColor *)shadowColor { return _color ?: [NSColor colorWithCalibratedWhite:0 alpha:1.0 / 3]; }
- (void)setShadowColor:(NSColor *)c { [c retain]; [_color release]; _color = c; }
- (void)set {}
- (id)copyWithZone:(NSZone *)z { NSShadow *s = [[NSShadow allocWithZone:z] init]; s->_offset = _offset; s->_blur = _blur; s->_color = [_color retain]; return s; }
- (void)encodeWithCoder:(NSCoder *)c {}
- (id)initWithCoder:(NSCoder *)c { return [self init]; }
- (void)dealloc { [_color release]; [super dealloc]; }
@end

/* ================================================================== text layout (host pango) */
@implementation XEFTextLayout
/* UTF-16 -> UTF-8 with an index map (u2b[i] = byte offset of UTF-16 index i; u2b[len] = total bytes) */
- (id)initWithAttributedString:(NSAttributedString *)as width:(CGFloat)width {
  if (!(self = [super init])) return nil;
  NSString *s = [as string] ?: @"";
  NSUInteger len = [s length];
  unichar *u = malloc((len + 1) * sizeof(unichar));
  [s getCharacters:u range:NSMakeRange(0, len)];
  char *utf8 = malloc(len * 3 + 4);
  _u2b = malloc((len + 1) * sizeof(int));
  int nb = 0;
  for (NSUInteger i = 0; i < len; i++) {
    _u2b[i] = nb;
    uint32_t c = u[i];
    if (c >= 0xD800 && c < 0xDC00 && i + 1 < len && u[i + 1] >= 0xDC00 && u[i + 1] < 0xE000) {
      c = 0x10000 + ((c - 0xD800) << 10) + (u[i + 1] - 0xDC00);
      utf8[nb++] = (char)(0xF0 | (c >> 18)); utf8[nb++] = (char)(0x80 | ((c >> 12) & 0x3F));
      utf8[nb++] = (char)(0x80 | ((c >> 6) & 0x3F)); utf8[nb++] = (char)(0x80 | (c & 0x3F));
      _u2b[++i] = nb;   /* low surrogate: maps past the character */
      continue; }
    if (c >= 0xD800 && c < 0xE000) c = 0xFFFD;
    if (c == 0x2028 || c == 0x2029) c = '\n';
    if (c < 0x80) utf8[nb++] = (char)c;
    else if (c < 0x800) { utf8[nb++] = (char)(0xC0 | (c >> 6)); utf8[nb++] = (char)(0x80 | (c & 0x3F)); }
    else { utf8[nb++] = (char)(0xE0 | (c >> 12)); utf8[nb++] = (char)(0x80 | ((c >> 6) & 0x3F)); utf8[nb++] = (char)(0x80 | (c & 0x3F)); }
  }
  _u2b[len] = nb; _len = len; _nbytes = nb;
  utf8[nb] = 0;
  _t = xef_host_text_create(utf8, nb);
  free(utf8); free(u);
  _width = width;
  xef_host_text_set_width(_t, width > 0 ? width : -1);
  /* attributes */
  NSFont *deffont = [NSFont fontWithName:@"Helvetica" size:12];
  xef_host_text_font(_t, -1, -1, [[deffont _xefFamily] UTF8String], 12, [deffont _xefWeight], [deffont _xefItalic]);
  NSInteger align = 0; CGFloat spacing = 0; BOOL alignSet = NO;
  CGFloat maxLine = 0;
  NSUInteger i = 0;
  while (i < len) {
    NSRange r;
    NSDictionary *a = [as attributesAtIndex:i effectiveRange:&r];
    if (r.length == 0) r.length = 1;
    if (r.location + r.length > len) r.length = len - r.location;
    int b0 = _u2b[r.location], b1 = _u2b[r.location + r.length];
    NSFont *f = [a objectForKey:NSFontAttributeName];
    if (![f isKindOfClass:[NSFont class]]) f = deffont;
    xef_host_text_font(_t, b0, b1, [[f _xefFamily] UTF8String], [f pointSize], [f _xefWeight], [f _xefItalic]);
    if ([f _xefLineHeight] > maxLine) maxLine = [f _xefLineHeight];
    NSColor *c = [a objectForKey:NSForegroundColorAttributeName];
    if (![c isKindOfClass:[NSColor class]]) c = [NSColor blackColor];
    xef_host_text_color(_t, b0, b1, c->r, c->g, c->b, c->a);
    NSColor *bg = [a objectForKey:NSBackgroundColorAttributeName];
    if ([bg isKindOfClass:[NSColor class]] && bg->a > 0) xef_host_text_background(_t, b0, b1, bg->r, bg->g, bg->b, bg->a);
    NSInteger ul = [[a objectForKey:NSUnderlineStyleAttributeName] integerValue], st = [[a objectForKey:NSStrikethroughStyleAttributeName] integerValue];
    if ([a objectForKey:NSLinkAttributeName]) ul = ul ? ul : 1;
    if (ul || st) xef_host_text_decoration(_t, b0, b1, (ul & 0xff) == 9 ? 2 : (ul ? 1 : 0), st ? 1 : 0);
    id kern = [a objectForKey:NSKernAttributeName];
    if (kern && [kern doubleValue] != 0) xef_host_text_kern(_t, b0, b1, [kern doubleValue]);
    NSParagraphStyle *ps = [a objectForKey:NSParagraphStyleAttributeName];
    if (!alignSet && [ps isKindOfClass:[NSParagraphStyle class]]) { align = [ps alignment]; spacing = [ps lineSpacing]; alignSet = YES; }
    i = r.location + r.length;
  }
  if (_alignOverride >= 0 && !alignSet) align = 4;
  xef_host_text_set_align(_t, align == 4 ? 0 : (int)align);   /* natural = left (LTR) */
  if (spacing > 0) xef_host_text_set_spacing(_t, spacing);
  _defaultLineHeight = maxLine > 0 ? maxLine : [deffont _xefLineHeight];
  double sz[4]; xef_host_text_size(_t, sz);
  _size = NSMakeSize(ceil(sz[0]), ceil(sz[1])); _baseline = sz[2]; _lines = (NSUInteger)sz[3];
  if (len == 0) _size.height = ceil(_defaultLineHeight);
  return self; }
+ (XEFTextLayout *)layoutWithAttributedString:(NSAttributedString *)s width:(CGFloat)w { return [[[self alloc] initWithAttributedString:s width:w] autorelease]; }
+ (XEFTextLayout *)layoutWithString:(NSString *)s attributes:(NSDictionary *)a width:(CGFloat)w {
  NSAttributedString *as = [[[NSAttributedString alloc] initWithString:s ?: @"" attributes:a] autorelease];
  return [self layoutWithAttributedString:as width:w]; }
- (void)dealloc { if (_t) xef_host_text_destroy(_t); free(_u2b); [super dealloc]; }
- (NSSize)size { return _size; }
- (CGFloat)baseline { return _baseline; }
- (NSUInteger)lineCount { return _lines; }
- (CGFloat)defaultLineHeight { return _defaultLineHeight; }
- (NSUInteger)_u16ForByte:(int)b {
  NSUInteger lo = 0, hi = _len;
  while (lo < hi) { NSUInteger mid = (lo + hi + 1) / 2; if (_u2b[mid] <= b) lo = mid; else hi = mid - 1; }
  return lo; }
/* top-left corner of the text at p (current context; flipped or not) */
- (void)drawAtTopLeft:(NSPoint)p {
  NSGraphicsContext *gc = [NSGraphicsContext currentContext];
  CGContextRef c = [gc CGContext]; int h = XEFCGContextGetHostHandle(c);
  if (!h || !_t) return;
  if ([gc isFlipped]) { xef_host_text_draw(h, _t, p.x, p.y); return; }
  CGContextSaveGState(c);
  CGContextTranslateCTM(c, p.x, p.y); CGContextScaleCTM(c, 1, -1);
  xef_host_text_draw(h, _t, 0, 0);
  CGContextRestoreGState(c); }
/* layout coordinates: y down from the top of the text */
- (NSUInteger)characterIndexAtPoint:(NSPoint)p {
  int tr = 0; int b = xef_host_text_hit(_t, p.x, p.y, &tr);
  NSUInteger i = [self _u16ForByte:b];
  if (tr && i < _len) { i++; if (i < _len && _u2b[i] == _u2b[i - 1]) i++; }
  return i > _len ? _len : i; }
- (NSRect)caretRectAtIndex:(NSUInteger)i {
  if (i > _len) i = _len;
  double o[4]; xef_host_text_cursor(_t, _u2b[i], o);
  CGFloat h = o[2] > 0 ? o[2] : _defaultLineHeight;
  return NSMakeRect(o[0], o[1], 1, h); }
- (NSRect)rectOfCharacterAtIndex:(NSUInteger)i {
  if (i >= _len) { NSRect c = [self caretRectAtIndex:_len]; c.size.width = 0; return c; }
  double o[4]; xef_host_text_char_rect(_t, _u2b[i], o); return NSMakeRect(o[0], o[1], o[2], o[3]); }
/* line fragments: start index (UTF-16), top, height, baseline */
- (NSUInteger)getLines:(XEFLineInfo *)out max:(NSUInteger)max {
  double *tmp = malloc(max * 4 * sizeof(double));
  int n = xef_host_text_lines(_t, tmp, (int)max);
  for (int k = 0; k < n; k++) { out[k].start = [self _u16ForByte:(int)tmp[k * 4]]; out[k].top = tmp[k * 4 + 1]; out[k].height = tmp[k * 4 + 2]; out[k].baseline = tmp[k * 4 + 3]; }
  free(tmp); return n; }
- (NSUInteger)length { return _len; }
@end

/* ---- string drawing --------------------------------------------------------------------------------------------------- */
enum { kUsesLineFragmentOrigin = 1 << 0, kTruncatesLastVisibleLine = 1 << 5 };
static void draw_layout_in_rect(XEFTextLayout *l, NSRect r) {
  NSGraphicsContext *gc = [NSGraphicsContext currentContext]; CGContextRef c = [gc CGContext];
  if (!c) return;
  CGContextSaveGState(c); CGContextClipToRect(c, r);
  [l drawAtTopLeft:NSMakePoint(r.origin.x, [gc isFlipped] ? r.origin.y : r.origin.y + r.size.height)];
  CGContextRestoreGState(c); }

@implementation NSString (XEFStringDrawing)
- (NSSize)sizeWithAttributes:(NSDictionary *)a { return [[XEFTextLayout layoutWithString:self attributes:a width:-1] size]; }
- (void)drawAtPoint:(NSPoint)p withAttributes:(NSDictionary *)a {
  XEFTextLayout *l = [XEFTextLayout layoutWithString:self attributes:a width:-1];
  BOOL fl = [[NSGraphicsContext currentContext] isFlipped];
  [l drawAtTopLeft:NSMakePoint(p.x, fl ? p.y : p.y + [l size].height)]; }
- (void)drawInRect:(NSRect)r withAttributes:(NSDictionary *)a { draw_layout_in_rect([XEFTextLayout layoutWithString:self attributes:a width:r.size.width], r); }
- (void)drawWithRect:(NSRect)r options:(NSUInteger)o attributes:(NSDictionary *)a context:(id)ctx {
  if (o & kUsesLineFragmentOrigin) [self drawInRect:r withAttributes:a];
  else [self drawAtPoint:r.origin withAttributes:a]; }
- (void)drawWithRect:(NSRect)r options:(NSUInteger)o attributes:(NSDictionary *)a { [self drawWithRect:r options:o attributes:a context:nil]; }
- (NSRect)boundingRectWithSize:(NSSize)s options:(NSUInteger)o attributes:(NSDictionary *)a context:(id)ctx {
  XEFTextLayout *l = [XEFTextLayout layoutWithString:self attributes:a width:(o & kUsesLineFragmentOrigin) && s.width > 0 ? s.width : -1];
  NSSize z = [l size]; return NSMakeRect(0, 0, z.width, z.height); }
- (NSRect)boundingRectWithSize:(NSSize)s options:(NSUInteger)o attributes:(NSDictionary *)a { return [self boundingRectWithSize:s options:o attributes:a context:nil]; }
@end

@implementation NSAttributedString (XEFStringDrawing)
- (NSSize)size { return [[XEFTextLayout layoutWithAttributedString:self width:-1] size]; }
- (void)drawAtPoint:(NSPoint)p {
  XEFTextLayout *l = [XEFTextLayout layoutWithAttributedString:self width:-1];
  BOOL fl = [[NSGraphicsContext currentContext] isFlipped];
  [l drawAtTopLeft:NSMakePoint(p.x, fl ? p.y : p.y + [l size].height)]; }
- (void)drawInRect:(NSRect)r { draw_layout_in_rect([XEFTextLayout layoutWithAttributedString:self width:r.size.width], r); }
- (void)drawWithRect:(NSRect)r options:(NSUInteger)o context:(id)ctx { if (o & kUsesLineFragmentOrigin) [self drawInRect:r]; else [self drawAtPoint:r.origin]; }
- (void)drawWithRect:(NSRect)r options:(NSUInteger)o { [self drawWithRect:r options:o context:nil]; }
- (NSRect)boundingRectWithSize:(NSSize)s options:(NSUInteger)o context:(id)ctx {
  NSSize z = [[XEFTextLayout layoutWithAttributedString:self width:(o & kUsesLineFragmentOrigin) && s.width > 0 ? s.width : -1] size];
  return NSMakeRect(0, 0, z.width, z.height); }
- (NSRect)boundingRectWithSize:(NSSize)s options:(NSUInteger)o { return [self boundingRectWithSize:s options:o context:nil]; }
/* AppKit additions used by text code */
- (NSFont *)_xefFontAtIndex:(NSUInteger)i { return i < [self length] ? [self attribute:NSFontAttributeName atIndex:i effectiveRange:NULL] : nil; }
- (NSDictionary *)fontAttributesInRange:(NSRange)r { return r.location < [self length] ? [self attributesAtIndex:r.location effectiveRange:NULL] : @{}; }
- (NSDictionary *)rulerAttributesInRange:(NSRange)r { return @{}; }
- (BOOL)containsAttachments { return NO; }
- (BOOL)containsAttachmentsInRange:(NSRange)r { return NO; }
- (NSRange)doubleClickAtIndex:(NSUInteger)i {
  NSString *s = [self string]; NSUInteger n = [s length]; if (i >= n) return NSMakeRange(n, 0);
  NSCharacterSet *w = [NSCharacterSet alphanumericCharacterSet];
  if (![w characterIsMember:[s characterAtIndex:i]]) return NSMakeRange(i, 1);
  NSUInteger a = i, b = i; while (a > 0 && [w characterIsMember:[s characterAtIndex:a - 1]]) a--; while (b < n && [w characterIsMember:[s characterAtIndex:b]]) b++;
  return NSMakeRange(a, b - a); }
- (NSUInteger)nextWordFromIndex:(NSUInteger)i forward:(BOOL)f {
  NSString *s = [self string]; NSUInteger n = [s length]; NSCharacterSet *w = [NSCharacterSet alphanumericCharacterSet];
  if (f) { while (i < n && ![w characterIsMember:[s characterAtIndex:i]]) i++; while (i < n && [w characterIsMember:[s characterAtIndex:i]]) i++; return i; }
  while (i > 0 && ![w characterIsMember:[s characterAtIndex:i - 1]]) i--; while (i > 0 && [w characterIsMember:[s characterAtIndex:i - 1]]) i--; return i; }
- (NSData *)RTFFromRange:(NSRange)r documentAttributes:(NSDictionary *)d { return [[[self string] substringWithRange:r] dataUsingEncoding:NSUTF8StringEncoding]; }
- (NSData *)RTFDFromRange:(NSRange)r documentAttributes:(NSDictionary *)d { return [self RTFFromRange:r documentAttributes:d]; }
- (NSFileWrapper *)RTFDFileWrapperFromRange:(NSRange)r documentAttributes:(NSDictionary *)d {
  return [[[NSFileWrapper alloc] initRegularFileWithContents:[self RTFFromRange:r documentAttributes:d]] autorelease]; }
- (NSData *)dataFromRange:(NSRange)r documentAttributes:(NSDictionary *)d error:(NSError **)e { return [self RTFFromRange:r documentAttributes:d]; }
@end

@implementation NSMutableAttributedString (XEFAppKit)
- (void)fixAttributesInRange:(NSRange)r {}
- (void)fixFontAttributeInRange:(NSRange)r {}
- (void)fixParagraphStyleAttributeInRange:(NSRange)r {}
- (void)fixAttachmentAttributeInRange:(NSRange)r {}
- (void)applyFontTraits:(NSUInteger)t range:(NSRange)r {}
- (void)setAlignment:(NSInteger)al range:(NSRange)r {
  NSMutableParagraphStyle *p = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease]; [p setAlignment:al];
  [self addAttribute:NSParagraphStyleAttributeName value:p range:r]; }
- (void)setBaseWritingDirection:(NSInteger)d range:(NSRange)r {}
- (void)superscriptRange:(NSRange)r {} - (void)subscriptRange:(NSRange)r {} - (void)unscriptRange:(NSRange)r {}
@end

/* ================================================================== NSImage drawing */
@implementation NSBitmapImageRep (XEFGraphics)
/* RGBA meshed 8-bit (the only layout AppKit-lite creates) */
- (CGBitmapInfo)_xefBitmapInfo {
  if (!_alpha) return (CGBitmapInfo)(_spp == 4 ? kCGImageAlphaNoneSkipLast : kCGImageAlphaNone);
  BOOL first = (_fmt & NSBitmapFormatAlphaFirst) != 0, nonpre = (_fmt & NSBitmapFormatAlphaNonpremultiplied) != 0;
  return (CGBitmapInfo)(first ? (nonpre ? kCGImageAlphaFirst : kCGImageAlphaPremultipliedFirst) : (nonpre ? kCGImageAlphaLast : kCGImageAlphaPremultipliedLast)); }
- (CGContextRef)_xefCreateContext {
  if (!_data) return NULL;
  CGColorSpaceRef cs = _spp >= 3 ? CGColorSpaceCreateDeviceRGB() : CGColorSpaceCreateDeviceGray();
  CGContextRef c = CGBitmapContextCreate(_data, _w, _h, _bps, _bpr, cs, [self _xefBitmapInfo]);
  CGColorSpaceRelease(cs); return c; }
- (CGImageRef)CGImage {
  if (!_data) return NULL;
  CGImageRef img = (CGImageRef)objc_getAssociatedObject(self, "xef.cgimage");
  if (img) return img;
  CGColorSpaceRef cs = _spp >= 3 ? CGColorSpaceCreateDeviceRGB() : CGColorSpaceCreateDeviceGray();
  CGDataProviderRef p = CGDataProviderCreateWithData(NULL, _data, _bpr * _h, NULL);
  img = CGImageCreate(_w, _h, _bps, _bpp, _bpr, cs, [self _xefBitmapInfo], p, NULL, true, kCGRenderingIntentDefault);
  CGDataProviderRelease(p); CGColorSpaceRelease(cs);
  if (img) { objc_setAssociatedObject(self, "xef.cgimage", (id)img, OBJC_ASSOCIATION_RETAIN); CGImageRelease(img); }
  return img; }
- (id)initWithCGImage:(CGImageRef)img {
  size_t w = CGImageGetWidth(img), h = CGImageGetHeight(img);
  if (!(self = [self initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                               colorSpaceName:@"NSDeviceRGBColorSpace" bitmapFormat:0 bytesPerRow:w * 4 bitsPerPixel:32])) return nil;
  CGContextRef c = [self _xefCreateContext];
  CGContextDrawImage(c, CGRectMake(0, 0, w, h), img); CGContextRelease(c);
  return self; }
- (BOOL)drawInRect:(NSRect)r {
  CGContextRef c = XEFCurrentCGContext(); CGImageRef img = [self CGImage];
  if (!c || !img) return NO;
  CGContextDrawImage(c, r, img); return YES; }
- (BOOL)draw { return [self drawInRect:NSMakeRect(0, 0, _w, _h)]; }
@end

@implementation NSImage (XEFGraphics)
+ (NSImage *)imageWithSystemSymbolName:(NSString *)n accessibilityDescription:(NSString *)d { return nil; }
- (id)initWithCGImage:(CGImageRef)img size:(NSSize)s {
  if (!img) { [self release]; return nil; }
  if (s.width == 0 || s.height == 0) s = NSMakeSize(CGImageGetWidth(img), CGImageGetHeight(img));
  if (!(self = [self initWithSize:s])) return nil;
  NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:img];
  if (rep) { [self addRepresentation:rep]; [rep release]; }
  return self; }
- (CGImageRef)CGImageForProposedRect:(NSRect *)r context:(NSGraphicsContext *)c hints:(NSDictionary *)h {
  for (id rep in _reps) if ([rep isKindOfClass:[NSBitmapImageRep class]]) return [rep CGImage];
  return NULL; }
- (NSBitmapImageRep *)_xefBitmap {
  for (id rep in _reps) if ([rep isKindOfClass:[NSBitmapImageRep class]]) return rep;
  if (objc_getAssociatedObject(self, "xef.handler")) { [self performSelector:@selector(_xefRenderHandler)]; for (id rep in _reps) if ([rep isKindOfClass:[NSBitmapImageRep class]]) return rep; }
  return nil; }
/* draws the from-rect (image points; zero = whole image) into rect; flip-aware when asked */
- (void)_xefDrawInRect:(NSRect)d fromRect:(NSRect)s operation:(NSUInteger)op fraction:(CGFloat)f respectFlipped:(BOOL)rf {
  CGContextRef c = XEFCurrentCGContext(); NSBitmapImageRep *rep = [self _xefBitmap];
  CGImageRef img = [rep CGImage];
  if (c && !img && [_reps count] && _size.width > 0 && _size.height > 0) {   /* representations that draw themselves (NSCustomImageRep) */
    id r0 = _reps[0]; CGContextSaveGState(c); CGContextSetAlpha(c, f); CGContextClipToRect(c, d); [r0 drawInRect:d]; CGContextRestoreGState(c); return; }
  if (!c || !img || _size.width <= 0 || _size.height <= 0) return;
  CGContextSaveGState(c);
  CGContextSetBlendMode(c, XEFBlendModeForOperation(op)); CGContextSetAlpha(c, f);
  if (rf && [[NSGraphicsContext currentContext] isFlipped]) { CGContextTranslateCTM(c, 0, d.origin.y * 2 + d.size.height); CGContextScaleCTM(c, 1, -1); }
  CGContextClipToRect(c, d);
  if (s.size.width > 0 && s.size.height > 0 && !NSEqualRects(s, NSMakeRect(0, 0, _size.width, _size.height))) {
    CGFloat sx = d.size.width / s.size.width, sy = d.size.height / s.size.height;
    d = NSMakeRect(d.origin.x - s.origin.x * sx, d.origin.y - s.origin.y * sy, _size.width * sx, _size.height * sy); }
  CGContextDrawImage(c, d, img);
  CGContextRestoreGState(c); }
- (void)drawInRect:(NSRect)d fromRect:(NSRect)s operation:(NSUInteger)op fraction:(CGFloat)f { [self _xefDrawInRect:d fromRect:s operation:op fraction:f respectFlipped:NO]; }
- (void)drawInRect:(NSRect)d fromRect:(NSRect)s operation:(NSUInteger)op fraction:(CGFloat)f respectFlipped:(BOOL)rf hints:(NSDictionary *)h {
  [self _xefDrawInRect:d fromRect:s operation:op fraction:f respectFlipped:rf]; }
- (void)drawInRect:(NSRect)d { [self _xefDrawInRect:d fromRect:NSZeroRect operation:2 fraction:1 respectFlipped:YES]; }
- (void)drawAtPoint:(NSPoint)p fromRect:(NSRect)s operation:(NSUInteger)op fraction:(CGFloat)f {
  NSSize z = (s.size.width > 0 && s.size.height > 0) ? s.size : _size;
  [self _xefDrawInRect:NSMakeRect(p.x, p.y, z.width, z.height) fromRect:s operation:op fraction:f respectFlipped:NO]; }
- (void)compositeToPoint:(NSPoint)p operation:(NSUInteger)op { [self drawAtPoint:p fromRect:NSZeroRect operation:op fraction:1]; }
- (void)dissolveToPoint:(NSPoint)p fraction:(CGFloat)f { [self drawAtPoint:p fromRect:NSZeroRect operation:2 fraction:f]; }
- (BOOL)isTemplate { return NO; } - (void)setTemplate:(BOOL)t {}
- (NSString *)name { return nil; }
- (NSString *)accessibilityDescription { return nil; } - (void)setAccessibilityDescription:(NSString *)d {}
- (NSImage *)imageWithSymbolConfiguration:(id)c { return self; }
- (BOOL)isFlipped { return NO; } - (void)setFlipped:(BOOL)f {}
- (void)setCacheMode:(NSInteger)m {} - (void)recache {}
- (NSEdgeInsets)capInsets { NSEdgeInsets e = {0, 0, 0, 0}; return e; } - (void)setCapInsets:(NSEdgeInsets)e {}
- (NSInteger)resizingMode { return 0; } - (void)setResizingMode:(NSInteger)m {}
- (NSRect)alignmentRect { return NSMakeRect(0, 0, _size.width, _size.height); }
- (void)encodeWithCoder:(NSCoder *)c {}
- (id)initWithCoder:(NSCoder *)c { return [self initWithSize:NSZeroSize]; }
@end

/* ================================================================== view geometry and drawing */
/* view -> its superview's coordinates (AppKit: frame in the superview's space; flipping is relative to the superview) */
static CGAffineTransform view_to_super(NSView *v) {
  CGAffineTransform t = CGAffineTransformMakeTranslation(v->_frame.origin.x, v->_frame.origin.y);
  BOOL superFlipped = v->_superview ? [v->_superview isFlipped] : NO;
  if (superFlipped != [v isFlipped]) t = CGAffineTransformConcat(CGAffineTransformMake(1, 0, 0, -1, 0, v->_frame.size.height), t);
  CGFloat sx = v->_bounds.size.width > 0 && v->_frame.size.width > 0 ? v->_frame.size.width / v->_bounds.size.width : 1;
  CGFloat sy = v->_bounds.size.height > 0 && v->_frame.size.height > 0 ? v->_frame.size.height / v->_bounds.size.height : 1;
  if (sx != 1 || sy != 1) t = CGAffineTransformConcat(CGAffineTransformMakeScale(sx, sy), t);
  return CGAffineTransformConcat(CGAffineTransformMakeTranslation(-v->_bounds.origin.x, -v->_bounds.origin.y), t); }
/* view -> window base coordinates (y-up, content area) */
static CGAffineTransform view_to_window(NSView *v) {
  CGAffineTransform t = CGAffineTransformIdentity;
  for (NSView *c = v; c; c = c->_superview) t = CGAffineTransformConcat(t, view_to_super(c));
  return t; }

@implementation NSView (XEFGeometry)
- (NSPoint)convertPoint:(NSPoint)p toView:(NSView *)v {
  if (v == self) return p;
  CGPoint w = CGPointApplyAffineTransform(p, view_to_window(self));
  return v ? CGPointApplyAffineTransform(w, CGAffineTransformInvert(view_to_window(v))) : w; }
- (NSPoint)convertPoint:(NSPoint)p fromView:(NSView *)v {
  if (v == self) return p;
  CGPoint w = v ? CGPointApplyAffineTransform(p, view_to_window(v)) : p;
  return CGPointApplyAffineTransform(w, CGAffineTransformInvert(view_to_window(self))); }
- (NSSize)convertSize:(NSSize)s toView:(NSView *)v { NSRect r = [self convertRect:NSMakeRect(0, 0, s.width, s.height) toView:v]; return r.size; }
- (NSSize)convertSize:(NSSize)s fromView:(NSView *)v { NSRect r = [self convertRect:NSMakeRect(0, 0, s.width, s.height) fromView:v]; return r.size; }
- (NSRect)convertRect:(NSRect)r toView:(NSView *)v {
  if (v == self) return r;
  CGAffineTransform t = view_to_window(self);
  if (v) t = CGAffineTransformConcat(t, CGAffineTransformInvert(view_to_window(v)));
  return CGRectApplyAffineTransform(r, t); }
- (NSRect)convertRect:(NSRect)r fromView:(NSView *)v {
  if (v == self) return r;
  CGAffineTransform t = CGAffineTransformInvert(view_to_window(self));
  if (v) t = CGAffineTransformConcat(view_to_window(v), t);
  return CGRectApplyAffineTransform(r, t); }
- (NSPoint)convertPointToBase:(NSPoint)p { return [self convertPoint:p toView:nil]; }
- (NSPoint)convertPointFromBase:(NSPoint)p { return [self convertPoint:p fromView:nil]; }
- (NSRect)convertRectToBase:(NSRect)r { return [self convertRect:r toView:nil]; }
- (NSRect)convertRectFromBase:(NSRect)r { return [self convertRect:r fromView:nil]; }
- (NSPoint)convertPointFromBacking:(NSPoint)p { return p; }
- (NSPoint)convertPointToLayer:(NSPoint)p { return p; } - (NSPoint)convertPointFromLayer:(NSPoint)p { return p; }
/* p in the superview's coordinates */
- (NSView *)hitTest:(NSPoint)p {
  if (_hidden) return nil;
  if (_superview && !NSMouseInRect(p, _frame, [_superview isFlipped])) return nil;
  NSPoint q = _superview ? [self convertPoint:p fromView:_superview] : CGPointApplyAffineTransform(p, CGAffineTransformInvert(view_to_super(self)));
  if (!_superview && !(q.x >= _bounds.origin.x && q.x <= NSMaxX(_bounds) && q.y >= _bounds.origin.y && q.y <= NSMaxY(_bounds))) return nil;
  for (NSView *s in [_subviews reverseObjectEnumerator]) { NSView *h = [s hitTest:q]; if (h) return h; }
  return self; }
/* viewDidHide / viewDidUnhide reach the view and those of its descendants that are not hidden themselves */
- (void)_xefHiddenChanged:(BOOL)hidden {
  if (hidden) [self viewDidHide]; else [self viewDidUnhide];
  for (NSView *s in [[_subviews copy] autorelease]) if (!s->_hidden) [s _xefHiddenChanged:hidden]; }
- (void)viewDidHide {} - (void)viewDidUnhide {}
- (void)setHidden:(BOOL)f {
  if (_hidden == f) return;
  _hidden = f; if (_window) _window->_dirty2D = YES;
  BOOL ancestorHidden = NO; for (NSView *v = _superview; v; v = v->_superview) if (v->_hidden) ancestorHidden = YES;
  if (!ancestorHidden) [self _xefHiddenChanged:f]; }
- (BOOL)isHidden { return _hidden; }
- (BOOL)isHiddenOrHasHiddenAncestor { for (NSView *v = self; v; v = v->_superview) if (v->_hidden) return YES; return NO; }
- (NSRect)visibleRect {
  if ([self isHiddenOrHasHiddenAncestor]) return NSZeroRect;
  NSRect r = _bounds;
  for (NSView *v = self; v->_superview; v = v->_superview) {
    NSRect sr = [v->_superview convertRect:v->_superview->_bounds toView:self];
    r = NSIntersectionRect(r, sr); }
  return r; }
- (void)setNeedsDisplayInRect:(NSRect)r { [self setNeedsDisplay:YES]; }
- (void)displayRect:(NSRect)r { [self display]; }
- (void)displayIfNeededInRect:(NSRect)r { [self displayIfNeeded]; }
- (void)displayRectIgnoringOpacity:(NSRect)r { [self display]; }
- (void)displayIfNeededIgnoringOpacity { [self displayIfNeeded]; }
- (BOOL)canDrawConcurrently { return NO; } - (void)setCanDrawConcurrently:(BOOL)f {}
- (BOOL)canDraw { return _window != nil && !_hidden; }
- (BOOL)needsToDrawRect:(NSRect)r { return YES; }
- (void)getRectsBeingDrawn:(const NSRect **)rects count:(NSInteger *)n { static NSRect one; one = _bounds; if (rects) *rects = &one; if (n) *n = 1; }
- (BOOL)wantsDefaultClipping { return YES; }
- (void)setTag:(NSInteger)t { _tag = t; }
- (NSInteger)tag { return -1; }
- (id)viewWithTag:(NSInteger)t {
  if ([self tag] == t) return self;
  for (NSView *s in _subviews) { id v = [s viewWithTag:t]; if (v) return v; }
  return nil; }
- (void)scrollPoint:(NSPoint)p { NSView *v = self; while (v->_superview && ![v->_superview respondsToSelector:@selector(scrollToPoint:)]) v = v->_superview;
  if (v->_superview) [(id)v->_superview scrollToPoint:[self convertPoint:p toView:v->_superview]]; }
- (BOOL)scrollRectToVisible:(NSRect)r {
  NSView *clip = _superview;
  while (clip && ![clip respondsToSelector:@selector(scrollToPoint:)]) clip = clip->_superview;
  if (!clip) return NO;
  NSRect inClip = [self convertRect:r toView:clip], vis = clip->_bounds;
  NSPoint o = vis.origin;
  if (NSMinY(inClip) < NSMinY(vis)) o.y = NSMinY(inClip); else if (NSMaxY(inClip) > NSMaxY(vis)) o.y = NSMaxY(inClip) - vis.size.height;
  if (NSMinX(inClip) < NSMinX(vis)) o.x = NSMinX(inClip); else if (NSMaxX(inClip) > NSMaxX(vis)) o.x = NSMaxX(inClip) - vis.size.width;
  if (NSEqualPoints(o, vis.origin)) return NO;
  [(id)clip scrollToPoint:o]; return YES; }
- (BOOL)autoscroll:(NSEvent *)e { return NO; }
- (NSScrollView *)enclosingScrollView {
  for (NSView *v = _superview; v; v = v->_superview) if ([v isKindOfClass:NSClassFromString(@"NSScrollView")]) return (NSScrollView *)v;
  return nil; }
- (void)setToolTip:(NSString *)t { [t retain]; [_toolTip release]; _toolTip = t; }
- (NSString *)toolTip { return _toolTip; }
- (NSView *)ancestorSharedWithView:(NSView *)v {
  for (NSView *a = self; a; a = a->_superview) for (NSView *b = v; b; b = b->_superview) if (a == b) return a;
  return nil; }
- (BOOL)isDescendantOf:(NSView *)v { for (NSView *a = self; a; a = a->_superview) if (a == v) return YES; return NO; }
- (NSView *)opaqueAncestor { return self; }
- (void)lockFocus {
  NSWindow *w = _window; if (![w _xef2D]) return;
  [w _xefBacking];
  [NSGraphicsContext saveGraphicsState];
  CGContextRef c = (CGContextRef)w->_backing;
  [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:c flipped:[self isFlipped]]];
  CGContextSaveGState(c);
  CGContextConcatCTM(c, view_to_window(self)); }
- (void)unlockFocus {
  NSWindow *w = _window; if (![w _xef2D] || !w->_backing) return;
  CGContextRestoreGState((CGContextRef)w->_backing);
  [NSGraphicsContext restoreGraphicsState]; }
- (BOOL)lockFocusIfCanDraw { if (![self canDraw]) return NO; [self lockFocus]; return YES; }
- (void)drawFocusRingMask {} - (NSRect)focusRingMaskBounds { return _bounds; } - (void)noteFocusRingMaskChanged {}
- (NSInteger)focusRingType { return 0; } - (void)setFocusRingType:(NSInteger)t {}
- (CGFloat)alphaValue { return 1; } - (void)setAlphaValue:(CGFloat)a {}
- (NSColor *)backgroundColor { return nil; }
- (void)_xefDrawTree:(CGContextRef)c {
  if (_hidden) return;
  CGContextSaveGState(c);
  CGContextConcatCTM(c, view_to_super(self));
  CGContextClipToRect(c, _bounds);
  NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithCGContext:c flipped:[self isFlipped]];
  [NSGraphicsContext setCurrentContext:gc];
  _needsDisplay = NO;
  if (_layer) {   /* layer-backed view: the layer's background, corner radius and border */
    id<XEFLayerLike> L = (id<XEFLayerLike>)_layer;
    BOOL ok = [L respondsToSelector:@selector(cornerRadius)];
    CGColorRef bg = ok ? [L backgroundColor] : NULL, bc = ok ? [L borderColor] : NULL;
    CGFloat rad = ok ? [L cornerRadius] : 0, bw = ok ? [L borderWidth] : 0;
    CGPathRef p = rad > 0 ? CGPathCreateWithRoundedRect(_bounds, rad, rad, NULL) : CGPathCreateWithRect(_bounds, NULL);
    if (bg && CGColorGetAlpha(bg) > 0) { CGContextSaveGState(c); CGContextSetFillColorWithColor(c, bg); CGContextAddPath(c, p); CGContextFillPath(c); CGContextRestoreGState(c); }
    if (rad > 0) { CGContextAddPath(c, p); CGContextClip(c); }
    if (bw > 0 && bc) { CGContextSaveGState(c); CGContextSetStrokeColorWithColor(c, bc); CGContextSetLineWidth(c, bw * 2); CGContextAddPath(c, p); CGContextStrokePath(c); CGContextRestoreGState(c); }
    CGPathRelease(p); }
  CGContextSaveGState(c);
  @try { [self drawRect:_bounds]; }
  @catch (id e) { NSLog(@"xef: exception while drawing %@: %@", [self class], e); }
  CGContextRestoreGState(c);
  for (NSView *s in [[_subviews copy] autorelease]) [s _xefDrawTree:c];
  [NSGraphicsContext setCurrentContext:gc];
  CGContextSaveGState(c);
  if ([self respondsToSelector:@selector(_xefDrawOverlay)]) [self performSelector:@selector(_xefDrawOverlay)];
  CGContextRestoreGState(c);
  CGContextRestoreGState(c); }
@end

/* ================================================================== window backing store */
static int g_2d_mode = -1;   /* XEF_APPKIT_2D=0 disables */
static BOOL tree_uses_gpu(NSView *v) {
  if (!v) return NO;
  if (v->_glUsed) return YES;
  Class gl = NSClassFromString(@"NSOpenGLView"), ml = NSClassFromString(@"CAMetalLayer"), mtk = NSClassFromString(@"MTKView");
  if ((gl && [v isKindOfClass:gl]) || (mtk && [v isKindOfClass:mtk])) return YES;
  if (v->_layer && ml && [v->_layer isKindOfClass:ml]) return YES;
  for (NSView *s in v->_subviews) if (tree_uses_gpu(s)) return YES;
  return NO; }


/* XEF_APPKIT_TREE=1: prints each window's view tree when it is drawn */
static void dump_tree(NSView *v, int depth) {
  if (!v) return;
  NSString *extra = @"";
  if ([v respondsToSelector:@selector(drawsBackground)] && [v respondsToSelector:@selector(backgroundColor)])
    extra = [NSString stringWithFormat:@" drawsBg=%d bg=%@", (int)[(id)v drawsBackground], [(id)v backgroundColor]];
  if (v->_layer) { id<XEFLayerLike> L = (id<XEFLayerLike>)v->_layer; extra = [extra stringByAppendingFormat:@" layer=%s bg=%@ wants=%d", class_getName([v->_layer class]),
                   [L respondsToSelector:@selector(cornerRadius)] && [L backgroundColor] ? [NSColor colorWithCGColor:[L backgroundColor]] : nil, (int)v->_wantsLayer]; }
  fprintf(stderr, "xef: %*s%s frame %s bounds %s%s%s%s\n", depth * 2, "", class_getName([v class]), [NSStringFromRect(v->_frame) UTF8String],
          [NSStringFromRect(v->_bounds) UTF8String], [v isFlipped] ? " flipped" : "", v->_hidden ? " HIDDEN" : "", [extra UTF8String]);
  for (NSView *s in v->_subviews) dump_tree(s, depth + 1); }

/* XEF_APPKIT_SHOT=out.ppm [XEF_APPKIT_SHOT_FRAME=N, default 1] [XEF_APPKIT_SHOT_EXIT=1]: saves the Nth presented window frame */
static void dump_shot(const unsigned char *px, size_t w, size_t h) {
  static int frame = 0; static const char *path; static int want = -1;
  if (want < 0) { path = getenv("XEF_APPKIT_SHOT"); const char *n = getenv("XEF_APPKIT_SHOT_FRAME"); want = n ? atoi(n) : 1; }
  if (!path || ++frame != want) return;
  FILE *f = fopen(path, "wb"); if (!f) return;
  fprintf(f, "P6\n%zu %zu\n255\n", w, h);
  for (size_t i = 0; i < w * h; i++) { unsigned char rgb[3] = { px[i * 4 + 2], px[i * 4 + 1], px[i * 4] }; fwrite(rgb, 1, 3, f); }
  fclose(f);
  fprintf(stderr, "xef: AppKit frame %d saved to %s\n", frame, path);
  const char *ex = getenv("XEF_APPKIT_SHOT_EXIT"); if (ex && ex[0] == '1') exit(0); }

@implementation NSWindow (XEFBacking)
- (BOOL)_xef2D {
  if (g_2d_mode < 0) { const char *e = getenv("XEF_APPKIT_2D"); g_2d_mode = !(e && e[0] == '0'); }
  if (!g_2d_mode || _no2D || _handle <= 0) return NO;
  if (tree_uses_gpu(_content)) { _no2D = YES; return NO; }
  return YES; }
- (void)_xefBacking {
  NSRect c = [self contentRectForFrameRect:_frame];
  size_t w = (size_t)fmax(1, ceil(c.size.width)), h = (size_t)fmax(1, ceil(c.size.height));
  CGContextRef b = (CGContextRef)_backing;
  if (b && CGBitmapContextGetWidth(b) == w && CGBitmapContextGetHeight(b) == h) return;
  if (b) CGContextRelease(b);
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  _backing = CGBitmapContextCreate(NULL, w, h, 8, w * 4, cs, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
  CGColorSpaceRelease(cs); }
- (void)_xefRedraw {
  if (![self _xef2D]) return;
  [_content layoutSubtreeIfNeeded];
  [self _xefBacking];
  CGContextRef c = (CGContextRef)_backing;
  if (!c) return;
  _dirty2D = NO;
  NSGraphicsContext *saved = [[[NSGraphicsContext currentContext] retain] autorelease];
  size_t w = CGBitmapContextGetWidth(c), h = CGBitmapContextGetHeight(c);
  CGContextSaveGState(c);
  NSColor *bg = [self backgroundColor];
  CGContextSetBlendMode(c, kCGBlendModeCopy);
  CGContextSetRGBFillColor(c, bg->r, bg->g, bg->b, _opaque ? 1 : bg->a);
  CGContextFillRect(c, CGRectMake(0, 0, w, h));
  CGContextRestoreGState(c);
  if (getenv("XEF_APPKIT_TREE")) {
    fprintf(stderr, "xef: window %p %s '%s' frame %s bg %s\n", self, class_getName([self class]), [[self title] UTF8String],
            [NSStringFromRect(_frame) UTF8String], [[[self backgroundColor] description] UTF8String]);
    dump_tree(_content, 1); }
  [_content _xefDrawTree:c];
  [NSGraphicsContext setCurrentContext:saved];
  CGContextFlush(c);
  xef_host_present_pixels(_handle, CGBitmapContextGetData(c), (int)w, (int)h, 80 /* MTLPixelFormatBGRA8Unorm */);
  if (!objc_getAssociatedObject(self, "xef.popup")) dump_shot(CGBitmapContextGetData(c), w, h); }
- (NSGraphicsContext *)graphicsContext { [self _xefBacking]; return [NSGraphicsContext graphicsContextWithCGContext:(CGContextRef)_backing flipped:NO]; }
- (void)setViewsNeedDisplay:(BOOL)f { if (f) _dirty2D = YES; }
- (BOOL)viewsNeedDisplay { return _dirty2D; }
- (void)displayIfNeeded { if ([self _xef2D]) { if (_dirty2D) [self _xefRedraw]; } else [_content displayIfNeeded]; }
- (void)disableFlushWindow {} - (void)enableFlushWindow {} - (void)flushWindowIfNeeded {}
- (BOOL)isFlushWindowDisabled { return NO; }
- (void)useOptimizedDrawing:(BOOL)f {}
- (void)setAutodisplay:(BOOL)f {} - (BOOL)isAutodisplay { return YES; }
@end

/* decoding through the host (gdk-pixbuf): anything it can read becomes a premultiplied RGBA bitmap rep */
@implementation NSBitmapImageRep (XEFDecode)
- (id)initWithData:(NSData *)data {
  int wh[2] = {0, 0}; int h = [data length] ? xef_host_image_decode([data bytes], [data length], wh) : 0;
  if (!h) { [self release]; return nil; }
  if (!(self = [self initWithBitmapDataPlanes:NULL pixelsWide:wh[0] pixelsHigh:wh[1] bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                               colorSpaceName:@"NSDeviceRGBColorSpace" bitmapFormat:0 bytesPerRow:wh[0] * 4 bitsPerPixel:32])) { xef_host_image_free(h); return nil; }
  xef_host_image_copy(h, _data); xef_host_image_free(h);
  for (NSInteger i = 0, n = _w * _h; i < n; i++) {   /* premultiply */
    unsigned char *px = _data + i * 4; unsigned a = px[3];
    if (a != 255) { px[0] = (px[0] * a + 127) / 255; px[1] = (px[1] * a + 127) / 255; px[2] = (px[2] * a + 127) / 255; } }
  return self; }
+ (id)imageRepWithData:(NSData *)d { return [[[self alloc] initWithData:d] autorelease]; }
+ (id)imageRepWithContentsOfFile:(NSString *)p { NSData *d = [NSData dataWithContentsOfFile:p]; return d ? [self imageRepWithData:d] : nil; }
@end

@implementation NSImage (XEFDecode)
- (id)initWithData:(NSData *)data {
  Class rc = [NSImageRep imageRepClassForData:data]; id rep = rc ? [[rc imageRepsWithData:data] firstObject] : nil;
  if (!rep) { [self release]; return nil; }
  NSSize sz = [rep isKindOfClass:[NSBitmapImageRep class]] ? NSMakeSize([rep pixelsWide], [rep pixelsHigh]) : [rep size];
  if (!(self = [self initWithSize:sz])) return nil;
  [self addRepresentation:rep]; return self; }
- (id)initWithContentsOfFile:(NSString *)path {
  NSData *d = path ? [NSData dataWithContentsOfFile:path] : nil;
  if (!d) { [self release]; return nil; }
  return [self initWithData:d]; }
- (id)initWithContentsOfURL:(NSURL *)u { return [u isFileURL] ? [self initWithContentsOfFile:[u path]] : ([self release], nil); }
- (id)initByReferencingFile:(NSString *)p { return [self initWithContentsOfFile:p]; }
- (id)initByReferencingURL:(NSURL *)u { return [self initWithContentsOfURL:u]; }
@end

/* ---- encoding, pixel access, image focus and drawing handlers ---- */
@interface NSColor (XEFPix)
+ (NSColor *)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
- (void)getRed:(CGFloat *)r green:(CGFloat *)g blue:(CGFloat *)b alpha:(CGFloat *)a;
@end
@implementation NSBitmapImageRep (XEFEncode)
- (BOOL)isPlanar { return NO; } - (NSInteger)numberOfPlanes { return 1; } - (NSInteger)bytesPerPlane { return _bpr * _h; }
- (NSBitmapFormat)bitmapFormat { return _fmt; }
- (void)getBitmapDataPlanes:(unsigned char **)p { if (p) p[0] = _data; }
/* RGBA8 non-premultiplied copy of the pixels (what the host encoder takes) */
- (unsigned char *)_xefCopyRGBA {
  if (!_data || _bps != 8 || _spp < 1) return NULL;
  unsigned char *o = malloc((size_t)_w * _h * 4); if (!o) return NULL;
  BOOL first = (_fmt & NSBitmapFormatAlphaFirst) != 0, nonpre = (_fmt & NSBitmapFormatAlphaNonpremultiplied) != 0;
  for (NSInteger y = 0; y < _h; y++) for (NSInteger x = 0; x < _w; x++) {
    const unsigned char *p = _data + y * _bpr + x * (_bpp / 8); unsigned char *q = o + (y * _w + x) * 4; unsigned a = 255, r, g, b;
    NSInteger colors = _alpha ? _spp - 1 : _spp, base = (_alpha && first) ? 1 : 0;
    if (_alpha) a = first ? p[0] : p[colors];
    if (colors >= 3) { r = p[base]; g = p[base + 1]; b = p[base + 2]; } else { r = g = b = p[base]; }
    if (_alpha && !nonpre && a && a != 255) { r = MIN(255, (r * 255 + a / 2) / a); g = MIN(255, (g * 255 + a / 2) / a); b = MIN(255, (b * 255 + a / 2) / a); }
    q[0] = r; q[1] = g; q[2] = b; q[3] = a; }
  return o; }
- (NSData *)representationUsingType:(NSUInteger)type properties:(NSDictionary *)props {
  static const char *names[] = { "tiff", "bmp", NULL /* GIF: no writer */, "jpeg", "png", NULL /* JPEG 2000 */ };
  if (type > 5 || !names[type]) return nil;
  unsigned char *rgba = [self _xefCopyRGBA]; if (!rgba) return nil;
  NSNumber *q = props[@"NSImageCompressionFactor"];
  unsigned long len = 0; int h = xef_host_image_encode(rgba, (int)_w, (int)_h, names[type], q ? (int)([q doubleValue] * 100) : -1, &len);
  free(rgba); if (!h) return nil;
  NSMutableData *d = [NSMutableData dataWithLength:len]; xef_host_blob_copy(h, [d mutableBytes]); xef_host_blob_free(h); return d; }
+ (NSData *)representationOfImageRepsInArray:(NSArray *)a usingType:(NSUInteger)t properties:(NSDictionary *)p {
  for (id r in a) if ([r isKindOfClass:[NSBitmapImageRep class]]) return [r representationUsingType:t properties:p]; return nil; }
- (NSData *)TIFFRepresentation { return [self representationUsingType:0 properties:nil]; }
- (NSData *)TIFFRepresentationUsingCompression:(NSUInteger)c factor:(float)f { return [self TIFFRepresentation]; }
+ (NSData *)TIFFRepresentationOfImageRepsInArray:(NSArray *)a { return [self representationOfImageRepsInArray:a usingType:0 properties:nil]; }
+ (NSArray *)imageRepsWithData:(NSData *)d { id r = [[[self alloc] initWithData:d] autorelease]; return r ? @[r] : @[]; }
- (void)getPixel:(NSUInteger *)px atX:(NSInteger)x y:(NSInteger)y {
  if (x < 0 || y < 0 || x >= _w || y >= _h || !_data || _bps != 8) return;
  const unsigned char *p = _data + y * _bpr + x * (_bpp / 8); for (NSInteger i = 0; i < _spp; i++) px[i] = p[i]; }
- (void)setPixel:(NSUInteger *)px atX:(NSInteger)x y:(NSInteger)y {
  if (x < 0 || y < 0 || x >= _w || y >= _h || !_data || _bps != 8) return;
  unsigned char *p = _data + y * _bpr + x * (_bpp / 8); for (NSInteger i = 0; i < _spp; i++) p[i] = (unsigned char)px[i];
  objc_setAssociatedObject(self, "xef.cgimage", nil, OBJC_ASSOCIATION_RETAIN); }
- (NSColor *)colorAtX:(NSInteger)x y:(NSInteger)y {
  if (x < 0 || y < 0 || x >= _w || y >= _h) return nil;
  unsigned char *rgba = [self _xefCopyRGBA]; if (!rgba) return nil;
  const unsigned char *q = rgba + (y * _w + x) * 4;
  NSColor *c = [NSColor colorWithRed:q[0] / 255.0 green:q[1] / 255.0 blue:q[2] / 255.0 alpha:q[3] / 255.0]; free(rgba); return c; }
- (void)setColor:(NSColor *)c atX:(NSInteger)x y:(NSInteger)y {
  if (x < 0 || y < 0 || x >= _w || y >= _h || !_data || _bps != 8 || _spp < 3) return;
  CGFloat r = 0, g = 0, b = 0, a = 1; [c getRed:&r green:&g blue:&b alpha:&a];
  BOOL first = (_fmt & NSBitmapFormatAlphaFirst) != 0, nonpre = (_fmt & NSBitmapFormatAlphaNonpremultiplied) != 0; CGFloat m = (_alpha && !nonpre) ? a : 1;
  unsigned char *p = _data + y * _bpr + x * (_bpp / 8); NSInteger base = (_alpha && first) ? 1 : 0;
  p[base] = (unsigned char)(r * m * 255 + 0.5); p[base + 1] = (unsigned char)(g * m * 255 + 0.5); p[base + 2] = (unsigned char)(b * m * 255 + 0.5);
  if (_alpha) p[first ? 0 : 3] = (unsigned char)(a * 255 + 0.5);
  objc_setAssociatedObject(self, "xef.cgimage", nil, OBJC_ASSOCIATION_RETAIN); }
@end

typedef BOOL (^XEFImageDrawingHandler)(NSRect);
@implementation NSImage (XEFFocus)
+ (NSImage *)imageWithSize:(NSSize)s flipped:(BOOL)f drawingHandler:(BOOL (^)(NSRect))h {
  NSImage *i = [[[NSImage alloc] initWithSize:s] autorelease];
  objc_setAssociatedObject(i, "xef.handler", [[h copy] autorelease], OBJC_ASSOCIATION_RETAIN);
  objc_setAssociatedObject(i, "xef.handlerFlipped", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); return i; }
/* a bitmap the image draws into while focused (also used for the handler render) */
- (NSBitmapImageRep *)_xefNewTarget {
  NSInteger w = (NSInteger)ceil(_size.width), h = (NSInteger)ceil(_size.height); if (w < 1) w = 1; if (h < 1) h = 1;
  return [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
              colorSpaceName:@"NSDeviceRGBColorSpace" bitmapFormat:0 bytesPerRow:w * 4 bitsPerPixel:32] autorelease]; }
- (void)lockFocusFlipped:(BOOL)f {
  NSBitmapImageRep *t = [self _xefNewTarget]; objc_setAssociatedObject(self, "xef.focus", t, OBJC_ASSOCIATION_RETAIN);
  [NSGraphicsContext saveGraphicsState];
  NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithBitmapImageRep:t]; [NSGraphicsContext setCurrentContext:gc];
  if (f) { CGContextRef c = XEFCurrentCGContext(); CGContextTranslateCTM(c, 0, _size.height); CGContextScaleCTM(c, 1, -1); } }
- (void)lockFocus { [self lockFocusFlipped:NO]; }
- (void)unlockFocus {
  NSBitmapImageRep *t = objc_getAssociatedObject(self, "xef.focus"); if (!t) return;
  [NSGraphicsContext restoreGraphicsState];
  [_reps removeAllObjects]; [self addRepresentation:t]; objc_setAssociatedObject(self, "xef.focus", nil, OBJC_ASSOCIATION_RETAIN); }
- (void)_xefRenderHandler {
  XEFImageDrawingHandler h = objc_getAssociatedObject(self, "xef.handler"); if (!h) return;
  BOOL f = [objc_getAssociatedObject(self, "xef.handlerFlipped") boolValue];
  NSBitmapImageRep *t = [self _xefNewTarget];
  [NSGraphicsContext saveGraphicsState];
  [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:t]];
  if (f) { CGContextRef c = XEFCurrentCGContext(); CGContextTranslateCTM(c, 0, _size.height); CGContextScaleCTM(c, 1, -1); }
  h(NSMakeRect(0, 0, _size.width, _size.height));
  [NSGraphicsContext restoreGraphicsState];
  [self addRepresentation:t]; objc_setAssociatedObject(self, "xef.handler", nil, OBJC_ASSOCIATION_RETAIN); }
- (void)addRepresentations:(NSArray *)a { for (id r in a) [self addRepresentation:r]; }
- (void)removeRepresentation:(id)r { [_reps removeObjectIdenticalTo:r]; }
- (id)bestRepresentationForRect:(NSRect)r context:(NSGraphicsContext *)c hints:(NSDictionary *)h { return [self _xefBitmap] ?: [_reps firstObject]; }
- (id)bestRepresentationForDevice:(id)d { return [self _xefBitmap] ?: [_reps firstObject]; }
- (void)drawRepresentation:(id)rep inRect:(NSRect)r { if ([rep respondsToSelector:@selector(drawInRect:)]) [rep drawInRect:r]; }
- (id)initWithDataIgnoringOrientation:(NSData *)d { return [self initWithData:d]; }
- (NSData *)TIFFRepresentation { return [[self _xefBitmap] TIFFRepresentation]; }
- (NSData *)TIFFRepresentationUsingCompression:(NSUInteger)c factor:(float)f { return [self TIFFRepresentation]; }
- (id)copyWithZone:(NSZone *)z { NSImage *c = [[NSImage alloc] initWithSize:_size]; [c addRepresentations:_reps]; return c; }
+ (NSArray *)imageTypes { return @[@"public.png", @"public.jpeg", @"public.tiff", @"com.compuserve.gif", @"com.microsoft.bmp", @"org.webmproject.webp"]; }
+ (NSArray *)imageUnfilteredTypes { return [self imageTypes]; }
+ (NSArray *)imageUnfilteredFileTypes { return @[@"png", @"jpg", @"jpeg", @"tif", @"tiff", @"gif", @"bmp", @"webp"]; }
+ (NSArray *)imageFileTypes { return [self imageUnfilteredFileTypes]; }
+ (BOOL)canInitWithPasteboard:(id)p { return NO; }
@end

/* ---- NSImageRep: the base class, the registry, and NSCustomImageRep ---- */
static NSMutableArray *g_rep_classes;
static NSMutableArray *XEFRepClasses(void) { if (!g_rep_classes) g_rep_classes = [[NSMutableArray alloc] initWithObjects:[NSBitmapImageRep class], [NSPDFImageRep class], [NSEPSImageRep class], nil]; return g_rep_classes; }
@implementation NSImageRep
- (void)dealloc { [_rcs release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (void)encodeWithCoder:(NSCoder *)c {} - (id)initWithCoder:(NSCoder *)c { return [self init]; }
- (NSSize)size { return _sizeSet ? _repSize : NSMakeSize([self pixelsWide], [self pixelsHigh]); } - (void)setSize:(NSSize)s { _repSize = s; _sizeSet = YES; }
- (BOOL)hasAlpha { return _ralpha; } - (void)setAlpha:(BOOL)f { _ralpha = f; }
- (BOOL)isOpaque { return _ropaque; } - (void)setOpaque:(BOOL)f { _ropaque = f; }
- (NSString *)colorSpaceName { return _rcs; } - (void)setColorSpaceName:(NSString *)n { [n retain]; [_rcs release]; _rcs = n; }
- (NSInteger)bitsPerSample { return _rbps; } - (void)setBitsPerSample:(NSInteger)n { _rbps = n; }
- (NSInteger)pixelsWide { return _rpw; } - (void)setPixelsWide:(NSInteger)n { _rpw = n; }
- (NSInteger)pixelsHigh { return _rph; } - (void)setPixelsHigh:(NSInteger)n { _rph = n; }
- (NSInteger)layoutDirection { return _rdir; } - (void)setLayoutDirection:(NSInteger)d { _rdir = d; }
- (BOOL)drawInRect:(NSRect)r { return NO; }
- (BOOL)draw { NSSize s = [self size]; return [self drawInRect:NSMakeRect(0, 0, s.width, s.height)]; }
- (BOOL)drawAtPoint:(NSPoint)p { NSSize s = [self size]; return [self drawInRect:NSMakeRect(p.x, p.y, s.width, s.height)]; }
- (BOOL)drawInRect:(NSRect)r fromRect:(NSRect)s operation:(NSUInteger)op fraction:(CGFloat)f respectFlipped:(BOOL)rf hints:(NSDictionary *)h { return [self drawInRect:r]; }
- (CGImageRef)CGImageForProposedRect:(NSRect *)r context:(NSGraphicsContext *)c hints:(NSDictionary *)h { return NULL; }
+ (void)registerImageRepClass:(Class)c { if (![XEFRepClasses() containsObject:c]) [XEFRepClasses() addObject:c]; }
+ (void)unregisterImageRepClass:(Class)c { [XEFRepClasses() removeObject:c]; }
+ (NSArray *)registeredImageRepClasses { return [[XEFRepClasses() copy] autorelease]; }
+ (BOOL)canInitWithData:(NSData *)d { return NO; } + (BOOL)canInitWithPasteboard:(id)p { return NO; }
+ (Class)imageRepClassForData:(NSData *)d { for (Class c in [[XEFRepClasses() copy] autorelease]) if ([c canInitWithData:d]) return c; return nil; }
+ (Class)imageRepClassForType:(NSString *)t { return [self imageRepClassForFileType:t]; }
+ (Class)imageRepClassForFileType:(NSString *)t { for (Class c in XEFRepClasses()) if ([[c imageUnfilteredFileTypes] containsObject:[t lowercaseString]] || [[c imageUnfilteredTypes] containsObject:t]) return c; return nil; }
+ (Class)imageRepClassForPasteboardType:(NSString *)t { return nil; }
+ (NSArray *)imageUnfilteredTypes { return @[]; } + (NSArray *)imageTypes { return [self imageUnfilteredTypes]; }
+ (NSArray *)imageUnfilteredFileTypes { return @[]; } + (NSArray *)imageFileTypes { return [self imageUnfilteredFileTypes]; }
+ (NSArray *)imageUnfilteredPasteboardTypes { return @[]; } + (NSArray *)imagePasteboardTypes { return @[]; }
+ (NSArray *)imageRepsWithContentsOfFile:(NSString *)p { NSData *d = p ? [NSData dataWithContentsOfFile:p] : nil; if (!d) return nil; Class c = [self imageRepClassForData:d]; return c ? [c imageRepsWithData:d] : nil; }
+ (id)imageRepWithContentsOfFile:(NSString *)p { return [[self imageRepsWithContentsOfFile:p] firstObject]; }
+ (NSArray *)imageRepsWithContentsOfURL:(NSURL *)u { return [u isFileURL] ? [self imageRepsWithContentsOfFile:[u path]] : nil; }
+ (id)imageRepWithContentsOfURL:(NSURL *)u { return [[self imageRepsWithContentsOfURL:u] firstObject]; }
+ (NSArray *)imageRepsWithData:(NSData *)d { return @[]; }
+ (NSArray *)imageRepsWithPasteboard:(id)p { return nil; } + (id)imageRepWithPasteboard:(id)p { return nil; }
@end
@implementation NSBitmapImageRep (XEFRepBase)
+ (BOOL)canInitWithData:(NSData *)d {
  const unsigned char *b = [d bytes]; NSUInteger n = [d length]; if (n < 4) return NO;
  return !memcmp(b, "\x89PNG", 4) || !memcmp(b, "\xff\xd8\xff", 3) || !memcmp(b, "GIF8", 4) || !memcmp(b, "II*\0", 4) || !memcmp(b, "MM\0*", 4) || !memcmp(b, "BM", 2) || (n > 12 && !memcmp(b, "RIFF", 4) && !memcmp(b + 8, "WEBP", 4)); }
+ (NSArray *)imageUnfilteredFileTypes { return @[@"png", @"jpg", @"jpeg", @"tif", @"tiff", @"gif", @"bmp", @"webp"]; }
+ (NSArray *)imageUnfilteredTypes { return @[@"public.png", @"public.jpeg", @"public.tiff", @"com.compuserve.gif", @"com.microsoft.bmp", @"org.webmproject.webp"]; }
- (BOOL)hasAlpha { return _alpha; } - (NSInteger)bitsPerSample { return _bps; } - (NSString *)colorSpaceName { return _cs; } - (BOOL)isOpaque { return _sizeSet ? _ropaque : !_alpha || YES; }
- (NSSize)size { return _sizeSet ? _repSize : NSMakeSize(_w, _h); }
@end

@implementation NSCustomImageRep
- (id)initWithDrawSelector:(SEL)s delegate:(id)d { if ((self = [super init])) { _sel = s; _delegate = d; } return self; }
- (id)initWithSize:(NSSize)s flipped:(BOOL)f drawingHandler:(BOOL (^)(NSRect))h { if ((self = [super init])) { [self setSize:s]; _flipped = f; _handler = [h copy]; } return self; }
- (void)dealloc { [_handler release]; [super dealloc]; }
- (id)delegate { return _delegate; } - (SEL)drawSelector { return _sel; } - (id)drawingHandler { return _handler; }
- (BOOL)drawInRect:(NSRect)r {
  CGContextRef c = XEFCurrentCGContext(); if (!c) return NO;
  NSSize s = [self size]; if (s.width <= 0 || s.height <= 0) return NO;
  CGContextSaveGState(c); CGContextTranslateCTM(c, r.origin.x, r.origin.y); CGContextScaleCTM(c, r.size.width / s.width, r.size.height / s.height);
  BOOL ok = NO;
  if (_handler) ok = ((BOOL (^)(NSRect))_handler)(NSMakeRect(0, 0, s.width, s.height));
  else if (_delegate && _sel) ok = ((BOOL (*)(id, SEL, id))objc_msgSend)(_delegate, _sel, self);
  CGContextRestoreGState(c); return ok; }
@end

/* ---- NSColor: CMYK components, HSB factory with a colour space, pattern colours, extra system colours ---- */
@implementation NSColor (XEFMore)
- (void)_xefCMYK:(CGFloat *)c m:(CGFloat *)m y:(CGFloat *)y k:(CGFloat *)k {
  NSArray *st = objc_getAssociatedObject(self, "xef.cmyk");
  if (st) { *c = [st[0] doubleValue]; *m = [st[1] doubleValue]; *y = [st[2] doubleValue]; *k = [st[3] doubleValue]; return; }
  CGFloat kk = 1 - MAX(r, MAX(g, b)); if (kk >= 1) { *c = *m = *y = 0; *k = 1; return; }
  *k = kk; *c = (1 - r - kk) / (1 - kk); *m = (1 - g - kk) / (1 - kk); *y = (1 - b - kk) / (1 - kk); }
- (CGFloat)cyanComponent { CGFloat c, m, y, k; [self _xefCMYK:&c m:&m y:&y k:&k]; return c; } - (CGFloat)magentaComponent { CGFloat c, m, y, k; [self _xefCMYK:&c m:&m y:&y k:&k]; return m; }
- (CGFloat)yellowComponent { CGFloat c, m, y, k; [self _xefCMYK:&c m:&m y:&y k:&k]; return y; } - (CGFloat)blackComponent { CGFloat c, m, y, k; [self _xefCMYK:&c m:&m y:&y k:&k]; return k; }
- (void)getCyan:(CGFloat *)c magenta:(CGFloat *)m yellow:(CGFloat *)y black:(CGFloat *)k alpha:(CGFloat *)al { CGFloat cc, mm, yy, kk; [self _xefCMYK:&cc m:&mm y:&yy k:&kk]; if (c) *c = cc; if (m) *m = mm; if (y) *y = yy; if (k) *k = kk; if (al) *al = a; }
+ (NSColor *)colorWithColorSpace:(id)cs hue:(CGFloat)h saturation:(CGFloat)s brightness:(CGFloat)v alpha:(CGFloat)al { return [self colorWithHue:h saturation:s brightness:v alpha:al]; }
+ (NSColor *)colorWithPatternImage:(NSImage *)i { NSColor *c = [NSColor colorWithCalibratedRed:.5 green:.5 blue:.5 alpha:1]; objc_setAssociatedObject(c, "xef.pattern", [[i copy] autorelease], OBJC_ASSOCIATION_RETAIN); return c; }
- (NSImage *)patternImage { return objc_getAssociatedObject(self, "xef.pattern"); }
+ (NSColor *)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)al exposure:(CGFloat)e { return [self colorWithRed:r green:g blue:b alpha:al]; }
+ (NSColor *)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)al linearExposure:(CGFloat)e { return [self colorWithRed:r green:g blue:b alpha:al]; }
- (CGFloat)linearExposure { return 1; } - (NSColor *)standardDynamicRangeColor { return self; } - (NSColor *)colorByApplyingContentHeadroom:(CGFloat)h { return self; }
+ (NSColor *)selectedMenuItemTextColor { return [NSColor whiteColor]; } + (NSColor *)selectedMenuItemColor { return [NSColor colorWithCalibratedRed:.04 green:.52 blue:1 alpha:1]; }
+ (NSColor *)textInsertionPointColor { return [NSColor blackColor]; } + (NSColor *)quinarySystemFillColor { return [NSColor colorWithCalibratedRed:.5 green:.5 blue:.5 alpha:.04]; }
+ (NSColor *)scrubberTexturedBackgroundColor { return [NSColor colorWithCalibratedRed:.2 green:.2 blue:.2 alpha:1]; }
+ (NSInteger)currentControlTint { return 1; } + (NSColor *)colorForControlTint:(NSInteger)t { return [NSColor colorWithCalibratedRed:.04 green:.52 blue:1 alpha:1]; }
+ (NSColor *)colorWithCIColor:(id)c { return nil; } + (NSColor *)colorFromPasteboard:(id)p { return nil; } - (void)writeToPasteboard:(id)p {}
- (NSString *)localizedCatalogNameComponent { return nil; } - (NSString *)localizedColorNameComponent { return nil; }
@end

/* ---- NSImage: stored settings, deprecated compositing, hit testing ---- */
static id XEFImgGet(id o, const char *k) { return objc_getAssociatedObject(o, k); }
static void XEFImgSet(id o, const char *k, id v) { objc_setAssociatedObject(o, k, v, OBJC_ASSOCIATION_RETAIN); }
@implementation NSImage (XEFSettings)
- (NSColor *)backgroundColor { return XEFImgGet(self, "xef.bg") ?: [NSColor clearColor]; } - (void)setBackgroundColor:(NSColor *)c { XEFImgSet(self, "xef.bg", c); }
- (id)delegate { return XEFImgGet(self, "xef.delegate"); } - (void)setDelegate:(id)d { objc_setAssociatedObject(self, "xef.delegate", d, OBJC_ASSOCIATION_ASSIGN); }
- (BOOL)usesEPSOnResolutionMismatch { return [XEFImgGet(self, "xef.eps") boolValue]; } - (void)setUsesEPSOnResolutionMismatch:(BOOL)f { XEFImgSet(self, "xef.eps", [NSNumber numberWithBool:f]); }
- (BOOL)prefersColorMatch { return [XEFImgGet(self, "xef.pcm") ?: @YES boolValue]; } - (void)setPrefersColorMatch:(BOOL)f { XEFImgSet(self, "xef.pcm", [NSNumber numberWithBool:f]); }
- (BOOL)matchesOnMultipleResolution { return [XEFImgGet(self, "xef.mmr") ?: @YES boolValue]; } - (void)setMatchesOnMultipleResolution:(BOOL)f { XEFImgSet(self, "xef.mmr", [NSNumber numberWithBool:f]); }
- (BOOL)matchesOnlyOnBestFittingAxis { return [XEFImgGet(self, "xef.mba") boolValue]; } - (void)setMatchesOnlyOnBestFittingAxis:(BOOL)f { XEFImgSet(self, "xef.mba", [NSNumber numberWithBool:f]); }
- (NSInteger)cacheMode { return [XEFImgGet(self, "xef.cm") integerValue]; } - (void)setCacheMode:(NSInteger)m { XEFImgSet(self, "xef.cm", [NSNumber numberWithInteger:m]); }
- (void)setAlignmentRect:(NSRect)r { XEFImgSet(self, "xef.align", [NSValue valueWithRect:r]); }
- (BOOL)scalesWhenResized { return [XEFImgGet(self, "xef.swr") boolValue]; } - (void)setScalesWhenResized:(BOOL)f { XEFImgSet(self, "xef.swr", [NSNumber numberWithBool:f]); }
- (BOOL)isDataRetained { return [XEFImgGet(self, "xef.dr") boolValue]; } - (void)setDataRetained:(BOOL)f { XEFImgSet(self, "xef.dr", [NSNumber numberWithBool:f]); }
- (BOOL)isCachedSeparately { return [XEFImgGet(self, "xef.cs") boolValue]; } - (void)setCachedSeparately:(BOOL)f { XEFImgSet(self, "xef.cs", [NSNumber numberWithBool:f]); }
- (BOOL)cacheDepthMatchesImageDepth { return [XEFImgGet(self, "xef.cdm") boolValue]; } - (void)setCacheDepthMatchesImageDepth:(BOOL)f { XEFImgSet(self, "xef.cdm", [NSNumber numberWithBool:f]); }
- (id)symbolConfiguration { return nil; } - (NSLocale *)locale { return nil; } - (NSImage *)imageWithLocale:(NSLocale *)l { return self; }
+ (NSImage *)imageWithSystemSymbolName:(NSString *)n variableValue:(double)v accessibilityDescription:(NSString *)d { return nil; }
+ (NSImage *)imageWithSymbolName:(NSString *)n variableValue:(double)v { return nil; } + (NSImage *)imageWithSymbolName:(NSString *)n bundle:(NSBundle *)b variableValue:(double)v { return nil; }
- (id)initWithPasteboard:(id)p { [self release]; return nil; } - (id)initWithIconRef:(void *)r { return [self initWithSize:NSMakeSize(32, 32)]; }
+ (NSArray *)readableTypesForPasteboard:(id)p { return @[]; } - (NSArray *)writableTypesForPasteboard:(id)p { return @[]; } + (NSArray *)imageUnfilteredPasteboardTypes { return @[]; } + (NSArray *)imagePasteboardTypes { return @[]; }
- (CGFloat)recommendedLayerContentsScale:(CGFloat)s { return s < 1 ? 1 : ceil(s); } - (id)layerContentsForContentsScale:(CGFloat)s { return (id)[self CGImageForProposedRect:NULL context:nil hints:nil]; }
- (BOOL)hitTestRect:(NSRect)r withImageDestinationRect:(NSRect)d context:(NSGraphicsContext *)c hints:(NSDictionary *)h flipped:(BOOL)f {
  NSBitmapImageRep *b = [self _xefBitmap]; if (!b || NSIsEmptyRect(d)) return NO;
  NSRect hit = NSIntersectionRect(r, d); if (NSIsEmptyRect(hit)) return NO;
  NSInteger px = (NSInteger)((NSMidX(hit) - d.origin.x) / d.size.width * [b pixelsWide]), py = (NSInteger)((NSMidY(hit) - d.origin.y) / d.size.height * [b pixelsHigh]);
  if (!f) py = [b pixelsHigh] - 1 - py; NSColor *col = [b colorAtX:px y:py]; return col && [col alphaComponent] > 0.01; }
- (void)dissolveToPoint:(NSPoint)p fromRect:(NSRect)s fraction:(CGFloat)f { [self drawAtPoint:p fromRect:s operation:2 fraction:f]; }
- (void)compositeToPoint:(NSPoint)p fromRect:(NSRect)s operation:(NSUInteger)op { [self drawAtPoint:p fromRect:s operation:op fraction:1]; }
- (void)compositeToPoint:(NSPoint)p operation:(NSUInteger)op fraction:(CGFloat)f { [self drawAtPoint:p fromRect:NSZeroRect operation:op fraction:f]; }
- (void)compositeToPoint:(NSPoint)p fromRect:(NSRect)s operation:(NSUInteger)op fraction:(CGFloat)f { [self drawAtPoint:p fromRect:s operation:op fraction:f]; }
- (void)lockFocusOnRepresentation:(id)rep { [self lockFocus]; } - (void)cancelIncrementalLoad {}
@end

/* ---- NSPDFImageRep: pages rendered by the host (poppler-utils) on demand ---- */
@implementation NSPDFImageRep
+ (BOOL)canInitWithData:(NSData *)d { return [d length] > 4 && !memcmp([d bytes], "%PDF", 4); }
+ (NSArray *)imageUnfilteredTypes { return @[@"com.adobe.pdf"]; } + (NSArray *)imageUnfilteredFileTypes { return @[@"pdf"]; }
+ (NSArray *)imageRepsWithData:(NSData *)d { id r = [[[self alloc] initWithData:d] autorelease]; return r ? @[r] : @[]; }
+ (id)imageRepWithData:(NSData *)d { return [[[self alloc] initWithData:d] autorelease]; }
- (id)initWithData:(NSData *)d {
  int pages = 0; double wh[2] = {0, 0};
  if (![d length] || !xef_host_pdf_info([d bytes], [d length], &pages, wh)) { [self release]; return nil; }
  if ((self = [super init])) { _pdf = [d copy]; _pages = pages; _bounds = NSMakeRect(0, 0, wh[0], wh[1]); _ralpha = YES; _rbps = 0; _rcs = [@"NSDeviceRGBColorSpace" retain]; }
  return self; }
- (void)dealloc { [_pdf release]; [super dealloc]; }
- (NSInteger)pageCount { return _pages; } - (NSInteger)currentPage { return _page; } - (void)setCurrentPage:(NSInteger)p { _page = p < 0 ? 0 : p >= _pages ? _pages - 1 : p; }
- (NSRect)bounds { return _bounds; } - (NSData *)PDFRepresentation { return _pdf; }
- (NSSize)size { return _sizeSet ? _repSize : _bounds.size; }
- (BOOL)drawInRect:(NSRect)r {
  CGContextRef c = XEFCurrentCGContext(); if (!c || r.size.width <= 0 || r.size.height <= 0 || _bounds.size.width <= 0) return NO;
  double dpi = 72.0 * r.size.width / _bounds.size.width; if (dpi < 8) dpi = 8; if (dpi > 600) dpi = 600;
  int wh[2] = {0, 0}; int h = xef_host_pdf_render([_pdf bytes], [_pdf length], (int)_page + 1, dpi, wh); if (!h) return NO;
  NSBitmapImageRep *b = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:wh[0] pixelsHigh:wh[1] bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:@"NSDeviceRGBColorSpace" bitmapFormat:0 bytesPerRow:wh[0] * 4 bitsPerPixel:32];
  xef_host_image_copy(h, [b bitmapData]); xef_host_image_free(h);
  unsigned char *px = [b bitmapData]; for (NSInteger i = 0, n = (NSInteger)wh[0] * wh[1]; i < n; i++) { unsigned a = px[i * 4 + 3]; if (a != 255) { px[i*4] = px[i*4] * a / 255; px[i*4+1] = px[i*4+1] * a / 255; px[i*4+2] = px[i*4+2] * a / 255; } }
  CGImageRef img = [b CGImage]; if (img) CGContextDrawImage(c, r, img); [b release]; return img != NULL; }
@end

@implementation NSBezierPath (XEFDefaults)
+ (CGFloat)defaultMiterLimit { return 10; } + (CGFloat)defaultFlatness { return 0.6; } + (NSInteger)defaultWindingRule { return 0; } + (NSInteger)defaultLineCapStyle { return 0; } + (NSInteger)defaultLineJoinStyle { return 0; }
- (void)relativeCurveToPoint:(NSPoint)e controlPoint1:(NSPoint)c1 controlPoint2:(NSPoint)c2 { NSPoint cp = [self currentPoint]; [self curveToPoint:NSMakePoint(cp.x + e.x, cp.y + e.y) controlPoint1:NSMakePoint(cp.x + c1.x, cp.y + c1.y) controlPoint2:NSMakePoint(cp.x + c2.x, cp.y + c2.y)]; }
- (void)relativeCurveToPoint:(NSPoint)e controlPoint:(NSPoint)c { [self relativeCurveToPoint:e controlPoint1:c controlPoint2:c]; }
- (BOOL)cachesBezierPath { return YES; } - (void)setCachesBezierPath:(BOOL)f {}
+ (void)drawPackedGlyphs:(const char *)g atPoint:(NSPoint)p {}
@end

/* ---- NSCachedImageRep (a window-less offscreen cache: only its geometry) and NSEPSImageRep (the header comments are read; nothing is rendered — no PostScript interpreter) ---- */
@implementation NSCachedImageRep
- (id)initWithSize:(NSSize)s depth:(NSInteger)d separate:(BOOL)sep alpha:(BOOL)a { if ((self = [super init])) { _rect = NSMakeRect(0, 0, s.width, s.height); [self setSize:s]; _ralpha = a; } return self; }
- (id)initWithWindow:(id)w rect:(NSRect)r { if ((self = [super init])) { _win = w; _rect = r; [self setSize:r.size]; } return self; }
- (NSRect)rect { return _rect; } - (id)window { if (!_win) _win = [[NSWindow alloc] initWithContentRect:_rect styleMask:0 backing:NSBackingStoreBuffered defer:YES]; return _win; } - (BOOL)drawInRect:(NSRect)r { return NO; }
@end
@implementation NSEPSImageRep
+ (BOOL)canInitWithData:(NSData *)d { return NO; }   /* current macOS no longer reads EPS data */
+ (NSArray *)imageUnfilteredTypes { return @[@"com.adobe.encapsulated-postscript"]; } + (NSArray *)imageUnfilteredFileTypes { return @[@"eps"]; }
+ (NSArray *)imageRepsWithData:(NSData *)d { id r = [[[self alloc] initWithData:d] autorelease]; return r ? @[r] : @[]; }
+ (id)imageRepWithData:(NSData *)d { return [[[self alloc] initWithData:d] autorelease]; }
- (id)initWithData:(NSData *)d {
  if (!([d length] > 11 && !memcmp([d bytes], "%!PS-Adobe-", 11))) { [self release]; return nil; }
  if (YES) { [self release]; return nil; }   /* see canInitWithData: */
  NSString *s = [[[NSString alloc] initWithData:[d subdataWithRange:NSMakeRange(0, MIN((NSUInteger)4096, [d length]))] encoding:NSISOLatin1StringEncoding] autorelease]; double a, b, c, e = 0; NSRange r = [s rangeOfString:@"%%BoundingBox:"];
  if (r.location == NSNotFound || sscanf([[s substringFromIndex:NSMaxRange(r)] UTF8String], "%lf %lf %lf %lf", &a, &b, &c, &e) != 4) { [self release]; return nil; }
  if ((self = [super init])) { _eps = [d copy]; _bbox = NSMakeRect(a, b, c - a, e - b); [self setSize:_bbox.size]; } return self; }
- (void)dealloc { [_eps release]; [super dealloc]; } - (NSRect)boundingBox { return _bbox; } - (NSData *)EPSRepresentation { return _eps; } - (void)prepareGState {} - (BOOL)drawInRect:(NSRect)r { return NO; }
@end
