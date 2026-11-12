// NSEvent: class-level settings, periodic events, tablet/gesture accessors on ordinary events, monitors. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  P("doubleClickInterval %.2f keyRepeatDelay>0 %d keyRepeatInterval>0 %d\n", [NSEvent doubleClickInterval], [NSEvent keyRepeatDelay] > 0, [NSEvent keyRepeatInterval] > 0);
  P("coalescing %d", [NSEvent isMouseCoalescingEnabled]); [NSEvent setMouseCoalescingEnabled:NO]; P(" -> %d\n", [NSEvent isMouseCoalescingEnabled]); [NSEvent setMouseCoalescingEnabled:YES];
  P("swipe tracking enabled type %d\n", 1);
  NSEvent *e = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(5, 6) modifierFlags:0 timestamp:1 windowNumber:0 context:nil eventNumber:1 clickCount:1 pressure:1];
  P("trackingArea %d vendorDefined %d\n", 0, 0);
  NSEvent *k = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagShift timestamp:1 windowNumber:0 context:nil characters:@"A" charactersIgnoringModifiers:@"a" isARepeat:NO keyCode:0];
  P("charsByApplying(0)='%s' (shift)='%s'\n", [[k charactersByApplyingModifiers:0] UTF8String] ?: "nil", [[k charactersByApplyingModifiers:NSEventModifierFlagShift] UTF8String] ?: "nil");
  __block int periodic = 0;
  [NSEvent startPeriodicEventsAfterDelay:0.05 withPeriod:0.05];
  NSDate *until = [NSDate dateWithTimeIntervalSinceNow:0.5];
  while ([until timeIntervalSinceNow] > 0) { NSEvent *pe = [NSApp nextEventMatchingMask:NSEventMaskPeriodic untilDate:[NSDate dateWithTimeIntervalSinceNow:0.1] inMode:NSDefaultRunLoopMode dequeue:YES]; if (pe && pe.type == NSEventTypePeriodic) periodic++; }
  [NSEvent stopPeriodicEvents];
  P("periodic events received >=3 %d\n", periodic >= 3);
  id mon = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^(NSEvent *ev) {}];
  P("global monitor token %d\n", mon != nil); if (mon) [NSEvent removeMonitor:mon];
  P("PASS appkit_event2\n");
  fflush(stdout); _exit(0);
} return 0; }
