/* AppKit-lite controls (AppKitControls.m) and menus (AppKitMenu.m). */
#import "AppKitLite.h"
#import "AppKitGraphics.h"

@class NSText, NSTextView;

NSEvent *XEFNextTrackingEvent(void);       /* next mouse-up/drag/move event (modal tracking loops) */
void XEFRedrawWindowNow(NSWindow *w);       /* presents the window right away (inside tracking loops) */

@interface NSCell : NSObject <NSCopying, NSCoding> {
@public
  id _contents; NSFont *_font; NSImage *_image; id _formatter, _rep; NSString *_placeholder; NSAttributedString *_attrTitle;
  NSView *_controlView; NSInteger _type, _state, _tag, _align, _lineBreak, _sendMask; NSUInteger _controlSize;
  BOOL _enabled, _editable, _selectable, _bezeled, _bordered, _highlighted, _scrollable, _wraps, _continuous, _allowsMixed;
}
- (id)initTextCell:(NSString *)s; - (id)initImageCell:(NSImage *)i;
- (id)objectValue; - (void)setObjectValue:(id)v; - (NSString *)stringValue; - (void)setStringValue:(NSString *)s;
- (NSAttributedString *)attributedStringValue; - (void)setAttributedStringValue:(NSAttributedString *)s;
- (int)intValue; - (void)setIntValue:(int)v; - (NSInteger)integerValue; - (void)setIntegerValue:(NSInteger)v;
- (float)floatValue; - (void)setFloatValue:(float)v; - (double)doubleValue; - (void)setDoubleValue:(double)v;
- (NSString *)title; - (void)setTitle:(NSString *)t; - (NSFont *)font; - (void)setFont:(NSFont *)f;
- (NSInteger)alignment; - (void)setAlignment:(NSInteger)a; - (NSInteger)lineBreakMode; - (void)setLineBreakMode:(NSInteger)m;
- (NSInteger)state; - (void)setState:(NSInteger)s; - (void)setNextState; - (BOOL)allowsMixedState; - (void)setAllowsMixedState:(BOOL)f;
- (BOOL)isEnabled; - (void)setEnabled:(BOOL)f; - (BOOL)isEditable; - (void)setEditable:(BOOL)f; - (BOOL)isSelectable; - (void)setSelectable:(BOOL)f;
- (BOOL)isBezeled; - (void)setBezeled:(BOOL)f; - (BOOL)isBordered; - (void)setBordered:(BOOL)f; - (BOOL)wraps; - (void)setWraps:(BOOL)f;
- (BOOL)isScrollable; - (void)setScrollable:(BOOL)f; - (BOOL)isHighlighted; - (void)setHighlighted:(BOOL)f;
- (BOOL)isContinuous; - (void)setContinuous:(BOOL)f; - (NSInteger)sendActionOn:(NSInteger)m;
- (BOOL)usesSingleLineMode; - (void)setUsesSingleLineMode:(BOOL)f;
- (NSView *)controlView; - (void)setControlView:(NSView *)v; - (id)target; - (void)setTarget:(id)t; - (SEL)action; - (void)setAction:(SEL)a;
- (NSInteger)tag; - (void)setTag:(NSInteger)t; - (NSImage *)image; - (void)setImage:(NSImage *)i;
- (id)formatter; - (void)setFormatter:(id)f; - (id)representedObject; - (void)setRepresentedObject:(id)o;
- (NSUInteger)controlSize; - (void)setControlSize:(NSUInteger)s; - (NSString *)placeholderString; - (void)setPlaceholderString:(NSString *)s;
- (NSString *)keyEquivalent; - (void)setKeyEquivalent:(NSString *)k; - (BOOL)acceptsFirstResponder;
- (NSSize)cellSize; - (NSRect)drawingRectForBounds:(NSRect)r; - (NSRect)titleRectForBounds:(NSRect)r;
- (void)drawWithFrame:(NSRect)r inView:(NSView *)v; - (void)drawInteriorWithFrame:(NSRect)r inView:(NSView *)v;
- (BOOL)trackMouse:(NSEvent *)e inRect:(NSRect)r ofView:(NSView *)v untilMouseUp:(BOOL)u;
- (void)_changed; - (NSColor *)_textColor;
@end

@interface NSActionCell : NSCell { @public id _target; SEL _action; }
@end

@interface NSControl : NSView { @public NSCell *_cell; }
+ (Class)cellClass;
- (id)cell; - (void)setCell:(NSCell *)c;
- (id)target; - (void)setTarget:(id)t; - (SEL)action; - (void)setAction:(SEL)a;
- (id)objectValue; - (void)setObjectValue:(id)v; - (NSString *)stringValue; - (void)setStringValue:(NSString *)s;
- (int)intValue; - (void)setIntValue:(int)v; - (NSInteger)integerValue; - (double)doubleValue; - (void)setDoubleValue:(double)v;
- (NSFont *)font; - (void)setFont:(NSFont *)f; - (BOOL)isEnabled; - (void)setEnabled:(BOOL)f;
- (BOOL)sendAction:(SEL)a to:(id)t; - (void)sizeToFit; - (void)performClick:(id)s;
- (void)_xefAbortEditing;
@end

@interface NSButtonImageSource : NSObject <NSCoding> { NSString *_name; }
- (NSString *)imageName;
@end

@interface NSButtonCell : NSActionCell {
@public
  NSInteger _bezelStyle, _buttonType, _imagePosition; NSString *_key, *_altTitle; NSImage *_altImage; NSUInteger _keyMask; BOOL _transparent;
}
- (NSString *)alternateTitle; - (void)setAlternateTitle:(NSString *)t; - (NSImage *)alternateImage; - (void)setAlternateImage:(NSImage *)i;
- (NSInteger)bezelStyle; - (void)setBezelStyle:(NSInteger)s; - (void)setButtonType:(NSInteger)t;
- (NSUInteger)keyEquivalentModifierMask; - (void)setKeyEquivalentModifierMask:(NSUInteger)m;
- (BOOL)isTransparent; - (void)setTransparent:(BOOL)f; - (NSInteger)imagePosition; - (void)setImagePosition:(NSInteger)p;
- (NSAttributedString *)attributedTitle; - (void)setAttributedTitle:(NSAttributedString *)t;
@end

@interface NSButton : NSControl
- (NSString *)title; - (void)setTitle:(NSString *)t; - (NSInteger)state; - (void)setState:(NSInteger)s;
- (void)setButtonType:(NSInteger)t; - (NSString *)keyEquivalent; - (void)setKeyEquivalent:(NSString *)k;
- (NSImage *)image; - (void)setImage:(NSImage *)i; - (void)setBezelStyle:(NSInteger)s; - (void)setTag:(NSInteger)t;
@end

@interface NSTextFieldCell : NSActionCell { @public NSColor *_bg, *_tc; BOOL _drawsBg; NSInteger _bezelStyle; }
- (NSColor *)backgroundColor; - (void)setBackgroundColor:(NSColor *)c; - (NSColor *)textColor; - (void)setTextColor:(NSColor *)c;
- (BOOL)drawsBackground; - (void)setDrawsBackground:(BOOL)f; - (NSInteger)bezelStyle; - (void)setBezelStyle:(NSInteger)s;
@end

@interface NSTextField : NSControl {
@public
  id _delegate; BOOL _editing; NSMutableString *_editString; NSRange _sel; CGFloat _scrollX;
}
- (id)delegate; - (void)setDelegate:(id)d; - (void)setEditable:(BOOL)f; - (void)setSelectable:(BOOL)f; - (void)setBezeled:(BOOL)f;
- (void)setDrawsBackground:(BOOL)f; - (void)setTextColor:(NSColor *)c; - (void)selectText:(id)s;
- (void)_xefEndEditing:(NSInteger)movement;
@end
@interface NSSecureTextField : NSTextField
@end
@interface NSSecureTextFieldCell : NSTextFieldCell
@end
@interface NSSearchField : NSTextField
@end
@interface NSSearchFieldCell : NSTextFieldCell
@end
@interface NSTokenField : NSTextField
@end
@interface NSTokenFieldCell : NSTextFieldCell
@end

@interface NSPopUpButtonCell : NSButtonCell { @public NSMenu *_menu; NSInteger _selected, _arrowPosition, _preferredEdge; BOOL _pullsDown; }
- (id)initTextCell:(NSString *)s pullsDown:(BOOL)p;
- (NSMenu *)menu; - (void)setMenu:(NSMenu *)m; - (BOOL)pullsDown; - (void)setPullsDown:(BOOL)f;
- (NSInteger)numberOfItems; - (NSMenuItem *)itemAtIndex:(NSInteger)i; - (NSInteger)indexOfItem:(NSMenuItem *)i;
- (NSMenuItem *)selectedItem; - (NSInteger)indexOfSelectedItem; - (void)selectItemAtIndex:(NSInteger)i;
@end
@interface NSPopUpButton : NSButton
@end

@interface NSScroller : NSControl { @public double _value; CGFloat _knobProportion; NSInteger _hitPart; }
- (double)doubleValue; - (void)setDoubleValue:(double)v; - (CGFloat)knobProportion; - (void)setKnobProportion:(CGFloat)p;
@end

@interface NSClipView : NSView { @public NSView *_doc; NSColor *_bg; BOOL _drawsBg; }
- (id)documentView; - (void)setDocumentView:(NSView *)v; - (NSRect)documentRect; - (NSRect)documentVisibleRect;
- (void)scrollToPoint:(NSPoint)p; - (NSPoint)constrainScrollPoint:(NSPoint)p;
- (NSColor *)backgroundColor; - (void)setBackgroundColor:(NSColor *)c; - (BOOL)drawsBackground; - (void)setDrawsBackground:(BOOL)f;
@end

@interface NSScrollView : NSView {
@public
  NSClipView *_clip; NSScroller *_vs, *_hs; BOOL _hasV, _hasH, _autohides, _drawsBg; NSInteger _border; CGFloat _lineScroll;
}
- (NSClipView *)contentView; - (id)documentView; - (void)setDocumentView:(NSView *)v; - (NSSize)contentSize;
- (void)setHasVerticalScroller:(BOOL)f; - (void)setHasHorizontalScroller:(BOOL)f; - (void)tile; - (void)reflectScrolledClipView:(NSClipView *)c;
@end

@interface NSBox : NSView { @public NSInteger _boxType, _titlePos, _borderType; BOOL _transparent; NSString *_title; NSColor *_fill; }
@end
@interface NSCustomView : NSView
@end
@interface NSAppearance : NSObject <NSCoding> { @public NSString *_name; }
+ (NSAppearance *)appearanceNamed:(NSString *)n;
@end

@interface NSLayoutConstraint : NSObject
@end

/* menus (AppKitMenu.m) */
@interface NSMenu (XEFMenu)
- (void)insertItem:(NSMenuItem *)i atIndex:(NSInteger)idx;
- (NSMenuItem *)insertItemWithTitle:(NSString *)t action:(SEL)a keyEquivalent:(NSString *)k atIndex:(NSInteger)i;
- (void)removeItemAtIndex:(NSInteger)i; - (void)removeItem:(NSMenuItem *)i; - (void)removeAllItems;
- (NSInteger)numberOfItems; - (NSMenuItem *)itemAtIndex:(NSInteger)i;
- (NSMenuItem *)_xefPopUpPositioningItem:(NSMenuItem *)item atLocation:(NSPoint)p inView:(NSView *)v minWidth:(CGFloat)w;
- (BOOL)performKeyEquivalent:(NSEvent *)e;
@end
@interface NSMenuItem (XEFMenu)
- (NSInteger)state; - (void)setState:(NSInteger)s; - (NSInteger)tag; - (void)setTag:(NSInteger)t;
- (id)representedObject; - (void)setRepresentedObject:(id)o; - (BOOL)isEnabled; - (void)setEnabled:(BOOL)f;
- (BOOL)isSeparatorItem; - (NSString *)keyEquivalent; - (NSUInteger)keyEquivalentModifierMask; - (NSMenu *)menu; - (BOOL)isHidden;
@end

@interface NSApplication (XEFActions)
- (BOOL)sendAction:(SEL)a to:(id)t from:(id)s; - (id)targetForAction:(SEL)a to:(id)t from:(id)s; - (id)targetForAction:(SEL)a;
@end
@interface NSApplication (XEFMenus)
- (BOOL)_xefHandleKeyEquivalent:(NSEvent *)e;
@end
@interface NSWindow (XEFKeyViews)
- (void)selectNextKeyView:(id)s; - (void)selectPreviousKeyView:(id)s; - (NSUndoManager *)undoManager;
@end
@interface NSView (XEFKeyEquivalents)
- (BOOL)performKeyEquivalent:(NSEvent *)e;
@end
