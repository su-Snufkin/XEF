/*
 * pbcopy implementation for XEF
 */

#import <Foundation/Foundation.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSFileHandle *input = [NSFileHandle fileHandleWithStandardInput];
        NSData *data = [input readDataToEndOfFile];
        NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (str) {
            // Write to clipboard storage or file
            NSString *clipPath = @"/tmp/.xef_clipboard";
            [str writeToFile:clipPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        return 0;
    }
}
