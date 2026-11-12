// NSImage: stored settings and their defaults, hit testing, deprecated compositing. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(4, 4)];
  [img lockFocus]; [[NSColor redColor] set]; NSRectFill(NSMakeRect(0, 0, 2, 4)); [img unlockFocus];
  P("defaults: bg clear %d eps %d colorMatch %d multiRes %d bestAxis %d cacheMode %ld scalesWhenResized %d dataRetained %d cachedSeparately %d cacheDepth %d delegate %d\n",
    [img.backgroundColor isEqual:[NSColor clearColor]], img.usesEPSOnResolutionMismatch, img.prefersColorMatch, img.matchesOnMultipleResolution, img.matchesOnlyOnBestFittingAxis, (long)img.cacheMode, img.scalesWhenResized, img.isDataRetained, img.isCachedSeparately, img.cacheDepthMatchesImageDepth, img.delegate != nil);
  img.matchesOnMultipleResolution = NO; img.prefersColorMatch = NO; img.cacheMode = NSImageCacheNever; img.backgroundColor = [NSColor blueColor]; img.usesEPSOnResolutionMismatch = YES;
  P("set: multiRes %d colorMatch %d cacheMode %ld bg blue %d eps %d\n", img.matchesOnMultipleResolution, img.prefersColorMatch, (long)img.cacheMode, [img.backgroundColor isEqual:[NSColor blueColor]], img.usesEPSOnResolutionMismatch);
  BOOL left = [img hitTestRect:NSMakeRect(0, 0, 1, 1) withImageDestinationRect:NSMakeRect(0, 0, 4, 4) context:nil hints:nil flipped:NO];
  BOOL right = [img hitTestRect:NSMakeRect(3, 1, 1, 1) withImageDestinationRect:NSMakeRect(0, 0, 4, 4) context:nil hints:nil flipped:NO];
  BOOL outside = [img hitTestRect:NSMakeRect(10, 10, 1, 1) withImageDestinationRect:NSMakeRect(0, 0, 4, 4) context:nil hints:nil flipped:NO];
  P("hit left(red) %d right(clear) %d outside %d\n", left, right, outside);
  P("symbol nil %d\n", [NSImage imageWithSystemSymbolName:@"nonexistent.symbol.name" variableValue:0.5 accessibilityDescription:nil] == nil);
  P("PASS appkit_image2\n");
  fflush(stdout); _exit(0);
} return 0; }
