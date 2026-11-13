/* More small classes; matched against macOS by tests/darwin/mac/appkit_misc11.m. */
#import "AppKitMisc7.h"
#include <objc/runtime.h>

@implementation NSCollectionViewTransitionLayout
- (id)initWithCurrentLayout:(id)c nextLayout:(id)n { self = [super init]; _cur = [c retain]; _next = [n retain]; _vals = [[NSMutableDictionary alloc] init]; return self; }
- (void)dealloc { [_cur release]; [_next release]; [_vals release]; [super dealloc]; }
- (CGFloat)transitionProgress { return _prog; } - (void)setTransitionProgress:(CGFloat)p { _prog = p; } - (id)currentLayout { return _cur; } - (id)nextLayout { return _next; }
- (void)updateValue:(CGFloat)v forAnimatedKey:(NSString *)k {} - (CGFloat)valueForAnimatedKey:(NSString *)k { return [[_vals objectForKey:k] doubleValue]; }
@end

@implementation NSCollectionViewDiffableDataSource
- (id)initWithCollectionView:(NSCollectionView *)c itemProvider:(id)p { self = [super init]; _cv = c; _prov = [p copy]; _snap = [[NSDiffableDataSourceSnapshot alloc] init]; [c setDataSource:(id)self]; return self; }
- (void)dealloc { [_prov release]; [_supp release]; [_snap release]; [super dealloc]; }
- (NSDiffableDataSourceSnapshot *)snapshot { return [[_snap copy] autorelease]; }
- (void)applySnapshot:(NSDiffableDataSourceSnapshot *)s animatingDifferences:(BOOL)a { [s retain]; [_snap release]; _snap = [s copy]; [s release]; [_cv reloadData]; }
- (id)itemIdentifierForIndexPath:(NSIndexPath *)p { NSArray *secs = [_snap sectionIdentifiers]; if ([p section] >= (NSInteger)[secs count]) return nil; NSArray *a = [_snap itemIdentifiersInSectionWithIdentifier:[secs objectAtIndex:(NSUInteger)[p section]]]; return [p item] < (NSInteger)[a count] ? [a objectAtIndex:(NSUInteger)[p item]] : nil; }
- (NSIndexPath *)indexPathForItemIdentifier:(id)i { NSArray *secs = [_snap sectionIdentifiers]; for (NSUInteger s = 0; s < [secs count]; s++) { NSUInteger k = [[_snap itemIdentifiersInSectionWithIdentifier:[secs objectAtIndex:s]] indexOfObject:i]; if (k != NSNotFound) return [NSIndexPath indexPathForItem:(NSInteger)k inSection:(NSInteger)s]; } return nil; }
- (id)supplementaryViewProvider { return _supp; } - (void)setSupplementaryViewProvider:(id)p { id c = p ? [p copy] : nil; [_supp release]; _supp = c; }
- (NSInteger)numberOfSectionsInCollectionView:(NSCollectionView *)c { return [_snap numberOfSections]; }
- (NSInteger)collectionView:(NSCollectionView *)c numberOfItemsInSection:(NSInteger)s { NSArray *secs = [_snap sectionIdentifiers]; return s < (NSInteger)[secs count] ? (NSInteger)[[_snap itemIdentifiersInSectionWithIdentifier:[secs objectAtIndex:(NSUInteger)s]] count] : 0; }
- (id)collectionView:(NSCollectionView *)c itemForRepresentedObjectAtIndexPath:(NSIndexPath *)p { if (!_prov) return nil; id (^pr)(id, id, id) = (id (^)(id, id, id))_prov; return pr(c, p, [self itemIdentifierForIndexPath:p]); }
@end

@implementation NSCollectionViewCompositionalLayoutConfiguration
- (id)copyWithZone:(NSZone *)z { NSCollectionViewCompositionalLayoutConfiguration *c = [[[self class] alloc] init]; c->_dir = _dir; c->_gap = _gap; c->_bound = [_bound copy]; return c; }
- (void)dealloc { [_bound release]; [super dealloc]; }
- (NSInteger)scrollDirection { return _dir; } - (void)setScrollDirection:(NSInteger)d { _dir = d; } - (CGFloat)interSectionSpacing { return _gap; } - (void)setInterSectionSpacing:(CGFloat)g { _gap = g; }
- (NSArray *)boundarySupplementaryItems { return _bound ? _bound : [NSArray array]; } - (void)setBoundarySupplementaryItems:(NSArray *)b { id c = [b copy]; [_bound release]; _bound = c; }
@end
@implementation NSCollectionViewCompositionalLayout
- (id)initWithSection:(NSCollectionLayoutSection *)s { return [self initWithSection:s configuration:nil]; }
- (id)initWithSection:(NSCollectionLayoutSection *)s configuration:(NSCollectionViewCompositionalLayoutConfiguration *)c { self = [super init]; _sec = [s retain]; _cfg = c ? [c copy] : [[NSCollectionViewCompositionalLayoutConfiguration alloc] init]; return self; }
- (id)initWithSectionProvider:(id)p { return [self initWithSectionProvider:p configuration:nil]; }
- (id)initWithSectionProvider:(id)p configuration:(NSCollectionViewCompositionalLayoutConfiguration *)c { self = [super init]; _provider = [p copy]; _cfg = c ? [c copy] : [[NSCollectionViewCompositionalLayoutConfiguration alloc] init]; return self; }
- (void)dealloc { [_sec release]; [_provider release]; [_cfg release]; [super dealloc]; }
- (NSCollectionViewCompositionalLayoutConfiguration *)configuration { return _cfg; } - (void)setConfiguration:(NSCollectionViewCompositionalLayoutConfiguration *)c { id k = [c copy]; [_cfg release]; _cfg = k; [self invalidateLayout]; }
@end

@implementation NSAlignmentFeedbackFilter
+ (unsigned long long)inputEventMask { return 69702; } - (void)updateWithEvent:(NSEvent *)e {} - (void)updateWithPanRecognizer:(id)r {}
- (id)alignmentFeedbackTokenForMovementInView:(NSView *)v previousPoint:(NSPoint)p alignedPoint:(NSPoint)a defaultPoint:(NSPoint)d { return nil; }
- (id)alignmentFeedbackTokenForHorizontalMovementInView:(NSView *)v previousX:(CGFloat)p alignedX:(CGFloat)a defaultX:(CGFloat)d { return nil; }
- (id)alignmentFeedbackTokenForVerticalMovementInView:(NSView *)v previousY:(CGFloat)p alignedY:(CGFloat)a defaultY:(CGFloat)d { return nil; } - (void)performFeedback:(NSArray *)f performanceTime:(NSInteger)t {}
@end
@implementation NSWritingToolsCoordinatorAnimationParameters
- (void)dealloc { [_prog release]; [_comp release]; [super dealloc]; }
- (NSTimeInterval)duration { return _dur; } - (NSTimeInterval)delay { return _delay; }
- (id)progressHandler { return _prog; } - (void)setProgressHandler:(id)h { id c = h ? [h copy] : nil; [_prog release]; _prog = c; } - (id)completionHandler { return _comp; } - (void)setCompletionHandler:(id)h { id c = h ? [h copy] : nil; [_comp release]; _comp = c; }
@end
@implementation NSWritingToolsCoordinatorContext
- (id)initWithAttributedString:(NSAttributedString *)a range:(NSRange)r { self = [super init]; _as = [a copy]; _range = r; _id = [[NSUUID alloc] init]; return self; }
- (void)dealloc { [_as release]; [_id release]; [super dealloc]; }
- (NSAttributedString *)attributedString { return _as; } - (NSRange)range { return _range; } - (NSUUID *)identifier { return _id; } - (NSRange)resolvedRange { return _range; }
@end
@implementation NSTextListElement
- (id)initWithParentElement:(id)p textList:(NSTextList *)l contents:(NSAttributedString *)c markerAttributes:(NSDictionary *)m childElements:(NSArray *)k { self = [super initWithAttributedString:c ? c : [[[NSAttributedString alloc] initWithString:@""] autorelease]]; _list = [l retain]; _contents = [c copy]; _mattrs = [m copy]; _kids = [k copy]; _parent = p; return self; }
+ (id)textListElementWithContents:(NSAttributedString *)c markerAttributes:(NSDictionary *)m textList:(NSTextList *)l childElements:(NSArray *)k { return [[[self alloc] initWithParentElement:nil textList:l contents:c markerAttributes:m childElements:k] autorelease]; }
+ (id)textListElementWithChildElements:(NSArray *)k textList:(NSTextList *)l nestingLevel:(NSInteger)n { return [[[self alloc] initWithParentElement:nil textList:l contents:nil markerAttributes:nil childElements:k] autorelease]; }
- (void)dealloc { [_list release]; [_contents release]; [_mattrs release]; [_kids release]; [super dealloc]; }
- (NSTextList *)textList { return _list; } - (NSAttributedString *)contents { return _contents; } - (NSDictionary *)markerAttributes { return _mattrs; } - (NSArray *)childElements { return _kids; } - (id)parentElement { return _parent; }
@end
@implementation NSStoryboardSegue
+ (id)segueWithIdentifier:(NSString *)i source:(id)s destination:(id)d performHandler:(void (^)(void))h { NSStoryboardSegue *g = [[[self alloc] initWithIdentifier:i source:s destination:d] autorelease]; g->_h = h ? Block_copy(h) : NULL; return g; }
- (id)initWithIdentifier:(NSString *)i source:(id)s destination:(id)d { self = [super init]; _id = [i copy]; _src = [s retain]; _dst = [d retain]; return self; }
- (void)dealloc { [_id release]; [_src release]; [_dst release]; if (_h) Block_release(_h); [super dealloc]; }
- (NSString *)identifier { return _id; } - (id)sourceController { return _src; } - (id)destinationController { return _dst; } - (void)perform { if (_h) _h(); }
@end
@implementation NSSliderAccessoryBehavior
+ (id)_make { return [[[self alloc] init] autorelease]; }
+ (id)automaticBehavior { return [self _make]; } + (id)valueStepBehavior { return [self _make]; } + (id)valueResetBehavior { return [self _make]; }
+ (id)behaviorWithTarget:(id)t action:(SEL)a { NSSliderAccessoryBehavior *b = [self _make]; b->_tgt = t; b->_act = a; return b; }
+ (id)behaviorWithHandler:(void (^)(id))h { NSSliderAccessoryBehavior *b = [self _make]; b->_h = h ? Block_copy(h) : NULL; return b; }
- (void)dealloc { if (_h) Block_release(_h); [super dealloc]; }
- (void)handleAction:(id)a { if (_h) _h(a); else if (_tgt && _act) [_tgt performSelector:_act withObject:a]; }
@end
@implementation NSSliderAccessory
+ (id)accessoryWithImage:(NSImage *)i { NSSliderAccessory *a = [[[self alloc] init] autorelease]; a->_img = [i retain]; a->_beh = [[NSSliderAccessoryBehavior automaticBehavior] retain]; a->_en = YES; return a; }
- (void)dealloc { [_img release]; [_beh release]; [super dealloc]; }
- (NSSliderAccessoryBehavior *)behavior { return _beh; } - (void)setBehavior:(NSSliderAccessoryBehavior *)b { [b retain]; [_beh release]; _beh = b; } - (BOOL)isEnabled { return _en; } - (void)setEnabled:(BOOL)f { _en = f; }
@end
@implementation NSTrackingSeparatorToolbarItem
+ (id)trackingSeparatorToolbarItemWithIdentifier:(NSString *)i splitView:(NSSplitView *)s dividerIndex:(NSInteger)d { NSTrackingSeparatorToolbarItem *t = [[[self alloc] initWithItemIdentifier:i] autorelease]; t->_sv = [s retain]; t->_idx = d; return t; }
- (void)dealloc { [_sv release]; [super dealloc]; }
- (NSSplitView *)splitView { return _sv; } - (void)setSplitView:(NSSplitView *)s { [s retain]; [_sv release]; _sv = s; } - (NSInteger)dividerIndex { return _idx; } - (void)setDividerIndex:(NSInteger)d { _idx = d; }
@end
@implementation NSScrubberFlowLayout
- (id)init { self = [super init]; _sz = NSMakeSize(50, 30); return self; }
- (CGFloat)itemSpacing { return _sp; } - (void)setItemSpacing:(CGFloat)s { _sp = s; [self invalidateLayout]; } - (NSSize)itemSize { return _sz; } - (void)setItemSize:(NSSize)s { _sz = s; [self invalidateLayout]; } - (void)invalidateLayoutForItemsAtIndexes:(NSIndexSet *)i { [self invalidateLayout]; }
@end
@implementation NSScrubberArrangedView
- (BOOL)isSelected { return _sel; } - (void)setSelected:(BOOL)f { _sel = f; } - (BOOL)isHighlighted { return _hi; } - (void)setHighlighted:(BOOL)f { _hi = f; }
- (void)applyLayoutAttributes:(NSScrubberLayoutAttributes *)a { [self setFrame:[a frame]]; [self setAlphaValue:[a alpha]]; }
@end
@implementation NSScrubberImageItemView
- (id)initWithFrame:(NSRect)f { self = [super initWithFrame:f]; _iv = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, f.size.width, f.size.height)]; [self addSubview:_iv]; return self; }
- (void)dealloc { [_iv release]; [super dealloc]; }
- (id)imageView { return _iv; } - (NSImage *)image { return [_iv image]; } - (void)setImage:(NSImage *)i { [_iv setImage:i]; } - (NSInteger)imageAlignment { return _al; } - (void)setImageAlignment:(NSInteger)a { _al = a; }
@end
@implementation NSDataAsset
- (id)initWithName:(NSString *)n { return [self initWithName:n bundle:[NSBundle mainBundle]]; }
- (id)initWithName:(NSString *)n bundle:(NSBundle *)b { [self release]; return nil; }   /* no asset catalogs of data sets here */
- (NSString *)name { return _name; } - (NSData *)data { return _data; } - (NSString *)typeIdentifier { return _uti; }
@end
@implementation NSBindingSelectionMarker
+ (id)_m:(NSString *)n { static NSMutableDictionary *d; if (!d) d = [[NSMutableDictionary alloc] init]; id m = [d objectForKey:n]; if (!m) { m = [[self alloc] init]; ((NSBindingSelectionMarker *)m)->_n = [n copy]; [d setObject:m forKey:n]; [m release]; } return m; }
+ (id)multipleValuesSelectionMarker { return [self _m:@"NSMultipleValuesMarker"]; } + (id)noSelectionMarker { return [self _m:@"NSNoSelectionMarker"]; } + (id)notApplicableSelectionMarker { return [self _m:@"NSNotApplicableMarker"]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; } - (NSString *)description { return _n; }
@end
@implementation NSTextAlternatives
- (id)initWithPrimaryString:(NSString *)p alternativeStrings:(NSArray *)a { self = [super init]; _p = [p copy]; _alts = [a copy]; return self; }
- (void)dealloc { [_p release]; [_alts release]; [super dealloc]; }
- (NSString *)primaryString { return _p; } - (NSArray *)alternativeStrings { return _alts; } - (void)noteSelectedAlternativeString:(NSString *)s {}
@end
@implementation NSTextPreview
- (id)initWithSnapshotImage:(CGImageRef)i presentationFrame:(NSRect)f candidateRects:(NSArray *)c { self = [super init]; _img = i ? CGImageRetain(i) : NULL; _fr = f; _cands = [c copy]; return self; }
- (id)initWithSnapshotImage:(CGImageRef)i presentationFrame:(NSRect)f { return [self initWithSnapshotImage:i presentationFrame:f candidateRects:[NSArray array]]; }
- (void)dealloc { if (_img) CGImageRelease(_img); [_cands release]; [super dealloc]; }
- (CGImageRef)previewImage { return _img; } - (NSRect)presentationFrame { return _fr; } - (NSArray *)candidateRects { return _cands; }
@end
@implementation NSAccessibilityCustomRotorSearchParameters
- (void)dealloc { [_cur release]; [_filter release]; [super dealloc]; }
- (id)currentItem { return _cur; } - (void)setCurrentItem:(id)i { [i retain]; [_cur release]; _cur = i; } - (NSInteger)searchDirection { return _dir; } - (void)setSearchDirection:(NSInteger)d { _dir = d; }
- (NSString *)filterString { return _filter; } - (void)setFilterString:(NSString *)s { [s retain]; [_filter release]; _filter = s; }
@end
@implementation NSNib
- (id)initWithNibNamed:(NSString *)n bundle:(NSBundle *)b {
  NSBundle *bd = b ? b : [NSBundle mainBundle];
  if (![bd pathForResource:n ofType:@"nib"] && ![bd pathForResource:n ofType:@"storyboardc"]) [NSException raise:NSInternalInconsistencyException format:@"-[NSNib _initWithNibNamed:bundle:options:] could not load the nib '%@' in bundle %@.", n, bd];
  self = [super init]; _name = [n copy]; _bundle = [bd retain]; return self; }
- (id)initWithNibData:(NSData *)d bundle:(NSBundle *)b { self = [super init]; _data = [d copy]; _bundle = [(b ? b : [NSBundle mainBundle]) retain]; return self; }
- (id)initWithContentsOfURL:(NSURL *)u { NSData *d = [NSData dataWithContentsOfURL:u]; if (!d) { [self release]; return nil; } return [self initWithNibData:d bundle:nil]; }
- (void)dealloc { [_name release]; [_bundle release]; [_data release]; [super dealloc]; }
- (BOOL)instantiateWithOwner:(id)o topLevelObjects:(NSArray **)t { if (!_name) return NO; return [_bundle loadNibNamed:_name owner:o topLevelObjects:t]; }
- (BOOL)instantiateNibWithExternalNameTable:(NSDictionary *)tab { id o = [tab objectForKey:@"NSNibOwner"]; return [self instantiateWithOwner:o topLevelObjects:NULL]; }
- (BOOL)instantiateNibWithOwner:(id)o topLevelObjects:(NSArray **)t { return [self instantiateWithOwner:o topLevelObjects:t]; }
@end
@implementation NSFilePromiseReceiver
+ (NSArray *)readableDraggedTypes { return [NSArray arrayWithObjects:@"com.apple.pasteboard.promised-file-url", @"com.apple.pasteboard.promised-file-content-type", nil]; }
- (NSArray *)fileTypes { return [NSArray array]; } - (NSArray *)fileNames { return [NSArray array]; }
- (void)receivePromisedFilesAtDestination:(NSURL *)d options:(NSDictionary *)o operationQueue:(NSOperationQueue *)q reader:(void (^)(NSURL *, NSError *))r {}
+ (NSArray *)readableTypesForPasteboard:(NSPasteboard *)p { return [self readableDraggedTypes]; }
@end

@implementation NSPrintOperation (XEFMisc)
- (void)setAccessoryView:(NSView *)v { objc_setAssociatedObject(self, "xef.pav", v, OBJC_ASSOCIATION_RETAIN); } - (NSView *)accessoryView { return objc_getAssociatedObject(self, "xef.pav"); }
- (void)setJobStyleHint:(NSString *)h { objc_setAssociatedObject(self, "xef.pjh", h, OBJC_ASSOCIATION_COPY); } - (NSString *)jobStyleHint { return objc_getAssociatedObject(self, "xef.pjh"); }
- (void)setShowPanels:(BOOL)f { objc_setAssociatedObject(self, "xef.psp", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); [self setShowsPrintPanel:f]; [self setShowsProgressPanel:f]; }
- (BOOL)showPanels { NSNumber *n = objc_getAssociatedObject(self, "xef.psp"); return n ? [n boolValue] : YES; }
@end
@implementation NSFontDescriptor (XEFMisc)
- (id)matrix { return [_attrs objectForKey:@"NSFontMatrixAttribute"]; } - (BOOL)requiresFontAssetRequest { return NO; }
+ (id)fontDescriptorWithName:(NSString *)n matrix:(id)m { NSMutableDictionary *d = [NSMutableDictionary dictionaryWithObject:n forKey:NSFontNameAttribute]; if (m) [d setObject:m forKey:@"NSFontMatrixAttribute"]; return [self fontDescriptorWithFontAttributes:d]; }
- (id)initWithFontAttributes:(NSDictionary *)a { self = [super init]; _attrs = [a copy]; if (!_attrs) _attrs = [[NSDictionary alloc] init]; return self; }
- (NSFontDescriptor *)matchingFontDescriptorWithMandatoryKeys:(NSSet *)k { return self; }
- (NSFontDescriptor *)fontDescriptorWithMatrix:(id)m { return [self fontDescriptorByAddingAttributes:[NSDictionary dictionaryWithObject:m forKey:@"NSFontMatrixAttribute"]]; }
@end
@implementation NSAnimation (XEFMisc)
- (id)initWithCoder:(NSCoder *)c { return [self initWithDuration:[c decodeDoubleForKey:@"NSDuration"] animationCurve:0]; }
- (void)startWhenAnimation:(NSAnimation *)a reachesProgress:(float)p {} - (void)stopWhenAnimation:(NSAnimation *)a reachesProgress:(float)p {} - (void)clearStartAnimation {} - (void)clearStopAnimation {}
- (NSArray *)runLoopModesForAnimating { return nil; }
@end
@implementation NSBundle (XEFMisc2)
- (NSString *)contextHelpForKey:(NSString *)k { return nil; }
- (NSString *)pathForImageResource:(NSString *)n { for (NSString *e in [NSArray arrayWithObjects:@"png", @"tiff", @"jpg", @"jpeg", @"gif", @"pdf", nil]) { NSString *p = [self pathForResource:n ofType:e]; if (p) return p; } return nil; }
- (NSURL *)URLForImageResource:(NSString *)n { NSString *p = [self pathForImageResource:n]; return p ? [NSURL fileURLWithPath:p] : nil; }
- (NSString *)pathForSoundResource:(NSString *)n { for (NSString *e in [NSArray arrayWithObjects:@"wav", @"aiff", @"aif", @"mp3", @"m4a", @"caf", nil]) { NSString *p = [self pathForResource:n ofType:e]; if (p) return p; } return nil; }
@end
@implementation NSPopover (XEFMisc)
- (id)effectiveAppearance { return [NSApp effectiveAppearance]; }
- (BOOL)hasFullSizeContent { return [objc_getAssociatedObject(self, "xef.fsc") boolValue]; } - (void)setHasFullSizeContent:(BOOL)f { objc_setAssociatedObject(self, "xef.fsc", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); }
- (void)showRelativeToToolbarItem:(NSToolbarItem *)i { NSView *v = [i view]; if (v) [self showRelativeToRect:[v bounds] ofView:v preferredEdge:NSMaxYEdge]; }
@end
@implementation NSTextFieldCell (XEFMisc2)
- (void)setPlaceholderAttributedString:(NSAttributedString *)s { objc_setAssociatedObject(self, "xef.pas", s, OBJC_ASSOCIATION_RETAIN); }
- (void)setWantsNotificationForMarkedText:(BOOL)f {}
- (NSArray *)allowedInputSourceLocales { return objc_getAssociatedObject(self, "xef.ail"); } - (void)setAllowedInputSourceLocales:(NSArray *)l { objc_setAssociatedObject(self, "xef.ail", [[l copy] autorelease], OBJC_ASSOCIATION_RETAIN); }
@end

/* the controller selection markers (NSMultipleValuesMarker ...) are objects, shared with the NSBindingSelectionMarker singletons */
id NSMultipleValuesMarker, NSNoSelectionMarker, NSNotApplicableMarker;
__attribute__((constructor)) static void xef_init_selection_markers(void) {
  NSMultipleValuesMarker = [NSBindingSelectionMarker multipleValuesSelectionMarker]; NSNoSelectionMarker = [NSBindingSelectionMarker noSelectionMarker]; NSNotApplicableMarker = [NSBindingSelectionMarker notApplicableSelectionMarker]; }
