// NSEPSImageRep (header parsing) and NSCachedImageRep (geometry). Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSData *eps = [@"%!PS-Adobe-3.0 EPSF-3.0\n%%BoundingBox: 10 20 110 70\n%%EndComments\nnewpath 0 0 moveto showpage\n" dataUsingEncoding:NSASCIIStringEncoding];
  P("canInit %d junk %d\n", [NSEPSImageRep canInitWithData:eps], [NSEPSImageRep canInitWithData:[NSData dataWithBytes:"junk" length:4]]);
  NSEPSImageRep *r = [NSEPSImageRep imageRepWithData:eps];
  P("rep %d bbox %s size %gx%g class %s\n", r != nil, r ? [NSStringFromRect(r.boundingBox) UTF8String] : "nil", r.size.width, r.size.height, [NSStringFromClass([NSImageRep imageRepClassForData:eps]) UTF8String]);
  P("EPSRepresentation same length %d\n", [r EPSRepresentation].length == eps.length);
  NSCachedImageRep *c = [[NSCachedImageRep alloc] initWithSize:NSMakeSize(30, 20) depth:0 separate:NO alpha:YES];
  P("cached: rect %s size %gx%g window nil %d alpha %d\n", [NSStringFromRect(c.rect) UTF8String], c.size.width, c.size.height, c.window == nil, c.hasAlpha);
  P("PASS appkit_epscache\n");
  fflush(stdout); _exit(0);
} return 0; }
