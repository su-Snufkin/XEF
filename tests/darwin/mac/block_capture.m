// Block_copy must retain captured Objective-C objects (libdispatch installs the hooks via _Block_use_RR2).
#import <Foundation/Foundation.h>
#include <Block.h>
@interface T : NSObject @end
@implementation T
- (void)dealloc { printf("dealloc\n"); [super dealloc]; }
@end
int main(void) {
  T *t = [T new];
  __block int n = 5;
  void (^b)(void) = ^{ printf("in block rc=%lu n=%d\n", (unsigned long)[t retainCount], n++); };
  void (^c)(void) = Block_copy(b);
  printf("after copy rc=%lu\n", (unsigned long)[t retainCount]);
  [t release];
  c(); c();
  printf("n=%d\n", n);
  Block_release(c);
  printf("end\n");
  dispatch_queue_t q = dispatch_queue_create("x", NULL);
  NSMutableArray *a = [NSMutableArray new];
  dispatch_async(q, ^{ [a addObject:@1]; });
  [a release];
  dispatch_sync(q, ^{});
  printf("queue done\n");
  return 0;
}
