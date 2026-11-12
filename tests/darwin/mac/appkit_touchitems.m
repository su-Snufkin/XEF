// Touch Bar item classes: button, slider, picker items — factories, defaults, indexed options. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(8, 8)];
  NSButtonTouchBarItem *b = [NSButtonTouchBarItem buttonTouchBarItemWithIdentifier:@"b1" title:@"Go" target:nil action:NULL];
  P("button: id %s title %s image nil %d enabled %d bezel nil %d label nil %d\n", [b.identifier UTF8String], [b.title UTF8String], b.image == nil, b.isEnabled, b.bezelColor == nil, b.customizationLabel == nil);
  NSButtonTouchBarItem *b2 = [NSButtonTouchBarItem buttonTouchBarItemWithIdentifier:@"b2" image:img target:nil action:NULL]; P("button image: title '%s' image same %d\n", [b2.title UTF8String], b2.image == img);
  NSButtonTouchBarItem *b3 = [NSButtonTouchBarItem buttonTouchBarItemWithIdentifier:@"b3" title:@"T" image:img target:nil action:NULL]; P("button both: title %s image %d\n", [b3.title UTF8String], b3.image != nil);
  b.title = @"X"; b.enabled = NO; b.customizationLabel = @"Lbl"; b.bezelColor = [NSColor redColor]; P("set: %s %d %s bezel %d\n", [b.title UTF8String], b.isEnabled, [b.customizationLabel UTF8String], b.bezelColor != nil);
  NSSliderTouchBarItem *s = [[NSSliderTouchBarItem alloc] initWithIdentifier:@"s1"];
  P("slider: value %g min %g max %g label nil %d valueAccessoryWidth %ld slider nonnil %d\n", s.doubleValue, s.minimumSliderWidth, s.maximumSliderWidth, s.label == nil, (long)s.valueAccessoryWidth, s.slider != nil);
  s.doubleValue = 0.5; s.label = @"Vol"; s.minimumSliderWidth = 100; s.maximumSliderWidth = 300; P("set: %g %s %g %g slider value %g\n", s.doubleValue, [s.label UTF8String], s.minimumSliderWidth, s.maximumSliderWidth, s.slider.doubleValue);
  NSPickerTouchBarItem *p = [NSPickerTouchBarItem pickerTouchBarItemWithIdentifier:@"p1" labels:@[@"A", @"B", @"C"] selectionMode:NSPickerTouchBarItemSelectionModeSelectOne target:nil action:NULL];
  P("picker: options %ld selected %ld mode %ld enabled %d labelAt1 %s repr %ld\n", (long)p.numberOfOptions, (long)p.selectedIndex, (long)p.selectionMode, p.isEnabled, [[p labelAtIndex:1] UTF8String], (long)p.controlRepresentation);
  p.selectedIndex = 2; [p setEnabled:NO atIndex:1]; P("set: selected %ld enabledAt1 %d enabledAt0 %d\n", (long)p.selectedIndex, [p isEnabledAtIndex:1], [p isEnabledAtIndex:0]);
  [p setLabel:@"Z" atIndex:0]; p.numberOfOptions = 4; P("label0 %s options %ld imageAt0 nil %d\n", [[p labelAtIndex:0] UTF8String], (long)p.numberOfOptions, [p imageAtIndex:0] == nil);
  NSPickerTouchBarItem *pi = [NSPickerTouchBarItem pickerTouchBarItemWithIdentifier:@"p2" images:@[img, img] selectionMode:NSPickerTouchBarItemSelectionModeMomentary target:nil action:NULL]; P("image picker: options %ld mode %ld image0 %d\n", (long)pi.numberOfOptions, (long)pi.selectionMode, [pi imageAtIndex:0] != nil);
  P("class hierarchy: %d\n", [b isKindOfClass:[NSTouchBarItem class]] && [s isKindOfClass:[NSTouchBarItem class]]);
  P("PASS appkit_touchitems\n");
  fflush(stdout); _exit(0);
} return 0; }
