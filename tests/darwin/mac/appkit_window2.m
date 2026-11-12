// NSWindow: identifier, animator proxy, validation, deprecated coordinate conversion, misc flags. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 300, 200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  P("identifier nil %d", w.identifier == nil); w.identifier = @"main"; P(" -> %s\n", [w.identifier UTF8String]);
  P("animator ok %d animations %lu\n", [w animator] != nil, (unsigned long)w.animations.count);
  NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:@"x" action:@selector(performClose:) keyEquivalent:@""];
  P("validate performClose %d\n", [w validateMenuItem:mi]);
  NSMenuItem *mi2 = [[NSMenuItem alloc] initWithTitle:@"x" action:@selector(nonexistent:) keyEquivalent:@""];
  P("validate nonexistent %d\n", [w validateMenuItem:mi2]);
  P("drawers %lu showsToolbarButton %d showsResizeIndicator %d canStoreColor %d oneShot %d\n", (unsigned long)w.drawers.count, w.showsToolbarButton, w.showsResizeIndicator, w.canStoreColor, w.isOneShot);
  NSPoint p = [w convertBaseToScreen:NSMakePoint(10, 10)]; NSPoint q = [w convertScreenToBase:p]; P("base<->screen roundtrip %.0f,%.0f\n", q.x, q.y);
  P("userSpaceScaleFactor>0 %d backingLocation %ld\n", w.userSpaceScaleFactor > 0, (long)w.backingLocation);
  P("PASS appkit_window2\n");
  fflush(stdout); _exit(0);
} return 0; }
