/* More small model classes: grid layout, compositional section, NSPathCell extras, NSPageLayout, symbol configuration, diffable table data source.
   Matched against macOS by tests/darwin/mac/appkit_misc6.m. */
#import "AppKitMisc2.h"
#include <objc/runtime.h>
#include <objc/message.h>

@implementation NSCollectionViewGridLayout
- (id)init { self = [super init]; return self; }
- (NSEdgeInsets)margins { return _m; } - (void)setMargins:(NSEdgeInsets)m { _m = m; [self invalidateLayout]; }
- (CGFloat)minimumInteritemSpacing { return _inter; } - (void)setMinimumInteritemSpacing:(CGFloat)v { _inter = v; [self invalidateLayout]; }
- (CGFloat)minimumLineSpacing { return _line; } - (void)setMinimumLineSpacing:(CGFloat)v { _line = v; [self invalidateLayout]; }
- (NSUInteger)maximumNumberOfRows { return _rows; } - (void)setMaximumNumberOfRows:(NSUInteger)n { _rows = n; [self invalidateLayout]; }
- (NSUInteger)maximumNumberOfColumns { return _cols; } - (void)setMaximumNumberOfColumns:(NSUInteger)n { _cols = n; [self invalidateLayout]; }
- (NSSize)minimumItemSize { return _min; } - (void)setMinimumItemSize:(NSSize)s { _min = s; [self invalidateLayout]; }
- (NSSize)maximumItemSize { return _max; } - (void)setMaximumItemSize:(NSSize)s { _max = s; [self invalidateLayout]; }
- (NSArray *)backgroundColors { return _bgs ? _bgs : [NSArray array]; } - (void)setBackgroundColors:(NSArray *)c { [c retain]; [_bgs release]; _bgs = c; }
- (void)dealloc { [_bgs release]; [super dealloc]; }
@end

@implementation NSCollectionLayoutSection
+ (id)sectionWithGroup:(id)g { NSCollectionLayoutSection *s = [[[self alloc] init] autorelease]; s->_group = [g retain]; s->_follow = YES; return s; }
- (id)init { self = [super init]; _follow = YES; return self; }
- (void)dealloc { [_group release]; [_bound release]; [_dec release]; [_handler release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { NSCollectionLayoutSection *s = [[[self class] alloc] init]; s->_group = [_group retain]; s->_ins = _ins; s->_gap = _gap; s->_orth = _orth; s->_bound = [_bound copy]; s->_dec = [_dec copy]; s->_follow = _follow; s->_handler = [_handler copy]; return s; }
- (NSDirectionalEdgeInsets)contentInsets { return _ins; } - (void)setContentInsets:(NSDirectionalEdgeInsets)i { _ins = i; }
- (CGFloat)interGroupSpacing { return _gap; } - (void)setInterGroupSpacing:(CGFloat)v { _gap = v; }
- (NSInteger)orthogonalScrollingBehavior { return _orth; } - (void)setOrthogonalScrollingBehavior:(NSInteger)b { _orth = b; }
- (NSArray *)boundarySupplementaryItems { return _bound ? _bound : [NSArray array]; } - (void)setBoundarySupplementaryItems:(NSArray *)a { [a retain]; [_bound release]; _bound = a; }
- (BOOL)supplementariesFollowContentInsets { return _follow; } - (void)setSupplementariesFollowContentInsets:(BOOL)f { _follow = f; }
- (id)visibleItemsInvalidationHandler { return _handler; } - (void)setVisibleItemsInvalidationHandler:(id)h { id c = h ? [h copy] : nil; [_handler release]; _handler = c; }
- (NSArray *)decorationItems { return _dec ? _dec : [NSArray array]; } - (void)setDecorationItems:(NSArray *)a { [a retain]; [_dec release]; _dec = a; }
@end

@implementation NSPathCell (XEFMisc)
- (NSArray *)allowedTypes { return objc_getAssociatedObject(self, "xef.at"); } - (void)setAllowedTypes:(NSArray *)t { objc_setAssociatedObject(self, "xef.at", [[t copy] autorelease], OBJC_ASSOCIATION_RETAIN); }
+ (Class)pathComponentCellClass { return objc_getClass("NSPathComponentCell"); }
- (NSRect)rectOfPathComponentCell:(id)c withFrame:(NSRect)f inView:(NSView *)v { NSUInteger n = [[self pathComponentCells] count], i = [[self pathComponentCells] indexOfObject:c]; if (!n || i == NSNotFound) return NSZeroRect; CGFloat w = f.size.width / n; return NSMakeRect(f.origin.x + i * w, f.origin.y, w, f.size.height); }
- (id)pathComponentCellAtPoint:(NSPoint)p withFrame:(NSRect)f inView:(NSView *)v { NSArray *a = [self pathComponentCells]; if (![a count] || !NSPointInRect(p, f)) return nil; NSUInteger i = (NSUInteger)((p.x - f.origin.x) / (f.size.width / [a count])); return i < [a count] ? [a objectAtIndex:i] : nil; }
- (id)clickedPathComponentCell { return objc_getAssociatedObject(self, "xef.clk"); }
- (void)mouseEntered:(NSEvent *)e withFrame:(NSRect)f inView:(NSView *)v {} - (void)mouseExited:(NSEvent *)e withFrame:(NSRect)f inView:(NSView *)v {}
- (SEL)doubleAction { NSString *s = objc_getAssociatedObject(self, "xef.da"); return s ? NSSelectorFromString(s) : NULL; } - (void)setDoubleAction:(SEL)a { objc_setAssociatedObject(self, "xef.da", a ? NSStringFromSelector(a) : nil, OBJC_ASSOCIATION_RETAIN); }
- (NSColor *)backgroundColor { return objc_getAssociatedObject(self, "xef.bg"); } - (void)setBackgroundColor:(NSColor *)c { objc_setAssociatedObject(self, "xef.bg", c, OBJC_ASSOCIATION_RETAIN); }
- (void)setPlaceholderAttributedString:(NSAttributedString *)s { [self setPlaceholderString:[s string]]; }
- (BOOL)validateMenuItem:(NSMenuItem *)m { return YES; }
@end

@implementation NSPageLayout
+ (NSPageLayout *)pageLayout { return [[[self alloc] init] autorelease]; }
- (id)init { self = [super init]; _acc = [[NSMutableArray alloc] init]; return self; }
- (void)dealloc { [_acc release]; [_accView release]; [_pi release]; [super dealloc]; }
- (void)addAccessoryController:(id)c { [_acc addObject:c]; } - (void)removeAccessoryController:(id)c { [_acc removeObject:c]; } - (NSArray *)accessoryControllers { return [NSArray arrayWithArray:_acc]; }
- (void)beginSheetUsingPrintInfo:(NSPrintInfo *)pi onWindow:(NSWindow *)w completionHandler:(void (^)(NSInteger))h { [pi retain]; [_pi release]; _pi = pi; if (h) h(0); }
- (void)beginSheetWithPrintInfo:(NSPrintInfo *)pi modalForWindow:(NSWindow *)w delegate:(id)d didEndSelector:(SEL)s contextInfo:(void *)ci { [pi retain]; [_pi release]; _pi = pi; if (d && s && [d respondsToSelector:s]) { void (*f)(id, SEL, id, NSInteger, void *) = (void (*)(id, SEL, id, NSInteger, void *))objc_msgSend; f(d, s, self, 0, ci); } }
- (NSInteger)runModalWithPrintInfo:(NSPrintInfo *)pi { [pi retain]; [_pi release]; _pi = pi; return 0; } - (NSInteger)runModal { return [self runModalWithPrintInfo:[NSPrintInfo sharedPrintInfo]]; }
- (NSPrintInfo *)printInfo { return _pi; } - (void)setAccessoryView:(NSView *)v { [v retain]; [_accView release]; _accView = v; } - (NSView *)accessoryView { return _accView; }
- (void)readPrintInfo {} - (void)writePrintInfo {}
@end

@implementation NSImageSymbolConfiguration
+ (id)_make:(NSDictionary *)d { NSImageSymbolConfiguration *c = [[[self alloc] init] autorelease]; c->_d = [d copy]; return c; }
- (void)dealloc { [_d release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
+ (id)configurationWithPointSize:(CGFloat)p weight:(CGFloat)w scale:(NSInteger)s { return [self _make:@{@"pt": @(p), @"w": @(w), @"scale": @(s)}]; }
+ (id)configurationWithPointSize:(CGFloat)p weight:(CGFloat)w { return [self _make:@{@"pt": @(p), @"w": @(w)}]; }
+ (id)configurationWithTextStyle:(NSString *)t scale:(NSInteger)s { return [self _make:@{@"style": t ? t : @"", @"scale": @(s)}]; }
+ (id)configurationWithTextStyle:(NSString *)t { return [self _make:@{@"style": t ? t : @""}]; }
+ (id)configurationWithScale:(NSInteger)s { return [self _make:@{@"scale": @(s)}]; }
+ (id)configurationPreferringMonochrome { return [self _make:@{@"mono": @YES}]; } + (id)configurationPreferringHierarchical { return [self _make:@{@"hier": @YES}]; } + (id)configurationPreferringMulticolor { return [self _make:@{@"multi": @YES}]; }
+ (id)configurationWithHierarchicalColor:(NSColor *)c { return [self _make:@{@"hier": c}]; } + (id)configurationWithPaletteColors:(NSArray *)c { return [self _make:@{@"palette": c}]; }
+ (id)configurationWithVariableValueMode:(NSInteger)m { return [self _make:@{@"vv": @(m)}]; } + (id)configurationWithColorRenderingMode:(NSInteger)m { return [self _make:@{@"crm": @(m)}]; }
- (id)configurationByApplyingConfiguration:(NSImageSymbolConfiguration *)c { NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:_d]; [d addEntriesFromDictionary:c->_d]; return [[self class] _make:d]; }
@end

@implementation NSTableViewDiffableDataSource
- (id)initWithTableView:(NSTableView *)t cellProvider:(id)p {
  self = [super init]; _tv = t; _provider = [p copy]; _snap = [[NSDiffableDataSourceSnapshot alloc] init]; _anim = 1;
  [t setDataSource:self]; [t setDelegate:self]; return self; }
- (void)dealloc { [_provider release]; [_rowProv release]; [_hdrProv release]; [_snap release]; [super dealloc]; }
- (NSDiffableDataSourceSnapshot *)snapshot { return [[_snap copy] autorelease]; }
- (void)applySnapshot:(NSDiffableDataSourceSnapshot *)s animatingDifferences:(BOOL)a { [self applySnapshot:s animatingDifferences:a completion:nil]; }
- (void)applySnapshot:(NSDiffableDataSourceSnapshot *)s animatingDifferences:(BOOL)a completion:(void (^)(void))c { [s retain]; [_snap release]; _snap = [s copy]; [s release]; [_tv reloadData]; if (c) c(); }
- (id)itemIdentifierForRow:(NSInteger)r { NSArray *a = [_snap itemIdentifiers]; return r >= 0 && r < (NSInteger)[a count] ? [a objectAtIndex:(NSUInteger)r] : nil; }
- (NSInteger)rowForItemIdentifier:(id)i { NSUInteger k = [[_snap itemIdentifiers] indexOfObject:i]; return k == NSNotFound ? NSNotFound : (NSInteger)k; }
- (id)sectionIdentifierForRow:(NSInteger)r { return nil; } - (NSInteger)rowForSectionIdentifier:(id)i { return NSNotFound; }
- (id)rowViewProvider { return _rowProv; } - (void)setRowViewProvider:(id)p { id c = p ? [p copy] : nil; [_rowProv release]; _rowProv = c; }
- (id)sectionHeaderViewProvider { return _hdrProv; } - (void)setSectionHeaderViewProvider:(id)p { id c = p ? [p copy] : nil; [_hdrProv release]; _hdrProv = c; }
- (NSInteger)defaultRowAnimation { return _anim; } - (void)setDefaultRowAnimation:(NSInteger)a { _anim = a; }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return [_snap numberOfItems]; }
- (NSView *)tableView:(NSTableView *)t viewForTableColumn:(NSTableColumn *)c row:(NSInteger)r {
  if (!_provider) return nil; NSView *(^p)(NSTableView *, NSTableColumn *, NSInteger, id) = (NSView *(^)(NSTableView *, NSTableColumn *, NSInteger, id))_provider; return p(t, c, r, [self itemIdentifierForRow:r]); }
@end
