// Key-value observing: observers of properties set through their setter, through KVC and manually notified ones.
#import <Foundation/Foundation.h>
#include <unistd.h>
#include <objc/runtime.h>
@interface Obs : NSObject { @public NSMutableArray *log; }
@end
@implementation Obs
- (id)init { log = [NSMutableArray array]; return self; }
- (void)observeValueForKeyPath:(NSString *)k ofObject:(id)o change:(NSDictionary *)c context:(void *)ctx {
  [log addObject:[NSString stringWithFormat:@"%@ kind=%@ old=%@ new=%@ prior=%@", k, c[NSKeyValueChangeKindKey], c[NSKeyValueChangeOldKey] ?: @"-", c[NSKeyValueChangeNewKey] ?: @"-", c[NSKeyValueChangeNotificationIsPriorKey] ?: @"-"]]; }
@end
@interface Model : NSObject { @public int plain; }
@property (nonatomic) int count;
@property (nonatomic, copy) NSString *name;
@property (nonatomic) double ratio;
@property (nonatomic) BOOL flag;
@end
@implementation Model
- (int)manual { return plain; }
- (void)bump { [self willChangeValueForKey:@"manual"]; plain++; [self didChangeValueForKey:@"manual"]; }
@end
static void dump(Obs *o, const char *what) { printf("%s:\n", what); for (NSString *l in o->log) printf("  %s\n", [l UTF8String]); [o->log removeAllObjects]; }
int main(void) {
  setvbuf(stdout, NULL, _IONBF, 0);
  @autoreleasepool {
    Model *m = [[Model alloc] init]; Obs *o = [[Obs alloc] init];
    [m addObserver:o forKeyPath:@"count" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:NULL];
    [m addObserver:o forKeyPath:@"name" options:NSKeyValueObservingOptionNew context:NULL];
    [m addObserver:o forKeyPath:@"ratio" options:NSKeyValueObservingOptionNew context:NULL];
    [m addObserver:o forKeyPath:@"flag" options:NSKeyValueObservingOptionNew context:NULL];
    printf("class is %s\n", object_getClass(m) == [Model class] ? "Model" : "isa-swizzled");
    m.count = 5; dump(o, "setter int");
    m.count = 5; dump(o, "same value");
    m.name = @"abc"; dump(o, "setter object");
    m.ratio = 2.5; dump(o, "setter double");
    m.flag = YES; dump(o, "setter bool");
    [m setValue:@9 forKey:@"count"]; dump(o, "KVC");
    [m removeObserver:o forKeyPath:@"count"]; m.count = 1; dump(o, "after removing count observer");
    [m addObserver:o forKeyPath:@"manual" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionPrior context:NULL]; [m bump]; dump(o, "manual willChange/didChange with prior");
    [m addObserver:o forKeyPath:@"count" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:NULL]; dump(o, "initial");
    [m removeObserver:o forKeyPath:@"name"]; [m removeObserver:o forKeyPath:@"ratio"]; [m removeObserver:o forKeyPath:@"flag"]; [m removeObserver:o forKeyPath:@"count"]; [m removeObserver:o forKeyPath:@"manual"];
    printf("observationInfo nil %d\n", m.observationInfo == nil);
    printf("done\n");
  }
  _exit(0);
}
