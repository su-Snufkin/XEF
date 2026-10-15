#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#define printf(...) (printf(__VA_ARGS__), fflush(stdout))
@interface Counter : NSObject { int n; } - (void)bump; - (int)n; @end
@implementation Counter
- (void)bump { @synchronized(self) { n++; } }
- (int)n { return n; }
@end
@interface Obs : NSObject @end
@implementation Obs
- (void)note:(NSNotification *)note { printf("notified %s %s\n", [[note name] UTF8String], [[[note userInfo] objectForKey:@"k"] UTF8String]); }
@end
int main(void) {
  @autoreleasepool {
    Counter *c = [[Counter alloc] init];
    dispatch_group_t g = dispatch_group_create();
    dispatch_queue_t q = dispatch_queue_create("test.q", DISPATCH_QUEUE_CONCURRENT);
    for (int i = 0; i < 20; i++) dispatch_group_async(g, q, ^{ for (int j = 0; j < 100; j++) [c bump]; });
    dispatch_group_wait(g, DISPATCH_TIME_FOREVER);
    printf("count=%d\n", [c n]);
    dispatch_queue_t serial = dispatch_queue_create("test.serial", DISPATCH_QUEUE_SERIAL);
    __block NSMutableString *order = [NSMutableString string];
    for (int i = 0; i < 5; i++) dispatch_async(serial, ^{ [order appendFormat:@"%d", i]; });
    dispatch_sync(serial, ^{ [order appendString:@"|"]; });
    printf("order=%s\n", [order UTF8String]);
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(0, 0), ^{ dispatch_semaphore_signal(sem); });
    printf("sem=%ld\n", dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)));
    static dispatch_once_t once; __block int k = 0; for (int i = 0; i < 3; i++) dispatch_once(&once, ^{ k++; }); printf("once=%d\n", k);
    __block int sum = 0; dispatch_apply(10, dispatch_get_global_queue(0, 0), ^(size_t i) { __sync_fetch_and_add(&sum, (int)i); }); printf("apply=%d\n", sum);
    NSOperationQueue *oq = [[NSOperationQueue alloc] init]; __block int ops = 0; NSLock *lock = [[NSLock alloc] init];
    for (int i = 0; i < 10; i++) [oq addOperationWithBlock:^{ [lock lock]; ops++; [lock unlock]; }];
    [oq waitUntilAllOperationsAreFinished]; printf("ops=%d\n", ops);
    Obs *o = [[Obs alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:o selector:@selector(note:) name:@"Hello" object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"Hello" object:nil userInfo:@{@"k": @"v"}];
    NSThread *t = [[NSThread alloc] initWithBlock:^{ printf("thread main=%d\n", [NSThread isMainThread]); }];
    [t start]; while (![t isFinished]) [NSThread sleepForTimeInterval:0.01];
    printf("main=%d\n", [NSThread isMainThread]);
    NSCondition *cond = [[NSCondition alloc] init]; __block BOOL ready = NO;
    [NSThread detachNewThreadWithBlock:^{ [cond lock]; ready = YES; [cond signal]; [cond unlock]; }];
    [cond lock]; while (!ready) [cond wait]; [cond unlock]; printf("cond ok\n");
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    __block int fired = 0;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.02 repeats:YES block:^(NSTimer *tt) { fired++; }];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    [timer invalidate]; printf("timer fired>=3: %d\n", fired >= 3);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ printf("after main\n"); });
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
  }
  return 0; }
