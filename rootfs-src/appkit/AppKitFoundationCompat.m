/* Foundation API that Darling's Foundation lacks and Cocoa apps call, provided by AppKit-lite (the Darling build needs
 * an older SDK; see tools/build_foundation.sh). */
#import <Foundation/Foundation.h>

/* newer Foundation notification names Darling does not define (it never posts them) */
NSString *const NSUndoManagerDidCloseUndoGroupNotification = @"NSUndoManagerDidCloseUndoGroupNotification";
/* NSKeyedUnarchiver class conveniences (macOS 10.13+), missing from Darling: decode the root object, checking only its
 * class (nested classes are not restricted: AppKit-lite's coders are not all secure) */
@implementation NSKeyedUnarchiver (XEFModern)
+ (id)_xefUnarchive:(NSData *)data classes:(NSSet *)classes error:(NSError **)error {
  if (error) *error = nil;
  if (!data) return nil;
  id result = nil;
  @try {
    NSKeyedUnarchiver *u = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    if (u) {
      result = [[[u decodeObjectForKey:@"root"] retain] autorelease];
      [u finishDecoding];
      [u release];
    }
  } @catch (id e) { result = nil; }
  if (result && classes) {
    BOOL ok = NO;
    for (Class c in classes) if ([result isKindOfClass:c]) { ok = YES; break; }
    if (!ok) result = nil;
  }
  if (!result && error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:4864 userInfo:nil];
  return result;
}
+ (id)unarchivedObjectOfClass:(Class)cls fromData:(NSData *)data error:(NSError **)error {
  return [self _xefUnarchive:data classes:cls ? [NSSet setWithObject:cls] : nil error:error];
}
+ (id)unarchivedObjectOfClasses:(NSSet *)classes fromData:(NSData *)data error:(NSError **)error {
  return [self _xefUnarchive:data classes:classes error:error];
}
+ (id)unarchiveTopLevelObjectWithData:(NSData *)data error:(NSError **)error { return [self _xefUnarchive:data classes:nil error:error]; }
+ (NSArray *)unarchivedArrayOfObjectsOfClass:(Class)cls fromData:(NSData *)data error:(NSError **)error {
  return [self _xefUnarchive:data classes:[NSSet setWithObject:[NSArray class]] error:error];
}
+ (NSArray *)unarchivedArrayOfObjectsOfClasses:(NSSet *)classes fromData:(NSData *)data error:(NSError **)error {
  return [self _xefUnarchive:data classes:[NSSet setWithObject:[NSArray class]] error:error];
}
+ (NSDictionary *)unarchivedDictionaryWithKeysOfClass:(Class)k objectsOfClass:(Class)v fromData:(NSData *)data error:(NSError **)error {
  return [self _xefUnarchive:data classes:[NSSet setWithObject:[NSDictionary class]] error:error];
}
+ (NSDictionary *)unarchivedDictionaryWithKeysOfClasses:(NSSet *)k objectsOfClasses:(NSSet *)v fromData:(NSData *)data error:(NSError **)error {
  return [self _xefUnarchive:data classes:[NSSet setWithObject:[NSDictionary class]] error:error];
}
- (NSInteger)decodingFailurePolicy { return 0; }
- (void)setDecodingFailurePolicy:(NSInteger)p {}
@end

/* clang's constant double / float numbers are {isa, value}: Darling's extras read a type-encoding ivar that is not
 * there. Fixed types and value getters by layout. */
#include <objc/runtime.h>
static const char *const_double_type(id self, SEL _cmd) { return "d"; }
static const char *const_float_type(id self, SEL _cmd) { return "f"; }
static double const_double_value(id self, SEL _cmd) { return *(const double *)((const char *)self + sizeof(void *)); }
static double const_float_value(id self, SEL _cmd) { return *(const float *)((const char *)self + sizeof(void *)); }
static long long const_double_ll(id self, SEL _cmd) { return (long long)const_double_value(self, _cmd); }
static long long const_float_ll(id self, SEL _cmd) { return (long long)const_float_value(self, _cmd); }
static int const_double_int(id self, SEL _cmd) { return (int)const_double_value(self, _cmd); }
static float const_double_float(id self, SEL _cmd) { return (float)const_double_value(self, _cmd); }
static float const_float_float(id self, SEL _cmd) { return (float)const_float_value(self, _cmd); }
static void const_double_get(id self, SEL _cmd, void *p) { if (p) *(double *)p = const_double_value(self, _cmd); }
static void const_float_get(id self, SEL _cmd, void *p) { if (p) *(float *)p = (float)const_float_value(self, _cmd); }
__attribute__((constructor)) static void fix_constant_numbers(void) {
  Class d = objc_getClass("NSConstantDoubleNumber"), f = objc_getClass("NSConstantFloatNumber");
  if (d) {
    class_replaceMethod(d, @selector(objCType), (IMP)const_double_type, "r*@:");
    class_replaceMethod(d, @selector(doubleValue), (IMP)const_double_value, "d@:");
    class_replaceMethod(d, @selector(floatValue), (IMP)const_double_float, "f@:");
    class_replaceMethod(d, @selector(longLongValue), (IMP)const_double_ll, "q@:");
    class_replaceMethod(d, @selector(integerValue), (IMP)const_double_ll, "q@:");
    class_replaceMethod(d, @selector(intValue), (IMP)const_double_int, "i@:");
    class_replaceMethod(d, @selector(getValue:), (IMP)const_double_get, "v@:^v"); }
  if (f) {
    class_replaceMethod(f, @selector(objCType), (IMP)const_float_type, "r*@:");
    class_replaceMethod(f, @selector(doubleValue), (IMP)const_float_value, "d@:");
    class_replaceMethod(f, @selector(floatValue), (IMP)const_float_float, "f@:");
    class_replaceMethod(f, @selector(longLongValue), (IMP)const_float_ll, "q@:");
    class_replaceMethod(f, @selector(integerValue), (IMP)const_float_ll, "q@:");
    class_replaceMethod(f, @selector(getValue:), (IMP)const_float_get, "v@:^v"); } }
