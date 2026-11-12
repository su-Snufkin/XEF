/* AppKit-lite: view controller hierarchy (children, presentation), NSSplitViewController / NSSplitViewItem,
 * NSTabViewController, gesture recognizers and the responder-chain methods for gestures and touches.
 * Behaviour follows real AppKit as recorded by tests/darwin/mac/appkit_controllers.m. */
#import "AppKitLite.h"
#import "AppKitGraphics.h"
#import "AppKitControls.h"
#import "AppKitControls2.h"
#import "AppKitControllers.h"
#include <objc/runtime.h>
#include <objc/message.h>
#include <math.h>

static char kCtl;
static NSMutableDictionary *props(id o) {
  NSMutableDictionary *d = objc_getAssociatedObject(o, &kCtl);
  if (!d) { d = [NSMutableDictionary dictionary]; objc_setAssociatedObject(o, &kCtl, d, OBJC_ASSOCIATION_RETAIN); }
  return d; }
static void put(NSMutableDictionary *d, NSString *k, id v) { if (v) d[k] = v; else [d removeObjectForKey:k]; }

/* ================================================================== NSViewController */
@implementation NSViewController (XEFMore)
- (void)loadViewIfNeeded { if (![self isViewLoaded]) (void)[self view]; }
- (NSView *)viewIfLoaded { return _view; }
- (void)setPreferredContentSize:(NSSize)s { objc_setAssociatedObject(self, "xef.preferredContentSize", [NSValue valueWithSize:s], OBJC_ASSOCIATION_RETAIN); }
- (NSString *)identifier { return props(self)[@"identifier"]; } - (void)setIdentifier:(NSString *)i { put(props(self), @"identifier", [[i copy] autorelease]); }
- (NSSize)preferredMinimumSize { return NSZeroSize; } - (NSSize)preferredMaximumSize { return NSMakeSize(10000, 10000); }
- (NSPoint)preferredScreenOrigin { id v = props(self)[@"origin"]; return v ? [v pointValue] : NSZeroPoint; }
- (void)setPreferredScreenOrigin:(NSPoint)p { props(self)[@"origin"] = [NSValue valueWithPoint:p]; }
- (NSView *)sourceItemView { return [props(self)[@"sourceItem"] nonretainedObjectValue]; }
- (void)setSourceItemView:(NSView *)v { put(props(self), @"sourceItem", v ? [NSValue valueWithNonretainedObject:v] : nil); }
- (id)extensionContext { return nil; }
- (void)preferredContentSizeDidChangeForViewController:(NSViewController *)c {}
- (void)viewWillTransitionToSize:(NSSize)s {}
- (BOOL)commitEditing { return YES; } - (void)discardEditing {}
- (BOOL)commitEditingAndReturnError:(NSError **)e { return YES; }
- (void)commitEditingWithDelegate:(id)d didCommitSelector:(SEL)s contextInfo:(void *)c {
  if ([d respondsToSelector:s]) ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(d, s, self, YES, c); }

/* ---- children: the parent keeps them in order; a child's view joins the responder chain through its controller */
- (NSArray *)childViewControllers { return [[props(self)[@"children"] copy] autorelease] ?: @[]; }
- (void)setChildViewControllers:(NSArray *)a {
  for (NSViewController *c in [self childViewControllers]) [c removeFromParentViewController];
  for (NSViewController *c in a) [self addChildViewController:c]; }
- (NSViewController *)parentViewController { return [props(self)[@"parent"] nonretainedObjectValue]; }
- (void)insertChildViewController:(NSViewController *)c atIndex:(NSInteger)i {
  if (!c || c == self) return;
  [[c retain] autorelease];
  if ([c parentViewController]) [c removeFromParentViewController];
  NSMutableArray *a = props(self)[@"children"]; if (!a) { a = [NSMutableArray array]; props(self)[@"children"] = a; }
  [a insertObject:c atIndex:i < 0 ? 0 : i > (NSInteger)[a count] ? [a count] : i];
  props(c)[@"parent"] = [NSValue valueWithNonretainedObject:self]; }
- (void)addChildViewController:(NSViewController *)c { [self insertChildViewController:c atIndex:[[self childViewControllers] count]]; }
- (void)removeChildViewControllerAtIndex:(NSInteger)i { NSArray *a = [self childViewControllers]; if (i >= 0 && i < (NSInteger)[a count]) [a[i] removeFromParentViewController]; }
- (void)removeFromParentViewController {
  NSViewController *p = [self parentViewController]; if (!p) return;
  [[self retain] autorelease];
  [props(p)[@"children"] removeObjectIdenticalTo:self]; [props(self) removeObjectForKey:@"parent"]; }
- (void)transitionFromViewController:(NSViewController *)from toViewController:(NSViewController *)to options:(NSUInteger)o completionHandler:(void (^)(void))h {
  NSView *sup = [[from view] superview];
  [from viewWillDisappear]; [to viewWillAppear];
  if (sup) { [sup addSubview:[to view]]; [[to view] setFrame:[[from view] frame]]; [[from view] removeFromSuperview]; }
  [from viewDidDisappear]; [to viewDidAppear];
  if (h) h(); }

/* ---- presentation: a sheet, a modal window or a popover shows the controller's view in a window of its own */
- (NSViewController *)presentingViewController { return [props(self)[@"presenter"] nonretainedObjectValue]; }
- (NSArray *)presentedViewControllers { return [[props(self)[@"presented"] copy] autorelease] ?: @[]; }
- (void)_xefPresent:(NSViewController *)vc window:(NSWindow *)w {
  NSMutableArray *a = props(self)[@"presented"]; if (!a) { a = [NSMutableArray array]; props(self)[@"presented"] = a; }
  [a addObject:vc]; props(vc)[@"presenter"] = [NSValue valueWithNonretainedObject:self]; props(vc)[@"presentWindow"] = w; }
- (void)presentViewControllerAsSheet:(NSViewController *)vc {
  NSWindow *host = [[self view] window], *sheet = [NSWindow windowWithContentViewController:vc];
  [self _xefPresent:vc window:sheet];
  if (host) [host beginSheet:sheet completionHandler:nil]; else [sheet makeKeyAndOrderFront:nil]; }
- (void)presentViewControllerAsModalWindow:(NSViewController *)vc {
  NSWindow *w = [NSWindow windowWithContentViewController:vc]; [self _xefPresent:vc window:w]; [w center]; [w makeKeyAndOrderFront:nil]; }
- (void)presentViewController:(NSViewController *)vc animator:(id)animator {
  if ([animator respondsToSelector:@selector(animatePresentationOfViewController:fromViewController:)]) {
    [self _xefPresent:vc window:nil];
    [animator performSelector:@selector(animatePresentationOfViewController:fromViewController:) withObject:vc withObject:self];
  } else [self presentViewControllerAsModalWindow:vc]; }
- (void)presentViewController:(NSViewController *)vc asPopoverRelativeToRect:(NSRect)r ofView:(NSView *)v preferredEdge:(NSInteger)e behavior:(NSInteger)b {
  NSWindow *w = [NSWindow windowWithContentViewController:vc]; [self _xefPresent:vc window:w];
  NSWindow *host = [v window];
  if (host) { NSRect hf = [host frame]; NSRect vr = [v convertRect:r toView:nil]; [w setFrameOrigin:NSMakePoint(hf.origin.x + vr.origin.x, hf.origin.y + vr.origin.y - [w frame].size.height)]; }
  [w makeKeyAndOrderFront:nil]; }
- (void)presentViewController:(NSViewController *)vc asPopoverRelativeToRect:(NSRect)r ofView:(NSView *)v preferredEdge:(NSInteger)e behavior:(NSInteger)b hasFullSizeContent:(BOOL)f {
  [self presentViewController:vc asPopoverRelativeToRect:r ofView:v preferredEdge:e behavior:b]; }
- (void)dismissViewController:(NSViewController *)vc {
  NSMutableArray *a = props(self)[@"presented"]; if (![a containsObject:vc]) return;
  NSWindow *w = props(vc)[@"presentWindow"], *host = [[self view] window];
  [[vc retain] autorelease];
  [a removeObject:vc]; [props(vc) removeObjectForKey:@"presenter"]; [props(vc) removeObjectForKey:@"presentWindow"];
  if (w && [w isSheet]) [host endSheet:w]; else [w orderOut:nil]; }
- (void)dismissController:(id)sender { NSViewController *p = [self presentingViewController]; if (p) [p dismissViewController:self]; }
@end

/* ================================================================== NSSplitViewItem, NSSplitViewController */
@interface NSSplitViewItem : NSObject {
@public
  NSViewController *_vc; BOOL _canCollapse, _collapsed, _springLoaded, _fullHeight; float _holding; CGFloat _min, _max, _fraction; NSInteger _behavior, _separator;
}
@end
@implementation NSSplitViewItem
+ (NSSplitViewItem *)_xef:(NSViewController *)vc behavior:(NSInteger)b {
  NSSplitViewItem *i = [[[self alloc] init] autorelease]; i->_vc = [vc retain]; i->_behavior = b; i->_min = -1; i->_max = -1; i->_fraction = -1; i->_holding = 250;
  if (b == 1) { i->_canCollapse = YES; i->_holding = 260; } else if (b == 3) { i->_canCollapse = YES; i->_holding = 260; } else if (b == 2) { i->_holding = 255; }
  return i; }
+ (NSSplitViewItem *)splitViewItemWithViewController:(NSViewController *)vc { return [self _xef:vc behavior:0]; }
+ (NSSplitViewItem *)sidebarWithViewController:(NSViewController *)vc { return [self _xef:vc behavior:1]; }
+ (NSSplitViewItem *)contentListWithViewController:(NSViewController *)vc { return [self _xef:vc behavior:2]; }
+ (NSSplitViewItem *)inspectorWithViewController:(NSViewController *)vc { return [self _xef:vc behavior:3]; }
+ (NSSplitViewItem *)mediaBrowserWithViewController:(NSViewController *)vc { return [self _xef:vc behavior:0]; }
- (void)dealloc { [_vc release]; [super dealloc]; }
- (NSViewController *)viewController { return _vc; } - (void)setViewController:(NSViewController *)v { [v retain]; [_vc release]; _vc = v; }
- (NSInteger)behavior { return _behavior; }
- (BOOL)canCollapse { return _canCollapse; } - (void)setCanCollapse:(BOOL)f { _canCollapse = f; }
- (BOOL)isCollapsed { return _collapsed; } - (void)setCollapsed:(BOOL)f { _collapsed = f; [_vc isViewLoaded] ? [[_vc view] setHidden:f] : (void)0; }
- (float)holdingPriority { return _holding; } - (void)setHoldingPriority:(float)p { _holding = p; }
- (CGFloat)minimumThickness { return _min; } - (void)setMinimumThickness:(CGFloat)t { _min = t; }
- (CGFloat)maximumThickness { return _max; } - (void)setMaximumThickness:(CGFloat)t { _max = t; }
- (CGFloat)preferredThicknessFraction { return _fraction; } - (void)setPreferredThicknessFraction:(CGFloat)f { _fraction = f; }
- (BOOL)isSpringLoaded { return _springLoaded; } - (void)setSpringLoaded:(BOOL)f { _springLoaded = f; }
- (BOOL)allowsFullHeightLayout { return _fullHeight; } - (void)setAllowsFullHeightLayout:(BOOL)f { _fullHeight = f; }
- (NSInteger)titlebarSeparatorStyle { return _separator; } - (void)setTitlebarSeparatorStyle:(NSInteger)s { _separator = s; }
- (CGFloat)automaticMaximumThickness { return -1; } - (void)setAutomaticMaximumThickness:(CGFloat)t {}
- (BOOL)isCollapseBehaviorAutomatic { return YES; }
- (void)setCollapsed:(BOOL)f animated:(BOOL)a { [self setCollapsed:f]; }
- (id)animator { return self; }
@end

@interface NSSplitViewController : NSViewController {
@public
  NSSplitView *_sv; NSMutableArray *_items; BOOL _built;
}
@end
@implementation NSSplitViewController
- (id)initWithNibName:(NSString *)n bundle:(NSBundle *)b { if ((self = [super initWithNibName:n bundle:b])) { _items = [[NSMutableArray alloc] init]; } return self; }
- (id)initWithCoder:(NSCoder *)c { if ((self = [super initWithCoder:c])) { _items = [[NSMutableArray alloc] init]; } return self; }
- (void)dealloc { [_sv release]; [_items release]; [super dealloc]; }
- (NSSplitView *)splitView {
  if (!_sv) { _sv = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 500, 500)]; [_sv setVertical:YES]; [_sv setDividerStyle:0]; [_sv setDelegate:self]; }
  return _sv; }
- (void)setSplitView:(NSSplitView *)sv { [sv retain]; [_sv release]; _sv = sv; [_sv setDelegate:self]; }
- (void)loadView {
  NSView *container = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 500)] autorelease];
  NSSplitView *sv = [self splitView]; [sv setFrame:[container bounds]]; [sv setAutoresizingMask:2 | 16]; [container addSubview:sv];
  for (NSSplitViewItem *i in _items) if ([[i viewController] view]) [sv addArrangedSubview:[[i viewController] view]];
  [self setView:container]; }
- (NSArray *)splitViewItems { return [[_items copy] autorelease]; }
- (void)setSplitViewItems:(NSArray *)a { for (NSSplitViewItem *i in [self splitViewItems]) [self removeSplitViewItem:i]; for (NSSplitViewItem *i in a) [self addSplitViewItem:i]; }
- (void)insertSplitViewItem:(NSSplitViewItem *)item atIndex:(NSInteger)idx {
  if (!item) return;
  NSInteger at = idx < 0 ? 0 : idx > (NSInteger)[_items count] ? [_items count] : idx;
  [_items insertObject:item atIndex:at]; [self insertChildViewController:[item viewController] atIndex:at];
  if ([self isViewLoaded] && [[item viewController] view]) [[self splitView] insertArrangedSubview:[[item viewController] view] atIndex:at]; }
- (void)addSplitViewItem:(NSSplitViewItem *)item { [self insertSplitViewItem:item atIndex:[_items count]]; }
- (void)removeSplitViewItem:(NSSplitViewItem *)item {
  if (![_items containsObject:item]) return;
  [[item retain] autorelease];
  NSViewController *vc = [item viewController];
  if ([vc isViewLoaded]) [[self splitView] removeArrangedSubview:[vc view]];
  [vc removeFromParentViewController]; [_items removeObject:item]; }
- (NSSplitViewItem *)splitViewItemForViewController:(NSViewController *)vc { for (NSSplitViewItem *i in _items) if ([i viewController] == vc) return i; return nil; }
- (BOOL)isSidebarCollapsed { return NO; }
- (void)toggleSidebar:(id)s { for (NSSplitViewItem *i in _items) if ([i behavior] == 1) [i setCollapsed:![i isCollapsed]]; }
- (void)toggleInspector:(id)s { for (NSSplitViewItem *i in _items) if ([i behavior] == 3) [i setCollapsed:![i isCollapsed]]; }
- (BOOL)validateUserInterfaceItem:(id)i { return YES; }
- (BOOL)splitView:(NSSplitView *)sv canCollapseSubview:(NSView *)v { for (NSSplitViewItem *i in _items) if ([[i viewController] viewIfLoaded] == v) return [i canCollapse]; return NO; }
- (CGFloat)splitView:(NSSplitView *)sv constrainMinCoordinate:(CGFloat)p ofSubviewAt:(NSInteger)i {
  NSSplitViewItem *it = i < (NSInteger)[_items count] ? _items[i] : nil; return it && [it minimumThickness] > 0 ? p + [it minimumThickness] : p; }
- (CGFloat)splitView:(NSSplitView *)sv constrainMaxCoordinate:(CGFloat)p ofSubviewAt:(NSInteger)i {
  NSSplitViewItem *it = i < (NSInteger)[_items count] ? _items[i] : nil; return it && [it maximumThickness] > 0 ? fmin(p, [[sv arrangedSubviews][i] frame].origin.x + [it maximumThickness]) : p; }
@end

/* ================================================================== NSTabViewController */
@interface NSTabViewController : NSViewController {
@public
  NSTabView *_tv; NSMutableArray *_items; NSInteger _style, _sel; BOOL _propagate; NSUInteger _transition;
}
@end
@implementation NSTabViewController
- (void)_xefInit { _items = [[NSMutableArray alloc] init]; _sel = -1; _propagate = YES; _transition = 0x1000; }
- (id)initWithNibName:(NSString *)n bundle:(NSBundle *)b { if ((self = [super initWithNibName:n bundle:b])) [self _xefInit]; return self; }
- (id)initWithCoder:(NSCoder *)c { if ((self = [super initWithCoder:c])) [self _xefInit]; return self; }
- (void)dealloc { [_tv release]; [_items release]; [super dealloc]; }
- (NSInteger)tabStyle { return _style; } - (void)setTabStyle:(NSInteger)s { _style = s; }
- (BOOL)canPropagateSelectedChildViewControllerTitle { return _propagate; } - (void)setCanPropagateSelectedChildViewControllerTitle:(BOOL)f { _propagate = f; }
- (NSUInteger)transitionOptions { return _transition; } - (void)setTransitionOptions:(NSUInteger)o { _transition = o; }
- (NSTabView *)tabView { (void)[self view]; return _tv; }
- (void)setTabView:(NSTabView *)t { [t retain]; [_tv release]; _tv = t; [_tv setDelegate:self]; }
- (NSString *)title {
  NSString *own = [super title]; if (own) return own;
  if (_propagate && _sel >= 0 && _sel < (NSInteger)[_items count]) return [[[_items[_sel] viewController] title] copy] ? [[_items[_sel] viewController] title] : nil;
  return nil; }
- (void)loadView {
  NSTabView *tv = _tv ?: [[[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, 500, 500)] autorelease];
  [self setTabView:tv];
  for (NSTabViewItem *i in _items) [tv addTabViewItem:i];
  if (_sel >= 0 && _sel < (NSInteger)[_items count]) [tv selectTabViewItemAtIndex:_sel];
  [self setView:tv]; }
- (NSArray *)tabViewItems { return [[_items copy] autorelease]; }
- (void)setTabViewItems:(NSArray *)a { for (NSTabViewItem *i in [self tabViewItems]) [self removeTabViewItem:i]; for (NSTabViewItem *i in a) [self addTabViewItem:i]; }
- (void)insertTabViewItem:(NSTabViewItem *)item atIndex:(NSInteger)idx {
  if (!item) return;
  NSInteger at = idx < 0 ? 0 : idx > (NSInteger)[_items count] ? [_items count] : idx;
  [_items insertObject:item atIndex:at];
  id vc = [item viewController]; if (vc) [self insertChildViewController:vc atIndex:at];
  if ([vc title] && ![[item label] length]) [item setLabel:[vc title]];
  if (_sel < 0) _sel = 0; else if (at <= _sel && [_items count] > 1) _sel++;
  if (_tv) [_tv insertTabViewItem:item atIndex:at]; }
- (void)addTabViewItem:(NSTabViewItem *)item { [self insertTabViewItem:item atIndex:[_items count]]; }
- (void)removeTabViewItem:(NSTabViewItem *)item {
  NSUInteger i = [_items indexOfObject:item]; if (i == NSNotFound) return;
  [[item retain] autorelease];
  if (_tv) [_tv removeTabViewItem:item];
  [[item viewController] removeFromParentViewController]; [_items removeObjectAtIndex:i];
  if (_sel >= (NSInteger)[_items count]) _sel = (NSInteger)[_items count] - 1; }
- (NSTabViewItem *)tabViewItemForViewController:(NSViewController *)vc { for (NSTabViewItem *i in _items) if ([i viewController] == vc) return i; return nil; }
- (NSInteger)selectedTabViewItemIndex { return _sel; }
- (void)setSelectedTabViewItemIndex:(NSInteger)i {
  if (i < 0 || i >= (NSInteger)[_items count]) return;
  _sel = i; if (_tv) [_tv selectTabViewItemAtIndex:i]; }
- (void)tabView:(NSTabView *)t didSelectTabViewItem:(NSTabViewItem *)i { NSUInteger k = [_items indexOfObject:i]; if (k != NSNotFound) _sel = k; }
@end

/* ================================================================== gesture recognizers */
@interface NSGestureRecognizer : NSObject {
@public
  id _target; SEL _action; NSView *_view; NSInteger _state; BOOL _enabled, _delaysPrimary, _delaysSecondary, _delaysOther; id _delegate; NSUInteger _buttonMask;
  NSPoint _start, _last; NSTimeInterval _downTime; NSInteger _clicks; BOOL _tracking;
}
@end
enum { kPossible, kBegan, kChanged, kEnded, kCancelled, kFailed };
@implementation NSGestureRecognizer
- (id)init { return [self initWithTarget:nil action:NULL]; }
- (id)initWithTarget:(id)t action:(SEL)a { if ((self = [super init])) { _target = t; _action = a; _enabled = YES; _delaysPrimary = YES; _buttonMask = 1; } return self; }
- (id)initWithCoder:(NSCoder *)c { return [self init]; } - (void)encodeWithCoder:(NSCoder *)c {}
- (id)target { return _target; } - (void)setTarget:(id)t { _target = t; }
- (SEL)action { return _action; } - (void)setAction:(SEL)a { _action = a; }
- (NSView *)view { return _view; } - (void)_xefSetView:(NSView *)v { _view = v; }
- (NSInteger)state { return _state; } - (void)setState:(NSInteger)s { _state = s; }
- (BOOL)isEnabled { return _enabled; } - (void)setEnabled:(BOOL)f { _enabled = f; if (!f) _state = kPossible; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (BOOL)delaysPrimaryMouseButtonEvents { return _delaysPrimary; } - (void)setDelaysPrimaryMouseButtonEvents:(BOOL)f { _delaysPrimary = f; }
- (BOOL)delaysSecondaryMouseButtonEvents { return _delaysSecondary; } - (void)setDelaysSecondaryMouseButtonEvents:(BOOL)f { _delaysSecondary = f; }
- (BOOL)delaysOtherMouseButtonEvents { return _delaysOther; } - (void)setDelaysOtherMouseButtonEvents:(BOOL)f { _delaysOther = f; }
- (BOOL)delaysKeyEvents { return YES; } - (void)setDelaysKeyEvents:(BOOL)f {} - (BOOL)delaysMagnificationEvents { return YES; } - (void)setDelaysMagnificationEvents:(BOOL)f {}
- (BOOL)delaysRotationEvents { return YES; } - (void)setDelaysRotationEvents:(BOOL)f {}
- (BOOL)allowedTouchTypes { return NO; } - (id)pressureConfiguration { return nil; } - (void)setPressureConfiguration:(id)c {}
- (id)name { return props(self)[@"name"]; } - (void)setName:(NSString *)n { put(props(self), @"name", n); }
- (NSPoint)locationInView:(NSView *)v { return [(v ?: _view) convertPoint:_last fromView:nil]; }
- (NSPoint)locationOfTouch:(NSInteger)i inView:(NSView *)v { return [self locationInView:v]; }
- (NSInteger)numberOfTouches { return _tracking ? 1 : 0; }
- (void)reset { _state = kPossible; _tracking = NO; }
- (void)canPreventGestureRecognizer:(id)g {}
- (BOOL)canBePreventedByGestureRecognizer:(NSGestureRecognizer *)g { return YES; }
- (void)requireGestureRecognizerToFail:(NSGestureRecognizer *)g {}
- (void)_xefFire { if (_target && _action && [_target respondsToSelector:_action]) ((void (*)(id, SEL, id))objc_msgSend)(_target, _action, self); }
/* window-dispatched mouse events: subclasses decide what a gesture is */
- (void)_xefMouseDown:(NSEvent *)e {}
- (void)_xefMouseDragged:(NSEvent *)e {}
- (void)_xefMouseUp:(NSEvent *)e {}
- (void)mouseDown:(NSEvent *)e { if (_enabled) [self _xefMouseDown:e]; }
- (void)mouseDragged:(NSEvent *)e { if (_enabled) [self _xefMouseDragged:e]; }
- (void)mouseUp:(NSEvent *)e { if (_enabled) [self _xefMouseUp:e]; }
- (void)rightMouseDown:(NSEvent *)e {} - (void)rightMouseDragged:(NSEvent *)e {} - (void)rightMouseUp:(NSEvent *)e {}
- (void)otherMouseDown:(NSEvent *)e {} - (void)otherMouseDragged:(NSEvent *)e {} - (void)otherMouseUp:(NSEvent *)e {}
- (void)keyDown:(NSEvent *)e {} - (void)keyUp:(NSEvent *)e {} - (void)flagsChanged:(NSEvent *)e {}
- (void)magnifyWithEvent:(NSEvent *)e {} - (void)rotateWithEvent:(NSEvent *)e {}
- (void)touchesBeganWithEvent:(NSEvent *)e {} - (void)touchesMovedWithEvent:(NSEvent *)e {} - (void)touchesEndedWithEvent:(NSEvent *)e {} - (void)touchesCancelledWithEvent:(NSEvent *)e {}
@end

@interface NSClickGestureRecognizer : NSGestureRecognizer { @public NSInteger _required, _touchesRequired; }
@end
@implementation NSClickGestureRecognizer
- (id)initWithTarget:(id)t action:(SEL)a { if ((self = [super initWithTarget:t action:a])) { _required = 1; _touchesRequired = 1; } return self; }
- (NSUInteger)buttonMask { return _buttonMask; } - (void)setButtonMask:(NSUInteger)m { _buttonMask = m; }
- (NSInteger)numberOfClicksRequired { return _required; } - (void)setNumberOfClicksRequired:(NSInteger)n { _required = n; }
- (NSInteger)numberOfTouchesRequired { return _touchesRequired; } - (void)setNumberOfTouchesRequired:(NSInteger)n { _touchesRequired = n; }
- (void)_xefMouseDown:(NSEvent *)e { _tracking = YES; _last = [e locationInWindow]; _clicks = [e clickCount]; _state = kPossible; }
- (void)_xefMouseUp:(NSEvent *)e {
  if (!_tracking) return;
  _tracking = NO; _last = [e locationInWindow];
  NSPoint p = [_view convertPoint:_last fromView:nil];
  if (NSPointInRect(p, [_view bounds]) && [e clickCount] >= _required) { _state = kEnded; [self _xefFire]; }
  _state = kPossible; }
@end

@interface NSPanGestureRecognizer : NSGestureRecognizer { @public NSInteger _touchesRequired; NSPoint _translation; NSTimeInterval _lastTime; NSPoint _velocity; }
@end
@implementation NSPanGestureRecognizer
- (id)initWithTarget:(id)t action:(SEL)a { if ((self = [super initWithTarget:t action:a])) { _touchesRequired = 1; } return self; }
- (NSUInteger)buttonMask { return _buttonMask; } - (void)setButtonMask:(NSUInteger)m { _buttonMask = m; }
- (NSInteger)numberOfTouchesRequired { return _touchesRequired; } - (void)setNumberOfTouchesRequired:(NSInteger)n { _touchesRequired = n; }
- (NSPoint)translationInView:(NSView *)v { return _translation; }
- (void)setTranslation:(NSPoint)t inView:(NSView *)v { _start = NSMakePoint(_last.x - t.x, _last.y - t.y); _translation = t; }
- (NSPoint)velocityInView:(NSView *)v { return _velocity; }
- (void)_xefMouseDown:(NSEvent *)e { _tracking = YES; _start = _last = [e locationInWindow]; _translation = NSZeroPoint; _velocity = NSZeroPoint; _lastTime = [e timestamp]; _state = kPossible; }
- (void)_xefMouseDragged:(NSEvent *)e {
  if (!_tracking) return;
  NSPoint p = [e locationInWindow]; NSTimeInterval dt = [e timestamp] - _lastTime;
  _translation = NSMakePoint(p.x - _start.x, p.y - _start.y);
  if (dt > 0) _velocity = NSMakePoint((p.x - _last.x) / dt, (p.y - _last.y) / dt);
  _last = p; _lastTime = [e timestamp];
  if (_state == kPossible) { if (hypot(_translation.x, _translation.y) < 3) return; _state = kBegan; } else _state = kChanged;
  [self _xefFire]; }
- (void)_xefMouseUp:(NSEvent *)e {
  BOOL began = _state != kPossible; _tracking = NO;
  if (began) { _state = kEnded; [self _xefFire]; }
  _state = kPossible; }
@end

@interface NSPressGestureRecognizer : NSGestureRecognizer { @public NSTimeInterval _minimum; CGFloat _movement; NSInteger _touchesRequired; }
@end
@implementation NSPressGestureRecognizer
- (id)initWithTarget:(id)t action:(SEL)a { if ((self = [super initWithTarget:t action:a])) { _minimum = 0.5; _movement = 5; _touchesRequired = 1; } return self; }
- (NSUInteger)buttonMask { return _buttonMask; } - (void)setButtonMask:(NSUInteger)m { _buttonMask = m; }
- (NSTimeInterval)minimumPressDuration { return _minimum; } - (void)setMinimumPressDuration:(NSTimeInterval)d { _minimum = d; }
- (CGFloat)allowableMovement { return _movement; } - (void)setAllowableMovement:(CGFloat)m { _movement = m; }
- (NSInteger)numberOfTouchesRequired { return _touchesRequired; } - (void)setNumberOfTouchesRequired:(NSInteger)n { _touchesRequired = n; }
- (void)_xefBegin { if (_tracking && _state == kPossible) { _state = kBegan; [self _xefFire]; } }
- (void)_xefMouseDown:(NSEvent *)e { _tracking = YES; _start = _last = [e locationInWindow]; _state = kPossible; [self performSelector:@selector(_xefBegin) withObject:nil afterDelay:_minimum]; }
- (void)_xefMouseDragged:(NSEvent *)e {
  NSPoint p = [e locationInWindow]; _last = p;
  if (_state == kPossible && hypot(p.x - _start.x, p.y - _start.y) > _movement) { _tracking = NO; _state = kFailed; }
  else if (_state == kBegan || _state == kChanged) { _state = kChanged; [self _xefFire]; } }
- (void)_xefMouseUp:(NSEvent *)e {
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_xefBegin) object:nil];
  if (_state == kBegan || _state == kChanged) { _state = kEnded; [self _xefFire]; }
  _tracking = NO; _state = kPossible; }
@end

@interface NSMagnificationGestureRecognizer : NSGestureRecognizer { @public CGFloat _magnification; }
@end
@implementation NSMagnificationGestureRecognizer
- (CGFloat)magnification { return _magnification; } - (void)setMagnification:(CGFloat)m { _magnification = m; }
- (void)magnifyWithEvent:(NSEvent *)e {
  if (!_enabled) return;
  _magnification += 0; _state = _state == kPossible ? kBegan : kChanged; [self _xefFire]; }
@end

@interface NSRotationGestureRecognizer : NSGestureRecognizer { @public CGFloat _rotation; }
@end
@implementation NSRotationGestureRecognizer
- (CGFloat)rotation { return _rotation; } - (void)setRotation:(CGFloat)r { _rotation = r; }
- (CGFloat)rotationInDegrees { return _rotation * 180 / M_PI; } - (void)setRotationInDegrees:(CGFloat)d { _rotation = d * M_PI / 180; }
@end

/* recognizers of the view under the pointer and of its ancestors see the window's mouse events; the events still reach
 * the views (AppKit delays them until the gesture fails, which needs a timing model AppKit-lite does not have) */
BOOL XEFGestureDispatch(NSWindow *w, NSView *target, NSEvent *e) {
  NSEventType t = [e type];
  BOOL down = t == NSEventTypeLeftMouseDown, drag = t == NSEventTypeLeftMouseDragged, up = t == NSEventTypeLeftMouseUp;
  if (!down && !drag && !up) return NO;
  static NSMutableArray *active;
  if (!active) active = [[NSMutableArray alloc] init];
  if (down) {
    [active removeAllObjects];
    for (NSView *v = target; v; v = [v superview]) for (id g in [v gestureRecognizers]) if ([g isKindOfClass:[NSGestureRecognizer class]]) [active addObject:g]; }
  for (NSGestureRecognizer *g in [[active copy] autorelease]) {
    if (down) [g mouseDown:e]; else if (drag) [g mouseDragged:e]; else [g mouseUp:e]; }
  if (up) [active removeAllObjects];
  return NO; }

/* ================================================================== responder chain: gestures, touches, restoration */
@interface NSResponder (XEFForward)
@end
#define FWD(sel) - (void)sel:(NSEvent *)e { if (_nextResponder && [_nextResponder respondsToSelector:@selector(sel:)]) [(id)_nextResponder sel:e]; }
@implementation NSResponder (XEFMore)
FWD(mouseCancelled)
- (void)magnifyWithEvent:(NSEvent *)e { if (_nextResponder && [_nextResponder respondsToSelector:@selector(magnifyWithEvent:)]) [(id)_nextResponder magnifyWithEvent:e]; }
- (void)rotateWithEvent:(NSEvent *)e { if (_nextResponder && [_nextResponder respondsToSelector:@selector(rotateWithEvent:)]) [(id)_nextResponder rotateWithEvent:e]; }
- (void)swipeWithEvent:(NSEvent *)e { if (_nextResponder && [_nextResponder respondsToSelector:@selector(swipeWithEvent:)]) [(id)_nextResponder swipeWithEvent:e]; }
- (void)beginGestureWithEvent:(NSEvent *)e { if (_nextResponder && [_nextResponder respondsToSelector:@selector(beginGestureWithEvent:)]) [(id)_nextResponder beginGestureWithEvent:e]; }
- (void)endGestureWithEvent:(NSEvent *)e { if (_nextResponder && [_nextResponder respondsToSelector:@selector(endGestureWithEvent:)]) [(id)_nextResponder endGestureWithEvent:e]; }
- (void)smartMagnifyWithEvent:(NSEvent *)e { if (_nextResponder && [_nextResponder respondsToSelector:@selector(smartMagnifyWithEvent:)]) [(id)_nextResponder smartMagnifyWithEvent:e]; }
- (void)changeModeWithEvent:(NSEvent *)e { if (_nextResponder && [_nextResponder respondsToSelector:@selector(changeModeWithEvent:)]) [(id)_nextResponder changeModeWithEvent:e]; }
- (void)touchesBeganWithEvent:(NSEvent *)e { if (_nextResponder && [_nextResponder respondsToSelector:@selector(touchesBeganWithEvent:)]) [(id)_nextResponder touchesBeganWithEvent:e]; }
- (void)touchesMovedWithEvent:(NSEvent *)e { if (_nextResponder && [_nextResponder respondsToSelector:@selector(touchesMovedWithEvent:)]) [(id)_nextResponder touchesMovedWithEvent:e]; }
- (void)touchesEndedWithEvent:(NSEvent *)e { if (_nextResponder && [_nextResponder respondsToSelector:@selector(touchesEndedWithEvent:)]) [(id)_nextResponder touchesEndedWithEvent:e]; }
- (void)touchesCancelledWithEvent:(NSEvent *)e { if (_nextResponder && [_nextResponder respondsToSelector:@selector(touchesCancelledWithEvent:)]) [(id)_nextResponder touchesCancelledWithEvent:e]; }
- (void)quickLookWithEvent:(NSEvent *)e { if (_nextResponder && [_nextResponder respondsToSelector:@selector(quickLookWithEvent:)]) [(id)_nextResponder quickLookWithEvent:e]; }
- (void)pressureChangeWithEvent:(NSEvent *)e { if (_nextResponder && [_nextResponder respondsToSelector:@selector(pressureChangeWithEvent:)]) [(id)_nextResponder pressureChangeWithEvent:e]; }
- (void)contextMenuKeyDown:(NSEvent *)e { if (_nextResponder && [_nextResponder respondsToSelector:@selector(contextMenuKeyDown:)]) [(id)_nextResponder contextMenuKeyDown:e]; }
- (void)flushBufferedKeyEvents {} - (void)showContextHelp:(id)s {} - (void)helpRequested:(NSEvent *)e {}
- (BOOL)shouldBeTreatedAsInkEvent:(NSEvent *)e { return NO; }
- (BOOL)wantsScrollEventsForSwipeTrackingOnAxis:(NSInteger)a { return NO; } - (BOOL)wantsForwardedScrollEventsForAxis:(NSInteger)a { return NO; }
- (id)supplementalTargetForAction:(SEL)a sender:(id)s { return nil; }
- (BOOL)validateProposedFirstResponder:(NSResponder *)r forEvent:(NSEvent *)e { return YES; }
- (NSError *)willPresentError:(NSError *)e { return e; }
- (BOOL)presentError:(NSError *)e { NSLog(@"%@", e); return YES; }
- (void)presentError:(NSError *)e modalForWindow:(NSWindow *)w delegate:(id)d didPresentSelector:(SEL)s contextInfo:(void *)c {
  BOOL ok = [self presentError:e]; if ([d respondsToSelector:s]) ((void (*)(id, SEL, BOOL, void *))objc_msgSend)(d, s, ok, c); }
- (void)performTextFinderAction:(id)s {} - (void)newWindowForTab:(id)s {} - (void)showWritingTools:(id)s {}
- (id)makeTouchBar { return nil; } - (id)touchBar { return nil; } - (void)setTouchBar:(id)t {}
- (void)updateUserActivityState:(id)a {} - (id)userActivity { return props(self)[@"activity"]; } - (void)setUserActivity:(id)a { put(props(self), @"activity", a); }
- (void)restoreUserActivityState:(id)a {}
- (void)encodeRestorableStateWithCoder:(NSCoder *)c {} - (void)encodeRestorableStateWithCoder:(NSCoder *)c backgroundQueue:(id)q { [self encodeRestorableStateWithCoder:c]; }
- (void)restoreStateWithCoder:(NSCoder *)c {} - (void)invalidateRestorableState {}
+ (NSArray *)allowedClassesForRestorableStateKeyPath:(NSString *)k { return @[]; } + (NSArray *)restorableStateKeyPaths { return @[]; }
@end

/* ---- NSSplitViewItem: collapse behaviour, safe area, accessory controllers ---- */
@implementation NSSplitViewItem (XEFMore)
- (NSInteger)collapseBehavior { return [objc_getAssociatedObject(self, "xef.collapseB") integerValue]; } - (void)setCollapseBehavior:(NSInteger)b { objc_setAssociatedObject(self, "xef.collapseB", [NSNumber numberWithInteger:b], OBJC_ASSOCIATION_RETAIN); }
- (BOOL)canCollapseFromWindowResize { return [objc_getAssociatedObject(self, "xef.collapseR") boolValue]; } - (void)setCanCollapseFromWindowResize:(BOOL)f { objc_setAssociatedObject(self, "xef.collapseR", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); }
- (BOOL)automaticallyAdjustsSafeAreaInsets { return [objc_getAssociatedObject(self, "xef.safe") boolValue]; } - (void)setAutomaticallyAdjustsSafeAreaInsets:(BOOL)f { objc_setAssociatedObject(self, "xef.safe", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); }
- (NSMutableArray *)_xefAcc:(const char *)k { NSMutableArray *a = objc_getAssociatedObject(self, k); if (!a) { a = [NSMutableArray array]; objc_setAssociatedObject(self, k, a, OBJC_ASSOCIATION_RETAIN); } return a; }
- (NSArray *)topAlignedAccessoryViewControllers { return [NSArray arrayWithArray:[self _xefAcc:"xef.topAcc"]]; } - (void)setTopAlignedAccessoryViewControllers:(NSArray *)a { [[self _xefAcc:"xef.topAcc"] setArray:a ?: @[]]; }
- (NSArray *)bottomAlignedAccessoryViewControllers { return [NSArray arrayWithArray:[self _xefAcc:"xef.botAcc"]]; } - (void)setBottomAlignedAccessoryViewControllers:(NSArray *)a { [[self _xefAcc:"xef.botAcc"] setArray:a ?: @[]]; }
- (void)addTopAlignedAccessoryViewController:(id)c { [[self _xefAcc:"xef.topAcc"] addObject:c]; } - (void)insertTopAlignedAccessoryViewController:(id)c atIndex:(NSInteger)i { NSMutableArray *a = [self _xefAcc:"xef.topAcc"]; [a insertObject:c atIndex:MIN((NSUInteger)i, [a count])]; } - (void)removeTopAlignedAccessoryViewControllerAtIndex:(NSInteger)i { NSMutableArray *a = [self _xefAcc:"xef.topAcc"]; if (i >= 0 && i < (NSInteger)[a count]) [a removeObjectAtIndex:i]; }
- (void)addBottomAlignedAccessoryViewController:(id)c { [[self _xefAcc:"xef.botAcc"] addObject:c]; } - (void)insertBottomAlignedAccessoryViewController:(id)c atIndex:(NSInteger)i { NSMutableArray *a = [self _xefAcc:"xef.botAcc"]; [a insertObject:c atIndex:MIN((NSUInteger)i, [a count])]; } - (void)removeBottomAlignedAccessoryViewControllerAtIndex:(NSInteger)i { NSMutableArray *a = [self _xefAcc:"xef.botAcc"]; if (i >= 0 && i < (NSInteger)[a count]) [a removeObjectAtIndex:i]; }
- (id)animator { return self; } - (NSDictionary *)animations { return @{}; } - (void)setAnimations:(NSDictionary *)a {} - (id)animationForKey:(NSString *)k { return nil; } + (id)defaultAnimationForKey:(NSString *)k { return nil; }
@end
