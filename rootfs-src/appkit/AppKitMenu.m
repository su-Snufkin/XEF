/* AppKit-lite menus: NSMenu / NSMenuItem (nib decoding, validation, key equivalents) and pop-up menu windows.
 *
 * There is no global menu bar on the X11 host. Menus appear as override-redirect pop-up windows drawn by AppKit-lite:
 * NSPopUpButton menus, context menus (-menuForEvent:), and the application's main menu, which a right click on any
 * window background opens (the top level lists the main menu's submenus). Key equivalents work as on macOS, with the
 * Control key accepted in place of Command (X11 desktops reserve the Super key). */
#import "AppKitLite.h"
#import "AppKitGraphics.h"
#import "AppKitControls.h"
#include "xef_host.h"
#include <objc/runtime.h>
#include <objc/message.h>
#include <math.h>

NSString *const NSMenuDidAddItemNotification = @"NSMenuDidAddItemNotification";
NSString *const NSMenuDidRemoveItemNotification = @"NSMenuDidRemoveItemNotification";
NSString *const NSMenuDidChangeItemNotification = @"NSMenuDidChangeItemNotification";
NSString *const NSMenuDidSendActionNotification = @"NSMenuDidSendActionNotification";
NSString *const NSMenuWillSendActionNotification = @"NSMenuWillSendActionNotification";
NSString *const NSMenuDidBeginTrackingNotification = @"NSMenuDidBeginTrackingNotification";
NSString *const NSMenuDidEndTrackingNotification = @"NSMenuDidEndTrackingNotification";

static id menu_stub(id self, SEL _cmd, ...) { return nil; }
int XEFStubProbing(void);
BOOL XEFRealRespondsToSelector(id self, SEL a);
void XEFRegisterMenuStub(IMP i);
static BOOL menu_resolve(Class c, SEL sel) {
  if (XEFStubProbing()) return NO;
  const char *n = sel_getName(sel);
  if (n[0] == '_' || !strncmp(n, "respondsTo", 10) || !strncmp(n, "init", 4) || !strncmp(n, "copy", 4) || !strncmp(n, "mutableCopy", 11)) return NO;
  class_addMethod(c, sel, (IMP)menu_stub, "@@:");
  return YES; }

/* ================================================================== NSMenuItem */
@implementation NSMenuItem
+ (BOOL)resolveInstanceMethod:(SEL)sel { return menu_resolve(self, sel); }
+ (void)load { XEFRegisterMenuStub((IMP)menu_stub); }
- (BOOL)respondsToSelector:(SEL)a { return XEFRealRespondsToSelector(self, a); }
+ (NSMenuItem *)separatorItem { NSMenuItem *i = [[[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""] autorelease]; i->_separator = YES; i->_disabled = YES; return i; }
+ (NSMenuItem *)sectionHeaderWithTitle:(NSString *)t { NSMenuItem *i = [[[NSMenuItem alloc] initWithTitle:t action:NULL keyEquivalent:@""] autorelease]; i->_disabled = YES; i->_sectionHeader = YES; return i; }
- (BOOL)isSectionHeader { return _sectionHeader; }
+ (BOOL)usesUserKeyEquivalents { return NO; } + (void)setUsesUserKeyEquivalents:(BOOL)f {}
- (id)init { return [self initWithTitle:@"" action:NULL keyEquivalent:@""]; }
- (id)initWithTitle:(NSString *)t action:(SEL)a keyEquivalent:(NSString *)k {
  if ((self = [super init])) { _title = [t copy] ?: @""; _action = a; _key = [k copy] ?: @""; _mask = NSEventModifierFlagCommand; } return self; }
- (id)initWithCoder:(NSCoder *)c {
  if (!(self = [self initWithTitle:[c decodeObjectForKey:@"NSTitle"] ?: @"" action:NULL keyEquivalent:[c decodeObjectForKey:@"NSKeyEquiv"] ?: @""])) return nil;
  if ([c containsValueForKey:@"NSKeyEquivModMask"]) _mask = (NSUInteger)[c decodeIntegerForKey:@"NSKeyEquivModMask"];
  _state = [c decodeIntegerForKey:@"NSState"];
  _tag = [c decodeIntegerForKey:@"NSTag"];
  _disabled = [c decodeBoolForKey:@"NSIsDisabled"];
  _hidden = [c decodeBoolForKey:@"NSIsHidden"];
  _separator = [c decodeBoolForKey:@"NSIsSeparator"];
  _alternate = [c decodeBoolForKey:@"NSIsAlternate"];
  _indent = [c decodeIntegerForKey:@"NSIndent"];
  id rep = [c decodeObjectForKey:@"NSRepObject"]; if (rep) _rep = [rep retain];
  id sub = [c decodeObjectForKey:@"NSSubmenu"]; if ([sub isKindOfClass:[NSMenu class]]) [self setSubmenu:sub];
  id action = [c decodeObjectForKey:@"NSAction"]; if ([action isKindOfClass:[NSString class]]) _action = NSSelectorFromString(action);
  return self; }
- (void)encodeWithCoder:(NSCoder *)c {}
- (id)copyWithZone:(NSZone *)z {
  NSMenuItem *i = [[NSMenuItem allocWithZone:z] initWithTitle:_title action:_action keyEquivalent:_key];
  i->_mask = _mask; i->_state = _state; i->_tag = _tag; i->_disabled = _disabled; i->_hidden = _hidden; i->_separator = _separator;
  i->_target = _target; i->_rep = [_rep retain]; i->_image = [_image retain]; if (_sub) [i setSubmenu:[[_sub copy] autorelease]];
  return i; }
- (void)dealloc { [_title release]; [_sub release]; [_key release]; [_rep release]; [_image release]; [_onImage release]; [_attrTitle release]; [_toolTip release]; [_view release]; [super dealloc]; }
- (NSString *)title { return _title; } - (void)setTitle:(NSString *)t { [_title release]; _title = [t copy] ?: @""; }
- (NSAttributedString *)attributedTitle { return _attrTitle; } - (void)setAttributedTitle:(NSAttributedString *)t { [_attrTitle release]; _attrTitle = [t copy]; }
- (id)submenu { return _sub; }
- (void)setSubmenu:(id)m { [m retain]; [_sub release]; _sub = m; if (m) ((NSMenu *)m)->_supermenu = _menu; }
- (BOOL)hasSubmenu { return _sub != nil; }
- (NSMenu *)parentItem { return nil; }
- (void)setTarget:(id)t { _target = t; } - (id)target { return _target; }
- (SEL)action { return _action; } - (void)setAction:(SEL)a { _action = a; }
- (NSString *)keyEquivalent { return _key; } - (void)setKeyEquivalent:(NSString *)k { [_key release]; _key = [k copy] ?: @""; }
- (NSUInteger)keyEquivalentModifierMask { return _mask; } - (void)setKeyEquivalentModifierMask:(NSUInteger)m { _mask = m; }
- (NSString *)userKeyEquivalent { return @""; }
- (NSInteger)state { return _state; } - (void)setState:(NSInteger)s { _state = s; }
- (NSInteger)tag { return _tag; } - (void)setTag:(NSInteger)t { _tag = t; }
- (id)representedObject { return _rep; } - (void)setRepresentedObject:(id)o { [o retain]; [_rep release]; _rep = o; }
- (BOOL)isEnabled { return !_disabled; } - (void)setEnabled:(BOOL)f { _disabled = !f; }
- (BOOL)isHidden { return _hidden; } - (void)setHidden:(BOOL)f { _hidden = f; }
- (BOOL)isHiddenOrHasHiddenAncestor { return _hidden; }
- (BOOL)isSeparatorItem { return _separator; }
- (BOOL)isAlternate { return _alternate; } - (void)setAlternate:(BOOL)f { _alternate = f; }
- (BOOL)isHighlighted { return NO; }
- (NSInteger)indentationLevel { return _indent; } - (void)setIndentationLevel:(NSInteger)l { _indent = l; }
- (NSImage *)image { return _image; } - (void)setImage:(NSImage *)i { [i retain]; [_image release]; _image = i; }
- (void)_setActionImage:(NSImage *)i { [self setImage:i]; }   /* SPI (macOS 26 menu item symbols) */
- (NSImage *)onStateImage { return _onImage; } - (void)setOnStateImage:(NSImage *)i { [i retain]; [_onImage release]; _onImage = i; }
- (NSImage *)offStateImage { return nil; } - (void)setOffStateImage:(NSImage *)i {}
- (NSImage *)mixedStateImage { return nil; } - (void)setMixedStateImage:(NSImage *)i {}
- (NSString *)toolTip { return _toolTip; } - (void)setToolTip:(NSString *)t { [_toolTip release]; _toolTip = [t copy]; }
- (NSView *)view { return _view; } - (void)setView:(NSView *)v { [v retain]; [_view release]; _view = v; }
- (NSMenu *)menu { return _menu; } - (void)setMenu:(NSMenu *)m { _menu = m; }
- (BOOL)allowsKeyEquivalentWhenHidden { return NO; } - (void)setAllowsKeyEquivalentWhenHidden:(BOOL)f {}
- (NSString *)description { return [NSString stringWithFormat:@"<NSMenuItem %p %@>", self, _title]; }
/* the key-equivalent label of a pop-up row, e.g. "⌃⇧N" */
- (NSString *)_xefKeyLabel {
  if (![_key length]) return @"";
  NSMutableString *s = [NSMutableString string];
  BOOL shift = (_mask & NSEventModifierFlagShift) || ([_key length] == 1 && [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:[_key characterAtIndex:0]]);
  if (_mask & NSEventModifierFlagControl) [s appendString:@"⌃"];
  if (_mask & NSEventModifierFlagOption) [s appendString:@"⌥"];
  if (shift) [s appendString:@"⇧"];
  if (_mask & NSEventModifierFlagCommand) [s appendString:@"⌘"];
  unichar k = [_key characterAtIndex:0];
  if (k == '\r') [s appendString:@"↩"]; else if (k == 8 || k == 127) [s appendString:@"⌫"]; else if (k == 27) [s appendString:@"⎋"];
  else if (k == '\t') [s appendString:@"⇥"]; else if (k == ' ') [s appendString:@"Space"];
  else [s appendString:[_key uppercaseString]];
  return s; }
@end

/* ================================================================== NSMenu */
@implementation NSMenu
+ (BOOL)resolveInstanceMethod:(SEL)sel { return menu_resolve(self, sel); }
- (BOOL)respondsToSelector:(SEL)a { return XEFRealRespondsToSelector(self, a); }
+ (void)setMenuBarVisible:(BOOL)f {} + (BOOL)menuBarVisible { return NO; }
+ (CGFloat)menuBarHeight { return 0; }
- (id)initWithTitle:(NSString *)t { if ((self = [super init])) { _title = [t copy] ?: @""; _items = [[NSMutableArray alloc] init]; _autoenables = YES; } return self; }
- (id)init { return [self initWithTitle:@""]; }
- (id)initWithCoder:(NSCoder *)c {
  if (!(self = [self initWithTitle:[c decodeObjectForKey:@"NSTitle"] ?: @""])) return nil;
  for (id i in [c decodeObjectForKey:@"NSMenuItems"]) if ([i isKindOfClass:[NSMenuItem class]]) [self addItem:i];
  if ([c containsValueForKey:@"NSNoAutoenable"]) _autoenables = ![c decodeBoolForKey:@"NSNoAutoenable"];
  /* system menus are tagged by name in the nib */
  NSString *name = [c decodeObjectForKey:@"NSName"];
  if ([name isKindOfClass:[NSString class]] && NSApp) {
    if ([name isEqualToString:@"_NSMainMenu"]) [NSApp setMainMenu:self];
    else if ([name isEqualToString:@"_NSWindowsMenu"]) [NSApp setWindowsMenu:self];
    else if ([name isEqualToString:@"_NSServicesMenu"]) [NSApp setServicesMenu:self]; }
  return self; }
- (void)encodeWithCoder:(NSCoder *)c {}
- (id)copyWithZone:(NSZone *)z { NSMenu *m = [[NSMenu allocWithZone:z] initWithTitle:_title]; for (NSMenuItem *i in _items) [m addItem:[[i copy] autorelease]]; return m; }
- (void)dealloc { for (NSMenuItem *i in _items) i->_menu = nil; [_title release]; [_items release]; [_font release]; [super dealloc]; }
- (NSString *)title { return _title; } - (void)setTitle:(NSString *)t { [_title release]; _title = [t copy] ?: @""; }
- (NSArray *)itemArray { return _items; }
- (void)setItemArray:(NSArray *)a { [self removeAllItems]; for (NSMenuItem *i in a) [self addItem:i]; }
- (NSInteger)numberOfItems { return [_items count]; }
- (NSMenuItem *)itemAtIndex:(NSInteger)i { return i >= 0 && i < (NSInteger)[_items count] ? [_items objectAtIndex:i] : nil; }
- (void)insertItem:(NSMenuItem *)i atIndex:(NSInteger)idx {
  if (!i) return;
  if (idx < 0) idx = 0; if (idx > (NSInteger)[_items count]) idx = [_items count];
  [_items insertObject:i atIndex:idx]; i->_menu = self; if (i->_sub) ((NSMenu *)i->_sub)->_supermenu = self; }
- (void)addItem:(NSMenuItem *)i { [self insertItem:i atIndex:[_items count]]; }
- (NSMenuItem *)insertItemWithTitle:(NSString *)t action:(SEL)a keyEquivalent:(NSString *)k atIndex:(NSInteger)idx {
  NSMenuItem *i = [[[NSMenuItem alloc] initWithTitle:t action:a keyEquivalent:k] autorelease]; [self insertItem:i atIndex:idx]; return i; }
- (NSMenuItem *)addItemWithTitle:(NSString *)t action:(SEL)a keyEquivalent:(NSString *)k { return [self insertItemWithTitle:t action:a keyEquivalent:k atIndex:[_items count]]; }
- (void)removeItemAtIndex:(NSInteger)i { if (i >= 0 && i < (NSInteger)[_items count]) { ((NSMenuItem *)[_items objectAtIndex:i])->_menu = nil; [_items removeObjectAtIndex:i]; } }
- (void)removeItem:(NSMenuItem *)i { [self removeItemAtIndex:[self indexOfItem:i]]; }
- (void)removeAllItems { for (NSMenuItem *i in _items) i->_menu = nil; [_items removeAllObjects]; }
- (NSInteger)indexOfItem:(NSMenuItem *)i { NSUInteger x = [_items indexOfObjectIdenticalTo:i]; return x == NSNotFound ? -1 : (NSInteger)x; }
- (NSInteger)indexOfItemWithTitle:(NSString *)t { NSInteger k = 0; for (NSMenuItem *i in _items) { if ([i->_title isEqualToString:t]) return k; k++; } return -1; }
- (NSInteger)indexOfItemWithTag:(NSInteger)t { NSInteger k = 0; for (NSMenuItem *i in _items) { if (i->_tag == t) return k; k++; } return -1; }
- (NSInteger)indexOfItemWithSubmenu:(NSMenu *)m { NSInteger k = 0; for (NSMenuItem *i in _items) { if (i->_sub == m) return k; k++; } return -1; }
- (NSInteger)indexOfItemWithRepresentedObject:(id)o { NSInteger k = 0; for (NSMenuItem *i in _items) { if ([i->_rep isEqual:o]) return k; k++; } return -1; }
- (NSInteger)indexOfItemWithTarget:(id)t andAction:(SEL)a { NSInteger k = 0; for (NSMenuItem *i in _items) { if (i->_target == t && (!a || i->_action == a)) return k; k++; } return -1; }
- (NSMenuItem *)itemWithTitle:(NSString *)t { return [self itemAtIndex:[self indexOfItemWithTitle:t]]; }
- (NSMenuItem *)itemWithTag:(NSInteger)t { return [self itemAtIndex:[self indexOfItemWithTag:t]]; }
- (void)setSubmenu:(NSMenu *)m forItem:(NSMenuItem *)i { [i setSubmenu:m]; }
- (NSMenu *)supermenu { return _supermenu; } - (void)setSupermenu:(NSMenu *)m { _supermenu = m; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (BOOL)autoenablesItems { return _autoenables; } - (void)setAutoenablesItems:(BOOL)f { _autoenables = f; }
- (CGFloat)minimumWidth { return _minWidth; } - (void)setMinimumWidth:(CGFloat)w { _minWidth = w; }
- (NSFont *)font { return _font ?: [NSFont menuFontOfSize:13]; } - (void)setFont:(NSFont *)f { [f retain]; [_font release]; _font = f; }
- (NSSize)size { return NSMakeSize(200, [_items count] * 22 + 10); }
- (BOOL)showsStateColumn { return YES; } - (void)setShowsStateColumn:(BOOL)f {}
- (NSMenuItem *)highlightedItem { return nil; }
- (NSInteger)userInterfaceLayoutDirection { return 0; } - (void)setUserInterfaceLayoutDirection:(NSInteger)d {}
- (void)cancelTracking {} - (void)cancelTrackingWithoutAnimation {}
- (void)itemChanged:(NSMenuItem *)i {}
- (void)setAllowsContextMenuPlugIns:(BOOL)f {}
/* NSMenuValidation: delegate refresh, then enable each item whose action has a validating target */
- (void)update {
  if ([_delegate respondsToSelector:@selector(menuNeedsUpdate:)]) [_delegate menuNeedsUpdate:self];
  if ([_delegate respondsToSelector:@selector(numberOfItemsInMenu:)] && [_delegate respondsToSelector:@selector(menu:updateItem:atIndex:shouldCancel:)]) {
    NSInteger n = ((NSInteger (*)(id, SEL, id))objc_msgSend)(_delegate, @selector(numberOfItemsInMenu:), self);
    while ((NSInteger)[_items count] < n) [self addItemWithTitle:@"" action:NULL keyEquivalent:@""];
    while ((NSInteger)[_items count] > n) [self removeItemAtIndex:[_items count] - 1];
    for (NSInteger i = 0; i < n; i++)
      if (!((BOOL (*)(id, SEL, id, id, NSInteger, BOOL))objc_msgSend)(_delegate, @selector(menu:updateItem:atIndex:shouldCancel:), self, [_items objectAtIndex:i], i, NO)) break; }
  if (!_autoenables) return;
  for (NSMenuItem *i in _items) {
    if (i->_separator || i->_sectionHeader) continue;
    if (i->_sub) { i->_disabled = NO; continue; }
    if (!i->_action) { i->_disabled = YES; continue; }
    id t = [NSApp targetForAction:i->_action to:i->_target from:i];
    BOOL ok = t != nil;
    if (ok && [t respondsToSelector:@selector(validateMenuItem:)]) ok = [t validateMenuItem:i];
    else if (ok && [t respondsToSelector:@selector(validateUserInterfaceItem:)]) ok = [t validateUserInterfaceItem:(id)i];
    i->_disabled = !ok; } }
- (void)performActionForItemAtIndex:(NSInteger)idx {
  NSMenuItem *i = [self itemAtIndex:idx];
  if (!i || !i->_action) return;
  [[NSNotificationCenter defaultCenter] postNotificationName:NSMenuWillSendActionNotification object:self userInfo:@{ @"MenuItem": i }];
  [NSApp sendAction:i->_action to:i->_target from:i];
  [[NSNotificationCenter defaultCenter] postNotificationName:NSMenuDidSendActionNotification object:self userInfo:@{ @"MenuItem": i }]; }
/* key equivalents (depth first). Control stands in for Command on X11 when the item wants Command. */
static BOOL key_matches(NSMenuItem *i, NSEvent *e, BOOL ctrlAsCmd) {
  if (![i->_key length] || i->_separator) return NO;
  NSString *k = i->_key;
  NSUInteger have = [e modifierFlags] & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift);
  if (ctrlAsCmd && (have & NSEventModifierFlagControl) && !(have & NSEventModifierFlagCommand)) have = (have & ~NSEventModifierFlagControl) | NSEventModifierFlagCommand;
  NSUInteger want = i->_mask & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift);
  unichar kc = [k characterAtIndex:0];
  if ([k length] == 1 && [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:kc]) { want |= NSEventModifierFlagShift; k = [k lowercaseString]; }
  NSString *c = [[e charactersIgnoringModifiers] lowercaseString];
  BOOL keyOK = [k isEqualToString:c] || (kc == '\r' && ([e keyCode] == 36 || [e keyCode] == 76)) || ((kc == 8 || kc == 127) && [e keyCode] == 51) || (kc == 27 && [e keyCode] == 53);
  if (!keyOK) return NO;
  if ((want & NSEventModifierFlagShift) == 0 && (have & NSEventModifierFlagShift) && ![[e characters] isEqualToString:[e charactersIgnoringModifiers]]) have &= ~NSEventModifierFlagShift;   /* shifted symbol keys */
  return want == have; }
- (NSMenuItem *)_xefItemForKeyEquivalent:(NSEvent *)e ctrlAsCmd:(BOOL)cc {
  [self update];
  for (NSMenuItem *i in _items) {
    if (i->_sub) { NSMenuItem *f = [(NSMenu *)i->_sub _xefItemForKeyEquivalent:e ctrlAsCmd:cc]; if (f) return f; continue; }
    if (!i->_disabled && key_matches(i, e, cc)) return i; }
  return nil; }
- (BOOL)performKeyEquivalent:(NSEvent *)e {
  NSMenuItem *i = [self _xefItemForKeyEquivalent:e ctrlAsCmd:NO];
  if (!i && ([e modifierFlags] & NSEventModifierFlagControl)) i = [self _xefItemForKeyEquivalent:e ctrlAsCmd:YES];
  if (!i) return NO;
  [i->_menu performActionForItemAtIndex:[i->_menu indexOfItem:i]];
  return YES; }
+ (void)popUpContextMenu:(NSMenu *)m withEvent:(NSEvent *)e forView:(NSView *)v {
  NSPoint p = [v convertPoint:[e locationInWindow] fromView:nil];
  NSMenuItem *i = [m _xefPopUpPositioningItem:nil atLocation:p inView:v minWidth:0];
  if (i && i->_action) [i->_menu performActionForItemAtIndex:[i->_menu indexOfItem:i]]; }
+ (void)popUpContextMenu:(NSMenu *)m withEvent:(NSEvent *)e forView:(NSView *)v withFont:(NSFont *)f { [self popUpContextMenu:m withEvent:e forView:v]; }
- (BOOL)popUpMenuPositioningItem:(NSMenuItem *)item atLocation:(NSPoint)p inView:(NSView *)v {
  NSMenuItem *i = [self _xefPopUpPositioningItem:item atLocation:p inView:v minWidth:0];
  if (i && i->_action) [i->_menu performActionForItemAtIndex:[i->_menu indexOfItem:i]];
  return i != nil; }
@end

/* ================================================================== pop-up menu windows */
#define ROW_H 22.0
#define SEP_H 11.0
#define PAD_Y 5.0

@interface XEFMenuView : NSView { @public NSMenu *_m; NSInteger _hl; CGFloat _keyCol; }
@end
@implementation XEFMenuView
- (BOOL)isFlipped { return YES; }
- (NSArray *)_visible { NSMutableArray *a = [NSMutableArray array]; for (NSMenuItem *i in _m->_items) if (!i->_hidden && !i->_alternate) [a addObject:i]; return a; }
- (NSRect)_rectOf:(NSInteger)idx {
  CGFloat y = PAD_Y; NSArray *v = [self _visible];
  for (NSInteger k = 0; k < (NSInteger)[v count]; k++) {
    NSMenuItem *i = [v objectAtIndex:k]; CGFloat h = i->_separator ? SEP_H : ROW_H;
    if (k == idx) return NSMakeRect(0, y, _bounds.size.width, h);
    y += h; }
  return NSZeroRect; }
- (NSInteger)_indexAt:(NSPoint)p {
  if (!NSPointInRect(p, _bounds)) return -1;
  NSArray *v = [self _visible];
  for (NSInteger k = 0; k < (NSInteger)[v count]; k++) if (NSPointInRect(p, [self _rectOf:k])) return k;
  return -1; }
- (NSMenuItem *)_itemAt:(NSInteger)k { NSArray *v = [self _visible]; return k >= 0 && k < (NSInteger)[v count] ? [v objectAtIndex:k] : nil; }
- (void)drawRect:(NSRect)r {
  [[NSColor colorWithCalibratedWhite:0.97 alpha:1] setFill]; NSRectFill(_bounds);
  [[NSColor colorWithCalibratedWhite:0.7 alpha:1] setFill]; NSFrameRect(_bounds);
  NSFont *f = [_m font];
  NSArray *v = [self _visible];
  for (NSInteger k = 0; k < (NSInteger)[v count]; k++) {
    NSMenuItem *i = [v objectAtIndex:k]; NSRect row = [self _rectOf:k];
    if (i->_separator) { [[NSColor colorWithCalibratedWhite:0.82 alpha:1] setFill]; NSRectFill(NSMakeRect(10, NSMidY(row), row.size.width - 20, 1)); continue; }
    BOOL hl = k == _hl && !i->_disabled;
    if (i->_sectionHeader) { [i->_title drawAtPoint:NSMakePoint(12, row.origin.y + (ROW_H - [f _xefLineHeight]) / 2)
                                   withAttributes:@{ NSFontAttributeName: [NSFont boldSystemFontOfSize:11], NSForegroundColorAttributeName: [NSColor secondaryLabelColor] }]; continue; }
    if (hl) { [[NSColor controlAccentColor] setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(row, 5, 0) xRadius:4 yRadius:4] fill]; }
    NSColor *tc = i->_disabled ? [NSColor disabledControlTextColor] : hl ? [NSColor whiteColor] : [NSColor controlTextColor];
    NSDictionary *a = @{ NSFontAttributeName: f, NSForegroundColorAttributeName: tc };
    CGFloat ty = row.origin.y + (ROW_H - [f _xefLineHeight]) / 2;
    if (i->_state == 1) [@"✓" drawAtPoint:NSMakePoint(9, ty) withAttributes:a];
    else if (i->_state == -1) [@"–" drawAtPoint:NSMakePoint(9, ty) withAttributes:a];
    CGFloat x = 24 + i->_indent * 10;
    if (i->_image) { NSSize s = [i->_image size]; CGFloat h = fmin(s.height, 16), w = s.height > 0 ? s.width * h / s.height : 0;
      [i->_image drawInRect:NSMakeRect(x, NSMidY(row) - h / 2, w, h)]; x += w + 5; }
    if (i->_attrTitle) [i->_attrTitle drawAtPoint:NSMakePoint(x, ty)];
    else [i->_title drawAtPoint:NSMakePoint(x, ty) withAttributes:a];
    if (i->_sub) [@"▸" drawAtPoint:NSMakePoint(row.size.width - 20, ty) withAttributes:a];
    else { NSString *kl = [i _xefKeyLabel];
      if ([kl length]) { NSSize ks = [kl sizeWithAttributes:a]; [kl drawAtPoint:NSMakePoint(row.size.width - 14 - ks.width, ty) withAttributes:a]; } } } }
@end

@interface XEFMenuWindow : NSWindow { @public XEFMenuView *_mv; }
@end
@implementation XEFMenuWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

/* size of a menu's pop-up */
static NSSize menu_size(NSMenu *m, CGFloat minWidth) {
  NSFont *f = [m font]; NSDictionary *a = @{ NSFontAttributeName: f };
  CGFloat w = 0, kw = 0, h = 2 * PAD_Y;
  for (NSMenuItem *i in m->_items) {
    if (i->_hidden || i->_alternate) continue;
    if (i->_separator) { h += SEP_H; continue; }
    h += ROW_H;
    CGFloat tw = (i->_attrTitle ? [i->_attrTitle size].width : [i->_title sizeWithAttributes:a].width) + i->_indent * 10 + (i->_image ? 21 : 0);
    w = fmax(w, tw);
    kw = fmax(kw, i->_sub ? 16 : [[i _xefKeyLabel] sizeWithAttributes:a].width); }
  w = ceil(w + 24 + (kw > 0 ? kw + 30 : 16));
  return NSMakeSize(fmax(w, fmax(minWidth, m->_minWidth)), h); }

static XEFMenuWindow *open_menu_window(NSMenu *m, NSPoint screenTopLeft, CGFloat minWidth) {
  [m update];
  NSSize s = menu_size(m, minWidth);
  NSRect scr = [[NSScreen mainScreen] frame];
  NSRect fr = NSMakeRect(screenTopLeft.x, screenTopLeft.y - s.height, s.width, s.height);
  if (NSMaxX(fr) > NSMaxX(scr)) fr.origin.x = NSMaxX(scr) - fr.size.width;
  if (fr.origin.y < scr.origin.y) fr.origin.y = scr.origin.y;
  if (fr.origin.x < 0) fr.origin.x = 0;
  XEFMenuWindow *w = [[XEFMenuWindow alloc] initWithContentRect:fr styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  xef_host_window_set_popup([w xefHandle], 1);
  objc_setAssociatedObject(w, "xef.popup", @YES, OBJC_ASSOCIATION_RETAIN);
  [w setReleasedWhenClosed:NO];
  XEFMenuView *v = [[XEFMenuView alloc] initWithFrame:NSMakeRect(0, 0, fr.size.width, fr.size.height)];
  v->_m = m; v->_hl = -1; w->_mv = v;
  [w setContentView:v]; [v release];
  [w orderFront:nil];
  [w _xefRedraw];
  return w; }

/* screen point of an event (window base coordinates + window origin) */
static NSPoint event_screen_point(NSEvent *e) {
  NSWindow *w = [e window]; NSPoint p = [e locationInWindow];
  if (!w) return p;
  NSRect c = [w contentRectForFrameRect:[w frame]];
  return NSMakePoint(c.origin.x + p.x, c.origin.y + p.y); }

@implementation NSMenu (XEFPopUp)
/* modal pop-up: returns the chosen item (enabled, without submenu) or nil when cancelled */
- (NSMenuItem *)_xefPopUpPositioningItem:(NSMenuItem *)item atLocation:(NSPoint)p inView:(NSView *)v minWidth:(CGFloat)minWidth {
  if (![_items count]) return nil;
  [[NSNotificationCenter defaultCenter] postNotificationName:NSMenuDidBeginTrackingNotification object:self];
  if ([_delegate respondsToSelector:@selector(menuWillOpen:)]) [_delegate menuWillOpen:self];
  NSPoint top;   /* screen top-left of the pop-up */
  if (v) {
    NSWindow *w = [v window];
    NSPoint wp = [v convertPoint:p toView:nil];
    NSRect c = [w contentRectForFrameRect:[w frame]];
    top = NSMakePoint(c.origin.x + wp.x, c.origin.y + wp.y);
  } else top = p;
  if (item) {   /* the positioning item lands at the location: shift up by its offset */
    CGFloat off = PAD_Y;
    for (NSMenuItem *i in _items) { if (i == item) break; if (!i->_hidden && !i->_alternate) off += i->_separator ? SEP_H : ROW_H; }
    top.y += off; }
  NSMutableArray *stack = [NSMutableArray array];   /* open menu windows, outermost first */
  XEFMenuWindow *root = open_menu_window(self, top, minWidth);
  [stack addObject:root]; [root release];
  if (item) { XEFMenuView *mv = root->_mv; NSArray *vis = [mv _visible]; mv->_hl = [vis indexOfObjectIdenticalTo:item]; if (mv->_hl == (NSInteger)NSNotFound) mv->_hl = -1; [root _xefRedraw]; }
  xef_host_grab_pointer([root xefHandle], 1);
  NSMenuItem *chosen = nil;
  double opened = [NSDate timeIntervalSinceReferenceDate];
  BOOL done = NO, moved = NO;
  NSUInteger mask = (1 << NSEventTypeLeftMouseDown) | (1 << NSEventTypeLeftMouseUp) | (1 << NSEventTypeRightMouseDown) | (1 << NSEventTypeRightMouseUp) |
                    (1 << NSEventTypeMouseMoved) | (1 << NSEventTypeLeftMouseDragged) | (1 << NSEventTypeRightMouseDragged) | (1 << NSEventTypeKeyDown) |
                    (1 << NSEventTypeOtherMouseDown);
  while (!done) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSEvent *e = [NSApp nextEventMatchingMask:mask untilDate:[NSDate distantFuture] inMode:@"NSEventTrackingRunLoopMode" dequeue:YES];
    if (!e) { [pool drain]; continue; }
    NSEventType t = [e type];
    if (t == NSEventTypeKeyDown) {
      XEFMenuWindow *top = [stack lastObject]; XEFMenuView *mv = top->_mv; NSArray *vis = [mv _visible];
      unsigned short kc = [e keyCode];
      if (kc == 53) done = YES;                                   /* Esc */
      else if (kc == 126 || kc == 125) {                          /* up / down: next enabled row */
        NSInteger n = [vis count], k = mv->_hl;
        for (NSInteger step = 0; step < n; step++) {
          k = kc == 125 ? (k + 1) % n : (k <= 0 ? n - 1 : k - 1);
          NSMenuItem *i = [vis objectAtIndex:k]; if (!i->_separator && !i->_disabled) break; }
        mv->_hl = k; [top _xefRedraw]; }
      else if (kc == 123 && [stack count] > 1) { [top close]; [stack removeLastObject]; }
      else if ((kc == 124 || kc == 36 || kc == 76 || kc == 49) && mv->_hl >= 0) {
        NSMenuItem *i = [mv _itemAt:mv->_hl];
        if (i->_sub) { NSRect r = [mv _rectOf:mv->_hl]; NSRect c = [top contentRectForFrameRect:[top frame]];
          XEFMenuWindow *sub = open_menu_window(i->_sub, NSMakePoint(NSMaxX(c) - 4, NSMaxY(c) - r.origin.y + PAD_Y), 0);
          [stack addObject:sub]; [sub release]; }
        else if (kc != 124 && !i->_disabled) { chosen = i; done = YES; } }
      [pool drain]; continue; }
    NSPoint sp = event_screen_point(e);
    /* the innermost menu window under the pointer */
    NSInteger level = -1; NSInteger row = -1;
    for (NSInteger k = [stack count] - 1; k >= 0; k--) {
      XEFMenuWindow *mw = [stack objectAtIndex:k];
      NSRect c = [mw contentRectForFrameRect:[mw frame]];
      if (NSPointInRect(sp, c)) { level = k; row = [mw->_mv _indexAt:NSMakePoint(sp.x - c.origin.x, NSMaxY(c) - sp.y)]; break; } }
    if (t == NSEventTypeMouseMoved || t == NSEventTypeLeftMouseDragged || t == NSEventTypeRightMouseDragged) {
      moved = YES;
      if (level >= 0) {
        while ((NSInteger)[stack count] - 1 > level) { [[stack lastObject] close]; [stack removeLastObject]; }
        XEFMenuWindow *mw = [stack objectAtIndex:level]; XEFMenuView *mv = mw->_mv;
        if (mv->_hl != row) {
          mv->_hl = row; [mw _xefRedraw];
          NSMenuItem *i = [mv _itemAt:row];
          if (i && i->_sub && !i->_disabled) {
            NSRect r = [mv _rectOf:row]; NSRect c = [mw contentRectForFrameRect:[mw frame]];
            XEFMenuWindow *sub = open_menu_window(i->_sub, NSMakePoint(NSMaxX(c) - 4, NSMaxY(c) - r.origin.y + PAD_Y), 0);
            [stack addObject:sub]; [sub release]; } } }
      [pool drain]; continue; }
    BOOL up = t == NSEventTypeLeftMouseUp || t == NSEventTypeRightMouseUp;
    BOOL down = t == NSEventTypeLeftMouseDown || t == NSEventTypeRightMouseDown || t == NSEventTypeOtherMouseDown;
    if (level < 0) {
      /* outside every menu: a press cancels; the release of the opening click (press-drag-release) is ignored */
      if (down || (up && moved && [NSDate timeIntervalSinceReferenceDate] - opened > 0.3)) done = YES;
      [pool drain]; continue; }
    NSMenuItem *i = [((XEFMenuWindow *)[stack objectAtIndex:level])->_mv _itemAt:row];
    if (up && (moved || [NSDate timeIntervalSinceReferenceDate] - opened > 0.3) && i && !i->_separator && !i->_disabled && !i->_sub) { chosen = i; done = YES; }
    [pool drain]; }
  xef_host_grab_pointer(0, 0);
  for (XEFMenuWindow *w in [stack reverseObjectEnumerator]) [w close];
  if ([_delegate respondsToSelector:@selector(menuDidClose:)]) [_delegate menuDidClose:self];
  [[NSNotificationCenter defaultCenter] postNotificationName:NSMenuDidEndTrackingNotification object:self];
  return chosen; }
@end

/* ================================================================== context menus and the main menu */
@implementation NSView (XEFContextMenu)
- (NSMenu *)menuForEvent:(NSEvent *)e { return [self menu]; }
- (void)rightMouseDown:(NSEvent *)e {
  NSMenu *m = [self menuForEvent:e];
  if (m) { [NSMenu popUpContextMenu:m withEvent:e forView:self]; return; }
  [[self nextResponder] rightMouseDown:e]; }
- (void)willOpenMenu:(NSMenu *)m withEvent:(NSEvent *)e {} - (void)didCloseMenu:(NSMenu *)m withEvent:(NSEvent *)e {}
@end

@implementation NSWindow (XEFMainMenu)
/* no menu bar on the host: an unhandled right click opens the main menu (its submenus as the first level) */
- (void)rightMouseDown:(NSEvent *)e {
  NSMenu *main = [NSApp mainMenu];
  if (![main->_items count]) return;
  NSMenu *top = [[[NSMenu alloc] initWithTitle:@""] autorelease];
  for (NSMenuItem *i in main->_items) {
    if (i->_hidden || !i->_sub) continue;
    NSString *t = [i->_title length] ? i->_title : [(NSMenu *)i->_sub title];
    if (![t length] || [t isEqualToString:@"Apple"]) t = [[NSProcessInfo processInfo] processName];
    NSMenuItem *p = [[[NSMenuItem alloc] initWithTitle:t action:NULL keyEquivalent:@""] autorelease];
    p->_sub = [i->_sub retain];   /* shared, the submenu keeps its supermenu */
    [top->_items addObject:p]; p->_menu = top; }
  NSMenuItem *chosen = [top _xefPopUpPositioningItem:nil atLocation:[e locationInWindow] inView:_content minWidth:0];
  for (NSMenuItem *p in top->_items) p->_menu = nil;
  if (chosen && chosen->_action) [chosen->_menu performActionForItemAtIndex:[chosen->_menu indexOfItem:chosen]]; }
@end

@implementation NSApplication (XEFMenus)
/* key equivalents: key window views first, then the main menu */
- (BOOL)_xefHandleKeyEquivalent:(NSEvent *)e {
  if (!([e modifierFlags] & (NSEventModifierFlagCommand | NSEventModifierFlagControl))) return NO;
  NSWindow *k = [self keyWindow];
  if (k && [k performKeyEquivalent:e]) return YES;
  return [[self mainMenu] performKeyEquivalent:e]; }
- (NSMenu *)windowsMenu { return _windowsMenu; }
- (NSMenu *)servicesMenu { return _services; }
- (NSMenu *)helpMenu { return nil; }
- (void)addWindowsItem:(NSWindow *)w title:(NSString *)t filename:(BOOL)f {} - (void)removeWindowsItem:(NSWindow *)w {}
- (void)changeWindowsItem:(NSWindow *)w title:(NSString *)t filename:(BOOL)f {}
- (void)updateWindowsItem:(NSWindow *)w {}
@end

/* ================================================================== the menu bar */
/* A strip at the top-left of the screen with the main menu's titles (the X11 host has no global menu bar); clicking a
 * title drops its menu down. XEF_MENUBAR=0 disables it (the right-click main menu stays available). */
@interface XEFMenuBarView : NSView { @public NSInteger _hl; }
@end
@implementation XEFMenuBarView
- (BOOL)isFlipped { return YES; }
- (NSArray *)_titles {
  NSMutableArray *a = [NSMutableArray array];
  for (NSMenuItem *i in [[NSApp mainMenu] itemArray]) {
    if (i->_hidden || !i->_sub) continue;
    NSString *t = [i->_title length] ? i->_title : [(NSMenu *)i->_sub title];
    if (![a count] || ![t length] || [t isEqualToString:@"Apple"]) t = [[NSProcessInfo processInfo] processName];
    [a addObject:@[t, i]]; }
  return a; }
- (NSArray *)_rects {
  NSMutableArray *r = [NSMutableArray array]; CGFloat x = 8; BOOL first = YES;
  for (NSArray *t in [self _titles]) {
    NSFont *f = first ? [NSFont boldSystemFontOfSize:13] : [NSFont menuBarFontOfSize:13];
    CGFloat w = [[t objectAtIndex:0] sizeWithAttributes:@{ NSFontAttributeName: f }].width + 18;
    [r addObject:[NSValue valueWithRect:NSMakeRect(x, 0, w, _bounds.size.height)]]; x += w; first = NO; }
  return r; }
- (CGFloat)_width { NSRect last = [[[self _rects] lastObject] rectValue]; return NSMaxX(last) + 8; }
- (void)drawRect:(NSRect)r {
  [[NSColor colorWithCalibratedWhite:0.96 alpha:1] setFill]; NSRectFill(_bounds);
  [[NSColor colorWithCalibratedWhite:0.75 alpha:1] setFill]; NSRectFill(NSMakeRect(0, _bounds.size.height - 1, _bounds.size.width, 1));
  NSArray *t = [self _titles], *rs = [self _rects];
  for (NSUInteger k = 0; k < [t count]; k++) {
    NSRect rr = [[rs objectAtIndex:k] rectValue];
    if ((NSInteger)k == _hl) { [[NSColor controlAccentColor] setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rr, 1, 2) xRadius:4 yRadius:4] fill]; }
    NSFont *f = k == 0 ? [NSFont boldSystemFontOfSize:13] : [NSFont menuBarFontOfSize:13];
    NSDictionary *a = @{ NSFontAttributeName: f, NSForegroundColorAttributeName: (NSInteger)k == _hl ? [NSColor whiteColor] : [NSColor controlTextColor] };
    [[[t objectAtIndex:k] objectAtIndex:0] drawAtPoint:NSMakePoint(rr.origin.x + 9, (_bounds.size.height - [f _xefLineHeight]) / 2) withAttributes:a]; } }
- (void)mouseDown:(NSEvent *)e {
  NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
  NSArray *t = [self _titles], *rs = [self _rects];
  for (NSUInteger k = 0; k < [t count]; k++) {
    NSRect rr = [[rs objectAtIndex:k] rectValue];
    if (!NSPointInRect(p, rr)) continue;
    _hl = k; XEFRedrawWindowNow(_window);
    NSMenuItem *owner = [[t objectAtIndex:k] objectAtIndex:1];
    NSMenuItem *chosen = [(NSMenu *)owner->_sub _xefPopUpPositioningItem:nil atLocation:NSMakePoint(rr.origin.x, NSMaxY(rr)) inView:self minWidth:0];
    _hl = -1; XEFRedrawWindowNow(_window);
    if (chosen && chosen->_action) [chosen->_menu performActionForItemAtIndex:[chosen->_menu indexOfItem:chosen]];
    return; } }
@end

@interface XEFMenuBarWindow : NSWindow
@end
@implementation XEFMenuBarWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
- (void)rightMouseDown:(NSEvent *)e {}
@end

static XEFMenuBarWindow *g_menubar;
@implementation NSApplication (XEFMenuBar)
- (void)_xefUpdateMenuBar {
  if (getenv("XEF_APPKIT_DEBUG")) NSLog(@"xef: menu bar: main menu %@ (%lu items)", [self mainMenu], (unsigned long)[[[self mainMenu] itemArray] count]);
  const char *env = getenv("XEF_MENUBAR");
  if ((env && env[0] == '0') || ![[[self mainMenu] itemArray] count]) return;
  if (!g_menubar) {
    XEFMenuBarView *v = [[[XEFMenuBarView alloc] initWithFrame:NSMakeRect(0, 0, 400, 24)] autorelease]; v->_hl = -1;
    CGFloat w = [v _width];
    NSRect scr = [[NSScreen mainScreen] frame];
    g_menubar = [[XEFMenuBarWindow alloc] initWithContentRect:NSMakeRect(0, NSMaxY(scr) - 24, w, 24) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    xef_host_window_set_popup([g_menubar xefHandle], 1);
    objc_setAssociatedObject(g_menubar, "xef.popup", @YES, OBJC_ASSOCIATION_RETAIN);
    [g_menubar setReleasedWhenClosed:NO];
    [v setFrame:NSMakeRect(0, 0, w, 24)];
    [g_menubar setContentView:v];
    [g_menubar orderFront:nil]; }
  [g_menubar _xefRedraw]; }
@end
