/*
 * ScriptingBridge implementation for XEF
 * Generated from Darling specs
 */

#import <Foundation/Foundation.h>

@interface SBApplication : NSObject @end
@implementation SBApplication
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}
- (void)forwardInvocation:(NSInvocation *)anInvocation {}
@end

@interface SBElementArray : NSObject @end
@implementation SBElementArray
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}
- (void)forwardInvocation:(NSInvocation *)anInvocation {}
@end

@interface SBObject : NSObject @end
@implementation SBObject
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}
- (void)forwardInvocation:(NSInvocation *)anInvocation {}
@end

