// AppKit 2D drawing test: a custom view drawn with NSColor/NSRectFill, NSBezierPath, CGContext gradients, string drawing
// and an NSImage, plus a flipped subview. Build: tests/darwin/appkit2d/build.sh; run with XEF_APPKIT_SHOT=out.ppm.
#import <Cocoa/Cocoa.h>

@interface Canvas : NSView
@end
@implementation Canvas
- (void)drawRect:(NSRect)dirty {
  [[NSColor colorWithCalibratedRed:0.95 green:0.93 blue:0.85 alpha:1] setFill];
  NSRectFill(self.bounds);
  // rounded rect, filled + stroked
  NSBezierPath *rr = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(20, 20, 160, 100) xRadius:16 yRadius:16];
  [[NSColor systemBlueColor] setFill]; [rr fill];
  [[NSColor blackColor] setStroke]; [rr setLineWidth:3]; [rr stroke];
  // oval
  [[NSColor colorWithCalibratedRed:1 green:0.4 blue:0.2 alpha:0.8] setFill];
  [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(200, 20, 120, 100)] fill];
  // CG gradient
  CGContextRef c = [[NSGraphicsContext currentContext] CGContext];
  CGContextSaveGState(c);
  CGContextClipToRect(c, CGRectMake(340, 20, 140, 100));
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGFloat comps[] = {0.1, 0.8, 0.2, 1, 0.1, 0.2, 0.9, 1};
  CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, NULL, 2);
  CGContextDrawLinearGradient(c, g, CGPointMake(340, 20), CGPointMake(480, 120), 0);
  CGGradientRelease(g); CGColorSpaceRelease(cs);
  CGContextRestoreGState(c);
  // text
  NSDictionary *a = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:24], NSForegroundColorAttributeName: [NSColor darkGrayColor]};
  [@"Hello from XEF AppKit 2D" drawAtPoint:NSMakePoint(20, 150) withAttributes:a];
  NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init]; ps.alignment = NSTextAlignmentCenter;
  NSDictionary *b = @{NSFontAttributeName: [NSFont fontWithName:@"Times" size:16], NSParagraphStyleAttributeName: ps,
                      NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.5 green:0 blue:0.5 alpha:1]};
  [@"Wrapped, centred text in a rectangle: the quick brown fox jumps over the lazy dog." drawInRect:NSMakeRect(20, 190, 300, 60) withAttributes:b];
  [[NSColor redColor] setFill]; NSFrameRect(NSMakeRect(20, 190, 300, 60));
  // image from a bitmap
  NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:32 pixelsHigh:32 bitsPerSample:8 samplesPerPixel:4
      hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:32 * 4 bitsPerPixel:32];
  unsigned char *p = rep.bitmapData;
  for (int y = 0; y < 32; y++) for (int x = 0; x < 32; x++) { unsigned char *q = p + (y * 32 + x) * 4; q[0] = x * 8; q[1] = y * 8; q[2] = 128; q[3] = 255; }
  NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(32, 32)]; [img addRepresentation:rep];
  [img drawInRect:NSMakeRect(360, 150, 96, 96)];
}
@end

@interface FlippedLabel : NSView
@end
@implementation FlippedLabel
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)r {
  [[NSColor whiteColor] setFill]; NSRectFill(self.bounds);
  [[NSColor blueColor] setFill]; NSRectFill(NSMakeRect(0, 0, 20, 10));   // top-left in a flipped view
  [@"flipped: top line" drawAtPoint:NSMakePoint(24, 0) withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:13]}];
}
@end

int main(int argc, char **argv) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 500, 330)
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    w.title = @"appkit2d";
    Canvas *v = [[Canvas alloc] initWithFrame:NSMakeRect(0, 0, 500, 330)];
    FlippedLabel *f = [[FlippedLabel alloc] initWithFrame:NSMakeRect(20, 270, 300, 40)];
    [v addSubview:f];
    w.contentView = v;
    [w makeKeyAndOrderFront:nil];
    [NSApp run];
  }
  return 0;
}
