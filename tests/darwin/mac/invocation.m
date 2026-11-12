// NSInvocation and message forwarding: every argument and result class of the arm64 calling convention (integers,
// float / double, HFA structs, small and large structs, stack arguments), invokeWithTarget:, retainArguments,
// forwardInvocation: proxies, NSPredicate and key-value observing (which are built on invocations).
#import <Foundation/Foundation.h>
#include <objc/message.h>
#include <unistd.h>
#define P(...) printf(__VA_ARGS__)

typedef struct { int a, b; } Small;
typedef struct { double x, y; } Pair;
typedef struct { float f[3]; } Fl3;
typedef struct { long a, b, c, d; } Big;
typedef struct { char c; double d; } Mixed;

@interface T : NSObject
@end
@implementation T
- (int)addInt:(int)a to:(int)b { return a + b; }
- (long long)wide:(long long)a { return a * 3; }
- (double)scale:(double)d by:(float)f { return d * f; }
- (float)half:(float)f { return f / 2; }
- (BOOL)flag:(BOOL)b { return !b; }
- (char)ch:(char)c { return c + 1; }
- (NSRect)rect:(NSRect)r grownBy:(double)g { return NSMakeRect(r.origin.x, r.origin.y, r.size.width + g, r.size.height + g); }
- (NSSize)size:(NSSize)s { return NSMakeSize(s.height, s.width); }
- (NSRange)range:(NSRange)r { return NSMakeRange(r.location + 1, r.length * 2); }
- (Small)small:(Small)s { return (Small){ s.a + s.b, s.a - s.b }; }
- (Pair)pair:(Pair)p { return (Pair){ p.y, p.x }; }
- (Fl3)fl3:(Fl3)v { return (Fl3){ { v.f[2], v.f[1], v.f[0] } }; }
- (Big)big:(Big)b with:(long)k { return (Big){ b.a * k, b.b * k, b.c * k, b.d * k }; }
- (Mixed)mixed:(Mixed)m { return (Mixed){ m.c + 1, m.d * 2 }; }
- (id)obj:(id)o { return [NSString stringWithFormat:@"<%@>", o]; }
- (NSString *)many:(int)a b:(int)b c:(int)c d:(int)d e:(int)e f:(int)f g:(int)g h:(int)h i:(int)i j:(int)j k:(double)k {
  return [NSString stringWithFormat:@"%d%d%d%d%d%d%d%d%d %g", a, b, c, d, e, f, g, h, i + j, k]; }
- (double)spill:(double)a :(double)b :(double)c :(double)d :(double)e :(double)f :(double)g :(double)h :(double)i :(double)j { return a + b + c + d + e + f + g + h + i * 10 + j * 100; }
- (SEL)selector:(SEL)s { return s; }
- (void)nothing { }
@end

@interface Forwarder : NSProxy { T *real; @public int calls; }
@end
@implementation Forwarder
- (id)init { real = [[T alloc] init]; return self; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s { return [real methodSignatureForSelector:s]; }
- (void)forwardInvocation:(NSInvocation *)inv { calls++; [inv invokeWithTarget:real]; }
@end
@interface Wrapper : NSObject { T *inner; @public int log; }
@end
@implementation Wrapper
- (id)init { inner = [[T alloc] init]; return self; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s { return [super methodSignatureForSelector:s] ?: [inner methodSignatureForSelector:s]; }
- (void)forwardInvocation:(NSInvocation *)inv { log++; if ([inner respondsToSelector:[inv selector]]) [inv invokeWithTarget:inner]; else [super forwardInvocation:inv]; }
@end

static NSInvocation *make(id target, SEL s) { NSInvocation *i = [NSInvocation invocationWithMethodSignature:[target methodSignatureForSelector:s]]; i.target = target; i.selector = s; return i; }

@interface Obs : NSObject { @public int hits; id last; }
@end
@implementation Obs
- (void)observeValueForKeyPath:(NSString *)k ofObject:(id)o change:(NSDictionary *)c context:(void *)ctx { hits++; last = c[NSKeyValueChangeNewKey]; }
@end
@interface Model : NSObject { @public int count; }
- (void)setCountTo:(int)n;
@end
@implementation Model
- (void)setCountTo:(int)n { count = n; }
@end

int main(void) {
  setvbuf(stdout, NULL, _IONBF, 0);
  @autoreleasepool {
    T *t = [[T alloc] init];
    P("== invoke\n");
    { NSInvocation *i = make(t, @selector(addInt:to:)); int a = 40, b = 2, r; [i setArgument:&a atIndex:2]; [i setArgument:&b atIndex:3]; [i invoke]; [i getReturnValue:&r]; P("int %d\n", r); }
    { NSInvocation *i = make(t, @selector(wide:)); long long a = 1LL << 40, r; [i setArgument:&a atIndex:2]; [i invoke]; [i getReturnValue:&r]; P("long long %lld\n", r); }
    { NSInvocation *i = make(t, @selector(scale:by:)); double d = 2.5; float f = 4; double r; [i setArgument:&d atIndex:2]; [i setArgument:&f atIndex:3]; [i invoke]; [i getReturnValue:&r]; P("double %g\n", r); }
    { NSInvocation *i = make(t, @selector(half:)); float f = 5, r; [i setArgument:&f atIndex:2]; [i invoke]; [i getReturnValue:&r]; P("float %g\n", r); }
    { NSInvocation *i = make(t, @selector(flag:)); BOOL b = YES, r; [i setArgument:&b atIndex:2]; [i invoke]; [i getReturnValue:&r]; P("bool %d\n", r); }
    { NSInvocation *i = make(t, @selector(ch:)); char c = 'a', r; [i setArgument:&c atIndex:2]; [i invoke]; [i getReturnValue:&r]; P("char %c\n", r); }
    { NSInvocation *i = make(t, @selector(rect:grownBy:)); NSRect rc = NSMakeRect(1, 2, 3, 4), r; double g = 10; [i setArgument:&rc atIndex:2]; [i setArgument:&g atIndex:3]; [i invoke]; [i getReturnValue:&r]; P("NSRect %g %g %g %g\n", r.origin.x, r.origin.y, r.size.width, r.size.height); }
    { NSInvocation *i = make(t, @selector(size:)); NSSize s = NSMakeSize(7, 9), r; [i setArgument:&s atIndex:2]; [i invoke]; [i getReturnValue:&r]; P("NSSize %g %g\n", r.width, r.height); }
    { NSInvocation *i = make(t, @selector(range:)); NSRange a = NSMakeRange(5, 6), r; [i setArgument:&a atIndex:2]; [i invoke]; [i getReturnValue:&r]; P("NSRange %lu %lu\n", (unsigned long)r.location, (unsigned long)r.length); }
    { NSInvocation *i = make(t, @selector(small:)); Small s = { 10, 3 }, r; [i setArgument:&s atIndex:2]; [i invoke]; [i getReturnValue:&r]; P("Small %d %d\n", r.a, r.b); }
    { NSInvocation *i = make(t, @selector(pair:)); Pair s = { 1.5, 2.5 }, r; [i setArgument:&s atIndex:2]; [i invoke]; [i getReturnValue:&r]; P("Pair %g %g\n", r.x, r.y); }
    { NSInvocation *i = make(t, @selector(fl3:)); Fl3 s = { { 1, 2, 3 } }, r; [i setArgument:&s atIndex:2]; [i invoke]; [i getReturnValue:&r]; P("Fl3 %g %g %g\n", r.f[0], r.f[1], r.f[2]); }
    { NSInvocation *i = make(t, @selector(big:with:)); Big b = { 1, 2, 3, 4 }, r; long k = 5; [i setArgument:&b atIndex:2]; [i setArgument:&k atIndex:3]; [i invoke]; [i getReturnValue:&r]; P("Big %ld %ld %ld %ld\n", r.a, r.b, r.c, r.d); }
    { NSInvocation *i = make(t, @selector(mixed:)); Mixed m = { 'x', 1.25 }, r; [i setArgument:&m atIndex:2]; [i invoke]; [i getReturnValue:&r]; P("Mixed %c %g\n", r.c, r.d); }
    { NSInvocation *i = make(t, @selector(obj:)); id o = @"hi", r; [i setArgument:&o atIndex:2]; [i invoke]; [i getReturnValue:&r]; P("object %s\n", [r UTF8String]); }
    { NSInvocation *i = make(t, @selector(many:b:c:d:e:f:g:h:i:j:k:)); int v[10] = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }; double k = 0.5; id r;
      for (int n = 0; n < 10; n++) [i setArgument:&v[n] atIndex:2 + n]; [i setArgument:&k atIndex:12]; [i invoke]; [i getReturnValue:&r]; P("stack ints %s\n", [r UTF8String]); }
    { NSInvocation *i = make(t, @selector(spill::::::::::)); double v[10]; double r; for (int n = 0; n < 10; n++) { v[n] = n + 1; [i setArgument:&v[n] atIndex:2 + n]; } [i invoke]; [i getReturnValue:&r]; P("stack doubles %g\n", r); }
    { NSInvocation *i = make(t, @selector(selector:)); SEL s = @selector(foo:bar:), r; [i setArgument:&s atIndex:2]; [i invoke]; [i getReturnValue:&r]; P("SEL %s\n", sel_getName(r)); }
    { NSInvocation *i = make(t, @selector(nothing)); [i invoke]; P("void ok, return length %lu\n", (unsigned long)i.methodSignature.methodReturnLength); }
    P("== API\n");
    { NSInvocation *i = [NSInvocation invocationWithMethodSignature:[T instanceMethodSignatureForSelector:@selector(addInt:to:)]];
      P("args %lu returnType %s length %lu retained %d target nil %d\n", (unsigned long)i.methodSignature.numberOfArguments, i.methodSignature.methodReturnType, (unsigned long)i.methodSignature.methodReturnLength, i.argumentsRetained, i.target == nil);
      i.selector = @selector(addInt:to:); int a = 1, b = 2; [i setArgument:&a atIndex:2]; [i setArgument:&b atIndex:3];
      P("selector %s; invokeWithTarget:\n", sel_getName(i.selector)); [i invokeWithTarget:t]; int r; [i getReturnValue:&r]; P("result %d target %d\n", r, i.target == t);
      int g; [i getArgument:&g atIndex:3]; P("getArgument %d\n", g);
      @try { [i setArgument:&a atIndex:9]; } @catch (NSException *e) { P("out of range: %s\n", [e.name UTF8String]); }
      T *other = [[T alloc] init]; [i invokeWithTarget:other]; P("other target %d\n", i.target == other); }
    { NSInvocation *i = make(t, @selector(obj:)); NSString *s = [NSString stringWithFormat:@"%d", 42]; [i setArgument:&s atIndex:2]; [i retainArguments]; P("retained %d\n", i.argumentsRetained); [i invoke]; id r; [i getReturnValue:&r]; P("%s\n", [r UTF8String]); }
    { NSInvocation *i = [NSInvocation invocationWithMethodSignature:[t methodSignatureForSelector:@selector(wide:)]]; i.selector = @selector(wide:); NSInvocation *j = make(t, @selector(wide:)); long long a = 3, r = -1; [j setArgument:&a atIndex:2]; [i invoke]; P("nil target does nothing\n"); [j invoke]; [j getReturnValue:&r]; P("%lld\n", r); }
    P("== forwarding\n");
    { Forwarder *f = [[Forwarder alloc] init]; int r = ((int (*)(id, SEL, int, int))objc_msgSend)(f, @selector(addInt:to:), 20, 22); P("int through proxy %d calls %d\n", r, f->calls);
      double d = ((double (*)(id, SEL, double, float))objc_msgSend)(f, @selector(scale:by:), 3, 2); P("double %g\n", d);
      NSRect rc = ((NSRect (*)(id, SEL, NSRect, double))objc_msgSend)(f, @selector(rect:grownBy:), NSMakeRect(1, 2, 3, 4), 1); P("NSRect %g %g %g %g\n", rc.origin.x, rc.origin.y, rc.size.width, rc.size.height);
      Small sm = ((Small (*)(id, SEL, Small))objc_msgSend)(f, @selector(small:), (Small){ 9, 4 }); P("Small %d %d\n", sm.a, sm.b);
      Big bg = ((Big (*)(id, SEL, Big, long))objc_msgSend)(f, @selector(big:with:), (Big){ 1, 2, 3, 4 }, 3); P("Big %ld %ld %ld %ld\n", bg.a, bg.b, bg.c, bg.d);
      Mixed mx = ((Mixed (*)(id, SEL, Mixed))objc_msgSend)(f, @selector(mixed:), (Mixed){ 'a', 2.5 }); P("Mixed %c %g\n", mx.c, mx.d);
      NSString *s = ((id (*)(id, SEL, int, int, int, int, int, int, int, int, int, int, double))objc_msgSend)(f, @selector(many:b:c:d:e:f:g:h:i:j:k:), 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 0.25); P("stack %s\n", [s UTF8String]); }
    { Wrapper *w = [[Wrapper alloc] init]; long long r = ((long long (*)(id, SEL, long long))objc_msgSend)(w, @selector(wide:), 7); P("wrapper %lld log %d\n", r, w->log);
      @try { [w performSelector:@selector(unknownSelector)]; } @catch (NSException *e) { P("unrecognized: %s\n", [e.name UTF8String]); } P("log after unknown %d\n", w->log); }
    P("== performSelector / predicates / KVO\n");
    P("performSelector %s\n", [[t performSelector:@selector(obj:) withObject:@"p"] UTF8String]);
    { NSArray *a = @[@{@"n": @1}, @{@"n": @5}, @{@"n": @9}]; NSArray *r = [a filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"n > 3"]]; P("predicate %lu\n", (unsigned long)r.count); }
    { NSUndoManager *u = [[NSUndoManager alloc] init]; [u setGroupsByEvent:NO]; Model *m = [[Model alloc] init]; [u beginUndoGrouping]; [[u prepareWithInvocationTarget:m] setCountTo:1]; [u endUndoGrouping]; P("undo can %d\n", [u canUndo]); [u undo]; P("after undo count %d\n", m->count); }
    P("done\n");
  }
  _exit(0);
}
