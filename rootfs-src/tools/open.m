/*
 * open implementation for XEF
 */

#import <Foundation/Foundation.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "Usage: open <file-or-app-path>\n");
            return 1;
        }
        NSLog(@"[xef-open] Opening %@", [NSString stringWithUTF8String:argv[1]]);
        return 0;
    }
}
