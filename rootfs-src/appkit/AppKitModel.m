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
