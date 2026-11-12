/* AppKit-lite: the rest of NSView's and NSWindow's public API - hierarchy edits, layout passes, caching a view into a
 * bitmap, tool tips, gesture recognizers, sheets, child windows, frame autosaving and the many plain properties.
 * Behaviour follows real AppKit as recorded by tests/darwin/mac/appkit_view.m. State that few views use lives in a
 * per-object dictionary. */
#import "AppKitLite.h"
#import "AppKitGraphics.h"
#import "AppKitControls.h"
#include <objc/runtime.h>
#include <math.h>

extern NSString *const NSDeviceRGBColorSpace;
const CGFloat NSViewNoIntrinsicMetric = -1;
const CGFloat NSViewNoInstrinsicMetric = -1;
NSString *const NSViewGlobalFrameDidChangeNotification = @"NSViewGlobalFrameDidChangeNotification";
NSString *const NSViewDidUpdateTrackingAreasNotification = @"NSViewDidUpdateTrackingAreasNotification";
NSString *const NSViewFocusDidChangeNotification = @"NSViewFocusDidChangeNotification";
NSString *const NSWindowDidEndSheetNotification = @"NSWindowDidEndSheetNotification";
NSString *const NSWindowWillBeginSheetNotification = @"NSWindowWillBeginSheetNotification";

static char kProps;
static NSMutableDictionary *props(id o) {
  NSMutableDictionary *d = objc_getAssociatedObject(o, &kProps);
  if (!d) { d = [NSMutableDictionary dictionary]; objc_setAssociatedObject(o, &kProps, d, OBJC_ASSOCIATION_RETAIN); }
  return d; }
static void put(NSMutableDictionary *d, NSString *k, id v) { if (v) d[k] = v; else [d removeObjectForKey:k]; }

#define X_OBJ(get, set, key) - (id)get { return _extra[key]; } - (void)set:(id)v { put([self _xefExtra], key, v); }
#define X_BOOL(get, set, key, def) - (BOOL)get { id v = _extra[key]; return v ? [v boolValue] : def; } - (void)set:(BOOL)f { [self _xefExtra][key] = @(f); }
#define X_INT(get, set, key, def) - (NSInteger)get { id v = _extra[key]; return v ? [v integerValue] : def; } - (void)set:(NSInteger)i { [self _xefExtra][key] = @(i); }

/* ================================================================== NSView */
@implementation NSView (XEFMore)
+ (BOOL)requiresConstraintBasedLayout { return NO; }
+ (NSView *)focusView { return nil; }
+ (NSMenu *)defaultMenu { return nil; }
+ (BOOL)isCompatibleWithResponsiveScrolling { return NO; }
+ (NSInteger)defaultFocusRingType { return 0; }

X_OBJ(identifier, setIdentifier, @"identifier")
/* ---- hierarchy */
- (void)addSubview:(NSView *)v positioned:(NSInteger)place relativeTo:(NSView *)other {
  if (!v || v == self) return;
  NSMutableArray *rest = [NSMutableArray arrayWithArray:_subviews]; [rest removeObjectIdenticalTo:v];
  NSUInteger i = other ? [rest indexOfObjectIdenticalTo:other] : NSNotFound;
  if (i == NSNotFound) i = place < 0 /* NSWindowBelow */ ? 0 : [rest count];
  else if (place >= 0) i++;
  [self _xefInsertSubview:v atIndex:i]; }
- (void)sortSubviewsUsingFunction:(NSComparisonResult (*)(id, id, void *))compare context:(void *)ctx {
  [_subviews sortUsingFunction:(NSInteger (*)(id, id, void *))compare context:ctx]; if (_window) _window->_dirty2D = YES; }
- (void)replaceSubview:(NSView *)old with:(NSView *)new {
  NSUInteger i = [_subviews indexOfObjectIdenticalTo:old];
  if (i == NSNotFound || !new || new == old) return;
  [[old retain] autorelease];
  [self _xefInsertSubview:new atIndex:i];
  [old removeFromSuperview]; }
- (void)setSubviews:(NSArray *)views {
  for (NSView *v in [[_subviews copy] autorelease]) if ([views indexOfObjectIdenticalTo:v] == NSNotFound) [v removeFromSuperview];
  NSUInteger i = 0;
  for (NSView *v in views) [self _xefInsertSubview:v atIndex:i++]; }
- (void)removeFromSuperviewWithoutNeedingDisplay { [self removeFromSuperview]; }

/* ---- layout */
- (BOOL)needsLayout { return !_layoutClean; }
- (void)setNeedsLayout:(BOOL)f { _layoutClean = !f; if (f && _window) _window->_dirty2D = YES; }
- (void)layout {}
- (void)layoutSubtreeIfNeeded {
  if (!_layoutClean) { _layoutClean = YES; [self layout]; }
  for (NSView *s in [[_subviews copy] autorelease]) [s layoutSubtreeIfNeeded]; }
- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric); }
- (NSSize)fittingSize { NSSize s = [self intrinsicContentSize]; return NSMakeSize(s.width > 0 ? s.width : 0, s.height > 0 ? s.height : 0); }
- (void)invalidateIntrinsicContentSize { [_superview setNeedsLayout:YES]; }
- (BOOL)translatesAutoresizingMaskIntoConstraints { return !_noTranslates; } - (void)setTranslatesAutoresizingMaskIntoConstraints:(BOOL)f { _noTranslates = !f; }
- (void)updateConstraints {} - (void)updateConstraintsForSubtreeIfNeeded {}
- (BOOL)needsUpdateConstraints { return NO; } - (void)setNeedsUpdateConstraints:(BOOL)f {}
- (NSRect)alignmentRectForFrame:(NSRect)f { return f; } - (NSRect)frameForAlignmentRect:(NSRect)r { return r; }
- (NSEdgeInsets)alignmentRectInsets { return NSEdgeInsetsMake(0, 0, 0, 0); }
- (CGFloat)firstBaselineOffsetFromTop { return 0; } - (CGFloat)lastBaselineOffsetFromBottom { return 0; } - (CGFloat)baselineOffsetFromBottom { return 0; }
- (float)contentHuggingPriorityForOrientation:(NSInteger)o { id v = _extra[o ? @"hugV" : @"hugH"]; return v ? [v floatValue] : 250; }
- (void)setContentHuggingPriority:(float)p forOrientation:(NSInteger)o { [self _xefExtra][o ? @"hugV" : @"hugH"] = @(p); }
- (float)contentCompressionResistancePriorityForOrientation:(NSInteger)o { id v = _extra[o ? @"crV" : @"crH"]; return v ? [v floatValue] : 750; }
- (void)setContentCompressionResistancePriority:(float)p forOrientation:(NSInteger)o { [self _xefExtra][o ? @"crV" : @"crH"] = @(p); }
X_BOOL(isHorizontalContentSizeConstraintActive, setHorizontalContentSizeConstraintActive, @"hcs", YES)
X_BOOL(isVerticalContentSizeConstraintActive, setVerticalContentSizeConstraintActive, @"vcs", YES)
- (NSArray *)constraintsAffectingLayoutForOrientation:(NSInteger)o { return @[]; }
- (void)exerciseAmbiguityInLayout {} - (BOOL)hasAmbiguousLayout { return NO; }

/* ---- geometry odds and ends */
- (CGFloat)frameRotation { return _frameRotation; } - (void)setFrameRotation:(CGFloat)r { _frameRotation = r; }
- (CGFloat)frameCenterRotation { return _frameRotation; } - (void)setFrameCenterRotation:(CGFloat)r { _frameRotation = r; }
- (CGFloat)boundsRotation { return _boundsRotation; } - (void)setBoundsRotation:(CGFloat)r { _boundsRotation = r; }
- (void)rotateByAngle:(CGFloat)a { _boundsRotation += a; }
- (BOOL)isRotatedFromBase { return NO; }
- (BOOL)isRotatedOrScaledFromBase { for (NSView *v = self; v; v = v->_superview) if (!NSEqualSizes(v->_bounds.size, v->_frame.size)) return YES; return NO; }
- (BOOL)postsFrameChangedNotifications { return !_noFrameNotes; } - (void)setPostsFrameChangedNotifications:(BOOL)f { _noFrameNotes = !f; }
- (BOOL)postsBoundsChangedNotifications { return !_noBoundsNotes; } - (void)setPostsBoundsChangedNotifications:(BOOL)f { _noBoundsNotes = !f; }
- (NSRect)backingAlignedRect:(NSRect)r options:(NSUInteger)o { CGFloat x0 = round(NSMinX(r)), y0 = round(NSMinY(r)); return NSMakeRect(x0, y0, round(NSMaxX(r)) - x0, round(NSMaxY(r)) - y0); }
- (NSRect)centerScanRect:(NSRect)r { return [self backingAlignedRect:r options:0]; }
- (NSSize)convertSizeToLayer:(NSSize)s { return s; } - (NSSize)convertSizeFromLayer:(NSSize)s { return s; }
- (NSRect)convertRectToLayer:(NSRect)r { return r; } - (NSRect)convertRectFromLayer:(NSRect)r { return r; }
- (NSRect)adjustScroll:(NSRect)r { return r; }
- (void)translateRectsNeedingDisplayInRect:(NSRect)r by:(NSSize)d { [self setNeedsDisplay:YES]; }
- (void)scrollClipView:(NSView *)c toPoint:(NSPoint)p { if ([c respondsToSelector:@selector(scrollToPoint:)]) [(id)c scrollToPoint:p]; }
- (void)reflectScrolledClipView:(NSView *)c {}
- (NSRect)preparedContentRect { return [self visibleRect]; } - (void)setPreparedContentRect:(NSRect)r {} - (void)prepareContentInRect:(NSRect)r {}
- (NSRect)rectForSmartMagnificationAtPoint:(NSPoint)p inRect:(NSRect)r { return NSZeroRect; }
- (NSEdgeInsets)safeAreaInsets { return NSEdgeInsetsMake(0, 0, 0, 0); } - (NSRect)safeAreaRect { return _bounds; }
- (NSEdgeInsets)additionalSafeAreaInsets { return NSEdgeInsetsMake(0, 0, 0, 0); } - (void)setAdditionalSafeAreaInsets:(NSEdgeInsets)i {}
- (NSEdgeInsets)edgeInsetsForLayoutRegion:(id)r { return NSEdgeInsetsMake(0, 0, 0, 0); } - (NSRect)rectForLayoutRegion:(id)r { return _bounds; }

/* ---- drawing */
- (void)viewWillDraw {} - (void)updateLayer {} - (BOOL)wantsUpdateLayer { return NO; }
- (void)displayIfNeededInRectIgnoringOpacity:(NSRect)r { [self displayIfNeeded]; }
- (void)displayRectIgnoringOpacity:(NSRect)r inContext:(NSGraphicsContext *)c {
  NSGraphicsContext *saved = [[[NSGraphicsContext currentContext] retain] autorelease];
  if (c && [c CGContext]) [self _xefDrawTree:[c CGContext]];
  [NSGraphicsContext setCurrentContext:saved]; }
/* a bitmap of the view's size, and the view (with its subviews) drawn into it */
- (NSBitmapImageRep *)bitmapImageRepForCachingDisplayInRect:(NSRect)r {
  NSInteger w = (NSInteger)ceil(r.size.width), h = (NSInteger)ceil(r.size.height);
  if (w <= 0 || h <= 0) return nil;
  return [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                              colorSpaceName:NSDeviceRGBColorSpace bitmapFormat:0 bytesPerRow:w * 4 bitsPerPixel:32] autorelease]; }
- (void)cacheDisplayInRect:(NSRect)r toBitmapImageRep:(NSBitmapImageRep *)rep {
  CGContextRef c = [rep _xefCreateContext]; if (!c) return;
  NSGraphicsContext *saved = [[[NSGraphicsContext currentContext] retain] autorelease];
  NSRect f = _frame; NSView *sup = _superview;
  CGContextSaveGState(c);
  /* bitmap contexts are y-up with the origin at the bottom left, like an unflipped superview */
  _superview = nil; _frame.origin = NSMakePoint(-r.origin.x, -r.origin.y);
  [self _xefDrawTree:c];
  _superview = sup; _frame = f;
  CGContextRestoreGState(c);
  [NSGraphicsContext setCurrentContext:saved];
  CGContextRelease(c); }
X_BOOL(canDrawSubviewsIntoLayer, setCanDrawSubviewsIntoLayer, @"cdsl", NO) X_BOOL(layerUsesCoreImageFilters, setLayerUsesCoreImageFilters, @"cif", NO)
X_BOOL(clipsToBounds, setClipsToBounds, @"clips", NO) X_BOOL(wantsRestingTouches, setWantsRestingTouches, @"rest", NO)
X_BOOL(prefersCompactControlSizeMetrics, setPrefersCompactControlSizeMetrics, @"compact", NO)
X_INT(layerContentsPlacement, setLayerContentsPlacement, @"lcp", 0) X_INT(userInterfaceLayoutDirection, setUserInterfaceLayoutDirection, @"uild", 0)
X_OBJ(backgroundFilters, setBackgroundFilters, @"bgf") X_OBJ(compositingFilter, setCompositingFilter, @"cf") X_OBJ(contentFilters, setContentFilters, @"cnf")
X_OBJ(shadow, setShadow, @"shadow") X_OBJ(pressureConfiguration, setPressureConfiguration, @"pressure") X_OBJ(writingToolsCoordinator, setWritingToolsCoordinator, @"wtc")
- (NSInteger)layerContentsRedrawPolicy { return 0; }
- (BOOL)allowsVibrancy { return NO; } - (BOOL)isDrawingFindIndicator { return NO; }
- (void)viewDidChangeEffectiveAppearance {}
- (void)setKeyboardFocusRingNeedsDisplayInRect:(NSRect)r { [self setNeedsDisplay:YES]; }
- (BOOL)preservesContentDuringLiveResize { return NO; } - (NSRect)rectPreservedDuringLiveResize { return NSZeroRect; }
- (void)getRectsExposedDuringLiveResize:(NSRect[4])rects count:(NSInteger *)count { if (count) *count = 0; }
- (void)viewWillStartLiveResize {} - (void)viewDidEndLiveResize {}

/* ---- events */
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return NO; }
- (BOOL)shouldDelayWindowOrderingForEvent:(NSEvent *)e { return NO; }
- (BOOL)needsPanelToBecomeKey { return NO; }
- (BOOL)mouseDownCanMoveWindow { return ![self isOpaque]; }
- (BOOL)canBecomeKeyView { return [self acceptsFirstResponder] && ![self isHiddenOrHasHiddenAncestor]; }
- (id)inputContext { return nil; } - (id)enclosingMenuItem { return nil; } - (id)candidateListTouchBarItem { return nil; }
- (NSUInteger)allowedTouchTypes { return 0; }
- (void)prepareForReuse {}
- (NSArray *)gestureRecognizers { return _extra[@"gestures"] ?: @[]; }
- (void)setGestureRecognizers:(NSArray *)a {
  for (id g in [self gestureRecognizers]) if ([g respondsToSelector:@selector(_xefSetView:)]) [g performSelector:@selector(_xefSetView:) withObject:nil];
  [self _xefExtra][@"gestures"] = [NSMutableArray arrayWithArray:a ?: @[]];
  for (id g in a) if ([g respondsToSelector:@selector(_xefSetView:)]) [g performSelector:@selector(_xefSetView:) withObject:self]; }
- (void)addGestureRecognizer:(id)g {
  if (!g) return;
  NSMutableArray *a = _extra[@"gestures"]; if (!a) { a = [NSMutableArray array]; [self _xefExtra][@"gestures"] = a; }
  if (![a containsObject:g]) [a addObject:g];
  if ([g respondsToSelector:@selector(_xefSetView:)]) [g performSelector:@selector(_xefSetView:) withObject:self]; }
- (void)removeGestureRecognizer:(id)g {
  NSMutableArray *a = _extra[@"gestures"]; if (![a containsObject:g]) return;
  if ([g respondsToSelector:@selector(_xefSetView:)]) [g performSelector:@selector(_xefSetView:) withObject:nil];
  [a removeObject:g]; }
/* tool tip rectangles and the older tracking rectangles: kept, so that owners are asked consistently */
- (NSInteger)addToolTipRect:(NSRect)r owner:(id)owner userData:(void *)data {
  NSMutableArray *a = _extra[@"tips"]; if (!a) { a = [NSMutableArray array]; [self _xefExtra][@"tips"] = a; }
  static NSInteger next = 1; NSInteger tag = next++;
  [a addObject:@{ @"tag": @(tag), @"rect": [NSValue valueWithRect:r], @"owner": [NSValue valueWithNonretainedObject:owner] }];
  return tag; }
- (void)removeToolTip:(NSInteger)tag { NSMutableArray *a = _extra[@"tips"]; for (NSDictionary *d in [[a copy] autorelease]) if ([d[@"tag"] integerValue] == tag) [a removeObject:d]; }
- (void)removeAllToolTips { [_extra removeObjectForKey:@"tips"]; }
- (NSInteger)addTrackingRect:(NSRect)r owner:(id)owner userData:(void *)data assumeInside:(BOOL)inside {
  NSTrackingArea *t = [[[NSTrackingArea alloc] initWithRect:r options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | (inside ? NSTrackingAssumeInside : 0) owner:owner userInfo:nil] autorelease];
  [self addTrackingArea:t];
  NSMutableDictionary *m = _extra[@"trackingRects"]; if (!m) { m = [NSMutableDictionary dictionary]; [self _xefExtra][@"trackingRects"] = m; }
  static NSInteger next = 1; NSInteger tag = next++; m[@(tag)] = t; return tag; }
- (void)removeTrackingRect:(NSInteger)tag { NSMutableDictionary *m = _extra[@"trackingRects"]; NSTrackingArea *t = m[@(tag)]; if (t) { [self removeTrackingArea:t]; [m removeObjectForKey:@(tag)]; } }
- (void)removeCursorRect:(NSRect)r cursor:(id)c {}
- (NSArray *)registeredDraggedTypes { return _dragTypes ?: @[]; }
- (id)beginDraggingSessionWithItems:(NSArray *)items event:(NSEvent *)e source:(id)src { return nil; }
- (id)displayLinkWithTarget:(id)t selector:(SEL)s { return nil; }

/* ---- full screen, look-up, printing */
- (BOOL)enterFullScreenMode:(id)screen withOptions:(NSDictionary *)o { return NO; } - (void)exitFullScreenModeWithOptions:(NSDictionary *)o {} - (BOOL)isInFullScreenMode { return NO; }
- (void)showDefinitionForAttributedString:(NSAttributedString *)s atPoint:(NSPoint)p {}
- (void)showDefinitionForAttributedString:(NSAttributedString *)s range:(NSRange)r options:(NSDictionary *)o baselineOriginProvider:(id)b {}
- (void)print:(id)s {} - (BOOL)knowsPageRange:(NSRangePointer)r { return NO; }
- (NSRect)rectForPage:(NSInteger)p { return _bounds; } - (NSPoint)locationOfPrintRect:(NSRect)r { return NSZeroPoint; }
- (void)adjustPageWidthNew:(CGFloat *)n left:(CGFloat)l right:(CGFloat)r limit:(CGFloat)lim { if (n) *n = r; }
- (void)adjustPageHeightNew:(CGFloat *)n top:(CGFloat)t bottom:(CGFloat)b limit:(CGFloat)lim { if (n) *n = b; }
- (void)drawPageBorderWithSize:(NSSize)s {} - (void)beginDocument {} - (void)endDocument {} - (void)beginPageInRect:(NSRect)r atPlacement:(NSPoint)p {} - (void)endPage {}
- (CGFloat)heightAdjustLimit { return 0.2; } - (CGFloat)widthAdjustLimit { return 0.2; }
- (NSAttributedString *)pageHeader { return nil; } - (NSAttributedString *)pageFooter { return nil; } - (NSString *)printJobTitle { return [_window title] ?: @""; }
- (NSData *)dataWithPDFInsideRect:(NSRect)r { return nil; } - (NSData *)dataWithEPSInsideRect:(NSRect)r { return nil; }
- (void)writePDFInsideRect:(NSRect)r toPasteboard:(id)p {} - (void)writeEPSInsideRect:(NSRect)r toPasteboard:(id)p {}
/* ruler client protocol: a view without rulers declines */
- (BOOL)rulerView:(id)r shouldMoveMarker:(id)m { return NO; } - (CGFloat)rulerView:(id)r willMoveMarker:(id)m toLocation:(CGFloat)l { return l; }
- (void)rulerView:(id)r didMoveMarker:(id)m {} - (BOOL)rulerView:(id)r shouldRemoveMarker:(id)m { return NO; } - (void)rulerView:(id)r didRemoveMarker:(id)m {}
- (BOOL)rulerView:(id)r shouldAddMarker:(id)m { return NO; } - (CGFloat)rulerView:(id)r willAddMarker:(id)m atLocation:(CGFloat)l { return l; }
- (void)rulerView:(id)r didAddMarker:(id)m {} - (void)rulerView:(id)r handleMouseDown:(NSEvent *)e {} - (void)rulerView:(id)r willSetClientView:(NSView *)v {}
- (CGFloat)rulerView:(id)r locationForPoint:(NSPoint)p { return p.x; } - (NSPoint)rulerView:(id)r pointForLocation:(CGFloat)l { return NSMakePoint(l, 0); }
@end

/* ================================================================== NSWindow */
#define W_OBJ(get, set, key) - (id)get { return props(self)[key]; } - (void)set:(id)v { put(props(self), key, v); }
#define W_BOOL(get, set, key, def) - (BOOL)get { id v = props(self)[key]; return v ? [v boolValue] : def; } - (void)set:(BOOL)f { props(self)[key] = @(f); }
#define W_INT(get, set, key, def) - (NSInteger)get { id v = props(self)[key]; return v ? [v integerValue] : def; } - (void)set:(NSInteger)i { props(self)[key] = @(i); }
#define W_SIZE(get, set, key) - (NSSize)get { id v = props(self)[key]; return v ? [v sizeValue] : NSZeroSize; } - (void)set:(NSSize)s { props(self)[key] = [NSValue valueWithSize:s]; }

@interface NSObject (XEFWindowInformal)
- (void)windowDidBecomeMain:(NSNotification *)n; - (void)windowDidResignMain:(NSNotification *)n; - (NSView *)view; - (NSSize)preferredContentSize;
- (void)setContentViewController:(id)vc; - (void)setVisible:(BOOL)f; - (BOOL)isVisible;
@end

@implementation NSWindow (XEFMore)
+ (NSWindow *)windowWithContentViewController:(id)vc {
  NSView *v = [vc respondsToSelector:@selector(view)] ? [vc view] : nil; NSSize s = v ? [v frame].size : NSMakeSize(480, 270);
  if (s.width <= 0 || s.height <= 0) s = NSMakeSize(480, 270);
  NSWindow *w = [[[self alloc] initWithContentRect:NSMakeRect(0, 0, s.width, s.height) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                           backing:NSBackingStoreBuffered defer:YES] autorelease];
  [w setReleasedWhenClosed:NO];
  if ([w respondsToSelector:@selector(setContentViewController:)]) [(id)w setContentViewController:vc]; else if (v) [w setContentView:v];
  if ([vc respondsToSelector:@selector(title)] && [vc title]) [w setTitle:[vc title]];
  return w; }
+ (CGFloat)minFrameWidthWithTitle:(NSString *)t styleMask:(NSWindowStyleMask)m { return 100; }
+ (id)standardWindowButton:(NSInteger)b forStyleMask:(NSWindowStyleMask)m { return nil; }
+ (NSInteger)defaultDepthLimit { return 0; }
+ (BOOL)allowsAutomaticWindowTabbing { return NO; } + (void)setAllowsAutomaticWindowTabbing:(BOOL)f {} + (NSInteger)userTabbingPreference { return 0; }
+ (void)removeFrameUsingName:(NSString *)n { if (n) [[NSUserDefaults standardUserDefaults] removeObjectForKey:[@"NSWindow Frame " stringByAppendingString:n]]; }

/* ---- layout and editing */
- (void)updateConstraintsIfNeeded {} - (void)layoutIfNeeded { [_content layoutSubtreeIfNeeded]; }
- (NSInteger)anchorAttributeForOrientation:(NSInteger)o { return o ? 3 : 1; } - (void)setAnchorAttribute:(NSInteger)a forOrientation:(NSInteger)o {}
- (void)visualizeConstraints:(NSArray *)c {} - (id)contentLayoutGuide { return nil; }
- (id)fieldEditor:(BOOL)create forObject:(id)o { return nil; }
- (void)endEditingFor:(id)o { if (_first && [_first respondsToSelector:@selector(_xefIsEditing)] && [(id)_first _xefIsEditing]) [self makeFirstResponder:self]; }
- (void)recalculateKeyViewLoop {} - (NSInteger)keyViewSelectionDirection { return 0; }
W_BOOL(autorecalculatesKeyViewLoop, setAutorecalculatesKeyViewLoop, @"arkvl", NO)
- (void)disableKeyEquivalentForDefaultButtonCell { props(self)[@"noDefaultKey"] = @YES; } - (void)enableKeyEquivalentForDefaultButtonCell { [props(self) removeObjectForKey:@"noDefaultKey"]; }

/* ---- geometry */
- (NSRect)constrainFrameRect:(NSRect)f toScreen:(id)s { return f; }
- (NSTimeInterval)animationResizeTime:(NSRect)f { return 0.2; }
- (NSRect)convertRectFromBacking:(NSRect)r { return r; } - (NSPoint)convertPointToBacking:(NSPoint)p { return p; } - (NSPoint)convertPointFromBacking:(NSPoint)p { return p; }
- (NSRect)backingAlignedRect:(NSRect)r options:(NSUInteger)o { CGFloat x0 = round(NSMinX(r)), y0 = round(NSMinY(r)); return NSMakeRect(x0, y0, round(NSMaxX(r)) - x0, round(NSMaxY(r)) - y0); }
- (NSSize)minSize { NSRect f = [self frameRectForContentRect:NSMakeRect(0, 0, _minSize.width, _minSize.height)]; return _minSize.width || _minSize.height ? f.size : NSZeroSize; }
- (NSSize)maxSize { return _maxSize.width || _maxSize.height ? [self frameRectForContentRect:NSMakeRect(0, 0, _maxSize.width, _maxSize.height)].size : NSMakeSize(3.40282347e+38F, 3.40282347e+38F); }
W_SIZE(minFullScreenContentSize, setMinFullScreenContentSize, @"minFS") W_SIZE(maxFullScreenContentSize, setMaxFullScreenContentSize, @"maxFS")
- (NSSize)aspectRatio { return _aspect; } - (void)setAspectRatio:(NSSize)s { _aspect = s; } - (NSSize)contentAspectRatio { return _aspect; }
- (NSSize)resizeIncrements { id v = props(self)[@"incr"]; return v ? [v sizeValue] : NSMakeSize(1, 1); }
- (NSSize)contentResizeIncrements { return [self resizeIncrements]; } - (void)setContentResizeIncrements:(NSSize)s { props(self)[@"incr"] = [NSValue valueWithSize:s]; }
- (NSRect)cascadingReferenceFrame { return [self frame]; }
- (NSUInteger)resizeFlags { return 0; } - (BOOL)preservesContentDuringLiveResize { return YES; }
- (CGFloat)contentBorderThicknessForEdge:(NSInteger)e { return 0; } - (void)setContentBorderThickness:(CGFloat)t forEdge:(NSInteger)e {}
- (BOOL)autorecalculatesContentBorderThicknessForEdge:(NSInteger)e { return NO; } - (void)setAutorecalculatesContentBorderThickness:(BOOL)f forEdge:(NSInteger)e {}
/* saved frames: "x y w h screenX screenY screenW screenH " as AppKit writes them */
- (NSString *)stringWithSavedFrame {
  NSRect f = [self frame], s = [[NSScreen mainScreen] frame];
  return [NSString stringWithFormat:@"%d %d %d %d %d %d %d %d ", (int)f.origin.x, (int)f.origin.y, (int)f.size.width, (int)f.size.height, (int)s.origin.x, (int)s.origin.y, (int)s.size.width, (int)s.size.height]; }
- (void)setFrameFromString:(NSString *)s {
  NSArray *p = [[s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] componentsSeparatedByString:@" "];
  if ([p count] < 4) return;
  NSRect f = NSMakeRect([p[0] doubleValue], [p[1] doubleValue], [p[2] doubleValue], [p[3] doubleValue]);
  if (!(_style & NSWindowStyleMaskResizable)) { NSRect cur = [self frame]; f.origin.y += f.size.height - cur.size.height; f.size = cur.size; }
  if (f.size.width > 0 && f.size.height > 0) [self setFrame:f display:YES]; }
- (void)saveFrameUsingName:(NSString *)n { if ([n length]) [[NSUserDefaults standardUserDefaults] setObject:[self stringWithSavedFrame] forKey:[@"NSWindow Frame " stringByAppendingString:n]]; }
- (BOOL)setFrameUsingName:(NSString *)n force:(BOOL)force {
  NSString *s = [n length] ? [[NSUserDefaults standardUserDefaults] stringForKey:[@"NSWindow Frame " stringByAppendingString:n]] : nil;
  if (!s) return NO;
  [self setFrameFromString:s]; return YES; }
- (BOOL)setFrameUsingName:(NSString *)n { return [self setFrameUsingName:n force:NO]; }
- (NSString *)frameAutosaveName { return props(self)[@"autosave"] ?: @""; }

/* ---- key and main */
- (void)becomeKeyWindow { [self makeKeyWindow]; }
- (void)becomeMainWindow {
  if (props(self)[@"main"]) return;
  props(self)[@"main"] = @YES;
  NSNotification *n = [NSNotification notificationWithName:@"NSWindowDidBecomeMainNotification" object:self];
  [[NSNotificationCenter defaultCenter] postNotification:n];
  if ([_delegate respondsToSelector:@selector(windowDidBecomeMain:)]) [_delegate windowDidBecomeMain:n]; }
- (void)resignMainWindow {
  if (!props(self)[@"main"]) return;
  [props(self) removeObjectForKey:@"main"];
  NSNotification *n = [NSNotification notificationWithName:@"NSWindowDidResignMainNotification" object:self];
  [[NSNotificationCenter defaultCenter] postNotification:n];
  if ([_delegate respondsToSelector:@selector(windowDidResignMain:)]) [_delegate windowDidResignMain:n]; }

/* ---- sheets and child windows: a sheet is shown as a window centred over its parent */
- (NSArray *)sheets { return props(self)[@"sheets"] ?: @[]; }
- (NSWindow *)attachedSheet { return [[self sheets] lastObject]; }
- (BOOL)isSheet { return props(self)[@"sheetParent"] != nil; }
- (NSWindow *)sheetParent { return [props(self)[@"sheetParent"] nonretainedObjectValue]; }
- (void)beginSheet:(NSWindow *)sheet completionHandler:(void (^)(NSModalResponse))handler {
  if (!sheet || sheet == self) return;
  NSMutableArray *a = props(self)[@"sheets"]; if (!a) { a = [NSMutableArray array]; props(self)[@"sheets"] = a; }
  if ([a containsObject:sheet]) return;
  [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowWillBeginSheetNotification object:self];
  [a addObject:sheet];
  props(sheet)[@"sheetParent"] = [NSValue valueWithNonretainedObject:self];
  put(props(sheet), @"sheetHandler", [[handler copy] autorelease]);
  NSRect pf = [self frame], sf = [sheet frame];
  [sheet setFrameOrigin:NSMakePoint(pf.origin.x + (pf.size.width - sf.size.width) / 2, NSMaxY(pf) - sf.size.height - 28)];
  [sheet makeKeyAndOrderFront:nil]; }
- (void)beginCriticalSheet:(NSWindow *)sheet completionHandler:(void (^)(NSModalResponse))handler { [self beginSheet:sheet completionHandler:handler]; }
- (void)endSheet:(NSWindow *)sheet returnCode:(NSModalResponse)code {
  NSMutableArray *a = props(self)[@"sheets"]; if (![a containsObject:sheet]) return;
  [[sheet retain] autorelease];
  void (^handler)(NSModalResponse) = [[props(sheet)[@"sheetHandler"] retain] autorelease];
  [a removeObject:sheet]; [props(sheet) removeObjectForKey:@"sheetParent"]; [props(sheet) removeObjectForKey:@"sheetHandler"];
  [sheet orderOut:nil];
  [self makeKeyAndOrderFront:nil];
  if (handler) handler(code);
  [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowDidEndSheetNotification object:self]; }
- (void)endSheet:(NSWindow *)sheet { [self endSheet:sheet returnCode:0]; }
- (NSArray *)childWindows { return props(self)[@"children"] ?: @[]; }
- (NSWindow *)parentWindow { return [props(self)[@"parent"] nonretainedObjectValue]; }
- (void)setParentWindow:(NSWindow *)w { put(props(self), @"parent", w ? [NSValue valueWithNonretainedObject:w] : nil); }
- (void)_xefAddChild:(NSWindow *)c {
  NSMutableArray *a = props(self)[@"children"]; if (!a) { a = [NSMutableArray array]; props(self)[@"children"] = a; }
  if (c && ![a containsObject:c]) { [a addObject:c]; [c setParentWindow:self]; } }
- (void)_xefRemoveChild:(NSWindow *)c { NSMutableArray *a = props(self)[@"children"]; if ([a containsObject:c]) { [c setParentWindow:nil]; [a removeObject:c]; } }

/* ---- title bar, toolbar, tabs */
W_OBJ(subtitle, setSubtitle, @"subtitle") W_OBJ(representedURL, setRepresentedURL, @"repURL") W_OBJ(miniwindowImage, setMiniwindowImage, @"miniImage")
W_OBJ(appearanceSource, setAppearanceSource, @"appearanceSource") W_OBJ(tabbingIdentifier, setTabbingIdentifier, @"tabbingID") W_OBJ(restorationClass, setRestorationClass, @"restorationClass")
W_INT(toolbarStyle, setToolbarStyle, @"toolbarStyle", 0) W_INT(titlebarSeparatorStyle, setTitlebarSeparatorStyle, @"tbSep", 0) W_INT(sharingType, setSharingType, @"sharing", 1)
W_INT(depthLimit, setDepthLimit, @"depth", 0) W_INT(backingType, setBackingType, @"backing", 2)
W_BOOL(isExcludedFromWindowsMenu, setExcludedFromWindowsMenu, @"noWindowsMenu", NO) W_BOOL(isMovable, setMovable, @"movable", YES) W_BOOL(canHide, setCanHide, @"canHide", YES)
W_BOOL(preventsApplicationTerminationWhenModal, setPreventsApplicationTerminationWhenModal, @"preventsTerm", YES)
W_BOOL(allowsToolTipsWhenApplicationIsInactive, setAllowsToolTipsWhenApplicationIsInactive, @"tipsInactive", NO)
W_BOOL(canBecomeVisibleWithoutLogin, setCanBecomeVisibleWithoutLogin, @"noLogin", NO)
- (NSInteger)titleVisibility { return [props(self)[@"titleHidden"] boolValue] ? 1 : 0; }
- (BOOL)titlebarAppearsTransparent { return [props(self)[@"tbTransparent"] boolValue]; }
- (NSString *)representedFilename { return [[self representedURL] path] ?: @""; }
- (void)setTitleWithRepresentedFilename:(NSString *)path { [self setRepresentedURL:path ? [NSURL fileURLWithPath:path] : nil]; [self setTitle:[path lastPathComponent] ?: @""]; }
- (NSArray *)titlebarAccessoryViewControllers { return props(self)[@"accessories"] ?: @[]; }
- (void)setTitlebarAccessoryViewControllers:(NSArray *)a { props(self)[@"accessories"] = [NSMutableArray arrayWithArray:a ?: @[]]; }
- (void)insertTitlebarAccessoryViewController:(id)vc atIndex:(NSInteger)i {
  NSMutableArray *a = [NSMutableArray arrayWithArray:[self titlebarAccessoryViewControllers]]; if (vc) [a insertObject:vc atIndex:i > (NSInteger)[a count] ? [a count] : i]; props(self)[@"accessories"] = a; }
- (void)addTitlebarAccessoryViewController:(id)vc { [self insertTitlebarAccessoryViewController:vc atIndex:[[self titlebarAccessoryViewControllers] count]]; }
- (void)removeTitlebarAccessoryViewControllerAtIndex:(NSInteger)i {
  NSMutableArray *a = [NSMutableArray arrayWithArray:[self titlebarAccessoryViewControllers]]; if (i >= 0 && i < (NSInteger)[a count]) [a removeObjectAtIndex:i]; props(self)[@"accessories"] = a; }
- (id)toolbar { return props(self)[@"toolbar"]; }
- (void)setToolbar:(id)t {
  id old = [[props(self)[@"toolbar"] retain] autorelease];
  if (old == t) return;
  if ([old respondsToSelector:@selector(_xefSetWindow:)]) [old performSelector:@selector(_xefSetWindow:) withObject:nil];
  put(props(self), @"toolbar", t);
  if ([t respondsToSelector:@selector(_xefSetWindow:)]) [t performSelector:@selector(_xefSetWindow:) withObject:self];
  _dirty2D = YES; }
- (void)toggleToolbarShown:(id)s { id t = [self toolbar]; if ([t respondsToSelector:@selector(setVisible:)]) [t setVisible:![t isVisible]]; _dirty2D = YES; }
- (void)runToolbarCustomizationPalette:(id)s {}
- (NSInteger)tabbingMode { return 0; } - (NSArray *)tabbedWindows { return nil; } - (id)tab { return nil; } - (id)tabGroup { return nil; }
- (void)selectNextTab:(id)s {} - (void)selectPreviousTab:(id)s {} - (void)moveTabToNewWindow:(id)s {} - (void)mergeAllWindows:(id)s {} - (void)toggleTabBar:(id)s {} - (void)toggleTabOverview:(id)s {}
- (void)addTabbedWindow:(NSWindow *)w ordered:(NSInteger)o { [w makeKeyAndOrderFront:nil]; }
- (NSInteger)windowTitlebarLayoutDirection { return 0; }

/* ---- state */
- (BOOL)hidesOnDeactivate { return NO; } - (BOOL)worksWhenModal { return NO; } - (BOOL)isFloatingPanel { return NO; } - (BOOL)isModalPanel { return NO; }
- (BOOL)isDocumentEdited { return [props(self)[@"edited"] boolValue]; }
- (BOOL)hasCloseBox { return (_style & NSWindowStyleMaskClosable) != 0; } - (BOOL)hasTitleBar { return (_style & NSWindowStyleMaskTitled) != 0; }
- (BOOL)isMiniaturizable { return (_style & NSWindowStyleMaskMiniaturizable) != 0; } - (BOOL)isResizable { return (_style & NSWindowStyleMaskResizable) != 0; }
- (BOOL)isZoomable { return (_style & NSWindowStyleMaskResizable) != 0; }
- (void)setIsMiniaturized:(BOOL)f { if (f) [self miniaturize:nil]; else [self deminiaturize:nil]; } - (void)setIsZoomed:(BOOL)f { if (f != [self isZoomed]) [self zoom:nil]; }
- (BOOL)hasDynamicDepthLimit { return NO; } - (void)setDynamicDepthLimit:(BOOL)f {} - (BOOL)canRepresentDisplayGamut:(NSInteger)g { return g == 1; }
- (BOOL)allowsConcurrentViewDrawing { return NO; } - (BOOL)displaysWhenScreenProfileChanges { return NO; }
- (NSInteger)animationBehavior { return 0; } - (id)colorSpace { return [NSColorSpace sRGBColorSpace]; } - (id)dockTile { return [NSApp respondsToSelector:@selector(dockTile)] ? [NSApp dockTile] : nil; }
- (NSDictionary *)deviceDescription { return [[NSScreen mainScreen] deviceDescription]; }
- (void)invalidateShadow {} - (BOOL)hasActiveWindowSharingSession { return NO; }
- (void)transferWindowSharingToWindow:(NSWindow *)w completionHandler:(void (^)(NSError *))h { if (h) h(nil); }
- (void)requestSharingOfWindow:(NSWindow *)w completionHandler:(void (^)(NSError *))h { if (h) h(nil); }
- (void)requestSharingOfWindowUsingPreview:(id)i title:(NSString *)t completionHandler:(void (^)(NSError *))h { if (h) h(nil); }
- (BOOL)isRestorable { return NO; } - (void)disableSnapshotRestoration {} - (void)enableSnapshotRestoration {}
- (void)performWindowDragWithEvent:(NSEvent *)e {}
- (NSData *)dataWithPDFInsideRect:(NSRect)r { return nil; } - (NSData *)dataWithEPSInsideRect:(NSRect)r { return nil; } - (void)print:(id)s {}
- (id)handleCloseScriptCommand:(id)c { [self performSelector:@selector(performClose:) withObject:nil]; return nil; } - (id)handlePrintScriptCommand:(id)c { return nil; } - (id)handleSaveScriptCommand:(id)c { return nil; }

/* ---- events */
- (NSEvent *)currentEvent { return [NSApp currentEvent]; }
- (BOOL)acceptsMouseMovedEvents { return [props(self)[@"mouseMoved"] boolValue]; }
- (NSEvent *)nextEventMatchingMask:(NSUInteger)m untilDate:(NSDate *)d inMode:(NSString *)mode dequeue:(BOOL)dq { return [NSApp nextEventMatchingMask:m untilDate:d inMode:mode dequeue:dq]; }
- (NSEvent *)nextEventMatchingMask:(NSUInteger)m { return [NSApp nextEventMatchingMask:m untilDate:[NSDate distantFuture] inMode:@"NSEventTrackingRunLoopMode" dequeue:YES]; }
- (void)postEvent:(NSEvent *)e atStart:(BOOL)s { [NSApp postEvent:e atStart:s]; }
- (void)discardEventsMatchingMask:(NSUInteger)m beforeEvent:(NSEvent *)e {}
- (void)trackEventsMatchingMask:(NSUInteger)m timeout:(NSTimeInterval)t mode:(NSString *)mode handler:(void (^)(NSEvent *, BOOL *))handler {
  BOOL stop = NO;
  while (!stop) {
    NSEvent *e = [NSApp nextEventMatchingMask:m untilDate:[NSDate dateWithTimeIntervalSinceNow:t] inMode:mode dequeue:YES];
    handler(e, &stop);
    if (!e) break; } }
- (void)discardCursorRects {} - (void)resetCursorRects {} - (BOOL)areCursorRectsEnabled { return YES; }
- (id)beginDraggingSessionWithItems:(NSArray *)items event:(NSEvent *)e source:(id)src { return nil; }
- (id)displayLinkWithTarget:(id)t selector:(SEL)s { return nil; }
@end
