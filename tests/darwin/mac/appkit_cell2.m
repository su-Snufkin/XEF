// NSCell: take*ValueFrom, cell attributes, periodic delays, identifier, focus ring helpers, deprecated entry/mnemonic API. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSCell *c = [[NSCell alloc] initTextCell:@"x"];
  NSTextField *src = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 50, 20)]; src.doubleValue = 3.5;
  [c takeFloatValueFrom:src]; P("takeFloat %.1f int %ld\n", c.floatValue, (long)c.integerValue);
  src.integerValue = 7; [c takeIntegerValueFrom:src]; P("takeInteger %ld\n", (long)c.integerValue);
  float delay = 0, interval = 0; [c getPeriodicDelay:&delay interval:&interval]; P("periodic delay %.2f interval %.3f\n", delay, interval);
  P("cellAttribute enabled %ld highlighted %ld state %ld editable %ld\n", (long)[c cellAttribute:NSCellDisabled], (long)[c cellAttribute:NSCellHighlighted], (long)[c cellAttribute:NSCellState], (long)[c cellAttribute:NSCellEditable]);
  [c setCellAttribute:NSCellEditable to:1]; P("after set editable %d attr %ld\n", c.isEditable, (long)[c cellAttribute:NSCellEditable]);
  [c setCellAttribute:NSCellState to:1]; P("after set state %ld\n", (long)c.state);
  P("identifier nil %d", c.identifier == nil); c.identifier = @"cid"; P(" -> %s\n", [c.identifier UTF8String]);
  P("sendsActionOnEndEditing %d", c.sendsActionOnEndEditing); c.sendsActionOnEndEditing = YES; P(" -> %d\n", c.sendsActionOnEndEditing);
  P("defaultFocusRingType %ld\n", (long)[NSCell defaultFocusRingType]);
  P("wantsNotificationForMarkedText %d\n", c.wantsNotificationForMarkedText);
  P("mouseDownFlags %ld\n", (long)c.mouseDownFlags);
  P("menuForEvent nil %d\n", [c menuForEvent:nil inRect:NSMakeRect(0, 0, 10, 10) ofView:src] == nil);
  NSRect fr = [c focusRingMaskBoundsForFrame:NSMakeRect(0, 0, 40, 20) inView:src]; P("focus ring mask %g,%g,%g,%g\n", fr.origin.x, fr.origin.y, fr.size.width, fr.size.height);
  P("highlightColor nonnil %d\n", [c highlightColorWithFrame:NSMakeRect(0, 0, 40, 20) inView:src] != nil);
  P("PASS appkit_cell2\n");
  fflush(stdout); _exit(0);
} return 0; }
