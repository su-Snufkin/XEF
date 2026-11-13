/* Small model classes (AppKitMisc.m). */
#import "AppKitLite.h"
#include <objc/message.h>
#import "AppKitGraphics.h"
#import "AppKitControllers.h"
#import "AppKitModel.h"
#import "AppKitControls2.h"
#import "AppKitText.h"
#import "AppKitDocument.h"

@interface NSUserInterfaceCompressionOptions : NSObject <NSCopying> { @public NSSet *_ids; }
- (id)initWithIdentifier:(NSString *)i; - (id)initWithCompressionOptions:(NSSet *)s;
- (BOOL)containsOptions:(NSUserInterfaceCompressionOptions *)o; - (BOOL)intersectsOptions:(NSUserInterfaceCompressionOptions *)o; - (BOOL)isEmpty;
- (NSUserInterfaceCompressionOptions *)optionsByAddingOptions:(NSUserInterfaceCompressionOptions *)o; - (NSUserInterfaceCompressionOptions *)optionsByRemovingOptions:(NSUserInterfaceCompressionOptions *)o;
+ (NSUserInterfaceCompressionOptions *)hideImagesOption; + (NSUserInterfaceCompressionOptions *)hideTextOption; + (NSUserInterfaceCompressionOptions *)reduceMetricsOption;
+ (NSUserInterfaceCompressionOptions *)breakEqualWidthsOption; + (NSUserInterfaceCompressionOptions *)standardOptions;
@end

@interface NSFontCollection : NSObject <NSCopying, NSMutableCopying> { @public NSArray *_query, *_excl; NSString *_name; BOOL _all; }
+ (NSFontCollection *)fontCollectionWithDescriptors:(NSArray *)d; + (NSFontCollection *)fontCollectionWithAllAvailableDescriptors; + (NSFontCollection *)fontCollectionWithLocale:(NSLocale *)l;
+ (BOOL)showFontCollection:(NSFontCollection *)c withName:(NSString *)n visibility:(NSInteger)v error:(NSError **)e; + (BOOL)hideFontCollectionWithName:(NSString *)n visibility:(NSInteger)v error:(NSError **)e;
+ (BOOL)renameFontCollectionWithName:(NSString *)n visibility:(NSInteger)v toName:(NSString *)t error:(NSError **)e; + (NSArray *)allFontCollectionNames;
+ (NSFontCollection *)fontCollectionWithName:(NSString *)n; + (NSFontCollection *)fontCollectionWithName:(NSString *)n visibility:(NSInteger)v;
- (NSArray *)queryDescriptors; - (NSArray *)exclusionDescriptors; - (NSArray *)matchingDescriptors; - (NSArray *)matchingDescriptorsWithOptions:(NSDictionary *)o;
- (NSArray *)matchingDescriptorsForFamily:(NSString *)f; - (NSArray *)matchingDescriptorsForFamily:(NSString *)f options:(NSDictionary *)o;
@end

@interface NSTitlebarAccessoryViewController : NSViewController { @public NSInteger _la; CGFloat _fsmin; BOOL _hidden, _auto; NSDictionary *_anims; }
- (NSInteger)layoutAttribute; - (void)setLayoutAttribute:(NSInteger)a; - (CGFloat)fullScreenMinHeight; - (void)setFullScreenMinHeight:(CGFloat)h;
- (BOOL)isHidden; - (void)setHidden:(BOOL)f; - (BOOL)automaticallyAdjustsSize; - (void)setAutomaticallyAdjustsSize:(BOOL)f;
- (id)animator; - (NSDictionary *)animations; - (void)setAnimations:(NSDictionary *)a; - (id)animationForKey:(NSString *)k; + (id)defaultAnimationForKey:(NSString *)k;
@end

@interface NSApplication (XEFMisc)
- (void)registerForRemoteNotifications; - (void)unregisterForRemoteNotifications; - (BOOL)isRegisteredForRemoteNotifications; - (void)registerForRemoteNotificationTypes:(NSUInteger)t; - (NSUInteger)enabledRemoteNotificationTypes;
- (void)beginSheet:(NSWindow *)s modalForWindow:(NSWindow *)w modalDelegate:(id)d didEndSelector:(SEL)sel contextInfo:(void *)ci; - (void)endSheet:(NSWindow *)s; - (void)endSheet:(NSWindow *)s returnCode:(NSInteger)rc;
- (void)makeWindowsPerform:(SEL)sel inOrder:(BOOL)o; - (id)context; - (BOOL)isAutomaticCustomizeTouchBarMenuItemEnabled; - (void)setAutomaticCustomizeTouchBarMenuItemEnabled:(BOOL)f;
- (void)toggleTouchBarCustomizationPalette:(id)s; - (void)unregisterUserInterfaceItemSearchHandler:(id)h;
- (BOOL)searchString:(NSString *)s inUserInterfaceItemString:(NSString *)i searchRange:(NSRange)r foundRange:(NSRange *)f;
- (void)restoreWindowWithIdentifier:(NSString *)i state:(NSCoder *)s completionHandler:(void (^)(NSWindow *, NSError *))h;
@end

/* Touch Bar items, writing tools, text finder/checking, input server */
@interface NSColorPickerTouchBarItem : NSTouchBarItem { @public NSColor *_color; BOOL _alpha, _enabled; id _colorList, _spaces, _target; SEL _action; }
+ (id)colorPickerWithIdentifier:(NSString *)i; + (id)textColorPickerWithIdentifier:(NSString *)i; + (id)strokeColorPickerWithIdentifier:(NSString *)i; + (id)colorPickerWithIdentifier:(NSString *)i buttonImage:(NSImage *)img;
- (NSColor *)color; - (void)setColor:(NSColor *)c; - (BOOL)showsAlpha; - (void)setShowsAlpha:(BOOL)f; - (id)allowedColorSpaces; - (void)setAllowedColorSpaces:(id)s; - (id)colorList; - (void)setColorList:(id)l;
- (NSString *)customizationLabel; - (void)setCustomizationLabel:(NSString *)l; - (id)target; - (void)setTarget:(id)t; - (SEL)action; - (void)setAction:(SEL)a; - (BOOL)isEnabled; - (void)setEnabled:(BOOL)f;
@end
@interface NSStepperTouchBarItem : NSTouchBarItem { @public double _max, _min, _inc, _val; id _target; SEL _action; }
+ (id)stepperTouchBarItemWithIdentifier:(NSString *)i formatter:(NSFormatter *)f; + (id)stepperTouchBarItemWithIdentifier:(NSString *)i drawingHandler:(void (^)(NSRect, double))h;
- (double)maxValue; - (void)setMaxValue:(double)v; - (double)minValue; - (void)setMinValue:(double)v; - (double)increment; - (void)setIncrement:(double)v; - (double)value; - (void)setValue:(double)v;
- (id)target; - (void)setTarget:(id)t; - (SEL)action; - (void)setAction:(SEL)a; - (NSString *)customizationLabel; - (void)setCustomizationLabel:(NSString *)l;
@end
@interface NSPopoverTouchBarItem : NSTouchBarItem { @public NSTouchBar *_pop, *_hold; NSTouchBarItem *_coll; NSImage *_img; NSString *_lab; BOOL _close; }
- (NSTouchBar *)popoverTouchBar; - (void)setPopoverTouchBar:(NSTouchBar *)b; - (NSString *)customizationLabel; - (void)setCustomizationLabel:(NSString *)l;
- (NSTouchBarItem *)collapsedRepresentation; - (void)setCollapsedRepresentation:(NSTouchBarItem *)i; - (NSImage *)collapsedRepresentationImage; - (void)setCollapsedRepresentationImage:(NSImage *)i;
- (NSString *)collapsedRepresentationLabel; - (void)setCollapsedRepresentationLabel:(NSString *)l; - (NSTouchBar *)pressAndHoldTouchBar; - (void)setPressAndHoldTouchBar:(NSTouchBar *)b;
- (BOOL)showsCloseButton; - (void)setShowsCloseButton:(BOOL)f; - (void)showPopover:(id)s; - (void)dismissPopover:(id)s; - (id)makeStandardActivatePopoverGestureRecognizer;
@end
@interface NSCandidateListTouchBarItem : NSTouchBarItem { @public id _client, _delegate; BOOL _coll, _allowsColl, _ticc; id _attr; NSArray *_cands; }
- (id)client; - (void)setClient:(id)c; - (id)delegate; - (void)setDelegate:(id)d; - (BOOL)isCollapsed; - (void)setCollapsed:(BOOL)f; - (BOOL)allowsCollapsing; - (void)setAllowsCollapsing:(BOOL)f;
- (BOOL)isCandidateListVisible; - (void)updateWithInsertionPointVisibility:(BOOL)f; - (BOOL)allowsTextInputContextCandidates; - (void)setAllowsTextInputContextCandidates:(BOOL)f;
- (id)attributedStringForCandidate; - (void)setAttributedStringForCandidate:(id)b; - (NSArray *)candidates; - (void)setCandidates:(NSArray *)c forSelectedRange:(NSRange)r inString:(NSString *)s;
- (NSString *)customizationLabel; - (void)setCustomizationLabel:(NSString *)l;
@end
@interface NSWritingToolsCoordinator : NSObject { @public id _delegate, _eff, _dec; NSInteger _pref, _prefopt; BOOL _list; }
+ (BOOL)isWritingToolsAvailable; - (id)initWithDelegate:(id)d; - (id)delegate; - (NSView *)view; - (NSView *)effectContainerView; - (void)setEffectContainerView:(NSView *)v;
- (NSView *)decorationContainerView; - (void)setDecorationContainerView:(NSView *)v; - (NSInteger)state; - (void)stopWritingTools; - (NSInteger)preferredBehavior; - (void)setPreferredBehavior:(NSInteger)b;
- (NSInteger)behavior; - (NSInteger)preferredResultOptions; - (void)setPreferredResultOptions:(NSInteger)o; - (NSInteger)resultOptions; - (BOOL)includesTextListMarkers; - (void)setIncludesTextListMarkers:(BOOL)f;
- (void)updateRange:(NSRange)r withText:(id)t reason:(NSInteger)reason forContextWithIdentifier:(id)i; - (void)updateForReflowedTextInContextWithIdentifier:(id)i;
@end
@interface NSTextFinder : NSObject { @public id _client, _bar; BOOL _incr, _dim; }
- (id)client; - (void)setClient:(id)c; - (void)performAction:(NSInteger)a; - (BOOL)validateAction:(NSInteger)a; - (id)findBarContainer; - (void)setFindBarContainer:(id)c; - (void)cancelFindIndicator;
- (BOOL)findIndicatorNeedsUpdate; - (void)setFindIndicatorNeedsUpdate:(BOOL)f; - (BOOL)isIncrementalSearchingEnabled; - (void)setIncrementalSearchingEnabled:(BOOL)f;
- (BOOL)incrementalSearchingShouldDimContentView; - (void)setIncrementalSearchingShouldDimContentView:(BOOL)f; - (NSArray *)incrementalMatchRanges; + (void)drawIncrementalMatchHighlightInRect:(NSRect)r; - (void)noteClientStringWillChange;
@end
@interface NSTextCheckingController : NSObject { @public id _client; NSInteger _tag; }
- (id)initWithClient:(id)c; - (id)client; - (void)invalidate; - (void)didChangeTextInRange:(NSRange)r; - (void)insertedTextInRange:(NSRange)r; - (void)didChangeSelectedRange; - (void)considerTextCheckingForRange:(NSRange)r;
- (void)checkTextInRange:(NSRange)r types:(NSUInteger)t options:(NSDictionary *)o; - (void)checkTextInSelection:(id)s; - (void)checkTextInDocument:(id)s; - (void)orderFrontSubstitutionsPanel:(id)s;
- (void)checkSpelling:(id)s; - (void)showGuessPanel:(id)s; - (void)changeSpelling:(id)s; - (void)ignoreSpelling:(id)s; - (void)updateCandidates; - (NSArray *)validAnnotations;
- (NSMenu *)menuAtIndex:(NSUInteger)i clickedOnSelection:(BOOL)s effectiveRange:(NSRange *)r; - (NSInteger)spellCheckerDocumentTag; - (void)setSpellCheckerDocumentTag:(NSInteger)t;
@end
@interface NSInputServer : NSObject { @public id _delegate; NSString *_name; }
- (id)initWithDelegate:(id)d name:(NSString *)n; - (void)insertText:(id)s client:(id)c; - (void)doCommandBySelector:(SEL)s client:(id)c; - (void)markedTextAbandoned:(id)c; - (void)markedTextSelectionChanged:(NSRange)r client:(id)c;
- (void)terminate:(id)s; - (BOOL)canBeDisabled; - (BOOL)wantsToInterpretAllKeystrokes; - (BOOL)wantsToHandleMouseEvents; - (BOOL)wantsToDelayTextChangeNotifications;
- (void)inputClientBecomeActive:(id)c; - (void)inputClientResignActive:(id)c; - (void)inputClientEnabled:(id)c; - (void)inputClientDisabled:(id)c;
- (void)activeConversationWillChange:(id)c fromOldConversation:(NSInteger)o; - (void)activeConversationChanged:(id)c toNewConversation:(NSInteger)n;
- (void)mouseDownOnCharacterIndex:(NSUInteger)i atCoordinate:(NSPoint)p withModifier:(NSUInteger)m client:(id)c; - (void)mouseDraggedOnCharacterIndex:(NSUInteger)i atCoordinate:(NSPoint)p withModifier:(NSUInteger)m client:(id)c;
- (void)mouseUpOnCharacterIndex:(NSUInteger)i atCoordinate:(NSPoint)p withModifier:(NSUInteger)m client:(id)c;
@end
@interface NSSpellChecker (XEFMisc)
- (NSMenu *)menuForResult:(id)r string:(NSString *)s options:(NSDictionary *)o atLocation:(NSPoint)p inView:(NSView *)v; - (NSPanel *)spellingPanel; - (NSPanel *)substitutionsPanel;
- (id)substitutionsPanelAccessoryViewController; - (void)setSubstitutionsPanelAccessoryViewController:(id)c; - (void)setWordFieldStringValue:(NSString *)s;
- (void)showCorrectionIndicatorOfType:(NSInteger)t primaryString:(NSString *)p alternativeStrings:(NSArray *)a forStringInRect:(NSRect)r view:(NSView *)v completionHandler:(void (^)(NSString *))h;
- (void)showInlinePredictionForCandidates:(NSArray *)c client:(id)cl; - (NSArray *)guessesForWord:(NSString *)w; - (void)forgetWord:(NSString *)w;
+ (BOOL)isAutomaticTextReplacementEnabled; + (BOOL)isAutomaticSpellingCorrectionEnabled; + (BOOL)isAutomaticQuoteSubstitutionEnabled; + (BOOL)isAutomaticDashSubstitutionEnabled;
+ (BOOL)isAutomaticCapitalizationEnabled; + (BOOL)isAutomaticPeriodSubstitutionEnabled; + (BOOL)isAutomaticTextCompletionEnabled; + (BOOL)isAutomaticInlinePredictionEnabled;
@end

@interface NSBitmapImageRep (XEFMisc)
- (id)initWithFocusedViewRect:(NSRect)r; - (id)initWithCIImage:(id)i; - (void)getCompression:(NSUInteger *)c factor:(float *)f; - (void)setCompression:(NSUInteger)c factor:(float)f;
+ (NSData *)TIFFRepresentationOfImageRepsInArray:(NSArray *)a usingCompression:(NSUInteger)c factor:(float)f; + (void)getTIFFCompressionTypes:(const NSUInteger **)t count:(NSInteger *)n;
+ (NSString *)localizedNameForTIFFCompressionType:(NSUInteger)t; - (BOOL)canBeCompressedUsing:(NSUInteger)c;
- (void)colorizeByMappingGray:(CGFloat)m toColor:(NSColor *)c blackMapping:(NSColor *)b whiteMapping:(NSColor *)w;
- (id)initForIncrementalLoad; - (NSInteger)incrementalLoadFromData:(NSData *)d complete:(BOOL)c; - (NSColorSpace *)colorSpace;
- (NSBitmapImageRep *)bitmapImageRepByConvertingToColorSpace:(NSColorSpace *)cs renderingIntent:(NSInteger)i; - (NSBitmapImageRep *)bitmapImageRepByRetaggingWithColorSpace:(NSColorSpace *)cs;
- (void)setProperty:(NSString *)k withValue:(id)v; - (id)valueForProperty:(NSString *)k;
@end

@interface NSBrowser (XEFMisc)
- (BOOL)_xefClassic;
- (id)itemAtIndexPath:(NSIndexPath *)p; - (void)validateVisibleColumns; - (void)scrollColumnsRightBy:(NSInteger)n; - (void)scrollColumnsLeftBy:(NSInteger)n; - (void)drawTitleOfColumn:(NSInteger)c inRect:(NSRect)r;
- (BOOL)prefersAllColumnUserResizing; - (void)setPrefersAllColumnUserResizing:(BOOL)f; - (void)noteHeightOfRowsWithIndexesChanged:(NSIndexSet *)s inColumn:(NSInteger)c;
- (NSString *)columnsAutosaveName; - (void)setColumnsAutosaveName:(NSString *)n; + (void)removeSavedColumnsWithAutosaveName:(NSString *)n;
- (BOOL)canDragRowsWithIndexes:(NSIndexSet *)s inColumn:(NSInteger)c withEvent:(NSEvent *)e; - (NSImage *)draggingImageForRowsWithIndexes:(NSIndexSet *)s inColumn:(NSInteger)c withEvent:(NSEvent *)e offset:(NSPointPointer)o;
- (void)setDraggingSourceOperationMask:(NSUInteger)m forLocal:(BOOL)l; - (BOOL)editItemAtIndexPath:(NSIndexPath *)p withEvent:(NSEvent *)e select:(BOOL)s; - (void)scrollViaScroller:(NSScroller *)s;
@end
@interface NSDocument (XEFMisc)
- (void)runModalPageLayoutWithPrintInfo:(NSPrintInfo *)pi delegate:(id)d didRunSelector:(SEL)s contextInfo:(void *)ci; - (BOOL)preparePageLayout:(id)l; - (BOOL)shouldChangePrintInfo:(NSPrintInfo *)pi;
- (void)runModalPrintOperation:(id)op delegate:(id)d didRunSelector:(SEL)s contextInfo:(void *)ci; - (id)PDFPrintOperation; - (void)shareDocumentWithSharingService:(id)s completionHandler:(void (^)(BOOL))h;
- (void)prepareSharingServicePicker:(id)p; - (NSArray *)previewRepresentableActivityItems; - (void)setPreviewRepresentableActivityItems:(NSArray *)a;
- (void)printShowingPrintPanel:(BOOL)f; - (void)runModalPageLayoutWithPrintInfo:(NSPrintInfo *)pi; - (void)saveToFile:(NSString *)f saveOperation:(NSUInteger)op delegate:(id)d didSaveSelector:(SEL)s contextInfo:(void *)ci;
- (id)handleSaveScriptCommand:(id)c; - (id)handleCloseScriptCommand:(id)c; - (id)handlePrintScriptCommand:(id)c; - (id)objectSpecifier;
@end
@interface NSLayoutManager (XEFMisc)
- (NSRect)boundingRectForGlyphRange:(NSRange)r inTextContainer:(NSTextContainer *)c;
- (NSUInteger)getLineFragmentInsertionPointsForCharacterAtIndex:(NSUInteger)i alternatePositions:(BOOL)a inDisplayOrder:(BOOL)d positions:(CGFloat *)p characterIndexes:(NSUInteger *)c;
- (NSFont *)substituteFontForFont:(NSFont *)f; - (void)insertGlyphs:(const NSGlyph *)g length:(NSUInteger)n forStartingGlyphAtIndex:(NSUInteger)i characterIndex:(NSUInteger)c;
- (void)insertGlyph:(NSGlyph)g atGlyphIndex:(NSUInteger)i characterIndex:(NSUInteger)c; - (void)replaceGlyphAtIndex:(NSUInteger)i withGlyph:(NSGlyph)g; - (void)deleteGlyphsInRange:(NSRange)r;
- (void)setCharacterIndex:(NSUInteger)c forGlyphAtIndex:(NSUInteger)i; - (void)setIntAttribute:(NSInteger)a value:(NSInteger)v forGlyphAtIndex:(NSUInteger)i; - (void)invalidateGlyphsOnLayoutInvalidationForGlyphRange:(NSRange)r;
- (NSInteger)intAttribute:(NSInteger)a forGlyphAtIndex:(NSUInteger)i;
- (NSUInteger)getGlyphsInRange:(NSRange)r glyphs:(NSGlyph *)g characterIndexes:(NSUInteger *)c glyphInscriptions:(NSInteger *)in elasticBits:(BOOL *)e;
- (NSUInteger)getGlyphsInRange:(NSRange)r glyphs:(NSGlyph *)g characterIndexes:(NSUInteger *)c glyphInscriptions:(NSInteger *)in elasticBits:(BOOL *)e bidiLevels:(unsigned char *)b;
- (void)textStorage:(NSTextStorage *)s edited:(NSUInteger)m range:(NSRange)r changeInLength:(NSInteger)d invalidatedRange:(NSRange)i;
- (void)setLocations:(NSPoint *)l startingGlyphIndexes:(NSUInteger *)s count:(NSUInteger)n forGlyphRange:(NSRange)r;
- (void)showPackedGlyphs:(char *)g length:(NSUInteger)n glyphRange:(NSRange)r atPoint:(NSPoint)p font:(NSFont *)f color:(NSColor *)c printingAdjustment:(NSSize)a;
- (void)showCGGlyphs:(const unsigned short *)g positions:(const NSPoint *)p count:(NSUInteger)n font:(NSFont *)f matrix:(NSAffineTransform *)m attributes:(NSDictionary *)a inContext:(NSGraphicsContext *)c;
@end
