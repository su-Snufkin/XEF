// NSView without a visible window: lifecycle callbacks and their order, hierarchy edits, coordinate conversion (flipped
// views, bounds origin and scale), autoresizing, hidden state, hit testing, notifications, layout passes, defaults.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
static const char *R(NSRect r) { return [[NSString stringWithFormat:@"{%g,%g,%g,%g}", r.origin.x, r.origin.y, r.size.width, r.size.height] UTF8String]; }
static const char *PT(NSPoint p) { return [[NSString stringWithFormat:@"{%g,%g}", p.x, p.y] UTF8String]; }
static BOOL quiet = YES;

@interface V : NSView { @public NSString *name; BOOL flipped; }
@end
@implementation V
+ (V *)v:(NSString *)n frame:(NSRect)f { V *v = [[V alloc] initWithFrame:f]; v->name = n; return v; }
- (BOOL)isFlipped { return flipped; }
- (const char *)n { return [name UTF8String]; }
// the content view's superview is a private frame view of the window: not reported
- (void)viewWillMoveToSuperview:(NSView *)s { if (!quiet && ![name isEqual:@"content"]) P("  %s willMoveToSuperview %s\n", [self n], s ? [(V *)s n] : "nil"); [super viewWillMoveToSuperview:s]; }
- (void)viewDidMoveToSuperview { if (!quiet && ![name isEqual:@"content"]) P("  %s didMoveToSuperview %s\n", [self n], self.superview ? [(V *)self.superview n] : "nil"); [super viewDidMoveToSuperview]; }
- (void)viewWillMoveToWindow:(NSWindow *)w { if (!quiet) P("  %s willMoveToWindow %d\n", [self n], w != nil); [super viewWillMoveToWindow:w]; }
- (void)viewDidMoveToWindow { if (!quiet) P("  %s didMoveToWindow %d\n", [self n], self.window != nil); [super viewDidMoveToWindow]; }
- (void)didAddSubview:(NSView *)s { if (!quiet) P("  %s didAddSubview %s\n", [self n], [(V *)s n]); [super didAddSubview:s]; }
- (void)willRemoveSubview:(NSView *)s { if (!quiet) P("  %s willRemoveSubview %s\n", [self n], [(V *)s n]); [super willRemoveSubview:s]; }
- (void)viewDidHide { if (!quiet) P("  %s didHide\n", [self n]); [super viewDidHide]; }
- (void)viewDidUnhide { if (!quiet) P("  %s didUnhide\n", [self n]); [super viewDidUnhide]; }
- (void)resizeSubviewsWithOldSize:(NSSize)o { if (!quiet) P("  %s resizeSubviewsWithOldSize %g,%g\n", [self n], o.width, o.height); [super resizeSubviewsWithOldSize:o]; }
- (void)resizeWithOldSuperviewSize:(NSSize)o { if (!quiet) P("  %s resizeWithOldSuperviewSize %g,%g\n", [self n], o.width, o.height); [super resizeWithOldSuperviewSize:o]; }
- (void)layout { if (!quiet) P("  %s layout\n", [self n]); [super layout]; }
@end
static const char *names(NSArray *views) { NSMutableArray *a = [NSMutableArray array]; for (V *v in views) [a addObject:v->name]; return [[a componentsJoinedByString:@","] UTF8String]; }
static NSComparisonResult byName(__kindof NSView *a, __kindof NSView *b, void *ctx) { return [((V *)a)->name compare:((V *)b)->name]; }

static void defaults(void) {
  P("== defaults\n");
  NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(10, 20, 100, 50)];
  P("frame %s bounds %s tag %ld hidden %d alpha %g mask %lu autoresizes %d flipped %d opaque %d\n", R(v.frame), R(v.bounds), (long)v.tag, v.hidden, v.alphaValue, (unsigned long)v.autoresizingMask,
    v.autoresizesSubviews, v.isFlipped, v.isOpaque);
  NSSize ic = v.intrinsicContentSize;
  P("acceptsFirstResponder %d canBecomeKeyView %d mouseDownCanMoveWindow %d wantsLayer %d layer %d needsDisplay %d intrinsic %g,%g noMetric %g\n", v.acceptsFirstResponder, v.canBecomeKeyView, v.mouseDownCanMoveWindow,
    v.wantsLayer, v.layer != nil, v.needsDisplay, ic.width, ic.height, NSViewNoIntrinsicMetric);
  P("identifier %d toolTip %d superview %d window %d subviews %ld postsFrame %d postsBounds %d translates %d rotation %g focusRing %ld\n", v.identifier != nil, v.toolTip != nil, v.superview != nil, v.window != nil,
    (long)v.subviews.count, v.postsFrameChangedNotifications, v.postsBoundsChangedNotifications, v.translatesAutoresizingMaskIntoConstraints, v.frameRotation, (long)v.focusRingType);
  NSView *z = [[NSView alloc] init]; P("init frame %s\n", R(z.frame));
}

static void hierarchy(void) {
  P("== hierarchy\n");
  V *root = [V v:@"root" frame:NSMakeRect(0, 0, 200, 100)], *a = [V v:@"a" frame:NSMakeRect(0, 0, 10, 10)], *b = [V v:@"b" frame:NSMakeRect(0, 0, 10, 10)], *c = [V v:@"c" frame:NSMakeRect(0, 0, 10, 10)];
  quiet = NO;
  P("add a to root\n"); [root addSubview:a];
  P("add b to a\n"); [a addSubview:b];
  P("move b to root\n"); [root addSubview:b];
  P("add b to root again\n"); [root addSubview:b];
  P("remove a\n"); [a removeFromSuperview];
  quiet = YES;
  [root addSubview:a]; [root addSubview:c];
  P("order %s\n", names(root.subviews));
  [root addSubview:a]; P("re-add a: %s\n", names(root.subviews));
  [root addSubview:c positioned:NSWindowBelow relativeTo:nil]; P("c below all: %s\n", names(root.subviews));
  [root addSubview:c positioned:NSWindowAbove relativeTo:b]; P("c above b: %s\n", names(root.subviews));
  [root addSubview:a positioned:NSWindowBelow relativeTo:b]; P("a below b: %s\n", names(root.subviews));
  [root sortSubviewsUsingFunction:byName context:NULL]; P("sorted: %s\n", names(root.subviews));
  V *d = [V v:@"d" frame:NSMakeRect(0, 0, 10, 10)];
  quiet = NO; P("replace b with d\n"); [root replaceSubview:b with:d]; quiet = YES;
  P("after replace: %s b.superview %d\n", names(root.subviews), b.superview != nil);
  root.subviews = @[c, b]; P("setSubviews: %s a.superview %d d.superview %d\n", names(root.subviews), a.superview != nil, d.superview != nil);
  V *deep = [V v:@"deep" frame:NSMakeRect(0, 0, 5, 5)]; [b addSubview:deep];
  P("descendant deep of root %d, root of deep %d, self %d; shared ancestor of deep and c: %s, of deep and a: %d\n", [deep isDescendantOf:root], [root isDescendantOf:deep], [root isDescendantOf:root],
    [(V *)[deep ancestorSharedWithView:c] n], [deep ancestorSharedWithView:a] != nil);
  P("viewWithTag -1 from root is root %d\n", [root viewWithTag:-1] == root);
}

static void geometry(void) {
  P("== geometry\n");
  V *root = [V v:@"root" frame:NSMakeRect(0, 0, 400, 300)], *a = [V v:@"a" frame:NSMakeRect(50, 40, 200, 100)], *b = [V v:@"b" frame:NSMakeRect(10, 20, 60, 30)];
  [root addSubview:a]; [a addSubview:b];
  P("b (5,5) to a %s to root %s; root (100,100) to b %s\n", PT([b convertPoint:NSMakePoint(5, 5) toView:a]), PT([b convertPoint:NSMakePoint(5, 5) toView:root]), PT([b convertPoint:NSMakePoint(100, 100) fromView:root]));
  P("rect b->root %s root->b %s\n", R([b convertRect:NSMakeRect(1, 2, 10, 5) toView:root]), R([b convertRect:NSMakeRect(61, 62, 10, 5) fromView:root]));
  a->flipped = YES;
  P("a flipped: b (5,5) to root %s, b rect to root %s, root (100,100) to a %s\n", PT([b convertPoint:NSMakePoint(5, 5) toView:root]), R([b convertRect:NSMakeRect(1, 2, 10, 5) toView:root]), PT([a convertPoint:NSMakePoint(100, 100) fromView:root]));
  b->flipped = YES;
  P("both flipped: b (5,5) to root %s to a %s\n", PT([b convertPoint:NSMakePoint(5, 5) toView:root]), PT([b convertPoint:NSMakePoint(5, 5) toView:a]));
  a->flipped = NO; b->flipped = NO;
  [a setFrameOrigin:NSMakePoint(60, 50)]; [a setFrameSize:NSMakeSize(220, 110)]; P("frame %s bounds %s\n", R(a.frame), R(a.bounds));
  [a setBoundsOrigin:NSMakePoint(100, 50)]; P("bounds origin 100,50: bounds %s frame %s; b (0,0) to root %s\n", R(a.bounds), R(a.frame), PT([b convertPoint:NSZeroPoint toView:root]));
  [a translateOriginToPoint:NSMakePoint(10, 10)]; P("translate 10,10: bounds %s\n", R(a.bounds));
  [a setBoundsOrigin:NSZeroPoint]; [a setBoundsSize:NSMakeSize(110, 55)];
  P("bounds size halved: bounds %s frame %s; a (10,10) to root %s; root (80,70) to a %s; size %g\n", R(a.bounds), R(a.frame), PT([a convertPoint:NSMakePoint(10, 10) toView:root]), PT([a convertPoint:NSMakePoint(80, 70) fromView:root]),
    [a convertSize:NSMakeSize(10, 10) toView:root].width);
  [a setFrameSize:NSMakeSize(440, 220)]; P("frame doubled: bounds %s\n", R(a.bounds));
  [a setBoundsSize:NSMakeSize(440, 220)]; [a scaleUnitSquareToSize:NSMakeSize(2, 2)]; P("scale 2: bounds %s\n", R(a.bounds));
}

static void autoresizing(void) {
  P("== autoresizing\n");
  NSUInteger masks[] = { 0, NSViewWidthSizable, NSViewMinXMargin, NSViewMaxXMargin, NSViewMinXMargin | NSViewMaxXMargin, NSViewMinXMargin | NSViewWidthSizable, NSViewMinXMargin | NSViewWidthSizable | NSViewMaxXMargin,
                         NSViewHeightSizable, NSViewMinYMargin, NSViewMinYMargin | NSViewMaxYMargin | NSViewHeightSizable, NSViewWidthSizable | NSViewHeightSizable };
  for (int flip = 0; flip < 2; flip++) {
    V *root = [V v:@"root" frame:NSMakeRect(0, 0, 200, 100)]; root->flipped = flip;
    NSMutableArray *kids = [NSMutableArray array];
    for (int i = 0; i < 11; i++) { V *k = [V v:[NSString stringWithFormat:@"k%d", i] frame:NSMakeRect(20, 10, 100, 40)]; k.autoresizingMask = masks[i]; [root addSubview:k]; [kids addObject:k]; }
    [root setFrameSize:NSMakeSize(320, 160)];
    P("grow%s:", flip ? " (flipped)" : ""); for (V *k in kids) P(" %lu%s", (unsigned long)k.autoresizingMask, R(k.frame)); P("\n");
    [root setFrameSize:NSMakeSize(100, 50)];
    P("shrink:"); for (V *k in kids) P(" %lu%s", (unsigned long)k.autoresizingMask, R(k.frame)); P("\n");
  }
  V *root = [V v:@"root" frame:NSMakeRect(0, 0, 200, 100)], *k = [V v:@"k" frame:NSMakeRect(20, 10, 100, 40)], *g = [V v:@"g" frame:NSMakeRect(0, 0, 100, 40)];
  k.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable; g.autoresizingMask = NSViewWidthSizable; [root addSubview:k]; [k addSubview:g];
  quiet = NO; P("callbacks\n"); [root setFrameSize:NSMakeSize(300, 100)]; quiet = YES;
  P("k %s g %s\n", R(k.frame), R(g.frame));
  root.autoresizesSubviews = NO; [root setFrameSize:NSMakeSize(400, 100)]; P("autoresizesSubviews NO: k %s\n", R(k.frame));
  [root setFrameOrigin:NSMakePoint(5, 5)]; P("origin only: k %s\n", R(k.frame));
}

static void hiddenAndHits(void) {
  P("== hidden, hit testing\n");
  V *root = [V v:@"root" frame:NSMakeRect(0, 0, 200, 100)], *a = [V v:@"a" frame:NSMakeRect(10, 10, 100, 50)], *b = [V v:@"b" frame:NSMakeRect(20, 10, 100, 50)], *inner = [V v:@"inner" frame:NSMakeRect(5, 5, 20, 20)];
  [root addSubview:a]; [root addSubview:b]; [a addSubview:inner];
  P("hit (30,30) %s (15,15) %s (16,16) %s (150,90) %s (300,300) %d\n", [(V *)[root hitTest:NSMakePoint(30, 30)] n], [(V *)[root hitTest:NSMakePoint(15, 15)] n], [(V *)[root hitTest:NSMakePoint(16, 16)] n],
    [(V *)[root hitTest:NSMakePoint(150, 90)] n], [root hitTest:NSMakePoint(300, 300)] != nil);
  P("edges: (10,10) %s (110,60) %s (109,59) %s\n", [(V *)[root hitTest:NSMakePoint(10, 10)] n], [(V *)[root hitTest:NSMakePoint(110, 60)] n], [(V *)[root hitTest:NSMakePoint(109, 59)] n]);
  quiet = NO; P("hide a\n"); a.hidden = YES; P("hide a again\n"); a.hidden = YES; quiet = YES;
  P("a hidden %d inner hidden %d inner hiddenOrAncestor %d hit (16,16) %s visibleRect of inner %s\n", a.hidden, inner.hidden, inner.hiddenOrHasHiddenAncestor, [(V *)[root hitTest:NSMakePoint(16, 16)] n], R(inner.visibleRect));
  quiet = NO; P("hide inner, unhide a\n"); inner.hidden = YES; a.hidden = NO; quiet = YES;
  V *off = [V v:@"off" frame:NSMakeRect(0, 0, 10, 10)]; root->flipped = YES;
  P("flipped root hit (30,30) %s\n", [(V *)[root hitTest:NSMakePoint(30, 30)] n]); (void)off;
}

static void notifications(void) {
  P("== notifications and layout\n");
  V *root = [V v:@"root" frame:NSMakeRect(0, 0, 200, 100)], *a = [V v:@"a" frame:NSMakeRect(10, 10, 100, 50)]; [root addSubview:a];
  __block int frames = 0, bounds = 0;
  id o1 = [[NSNotificationCenter defaultCenter] addObserverForName:NSViewFrameDidChangeNotification object:a queue:nil usingBlock:^(NSNotification *n) { frames++; }];
  id o2 = [[NSNotificationCenter defaultCenter] addObserverForName:NSViewBoundsDidChangeNotification object:a queue:nil usingBlock:^(NSNotification *n) { bounds++; }];
  a.frame = NSMakeRect(10, 10, 120, 50); a.frame = NSMakeRect(10, 10, 120, 50); [a setFrameOrigin:NSMakePoint(11, 10)]; [a setFrameSize:NSMakeSize(130, 50)];
  P("frame notifications %d bounds %d\n", frames, bounds);
  a.postsBoundsChangedNotifications = YES; [a setBoundsOrigin:NSMakePoint(5, 5)]; [a setBoundsOrigin:NSMakePoint(5, 5)]; [a setBoundsSize:NSMakeSize(65, 25)];
  P("bounds notifications %d frames %d\n", bounds, frames);
  a.postsFrameChangedNotifications = NO; a.frame = NSMakeRect(0, 0, 10, 10); P("posting off: frames %d\n", frames);
  [[NSNotificationCenter defaultCenter] removeObserver:o1]; [[NSNotificationCenter defaultCenter] removeObserver:o2];
  P("needsLayout root %d a %d\n", root.needsLayout, a.needsLayout);
  quiet = NO; P("layoutSubtreeIfNeeded\n"); [root layoutSubtreeIfNeeded];
  P("again\n"); [root layoutSubtreeIfNeeded];
  P("a needs layout\n"); a.needsLayout = YES; P("root %d a %d\n", root.needsLayout, a.needsLayout); [root layoutSubtreeIfNeeded]; quiet = YES;
  P("after: root %d a %d\n", root.needsLayout, a.needsLayout);
  a.needsDisplay = NO; [a setNeedsDisplayInRect:NSMakeRect(0, 0, 5, 5)]; P("needsDisplay after rect %d\n", a.needsDisplay);
}

static void window(void) {
  P("== window\n");
  NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 300, 200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
  V *content = [V v:@"content" frame:NSMakeRect(0, 0, 10, 10)], *a = [V v:@"a" frame:NSMakeRect(10, 20, 100, 50)], *b = [V v:@"b" frame:NSMakeRect(1, 2, 3, 4)]; [a addSubview:b];
  quiet = NO; P("set content view\n"); w.contentView = content;
  P("add a (with b) to content\n"); [content addSubview:a];
  P("remove a\n"); [a removeFromSuperview]; quiet = YES;
  [content addSubview:a];
  P("content frame %s window of b %d nextResponder of a is content %d, of content is window %d\n", R(content.frame), b.window == w, a.nextResponder == content, content.nextResponder == w);
  P("a (5,5) to window %s from window (50,50) %s rect to nil %s\n", PT([a convertPoint:NSMakePoint(5, 5) toView:nil]), PT([a convertPoint:NSMakePoint(50, 50) fromView:nil]), R([a convertRect:NSMakeRect(0, 0, 10, 10) toView:nil]));
  [w setContentSize:NSMakeSize(400, 250)]; P("content after setContentSize %s\n", R(content.frame));
  P("firstResponder is window %d makeFirstResponder(a) %d now a %d\n", w.firstResponder == w, [w makeFirstResponder:a], w.firstResponder == a);
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    defaults(); hierarchy(); geometry(); autoresizing(); hiddenAndHits(); notifications(); window();
    P("done\n");
  }
  return 0;
}
