// NSApplication: modal sessions, stopModal codes, enumerateWindows, activation policy, validation. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
@interface T : NSObject { @public int fired; NSInteger code; } - (void)stopIt:(NSTimer *)t; - (void)doIt:(id)s; @end
@implementation T
- (void)stopIt:(NSTimer *)t { fired++; P("  timer fired, modalWindow set %d\n", [NSApp modalWindow] != nil); if (code == -1) [NSApp abortModal]; else if (code == 0) [NSApp stopModal]; else [NSApp stopModalWithCode:code]; }
- (void)doIt:(id)s {}
@end
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  P("policy default %ld set %d now %ld\n", (long)[NSApp activationPolicy], [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory], (long)[NSApp activationPolicy]);
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  NSWindow *w2 = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  [w makeKeyAndOrderFront:nil]; [w2 orderFront:nil];
  T *t = [T new];
  P("modalWindow before %d\n", [NSApp modalWindow] != nil);
  NSInteger codes[] = { 0, 42, -1 };
  for (int i = 0; i < 3; i++) {
    t->code = codes[i];
    NSTimer *tm = [NSTimer timerWithTimeInterval:0.1 target:t selector:@selector(stopIt:) userInfo:nil repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:tm forMode:NSRunLoopCommonModes];
    NSInteger r = [NSApp runModalForWindow:w];
    P("modal %d returned %ld\n", i, (long)r);
  }
  P("== session\n");
  NSModalSession s = [NSApp beginModalSessionForWindow:w];
  NSInteger r = [NSApp runModalSession:s]; P("running session -> %ld (continue=%d)\n", (long)r, r == NSModalResponseContinue);
  [NSApp stopModalWithCode:7]; r = [NSApp runModalSession:s]; P("after stop -> %ld\n", (long)r);
  [NSApp endModalSession:s]; P("modalWindow after %d\n", [NSApp modalWindow] != nil);
  P("== windows\n");
  __block int n = 0; [NSApp enumerateWindowsWithOptions:0 usingBlock:^(NSWindow *x, BOOL *stop) { n++; }]; P("enumerated %d\n", n);
  __block int m = 0; [NSApp enumerateWindowsWithOptions:0 usingBlock:^(NSWindow *x, BOOL *stop) { m++; *stop = YES; }]; P("enumerated with stop %d\n", m);
  P("== validation\n");
  NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:@"X" action:@selector(nonexistentAction:) keyEquivalent:@""];
  P("validate unknown action %d\n", [NSApp validateMenuItem:mi]);
  NSMenuItem *mi2 = [[NSMenuItem alloc] initWithTitle:@"Y" action:@selector(hide:) keyEquivalent:@""];
  P("validate hide: %d\n", [NSApp validateMenuItem:mi2]);
  P("layout direction %ld dockTile %d appearance-ish %d\n", (long)[NSApp userInterfaceLayoutDirection], [NSApp dockTile] != nil, 1);
  P("PASS appkit_modal\n");
  fflush(stdout); _exit(0);
} return 0; }
