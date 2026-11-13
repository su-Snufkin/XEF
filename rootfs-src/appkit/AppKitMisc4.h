/* Compositional layout model, text lists, tab groups, combo button, help manager and other small classes (AppKitMisc4.m). */
#import "AppKitMisc3.h"

@interface NSCollectionLayoutDimension : NSObject <NSCopying> { @public NSInteger _kind; CGFloat _v; }
+ (id)fractionalWidthDimension:(CGFloat)v; + (id)fractionalHeightDimension:(CGFloat)v; + (id)absoluteDimension:(CGFloat)v; + (id)estimatedDimension:(CGFloat)v;
- (BOOL)isFractionalWidth; - (BOOL)isFractionalHeight; - (BOOL)isAbsolute; - (BOOL)isEstimated; - (CGFloat)dimension;
@end
@interface NSCollectionLayoutSize : NSObject <NSCopying> { @public NSCollectionLayoutDimension *_w, *_h; }
+ (id)sizeWithWidthDimension:(NSCollectionLayoutDimension *)w heightDimension:(NSCollectionLayoutDimension *)h; - (NSCollectionLayoutDimension *)widthDimension; - (NSCollectionLayoutDimension *)heightDimension;
@end
@interface NSCollectionLayoutSpacing : NSObject <NSCopying> { @public BOOL _flex; CGFloat _v; }
+ (id)flexibleSpacing:(CGFloat)v; + (id)fixedSpacing:(CGFloat)v; - (CGFloat)spacing; - (BOOL)isFlexibleSpacing; - (BOOL)isFixedSpacing;
@end
@interface NSCollectionLayoutEdgeSpacing : NSObject <NSCopying> { @public NSCollectionLayoutSpacing *_l, *_t, *_r, *_b; }
+ (id)spacingForLeading:(NSCollectionLayoutSpacing *)l top:(NSCollectionLayoutSpacing *)t trailing:(NSCollectionLayoutSpacing *)r bottom:(NSCollectionLayoutSpacing *)b;
- (NSCollectionLayoutSpacing *)leading; - (NSCollectionLayoutSpacing *)top; - (NSCollectionLayoutSpacing *)trailing; - (NSCollectionLayoutSpacing *)bottom;
@end
@interface NSCollectionLayoutAnchor : NSObject <NSCopying> { @public NSUInteger _edges; NSPoint _off; int _mode; }
+ (id)layoutAnchorWithEdges:(NSUInteger)e; + (id)layoutAnchorWithEdges:(NSUInteger)e absoluteOffset:(NSPoint)o; + (id)layoutAnchorWithEdges:(NSUInteger)e fractionalOffset:(NSPoint)o;
- (NSUInteger)edges; - (NSPoint)offset; - (BOOL)isAbsoluteOffset; - (BOOL)isFractionalOffset;
@end
@interface NSCollectionLayoutItem : NSObject <NSCopying> { @public NSCollectionLayoutSize *_size; NSDirectionalEdgeInsets _ci; NSCollectionLayoutEdgeSpacing *_es; NSArray *_supp; }
+ (id)itemWithLayoutSize:(NSCollectionLayoutSize *)s; + (id)itemWithLayoutSize:(NSCollectionLayoutSize *)s supplementaryItems:(NSArray *)a;
- (NSDirectionalEdgeInsets)contentInsets; - (void)setContentInsets:(NSDirectionalEdgeInsets)i; - (NSCollectionLayoutEdgeSpacing *)edgeSpacing; - (void)setEdgeSpacing:(NSCollectionLayoutEdgeSpacing *)e;
- (NSCollectionLayoutSize *)layoutSize; - (NSArray *)supplementaryItems;
@end
@interface NSCollectionLayoutSupplementaryItem : NSCollectionLayoutItem { @public NSInteger _z; NSString *_kind; NSCollectionLayoutAnchor *_ca, *_ia; }
+ (id)supplementaryItemWithLayoutSize:(NSCollectionLayoutSize *)s elementKind:(NSString *)k containerAnchor:(NSCollectionLayoutAnchor *)a;
+ (id)supplementaryItemWithLayoutSize:(NSCollectionLayoutSize *)s elementKind:(NSString *)k containerAnchor:(NSCollectionLayoutAnchor *)a itemAnchor:(NSCollectionLayoutAnchor *)i;
- (NSInteger)zIndex; - (void)setZIndex:(NSInteger)z; - (NSString *)elementKind; - (NSCollectionLayoutAnchor *)containerAnchor; - (NSCollectionLayoutAnchor *)itemAnchor;
@end
@interface NSCollectionLayoutBoundarySupplementaryItem : NSCollectionLayoutSupplementaryItem { @public BOOL _ext, _pin; NSUInteger _align; NSPoint _off; }
+ (id)boundarySupplementaryItemWithLayoutSize:(NSCollectionLayoutSize *)s elementKind:(NSString *)k alignment:(NSUInteger)a;
+ (id)boundarySupplementaryItemWithLayoutSize:(NSCollectionLayoutSize *)s elementKind:(NSString *)k alignment:(NSUInteger)a absoluteOffset:(NSPoint)o;
- (BOOL)extendsBoundary; - (void)setExtendsBoundary:(BOOL)f; - (BOOL)pinToVisibleBounds; - (void)setPinToVisibleBounds:(BOOL)f; - (NSUInteger)alignment; - (NSPoint)offset;
@end
@interface NSCollectionLayoutDecorationItem : NSCollectionLayoutItem { @public NSInteger _z; NSString *_kind; }
+ (id)backgroundDecorationItemWithElementKind:(NSString *)k; - (NSInteger)zIndex; - (void)setZIndex:(NSInteger)z; - (NSString *)elementKind;
@end
@interface NSCollectionLayoutGroup : NSCollectionLayoutItem { @public NSArray *_subs; NSCollectionLayoutSpacing *_inter; id _provider; }
+ (id)horizontalGroupWithLayoutSize:(NSCollectionLayoutSize *)s subitem:(NSCollectionLayoutItem *)i count:(NSInteger)n; + (id)horizontalGroupWithLayoutSize:(NSCollectionLayoutSize *)s subitems:(NSArray *)a;
+ (id)verticalGroupWithLayoutSize:(NSCollectionLayoutSize *)s subitem:(NSCollectionLayoutItem *)i count:(NSInteger)n; + (id)verticalGroupWithLayoutSize:(NSCollectionLayoutSize *)s subitems:(NSArray *)a;
+ (id)customGroupWithLayoutSize:(NSCollectionLayoutSize *)s itemProvider:(id)p; - (NSArray *)supplementaryItems; - (void)setSupplementaryItems:(NSArray *)a;
- (NSCollectionLayoutSpacing *)interItemSpacing; - (void)setInterItemSpacing:(NSCollectionLayoutSpacing *)s; - (NSArray *)subitems; - (NSString *)visualDescription;
@end
@interface NSCollectionLayoutGroupCustomItem : NSObject <NSCopying> { @public NSRect _f; NSInteger _z; }
+ (id)customItemWithFrame:(NSRect)f; + (id)customItemWithFrame:(NSRect)f zIndex:(NSInteger)z; - (NSRect)frame; - (NSInteger)zIndex;
@end

@interface NSTextList : NSObject <NSCopying> { @public NSString *_fmt; NSUInteger _opts; NSInteger _start; }
- (id)initWithMarkerFormat:(NSString *)f options:(NSUInteger)o; - (id)initWithMarkerFormat:(NSString *)f options:(NSUInteger)o startingItemNumber:(NSInteger)n; - (NSString *)markerFormat; - (NSUInteger)listOptions;
- (NSInteger)startingItemNumber; - (void)setStartingItemNumber:(NSInteger)n; - (BOOL)isOrdered; - (NSString *)markerForItemNumber:(NSInteger)n; + (BOOL)includesTextListMarkers;
@end

@interface NSWindowTabGroup : NSObject { @public NSMutableArray *_wins; NSString *_ident; BOOL _overview; NSWindow *_sel; }
- (NSString *)identifier; - (NSArray *)windows; - (BOOL)isOverviewVisible; - (void)setOverviewVisible:(BOOL)f; - (BOOL)isTabBarVisible; - (NSWindow *)selectedWindow; - (void)setSelectedWindow:(NSWindow *)w;
- (void)addWindow:(NSWindow *)w; - (void)insertWindow:(NSWindow *)w atIndex:(NSInteger)i; - (void)removeWindow:(NSWindow *)w;
@end

@interface NSComboButton : NSControl { @public NSString *_t; NSImage *_img; NSInteger _scaling, _style; NSMenu *_menu; id _tgt; SEL _act; }
+ (id)comboButtonWithTitle:(NSString *)t menu:(NSMenu *)m target:(id)tg action:(SEL)a; + (id)comboButtonWithImage:(NSImage *)i menu:(NSMenu *)m target:(id)tg action:(SEL)a;
+ (id)comboButtonWithTitle:(NSString *)t image:(NSImage *)i menu:(NSMenu *)m target:(id)tg action:(SEL)a;
- (NSString *)title; - (void)setTitle:(NSString *)t; - (NSImage *)image; - (void)setImage:(NSImage *)i; - (NSInteger)imageScaling; - (void)setImageScaling:(NSInteger)s; - (NSInteger)style; - (void)setStyle:(NSInteger)s;
@end

@interface NSCollectionViewLayoutInvalidationContext : NSObject { @public BOOL _all, _counts; NSMutableSet *_items, *_supp, *_dec; NSPoint _off; NSSize _sz; }
- (void)invalidateEverything; - (void)invalidateDataSourceCounts; - (void)invalidateItemsAtIndexPaths:(NSSet *)p; - (void)invalidateSupplementaryElementsOfKind:(NSString *)k atIndexPaths:(NSSet *)p;
- (void)invalidateDecorationElementsOfKind:(NSString *)k atIndexPaths:(NSSet *)p; - (NSSet *)invalidatedItemIndexPaths; - (NSSet *)invalidatedSupplementaryIndexPaths; - (NSSet *)invalidatedDecorationIndexPaths;
- (NSPoint)contentOffsetAdjustment; - (void)setContentOffsetAdjustment:(NSPoint)o; - (NSSize)contentSizeAdjustment; - (void)setContentSizeAdjustment:(NSSize)s;
@end

@interface NSScrubberLayout : NSObject { @public id _scrubber; NSRect _vis; }
+ (Class)layoutAttributesClass; - (id)scrubber; - (NSRect)visibleRect; - (void)invalidateLayout; - (void)prepareLayout; - (NSSize)scrubberContentSize; - (id)layoutAttributesForItemAtIndex:(NSInteger)i;
- (NSSet *)layoutAttributesForItemsInRect:(NSRect)r; - (BOOL)shouldInvalidateLayoutForSelectionChange; - (BOOL)shouldInvalidateLayoutForHighlightChange;
- (BOOL)shouldInvalidateLayoutForChangeFromVisibleRect:(NSRect)a toVisibleRect:(NSRect)b; - (BOOL)automaticallyMirrorsInRightToLeftLayout;
@end

@interface NSHelpManager : NSObject { @public NSMapTable *_help; }
+ (NSHelpManager *)sharedHelpManager; + (BOOL)isContextHelpModeActive; + (void)setContextHelpModeActive:(BOOL)f; - (void)setContextHelp:(NSAttributedString *)h forObject:(id)o; - (void)removeContextHelpForObject:(id)o;
- (NSAttributedString *)contextHelpForObject:(id)o; - (BOOL)showContextHelpForObject:(id)o locationHint:(NSPoint)p; - (void)openHelpAnchor:(NSString *)a inBook:(NSString *)b; - (BOOL)findString:(NSString *)s inBook:(NSString *)b;
- (void)registerBooksInBundle:(NSBundle *)b;
@end

@interface NSFontManager (XEFMisc2)
- (NSDictionary *)convertAttributes:(NSDictionary *)a; - (NSArray *)availableFontNamesMatchingFontDescriptor:(NSFontDescriptor *)d; - (NSArray *)collectionNames; - (NSArray *)fontDescriptorsInCollection:(NSString *)n;
- (BOOL)addCollection:(NSString *)n options:(NSInteger)o; - (BOOL)removeCollection:(NSString *)n; - (void)addFontDescriptors:(NSArray *)d toCollection:(NSString *)n; - (void)removeFontDescriptor:(NSFontDescriptor *)d fromCollection:(NSString *)n;
- (NSUInteger)convertFontTraits:(NSUInteger)t; - (BOOL)validateMenuItem:(NSMenuItem *)m;
@end
@interface NSPrintInfo (XEFMisc2)
- (void)setPaperName:(NSString *)n; - (id)printer; - (void)setPrinter:(id)p; - (NSString *)localizedPaperName; - (void *)PMPrintSession; - (void *)PMPageFormat; - (void *)PMPrintSettings;
- (void)takeSettingsFromPDFInfo:(NSPDFInfo *)i; + (void)setDefaultPrinter:(id)p; + (NSSize)sizeForPaperName:(NSString *)n;
@end
@interface NSOpenPanel (XEFMisc2)
- (BOOL)resolvesAliases; - (void)setResolvesAliases:(BOOL)f; - (BOOL)canResolveUbiquitousConflicts; - (void)setCanResolveUbiquitousConflicts:(BOOL)f; - (BOOL)canDownloadUbiquitousContents; - (void)setCanDownloadUbiquitousContents:(BOOL)f;
- (BOOL)isAccessoryViewDisclosed; - (void)setAccessoryViewDisclosed:(BOOL)f;
@end
