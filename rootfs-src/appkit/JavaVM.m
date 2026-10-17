/*
 * JavaVM implementation for XEF
 * Generated from Darling specs
 */

#import <Foundation/Foundation.h>

@interface NSJavaConfiguration : NSObject @end
@implementation NSJavaConfiguration
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}
- (void)forwardInvocation:(NSInvocation *)anInvocation {}
@end

@interface NSJavaVirtualMachine : NSObject @end
@implementation NSJavaVirtualMachine
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}
- (void)forwardInvocation:(NSInvocation *)anInvocation {}
@end

