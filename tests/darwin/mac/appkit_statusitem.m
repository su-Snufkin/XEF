// NSStatusItem / NSStatusBar: length, visibility, behavior, autosave name, button forwarding, view. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSStatusBar *bar = [NSStatusBar systemStatusBar]; P("bar ok %d same %d thickness>0 %d vertical %d\n", bar != nil, bar == [NSStatusBar systemStatusBar], bar.thickness > 0, bar.isVertical);
  NSStatusItem *it = [bar statusItemWithLength:NSVariableStatusItemLength];
  P("defaults: length %g visible %d behavior %lu autosave %s statusBar same %d button %d\n", it.length, it.isVisible, (unsigned long)it.behavior, it.autosaveName ? [it.autosaveName UTF8String] : "nil", it.statusBar == bar, it.button != nil);
  it.length = 40; P("length %g\n", it.length);
  it.visible = NO; P("visible %d\n", it.isVisible); it.visible = YES;
  it.behavior = NSStatusItemBehaviorRemovalAllowed; P("behavior %lu\n", (unsigned long)it.behavior);
  it.autosaveName = @"xef.item"; P("autosave %s\n", [it.autosaveName UTF8String]);
  it.button.title = @"T"; P("button title %s\n", [it.button.title UTF8String]);
  NSMenu *m = [[NSMenu alloc] initWithTitle:@"m"]; it.menu = m; P("menu set %d\n", it.menu == m);
  [bar removeStatusItem:it]; P("removed\n");
  NSStatusItem *fixed = [bar statusItemWithLength:24]; P("fixed length %g\n", fixed.length);
  P("PASS appkit_statusitem\n");
  fflush(stdout); _exit(0);
} return 0; }
