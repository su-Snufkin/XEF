// NSImageRep base class, bitmap rep as an image rep, custom rep drawing, class-level registry. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
@interface Painter : NSObject { @public int calls; } - (BOOL)paint:(NSImageRep *)rep; @end
@implementation Painter - (BOOL)paint:(NSImageRep *)rep { calls++; [[NSColor redColor] set]; NSRectFill(NSMakeRect(0, 0, 100, 100)); return YES; } @end
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSBitmapImageRep *b = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:4 pixelsHigh:3 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
  NSImageRep *r = b;
  P("bitmap as rep: class ok %d size %gx%g pixels %ldx%ld alpha %d bps %ld cs %s opaque %d\n", [r isKindOfClass:[NSImageRep class]], r.size.width, r.size.height, (long)r.pixelsWide, (long)r.pixelsHigh, r.hasAlpha, (long)r.bitsPerSample, [r.colorSpaceName UTF8String], r.isOpaque);
  r.size = NSMakeSize(8, 6); P("size set %gx%g pixels still %ldx%ld\n", r.size.width, r.size.height, (long)r.pixelsWide, (long)r.pixelsHigh);
  unsigned char *d = b.bitmapData; for (int i = 0; i < 4 * 3; i++) { d[i * 4] = 255; d[i * 4 + 3] = 255; }
  NSData *png = [b representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
  P("png %d canInit %d canInit junk %d\n", png.length > 0, [NSBitmapImageRep canInitWithData:png], [NSBitmapImageRep canInitWithData:[NSData dataWithBytes:"junk" length:4]]);
  Class c = [NSImageRep imageRepClassForData:png]; P("class for png data %s\n", c ? [NSStringFromClass(c) UTF8String] : "nil");
  P("registered has bitmap %d\n", [[NSImageRep registeredImageRepClasses] containsObject:[NSBitmapImageRep class]]);
  P("image types >0 %d\n", [NSImageRep imageUnfilteredTypes].count > 0);
  [png writeToFile:@"/tmp/xef_rep.png" atomically:YES];
  NSImageRep *fr = [NSImageRep imageRepWithContentsOfFile:@"/tmp/xef_rep.png"]; P("rep from file %d class %s pixels %ldx%ld\n", fr != nil, fr ? [NSStringFromClass([fr class]) UTF8String] : "nil", (long)fr.pixelsWide, (long)fr.pixelsHigh);
  NSArray *frs = [NSImageRep imageRepsWithContentsOfFile:@"/tmp/xef_rep.png"]; P("reps from file %lu\n", (unsigned long)frs.count);
  P("missing file %d\n", [NSImageRep imageRepWithContentsOfFile:@"/nonexistent.png"] != nil);
  Painter *pt = [Painter new];
  NSCustomImageRep *cr = [[NSCustomImageRep alloc] initWithDrawSelector:@selector(paint:) delegate:pt];
  cr.size = NSMakeSize(10, 10);
  P("custom: selector ok %d delegate ok %d size %gx%g\n", cr.drawSelector == @selector(paint:), cr.delegate == pt, cr.size.width, cr.size.height);
  NSBitmapImageRep *dst = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:10 pixelsHigh:10 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
  [NSGraphicsContext saveGraphicsState]; [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:dst]];
  BOOL ok = [cr drawInRect:NSMakeRect(0, 0, 10, 10)];
  [NSGraphicsContext restoreGraphicsState];
  unsigned char *o = dst.bitmapData; P("custom draw ok %d calls %d center %d %d %d %d\n", ok, pt->calls, o[(5 * 10 + 5) * 4], o[(5 * 10 + 5) * 4 + 1], o[(5 * 10 + 5) * 4 + 2], o[(5 * 10 + 5) * 4 + 3]);
  NSCustomImageRep *hr = [[NSCustomImageRep alloc] initWithSize:NSMakeSize(6, 6) flipped:NO drawingHandler:^BOOL(NSRect rect) { [[NSColor blueColor] set]; NSRectFill(rect); return YES; }];
  P("handler rep size %gx%g handler %d\n", hr.size.width, hr.size.height, hr.drawingHandler != nil);
  NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(10, 10)]; [img addRepresentation:cr];
  P("image reps %lu first class %s\n", (unsigned long)img.representations.count, [NSStringFromClass([img.representations[0] class]) UTF8String]);
  P("PASS appkit_imagerep\n");
  fflush(stdout); _exit(0);
} return 0; }
