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
