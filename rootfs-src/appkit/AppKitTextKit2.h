/* AppKit-lite TextKit 2 model (AppKitTextKit2.m): text locations/ranges, content storage, layout manager, fragments, selection. */
#import "AppKitLite.h"
#import "AppKitGraphics.h"
#import "AppKitText.h"

@protocol NSTextLocation <NSObject>
- (id)location;
- (NSInteger)compare:(id)other;
@end

@interface NSTextRange : NSObject { @public id _loc, _end; }
- (id)initWithLocation:(id)l endLocation:(id)e; - (id)initWithLocation:(id)l;
- (BOOL)isEmpty; - (id)location; - (id)endLocation; - (BOOL)isEqualToTextRange:(NSTextRange *)r;
- (BOOL)containsLocation:(id)l; - (BOOL)containsRange:(NSTextRange *)r; - (BOOL)intersectsWithTextRange:(NSTextRange *)r;
- (NSTextRange *)textRangeByIntersectingWithTextRange:(NSTextRange *)r; - (NSTextRange *)textRangeByFormingUnionWithTextRange:(NSTextRange *)r;
@end

@class NSTextContentManager, NSTextLayoutManager, NSTextParagraph;

@interface NSTextElement : NSObject { @public NSTextContentManager *_cm; NSTextRange *_range; }
- (id)initWithTextContentManager:(NSTextContentManager *)m; - (NSTextContentManager *)textContentManager; - (void)setTextContentManager:(NSTextContentManager *)m;
- (NSTextRange *)elementRange; - (void)setElementRange:(NSTextRange *)r; - (NSArray *)childElements; - (NSTextElement *)parentElement; - (BOOL)isRepresentedElement;
@end

@interface NSTextParagraph : NSTextElement { @public NSAttributedString *_as; }
- (id)initWithAttributedString:(NSAttributedString *)a; - (NSAttributedString *)attributedString;
- (NSTextRange *)paragraphContentRange; - (NSTextRange *)paragraphSeparatorRange;
@end

@interface NSTextContentManager : NSObject { @public id _delegate; NSMutableArray *_lms; NSTextLayoutManager *_primary; BOOL _autoLM, _autoStore, _editing; }
- (id)delegate; - (void)setDelegate:(id)d; - (NSArray *)textLayoutManagers; - (void)addTextLayoutManager:(NSTextLayoutManager *)m; - (void)removeTextLayoutManager:(NSTextLayoutManager *)m;
- (NSTextLayoutManager *)primaryTextLayoutManager; - (void)setPrimaryTextLayoutManager:(NSTextLayoutManager *)m;
- (void)synchronizeTextLayoutManagers:(void (^)(NSError *))h; - (void)synchronizeToBackingStore:(void (^)(NSError *))h;
- (NSArray *)textElementsForRange:(NSTextRange *)r; - (BOOL)hasEditingTransaction; - (void)performEditingTransactionUsingBlock:(void (^)(void))b;
- (void)recordEditActionInRange:(NSTextRange *)r newTextRange:(NSTextRange *)n;
- (BOOL)automaticallySynchronizesTextLayoutManagers; - (void)setAutomaticallySynchronizesTextLayoutManagers:(BOOL)f;
- (BOOL)automaticallySynchronizesToBackingStore; - (void)setAutomaticallySynchronizesToBackingStore:(BOOL)f;
- (NSTextRange *)documentRange;
- (id)locationFromLocation:(id)l withOffset:(NSInteger)o; - (NSInteger)offsetFromLocation:(id)a toLocation:(id)b;
- (id)enumerateTextElementsFromLocation:(id)l options:(NSUInteger)o usingBlock:(BOOL (^)(NSTextElement *))b;
- (void)replaceContentsInRange:(NSTextRange *)r withTextElements:(NSArray *)e;
- (void)_xefContentChanged;
@end

@interface NSTextContentStorage : NSTextContentManager { @public NSAttributedString *_attr; NSTextStorage *_storage; BOOL _listMarkers; }
- (NSAttributedString *)attributedString; - (void)setAttributedString:(NSAttributedString *)a;
- (NSAttributedString *)attributedStringForTextElement:(NSTextElement *)e; - (NSTextElement *)textElementForAttributedString:(NSAttributedString *)a;
- (NSTextRange *)adjustedRangeFromRange:(NSTextRange *)r forEditingTextSelection:(BOOL)f;
- (NSTextStorage *)textStorage; - (void)setTextStorage:(NSTextStorage *)s;
- (BOOL)includesTextListMarkers; - (void)setIncludesTextListMarkers:(BOOL)f;
- (void)processEditingForTextStorage:(NSTextStorage *)s edited:(NSUInteger)m range:(NSRange)r changeInLength:(NSInteger)d invalidatedRange:(NSRange)i;
- (void)performEditingTransactionForTextStorage:(NSTextStorage *)s usingBlock:(void (^)(void))b;
@end

@interface NSTextLineFragment : NSObject { @public NSAttributedString *_as; NSRange _range; NSRect _bounds; NSPoint _origin; BOOL _laid; }
- (id)initWithAttributedString:(NSAttributedString *)a range:(NSRange)r; - (id)initWithString:(NSString *)s attributes:(NSDictionary *)a range:(NSRange)r;
- (NSAttributedString *)attributedString; - (NSRange)characterRange; - (NSRect)typographicBounds; - (NSPoint)glyphOrigin;
- (void)drawAtPoint:(NSPoint)p inContext:(CGContextRef)c; - (NSPoint)locationForCharacterAtIndex:(NSInteger)i;
- (NSInteger)characterIndexForPoint:(NSPoint)p; - (CGFloat)fractionOfDistanceThroughGlyphForPoint:(NSPoint)p;
@end

@interface NSTextLayoutFragment : NSObject { @public NSTextElement *_el; NSTextRange *_range; NSTextLayoutManager *_lm; NSArray *_lines; NSRect _frame; NSInteger _state; id _queue; }
- (id)initWithTextElement:(NSTextElement *)e range:(NSTextRange *)r; - (NSTextLayoutManager *)textLayoutManager; - (NSTextElement *)textElement; - (NSTextRange *)rangeInElement;
- (NSArray *)textLineFragments; - (NSTextLineFragment *)textLineFragmentForVerticalOffset:(CGFloat)o requiresExactMatch:(BOOL)e;
- (NSTextLineFragment *)textLineFragmentForTextLocation:(id)l isUpstreamAffinity:(BOOL)u;
- (id)layoutQueue; - (void)setLayoutQueue:(id)q; - (NSInteger)state; - (void)invalidateLayout; - (NSRect)layoutFragmentFrame; - (NSRect)renderingSurfaceBounds;
- (CGFloat)leadingPadding; - (CGFloat)trailingPadding; - (CGFloat)topMargin; - (CGFloat)bottomMargin;
- (void)drawAtPoint:(NSPoint)p inContext:(CGContextRef)c; - (NSArray *)textAttachmentViewProviders; - (NSRect)frameForTextAttachmentAtLocation:(id)l;
@end

@interface NSTextSelection : NSObject { @public NSArray *_ranges; NSInteger _aff, _gran; BOOL _logical; CGFloat _anchor; id _secondary; NSDictionary *_typing; }
- (id)initWithRanges:(NSArray *)r affinity:(NSInteger)a granularity:(NSInteger)g; - (id)initWithRange:(NSTextRange *)r affinity:(NSInteger)a granularity:(NSInteger)g;
- (id)initWithLocation:(id)l affinity:(NSInteger)a; - (NSArray *)textRanges; - (NSInteger)granularity; - (NSInteger)affinity; - (BOOL)isTransient;
- (CGFloat)anchorPositionOffset; - (void)setAnchorPositionOffset:(CGFloat)o; - (BOOL)isLogical; - (void)setLogical:(BOOL)f;
- (id)secondarySelectionLocation; - (void)setSecondarySelectionLocation:(id)l; - (NSDictionary *)typingAttributes; - (void)setTypingAttributes:(NSDictionary *)d;
- (NSTextSelection *)textSelectionWithTextRanges:(NSArray *)r;
@end

@interface NSTextSelectionNavigation : NSObject { @public id _ds; BOOL _noncontig, _rotates; }
- (id)initWithDataSource:(id)d; - (id)textSelectionDataSource; - (BOOL)allowsNonContiguousRanges; - (void)setAllowsNonContiguousRanges:(BOOL)f;
- (BOOL)rotatesCoordinateSystemForLayoutOrientation; - (void)setRotatesCoordinateSystemForLayoutOrientation:(BOOL)f; - (void)flushLayoutCache;
- (NSTextSelection *)destinationSelectionForTextSelection:(NSTextSelection *)s direction:(NSInteger)d destination:(NSInteger)dst extending:(BOOL)e confined:(BOOL)c;
- (NSArray *)textSelectionsInteractingAtPoint:(NSPoint)p inContainerAtLocation:(id)l anchors:(NSArray *)a modifiers:(NSUInteger)m selecting:(BOOL)s bounds:(NSRect)b;
- (NSTextSelection *)textSelectionForSelectionGranularity:(NSInteger)g enclosingTextSelection:(NSTextSelection *)s;
- (NSTextSelection *)textSelectionForSelectionGranularity:(NSInteger)g enclosingPoint:(NSPoint)p inContainerAtLocation:(id)l;
- (id)resolvedInsertionLocationForTextSelection:(NSTextSelection *)s writingDirection:(NSInteger)d;
- (NSArray *)deletionRangesForTextSelection:(NSTextSelection *)s direction:(NSInteger)d destination:(NSInteger)dst allowsDecomposition:(BOOL)a;
@end

@interface NSTextViewportLayoutController : NSObject { @public NSTextLayoutManager *_lm; id _delegate; NSRect _vb; NSTextRange *_vr; }
- (id)initWithTextLayoutManager:(NSTextLayoutManager *)m; - (id)delegate; - (void)setDelegate:(id)d; - (NSTextLayoutManager *)textLayoutManager;
- (NSRect)viewportBounds; - (NSTextRange *)viewportRange; - (void)layoutViewport; - (void)relocateViewportToTextLocation:(id)l; - (CGFloat)adjustViewportByVerticalOffset:(CGFloat)o;
@end

@interface NSTextLayoutManager : NSObject { @public id _delegate; NSTextContentManager *_cm; NSTextContainer *_tc; BOOL _fontLeading, _hyph, _limits, _resolves; NSArray *_sels; NSTextSelectionNavigation *_nav; NSTextViewportLayoutController *_vlc; NSMutableArray *_frags; NSString *_sig; NSMutableArray *_ra; id _queue, _validator; }
- (id)delegate; - (void)setDelegate:(id)d; - (BOOL)usesFontLeading; - (void)setUsesFontLeading:(BOOL)f; - (BOOL)limitsLayoutForSuspiciousContents; - (void)setLimitsLayoutForSuspiciousContents:(BOOL)f;
- (BOOL)usesHyphenation; - (void)setUsesHyphenation:(BOOL)f; - (BOOL)resolvesNaturalAlignmentWithBaseWritingDirection; - (void)setResolvesNaturalAlignmentWithBaseWritingDirection:(BOOL)f;
- (NSTextContentManager *)textContentManager; - (void)replaceTextContentManager:(NSTextContentManager *)m; - (NSTextContainer *)textContainer; - (void)setTextContainer:(NSTextContainer *)c;
- (NSRect)usageBoundsForTextContainer; - (NSTextViewportLayoutController *)textViewportLayoutController; - (id)layoutQueue; - (void)setLayoutQueue:(id)q;
- (NSTextRange *)ensureLayoutForRange:(NSTextRange *)r; - (void)ensureLayoutForBounds:(NSRect)b; - (void)invalidateLayoutForRange:(NSTextRange *)r;
- (NSTextLayoutFragment *)textLayoutFragmentForPosition:(NSPoint)p; - (NSTextLayoutFragment *)textLayoutFragmentForLocation:(id)l;
- (id)enumerateTextLayoutFragmentsFromLocation:(id)l options:(NSUInteger)o usingBlock:(BOOL (^)(NSTextLayoutFragment *))b;
- (NSArray *)textSelections; - (void)setTextSelections:(NSArray *)s; - (NSTextSelectionNavigation *)textSelectionNavigation; - (void)setTextSelectionNavigation:(NSTextSelectionNavigation *)n;
- (void)enumerateRenderingAttributesFromLocation:(id)l reverse:(BOOL)r usingBlock:(BOOL (^)(NSTextLayoutManager *, NSDictionary *, NSTextRange *))b;
- (void)setRenderingAttributes:(NSDictionary *)a forTextRange:(NSTextRange *)r; - (void)addRenderingAttribute:(NSString *)n value:(id)v forTextRange:(NSTextRange *)r;
- (void)removeRenderingAttribute:(NSString *)n forTextRange:(NSTextRange *)r; - (void)invalidateRenderingAttributesForTextRange:(NSTextRange *)r;
- (id)renderingAttributesValidator; - (void)setRenderingAttributesValidator:(id)v; + (NSDictionary *)linkRenderingAttributes; - (NSDictionary *)renderingAttributesForLink:(id)l atLocation:(id)loc;
- (id)enumerateTextSegmentsInRange:(NSTextRange *)r type:(NSInteger)t options:(NSUInteger)o usingBlock:(BOOL (^)(NSTextRange *, NSRect, CGFloat, NSTextContainer *))b;
- (void)replaceContentsInRange:(NSTextRange *)r withTextElements:(NSArray *)e; - (void)replaceContentsInRange:(NSTextRange *)r withAttributedString:(NSAttributedString *)a;
- (NSTextRange *)documentRange;
- (id)enumerateSubstringsFromLocation:(id)l options:(NSUInteger)o usingBlock:(void (^)(NSString *, NSTextRange *, NSTextRange *, BOOL *))b;
- (NSTextRange *)textRangeForSelectionGranularity:(NSInteger)g enclosingLocation:(id)l;
- (id)locationFromLocation:(id)l withOffset:(NSInteger)o; - (NSInteger)offsetFromLocation:(id)a toLocation:(id)b;
- (NSInteger)baseWritingDirectionAtLocation:(id)l;
- (void)enumerateCaretOffsetsInLineFragmentAtLocation:(id)l usingBlock:(void (^)(CGFloat, id, BOOL, BOOL *))b;
- (NSTextRange *)lineFragmentRangeForPoint:(NSPoint)p inContainerAtLocation:(id)l;
@end

@interface NSTextContainer (XEFTextKit2) - (NSTextLayoutManager *)textLayoutManager; - (void)setTextLayoutManager:(NSTextLayoutManager *)m; @end
