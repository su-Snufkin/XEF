// Pieces of Apple's Foundation that clang's codegen references directly: the shared empty NSArray / NSDictionary
// used for `@[]` and `@{}` literals.
#import <Foundation/Foundation.h>

@interface __NSArray0 : NSArray @end
@implementation __NSArray0
- (NSUInteger)count { return 0; }
- (id)objectAtIndex:(NSUInteger)i { [NSException raise:NSRangeException format:@"index %lu beyond bounds for empty array", (unsigned long)i]; return nil; }
- (id)retain { return self; }
- (oneway void)release {}
- (NSUInteger)retainCount { return ~(NSUInteger)0; }
@end

@interface __NSDictionary0 : NSDictionary @end
@implementation __NSDictionary0
- (NSUInteger)count { return 0; }
- (id)objectForKey:(id)k { return nil; }
- (NSEnumerator *)keyEnumerator { return [@[] objectEnumerator]; }
- (id)retain { return self; }
- (oneway void)release {}
- (NSUInteger)retainCount { return ~(NSUInteger)0; }
@end

__attribute__((visibility("default"))) struct { Class isa; char pad[120]; } __NSArray0__struct, __NSDictionary0__struct;
__attribute__((constructor)) static void xef_empty_collections(void) {
    __NSArray0__struct.isa = [__NSArray0 class];
    __NSDictionary0__struct.isa = [__NSDictionary0 class];
}

// ---- compile-time constant literals (clang -fobjc-constant-literals) ----------------------------------------
// clang emits `@1`, `@2.5`, `@[...]`, `@{...}` as statically allocated objects of these classes; the layouts
// below are the ones clang uses ({isa, encoding, int64} / {isa, double|float, encoding} / {isa, count, objects*} / {isa, 1, count, keys*, objects*}).
#define XEF_NUM_GETTER(name, type, expr) - (type)name { return (type)(expr); }
#define XEF_NUM_METHODS(valueExpr, intLike) \
    XEF_NUM_GETTER(charValue, char, valueExpr) XEF_NUM_GETTER(unsignedCharValue, unsigned char, valueExpr) \
    XEF_NUM_GETTER(shortValue, short, valueExpr) XEF_NUM_GETTER(unsignedShortValue, unsigned short, valueExpr) \
    XEF_NUM_GETTER(intValue, int, valueExpr) XEF_NUM_GETTER(unsignedIntValue, unsigned int, valueExpr) \
    XEF_NUM_GETTER(longValue, long, valueExpr) XEF_NUM_GETTER(unsignedLongValue, unsigned long, valueExpr) \
    XEF_NUM_GETTER(longLongValue, long long, valueExpr) XEF_NUM_GETTER(unsignedLongLongValue, unsigned long long, valueExpr) \
    XEF_NUM_GETTER(integerValue, NSInteger, valueExpr) XEF_NUM_GETTER(unsignedIntegerValue, NSUInteger, valueExpr) \
    XEF_NUM_GETTER(floatValue, float, valueExpr) XEF_NUM_GETTER(doubleValue, double, valueExpr) \
    - (BOOL)boolValue { return (valueExpr) != 0; } \
    - (const char *)objCType { return _encoding; } \
    - (id)retain { return self; } - (oneway void)release {} - (NSUInteger)retainCount { return ~(NSUInteger)0; } \
    - (id)copyWithZone:(NSZone *)z { return self; } - (id)copy { return self; }

@interface NSConstantIntegerNumber : NSNumber { const char *_encoding; long long _value; } @end
@implementation NSConstantIntegerNumber
XEF_NUM_METHODS(_value, 1)
- (void)getValue:(void *)p {
    switch (_encoding[0]) {
        case 'c': case 'C': *(char *)p = (char)_value; break;
        case 's': case 'S': *(short *)p = (short)_value; break;
        case 'i': case 'I': *(int *)p = (int)_value; break;
        default: *(long long *)p = _value; break;
    }
}
- (NSString *)stringValue { return [[NSNumber numberWithLongLong:_value] stringValue]; }
- (NSString *)description { return [self stringValue]; }
- (NSString *)descriptionWithLocale:(id)l { return [self stringValue]; }
- (NSUInteger)hash { return (NSUInteger)[[NSNumber numberWithLongLong:_value] hash]; }
- (BOOL)isEqual:(id)o { return [[NSNumber numberWithLongLong:_value] isEqual:o]; }
- (BOOL)isEqualToNumber:(NSNumber *)o { return [[NSNumber numberWithLongLong:_value] isEqualToNumber:o]; }
- (NSComparisonResult)compare:(NSNumber *)o { return [[NSNumber numberWithLongLong:_value] compare:o]; }
@end

@interface NSConstantDoubleNumber : NSNumber { double _value; const char *_encoding; } @end
@implementation NSConstantDoubleNumber
XEF_NUM_METHODS(_value, 0)
- (void)getValue:(void *)p { *(double *)p = _value; }
- (NSString *)stringValue { return [[NSNumber numberWithDouble:_value] stringValue]; }
- (NSString *)description { return [self stringValue]; }
- (NSString *)descriptionWithLocale:(id)l { return [self stringValue]; }
- (NSUInteger)hash { return (NSUInteger)[[NSNumber numberWithDouble:_value] hash]; }
- (BOOL)isEqual:(id)o { return [[NSNumber numberWithDouble:_value] isEqual:o]; }
- (BOOL)isEqualToNumber:(NSNumber *)o { return [[NSNumber numberWithDouble:_value] isEqualToNumber:o]; }
- (NSComparisonResult)compare:(NSNumber *)o { return [[NSNumber numberWithDouble:_value] compare:o]; }
@end

@interface NSConstantFloatNumber : NSNumber { float _value; const char *_encoding; } @end
@implementation NSConstantFloatNumber
XEF_NUM_METHODS(_value, 0)
- (void)getValue:(void *)p { *(float *)p = _value; }
- (NSString *)stringValue { return [[NSNumber numberWithFloat:_value] stringValue]; }
- (NSString *)description { return [self stringValue]; }
- (NSString *)descriptionWithLocale:(id)l { return [self stringValue]; }
- (NSUInteger)hash { return (NSUInteger)[[NSNumber numberWithFloat:_value] hash]; }
- (BOOL)isEqual:(id)o { return [[NSNumber numberWithFloat:_value] isEqual:o]; }
- (BOOL)isEqualToNumber:(NSNumber *)o { return [[NSNumber numberWithFloat:_value] isEqualToNumber:o]; }
- (NSComparisonResult)compare:(NSNumber *)o { return [[NSNumber numberWithFloat:_value] compare:o]; }
@end

@interface NSConstantArray : NSArray { NSUInteger _count; id *_objects; } @end
@implementation NSConstantArray
- (NSUInteger)count { return _count; }
- (id)objectAtIndex:(NSUInteger)i {
    if (i >= _count) [NSException raise:NSRangeException format:@"index %lu beyond bounds [0 .. %lu]", (unsigned long)i, (unsigned long)_count - 1];
    return _objects[i];
}
- (void)getObjects:(id *)buf range:(NSRange)r { for (NSUInteger i = 0; i < r.length; i++) buf[i] = _objects[r.location + i]; }
- (id)retain { return self; } - (oneway void)release {} - (NSUInteger)retainCount { return ~(NSUInteger)0; }
- (id)copyWithZone:(NSZone *)z { return self; } - (id)copy { return self; }
@end

@interface NSConstantDictionary : NSDictionary { NSUInteger _version; NSUInteger _count; id *_keys; id *_objects; } @end
@implementation NSConstantDictionary
- (NSUInteger)count { return _count; }
- (id)objectForKey:(id)k { for (NSUInteger i = 0; i < _count; i++) if ([_keys[i] isEqual:k]) return _objects[i]; return nil; }
- (NSEnumerator *)keyEnumerator { return [[NSArray arrayWithObjects:_keys count:_count] objectEnumerator]; }
- (id)retain { return self; } - (oneway void)release {} - (NSUInteger)retainCount { return ~(NSUInteger)0; }
- (id)copyWithZone:(NSZone *)z { return self; } - (id)copy { return self; }
@end
