/* AppKit-lite public declarations (values follow Apple's public API). */
#import <Foundation/Foundation.h>
#include <stdint.h>

typedef NS_ENUM(NSUInteger, NSBackingStoreType) { NSBackingStoreRetained = 0, NSBackingStoreNonretained = 1, NSBackingStoreBuffered = 2 };
typedef NS_OPTIONS(NSUInteger, NSWindowStyleMask) {
  NSWindowStyleMaskBorderless = 0, NSWindowStyleMaskTitled = 1 << 0, NSWindowStyleMaskClosable = 1 << 1,
  NSWindowStyleMaskMiniaturizable = 1 << 2, NSWindowStyleMaskResizable = 1 << 3,
  NSWindowStyleMaskFullScreen = 1 << 14, NSWindowStyleMaskFullSizeContentView = 1 << 15 };
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
typedef NS_OPTIONS(NSUInteger, NSTrackingAreaOptions) {
  NSTrackingMouseEnteredAndExited = 0x01, NSTrackingMouseMoved = 0x02, NSTrackingCursorUpdate = 0x04,
  NSTrackingActiveWhenFirstResponder = 0x10, NSTrackingActiveInKeyWindow = 0x20, NSTrackingActiveInActiveApp = 0x40,
  NSTrackingActiveAlways = 0x80, NSTrackingAssumeInside = 0x100, NSTrackingInVisibleRect = 0x200,
  NSTrackingEnabledDuringMouseDrag = 0x400 };
typedef NS_ENUM(NSUInteger, NSBitmapFormat) { NSBitmapFormatAlphaFirst = 1, NSBitmapFormatAlphaNonpremultiplied = 2, NSBitmapFormatFloatingPointSamples = 4 };
typedef NS_OPTIONS(NSUInteger, NSWindowOcclusionState) { NSWindowOcclusionStateVisible = 1 << 1 };
typedef NS_ENUM(NSUInteger, NSApplicationTerminateReply) { NSTerminateCancel = 0, NSTerminateNow = 1, NSTerminateLater = 2 };
typedef NS_ENUM(NSUInteger, NSRequestUserAttentionType) { NSCriticalRequest = 0, NSInformationalRequest = 10 };
enum { NSOpenGLCPSwapInterval = 222, NSOpenGLCPSurfaceOrder = 235, NSOpenGLCPSurfaceOpacity = 236, NSOpenGLCPSwapRectangle = 200 };

extern id NSApp;
extern NSString *const NSWindowWillCloseNotification, *const NSApplicationDidFinishLaunchingNotification;
extern NSString *const NSCalibratedRGBColorSpace, *const NSPasteboardTypeString, *const NSPasteboardTypeURL,
    *const NSPasteboardURLReadingFileURLsOnlyKey, *const NSTextInputContextKeyboardSelectionDidChangeNotification;
extern NSString *const NSDefaultRunLoopMode, *const NSRunLoopCommonModes;
extern NSString *const NSWindowDidFailToEnterFullScreenNotification, *const NSWindowDidFailToExitFullScreenNotification;
extern const NSPoint NSZeroPoint;
extern const NSRect NSZeroRect;
BOOL NSPointInRect(NSPoint aPoint, NSRect aRect);
BOOL NSMouseInRect(NSPoint aPoint, NSRect aRect, BOOL flipped);

@interface NSResponder : NSObject {
@public
  NSResponder *_nextResponder;
}
- (NSResponder *)nextResponder;
- (void)setNextResponder:(NSResponder *)r;
- (BOOL)acceptsFirstResponder;
- (BOOL)becomeFirstResponder;
- (BOOL)resignFirstResponder;
- (void)keyDown:(id)e; - (void)keyUp:(id)e; - (void)flagsChanged:(id)e;
- (void)mouseDown:(id)e; - (void)mouseUp:(id)e; - (void)mouseMoved:(id)e; - (void)mouseDragged:(id)e;
- (void)rightMouseDown:(id)e; - (void)rightMouseUp:(id)e; - (void)rightMouseDragged:(id)e;
- (void)otherMouseDown:(id)e; - (void)otherMouseUp:(id)e; - (void)otherMouseDragged:(id)e;
- (void)scrollWheel:(id)e;
- (void)mouseEntered:(id)e; - (void)mouseExited:(id)e; - (void)cursorUpdate:(id)e;
- (void)tabletPoint:(id)e; - (void)tabletProximity:(id)e;
- (void)interpretKeyEvents:(NSArray *)events;
- (void)doCommandBySelector:(SEL)aSelector;
@end

@interface NSEvent : NSObject {
@public
  NSEventType _type; unsigned short _keyCode; NSPoint _loc; NSEventModifierFlags _flags; NSString *_chars;
  id _window; double _ts; NSInteger _button; double _dx, _dy;
}
- (NSEventType)type; - (unsigned short)keyCode; - (NSPoint)locationInWindow; - (NSEventModifierFlags)modifierFlags;
- (NSString *)characters; - (NSString *)charactersIgnoringModifiers; - (id)window; - (NSTimeInterval)timestamp;
- (NSInteger)buttonNumber; - (CGFloat)deltaX; - (CGFloat)deltaY; - (CGFloat)scrollingDeltaX; - (CGFloat)scrollingDeltaY;
- (BOOL)hasPreciseScrollingDeltas; - (BOOL)isARepeat; - (NSInteger)clickCount; - (NSInteger)windowNumber;
+ (NSEvent *)otherEventWithType:(NSEventType)t location:(NSPoint)p modifierFlags:(NSUInteger)f timestamp:(NSTimeInterval)ts
    windowNumber:(NSInteger)w context:(id)c subtype:(short)s data1:(NSInteger)d1 data2:(NSInteger)d2;
+ (NSEventModifierFlags)modifierFlags; + (NSUInteger)pressedMouseButtons; + (NSPoint)mouseLocation;
+ (id)addLocalMonitorForEventsMatchingMask:(unsigned long long)mask handler:(NSEvent *(^)(NSEvent *))block;
+ (void)removeMonitor:(id)monitor;
@end

@interface NSTrackingArea : NSObject { @public NSRect _rect; NSTrackingAreaOptions _options; id _owner; NSDictionary *_userInfo; }
- (id)initWithRect:(NSRect)r options:(NSTrackingAreaOptions)o owner:(id)owner userInfo:(NSDictionary *)u;
- (NSRect)rect; - (NSTrackingAreaOptions)options; - (id)owner; - (NSDictionary *)userInfo;
@end

@interface NSBitmapImageRep : NSObject { @public unsigned char *_data; NSInteger _w, _h, _bps, _spp, _bpr, _bpp; BOOL _alpha, _planar; NSBitmapFormat _fmt; NSString *_cs; }
- (id)initWithBitmapDataPlanes:(unsigned char **)planes pixelsWide:(NSInteger)w pixelsHigh:(NSInteger)h bitsPerSample:(NSInteger)bps
    samplesPerPixel:(NSInteger)spp hasAlpha:(BOOL)a isPlanar:(BOOL)p colorSpaceName:(NSString *)cs bitmapFormat:(NSBitmapFormat)f
    bytesPerRow:(NSInteger)bpr bitsPerPixel:(NSInteger)bpp;
- (unsigned char *)bitmapData; - (NSInteger)pixelsWide; - (NSInteger)pixelsHigh; - (NSInteger)bytesPerRow; - (NSInteger)bitsPerPixel;
@end

@interface NSImage : NSObject { @public NSSize _size; NSMutableArray *_reps; }
- (id)initWithSize:(NSSize)s; - (NSSize)size; - (void)addRepresentation:(id)rep; - (NSArray *)representations;
@end

@interface NSPasteboardItem : NSObject { @public NSMutableDictionary *_data; }
- (NSArray *)types;
- (BOOL)setString:(NSString *)s forType:(NSString *)t;
- (NSString *)stringForType:(NSString *)t;
- (BOOL)setData:(NSData *)d forType:(NSString *)t;
- (NSData *)dataForType:(NSString *)t;
@end

@interface NSPasteboard : NSObject { @public NSMutableArray *_types; NSMutableDictionary *_data; NSInteger _change; }
+ (NSPasteboard *)generalPasteboard;
- (NSInteger)declareTypes:(NSArray *)types owner:(id)owner; - (BOOL)setString:(NSString *)s forType:(NSString *)t;
- (NSString *)stringForType:(NSString *)t; - (NSArray *)types;
- (NSArray *)readObjectsForClasses:(NSArray *)classes options:(NSDictionary *)o;
- (NSInteger)clearContents; - (BOOL)writeObjects:(NSArray *)objects;
@end

@interface NSStatusItem : NSObject { @public id _menu; NSString *_title; id _image; id _button; }
- (id)button; - (id)menu; - (void)setMenu:(id)m; - (void)setTitle:(NSString *)t; - (void)setImage:(id)i; - (void)setHighlightMode:(BOOL)f;
@end

@interface NSStatusBar : NSObject
+ (NSStatusBar *)systemStatusBar;
- (NSStatusItem *)statusItemWithLength:(CGFloat)length;
- (void)removeStatusItem:(NSStatusItem *)item;
@end

@interface NSRunningApplication : NSObject
+ (NSRunningApplication *)currentApplication;
- (BOOL)isFinishedLaunching; - (BOOL)isActive; - (NSString *)localizedName;
@end

@interface NSScreen : NSObject
+ (NSScreen *)mainScreen; + (NSArray *)screens;
- (NSRect)frame; - (NSRect)visibleFrame; - (CGFloat)backingScaleFactor;
- (NSDictionary *)deviceDescription; - (NSRect)convertRectToBacking:(NSRect)r; - (NSString *)localizedName;
@end

@interface NSColor : NSObject { @public CGFloat r, g, b, a; }
+ (NSColor *)colorWithCalibratedRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (NSColor *)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (NSColor *)blackColor; + (NSColor *)whiteColor; + (NSColor *)clearColor;
- (CGFloat)redComponent; - (CGFloat)greenComponent; - (CGFloat)blueComponent; - (CGFloat)alphaComponent; - (void)set;
@end

@class NSImage;
@interface NSCursor : NSObject { @public NSImage *_image; NSPoint _hot; }
+ (NSCursor *)arrowCursor; + (NSCursor *)IBeamCursor; + (NSCursor *)crosshairCursor; + (NSCursor *)pointingHandCursor;
+ (NSCursor *)resizeLeftRightCursor; + (NSCursor *)resizeUpDownCursor; + (NSCursor *)closedHandCursor; + (NSCursor *)operationNotAllowedCursor;
+ (void)hide; + (void)unhide; - (void)set; - (void)push; - (void)pop;
- (id)initWithImage:(NSImage *)i hotSpot:(NSPoint)p;
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
  NSMutableArray *_tracking; id _layer; BOOL _wantsLayer; NSArray *_dragTypes;
  NSUInteger _autoresizingMask; BOOL _autoresizesSubviews;
}
+ (Class)layerClass;
- (id)makeBackingLayer;
- (id)initWithFrame:(NSRect)f;
- (NSRect)frame; - (NSRect)bounds; - (void)setFrame:(NSRect)f; - (void)setFrameSize:(NSSize)s; - (void)setBounds:(NSRect)b;
- (NSWindow *)window; - (NSView *)superview; - (NSArray *)subviews; - (void)addSubview:(NSView *)v; - (void)removeFromSuperview;
- (void)setNeedsDisplay:(BOOL)f; - (BOOL)needsDisplay; - (void)display; - (void)displayIfNeeded;
- (void)drawRect:(NSRect)r; - (BOOL)isFlipped; - (BOOL)isOpaque; - (void)viewDidMoveToWindow;
- (void)lockFocus; - (void)unlockFocus; - (void)setWantsBestResolutionOpenGLSurface:(BOOL)f;
- (NSRect)convertRectToBacking:(NSRect)r; - (NSRect)convertRectFromBacking:(NSRect)r;
- (NSPoint)convertPoint:(NSPoint)p fromView:(NSView *)v;
- (NSPoint)convertPoint:(NSPoint)p toView:(NSView *)v;
- (NSSize)convertSizeToBacking:(NSSize)s; - (NSSize)convertSizeFromBacking:(NSSize)s;
- (void)setAutoresizingMask:(NSUInteger)m; - (NSUInteger)autoresizingMask;
- (void)setAutoresizesSubviews:(BOOL)f; - (BOOL)autoresizesSubviews;
- (NSView *)hitTest:(NSPoint)p;
- (void)setWantsLayer:(BOOL)f; - (void)updateTrackingAreas;
- (void)addTrackingArea:(NSTrackingArea *)a; - (void)removeTrackingArea:(NSTrackingArea *)a; - (NSArray *)trackingAreas;
- (void)registerForDraggedTypes:(NSArray *)t; - (BOOL)mouse:(NSPoint)p inRect:(NSRect)r; - (void)viewDidChangeBackingProperties;
- (id)layer; - (void)setLayer:(id)l; - (BOOL)wantsLayer;
@end

@interface NSWindow : NSResponder {
@public
  NSRect _frame; NSWindowStyleMask _style; NSView *_content; NSString *_title; int _handle; BOOL _visible, _released, _moved, _key, _closed;
  id _delegate; NSResponder *_first; id _bg;
  NSInteger _level; NSUInteger _collection; NSString *_miniTitle; BOOL _mini, _zoomed, _opaque, _shadow, _ignoresMouse; CGFloat _alpha;
  NSRect _unzoomed; NSSize _minSize, _maxSize, _aspect; BOOL _inside;
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
- (BOOL)canBecomeKeyWindow; - (BOOL)canBecomeMainWindow; - (void)resignKeyWindow;
- (void)setLevel:(NSInteger)l; - (NSInteger)level; - (void)setCollectionBehavior:(NSUInteger)b; - (NSUInteger)collectionBehavior;
- (NSPoint)cascadeTopLeftFromPoint:(NSPoint)p; - (void)zoom:(id)s; - (BOOL)isZoomed; - (void)performZoom:(id)s;
- (void)miniaturize:(id)s; - (void)deminiaturize:(id)s; - (BOOL)isMiniaturized; - (void)performMiniaturize:(id)s;
- (void)setFrameAutosaveName:(NSString *)n; - (void)setContentMinSize:(NSSize)s; - (void)setContentMaxSize:(NSSize)s;
- (void)setContentAspectRatio:(NSSize)s; - (void)setResizeIncrements:(NSSize)s; - (void)setStyleMask:(NSWindowStyleMask)m; - (NSWindowStyleMask)styleMask;
- (void)setHasShadow:(BOOL)f; - (void)setRestorable:(BOOL)f; - (void)setTabbingMode:(NSInteger)m; - (void)setMiniwindowTitle:(NSString *)t; - (NSString *)miniwindowTitle;
- (void)setIgnoresMouseEvents:(BOOL)f; - (CGFloat)alphaValue; - (void)setAlphaValue:(CGFloat)a; - (NSWindowOcclusionState)occlusionState; - (BOOL)isOpaque;
- (NSRect)convertRectToScreen:(NSRect)r; - (NSPoint)mouseLocationOutsideOfEventStream; - (void)toggleFullScreen:(id)s;
+ (NSInteger)windowNumberAtPoint:(NSPoint)p belowWindowWithWindowNumber:(NSInteger)n;
@end

enum {
  NSModalResponseOK = 1,
  NSModalResponseCancel = 0,
};
typedef NSInteger NSModalResponse;

@class NSURL;

@interface NSSavePanel : NSWindow {
@public
  NSString *_prompt;
  NSString *_message;
  NSURL *_directoryURL;
  NSString *_nameFieldStringValue;
  NSArray *_allowedFileTypes;
  NSArray *_allowedContentTypes;
  BOOL _allowsOtherFileTypes;
  BOOL _canCreateDirectories;
  NSURL *_url;
}
+ (NSSavePanel *)savePanel;
- (void)setTitle:(NSString *)title;
- (NSString *)title;
- (void)setPrompt:(NSString *)prompt;
- (NSString *)prompt;
- (void)setMessage:(NSString *)message;
- (NSString *)message;
- (void)setDirectoryURL:(NSURL *)url;
- (NSURL *)directoryURL;
- (void)setNameFieldStringValue:(NSString *)value;
- (NSString *)nameFieldStringValue;
- (void)setAllowedFileTypes:(NSArray *)types;
- (NSArray *)allowedFileTypes;
- (void)setAllowedContentTypes:(NSArray *)types;
- (NSArray *)allowedContentTypes;
- (void)setAllowsOtherFileTypes:(BOOL)flag;
- (BOOL)allowsOtherFileTypes;
- (void)setCanCreateDirectories:(BOOL)flag;
- (BOOL)canCreateDirectories;
- (NSURL *)URL;
- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSModalResponse returnCode))handler;
- (void)beginWithCompletionHandler:(void (^)(NSModalResponse returnCode))handler;
- (NSModalResponse)runModal;
@end

@interface NSOpenPanel : NSSavePanel {
@public
  BOOL _canChooseFiles;
  BOOL _canChooseDirectories;
  BOOL _allowsMultipleSelection;
  NSArray *_urls;
}
+ (NSOpenPanel *)openPanel;
- (void)setCanChooseFiles:(BOOL)flag;
- (BOOL)canChooseFiles;
- (void)setCanChooseDirectories:(BOOL)flag;
- (BOOL)canChooseDirectories;
- (void)setAllowsMultipleSelection:(BOOL)flag;
- (BOOL)allowsMultipleSelection;
- (NSArray *)URLs;
@end

@interface NSApplication : NSResponder {
@public
  id _delegate; NSMutableArray *_queue, *_windows; BOOL _running, _launched, _active, _stop; NSApplicationActivationPolicy _policy; NSMenu *_menu;
  NSEvent *_current; NSMenu *_services, *_windowsMenu;
}
+ (NSApplication *)sharedApplication;
- (BOOL)setActivationPolicy:(NSApplicationActivationPolicy)p; - (void)activateIgnoringOtherApps:(BOOL)f; - (BOOL)isActive;
- (void)run; - (void)stop:(id)s; - (void)terminate:(id)s; - (void)finishLaunching; - (BOOL)isRunning;
- (NSEvent *)nextEventMatchingMask:(NSUInteger)m untilDate:(NSDate *)d inMode:(NSString *)mode dequeue:(BOOL)dq;
- (void)sendEvent:(NSEvent *)e; - (void)postEvent:(NSEvent *)e atStart:(BOOL)s;
- (void)setDelegate:(id)d; - (id)delegate; - (NSArray *)windows; - (NSWindow *)keyWindow; - (NSWindow *)mainWindow;
- (NSEvent *)currentEvent; - (void)setServicesMenu:(NSMenu *)m; - (void)setWindowsMenu:(NSMenu *)m; - (void)setAppleMenu:(NSMenu *)m;
- (NSInteger)requestUserAttention:(NSRequestUserAttentionType)t; - (void)hide:(id)s; - (void)hideOtherApplications:(id)s; - (void)unhideAllApplications:(id)s;
- (void)orderFrontStandardAboutPanel:(id)s; - (void)arrangeInFront:(id)s;
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
