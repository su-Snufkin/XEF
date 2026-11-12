// NSColor: CMYK components, hue-based factory with a color space, pattern colors, catalog names, control tint. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSColor *c = [NSColor colorWithDeviceRed:0.2 green:0.4 blue:0.6 alpha:1];
  NSColor *cm = [c colorUsingColorSpace:[NSColorSpace deviceCMYKColorSpace]];
  P("cmyk conv %d\n", cm != nil);
  CGFloat cy, m, y, k, a;
  NSColor *cmyk = [NSColor colorWithDeviceCyan:0.1 magenta:0.2 yellow:0.3 black:0.4 alpha:0.5];
  [cmyk getCyan:&cy magenta:&m yellow:&y black:&k alpha:&a]; P("cmyk roundtrip %.2f %.2f %.2f %.2f %.2f\n", cy, m, y, k, a);
  P("components cyan %.2f magenta %.2f yellow %.2f black %.2f\n", cmyk.cyanComponent, cmyk.magentaComponent, cmyk.yellowComponent, cmyk.blackComponent);
  NSColor *h = [NSColor colorWithColorSpace:[NSColorSpace deviceRGBColorSpace] hue:0.5 saturation:1 brightness:1 alpha:1];
  CGFloat r, g, b; [[h colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] getRed:&r green:&g blue:&b alpha:&a]; P("hue .5 -> rgb %.2f %.2f %.2f\n", r, g, b);
  NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(4, 4)];
  NSColor *pat = [NSColor colorWithPatternImage:img]; P("pattern type %ld image same %d\n", (long)pat.type, pat.patternImage == img);
  P("system colors exist: insertion %d selMenuText %d quinary %d\n", [NSColor textInsertionPointColor] != nil, [NSColor selectedMenuItemTextColor] != nil, [NSColor quinarySystemFillColor] != nil);
  P("controlTint %ld\n", (long)[NSColor currentControlTint]);
  P("PASS appkit_color2\n");
  fflush(stdout); _exit(0);
} return 0; }
