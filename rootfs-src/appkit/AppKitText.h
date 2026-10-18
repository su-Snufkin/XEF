/* AppKit-lite text system (AppKitText.m). */
#import "AppKitLite.h"
#import "AppKitGraphics.h"

@class NSLayoutManager, NSTextContainer, NSTextView;
typedef unsigned int NSGlyph;

@interface NSTextStorage : NSMutableAttributedString {
@public
  NSMutableAttributedString *_s; NSMutableArray *_lms; id _delegate;
  NSUInteger _editedMask; NSRange _editedRange; NSInteger _delta; NSInteger _nest;
}
- (NSArray *)layoutManagers; - (void)addLayoutManager:(NSLayoutManager *)lm; - (void)removeLayoutManager:(NSLayoutManager *)lm;
- (void)edited:(NSUInteger)mask range:(NSRange)r changeInLength:(NSInteger)d; - (void)processEditing;
- (id)delegate; - (void)setDelegate:(id)d;
@end

@interface NSTextContainer : NSObject <NSCoding> {
@public
  NSSize _size; CGFloat _padding; BOOL _widthTracks, _heightTracks; NSTextView *_tv; NSLayoutManager *_lm; NSUInteger _maxLines; NSInteger _lineBreak;
  NSArray *_exclusion;
}
- (id)initWithContainerSize:(NSSize)s; - (id)initWithSize:(NSSize)s;
- (NSSize)containerSize; - (void)setContainerSize:(NSSize)s; - (NSSize)size; - (void)setSize:(NSSize)s;
- (CGFloat)lineFragmentPadding; - (void)setLineFragmentPadding:(CGFloat)p;
- (BOOL)widthTracksTextView; - (void)setWidthTracksTextView:(BOOL)f; - (BOOL)heightTracksTextView; - (void)setHeightTracksTextView:(BOOL)f;
- (NSTextView *)textView; - (void)setTextView:(NSTextView *)tv; - (NSLayoutManager *)layoutManager; - (void)setLayoutManager:(NSLayoutManager *)lm;
@end

@interface NSLayoutManager : NSObject <NSCoding> {
@public
  NSTextStorage *_storage; NSMutableArray *_containers; id _delegate; XEFTextLayout *_layout; CGFloat _layoutWidth;
  BOOL _showInvisibles, _bgLayout, _nonContiguous, _usesFontLeading; NSMutableDictionary *_tempAttrs;
}
- (NSTextStorage *)textStorage; - (void)setTextStorage:(NSTextStorage *)s; - (NSArray *)textContainers;
- (void)addTextContainer:(NSTextContainer *)c; - (NSTextView *)firstTextView;
- (XEFTextLayout *)_xefLayout; - (void)_xefInvalidate;
- (NSRect)usedRectForTextContainer:(NSTextContainer *)c;
- (void)drawBackgroundForGlyphRange:(NSRange)r atPoint:(NSPoint)p; - (void)drawGlyphsForGlyphRange:(NSRange)r atPoint:(NSPoint)p;
- (NSUInteger)characterIndexForPoint:(NSPoint)p inTextContainer:(NSTextContainer *)c fractionOfDistanceBetweenInsertionPoints:(CGFloat *)f;
- (CGFloat)defaultLineHeightForFont:(NSFont *)f;
@end

@interface NSText : NSView
@end

@interface NSTextView : NSText {
@public
  NSTextStorage *_storage; NSLayoutManager *_lm; NSTextContainer *_tc; NSRange _sel; NSUInteger _anchor; NSDictionary *_typing; id _tvDelegate;
  NSColor *_bgColor, *_insertionColor; NSDictionary *_selAttrs, *_linkAttrs; NSParagraphStyle *_defaultPara;
  NSSize _inset, _minSize, _maxSize; CGFloat _goalX;
  BOOL _editable, _selectable, _rich, _imports, _drawsBg, _vResizable, _hResizable, _fieldEditor, _allowsUndo, _usesFontPanel, _usesRuler, _ownsStorage, _inLayout;
}
- (id)initWithFrame:(NSRect)f textContainer:(NSTextContainer *)c;
- (NSTextStorage *)textStorage; - (NSLayoutManager *)layoutManager; - (NSTextContainer *)textContainer; - (void)setTextContainer:(NSTextContainer *)c;
- (NSString *)string; - (void)setString:(NSString *)s; - (NSRange)selectedRange; - (void)setSelectedRange:(NSRange)r;
- (void)_xefTextChanged; - (void)_xefLayoutChanged; - (NSPoint)textContainerOrigin; - (void)sizeToFit;
- (BOOL)isEditable; - (void)setEditable:(BOOL)f; - (id)delegate; - (void)setDelegate:(id)d;
@end

@interface NSFontManager : NSObject {
@public
  id _target; SEL _action; NSFont *_selected; NSInteger _pendingTrait, _pendingAction; id _delegate;
}
+ (NSFontManager *)sharedFontManager; - (NSFont *)convertFont:(NSFont *)f;
- (NSFont *)convertFont:(NSFont *)f toHaveTrait:(NSUInteger)t; - (NSFont *)convertFont:(NSFont *)f toSize:(CGFloat)s;
- (NSUInteger)traitsOfFont:(NSFont *)f; - (void)setSelectedFont:(NSFont *)f isMultiple:(BOOL)m;
@end

@interface NSFontPanel : NSObject
@end
@interface NSColorPanel : NSObject
@end
