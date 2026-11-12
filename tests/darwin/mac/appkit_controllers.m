// View controllers (loading, children, split and tab controllers), synthesized events and the responder chain, gesture
// recognizers driven by events sent to them directly. Real AppKit's output is the reference.
#import <Cocoa/Cocoa.h>
#define P(...) printf(__VA_ARGS__)

@interface VC : NSViewController { @public NSString *name; }
@end
@implementation VC
+ (VC *)named:(NSString *)n { VC *v = [[VC alloc] initWithNibName:nil bundle:nil]; v->name = n; v.title = n; return v; }
- (void)loadView { P("  %s loadView\n", [name UTF8String]); self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 80)]; }
- (void)viewDidLoad { [super viewDidLoad]; P("  %s viewDidLoad\n", [name UTF8String]); }
- (void)viewWillAppear { [super viewWillAppear]; P("  %s viewWillAppear\n", [name UTF8String]); }
- (void)viewDidAppear { [super viewDidAppear]; P("  %s viewDidAppear\n", [name UTF8String]); }
- (void)viewWillDisappear { [super viewWillDisappear]; P("  %s viewWillDisappear\n", [name UTF8String]); }
- (void)viewDidDisappear { [super viewDidDisappear]; P("  %s viewDidDisappear\n", [name UTF8String]); }
@end
static const char *kids(NSViewController *v) { NSMutableArray *a = [NSMutableArray array]; for (VC *c in v.childViewControllers) [a addObject:[c isKindOfClass:[VC class]] ? c->name : NSStringFromClass([c class])]; return [[a componentsJoinedByString:@","] UTF8String]; }

static void controllers(void) {
  P("== NSViewController\n");
  VC *a = [VC named:@"a"];
  P("loaded %d viewIfLoaded %d preferredContentSize %g,%g identifier %d parent %d children %ld presented %ld\n", a.viewLoaded, a.viewIfLoaded != nil, a.preferredContentSize.width, a.preferredContentSize.height,
    a.identifier != nil, a.parentViewController != nil, (long)a.childViewControllers.count, (long)a.presentedViewControllers.count);
  P("loadViewIfNeeded\n"); [a loadViewIfNeeded]; P("again\n"); [a loadViewIfNeeded];
  P("loaded %d view.nextResponder is vc %d vc.nextResponder %d\n", a.viewLoaded, a.view.nextResponder == a, a.nextResponder != nil);
  NSView *host = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)]; [host addSubview:a.view];
  P("in a superview: view.nextResponder is vc %d vc.nextResponder is superview %d\n", a.view.nextResponder == a, a.nextResponder == host);
  VC *b = [VC named:@"b"], *c = [VC named:@"c"], *d = [VC named:@"d"];
  [a addChildViewController:b]; [a addChildViewController:c]; [a insertChildViewController:d atIndex:1];
  P("children %s parent of d is a %d b loaded %d\n", kids(a), d.parentViewController == a, b.viewLoaded);
  [a removeChildViewControllerAtIndex:0]; [c removeFromParentViewController]; P("after removals %s parent of c %d\n", kids(a), c.parentViewController != nil);
  a.preferredContentSize = NSMakeSize(200, 100); a.identifier = @"main"; P("preferred %g,%g identifier %s title %s\n", a.preferredContentSize.width, a.preferredContentSize.height, [a.identifier UTF8String], [a.title UTF8String]);
  NSViewController *plain = [[NSViewController alloc] init]; P("plain controller view %s frame %g,%g\n", [[plain.view className] UTF8String], plain.view.frame.size.width, plain.view.frame.size.height);

  P("== NSSplitViewController\n");
  NSSplitViewController *s = [[NSSplitViewController alloc] init];
  P("splitView %s vertical %d items %ld loaded %d\n", [[s.splitView className] UTF8String], s.splitView.vertical, (long)s.splitViewItems.count, s.viewLoaded);
  VC *left = [VC named:@"left"], *right = [VC named:@"right"];
  NSSplitViewItem *li = [NSSplitViewItem sidebarWithViewController:left], *ri = [NSSplitViewItem splitViewItemWithViewController:right];
  P("item defaults: canCollapse %d collapsed %d holding %g min %g max %g behavior %ld springLoaded %d controller %d\n", ri.canCollapse, ri.collapsed, ri.holdingPriority, ri.minimumThickness, ri.maximumThickness, (long)ri.behavior,
    ri.springLoaded, ri.viewController == right);
  P("sidebar: canCollapse %d holding %g behavior %ld\n", li.canCollapse, li.holdingPriority, (long)li.behavior);
  P("add items\n"); [s addSplitViewItem:li]; [s addSplitViewItem:ri];
  P("items %ld children %s item for right %d left loaded %d\n", (long)s.splitViewItems.count, kids(s), [s splitViewItemForViewController:right] == ri, left.viewLoaded);
  P("load the view\n"); NSView *sv = s.view;
  P("view is splitView %d arranged %ld delegate is controller %d\n", sv == s.splitView, (long)s.splitView.arrangedSubviews.count, (id)s.splitView.delegate == s);
  [s removeSplitViewItem:li]; P("removed: items %ld children %s arranged %ld\n", (long)s.splitViewItems.count, kids(s), (long)s.splitView.arrangedSubviews.count);

  P("== NSTabViewController\n");
  NSTabViewController *t = [[NSTabViewController alloc] init];
  P("defaults style %ld selected %ld items %ld propagates title %d transition %lu\n", (long)t.tabStyle, (long)t.selectedTabViewItemIndex, (long)t.tabViewItems.count, t.canPropagateSelectedChildViewControllerTitle, (unsigned long)t.transitionOptions);
  VC *one = [VC named:@"one"], *two = [VC named:@"two"];
  P("add tabs\n"); [t addTabViewItem:[NSTabViewItem tabViewItemWithViewController:one]]; [t addTabViewItem:[NSTabViewItem tabViewItemWithViewController:two]];
  P("items %ld children %s selected %ld label %s title %s\n", (long)t.tabViewItems.count, kids(t), (long)t.selectedTabViewItemIndex, [t.tabViewItems[1].label UTF8String], [t.title UTF8String]);
  P("load the view\n"); (void)t.view;
  P("tabView %s items in tab view %ld one loaded %d two loaded %d\n", [[t.tabView className] UTF8String], (long)t.tabView.numberOfTabViewItems, one.viewLoaded, two.viewLoaded);
  P("select 1\n"); t.selectedTabViewItemIndex = 1; P("selected %ld title %s two loaded %d item for two %d\n", (long)t.selectedTabViewItemIndex, [t.title UTF8String], two.viewLoaded, [t tabViewItemForViewController:two] == t.tabViewItems[1]);
}

@interface R : NSResponder { @public NSString *name; BOOL handles; }
@end
@implementation R
- (void)mouseDown:(NSEvent *)e { P("  %s mouseDown%s\n", [name UTF8String], handles ? "" : " (passes on)"); if (!handles) [super mouseDown:e]; }
- (void)ping:(id)s { P("  %s ping\n", [name UTF8String]); }
@end

static void events(void) {
  P("== NSEvent\n");
  NSEvent *m = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(12, 34) modifierFlags:NSEventModifierFlagShift timestamp:5.5 windowNumber:0 context:nil eventNumber:7 clickCount:2 pressure:0.5];
  P("mouse: type %lu location %g,%g shift %d ts %g window %ld number %ld clicks %ld pressure %g button %ld window obj %d\n", (unsigned long)m.type, m.locationInWindow.x, m.locationInWindow.y,
    (m.modifierFlags & NSEventModifierFlagShift) != 0, m.timestamp, (long)m.windowNumber, (long)m.eventNumber, (long)m.clickCount, m.pressure, (long)m.buttonNumber, m.window != nil);
  NSEvent *r = [NSEvent mouseEventWithType:NSEventTypeRightMouseUp location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:0];
  NSEvent *o = [NSEvent mouseEventWithType:NSEventTypeOtherMouseDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1];
  P("buttons: right %ld other %ld\n", (long)r.buttonNumber, (long)o.buttonNumber);
  NSEvent *k = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand timestamp:1 windowNumber:0 context:nil characters:@"q" charactersIgnoringModifiers:@"Q" isARepeat:YES keyCode:12];
  P("key: type %lu chars %s ignoring %s repeat %d keyCode %d command %d\n", (unsigned long)k.type, [k.characters UTF8String], [k.charactersIgnoringModifiers UTF8String], k.isARepeat, k.keyCode,
    (k.modifierFlags & NSEventModifierFlagCommand) != 0);
  NSEvent *a = [NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSMakePoint(1, 2) modifierFlags:0 timestamp:2 windowNumber:0 context:nil subtype:9 data1:111 data2:222];
  P("other: type %lu subtype %d data %ld %ld\n", (unsigned long)a.type, a.subtype, (long)a.data1, (long)a.data2);
  int marker = 0;
  NSEvent *x = [NSEvent enterExitEventWithType:NSEventTypeMouseEntered location:NSMakePoint(3, 4) modifierFlags:0 timestamp:3 windowNumber:0 context:nil eventNumber:1 trackingNumber:42 userData:&marker];
  P("enter: type %lu tracking %ld userData ok %d\n", (unsigned long)x.type, (long)x.trackingNumber, x.userData == &marker);
  P("masks: left down %llx key down %llx from type %llx\n", (unsigned long long)NSEventMaskLeftMouseDown, (unsigned long long)NSEventMaskKeyDown, (unsigned long long)NSEventMaskFromType(NSEventTypeScrollWheel));

  P("== responder chain\n");
  R *top = [[R alloc] init], *mid = [[R alloc] init], *bottom = [[R alloc] init]; top->name = @"top"; mid->name = @"mid"; bottom->name = @"bottom"; top->handles = YES;
  bottom.nextResponder = mid; mid.nextResponder = top;
  P("mouseDown at the bottom\n"); [bottom mouseDown:m];
  P("tryToPerform ping %d missing %d\n", [bottom tryToPerform:@selector(ping:) with:nil], [bottom tryToPerform:@selector(copy:) with:nil]);
  NSResponder *plain = [[NSResponder alloc] init];
  P("plain: accepts %d become %d resign %d validate %d supplemental %d\n", plain.acceptsFirstResponder, [plain becomeFirstResponder], [plain resignFirstResponder],
    [plain validateProposedFirstResponder:plain forEvent:nil], [plain supplementalTargetForAction:@selector(ping:) sender:nil] != nil);
}

@interface Target : NSObject
@end
@implementation Target
- (void)click:(NSClickGestureRecognizer *)g { P("  click action state %ld\n", (long)g.state); }
- (void)pan:(NSPanGestureRecognizer *)g { NSPoint t = [g translationInView:g.view]; P("  pan action state %ld translation %g,%g\n", (long)g.state, t.x, t.y); }
@end

static void gestures(void) {
  P("== gesture recognizers\n");
  Target *t = [[Target alloc] init];
  NSClickGestureRecognizer *c = [[NSClickGestureRecognizer alloc] initWithTarget:t action:@selector(click:)];
  P("click defaults: clicks %ld buttonMask %lu state %ld enabled %d view %d target %d delays primary %d\n", (long)c.numberOfClicksRequired, (unsigned long)c.buttonMask, (long)c.state, c.enabled, c.view != nil, c.target == t,
    c.delaysPrimaryMouseButtonEvents);
  NSPanGestureRecognizer *p = [[NSPanGestureRecognizer alloc] initWithTarget:t action:@selector(pan:)];
  NSPressGestureRecognizer *pr = [[NSPressGestureRecognizer alloc] initWithTarget:t action:@selector(click:)];
  NSMagnificationGestureRecognizer *mg = [[NSMagnificationGestureRecognizer alloc] initWithTarget:t action:@selector(click:)];
  NSRotationGestureRecognizer *ro = [[NSRotationGestureRecognizer alloc] initWithTarget:t action:@selector(click:)];
  P("pan buttonMask %lu; press buttonMask %lu movement %g; magnification %g rotation %g\n", (unsigned long)p.buttonMask, (unsigned long)pr.buttonMask, pr.allowableMovement, mg.magnification, ro.rotation);
  NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 300, 200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
  NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(20, 20, 200, 100)]; [w.contentView addSubview:v];
  [v addGestureRecognizer:c]; [v addGestureRecognizer:p];
  P("attached: view %d recognizers %ld\n", c.view == v, (long)v.gestureRecognizers.count);
  [v removeGestureRecognizer:c]; P("removed: view %d recognizers %ld\n", c.view != nil, (long)v.gestureRecognizers.count);
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    controllers(); events(); gestures();
    P("done\n");
  }
  return 0;
}
