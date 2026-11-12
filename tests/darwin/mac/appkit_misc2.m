// NSScreen / NSCursor / NSAlert / NSBox / NSSearchField / NSBezierPath / NSScroller additions: defaults and stored settings. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSScreen *sc = [NSScreen mainScreen];
  P("screen: deepest nonnil %d separateSpaces %d safeArea %s depths %d maxFPS>0 %d granularity>=0 %d\n", [NSScreen deepestScreen] != nil, [NSScreen screensHaveSeparateSpaces], [[NSString stringWithFormat:@"%g,%g,%g,%g", sc.safeAreaInsets.top, sc.safeAreaInsets.left, sc.safeAreaInsets.bottom, sc.safeAreaInsets.right] UTF8String], sc.supportedWindowDepths != NULL, sc.maximumFramesPerSecond > 0, sc.displayUpdateGranularity >= 0);
  NSRect br = [sc convertRectFromBacking:NSMakeRect(0, 0, 100, 50)]; NSRect back = [sc convertRectToBacking:br]; P("backing roundtrip %s\n", [NSStringFromRect(back) UTF8String]);
  NSRect aligned = [sc backingAlignedRect:NSMakeRect(0.3, 0.3, 10.2, 10.2) options:NSAlignAllEdgesNearest]; P("aligned has integral size %d\n", aligned.size.width == floor(aligned.size.width));
  P("cursors: zoomIn %d zoomOut %d dragLink %d columnResize %d rowResize %d\n", [NSCursor zoomInCursor] != nil, [NSCursor zoomOutCursor] != nil, [NSCursor dragLinkCursor] != nil, [NSCursor columnResizeCursor] != nil, [NSCursor rowResizeCursor] != nil);
  NSCursor *c = [NSCursor crosshairCursor]; [c push]; P("push/pop ok "); [NSCursor pop]; P("done\n");
  NSAlert *a = [[NSAlert alloc] init];
  P("alert defaults: showsHelp %d helpAnchor nil %d delegate nil %d accessory nil %d suppression %d icon nonnil %d\n", a.showsHelp, a.helpAnchor == nil, a.delegate == nil, a.accessoryView == nil, a.showsSuppressionButton, a.icon != nil);
  a.showsHelp = YES; a.helpAnchor = @"anchor"; a.showsSuppressionButton = YES; P("set: help %d anchor %s suppression %d suppressionButton nonnil %d\n", a.showsHelp, [a.helpAnchor UTF8String], a.showsSuppressionButton, a.suppressionButton != nil);
  NSAlert *ea = [NSAlert alertWithError:[NSError errorWithDomain:@"d" code:1 userInfo:@{ NSLocalizedDescriptionKey: @"Boom", NSLocalizedRecoverySuggestionErrorKey: @"Try again" }]]; P("alertWithError: message '%s' informative '%s' style %ld\n", [ea.messageText UTF8String], [ea.informativeText UTF8String], (long)ea.alertStyle);
  NSBox *b = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 100, 60)];
  P("box defaults: borderWidth %g cornerRadius %g titleFont nonnil %d borderType %lu boxType %lu\n", b.borderWidth, b.cornerRadius, b.titleFont != nil, (unsigned long)b.borderType, (unsigned long)b.boxType);
  b.borderWidth = 3; b.cornerRadius = 8; b.borderColor = [NSColor redColor]; P("set: %g %g red %d\n", b.borderWidth, b.cornerRadius, [b.borderColor isEqual:[NSColor redColor]]);
  NSSearchField *sf = [[NSSearchField alloc] initWithFrame:NSMakeRect(0, 0, 200, 22)];
  P("search defaults: recents %lu recentsAutosave nil %d menuTemplate nil %d sendsWhole %d maxRecents %ld immediate %d centers %d\n", (unsigned long)sf.recentSearches.count, sf.recentsAutosaveName == nil, sf.searchMenuTemplate == nil, sf.sendsWholeSearchString, (long)sf.maximumRecents, sf.sendsSearchStringImmediately, sf.centersPlaceholder);
  sf.recentSearches = @[@"a", @"b"]; sf.maximumRecents = 5; sf.sendsWholeSearchString = YES; sf.recentsAutosaveName = @"r"; P("set: recents %lu max %ld whole %d autosave %s\n", (unsigned long)sf.recentSearches.count, (long)sf.maximumRecents, sf.sendsWholeSearchString, [sf.recentsAutosaveName UTF8String]);
  P("search rects nonempty %d\n", !NSIsEmptyRect(sf.searchTextBounds));
  P("bezier defaults: miter %g flatness %g winding %ld cap %ld join %ld\n", [NSBezierPath defaultMiterLimit], [NSBezierPath defaultFlatness], (long)[NSBezierPath defaultWindingRule], (long)[NSBezierPath defaultLineCapStyle], (long)[NSBezierPath defaultLineJoinStyle]);
  NSBezierPath *p = [NSBezierPath bezierPath]; [p moveToPoint:NSMakePoint(10, 10)]; [p relativeCurveToPoint:NSMakePoint(20, 0) controlPoint1:NSMakePoint(5, 10) controlPoint2:NSMakePoint(15, -10)]; P("relative curve current point %g,%g\n", p.currentPoint.x, p.currentPoint.y);
  P("scroller: compatibleOverlay %d usableParts %lu\n", [NSScroller isCompatibleWithOverlayScrollers], (unsigned long)[[[NSScroller alloc] initWithFrame:NSMakeRect(0, 0, 15, 100)] usableParts]);
  P("PASS appkit_misc2\n");
  fflush(stdout); _exit(0);
} return 0; }
