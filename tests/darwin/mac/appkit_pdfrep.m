// NSPDFImageRep: page count, bounds, current page, drawing a page, NSImage from PDF data, registry. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
static const unsigned char kPDF[] = {37,80,68,70,45,49,46,52,10,49,32,48,32,111,98,106,10,60,60,32,47,84,121,112,101,32,47,67,97,116,97,108,111,103,32,47,80,97,103,101,115,32,50,32,48,32,82,32,62,62,10,101,110,100,111,98,106,10,50,32,48,32,111,98,106,10,60,60,32,47,84,121,112,101,32,47,80,97,103,101,115,32,47,75,105,100,115,32,91,51,32,48,32,82,93,32,47,67,111,117,110,116,32,49,32,62,62,10,101,110,100,111,98,106,10,51,32,48,32,111,98,106,10,60,60,32,47,84,121,112,101,32,47,80,97,103,101,32,47,80,97,114,101,110,116,32,50,32,48,32,82,32,47,77,101,100,105,97,66,111,120,32,91,48,32,48,32,50,48,48,32,49,48,48,93,32,47,67,111,110,116,101,110,116,115,32,52,32,48,32,82,32,47,82,101,115,111,117,114,99,101,115,32,60,60,32,62,62,32,62,62,10,101,110,100,111,98,106,10,52,32,48,32,111,98,106,10,60,60,32,47,76,101,110,103,116,104,32,50,53,32,62,62,10,115,116,114,101,97,109,10,49,32,48,32,48,32,114,103,32,48,32,48,32,49,48,48,32,49,48,48,32,114,101,32,102,10,101,110,100,115,116,114,101,97,109,10,101,110,100,111,98,106,10,120,114,101,102,10,48,32,53,10,48,48,48,48,48,48,48,48,48,48,32,54,53,53,51,53,32,102,32,10,48,48,48,48,48,48,48,48,48,57,32,48,48,48,48,48,32,110,32,10,48,48,48,48,48,48,48,48,53,56,32,48,48,48,48,48,32,110,32,10,48,48,48,48,48,48,48,49,49,53,32,48,48,48,48,48,32,110,32,10,48,48,48,48,48,48,48,50,49,57,32,48,48,48,48,48,32,110,32,10,116,114,97,105,108,101,114,10,60,60,32,47,83,105,122,101,32,53,32,47,82,111,111,116,32,49,32,48,32,82,32,62,62,10,115,116,97,114,116,120,114,101,102,10,50,57,52,10,37,37,69,79,70,10};
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSData *d = [NSData dataWithBytes:kPDF length:sizeof kPDF];
  P("canInit %d junk %d\n", [NSPDFImageRep canInitWithData:d], [NSPDFImageRep canInitWithData:[NSData dataWithBytes:"junk" length:4]]);
  NSPDFImageRep *r = [NSPDFImageRep imageRepWithData:d];
  P("rep %d pages %ld current %ld bounds %s size %gx%g\n", r != nil, (long)r.pageCount, (long)r.currentPage, [NSStringFromRect(r.bounds) UTF8String], r.size.width, r.size.height);
  r.currentPage = 5; P("clamped current %ld\n", (long)r.currentPage);
  P("PDFRepresentation same length %d\n", [r PDFRepresentation].length == d.length);
  P("class for data %s\n", [NSStringFromClass([NSImageRep imageRepClassForData:d]) UTF8String]);
  NSImage *img = [[NSImage alloc] initWithData:d]; P("image %d size %gx%g reps %lu class %s\n", img != nil, img.size.width, img.size.height, (unsigned long)img.representations.count, [NSStringFromClass([img.representations[0] class]) UTF8String]);
  NSBitmapImageRep *dst = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:200 pixelsHigh:100 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
  [NSGraphicsContext saveGraphicsState]; [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:dst]];
  BOOL ok = [r drawInRect:NSMakeRect(0, 0, 200, 100)];
  [NSGraphicsContext restoreGraphicsState];
  unsigned char *o = dst.bitmapData; unsigned char *l = o + (50 * 200 + 50) * 4, *rr = o + (50 * 200 + 150) * 4;
  P("draw ok %d left red %d right empty %d\n", ok, l[0] > 200 && l[1] < 50 && l[3] > 200, rr[3] < 50);
  P("PASS appkit_pdfrep\n");
  fflush(stdout); _exit(0);
} return 0; }
