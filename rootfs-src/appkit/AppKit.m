/* AppKit-lite: small AppKit/NSOpenGL implementation for xef-osx. MRC (no ARC). */
#import "AppKitLite.h"
#include "xef_host.h"
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <Block.h>
#include <stdio.h>
#include <objc/message.h>
#include <objc/runtime.h>

id NSApp = nil;
NSString *const NSWindowWillCloseNotification = @"NSWindowWillCloseNotification";
NSString *const NSApplicationDidFinishLaunchingNotification = @"NSApplicationDidFinishLaunchingNotification";
NSString *const NSCalibratedRGBColorSpace = @"NSCalibratedRGBColorSpace";
NSString *const NSPasteboardTypeString = @"public.utf8-plain-text";
NSString *const NSPasteboardTypeURL = @"public.url";
NSString *const NSPasteboardURLReadingFileURLsOnlyKey = @"NSPasteboardURLReadingFileURLsOnlyKey";
NSString *const NSTextInputContextKeyboardSelectionDidChangeNotification = @"NSTextInputContextKeyboardSelectionDidChangeNotification";
NSString *const NSApplicationDidBecomeActiveNotification = @"NSApplicationDidBecomeActiveNotification";
NSString *const NSApplicationDidResignActiveNotification = @"NSApplicationDidResignActiveNotification";
NSString *const NSApplicationWillTerminateNotification = @"NSApplicationWillTerminateNotification";
NSString *const NSWindowDidBecomeKeyNotification = @"NSWindowDidBecomeKeyNotification";
NSString *const NSWindowDidChangeBackingPropertiesNotification = @"NSWindowDidChangeBackingPropertiesNotification";
NSString *const NSWindowDidChangeScreenNotification = @"NSWindowDidChangeScreenNotification";
NSString *const NSWindowDidChangeScreenProfileNotification = @"NSWindowDidChangeScreenProfileNotification";
NSString *const NSWindowDidDeminiaturizeNotification = @"NSWindowDidDeminiaturizeNotification";
NSString *const NSWindowDidEndLiveResizeNotification = @"NSWindowDidEndLiveResizeNotification";
NSString *const NSWindowDidEnterFullScreenNotification = @"NSWindowDidEnterFullScreenNotification";
NSString *const NSWindowDidExitFullScreenNotification = @"NSWindowDidExitFullScreenNotification";
NSString *const NSWindowDidExposeNotification = @"NSWindowDidExposeNotification";
NSString *const NSWindowDidMiniaturizeNotification = @"NSWindowDidMiniaturizeNotification";
NSString *const NSWindowDidMoveNotification = @"NSWindowDidMoveNotification";
NSString *const NSWindowDidResignKeyNotification = @"NSWindowDidResignKeyNotification";
NSString *const NSWindowDidResizeNotification = @"NSWindowDidResizeNotification";
NSString *const NSWindowWillEnterFullScreenNotification = @"NSWindowWillEnterFullScreenNotification";
NSString *const NSWindowWillExitFullScreenNotification = @"NSWindowWillExitFullScreenNotification";
NSString *const NSWindowWillStartLiveResizeNotification = @"NSWindowWillStartLiveResizeNotification";
NSString *const NSBackingPropertyOldScaleFactorKey = @"NSBackingPropertyOldScaleFactorKey";
NSString *const NSDeviceRGBColorSpace = @"NSDeviceRGBColorSpace";
NSString *const NSFilenamesPboardType = @"NSFilenamesPboardType";
const double NSAppKitVersionNumber = 2685.0;   /* macOS 15-ish: SDL/GLFW only compare against old releases */
static NSMutableArray *g_monitors;   /* local event monitors: @{@"mask", @"block"} */

/* host screen (xef_host_screen_info; 1440x900 when the host has no display), scale factor 1.0 */
static double g_sw = 1440.0, g_sh = 900.0; static int g_smmw = 381, g_smmh = 238;
static void screen_init(void) {
  static BOOL done; if (done) return; done = YES;
  int w = 0, h = 0, mw = 0, mh = 0; xef_host_screen_info(&w, &h, &mw, &mh);
  if (w > 0 && h > 0) { g_sw = w; g_sh = h; g_smmw = mw; g_smmh = mh; }
}
#define SCREEN_W (screen_init(), g_sw)
#define SCREEN_H (screen_init(), g_sh)
#define TITLEBAR 28.0

static NSOpenGLContext *g_current;

/* ---------------------------------------------------------------- responder */
@implementation NSResponder
- (BOOL)acceptsFirstResponder { return NO; }
- (BOOL)becomeFirstResponder { return YES; }
- (BOOL)resignFirstResponder { return YES; }
- (void)keyDown:(id)e {} - (void)keyUp:(id)e {} - (void)flagsChanged:(id)e {}
- (void)mouseDown:(id)e {} - (void)mouseUp:(id)e {} - (void)mouseMoved:(id)e {} - (void)mouseDragged:(id)e {}
- (void)rightMouseDown:(id)e {} - (void)rightMouseUp:(id)e {} - (void)rightMouseDragged:(id)e {}
- (void)otherMouseDown:(id)e {} - (void)otherMouseUp:(id)e {} - (void)otherMouseDragged:(id)e {}
- (void)scrollWheel:(id)e {}
- (void)mouseEntered:(id)e {} - (void)mouseExited:(id)e {} - (void)cursorUpdate:(id)e {}
/* NSTextInputContext without input methods: printable characters go to insertText:replacementRange:, everything else
 * (return, delete, arrows, ...) to doCommandBySelector: like the default key bindings of a text view. */
- (void)interpretKeyEvents:(NSArray *)events {
  for (NSEvent *e in events) {
    NSString *c = [e characters]; unichar ch = [c length] ? [c characterAtIndex:0] : 0;
    if (ch >= 0x20 && ch != 0x7f && !(e->_flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl))) {
      if ([self respondsToSelector:@selector(insertText:replacementRange:)])
        [(id)self insertText:c replacementRange:NSMakeRange(NSNotFound, 0)];
      continue; }
    SEL cmd = NULL;
    switch (e->_keyCode) {
    case 36: case 76: cmd = @selector(insertNewline:); break; case 48: cmd = @selector(insertTab:); break;
    case 51: cmd = @selector(deleteBackward:); break; case 117: cmd = @selector(deleteForward:); break;
    case 53: cmd = @selector(cancelOperation:); break;
    case 123: cmd = @selector(moveLeft:); break; case 124: cmd = @selector(moveRight:); break;
    case 125: cmd = @selector(moveDown:); break; case 126: cmd = @selector(moveUp:); break;
    case 115: cmd = @selector(moveToBeginningOfLine:); break; case 119: cmd = @selector(moveToEndOfLine:); break;
    case 116: cmd = @selector(pageUp:); break; case 121: cmd = @selector(pageDown:); break; }
    if (cmd && [self respondsToSelector:@selector(doCommandBySelector:)]) [(id)self doCommandBySelector:cmd]; } }
@end

/* -------------------------------------------------------------------- event */
@implementation NSEvent
- (NSEventType)type { return _type; }
- (unsigned short)keyCode { return _keyCode; }
- (NSPoint)locationInWindow { return _loc; }
- (NSEventModifierFlags)modifierFlags { return _flags; }
- (NSString *)characters { return _chars ? _chars : @""; }
- (NSString *)charactersIgnoringModifiers { return [self characters]; }
- (id)window { return _window; }
- (NSTimeInterval)timestamp { return _ts; }
- (NSInteger)buttonNumber { return _button; }
- (CGFloat)deltaX { return _dx; } - (CGFloat)deltaY { return _dy; }
- (CGFloat)scrollingDeltaX { return _dx; } - (CGFloat)scrollingDeltaY { return _dy; }
- (BOOL)hasPreciseScrollingDeltas { return NO; } - (BOOL)isARepeat { return NO; } - (NSInteger)clickCount { return 1; }
+ (NSEvent *)otherEventWithType:(NSEventType)t location:(NSPoint)p modifierFlags:(NSUInteger)f timestamp:(NSTimeInterval)ts
    windowNumber:(NSInteger)w context:(id)c subtype:(short)s data1:(NSInteger)d1 data2:(NSInteger)d2 {
  NSEvent *e = [[[NSEvent alloc] init] autorelease]; e->_type = t; e->_loc = p; e->_flags = f; e->_ts = ts; return e;
}
+ (NSEventModifierFlags)modifierFlags { return 0; }
+ (NSUInteger)pressedMouseButtons { return 0; }
+ (NSPoint)mouseLocation {
  int sx = 0, sy = 0; if (!xef_host_pointer(0, &sx, &sy, NULL, NULL)) return NSMakePoint(0, 0);
  return NSMakePoint(sx, SCREEN_H - sy); }
+ (id)addLocalMonitorForEventsMatchingMask:(unsigned long long)mask handler:(NSEvent *(^)(NSEvent *))block {
  if (!g_monitors) g_monitors = [[NSMutableArray alloc] init];
  id blk = (id)Block_copy(block);   /* manual retain, released in removeMonitor: */
  NSDictionary *m = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedLongLong:mask], @"mask", blk, @"block", nil];
  [g_monitors addObject:m]; return m; }
+ (void)removeMonitor:(id)monitor {
  if (!monitor || ![g_monitors containsObject:monitor]) return;
  id blk = [monitor objectForKey:@"block"]; [g_monitors removeObject:monitor]; Block_release(blk); }
- (void)dealloc { [_chars release]; [super dealloc]; }
@end


/* ----------------------------------------------------------- tracking area */
@implementation NSTrackingArea
- (id)initWithRect:(NSRect)r options:(NSTrackingAreaOptions)o owner:(id)owner userInfo:(NSDictionary *)u {
  if ((self = [super init])) { _rect = r; _options = o; _owner = owner; _userInfo = [u retain]; } return self; }
- (NSRect)rect { return _rect; } - (NSTrackingAreaOptions)options { return _options; }
- (id)owner { return _owner; } - (NSDictionary *)userInfo { return _userInfo; }
- (void)dealloc { [_userInfo release]; [super dealloc]; }
@end

/* ------------------------------------------------------------- image / rep */
@implementation NSBitmapImageRep
- (id)initWithBitmapDataPlanes:(unsigned char **)planes pixelsWide:(NSInteger)w pixelsHigh:(NSInteger)h bitsPerSample:(NSInteger)bps
    samplesPerPixel:(NSInteger)spp hasAlpha:(BOOL)a isPlanar:(BOOL)p colorSpaceName:(NSString *)cs bitmapFormat:(NSBitmapFormat)f
    bytesPerRow:(NSInteger)bpr bitsPerPixel:(NSInteger)bpp {
  if (!(self = [super init])) return nil;
  if (w <= 0 || h <= 0 || bps <= 0 || spp <= 0 || p) { [self release]; return nil; }   /* planar reps are not supported */
  _w = w; _h = h; _bps = bps; _spp = spp; _alpha = a; _fmt = f; _cs = [cs retain];
  _bpp = bpp ? bpp : bps * spp; _bpr = bpr ? bpr : (w * _bpp + 7) / 8;
  _data = calloc(1, (size_t)_bpr * h);
  if (planes && planes[0]) memcpy(_data, planes[0], (size_t)_bpr * h);
  if (!_data) { [self release]; return nil; }
  return self; }
- (unsigned char *)bitmapData { return _data; } - (NSInteger)pixelsWide { return _w; } - (NSInteger)pixelsHigh { return _h; }
- (NSInteger)bytesPerRow { return _bpr; } - (NSInteger)bitsPerPixel { return _bpp; }
- (void)dealloc { free(_data); [_cs release]; [super dealloc]; }
@end

@implementation NSImage
- (id)initWithSize:(NSSize)s { if ((self = [super init])) { _size = s; _reps = [[NSMutableArray alloc] init]; } return self; }
- (NSSize)size { return _size; } - (void)addRepresentation:(id)rep { [_reps addObject:rep]; } - (NSArray *)representations { return _reps; }
- (void)dealloc { [_reps release]; [super dealloc]; }
@end

/* -------------------------------------------------------------- pasteboard */
/* process-local clipboard (no X selection integration): reads back what this process wrote */
@implementation NSPasteboard
+ (NSPasteboard *)generalPasteboard { static NSPasteboard *g; if (!g) { g = [[NSPasteboard alloc] init]; g->_types = [[NSMutableArray alloc] init]; g->_data = [[NSMutableDictionary alloc] init]; } return g; }
- (NSInteger)declareTypes:(NSArray *)types owner:(id)owner { [_types setArray:types]; [_data removeAllObjects]; return ++_change; }
- (BOOL)setString:(NSString *)s forType:(NSString *)t {
  if (!s || !t) return NO; if (![_types containsObject:t]) [_types addObject:t]; [_data setObject:[[s copy] autorelease] forKey:t]; _change++; return YES; }
- (NSString *)stringForType:(NSString *)t { id o = [_data objectForKey:t]; return [o isKindOfClass:[NSString class]] ? o : nil; }
- (NSArray *)types { return _types; }
- (NSArray *)readObjectsForClasses:(NSArray *)classes options:(NSDictionary *)o { return nil; }
@end

@implementation NSRunningApplication
+ (NSRunningApplication *)currentApplication { static NSRunningApplication *g; if (!g) g = [[NSRunningApplication alloc] init]; return g; }
- (BOOL)isFinishedLaunching { return NSApp ? ((NSApplication *)NSApp)->_launched : NO; }
- (BOOL)isActive { return NSApp ? [NSApp isActive] : NO; }
- (NSString *)localizedName { return [[NSProcessInfo processInfo] processName]; }
@end

/* macOS virtual keycode -> unshifted ASCII character (ANSI layout) */
static unichar key_char(int kc, int shift) {
  static const char ansi[128] = {
    [0]='a',[11]='b',[8]='c',[2]='d',[14]='e',[3]='f',[5]='g',[4]='h',[34]='i',[38]='j',[40]='k',[37]='l',[46]='m',
    [45]='n',[31]='o',[35]='p',[12]='q',[15]='r',[1]='s',[17]='t',[32]='u',[9]='v',[13]='w',[7]='x',[16]='y',[6]='z',
    [18]='1',[19]='2',[20]='3',[21]='4',[23]='5',[22]='6',[26]='7',[28]='8',[25]='9',[29]='0',
    [49]=' ',[36]='\r',[48]='\t',[53]=27,[51]=127,[27]='-',[24]='=',[33]='[',[30]=']',[42]='\\',[41]=';',[39]='\'',[43]=',',[47]='.',[44]='/',[50]='`'};
  if (kc < 0 || kc > 127 || !ansi[kc]) return 0;
  char c = ansi[kc]; if (shift && c >= 'a' && c <= 'z') c -= 32; return (unichar)c;
}

/* ------------------------------------------------------------------- screen */
@implementation NSScreen
+ (NSScreen *)mainScreen { static NSScreen *s; if (!s) s = [[NSScreen alloc] init]; return s; }
+ (NSArray *)screens { return [NSArray arrayWithObject:[self mainScreen]]; }
- (NSRect)frame { return NSMakeRect(0, 0, SCREEN_W, SCREEN_H); }
- (NSRect)visibleFrame { return NSMakeRect(0, 0, SCREEN_W, SCREEN_H - 25); }
- (CGFloat)backingScaleFactor { return 1.0; }
- (NSDictionary *)deviceDescription {   /* NSScreenNumber = the CGDirectDisplayID of CoreGraphics-lite (1) */
  return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInt:1], @"NSScreenNumber",
          [NSValue valueWithSize:NSMakeSize(SCREEN_W, SCREEN_H)], @"NSDeviceSize", nil]; }
- (NSRect)convertRectToBacking:(NSRect)r { return r; }
- (NSString *)localizedName { return @"XEF Display"; }
@end

/* ------------------------------------------------------------ color / cursor */
@implementation NSColor
+ (NSColor *)colorWithCalibratedRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
  NSColor *c = [[[NSColor alloc] init] autorelease]; c->r = r; c->g = g; c->b = b; c->a = a; return c; }
+ (NSColor *)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a { return [self colorWithCalibratedRed:r green:g blue:b alpha:a]; }
+ (NSColor *)blackColor { return [self colorWithRed:0 green:0 blue:0 alpha:1]; }
+ (NSColor *)whiteColor { return [self colorWithRed:1 green:1 blue:1 alpha:1]; }
+ (NSColor *)clearColor { return [self colorWithRed:0 green:0 blue:0 alpha:0]; }
- (CGFloat)redComponent { return r; } - (CGFloat)greenComponent { return g; } - (CGFloat)blueComponent { return b; } - (CGFloat)alphaComponent { return a; }
- (void)set {}
@end

@implementation NSCursor
+ (NSCursor *)arrowCursor { static NSCursor *c; if (!c) c = [[NSCursor alloc] init]; return c; }
+ (NSCursor *)IBeamCursor { return [self arrowCursor]; } + (NSCursor *)crosshairCursor { return [self arrowCursor]; }
+ (NSCursor *)pointingHandCursor { return [self arrowCursor]; }
+ (NSCursor *)resizeLeftRightCursor { return [self arrowCursor]; } + (NSCursor *)resizeUpDownCursor { return [self arrowCursor]; }
+ (NSCursor *)closedHandCursor { return [self arrowCursor]; } + (NSCursor *)operationNotAllowedCursor { return [self arrowCursor]; }
/* HLE: cursor shapes/images are not forwarded to X11 (the pointer keeps the server default) */
+ (void)hide {} + (void)unhide {} - (void)set {} - (void)push {} - (void)pop {}
- (id)initWithImage:(NSImage *)i hotSpot:(NSPoint)p { if ((self = [super init])) { _image = [i retain]; _hot = p; } return self; }
- (void)dealloc { [_image release]; [super dealloc]; }
@end

/* --------------------------------------------------------------------- menu */
@implementation NSMenuItem
- (id)initWithTitle:(NSString *)t action:(SEL)a keyEquivalent:(NSString *)k {
  if ((self = [super init])) { _title = [t copy]; _action = a; _key = [k copy]; } return self; }
+ (NSMenuItem *)separatorItem { return [[[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""] autorelease]; }
- (void)setSubmenu:(id)m { [m retain]; [_sub release]; _sub = m; } - (id)submenu { return _sub; }
- (NSString *)title { return _title; } - (void)setTitle:(NSString *)t { [t retain]; [_title release]; _title = t; }
- (void)setTarget:(id)t { _target = t; } - (id)target { return _target; } - (SEL)action { return _action; }
- (void)setKeyEquivalentModifierMask:(NSUInteger)m {}
- (void)dealloc { [_title release]; [_sub release]; [_key release]; [super dealloc]; }
@end

@implementation NSMenu
- (id)initWithTitle:(NSString *)t { if ((self = [super init])) { _title = [t copy]; _items = [[NSMutableArray alloc] init]; } return self; }
- (id)init { return [self initWithTitle:@""]; }
- (void)addItem:(NSMenuItem *)i { [_items addObject:i]; }
- (NSMenuItem *)addItemWithTitle:(NSString *)t action:(SEL)a keyEquivalent:(NSString *)k {
  NSMenuItem *i = [[[NSMenuItem alloc] initWithTitle:t action:a keyEquivalent:k] autorelease]; [_items addObject:i]; return i; }
- (NSArray *)itemArray { return _items; } - (NSString *)title { return _title; }
- (void)dealloc { [_title release]; [_items release]; [super dealloc]; }
@end

/* --------------------------------------------------------------------- view */
@implementation NSView
- (id)initWithFrame:(NSRect)f {
  if ((self = [super init])) { _frame = f; _bounds = NSMakeRect(0, 0, f.size.width, f.size.height); _subviews = [[NSMutableArray alloc] init]; _needsDisplay = YES; }
  return self; }
- (id)init { return [self initWithFrame:NSMakeRect(0, 0, 0, 0)]; }
- (NSRect)frame { return _frame; } - (NSRect)bounds { return _bounds; }
- (void)setFrame:(NSRect)f { _frame = f; _bounds.size = f.size; _needsDisplay = YES; }
- (void)setFrameSize:(NSSize)s { NSRect f = _frame; f.size = s; [self setFrame:f]; }
- (void)setBounds:(NSRect)b { _bounds = b; }
- (NSWindow *)window { return _window; } - (NSView *)superview { return _superview; } - (NSArray *)subviews { return _subviews; }
/* a view leaving its window stops being the window's first responder (the window does not retain it: SDL2 removes and
 * releases its text-input view while it is first responder, and the next keyDown: went to freed memory) */
- (void)_setWindow:(NSWindow *)w {
  if (_window && _window != w && _window->_first == (NSResponder *)self) _window->_first = nil;
  _window = w; for (NSView *s in _subviews) [s _setWindow:w]; [self viewDidMoveToWindow]; }
- (void)addSubview:(NSView *)v { [_subviews addObject:v]; v->_superview = self; [v _setWindow:_window]; }
- (void)removeFromSuperview { NSView *s = _superview; if (!s) return; _superview = nil; [self _setWindow:nil]; [s->_subviews removeObject:self]; }
- (void)setNeedsDisplay:(BOOL)f { _needsDisplay = f; }
- (BOOL)needsDisplay { return _needsDisplay; }
- (void)display { _needsDisplay = NO; [self drawRect:_bounds]; for (NSView *s in _subviews) [s display]; }
- (void)displayIfNeeded { if (_needsDisplay) [self display]; else for (NSView *s in _subviews) [s displayIfNeeded]; }
- (void)drawRect:(NSRect)r {}
- (BOOL)isFlipped { return NO; } - (BOOL)isOpaque { return NO; }
- (void)viewDidMoveToWindow {}
- (void)lockFocus {} - (void)unlockFocus {}
- (void)setWantsBestResolutionOpenGLSurface:(BOOL)f { _bestRes = f; }
- (NSRect)convertRectToBacking:(NSRect)r { return r; } - (NSRect)convertRectFromBacking:(NSRect)r { return r; }
- (NSPoint)convertPoint:(NSPoint)p fromView:(NSView *)v { return p; }
- (void)setWantsLayer:(BOOL)f { _wantsLayer = f; } - (BOOL)wantsLayer { return _wantsLayer; }
- (id)layer { return _layer; } - (void)setLayer:(id)l { [l retain]; [_layer release]; _layer = l; }
- (void)updateTrackingAreas {}
- (void)addTrackingArea:(NSTrackingArea *)a { if (!_tracking) _tracking = [[NSMutableArray alloc] init]; [_tracking addObject:a]; }
- (void)removeTrackingArea:(NSTrackingArea *)a { [_tracking removeObject:a]; }
- (NSArray *)trackingAreas { return _tracking ? _tracking : [NSArray array]; }
- (void)registerForDraggedTypes:(NSArray *)t { [t retain]; [_dragTypes release]; _dragTypes = t; }   /* no drag sources on X11-lite */
- (BOOL)mouse:(NSPoint)p inRect:(NSRect)r { return NSPointInRect(p, r); }
- (void)viewDidChangeBackingProperties {}
- (BOOL)acceptsFirstResponder { return YES; }
- (void)dealloc { if (_window && _window->_first == (NSResponder *)self) _window->_first = nil;
  [_subviews release]; [_tracking release]; [_layer release]; [_dragTypes release]; [super dealloc]; }
@end

/* ------------------------------------------------------------------- window */
static NSString *const kWinDidResize = @"NSWindowDidResizeNotification", *const kWinDidMove = @"NSWindowDidMoveNotification",
    *const kWinDidBecomeKey = @"NSWindowDidBecomeKeyNotification", *const kWinDidResignKey = @"NSWindowDidResignKeyNotification",
    *const kWinDidMini = @"NSWindowDidMiniaturizeNotification", *const kWinDidDemini = @"NSWindowDidDeminiaturizeNotification",
    *const kWinDidOcclusion = @"NSWindowDidChangeOcclusionStateNotification";

@implementation NSWindow
- (id)initWithContentRect:(NSRect)r styleMask:(NSWindowStyleMask)s backing:(NSBackingStoreType)b defer:(BOOL)d {
  if ((self = [super init])) {
    _style = s; _released = YES; _title = @""; _opaque = YES; _shadow = YES; _alpha = 1.0; _level = 0;
    _frame = [NSWindow frameRectForContentRect:r styleMask:s];
    NSRect c = r; int hx = (int)c.origin.x, hy = (int)(SCREEN_H - c.origin.y - c.size.height);
    _handle = xef_host_window_create(hx, hy, (int)c.size.width, (int)c.size.height, "");
    [NSApplication sharedApplication];
    [(NSApplication *)NSApp _addWindow:self];
  }
  return self; }
+ (NSRect)frameRectForContentRect:(NSRect)c styleMask:(NSWindowStyleMask)m {
  if (m & NSWindowStyleMaskTitled) c.size.height += TITLEBAR; return c; }
+ (NSRect)contentRectForFrameRect:(NSRect)f styleMask:(NSWindowStyleMask)m {
  if (m & NSWindowStyleMaskTitled) f.size.height -= TITLEBAR; return f; }
- (NSRect)contentRectForFrameRect:(NSRect)f { return [NSWindow contentRectForFrameRect:f styleMask:_style]; }
- (NSRect)frameRectForContentRect:(NSRect)c { return [NSWindow frameRectForContentRect:c styleMask:_style]; }
- (NSRect)frame { return _frame; }
- (void)_notify:(NSString *)name selector:(SEL)sel {
  if (![_delegate respondsToSelector:sel]) return;
  [_delegate performSelector:sel withObject:[NSNotification notificationWithName:name object:self]]; }
/* stores a new frame; sync = push the content rect to the X11 window (false when the change came from the host) */
- (void)_applyFrame:(NSRect)f sync:(BOOL)sync {
  NSRect old = _frame; _frame = f; NSRect c = [self contentRectForFrameRect:f];
  if (_content) [_content setFrame:NSMakeRect(0, 0, c.size.width, c.size.height)];
  if (sync) xef_host_window_set_frame(_handle, (int)c.origin.x, (int)(SCREEN_H - c.origin.y - c.size.height), (int)c.size.width, (int)c.size.height);
  if (old.size.width != f.size.width || old.size.height != f.size.height) [self _notify:kWinDidResize selector:@selector(windowDidResize:)];
  if (old.origin.x != f.origin.x || old.origin.y != f.origin.y) [self _notify:kWinDidMove selector:@selector(windowDidMove:)]; }
- (void)setFrame:(NSRect)f display:(BOOL)d { _zoomed = NO; [self _applyFrame:f sync:YES]; }
- (void)setFrameOrigin:(NSPoint)p { NSRect f = _frame; f.origin = p; [self _applyFrame:f sync:YES]; }
- (void)setContentSize:(NSSize)s { NSRect c = [self contentRectForFrameRect:_frame]; c.origin.y += c.size.height - s.height; c.size = s; [self setFrame:[self frameRectForContentRect:c] display:YES]; }
- (void)center {
  NSRect f = _frame; f.origin = NSMakePoint((SCREEN_W - f.size.width) / 2, (SCREEN_H - f.size.height) / 2); _moved = YES; [self _applyFrame:f sync:YES]; }
- (NSPoint)cascadeTopLeftFromPoint:(NSPoint)p {
  /* NSZeroPoint: leave the window where it is; the returned point is where the next cascaded window goes */
  if (p.x != 0 || p.y != 0) { NSRect f = _frame; f.origin = NSMakePoint(p.x, p.y - f.size.height); [self _applyFrame:f sync:YES]; }
  return NSMakePoint(_frame.origin.x + 22, _frame.origin.y + _frame.size.height - 22); }
- (void)setTitle:(NSString *)t { [t retain]; [_title release]; _title = t; xef_host_window_set_title(_handle, [t UTF8String]); }
- (NSString *)title { return _title; }
- (void)setContentView:(NSView *)v {
  if (_content == v) return;
  [v retain]; [_content _setWindow:nil]; [_content release]; _content = v;
  NSRect c = [self contentRectForFrameRect:_frame]; [v setFrame:NSMakeRect(0, 0, c.size.width, c.size.height)];
  [v _setWindow:self]; }
- (NSView *)contentView { return _content; }
- (BOOL)isVisible { return _visible && !_mini; }
- (void)orderFront:(id)s {
  if (_visible) return;
  _visible = YES; xef_host_window_show(_handle);
  [self _notify:kWinDidOcclusion selector:@selector(windowDidChangeOcclusionState:)]; }
- (void)makeKeyAndOrderFront:(id)s { [self orderFront:s]; [self makeKeyWindow]; }
- (void)orderOut:(id)s {
  if (!_visible) return;
  _visible = NO; xef_host_window_hide(_handle);
  [self _notify:kWinDidOcclusion selector:@selector(windowDidChangeOcclusionState:)]; }
- (BOOL)canBecomeKeyWindow { return (_style & NSWindowStyleMaskTitled) != 0; }
- (BOOL)canBecomeMainWindow { return [self canBecomeKeyWindow]; }
- (void)makeKeyWindow {
  if (_closed || _key || ![self canBecomeKeyWindow]) return;
  for (NSWindow *o in [[[(NSApplication *)NSApp windows] copy] autorelease]) if (o != self && o->_key) [o resignKeyWindow];
  _key = YES; if (!_first && _content) [self makeFirstResponder:_content];
  [self _notify:kWinDidBecomeKey selector:@selector(windowDidBecomeKey:)]; }
- (void)resignKeyWindow {
  if (!_key) return;
  _key = NO; [self _notify:kWinDidResignKey selector:@selector(windowDidResignKey:)]; }
- (BOOL)isKeyWindow { return _key; }
- (void)setReleasedWhenClosed:(BOOL)f { _released = f; }
- (void)setAcceptsMouseMovedEvents:(BOOL)f {}
- (BOOL)makeFirstResponder:(NSResponder *)r {
  if (_first && ![_first resignFirstResponder]) return NO;
  if (r && ![r becomeFirstResponder]) return NO;
  _first = r; return YES; }
- (NSResponder *)firstResponder { return _first ? _first : (NSResponder *)self; }
- (void)setDelegate:(id)d { _delegate = d; } - (id)delegate { return _delegate; }
- (CGFloat)backingScaleFactor { return 1.0; }
- (void)setOpaque:(BOOL)f { _opaque = f; } - (BOOL)isOpaque { return _opaque; }
- (void)setBackgroundColor:(NSColor *)c {}
- (void)display { [_content display]; }
- (NSInteger)windowNumber { return _handle; } - (int)xefHandle { return _handle; }
- (void)setLevel:(NSInteger)l { _level = l; } - (NSInteger)level { return _level; }
- (void)setCollectionBehavior:(NSUInteger)b { _collection = b; } - (NSUInteger)collectionBehavior { return _collection; }
- (void)setFrameAutosaveName:(NSString *)n {} - (void)setHasShadow:(BOOL)f { _shadow = f; } - (void)setRestorable:(BOOL)f {}
- (void)setTabbingMode:(NSInteger)m {} - (void)setIgnoresMouseEvents:(BOOL)f { _ignoresMouse = f; }
- (void)setContentMinSize:(NSSize)s { _minSize = s; } - (void)setContentMaxSize:(NSSize)s { _maxSize = s; }
- (void)setContentAspectRatio:(NSSize)s { _aspect = s; } - (void)setResizeIncrements:(NSSize)s {}
- (void)setMiniwindowTitle:(NSString *)t { [t retain]; [_miniTitle release]; _miniTitle = t; }
- (NSString *)miniwindowTitle { return _miniTitle ? _miniTitle : _title; }
- (CGFloat)alphaValue { return _alpha; } - (void)setAlphaValue:(CGFloat)a { _alpha = a; }
- (NSWindowOcclusionState)occlusionState { return [self isVisible] ? NSWindowOcclusionStateVisible : 0; }
- (NSWindowStyleMask)styleMask { return _style; }
- (void)setStyleMask:(NSWindowStyleMask)m {
  if (m == _style) return;
  NSRect c = [self contentRectForFrameRect:_frame]; _style = m; _frame = [self frameRectForContentRect:c]; }
- (NSRect)convertRectToScreen:(NSRect)r { r.origin.x += _frame.origin.x; r.origin.y += _frame.origin.y; return r; }
- (NSPoint)mouseLocationOutsideOfEventStream {
  int wx = 0, wy = 0; if (!xef_host_pointer(_handle, NULL, NULL, &wx, &wy)) return NSMakePoint(0, 0);
  CGFloat ch = _content ? _content->_bounds.size.height : 0; return NSMakePoint(wx, ch - wy); }
+ (NSInteger)windowNumberAtPoint:(NSPoint)p belowWindowWithWindowNumber:(NSInteger)n {
  NSArray *ws = [(NSApplication *)NSApp windows];
  for (NSInteger i = (NSInteger)[ws count] - 1; i >= 0; i--) {   /* later windows are in front */
    NSWindow *w = [ws objectAtIndex:i]; if ([w isVisible] && NSPointInRect(p, w->_frame)) return w->_handle; }
  return 0; }
- (void)zoom:(id)s {
  if (_zoomed) { _zoomed = NO; [self _applyFrame:_unzoomed sync:YES]; return; }
  _unzoomed = _frame; NSRect v = [[NSScreen mainScreen] visibleFrame];
  [self _applyFrame:v sync:YES]; _zoomed = YES; }
- (BOOL)isZoomed { return _zoomed; } - (void)performZoom:(id)s { [self zoom:s]; }
- (void)toggleFullScreen:(id)s { [self zoom:s]; }   /* HLE: full screen == zoomed window on X11 without a window manager */
- (void)miniaturize:(id)s { if (_mini) return; _mini = YES; xef_host_window_hide(_handle); [self _notify:kWinDidMini selector:@selector(windowDidMiniaturize:)]; }
- (void)deminiaturize:(id)s { if (!_mini) return; _mini = NO; if (_visible) xef_host_window_show(_handle); [self _notify:kWinDidDemini selector:@selector(windowDidDeminiaturize:)]; }
- (BOOL)isMiniaturized { return _mini; } - (void)performMiniaturize:(id)s { [self miniaturize:s]; }
- (void)close {
  if (_closed) return;
  if ([_delegate respondsToSelector:@selector(windowShouldClose:)] && ![_delegate windowShouldClose:self]) return;
  _closed = YES; _visible = NO; _key = NO;
  [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowWillCloseNotification object:self];
  if ([_delegate respondsToSelector:@selector(windowWillClose:)]) [_delegate windowWillClose:[NSNotification notificationWithName:NSWindowWillCloseNotification object:self]];
  xef_host_window_close(_handle);
  [(NSApplication *)NSApp _removeWindow:self];
  if (_released) [self autorelease]; }
- (void)_hostEnterExit:(NSEvent *)e {
  /* tracking areas: mouse entered/exited (+ cursor update on enter) go to the area's owner */
  for (NSView *v = _content; v; v = nil)
    for (NSTrackingArea *a in [[[v trackingAreas] copy] autorelease]) {
      if (!(a->_options & NSTrackingMouseEnteredAndExited)) continue;
      if (e->_type == NSEventTypeMouseEntered) { if (a->_options & NSTrackingCursorUpdate) [a->_owner cursorUpdate:e]; [a->_owner mouseEntered:e]; }
      else [a->_owner mouseExited:e]; } }
- (void)sendEvent:(NSEvent *)e {
  NSResponder *t = _first ? _first : (NSResponder *)_content;
  switch (e->_type) {
  case NSEventTypeKeyDown: [t keyDown:e]; break; case NSEventTypeKeyUp: [t keyUp:e]; break;
  case NSEventTypeFlagsChanged: [t flagsChanged:e]; break;
  case NSEventTypeLeftMouseDown: [self makeKeyWindow]; [_content mouseDown:e]; break; case NSEventTypeLeftMouseUp: [_content mouseUp:e]; break;
  case NSEventTypeRightMouseDown: [_content rightMouseDown:e]; break; case NSEventTypeRightMouseUp: [_content rightMouseUp:e]; break;
  case NSEventTypeOtherMouseDown: [_content otherMouseDown:e]; break; case NSEventTypeOtherMouseUp: [_content otherMouseUp:e]; break;
  case NSEventTypeMouseMoved: [_content mouseMoved:e]; break; case NSEventTypeLeftMouseDragged: [_content mouseDragged:e]; break;
  case NSEventTypeRightMouseDragged: [_content rightMouseDragged:e]; break; case NSEventTypeOtherMouseDragged: [_content otherMouseDragged:e]; break;
  case NSEventTypeScrollWheel: [_content scrollWheel:e]; break;
  case NSEventTypeMouseEntered: case NSEventTypeMouseExited: [self _hostEnterExit:e]; break;
  default: break; } }
- (void)dealloc { if (!_closed) xef_host_window_close(_handle); [_content release]; [_title release]; [_miniTitle release]; [super dealloc]; }
@end

/* -------------------------------------------------------------- application */
@implementation NSApplication
+ (NSApplication *)sharedApplication {
  if (!NSApp) { NSApp = [[self alloc] init]; } return NSApp; }
- (id)init {
  if ((self = [super init])) { _queue = [[NSMutableArray alloc] init]; _windows = [[NSMutableArray alloc] init]; if (!NSApp) NSApp = self; }
  return self; }
- (BOOL)setActivationPolicy:(NSApplicationActivationPolicy)p { _policy = p; return YES; }
- (void)activateIgnoringOtherApps:(BOOL)f { _active = YES; } - (BOOL)isActive { return _active; }
- (void)setDelegate:(id)d { _delegate = d; } - (id)delegate { return _delegate; }
- (void)setMainMenu:(NSMenu *)m { [m retain]; [_menu release]; _menu = m; } - (NSMenu *)mainMenu { return _menu; }
- (void)setServicesMenu:(NSMenu *)m { [m retain]; [_services release]; _services = m; }
- (void)setWindowsMenu:(NSMenu *)m { [m retain]; [_windowsMenu release]; _windowsMenu = m; }
- (void)setAppleMenu:(NSMenu *)m {}   /* obsolete (a no-op on current AppKit as well) */
/* No menu bar / dock / other applications on the X11 host: these menu actions have nothing to act on. */
- (NSInteger)requestUserAttention:(NSRequestUserAttentionType)t { return 0; }
- (void)hide:(id)s {} - (void)hideOtherApplications:(id)s {} - (void)unhideAllApplications:(id)s {}
- (void)orderFrontStandardAboutPanel:(id)s {}
- (void)arrangeInFront:(id)s { for (NSWindow *w in [[_windows copy] autorelease]) if (w->_visible) [w orderFront:s]; }
- (NSEvent *)currentEvent { return _current; }
- (NSArray *)windows { return _windows; }
- (NSWindow *)keyWindow { for (NSWindow *w in _windows) if (w->_key) return w; return nil; }
- (NSWindow *)mainWindow { return [self keyWindow]; }
- (void)_addWindow:(NSWindow *)w { [_windows addObject:w]; }
- (void)_removeWindow:(NSWindow *)w { [_windows removeObject:w]; }
- (void)finishLaunching {
  if (_launched) return; _launched = YES;
  NSNotification *n = [NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:self];
  if ([_delegate respondsToSelector:@selector(applicationWillFinishLaunching:)]) [_delegate applicationWillFinishLaunching:n];
  [[NSNotificationCenter defaultCenter] postNotification:n];
  if ([_delegate respondsToSelector:@selector(applicationDidFinishLaunching:)]) [_delegate applicationDidFinishLaunching:n]; }
- (BOOL)isRunning { return _running; }
- (void)postEvent:(NSEvent *)e atStart:(BOOL)s { if (s) [_queue insertObject:e atIndex:0]; else [_queue addObject:e]; }

- (NSWindow *)_eventWindow { NSWindow *w = [self keyWindow]; if (w) return w; for (NSWindow *x in _windows) if (x->_visible) return x; return [_windows firstObject]; }

/* translate a host event into an NSEvent; non-input host events are handled here and return nil */
- (NSEvent *)_convert:(xef_host_event_t *)h {
  NSWindow *w = [self _eventWindow];
  if (h->type == XEF_EV_CLOSE) { [w close]; return nil; }
  if (h->type == XEF_EV_FOCUS_IN) { _active = YES; [w makeKeyWindow]; return nil; }
  if (h->type == XEF_EV_FOCUS_OUT) { _active = NO; [w resignKeyWindow]; return nil; }
  if (h->type == XEF_EV_RESIZE) {
    if (w) { NSRect f = w->_frame; NSRect c = [w contentRectForFrameRect:f]; c.size = NSMakeSize(h->x, h->y);
      f.size = [w frameRectForContentRect:c].size; [w _applyFrame:f sync:NO]; }
    return nil; }
  NSEvent *e = [[[NSEvent alloc] init] autorelease];
  e->_type = (NSEventType)h->type; e->_keyCode = (unsigned short)h->keycode; e->_flags = (NSEventModifierFlags)h->flags; e->_window = w;
  CGFloat ch = w && w->_content ? w->_content->_bounds.size.height : 0;
  e->_loc = NSMakePoint(h->x, ch - h->y);
  e->_ts = [NSDate timeIntervalSinceReferenceDate];
  if (h->type == NSEventTypeScrollWheel) e->_dy = h->keycode;
  if (h->type == NSEventTypeKeyDown || h->type == NSEventTypeKeyUp) {
    unichar c = key_char(h->keycode, (h->flags & NSEventModifierFlagShift) != 0);
    if (c) e->_chars = [[NSString alloc] initWithCharacters:&c length:1]; }
  if (h->type == NSEventTypeRightMouseDown || h->type == NSEventTypeRightMouseUp || h->type == NSEventTypeRightMouseDragged) e->_button = 1;
  if (h->type >= NSEventTypeOtherMouseDown && h->type <= NSEventTypeOtherMouseDragged) e->_button = 2;
  return e; }

- (NSEvent *)_take:(NSUInteger)mask {
  for (;;) {
    NSEvent *e = nil;
    if ([_queue count]) { e = [[[_queue objectAtIndex:0] retain] autorelease]; [_queue removeObjectAtIndex:0]; }
    else { xef_host_event_t h; memset(&h, 0, sizeof h); if (!xef_host_pump(&h)) return nil; e = [self _convert:&h]; if (!e) continue; }
    if (mask == (NSUInteger)NSEventMaskAny || ((1ULL << e->_type) & mask)) return e; } }

- (NSEvent *)nextEventMatchingMask:(NSUInteger)m untilDate:(NSDate *)d inMode:(NSString *)mode dequeue:(BOOL)dq {
  for (;;) {
    NSEvent *e = [self _take:m];
    if (e) { if (!dq) [_queue insertObject:e atIndex:0]; return e; }
    if (!d || [d timeIntervalSinceNow] <= 0) return nil;
    usleep(1000); } }

- (void)sendEvent:(NSEvent *)e {
  NSEvent *prev = _current; _current = e; NSEvent *ev = e;
  for (NSDictionary *m in [[g_monitors copy] autorelease]) {   /* local monitors see the event first and may replace/swallow it */
    if (!((1ULL << ev->_type) & [[m objectForKey:@"mask"] unsignedLongLongValue])) continue;
    NSEvent *(^blk)(NSEvent *) = (NSEvent *(^)(NSEvent *))[m objectForKey:@"block"];
    ev = blk(ev); if (!ev) break; }
  if (ev) { NSWindow *w = ev->_window ? ev->_window : [self _eventWindow]; [w sendEvent:ev]; }
  _current = prev; }
- (void)updateWindows { for (NSWindow *w in [[_windows copy] autorelease]) if (w->_visible) [w->_content displayIfNeeded]; }

/* stop: ends the loop after the current event (also when called from applicationDidFinishLaunching:) */
- (void)run {
  _running = YES; _stop = NO; [self finishLaunching];
  do {
    NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init];
    NSEvent *e = [self nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate dateWithTimeIntervalSinceNow:0.016] inMode:nil dequeue:YES];
    if (e) [self sendEvent:e];
    [self updateWindows];
    if (![_windows count] && [_delegate respondsToSelector:@selector(applicationShouldTerminateAfterLastWindowClosed:)] &&
        [_delegate applicationShouldTerminateAfterLastWindowClosed:self]) { [p drain]; [self terminate:self]; }
    [p drain]; } while (!_stop);
  _running = NO; _stop = NO; }
- (void)stop:(id)s { _stop = YES; }
- (void)terminate:(id)s {
  if ([_delegate respondsToSelector:@selector(applicationShouldTerminate:)] && [_delegate applicationShouldTerminate:self] == NSTerminateCancel) return;
  if ([_delegate respondsToSelector:@selector(applicationWillTerminate:)]) [_delegate applicationWillTerminate:[NSNotification notificationWithName:@"NSApplicationWillTerminateNotification" object:self]];
  for (NSWindow *w in [[_windows copy] autorelease]) xef_host_window_close(w->_handle);
  exit(0); }
@end

/* ----------------------------------------------------------- NSOpenGL* ---- */
@implementation NSOpenGLPixelFormat
- (id)initWithAttributes:(const NSOpenGLPixelFormatAttribute *)a {
  if (!(self = [super init])) return nil;
  profile = NSOpenGLProfileVersionLegacy;
  for (; a && *a && _n < 62; a++) {
    NSOpenGLPixelFormatAttribute k = *a; _attrs[_n++] = k;
    switch (k) {
    case NSOpenGLPFADoubleBuffer: dbl = YES; break;
    case NSOpenGLPFAAuxBuffers: case NSOpenGLPFAAccumSize: case NSOpenGLPFARendererID: case NSOpenGLPFAScreenMask:
      a++; _attrs[_n++] = *a; break;
    case NSOpenGLPFAColorSize: color = *++a; _attrs[_n++] = color; break;
    case NSOpenGLPFAAlphaSize: alpha = *++a; _attrs[_n++] = alpha; break;
    case NSOpenGLPFADepthSize: depth = *++a; _attrs[_n++] = depth; break;
    case NSOpenGLPFAStencilSize: stencil = *++a; _attrs[_n++] = stencil; break;
    case NSOpenGLPFASamples: samples = *++a; _attrs[_n++] = samples; break;
    case NSOpenGLPFASampleBuffers: sampleBuffers = *++a; _attrs[_n++] = sampleBuffers; break;
    case NSOpenGLPFAOpenGLProfile: profile = *++a; _attrs[_n++] = profile; break;
    default: break; } }
  _attrs[_n] = 0; return self; }
- (id)initWithData:(NSData *)d { return nil; }
- (NSInteger)numberOfVirtualScreens { return 1; }
- (void)getValues:(int *)v forAttribute:(NSOpenGLPixelFormatAttribute)a forVirtualScreen:(int)s {
  switch (a) { case NSOpenGLPFAColorSize: *v = color ? color : 24; break; case NSOpenGLPFAAlphaSize: *v = alpha; break;
  case NSOpenGLPFADepthSize: *v = depth; break; case NSOpenGLPFAStencilSize: *v = stencil; break;
  case NSOpenGLPFADoubleBuffer: *v = dbl; break; case NSOpenGLPFASamples: *v = samples; break;
  case NSOpenGLPFASampleBuffers: *v = sampleBuffers; break; case NSOpenGLPFAOpenGLProfile: *v = profile; break; default: *v = 0; } }
@end

@implementation NSOpenGLContext
- (id)initWithFormat:(NSOpenGLPixelFormat *)f shareContext:(NSOpenGLContext *)s {
  if (!f) return nil;
  if ((self = [super init])) { _pf = [f retain]; _share = [s retain]; _swap = 1; _opaque = YES; } return self; }
- (void)setView:(NSView *)v { _view = v; if (g_current == self) [self makeCurrentContext]; }
- (NSView *)view { return _view; }
- (int)_handle { return _view && _view->_window ? _view->_window->_handle : 0; }
- (void)makeCurrentContext {
  g_current = self; int h = [self _handle];
  if (h) xef_host_gl_set_profile(h, _pf ? _pf->profile : NSOpenGLProfileVersionLegacy);   /* core contexts need glXCreateContextAttribsARB */
  xef_host_gl_make_current(h); }
+ (void)clearCurrentContext { g_current = nil; xef_host_gl_make_current(0); }
+ (NSOpenGLContext *)currentContext { return g_current; }
- (void)clearDrawable { _view = nil; if (g_current == self) xef_host_gl_make_current(0); }
- (void)flushBuffer { int h = [self _handle]; if (h) xef_host_swap(h); }
- (void)update {}
- (void)setValues:(const int *)v forParameter:(NSOpenGLContextParameter)p {
  if (p == NSOpenGLCPSwapInterval) _swap = *v; else if (p == NSOpenGLCPSurfaceOpacity) _opaque = *v; }
- (void)getValues:(int *)v forParameter:(NSOpenGLContextParameter)p { *v = (p == NSOpenGLCPSwapInterval) ? _swap : (p == NSOpenGLCPSurfaceOpacity) ? _opaque : 0; }
- (NSOpenGLPixelFormat *)pixelFormat { return _pf; }
- (void *)CGLContextObj { return (void *)self; }
- (void)dealloc { if (g_current == self) g_current = nil; [_pf release]; [_share release]; [super dealloc]; }
@end

@implementation NSOpenGLView
+ (NSOpenGLPixelFormat *)defaultPixelFormat {
  NSOpenGLPixelFormatAttribute a[] = { NSOpenGLPFADoubleBuffer, NSOpenGLPFADepthSize, 24, 0 };
  return [[[NSOpenGLPixelFormat alloc] initWithAttributes:a] autorelease]; }
- (id)initWithFrame:(NSRect)f pixelFormat:(NSOpenGLPixelFormat *)pf {
  if ((self = [super initWithFrame:f])) {
    _pf = [pf retain]; _ctx = [[NSOpenGLContext alloc] initWithFormat:pf shareContext:nil]; [_ctx setView:self];
    if (!_ctx) { [self release]; return nil; } }
  return self; }
- (id)initWithFrame:(NSRect)f { return [self initWithFrame:f pixelFormat:[NSOpenGLView defaultPixelFormat]]; }
- (NSOpenGLContext *)openGLContext { return _ctx; }
- (void)setOpenGLContext:(NSOpenGLContext *)c { [c retain]; [_ctx release]; _ctx = c; [c setView:self]; }
- (NSOpenGLPixelFormat *)pixelFormat { return _pf; }
- (void)setPixelFormat:(NSOpenGLPixelFormat *)p { [p retain]; [_pf release]; _pf = p; }
- (void)prepareOpenGL {} - (void)reshape {} - (void)update { [_ctx update]; }
- (void)clearGLContext { [_ctx clearDrawable]; [_ctx release]; _ctx = nil; _prepared = NO; }
- (void)setFrame:(NSRect)f { [super setFrame:f]; if (_window) { [_ctx makeCurrentContext]; [self reshape]; } }
- (void)viewDidMoveToWindow {
  if (!_window) return;
  [_ctx setView:self]; [_ctx makeCurrentContext];
  if (!_prepared) { _prepared = YES; [self prepareOpenGL]; }
  [self reshape]; }
- (void)lockFocus { [_ctx makeCurrentContext]; }
- (void)drawRect:(NSRect)r { [_ctx makeCurrentContext]; }
- (void)dealloc { [_ctx release]; [_pf release]; [super dealloc]; }
@end

/* ---------------------------------------------------------------- alerts */
/* There is no modal UI: an alert is written to stderr and answered with its first button (NSAlertFirstButtonReturn),
 * which is what the default-button keyboard shortcut would do. Used by SDL_ShowMessageBox for fatal errors. */
@interface NSButton : NSView { @public NSString *_title, *_keyEquivalent; NSInteger _tag; }
@end
@implementation NSButton
- (NSString *)title { return _title; }
- (void)setTitle:(NSString *)t { [t retain]; [_title release]; _title = t; }
- (NSString *)keyEquivalent { return _keyEquivalent; }
- (void)setKeyEquivalent:(NSString *)k { [k retain]; [_keyEquivalent release]; _keyEquivalent = k; }
- (NSInteger)tag { return _tag; }
- (void)setTag:(NSInteger)t { _tag = t; }
- (void)dealloc { [_title release]; [_keyEquivalent release]; [super dealloc]; }
@end

@interface NSAlert : NSObject { NSString *_message, *_info; NSMutableArray *_buttons; NSUInteger _style; }
@end
@implementation NSAlert
- (id)init { if ((self = [super init])) { _buttons = [[NSMutableArray alloc] init]; _message = @""; _info = @""; } return self; }
- (void)setMessageText:(NSString *)s { [s retain]; [_message release]; _message = s ? s : @""; }
- (NSString *)messageText { return _message; }
- (void)setInformativeText:(NSString *)s { [s retain]; [_info release]; _info = s ? s : @""; }
- (NSString *)informativeText { return _info; }
- (void)setAlertStyle:(NSUInteger)s { _style = s; }
- (NSUInteger)alertStyle { return _style; }
- (NSArray *)buttons { return _buttons; }
- (NSButton *)addButtonWithTitle:(NSString *)t {
  NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 24)]; [b setTitle:t]; [b setTag:1000 + [_buttons count]];
  [_buttons addObject:b]; [b release]; return b; }
- (id)window { return nil; }
- (void)layout {}
- (NSInteger)runModal {
  fprintf(stderr, "[AppKit-lite NSAlert] %s%s%s\n", [_message UTF8String], [_info length] ? ": " : "", [_info UTF8String]);
  return 1000; }   /* NSAlertFirstButtonReturn */
- (void)beginSheetModalForWindow:(id)w completionHandler:(void (^)(NSInteger))h { NSInteger r = [self runModal]; if (h) h(r); }
- (void)beginSheetModalForWindow:(id)w modalDelegate:(id)d didEndSelector:(SEL)s contextInfo:(void *)c {
  NSInteger r = [self runModal];
  if (d && s) ((void (*)(id, SEL, id, NSInteger, void *))objc_msgSend)(d, s, self, r, c); }
- (void)dealloc { [_message release]; [_info release]; [_buttons release]; [super dealloc]; }
@end

/* ======================================================= SDL2 Cocoa backend */
/* The rest of what SDL2's video backend (SDL_cocoa*.m) sends. Geometry is single-screen and scale 1.0 as above. */
static char kNextResponderKey;
@implementation NSResponder (XefSDL)
- (NSResponder *)nextResponder { return objc_getAssociatedObject(self, &kNextResponderKey); }
- (void)setNextResponder:(NSResponder *)r { objc_setAssociatedObject(self, &kNextResponderKey, r, OBJC_ASSOCIATION_ASSIGN); }
@end

@implementation NSView (XefSDL)
- (NSRect)convertRect:(NSRect)r toView:(NSView *)v { return r; }      /* subviews fill their parent at the origin */
- (NSRect)convertRect:(NSRect)r fromView:(NSView *)v { return r; }
- (NSPoint)convertPoint:(NSPoint)p toView:(NSView *)v { return p; }
- (NSSize)convertSizeToBacking:(NSSize)s { return s; }
- (NSSize)convertSizeFromBacking:(NSSize)s { return s; }
- (NSPoint)convertPointToBacking:(NSPoint)p { return p; }
- (NSView *)hitTest:(NSPoint)p {
  if (!NSPointInRect(p, _frame)) return nil;
  NSPoint q = NSMakePoint(p.x - _frame.origin.x, p.y - _frame.origin.y);
  for (NSView *s in [_subviews reverseObjectEnumerator]) { NSView *h = [s hitTest:q]; if (h) return h; }
  return self; }
- (void)setAutoresizingMask:(NSUInteger)m {} - (NSUInteger)autoresizingMask { return 0; }
- (void)setAutoresizesSubviews:(BOOL)f {}
- (void)addCursorRect:(NSRect)r cursor:(NSCursor *)c {} - (void)resetCursorRects {} - (void)discardCursorRects {}
- (void)setAcceptsTouchEvents:(BOOL)f {} - (void)setAllowedTouchTypes:(NSUInteger)t {}
- (NSView *)viewWithTag:(NSInteger)t { return nil; } - (NSInteger)tag { return -1; }
- (void)unregisterDraggedTypes { [_dragTypes release]; _dragTypes = nil; }
- (void)setHidden:(BOOL)f {} - (BOOL)isHidden { return NO; }
- (void)setPostsFrameChangedNotifications:(BOOL)f {}
- (void)setLayerContentsRedrawPolicy:(NSInteger)p {}
- (NSRect)visibleRect { return _bounds; }
- (BOOL)inLiveResize { return NO; }
@end

@implementation NSWindow (XefSDL)
- (id)initWithContentRect:(NSRect)r styleMask:(NSWindowStyleMask)s backing:(NSBackingStoreType)b defer:(BOOL)d screen:(NSScreen *)sc {
  return [self initWithContentRect:r styleMask:s backing:b defer:d]; }
- (NSScreen *)screen { return [NSScreen mainScreen]; }
- (NSScreen *)deepestScreen { return [NSScreen mainScreen]; }
- (NSRect)contentLayoutRect { NSRect c = [self contentRectForFrameRect:_frame]; return NSMakeRect(0, 0, c.size.width, c.size.height); }
- (id)standardWindowButton:(NSInteger)b { return nil; }   /* no title-bar widgets: the host window manager draws them */
- (void)setMovableByWindowBackground:(BOOL)f {} - (BOOL)isMovableByWindowBackground { return NO; }
- (void)invalidateCursorRectsForView:(NSView *)v {} - (void)disableCursorRects {} - (void)enableCursorRects {}
- (BOOL)isOnActiveSpace { return YES; }
- (void)performClose:(id)s { [self close]; }
- (void)orderBack:(id)s { [self orderFront:s]; } - (void)orderFrontRegardless { [self orderFront:nil]; }
- (void)orderWindow:(NSInteger)place relativeTo:(NSInteger)other { if (place) [self orderFront:nil]; else [self orderOut:nil]; }
- (BOOL)isMainWindow { return _key; } - (void)makeMainWindow {}
- (NSRect)convertRectFromScreen:(NSRect)r { r.origin.x -= _frame.origin.x; r.origin.y -= _frame.origin.y; return r; }
- (NSPoint)convertPointFromScreen:(NSPoint)p { return NSMakePoint(p.x - _frame.origin.x, p.y - _frame.origin.y); }
- (NSPoint)convertPointToScreen:(NSPoint)p { return NSMakePoint(p.x + _frame.origin.x, p.y + _frame.origin.y); }
- (NSRect)convertRectToBacking:(NSRect)r { return r; }
- (void)setFrame:(NSRect)f display:(BOOL)d animate:(BOOL)a { [self setFrame:f display:d]; }
- (void)setFrameTopLeftPoint:(NSPoint)p { NSRect f = _frame; f.origin = NSMakePoint(p.x, p.y - f.size.height); [self _applyFrame:f sync:YES]; }
- (void)setShowsResizeIndicator:(BOOL)f {} - (void)setPreservesContentDuringLiveResize:(BOOL)f {}
- (void)setAllowsConcurrentViewDrawing:(BOOL)f {} - (void)setColorSpace:(id)c {} - (void)setAnimationBehavior:(NSInteger)b {}
- (void)setTitleVisibility:(NSInteger)v {} - (void)setTitlebarAppearsTransparent:(BOOL)f {}
- (void)setDisplaysWhenScreenProfileChanges:(BOOL)f {} - (void)setHidesOnDeactivate:(BOOL)f {}
- (void)setAppearance:(id)a {} - (id)appearance { return nil; } - (id)effectiveAppearance { return nil; }
- (void)setMinSize:(NSSize)s {} - (void)setMaxSize:(NSSize)s {}
- (NSSize)contentMinSize { return _minSize; } - (NSSize)contentMaxSize { return _maxSize; }
- (BOOL)inLiveResize { return NO; } - (BOOL)hasShadow { return _shadow; } - (BOOL)ignoresMouseEvents { return _ignoresMouse; }
- (BOOL)isReleasedWhenClosed { return _released; }
- (void)flushWindow {} - (void)update {} - (void)makeFirstResponderIfNeeded {}
- (void)setDocumentEdited:(BOOL)f {} - (void)setRepresentedFilename:(NSString *)n {}
- (NSInteger)orderedIndex { return 0; } - (void)setOrderedIndex:(NSInteger)i {}
- (BOOL)canEnterFullScreenMode { return YES; }
+ (NSArray *)windowNumbersWithOptions:(NSUInteger)o {
  NSMutableArray *a = [NSMutableArray array];
  for (NSWindow *w in [(NSApplication *)NSApp windows]) if ([w isVisible]) [a insertObject:[NSNumber numberWithInteger:w->_handle] atIndex:0];
  return a; }
@end

@implementation NSApplication (XefSDL)
- (NSArray *)orderedWindows { return [[_windows reverseObjectEnumerator] allObjects]; }   /* front to back */
- (NSWindow *)windowWithWindowNumber:(NSInteger)n { for (NSWindow *w in _windows) if (w->_handle == n) return w; return nil; }
- (void)setApplicationIconImage:(NSImage *)i {} - (NSImage *)applicationIconImage { return nil; }   /* X11 icons are not set */
- (NSInteger)runModalForWindow:(NSWindow *)w { return 1000; }   /* NSModalResponseOK-ish: nothing to wait for */
- (void)stopModal {} - (void)stopModalWithCode:(NSInteger)c {} - (void)abortModal {}
- (NSWindow *)modalWindow { return nil; }
- (void)setPresentationOptions:(NSUInteger)o {} - (NSUInteger)presentationOptions { return 0; } - (NSUInteger)currentSystemPresentationOptions { return 0; }
- (void)activate { _active = YES; }
- (BOOL)isHidden { return NO; } - (void)unhide:(id)s {} - (void)unhideWithoutActivation {}
- (void)cancelUserAttentionRequest:(NSInteger)r {}
- (id)effectiveAppearance { return nil; } - (void)setAppearance:(id)a {}
- (void)discardEventsMatchingMask:(NSUInteger)m beforeEvent:(NSEvent *)e {}
- (id)servicesProvider { return nil; } - (void)setServicesProvider:(id)p {}
- (void)registerUserInterfaceItemSearchHandler:(id)h {}
- (BOOL)isFullKeyboardAccessEnabled { return NO; }
- (void)setHelpMenu:(NSMenu *)m {}
@end

@implementation NSRunningApplication (XefSDL)
+ (NSArray *)runningApplicationsWithBundleIdentifier:(NSString *)b { return [NSArray array]; }   /* no Dock/Finder to activate first */
- (BOOL)activateWithOptions:(NSUInteger)o { if (NSApp) [NSApp activateIgnoringOtherApps:YES]; return YES; }
- (NSString *)bundleIdentifier { return [[NSBundle mainBundle] bundleIdentifier]; }
- (BOOL)isHidden { return NO; } - (pid_t)processIdentifier { return getpid(); }
@end

@implementation NSEvent (XefSDL)
- (NSUInteger)phase { return 0; } - (NSUInteger)momentumPhase { return 0; }   /* NSEventPhaseNone */
- (short)subtype { return 0; }                                                 /* NSEventSubtypeMouseEvent */
- (BOOL)isDirectionInvertedFromDevice { return NO; }
- (NSSet *)touchesMatchingPhase:(NSUInteger)p inView:(NSView *)v { return [NSSet set]; }
- (NSInteger)windowNumber { return _window ? [(NSWindow *)_window windowNumber] : 0; }
- (float)pressure { return 1.0f; } - (CGFloat)deltaZ { return 0; }
- (NSUInteger)deviceID { return 0; } - (void *)CGEvent { return NULL; }
@end

@implementation NSPasteboard (XefSDL)
- (NSInteger)changeCount { return _change; }
- (NSString *)availableTypeFromArray:(NSArray *)types { for (NSString *t in types) if ([_types containsObject:t]) return t; return nil; }
- (NSData *)dataForType:(NSString *)t { id v = [_data objectForKey:t]; return [v isKindOfClass:[NSString class]] ? [v dataUsingEncoding:NSUTF8StringEncoding] : v; }
- (id)propertyListForType:(NSString *)t { return [_data objectForKey:t]; }
@end

@implementation NSCursor (XefSDL)
+ (NSCursor *)currentCursor { return [self arrowCursor]; }
+ (NSCursor *)currentSystemCursor { return [self arrowCursor]; }
+ (NSCursor *)disappearingItemCursor { return [self arrowCursor]; } + (NSCursor *)dragCopyCursor { return [self arrowCursor]; }
+ (NSCursor *)openHandCursor { return [self arrowCursor]; } + (NSCursor *)resizeLeftCursor { return [self arrowCursor]; }
+ (NSCursor *)resizeRightCursor { return [self arrowCursor]; } + (NSCursor *)resizeUpCursor { return [self arrowCursor]; }
+ (NSCursor *)resizeDownCursor { return [self arrowCursor]; } + (NSCursor *)contextualMenuCursor { return [self arrowCursor]; }
+ (void)setHiddenUntilMouseMoves:(BOOL)f {}
- (NSImage *)image { return _image; } - (NSPoint)hotSpot { return _hot; }
@end

@implementation NSMenu (XefSDL)
+ (void)setMenuBarVisible:(BOOL)f {} + (BOOL)menuBarVisible { return NO; }
- (NSInteger)numberOfItems { return [_items count]; }
- (NSMenuItem *)itemAtIndex:(NSInteger)i { return [_items objectAtIndex:i]; }
- (void)removeAllItems { [_items removeAllObjects]; }
- (void)setAutoenablesItems:(BOOL)f {}
@end

@implementation NSOpenGLPixelFormat (XefSDL)
- (void *)CGLPixelFormatObj { return self; }
@end

@implementation NSImage (XefSDL)
- (void)drawInRect:(NSRect)d fromRect:(NSRect)s operation:(NSUInteger)op fraction:(CGFloat)f {}   /* no 2D drawing on X11-lite */
- (void)setSize:(NSSize)s { _size = s; } - (BOOL)isValid { return YES; }
- (void)lockFocus {} - (void)unlockFocus {}
@end

/* minimal 2D drawing classes: SDL's software framebuffer path draws through them; nothing is drawn (OpenGL only) */
@interface NSGraphicsContext : NSObject
@end
@implementation NSGraphicsContext
static NSGraphicsContext *g_gc;
+ (NSGraphicsContext *)currentContext { return g_gc; }
+ (void)setCurrentContext:(NSGraphicsContext *)c { [c retain]; [g_gc release]; g_gc = c; }
+ (NSGraphicsContext *)graphicsContextWithWindow:(NSWindow *)w { return [[[NSGraphicsContext alloc] init] autorelease]; }
+ (NSGraphicsContext *)graphicsContextWithCGContext:(void *)c flipped:(BOOL)f { return [[[NSGraphicsContext alloc] init] autorelease]; }
+ (void)saveGraphicsState {} + (void)restoreGraphicsState {}
- (void)saveGraphicsState {} - (void)restoreGraphicsState {} - (void)flushGraphics {}
- (void *)CGContext { return NULL; } - (void *)graphicsPort { return NULL; }
- (void)setCompositingOperation:(NSUInteger)o {} - (void)setShouldAntialias:(BOOL)f {}
@end

@interface NSBezierPath : NSObject
@end
@implementation NSBezierPath
+ (NSBezierPath *)bezierPath { return [[[NSBezierPath alloc] init] autorelease]; }
+ (NSBezierPath *)bezierPathWithRect:(NSRect)r { return [self bezierPath]; }
+ (void)fillRect:(NSRect)r {} + (void)strokeRect:(NSRect)r {} + (void)clipRect:(NSRect)r {}
- (void)appendBezierPathWithRect:(NSRect)r {} - (void)addClip {} - (void)setClip {} - (void)fill {} - (void)stroke {}
- (void)moveToPoint:(NSPoint)p {} - (void)lineToPoint:(NSPoint)p {} - (void)closePath {}
@end

@interface NSColorSpace : NSObject
@end
@implementation NSColorSpace
+ (NSColorSpace *)sRGBColorSpace { static NSColorSpace *s; if (!s) s = [[NSColorSpace alloc] init]; return s; }
+ (NSColorSpace *)deviceRGBColorSpace { return [self sRGBColorSpace]; } + (NSColorSpace *)genericRGBColorSpace { return [self sRGBColorSpace]; }
- (NSData *)ICCProfileData { return nil; } - (void *)CGColorSpace { return NULL; } - (NSInteger)numberOfColorComponents { return 3; }
@end

void NSRectFill(NSRect r) {}
void NSBeep(void) {}

/* Anything else AppKit has and AppKit-lite does not: windows, views and the application answer unknown selectors with a
 * logged no-op returning 0/nil (setters of cosmetic state such as setOneShot: dominate). Selectors that SDL/GLFW probe
 * with respondsToSelector: are unaffected: resolveInstanceMethod: is only reached when a message is actually sent. */
static id lite_stub(id self, SEL _cmd, ...) {
  static NSMutableSet *seen; @synchronized ([NSResponder class]) {
    if (!seen) seen = [[NSMutableSet alloc] init];
    NSString *k = [NSString stringWithFormat:@"%s %s", class_getName(object_getClass(self)), sel_getName(_cmd)];
    if (![seen containsObject:k]) { [seen addObject:k]; fprintf(stderr, "STUB -[%s %s]\n", class_getName(object_getClass(self)), sel_getName(_cmd)); } }
  return nil; }
@implementation NSResponder (XefStubs)
+ (BOOL)resolveInstanceMethod:(SEL)sel {
  const char *n = sel_getName(sel);
  if (n[0] == '_' || !strncmp(n, "respondsTo", 10) || !strncmp(n, "init", 4) || !strncmp(n, "copy", 4) || !strncmp(n, "mutableCopy", 11)) return NO;
  /* only real AppKit classes and their subclasses */
  BOOL appkit = NO;
  for (Class c = self; c; c = class_getSuperclass(c))
    if (c == [NSView class] || c == [NSWindow class] || c == [NSApplication class]) { appkit = YES; break; }
  if (!appkit) return NO;
  class_addMethod(self, sel, (IMP)lite_stub, "@@:");
  return YES; }
@end

@implementation NSBitmapImageRep (XefSDL)
- (id)initWithBitmapDataPlanes:(unsigned char **)planes pixelsWide:(NSInteger)w pixelsHigh:(NSInteger)h bitsPerSample:(NSInteger)bps
    samplesPerPixel:(NSInteger)spp hasAlpha:(BOOL)a isPlanar:(BOOL)p colorSpaceName:(NSString *)cs bytesPerRow:(NSInteger)bpr bitsPerPixel:(NSInteger)bpp {
  return [self initWithBitmapDataPlanes:planes pixelsWide:w pixelsHigh:h bitsPerSample:bps samplesPerPixel:spp hasAlpha:a isPlanar:p
                         colorSpaceName:cs bitmapFormat:0 bytesPerRow:bpr bitsPerPixel:bpp]; }
- (NSInteger)samplesPerPixel { return _spp; } - (NSInteger)bitsPerSample { return _bps; } - (BOOL)hasAlpha { return _alpha; }
- (NSSize)size { return NSMakeSize(_w, _h); } - (void)setSize:(NSSize)s {}
@end
