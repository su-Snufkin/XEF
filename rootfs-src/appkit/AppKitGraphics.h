/* AppKit-lite 2D drawing declarations (AppKitGraphics.m) shared by the controls and the text system. */
#import "AppKitLite.h"
#import <CoreGraphics/CoreGraphics.h>

@class NSFontDescriptor, NSScrollView;

/* CoreGraphics-lite SPI */
int XEFCGContextGetHostHandle(CGContextRef c);
CGContextRef XEFCurrentCGContext(void);
CGBlendMode XEFBlendModeForOperation(NSUInteger op);
void CGContextSetCTM(CGContextRef c, CGAffineTransform t);   /* SPI */

void NSRectFill(NSRect r);
void NSRectFillUsingOperation(NSRect r, NSUInteger op);
void NSFrameRect(NSRect r);
void NSFrameRectWithWidth(NSRect r, CGFloat w);
void NSRectClip(NSRect r);

@interface NSColorSpace : NSObject
+ (NSColorSpace *)sRGBColorSpace;
@end

@interface NSGraphicsContext : NSObject {
@public
  CGContextRef _cg; BOOL _flipped, _aa; NSUInteger _op; NSInteger _interp;
}
+ (NSGraphicsContext *)currentContext; + (void)setCurrentContext:(NSGraphicsContext *)c;
+ (NSGraphicsContext *)graphicsContextWithCGContext:(CGContextRef)c flipped:(BOOL)f;
+ (void)saveGraphicsState; + (void)restoreGraphicsState;
- (CGContextRef)CGContext; - (BOOL)isFlipped; - (void)saveGraphicsState; - (void)restoreGraphicsState;
@end

@interface NSBezierPath : NSObject <NSCopying> {
@public
  CGMutablePathRef _path; CGFloat _lineWidth, _miter, _flatness, _phase; NSInteger _cap, _join, _winding; CGFloat *_dash; NSInteger _ndash;
}
+ (NSBezierPath *)bezierPath; + (NSBezierPath *)bezierPathWithRect:(NSRect)r; + (NSBezierPath *)bezierPathWithOvalInRect:(NSRect)r;
+ (NSBezierPath *)bezierPathWithRoundedRect:(NSRect)r xRadius:(CGFloat)x yRadius:(CGFloat)y;
+ (void)strokeLineFromPoint:(NSPoint)a toPoint:(NSPoint)b;
- (void)moveToPoint:(NSPoint)p; - (void)lineToPoint:(NSPoint)p; - (void)closePath;
- (void)curveToPoint:(NSPoint)e controlPoint1:(NSPoint)c1 controlPoint2:(NSPoint)c2;
- (void)appendBezierPathWithRect:(NSRect)r; - (void)appendBezierPathWithOvalInRect:(NSRect)r;
- (void)appendBezierPathWithRoundedRect:(NSRect)r xRadius:(CGFloat)x yRadius:(CGFloat)y;
- (void)fill; - (void)stroke; - (void)addClip; - (void)setLineWidth:(CGFloat)w;
- (void)transformUsingAffineTransform:(NSAffineTransform *)t;
@end

@interface NSFont : NSObject <NSCopying, NSSecureCoding> {
@public
  NSString *_name, *_family, *_hostFamily; CGFloat _size, _ascent, _descent, _lineHeight, _avgWidth; int _weight, _italic;
}
+ (NSFont *)fontWithName:(NSString *)n size:(CGFloat)s; + (NSFont *)systemFontOfSize:(CGFloat)s; + (NSFont *)boldSystemFontOfSize:(CGFloat)s;
+ (NSFont *)userFontOfSize:(CGFloat)s; + (NSFont *)userFixedPitchFontOfSize:(CGFloat)s; + (NSFont *)labelFontOfSize:(CGFloat)s;
+ (NSFont *)controlContentFontOfSize:(CGFloat)s; + (NSFont *)menuFontOfSize:(CGFloat)s; + (NSFont *)menuBarFontOfSize:(CGFloat)s;
+ (NSFont *)systemFontOfSize:(CGFloat)s weight:(CGFloat)w; + (NSFont *)fontWithName:(NSString *)n size:(CGFloat)s;
+ (CGFloat)systemFontSize; + (CGFloat)smallSystemFontSize;
- (NSString *)fontName; - (NSString *)familyName; - (CGFloat)pointSize; - (CGFloat)ascender; - (CGFloat)descender; - (CGFloat)leading;
- (NSString *)_xefFamily; - (int)_xefWeight; - (int)_xefItalic; - (CGFloat)_xefLineHeight;
@end

@interface NSFontDescriptor : NSObject <NSCopying, NSSecureCoding> { @public NSDictionary *_attrs; }
+ (NSFontDescriptor *)fontDescriptorWithFontAttributes:(NSDictionary *)a;
- (id)objectForKey:(NSString *)k;
@end

@interface NSTextTab : NSObject <NSCopying, NSSecureCoding> { @public CGFloat _loc; NSInteger _align; NSDictionary *_options; }
@end

@interface NSParagraphStyle : NSObject <NSCopying, NSMutableCopying, NSSecureCoding> {
@public
  NSInteger _align, _lineBreak, _direction; CGFloat _lineSpacing, _paraSpacing, _paraSpacingBefore, _firstIndent, _headIndent, _tailIndent;
  CGFloat _minLine, _maxLine, _lineMultiple, _tabInterval; NSArray *_tabs; float _hyphen;
}
+ (NSParagraphStyle *)defaultParagraphStyle;
- (NSInteger)alignment; - (NSInteger)lineBreakMode; - (CGFloat)lineSpacing; - (CGFloat)paragraphSpacing;
- (void)_xefCopyFrom:(NSParagraphStyle *)o;
@end
@interface NSMutableParagraphStyle : NSParagraphStyle
- (void)setAlignment:(NSInteger)a; - (void)setLineBreakMode:(NSInteger)m; - (void)setLineSpacing:(CGFloat)s;
@end

@interface NSShadow : NSObject <NSCopying, NSSecureCoding> { @public NSSize _offset; CGFloat _blur; NSColor *_color; }
@end

extern NSString *const NSFontAttributeName, *const NSForegroundColorAttributeName, *const NSBackgroundColorAttributeName,
    *const NSParagraphStyleAttributeName, *const NSUnderlineStyleAttributeName, *const NSStrikethroughStyleAttributeName,
    *const NSKernAttributeName, *const NSLinkAttributeName, *const NSAttachmentAttributeName, *const NSFontNameAttribute,
    *const NSFontFamilyAttribute, *const NSFontSizeAttribute, *const NSFontTraitsAttribute, *const NSFontSymbolicTrait;

/* host text layout of an attributed string (pango); coordinates are layout coordinates: origin top-left, y down */
typedef struct { NSUInteger start; CGFloat top, height, baseline; } XEFLineInfo;
@interface XEFTextLayout : NSObject {
@public
  int _t; int *_u2b; NSUInteger _len; int _nbytes; CGFloat _width, _baseline, _defaultLineHeight; NSSize _size; NSUInteger _lines; NSInteger _alignOverride;
}
+ (XEFTextLayout *)layoutWithAttributedString:(NSAttributedString *)s width:(CGFloat)w;   /* w <= 0: no wrapping */
+ (XEFTextLayout *)layoutWithString:(NSString *)s attributes:(NSDictionary *)a width:(CGFloat)w;
- (NSSize)size; - (CGFloat)baseline; - (NSUInteger)lineCount; - (CGFloat)defaultLineHeight; - (NSUInteger)length;
- (void)drawAtTopLeft:(NSPoint)p;   /* in the current NSGraphicsContext; p = top-left corner of the text */
- (NSUInteger)characterIndexAtPoint:(NSPoint)p;
- (NSRect)caretRectAtIndex:(NSUInteger)i;
- (NSRect)rectOfCharacterAtIndex:(NSUInteger)i;
- (NSUInteger)getLines:(XEFLineInfo *)out max:(NSUInteger)max;
@end

@interface NSString (XEFStringDrawing)
- (NSSize)sizeWithAttributes:(NSDictionary *)a; - (void)drawAtPoint:(NSPoint)p withAttributes:(NSDictionary *)a;
- (void)drawInRect:(NSRect)r withAttributes:(NSDictionary *)a;
@end
@interface NSAttributedString (XEFStringDrawing)
- (NSSize)size; - (void)drawAtPoint:(NSPoint)p; - (void)drawInRect:(NSRect)r;
- (NSRange)doubleClickAtIndex:(NSUInteger)i; - (NSUInteger)nextWordFromIndex:(NSUInteger)i forward:(BOOL)f;
@end

@interface NSColor (XEFDrawing)
- (void)set; - (void)setFill; - (void)setStroke; - (CGColorRef)CGColor;
+ (NSColor *)colorWithCalibratedWhite:(CGFloat)w alpha:(CGFloat)a;
+ (NSColor *)windowBackgroundColor; + (NSColor *)controlColor; + (NSColor *)controlTextColor; + (NSColor *)textColor;
+ (NSColor *)textBackgroundColor; + (NSColor *)selectedTextBackgroundColor; + (NSColor *)gridColor; + (NSColor *)selectedControlColor;
+ (NSColor *)disabledControlTextColor; + (NSColor *)controlBackgroundColor; + (NSColor *)secondaryLabelColor; + (NSColor *)labelColor;
+ (NSColor *)separatorColor; + (NSColor *)controlAccentColor; + (NSColor *)keyboardFocusIndicatorColor; + (NSColor *)alternateSelectedControlColor;
+ (NSColor *)scrollBarColor; + (NSColor *)knobColor; + (NSColor *)grayColor; + (NSColor *)lightGrayColor; + (NSColor *)darkGrayColor;
+ (NSColor *)placeholderTextColor; + (NSColor *)colorWithCGColor:(CGColorRef)c;
@end

@interface NSBitmapImageRep (XEFGraphics)
- (CGContextRef)_xefCreateContext; - (CGImageRef)CGImage;
@end

@interface NSView (XEFGeometry)
- (NSRect)convertRect:(NSRect)r toView:(NSView *)v; - (NSRect)convertRect:(NSRect)r fromView:(NSView *)v;
- (NSPoint)convertPoint:(NSPoint)p toView:(NSView *)v;
- (BOOL)isHidden; - (void)setHidden:(BOOL)f; - (NSRect)visibleRect; - (BOOL)scrollRectToVisible:(NSRect)r;
- (NSScrollView *)enclosingScrollView; - (void)setNeedsDisplayInRect:(NSRect)r; - (void)_xefDrawTree:(CGContextRef)c;
@end

@interface NSWindow (XEFBacking)
- (void)_xefBacking;
@end

/* Delegate / informal-protocol methods AppKit-lite sends: declared so that calls use the right ABI (undeclared
 * selectors are called as variadic functions on arm64, which passes CGFloat / NSPoint / NSRange arguments wrongly) */
@class NSMenu, NSMenuItem;
@interface NSObject (XEFInformalProtocols)
- (void)applicationWillFinishLaunching:(NSNotification *)n; - (void)applicationDidFinishLaunching:(NSNotification *)n;
- (NSUInteger)applicationShouldTerminate:(id)app; - (BOOL)applicationShouldTerminateAfterLastWindowClosed:(id)app;
- (void)applicationWillTerminate:(NSNotification *)n;
- (void)controlTextDidChange:(NSNotification *)n; - (void)controlTextDidEndEditing:(NSNotification *)n;
- (void)insertText:(id)s replacementRange:(NSRange)r;
- (BOOL)isHiddenOrHasHiddenAncestor; - (NSMenu *)menu;
- (void)menuWillOpen:(NSMenu *)m; - (void)menuDidClose:(NSMenu *)m; - (void)menuNeedsUpdate:(NSMenu *)m;
- (void)scrollToPoint:(NSPoint)p;
- (BOOL)validateMenuItem:(NSMenuItem *)i; - (BOOL)validateUserInterfaceItem:(id)i;
- (id)windowController; - (BOOL)windowShouldClose:(id)w; - (void)windowWillClose:(NSNotification *)n;
- (NSUndoManager *)windowWillReturnUndoManager:(id)w;
- (void)_xefClicked; - (BOOL)_xefIsEditing;
+ (id)sharedDocumentController;
@end
@interface NSColor (XEFBlend)
- (NSColor *)shadowWithLevel:(CGFloat)l; - (NSColor *)highlightWithLevel:(CGFloat)l; - (NSColor *)blendedColorWithFraction:(CGFloat)f ofColor:(NSColor *)c;
@end
@interface NSWindow (XEFScreenConversion)
- (NSPoint)convertPointFromScreen:(NSPoint)p; - (NSPoint)convertPointToScreen:(NSPoint)p; - (NSRect)convertRectFromScreen:(NSRect)r;
@end
