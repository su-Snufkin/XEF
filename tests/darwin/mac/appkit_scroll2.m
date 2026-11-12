// NSScrollView / NSTableView / NSWorkspace additions: magnification limits, document cursor, rulers, legacy table API, deprecated launch API. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
  NSView *doc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 800)]; sv.documentView = doc;
  P("defaults: min %g max %g allowsMag %d mag %g pageScroll h %g v %g cursor nil %d findBar %d ruler class %s\n", sv.minMagnification, sv.maxMagnification, sv.allowsMagnification, sv.magnification, sv.horizontalPageScroll, sv.verticalPageScroll, sv.documentCursor == nil, sv.isFindBarVisible, [NSStringFromClass([NSScrollView rulerViewClass]) UTF8String]);
  sv.minMagnification = 0.5; sv.maxMagnification = 3; sv.allowsMagnification = YES; P("set: %g %g\n", sv.minMagnification, sv.maxMagnification);
  sv.magnification = 10; P("clamped max %g", sv.magnification); sv.magnification = 0.1; P(" min %g\n", sv.magnification);
  [sv setMagnification:2 centeredAtPoint:NSMakePoint(100, 100)]; P("centered mag %g\n", sv.magnification);
  [sv magnifyToFitRect:NSMakeRect(0, 0, 150, 100)]; P("fit rect mag %.2f\n", sv.magnification);
  NSCursor *c = [NSCursor crosshairCursor]; sv.documentCursor = c; P("cursor set %d\n", sv.documentCursor == c);
  P("rulers nil: h %d v %d\n", sv.horizontalRulerView == nil, sv.verticalRulerView == nil);
  sv.findBarPosition = NSScrollViewFindBarPositionAboveContent; P("findBarPosition %ld\n", (long)sv.findBarPosition);
  NSTableView *tv = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
  P("table: focusedColumn %ld autoresizesAll %d\n", (long)tv.focusedColumn, [tv autoresizesAllColumnsToFit]);
  tv.focusedColumn = 0; P("focusedColumn after set %ld\n", (long)tv.focusedColumn);
  [tv setDrawsGrid:YES]; P("drawsGrid %d\n", [tv drawsGrid]);
  P("textShouldBegin %d\n", [tv textShouldBeginEditing:[[NSTextView alloc] initWithFrame:NSZeroRect]]);
  NSWorkspace *w = [NSWorkspace sharedWorkspace];
  P("launchApplication missing %d\n", [w launchApplication:@"NoSuchAppAnywhere"]);
  P("openTempFile missing %d\n", [w openTempFile:@"/nonexistent/file"]);
  NSString *app = nil, *type = nil; BOOL ok = [w getInfoForFile:@"/etc" application:&app type:&type]; P("getInfoForFile dir ok %d type %s\n", ok, type ? [type UTF8String] : "nil");
  P("PASS appkit_scroll2\n");
  fflush(stdout); _exit(0);
} return 0; }
