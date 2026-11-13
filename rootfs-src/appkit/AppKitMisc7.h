/* More small classes (AppKitMisc7.m). */
#import "AppKitMisc6.h"
#import "AppKitTextKit2.h"

@interface NSCollectionViewTransitionLayout : NSCollectionViewLayout { @public NSCollectionViewLayout *_cur, *_next; CGFloat _prog; NSMutableDictionary *_vals; }
- (CGFloat)transitionProgress; - (void)setTransitionProgress:(CGFloat)p; - (id)currentLayout; - (id)nextLayout; - (id)initWithCurrentLayout:(id)c nextLayout:(id)n; - (void)updateValue:(CGFloat)v forAnimatedKey:(NSString *)k; - (CGFloat)valueForAnimatedKey:(NSString *)k;
@end
@interface NSCollectionViewDiffableDataSource : NSObject { @public NSCollectionView *_cv; id _prov, _supp; NSDiffableDataSourceSnapshot *_snap; }
- (id)initWithCollectionView:(NSCollectionView *)c itemProvider:(id)p; - (NSDiffableDataSourceSnapshot *)snapshot; - (void)applySnapshot:(NSDiffableDataSourceSnapshot *)s animatingDifferences:(BOOL)a;
- (id)itemIdentifierForIndexPath:(NSIndexPath *)p; - (NSIndexPath *)indexPathForItemIdentifier:(id)i; - (id)supplementaryViewProvider; - (void)setSupplementaryViewProvider:(id)p;
@end
@interface NSCollectionViewCompositionalLayoutConfiguration : NSObject <NSCopying> { @public NSInteger _dir; CGFloat _gap; NSArray *_bound; }
- (NSInteger)scrollDirection; - (void)setScrollDirection:(NSInteger)d; - (CGFloat)interSectionSpacing; - (void)setInterSectionSpacing:(CGFloat)g; - (NSArray *)boundarySupplementaryItems; - (void)setBoundarySupplementaryItems:(NSArray *)b;
@end
@interface NSCollectionViewCompositionalLayout : NSCollectionViewLayout { @public NSCollectionLayoutSection *_sec; id _provider; NSCollectionViewCompositionalLayoutConfiguration *_cfg; }
- (id)initWithSection:(NSCollectionLayoutSection *)s; - (id)initWithSection:(NSCollectionLayoutSection *)s configuration:(NSCollectionViewCompositionalLayoutConfiguration *)c; - (id)initWithSectionProvider:(id)p; - (id)initWithSectionProvider:(id)p configuration:(NSCollectionViewCompositionalLayoutConfiguration *)c;
- (NSCollectionViewCompositionalLayoutConfiguration *)configuration; - (void)setConfiguration:(NSCollectionViewCompositionalLayoutConfiguration *)c;
@end
@interface NSAlignmentFeedbackFilter : NSObject
+ (unsigned long long)inputEventMask; - (void)updateWithEvent:(NSEvent *)e; - (void)updateWithPanRecognizer:(id)r;
- (id)alignmentFeedbackTokenForMovementInView:(NSView *)v previousPoint:(NSPoint)p alignedPoint:(NSPoint)a defaultPoint:(NSPoint)d;
- (id)alignmentFeedbackTokenForHorizontalMovementInView:(NSView *)v previousX:(CGFloat)p alignedX:(CGFloat)a defaultX:(CGFloat)d;
- (id)alignmentFeedbackTokenForVerticalMovementInView:(NSView *)v previousY:(CGFloat)p alignedY:(CGFloat)a defaultY:(CGFloat)d; - (void)performFeedback:(NSArray *)f performanceTime:(NSInteger)t;
@end
@interface NSWritingToolsCoordinatorAnimationParameters : NSObject { @public NSTimeInterval _dur, _delay; id _prog, _comp; }
- (NSTimeInterval)duration; - (NSTimeInterval)delay; - (id)progressHandler; - (void)setProgressHandler:(id)h; - (id)completionHandler; - (void)setCompletionHandler:(id)h;
@end
@interface NSWritingToolsCoordinatorContext : NSObject { @public NSAttributedString *_as; NSRange _range; NSUUID *_id; }
- (id)initWithAttributedString:(NSAttributedString *)a range:(NSRange)r; - (NSAttributedString *)attributedString; - (NSRange)range; - (NSUUID *)identifier; - (NSRange)resolvedRange;
@end
@interface NSTextListElement : NSTextParagraph { @public NSTextList *_list; NSAttributedString *_contents; NSDictionary *_mattrs; NSArray *_kids; id _parent; }
- (id)initWithParentElement:(id)p textList:(NSTextList *)l contents:(NSAttributedString *)c markerAttributes:(NSDictionary *)m childElements:(NSArray *)k;
+ (id)textListElementWithContents:(NSAttributedString *)c markerAttributes:(NSDictionary *)m textList:(NSTextList *)l childElements:(NSArray *)k; + (id)textListElementWithChildElements:(NSArray *)k textList:(NSTextList *)l nestingLevel:(NSInteger)n;
- (NSTextList *)textList; - (NSAttributedString *)contents; - (NSDictionary *)markerAttributes;
@end
@interface NSStoryboardSegue : NSObject { @public NSString *_id; id _src, _dst; void (^_h)(void); }
+ (id)segueWithIdentifier:(NSString *)i source:(id)s destination:(id)d performHandler:(void (^)(void))h; - (id)initWithIdentifier:(NSString *)i source:(id)s destination:(id)d; - (NSString *)identifier; - (id)sourceController; - (id)destinationController; - (void)perform;
@end
@interface NSSliderAccessoryBehavior : NSObject { @public id _tgt; SEL _act; void (^_h)(id); }
+ (id)automaticBehavior; + (id)valueStepBehavior; + (id)valueResetBehavior; + (id)behaviorWithTarget:(id)t action:(SEL)a; + (id)behaviorWithHandler:(void (^)(id))h; - (void)handleAction:(id)a;
@end
@interface NSSliderAccessory : NSObject { @public NSImage *_img; NSSliderAccessoryBehavior *_beh; BOOL _en; }
+ (id)accessoryWithImage:(NSImage *)i; - (NSSliderAccessoryBehavior *)behavior; - (void)setBehavior:(NSSliderAccessoryBehavior *)b; - (BOOL)isEnabled; - (void)setEnabled:(BOOL)f;
@end
@interface NSTrackingSeparatorToolbarItem : NSToolbarItem { @public NSSplitView *_sv; NSInteger _idx; }
+ (id)trackingSeparatorToolbarItemWithIdentifier:(NSString *)i splitView:(NSSplitView *)s dividerIndex:(NSInteger)d; - (NSSplitView *)splitView; - (void)setSplitView:(NSSplitView *)s; - (NSInteger)dividerIndex; - (void)setDividerIndex:(NSInteger)d;
@end
@interface NSScrubberFlowLayout : NSScrubberLayout { @public CGFloat _sp; NSSize _sz; }
- (CGFloat)itemSpacing; - (void)setItemSpacing:(CGFloat)s; - (NSSize)itemSize; - (void)setItemSize:(NSSize)s; - (void)invalidateLayoutForItemsAtIndexes:(NSIndexSet *)i;
@end
@interface NSScrubberArrangedView : NSView { @public BOOL _sel, _hi; }
- (BOOL)isSelected; - (void)setSelected:(BOOL)f; - (BOOL)isHighlighted; - (void)setHighlighted:(BOOL)f; - (void)applyLayoutAttributes:(NSScrubberLayoutAttributes *)a;
@end
@interface NSScrubberImageItemView : NSScrubberArrangedView { @public NSImageView *_iv; NSInteger _al; }
- (id)imageView; - (NSImage *)image; - (void)setImage:(NSImage *)i; - (NSInteger)imageAlignment; - (void)setImageAlignment:(NSInteger)a;
@end
@interface NSDataAsset : NSObject { @public NSString *_name; NSData *_data; NSString *_uti; }
- (id)initWithName:(NSString *)n; - (id)initWithName:(NSString *)n bundle:(NSBundle *)b; - (NSString *)name; - (NSData *)data; - (NSString *)typeIdentifier;
@end
@interface NSBindingSelectionMarker : NSObject <NSCopying> { @public NSString *_n; }
+ (id)multipleValuesSelectionMarker; + (id)noSelectionMarker; + (id)notApplicableSelectionMarker;
@end
@interface NSTextAlternatives : NSObject { @public NSString *_p; NSArray *_alts; }
- (id)initWithPrimaryString:(NSString *)p alternativeStrings:(NSArray *)a; - (NSString *)primaryString; - (NSArray *)alternativeStrings; - (void)noteSelectedAlternativeString:(NSString *)s;
@end
@interface NSTextPreview : NSObject { @public CGImageRef _img; NSRect _fr; NSArray *_cands; }
- (id)initWithSnapshotImage:(CGImageRef)i presentationFrame:(NSRect)f candidateRects:(NSArray *)c; - (id)initWithSnapshotImage:(CGImageRef)i presentationFrame:(NSRect)f; - (CGImageRef)previewImage; - (NSRect)presentationFrame; - (NSArray *)candidateRects;
@end
@interface NSAccessibilityCustomRotorSearchParameters : NSObject { @public id _cur; NSInteger _dir; NSString *_filter; }
- (id)currentItem; - (void)setCurrentItem:(id)i; - (NSInteger)searchDirection; - (void)setSearchDirection:(NSInteger)d; - (NSString *)filterString; - (void)setFilterString:(NSString *)s;
@end
@interface NSNib : NSObject { @public NSString *_name; NSBundle *_bundle; NSData *_data; }
- (id)initWithNibNamed:(NSString *)n bundle:(NSBundle *)b; - (id)initWithNibData:(NSData *)d bundle:(NSBundle *)b; - (id)initWithContentsOfURL:(NSURL *)u;
- (BOOL)instantiateWithOwner:(id)o topLevelObjects:(NSArray **)t; - (BOOL)instantiateNibWithExternalNameTable:(NSDictionary *)t; - (BOOL)instantiateNibWithOwner:(id)o topLevelObjects:(NSArray **)t;
@end
@interface NSFilePromiseReceiver : NSObject
+ (NSArray *)readableDraggedTypes; - (NSArray *)fileTypes; - (NSArray *)fileNames; - (void)receivePromisedFilesAtDestination:(NSURL *)d options:(NSDictionary *)o operationQueue:(NSOperationQueue *)q reader:(void (^)(NSURL *, NSError *))r; + (NSArray *)readableTypesForPasteboard:(NSPasteboard *)p;
@end
@interface NSPrintOperation (XEFMisc)
- (void)setAccessoryView:(NSView *)v; - (NSView *)accessoryView; - (void)setJobStyleHint:(NSString *)h; - (NSString *)jobStyleHint; - (void)setShowPanels:(BOOL)f; - (BOOL)showPanels;
@end
@interface NSFontDescriptor (XEFMisc)
- (id)matrix; - (BOOL)requiresFontAssetRequest; + (id)fontDescriptorWithName:(NSString *)n matrix:(id)m; - (id)initWithFontAttributes:(NSDictionary *)a; - (NSFontDescriptor *)matchingFontDescriptorWithMandatoryKeys:(NSSet *)k; - (NSFontDescriptor *)fontDescriptorWithMatrix:(id)m;
@end
@interface NSAnimation (XEFMisc)
- (id)initWithCoder:(NSCoder *)c; - (void)startWhenAnimation:(NSAnimation *)a reachesProgress:(float)p; - (void)stopWhenAnimation:(NSAnimation *)a reachesProgress:(float)p; - (void)clearStartAnimation; - (void)clearStopAnimation; - (NSArray *)runLoopModesForAnimating;
@end
@interface NSBundle (XEFMisc2)
- (NSString *)contextHelpForKey:(NSString *)k; - (NSString *)pathForImageResource:(NSString *)n; - (NSURL *)URLForImageResource:(NSString *)n; - (NSString *)pathForSoundResource:(NSString *)n;
@end
@interface NSPopover (XEFMisc)
- (id)effectiveAppearance; - (BOOL)hasFullSizeContent; - (void)setHasFullSizeContent:(BOOL)f; - (void)showRelativeToToolbarItem:(NSToolbarItem *)i;
@end
@interface NSTextFieldCell (XEFMisc2)
- (void)setPlaceholderAttributedString:(NSAttributedString *)s; - (void)setWantsNotificationForMarkedText:(BOOL)f; - (NSArray *)allowedInputSourceLocales; - (void)setAllowedInputSourceLocales:(NSArray *)l;
@end
