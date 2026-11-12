/* AppKit-lite: NSToolbar / NSToolbarItem (the item model with the delegate protocol; the bar is not drawn),
 * NSAnimation, NSPopover, NSController / NSObjectController / NSArrayController (content, arrangement, selection; no
 * Cocoa bindings). Behaviour follows real AppKit as recorded by tests/darwin/mac/appkit_misc.m. */
#import "AppKitLite.h"
#import "AppKitGraphics.h"
#import "AppKitModel.h"
#include <objc/runtime.h>
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
  if (_filter) r = [r filteredArrayUsingPredicate:_filter];
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


/* ================================================================== NSGridView */
#define kAutoSize 1.17549435e-38f      /* NSGridViewSizeForContent: FLT_MIN */
@implementation NSGridCell
- (id)init { if ((self = [super init])) { _cols = NSMakeRange(0, 1); _rows = NSMakeRange(0, 1); } return self; }
- (void)dealloc { [_content release]; [_custom release]; [super dealloc]; }
+ (NSView *)emptyContentView { static NSView *v; if (!v) v = [[NSView alloc] initWithFrame:NSZeroRect]; return v; }
- (NSView *)contentView { return _content; }
- (void)setContentView:(NSView *)v {
  if (v == _content) return;
  NSGridView *g = _row ? _row->_grid : nil;
  if (_content && [_content superview] == g) [_content removeFromSuperview];
  [v retain]; [_content release]; _content = v;
  if (v && g && v != [NSGridCell emptyContentView]) [g addSubview:v];
  [g setNeedsLayout:YES]; [g invalidateIntrinsicContentSize]; }
- (NSGridRow *)row { return _row; } - (NSGridColumn *)column { return _column; }
- (NSInteger)xPlacement { return _x; } - (void)setXPlacement:(NSInteger)p { _x = p; [_row->_grid setNeedsLayout:YES]; }
- (NSInteger)yPlacement { return _y; } - (void)setYPlacement:(NSInteger)p { _y = p; [_row->_grid setNeedsLayout:YES]; }
- (NSInteger)rowAlignment { return _rowAlign; } - (void)setRowAlignment:(NSInteger)a { _rowAlign = a; }
- (NSArray *)customPlacementConstraints { return _custom ?: @[]; } - (void)setCustomPlacementConstraints:(NSArray *)a { [a retain]; [_custom release]; _custom = a; }
@end
@implementation NSGridRow
- (id)init { if ((self = [super init])) { _cells = [[NSMutableArray alloc] init]; _height = kAutoSize; } return self; }
- (void)dealloc { [_cells release]; [super dealloc]; }
- (NSGridView *)gridView { return _grid; }
- (NSInteger)numberOfCells { return [_cells count]; } - (NSGridCell *)cellAtIndex:(NSInteger)i { return i >= 0 && i < (NSInteger)[_cells count] ? _cells[i] : nil; }
- (CGFloat)height { return _height; } - (void)setHeight:(CGFloat)h { _height = h; [_grid setNeedsLayout:YES]; [_grid invalidateIntrinsicContentSize]; }
- (BOOL)isHidden { return _hidden; } - (void)setHidden:(BOOL)f { _hidden = f; [_grid _xefApplyHidden]; }
- (CGFloat)topPadding { return _top; } - (void)setTopPadding:(CGFloat)p { _top = p; [_grid setNeedsLayout:YES]; [_grid invalidateIntrinsicContentSize]; }
- (CGFloat)bottomPadding { return _bottom; } - (void)setBottomPadding:(CGFloat)p { _bottom = p; [_grid setNeedsLayout:YES]; [_grid invalidateIntrinsicContentSize]; }
- (NSInteger)yPlacement { return _y; } - (void)setYPlacement:(NSInteger)p { _y = p; [_grid setNeedsLayout:YES]; }
- (NSInteger)rowAlignment { return _align; } - (void)setRowAlignment:(NSInteger)a { _align = a; }
- (void)mergeCellsInRange:(NSRange)r { NSInteger i = [_grid->_grows indexOfObjectIdenticalTo:self]; [_grid mergeCellsInHorizontalRange:r verticalRange:NSMakeRange(i, 1)]; }
@end
@implementation NSGridColumn
- (id)init { if ((self = [super init])) { _width = kAutoSize; } return self; }
- (NSGridView *)gridView { return _grid; }
- (NSInteger)numberOfCells { return [_grid->_grows count]; }
- (NSGridCell *)cellAtIndex:(NSInteger)i { NSInteger c = [_grid->_gcols indexOfObjectIdenticalTo:self]; return [_grid cellAtColumnIndex:c rowIndex:i]; }
- (CGFloat)width { return _width; } - (void)setWidth:(CGFloat)w { _width = w; [_grid setNeedsLayout:YES]; [_grid invalidateIntrinsicContentSize]; }
- (BOOL)isHidden { return _hidden; } - (void)setHidden:(BOOL)f { _hidden = f; [_grid _xefApplyHidden]; }
- (CGFloat)leadingPadding { return _lead; } - (void)setLeadingPadding:(CGFloat)p { _lead = p; [_grid setNeedsLayout:YES]; [_grid invalidateIntrinsicContentSize]; }
- (CGFloat)trailingPadding { return _trail; } - (void)setTrailingPadding:(CGFloat)p { _trail = p; [_grid setNeedsLayout:YES]; [_grid invalidateIntrinsicContentSize]; }
- (NSInteger)xPlacement { return _x; } - (void)setXPlacement:(NSInteger)p { _x = p; [_grid setNeedsLayout:YES]; }
- (void)mergeCellsInRange:(NSRange)r { NSInteger i = [_grid->_gcols indexOfObjectIdenticalTo:self]; [_grid mergeCellsInHorizontalRange:NSMakeRange(i, 1) verticalRange:r]; }
@end

@implementation NSGridView
- (void)_xefGridInit { _grows = [[NSMutableArray alloc] init]; _gcols = [[NSMutableArray alloc] init]; _x = 2; _y = 2; _align = 1; _rowSpacing = _colSpacing = 6; }
- (id)initWithFrame:(NSRect)f { if ((self = [super initWithFrame:f])) [self _xefGridInit]; return self; }
- (id)initWithCoder:(NSCoder *)c { if ((self = [super initWithCoder:c])) [self _xefGridInit]; return self; }
- (void)dealloc { [_grows release]; [_gcols release]; [super dealloc]; }
+ (NSGridView *)gridViewWithNumberOfColumns:(NSInteger)c rows:(NSInteger)r {
  NSGridView *g = [[[self alloc] initWithFrame:NSZeroRect] autorelease];
  for (NSInteger i = 0; i < c; i++) [g addColumnWithViews:@[]];
  for (NSInteger i = 0; i < r; i++) [g addRowWithViews:@[]];
  return g; }
+ (NSGridView *)gridViewWithViews:(NSArray *)rows {
  NSGridView *g = [[[self alloc] initWithFrame:NSZeroRect] autorelease];
  for (NSArray *row in rows) [g addRowWithViews:row];
  return g; }
- (BOOL)isFlipped { return NO; }
- (NSInteger)numberOfRows { return [_grows count]; } - (NSInteger)numberOfColumns { return [_gcols count]; }
- (NSGridRow *)rowAtIndex:(NSInteger)i { return i >= 0 && i < (NSInteger)[_grows count] ? _grows[i] : nil; }
- (NSGridColumn *)columnAtIndex:(NSInteger)i { return i >= 0 && i < (NSInteger)[_gcols count] ? _gcols[i] : nil; }
- (NSInteger)indexOfRow:(NSGridRow *)r { NSUInteger i = [_grows indexOfObjectIdenticalTo:r]; return i == NSNotFound ? NSNotFound : (NSInteger)i; }
- (NSInteger)indexOfColumn:(NSGridColumn *)c { NSUInteger i = [_gcols indexOfObjectIdenticalTo:c]; return i == NSNotFound ? NSNotFound : (NSInteger)i; }
- (NSGridCell *)cellAtColumnIndex:(NSInteger)c rowIndex:(NSInteger)r {
  if (r < 0 || r >= (NSInteger)[_grows count]) return nil;
  NSGridRow *row = _grows[r]; return c >= 0 && c < (NSInteger)[row->_cells count] ? row->_cells[c] : nil; }
- (NSGridCell *)cellForView:(NSView *)v { for (NSGridRow *r in _grows) for (NSGridCell *c in r->_cells) if (c->_content == v) return c; return nil; }
- (NSGridCell *)_xefNewCellRow:(NSGridRow *)r column:(NSGridColumn *)c view:(id)v {
  NSGridCell *cell = [[[NSGridCell alloc] init] autorelease]; cell->_row = r; cell->_column = c;
  if ([v isKindOfClass:[NSView class]] && v != [NSGridCell emptyContentView]) { cell->_content = [v retain]; if ([(NSView *)v superview] != self) [self addSubview:v]; }
  return cell; }
- (void)_xefChanged { [self setNeedsLayout:YES]; [self invalidateIntrinsicContentSize]; }
- (NSGridRow *)insertRowAtIndex:(NSInteger)idx withViews:(NSArray *)views {
  while ((NSInteger)[views count] > (NSInteger)[_gcols count]) [self addColumnWithViews:@[]];
  NSGridRow *row = [[[NSGridRow alloc] init] autorelease]; row->_grid = self;
  for (NSUInteger c = 0; c < [_gcols count]; c++) [row->_cells addObject:[self _xefNewCellRow:row column:_gcols[c] view:c < [views count] ? views[c] : nil]];
  [_grows insertObject:row atIndex:idx < 0 ? 0 : idx > (NSInteger)[_grows count] ? [_grows count] : idx];
  [self _xefChanged]; return row; }
- (NSGridRow *)addRowWithViews:(NSArray *)views { return [self insertRowAtIndex:[_grows count] withViews:views]; }
- (void)removeRowAtIndex:(NSInteger)i {
  NSGridRow *r = [self rowAtIndex:i]; if (!r) return;
  for (NSGridCell *c in r->_cells) if (c->_content && [c->_content superview] == self && c->_row == r) [c->_content removeFromSuperview];
  [_grows removeObjectAtIndex:i]; [self _xefChanged]; }
- (void)moveRowAtIndex:(NSInteger)from toIndex:(NSInteger)to {
  NSGridRow *r = [[[self rowAtIndex:from] retain] autorelease]; if (!r) return;
  [_grows removeObjectAtIndex:from]; [_grows insertObject:r atIndex:to < 0 ? 0 : to > (NSInteger)[_grows count] ? [_grows count] : to]; [self _xefChanged]; }
- (NSGridColumn *)insertColumnAtIndex:(NSInteger)idx withViews:(NSArray *)views {
  while ((NSInteger)[views count] > (NSInteger)[_grows count]) [self addRowWithViews:@[]];
  NSGridColumn *col = [[[NSGridColumn alloc] init] autorelease]; col->_grid = self;
  NSInteger at = idx < 0 ? 0 : idx > (NSInteger)[_gcols count] ? [_gcols count] : idx;
  [_gcols insertObject:col atIndex:at];
  for (NSUInteger r = 0; r < [_grows count]; r++) { NSGridRow *row = _grows[r]; [row->_cells insertObject:[self _xefNewCellRow:row column:col view:r < [views count] ? views[r] : nil] atIndex:at]; }
  [self _xefChanged]; return col; }
- (NSGridColumn *)addColumnWithViews:(NSArray *)views { return [self insertColumnAtIndex:[_gcols count] withViews:views]; }
- (void)removeColumnAtIndex:(NSInteger)i {
  NSGridColumn *col = [self columnAtIndex:i]; if (!col) return;
  for (NSGridRow *r in _grows) { NSGridCell *c = r->_cells[i]; if (c->_content && [c->_content superview] == self && c->_column == col) [c->_content removeFromSuperview]; [r->_cells removeObjectAtIndex:i]; }
  [_gcols removeObjectAtIndex:i]; [self _xefChanged]; }
- (void)moveColumnAtIndex:(NSInteger)from toIndex:(NSInteger)to {
  NSGridColumn *col = [[[self columnAtIndex:from] retain] autorelease]; if (!col) return;
  NSInteger at = to < 0 ? 0 : to >= (NSInteger)[_gcols count] ? [_gcols count] - 1 : to;
  [_gcols removeObjectAtIndex:from]; [_gcols insertObject:col atIndex:at];
  for (NSGridRow *r in _grows) { id c = [[r->_cells[from] retain] autorelease]; [r->_cells removeObjectAtIndex:from]; [r->_cells insertObject:c atIndex:at]; }
  [self _xefChanged]; }
- (NSInteger)xPlacement { return _x; } - (void)setXPlacement:(NSInteger)p { _x = p; [self setNeedsLayout:YES]; }
- (NSInteger)yPlacement { return _y; } - (void)setYPlacement:(NSInteger)p { _y = p; [self setNeedsLayout:YES]; }
- (NSInteger)rowAlignment { return _align; } - (void)setRowAlignment:(NSInteger)a { _align = a; }
- (CGFloat)rowSpacing { return _rowSpacing; } - (void)setRowSpacing:(CGFloat)s { _rowSpacing = s; [self _xefChanged]; }
- (CGFloat)columnSpacing { return _colSpacing; } - (void)setColumnSpacing:(CGFloat)s { _colSpacing = s; [self _xefChanged]; }
/* merging: every position of the block holds the top-left cell, which remembers the block */
- (void)mergeCellsInHorizontalRange:(NSRange)h verticalRange:(NSRange)v {
  if (!h.length || !v.length || NSMaxRange(h) > [_gcols count] || NSMaxRange(v) > [_grows count]) return;
  NSGridCell *top = [self cellAtColumnIndex:h.location rowIndex:v.location];
  for (NSUInteger r = v.location; r < NSMaxRange(v); r++) for (NSUInteger c = h.location; c < NSMaxRange(h); c++) {
    NSGridCell *old = [self cellAtColumnIndex:c rowIndex:r];
    if (old != top) { if (old->_content && [old->_content superview] == self) [old->_content removeFromSuperview]; [((NSGridRow *)_grows[r])->_cells replaceObjectAtIndex:c withObject:top]; } }
  top->_cols = h; top->_rows = v; [self _xefChanged]; }
- (void)_xefApplyHidden {
  for (NSUInteger r = 0; r < [_grows count]; r++) for (NSUInteger c = 0; c < [_gcols count]; c++) {
    NSGridCell *cell = [self cellAtColumnIndex:c rowIndex:r]; if (!cell->_content) continue;
    BOOL hide = [_grows[r] isHidden] || [_gcols[c] isHidden]; [cell->_content setHidden:hide]; }
  [self _xefChanged]; }
/* ---- layout */
static NSSize content_size(NSGridCell *c) {
  NSView *v = c->_content; if (!v || [v isHidden]) return NSZeroSize;
  NSSize s = [v intrinsicContentSize]; NSSize f = [v frame].size;
  return NSMakeSize(s.width >= 0 ? s.width : f.width, s.height >= 0 ? s.height : f.height); }
- (BOOL)_xefVisibleRow:(NSInteger)r { return ![_grows[r] isHidden]; } - (BOOL)_xefVisibleCol:(NSInteger)c { return ![_gcols[c] isHidden]; }
/* column widths and row heights (zero for hidden ones); spanning cells do not contribute */
- (void)_xefMeasure:(CGFloat *)widths heights:(CGFloat *)heights {
  NSInteger nr = [_grows count], nc = [_gcols count];
  for (NSInteger c = 0; c < nc; c++) {
    NSGridColumn *col = _gcols[c]; if (col->_hidden) { widths[c] = 0; continue; }
    CGFloat w = 0;
    if (col->_width != kAutoSize) w = col->_width;
    else for (NSInteger r = 0; r < nr; r++) { if (![self _xefVisibleRow:r]) continue; NSGridCell *cell = [self cellAtColumnIndex:c rowIndex:r]; if (cell->_cols.length > 1) continue; w = fmax(w, content_size(cell).width); }
    widths[c] = w + col->_lead + col->_trail; }
  for (NSInteger r = 0; r < nr; r++) {
    NSGridRow *row = _grows[r]; if (row->_hidden) { heights[r] = 0; continue; }
    CGFloat h = 0;
    if (row->_height != kAutoSize) h = row->_height;
    else for (NSInteger c = 0; c < nc; c++) { if (![self _xefVisibleCol:c]) continue; NSGridCell *cell = [self cellAtColumnIndex:c rowIndex:r]; if (cell->_rows.length > 1) continue; h = fmax(h, content_size(cell).height); }
    heights[r] = h + row->_top + row->_bottom; } }
- (NSSize)_xefTotal:(CGFloat *)w heights:(CGFloat *)h {
  CGFloat tw = 0, th = 0; NSInteger vc = 0, vr = 0;
  for (NSUInteger c = 0; c < [_gcols count]; c++) if ([self _xefVisibleCol:c]) { tw += w[c]; vc++; }
  for (NSUInteger r = 0; r < [_grows count]; r++) if ([self _xefVisibleRow:r]) { th += h[r]; vr++; }
  return NSMakeSize(tw + (vc > 1 ? (vc - 1) * _colSpacing : 0), th + (vr > 1 ? (vr - 1) * _rowSpacing : 0)); }
- (NSSize)intrinsicContentSize {
  NSInteger nr = [_grows count], nc = [_gcols count];
  CGFloat *w = calloc(nc + 1, sizeof(CGFloat)), *h = calloc(nr + 1, sizeof(CGFloat));
  [self _xefMeasure:w heights:h]; NSSize s = [self _xefTotal:w heights:h]; free(w); free(h); return s; }
- (NSSize)fittingSize { return [self intrinsicContentSize]; }
- (void)layout {
  NSInteger nr = [_grows count], nc = [_gcols count]; if (!nr || !nc) return;
  CGFloat *w = calloc(nc + 1, sizeof(CGFloat)), *h = calloc(nr + 1, sizeof(CGFloat)), *x = calloc(nc + 1, sizeof(CGFloat)), *y = calloc(nr + 1, sizeof(CGFloat));
  [self _xefMeasure:w heights:h];
  CGFloat cx = 0, cy = 0; BOOL firstC = YES, firstR = YES;
  for (NSInteger c = 0; c < nc; c++) { if (![self _xefVisibleCol:c]) { x[c] = cx; continue; } if (!firstC) cx += _colSpacing; firstC = NO; x[c] = cx; cx += w[c]; }
  for (NSInteger r = 0; r < nr; r++) { if (![self _xefVisibleRow:r]) { y[r] = cy; continue; } if (!firstR) cy += _rowSpacing; firstR = NO; y[r] = cy; cy += h[r]; }
  CGFloat top = _bounds.size.height;
  NSMutableSet *done = [NSMutableSet set];
  for (NSInteger r = 0; r < nr; r++) for (NSInteger c = 0; c < nc; c++) {
    NSGridCell *cell = [self cellAtColumnIndex:c rowIndex:r];
    if ([done containsObject:cell] || !cell->_content || [cell->_content isHidden]) continue;
    [done addObject:cell];
    NSRange cr = cell->_cols.length > 1 ? cell->_cols : NSMakeRange(c, 1), rr = cell->_rows.length > 1 ? cell->_rows : NSMakeRange(r, 1);
    NSInteger c1 = NSMaxRange(cr) - 1, r1 = NSMaxRange(rr) - 1;
    CGFloat ax = x[cr.location] + ((NSGridColumn *)_gcols[cr.location])->_lead, aw = x[c1] + w[c1] - ((NSGridColumn *)_gcols[c1])->_trail - ax;
    CGFloat ay = y[rr.location] + ((NSGridRow *)_grows[rr.location])->_top, ah = y[r1] + h[r1] - ((NSGridRow *)_grows[r1])->_bottom - ay;
    NSSize cs = content_size(cell);
    NSInteger xp = cell->_x ?: ((NSGridColumn *)_gcols[cr.location])->_x ?: _x, yp = cell->_y ?: ((NSGridRow *)_grows[rr.location])->_y ?: _y;
    CGFloat fw = xp == 5 ? aw : cs.width, fh = yp == 5 ? ah : cs.height, fx = ax, fy = ay;
    if (xp == 3) fx = ax + aw - fw; else if (xp == 4) fx = ax + (aw - fw) / 2;
    if (yp == 3) fy = ay + ah - fh; else if (yp == 4) fy = ay + (ah - fh) / 2;
    [cell->_content setFrame:NSMakeRect(fx, top - fy - fh, fw, fh)]; }
  free(w); free(h); free(x); free(y); }
- (void)setFrame:(NSRect)f { [super setFrame:f]; [self setNeedsLayout:YES]; }
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; [self setNeedsLayout:YES]; }
@end


/* ================================================================== NSMatrix */
@implementation NSMatrix
+ (Class)cellClass { return nil; }
- (void)_xefInit { _cells = [[NSMutableArray alloc] init]; _selected = [[NSMutableArray alloc] init]; _selRow = _selCol = -1; _spacing = NSMakeSize(1, 1); _enabled = YES; _cellClass = [NSActionCell class]; }
- (id)initWithFrame:(NSRect)f { if ((self = [super initWithFrame:f])) [self _xefInit]; return self; }
- (NSCell *)_xefNewCell { return _proto ? [[_proto copy] autorelease] : [[[_cellClass alloc] initTextCell:@""] autorelease]; }
- (void)_xefResizeCells {
  if (!_sizeSet) {
    NSSize c = _proto ? [_proto cellSize] : NSZeroSize;
    _cellSize = _proto && c.width > 0 ? c : NSMakeSize(_cols ? (_frame.size.width - (_cols - 1) * _spacing.width) / _cols : 0, _rows ? (_frame.size.height - (_rows - 1) * _spacing.height) / _rows : 0); } }
- (id)initWithFrame:(NSRect)f mode:(NSInteger)mode prototype:(NSCell *)proto numberOfRows:(NSInteger)r numberOfColumns:(NSInteger)c {
  if ((self = [self initWithFrame:f])) {
    _mode = mode; _proto = [proto copy]; _cellClass = nil; _allowsEmpty = mode != 0;
    [self renewRows:r columns:c]; [self _xefResizeCells];
    if (mode == 0 && [_cells count]) [self selectCellAtRow:0 column:0]; }
  return self; }
- (id)initWithFrame:(NSRect)f mode:(NSInteger)mode cellClass:(Class)cls numberOfRows:(NSInteger)r numberOfColumns:(NSInteger)c {
  if ((self = [self initWithFrame:f])) {
    _mode = mode; _cellClass = cls ?: [NSActionCell class]; _allowsEmpty = mode != 0;
    [self renewRows:r columns:c]; [self _xefResizeCells];
    if (mode == 0 && [_cells count]) [self selectCellAtRow:0 column:0]; }
  return self; }
- (id)initWithCoder:(NSCoder *)c {
  if ((self = [super initWithCoder:c])) {
    [self _xefInit];
    _rows = [c decodeIntegerForKey:@"NSNumRows"]; _cols = [c decodeIntegerForKey:@"NSNumCols"];
    for (id cell in [c decodeObjectForKey:@"NSCells"] ?: @[]) if ([cell isKindOfClass:[NSCell class]]) [_cells addObject:cell];
    id proto = [c decodeObjectForKey:@"NSProtoCell"]; if ([proto isKindOfClass:[NSCell class]]) _proto = [proto retain];
    if ([c containsValueForKey:@"NSCellSize"]) { _cellSize = [c decodeSizeForKey:@"NSCellSize"]; _sizeSet = YES; }
    if ([c containsValueForKey:@"NSIntercellSpacing"]) _spacing = [c decodeSizeForKey:@"NSIntercellSpacing"];
    uint32_t fl = (uint32_t)[c decodeIntForKey:@"NSMatrixFlags"]; _mode = (fl & 0x40000000u) ? 0 : (fl & 0x20000000u) ? 1 : (fl & 0x10000000u) ? 2 : 3; _allowsEmpty = (fl & 0x80000000u) != 0;
    id sel = [c decodeObjectForKey:@"NSSelectedCell"]; if (sel && [_cells containsObject:sel]) { NSInteger i = [_cells indexOfObjectIdenticalTo:sel]; if (_cols) [self selectCellAtRow:i / _cols column:i % _cols]; }
    [self _xefResizeCells]; }
  return self; }
- (void)dealloc { [_cells release]; [_selected release]; [_proto release]; [super dealloc]; }
- (BOOL)isFlipped { return YES; }
- (NSInteger)numberOfRows { return _rows; } - (NSInteger)numberOfColumns { return _cols; }
- (NSArray *)cells { return [NSArray arrayWithArray:_cells]; }
- (NSInteger)mode { return _mode; } - (void)setMode:(NSInteger)m { _mode = m; }
- (Class)cellClass { return _cellClass; } - (void)setCellClass:(Class)c { _cellClass = c; }
- (id)prototype { return _proto; } - (void)setPrototype:(NSCell *)p { [p retain]; [_proto release]; _proto = p; }
- (BOOL)allowsEmptySelection { return _allowsEmpty; } - (void)setAllowsEmptySelection:(BOOL)f { _allowsEmpty = f; }
- (BOOL)autosizesCells { return _autosizes; } - (void)setAutosizesCells:(BOOL)f { _autosizes = f; }
- (BOOL)isSelectionByRect { return YES; } - (void)setSelectionByRect:(BOOL)f {}
- (NSSize)cellSize { return _cellSize; } - (void)setCellSize:(NSSize)s { _cellSize = s; _sizeSet = YES; [self setNeedsDisplay:YES]; }
- (NSSize)intercellSpacing { return _spacing; } - (void)setIntercellSpacing:(NSSize)s { _spacing = s; [self setNeedsDisplay:YES]; }
- (void)sizeToCells { [self setFrameSize:NSMakeSize(_cols * _cellSize.width + (_cols > 1 ? (_cols - 1) * _spacing.width : 0), _rows * _cellSize.height + (_rows > 1 ? (_rows - 1) * _spacing.height : 0)) ]; }
- (void)setFrameSize:(NSSize)s {
  [super setFrameSize:s];
  if (_autosizes && _rows && _cols) { _cellSize = NSMakeSize((s.width - (_cols - 1) * _spacing.width) / _cols, (s.height - (_rows - 1) * _spacing.height) / _rows); _sizeSet = YES; } }
- (NSCell *)cellAtRow:(NSInteger)r column:(NSInteger)c {
  if (r < 0 || c < 0 || r >= _rows || c >= _cols) return nil;
  NSInteger i = r * _cols + c; return i < (NSInteger)[_cells count] ? _cells[i] : nil; }
- (NSRect)cellFrameAtRow:(NSInteger)r column:(NSInteger)c { return NSMakeRect(c * (_cellSize.width + _spacing.width), r * (_cellSize.height + _spacing.height), _cellSize.width, _cellSize.height); }
- (BOOL)getRow:(NSInteger *)row column:(NSInteger *)col forPoint:(NSPoint)p {
  for (NSInteger r = 0; r < _rows; r++) for (NSInteger c = 0; c < _cols; c++) if (NSPointInRect(p, [self cellFrameAtRow:r column:c])) { if (row) *row = r; if (col) *col = c; return YES; }
  if (row) *row = -1; if (col) *col = -1; return NO; }
- (BOOL)getRow:(NSInteger *)row column:(NSInteger *)col ofCell:(NSCell *)cell {
  NSUInteger i = [_cells indexOfObjectIdenticalTo:cell]; if (i == NSNotFound || !_cols || (NSInteger)i >= _rows * _cols) { if (row) *row = -1; if (col) *col = -1; return NO; }
  if (row) *row = i / _cols; if (col) *col = i % _cols; return YES; }
- (NSCell *)cellWithTag:(NSInteger)t { for (NSCell *c in _cells) if ([c tag] == t) return c; return nil; }
- (void)putCell:(NSCell *)cell atRow:(NSInteger)r column:(NSInteger)c {
  if (r < 0 || c < 0 || r >= _rows || c >= _cols) return;
  NSInteger i = r * _cols + c; if (i >= (NSInteger)[_cells count]) return;
  NSCell *old = _cells[i]; [_selected removeObjectIdenticalTo:old]; [cell setControlView:self]; [_cells replaceObjectAtIndex:i withObject:cell]; [self setNeedsDisplay:YES]; }
/* edits: the cells are rebuilt from the first rows * cols entries (a renew to fewer rows or columns keeps the old storage) */
- (NSMutableArray *)_xefGrid { NSMutableArray *g = [NSMutableArray array]; for (NSInteger r = 0; r < _rows; r++) { NSMutableArray *row = [NSMutableArray array]; for (NSInteger c = 0; c < _cols; c++) { NSInteger i = r * _cols + c; [row addObject:i < (NSInteger)[_cells count] ? _cells[i] : [self _xefNewCell]]; } [g addObject:row]; } return g; }
- (void)_xefStore:(NSArray *)grid cols:(NSInteger)cols {
  NSMutableArray *flat = [NSMutableArray array]; for (NSArray *row in grid) [flat addObjectsFromArray:row];
  NSUInteger keep = [flat count]; for (NSUInteger i = keep; i < [_cells count] && ![flat count]; i++) {}
  [_cells setArray:flat]; _rows = [grid count]; _cols = cols; for (NSCell *c in _cells) [c setControlView:self];
  [_selected filterUsingPredicate:[NSPredicate predicateWithFormat:@"SELF IN %@", _cells]]; [self setNeedsDisplay:YES]; }
- (void)renewRows:(NSInteger)r columns:(NSInteger)c {
  NSInteger need = r * c; NSInteger oldRows = _rows, oldCols = _cols;
  if (oldCols == c && oldRows <= r) { while ((NSInteger)[_cells count] < need) { NSCell *cell = [self _xefNewCell]; [cell setControlView:self]; [_cells addObject:cell]; } _rows = r; return; }
  NSMutableArray *old = [NSMutableArray arrayWithArray:_cells];
  while ((NSInteger)[_cells count] < need) { NSCell *cell = [self _xefNewCell]; [cell setControlView:self]; [_cells addObject:cell]; }
  _rows = r; _cols = c; (void)old; for (NSCell *cell in _cells) [cell setControlView:self]; }
- (NSCell *)_xefMakeCell { NSCell *c = [self _xefNewCell]; [c setControlView:self]; return c; }
- (void)insertRow:(NSInteger)i {
  NSMutableArray *g = [self _xefGrid]; NSMutableArray *row = [NSMutableArray array]; for (NSInteger c = 0; c < _cols; c++) [row addObject:[self _xefMakeCell]];
  [g insertObject:row atIndex:i < 0 ? 0 : i > (NSInteger)[g count] ? [g count] : i]; [self _xefStore:g cols:_cols]; }
- (void)addRow { [self insertRow:_rows]; }
- (void)removeRow:(NSInteger)i { NSMutableArray *g = [self _xefGrid]; if (i < 0 || i >= (NSInteger)[g count]) return; [g removeObjectAtIndex:i]; [self _xefStore:g cols:_cols]; }
- (void)insertColumn:(NSInteger)i {
  NSMutableArray *g = [self _xefGrid]; for (NSMutableArray *row in g) [row insertObject:[self _xefMakeCell] atIndex:i < 0 ? 0 : i > (NSInteger)[row count] ? [row count] : i];
  [self _xefStore:g cols:_cols + 1]; }
- (void)addColumn { [self insertColumn:_cols]; }
- (void)removeColumn:(NSInteger)i { NSMutableArray *g = [self _xefGrid]; if (i < 0 || i >= _cols) return; for (NSMutableArray *row in g) [row removeObjectAtIndex:i]; [self _xefStore:g cols:_cols - 1]; }
/* ---- selection */
- (void)_xefSelect:(NSCell *)cell row:(NSInteger)r column:(NSInteger)c extend:(BOOL)extend {
  if (!extend) { for (NSCell *o in _selected) [o setState:0]; [_selected removeAllObjects]; }
  if (cell) { [cell setState:1]; if (![_selected containsObject:cell]) [_selected addObject:cell]; }
  _selRow = r; _selCol = c; [self setNeedsDisplay:YES]; }
- (void)selectCellAtRow:(NSInteger)r column:(NSInteger)c {
  NSCell *cell = [self cellAtRow:r column:c];
  if (!cell) { if (_allowsEmpty || _mode != 0) [self _xefSelect:nil row:-1 column:-1 extend:NO]; return; }
  [self _xefSelect:cell row:r column:c extend:NO]; }
- (BOOL)selectCellWithTag:(NSInteger)t {
  NSCell *cell = [self cellWithTag:t]; if (!cell) return NO;
  NSInteger r, c; [self getRow:&r column:&c ofCell:cell]; [self _xefSelect:cell row:r column:c extend:NO]; return YES; }
- (void)deselectAllCells { if (_mode == 0 && !_allowsEmpty) return; [self _xefSelect:nil row:-1 column:-1 extend:NO]; }
- (void)deselectSelectedCell { [self deselectAllCells]; }
- (void)selectAll:(id)s { for (NSCell *c in _cells) { [c setState:1]; if (![_selected containsObject:c]) [_selected addObject:c]; } [self setNeedsDisplay:YES]; }
- (NSCell *)selectedCell { return [_selected lastObject]; }
- (NSArray *)selectedCells { return [NSArray arrayWithArray:_selected]; }
- (NSInteger)selectedRow { return _selRow; } - (NSInteger)selectedColumn { return _selCol; }
/* ---- target and action belong to the matrix (the cells keep their own) */
- (id)target { return _target; } - (void)setTarget:(id)t { _target = t; }
- (SEL)action { return _action; } - (void)setAction:(SEL)a { _action = a; }
- (SEL)doubleAction { return _doubleAction; } - (void)setDoubleAction:(SEL)a { _doubleAction = a; }
- (BOOL)isEnabled { return _enabled; } - (void)setEnabled:(BOOL)f { _enabled = f; [self setNeedsDisplay:YES]; }
- (BOOL)sendAction:(SEL)a to:(id)t { return a ? [NSApp sendAction:a to:t from:self] : NO; }
- (void)sendAction { if (_action) [self sendAction:_action to:_target]; }
- (void)sendDoubleAction { if (_doubleAction) [self sendAction:_doubleAction to:_target]; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return YES; }
- (void)drawRect:(NSRect)r {
  if ([objc_getAssociatedObject(self, "xef.drawsBg") boolValue]) { [(NSColor *)objc_getAssociatedObject(self, "xef.bg") set]; NSRectFill([self bounds]); }
  BOOL cb = [objc_getAssociatedObject(self, "xef.drawsCellBg") boolValue];
  for (NSInteger i = 0; i < _rows; i++) for (NSInteger j = 0; j < _cols; j++) { NSCell *c = [self cellAtRow:i column:j]; if (!c) continue; if (cb) { [(NSColor *)objc_getAssociatedObject(self, "xef.cellBg") set]; NSRectFill([self cellFrameAtRow:i column:j]); } [c drawWithFrame:[self cellFrameAtRow:i column:j] inView:self]; } }
- (void)mouseDown:(NSEvent *)e {
  if (!_enabled) return;
  NSInteger r, c; NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
  if (![self getRow:&r column:&c forPoint:p]) return;
  NSCell *cell = [self cellAtRow:r column:c]; if (![cell isEnabled]) return;
  if (_mode == 0) { [self _xefSelect:cell row:r column:c extend:NO]; }
  else if (_mode == 2) { BOOL ext = ([e modifierFlags] & (NSEventModifierFlagShift | NSEventModifierFlagCommand)) != 0; [self _xefSelect:cell row:r column:c extend:ext]; }
  else { [cell setHighlighted:YES]; _selRow = r; _selCol = c; [self setNeedsDisplay:YES]; }
  XEFRedrawWindowNow(_window);
  for (;;) { NSEvent *n = XEFNextTrackingEvent(); if (n && [n type] == NSEventTypeLeftMouseUp) break; }
  if (_mode == 1 || _mode == 3) { [cell setHighlighted:NO]; if (_mode == 1 && [cell state] == 0) {} }
  if ([cell action] && [cell target]) [self sendAction:[cell action] to:[cell target]];
  else if ([e clickCount] >= 2 && _doubleAction) [self sendDoubleAction];
  else [self sendAction]; }
@end


/* ================================================================== NSCollectionView */
@interface NSObject (XEFCollectionInformal)
- (NSInteger)numberOfSectionsInCollectionView:(id)cv; - (NSInteger)collectionView:(id)cv numberOfItemsInSection:(NSInteger)s;
- (NSCollectionViewItem *)collectionView:(id)cv itemForRepresentedObjectAtIndexPath:(NSIndexPath *)p;
- (BOOL)collectionView:(id)cv shouldSelectItemsAtIndexPaths:(NSSet *)p; - (void)collectionView:(id)cv didSelectItemsAtIndexPaths:(NSSet *)p;
- (BOOL)collectionView:(id)cv shouldDeselectItemsAtIndexPaths:(NSSet *)p; - (void)collectionView:(id)cv didDeselectItemsAtIndexPaths:(NSSet *)p;
- (NSSize)collectionView:(id)cv layout:(id)l sizeForItemAtIndexPath:(NSIndexPath *)p;
@end

@implementation NSIndexPath (XEFCollection)
+ (NSIndexPath *)indexPathForItem:(NSInteger)i inSection:(NSInteger)s { NSUInteger idx[2] = { (NSUInteger)s, (NSUInteger)i }; return [NSIndexPath indexPathWithIndexes:idx length:2]; }
- (NSInteger)section { return [self length] > 0 ? (NSInteger)[self indexAtPosition:0] : 0; }
- (NSInteger)item { return [self length] > 1 ? (NSInteger)[self indexAtPosition:1] : 0; }
@end

@implementation NSCollectionViewLayoutAttributes
+ (id)layoutAttributesForItemWithIndexPath:(NSIndexPath *)p { NSCollectionViewLayoutAttributes *a = [[[self alloc] init] autorelease]; a->_path = [p retain]; return a; }
- (id)init { if ((self = [super init])) { _alpha = 1; } return self; }
- (id)copyWithZone:(NSZone *)z { NSCollectionViewLayoutAttributes *a = [[[self class] allocWithZone:z] init]; a->_frame = _frame; a->_path = [_path retain]; a->_zIndex = _zIndex; a->_hidden = _hidden; a->_alpha = _alpha; return a; }
- (void)dealloc { [_path release]; [_kind release]; [super dealloc]; }
- (NSRect)frame { return _frame; } - (void)setFrame:(NSRect)f { _frame = f; }
- (NSSize)size { return _frame.size; } - (void)setSize:(NSSize)s { _frame.size = s; }
- (NSPoint)center { return NSMakePoint(NSMidX(_frame), NSMidY(_frame)); } - (void)setCenter:(NSPoint)c { _frame.origin = NSMakePoint(c.x - _frame.size.width / 2, c.y - _frame.size.height / 2); }
- (NSIndexPath *)indexPath { return _path; } - (void)setIndexPath:(NSIndexPath *)p { [p retain]; [_path release]; _path = p; }
- (NSInteger)zIndex { return _zIndex; } - (void)setZIndex:(NSInteger)z { _zIndex = z; }
- (BOOL)isHidden { return _hidden; } - (void)setHidden:(BOOL)f { _hidden = f; }
- (CGFloat)alpha { return _alpha; } - (void)setAlpha:(CGFloat)a { _alpha = a; }
- (NSInteger)representedElementCategory { return _category; } - (NSString *)representedElementKind { return _kind; }
@end

@implementation NSCollectionViewLayout
- (NSCollectionView *)collectionView { return _cv; }
- (NSSize)collectionViewContentSize { return NSZeroSize; }
- (void)invalidateLayout { _valid = NO; [_cv setNeedsLayout:YES]; }
- (void)prepareLayout {}
- (NSCollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)p { return nil; }
- (NSArray *)layoutAttributesForElementsInRect:(NSRect)r { return @[]; }
- (BOOL)shouldInvalidateLayoutForBoundsChange:(NSRect)b { return YES; }
@end

@implementation NSCollectionViewFlowLayout
- (id)init { if ((self = [super init])) { _item = NSMakeSize(50, 50); _line = _inter = 10; } return self; }
- (void)dealloc { [_attrs release]; [super dealloc]; }
- (NSSize)itemSize { return _item; } - (void)setItemSize:(NSSize)s { _item = s; [self invalidateLayout]; }
- (CGFloat)minimumLineSpacing { return _line; } - (void)setMinimumLineSpacing:(CGFloat)v { _line = v; [self invalidateLayout]; }
- (CGFloat)minimumInteritemSpacing { return _inter; } - (void)setMinimumInteritemSpacing:(CGFloat)v { _inter = v; [self invalidateLayout]; }
- (NSEdgeInsets)sectionInset { return _inset; } - (void)setSectionInset:(NSEdgeInsets)i { _inset = i; [self invalidateLayout]; }
- (NSInteger)scrollDirection { return _dir; } - (void)setScrollDirection:(NSInteger)d { _dir = d; [self invalidateLayout]; }
- (NSSize)headerReferenceSize { return _header; } - (void)setHeaderReferenceSize:(NSSize)s { _header = s; [self invalidateLayout]; }
- (NSSize)footerReferenceSize { return _footer; } - (void)setFooterReferenceSize:(NSSize)s { _footer = s; [self invalidateLayout]; }
- (NSSize)estimatedItemSize { return _estimated; } - (void)setEstimatedItemSize:(NSSize)s { _estimated = s; }
- (BOOL)sectionHeadersPinToVisibleBounds { return _pin; } - (void)setSectionHeadersPinToVisibleBounds:(BOOL)f { _pin = f; }
- (BOOL)sectionFootersPinToVisibleBounds { return NO; } - (void)setSectionFootersPinToVisibleBounds:(BOOL)f {}
- (NSSize)_xefSizeFor:(NSIndexPath *)p { id d = [_cv delegate]; return [d respondsToSelector:@selector(collectionView:layout:sizeForItemAtIndexPath:)] ? [d collectionView:_cv layout:self sizeForItemAtIndexPath:p] : _item; }
/* items flow along the scroll direction's cross axis, as many per line as fit; the leftover space is shared between them */
- (void)_xefPrepare {
  if (_valid || !_cv) return;
  [_attrs release]; _attrs = [[NSMutableArray alloc] init];
  NSSize bounds = [_cv bounds].size; BOOL vert = _dir == 0;
  CGFloat cross = vert ? bounds.width : bounds.height, along = 0;
  NSInteger sections = [_cv numberOfSections];
  for (NSInteger s = 0; s < sections; s++) {
    NSInteger count = [_cv numberOfItemsInSection:s];
    CGFloat leadIn = vert ? _inset.top : _inset.left, leadOut = vert ? _inset.bottom : _inset.right, crossIn = vert ? _inset.left : _inset.top, crossOut = vert ? _inset.right : _inset.bottom;
    CGFloat usable = cross - crossIn - crossOut;
    along += leadIn + (vert ? _header.height : _header.width);
    NSSize first = count ? [self _xefSizeFor:[NSIndexPath indexPathForItem:0 inSection:s]] : _item;
    CGFloat ic = vert ? first.width : first.height, il = vert ? first.height : first.width;
    NSInteger n = ic > 0 ? (NSInteger)floor((usable + _inter) / (ic + _inter)) : 1; if (n < 1) n = 1;
    CGFloat gap = n > 1 ? (usable - n * ic) / (n - 1) : 0; if (gap < _inter) gap = _inter;
    NSInteger lines = count ? (count + n - 1) / n : 0;
    for (NSInteger i = 0; i < count; i++) {
      NSIndexPath *p = [NSIndexPath indexPathForItem:i inSection:s]; NSSize sz = [self _xefSizeFor:p];
      NSInteger line = i / n, pos = i % n;
      CGFloat a = along + line * (il + _line), c = crossIn + pos * (ic + gap);
      NSCollectionViewLayoutAttributes *at = [NSCollectionViewLayoutAttributes layoutAttributesForItemWithIndexPath:p];
      at->_frame = vert ? NSMakeRect(c, a, sz.width, sz.height) : NSMakeRect(a, c, sz.width, sz.height);
      [_attrs addObject:at]; }
    along += lines * il + (lines > 1 ? (lines - 1) * _line : 0) + leadOut + (vert ? _footer.height : _footer.width); }
  _content = vert ? NSMakeSize(cross, along) : NSMakeSize(along, cross);
  _valid = YES; }
- (NSSize)collectionViewContentSize { [self _xefPrepare]; return _content; }
- (void)prepareLayout { _valid = NO; [self _xefPrepare]; }
- (NSCollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)p {
  [self _xefPrepare];
  for (NSCollectionViewLayoutAttributes *a in _attrs) if ([a->_path isEqual:p]) return a;
  NSCollectionViewLayoutAttributes *a = [NSCollectionViewLayoutAttributes layoutAttributesForItemWithIndexPath:p]; a->_frame = NSMakeRect(0, 0, _item.width, _item.height); return a; }
- (NSArray *)layoutAttributesForElementsInRect:(NSRect)r {
  [self _xefPrepare]; NSMutableArray *out = [NSMutableArray array];
  for (NSCollectionViewLayoutAttributes *a in _attrs) if (NSIntersectsRect(a->_frame, r)) [out addObject:a];
  return out; }
- (void)invalidateLayout { [super invalidateLayout]; }
@end

@implementation NSCollectionViewItem
- (BOOL)isSelected { return _selected; }
- (void)setSelected:(BOOL)f { _selected = f; }
- (NSInteger)highlightState { return _highlight; } - (void)setHighlightState:(NSInteger)s { _highlight = s; }
- (NSCollectionView *)collectionView { return _cv; }
- (id)imageView { return _imageView; } - (void)setImageView:(id)v { _imageView = v; }
- (id)textField { return _textField; } - (void)setTextField:(id)v { _textField = v; }
- (NSArray *)draggingImageComponents { return @[]; }
@end

@implementation NSCollectionView
- (void)_xefInit { _classes = [[NSMutableDictionary alloc] init]; _nibs = [[NSMutableDictionary alloc] init]; _visible = [[NSMutableDictionary alloc] init]; _reuse = [[NSMutableDictionary alloc] init];
  _selection = [[NSMutableSet alloc] init]; _empty = YES; _sections = -1; _bg = [@[[NSColor controlBackgroundColor]] retain]; }
- (id)initWithFrame:(NSRect)f { if ((self = [super initWithFrame:f])) [self _xefInit]; return self; }
- (id)initWithCoder:(NSCoder *)c { if ((self = [super initWithCoder:c])) { [self _xefInit]; _selectable = [c decodeBoolForKey:@"NSSelectable"]; _multiple = [c decodeBoolForKey:@"NSAllowsMultipleSelection"]; } return self; }
- (void)dealloc { [_classes release]; [_nibs release]; [_visible release]; [_reuse release]; [_counts release]; [_selection release]; [_bg release]; [super dealloc]; }
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return NO; }
- (id)dataSource { return _dataSource; } - (void)setDataSource:(id)d { _dataSource = d; [self reloadData]; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (NSCollectionViewLayout *)collectionViewLayout { return _layout; }
- (void)setCollectionViewLayout:(NSCollectionViewLayout *)l { if (_layout) _layout->_cv = nil; [l retain]; [_layout release]; _layout = l; l->_cv = self; [l invalidateLayout]; }
- (BOOL)isSelectable { return _selectable; } - (void)setSelectable:(BOOL)f { _selectable = f; }
- (BOOL)allowsMultipleSelection { return _multiple; } - (void)setAllowsMultipleSelection:(BOOL)f { _multiple = f; }
- (BOOL)allowsEmptySelection { return _empty; } - (void)setAllowsEmptySelection:(BOOL)f { _empty = f; }
- (NSArray *)backgroundColors { return _bg; } - (void)setBackgroundColors:(NSArray *)a { [a retain]; [_bg release]; _bg = a; [self setNeedsDisplay:YES]; }
- (void)registerClass:(Class)c forItemWithIdentifier:(NSString *)i { if (c) _classes[i] = c; else [_classes removeObjectForKey:i]; }
- (void)registerNib:(id)n forItemWithIdentifier:(NSString *)i { if (n) _nibs[i] = n; else [_nibs removeObjectForKey:i]; }
- (void)registerClass:(Class)c forSupplementaryViewOfKind:(NSString *)k withIdentifier:(NSString *)i {}
- (void)registerNib:(id)n forSupplementaryViewOfKind:(NSString *)k withIdentifier:(NSString *)i {}
- (NSCollectionViewItem *)makeItemWithIdentifier:(NSString *)i forIndexPath:(NSIndexPath *)p {
  NSMutableArray *q = _reuse[i]; NSCollectionViewItem *it = [q lastObject];
  if (it) { [[it retain] autorelease]; [q removeLastObject]; return it; }
  Class c = _classes[i];
  if (!c) [NSException raise:NSInvalidArgumentException format:@"could not dequeue an item of identifier %@ - must register a nib or a class for the identifier or connect a prototype cell in a storyboard", i];
  it = [[[c alloc] initWithNibName:nil bundle:nil] autorelease]; it->_cv = self; return it; }
- (void)_xefReloadCounts {
  [_counts release]; _counts = nil; _sections = -1; }
- (NSInteger)numberOfSections {
  if (_sections >= 0) return _sections;
  _sections = [_dataSource respondsToSelector:@selector(numberOfSectionsInCollectionView:)] ? [_dataSource numberOfSectionsInCollectionView:self] : (_dataSource ? 1 : 1);
  _counts = [[NSMutableArray alloc] init]; for (NSInteger s = 0; s < _sections; s++) [_counts addObject:[NSNull null]];
  return _sections; }
- (NSInteger)numberOfItemsInSection:(NSInteger)s {
  [self numberOfSections];
  if (s < 0 || s >= (NSInteger)[_counts count]) return 0;
  if (_counts[s] == (id)[NSNull null]) _counts[s] = @([_dataSource respondsToSelector:@selector(collectionView:numberOfItemsInSection:)] ? [_dataSource collectionView:self numberOfItemsInSection:s] : 0);
  return [_counts[s] integerValue]; }
- (void)reloadData {
  for (NSCollectionViewItem *it in [_visible allValues]) [[it view] removeFromSuperview];
  [_visible removeAllObjects]; [_reuse removeAllObjects]; [self _xefReloadCounts]; [_layout invalidateLayout]; [self setNeedsLayout:YES]; [self setNeedsDisplay:YES]; }
- (void)reloadItemsAtIndexPaths:(NSSet *)p { [self reloadData]; }
- (void)insertItemsAtIndexPaths:(NSSet *)p { [self reloadData]; } - (void)deleteItemsAtIndexPaths:(NSSet *)p { [self reloadData]; }
- (void)reloadSections:(NSIndexSet *)s { [self reloadData]; } - (void)insertSections:(NSIndexSet *)s { [self reloadData]; } - (void)deleteSections:(NSIndexSet *)s { [self reloadData]; }
- (void)performBatchUpdates:(void (^)(void))u completionHandler:(void (^)(BOOL))c { if (u) u(); [self reloadData]; if (c) c(YES); }
- (NSArray *)visibleItems { NSArray *k = [[_visible allKeys] sortedArrayUsingSelector:@selector(compare:)]; NSMutableArray *a = [NSMutableArray array]; for (NSIndexPath *p in k) [a addObject:_visible[p]]; return a; }
- (NSSet *)indexPathsForVisibleItems { return [NSSet setWithArray:[_visible allKeys]]; }
- (NSCollectionViewItem *)itemAtIndexPath:(NSIndexPath *)p { return _visible[p]; }
- (NSCollectionViewItem *)itemAtIndex:(NSUInteger)i { return _visible[[NSIndexPath indexPathForItem:i inSection:0]]; }
- (NSIndexPath *)indexPathForItem:(NSCollectionViewItem *)it { for (NSIndexPath *p in _visible) if (_visible[p] == it) return p; return nil; }
- (NSCollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)p { return [_layout layoutAttributesForItemAtIndexPath:p]; }
- (NSRect)frameForItemAtIndex:(NSUInteger)i { return [[_layout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0]] frame]; }
- (NSIndexPath *)indexPathForItemAtPoint:(NSPoint)pt { for (NSCollectionViewLayoutAttributes *a in [_layout layoutAttributesForElementsInRect:_bounds]) if (NSPointInRect(pt, a->_frame)) return a->_path; return nil; }
- (void)scrollToItemsAtIndexPaths:(NSSet *)p scrollPosition:(NSUInteger)pos { NSIndexPath *first = [[p allObjects] firstObject]; if (first) [self scrollRectToVisible:[[_layout layoutAttributesForItemAtIndexPath:first] frame]]; }
/* ---- selection */
- (void)_xefSync { for (NSIndexPath *p in _visible) [_visible[p] setSelected:[_selection containsObject:p]]; }
- (NSSet *)selectionIndexPaths { return [NSSet setWithSet:_selection]; }
- (void)setSelectionIndexPaths:(NSSet *)s {
  NSSet *use = (!_multiple && [s count] > 1) ? [NSSet setWithObject:[[s allObjects] firstObject]] : s;
  [_selection setSet:use]; [self _xefSync]; [self setNeedsDisplay:YES]; }
- (NSIndexSet *)selectionIndexes { NSMutableIndexSet *r = [NSMutableIndexSet indexSet]; for (NSIndexPath *p in _selection) if ([p section] == 0) [r addIndex:[p item]]; return r; }
- (void)selectItemsAtIndexPaths:(NSSet *)p scrollPosition:(NSUInteger)pos {
  NSMutableSet *n = _multiple ? [NSMutableSet setWithSet:_selection] : [NSMutableSet set]; [n unionSet:p]; [self setSelectionIndexPaths:n]; }
- (void)deselectItemsAtIndexPaths:(NSSet *)p { NSMutableSet *n = [NSMutableSet setWithSet:_selection]; [n minusSet:p]; [self setSelectionIndexPaths:n]; }
- (void)selectAll:(id)s {
  if (!_selectable || !_multiple) return;
  NSMutableSet *all = [NSMutableSet set]; for (NSInteger sec = 0; sec < [self numberOfSections]; sec++) for (NSInteger i = 0; i < [self numberOfItemsInSection:sec]; i++) [all addObject:[NSIndexPath indexPathForItem:i inSection:sec]];
  [self setSelectionIndexPaths:all];
  if ([_delegate respondsToSelector:@selector(collectionView:didSelectItemsAtIndexPaths:)]) [_delegate collectionView:self didSelectItemsAtIndexPaths:all]; }
- (void)deselectAll:(id)s {
  NSSet *old = [NSSet setWithSet:_selection]; if (![old count]) return;
  [self setSelectionIndexPaths:[NSSet set]];
  if ([_delegate respondsToSelector:@selector(collectionView:didDeselectItemsAtIndexPaths:)]) [_delegate collectionView:self didDeselectItemsAtIndexPaths:old]; }
/* ---- layout: the items that intersect the visible rectangle are created, the others are queued for reuse */
- (void)layout {
  if (!_layout || !_dataSource) return;
  [_layout invalidateLayout]; _layout->_valid = NO;
  NSSize content = [_layout collectionViewContentSize];
  if ([_superview isKindOfClass:[NSClipView class]]) {
    /* inside a scroll view the view is at least as large as the clip view along the cross axis and as the content along the scroll axis */
    NSSize clip = [_superview bounds].size; BOOL vert = !([_layout isKindOfClass:[NSCollectionViewFlowLayout class]] && ((NSCollectionViewFlowLayout *)_layout)->_dir == 1);
    NSSize want = vert ? NSMakeSize(clip.width, fmax(content.height, clip.height)) : NSMakeSize(fmax(content.width, clip.width), clip.height);
    if (!NSEqualSizes(_frame.size, want)) { [self setFrameSize:want]; _layout->_valid = NO; content = [_layout collectionViewContentSize]; } }
  for (NSInteger s = 0; s < [self numberOfSections]; s++) [self numberOfItemsInSection:s];
  NSRect vis = _window ? [self visibleRect] : _bounds; if (NSIsEmptyRect(vis)) vis = _bounds;
  NSArray *want = [_layout layoutAttributesForElementsInRect:vis]; NSMutableSet *keep = [NSMutableSet set];
  for (NSCollectionViewLayoutAttributes *a in want) {
    [keep addObject:a->_path]; NSCollectionViewItem *it = _visible[a->_path];
    if (!it) {
      it = [_dataSource respondsToSelector:@selector(collectionView:itemForRepresentedObjectAtIndexPath:)] ? [_dataSource collectionView:self itemForRepresentedObjectAtIndexPath:a->_path] : nil;
      if (!it) continue;
      it->_cv = self; _visible[a->_path] = it; [self addSubview:[it view]]; [it setSelected:[_selection containsObject:a->_path]]; }
    if (!NSEqualRects([[it view] frame], a->_frame)) [[it view] setFrame:a->_frame]; }
  for (NSIndexPath *p in [_visible allKeys]) if (![keep containsObject:p]) {
    NSCollectionViewItem *it = _visible[p]; [[it view] removeFromSuperview]; [_visible removeObjectForKey:p];
    NSString *key = @"cell"; for (NSString *k in _classes) if ([it isKindOfClass:_classes[k]]) key = k;
    NSMutableArray *q = _reuse[key]; if (!q) { q = [NSMutableArray array]; _reuse[key] = q; } [q addObject:it]; } }
- (void)setFrame:(NSRect)f { [super setFrame:f]; [_layout invalidateLayout]; [self setNeedsLayout:YES]; }
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; [self setNeedsLayout:YES]; }
- (void)drawRect:(NSRect)r { NSColor *c = [_bg firstObject]; if (c) { [c setFill]; NSRectFill(_bounds); } }
- (void)mouseDown:(NSEvent *)e {
  if (!_selectable) return;
  NSIndexPath *p = [self indexPathForItemAtPoint:[self convertPoint:[e locationInWindow] fromView:nil]];
  NSSet *old = [NSSet setWithSet:_selection];
  if (!p) { if (_empty && [old count]) { [self setSelectionIndexPaths:[NSSet set]]; if ([_delegate respondsToSelector:@selector(collectionView:didDeselectItemsAtIndexPaths:)]) [_delegate collectionView:self didDeselectItemsAtIndexPaths:old]; } return; }
  NSSet *one = [NSSet setWithObject:p];
  if ([_delegate respondsToSelector:@selector(collectionView:shouldSelectItemsAtIndexPaths:)] && ![_delegate collectionView:self shouldSelectItemsAtIndexPaths:one]) return;
  BOOL ext = _multiple && ([e modifierFlags] & (NSEventModifierFlagCommand | NSEventModifierFlagShift));
  if (ext && [_selection containsObject:p]) { [self deselectItemsAtIndexPaths:one]; if ([_delegate respondsToSelector:@selector(collectionView:didDeselectItemsAtIndexPaths:)]) [_delegate collectionView:self didDeselectItemsAtIndexPaths:one]; }
  else { [self selectItemsAtIndexPaths:ext ? one : one scrollPosition:0]; if ([_delegate respondsToSelector:@selector(collectionView:didSelectItemsAtIndexPaths:)]) [_delegate collectionView:self didSelectItemsAtIndexPaths:one]; } }
@end

/* ================================================================== NSTreeNode / NSTreeController */
@implementation NSTreeNode
+ (id)treeNodeWithRepresentedObject:(id)o { return [[[self alloc] initWithRepresentedObject:o] autorelease]; }
- (id)init { return [self initWithRepresentedObject:nil]; }
- (id)initWithRepresentedObject:(id)o { if ((self = [super init])) { _obj = [o retain]; _kids = [[NSMutableArray alloc] init]; } return self; }
- (void)dealloc { for (NSTreeNode *k in _kids) k->_parent = nil; [_obj release]; [_kids release]; [super dealloc]; }
- (id)representedObject { return _obj; } - (NSTreeNode *)parentNode { return _parent; }
- (NSArray *)childNodes { return [_kids count] ? _kids : nil; }
- (NSMutableArray *)mutableChildNodes { return [self mutableArrayValueForKey:@"xefChildren"]; }
- (NSUInteger)countOfXefChildren { return [_kids count]; }
- (id)objectInXefChildrenAtIndex:(NSUInteger)i { return _kids[i]; }
- (void)insertObject:(NSTreeNode *)n inXefChildrenAtIndex:(NSUInteger)i { n->_parent = self; [_kids insertObject:n atIndex:i]; }
- (void)removeObjectFromXefChildrenAtIndex:(NSUInteger)i { ((NSTreeNode *)_kids[i])->_parent = nil; [_kids removeObjectAtIndex:i]; }
- (BOOL)isLeaf { return [_kids count] == 0; }
- (NSIndexPath *)indexPath {
  NSUInteger idx[64]; NSUInteger n = 0;
  for (NSTreeNode *x = self; x->_parent && n < 64; x = x->_parent) idx[n++] = [x->_parent->_kids indexOfObjectIdenticalTo:x];
  NSUInteger rev[64]; for (NSUInteger i = 0; i < n; i++) rev[i] = idx[n - 1 - i];
  return [NSIndexPath indexPathWithIndexes:rev length:n]; }
- (NSTreeNode *)descendantNodeAtIndexPath:(NSIndexPath *)p {
  NSTreeNode *x = self;
  for (NSUInteger i = 0; i < [p length]; i++) { NSUInteger k = [p indexAtPosition:i]; if (k >= [x->_kids count]) return nil; x = x->_kids[k]; }
  return x; }
- (void)sortWithSortDescriptors:(NSArray *)d recursively:(BOOL)r {
  if ([d count]) {   /* descriptors name keys of the represented objects */
    NSMutableArray *m = [NSMutableArray array];
    for (NSSortDescriptor *x in d) [m addObject:[NSSortDescriptor sortDescriptorWithKey:[@"representedObject." stringByAppendingString:[x key] ?: @""] ascending:[x ascending] selector:[x selector]]];
    [_kids sortUsingDescriptors:m]; }
  if (r) for (NSTreeNode *k in _kids) [k sortWithSortDescriptors:d recursively:YES]; }
@end

@implementation NSTreeController
- (id)initWithContent:(id)c { if ((self = [super initWithContent:nil])) { _preserves = YES; _selectsInserted = YES; _avoidsEmpty = YES; _selPaths = [[NSMutableArray alloc] init]; _class = [NSMutableDictionary class]; [self setContent:c]; } return self; }
- (void)dealloc { [_childrenKP release]; [_countKP release]; [_leafKP release]; [_root release]; [_selPaths release]; [_sorts release]; [super dealloc]; }
- (NSArray *)_xefChildrenOf:(id)o { return _childrenKP && o ? [o valueForKeyPath:_childrenKP] : nil; }
- (void)_xefFill:(NSTreeNode *)n {
  NSArray *ch = [self _xefChildrenOf:n->_obj];
  if (![ch isKindOfClass:[NSArray class]]) return;
  for (id c in ch) { NSTreeNode *k = [[NSTreeNode alloc] initWithRepresentedObject:c]; k->_parent = n; [n->_kids addObject:k]; [self _xefFill:k]; [k release]; } }
- (void)_xefRebuild {
  [_root release]; _root = [[NSTreeNode alloc] initWithRepresentedObject:_childrenKP && _content ? @{_childrenKP: _content} : nil];
  NSArray *top = [_content isKindOfClass:[NSArray class]] ? _content : (_content ? @[_content] : @[]);
  for (id o in top) { NSTreeNode *k = [[NSTreeNode alloc] initWithRepresentedObject:o]; k->_parent = _root; [_root->_kids addObject:k]; [self _xefFill:k]; [k release]; }
  if ([_sorts count]) [_root sortWithSortDescriptors:_sorts recursively:YES]; }
- (void)setContent:(id)c { [super setContent:c]; [_selPaths removeAllObjects]; [self _xefRebuild];
  if (_avoidsEmpty && [_root->_kids count]) [_selPaths addObject:[NSIndexPath indexPathWithIndex:0]]; }
- (NSTreeNode *)arrangedObjects { if (!_root) [self _xefRebuild]; return _root; }
- (void)rearrangeObjects {
  NSMutableArray *objs = [NSMutableArray array];
  for (NSIndexPath *p in _selPaths) { NSTreeNode *n = [_root descendantNodeAtIndexPath:p]; if (n) [objs addObject:n->_obj]; }
  [self _xefRebuild]; [_selPaths removeAllObjects];
  if (_preserves) [self _xefSelectObjects:objs under:_root]; }
- (void)_xefSelectObjects:(NSArray *)objs under:(NSTreeNode *)n {
  for (NSTreeNode *k in n->_kids) { if ([objs indexOfObjectIdenticalTo:k->_obj] != NSNotFound) [_selPaths addObject:[k indexPath]]; [self _xefSelectObjects:objs under:k]; } }
- (NSString *)childrenKeyPath { return _childrenKP; } - (void)setChildrenKeyPath:(NSString *)k { [k retain]; [_childrenKP release]; _childrenKP = k; [self _xefRebuild]; }
- (NSString *)countKeyPath { return _countKP; } - (void)setCountKeyPath:(NSString *)k { [k retain]; [_countKP release]; _countKP = k; }
- (NSString *)leafKeyPath { return _leafKP; } - (void)setLeafKeyPath:(NSString *)k { [k retain]; [_leafKP release]; _leafKP = k; }
- (NSString *)childrenKeyPathForNode:(NSTreeNode *)n { return _childrenKP; } - (NSString *)countKeyPathForNode:(NSTreeNode *)n { return _countKP; }
- (NSString *)leafKeyPathForNode:(NSTreeNode *)n { return _leafKP; }
- (NSArray *)sortDescriptors { return _sorts; } - (void)setSortDescriptors:(NSArray *)d { [d retain]; [_sorts release]; _sorts = d; [self rearrangeObjects]; }
- (BOOL)preservesSelection { return _preserves; } - (void)setPreservesSelection:(BOOL)f { _preserves = f; }
- (BOOL)selectsInsertedObjects { return _selectsInserted; } - (void)setSelectsInsertedObjects:(BOOL)f { _selectsInserted = f; }
- (BOOL)avoidsEmptySelection { return _avoidsEmpty; } - (void)setAvoidsEmptySelection:(BOOL)f { _avoidsEmpty = f; }
- (BOOL)alwaysUsesMultipleValuesMarker { return _multMarker; } - (void)setAlwaysUsesMultipleValuesMarker:(BOOL)f { _multMarker = f; }
/* selection */
- (NSArray *)selectionIndexPaths { return [[_selPaths copy] autorelease]; }
- (NSIndexPath *)selectionIndexPath { return [_selPaths firstObject]; }
- (BOOL)setSelectionIndexPaths:(NSArray *)ps {
  NSMutableArray *ok = [NSMutableArray array];   /* AppKit takes paths as given, even ones that lead nowhere */
  for (NSIndexPath *p in ps) if ([p length]) [ok addObject:p];
  [self willChangeValueForKey:@"selectionIndexPaths"]; [_selPaths setArray:ok]; [self didChangeValueForKey:@"selectionIndexPaths"]; return YES; }
- (BOOL)setSelectionIndexPath:(NSIndexPath *)p { return [self setSelectionIndexPaths:p ? @[p] : @[]]; }
- (BOOL)addSelectionIndexPaths:(NSArray *)ps { NSMutableArray *a = [NSMutableArray arrayWithArray:_selPaths]; for (id p in ps) if (![a containsObject:p]) [a addObject:p]; return [self setSelectionIndexPaths:a]; }
- (BOOL)removeSelectionIndexPaths:(NSArray *)ps { NSMutableArray *a = [NSMutableArray arrayWithArray:_selPaths]; [a removeObjectsInArray:ps]; return [self setSelectionIndexPaths:a]; }
- (NSArray *)selectedNodes { NSMutableArray *r = [NSMutableArray array]; for (NSIndexPath *p in _selPaths) { id n = [_root descendantNodeAtIndexPath:p]; if (n) [r addObject:n]; } return r; }
- (NSArray *)selectedObjects { NSMutableArray *r = [NSMutableArray array]; for (NSTreeNode *n in [self selectedNodes]) [r addObject:n->_obj ?: [NSNull null]]; return r; }
/* editing the content: lists are made mutable in place */
- (NSMutableArray *)_xefMutableChildrenOf:(NSTreeNode *)n {
  if (n == _root || !n) {
    if (![_content isKindOfClass:[NSMutableArray class]]) { NSMutableArray *m = [NSMutableArray arrayWithArray:[_content isKindOfClass:[NSArray class]] ? _content : (_content ? @[_content] : @[])]; [_content release]; _content = [m retain]; }
    return _content; }
  id cur = [n->_obj valueForKeyPath:_childrenKP];
  if (![cur isKindOfClass:[NSMutableArray class]]) { NSMutableArray *m = [NSMutableArray arrayWithArray:cur ?: @[]]; [n->_obj setValue:m forKeyPath:_childrenKP]; cur = [n->_obj valueForKeyPath:_childrenKP]; }
  return cur; }
- (void)insertObject:(id)o atArrangedObjectIndexPath:(NSIndexPath *)p {
  if (![p length]) return;
  NSIndexPath *pp = [p indexPathByRemovingLastIndex]; NSTreeNode *parent = [_root descendantNodeAtIndexPath:pp];
  if (!parent) return;
  NSMutableArray *list = [self _xefMutableChildrenOf:parent]; NSUInteger i = [p indexAtPosition:[p length] - 1];
  if (i > [list count]) i = [list count];
  [list insertObject:o atIndex:i]; [self rearrangeObjects];
  if (_selectsInserted) { NSTreeNode *n = [_root descendantNodeAtIndexPath:p]; if (n && n->_obj == o) [self setSelectionIndexPath:p]; } }
- (void)insertObjects:(NSArray *)os atArrangedObjectIndexPaths:(NSArray *)ps { for (NSUInteger i = 0; i < [os count] && i < [ps count]; i++) [self insertObject:os[i] atArrangedObjectIndexPath:ps[i]]; }
- (void)removeObjectAtArrangedObjectIndexPath:(NSIndexPath *)p {
  NSTreeNode *n = [_root descendantNodeAtIndexPath:p]; if (!n || !n->_parent) return;
  NSMutableArray *list = [self _xefMutableChildrenOf:n->_parent]; NSUInteger i = [list indexOfObjectIdenticalTo:n->_obj];
  if (i != NSNotFound) [list removeObjectAtIndex:i];
  [self rearrangeObjects]; }
- (void)removeObjectsAtArrangedObjectIndexPaths:(NSArray *)ps {
  NSArray *sorted = [ps sortedArrayUsingSelector:@selector(compare:)];
  for (NSIndexPath *p in [sorted reverseObjectEnumerator]) [self removeObjectAtArrangedObjectIndexPath:p]; }
- (void)moveNode:(NSTreeNode *)n toIndexPath:(NSIndexPath *)p {
  id o = [[n->_obj retain] autorelease]; NSIndexPath *from = [n indexPath];
  [self removeObjectAtArrangedObjectIndexPath:from]; [self insertObject:o atArrangedObjectIndexPath:p]; }
- (void)moveNodes:(NSArray *)ns toIndexPath:(NSIndexPath *)p {
  NSUInteger last = [p length] - 1; NSIndexPath *base = [p indexPathByRemovingLastIndex]; NSUInteger i = [p indexAtPosition:last];
  for (NSTreeNode *n in ns) [self moveNode:n toIndexPath:[base indexPathByAddingIndex:i++]]; }
- (BOOL)canInsert { return _editable; } - (BOOL)canInsertChild { return _editable && [[self selectedNodes] count] > 0; } - (BOOL)canAddChild { return [self canInsertChild]; }
- (BOOL)canAdd { return _editable; } - (BOOL)canRemove { return _editable && [_selPaths count] > 0; }
- (NSIndexPath *)_xefAfterSelection { NSIndexPath *s = [_selPaths firstObject]; if (!s) return [NSIndexPath indexPathWithIndex:[_root->_kids count]]; return [[s indexPathByRemovingLastIndex] indexPathByAddingIndex:[s indexAtPosition:[s length] - 1] + 1]; }
- (void)insert:(id)s { [self insertObject:[self newObject] atArrangedObjectIndexPath:[self _xefAfterSelection]]; }
- (void)add:(id)s { [self insert:s]; }
- (void)insertChild:(id)s {
  NSIndexPath *p = [_selPaths firstObject]; if (!p) { [self insert:s]; return; }
  NSTreeNode *n = [_root descendantNodeAtIndexPath:p];
  [self insertObject:[self newObject] atArrangedObjectIndexPath:[p indexPathByAddingIndex:[n->_kids count]]]; }
- (void)addChild:(id)s { [self insertChild:s]; }
- (void)remove:(id)s { [self removeObjectsAtArrangedObjectIndexPaths:[self selectionIndexPaths]]; [_selPaths removeAllObjects]; }
@end

/* ================================================================== NSBrowser */
@interface NSObject (XEFBrowserDelegate)
- (id)rootItemForBrowser:(id)b; - (NSInteger)browser:(id)b numberOfChildrenOfItem:(id)i; - (id)browser:(id)b child:(NSInteger)n ofItem:(id)i;
- (NSInteger)browser:(id)b numberOfRowsInColumn:(NSInteger)c; - (void)browser:(id)b willDisplayCell:(id)cell atRow:(NSInteger)r column:(NSInteger)c;
- (BOOL)browser:(id)b isLeafItem:(id)i; - (id)browser:(id)b objectValueForItem:(id)i; - (void)browserSelectionDidChange:(id)b;
@end
@implementation NSBrowser
- (BOOL)_xefClassic { return [_delegate respondsToSelector:@selector(browser:numberOfRowsInColumn:)] && ![_delegate respondsToSelector:@selector(browser:numberOfChildrenOfItem:)]; }
- (NSInteger)_xefRows:(NSInteger)c { if (c < 0 || c >= (NSInteger)[_items count]) return 0; id x = _items[c]; return [x isKindOfClass:[NSMatrix class]] ? [(NSMatrix *)x numberOfRows] : (NSInteger)[x count]; }
- (NSMatrix *)_xefMatrixForColumn:(NSInteger)c {
  NSInteger n = [_delegate browser:self numberOfRowsInColumn:c]; Class cc = _cellClass ?: [NSBrowserCell class], mc = [self matrixClass];
  NSRect f = [self frameOfInsideOfColumn:c]; if (f.size.width < 1) f.size.width = 100;
  NSMatrix *m = [[[mc alloc] initWithFrame:NSMakeRect(0, 0, f.size.width, n * _rowH) mode:2 cellClass:cc numberOfRows:n numberOfColumns:1] autorelease];
  [m setCellSize:NSMakeSize(f.size.width, _rowH)]; return m; }
- (id)_xefLoadedCell:(NSInteger)r column:(NSInteger)c {
  NSMatrix *m = c >= 0 && c < (NSInteger)[_items count] ? _items[c] : nil; NSBrowserCell *cell = [m cellAtRow:r column:0]; if (!cell) return nil;
  if (![cell isLoaded]) { [cell setLoaded:YES]; if ([_delegate respondsToSelector:@selector(browser:willDisplayCell:atRow:column:)]) [_delegate browser:self willDisplayCell:cell atRow:r column:c]; }
  return cell; }
- (id)loadedCellAtRow:(NSInteger)r column:(NSInteger)c { return [self _xefClassic] ? [self _xefLoadedCell:r column:c] : nil; }
- (NSMatrix *)matrixInColumn:(NSInteger)c { return [self _xefClassic] && c >= 0 && c < (NSInteger)[_items count] ? _items[c] : nil; }
- (NSInteger)columnOfMatrix:(NSMatrix *)m { NSUInteger i = [_items indexOfObjectIdenticalTo:m]; return i == NSNotFound ? -1 : (NSInteger)i; }
- (id)selectedCellInColumn:(NSInteger)c { NSInteger r = [self selectedRowInColumn:c]; return r < 0 ? nil : [self itemAtRow:r inColumn:c]; }
- (id)selectedCell { NSInteger c = [self selectedColumn]; return c < 0 ? nil : [self selectedCellInColumn:c]; }
- (NSArray *)selectedCells { NSInteger c = [self selectedColumn]; NSMutableArray *a = [NSMutableArray array]; if (c < 0) return a; [_sel[c] enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) { id x = [self itemAtRow:i inColumn:c]; if (x) [a addObject:x]; }]; return a; }
- (id)initWithFrame:(NSRect)f {
  if ((self = [super initWithFrame:f])) {
    _titled = YES; _empty = YES; _separates = YES; _typeSelect = YES; _minW = 100; _defW = 100; _rowH = 17; _resizing = 1; _sep = @"/"; _clickedRow = _clickedCol = -1;
    _parents = [[NSMutableArray alloc] init]; _items = [[NSMutableArray alloc] init]; _sel = [[NSMutableArray alloc] init]; _titles = [[NSMutableDictionary alloc] init]; _widths = [[NSMutableDictionary alloc] init]; }
  return self; }
- (void)dealloc { [_root release]; [_parents release]; [_items release]; [_sel release]; [_titles release]; [_widths release]; [_sep release]; [_bg release]; [_proto release]; [super dealloc]; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (BOOL)isLoaded { return _loaded; }
- (id)_xefChild:(NSInteger)i of:(id)p { return [_delegate browser:self child:i ofItem:p]; }
- (NSArray *)_xefChildrenOf:(id)p {
  NSInteger n = [_delegate respondsToSelector:@selector(browser:numberOfChildrenOfItem:)] ? [_delegate browser:self numberOfChildrenOfItem:p] : 0;
  NSMutableArray *a = [NSMutableArray array]; for (NSInteger i = 0; i < n; i++) { id c = [self _xefChild:i of:p]; [a addObject:c ?: [NSNull null]]; } return a; }
- (void)_xefTruncate:(NSInteger)keep { while ((NSInteger)[_items count] > keep) { [_items removeLastObject]; [_parents removeLastObject]; [_sel removeLastObject]; } }
- (void)_xefAddColumnFor:(id)parent { [_parents addObject:parent ?: [NSNull null]]; NSInteger c = [_items count]; [_items addObject:[self _xefClassic] ? (id)[self _xefMatrixForColumn:c] : (id)[self _xefChildrenOf:parent]]; [_sel addObject:[NSIndexSet indexSet]]; }
- (void)loadColumnZero {
  [_root release]; _root = nil;
  if ([self _xefClassic]) { [self _xefTruncate:0]; [self _xefAddColumnFor:nil]; _loaded = YES; [self setNeedsDisplay:YES]; return; }
  if ([_delegate respondsToSelector:@selector(rootItemForBrowser:)]) _root = [[_delegate rootItemForBrowser:self] retain];
  [self _xefTruncate:0]; [self _xefAddColumnFor:_root]; _loaded = YES; [self setNeedsDisplay:YES]; }
- (NSInteger)lastColumn { return [_items count] ? (NSInteger)[_items count] - 1 : 0; }
- (void)setLastColumn:(NSInteger)c { if (c >= 0) [self _xefTruncate:c + 1]; }
- (id)itemAtRow:(NSInteger)r inColumn:(NSInteger)c {
  if (c < 0 || c >= (NSInteger)[_items count] || r < 0 || r >= [self _xefRows:c]) return nil;
  if ([self _xefClassic]) return [self _xefLoadedCell:r column:c];
  id x = _items[c][r]; return x == [NSNull null] ? nil : x; }
- (id)parentForItemsInColumn:(NSInteger)c { if (c < 0 || c >= (NSInteger)[_parents count]) return nil; id x = _parents[c]; return x == [NSNull null] ? nil : x; }
- (BOOL)isLeafItem:(id)i { if ([i isKindOfClass:[NSBrowserCell class]]) return [(NSBrowserCell *)i isLeaf]; return [_delegate respondsToSelector:@selector(browser:isLeafItem:)] ? [_delegate browser:self isLeafItem:i] : [self _xefChildrenOf:i].count == 0; }
- (void)selectRowIndexes:(NSIndexSet *)ix inColumn:(NSInteger)c {
  if (!_loaded || c < 0 || c >= (NSInteger)[_items count]) return;
  NSUInteger n = [self _xefRows:c];
  NSMutableIndexSet *ok = [NSMutableIndexSet indexSet]; [ix enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) { if (i < n) [ok addIndex:i]; }];
  [self _xefTruncate:c + 1]; _sel[c] = [[ok copy] autorelease];
  if ([ok count] == 1) { id it = [self itemAtRow:[ok firstIndex] inColumn:c]; if (it && ![self isLeafItem:it]) [self _xefAddColumnFor:it]; }
  [self setNeedsDisplay:YES]; }
- (void)selectRow:(NSInteger)r inColumn:(NSInteger)c { if (r < 0) [self selectRowIndexes:[NSIndexSet indexSet] inColumn:c]; else [self selectRowIndexes:[NSIndexSet indexSetWithIndex:r] inColumn:c]; }
- (NSInteger)selectedColumn { for (NSInteger c = (NSInteger)[_sel count] - 1; c >= 0; c--) if ([_sel[c] count]) return c; return -1; }
- (NSInteger)selectedRowInColumn:(NSInteger)c { if (c < 0 || c >= (NSInteger)[_sel count] || ![_sel[c] count]) return -1; return [_sel[c] lastIndex]; }
- (NSIndexSet *)selectedRowIndexesInColumn:(NSInteger)c { return c >= 0 && c < (NSInteger)[_sel count] ? _sel[c] : [NSIndexSet indexSet]; }
- (NSString *)_xefNameOf:(id)it { if ([it isKindOfClass:[NSCell class]]) return [it stringValue] ?: @""; id v = [_delegate respondsToSelector:@selector(browser:objectValueForItem:)] ? [_delegate browser:self objectValueForItem:it] : nil; return [v isKindOfClass:[NSString class]] ? v : [v description] ?: @""; }
- (NSString *)pathToColumn:(NSInteger)c {
  NSMutableString *s = [NSMutableString string];
  for (NSInteger i = 0; i < c && i < (NSInteger)[_sel count]; i++) { NSInteger r = [self selectedRowInColumn:i]; if (r < 0) break; [s appendString:_sep]; [s appendString:[self _xefNameOf:[self itemAtRow:r inColumn:i]]]; }
  return s.length || c <= 0 ? s : _sep; }
- (NSString *)path { NSInteger sc = [self selectedColumn]; return sc < 0 ? @"" : [self pathToColumn:sc + 1]; }
- (NSIndexPath *)indexPathForColumn:(NSInteger)c {
  NSUInteger idx[64]; NSUInteger n = 0;
  for (NSInteger i = 0; i < c && i < (NSInteger)[_sel count] && n < 64; i++) { NSInteger r = [self selectedRowInColumn:i]; if (r < 0) break; idx[n++] = r; }
  return [NSIndexPath indexPathWithIndexes:idx length:n]; }
- (NSArray *)selectionIndexPaths {
  NSInteger sc = [self selectedColumn]; if (sc < 0) return @[];
  NSIndexPath *base = [self indexPathForColumn:sc]; NSMutableArray *r = [NSMutableArray array];
  [_sel[sc] enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) { [r addObject:[base indexPathByAddingIndex:i]]; }]; return r; }
- (NSIndexPath *)selectionIndexPath { return [[self selectionIndexPaths] firstObject]; }
- (void)setSelectionIndexPaths:(NSArray *)ps {
  if (!_loaded) [self loadColumnZero]; else { [self _xefTruncate:1]; _sel[0] = [NSIndexSet indexSet]; }
  NSIndexPath *first = [ps firstObject]; if (!first) return;
  NSUInteger len = [first length]; NSIndexPath *base = [first indexPathByRemovingLastIndex];
  for (NSUInteger i = 0; i < [base length]; i++) [self selectRow:[base indexAtPosition:i] inColumn:i];
  NSMutableIndexSet *last = [NSMutableIndexSet indexSet]; for (NSIndexPath *p in ps) if ([p length] == len) [last addIndex:[p indexAtPosition:len - 1]];
  [self selectRowIndexes:last inColumn:len - 1]; }
- (void)setSelectionIndexPath:(NSIndexPath *)p { [self setSelectionIndexPaths:p ? @[p] : @[]]; }
- (BOOL)setPath:(NSString *)path {
  if (!_loaded) [self loadColumnZero]; else { [self _xefTruncate:1]; _sel[0] = [NSIndexSet indexSet]; }
  NSArray *parts = [path componentsSeparatedByString:_sep]; NSInteger col = 0;
  for (NSString *name in parts) {
    if (![name length]) continue;
    NSInteger found = -1, n = [self _xefRows:col];
    for (NSInteger r = 0; r < n; r++) if ([[self _xefNameOf:[self itemAtRow:r inColumn:col]] isEqualToString:name]) { found = r; break; }
    if (found < 0) { [self _xefTruncate:1]; _sel[0] = [NSIndexSet indexSet]; return NO; }
    [self selectRow:found inColumn:col]; col++;
    if (col >= (NSInteger)[_items count]) break; }
  return YES; }
- (void)reloadColumn:(NSInteger)c {
  if (c < 0 || c >= (NSInteger)[_items count]) return;
  if ([self _xefClassic]) _items[c] = [self _xefMatrixForColumn:c]; else _items[c] = [self _xefChildrenOf:_parents[c]];
  [self setNeedsDisplay:YES]; }
- (void)reloadDataForRowIndexes:(NSIndexSet *)r inColumn:(NSInteger)c { [self reloadColumn:c]; }
- (void)addColumn { [self _xefAddColumnFor:[NSNull null]]; }
- (void)displayColumn:(NSInteger)c { [self setNeedsDisplay:YES]; } - (void)displayAllColumns { [self setNeedsDisplay:YES]; }
- (void)scrollColumnToVisible:(NSInteger)c {} - (void)scrollRowToVisible:(NSInteger)r inColumn:(NSInteger)c {} - (void)tile {} - (void)updateScroller {}
- (void)selectAll:(id)s { if (_multi && [self selectedColumn] >= 0) { NSInteger c = [self selectedColumn]; [self selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [self _xefRows:c])] inColumn:c]; } }
/* titles and geometry */
- (void)setTitle:(NSString *)t ofColumn:(NSInteger)c { if (t) _titles[@(c)] = t; else [_titles removeObjectForKey:@(c)]; }
- (NSString *)titleOfColumn:(NSInteger)c { return _titles[@(c)] ?: ([self _xefClassic] ? @"" : nil); }
- (CGFloat)titleHeight { return 17; }
- (CGFloat)widthOfColumn:(NSInteger)c { NSNumber *w = _widths[@(c)]; return w ? [w doubleValue] : _defW; }
- (void)setWidth:(CGFloat)w ofColumn:(NSInteger)c { if (w < _minW) w = _minW; _widths[@(c)] = @(w); }
- (NSRect)frameOfColumn:(NSInteger)c { CGFloat x = 0; for (NSInteger i = 0; i < c; i++) x += [self widthOfColumn:i] + (_separates ? 1 : 0); NSRect b = [self bounds]; return NSMakeRect(x, 0, [self widthOfColumn:c], b.size.height); }
- (NSRect)frameOfInsideOfColumn:(NSInteger)c { NSRect r = [self frameOfColumn:c]; if (_titled) { r.origin.y += [self titleHeight]; r.size.height -= [self titleHeight]; } return r; }
- (NSRect)titleFrameOfColumn:(NSInteger)c { NSRect r = [self frameOfColumn:c]; r.size.height = [self titleHeight]; return r; }
- (NSRect)frameOfRow:(NSInteger)r inColumn:(NSInteger)c { NSRect f = [self frameOfInsideOfColumn:c]; return NSMakeRect(f.origin.x, f.origin.y + r * _rowH, f.size.width, _rowH); }
- (CGFloat)columnWidthForColumnContentWidth:(CGFloat)w { return w + 6; } - (CGFloat)columnContentWidthForColumnWidth:(CGFloat)w { return w - 6; }
- (NSInteger)firstVisibleColumn { return 0; } - (NSInteger)lastVisibleColumn { return [self lastColumn]; } - (NSInteger)numberOfVisibleColumns { return [_items count]; }
- (BOOL)getRow:(NSInteger *)row column:(NSInteger *)col forPoint:(NSPoint)p {
  for (NSInteger c = 0; c < (NSInteger)[_items count]; c++) { NSRect f = [self frameOfInsideOfColumn:c]; if (NSPointInRect(p, f)) { NSInteger r = (NSInteger)((p.y - f.origin.y) / _rowH); if (r >= (NSInteger)[_items[c] count]) return NO; if (row) *row = r; if (col) *col = c; return YES; } }
  return NO; }
- (NSInteger)clickedRow { return _clickedRow; } - (NSInteger)clickedColumn { return _clickedCol; }
/* settings */
- (BOOL)isTitled { return _titled; } - (void)setTitled:(BOOL)f { _titled = f; }
- (BOOL)allowsMultipleSelection { return _multi; } - (void)setAllowsMultipleSelection:(BOOL)f { _multi = f; }
- (BOOL)allowsBranchSelection { return _branch; } - (void)setAllowsBranchSelection:(BOOL)f { _branch = f; }
- (BOOL)allowsEmptySelection { return _empty; } - (void)setAllowsEmptySelection:(BOOL)f { _empty = f; }
- (BOOL)reusesColumns { return _reuses; } - (void)setReusesColumns:(BOOL)f { _reuses = f; }
- (BOOL)separatesColumns { return _separates; } - (void)setSeparatesColumns:(BOOL)f { _separates = f; }
- (BOOL)allowsTypeSelect { return _typeSelect; } - (void)setAllowsTypeSelect:(BOOL)f { _typeSelect = f; }
- (BOOL)hasHorizontalScroller { return _hscroll; } - (void)setHasHorizontalScroller:(BOOL)f { _hscroll = f; }
- (BOOL)autohidesScroller { return _autohides; } - (void)setAutohidesScroller:(BOOL)f { _autohides = f; }
- (BOOL)acceptsArrowKeys { return _arrows; } - (void)setAcceptsArrowKeys:(BOOL)f { _arrows = f; }
- (BOOL)sendsActionOnArrowKeys { return _sendsArrows; } - (void)setSendsActionOnArrowKeys:(BOOL)f { _sendsArrows = f; }
- (BOOL)takesTitleFromPreviousColumn { return _takesTitle; } - (void)setTakesTitleFromPreviousColumn:(BOOL)f { _takesTitle = f; }
- (CGFloat)minColumnWidth { return _minW; } - (void)setMinColumnWidth:(CGFloat)w { _minW = w; }
- (CGFloat)defaultColumnWidth { return _defW; } - (void)setDefaultColumnWidth:(CGFloat)w { _defW = w; }
- (CGFloat)rowHeight { return _rowH; } - (void)setRowHeight:(CGFloat)h { _rowH = h; }
- (NSInteger)maxVisibleColumns { return _maxVis; } - (void)setMaxVisibleColumns:(NSInteger)n { _maxVis = n; }
- (NSInteger)columnResizingType { return _resizing; } - (void)setColumnResizingType:(NSInteger)t { _resizing = t; }
- (NSString *)pathSeparator { return _sep; } - (void)setPathSeparator:(NSString *)s { [s retain]; [_sep release]; _sep = s; }
- (SEL)doubleAction { return _dbl; } - (void)setDoubleAction:(SEL)a { _dbl = a; }
- (id)backgroundColor { return _bg; } - (void)setBackgroundColor:(id)c { [c retain]; [_bg release]; _bg = c; }
- (Class)cellClass { return _cellClass; } - (void)setCellClass:(Class)c { _cellClass = c; }
+ (Class)cellClass { return [NSBrowserCell class]; }
- (Class)matrixClass { return _matrixClass ?: [NSMatrix class]; } - (void)setMatrixClass:(Class)c { _matrixClass = c; }
- (id)cellPrototype { return _proto; } - (void)setCellPrototype:(id)c { [c retain]; [_proto release]; _proto = c; }
- (BOOL)sendAction { return [self sendAction:[self action] to:[self target]]; }
- (void)doClick:(id)s {} - (void)doDoubleClick:(id)s {}
/* drawing and mouse: plain lists */
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty {
  [[NSColor whiteColor] set]; NSRectFill([self bounds]);
  NSDictionary *at = @{ NSFontAttributeName: [NSFont systemFontOfSize:12] };
  for (NSInteger c = 0; c < (NSInteger)[_items count]; c++) {
    NSRect in = [self frameOfInsideOfColumn:c];
    if (_titled && _titles[@(c)]) [_titles[@(c)] drawInRect:[self titleFrameOfColumn:c] withAttributes:at];
    for (NSInteger r = 0; r < [self _xefRows:c]; r++) {
      NSRect f = [self frameOfRow:r inColumn:c]; BOOL on = [_sel[c] containsIndex:r];
      if (on) { [[NSColor selectedControlColor] set]; NSRectFill(f); }
      id it = [self itemAtRow:r inColumn:c]; [[self _xefNameOf:it] drawInRect:NSInsetRect(f, 4, 0) withAttributes:at]; }
    if (_separates) { [[NSColor gridColor] set]; NSRectFill(NSMakeRect(NSMaxX(in), in.origin.y, 1, in.size.height)); } } }
- (void)mouseDown:(NSEvent *)e {
  NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil]; NSInteger r, c;
  if (![self getRow:&r column:&c forPoint:p]) return;
  _clickedRow = r; _clickedCol = c; [self selectRow:r inColumn:c];
  if ([_delegate respondsToSelector:@selector(browserSelectionDidChange:)]) [_delegate browserSelectionDidChange:self];
  [self sendAction:[self action] to:[self target]];
  if ([e clickCount] == 2 && _dbl) [self sendAction:_dbl to:[self target]]; }
@end

/* ================================================================== NSPathControl */
@implementation NSPathControlItem
- (void)dealloc { [_title release]; [_atitle release]; [_image release]; [_url release]; [super dealloc]; }
- (NSString *)title { return _title ?: [_atitle string]; } - (void)setTitle:(NSString *)t { [t retain]; [_title release]; _title = t; }
- (NSAttributedString *)attributedTitle { return _atitle ?: (_title ? [[[NSAttributedString alloc] initWithString:_title] autorelease] : nil); }
- (void)setAttributedTitle:(NSAttributedString *)a { [a retain]; [_atitle release]; _atitle = a; }
- (id)image { return _image; } - (void)setImage:(id)i { [i retain]; [_image release]; _image = i; }
- (NSURL *)URL { return _url; }
@end
@implementation NSPathComponentCell
- (void)dealloc { [_url release]; [super dealloc]; }
- (NSURL *)URL { return _url; } - (void)setURL:(NSURL *)u { [u retain]; [_url release]; _url = u; }
@end
@implementation NSPathCell
- (void)dealloc { [_url release]; [_cells release]; [_ph release]; [super dealloc]; }
- (NSURL *)URL { return _url; } - (void)setURL:(NSURL *)u { [u retain]; [_url release]; _url = u; }
- (NSInteger)pathStyle { return _style; } - (void)setPathStyle:(NSInteger)s { _style = s; }
- (NSArray *)pathComponentCells { return _cells ?: @[]; } - (void)setPathComponentCells:(NSArray *)c { [c retain]; [_cells release]; _cells = c; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (NSString *)placeholderString { return _ph; } - (void)setPlaceholderString:(NSString *)s { [s retain]; [_ph release]; _ph = s; }
@end

@implementation NSPathControl
- (id)initWithFrame:(NSRect)f {
  if ((self = [super initWithFrame:f])) { _editable = YES; NSPathCell *c = [[NSPathCell alloc] init]; [self setCell:c]; [c release]; _items = [@[] retain]; }
  return self; }
- (void)dealloc { [_url release]; [_ph release]; [_aph release]; [_items release]; [_types release]; [_bg release]; [_menu release]; [super dealloc]; }
- (NSURL *)URL { return _url; }
- (NSArray *)_xefItemsForURL:(NSURL *)u {
  NSMutableArray *r = [NSMutableArray array]; if (!u) return r;
  BOOL file = [u isFileURL]; NSArray *comps = [[u path] pathComponents]; NSMutableString *acc = [NSMutableString string];
  NSString *base = file ? @"file://" : [NSString stringWithFormat:@"%@://%@", [u scheme], [u host] ?: @""];
  for (NSString *c in comps) {
    NSPathControlItem *it = [[NSPathControlItem alloc] init];
    if ([c isEqualToString:@"/"]) { if (!file) { [it release]; continue; } it->_title = [@"Macintosh HD" retain]; it->_url = [[NSURL URLWithString:@"file:///"] retain]; }
    else { [acc appendFormat:@"/%@", ([c respondsToSelector:@selector(stringByAddingPercentEscapesUsingEncoding:)] ? [c stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] : c)]; it->_title = [c retain]; it->_url = [[NSURL URLWithString:[base stringByAppendingString:acc]] retain]; }
    [r addObject:it]; [it release]; }
  return r; }
- (void)_xefSyncCells {
  NSMutableArray *cells = [NSMutableArray array];
  for (NSPathControlItem *i in _items) { NSPathComponentCell *c = [[NSPathComponentCell alloc] init]; [c setTitle:[i title] ?: @""]; [c setURL:[i URL]]; [c setImage:[i image]]; [cells addObject:c]; [c release]; }
  [(NSPathCell *)[self cell] setPathComponentCells:cells]; [self setNeedsDisplay:YES]; }
- (void)setURL:(NSURL *)u { [u retain]; [_url release]; _url = u; [_items release]; _items = [[self _xefItemsForURL:u] retain]; [(NSPathCell *)[self cell] setURL:u]; [self _xefSyncCells]; }
- (NSArray *)pathItems { return _items; }
- (void)setPathItems:(NSArray *)i { [i retain]; [_items release]; _items = i ?: [@[] retain]; [self _xefSyncCells]; }
- (NSArray *)pathComponentCells { return [(NSPathCell *)[self cell] pathComponentCells]; }
- (void)setPathComponentCells:(NSArray *)cells {
  NSMutableArray *its = [NSMutableArray array];
  for (NSPathComponentCell *c in cells) { NSPathControlItem *it = [[NSPathControlItem alloc] init]; it->_title = [[c title] retain]; it->_url = [[c URL] retain]; it->_image = [[c image] retain]; [its addObject:it]; [it release]; }
  [self setPathItems:its]; }
- (NSInteger)pathStyle { return _style; } - (void)setPathStyle:(NSInteger)s { _style = s; [(NSPathCell *)[self cell] setPathStyle:s]; [self setNeedsDisplay:YES]; }
- (BOOL)isEditable { return _editable; } - (void)setEditable:(BOOL)f { _editable = f; }
- (NSString *)placeholderString { return _ph; } - (void)setPlaceholderString:(NSString *)s { [s retain]; [_ph release]; _ph = s; [self setNeedsDisplay:YES]; }
- (NSAttributedString *)placeholderAttributedString { return _aph; } - (void)setPlaceholderAttributedString:(NSAttributedString *)s { [s retain]; [_aph release]; _aph = s; }
- (NSArray *)allowedTypes { return _types; } - (void)setAllowedTypes:(NSArray *)t { [t retain]; [_types release]; _types = t; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (SEL)doubleAction { return _dbl; } - (void)setDoubleAction:(SEL)a { _dbl = a; }
- (id)backgroundColor { return _bg; } - (void)setBackgroundColor:(id)c { [c retain]; [_bg release]; _bg = c; }
- (NSPathControlItem *)clickedPathItem { return _clicked; }
- (NSPathComponentCell *)clickedPathComponentCell { NSUInteger i = _clicked ? [_items indexOfObjectIdenticalTo:_clicked] : NSNotFound; NSArray *c = [self pathComponentCells]; return i < [c count] ? c[i] : nil; }
- (void)setDraggingSourceOperationMask:(NSUInteger)m forLocal:(BOOL)l {}
- (NSMenu *)menu { return _menu; } - (void)setMenu:(NSMenu *)m { [m retain]; [_menu release]; _menu = m; }
- (BOOL)isFlipped { return YES; }
/* items are drawn left to right, separated by an arrow; clicks find the item by drawn width */
- (CGFloat)_xefWidthOf:(NSString *)t { return [t sizeWithAttributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:12] }].width; }
- (void)drawRect:(NSRect)dirty {
  NSRect b = [self bounds]; if (_bg) { [_bg set]; NSRectFill(b); }
  NSDictionary *at = @{ NSFontAttributeName: [NSFont systemFontOfSize:12] }; CGFloat x = 4;
  if (![_items count]) { if (_ph) [_ph drawInRect:NSMakeRect(x, 3, b.size.width - 8, b.size.height - 6) withAttributes:at]; return; }
  for (NSUInteger i = 0; i < [_items count]; i++) {
    NSString *t = [_items[i] title] ?: @""; CGFloat w = [self _xefWidthOf:t];
    [t drawInRect:NSMakeRect(x, 3, w + 2, b.size.height - 6) withAttributes:at]; x += w + 6;
    if (i + 1 < [_items count]) { [@">" drawInRect:NSMakeRect(x, 3, 10, b.size.height - 6) withAttributes:at]; x += 14; } } }
- (void)mouseDown:(NSEvent *)e {
  NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil]; CGFloat x = 4;
  for (NSUInteger i = 0; i < [_items count]; i++) {
    CGFloat w = [self _xefWidthOf:[_items[i] title] ?: @""];
    if (p.x >= x && p.x <= x + w + 4) { _clicked = _items[i]; [self sendAction:[self action] to:[self target]]; if ([e clickCount] == 2 && _dbl) [self sendAction:_dbl to:[self target]]; return; }
    x += w + 20; } }
@end

/* ================================================================== NSSound */
static NSMutableDictionary *XEFNamedSounds(void) { static NSMutableDictionary *d; if (!d) d = [[NSMutableDictionary alloc] init]; return d; }
static NSTimeInterval XEFWavDuration(NSData *d) {
  const unsigned char *b = [d bytes]; NSUInteger n = [d length];
  if (n < 12 || memcmp(b, "RIFF", 4) || memcmp(b + 8, "WAVE", 4)) return -1;
  uint32_t rate = 0, bytesPerSec = 0, dataLen = 0; BOOL fmt = NO, dat = NO;
  for (NSUInteger p = 12; p + 8 <= n;) {
    uint32_t len; memcpy(&len, b + p + 4, 4);
    if (!memcmp(b + p, "fmt ", 4) && p + 8 + 16 <= n) { memcpy(&rate, b + p + 12, 4); memcpy(&bytesPerSec, b + p + 16, 4); fmt = YES; }
    else if (!memcmp(b + p, "data", 4)) { dataLen = len; if (p + 8 + len > n) dataLen = (uint32_t)(n - p - 8); dat = YES; }
    p += 8 + len + (len & 1); }
  if (!fmt || !dat || !bytesPerSec) return -1;
  return (NSTimeInterval)dataLen / bytesPerSec; }
@implementation NSSound
+ (NSSound *)soundNamed:(NSString *)n { return XEFNamedSounds()[n]; }
+ (NSArray *)soundUnfilteredTypes { return @[@"wav", @"wave", @"public.wav"]; } + (NSArray *)soundUnfilteredFileTypes { return @[@"wav", @"wave"]; } + (NSArray *)soundUnfilteredPasteboardTypes { return @[]; }
- (id)initWithData:(NSData *)d {
  NSTimeInterval t = d ? XEFWavDuration(d) : -1;
  if (t < 0) { [self release]; return nil; }
  if ((self = [super init])) { _data = [d retain]; _duration = t; _volume = 1; } return self; }
- (id)initWithContentsOfFile:(NSString *)p byReference:(BOOL)r { NSData *d = p ? [NSData dataWithContentsOfFile:p] : nil; if (!d) { [self release]; return nil; } return [self initWithData:d]; }
- (id)initWithContentsOfURL:(NSURL *)u byReference:(BOOL)r { return [u isFileURL] ? [self initWithContentsOfFile:[u path] byReference:r] : ([self release], nil); }
- (void)dealloc { [_timer invalidate]; [_data release]; [_name release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [[NSSound alloc] initWithData:_data]; }
- (NSTimeInterval)duration { return _duration; }
- (float)volume { return _volume; } - (void)setVolume:(float)v { _volume = v; }
- (BOOL)loops { return _loops; } - (void)setLoops:(BOOL)f { _loops = f; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (BOOL)isPlaying { return _playing; }
- (NSString *)name { return _name; } - (BOOL)setName:(NSString *)n { if (!n) return NO; [n retain]; [_name release]; _name = n; XEFNamedSounds()[n] = self; return YES; }
- (NSTimeInterval)currentTime { if (_playing && !_paused) { NSTimeInterval t = _offset + ([NSDate timeIntervalSinceReferenceDate] - _started); return t > _duration ? _duration : t; } return _offset; }
- (void)setCurrentTime:(NSTimeInterval)t { _offset = t < 0 ? 0 : t > _duration ? _duration : t; if (_playing && !_paused) { _started = [NSDate timeIntervalSinceReferenceDate]; [self _xefSchedule]; } }
- (void)_xefSchedule {
  [_timer invalidate]; _timer = nil;
  NSTimeInterval left = _duration - _offset; if (left < 0) left = 0;
  _timer = [NSTimer scheduledTimerWithTimeInterval:left target:self selector:@selector(_xefDone) userInfo:nil repeats:NO]; }
- (void)_xefDone {
  _timer = nil;
  if (_loops) { _offset = 0; _started = [NSDate timeIntervalSinceReferenceDate]; [self _xefSchedule]; return; }
  _playing = NO; _paused = NO; _offset = 0;
  if ([_delegate respondsToSelector:@selector(sound:didFinishPlaying:)]) [_delegate sound:self didFinishPlaying:YES]; }
- (BOOL)play { if (_playing) return NO; _playing = YES; _paused = NO; _started = [NSDate timeIntervalSinceReferenceDate]; [self _xefSchedule]; return YES; }
- (BOOL)pause { if (!_playing || _paused) return NO; _offset = [self currentTime]; _paused = YES; [_timer invalidate]; _timer = nil; return YES; }
- (BOOL)resume { if (!_playing || !_paused) return NO; _paused = NO; _started = [NSDate timeIntervalSinceReferenceDate]; [self _xefSchedule]; return YES; }
- (BOOL)stop {
  if (!_playing) return YES;
  [_timer invalidate]; _timer = nil; _playing = NO; _paused = NO; _offset = 0;
  if ([_delegate respondsToSelector:@selector(sound:didFinishPlaying:)]) [_delegate sound:self didFinishPlaying:NO];
  return YES; }
@end
@interface NSObject (XEFSoundDelegate) - (void)sound:(id)s didFinishPlaying:(BOOL)f; @end

/* ---- NSMatrix: edits with cells, sorting, backgrounds, tool tips, key cell, text-editing hooks ---- */
static BOOL XEFAssocBool(id o, const char *k, BOOL def) { NSNumber *n = objc_getAssociatedObject(o, k); return n ? [n boolValue] : def; }
@implementation NSMatrix (XEFMore)
- (NSCell *)makeCellAtRow:(NSInteger)r column:(NSInteger)c { NSCell *cell = [self _xefMakeCell]; return cell; }
- (void)getNumberOfRows:(NSInteger *)r columns:(NSInteger *)c { if (r) *r = _rows; if (c) *c = _cols; }
- (NSArray *)_xefFillCells:(NSArray *)cells count:(NSInteger)n { NSMutableArray *a = [NSMutableArray array]; for (NSInteger i = 0; i < n; i++) a[i] = i < (NSInteger)[cells count] ? cells[i] : [self _xefMakeCell]; return a; }
- (void)insertRow:(NSInteger)i withCells:(NSArray *)cells {
  NSMutableArray *g = [self _xefGrid]; NSInteger cols = _cols ?: (NSInteger)[cells count]; NSArray *row = [self _xefFillCells:cells count:cols];
  for (NSCell *c in row) [c setControlView:self];
  [g insertObject:[NSMutableArray arrayWithArray:row] atIndex:i < 0 ? 0 : i > (NSInteger)[g count] ? [g count] : i]; [self _xefStore:g cols:cols]; }
- (void)addRowWithCells:(NSArray *)cells { [self insertRow:_rows withCells:cells]; }
- (void)insertColumn:(NSInteger)i withCells:(NSArray *)cells {
  NSMutableArray *g = [self _xefGrid]; NSInteger rows = _rows ?: (NSInteger)[cells count]; NSArray *col = [self _xefFillCells:cells count:rows];
  if (![g count]) for (NSInteger r = 0; r < rows; r++) [g addObject:[NSMutableArray array]];
  for (NSInteger r = 0; r < rows; r++) { NSMutableArray *row = g[r]; [col[r] setControlView:self]; [row insertObject:col[r] atIndex:i < 0 ? 0 : i > (NSInteger)[row count] ? [row count] : i]; }
  [self _xefStore:g cols:_cols + 1]; }
- (void)addColumnWithCells:(NSArray *)cells { [self insertColumn:_cols withCells:cells]; }
- (void)setState:(NSInteger)s atRow:(NSInteger)r column:(NSInteger)c { [[self cellAtRow:r column:c] setState:s]; [self setNeedsDisplay:YES]; }
- (void)sendAction:(SEL)a to:(id)t forAllCells:(BOOL)all {
  for (NSCell *c in [[(all ? _cells : _selected) copy] autorelease]) [NSApp sendAction:a to:t from:c]; }
- (void)sortUsingSelector:(SEL)sel { [_cells sortUsingSelector:sel]; [self setNeedsDisplay:YES]; }
- (void)sortUsingFunction:(NSInteger (*)(id, id, void *))f context:(void *)ctx { [_cells sortUsingFunction:f context:ctx]; [self setNeedsDisplay:YES]; }
- (void)setSelectionFrom:(NSInteger)from to:(NSInteger)to anchor:(NSInteger)anchor highlight:(BOOL)h {
  NSInteger lo = MIN(from, to), hi = MAX(from, to);
  for (NSCell *c in _selected) [c setState:0]; [_selected removeAllObjects];
  for (NSInteger i = lo; i <= hi && i < (NSInteger)[_cells count]; i++) { if (i < 0) continue; NSCell *c = _cells[i]; if (h) [c setState:1]; [_selected addObject:c]; }
  if ([_selected count]) { NSInteger r, cc; [self getRow:&r column:&cc ofCell:[_selected lastObject]]; _selRow = r; _selCol = cc; } [self setNeedsDisplay:YES]; }
- (BOOL)drawsBackground { return XEFAssocBool(self, "xef.drawsBg", NO); } - (void)setDrawsBackground:(BOOL)f { objc_setAssociatedObject(self, "xef.drawsBg", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); [self setNeedsDisplay:YES]; }
- (NSColor *)backgroundColor { return objc_getAssociatedObject(self, "xef.bg"); } - (void)setBackgroundColor:(NSColor *)c { objc_setAssociatedObject(self, "xef.bg", c, OBJC_ASSOCIATION_RETAIN); [self setNeedsDisplay:YES]; }
- (BOOL)drawsCellBackground { return XEFAssocBool(self, "xef.drawsCellBg", NO); } - (void)setDrawsCellBackground:(BOOL)f { objc_setAssociatedObject(self, "xef.drawsCellBg", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); [self setNeedsDisplay:YES]; }
- (NSColor *)cellBackgroundColor { return objc_getAssociatedObject(self, "xef.cellBg"); } - (void)setCellBackgroundColor:(NSColor *)c { objc_setAssociatedObject(self, "xef.cellBg", c, OBJC_ASSOCIATION_RETAIN); [self setNeedsDisplay:YES]; }
- (BOOL)isAutoscroll { return XEFAssocBool(self, "xef.autoscroll", NO); } - (void)setAutoscroll:(BOOL)f { objc_setAssociatedObject(self, "xef.autoscroll", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); }
- (void)setScrollable:(BOOL)f { objc_setAssociatedObject(self, "xef.scrollable", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); }
- (BOOL)autorecalculatesCellSize { return XEFAssocBool(self, "xef.autorecalc", NO); } - (void)setAutorecalculatesCellSize:(BOOL)f { objc_setAssociatedObject(self, "xef.autorecalc", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); }
- (BOOL)tabKeyTraversesCells { return XEFAssocBool(self, "xef.tabTraverses", YES); } - (void)setTabKeyTraversesCells:(BOOL)f { objc_setAssociatedObject(self, "xef.tabTraverses", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); }
- (id)keyCell { return objc_getAssociatedObject(self, "xef.keyCell"); } - (void)setKeyCell:(id)c { objc_setAssociatedObject(self, "xef.keyCell", c, OBJC_ASSOCIATION_ASSIGN); }
- (id)delegate { return objc_getAssociatedObject(self, "xef.delegate"); } - (void)setDelegate:(id)d { objc_setAssociatedObject(self, "xef.delegate", d, OBJC_ASSOCIATION_ASSIGN); }
- (void)setToolTip:(NSString *)t forCell:(NSCell *)c { NSMutableDictionary *d = objc_getAssociatedObject(self, "xef.tips"); if (!d) { d = [NSMutableDictionary dictionary]; objc_setAssociatedObject(self, "xef.tips", d, OBJC_ASSOCIATION_RETAIN); } NSValue *k = [NSValue valueWithNonretainedObject:c]; if (t) d[k] = t; else [d removeObjectForKey:k]; }
- (NSString *)toolTipForCell:(NSCell *)c { return [objc_getAssociatedObject(self, "xef.tips") objectForKey:[NSValue valueWithNonretainedObject:c]]; }
- (NSString *)view:(NSView *)v stringForToolTip:(NSInteger)tag point:(NSPoint)p userData:(void *)u { NSInteger r, c; return [self getRow:&r column:&c forPoint:p] ? [self toolTipForCell:[self cellAtRow:r column:c]] : nil; }
- (void)drawCellAtRow:(NSInteger)r column:(NSInteger)c { NSCell *cell = [self cellAtRow:r column:c]; if (cell) [cell drawWithFrame:[self cellFrameAtRow:r column:c] inView:self]; }
- (void)highlightCell:(BOOL)f atRow:(NSInteger)r column:(NSInteger)c { [[self cellAtRow:r column:c] setHighlighted:f]; [self setNeedsDisplay:YES]; }
- (void)scrollCellToVisibleAtRow:(NSInteger)r column:(NSInteger)c { [self scrollRectToVisible:[self cellFrameAtRow:r column:c]]; }
- (void)setValidateSize:(BOOL)f {} - (NSInteger)mouseDownFlags { return 0; }
- (void)selectText:(id)s {} - (id)selectTextAtRow:(NSInteger)r column:(NSInteger)c { return [self cellAtRow:r column:c]; }
- (BOOL)textShouldBeginEditing:(NSText *)t { return YES; } - (BOOL)textShouldEndEditing:(NSText *)t { return YES; }
- (void)textDidBeginEditing:(NSNotification *)n {} - (void)textDidEndEditing:(NSNotification *)n {} - (void)textDidChange:(NSNotification *)n {}
- (BOOL)validateUserInterfaceItem:(id)i { return YES; }
@end
@implementation NSCell (XEFCompare)
- (NSComparisonResult)compare:(id)o { if (![o isKindOfClass:[NSCell class]]) return NSOrderedSame; return [[self stringValue] compare:[o stringValue]]; }
@end

/* ---- NSCollectionView: background view, legacy selection / content, supplementary views, moves ---- */
@implementation NSCollectionView (XEFMore)
- (NSView *)backgroundView { return objc_getAssociatedObject(self, "xef.bgview"); }
- (void)setBackgroundView:(NSView *)v {
  NSView *old = [self backgroundView]; if (old == v) return; [old removeFromSuperview];
  objc_setAssociatedObject(self, "xef.bgview", v, OBJC_ASSOCIATION_RETAIN);
  if (v) { [v setFrame:[self bounds]]; [self addSubview:v positioned:-1 relativeTo:nil]; } }
- (BOOL)backgroundViewScrollsWithContent { return [objc_getAssociatedObject(self, "xef.bgscrolls") boolValue]; }
- (void)setBackgroundViewScrollsWithContent:(BOOL)f { objc_setAssociatedObject(self, "xef.bgscrolls", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); }
- (id)prefetchDataSource { return objc_getAssociatedObject(self, "xef.prefetch"); } - (void)setPrefetchDataSource:(id)d { objc_setAssociatedObject(self, "xef.prefetch", d, OBJC_ASSOCIATION_ASSIGN); }
- (NSArray *)content { return objc_getAssociatedObject(self, "xef.content") ?: @[]; } - (void)setContent:(NSArray *)c { objc_setAssociatedObject(self, "xef.content", [[c copy] autorelease], OBJC_ASSOCIATION_RETAIN); }
- (void)setSelectionIndexes:(NSIndexSet *)ix {
  NSMutableSet *s = [NSMutableSet set]; [ix enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) { [s addObject:[NSIndexPath indexPathForItem:i inSection:0]]; }];
  [self setSelectionIndexPaths:s]; }
- (BOOL)isFirstResponder { return [[self window] firstResponder] == self; }
- (NSRect)frameForItemAtIndex:(NSUInteger)i withNumberOfItems:(NSUInteger)n { return [self frameForItemAtIndex:i]; }
- (NSCollectionViewLayoutAttributes *)layoutAttributesForSupplementaryElementOfKind:(NSString *)k atIndexPath:(NSIndexPath *)p { return nil; }
- (NSView *)makeSupplementaryViewOfKind:(NSString *)k withIdentifier:(NSString *)i forIndexPath:(NSIndexPath *)p { return nil; }
- (NSView *)supplementaryViewForElementKind:(NSString *)k atIndexPath:(NSIndexPath *)p { return nil; }
- (NSArray *)visibleSupplementaryViewsOfKind:(NSString *)k { return @[]; }
- (NSSet *)indexPathsForVisibleSupplementaryElementsOfKind:(NSString *)k { return [NSSet set]; }
- (void)moveItemAtIndexPath:(NSIndexPath *)a toIndexPath:(NSIndexPath *)b { [_layout invalidateLayout]; [self setNeedsDisplay:YES]; }
- (void)moveSection:(NSInteger)a toSection:(NSInteger)b { [_layout invalidateLayout]; [self setNeedsDisplay:YES]; }
- (void)toggleSectionCollapse:(id)s {}
- (void)setDraggingSourceOperationMask:(NSUInteger)m forLocal:(BOOL)l {}
- (NSImage *)draggingImageForItemsAtIndexPaths:(NSSet *)p withEvent:(NSEvent *)e offset:(NSPointPointer)o { return nil; }
- (NSImage *)draggingImageForItemsAtIndexes:(NSIndexSet *)i withEvent:(NSEvent *)e offset:(NSPointPointer)o { return nil; }
- (NSUInteger)draggingSession:(id)s sourceOperationMaskForDraggingContext:(NSInteger)c { return 1; }
@end

@implementation NSBrowserCell
- (BOOL)isLeaf { return _leaf; } - (void)setLeaf:(BOOL)f { _leaf = f; } - (BOOL)isLoaded { return _loaded; } - (void)setLoaded:(BOOL)f { _loaded = f; }
- (id)alternateImage { return _alt; } - (void)setAlternateImage:(id)i { [i retain]; [_alt release]; _alt = i; }
- (void)reset { _loaded = NO; } - (void)set {}
+ (id)branchImage { return nil; } + (id)highlightedBranchImage { return nil; }
@end

/* ================================================================== NSRuleEditor */
@interface NSObject (XEFRuleDelegate)
- (NSInteger)ruleEditor:(id)e numberOfChildrenForCriterion:(id)c withRowType:(NSInteger)t; - (id)ruleEditor:(id)e child:(NSInteger)i forCriterion:(id)c withRowType:(NSInteger)t;
- (id)ruleEditor:(id)e displayValueForCriterion:(id)c inRow:(NSInteger)r; - (NSDictionary *)ruleEditor:(id)e predicatePartsForCriterion:(id)c withDisplayValue:(id)v inRow:(NSInteger)r;
- (void)ruleEditorRowsDidChange:(NSNotification *)n;
@end
@implementation NSRuleEditor
- (id)initWithFrame:(NSRect)f {
  if ((self = [super initWithFrame:f])) { _nesting = 2; _rowH = 32; _editable = YES; _canRemoveAll = YES; _rows = [[NSMutableArray alloc] init]; _selRows = [[NSMutableIndexSet alloc] init]; _rowClass = [NSMutableDictionary class];
    _kpType = @"rowType"; _kpSub = @"subrows"; _kpCrit = @"criteria"; _kpDisp = @"displayValues"; }
  return self; }
- (void)dealloc { [_rows release]; [_selRows release]; [_fmtFile release]; [_fmtDict release]; [super dealloc]; }
- (BOOL)isFlipped { return YES; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; [self reloadCriteria]; }
- (NSInteger)nestingMode { return _nesting; } - (void)setNestingMode:(NSInteger)m { _nesting = m; }
- (CGFloat)rowHeight { return _rowH; } - (void)setRowHeight:(CGFloat)h { _rowH = h; [self setNeedsDisplay:YES]; }
- (BOOL)isEditable { return _editable; } - (void)setEditable:(BOOL)f { _editable = f; }
- (BOOL)canRemoveAllRows { return _canRemoveAll; } - (void)setCanRemoveAllRows:(BOOL)f { _canRemoveAll = f; }
- (Class)rowClass { return _rowClass; } - (void)setRowClass:(Class)c { _rowClass = c; }
- (NSString *)rowTypeKeyPath { return _kpType; } - (void)setRowTypeKeyPath:(NSString *)k { [k retain]; [_kpType release]; _kpType = k; }
- (NSString *)subrowsKeyPath { return _kpSub; } - (void)setSubrowsKeyPath:(NSString *)k { [k retain]; [_kpSub release]; _kpSub = k; }
- (NSString *)criteriaKeyPath { return _kpCrit; } - (void)setCriteriaKeyPath:(NSString *)k { [k retain]; [_kpCrit release]; _kpCrit = k; }
- (NSString *)displayValuesKeyPath { return _kpDisp; } - (void)setDisplayValuesKeyPath:(NSString *)k { [k retain]; [_kpDisp release]; _kpDisp = k; }
- (NSString *)formattingStringsFilename { return _fmtFile; } - (void)setFormattingStringsFilename:(NSString *)f { [f retain]; [_fmtFile release]; _fmtFile = f; }
- (NSDictionary *)formattingDictionary { return _fmtDict; } - (void)setFormattingDictionary:(NSDictionary *)d { [d retain]; [_fmtDict release]; _fmtDict = d; }
- (void)reloadCriteria { [self setNeedsDisplay:YES]; } - (void)reloadPredicate {}
/* row records: a mutable dictionary {type, parent (NSNumber row object id as pointer), criteria, display} kept in display order */
- (NSInteger)numberOfRows { return [_rows count]; }
- (NSMutableDictionary *)_xefRow:(NSInteger)i { return i >= 0 && i < (NSInteger)[_rows count] ? _rows[i] : nil; }
- (NSInteger)_xefParentOf:(NSInteger)i { NSMutableDictionary *r = [self _xefRow:i]; if (!r) return -1; id p = r[@"parent"]; if (!p) return -1; NSUInteger k = [_rows indexOfObjectIdenticalTo:p]; return k == NSNotFound ? -1 : (NSInteger)k; }
- (NSInteger)rowTypeForRow:(NSInteger)i { return [[[self _xefRow:i] objectForKey:@"type"] integerValue]; }
- (NSInteger)parentRowForRow:(NSInteger)i { return [self _xefParentOf:i]; }
- (NSArray *)criteriaForRow:(NSInteger)i { return [[self _xefRow:i] objectForKey:@"criteria"]; }
- (NSArray *)displayValuesForRow:(NSInteger)i { return [[self _xefRow:i] objectForKey:@"display"]; }
- (NSInteger)rowForDisplayValue:(id)v { for (NSUInteger i = 0; i < [_rows count]; i++) if ([[_rows[i] objectForKey:@"display"] containsObject:v]) return i; return -1; }
- (NSIndexSet *)subrowIndexesForRow:(NSInteger)i {
  NSMutableIndexSet *s = [NSMutableIndexSet indexSet]; for (NSInteger k = 0; k < (NSInteger)[_rows count]; k++) if ([self _xefParentOf:k] == i) [s addIndex:k]; return s; }
- (NSInteger)_xefSubtreeEnd:(NSInteger)i {   /* index after row i and all its descendants */
  NSInteger e = i + 1; while (e < (NSInteger)[_rows count]) { NSInteger p = [self _xefParentOf:e]; BOOL inside = NO; while (p >= 0) { if (p == i) { inside = YES; break; } p = [self _xefParentOf:p]; } if (!inside) break; e++; } return e; }
- (void)_xefFillRow:(NSMutableDictionary *)row index:(NSInteger)idx {
  NSMutableArray *crit = [NSMutableArray array], *disp = [NSMutableArray array]; NSInteger type = [row[@"type"] integerValue]; id c = nil;
  while ([_delegate respondsToSelector:@selector(ruleEditor:numberOfChildrenForCriterion:withRowType:)] && [_delegate ruleEditor:self numberOfChildrenForCriterion:c withRowType:type] > 0) {
    c = [_delegate ruleEditor:self child:0 forCriterion:c withRowType:type]; if (!c) break; [crit addObject:c];
    id v = [_delegate respondsToSelector:@selector(ruleEditor:displayValueForCriterion:inRow:)] ? [_delegate ruleEditor:self displayValueForCriterion:c inRow:idx] : c; [disp addObject:v ?: c]; }
  row[@"criteria"] = crit; row[@"display"] = disp; }
- (void)_xefChanged { [self setNeedsDisplay:YES]; [[NSNotificationCenter defaultCenter] postNotificationName:@"NSRuleEditorRowsDidChangeNotification" object:self];
  if ([_delegate respondsToSelector:@selector(ruleEditorRowsDidChange:)]) [_delegate ruleEditorRowsDidChange:[NSNotification notificationWithName:@"NSRuleEditorRowsDidChangeNotification" object:self]]; }
- (void)insertRowAtIndex:(NSInteger)idx withType:(NSInteger)type asSubrowOfRow:(NSInteger)parent animate:(BOOL)anim {
  NSMutableDictionary *row = [NSMutableDictionary dictionary]; row[@"type"] = @(type); if (parent >= 0 && parent < (NSInteger)[_rows count]) row[@"parent"] = _rows[parent];
  if (idx < 0) idx = 0; if (idx > (NSInteger)[_rows count]) idx = [_rows count];
  if (parent < 0 && idx < (NSInteger)[_rows count]) { while (idx > 0 && idx < (NSInteger)[_rows count] && [self _xefParentOf:idx] >= 0) idx++; }   /* top-level rows sit after their predecessor's subrows */
  [_rows insertObject:row atIndex:idx]; [self _xefFillRow:row index:idx]; [self _xefChanged]; }
- (void)addRow:(id)sender {
  if (![_rows count] && _nesting >= 2) { [self insertRowAtIndex:0 withType:1 asSubrowOfRow:-1 animate:NO]; [self insertRowAtIndex:1 withType:0 asSubrowOfRow:0 animate:NO]; return; }
  [self insertRowAtIndex:[_rows count] withType:0 asSubrowOfRow:-1 animate:NO]; }
- (void)setCriteria:(NSArray *)c andDisplayValues:(NSArray *)d forRowAtIndex:(NSInteger)i { NSMutableDictionary *r = [self _xefRow:i]; if (!r) return; r[@"criteria"] = [[c copy] autorelease]; r[@"display"] = [[d copy] autorelease]; [self _xefChanged]; }
- (void)removeRowAtIndex:(NSInteger)i { NSMutableDictionary *r = [self _xefRow:i]; if (!r) return; [_selRows removeAllIndexes]; [_rows removeObjectAtIndex:i]; for (NSMutableDictionary *o in _rows) if (o[@"parent"] == r) [o removeObjectForKey:@"parent"]; [self _xefChanged]; }
- (void)removeRowsAtIndexes:(NSIndexSet *)ix includeSubrows:(BOOL)sub {
  NSMutableArray *kill = [NSMutableArray array]; [ix enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) { if (i < [_rows count]) { [kill addObject:_rows[i]]; if (sub) for (NSInteger k = i + 1; k < [self _xefSubtreeEnd:i]; k++) [kill addObject:_rows[k]]; } }];
  [_rows removeObjectsInArray:kill]; for (NSMutableDictionary *o in _rows) if ([kill containsObject:o[@"parent"]]) [o removeObjectForKey:@"parent"];
  [_selRows removeAllIndexes]; [self _xefChanged]; }
- (NSIndexSet *)selectedRowIndexes { return _selRows; }
- (void)selectRowIndexes:(NSIndexSet *)ix byExtendingSelection:(BOOL)ext { if (!ext) [_selRows removeAllIndexes]; [_selRows addIndexes:ix]; [self setNeedsDisplay:YES]; }
- (NSPredicate *)predicateForRow:(NSInteger)i {
  NSMutableDictionary *r = [self _xefRow:i]; if (!r) return nil;
  if ([r[@"type"] integerValue] == 1) {
    NSMutableArray *subs = [NSMutableArray array]; [[self subrowIndexesForRow:i] enumerateIndexesUsingBlock:^(NSUInteger k, BOOL *stop) { NSPredicate *p = [self predicateForRow:k]; if (p) [subs addObject:p]; }];
    return [subs count] ? [NSCompoundPredicate andPredicateWithSubpredicates:subs] : nil; }
  NSExpression *l = nil, *rt = nil; NSNumber *op = nil; NSArray *crit = r[@"criteria"], *disp = r[@"display"];
  for (NSUInteger k = 0; k < [crit count]; k++) {
    NSDictionary *parts = [_delegate respondsToSelector:@selector(ruleEditor:predicatePartsForCriterion:withDisplayValue:inRow:)] ? [_delegate ruleEditor:self predicatePartsForCriterion:crit[k] withDisplayValue:disp[k] inRow:i] : nil;
    if (parts[@"NSRuleEditorPredicateLeftExpression"]) l = parts[@"NSRuleEditorPredicateLeftExpression"];
    if (parts[@"NSRuleEditorPredicateRightExpression"]) rt = parts[@"NSRuleEditorPredicateRightExpression"];
    if (parts[@"NSRuleEditorPredicateOperatorType"]) op = parts[@"NSRuleEditorPredicateOperatorType"]; }
  if (!l || !rt || !op) return nil;
  return [NSComparisonPredicate predicateWithLeftExpression:l rightExpression:rt modifier:NSDirectPredicateModifier type:(NSPredicateOperatorType)[op integerValue] options:0]; }
- (NSPredicate *)predicate {
  NSMutableArray *tops = [NSMutableArray array]; for (NSInteger i = 0; i < (NSInteger)[_rows count]; i++) if ([self _xefParentOf:i] < 0) { NSPredicate *p = [self predicateForRow:i]; if (p) [tops addObject:p]; }
  if (![tops count]) return nil; return [tops count] == 1 ? tops[0] : [NSCompoundPredicate andPredicateWithSubpredicates:tops]; }
- (void)drawRect:(NSRect)r {
  [[NSColor whiteColor] set]; NSRectFill([self bounds]);
  NSDictionary *at = @{ NSFontAttributeName: [NSFont systemFontOfSize:12] };
  for (NSInteger i = 0; i < (NSInteger)[_rows count]; i++) {
    NSInteger depth = 0; for (NSInteger p = [self _xefParentOf:i]; p >= 0; p = [self _xefParentOf:p]) depth++;
    NSRect f = NSMakeRect(8 + depth * 20, i * _rowH, [self bounds].size.width - 16 - depth * 20, _rowH);
    if ([_selRows containsIndex:i]) { [[NSColor selectedControlColor] set]; NSRectFill(NSMakeRect(0, i * _rowH, [self bounds].size.width, _rowH)); }
    [[[self displayValuesForRow:i] componentsJoinedByString:@"  "] drawInRect:NSInsetRect(f, 0, 6) withAttributes:at]; } }
@end

/* ---- NSCollectionViewLayout: the overridable hooks of the base class (all default behaviour: nothing changes, no extra elements) ---- */
@implementation NSCollectionViewLayout (XEFHooks)
+ (Class)layoutAttributesClass { return [NSCollectionViewLayoutAttributes class]; } + (Class)invalidationContextClass { return NSClassFromString(@"NSCollectionViewLayoutInvalidationContext") ?: [NSObject class]; }
- (void)invalidateLayoutWithContext:(id)c { [self invalidateLayout]; }
- (void)registerClass:(Class)c forDecorationViewOfKind:(NSString *)k { NSMutableDictionary *d = objc_getAssociatedObject(self, "xef.decor"); if (!d) { d = [NSMutableDictionary dictionary]; objc_setAssociatedObject(self, "xef.decor", d, OBJC_ASSOCIATION_RETAIN); } if (c) d[k] = c; else [d removeObjectForKey:k]; }
- (void)registerNib:(id)n forDecorationViewOfKind:(NSString *)k { }
- (NSCollectionViewLayoutAttributes *)layoutAttributesForSupplementaryViewOfKind:(NSString *)k atIndexPath:(NSIndexPath *)p { return nil; }
- (NSCollectionViewLayoutAttributes *)layoutAttributesForDecorationViewOfKind:(NSString *)k atIndexPath:(NSIndexPath *)p { return nil; }
- (NSCollectionViewLayoutAttributes *)layoutAttributesForDropTargetAtPoint:(NSPoint)p { return nil; }
- (NSCollectionViewLayoutAttributes *)layoutAttributesForInterItemGapBeforeIndexPath:(NSIndexPath *)p { return nil; }
- (id)invalidationContextForBoundsChange:(NSRect)b { return nil; }
- (BOOL)shouldInvalidateLayoutForPreferredLayoutAttributes:(NSCollectionViewLayoutAttributes *)p withOriginalAttributes:(NSCollectionViewLayoutAttributes *)o { return NO; }
- (id)invalidationContextForPreferredLayoutAttributes:(NSCollectionViewLayoutAttributes *)p withOriginalAttributes:(NSCollectionViewLayoutAttributes *)o { return nil; }
- (NSPoint)targetContentOffsetForProposedContentOffset:(NSPoint)p withScrollingVelocity:(NSPoint)v { return p; } - (NSPoint)targetContentOffsetForProposedContentOffset:(NSPoint)p { return p; }
- (void)prepareForCollectionViewUpdates:(NSArray *)u {} - (void)finalizeCollectionViewUpdates {} - (void)prepareForAnimatedBoundsChange:(NSRect)b {} - (void)finalizeAnimatedBoundsChange {}
- (void)prepareForTransitionToLayout:(NSCollectionViewLayout *)l {} - (void)prepareForTransitionFromLayout:(NSCollectionViewLayout *)l {} - (void)finalizeLayoutTransition {}
- (NSCollectionViewLayoutAttributes *)initialLayoutAttributesForAppearingItemAtIndexPath:(NSIndexPath *)p { return nil; } - (NSCollectionViewLayoutAttributes *)finalLayoutAttributesForDisappearingItemAtIndexPath:(NSIndexPath *)p { return nil; }
- (NSCollectionViewLayoutAttributes *)initialLayoutAttributesForAppearingSupplementaryElementOfKind:(NSString *)k atIndexPath:(NSIndexPath *)p { return nil; } - (NSCollectionViewLayoutAttributes *)finalLayoutAttributesForDisappearingSupplementaryElementOfKind:(NSString *)k atIndexPath:(NSIndexPath *)p { return nil; }
- (NSCollectionViewLayoutAttributes *)initialLayoutAttributesForAppearingDecorationElementOfKind:(NSString *)k atIndexPath:(NSIndexPath *)p { return nil; } - (NSCollectionViewLayoutAttributes *)finalLayoutAttributesForDisappearingDecorationElementOfKind:(NSString *)k atIndexPath:(NSIndexPath *)p { return nil; }
- (NSArray *)indexPathsToDeleteForSupplementaryViewOfKind:(NSString *)k { return @[]; } - (NSArray *)indexPathsToDeleteForDecorationViewOfKind:(NSString *)k { return @[]; }
- (NSArray *)indexPathsToInsertForSupplementaryViewOfKind:(NSString *)k { return @[]; } - (NSArray *)indexPathsToInsertForDecorationViewOfKind:(NSString *)k { return @[]; }
@end

/* ================================================================== NSRulerView / NSRulerMarker */
static NSMutableDictionary *g_ruler_units;
static NSDictionary *XEFRulerUnits(void) {
  if (!g_ruler_units) g_ruler_units = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
    @{ @"abbr": @"in", @"factor": @72.0 }, @"Inches", @{ @"abbr": @"cm", @"factor": @28.3464567 }, @"Centimeters", @{ @"abbr": @"pt", @"factor": @1.0 }, @"Points", @{ @"abbr": @"pc", @"factor": @12.0 }, @"Picas", nil];
  return g_ruler_units; }
@implementation NSRulerMarker
- (id)initWithRulerView:(NSRulerView *)r markerLocation:(CGFloat)l image:(NSImage *)i imageOrigin:(NSPoint)o { if ((self = [super init])) { _ruler = r; _loc = l; _image = [i retain]; _origin = o; _movable = YES; } return self; }
- (void)dealloc { [_image release]; [_rep release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { NSRulerMarker *m = [[NSRulerMarker alloc] initWithRulerView:_ruler markerLocation:_loc image:_image imageOrigin:_origin]; m->_movable = _movable; m->_removable = _removable; return m; }
- (id)initWithCoder:(NSCoder *)c { return [self init]; } - (void)encodeWithCoder:(NSCoder *)c {}
- (NSRulerView *)ruler { return _ruler; } - (CGFloat)markerLocation { return _loc; } - (void)setMarkerLocation:(CGFloat)l { _loc = l; [_ruler setNeedsDisplay:YES]; }
- (NSImage *)image { return _image; } - (void)setImage:(NSImage *)i { [i retain]; [_image release]; _image = i; } - (NSPoint)imageOrigin { return _origin; } - (void)setImageOrigin:(NSPoint)o { _origin = o; }
- (BOOL)isMovable { return _movable; } - (void)setMovable:(BOOL)f { _movable = f; } - (BOOL)isRemovable { return _removable; } - (void)setRemovable:(BOOL)f { _removable = f; } - (BOOL)isDragging { return _dragging; }
- (id)representedObject { return _rep; } - (void)setRepresentedObject:(id)o { [o retain]; [_rep release]; _rep = o; }
- (NSRect)imageRectInRuler { NSSize s = [_image size]; BOOL h = [_ruler orientation] == 0; return h ? NSMakeRect(_loc - _origin.x, [_ruler ruleThickness] - s.height + _origin.y, s.width, s.height) : NSMakeRect(_origin.x, _loc - _origin.y, s.width, s.height); }
- (CGFloat)thicknessRequiredInRuler { NSSize s = [_image size]; return [_ruler orientation] == 0 ? s.height : s.width; }
- (void)drawRect:(NSRect)r { NSRect f = [self imageRectInRuler]; [_image drawInRect:f fromRect:NSZeroRect operation:2 fraction:1]; }
- (BOOL)trackMouse:(NSEvent *)e adding:(BOOL)a { return NO; }
@end
@implementation NSRulerView
+ (void)registerUnitWithName:(NSString *)n abbreviation:(NSString *)a unitToPointsConversionFactor:(CGFloat)f stepUpCycle:(NSArray *)up stepDownCycle:(NSArray *)down { ((NSMutableDictionary *)XEFRulerUnits())[n] = @{ @"abbr": a ?: @"", @"factor": @(f) }; }
- (id)initWithScrollView:(NSScrollView *)s orientation:(NSInteger)o {
  if ((self = [super initWithFrame:NSZeroRect])) { _sv = s; _orient = o; _rule = 17; _markersT = 15; _units = @"Centimeters"; _markers = [[NSMutableArray alloc] init]; } return self; }
- (void)dealloc { [_markers release]; [_accessory release]; [_units release]; [super dealloc]; }
- (BOOL)isFlipped { return YES; }
- (NSScrollView *)scrollView { return _sv; } - (void)setScrollView:(NSScrollView *)s { _sv = s; }
- (NSInteger)orientation { return _orient; } - (void)setOrientation:(NSInteger)o { _orient = o; [self setNeedsDisplay:YES]; }
- (CGFloat)baselineLocation { return 0; }
- (CGFloat)requiredThickness { return _rule + _markersT + _accT; }
- (CGFloat)ruleThickness { return _rule; } - (void)setRuleThickness:(CGFloat)t { _rule = t; }
- (CGFloat)reservedThicknessForMarkers { return _markersT; } - (void)setReservedThicknessForMarkers:(CGFloat)t { _markersT = t; }
- (CGFloat)reservedThicknessForAccessoryView { return _accT; } - (void)setReservedThicknessForAccessoryView:(CGFloat)t { _accT = t; }
- (NSString *)measurementUnits { return _units; } - (void)setMeasurementUnits:(NSString *)u { [u retain]; [_units release]; _units = u; [self setNeedsDisplay:YES]; }
- (CGFloat)originOffset { return _origin; } - (void)setOriginOffset:(CGFloat)o { _origin = o; [self setNeedsDisplay:YES]; }
- (NSView *)clientView { return _client; } - (void)setClientView:(NSView *)v { _client = v; [self setNeedsDisplay:YES]; }
- (NSArray *)markers { return [NSArray arrayWithArray:_markers]; } - (void)setMarkers:(NSArray *)m { [_markers setArray:m ?: @[]]; [self setNeedsDisplay:YES]; }
- (void)addMarker:(NSRulerMarker *)m { if (![_markers containsObject:m]) [_markers addObject:m]; [self setNeedsDisplay:YES]; } - (void)removeMarker:(NSRulerMarker *)m { [_markers removeObject:m]; [self setNeedsDisplay:YES]; }
- (BOOL)trackMarker:(NSRulerMarker *)m withMouseEvent:(NSEvent *)e { return NO; }
- (NSView *)accessoryView { return _accessory; } - (void)setAccessoryView:(NSView *)v { [v retain]; [_accessory release]; _accessory = v; }
- (void)moveRulerlineFromLocation:(CGFloat)a toLocation:(CGFloat)b { [self setNeedsDisplay:YES]; } - (void)invalidateHashMarks { [self setNeedsDisplay:YES]; }
- (void)drawHashMarksAndLabelsInRect:(NSRect)r {
  NSDictionary *ud = [XEFRulerUnits() objectForKey:_units] ?: [XEFRulerUnits() objectForKey:@"Inches"]; CGFloat unit = [[ud objectForKey:@"factor"] doubleValue] ?: 72, len = _orient == 0 ? [self bounds].size.width : [self bounds].size.height;
  [[NSColor grayColor] set]; for (CGFloat v = 0; v * unit - _origin < len; v += 1) { CGFloat pos = v * unit + _origin; if (pos < 0) continue; if (_orient == 0) NSRectFill(NSMakeRect(pos, _rule - 6, 1, 6)); else NSRectFill(NSMakeRect(_rule - 6, pos, 6, 1)); } }
- (void)drawMarkersInRect:(NSRect)r { for (NSRulerMarker *m in _markers) [m drawRect:r]; }
- (void)drawRect:(NSRect)r { [[NSColor colorWithCalibratedWhite:.93 alpha:1] set]; NSRectFill(r); [self drawHashMarksAndLabelsInRect:r]; [self drawMarkersInRect:r]; }
@end

/* ================================================================== Touch Bar model */
@interface NSObject (XEFTouchBarDelegate) - (id)touchBar:(id)tb makeItemForIdentifier:(NSString *)i; @end
@implementation NSTouchBarItem
- (id)initWithIdentifier:(NSString *)i { if ((self = [super init])) _ident = [i copy]; return self; }
- (id)initWithCoder:(NSCoder *)c { return [self initWithIdentifier:[c decodeObjectForKey:@"identifier"]]; } - (void)encodeWithCoder:(NSCoder *)c {}
- (void)dealloc { [_ident release]; [_view release]; [_vc release]; [_label release]; [super dealloc]; }
- (NSString *)identifier { return _ident; } - (float)visibilityPriority { return _prio; } - (void)setVisibilityPriority:(float)p { _prio = p; }
- (id)view { return _view; } - (id)viewController { return _vc; } - (NSString *)customizationLabel { return _label; } - (BOOL)isVisible { return NO; }
@end
@implementation NSCustomTouchBarItem
- (void)setView:(id)v { [v retain]; [_view release]; _view = v; } - (void)setViewController:(id)v { [v retain]; [_vc release]; _vc = v; }
- (void)setCustomizationLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (id)view { return _view ?: [_vc view]; }
@end
@implementation NSGroupTouchBarItem
+ (id)groupItemWithIdentifier:(NSString *)i items:(NSArray *)items {
  NSGroupTouchBarItem *g = [[[self alloc] initWithIdentifier:i] autorelease]; g->_bar = [[NSTouchBar alloc] init]; g->_width = -1;
  NSMutableArray *ids = [NSMutableArray array]; for (NSTouchBarItem *it in items) [ids addObject:[it identifier]];
  [g->_bar setTemplateItems:[NSSet setWithArray:items]]; [g->_bar setDefaultItemIdentifiers:ids]; return g; }
+ (id)alertStyleGroupItemWithIdentifier:(NSString *)i { return [self groupItemWithIdentifier:i items:@[]]; }
+ (id)groupItemWithIdentifier:(NSString *)i items:(NSArray *)items allowedCompressionOptions:(id)o { return [self groupItemWithIdentifier:i items:items]; }
- (void)dealloc { [_bar release]; [super dealloc]; }
- (NSTouchBar *)groupTouchBar { return _bar; } - (void)setGroupTouchBar:(NSTouchBar *)b { [b retain]; [_bar release]; _bar = b; }
- (void)setCustomizationLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (BOOL)prefersEqualWidths { return _equal; } - (void)setPrefersEqualWidths:(BOOL)f { _equal = f; } - (CGFloat)preferredItemWidth { return _width ?: -1; } - (void)setPreferredItemWidth:(CGFloat)w { _width = w; }
- (NSInteger)groupUserInterfaceLayoutDirection { return 0; } - (void)setGroupUserInterfaceLayoutDirection:(NSInteger)d {}
- (id)effectiveCompressionOptions { return nil; } - (NSArray *)prioritizedCompressionOptions { return @[]; } - (void)setPrioritizedCompressionOptions:(NSArray *)o {}
@end
static BOOL g_auto_customize;
@implementation NSTouchBar
- (id)init { if ((self = [super init])) { _default = [@[] retain]; _allowed = [@[] retain]; _required = [@[] retain]; _templates = [[NSSet set] retain]; _cache = [[NSMutableDictionary alloc] init]; } return self; }
- (id)initWithCoder:(NSCoder *)c { return [self init]; } - (void)encodeWithCoder:(NSCoder *)c {}
- (void)dealloc { [_default release]; [_allowed release]; [_required release]; [_templates release]; [_principal release]; [_escape release]; [_custom release]; [_cache release]; [super dealloc]; }
- (NSArray *)defaultItemIdentifiers { return _default; } - (void)setDefaultItemIdentifiers:(NSArray *)a { [a retain]; [_default release]; _default = a ?: [@[] retain]; }
- (NSArray *)itemIdentifiers { return _default; }
- (NSArray *)customizationAllowedItemIdentifiers { return _allowed; } - (void)setCustomizationAllowedItemIdentifiers:(NSArray *)a { [a retain]; [_allowed release]; _allowed = a ?: [@[] retain]; }
- (NSArray *)customizationRequiredItemIdentifiers { return _required; } - (void)setCustomizationRequiredItemIdentifiers:(NSArray *)a { [a retain]; [_required release]; _required = a ?: [@[] retain]; }
- (NSString *)principalItemIdentifier { return _principal; } - (void)setPrincipalItemIdentifier:(NSString *)s { [s retain]; [_principal release]; _principal = s; }
- (NSString *)escapeKeyReplacementItemIdentifier { return _escape; } - (void)setEscapeKeyReplacementItemIdentifier:(NSString *)s { [s retain]; [_escape release]; _escape = s; }
- (NSString *)customizationIdentifier { return _custom; } - (void)setCustomizationIdentifier:(NSString *)s { [s retain]; [_custom release]; _custom = s; }
- (NSSet *)templateItems { return _templates; } - (void)setTemplateItems:(NSSet *)s { [s retain]; [_templates release]; _templates = s ?: [[NSSet set] retain]; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (BOOL)isVisible { return NO; }
- (id)itemForIdentifier:(NSString *)i {
  id c = _cache[i]; if (c) return c;
  for (NSTouchBarItem *t in _templates) if ([[t identifier] isEqualToString:i]) return t;
  id it = [_delegate respondsToSelector:@selector(touchBar:makeItemForIdentifier:)] ? [_delegate touchBar:self makeItemForIdentifier:i] : nil;
  if (!it && ([i hasPrefix:@"NSTouchBarItemIdentifier"])) it = [[[NSTouchBarItem alloc] initWithIdentifier:i] autorelease];
  if (it) _cache[i] = it; return it; }
+ (BOOL)isAutomaticCustomizeTouchBarMenuItemEnabled { return g_auto_customize; } + (void)setAutomaticCustomizeTouchBarMenuItemEnabled:(BOOL)f { g_auto_customize = f; }
@end

/* ================================================================== NSDrawer / NSPrinter */
@interface NSObject (XEFDrawerDelegate) - (BOOL)drawerShouldOpen:(id)d; - (BOOL)drawerShouldClose:(id)d; - (void)drawerWillOpen:(NSNotification *)n; - (void)drawerDidOpen:(NSNotification *)n; - (void)drawerWillClose:(NSNotification *)n; - (void)drawerDidClose:(NSNotification *)n; @end
@implementation NSDrawer
- (id)init { return [self initWithContentSize:NSMakeSize(100, 100) preferredEdge:2]; }
- (id)initWithContentSize:(NSSize)s preferredEdge:(NSUInteger)e {
  if ((self = [super init])) { _size = s; _pref = e; _edge = e; _trail = 15; _max = NSMakeSize(3.40282e+38, 3.40282e+38); _content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, s.width, s.height)]; }
  return self; }
- (void)dealloc { [_timer invalidate]; [_content release]; [super dealloc]; }
- (NSWindow *)parentWindow { return _parent; } - (void)setParentWindow:(NSWindow *)w { _parent = w; }
- (NSView *)contentView { return _content; } - (void)setContentView:(NSView *)v { [v retain]; [_content release]; _content = v; }
- (NSUInteger)preferredEdge { return _pref; } - (void)setPreferredEdge:(NSUInteger)e { _pref = e; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (NSInteger)state { return _state; } - (NSUInteger)edge { return _edge; }
- (NSSize)contentSize { return _size; } - (void)setContentSize:(NSSize)s { _size = NSMakeSize(MIN(MAX(s.width, _min.width), _max.width), MIN(MAX(s.height, _min.height), _max.height)); }
- (NSSize)minContentSize { return _min; } - (void)setMinContentSize:(NSSize)s { _min = s; } - (NSSize)maxContentSize { return _max; } - (void)setMaxContentSize:(NSSize)s { _max = s; }
- (CGFloat)leadingOffset { return _lead; } - (void)setLeadingOffset:(CGFloat)o { _lead = o; } - (CGFloat)trailingOffset { return _trail; } - (void)setTrailingOffset:(CGFloat)o { _trail = o; }
- (void)_xefNote:(NSString *)n sel:(SEL)s { NSNotification *nt = [NSNotification notificationWithName:n object:self]; [[NSNotificationCenter defaultCenter] postNotification:nt]; if ([_delegate respondsToSelector:s]) [_delegate performSelector:s withObject:nt]; }
- (void)_xefFinish { _timer = nil;
  if (_state == 1) { _state = 2; [self _xefNote:@"NSDrawerDidOpenNotification" sel:@selector(drawerDidOpen:)]; }
  else if (_state == 3) { _state = 0; [self _xefNote:@"NSDrawerDidCloseNotification" sel:@selector(drawerDidClose:)]; } }
- (void)_xefAnimate { [_timer invalidate]; _timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(_xefFinish) userInfo:nil repeats:NO]; }
- (void)openOnEdge:(NSUInteger)e { if (_state != 0) return; _edge = e; _state = 1; [self _xefNote:@"NSDrawerWillOpenNotification" sel:@selector(drawerWillOpen:)]; [self _xefAnimate]; }
- (void)open { if (_state == 3) { _state = 1; [self _xefNote:@"NSDrawerWillOpenNotification" sel:@selector(drawerWillOpen:)]; [self _xefAnimate]; return; } [self openOnEdge:_pref]; }
- (void)open:(id)s { if ([_delegate respondsToSelector:@selector(drawerShouldOpen:)] && ![_delegate drawerShouldOpen:self]) return; [self open]; }
- (void)close { if (_state == 0 || _state == 3) return; _state = 3; [self _xefNote:@"NSDrawerWillCloseNotification" sel:@selector(drawerWillClose:)]; [self _xefAnimate]; }
- (void)close:(id)s { if (_state == 3 || _state == 0) return; if ([_delegate respondsToSelector:@selector(drawerShouldClose:)] && ![_delegate drawerShouldClose:self]) return; [self close]; }
- (void)toggle:(id)s { if (_state == 1 || _state == 2) [self close:s]; else [self open:s]; }
@end
@implementation NSPrinter
+ (NSArray *)printerNames { return @[]; } + (NSArray *)printerTypes { return @[]; }
+ (NSPrinter *)printerWithName:(NSString *)n { return nil; } + (NSPrinter *)printerWithType:(NSString *)t { return nil; } + (NSPrinter *)printerWithName:(NSString *)n domain:(NSString *)d includeUnavailable:(BOOL)u { return nil; }
- (NSString *)name { return _name; } - (NSString *)type { return _type; } - (NSInteger)languageLevel { return 2; } - (NSSize)pageSizeForPaper:(NSString *)p { return NSMakeSize(612, 792); } - (NSDictionary *)deviceDescription { return @{}; }
- (NSString *)domain { return @""; } - (NSString *)host { return @""; } - (NSString *)note { return @""; }
- (BOOL)acceptsBinary { return NO; } - (BOOL)isColor { return NO; } - (BOOL)isFontAvailable:(NSString *)f { return NO; } - (BOOL)isOutputStackInReverseOrder { return NO; }
- (NSInteger)statusForTable:(NSString *)t { return 0; } - (BOOL)isKey:(NSString *)k inTable:(NSString *)t { return NO; } - (BOOL)booleanForKey:(NSString *)k inTable:(NSString *)t { return NO; } - (float)floatForKey:(NSString *)k inTable:(NSString *)t { return 0; } - (int)intForKey:(NSString *)k inTable:(NSString *)t { return 0; }
- (NSRect)rectForKey:(NSString *)k inTable:(NSString *)t { return NSZeroRect; } - (NSSize)sizeForKey:(NSString *)k inTable:(NSString *)t { return NSZeroSize; } - (NSString *)stringForKey:(NSString *)k inTable:(NSString *)t { return nil; } - (NSArray *)stringListForKey:(NSString *)k inTable:(NSString *)t { return nil; }
- (NSRect)imageRectForPaper:(NSString *)p { return NSMakeRect(0, 0, 612, 792); }
@end

/* ================================================================== NSDiffableDataSourceSnapshot / NSWorkspaceOpenConfiguration */
@implementation NSDiffableDataSourceSnapshot
- (id)init { if ((self = [super init])) { _secs = [[NSMutableArray alloc] init]; _items = [[NSMutableDictionary alloc] init]; } return self; }
- (void)dealloc { [_secs release]; [_items release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { NSDiffableDataSourceSnapshot *c = [[NSDiffableDataSourceSnapshot alloc] init]; [c->_secs setArray:_secs]; for (id k in _items) c->_items[k] = [NSMutableArray arrayWithArray:_items[k]]; return c; }
- (NSInteger)numberOfSections { return [_secs count]; } - (NSArray *)sectionIdentifiers { return [NSArray arrayWithArray:_secs]; }
- (NSArray *)itemIdentifiers { NSMutableArray *a = [NSMutableArray array]; for (id s in _secs) [a addObjectsFromArray:_items[s]]; return a; }
- (NSInteger)numberOfItems { return [[self itemIdentifiers] count]; }
- (NSInteger)numberOfItemsInSection:(id)s { return [_items[s] count]; }
- (NSArray *)itemIdentifiersInSectionWithIdentifier:(id)s { return [NSArray arrayWithArray:_items[s] ?: @[]]; }
- (id)sectionIdentifierForSectionContainingItemIdentifier:(id)i { for (id s in _secs) if ([_items[s] containsObject:i]) return s; return nil; }
- (NSInteger)indexOfItemIdentifier:(id)i { NSUInteger k = [[self itemIdentifiers] indexOfObject:i]; return k == NSNotFound ? NSNotFound : (NSInteger)k; }
- (NSInteger)indexOfSectionIdentifier:(id)s { NSUInteger k = [_secs indexOfObject:s]; return k == NSNotFound ? NSNotFound : (NSInteger)k; }
- (void)appendItemsWithIdentifiers:(NSArray *)ids { id s = [_secs lastObject]; if (s) [self appendItemsWithIdentifiers:ids intoSectionWithIdentifier:s]; }
- (void)appendItemsWithIdentifiers:(NSArray *)ids intoSectionWithIdentifier:(id)s { NSMutableArray *a = _items[s]; if (!a) return; for (id i in ids) if ([self indexOfItemIdentifier:i] == NSNotFound) [a addObject:i]; }
- (void)_xefInsert:(NSArray *)ids at:(id)ref after:(BOOL)after {
  id s = [self sectionIdentifierForSectionContainingItemIdentifier:ref]; if (!s) return; NSMutableArray *a = _items[s]; NSUInteger k = [a indexOfObject:ref] + (after ? 1 : 0);
  for (id i in ids) if ([self indexOfItemIdentifier:i] == NSNotFound) [a insertObject:i atIndex:k++]; }
- (void)insertItemsWithIdentifiers:(NSArray *)ids beforeItemWithIdentifier:(id)r { [self _xefInsert:ids at:r after:NO]; } - (void)insertItemsWithIdentifiers:(NSArray *)ids afterItemWithIdentifier:(id)r { [self _xefInsert:ids at:r after:YES]; }
- (void)deleteItemsWithIdentifiers:(NSArray *)ids { for (id s in _secs) [_items[s] removeObjectsInArray:ids]; }
- (void)deleteAllItems { [_secs removeAllObjects]; [_items removeAllObjects]; }
- (void)_xefMoveItem:(id)i ref:(id)r after:(BOOL)after { if ([i isEqual:r] || [self indexOfItemIdentifier:i] == NSNotFound || [self indexOfItemIdentifier:r] == NSNotFound) return; [self deleteItemsWithIdentifiers:@[i]]; [self _xefInsert:@[i] at:r after:after]; }
- (void)moveItemWithIdentifier:(id)i beforeItemWithIdentifier:(id)r { [self _xefMoveItem:i ref:r after:NO]; } - (void)moveItemWithIdentifier:(id)i afterItemWithIdentifier:(id)r { [self _xefMoveItem:i ref:r after:YES]; }
- (void)reloadItemsWithIdentifiers:(NSArray *)ids {} - (void)reloadSectionsWithIdentifiers:(NSArray *)ids {}
- (void)appendSectionsWithIdentifiers:(NSArray *)ids { for (id s in ids) if (![_secs containsObject:s]) { [_secs addObject:s]; _items[s] = [NSMutableArray array]; } }
- (void)_xefInsertSections:(NSArray *)ids at:(id)ref after:(BOOL)after { NSUInteger k = [_secs indexOfObject:ref]; if (k == NSNotFound) return; if (after) k++; for (id s in ids) if (![_secs containsObject:s]) { [_secs insertObject:s atIndex:k++]; _items[s] = [NSMutableArray array]; } }
- (void)insertSectionsWithIdentifiers:(NSArray *)ids beforeSectionWithIdentifier:(id)r { [self _xefInsertSections:ids at:r after:NO]; } - (void)insertSectionsWithIdentifiers:(NSArray *)ids afterSectionWithIdentifier:(id)r { [self _xefInsertSections:ids at:r after:YES]; }
- (void)deleteSectionsWithIdentifiers:(NSArray *)ids { for (id s in ids) { [_secs removeObject:s]; [_items removeObjectForKey:s]; } }
- (void)_xefMoveSection:(id)s ref:(id)r after:(BOOL)after { if ([s isEqual:r] || ![_secs containsObject:s] || ![_secs containsObject:r]) return; [_secs removeObject:s]; NSUInteger k = [_secs indexOfObject:r] + (after ? 1 : 0); [_secs insertObject:s atIndex:k]; }
- (void)moveSectionWithIdentifier:(id)s beforeSectionWithIdentifier:(id)r { [self _xefMoveSection:s ref:r after:NO]; } - (void)moveSectionWithIdentifier:(id)s afterSectionWithIdentifier:(id)r { [self _xefMoveSection:s ref:r after:YES]; }
@end
@implementation NSWorkspaceOpenConfiguration
+ (id)configuration { return [[[self alloc] init] autorelease]; }
- (id)init { if ((self = [super init])) { _prompts = _recents = _activates = _substitution = YES; _arch = 4294967295; _args = [@[] retain]; _env = [@{} retain]; } return self; }
- (void)dealloc { [_args release]; [_env release]; [_event release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { NSWorkspaceOpenConfiguration *c = [[NSWorkspaceOpenConfiguration alloc] init]; c->_prompts = _prompts; c->_recents = _recents; c->_activates = _activates; c->_hides = _hides; c->_hidesOthers = _hidesOthers; c->_printing = _printing; c->_newInstance = _newInstance; c->_substitution = _substitution; c->_universal = _universal; c->_arch = _arch; [c setArguments:_args]; [c setEnvironment:_env]; return c; }
- (BOOL)promptsUserIfNeeded { return _prompts; } - (void)setPromptsUserIfNeeded:(BOOL)f { _prompts = f; } - (BOOL)addsToRecentItems { return _recents; } - (void)setAddsToRecentItems:(BOOL)f { _recents = f; }
- (BOOL)activates { return _activates; } - (void)setActivates:(BOOL)f { _activates = f; } - (BOOL)hides { return _hides; } - (void)setHides:(BOOL)f { _hides = f; } - (BOOL)hidesOthers { return _hidesOthers; } - (void)setHidesOthers:(BOOL)f { _hidesOthers = f; }
- (BOOL)isForPrinting { return _printing; } - (void)setForPrinting:(BOOL)f { _printing = f; } - (BOOL)createsNewApplicationInstance { return _newInstance; } - (void)setCreatesNewApplicationInstance:(BOOL)f { _newInstance = f; }
- (BOOL)allowsRunningApplicationSubstitution { return _substitution; } - (void)setAllowsRunningApplicationSubstitution:(BOOL)f { _substitution = f; } - (BOOL)requiresUniversalLinks { return _universal; } - (void)setRequiresUniversalLinks:(BOOL)f { _universal = f; }
- (NSArray *)arguments { return _args; } - (void)setArguments:(NSArray *)a { [a retain]; [_args release]; _args = a ?: [@[] retain]; } - (NSDictionary *)environment { return _env; } - (void)setEnvironment:(NSDictionary *)e { [e retain]; [_env release]; _env = e ?: [@{} retain]; }
- (id)appleEvent { return _event; } - (void)setAppleEvent:(id)e { [e retain]; [_event release]; _event = e; } - (NSInteger)architecture { return _arch; } - (void)setArchitecture:(NSInteger)a { _arch = a; }
@end

/* ================================================================== NSSpeechSynthesizer */
static NSInteger g_speaking_count;
@interface NSObject (XEFSpeechDelegate) - (void)speechSynthesizer:(id)s didFinishSpeaking:(BOOL)ok; @end
@implementation NSSpeechSynthesizer
+ (NSString *)defaultVoice { return @"com.apple.speech.synthesis.voice.Alex"; } + (NSArray *)availableVoices { return @[[self defaultVoice]]; }
+ (NSDictionary *)attributesForVoice:(NSString *)v { return @{ @"VoiceName": [[v componentsSeparatedByString:@"."] lastObject] ?: @"", @"VoiceIdentifier": v ?: @"", @"VoiceLocaleIdentifier": @"en_US", @"VoiceGender": @"VoiceGenderMale" }; }
+ (BOOL)isAnyApplicationSpeaking { return g_speaking_count > 0; }
- (id)init { return [self initWithVoice:nil]; }
- (id)initWithVoice:(NSString *)v { if ((self = [super init])) { _voice = [v ?: [NSSpeechSynthesizer defaultVoice] copy]; _rate = 175; _volume = 1; _props = [[NSMutableDictionary alloc] init]; } return self; }
- (void)dealloc { [_timer invalidate]; [_voice release]; [_props release]; [super dealloc]; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (NSString *)voice { return _voice; } - (BOOL)setVoice:(NSString *)v { [_voice release]; _voice = [v ?: [NSSpeechSynthesizer defaultVoice] copy]; return YES; }
- (float)rate { return _rate; } - (void)setRate:(float)r { _rate = r; } - (float)volume { return _volume; } - (void)setVolume:(float)v { _volume = v; }
- (BOOL)usesFeedbackWindow { return _feedback; } - (void)setUsesFeedbackWindow:(BOOL)f { _feedback = f; }
- (BOOL)isSpeaking { return _speaking; }
- (void)_xefDone:(NSNumber *)ok { if ([_delegate respondsToSelector:@selector(speechSynthesizer:didFinishSpeaking:)]) [_delegate speechSynthesizer:self didFinishSpeaking:[ok boolValue]]; }
- (void)_xefFinish { _timer = nil; if (_speaking) { _speaking = NO; g_speaking_count--; [self _xefDone:@YES]; } }
- (BOOL)startSpeakingString:(NSString *)s {
  if (![s length]) return NO; if (_speaking) [self stopSpeaking];
  NSUInteger words = [[s componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] count]; NSTimeInterval d = MAX(0.2, words * 60.0 / MAX(_rate, 20.0));
  _speaking = YES; g_speaking_count++; _timer = [NSTimer scheduledTimerWithTimeInterval:d target:self selector:@selector(_xefFinish) userInfo:nil repeats:NO]; return YES; }
- (BOOL)startSpeakingString:(NSString *)s toURL:(NSURL *)u { return [self startSpeakingString:s]; }
- (void)stopSpeaking { if (!_speaking) return; [_timer invalidate]; _timer = nil; _speaking = NO; g_speaking_count--; [self performSelector:@selector(_xefDone:) withObject:@NO afterDelay:0]; }
- (void)stopSpeakingAtBoundary:(NSInteger)b { [self stopSpeaking]; } - (void)pauseSpeakingAtBoundary:(NSInteger)b {} - (void)continueSpeaking {}
- (void)addSpeechDictionary:(NSDictionary *)d {} - (NSString *)phonemesFromText:(NSString *)t { return t; }
- (id)objectForProperty:(NSString *)p error:(NSError **)e { return _props[p]; } - (BOOL)setObject:(id)o forProperty:(NSString *)p error:(NSError **)e { if (o) _props[p] = o; else [_props removeObjectForKey:p]; return YES; }
@end
