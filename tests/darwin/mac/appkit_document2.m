// NSDocument: duplicate, move, lock, deprecated file-name API, writable types. Real AppKit is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
@interface Doc : NSDocument { @public NSString *text; } @end
@implementation Doc
+ (BOOL)autosavesInPlace { return NO; }
- (NSData *)dataOfType:(NSString *)t error:(NSError **)e { return [text ?: @"" dataUsingEncoding:NSUTF8StringEncoding]; }
- (BOOL)readFromData:(NSData *)d ofType:(NSString *)t error:(NSError **)e { text = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]; return YES; }
- (void)makeWindowControllers {}
@end
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSFileManager *fm = [NSFileManager defaultManager]; [fm removeItemAtPath:@"/tmp/xef_doc2" error:nil]; [fm createDirectoryAtPath:@"/tmp/xef_doc2" withIntermediateDirectories:YES attributes:nil error:nil];
  Doc *d = [[Doc alloc] init]; d->text = @"hello";
  P("isEntireFileLoaded %d locked %d fileName %s backup %d sharing %d\n", d.isEntireFileLoaded, d.isLocked, d.fileName ? [d.fileName UTF8String] : "nil", d.backupFileURL != nil, d.allowsDocumentSharing);
  d.fileType = @"public.plain-text"; d.fileName = @"/tmp/xef_doc2/a.txt";
  P("fileName %s url %s lastComponent %s\n", [d.fileName UTF8String], [d.fileURL.path UTF8String], [d.lastComponentOfFileName UTF8String]);
  d.lastComponentOfFileName = @"b.txt"; P("renamed %s\n", [d.fileName UTF8String]);
  [d writeToURL:[NSURL fileURLWithPath:@"/tmp/xef_doc2/b.txt"] ofType:@"public.plain-text" error:nil]; P("written exists %d\n", [fm fileExistsAtPath:@"/tmp/xef_doc2/b.txt"]);
  [d lockWithCompletionHandler:^(NSError *err) { }]; P("locked %d\n", d.isLocked);
  [d unlockWithCompletionHandler:^(NSError *err) { }]; P("unlocked %d\n", d.isLocked);
  P("writableTypes %d\n", [d writableTypesForSaveOperation:0] != nil);
  P("async %d\n", [d canAsynchronouslyWriteToURL:[NSURL fileURLWithPath:@"/tmp/x"] ofType:@"public.plain-text" forSaveOperation:0]);
  P("PASS appkit_document2\n");
  fflush(stdout); _exit(0);
} return 0; }
