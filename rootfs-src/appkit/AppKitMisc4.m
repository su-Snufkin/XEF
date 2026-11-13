/* Compositional layout model, text lists, tab groups, combo button, help manager, font collections, print info extras.
   Matched against macOS by tests/darwin/mac/appkit_misc8.m. */
#import "AppKitMisc4.h"
#include <objc/runtime.h>

/* ---- compositional layout ---- */
@implementation NSCollectionLayoutDimension
+ (id)_k:(NSInteger)k v:(CGFloat)v { NSCollectionLayoutDimension *d = [[[self alloc] init] autorelease]; d->_kind = k; d->_v = v; return d; }
+ (id)fractionalWidthDimension:(CGFloat)v { return [self _k:0 v:v]; } + (id)fractionalHeightDimension:(CGFloat)v { return [self _k:1 v:v]; }
+ (id)absoluteDimension:(CGFloat)v { return [self _k:2 v:v]; } + (id)estimatedDimension:(CGFloat)v { return [self _k:3 v:v]; }
- (BOOL)isFractionalWidth { return _kind == 0; } - (BOOL)isFractionalHeight { return _kind == 1; } - (BOOL)isAbsolute { return _kind == 2; } - (BOOL)isEstimated { return _kind == 3; } - (CGFloat)dimension { return _v; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
@end
@implementation NSCollectionLayoutSize
+ (id)sizeWithWidthDimension:(NSCollectionLayoutDimension *)w heightDimension:(NSCollectionLayoutDimension *)h { NSCollectionLayoutSize *s = [[[self alloc] init] autorelease]; s->_w = [w retain]; s->_h = [h retain]; return s; }
- (void)dealloc { [_w release]; [_h release]; [super dealloc]; }
- (NSCollectionLayoutDimension *)widthDimension { return _w; } - (NSCollectionLayoutDimension *)heightDimension { return _h; }
- (id)copyWithZone:(NSZone *)z { return [[NSCollectionLayoutSize sizeWithWidthDimension:_w heightDimension:_h] retain]; }
@end
@implementation NSCollectionLayoutSpacing
+ (id)flexibleSpacing:(CGFloat)v { NSCollectionLayoutSpacing *s = [[[self alloc] init] autorelease]; s->_flex = YES; s->_v = v; return s; }
+ (id)fixedSpacing:(CGFloat)v { NSCollectionLayoutSpacing *s = [[[self alloc] init] autorelease]; s->_v = v; return s; }
- (CGFloat)spacing { return _v; } - (BOOL)isFlexibleSpacing { return _flex; } - (BOOL)isFixedSpacing { return !_flex; }
- (id)copyWithZone:(NSZone *)z { NSCollectionLayoutSpacing *s = [[[self class] alloc] init]; s->_flex = _flex; s->_v = _v; return s; }
@end
@implementation NSCollectionLayoutEdgeSpacing
+ (id)spacingForLeading:(NSCollectionLayoutSpacing *)l top:(NSCollectionLayoutSpacing *)t trailing:(NSCollectionLayoutSpacing *)r bottom:(NSCollectionLayoutSpacing *)b {
  NSCollectionLayoutEdgeSpacing *e = [[[self alloc] init] autorelease]; e->_l = [l retain]; e->_t = [t retain]; e->_r = [r retain]; e->_b = [b retain]; return e; }
- (void)dealloc { [_l release]; [_t release]; [_r release]; [_b release]; [super dealloc]; }
- (NSCollectionLayoutSpacing *)leading { return _l; } - (NSCollectionLayoutSpacing *)top { return _t; } - (NSCollectionLayoutSpacing *)trailing { return _r; } - (NSCollectionLayoutSpacing *)bottom { return _b; }
- (id)copyWithZone:(NSZone *)z { return [[NSCollectionLayoutEdgeSpacing spacingForLeading:_l top:_t trailing:_r bottom:_b] retain]; }
@end
@implementation NSCollectionLayoutAnchor
+ (id)layoutAnchorWithEdges:(NSUInteger)e { return [self layoutAnchorWithEdges:e absoluteOffset:NSZeroPoint]; }
+ (id)layoutAnchorWithEdges:(NSUInteger)e absoluteOffset:(NSPoint)o { NSCollectionLayoutAnchor *a = [[[self alloc] init] autorelease]; a->_edges = e; a->_off = o; a->_mode = 0; return a; }
+ (id)layoutAnchorWithEdges:(NSUInteger)e fractionalOffset:(NSPoint)o { NSCollectionLayoutAnchor *a = [[[self alloc] init] autorelease]; a->_edges = e; a->_off = o; a->_mode = 1; return a; }
- (NSUInteger)edges { return _edges; } - (NSPoint)offset { return _off; } - (BOOL)isAbsoluteOffset { return _mode == 0; } - (BOOL)isFractionalOffset { return _mode == 1; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
@end
@implementation NSCollectionLayoutItem
+ (id)itemWithLayoutSize:(NSCollectionLayoutSize *)s { return [self itemWithLayoutSize:s supplementaryItems:nil]; }
+ (id)itemWithLayoutSize:(NSCollectionLayoutSize *)s supplementaryItems:(NSArray *)a { NSCollectionLayoutItem *i = [[[self alloc] init] autorelease]; i->_size = [s copy]; i->_supp = [a copy]; return i; }
- (id)init { self = [super init]; _es = [[NSCollectionLayoutEdgeSpacing spacingForLeading:nil top:nil trailing:nil bottom:nil] retain]; return self; }
- (void)dealloc { [_size release]; [_es release]; [_supp release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { NSCollectionLayoutItem *c = [[[self class] allocWithZone:z] init]; c->_size = [_size copy]; c->_ci = _ci; [c->_es release]; c->_es = [_es copy]; c->_supp = [_supp copy]; return c; }
- (NSDirectionalEdgeInsets)contentInsets { return _ci; } - (void)setContentInsets:(NSDirectionalEdgeInsets)i { _ci = i; }
- (NSCollectionLayoutEdgeSpacing *)edgeSpacing { return _es; } - (void)setEdgeSpacing:(NSCollectionLayoutEdgeSpacing *)e { id c = [e copy]; [_es release]; _es = c; }
- (NSCollectionLayoutSize *)layoutSize { return _size; } - (NSArray *)supplementaryItems { return _supp ? _supp : [NSArray array]; }
@end
@implementation NSCollectionLayoutSupplementaryItem
+ (id)supplementaryItemWithLayoutSize:(NSCollectionLayoutSize *)s elementKind:(NSString *)k containerAnchor:(NSCollectionLayoutAnchor *)a { return [self supplementaryItemWithLayoutSize:s elementKind:k containerAnchor:a itemAnchor:nil]; }
+ (id)supplementaryItemWithLayoutSize:(NSCollectionLayoutSize *)s elementKind:(NSString *)k containerAnchor:(NSCollectionLayoutAnchor *)a itemAnchor:(NSCollectionLayoutAnchor *)i {
  NSCollectionLayoutSupplementaryItem *x = [[[self alloc] init] autorelease]; x->_size = [s copy]; x->_kind = [k copy]; x->_ca = [a retain]; x->_ia = [i retain]; x->_z = 1; return x; }
- (void)dealloc { [_kind release]; [_ca release]; [_ia release]; [super dealloc]; }
- (NSInteger)zIndex { return _z; } - (void)setZIndex:(NSInteger)z { _z = z; } - (NSString *)elementKind { return _kind; } - (NSCollectionLayoutAnchor *)containerAnchor { return _ca; } - (NSCollectionLayoutAnchor *)itemAnchor { return _ia; }
@end
@implementation NSCollectionLayoutBoundarySupplementaryItem
+ (id)boundarySupplementaryItemWithLayoutSize:(NSCollectionLayoutSize *)s elementKind:(NSString *)k alignment:(NSUInteger)a { return [self boundarySupplementaryItemWithLayoutSize:s elementKind:k alignment:a absoluteOffset:NSZeroPoint]; }
+ (id)boundarySupplementaryItemWithLayoutSize:(NSCollectionLayoutSize *)s elementKind:(NSString *)k alignment:(NSUInteger)a absoluteOffset:(NSPoint)o {
  NSCollectionLayoutBoundarySupplementaryItem *x = [[[self alloc] init] autorelease]; x->_size = [s copy]; x->_kind = [k copy]; x->_z = 1; x->_ext = YES; x->_align = a; x->_off = o; return x; }
- (BOOL)extendsBoundary { return _ext; } - (void)setExtendsBoundary:(BOOL)f { _ext = f; } - (BOOL)pinToVisibleBounds { return _pin; } - (void)setPinToVisibleBounds:(BOOL)f { _pin = f; }
- (NSUInteger)alignment { return _align; } - (NSPoint)offset { return _off; }
@end
@implementation NSCollectionLayoutDecorationItem
+ (id)backgroundDecorationItemWithElementKind:(NSString *)k { NSCollectionLayoutDecorationItem *d = [[[self alloc] init] autorelease]; d->_kind = [k copy]; return d; }
- (void)dealloc { [_kind release]; [super dealloc]; }
- (NSInteger)zIndex { return _z; } - (void)setZIndex:(NSInteger)z { _z = z; } - (NSString *)elementKind { return _kind; }
@end
@implementation NSCollectionLayoutGroup
+ (id)_g:(NSCollectionLayoutSize *)s subs:(NSArray *)a { NSCollectionLayoutGroup *g = [[[self alloc] init] autorelease]; g->_size = [s copy]; g->_subs = [a copy]; g->_inter = [[NSCollectionLayoutSpacing fixedSpacing:0] retain]; return g; }
+ (id)horizontalGroupWithLayoutSize:(NSCollectionLayoutSize *)s subitem:(NSCollectionLayoutItem *)i count:(NSInteger)n { return [self _g:s subs:i ? [NSArray arrayWithObject:i] : nil]; }
+ (id)horizontalGroupWithLayoutSize:(NSCollectionLayoutSize *)s subitems:(NSArray *)a { return [self _g:s subs:a]; }
+ (id)verticalGroupWithLayoutSize:(NSCollectionLayoutSize *)s subitem:(NSCollectionLayoutItem *)i count:(NSInteger)n { return [self _g:s subs:i ? [NSArray arrayWithObject:i] : nil]; }
+ (id)verticalGroupWithLayoutSize:(NSCollectionLayoutSize *)s subitems:(NSArray *)a { return [self _g:s subs:a]; }
+ (id)customGroupWithLayoutSize:(NSCollectionLayoutSize *)s itemProvider:(id)p { NSCollectionLayoutGroup *g = [self _g:s subs:nil]; g->_provider = [p copy]; return g; }
- (void)dealloc { [_subs release]; [_inter release]; [_provider release]; [super dealloc]; }
- (NSArray *)supplementaryItems { return _supp ? _supp : [NSArray array]; } - (void)setSupplementaryItems:(NSArray *)a { id c = [a copy]; [_supp release]; _supp = c; }
- (NSCollectionLayoutSpacing *)interItemSpacing { return _inter; } - (void)setInterItemSpacing:(NSCollectionLayoutSpacing *)s { id c = [s copy]; [_inter release]; _inter = c; }
- (NSArray *)subitems { return _subs ? _subs : [NSArray array]; }
- (NSString *)visualDescription { return [NSString stringWithFormat:@"+--------------------+\n| group (%lu subitems) |\n+--------------------+", (unsigned long)[[self subitems] count]]; }
@end
@implementation NSCollectionLayoutGroupCustomItem
+ (id)customItemWithFrame:(NSRect)f { return [self customItemWithFrame:f zIndex:0]; }
+ (id)customItemWithFrame:(NSRect)f zIndex:(NSInteger)z { NSCollectionLayoutGroupCustomItem *c = [[[self alloc] init] autorelease]; c->_f = f; c->_z = z; return c; }
- (NSRect)frame { return _f; } - (NSInteger)zIndex { return _z; } - (id)copyWithZone:(NSZone *)z { return [self retain]; }
@end

/* ---- NSTextList ---- */
static NSString *Roman(NSInteger n, BOOL upper) {
  static const int v[] = { 1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1 }; static const char *r[] = { "m", "cm", "d", "cd", "c", "xc", "l", "xl", "x", "ix", "v", "iv", "i" };
  NSMutableString *s = [NSMutableString string]; for (int i = 0; i < 13 && n > 0; i++) while (n >= v[i]) { [s appendString:[NSString stringWithUTF8String:r[i]]]; n -= v[i]; } return upper ? [s uppercaseString] : s; }
@implementation NSTextList
- (id)initWithMarkerFormat:(NSString *)f options:(NSUInteger)o { return [self initWithMarkerFormat:f options:o startingItemNumber:1]; }
- (id)initWithMarkerFormat:(NSString *)f options:(NSUInteger)o startingItemNumber:(NSInteger)n { self = [super init]; _fmt = [f copy]; _opts = o; _start = n; return self; }
- (id)initWithCoder:(NSCoder *)c { return [self initWithMarkerFormat:@"{decimal}" options:0]; }
- (void)dealloc { [_fmt release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [[NSTextList alloc] initWithMarkerFormat:_fmt options:_opts startingItemNumber:_start]; }
- (NSString *)markerFormat { return _fmt; } - (NSUInteger)listOptions { return _opts; } - (NSInteger)startingItemNumber { return _start; } - (void)setStartingItemNumber:(NSInteger)n { _start = n; }
- (BOOL)isOrdered { for (NSString *k in [NSArray arrayWithObjects:@"{decimal}", @"{lower-alpha}", @"{upper-alpha}", @"{lower-roman}", @"{upper-roman}", @"{lower-hexadecimal}", @"{upper-hexadecimal}", @"{octal}", @"{lower-latin}", @"{upper-latin}", nil]) if ([_fmt isEqualToString:k]) return YES; return NO; }
- (NSString *)markerForItemNumber:(NSInteger)n {
  NSString *f = _fmt;
  if ([f isEqualToString:@"{decimal}"]) return [NSString stringWithFormat:@"%ld", (long)n];
  if ([f isEqualToString:@"{disc}"]) return @"•"; if ([f isEqualToString:@"{circle}"]) return @"◦"; if ([f isEqualToString:@"{square}"]) return @"▪";
  if ([f isEqualToString:@"{hyphen}"]) return @"⁃"; if ([f isEqualToString:@"{check}"]) return @"✓"; if ([f isEqualToString:@"{box}"]) return @"▫"; if ([f isEqualToString:@"{diamond}"]) return @"◆";
  if ([f hasSuffix:@"-alpha}"] || [f hasSuffix:@"-latin}"]) { unichar c = (unichar)('a' + ((n - 1) % 26 + 26) % 26); NSString *s = [NSString stringWithCharacters:&c length:1]; return [f hasPrefix:@"{upper"] ? [s uppercaseString] : s; }
  if ([f isEqualToString:@"{lower-roman}"]) return Roman(n, NO); if ([f isEqualToString:@"{upper-roman}"]) return Roman(n, YES);
  if ([f isEqualToString:@"{lower-hexadecimal}"]) return [NSString stringWithFormat:@"%lx", (long)n]; if ([f isEqualToString:@"{upper-hexadecimal}"]) return [NSString stringWithFormat:@"%lX", (long)n];
  if ([f isEqualToString:@"{octal}"]) return [NSString stringWithFormat:@"%lo", (long)n];
  return f; }
+ (BOOL)includesTextListMarkers { return NO; }
@end

/* ---- tab group, combo button ---- */
@implementation NSWindowTabGroup
- (id)init { self = [super init]; _wins = [[NSMutableArray alloc] init]; _ident = [[[NSProcessInfo processInfo] globallyUniqueString] retain]; return self; }
- (void)dealloc { [_wins release]; [_ident release]; [super dealloc]; }
- (NSString *)identifier { return _ident; } - (NSArray *)windows { return [NSArray arrayWithArray:_wins]; }
- (BOOL)isOverviewVisible { return _overview; } - (void)setOverviewVisible:(BOOL)f { _overview = f; } - (BOOL)isTabBarVisible { return [_wins count] > 1; }
- (NSWindow *)selectedWindow { return _sel ? _sel : [_wins firstObject]; } - (void)setSelectedWindow:(NSWindow *)w { if ([_wins containsObject:w]) _sel = w; }
- (void)addWindow:(NSWindow *)w { if (![_wins containsObject:w]) [_wins addObject:w]; } - (void)insertWindow:(NSWindow *)w atIndex:(NSInteger)i { if ([_wins containsObject:w]) return; [_wins insertObject:w atIndex:(NSUInteger)MIN(MAX(i, 0), (NSInteger)[_wins count])]; }
- (void)removeWindow:(NSWindow *)w { [_wins removeObject:w]; if (_sel == w) _sel = nil; }
@end
@implementation NSComboButton
+ (id)_make:(NSString *)t image:(NSImage *)i menu:(NSMenu *)m target:(id)tg action:(SEL)a { NSComboButton *c = [[[self alloc] initWithFrame:NSMakeRect(0, 0, 80, 24)] autorelease]; c->_t = [(t ? t : @"") copy]; c->_img = [i retain]; c->_menu = [m retain]; c->_tgt = tg; c->_act = a; return c; }
+ (id)comboButtonWithTitle:(NSString *)t menu:(NSMenu *)m target:(id)tg action:(SEL)a { return [self _make:t image:nil menu:m target:tg action:a]; }
+ (id)comboButtonWithImage:(NSImage *)i menu:(NSMenu *)m target:(id)tg action:(SEL)a { return [self _make:nil image:i menu:m target:tg action:a]; }
+ (id)comboButtonWithTitle:(NSString *)t image:(NSImage *)i menu:(NSMenu *)m target:(id)tg action:(SEL)a { return [self _make:t image:i menu:m target:tg action:a]; }
- (void)dealloc { [_t release]; [_img release]; [_menu release]; [super dealloc]; }
- (NSString *)title { return _t ? _t : @""; } - (void)setTitle:(NSString *)t { [t retain]; [_t release]; _t = t; }
- (NSImage *)image { return _img; } - (void)setImage:(NSImage *)i { [i retain]; [_img release]; _img = i; }
- (NSInteger)imageScaling { return _scaling; } - (void)setImageScaling:(NSInteger)s { _scaling = s; } - (NSInteger)style { return _style; } - (void)setStyle:(NSInteger)s { _style = s; }
- (NSMenu *)menu { return _menu; } - (void)setMenu:(NSMenu *)m { [m retain]; [_menu release]; _menu = m; }
- (id)target { return _tgt; } - (void)setTarget:(id)t { _tgt = t; } - (SEL)action { return _act; } - (void)setAction:(SEL)a { _act = a; }
@end

/* ---- invalidation context, scrubber layout ---- */
@implementation NSCollectionViewLayoutInvalidationContext
- (id)init { self = [super init]; _items = [[NSMutableSet alloc] init]; _supp = [[NSMutableSet alloc] init]; _dec = [[NSMutableSet alloc] init]; return self; }
- (void)dealloc { [_items release]; [_supp release]; [_dec release]; [super dealloc]; }
- (BOOL)invalidateEverything { return _all; } - (BOOL)invalidateDataSourceCounts { return _counts; }
- (void)_xefAll { _all = YES; } - (void)_xefCounts { _counts = YES; }
- (void)invalidateItemsAtIndexPaths:(NSSet *)p { [_items unionSet:p]; }
- (void)invalidateSupplementaryElementsOfKind:(NSString *)k atIndexPaths:(NSSet *)p { [_supp unionSet:p]; } - (void)invalidateDecorationElementsOfKind:(NSString *)k atIndexPaths:(NSSet *)p { [_dec unionSet:p]; }
- (NSSet *)invalidatedItemIndexPaths { return _items; } - (NSSet *)invalidatedSupplementaryIndexPaths { return _supp; } - (NSSet *)invalidatedDecorationIndexPaths { return _dec; }
- (NSPoint)contentOffsetAdjustment { return _off; } - (void)setContentOffsetAdjustment:(NSPoint)o { _off = o; } - (NSSize)contentSizeAdjustment { return _sz; } - (void)setContentSizeAdjustment:(NSSize)s { _sz = s; }
@end
@implementation NSScrubberLayout
+ (Class)layoutAttributesClass { return objc_getClass("NSScrubberLayoutAttributes"); }
- (id)initWithCoder:(NSCoder *)c { return [self init]; }
- (id)scrubber { return _scrubber; } - (NSRect)visibleRect { return _vis; } - (void)invalidateLayout {} - (void)prepareLayout {} - (NSSize)scrubberContentSize { return NSZeroSize; }
- (id)layoutAttributesForItemAtIndex:(NSInteger)i { return nil; } - (NSSet *)layoutAttributesForItemsInRect:(NSRect)r { return [NSSet set]; }
- (BOOL)shouldInvalidateLayoutForSelectionChange { return NO; } - (BOOL)shouldInvalidateLayoutForHighlightChange { return NO; }
- (BOOL)shouldInvalidateLayoutForChangeFromVisibleRect:(NSRect)a toVisibleRect:(NSRect)b { return NO; } - (BOOL)automaticallyMirrorsInRightToLeftLayout { return YES; }
@end

/* ---- help manager ---- */
static BOOL g_ctxhelp;
@implementation NSHelpManager
+ (NSHelpManager *)sharedHelpManager { static NSHelpManager *h; if (!h) { h = [[self alloc] init]; h->_help = [[NSMapTable weakToStrongObjectsMapTable] retain]; } return h; }
+ (BOOL)isContextHelpModeActive { return g_ctxhelp; } + (void)setContextHelpModeActive:(BOOL)f { g_ctxhelp = f; }
- (void)setContextHelp:(NSAttributedString *)h forObject:(id)o { [_help setObject:h forKey:o]; } - (void)removeContextHelpForObject:(id)o { [_help removeObjectForKey:o]; }
- (NSAttributedString *)contextHelpForObject:(id)o { return [_help objectForKey:o]; } - (BOOL)showContextHelpForObject:(id)o locationHint:(NSPoint)p { return NO; }
- (void)openHelpAnchor:(NSString *)a inBook:(NSString *)b {} - (BOOL)findString:(NSString *)s inBook:(NSString *)b { return NO; } - (void)registerBooksInBundle:(NSBundle *)b {}
@end

/* ---- font manager collections, print info, open panel ---- */
static NSMutableDictionary *g_fm_cols;
@implementation NSFontManager (XEFMisc2)
- (NSDictionary *)convertAttributes:(NSDictionary *)a { NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:a]; NSFont *f = [a objectForKey:NSFontAttributeName]; if (f) [d setObject:[self convertFont:f] forKey:NSFontAttributeName]; return d; }
- (NSArray *)availableFontNamesMatchingFontDescriptor:(NSFontDescriptor *)d { NSString *n = [d postscriptName]; if (!n) n = [[d fontAttributes] objectForKey:NSFontNameAttribute]; NSString *fam = [[d fontAttributes] objectForKey:NSFontFamilyAttribute];
  NSMutableArray *o = [NSMutableArray array]; for (NSString *f in [self availableFonts]) if (!n && !fam ? YES : ((n && [f isEqualToString:n]) || (fam && [f hasPrefix:fam]))) [o addObject:f]; return o; }
- (NSArray *)collectionNames { NSMutableArray *a = [NSMutableArray arrayWithObjects:@"com.apple.AllFonts", @"com.apple.UserFonts", @"com.apple.Favorites", @"com.apple.Recents", nil]; [a addObjectsFromArray:[g_fm_cols allKeys]]; return a; }
- (NSArray *)fontDescriptorsInCollection:(NSString *)n { return [g_fm_cols objectForKey:n]; }
- (BOOL)addCollection:(NSString *)n options:(NSInteger)o { if (!g_fm_cols) g_fm_cols = [[NSMutableDictionary alloc] init]; if ([g_fm_cols objectForKey:n]) return NO; [g_fm_cols setObject:[NSArray array] forKey:n]; return YES; }
- (BOOL)removeCollection:(NSString *)n { if (![g_fm_cols objectForKey:n]) return NO; [g_fm_cols removeObjectForKey:n]; return YES; }
- (void)addFontDescriptors:(NSArray *)d toCollection:(NSString *)n { NSArray *old = [g_fm_cols objectForKey:n]; if (!old) return; [g_fm_cols setObject:[old arrayByAddingObjectsFromArray:d] forKey:n]; }
- (void)removeFontDescriptor:(NSFontDescriptor *)d fromCollection:(NSString *)n { NSMutableArray *a = [NSMutableArray arrayWithArray:[g_fm_cols objectForKey:n]]; [a removeObject:d]; if ([g_fm_cols objectForKey:n]) [g_fm_cols setObject:a forKey:n]; }
- (NSUInteger)convertFontTraits:(NSUInteger)t { return t; }
- (BOOL)validateMenuItem:(NSMenuItem *)m { return NO; }
@end
static NSString *g_paper_name;
@implementation NSPrintInfo (XEFMisc2)
- (void)setPaperName:(NSString *)n { [_dict setObject:n forKey:@"NSPaperName"]; }
- (id)printer { id p = [_dict objectForKey:@"NSPrinter"]; if (!p) { p = [[[NSPrinter alloc] init] autorelease]; ((NSPrinter *)p)->_name = [@"Default" copy]; } return p; } - (void)setPrinter:(id)p { if (p) [_dict setObject:p forKey:@"NSPrinter"]; }
- (NSString *)localizedPaperName { NSString *n = [self paperName]; if ([n isEqualToString:@"na-letter"]) return @"US Letter"; if ([n isEqualToString:@"iso-a4"]) return @"A4"; return n; }
- (void *)PMPrintSession { static char s; return &s; } - (void *)PMPageFormat { static char f; return &f; } - (void *)PMPrintSettings { static char p; return &p; }
- (void)takeSettingsFromPDFInfo:(NSPDFInfo *)i { [self setPaperSize:[i paperSize]]; [self setOrientation:[i orientation]]; if ([i URL]) [[self dictionary] setObject:[i URL] forKey:@"NSJobSavingURL"]; }
+ (void)setDefaultPrinter:(id)p {}
+ (NSSize)sizeForPaperName:(NSString *)n {
  NSString *l = [n lowercaseString];
  if ([l isEqualToString:@"a4"] || [l isEqualToString:@"iso-a4"]) return NSMakeSize(595, 842); if ([l isEqualToString:@"a3"]) return NSMakeSize(842, 1191); if ([l isEqualToString:@"a5"]) return NSMakeSize(420, 595);
  if ([l isEqualToString:@"letter"] || [l isEqualToString:@"na-letter"]) return NSMakeSize(612, 792); if ([l isEqualToString:@"legal"] || [l isEqualToString:@"na-legal"]) return NSMakeSize(612, 1008);
  return NSMakeSize(0, 0); }
@end
@implementation NSOpenPanel (XEFMisc2)
- (BOOL)resolvesAliases { NSNumber *n = objc_getAssociatedObject(self, "xef.ra"); return n ? [n boolValue] : YES; } - (void)setResolvesAliases:(BOOL)f { objc_setAssociatedObject(self, "xef.ra", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); }
- (BOOL)canResolveUbiquitousConflicts { NSNumber *n = objc_getAssociatedObject(self, "xef.cu"); return n ? [n boolValue] : YES; } - (void)setCanResolveUbiquitousConflicts:(BOOL)f { objc_setAssociatedObject(self, "xef.cu", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); }
- (BOOL)canDownloadUbiquitousContents { NSNumber *n = objc_getAssociatedObject(self, "xef.cd"); return n ? [n boolValue] : YES; } - (void)setCanDownloadUbiquitousContents:(BOOL)f { objc_setAssociatedObject(self, "xef.cd", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); }
- (BOOL)isAccessoryViewDisclosed { return [self accessoryView] ? [objc_getAssociatedObject(self, "xef.avd") boolValue] : NO; } - (void)setAccessoryViewDisclosed:(BOOL)f { objc_setAssociatedObject(self, "xef.avd", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); }
@end
