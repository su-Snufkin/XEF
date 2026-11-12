// NSColorSpace (predefined spaces, models, component counts, names) and NSRunningApplication additions. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
static void cs(const char *n, NSColorSpace *c) { P("%s: nonnil %d model %ld components %ld name %s\n", n, c != nil, (long)c.colorSpaceModel, (long)c.numberOfColorComponents, c.localizedName ? [c.localizedName UTF8String] : "nil"); }
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  cs("sRGB", [NSColorSpace sRGBColorSpace]); cs("genericRGB", [NSColorSpace genericRGBColorSpace]); cs("deviceRGB", [NSColorSpace deviceRGBColorSpace]);
  cs("genericGray", [NSColorSpace genericGrayColorSpace]); cs("deviceGray", [NSColorSpace deviceGrayColorSpace]); cs("genericCMYK", [NSColorSpace genericCMYKColorSpace]); cs("deviceCMYK", [NSColorSpace deviceCMYKColorSpace]);
  cs("gamma22gray", [NSColorSpace genericGamma22GrayColorSpace]); cs("extSRGB", [NSColorSpace extendedSRGBColorSpace]); cs("displayP3", [NSColorSpace displayP3ColorSpace]); cs("adobeRGB", [NSColorSpace adobeRGB1998ColorSpace]);
  P("same singleton %d different %d\n", [NSColorSpace sRGBColorSpace] == [NSColorSpace sRGBColorSpace], [NSColorSpace sRGBColorSpace] != [NSColorSpace displayP3ColorSpace]);
  P("rgb spaces >0 %d cmyk spaces >0 %d\n", [NSColorSpace availableColorSpacesWithModel:NSColorSpaceModelRGB].count > 0, [NSColorSpace availableColorSpacesWithModel:NSColorSpaceModelCMYK].count > 0);
  NSRunningApplication *me = [NSRunningApplication currentApplication];
  P("running app: terminated %d ownsMenuBar %d policy %ld bundleURL nil %d launchDate nil %d icon nil %d arch>0 %d pid>0 %d\n", me.isTerminated, me.ownsMenuBar, (long)me.activationPolicy, me.bundleURL == nil, me.launchDate == nil, me.icon == nil, me.executableArchitecture > 0, me.processIdentifier > 0);
  NSRunningApplication *byPid = [NSRunningApplication runningApplicationWithProcessIdentifier:me.processIdentifier]; P("byPid found %d bogus %d\n", byPid != nil, [NSRunningApplication runningApplicationWithProcessIdentifier:2000000] != nil);
  P("PASS appkit_colorspace\n");
  fflush(stdout); _exit(0);
} return 0; }
