// Auto Layout without a window: anchors, NSLayoutConstraint, priorities, inequalities, intrinsic content size with
// hugging and compression resistance, layout guides, the visual format language, fitting size. The frames real
// AppKit computes are the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)
static const char *R(NSRect r) { return [[NSString stringWithFormat:@"{%g,%g,%g,%g}", r.origin.x, r.origin.y, r.size.width, r.size.height] UTF8String]; }

@interface Box : NSView { @public NSSize intrinsic; BOOL flipped; }
@end
@implementation Box
- (NSSize)intrinsicContentSize { return intrinsic.width || intrinsic.height ? intrinsic : NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric); }
- (BOOL)isFlipped { return flipped; }
@end
static Box *box(NSView *parent) { Box *b = [[Box alloc] initWithFrame:NSZeroRect]; b.translatesAutoresizingMaskIntoConstraints = NO; if (parent) [parent addSubview:b]; return b; }
static Box *sized(NSView *parent, CGFloat w, CGFloat h) { Box *b = box(parent); b->intrinsic = NSMakeSize(w, h); return b; }
static NSView *root(CGFloat w, CGFloat h) { return [[Box alloc] initWithFrame:NSMakeRect(0, 0, w, h)]; }
#define ON(...) [NSLayoutConstraint activateConstraints:@[__VA_ARGS__]]

static void anchors(void) {
  P("== anchors\n");
  NSView *r = root(400, 300); Box *a = box(r), *b = box(r), *c = box(r);
  ON([a.leadingAnchor constraintEqualToAnchor:r.leadingAnchor constant:20], [a.topAnchor constraintEqualToAnchor:r.topAnchor constant:10],
     [a.widthAnchor constraintEqualToConstant:100], [a.heightAnchor constraintEqualToConstant:40]);
  ON([b.leadingAnchor constraintEqualToAnchor:a.trailingAnchor constant:8], [b.trailingAnchor constraintEqualToAnchor:r.trailingAnchor constant:-20],
     [b.topAnchor constraintEqualToAnchor:a.topAnchor], [b.bottomAnchor constraintEqualToAnchor:a.bottomAnchor]);
  ON([c.centerXAnchor constraintEqualToAnchor:r.centerXAnchor], [c.centerYAnchor constraintEqualToAnchor:r.centerYAnchor],
     [c.widthAnchor constraintEqualToAnchor:r.widthAnchor multiplier:0.5], [c.heightAnchor constraintEqualToAnchor:c.widthAnchor multiplier:0.25 constant:10]);
  [r layoutSubtreeIfNeeded];
  P("a %s b %s c %s\n", R(a.frame), R(b.frame), R(c.frame));
  [r setFrameSize:NSMakeSize(600, 200)]; [r layoutSubtreeIfNeeded];
  P("resized: a %s b %s c %s\n", R(a.frame), R(b.frame), R(c.frame));
  NSLayoutConstraint *k = [a.widthAnchor constraintEqualToConstant:50];
  P("constraint: first %d attr %ld relation %ld second %d attr2 %ld mult %g const %g priority %g active %d\n", k.firstItem == a, (long)k.firstAttribute, (long)k.relation, k.secondItem != nil, (long)k.secondAttribute,
    k.multiplier, k.constant, k.priority, k.active);
  NSLayoutConstraint *e = [b.leadingAnchor constraintEqualToAnchor:a.trailingAnchor constant:8];
  P("edge constraint: attr %ld attr2 %ld items %d %d; a constraints %ld r constraints %ld\n", (long)e.firstAttribute, (long)e.secondAttribute, e.firstItem == b, e.secondItem == a, (long)a.constraints.count, (long)r.constraints.count);
}

static void priorities(void) {
  P("== priorities and inequalities\n");
  NSView *r = root(300, 100); Box *a = box(r);
  NSLayoutConstraint *wide = [a.widthAnchor constraintEqualToConstant:500]; wide.priority = 500;
  ON([a.leadingAnchor constraintEqualToAnchor:r.leadingAnchor], [a.topAnchor constraintEqualToAnchor:r.topAnchor], [a.heightAnchor constraintEqualToConstant:20],
     [a.trailingAnchor constraintLessThanOrEqualToAnchor:r.trailingAnchor constant:-10], wide);
  [r layoutSubtreeIfNeeded]; P("capped by the inequality: %s\n", R(a.frame));
  wide.constant = 120; [r layoutSubtreeIfNeeded]; P("constant 120: %s\n", R(a.frame));
  NSLayoutConstraint *min = [a.widthAnchor constraintGreaterThanOrEqualToConstant:200]; min.active = YES;
  [r layoutSubtreeIfNeeded]; P("with minimum 200: %s\n", R(a.frame));
  Box *l = box(r), *m = box(r), *n = box(r);
  ON([l.leadingAnchor constraintEqualToAnchor:r.leadingAnchor constant:10], [m.leadingAnchor constraintEqualToAnchor:l.trailingAnchor constant:10], [n.leadingAnchor constraintEqualToAnchor:m.trailingAnchor constant:10],
     [n.trailingAnchor constraintEqualToAnchor:r.trailingAnchor constant:-10], [m.widthAnchor constraintEqualToAnchor:l.widthAnchor], [n.widthAnchor constraintEqualToAnchor:l.widthAnchor multiplier:2],
     [l.topAnchor constraintEqualToAnchor:r.topAnchor constant:30], [m.topAnchor constraintEqualToAnchor:l.topAnchor], [n.topAnchor constraintEqualToAnchor:l.topAnchor],
     [l.heightAnchor constraintEqualToConstant:20], [m.heightAnchor constraintEqualToAnchor:l.heightAnchor], [n.bottomAnchor constraintEqualToAnchor:r.bottomAnchor constant:-10]);
  [r layoutSubtreeIfNeeded]; P("1:1:2 row: %s %s %s\n", R(l.frame), R(m.frame), R(n.frame));
}

static void intrinsic(void) {
  P("== intrinsic content size\n");
  NSView *r = root(300, 100); Box *a = sized(r, 80, 30), *b = sized(r, 120, 20);
  ON([a.leadingAnchor constraintEqualToAnchor:r.leadingAnchor], [a.topAnchor constraintEqualToAnchor:r.topAnchor], [b.leadingAnchor constraintEqualToAnchor:a.trailingAnchor constant:10],
     [b.topAnchor constraintEqualToAnchor:r.topAnchor]);
  [r layoutSubtreeIfNeeded]; P("natural: a %s b %s\n", R(a.frame), R(b.frame));
  NSLayoutConstraint *end = [b.trailingAnchor constraintEqualToAnchor:r.trailingAnchor]; end.active = YES;
  [a setContentHuggingPriority:200 forOrientation:NSLayoutConstraintOrientationHorizontal];
  [r layoutSubtreeIfNeeded]; P("a hugs less: a %s b %s\n", R(a.frame), R(b.frame));
  [r setFrameSize:NSMakeSize(150, 100)]; [r layoutSubtreeIfNeeded]; P("squeezed, equal resistance: a %s b %s\n", R(a.frame), R(b.frame));
  [b setContentCompressionResistancePriority:400 forOrientation:NSLayoutConstraintOrientationHorizontal];
  [r layoutSubtreeIfNeeded]; P("b resists less: a %s b %s\n", R(a.frame), R(b.frame));
  a->intrinsic = NSMakeSize(100, 30); [a invalidateIntrinsicContentSize]; [r layoutSubtreeIfNeeded]; P("a grew: a %s b %s\n", R(a.frame), R(b.frame));
  P("fitting size of a %g,%g\n", a.fittingSize.width, a.fittingSize.height);
}

static void nested(void) {
  P("== nesting, flipped, guides, autoresizing siblings\n");
  NSView *r = root(400, 300); Box *panel = box(r); panel->flipped = YES; Box *inner = sized(panel, 60, 20), *below = sized(panel, 90, 25);
  ON([panel.leadingAnchor constraintEqualToAnchor:r.leadingAnchor constant:30], [panel.topAnchor constraintEqualToAnchor:r.topAnchor constant:40],
     [inner.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:5], [inner.topAnchor constraintEqualToAnchor:panel.topAnchor constant:5],
     [below.leadingAnchor constraintEqualToAnchor:inner.leadingAnchor], [below.topAnchor constraintEqualToAnchor:inner.bottomAnchor constant:4],
     [panel.trailingAnchor constraintEqualToAnchor:below.trailingAnchor constant:5], [panel.bottomAnchor constraintEqualToAnchor:below.bottomAnchor constant:5]);
  [r layoutSubtreeIfNeeded];
  P("panel sized by content %s inner %s below %s\n", R(panel.frame), R(inner.frame), R(below.frame));
  P("fitting size of panel %g,%g\n", panel.fittingSize.width, panel.fittingSize.height);
  NSLayoutGuide *g = [[NSLayoutGuide alloc] init]; [r addLayoutGuide:g]; Box *right = box(r);
  ON([g.leadingAnchor constraintEqualToAnchor:panel.trailingAnchor], [g.trailingAnchor constraintEqualToAnchor:r.trailingAnchor], [g.topAnchor constraintEqualToAnchor:r.topAnchor], [g.bottomAnchor constraintEqualToAnchor:r.bottomAnchor],
     [right.centerXAnchor constraintEqualToAnchor:g.centerXAnchor], [right.centerYAnchor constraintEqualToAnchor:g.centerYAnchor], [right.widthAnchor constraintEqualToConstant:50], [right.heightAnchor constraintEqualToConstant:50]);
  [r layoutSubtreeIfNeeded]; P("guide %s owning %d centered %s guides %ld\n", R(g.frame), g.owningView == r, R(right.frame), (long)r.layoutGuides.count);
  NSView *legacy = [[NSView alloc] initWithFrame:NSMakeRect(10, 200, 80, 60)]; [r addSubview:legacy]; Box *next = box(r);
  ON([next.leadingAnchor constraintEqualToAnchor:legacy.trailingAnchor constant:5], [next.topAnchor constraintEqualToAnchor:legacy.topAnchor], [next.widthAnchor constraintEqualToAnchor:legacy.widthAnchor],
     [next.heightAnchor constraintEqualToAnchor:legacy.heightAnchor multiplier:0.5]);
  [r layoutSubtreeIfNeeded]; P("next to an autoresizing view %s (it stays %s)\n", R(next.frame), R(legacy.frame));
}

static void visual(void) {
  P("== visual format\n");
  NSView *r = root(400, 200); Box *a = box(r), *b = box(r), *c = sized(r, 70, 22);
  NSDictionary *v = NSDictionaryOfVariableBindings(a, b, c); NSDictionary *m = @{ @"pad": @12, @"h": @40 };
  NSArray *h = [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-pad-[a(100)]-[b(>=50)]-pad-|" options:NSLayoutFormatAlignAllTop metrics:m views:v];
  NSArray *vv = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-[a(h)]" options:0 metrics:m views:v];
  NSArray *vb = [NSLayoutConstraint constraintsWithVisualFormat:@"V:[b(==a)]" options:0 metrics:m views:v];
  NSArray *cc = [NSLayoutConstraint constraintsWithVisualFormat:@"H:[c]-(>=8,==30@600)-|" options:0 metrics:m views:v];
  NSArray *cv = [NSLayoutConstraint constraintsWithVisualFormat:@"V:[a]-20-[c]" options:0 metrics:m views:v];
  P("counts %ld %ld %ld %ld %ld\n", (long)h.count, (long)vv.count, (long)vb.count, (long)cc.count, (long)cv.count);
  [NSLayoutConstraint activateConstraints:h]; [NSLayoutConstraint activateConstraints:vv]; [NSLayoutConstraint activateConstraints:vb]; [NSLayoutConstraint activateConstraints:cc]; [NSLayoutConstraint activateConstraints:cv];
  [r layoutSubtreeIfNeeded]; P("a %s b %s c %s\n", R(a.frame), R(b.frame), R(c.frame));
  NSLayoutConstraint *first = h[0];
  P("first: attr %ld relation %ld attr2 %ld constant %g priority %g\n", (long)first.firstAttribute, (long)first.relation, (long)first.secondAttribute, first.constant, first.priority);
  NSLayoutConstraint *old = [NSLayoutConstraint constraintWithItem:c attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:a attribute:NSLayoutAttributeWidth multiplier:1.5 constant:-10];
  [r addConstraint:old]; [r layoutSubtreeIfNeeded]; P("classic API: c %s active %d\n", R(c.frame), old.active);
  [r removeConstraint:old]; [r layoutSubtreeIfNeeded]; P("removed: c %s active %d\n", R(c.frame), old.active);
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    anchors(); priorities(); intrinsic(); nested(); visual();
    P("done\n");
  }
  return 0;
}
