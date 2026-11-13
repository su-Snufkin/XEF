/* The last small classes and extras (AppKitMisc8.m). */
#import "AppKitMisc7.h"

@interface NSScrubberSelectionStyle : NSObject
+ (id)outlineOverlayStyle; + (id)roundedBackgroundStyle; - (id)makeSelectionView;
@end
@interface NSScrubberTextItemView : NSScrubberArrangedView { @public NSTextField *_tf; }
- (NSTextField *)textField; - (NSString *)title; - (void)setTitle:(NSString *)t;
@end
@interface NSScrubberProportionalLayout : NSScrubberLayout { @public NSInteger _n; }
- (id)initWithNumberOfVisibleItems:(NSInteger)n; - (NSInteger)numberOfVisibleItems; - (void)setNumberOfVisibleItems:(NSInteger)n;
@end
@interface NSMutableFontCollection : NSFontCollection
- (void)setQueryDescriptors:(NSArray *)d; - (void)setExclusionDescriptors:(NSArray *)d; - (void)addQueryForDescriptors:(NSArray *)d; - (void)removeQueryForDescriptors:(NSArray *)d;
@end
@interface NSMenuToolbarItem : NSToolbarItem { @public NSMenu *_mtMenu; BOOL _ind; }
- (NSMenu *)menu; - (void)setMenu:(NSMenu *)m; - (BOOL)showsIndicator; - (void)setShowsIndicator:(BOOL)f;
@end
@interface NSItemBadge : NSObject { @public NSString *_t; }
+ (id)badgeWithCount:(NSInteger)n; + (id)badgeWithText:(NSString *)t; + (id)indicatorBadge; - (NSString *)text;
@end
@interface NSGlassEffectContainerView : NSView { @public NSView *_cv; CGFloat _sp; }
- (NSView *)contentView; - (void)setContentView:(NSView *)v; - (CGFloat)spacing; - (void)setSpacing:(CGFloat)s;
@end
@interface NSBackgroundExtensionView : NSView { @public NSView *_cv; BOOL _auto; }
- (NSView *)contentView; - (void)setContentView:(NSView *)v; - (BOOL)automaticallyPlacesContentView; - (void)setAutomaticallyPlacesContentView:(BOOL)f;
@end
@interface NSFontAssetRequest : NSObject { @public NSArray *_d; }
- (id)initWithFontDescriptors:(NSArray *)d options:(NSUInteger)o; - (NSArray *)downloadedFontDescriptors; - (NSProgress *)progress; - (void)downloadFontAssetsWithCompletionHandler:(void (^)(NSError *))h;
@end
@interface NSCollectionViewFlowLayoutInvalidationContext : NSCollectionViewLayoutInvalidationContext { @public BOOL _m, _a; }
- (BOOL)invalidateFlowLayoutDelegateMetrics; - (void)setInvalidateFlowLayoutDelegateMetrics:(BOOL)f; - (BOOL)invalidateFlowLayoutAttributes; - (void)setInvalidateFlowLayoutAttributes:(BOOL)f;
@end
@interface NSCollectionViewUpdateItem : NSObject { @public NSIndexPath *_b, *_a; NSInteger _act; }
- (NSIndexPath *)indexPathBeforeUpdate; - (NSIndexPath *)indexPathAfterUpdate; - (NSInteger)updateAction;
@end
@interface NSAccessibilityElement : NSObject { @public NSString *_role, *_label; NSRect _frame, _pframe; id _parent; NSMutableArray *_kids; }
+ (id)accessibilityElementWithRole:(NSString *)r frame:(NSRect)f label:(NSString *)l parent:(id)p; - (void)accessibilityAddChildElement:(id)c; - (NSRect)accessibilityFrameInParentSpace; - (void)setAccessibilityFrameInParentSpace:(NSRect)f;
- (NSString *)accessibilityRole; - (NSString *)accessibilityLabel; - (NSRect)accessibilityFrame; - (id)accessibilityParent; - (NSArray *)accessibilityChildren;
@end
@interface NSViewAnimation : NSAnimation { @public NSArray *_va; }
- (id)initWithViewAnimations:(NSArray *)a; - (NSArray *)viewAnimations; - (void)setViewAnimations:(NSArray *)a;
@end
@interface NSPreviewRepresentingActivityItem : NSObject { @public id _item; NSString *_title; id _image, _icon; }
- (id)initWithItem:(id)i title:(NSString *)t image:(id)img icon:(id)ic; - (id)initWithItem:(id)i title:(NSString *)t imageProvider:(id)ip iconProvider:(id)icp; - (id)item; - (NSString *)title;
@end
@interface NSPressureConfiguration : NSObject { @public NSInteger _b; }
- (NSInteger)pressureBehavior; - (id)initWithPressureBehavior:(NSInteger)b; - (void)set;
@end
@interface NSViewLayoutRegion : NSObject
+ (id)safeAreaLayoutRegionWithCornerAdaptation:(NSInteger)a; + (id)marginsLayoutRegionWithCornerAdaptation:(NSInteger)a;
@end
@interface NSStatusBarButton : NSButton { @public BOOL _dis; }
- (BOOL)appearsDisabled; - (void)setAppearsDisabled:(BOOL)f;
@end
@interface NSSharingServicePickerToolbarItem : NSToolbarItem { @public id _delegate; }
- (id)delegate; - (void)setDelegate:(id)d;
@end
@interface NSPredicateEditor : NSRuleEditor { @public NSArray *_rt; }
- (NSArray *)rowTemplates; - (void)setRowTemplates:(NSArray *)t;
@end
@interface NSGlyphGenerator : NSObject
+ (id)sharedGlyphGenerator; - (void)generateGlyphsForGlyphStorage:(id)s desiredNumberOfCharacters:(NSUInteger)n glyphIndex:(NSUInteger *)g characterIndex:(NSUInteger *)c;
@end
@interface NSStringDrawingContext : NSObject { @public CGFloat _min, _act; NSRect _tb; }
- (CGFloat)minimumScaleFactor; - (void)setMinimumScaleFactor:(CGFloat)f; - (CGFloat)actualScaleFactor; - (NSRect)totalBounds;
@end
@interface NSColorSampler : NSObject
- (void)showSamplerWithSelectionHandler:(void (^)(NSColor *))h;
@end
@interface NSAdaptiveImageGlyph : NSObject <NSCopying> { @public NSData *_d; NSString *_cid, *_desc; }
- (id)initWithImageContent:(NSData *)d; - (NSData *)imageContent; - (NSString *)contentIdentifier; - (NSString *)contentDescription; + (NSString *)contentType;
@end
@interface NSPICTImageRep : NSImageRep { @public NSData *_d; NSRect _bb; }
+ (id)imageRepWithData:(NSData *)d; - (id)initWithData:(NSData *)d; - (NSData *)PICTRepresentation; - (NSRect)boundingBox;
@end
@interface NSMovie : NSObject
@end

@interface NSToolbarItemGroup (XEFMisc)
+ (id)groupWithItemIdentifier:(NSString *)i titles:(NSArray *)t selectionMode:(NSInteger)m labels:(NSArray *)l target:(id)tg action:(SEL)a;
+ (id)groupWithItemIdentifier:(NSString *)i images:(NSArray *)im selectionMode:(NSInteger)m labels:(NSArray *)l target:(id)tg action:(SEL)a; - (BOOL)isSelectedAtIndex:(NSInteger)i;
@end
@interface NSWindowController (XEFMisc)
- (id)initWithWindowNibPath:(NSString *)p owner:(id)o; - (NSArray *)previewRepresentableActivityItems; - (void)setPreviewRepresentableActivityItems:(NSArray *)a;
@end
@interface NSTextContainer (XEFMisc2)
- (NSRect)lineFragmentRectForProposedRect:(NSRect)p atIndex:(NSUInteger)i writingDirection:(NSInteger)d remainingRect:(NSRect *)r; - (NSInteger)layoutOrientation;
- (NSRect)lineFragmentRectForProposedRect:(NSRect)p sweepDirection:(NSInteger)s movementDirection:(NSInteger)m remainingRect:(NSRect *)r;
@end
@interface NSSet (XEFAppKit)
+ (NSSet *)setWithCollectionViewIndexPath:(NSIndexPath *)p; + (NSSet *)setWithCollectionViewIndexPaths:(NSArray *)p; - (void)enumerateIndexPathsWithOptions:(NSUInteger)o usingBlock:(void (^)(NSIndexPath *, BOOL *))b;
@end
@interface NSResponder (XEFMisc)
- (NSInteger)interfaceStyle; - (void)setInterfaceStyle:(NSInteger)s; - (BOOL)performMnemonic:(NSString *)s;
@end
@interface NSOpenGLPixelFormat (XEFMisc)
- (id)initWithCGLPixelFormatObj:(void *)o; - (const void *)attributes; - (void)setAttributes:(const void *)a;
@end
@interface NSCollectionViewLayoutAttributes (XEFMisc)
+ (id)layoutAttributesForInterItemGapBeforeIndexPath:(NSIndexPath *)p; + (id)layoutAttributesForSupplementaryViewOfKind:(NSString *)k withIndexPath:(NSIndexPath *)p; + (id)layoutAttributesForDecorationViewOfKind:(NSString *)k withIndexPath:(NSIndexPath *)p;
@end
@interface NSCollectionViewFlowLayout (XEFMisc)
- (BOOL)sectionAtIndexIsCollapsed:(NSUInteger)i; - (void)collapseSectionAtIndex:(NSUInteger)i; - (void)expandSectionAtIndex:(NSUInteger)i;
@end
@interface NSClipView (XEFMisc)
- (NSCursor *)documentCursor; - (void)setDocumentCursor:(NSCursor *)c; - (void)viewBoundsChanged:(NSNotification *)n;
@end
@interface NSArrayController (XEFMisc)
- (void)didChangeArrangementCriteria; - (void)insertObjects:(NSArray *)o atArrangedObjectIndexes:(NSIndexSet *)i; - (void)removeObjectAtArrangedObjectIndex:(NSUInteger)i;
@end
@interface NSSplitView (XEFMisc)
- (void)setIsPaneSplitter:(BOOL)f; - (BOOL)isPaneSplitter;
@end
@interface NSSegmentedControl (XEFMisc)
- (void)compressWithPrioritizedCompressionOptions:(NSArray *)o; - (NSSize)minimumSizeWithPrioritizedCompressionOptions:(NSArray *)o;
@end
@interface NSSegmentedCell (XEFMisc)
- (void)drawSegment:(NSInteger)i inFrame:(NSRect)f withView:(NSView *)v; - (NSInteger)interiorBackgroundStyleForSegment:(NSInteger)i;
@end
@interface NSSecureTextFieldCell (XEFMisc)
- (BOOL)echosBullets; - (void)setEchosBullets:(BOOL)f;
@end
@interface NSPopUpButtonCell (XEFMisc)
- (NSInteger)indexOfItemWithTarget:(id)t andAction:(SEL)a; - (BOOL)validateMenuItem:(NSMenuItem *)m;
@end
@interface NSMutableParagraphStyle (XEFMisc)
- (NSInteger)lineBreakStrategy; - (void)setLineBreakStrategy:(NSInteger)s;
@end
@interface NSFileWrapper (XEFAppKit)
- (NSImage *)icon; - (void)setIcon:(NSImage *)i;
@end
@interface NSCursor (XEFMisc)
- (id)initWithCoder:(NSCoder *)c; + (void)pop;
@end
@interface NSBrowserCell (XEFMisc)
- (NSColor *)highlightColorInView:(NSView *)v;
@end
@interface NSAppearance (XEFMisc)
- (id)initWithAppearanceNamed:(NSString *)n bundle:(NSBundle *)b;
@end
@interface NSTextTab (XEFMisc)
+ (NSCharacterSet *)columnTerminatorsForLocale:(NSLocale *)l;
@end
@interface NSBundle (XEFMisc3)
- (BOOL)loadNibFile:(NSString *)f externalNameTable:(NSDictionary *)t withZone:(NSZone *)z; + (BOOL)loadNibFile:(NSString *)f externalNameTable:(NSDictionary *)t withZone:(NSZone *)z;
@end
@interface NSURL (XEFAppKit)
+ (NSURL *)URLFromPasteboard:(NSPasteboard *)p; - (void)writeToPasteboard:(NSPasteboard *)p; - (NSArray *)writableTypesForPasteboard:(NSPasteboard *)p; + (NSArray *)readableTypesForPasteboard:(NSPasteboard *)p;
@end
@interface NSString (XEFAppKit)
- (NSArray *)writableTypesForPasteboard:(NSPasteboard *)p; + (NSArray *)readableTypesForPasteboard:(NSPasteboard *)p;
@end
@interface NSColor (XEFAppKit)
- (NSString *)catalogNameComponent; - (NSString *)colorNameComponent; + (NSArray *)readableTypesForPasteboard:(NSPasteboard *)p; - (NSArray *)writableTypesForPasteboard:(NSPasteboard *)p;
@end
@interface NSAttributedString (XEFAppKit2)
- (NSArray *)writableTypesForPasteboard:(NSPasteboard *)p; + (NSArray *)readableTypesForPasteboard:(NSPasteboard *)p;
@end
@interface NSTextStorage (XEFMisc)
- (void)setAttributeRuns:(NSArray *)a; - (void)setParagraphs:(NSArray *)a; - (void)setWords:(NSArray *)a; - (void)setCharacters:(NSArray *)a;
@end
@interface NSBezierPath (XEFMisc)
- (void)appendBezierPathWithGlyph:(unsigned int)g inFont:(NSFont *)f; - (void)appendBezierPathWithGlyphs:(const unsigned int *)g count:(NSInteger)n inFont:(NSFont *)f;
- (void)appendBezierPathWithCGGlyph:(unsigned short)g inFont:(NSFont *)f; - (void)appendBezierPathWithCGGlyphs:(const unsigned short *)g count:(NSInteger)n inFont:(NSFont *)f; - (void)appendBezierPathWithPackedGlyphs:(const char *)g;
@end
@interface NSWorkspace (XEFMisc)
- (void)requestAuthorizationOfType:(NSInteger)t completionHandler:(void (^)(id, NSError *))h;
@end
@interface NSParagraphStyle (XEFMisc)
- (NSInteger)lineBreakStrategy;
@end
@interface NSMutableAttributedString (XEFMisc)
- (BOOL)readFromData:(NSData *)d options:(NSDictionary *)o documentAttributes:(NSDictionary **)a error:(NSError **)e; - (BOOL)readFromURL:(NSURL *)u options:(NSDictionary *)o documentAttributes:(NSDictionary **)a error:(NSError **)e;
- (BOOL)readFromData:(NSData *)d options:(NSDictionary *)o documentAttributes:(NSDictionary **)a; - (BOOL)readFromURL:(NSURL *)u options:(NSDictionary *)o documentAttributes:(NSDictionary **)a; - (void)updateAttachmentsFromPath:(NSString *)p;
@end
