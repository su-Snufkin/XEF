// NSButtonCell extras and NSMenuItemCell, compared with macOS.
#import <Cocoa/Cocoa.h>
int main(void){ @autoreleasepool { [NSApplication sharedApplication];
  NSButtonCell *c = [[NSButtonCell alloc] initTextCell:@"Go"];
  printf("aat '%s'\n", [[[c attributedAlternateTitle] string] UTF8String]);
  [c setAttributedAlternateTitle:[[NSAttributedString alloc] initWithString:@"Stop"]];
  printf("alt '%s' aat '%s'\n", [[c alternateTitle] UTF8String], [[[c attributedAlternateTitle] string] UTF8String]);
  printf("sound %d grad %ld\n", [c sound] != nil, (long)[c gradientType]);
  [c setGradientType:2]; printf("grad %ld\n", (long)[c gradientType]);
  [c setAlternateTitleWithMnemonic:@"S&top"];
  printf("mn '%s' loc %lu alt '%s'\n", [[c alternateMnemonic] UTF8String], (unsigned long)[c alternateMnemonicLocation], [[c alternateTitle] UTF8String]);
  printf("kef %d\n", [c keyEquivalentFont] != nil);
  NSMenuItemCell *m = [[NSMenuItemCell alloc] init];
  printf("super %s ns %d nd %d\n", [NSStringFromClass([m superclass]) UTF8String], [m needsSizing], [m needsDisplay]);
  NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:@"Open" action:NULL keyEquivalent:@""];
  [m setMenuItem:mi]; printf("mi %d ns %d\n", [m menuItem] == mi, [m needsSizing]);
  [m calcSize]; printf("ns %d\n", [m needsSizing]);
  [m setNeedsDisplay:YES]; printf("nd %d\n", [m needsDisplay]);
  printf("kw %g sw %g\n", [m keyEquivalentWidth], [m stateImageWidth]);
  return 0; } }
