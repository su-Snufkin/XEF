/*
 * pbpaste implementation for XEF
 */

#import <Foundation/Foundation.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSString *clipPath = @"/tmp/.xef_clipboard";
        NSString *str = [NSString stringWithContentsOfFile:clipPath encoding:NSUTF8StringEncoding error:nil];
        if (str) {
            printf("%s", [str UTF8String]);
        }
        return 0;
    }
}
