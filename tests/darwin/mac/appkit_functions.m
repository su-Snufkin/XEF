// Exported C functions of AppKit: window lists, depths, tiled rects, three/nine part images, pixel reads, alert panels' helpers, accessibility helpers. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSInteger n = -1; NSCountWindows(&n); P("countWindows %ld\n", (long)n);
  NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO]; [w orderFront:nil];
  NSCountWindows(&n); NSInteger list[8] = {0}; NSWindowList(MIN(n, 8), list); P("after window: count %ld first==windowNumber %d\n", (long)n, n > 0 && list[0] == [w windowNumber]);
  BOOL exact = NO; NSWindowDepth d = NSBestDepth(NSDeviceRGBColorSpace, 8, 32, NO, &exact); P("bestDepth nonzero %d exact %d\n", d != 0, exact);
  P("available depths nonnull %d\n", NSAvailableWindowDepths() != NULL);
  P("interfaceStyle %ld\n", (long)NSInterfaceStyleForKey(@"k", nil));
  P("controller marker: nsnull %d string %d\n", NSIsControllerMarker([NSNull null]), NSIsControllerMarker(@"x"));
  P("getFileType: %s\n", NSGetFileType(NSFileContentsPboardType) ? [NSGetFileType(NSFileContentsPboardType) UTF8String] : "nil");
  P("createFilenamePboardType txt: %s\n", [NSCreateFilenamePboardType(@"txt") UTF8String] ?: "nil");
  P("createFileContentsPboardType txt: %s\n", [NSCreateFileContentsPboardType(@"txt") UTF8String] ?: "nil");
  NSRectEdge sides[2] = { NSMinXEdge, NSMinYEdge }; CGFloat grays[2] = { 0.0, 0.5 };
  NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:20 pixelsHigh:20 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
  [NSGraphicsContext saveGraphicsState]; [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
  [[NSColor whiteColor] set]; NSRectFill(NSMakeRect(0, 0, 20, 20));
  NSRect rest = NSDrawTiledRects(NSMakeRect(0, 0, 20, 20), NSMakeRect(0, 0, 20, 20), sides, grays, 2); P("tiledRects remaining %s\n", [NSStringFromRect(rest) UTF8String]);
  NSColor *px = NSReadPixel(NSMakePoint(10, 10)); P("readPixel center nonnil %d\n", px != nil);
  CGFloat g[2] = { 0.25, 0.75 }; NSRect rl[2] = { NSMakeRect(5, 5, 3, 3), NSMakeRect(12, 12, 3, 3) }; NSRectFillListWithGrays(rl, g, 2);
  NSImage *red = [[NSImage alloc] initWithSize:NSMakeSize(2, 2)]; [red lockFocus]; [[NSColor redColor] set]; NSRectFill(NSMakeRect(0, 0, 2, 2)); [red unlockFocus];
  NSDrawThreePartImage(NSMakeRect(0, 0, 20, 4), red, red, red, NO, NSCompositingOperationSourceOver, 1, NO);
  [NSGraphicsContext restoreGraphicsState];
  unsigned char *o = rep.bitmapData; P("three-part drew red at (10,2): %d\n", o[(2 * 20 + 10) * 4] > 200 || o[(17 * 20 + 10) * 4] > 200);
  P("accessibility role descriptions: button '%s' textfield '%s' window '%s'\n", [NSAccessibilityRoleDescription(NSAccessibilityButtonRole, nil) UTF8String], [NSAccessibilityRoleDescription(NSAccessibilityTextFieldRole, nil) UTF8String], [NSAccessibilityRoleDescription(NSAccessibilityWindowRole, nil) UTF8String]);
  P("action description press '%s'\n", [NSAccessibilityActionDescription(NSAccessibilityPressAction) UTF8String]);
  NSRect fr = NSAccessibilityFrameInView([w contentView], NSMakeRect(1, 2, 3, 4)); P("frameInView nonzero size %d\n", fr.size.width > 0);
  NSArray *uc = NSAccessibilityUnignoredChildren(@[@"a", @"b"]); P("unignored children %lu\n", (unsigned long)uc.count);
  NSOpenGLSetOption(NSOpenGLGOFormatCacheSize, 5); GLint opt = 0; NSOpenGLGetOption(NSOpenGLGOFormatCacheSize, &opt); P("opengl option roundtrip %d\n", opt);
  GLint maj = 0, min = 0; NSOpenGLGetVersion(&maj, &min); P("opengl version major>0 %d\n", maj > 0);
  P("showsServicesMenuItem %d\n", NSShowsServicesMenuItem(@"x"));
  NSDisableScreenUpdates(); NSEnableScreenUpdates(); P("screen updates ok\n");
  P("applicationLoad %d\n", NSApplicationLoad());
  P("PASS appkit_functions\n");
  fflush(stdout); _exit(0);
} return 0; }
