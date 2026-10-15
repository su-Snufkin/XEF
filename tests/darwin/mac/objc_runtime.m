#import <objc/NSObject.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdio.h>
@protocol Greeter - (const char *)greet; @end
@interface Counter : NSObject <Greeter> { int n; } - (void)inc; - (int)n; + (instancetype)make; @end
@implementation Counter
+ (instancetype)make { return [[self alloc] init]; }
- (void)inc { n++; }
- (int)n { return n; }
- (const char *)greet { return "hello from objc"; }
+ (void)load { printf("+load Counter\n"); }
@end
@interface Counter (Extra) - (int)doubled; @end
@implementation Counter (Extra) - (int)doubled { return n * 2; } @end
@interface Sub : Counter @end
@implementation Sub - (void)inc { [super inc]; [super inc]; } @end
int main(void) {
  Counter *c = [Counter make]; [c inc]; [c inc];
  printf("%d %d %s\n", [c n], [c doubled], [c greet]);
  Sub *s = [Sub make]; [s inc]; printf("sub %d %s %s\n", [s n], class_getName([s class]), class_getName(class_getSuperclass([s class])));
  printf("%d %d\n", [s isKindOfClass:[Counter class]], [c respondsToSelector:@selector(doubled)]);
  printf("%d\n", class_conformsToProtocol([Counter class], @protocol(Greeter)));
  int (^blk)(int) = ^(int x) { return x + [c n]; }; printf("block %d\n", blk(5));
  Class k = objc_allocateClassPair([NSObject class], "Dyn", 0); class_addMethod(k, @selector(foo), imp_implementationWithBlock(^int(id self) { return 99; }), "i@:"); objc_registerClassPair(k);
  id d = [[k alloc] init]; printf("dyn %d\n", ((int(*)(id, SEL))objc_msgSend)(d, @selector(foo)));
  return 0; }
