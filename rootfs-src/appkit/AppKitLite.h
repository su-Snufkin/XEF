/* AppKit-lite public declarations (values follow Apple's public API). */
#import <Foundation/Foundation.h>
#include <stdint.h>

typedef NS_ENUM(NSUInteger, NSBackingStoreType) { NSBackingStoreRetained = 0, NSBackingStoreNonretained = 1, NSBackingStoreBuffered = 2 };
typedef NS_OPTIONS(NSUInteger, NSWindowStyleMask) {
  NSWindowStyleMaskBorderless = 0, NSWindowStyleMaskTitled = 1 << 0, NSWindowStyleMaskClosable = 1 << 1,
  NSWindowStyleMaskMiniaturizable = 1 << 2, NSWindowStyleMaskResizable = 1 << 3, NSWindowStyleMaskFullSizeContentView = 1 << 15 };
typedef NS_ENUM(NSInteger, NSApplicationActivationPolicy) { NSApplicationActivationPolicyRegular, NSApplicationActivationPolicyAccessory, NSApplicationActivationPolicyProhibited };
typedef NS_ENUM(NSUInteger, NSEventType) {
  NSEventTypeLeftMouseDown = 1, NSEventTypeLeftMouseUp = 2, NSEventTypeRightMouseDown = 3, NSEventTypeRightMouseUp = 4,
  NSEventTypeMouseMoved = 5, NSEventTypeLeftMouseDragged = 6, NSEventTypeRightMouseDragged = 7, NSEventTypeMouseEntered = 8,
  NSEventTypeMouseExited = 9, NSEventTypeKeyDown = 10, NSEventTypeKeyUp = 11, NSEventTypeFlagsChanged = 12,
  NSEventTypeAppKitDefined = 13, NSEventTypeSystemDefined = 14, NSEventTypeApplicationDefined = 15, NSEventTypePeriodic = 16,
  NSEventTypeScrollWheel = 22, NSEventTypeOtherMouseDown = 25, NSEventTypeOtherMouseUp = 26, NSEventTypeOtherMouseDragged = 27 };
typedef NS_OPTIONS(NSUInteger, NSEventModifierFlags) {
  NSEventModifierFlagCapsLock = 1 << 16, NSEventModifierFlagShift = 1 << 17, NSEventModifierFlagControl = 1 << 18,
  NSEventModifierFlagOption = 1 << 19, NSEventModifierFlagCommand = 1 << 20 };
#define NSEventMaskAny (~(uint64_t)0)
typedef uint32_t NSOpenGLPixelFormatAttribute;
enum { NSOpenGLPFAAllRenderers = 1, NSOpenGLPFATripleBuffer = 3, NSOpenGLPFADoubleBuffer = 5, NSOpenGLPFAStereo = 6,
  NSOpenGLPFAAuxBuffers = 7, NSOpenGLPFAColorSize = 8, NSOpenGLPFAAlphaSize = 11, NSOpenGLPFADepthSize = 12,
  NSOpenGLPFAStencilSize = 13, NSOpenGLPFAAccumSize = 14, NSOpenGLPFAMinimumPolicy = 51, NSOpenGLPFAMaximumPolicy = 52,
  NSOpenGLPFAOffScreen = 53, NSOpenGLPFAFullScreen = 54, NSOpenGLPFASampleBuffers = 55, NSOpenGLPFASamples = 56,
  NSOpenGLPFAAuxDepthStencil = 57, NSOpenGLPFAColorFloat = 58, NSOpenGLPFAMultisample = 59, NSOpenGLPFASupersample = 60,
  NSOpenGLPFASampleAlpha = 61, NSOpenGLPFARendererID = 70, NSOpenGLPFASingleRenderer = 71, NSOpenGLPFANoRecovery = 72,
  NSOpenGLPFAAccelerated = 73, NSOpenGLPFAClosestPolicy = 74, NSOpenGLPFABackingStore = 76, NSOpenGLPFAWindow = 80,
  NSOpenGLPFACompliant = 83, NSOpenGLPFAScreenMask = 84, NSOpenGLPFAAllowOfflineRenderers = 96,
  NSOpenGLPFAAcceleratedCompute = 97, NSOpenGLPFAOpenGLProfile = 99, NSOpenGLPFAVirtualScreenCount = 128 };
enum { NSOpenGLProfileVersionLegacy = 0x1000, NSOpenGLProfileVersion3_2Core = 0x3200, NSOpenGLProfileVersion4_1Core = 0x4100 };
typedef int32_t NSOpenGLContextParameter;
enum { NSOpenGLCPSwapInterval = 222, NSOpenGLCPSurfaceOrder = 235, NSOpenGLCPSurfaceOpacity = 236, NSOpenGLCPSwapRectangle = 200 };

extern id NSApp;
extern NSString *const NSWindowWillCloseNotification, *const NSApplicationDidFinishLaunchingNotification;

@interface NSResponder : NSObject
- (BOOL)acceptsFirstResponder;
- (BOOL)becomeFirstResponder;
- (BOOL)resignFirstResponder;
- (void)keyDown:(id)e; - (void)keyUp:(id)e; - (void)flagsChanged:(id)e;
- (void)mouseDown:(id)e; - (void)mouseUp:(id)e; - (void)mouseMoved:(id)e; - (void)mouseDragged:(id)e;
- (void)rightMouseDown:(id)e; - (void)rightMouseUp:(id)e; - (void)rightMouseDragged:(id)e;
- (void)otherMouseDown:(id)e; - (void)otherMouseUp:(id)e; - (void)otherMouseDragged:(id)e;
- (void)scrollWheel:(id)e;
@end

@interface NSEvent : NSObject {
@public
  NSEventType _type; unsigned short _keyCode; NSPoint _loc; NSEventModifierFlags _flags; NSString *_chars;
  id _window; double _ts; NSInteger _button; double _dx, _dy;
}
- (NSEventType)type; - (unsigned short)keyCode; - (NSPoint)locationInWindow; - (NSEventModifierFlags)modifierFlags;
- (NSString *)characters; - (NSString *)charactersIgnoringModifiers; - (id)window; - (NSTimeInterval)timestamp;
- (NSInteger)buttonNumber; - (CGFloat)deltaX; - (CGFloat)deltaY; - (CGFloat)scrollingDeltaX; - (CGFloat)scrollingDeltaY;
- (BOOL)hasPreciseScrollingDeltas; - (BOOL)isARepeat; - (NSInteger)clickCount;
+ (NSEvent *)otherEventWithType:(NSEventType)t location:(NSPoint)p modifierFlags:(NSUInteger)f timestamp:(NSTimeInterval)ts
    windowNumber:(NSInteger)w context:(id)c subtype:(short)s data1:(NSInteger)d1 data2:(NSInteger)d2;
+ (NSEventModifierFlags)modifierFlags; + (NSUInteger)pressedMouseButtons; + (NSPoint)mouseLocation;
@end

@interface NSScreen : NSObject
+ (NSScreen *)mainScreen; + (NSArray *)screens;
- (NSRect)frame; - (NSRect)visibleFrame; - (CGFloat)backingScaleFactor;
@end

@interface NSColor : NSObject { @public CGFloat r, g, b, a; }
+ (NSColor *)colorWithCalibratedRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (NSColor *)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (NSColor *)blackColor; + (NSColor *)whiteColor; + (NSColor *)clearColor;
- (CGFloat)redComponent; - (CGFloat)greenComponent; - (CGFloat)blueComponent; - (CGFloat)alphaComponent; - (void)set;
@end

@interface NSCursor : NSObject
+ (NSCursor *)arrowCursor; + (NSCursor *)IBeamCursor; + (NSCursor *)crosshairCursor; + (NSCursor *)pointingHandCursor;
+ (void)hide; + (void)unhide; - (void)set; - (void)push; - (void)pop;
@end

@interface NSMenuItem : NSObject { @public NSString *_title; id _sub; SEL _action; NSString *_key; id _target; }
- (id)initWithTitle:(NSString *)t action:(SEL)a keyEquivalent:(NSString *)k;
- (void)setSubmenu:(id)m; - (id)submenu; - (NSString *)title; - (void)setTitle:(NSString *)t;
- (void)setTarget:(id)t; - (id)target; - (SEL)action; - (void)setKeyEquivalentModifierMask:(NSUInteger)m;
+ (NSMenuItem *)separatorItem;
@end
@interface NSMenu : NSObject { @public NSString *_title; NSMutableArray *_items; }
- (id)initWithTitle:(NSString *)t; - (void)addItem:(NSMenuItem *)i;
- (NSMenuItem *)addItemWithTitle:(NSString *)t action:(SEL)a keyEquivalent:(NSString *)k;
- (NSArray *)itemArray; - (NSString *)title;
@end

@class NSWindow, NSOpenGLContext, NSOpenGLPixelFormat;

@interface NSView : NSResponder {
@public
  NSRect _frame, _bounds; NSWindow *_window; NSView *_superview; NSMutableArray *_subviews; BOOL _needsDisplay, _bestRes;
}
- (id)initWithFrame:(NSRect)f;
- (NSRect)frame; - (NSRect)bounds; - (void)setFrame:(NSRect)f; - (void)setFrameSize:(NSSize)s; - (void)setBounds:(NSRect)b;
- (NSWindow *)window; - (NSView *)superview; - (NSArray *)subviews; - (void)addSubview:(NSView *)v; - (void)removeFromSuperview;
- (void)setNeedsDisplay:(BOOL)f; - (BOOL)needsDisplay; - (void)display; - (void)displayIfNeeded;
- (void)drawRect:(NSRect)r; - (BOOL)isFlipped; - (BOOL)isOpaque; - (void)viewDidMoveToWindow;
- (void)lockFocus; - (void)unlockFocus; - (void)setWantsBestResolutionOpenGLSurface:(BOOL)f;
- (NSRect)convertRectToBacking:(NSRect)r; - (NSRect)convertRectFromBacking:(NSRect)r;
- (NSPoint)convertPoint:(NSPoint)p fromView:(NSView *)v; - (void)setWantsLayer:(BOOL)f; - (void)updateTrackingAreas;
@end

@interface NSWindow : NSResponder {
@public
  NSRect _frame; NSWindowStyleMask _style; NSView *_content; NSString *_title; int _handle; BOOL _visible, _released, _moved, _key, _closed;
  id _delegate; NSResponder *_first; id _bg;
}
- (id)initWithContentRect:(NSRect)r styleMask:(NSWindowStyleMask)s backing:(NSBackingStoreType)b defer:(BOOL)d;
- (void)makeKeyAndOrderFront:(id)s; - (void)orderFront:(id)s; - (void)orderOut:(id)s; - (void)makeKeyWindow; - (BOOL)isKeyWindow;
- (void)setTitle:(NSString *)t; - (NSString *)title; - (void)setContentView:(NSView *)v; - (NSView *)contentView;
- (NSRect)frame; - (void)setFrame:(NSRect)f display:(BOOL)d; - (void)setFrameOrigin:(NSPoint)p; - (void)setContentSize:(NSSize)s;
- (NSRect)contentRectForFrameRect:(NSRect)f; - (NSRect)frameRectForContentRect:(NSRect)c;
+ (NSRect)contentRectForFrameRect:(NSRect)f styleMask:(NSWindowStyleMask)m; + (NSRect)frameRectForContentRect:(NSRect)c styleMask:(NSWindowStyleMask)m;
- (void)close; - (BOOL)isVisible; - (void)setReleasedWhenClosed:(BOOL)f; - (void)center; - (void)setAcceptsMouseMovedEvents:(BOOL)f;
- (BOOL)makeFirstResponder:(NSResponder *)r; - (NSResponder *)firstResponder; - (void)setDelegate:(id)d; - (id)delegate;
- (CGFloat)backingScaleFactor; - (void)setOpaque:(BOOL)f; - (void)setBackgroundColor:(NSColor *)c; - (void)display; - (NSInteger)windowNumber;
- (void)sendEvent:(NSEvent *)e; - (int)xefHandle;
@end

@interface NSApplication : NSResponder {
@public
  id _delegate; NSMutableArray *_queue, *_windows; BOOL _running, _launched, _active; NSApplicationActivationPolicy _policy; NSMenu *_menu;
}
+ (NSApplication *)sharedApplication;
- (BOOL)setActivationPolicy:(NSApplicationActivationPolicy)p; - (void)activateIgnoringOtherApps:(BOOL)f; - (BOOL)isActive;
- (void)run; - (void)stop:(id)s; - (void)terminate:(id)s; - (void)finishLaunching; - (BOOL)isRunning;
- (NSEvent *)nextEventMatchingMask:(NSUInteger)m untilDate:(NSDate *)d inMode:(NSString *)mode dequeue:(BOOL)dq;
- (void)sendEvent:(NSEvent *)e; - (void)postEvent:(NSEvent *)e atStart:(BOOL)s;
- (void)setDelegate:(id)d; - (id)delegate; - (NSArray *)windows; - (NSWindow *)keyWindow; - (NSWindow *)mainWindow;
- (void)setMainMenu:(NSMenu *)m; - (NSMenu *)mainMenu; - (void)updateWindows; - (void)_addWindow:(NSWindow *)w; - (void)_removeWindow:(NSWindow *)w;
@end

@interface NSOpenGLPixelFormat : NSObject {
@public
  NSOpenGLPixelFormatAttribute _attrs[64]; int _n; BOOL dbl; int color, alpha, depth, stencil, samples, sampleBuffers, profile;
}
- (id)initWithAttributes:(const NSOpenGLPixelFormatAttribute *)a;
- (id)initWithData:(NSData *)d; - (NSInteger)numberOfVirtualScreens;
- (void)getValues:(int *)vals forAttribute:(NSOpenGLPixelFormatAttribute)a forVirtualScreen:(int)s;
@end

@interface NSOpenGLContext : NSObject {
@public
  NSOpenGLPixelFormat *_pf; NSView *_view; NSOpenGLContext *_share; int _swap; BOOL _opaque;
}
- (id)initWithFormat:(NSOpenGLPixelFormat *)f shareContext:(NSOpenGLContext *)s;
- (void)setView:(NSView *)v; - (NSView *)view; - (void)makeCurrentContext; + (void)clearCurrentContext; + (NSOpenGLContext *)currentContext;
- (void)clearDrawable; - (void)flushBuffer; - (void)update; - (void)setValues:(const int *)v forParameter:(NSOpenGLContextParameter)p;
- (void)getValues:(int *)v forParameter:(NSOpenGLContextParameter)p; - (NSOpenGLPixelFormat *)pixelFormat; - (void *)CGLContextObj;
@end

@interface NSOpenGLView : NSView {
@public
  NSOpenGLContext *_ctx; NSOpenGLPixelFormat *_pf; BOOL _prepared;
}
+ (NSOpenGLPixelFormat *)defaultPixelFormat;
- (id)initWithFrame:(NSRect)f pixelFormat:(NSOpenGLPixelFormat *)pf;
- (NSOpenGLContext *)openGLContext; - (void)setOpenGLContext:(NSOpenGLContext *)c; - (NSOpenGLPixelFormat *)pixelFormat;
- (void)setPixelFormat:(NSOpenGLPixelFormat *)p; - (void)prepareOpenGL; - (void)reshape; - (void)update; - (void)clearGLContext;
@end
