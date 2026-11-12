/* AppKit-lite: NSToolbar / NSToolbarItem (the item model with the delegate protocol; the bar is not drawn),
 * NSAnimation, NSPopover, NSController / NSObjectController / NSArrayController (content, arrangement, selection; no
 * Cocoa bindings). Behaviour follows real AppKit as recorded by tests/darwin/mac/appkit_misc.m. */
#import "AppKitLite.h"
#import "AppKitGraphics.h"
#import "AppKitModel.h"
#include <math.h>

NSString *const NSToolbarWillAddItemNotification = @"NSToolbarWillAddItemNotification";
NSString *const NSToolbarDidRemoveItemNotification = @"NSToolbarDidRemoveItemNotification";
NSString *const NSPopoverWillShowNotification = @"NSPopoverWillShowNotification";
NSString *const NSPopoverDidShowNotification = @"NSPopoverDidShowNotification";
NSString *const NSPopoverWillCloseNotification = @"NSPopoverWillCloseNotification";
NSString *const NSPopoverDidCloseNotification = @"NSPopoverDidCloseNotification";

@interface NSObject (XEFModelInformal)
- (NSArray *)toolbarDefaultItemIdentifiers:(id)t; - (NSArray *)toolbarAllowedItemIdentifiers:(id)t; - (NSArray *)toolbarSelectableItemIdentifiers:(id)t;
- (NSToolbarItem *)toolbar:(id)t itemForItemIdentifier:(NSString *)i willBeInsertedIntoToolbar:(BOOL)f;
- (void)toolbarWillAddItem:(NSNotification *)n; - (void)toolbarDidRemoveItem:(NSNotification *)n;
- (BOOL)animationShouldStart:(id)a; - (void)animationDidEnd:(id)a; - (void)animationDidStop:(id)a; - (void)animation:(id)a didReachProgressMark:(float)p;
- (float)animation:(id)a valueForProgress:(float)p;
- (BOOL)validateToolbarItem:(id)i;
- (void)popoverWillShow:(NSNotification *)n; - (void)popoverDidShow:(NSNotification *)n; - (void)popoverWillClose:(NSNotification *)n; - (void)popoverDidClose:(NSNotification *)n;
- (BOOL)popoverShouldClose:(id)p; - (BOOL)popoverShouldDetach:(id)p;
@end

/* ================================================================== NSToolbarItem */
@implementation NSToolbarItem
- (id)initWithItemIdentifier:(NSString *)i {
  if ((self = [super init])) { _ident = [i copy]; _label = @""; _palette = nil; _tag = -1; _enabled = YES; _autovalidates = YES; _min = _max = NSMakeSize(32, 32); }
  return self; }
- (id)init { return [self initWithItemIdentifier:@""]; }
- (void)dealloc { [_ident release]; [_label release]; [_palette release]; [_tip release]; [_view release]; [_image release]; [_menu release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z {
  NSToolbarItem *c = [[[self class] allocWithZone:z] initWithItemIdentifier:_ident];
  c->_label = [_label copy]; c->_palette = [_palette copy]; c->_tip = [_tip copy]; c->_enabled = _enabled; c->_min = _min; c->_max = _max; c->_target = _target; c->_action = _action;
  c->_image = [_image retain]; c->_bordered = _bordered; c->_autovalidates = _autovalidates; c->_priority = _priority;
  return c; }
- (NSString *)itemIdentifier { return _ident; }
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)l { [_label release]; _label = [l copy] ?: @""; }
- (NSString *)paletteLabel { return _palette ?: _label; }
- (void)setPaletteLabel:(NSString *)l { [_palette release]; _palette = [l copy]; }
- (NSString *)toolTip { return _tip; } - (void)setToolTip:(NSString *)t { [_tip release]; _tip = [t copy]; }
- (NSInteger)tag { return _tag; } - (void)setTag:(NSInteger)t { _tag = t; }
- (BOOL)isEnabled { return _enabled; } - (void)setEnabled:(BOOL)f { _enabled = f; }
- (NSView *)view { return _view; } - (void)setView:(NSView *)v { [v retain]; [_view release]; _view = v; }
- (NSSize)minSize { return _min; } - (void)setMinSize:(NSSize)s { _min = s; }
- (NSSize)maxSize { return _max; } - (void)setMaxSize:(NSSize)s { _max = s; }
- (NSInteger)visibilityPriority { return _priority; } - (void)setVisibilityPriority:(NSInteger)p { _priority = p; }
- (id)target { return _target; } - (void)setTarget:(id)t { _target = t; }
- (SEL)action { return _action; } - (void)setAction:(SEL)a { _action = a; }
- (NSImage *)image { if (!_image) _image = [[NSImage alloc] initWithSize:NSZeroSize]; return _image; } - (void)setImage:(NSImage *)i { [i retain]; [_image release]; _image = i; }
- (BOOL)isBordered { return _bordered; } - (void)setBordered:(BOOL)f { _bordered = f; }
- (BOOL)autovalidates { return _autovalidates; } - (void)setAutovalidates:(BOOL)f { _autovalidates = f; }
- (BOOL)isNavigational { return _navigational; } - (void)setNavigational:(BOOL)f { _navigational = f; }
- (NSMenuItem *)menuFormRepresentation {
  if (_menu) return _menu;
  NSMenuItem *m = [[NSMenuItem alloc] initWithTitle:_label ?: @"" action:_action keyEquivalent:@""]; [m setTarget:_target]; _menu = m; return m; }
- (void)setMenuFormRepresentation:(NSMenuItem *)m { [m retain]; [_menu release]; _menu = m; }
- (id)toolbar { return _toolbar; }
- (void)validate { if (_autovalidates && _target && _action && [_target respondsToSelector:@selector(validateToolbarItem:)]) _enabled = [_target validateToolbarItem:self]; }
- (BOOL)allowsDuplicatesInToolbar { return NO; }
- (BOOL)isSpaceItem { return [_ident isEqual:@"NSToolbarSpaceItem"]; }
@end

@implementation NSToolbarItemGroup
- (id)initWithItemIdentifier:(NSString *)i { if ((self = [super initWithItemIdentifier:i])) { _selectedIndex = -1; } return self; }
- (void)dealloc { [_subitems release]; [super dealloc]; }
- (NSArray *)subitems { return _subitems ?: @[]; } - (void)setSubitems:(NSArray *)a { [a retain]; [_subitems release]; _subitems = a; }
- (NSInteger)selectionMode { return _selectionMode; } - (void)setSelectionMode:(NSInteger)m { _selectionMode = m; }
- (NSInteger)selectedIndex { return _selectedIndex; } - (void)setSelectedIndex:(NSInteger)i { _selectedIndex = i; }
- (NSInteger)controlRepresentation { return _representation; } - (void)setControlRepresentation:(NSInteger)r { _representation = r; }
- (BOOL)isSelectedAt:(NSInteger)i { return i == _selectedIndex; } - (void)setSelected:(BOOL)f atIndex:(NSInteger)i { if (f) _selectedIndex = i; else if (_selectedIndex == i) _selectedIndex = -1; }
@end

/* ================================================================== NSToolbar */
@implementation NSToolbar
- (id)initWithIdentifier:(NSString *)i { if ((self = [super init])) { _ident = [i copy]; _items = [[NSMutableArray alloc] init]; _display = 1; _size = 1; } return self; }
- (id)init { return [self initWithIdentifier:@""]; }
- (void)dealloc { [_ident release]; [_selected release]; [_items release]; [super dealloc]; }
- (NSString *)identifier { return _ident; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (NSArray *)items { return [NSArray arrayWithArray:_items]; }
- (NSArray *)visibleItems { return _window ? [self items] : @[]; }
- (NSInteger)displayMode { return _display; } - (void)setDisplayMode:(NSInteger)m { _display = m ? m : 1; }
- (NSInteger)sizeMode { return _size; } - (void)setSizeMode:(NSInteger)m {}
- (BOOL)isVisible { return _visible; } - (void)setVisible:(BOOL)f { _visible = f; }
- (BOOL)allowsUserCustomization { return _customizes; } - (void)setAllowsUserCustomization:(BOOL)f { _customizes = f; }
- (BOOL)autosavesConfiguration { return _autosaves; } - (void)setAutosavesConfiguration:(BOOL)f { _autosaves = f; }
- (BOOL)showsBaselineSeparator { return _baseline; } - (void)setShowsBaselineSeparator:(BOOL)f { _baseline = f; }
- (BOOL)allowsExtensionItems { return _extensions; } - (void)setAllowsExtensionItems:(BOOL)f { _extensions = f; }
- (BOOL)customizationPaletteIsRunning { return NO; } - (void)runCustomizationPalette:(id)s {}
- (NSString *)selectedItemIdentifier { return _selected; }
- (void)setSelectedItemIdentifier:(NSString *)i {
  if (!i) { [_selected release]; _selected = nil; return; }
  NSArray *ok = [_delegate respondsToSelector:@selector(toolbarSelectableItemIdentifiers:)] ? [_delegate toolbarSelectableItemIdentifiers:self] : nil;
  if ([ok containsObject:i]) { [i retain]; [_selected release]; _selected = i; } }
- (BOOL)_xefStandard:(NSString *)i { return [i hasPrefix:@"NSToolbar"] && [i hasSuffix:@"Item"]; }
- (NSToolbarItem *)_xefMakeItem:(NSString *)ident {
  NSToolbarItem *it = nil;
  if (![self _xefStandard:ident] && [_delegate respondsToSelector:@selector(toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:)])
    it = [_delegate toolbar:self itemForItemIdentifier:ident willBeInsertedIntoToolbar:YES];
  else if ([self _xefStandard:ident]) it = [[[NSToolbarItem alloc] initWithItemIdentifier:ident] autorelease];
  return it; }
- (void)insertItemWithItemIdentifier:(NSString *)ident atIndex:(NSInteger)idx {
  NSToolbarItem *it = [self _xefMakeItem:ident]; if (!it) return;
  it->_toolbar = self;
  [_items insertObject:it atIndex:idx < 0 ? 0 : idx > (NSInteger)[_items count] ? [_items count] : idx];
  NSNotification *n = [NSNotification notificationWithName:NSToolbarWillAddItemNotification object:self userInfo:@{ @"item": it }];
  if ([_delegate respondsToSelector:@selector(toolbarWillAddItem:)]) [_delegate toolbarWillAddItem:n];
  [[NSNotificationCenter defaultCenter] postNotification:n]; }
- (void)removeItemAtIndex:(NSInteger)idx {
  if (idx < 0 || idx >= (NSInteger)[_items count]) return;
  NSToolbarItem *it = [[_items[idx] retain] autorelease];
  [_items removeObjectAtIndex:idx]; it->_toolbar = nil;
  NSNotification *n = [NSNotification notificationWithName:NSToolbarDidRemoveItemNotification object:self userInfo:@{ @"item": it }];
  if ([_delegate respondsToSelector:@selector(toolbarDidRemoveItem:)]) [_delegate toolbarDidRemoveItem:n];
  [[NSNotificationCenter defaultCenter] postNotification:n]; }
- (void)validateVisibleItems { for (NSToolbarItem *i in _items) [i validate]; }
- (NSDictionary *)configurationDictionary { NSMutableArray *ids = [NSMutableArray array]; for (NSToolbarItem *i in _items) [ids addObject:[i itemIdentifier]]; return @{ @"TB Item Identifiers": ids, @"TB Display Mode": @(_display) }; }
- (void)setConfigurationFromDictionary:(NSDictionary *)d {
  while ([_items count]) [self removeItemAtIndex:0];
  for (NSString *i in d[@"TB Item Identifiers"]) [self insertItemWithItemIdentifier:i atIndex:[_items count]];
  if (d[@"TB Display Mode"]) _display = [d[@"TB Display Mode"] integerValue]; }
/* attached to a window: the default items are created and added */
- (void)_xefSetWindow:(NSWindow *)w {
  _window = w; if (!w) return;
  _visible = YES;
  if ([_items count] || ![_delegate respondsToSelector:@selector(toolbarDefaultItemIdentifiers:)]) return;
  for (NSString *i in [_delegate toolbarDefaultItemIdentifiers:self]) [self insertItemWithItemIdentifier:i atIndex:[_items count]]; }
@end

/* ================================================================== NSAnimation */
@implementation NSAnimation
- (id)initWithDuration:(NSTimeInterval)d animationCurve:(NSInteger)c { if ((self = [super init])) { _duration = d; _curve = c; _marks = [[NSMutableArray alloc] init]; } return self; }
- (id)init { return [self initWithDuration:0.5 animationCurve:0]; }
- (void)dealloc { [_timer invalidate]; [_marks release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { NSAnimation *c = [[[self class] allocWithZone:z] initWithDuration:_duration animationCurve:_curve]; c->_frameRate = _frameRate; c->_blocking = _blocking; c->_delegate = _delegate; [c->_marks setArray:_marks]; return c; }
- (NSTimeInterval)duration { return _duration; } - (void)setDuration:(NSTimeInterval)d { _duration = d; }
- (NSInteger)animationCurve { return _curve; } - (void)setAnimationCurve:(NSInteger)c { _curve = c; }
- (float)frameRate { return _frameRate; } - (void)setFrameRate:(float)r { _frameRate = r; }
- (NSInteger)animationBlockingMode { return _blocking; } - (void)setAnimationBlockingMode:(NSInteger)m { _blocking = m; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (BOOL)isAnimating { return _running; }
- (float)currentProgress { return _progress; }
- (void)setCurrentProgress:(float)p { _progress = p < 0 ? 0 : p > 1 ? 1 : p; }
- (float)currentValue {
  float p = _progress;
  if (_running && [_delegate respondsToSelector:@selector(animation:valueForProgress:)]) return [_delegate animation:self valueForProgress:p];
  switch (_curve) {
    case 0: return (1 - cosf(p * M_PI)) / 2; case 1: return 1 - cosf(p * M_PI / 2); case 2: return sinf(p * M_PI / 2); default: return p; } }
- (NSArray *)progressMarks { return [NSArray arrayWithArray:_marks]; }
- (void)setProgressMarks:(NSArray *)a { [_marks removeAllObjects]; for (NSNumber *n in a) [self addProgressMark:[n floatValue]]; }
- (void)addProgressMark:(float)p {
  NSNumber *n = @(p); NSUInteger i = 0; while (i < [_marks count] && [_marks[i] floatValue] < p) i++;
  if (i < [_marks count] && [_marks[i] floatValue] == p) return;
  [_marks insertObject:n atIndex:i]; }
- (void)removeProgressMark:(float)p { for (NSNumber *n in [[_marks copy] autorelease]) if ([n floatValue] == p) [_marks removeObject:n]; }
- (void)_xefFinish:(BOOL)completed {
  [_timer invalidate]; _timer = nil; _running = NO;
  if (completed) { _progress = 1; if ([_delegate respondsToSelector:@selector(animationDidEnd:)]) [_delegate animationDidEnd:self]; }
  else if ([_delegate respondsToSelector:@selector(animationDidStop:)]) [_delegate animationDidStop:self]; }
- (void)_xefTick {
  if (!_running) return;
  NSTimeInterval t = [NSDate timeIntervalSinceReferenceDate] - _start;
  float p = _duration > 0 ? (float)(t / _duration) : 1; if (p > 1) p = 1;
  _progress = p;
  while (_nextMark < (NSInteger)[_marks count] && [_marks[_nextMark] floatValue] <= p) {
    float m = [_marks[_nextMark++] floatValue];
    if ([_delegate respondsToSelector:@selector(animation:didReachProgressMark:)]) [_delegate animation:self didReachProgressMark:m]; }
  if (p >= 1) [self _xefFinish:YES]; }
- (void)startAnimation {
  if (_running) return;
  if ([_delegate respondsToSelector:@selector(animationShouldStart:)] && ![_delegate animationShouldStart:self]) return;
  _running = YES; _progress = 0; _nextMark = 0; _start = [NSDate timeIntervalSinceReferenceDate];
  [[self retain] autorelease];
  if (_duration <= 0) { [self _xefTick]; return; }
  if (_blocking == 0) {
    while (_running) { [self _xefTick]; if (_running) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.004]]; }
  } else {
    _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / (_frameRate > 0 ? _frameRate : 60) target:self selector:@selector(_xefTick) userInfo:nil repeats:YES]; } }
- (void)stopAnimation { if (_running) [self _xefFinish:NO]; }
@end

/* ================================================================== NSPopover */
@implementation NSPopover
- (id)init { if ((self = [super init])) { _animates = YES; } return self; }
- (void)dealloc { [_vc release]; [_window release]; [_appearance release]; [super dealloc]; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (id)contentViewController { return _vc; } - (void)setContentViewController:(id)vc { [vc retain]; [_vc release]; _vc = vc; }
- (NSSize)contentSize { return _size.width > 0 || _size.height > 0 || !_vc ? _size : [[_vc view] frame].size; } - (void)setContentSize:(NSSize)s { _size = s; }
- (NSRect)positioningRect { return _rect; } - (void)setPositioningRect:(NSRect)r { _rect = r; }
- (BOOL)animates { return _animates; } - (void)setAnimates:(BOOL)f { _animates = f; }
- (NSInteger)behavior { return _behavior; } - (void)setBehavior:(NSInteger)b { _behavior = b; }
- (id)appearance { return _appearance; } - (void)setAppearance:(id)a { [a retain]; [_appearance release]; _appearance = a; }
- (BOOL)isShown { return _shown; } - (BOOL)isDetached { return _detached; }
- (void)_xefPost:(NSString *)name selector:(SEL)sel { NSNotification *n = [NSNotification notificationWithName:name object:self]; if ([_delegate respondsToSelector:sel]) [_delegate performSelector:sel withObject:n]; [[NSNotificationCenter defaultCenter] postNotification:n]; }
- (void)showRelativeToRect:(NSRect)r ofView:(NSView *)v preferredEdge:(NSInteger)edge {
  if (_shown) return;
  if (!NSIsEmptyRect(r)) _rect = r;
  _positioningView = v;
  NSView *content = [_vc view]; NSSize s = [self contentSize]; if (!content) return;
  if (s.width <= 0 || s.height <= 0) s = [content frame].size;
  [self _xefPost:NSPopoverWillShowNotification selector:@selector(popoverWillShow:)];
  NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, s.width, s.height) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  [w setReleasedWhenClosed:NO]; [content setFrame:NSMakeRect(0, 0, s.width, s.height)]; [w setContentView:content];
  NSWindow *host = [v window];
  if (host) { NSRect hf = [host frame], vr = [v convertRect:_rect toView:nil]; [w setFrameOrigin:NSMakePoint(hf.origin.x + vr.origin.x, hf.origin.y + vr.origin.y - s.height)]; }
  _window = w; _shown = YES; [w makeKeyAndOrderFront:nil];
  [self _xefPost:NSPopoverDidShowNotification selector:@selector(popoverDidShow:)]; }
- (void)close {
  if (!_shown) return;
  [self _xefPost:NSPopoverWillCloseNotification selector:@selector(popoverWillClose:)];
  [_window orderOut:nil]; [_window release]; _window = nil; _shown = NO;
  [self _xefPost:NSPopoverDidCloseNotification selector:@selector(popoverDidClose:)]; }
- (void)performClose:(id)s { if (!_shown) return; if ([_delegate respondsToSelector:@selector(popoverShouldClose:)] && ![_delegate popoverShouldClose:self]) return; [self close]; }
@end

/* ================================================================== controllers */
/* what valueForKey: of NSController.selection reaches: the selected object (the first one of several) */
@interface XEFSelectionProxy : NSObject { @public NSObjectController *_c; }
@end
@implementation XEFSelectionProxy
- (id)_object { return [[_c selectedObjects] firstObject]; }
- (id)valueForKey:(NSString *)k { return [[self _object] valueForKey:k]; }
- (void)setValue:(id)v forKey:(NSString *)k { [[self _object] setValue:v forKey:k]; }
- (id)valueForKeyPath:(NSString *)k { return [[self _object] valueForKeyPath:k]; }
- (id)forwardingTargetForSelector:(SEL)s { return [self _object]; }
@end

/* NSPredicate evaluation without NSInvocation (which this runtime lacks on arm64): comparison and compound predicates
 * over key paths and constants, the operators applications use. Anything else falls back to the framework. */
static id xef_expr_value(NSExpression *e, id obj) {
  switch ([e expressionType]) {
    case 0: return [e constantValue];
    case 1: return obj;
    case 3: return [obj valueForKeyPath:[e keyPath]];
    default: return [e expressionValueWithObject:obj context:nil]; } }
static BOOL xef_eval(NSPredicate *p, id obj) {
  if ([p isKindOfClass:[NSCompoundPredicate class]]) {
    NSCompoundPredicate *c = (NSCompoundPredicate *)p; NSArray *subs = [c subpredicates]; NSUInteger t = [c compoundPredicateType];
    if (t == 0) return !subs.count ? YES : !xef_eval(subs[0], obj);                       /* NOT */
    if (t == 1) { for (NSPredicate *q in subs) if (!xef_eval(q, obj)) return NO; return YES; }
    for (NSPredicate *q in subs) if (xef_eval(q, obj)) return YES; return NO; }
  if ([p isKindOfClass:[NSComparisonPredicate class]]) {
    NSComparisonPredicate *c = (NSComparisonPredicate *)p; id l = xef_expr_value([c leftExpression], obj), r = xef_expr_value([c rightExpression], obj);
    BOOL ci = ([c options] & 1) != 0;
    NSInteger cmp = NSOrderedSame;
    BOOL ordered = [l respondsToSelector:@selector(compare:)] && r != nil && l != nil;
    if (ordered) { cmp = ci && [l isKindOfClass:[NSString class]] ? [l caseInsensitiveCompare:r] : [l compare:r]; }
    switch ([c predicateOperatorType]) {
      case 0: return ordered && cmp == NSOrderedAscending; case 1: return ordered && cmp != NSOrderedDescending;
      case 2: return ordered && cmp == NSOrderedDescending; case 3: return ordered && cmp != NSOrderedAscending;
      case 4: return l == r || (ordered ? cmp == NSOrderedSame : [l isEqual:r]); case 5: return !(l == r || (ordered ? cmp == NSOrderedSame : [l isEqual:r]));
      case 8: return [l isKindOfClass:[NSString class]] && [l rangeOfString:r options:ci ? NSCaseInsensitiveSearch : 0].location == 0 && [r length] > 0 ? YES : ([l hasPrefix:r]);
      case 9: return [l hasSuffix:r];
      case 99: if ([l isKindOfClass:[NSString class]]) return [l rangeOfString:r options:ci ? NSCaseInsensitiveSearch : 0].location != NSNotFound; return [l containsObject:r];
      case 10: return [r containsObject:l];
      case 100: return [l containsObject:r];
      default: break; } }
  return [p evaluateWithObject:obj]; }

@implementation NSController
- (id)initWithCoder:(NSCoder *)c { return [self init]; } - (void)encodeWithCoder:(NSCoder *)c {}
- (BOOL)commitEditing { _editing = NO; return YES; } - (void)discardEditing { _editing = NO; } - (BOOL)isEditing { return _editing; }
- (void)objectDidBeginEditing:(id)e { _editing = YES; } - (void)objectDidEndEditing:(id)e { _editing = NO; }
- (BOOL)commitEditingAndReturnError:(NSError **)e { return [self commitEditing]; }
@end

@implementation NSObjectController
- (id)init { return [self initWithContent:nil]; }
- (id)initWithContent:(id)c { if ((self = [super init])) { _class = [NSMutableDictionary class]; _editable = YES; [self setContent:c]; } return self; }
- (id)initWithCoder:(NSCoder *)c { if ((self = [self initWithContent:nil])) { _prepares = [c decodeBoolForKey:@"NSAutomaticallyPreparesContent"]; } return self; }
- (void)dealloc { [_content release]; if (_selectionProxy) ((XEFSelectionProxy *)_selectionProxy)->_c = nil; [_selectionProxy release]; [super dealloc]; }
- (id)content { return _content; }
- (void)setContent:(id)c { [self willChangeValueForKey:@"content"]; [c retain]; [_content release]; _content = c; [self didChangeValueForKey:@"content"]; }
- (id)selection { if (!_selectionProxy) { _selectionProxy = [[XEFSelectionProxy alloc] init]; ((XEFSelectionProxy *)_selectionProxy)->_c = self; } return _selectionProxy; }
- (NSArray *)selectedObjects { return _content ? @[_content] : @[]; }
- (Class)objectClass { return _class; } - (void)setObjectClass:(Class)c { _class = c; }
- (BOOL)isEditable { return _editable; } - (void)setEditable:(BOOL)f { _editable = f; }
- (BOOL)automaticallyPreparesContent { return _prepares; } - (void)setAutomaticallyPreparesContent:(BOOL)f { _prepares = f; }
- (BOOL)usesLazyFetching { return _usesLazy; } - (void)setUsesLazyFetching:(BOOL)f { _usesLazy = f; }
- (BOOL)canAdd { return _editable && !_content; }
- (BOOL)canRemove { return _editable && _content != nil; }
- (id)newObject { return [[[_class alloc] init] autorelease]; }
- (void)addObject:(id)o { [self setContent:o]; }
- (void)removeObject:(id)o { if (o == _content) [self setContent:nil]; }
- (void)add:(id)s { if ([self canAdd]) [self addObject:[self newObject]]; }
- (void)remove:(id)s { if ([self canRemove]) [self setContent:nil]; }
- (void)prepareContent {} - (void)fetch:(id)s {} - (BOOL)fetchWithRequest:(id)r merge:(BOOL)m error:(NSError **)e { return YES; }
- (id)managedObjectContext { return nil; }
@end

@implementation NSArrayController
- (void)_xefInit { _arranged = [[NSMutableArray alloc] init]; _sel = [[NSMutableIndexSet alloc] init]; _preserves = YES; _selectsInserted = YES; _avoidsEmpty = YES; _clearsFilter = YES; }
- (id)initWithContent:(id)c { if ((self = [super initWithContent:nil])) { [self _xefInit]; [self setContent:c ?: @[]]; } return self; }
- (void)dealloc { [_arranged release]; [_sel release]; [_sorts release]; [_filter release]; [super dealloc]; }
- (NSMutableArray *)_mutableContent { if (![_content isKindOfClass:[NSMutableArray class]]) { NSMutableArray *m = [NSMutableArray arrayWithArray:_content ?: @[]]; [_content release]; _content = [m retain]; } return _content; }
/* filter, then sort; the selection follows its objects, then the rules for an empty selection apply */
- (NSArray *)arrangeObjects:(NSArray *)objs {
  NSArray *r = objs;
  if (_filter) { NSMutableArray *kept = [NSMutableArray array]; for (id o in r) if (xef_eval(_filter, o)) [kept addObject:o]; r = kept; }
  if ([_sorts count]) r = [r sortedArrayUsingDescriptors:_sorts];
  return r; }
- (void)rearrangeObjects {
  NSMutableArray *selected = [NSMutableArray array];
  if (_preserves) [_sel enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *st) { if (i < [_arranged count]) [selected addObject:_arranged[i]]; }];
  [self willChangeValueForKey:@"arrangedObjects"];
  [_arranged setArray:[self arrangeObjects:_content ?: @[]]];
  [_sel removeAllIndexes];
  for (id o in selected) { NSUInteger i = [_arranged indexOfObjectIdenticalTo:o]; if (i != NSNotFound) [_sel addIndex:i]; }
  [self didChangeValueForKey:@"arrangedObjects"]; }
- (void)setContent:(id)c {
  if (!_arranged) { [super setContent:c]; return; }
  [super setContent:c];
  [self rearrangeObjects];
  if (![_sel count] && _avoidsEmpty && [_arranged count]) [_sel addIndex:0]; }
- (NSArray *)arrangedObjects { return [NSArray arrayWithArray:_arranged]; }
- (NSIndexSet *)selectionIndexes { return [[_sel copy] autorelease]; }
- (NSUInteger)selectionIndex { return [_sel count] ? [_sel firstIndex] : NSNotFound; }
- (BOOL)setSelectionIndexes:(NSIndexSet *)s {
  NSMutableIndexSet *n = [NSMutableIndexSet indexSet];
  [s enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *st) { if (i < [_arranged count]) [n addIndex:i]; }];
  [self willChangeValueForKey:@"selectionIndexes"]; [_sel removeAllIndexes]; [_sel addIndexes:n]; [self didChangeValueForKey:@"selectionIndexes"];
  return YES; }
- (BOOL)setSelectionIndex:(NSUInteger)i { return [self setSelectionIndexes:i == NSNotFound ? [NSIndexSet indexSet] : [NSIndexSet indexSetWithIndex:i]]; }
- (BOOL)addSelectionIndexes:(NSIndexSet *)s { NSMutableIndexSet *n = [[_sel mutableCopy] autorelease]; [n addIndexes:s]; return [self setSelectionIndexes:n]; }
- (BOOL)removeSelectionIndexes:(NSIndexSet *)s { NSMutableIndexSet *n = [[_sel mutableCopy] autorelease]; [n removeIndexes:s]; return [self setSelectionIndexes:n]; }
- (NSArray *)selectedObjects { NSMutableArray *a = [NSMutableArray array]; [_sel enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *st) { if (i < [_arranged count]) [a addObject:_arranged[i]]; }]; return a; }
- (BOOL)setSelectedObjects:(NSArray *)objs {
  NSMutableIndexSet *n = [NSMutableIndexSet indexSet];
  for (id o in objs) { NSUInteger i = [_arranged indexOfObjectIdenticalTo:o]; if (i != NSNotFound) [n addIndex:i]; }
  return [self setSelectionIndexes:n]; }
- (BOOL)addSelectedObjects:(NSArray *)objs { NSMutableArray *a = [NSMutableArray arrayWithArray:[self selectedObjects]]; [a addObjectsFromArray:objs]; return [self setSelectedObjects:a]; }
- (BOOL)removeSelectedObjects:(NSArray *)objs { NSMutableArray *a = [NSMutableArray arrayWithArray:[self selectedObjects]]; [a removeObjectsInArray:objs]; return [self setSelectedObjects:a]; }
- (NSArray *)sortDescriptors { return _sorts ?: @[]; } - (void)setSortDescriptors:(NSArray *)a { [a retain]; [_sorts release]; _sorts = a; [self rearrangeObjects]; }
- (NSPredicate *)filterPredicate { return _filter; } - (void)setFilterPredicate:(NSPredicate *)p { [p retain]; [_filter release]; _filter = p; [self rearrangeObjects]; }
- (BOOL)preservesSelection { return _preserves; } - (void)setPreservesSelection:(BOOL)f { _preserves = f; }
- (BOOL)selectsInsertedObjects { return _selectsInserted; } - (void)setSelectsInsertedObjects:(BOOL)f { _selectsInserted = f; }
- (BOOL)avoidsEmptySelection { return _avoidsEmpty; } - (void)setAvoidsEmptySelection:(BOOL)f { _avoidsEmpty = f; }
- (BOOL)clearsFilterPredicateOnInsertion { return _clearsFilter; } - (void)setClearsFilterPredicateOnInsertion:(BOOL)f { _clearsFilter = f; }
- (BOOL)automaticallyRearrangesObjects { return _rearranges; } - (void)setAutomaticallyRearrangesObjects:(BOOL)f { _rearranges = f; }
- (BOOL)alwaysUsesMultipleValuesMarker { return NO; } - (void)setAlwaysUsesMultipleValuesMarker:(BOOL)f {}
- (NSArray *)automaticRearrangementKeyPaths { return @[]; }
- (BOOL)canAdd { return _editable; } - (BOOL)canInsert { return _editable; }
- (BOOL)canRemove { return _editable && [_sel count] > 0; }
- (BOOL)canSelectNext { return [_sel count] && [_sel lastIndex] + 1 < [_arranged count]; } - (BOOL)canSelectPrevious { return [_sel count] && [_sel firstIndex] > 0; }
- (id)selection { return [super selection]; }
- (void)selectNext:(id)s { if ([self canSelectNext]) [self setSelectionIndex:[_sel lastIndex] + 1]; }
- (void)selectPrevious:(id)s { if ([self canSelectPrevious]) [self setSelectionIndex:[_sel firstIndex] - 1]; }
/* adding and removing: a new object goes where it is put, not where the sort would place it, until the next rearrange */
- (void)insertObject:(id)o atArrangedObjectIndex:(NSUInteger)i {
  if (!o) return;
  if (_filter && _clearsFilter) { [_filter release]; _filter = nil; [self rearrangeObjects]; }
  NSMutableArray *content = [self _mutableContent]; if (i > [_arranged count]) i = [_arranged count];
  NSUInteger at = i < [_arranged count] ? [content indexOfObjectIdenticalTo:_arranged[i]] : [content count]; if (at == NSNotFound) at = [content count];
  [self willChangeValueForKey:@"arrangedObjects"];
  [content insertObject:o atIndex:at]; [_arranged insertObject:o atIndex:i];
  NSMutableIndexSet *shifted = [[_sel mutableCopy] autorelease]; [shifted shiftIndexesStartingAtIndex:i by:1];
  [_sel removeAllIndexes]; [_sel addIndexes:shifted];
  [self didChangeValueForKey:@"arrangedObjects"];
  if (_rearranges) [self rearrangeObjects];
  if (_selectsInserted) { NSUInteger k = [_arranged indexOfObjectIdenticalTo:o]; if (k != NSNotFound) [self setSelectionIndex:k]; } }
- (void)addObject:(id)o { [self insertObject:o atArrangedObjectIndex:[_arranged count]]; }
- (void)addObjects:(NSArray *)a { for (id o in a) [self addObject:o]; }
- (void)insert:(id)s { if ([self canInsert]) { NSUInteger i = [_sel count] ? [_sel firstIndex] : [_arranged count]; [self insertObject:[self newObject] atArrangedObjectIndex:i]; } }
- (void)add:(id)s { if ([self canAdd]) [self addObject:[self newObject]]; }
- (void)removeObjectsAtArrangedObjectIndexes:(NSIndexSet *)idx {
  if (![idx count]) return;
  NSMutableArray *gone = [NSMutableArray array];
  [idx enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *st) { if (i < [_arranged count]) [gone addObject:_arranged[i]]; }];
  NSUInteger first = [_sel count] ? [_sel firstIndex] : 0; BOOL hadSelection = [_sel count] > 0;
  NSMutableIndexSet *keep = [[_sel mutableCopy] autorelease];
  [self willChangeValueForKey:@"arrangedObjects"];
  NSMutableArray *content = [self _mutableContent];
  for (id o in gone) { NSUInteger k = [content indexOfObjectIdenticalTo:o]; if (k != NSNotFound) [content removeObjectAtIndex:k]; }
  [idx enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger i, BOOL *st) { if (i < [_arranged count]) { [_arranged removeObjectAtIndex:i]; [keep removeIndex:i]; [keep shiftIndexesStartingAtIndex:i + 1 by:-1]; } }];
  [_sel removeAllIndexes]; [_sel addIndexes:keep];
  [self didChangeValueForKey:@"arrangedObjects"];
  if (![_sel count] && hadSelection && _avoidsEmpty && [_arranged count]) [_sel addIndex:MIN(first, [_arranged count] - 1)]; }
- (void)removeObjects:(NSArray *)a { for (id o in a) [self removeObject:o]; }
- (void)removeObject:(id)o { NSUInteger i = [_arranged indexOfObjectIdenticalTo:o]; if (i != NSNotFound) [self removeObjectsAtArrangedObjectIndexes:[NSIndexSet indexSetWithIndex:i]]; }
- (void)remove:(id)s { if ([self canRemove]) [self removeObjectsAtArrangedObjectIndexes:_sel]; }
- (id)newObject { return [[[_class alloc] init] autorelease]; }
@end
