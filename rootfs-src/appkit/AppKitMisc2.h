/* More small model classes (AppKitMisc2.m). */
#import "AppKitMisc.h"
#import "AppKitTable.h"
typedef struct { CGFloat top, leading, bottom, trailing; } NSDirectionalEdgeInsets;
static inline NSDirectionalEdgeInsets NSDirectionalEdgeInsetsMake(CGFloat t, CGFloat l, CGFloat b, CGFloat r) { NSDirectionalEdgeInsets i = { t, l, b, r }; return i; }

@interface NSCollectionViewGridLayout : NSCollectionViewLayout { @public NSEdgeInsets _m; CGFloat _inter, _line; NSUInteger _rows, _cols; NSSize _min, _max; NSArray *_bgs; }
- (NSEdgeInsets)margins; - (void)setMargins:(NSEdgeInsets)m; - (CGFloat)minimumInteritemSpacing; - (void)setMinimumInteritemSpacing:(CGFloat)v; - (CGFloat)minimumLineSpacing; - (void)setMinimumLineSpacing:(CGFloat)v;
- (NSUInteger)maximumNumberOfRows; - (void)setMaximumNumberOfRows:(NSUInteger)n; - (NSUInteger)maximumNumberOfColumns; - (void)setMaximumNumberOfColumns:(NSUInteger)n;
- (NSSize)minimumItemSize; - (void)setMinimumItemSize:(NSSize)s; - (NSSize)maximumItemSize; - (void)setMaximumItemSize:(NSSize)s; - (NSArray *)backgroundColors; - (void)setBackgroundColors:(NSArray *)c;
@end

@interface NSCollectionLayoutSection : NSObject <NSCopying> { @public id _group; NSDirectionalEdgeInsets _ins; CGFloat _gap; NSInteger _orth; NSArray *_bound, *_dec; BOOL _follow; id _handler; }
+ (id)sectionWithGroup:(id)g; - (NSDirectionalEdgeInsets)contentInsets; - (void)setContentInsets:(NSDirectionalEdgeInsets)i; - (CGFloat)interGroupSpacing; - (void)setInterGroupSpacing:(CGFloat)v;
- (NSInteger)orthogonalScrollingBehavior; - (void)setOrthogonalScrollingBehavior:(NSInteger)b; - (NSArray *)boundarySupplementaryItems; - (void)setBoundarySupplementaryItems:(NSArray *)a;
- (BOOL)supplementariesFollowContentInsets; - (void)setSupplementariesFollowContentInsets:(BOOL)f; - (id)visibleItemsInvalidationHandler; - (void)setVisibleItemsInvalidationHandler:(id)h; - (NSArray *)decorationItems; - (void)setDecorationItems:(NSArray *)a;
@end

@interface NSPathCell (XEFMisc)
- (NSArray *)allowedTypes; - (void)setAllowedTypes:(NSArray *)t; + (Class)pathComponentCellClass; - (NSRect)rectOfPathComponentCell:(id)c withFrame:(NSRect)f inView:(NSView *)v;
- (id)pathComponentCellAtPoint:(NSPoint)p withFrame:(NSRect)f inView:(NSView *)v; - (id)clickedPathComponentCell; - (void)mouseEntered:(NSEvent *)e withFrame:(NSRect)f inView:(NSView *)v; - (void)mouseExited:(NSEvent *)e withFrame:(NSRect)f inView:(NSView *)v;
- (SEL)doubleAction; - (void)setDoubleAction:(SEL)a; - (NSColor *)backgroundColor; - (void)setBackgroundColor:(NSColor *)c; - (void)setPlaceholderAttributedString:(NSAttributedString *)s; - (BOOL)validateMenuItem:(NSMenuItem *)m;
@end

@interface NSPageLayout : NSObject { @public NSMutableArray *_acc; NSView *_accView; NSPrintInfo *_pi; }
+ (NSPageLayout *)pageLayout; - (void)addAccessoryController:(id)c; - (void)removeAccessoryController:(id)c; - (NSArray *)accessoryControllers;
- (void)beginSheetUsingPrintInfo:(NSPrintInfo *)pi onWindow:(NSWindow *)w completionHandler:(void (^)(NSInteger))h;
- (void)beginSheetWithPrintInfo:(NSPrintInfo *)pi modalForWindow:(NSWindow *)w delegate:(id)d didEndSelector:(SEL)s contextInfo:(void *)ci;
- (NSInteger)runModalWithPrintInfo:(NSPrintInfo *)pi; - (NSInteger)runModal; - (NSPrintInfo *)printInfo; - (void)setAccessoryView:(NSView *)v; - (NSView *)accessoryView; - (void)readPrintInfo; - (void)writePrintInfo;
@end

@interface NSImageSymbolConfiguration : NSObject <NSCopying> { @public NSDictionary *_d; }
+ (id)configurationWithPointSize:(CGFloat)p weight:(CGFloat)w scale:(NSInteger)s; + (id)configurationWithPointSize:(CGFloat)p weight:(CGFloat)w; + (id)configurationWithTextStyle:(NSString *)t scale:(NSInteger)s; + (id)configurationWithTextStyle:(NSString *)t;
+ (id)configurationWithScale:(NSInteger)s; + (id)configurationPreferringMonochrome; + (id)configurationPreferringHierarchical; + (id)configurationWithHierarchicalColor:(NSColor *)c; + (id)configurationWithPaletteColors:(NSArray *)c;
+ (id)configurationPreferringMulticolor; + (id)configurationWithVariableValueMode:(NSInteger)m; + (id)configurationWithColorRenderingMode:(NSInteger)m; - (id)configurationByApplyingConfiguration:(NSImageSymbolConfiguration *)c;
@end

@interface NSTableViewDiffableDataSource : NSObject  { @public NSTableView *_tv; id _provider, _rowProv, _hdrProv; NSDiffableDataSourceSnapshot *_snap; NSInteger _anim; }
- (id)initWithTableView:(NSTableView *)t cellProvider:(id)p; - (NSDiffableDataSourceSnapshot *)snapshot; - (void)applySnapshot:(NSDiffableDataSourceSnapshot *)s animatingDifferences:(BOOL)a;
- (void)applySnapshot:(NSDiffableDataSourceSnapshot *)s animatingDifferences:(BOOL)a completion:(void (^)(void))c; - (id)itemIdentifierForRow:(NSInteger)r; - (NSInteger)rowForItemIdentifier:(id)i;
- (id)sectionIdentifierForRow:(NSInteger)r; - (NSInteger)rowForSectionIdentifier:(id)i; - (id)rowViewProvider; - (void)setRowViewProvider:(id)p; - (id)sectionHeaderViewProvider; - (void)setSectionHeaderViewProvider:(id)p;
- (NSInteger)defaultRowAnimation; - (void)setDefaultRowAnimation:(NSInteger)a;
@end
