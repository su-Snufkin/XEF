// NSWorkspace: type utilities, file labels, volumes, file system info, shared instance. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSWorkspace *w = [NSWorkspace sharedWorkspace];
  P("shared %d same %d\n", w != nil, w == [NSWorkspace sharedWorkspace]);
  const char *types[] = { "public.png", "public.jpeg", "public.plain-text", "public.html", "com.adobe.pdf", "public.data", "public.item", "public.image", "public.json", "public.xml" };
  for (int i = 0; i < 10; i++) {
    NSString *t = @(types[i]);
    P("%s: ext %s desc %s\n", types[i], [[w preferredFilenameExtensionForType:t] UTF8String] ?: "nil", [[w localizedDescriptionForType:t] UTF8String] ?: "nil");
  }
  P("conforms png->image %d png->data %d png->text %d jpeg->image %d text->data %d html->text %d html->png %d pdf->data %d same %d\n",
    [w type:@"public.png" conformsToType:@"public.image"], [w type:@"public.png" conformsToType:@"public.data"], [w type:@"public.png" conformsToType:@"public.plain-text"],
    [w type:@"public.jpeg" conformsToType:@"public.image"], [w type:@"public.plain-text" conformsToType:@"public.data"], [w type:@"public.html" conformsToType:@"public.text"],
    [w type:@"public.html" conformsToType:@"public.png"], [w type:@"com.adobe.pdf" conformsToType:@"public.data"], [w type:@"public.png" conformsToType:@"public.png"]);
  P("validExt png/png %d png/jpg %d jpeg/jpg %d jpeg/JPEG %d\n", [w filenameExtension:@"png" isValidForType:@"public.png"], [w filenameExtension:@"jpg" isValidForType:@"public.png"], [w filenameExtension:@"jpg" isValidForType:@"public.jpeg"], [w filenameExtension:@"JPEG" isValidForType:@"public.jpeg"]);
  NSError *e = nil;
  NSFileManager *fm = [NSFileManager defaultManager]; [fm removeItemAtPath:@"/tmp/xef_ws" error:nil]; [fm createDirectoryAtPath:@"/tmp/xef_ws/X.app" withIntermediateDirectories:YES attributes:nil error:nil];
  [@"hello" writeToFile:@"/tmp/xef_ws/a.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil]; [[NSData dataWithBytes:"\x89PNG" length:4] writeToFile:@"/tmp/xef_ws/b.png" atomically:YES];
  P("typeOfFile txt %s png %s dir %s unknown %s\n", [[w typeOfFile:@"/tmp/xef_ws/a.txt" error:&e] UTF8String] ?: "nil", [[w typeOfFile:@"/tmp/xef_ws/b.png" error:&e] UTF8String] ?: "nil", [[w typeOfFile:@"/tmp/xef_ws" error:&e] UTF8String] ?: "nil", [[w typeOfFile:@"/nonexistent/x.png" error:&e] UTF8String] ?: "nil");
  P("labels %lu colors %lu\n", (unsigned long)w.fileLabels.count, (unsigned long)w.fileLabelColors.count);
  P("isFilePackage app %d txt %d dir %d\n", [w isFilePackageAtPath:@"/tmp/xef_ws/X.app"], [w isFilePackageAtPath:@"/tmp/xef_ws/a.txt"], [w isFilePackageAtPath:@"/tmp"]);
  P("mounted volumes include root %d\n", [[w mountedLocalVolumePaths] containsObject:@"/"]);
  BOOL rem = YES, wr = NO, un = YES; NSString *d = nil, *ty = nil;
  BOOL ok = [w getFileSystemInfoForPath:@"/" isRemovable:&rem isWritable:&wr isUnmountable:&un description:&d type:&ty];
  P("fsinfo ok %d removable %d unmountable %d\n", ok, rem, un);
  P("fsinfo bad %d\n", [w getFileSystemInfoForPath:@"/nonexistent/dir" isRemovable:&rem isWritable:&wr isUnmountable:&un description:&d type:&ty]);
  NSURL *none = [w URLForApplicationWithBundleIdentifier:@"com.example.nonexistent.app"]; P("unknown app url %d\n", none != nil);
  P("urls for unknown id %lu\n", (unsigned long)[w URLsForApplicationsWithBundleIdentifier:@"com.example.nonexistent.app"].count);
  P("fullPath unknown %d\n", [w fullPathForApplication:@"NoSuchAppAnywhere"] != nil);
  NSImage *icon = [w iconForFile:@"/tmp/xef_ws/a.txt"]; P("icon %d size %gx%g\n", icon != nil, icon.size.width, icon.size.height);
  NSImage *ti = [w iconForFileType:@"txt"]; P("typeicon %d size %gx%g\n", ti != nil, ti.size.width, ti.size.height);
  P("frontmost %d running>=1 %d\n", w.frontmostApplication != nil, w.runningApplications.count >= 1);
  P("PASS appkit_workspace\n");
  fflush(stdout); _exit(0);
} return 0; }
