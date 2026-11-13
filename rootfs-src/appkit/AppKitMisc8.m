/* The last small classes and extras; matched against macOS by tests/darwin/mac/appkit_misc12.m. */
#import "AppKitMisc8.h"
#include <objc/runtime.h>
#include <objc/message.h>

#define STR(iv, getter, setter) - (NSString *)getter { return iv; } - (void)setter:(NSString *)v { [v retain]; [iv release]; iv = v; }

@implementation NSScrubberSelectionStyle
+ (id)outlineOverlayStyle { return [[[self alloc] init] autorelease]; } + (id)roundedBackgroundStyle { return [[[self alloc] init] autorelease]; }
- (id)initWithCoder:(NSCoder *)c { return [self init]; } - (id)makeSelectionView { return [[[NSScrubberArrangedView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)] autorelease]; }
@end
@implementation NSScrubberTextItemView
- (id)initWithFrame:(NSRect)f { self = [super initWithFrame:f]; _tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, f.size.width, f.size.height)]; [_tf setEditable:NO]; [_tf setBezeled:NO]; [_tf setDrawsBackground:NO]; [self addSubview:_tf]; return self; }
- (void)dealloc { [_tf release]; [super dealloc]; }
- (NSTextField *)textField { return _tf; } - (NSString *)title { return [_tf stringValue]; } - (void)setTitle:(NSString *)t { [_tf setStringValue:t ? t : @""]; }
@end
@implementation NSScrubberProportionalLayout
- (id)init { self = [super init]; _n = 5; return self; } - (id)initWithNumberOfVisibleItems:(NSInteger)n { self = [super init]; _n = n; return self; }
- (NSInteger)numberOfVisibleItems { return _n; } - (void)setNumberOfVisibleItems:(NSInteger)n { _n = n; [self invalidateLayout]; }
@end
@implementation NSMutableFontCollection
- (void)setQueryDescriptors:(NSArray *)d { [d retain]; [_query release]; _query = d; } - (void)setExclusionDescriptors:(NSArray *)d { [d retain]; [_excl release]; _excl = d; }
- (void)addQueryForDescriptors:(NSArray *)d { NSMutableArray *a = [NSMutableArray arrayWithArray:_query]; for (id x in d) if (![a containsObject:x]) [a addObject:x]; [self setQueryDescriptors:a]; _all = NO; }
- (void)removeQueryForDescriptors:(NSArray *)d { NSMutableArray *a = [NSMutableArray arrayWithArray:_query]; [a removeObjectsInArray:d]; [self setQueryDescriptors:a]; }
@end
@implementation NSMenuToolbarItem
- (id)initWithItemIdentifier:(NSString *)i { self = [super initWithItemIdentifier:i]; _mtMenu = [[NSMenu alloc] initWithTitle:@""]; _ind = YES; return self; }
- (void)dealloc { [_mtMenu release]; [super dealloc]; }
- (NSMenu *)menu { return _mtMenu; } - (void)setMenu:(NSMenu *)m { [m retain]; [_mtMenu release]; _mtMenu = m; } - (BOOL)showsIndicator { return _ind; } - (void)setShowsIndicator:(BOOL)f { _ind = f; }
@end
@implementation NSItemBadge
+ (id)badgeWithCount:(NSInteger)n { NSItemBadge *b = [[[self alloc] init] autorelease]; b->_t = [[NSString stringWithFormat:@"%ld", (long)n] retain]; return b; }
+ (id)badgeWithText:(NSString *)t { NSItemBadge *b = [[[self alloc] init] autorelease]; b->_t = [t copy]; return b; } + (id)indicatorBadge { NSItemBadge *b = [[[self alloc] init] autorelease]; b->_t = [@"" retain]; return b; }
- (void)dealloc { [_t release]; [super dealloc]; } - (NSString *)text { return _t; }
@end
@implementation NSGlassEffectContainerView
- (void)dealloc { [_cv release]; [super dealloc]; }
- (NSView *)contentView { return _cv; } - (void)setContentView:(NSView *)v { [_cv removeFromSuperview]; [v retain]; [_cv release]; _cv = v; if (v) [self addSubview:v]; } - (CGFloat)spacing { return _sp; } - (void)setSpacing:(CGFloat)s { _sp = s; }
@end
@implementation NSBackgroundExtensionView
- (id)initWithFrame:(NSRect)f { self = [super initWithFrame:f]; _auto = YES; return self; } - (void)dealloc { [_cv release]; [super dealloc]; }
- (NSView *)contentView { return _cv; } - (void)setContentView:(NSView *)v { [_cv removeFromSuperview]; [v retain]; [_cv release]; _cv = v; if (v) [self addSubview:v]; }
- (BOOL)automaticallyPlacesContentView { return _auto; } - (void)setAutomaticallyPlacesContentView:(BOOL)f { _auto = f; }
@end
@implementation NSFontAssetRequest
- (id)initWithFontDescriptors:(NSArray *)d options:(NSUInteger)o { self = [super init]; _d = [d copy]; return self; } - (void)dealloc { [_d release]; [super dealloc]; }
- (NSArray *)downloadedFontDescriptors { return [NSArray array]; } - (NSProgress *)progress { Class c = NSClassFromString(@"NSProgress"); return c ? [[[c alloc] init] autorelease] : nil; }
- (void)downloadFontAssetsWithCompletionHandler:(void (^)(NSError *))h { if (h) h(nil); }
@end
@implementation NSCollectionViewFlowLayoutInvalidationContext
- (id)init { self = [super init]; _m = _a = YES; return self; }
- (BOOL)invalidateFlowLayoutDelegateMetrics { return _m; } - (void)setInvalidateFlowLayoutDelegateMetrics:(BOOL)f { _m = f; } - (BOOL)invalidateFlowLayoutAttributes { return _a; } - (void)setInvalidateFlowLayoutAttributes:(BOOL)f { _a = f; }
@end
@implementation NSCollectionViewUpdateItem
- (void)dealloc { [_b release]; [_a release]; [super dealloc]; } - (NSIndexPath *)indexPathBeforeUpdate { return _b; } - (NSIndexPath *)indexPathAfterUpdate { return _a; } - (NSInteger)updateAction { return _act; }
@end
@implementation NSAccessibilityElement
+ (id)accessibilityElementWithRole:(NSString *)r frame:(NSRect)f label:(NSString *)l parent:(id)p { NSAccessibilityElement *e = [[[self alloc] init] autorelease]; e->_role = [r copy]; e->_frame = f; e->_label = [l copy]; e->_parent = p; return e; }
- (id)init { self = [super init]; _kids = [[NSMutableArray alloc] init]; return self; } - (void)dealloc { [_role release]; [_label release]; [_kids release]; [super dealloc]; }
- (void)accessibilityAddChildElement:(id)c { [_kids addObject:c]; } - (NSRect)accessibilityFrameInParentSpace { return _pframe; } - (void)setAccessibilityFrameInParentSpace:(NSRect)f { _pframe = f; }
- (NSString *)accessibilityRole { return _role; } - (NSString *)accessibilityLabel { return _label; } - (NSRect)accessibilityFrame { return _frame; } - (id)accessibilityParent { return _parent; } - (NSArray *)accessibilityChildren { return _kids; }
@end
@implementation NSViewAnimation
- (id)initWithViewAnimations:(NSArray *)a { self = [super initWithDuration:0.5 animationCurve:0]; _va = [a copy]; return self; } - (void)dealloc { [_va release]; [super dealloc]; }
- (NSArray *)viewAnimations { return _va; } - (void)setViewAnimations:(NSArray *)a { [a retain]; [_va release]; _va = a; }
@end
@implementation NSPreviewRepresentingActivityItem
- (id)initWithItem:(id)i title:(NSString *)t image:(id)img icon:(id)ic { self = [super init]; _item = [i retain]; _title = [t copy]; _image = [img retain]; _icon = [ic retain]; return self; }
- (id)initWithItem:(id)i title:(NSString *)t imageProvider:(id)ip iconProvider:(id)icp { return [self initWithItem:i title:t image:ip icon:icp]; }
- (void)dealloc { [_item release]; [_title release]; [_image release]; [_icon release]; [super dealloc]; } - (id)item { return _item; } - (NSString *)title { return _title; }
@end
@implementation NSPressureConfiguration
- (id)initWithPressureBehavior:(NSInteger)b { self = [super init]; _b = b; return self; } - (NSInteger)pressureBehavior { return _b; } - (void)set {}
@end
@implementation NSViewLayoutRegion
+ (id)safeAreaLayoutRegionWithCornerAdaptation:(NSInteger)a { return [[[self alloc] init] autorelease]; } + (id)marginsLayoutRegionWithCornerAdaptation:(NSInteger)a { return [[[self alloc] init] autorelease]; }
@end
@implementation NSStatusBarButton
- (BOOL)appearsDisabled { return _dis; } - (void)setAppearsDisabled:(BOOL)f { _dis = f; }
@end
@implementation NSSharingServicePickerToolbarItem
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
@end
@implementation NSPredicateEditor
- (id)initWithFrame:(NSRect)f { self = [super initWithFrame:f]; _rt = [[NSArray arrayWithObject:[[[NSPredicateEditorRowTemplate alloc] initWithCompoundTypes:[NSArray arrayWithObjects:[NSNumber numberWithUnsignedInteger:NSAndPredicateType], [NSNumber numberWithUnsignedInteger:NSOrPredicateType], [NSNumber numberWithUnsignedInteger:NSNotPredicateType], nil]] autorelease]] retain]; return self; }
- (void)dealloc { [_rt release]; [super dealloc]; }
- (NSArray *)rowTemplates { return _rt; } - (void)setRowTemplates:(NSArray *)t { [t retain]; [_rt release]; _rt = t; }
@end
@implementation NSGlyphGenerator
+ (id)sharedGlyphGenerator { static NSGlyphGenerator *g; if (!g) g = [[self alloc] init]; return g; }
- (void)generateGlyphsForGlyphStorage:(id)s desiredNumberOfCharacters:(NSUInteger)n glyphIndex:(NSUInteger *)g characterIndex:(NSUInteger *)c {}
@end
@implementation NSStringDrawingContext
- (CGFloat)minimumScaleFactor { return _min; } - (void)setMinimumScaleFactor:(CGFloat)f { _min = f; } - (CGFloat)actualScaleFactor { return _act; } - (NSRect)totalBounds { return _tb; }
@end
@implementation NSColorSampler
- (void)showSamplerWithSelectionHandler:(void (^)(NSColor *))h { if (h) h(nil); }
@end
@implementation NSAdaptiveImageGlyph
- (id)initWithImageContent:(NSData *)d { self = [super init]; _d = [d copy]; _cid = [[[NSUUID UUID] UUIDString] retain]; return self; } - (id)initWithCoder:(NSCoder *)c { return [self initWithImageContent:[NSData data]]; }
- (void)dealloc { [_d release]; [_cid release]; [_desc release]; [super dealloc]; } - (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSData *)imageContent { return _d; } - (NSString *)contentIdentifier { return _cid; } - (NSString *)contentDescription { return _desc ? _desc : @""; } + (NSString *)contentType { return @"public.heic"; }
@end
@implementation NSPICTImageRep
+ (id)imageRepWithData:(NSData *)d { return [[[self alloc] initWithData:d] autorelease]; } - (id)initWithData:(NSData *)d { [self release]; return nil; }   /* PICT is not supported */
- (NSData *)PICTRepresentation { return _d; } - (NSRect)boundingBox { return _bb; }
@end
@implementation NSMovie
- (id)init { [self release]; return nil; }   /* QuickTime movies are gone: init fails on current macOS too */
@end

@implementation NSToolbarItemGroup (XEFMisc)
+ (id)_make:(NSString *)i count:(NSUInteger)n mode:(NSInteger)m labels:(NSArray *)l target:(id)tg action:(SEL)a title:(NSString *(^)(NSUInteger))tt image:(NSImage *(^)(NSUInteger))im {
  NSToolbarItemGroup *g = [[[self alloc] initWithItemIdentifier:i] autorelease]; NSMutableArray *subs = [NSMutableArray array];
  for (NSUInteger k = 0; k < n; k++) { NSToolbarItem *s = [[[NSToolbarItem alloc] initWithItemIdentifier:[NSString stringWithFormat:@"%@.%lu", i, (unsigned long)k]] autorelease]; if (tt) [s setTitle:tt(k)]; if (im) [s setImage:im(k)]; if (k < [l count]) [s setLabel:[l objectAtIndex:k]]; [s setTarget:tg]; [s setAction:a]; [subs addObject:s]; }
  [g setSubitems:subs]; [g setSelectionMode:m]; return g; }
+ (id)groupWithItemIdentifier:(NSString *)i titles:(NSArray *)t selectionMode:(NSInteger)m labels:(NSArray *)l target:(id)tg action:(SEL)a { return [self _make:i count:[t count] mode:m labels:l target:tg action:a title:^NSString *(NSUInteger k) { return [t objectAtIndex:k]; } image:nil]; }
+ (id)groupWithItemIdentifier:(NSString *)i images:(NSArray *)im selectionMode:(NSInteger)m labels:(NSArray *)l target:(id)tg action:(SEL)a { return [self _make:i count:[im count] mode:m labels:l target:tg action:a title:nil image:^NSImage *(NSUInteger k) { return [im objectAtIndex:k]; }]; }
- (BOOL)isSelectedAtIndex:(NSInteger)i { return i == [self selectedIndex]; }
@end
@implementation NSWindowController (XEFMisc)
- (id)initWithWindowNibPath:(NSString *)p owner:(id)o { self = [self initWithWindowNibName:[[p lastPathComponent] stringByDeletingPathExtension] owner:o]; return self; }
- (NSArray *)previewRepresentableActivityItems { return objc_getAssociatedObject(self, "xef.pra"); } - (void)setPreviewRepresentableActivityItems:(NSArray *)a { objc_setAssociatedObject(self, "xef.pra", a, OBJC_ASSOCIATION_RETAIN); }
@end
@implementation NSTextContainer (XEFMisc2)
- (NSRect)lineFragmentRectForProposedRect:(NSRect)p atIndex:(NSUInteger)i writingDirection:(NSInteger)d remainingRect:(NSRect *)r {
  CGFloat w = MIN(p.size.width, [self containerSize].width - p.origin.x); NSRect out = NSMakeRect(p.origin.x, p.origin.y, MAX(0, w), p.size.height); if (r) *r = NSMakeRect(NSMaxX(out), p.origin.y, MAX(0, NSMaxX(p) - NSMaxX(out)) > 0 ? 0 : 0, p.size.height); return out; }
- (NSInteger)layoutOrientation { return 0; }
- (NSRect)lineFragmentRectForProposedRect:(NSRect)p sweepDirection:(NSInteger)s movementDirection:(NSInteger)m remainingRect:(NSRect *)r { return [self lineFragmentRectForProposedRect:p atIndex:0 writingDirection:0 remainingRect:r]; }
@end
@implementation NSSet (XEFAppKit)
+ (NSSet *)setWithCollectionViewIndexPath:(NSIndexPath *)p { return [NSSet setWithObject:p]; } + (NSSet *)setWithCollectionViewIndexPaths:(NSArray *)p { return [NSSet setWithArray:p]; }
- (void)enumerateIndexPathsWithOptions:(NSUInteger)o usingBlock:(void (^)(NSIndexPath *, BOOL *))b { BOOL stop = NO; for (NSIndexPath *p in self) { b(p, &stop); if (stop) break; } }
@end
@implementation NSResponder (XEFMisc)
- (NSInteger)interfaceStyle { return 0; } - (void)setInterfaceStyle:(NSInteger)s {} - (BOOL)performMnemonic:(NSString *)s { return NO; }
@end
@implementation NSOpenGLPixelFormat (XEFMisc)
- (id)initWithCGLPixelFormatObj:(void *)o { return [self initWithAttributes:NULL]; } - (const void *)attributes { return NULL; } - (void)setAttributes:(const void *)a {}
@end
@implementation NSCollectionViewLayoutAttributes (XEFMisc)
+ (id)layoutAttributesForInterItemGapBeforeIndexPath:(NSIndexPath *)p { return [self layoutAttributesForItemWithIndexPath:p]; }
+ (id)layoutAttributesForSupplementaryViewOfKind:(NSString *)k withIndexPath:(NSIndexPath *)p { id a = [self layoutAttributesForItemWithIndexPath:p]; objc_setAssociatedObject(a, "xef.kind", k, OBJC_ASSOCIATION_COPY); return a; }
+ (id)layoutAttributesForDecorationViewOfKind:(NSString *)k withIndexPath:(NSIndexPath *)p { id a = [self layoutAttributesForItemWithIndexPath:p]; objc_setAssociatedObject(a, "xef.kind", k, OBJC_ASSOCIATION_COPY); return a; }
- (NSString *)representedElementKind { return objc_getAssociatedObject(self, "xef.kind"); }
@end
@implementation NSCollectionViewFlowLayout (XEFMisc)
- (BOOL)sectionAtIndexIsCollapsed:(NSUInteger)i { return [[objc_getAssociatedObject(self, "xef.coll") member:[NSNumber numberWithUnsignedInteger:i]] boolValue] || [objc_getAssociatedObject(self, "xef.coll") containsObject:[NSNumber numberWithUnsignedInteger:i]]; }
- (void)collapseSectionAtIndex:(NSUInteger)i { NSMutableSet *s = objc_getAssociatedObject(self, "xef.coll"); if (!s) { s = [NSMutableSet set]; objc_setAssociatedObject(self, "xef.coll", s, OBJC_ASSOCIATION_RETAIN); } [s addObject:[NSNumber numberWithUnsignedInteger:i]]; [self invalidateLayout]; }
- (void)expandSectionAtIndex:(NSUInteger)i { [(NSMutableSet *)objc_getAssociatedObject(self, "xef.coll") removeObject:[NSNumber numberWithUnsignedInteger:i]]; [self invalidateLayout]; }
@end
@implementation NSClipView (XEFMisc)
- (NSCursor *)documentCursor { return objc_getAssociatedObject(self, "xef.dc"); } - (void)setDocumentCursor:(NSCursor *)c { objc_setAssociatedObject(self, "xef.dc", c, OBJC_ASSOCIATION_RETAIN); }
- (void)viewBoundsChanged:(NSNotification *)n { [self setNeedsDisplay:YES]; }
@end
@implementation NSArrayController (XEFMisc)
- (void)didChangeArrangementCriteria { [self rearrangeObjects]; }
- (void)insertObjects:(NSArray *)o atArrangedObjectIndexes:(NSIndexSet *)i { NSMutableArray *c = [self content]; if (![c isKindOfClass:[NSMutableArray class]]) return; NSArray *arr = [self arrangedObjects]; NSUInteger at = [i firstIndex]; NSUInteger pos = at < [arr count] ? [c indexOfObject:[arr objectAtIndex:at]] : [c count]; if (pos == NSNotFound) pos = [c count]; for (NSUInteger k = 0; k < [o count]; k++) [c insertObject:[o objectAtIndex:k] atIndex:pos + k]; [self rearrangeObjects]; }
- (void)removeObjectAtArrangedObjectIndex:(NSUInteger)i { NSArray *arr = [self arrangedObjects]; if (i < [arr count]) [self removeObject:[arr objectAtIndex:i]]; }
@end
@implementation NSSplitView (XEFMisc)
- (void)setIsPaneSplitter:(BOOL)f { objc_setAssociatedObject(self, "xef.ps", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); } - (BOOL)isPaneSplitter { return [objc_getAssociatedObject(self, "xef.ps") boolValue]; }
@end
@implementation NSSegmentedControl (XEFMisc)
- (void)compressWithPrioritizedCompressionOptions:(NSArray *)o {} - (NSSize)minimumSizeWithPrioritizedCompressionOptions:(NSArray *)o { NSSize s = [self intrinsicContentSize]; return NSMakeSize(MAX(s.width, 1), MAX(s.height, 1)); }
@end
@implementation NSSegmentedCell (XEFMisc)
- (void)drawSegment:(NSInteger)i inFrame:(NSRect)f withView:(NSView *)v {} - (NSInteger)interiorBackgroundStyleForSegment:(NSInteger)i { return 0; }
@end
@implementation NSSecureTextFieldCell (XEFMisc)
- (BOOL)echosBullets { NSNumber *n = objc_getAssociatedObject(self, "xef.eb"); return n ? [n boolValue] : YES; } - (void)setEchosBullets:(BOOL)f { objc_setAssociatedObject(self, "xef.eb", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); }
@end
@implementation NSPopUpButtonCell (XEFMisc)
- (NSInteger)indexOfItemWithTarget:(id)t andAction:(SEL)a { NSArray *it = [self itemArray]; for (NSUInteger i = 0; i < [it count]; i++) { NSMenuItem *m = [it objectAtIndex:i]; if (a && [m target] == t && [m action] == a) return (NSInteger)i; } return -1; }
- (BOOL)validateMenuItem:(NSMenuItem *)m { return YES; }
@end
@implementation NSMutableParagraphStyle (XEFMisc)
- (NSInteger)lineBreakStrategy { return [objc_getAssociatedObject(self, "xef.lbs") integerValue]; } - (void)setLineBreakStrategy:(NSInteger)s { objc_setAssociatedObject(self, "xef.lbs", [NSNumber numberWithInteger:s], OBJC_ASSOCIATION_RETAIN); }
@end
@implementation NSParagraphStyle (XEFMisc)
- (NSInteger)lineBreakStrategy { return [objc_getAssociatedObject(self, "xef.lbs") integerValue]; }
@end
@implementation NSFileWrapper (XEFAppKit)
- (NSImage *)icon { return objc_getAssociatedObject(self, "xef.icon"); } - (void)setIcon:(NSImage *)i { objc_setAssociatedObject(self, "xef.icon", i, OBJC_ASSOCIATION_RETAIN); }
@end
@implementation NSCursor (XEFMisc)
- (id)initWithCoder:(NSCoder *)c { return [self initWithImage:[[[NSImage alloc] initWithSize:NSMakeSize(16, 16)] autorelease] hotSpot:NSZeroPoint]; }
+ (void)pop { [[NSCursor arrowCursor] pop]; }
@end
@implementation NSBrowserCell (XEFMisc)
- (NSColor *)highlightColorInView:(NSView *)v { return [NSColor selectedMenuItemColor]; }
@end
@implementation NSAppearance (XEFMisc)
- (id)initWithAppearanceNamed:(NSString *)n bundle:(NSBundle *)b { self = [self init]; _name = [n copy]; return self; }
@end
@implementation NSTextTab (XEFMisc)
+ (NSCharacterSet *)columnTerminatorsForLocale:(NSLocale *)l { return [NSCharacterSet characterSetWithCharactersInString:@".,"]; }
@end
@implementation NSBundle (XEFMisc3)
- (BOOL)loadNibFile:(NSString *)f externalNameTable:(NSDictionary *)t withZone:(NSZone *)z { NSString *n = [[f lastPathComponent] stringByDeletingPathExtension]; return [self loadNibNamed:n owner:[t objectForKey:@"NSNibOwner"] topLevelObjects:NULL]; }
+ (BOOL)loadNibFile:(NSString *)f externalNameTable:(NSDictionary *)t withZone:(NSZone *)z { return [[NSBundle mainBundle] loadNibFile:f externalNameTable:t withZone:z]; }
@end
@implementation NSURL (XEFAppKit)
+ (NSURL *)URLFromPasteboard:(NSPasteboard *)p { NSString *s = [p stringForType:@"public.file-url"]; if (!s) s = [p stringForType:@"public.url"]; return s ? [NSURL URLWithString:s] : nil; }
- (void)writeToPasteboard:(NSPasteboard *)p { [p declareTypes:[NSArray arrayWithObjects:@"public.file-url", @"public.url", NSPasteboardTypeString, nil] owner:nil]; [p setString:[self absoluteString] forType:[self isFileURL] ? @"public.file-url" : @"public.url"]; [p setString:[self absoluteString] forType:NSPasteboardTypeString]; }
- (NSArray *)writableTypesForPasteboard:(NSPasteboard *)p { return [NSArray arrayWithObjects:@"public.file-url", @"public.url", NSPasteboardTypeString, nil]; }
+ (NSArray *)readableTypesForPasteboard:(NSPasteboard *)p { return [NSArray arrayWithObjects:@"public.file-url", @"public.url", nil]; }
@end
@implementation NSString (XEFAppKit)
- (NSArray *)writableTypesForPasteboard:(NSPasteboard *)p { return [NSArray arrayWithObject:NSPasteboardTypeString]; } + (NSArray *)readableTypesForPasteboard:(NSPasteboard *)p { return [NSArray arrayWithObject:NSPasteboardTypeString]; }
@end
@implementation NSColor (XEFAppKit)
- (NSString *)catalogNameComponent { return @"System"; } - (NSString *)colorNameComponent { return [self description]; }
+ (NSArray *)readableTypesForPasteboard:(NSPasteboard *)p { return [NSArray arrayWithObject:@"com.apple.cocoa.pasteboard.color"]; } - (NSArray *)writableTypesForPasteboard:(NSPasteboard *)p { return [NSArray arrayWithObject:@"com.apple.cocoa.pasteboard.color"]; }
@end
@implementation NSAttributedString (XEFAppKit2)
- (NSArray *)writableTypesForPasteboard:(NSPasteboard *)p { return [NSArray arrayWithObjects:@"public.rtf", NSPasteboardTypeString, nil]; } + (NSArray *)readableTypesForPasteboard:(NSPasteboard *)p { return [NSArray arrayWithObjects:@"public.rtf", NSPasteboardTypeString, nil]; }
@end
@implementation NSTextStorage (XEFMisc)
- (void)setAttributeRuns:(NSArray *)a {} - (void)setParagraphs:(NSArray *)a {} - (void)setWords:(NSArray *)a {} - (void)setCharacters:(NSArray *)a {}
@end
@implementation NSBezierPath (XEFMisc)
- (void)appendBezierPathWithGlyph:(unsigned int)g inFont:(NSFont *)f { [self appendBezierPathWithGlyphs:&g count:1 inFont:f]; }
- (void)appendBezierPathWithGlyphs:(const unsigned int *)g count:(NSInteger)n inFont:(NSFont *)f { if ([self isEmpty] || ![self elementCount]) [NSException raise:NSGenericException format:@"No current point for line"]; for (NSInteger i = 0; i < n; i++) { NSSize a = [f advancementForCGGlyph:(unsigned short)g[i]]; [self relativeLineToPoint:NSMakePoint(a.width, 0)]; } }
- (void)appendBezierPathWithCGGlyph:(unsigned short)g inFont:(NSFont *)f { unsigned int x = g; [self appendBezierPathWithGlyphs:&x count:1 inFont:f]; }
- (void)appendBezierPathWithCGGlyphs:(const unsigned short *)g count:(NSInteger)n inFont:(NSFont *)f { for (NSInteger i = 0; i < n; i++) [self appendBezierPathWithCGGlyph:g[i] inFont:f]; }
- (void)appendBezierPathWithPackedGlyphs:(const char *)g {}
@end
@implementation NSWorkspace (XEFMisc)
- (void)requestAuthorizationOfType:(NSInteger)t completionHandler:(void (^)(id, NSError *))h { if (h) h(nil, nil); }
@end
@implementation NSMutableAttributedString (XEFMisc)
- (BOOL)readFromData:(NSData *)d options:(NSDictionary *)o documentAttributes:(NSDictionary **)a error:(NSError **)e {
  NSAttributedString *r = [[[NSAttributedString alloc] initWithData:d options:o documentAttributes:a error:e] autorelease]; if (!r) return NO; [self setAttributedString:r]; return YES; }
- (BOOL)readFromURL:(NSURL *)u options:(NSDictionary *)o documentAttributes:(NSDictionary **)a error:(NSError **)e { NSData *d = [NSData dataWithContentsOfURL:u options:0 error:e]; return d ? [self readFromData:d options:o documentAttributes:a error:e] : NO; }
- (BOOL)readFromData:(NSData *)d options:(NSDictionary *)o documentAttributes:(NSDictionary **)a { return [self readFromData:d options:o documentAttributes:a error:NULL]; }
- (BOOL)readFromURL:(NSURL *)u options:(NSDictionary *)o documentAttributes:(NSDictionary **)a { return [self readFromURL:u options:o documentAttributes:a error:NULL]; }
- (void)updateAttachmentsFromPath:(NSString *)p {}
@end

/* ---- the remaining odds and ends ---- */
@implementation NSMovie (XEFMisc)
- (id)initWithCoder:(NSCoder *)c { [self release]; return nil; } - (id)initWithMovie:(id)m { [self release]; return nil; } - (id)QTMovie { return nil; }
@end
static NSMutableDictionary *g_bsm_ph;
@implementation NSBindingSelectionMarker (XEFMisc)
+ (void)setDefaultPlaceholder:(id)p forMarker:(NSBindingSelectionMarker *)m onClass:(Class)c withBinding:(NSString *)b { if (!g_bsm_ph) g_bsm_ph = [[NSMutableDictionary alloc] init]; NSString *k = [NSString stringWithFormat:@"%@/%@/%@", m, NSStringFromClass(c), b]; if (p) [g_bsm_ph setObject:p forKey:k]; else [g_bsm_ph removeObjectForKey:k]; }
+ (id)defaultPlaceholderForMarker:(NSBindingSelectionMarker *)m onClass:(Class)c withBinding:(NSString *)b { return [g_bsm_ph objectForKey:[NSString stringWithFormat:@"%@/%@/%@", m, NSStringFromClass(c), b]]; }
@end
@implementation NSController (XEFMisc)
- (void)commitEditingWithDelegate:(id)d didCommitSelector:(SEL)s contextInfo:(void *)ci { BOOL ok = [self commitEditing]; if (d && s && [d respondsToSelector:s]) { void (*f)(id, SEL, id, BOOL, void *) = (void (*)(id, SEL, id, BOOL, void *))objc_msgSend; f(d, s, self, ok, ci); } }
@end
@implementation NSOpenPanel (XEFMisc3)
- (void)beginSheetForDirectory:(NSString *)d file:(NSString *)f types:(NSArray *)t modalForWindow:(NSWindow *)w modalDelegate:(id)md didEndSelector:(SEL)s contextInfo:(void *)ci {
  if (d) [self setDirectoryURL:[NSURL fileURLWithPath:d]]; if (t) [self setAllowedFileTypes:t];
  [self beginSheetModalForWindow:w completionHandler:^(NSModalResponse r) { if (md && s && [md respondsToSelector:s]) { void (*fn)(id, SEL, id, NSInteger, void *) = (void (*)(id, SEL, id, NSInteger, void *))objc_msgSend; fn(md, s, self, (NSInteger)r, ci); } }]; }
- (void)beginForDirectory:(NSString *)d file:(NSString *)f types:(NSArray *)t modelessDelegate:(id)md didEndSelector:(SEL)s contextInfo:(void *)ci {
  if (d) [self setDirectoryURL:[NSURL fileURLWithPath:d]]; if (t) [self setAllowedFileTypes:t];
  [self beginWithCompletionHandler:^(NSModalResponse r) { if (md && s && [md respondsToSelector:s]) { void (*fn)(id, SEL, id, NSInteger, void *) = (void (*)(id, SEL, id, NSInteger, void *))objc_msgSend; fn(md, s, self, (NSInteger)r, ci); } }]; }
@end
@implementation NSTableHeaderView (XEFMisc)
- (NSString *)view:(NSView *)v stringForToolTip:(NSInteger)tag point:(NSPoint)p userData:(void *)u { return nil; }
@end
@implementation NSTypesetter (XEFMisc)
- (NSUInteger)getGlyphsInRange:(NSRange)r glyphs:(NSGlyph *)g characterIndexes:(NSUInteger *)c glyphInscriptions:(NSInteger *)i elasticBits:(BOOL *)e bidiLevels:(unsigned char *)b { return 0; }
- (void)substituteGlyphsInRange:(NSRange)r withGlyphs:(NSGlyph *)g {} - (void)insertGlyph:(NSGlyph)g atGlyphIndex:(NSUInteger)i characterIndex:(NSUInteger)c {} - (void)deleteGlyphsInRange:(NSRange)r {}
@end
@implementation NSAttributedString (XEFAppKit3)
+ (id)attributedStringWithAdaptiveImageGlyph:(id)g attributes:(NSDictionary *)a { return [[[NSAttributedString alloc] initWithString:@"￼" attributes:a] autorelease]; }
- (NSFileWrapper *)fileWrapperFromRange:(NSRange)r documentAttributes:(NSDictionary *)d error:(NSError **)e { NSData *x = [self RTFFromRange:r documentAttributes:d ? d : @{}]; return x ? [[[NSFileWrapper alloc] initRegularFileWithContents:x] autorelease] : nil; }
- (NSData *)docFormatFromRange:(NSRange)r documentAttributes:(NSDictionary *)d { return nil; }
@end
@implementation NSEvent (XEFMisc)
- (id)context { return nil; }
@end
@implementation NSGraphicsContext (XEFMisc)
- (id)CIContext { return nil; } + (void)setGraphicsState:(NSInteger)g {}
@end
@implementation NSPopover (XEFMisc2)
- (id)initWithCoder:(NSCoder *)c { return [self init]; }
@end
@implementation NSTextSelection (XEFMisc) - (id)initWithCoder:(NSCoder *)c { return [self initWithLocation:((id (*)(id, SEL, NSInteger))objc_msgSend)((id)objc_getClass("NSCountableTextLocation"), sel_registerName("at:"), 0) affinity:0]; } @end
@implementation NSTextLineFragment (XEFMisc) - (id)initWithCoder:(NSCoder *)c { return [self initWithString:@"" attributes:nil range:NSMakeRange(0, 0)]; } @end
@implementation NSTextLayoutFragment (XEFMisc) - (id)initWithCoder:(NSCoder *)c { return [self initWithTextElement:nil range:nil]; } @end
@implementation NSTextContentManager (XEFMisc) - (id)initWithCoder:(NSCoder *)c { return [self init]; } @end

/* NSObject's class-level binding placeholders */
static NSMutableDictionary *g_obj_ph;
@implementation NSObject (XEFBindingPlaceholders)
+ (void)setDefaultPlaceholder:(id)p forMarker:(id)m withBinding:(NSString *)b { if (!g_obj_ph) g_obj_ph = [[NSMutableDictionary alloc] init]; NSString *k = [NSString stringWithFormat:@"%@/%@/%@", NSStringFromClass(self), m, b]; if (p) [g_obj_ph setObject:p forKey:k]; else [g_obj_ph removeObjectForKey:k]; }
+ (id)defaultPlaceholderForMarker:(id)m withBinding:(NSString *)b { return [g_obj_ph objectForKey:[NSString stringWithFormat:@"%@/%@/%@", NSStringFromClass(self), m, b]]; }
@end
