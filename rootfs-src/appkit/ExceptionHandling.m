/*
 * ExceptionHandling implementation for XEF
 * Generated from Darling specs
 */

#import <Foundation/Foundation.h>

@interface NSExceptionHandler : NSObject @end
@implementation NSExceptionHandler
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}
- (void)forwardInvocation:(NSInvocation *)anInvocation {}
@end

