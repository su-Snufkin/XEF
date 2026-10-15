#import <Foundation/Foundation.h>
int main(void) {
  @autoreleasepool {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"xef_file.txt"];
    BOOL ok = [@"file contents\nline2" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil];
    printf("write=%d\n", ok);
    NSData *d = [NSData dataWithContentsOfFile:path]; printf("data=%lu\n", (unsigned long)[d length]);
    NSError *err = nil;
    NSString *s = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
    printf("str=%lu err=%s\n", (unsigned long)[s length], err ? [[err description] UTF8String] : "none");
    NSString *s2 = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]; printf("s2=%lu\n", (unsigned long)[s2 length]);
    NSData *d2 = [@"abc" dataUsingEncoding:NSUTF8StringEncoding]; printf("d2=%lu\n", (unsigned long)[d2 length]);
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
  }
  return 0; }
