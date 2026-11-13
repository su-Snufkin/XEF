/* A long tail of small AppKit classes; matched against macOS by tests/darwin/mac/appkit_misc10.m. */
#import "AppKitMisc6.h"
#include <objc/runtime.h>

#define STR(iv, getter, setter) - (NSString *)getter { return iv; } - (void)setter:(NSString *)v { [v retain]; [iv release]; iv = v; }

@implementation NSSharingCollaborationModeRestriction
- (id)initWithDisabledMode:(NSInteger)m { return [self initWithDisabledMode:m alertTitle:nil alertMessage:nil alertDismissButtonTitle:nil alertRecoverySuggestionButtonTitle:nil alertRecoverySuggestionButtonLaunchURL:nil]; }
- (id)initWithDisabledMode:(NSInteger)m alertTitle:(NSString *)t alertMessage:(NSString *)msg { return [self initWithDisabledMode:m alertTitle:t alertMessage:msg alertDismissButtonTitle:nil alertRecoverySuggestionButtonTitle:nil alertRecoverySuggestionButtonLaunchURL:nil]; }
- (id)initWithDisabledMode:(NSInteger)m alertTitle:(NSString *)t alertMessage:(NSString *)msg alertDismissButtonTitle:(NSString *)d { return [self initWithDisabledMode:m alertTitle:t alertMessage:msg alertDismissButtonTitle:d alertRecoverySuggestionButtonTitle:nil alertRecoverySuggestionButtonLaunchURL:nil]; }
- (id)initWithDisabledMode:(NSInteger)m alertTitle:(NSString *)t alertMessage:(NSString *)msg alertDismissButtonTitle:(NSString *)d alertRecoverySuggestionButtonTitle:(NSString *)r alertRecoverySuggestionButtonLaunchURL:(NSURL *)u {
  self = [super init]; _mode = m; _t = [t copy]; _m = [msg copy]; _d = [d copy]; _r = [r copy]; _u = [u copy]; return self; }
- (void)dealloc { [_t release]; [_m release]; [_d release]; [_r release]; [_u release]; [super dealloc]; }
- (NSInteger)disabledMode { return _mode; } - (NSString *)alertTitle { return _t; } - (NSString *)alertMessage { return _m; } - (NSString *)alertDismissButtonTitle { return _d; }
- (NSString *)alertRecoverySuggestionButtonTitle { return _r; } - (NSURL *)alertRecoverySuggestionButtonLaunchURL { return _u; }
@end

@implementation NSSplitViewItemAccessoryViewController
- (id)init { self = [super init]; _auto = YES; return self; }
- (void)dealloc { [_anims release]; [super dealloc]; }
- (BOOL)isHidden { return _hid; } - (void)setHidden:(BOOL)f { _hid = f; if ([self isViewLoaded]) [[self view] setHidden:f]; }
- (BOOL)automaticallyAppliesContentInsets { return _auto; } - (void)setAutomaticallyAppliesContentInsets:(BOOL)f { _auto = f; }
- (id)animator { return self; } - (NSDictionary *)animations { return _anims ? _anims : [NSDictionary dictionary]; } - (void)setAnimations:(NSDictionary *)a { [a retain]; [_anims release]; _anims = a; }
- (id)animationForKey:(NSString *)k { id a = [_anims objectForKey:k]; return a ? a : [[self class] defaultAnimationForKey:k]; }
+ (id)defaultAnimationForKey:(NSString *)k { return [k isEqualToString:@"hidden"] ? (id)[NSNull null] : nil; }
@end

@implementation NSWindowTab
- (void)dealloc { [_title release]; [_tip release]; [_attr release]; [_acc release]; [super dealloc]; }
- (NSString *)title { return _title ? _title : @""; } - (void)setTitle:(NSString *)t { [t retain]; [_title release]; _title = t; }
- (NSAttributedString *)attributedTitle { return _attr; } - (void)setAttributedTitle:(NSAttributedString *)a { [a retain]; [_attr release]; _attr = a; }
- (NSString *)toolTip { return _tip ? _tip : @""; } - (void)setToolTip:(NSString *)t { [t retain]; [_tip release]; _tip = t; }
- (NSView *)accessoryView { return _acc; } - (void)setAccessoryView:(NSView *)v { [v retain]; [_acc release]; _acc = v; }
@end
@implementation NSWindow (XEFTab)
- (id)tab { NSWindowTab *t = objc_getAssociatedObject(self, "xef.wtab"); if (!t) { t = [[[NSWindowTab alloc] init] autorelease]; objc_setAssociatedObject(self, "xef.wtab", t, OBJC_ASSOCIATION_RETAIN); } return t; }
@end

@implementation NSTextInsertionIndicator
- (id)initWithFrame:(NSRect)f { self = [super initWithFrame:f]; _mode = 100; _color = [[NSColor textColor] retain]; _opts = 1; return self; }
- (void)dealloc { [_color release]; [_ins release]; [super dealloc]; }
- (NSInteger)displayMode { return _mode; } - (void)setDisplayMode:(NSInteger)m {}   /* macOS keeps reporting the automatic mode here */
- (NSColor *)color { return _color; } - (void)setColor:(NSColor *)c { [c retain]; [_color release]; _color = c; }
- (NSUInteger)automaticModeOptions { return _opts; } - (void)setAutomaticModeOptions:(NSUInteger)o { _opts = o; }
- (id)effectsViewInserter { return _ins; } - (void)setEffectsViewInserter:(id)i { id c = i ? [i copy] : nil; [_ins release]; _ins = c; }
@end

@implementation NSTableViewRowAction
+ (id)rowActionWithStyle:(NSInteger)s title:(NSString *)t handler:(id)h { NSTableViewRowAction *a = [[[self alloc] init] autorelease]; a->_style = s; a->_title = [t copy]; a->_h = [h copy]; a->_bg = [(s == 1 ? [NSColor redColor] : [NSColor grayColor]) retain]; return a; }
- (void)dealloc { [_title release]; [_bg release]; [_img release]; [_h release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSInteger)style { return _style; } STR(_title, title, setTitle)
- (NSColor *)backgroundColor { return _bg; } - (void)setBackgroundColor:(NSColor *)c { [c retain]; [_bg release]; _bg = c; }
- (NSImage *)image { return _img; } - (void)setImage:(NSImage *)i { [i retain]; [_img release]; _img = i; }
@end

@implementation NSPDFPanel
+ (id)panel { return [[[self alloc] init] autorelease]; }
- (id)init { self = [super init]; _name = [@"Untitled" retain]; return self; }
- (void)dealloc { [_acc release]; [_name release]; [super dealloc]; }
- (id)accessoryController { return _acc; } - (void)setAccessoryController:(id)c { [c retain]; [_acc release]; _acc = c; }
- (NSUInteger)options { return _opts; } - (void)setOptions:(NSUInteger)o { _opts = o; } STR(_name, defaultFileName, setDefaultFileName)
- (void)beginSheetWithPDFInfo:(NSPDFInfo *)i modalForWindow:(NSWindow *)w completionHandler:(void (^)(NSInteger))h { if (h) h(0); }
@end

@implementation NSDraggingImageComponent
+ (id)draggingImageComponentWithKey:(NSString *)k { return [[[self alloc] initWithKey:k] autorelease]; }
- (id)initWithKey:(NSString *)k { self = [super init]; _key = [k copy]; return self; }
- (void)dealloc { [_key release]; [_contents release]; [super dealloc]; }
STR(_key, key, setKey) - (id)contents { return _contents; } - (void)setContents:(id)c { [c retain]; [_contents release]; _contents = c; } - (NSRect)frame { return _frame; } - (void)setFrame:(NSRect)f { _frame = f; }
@end
@implementation NSDraggingItem
- (id)initWithPasteboardWriter:(id)w { self = [super init]; _item = [w retain]; return self; }
- (void)dealloc { [_item release]; [_provider release]; [super dealloc]; }
- (id)item { return _item; } - (NSRect)draggingFrame { return _frame; } - (void)setDraggingFrame:(NSRect)f { _frame = f; }
- (id)imageComponentsProvider { return _provider; } - (void)setImageComponentsProvider:(id)p { id c = p ? [p copy] : nil; [_provider release]; _provider = c; }
- (void)setDraggingFrame:(NSRect)f contents:(id)c { _frame = f; NSDraggingImageComponent *ic = [NSDraggingImageComponent draggingImageComponentWithKey:@"icon"]; [ic setContents:c]; [ic setFrame:NSMakeRect(0, 0, f.size.width, f.size.height)];
  [self setImageComponentsProvider:^NSArray *(void) { return [NSArray arrayWithObject:ic]; }]; }
- (NSArray *)imageComponents { if (!_provider) return nil; NSArray *(^p)(void) = (NSArray *(^)(void))_provider; return p(); }
@end

@implementation NSFilePromiseProvider
- (id)initWithFileType:(NSString *)t delegate:(id)d {
  if (![d respondsToSelector:@selector(filePromiseProvider:writePromiseToURL:completionHandler:)]) [NSException raise:NSInvalidArgumentException format:@"NSFilePromiseProviderDelegate is missing a ...writePromiseToURL:... method"];
  self = [super init]; _type = [t copy]; _delegate = d; return self; }
- (void)dealloc { [_type release]; [_info release]; [super dealloc]; }
STR(_type, fileType, setFileType) - (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; } - (id)userInfo { return _info; } - (void)setUserInfo:(id)u { [u retain]; [_info release]; _info = u; }
- (NSArray *)writableTypesForPasteboard:(NSPasteboard *)p { return [NSArray arrayWithObjects:@"com.apple.NSFilePromiseItemMetaData", @"com.apple.pasteboard.promised-file-url", @"com.apple.pasteboard.promised-file-content-type", @"public.url", _type, nil]; }
@end

@implementation NSTintConfiguration
+ (id)_m:(NSColor *)c adapts:(BOOL)a { NSTintConfiguration *t = [[[self alloc] init] autorelease]; t->_base = [c retain]; t->_adapts = a; return t; }
+ (id)defaultTintConfiguration { return [self _m:nil adapts:NO]; } + (id)monochromeTintConfiguration { return [self _m:nil adapts:NO]; }
+ (id)tintConfigurationWithPreferredColor:(NSColor *)c { return [self _m:c adapts:YES]; } + (id)tintConfigurationWithFixedColor:(NSColor *)c { return [self _m:c adapts:NO]; }
- (void)dealloc { [_base release]; [super dealloc]; }
- (NSColor *)baseTintColor { return _base; } - (NSColor *)equivalentContentTintColor { return _base && !_adapts ? _base : nil; } - (BOOL)adaptsToUserAccentColor { return _adapts; }
@end

@implementation NSScrubberLayoutAttributes
+ (id)layoutAttributesForItemAtIndex:(NSInteger)i { NSScrubberLayoutAttributes *a = [[[self alloc] init] autorelease]; a->_i = i; return a; }
- (id)init { self = [super init]; _a = 1; _i = -1; return self; } - (id)copyWithZone:(NSZone *)z { NSScrubberLayoutAttributes *c = [[[self class] alloc] init]; c->_i = _i; c->_f = _f; c->_a = _a; return c; }
- (NSInteger)itemIndex { return _i; } - (void)setItemIndex:(NSInteger)i { _i = i; } - (NSRect)frame { return _f; } - (void)setFrame:(NSRect)f { _f = f; } - (CGFloat)alpha { return _a; } - (void)setAlpha:(CGFloat)a { _a = a; }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[NSScrubberLayoutAttributes class]] && ((NSScrubberLayoutAttributes *)o)->_i == _i; } - (NSUInteger)hash { return (NSUInteger)_i; }
@end

@implementation NSSearchToolbarItem
- (id)initWithItemIdentifier:(NSString *)i { self = [super initWithItemIdentifier:i]; _sf = [[NSSearchField alloc] initWithFrame:NSMakeRect(0, 0, 240, 22)]; _resigns = YES; _pw = 240; return self; }
- (void)dealloc { [_sf release]; [super dealloc]; }
- (NSSearchField *)searchField { return _sf; } - (void)setSearchField:(NSSearchField *)f { [f retain]; [_sf release]; _sf = f; }
- (BOOL)resignsFirstResponderWithCancel { return _resigns; } - (void)setResignsFirstResponderWithCancel:(BOOL)f { _resigns = f; }
- (CGFloat)preferredWidthForSearchField { return _pw; } - (void)setPreferredWidthForSearchField:(CGFloat)w { _pw = w; }
- (void)beginSearchInteraction { [[_sf window] makeFirstResponder:_sf]; } - (void)endSearchInteraction { [[_sf window] makeFirstResponder:nil]; }
@end

@implementation NSGlassEffectView
- (id)initWithFrame:(NSRect)f { self = [super initWithFrame:f]; _cr = 8; return self; }
- (void)dealloc { [_cv release]; [_tint release]; [super dealloc]; }
- (NSView *)contentView { return _cv; } - (void)setContentView:(NSView *)v { [_cv removeFromSuperview]; [v retain]; [_cv release]; _cv = v; if (v) [self addSubview:v]; }
- (CGFloat)cornerRadius { return _cr; } - (void)setCornerRadius:(CGFloat)r { _cr = r; } - (NSColor *)tintColor { return _tint; } - (void)setTintColor:(NSColor *)c { [c retain]; [_tint release]; _tint = c; }
- (NSInteger)style { return _style; } - (void)setStyle:(NSInteger)s { _style = s; }
@end

@implementation NSNibConnector
- (void)dealloc { [_src release]; [_dst release]; [_label release]; [super dealloc]; }
- (id)source { return _src; } - (void)setSource:(id)s { [s retain]; [_src release]; _src = s; } - (id)destination { return _dst; } - (void)setDestination:(id)d { [d retain]; [_dst release]; _dst = d; }
STR(_label, label, setLabel) - (void)replaceObject:(id)o withObject:(id)n { if (_src == o) [self setSource:n]; if (_dst == o) [self setDestination:n]; } - (void)establishConnection {}
@end

@implementation NSOpenGLPixelBuffer
- (id)initWithTextureTarget:(unsigned int)t textureInternalFormat:(unsigned int)f textureMaxMipMapLevel:(int)m pixelsWide:(int)w pixelsHigh:(int)h { [self release]; return nil; }   /* removed from current macOS: init fails */
- (id)initWithCGLPBufferObj:(void *)o { [self release]; return nil; } - (void *)CGLPBufferObj { return NULL; }
- (int)pixelsWide { return (int)_w; } - (int)pixelsHigh { return (int)_h; } - (unsigned int)textureTarget { return (unsigned int)_tgt; } - (unsigned int)textureInternalFormat { return (unsigned int)_fmt; } - (int)textureMaxMipMapLevel { return (int)_mip; }
@end

@implementation NSMediaLibraryBrowserController
+ (id)sharedMediaLibraryBrowserController { static NSMediaLibraryBrowserController *c; if (!c) c = [[self alloc] init]; return c; }
- (BOOL)isVisible { return _vis; } - (void)setVisible:(BOOL)f { _vis = f; } - (NSRect)frame { return _f; } - (void)setFrame:(NSRect)f { _f = f; }
- (NSUInteger)mediaLibraries { return _libs; } - (void)setMediaLibraries:(NSUInteger)m { _libs = m; } - (void)togglePanel:(id)s { _vis = !_vis; }
@end

@implementation NSAccessibilityCustomRotorItemResult
- (id)initWithTargetElement:(id)e { self = [super init]; _tgt = [e retain]; _range = NSMakeRange(NSNotFound, 0); return self; }
- (id)initWithItemLoadingToken:(id)t customLabel:(NSString *)l { self = [super init]; _tok = [t retain]; _label = [l copy]; _range = NSMakeRange(NSNotFound, 0); return self; }
- (void)dealloc { [_tgt release]; [_tok release]; [_label release]; [super dealloc]; }
- (id)targetElement { return _tgt; } - (id)itemLoadingToken { return _tok; } - (NSRange)targetRange { return _range; } - (void)setTargetRange:(NSRange)r { _range = r; } STR(_label, customLabel, setCustomLabel)
@end

@implementation NSSharingServicePickerTouchBarItem
- (id)initWithIdentifier:(NSString *)i { self = [super initWithIdentifier:i]; _en = YES; _title = [@"" retain]; _img = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)]; return self; }
- (void)dealloc { [_title release]; [_img release]; [super dealloc]; }
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; } - (BOOL)isEnabled { return _en; } - (void)setEnabled:(BOOL)f { _en = f; }
STR(_title, buttonTitle, setButtonTitle) - (NSImage *)buttonImage { return _img; } - (void)setButtonImage:(NSImage *)i { [i retain]; [_img release]; _img = i; }
@end

@implementation NSTokenField (XEFMisc)
/* the field's cell is a plain NSTextFieldCell on this host: keep the token settings here and mirror them into a real NSTokenFieldCell */
- (id)_xefTC { id c = [self cell]; return [c respondsToSelector:@selector(tokenStyle)] ? c : nil; }
- (NSInteger)tokenStyle { return [objc_getAssociatedObject(self, "xef.ts") integerValue]; } - (void)setTokenStyle:(NSInteger)s { objc_setAssociatedObject(self, "xef.ts", [NSNumber numberWithInteger:s], OBJC_ASSOCIATION_RETAIN); [[self _xefTC] setTokenStyle:s]; }
- (NSTimeInterval)completionDelay { return [objc_getAssociatedObject(self, "xef.cd") doubleValue]; } - (void)setCompletionDelay:(NSTimeInterval)d { objc_setAssociatedObject(self, "xef.cd", [NSNumber numberWithDouble:d], OBJC_ASSOCIATION_RETAIN); [[self _xefTC] setCompletionDelay:d]; }
+ (NSTimeInterval)defaultCompletionDelay { return 0; }
- (NSCharacterSet *)tokenizingCharacterSet { NSCharacterSet *c = objc_getAssociatedObject(self, "xef.tcs"); return c ? c : [NSCharacterSet characterSetWithCharactersInString:@","]; } - (void)setTokenizingCharacterSet:(NSCharacterSet *)c { objc_setAssociatedObject(self, "xef.tcs", c, OBJC_ASSOCIATION_RETAIN); [[self _xefTC] setTokenizingCharacterSet:c]; }
@end
@implementation NSObjectController (XEFMisc)
- (BOOL)validateUserInterfaceItem:(id)i { return NO; } - (void)setManagedObjectContext:(id)c { objc_setAssociatedObject(self, "xef.moc", c, OBJC_ASSOCIATION_RETAIN); }
- (NSString *)entityName { return objc_getAssociatedObject(self, "xef.en"); } - (void)setEntityName:(NSString *)n { objc_setAssociatedObject(self, "xef.en", [[n copy] autorelease], OBJC_ASSOCIATION_RETAIN); }
- (NSPredicate *)fetchPredicate { return objc_getAssociatedObject(self, "xef.fp"); } - (void)setFetchPredicate:(NSPredicate *)p { objc_setAssociatedObject(self, "xef.fp", p, OBJC_ASSOCIATION_RETAIN); }
- (id)defaultFetchRequest { [NSException raise:NSInternalInconsistencyException format:@"Cannot perform operation without a managed object context"]; return nil; }
@end
@implementation NSCollectionView (XEFMisc2)
- (id)newItemForRepresentedObject:(id)o { id p = [self itemPrototype]; if (!p) return nil; id c = [p copy]; [c setRepresentedObject:o]; return c; }
- (id)itemPrototype { return objc_getAssociatedObject(self, "xef.ip"); } - (void)setItemPrototype:(id)p { objc_setAssociatedObject(self, "xef.ip", p, OBJC_ASSOCIATION_RETAIN); }
- (NSUInteger)maxNumberOfRows { return [objc_getAssociatedObject(self, "xef.mr") unsignedIntegerValue]; } - (void)setMaxNumberOfRows:(NSUInteger)n { objc_setAssociatedObject(self, "xef.mr", [NSNumber numberWithUnsignedInteger:n], OBJC_ASSOCIATION_RETAIN); }
- (NSUInteger)maxNumberOfColumns { return [objc_getAssociatedObject(self, "xef.mc") unsignedIntegerValue]; } - (void)setMaxNumberOfColumns:(NSUInteger)n { objc_setAssociatedObject(self, "xef.mc", [NSNumber numberWithUnsignedInteger:n], OBJC_ASSOCIATION_RETAIN); }
- (NSSize)minItemSize { return [objc_getAssociatedObject(self, "xef.mis") sizeValue]; } - (void)setMinItemSize:(NSSize)s { objc_setAssociatedObject(self, "xef.mis", [NSValue valueWithSize:s], OBJC_ASSOCIATION_RETAIN); }
- (NSSize)maxItemSize { return [objc_getAssociatedObject(self, "xef.mxs") sizeValue]; } - (void)setMaxItemSize:(NSSize)s { objc_setAssociatedObject(self, "xef.mxs", [NSValue valueWithSize:s], OBJC_ASSOCIATION_RETAIN); }
@end
@implementation NSTextView (XEFMisc2)
- (id)initUsingTextLayoutManager:(BOOL)f { return [self initWithFrame:NSZeroRect]; } + (id)textViewUsingTextLayoutManager:(BOOL)f { return [[[self alloc] initUsingTextLayoutManager:f] autorelease]; }
- (void)toggleTraditionalCharacterShape:(id)s {} - (NSUInteger)draggingSession:(id)s sourceOperationMaskForDraggingContext:(NSInteger)c { return c == 0 ? 1 : 3; }
- (NSInteger)conversationIdentifier { [NSException raise:NSInternalInconsistencyException format:@"conversationIdentifier should be using NSLayoutManager"]; return 0; }
- (BOOL)dragSelectionWithEvent:(NSEvent *)e offset:(NSSize)o slideBack:(BOOL)b { return NO; } - (NSImage *)dragImageForSelectionWithEvent:(NSEvent *)e origin:(NSPointPointer)o { if (o) *o = NSZeroPoint; return nil; }
- (NSUInteger)dragOperationForDraggingInfo:(id)i type:(NSString *)t { return 1; } - (NSInteger)allowedWritingToolsResultOptions { return 0; }
- (void)handleTextCheckingResults:(NSArray *)r forRange:(NSRange)rg types:(NSUInteger)t options:(NSDictionary *)o orthography:(id)or wordCount:(NSInteger)n {}
- (NSInteger)inlinePredictionType { return 0; } - (NSInteger)mathExpressionCompletionType { return 0; } - (NSArray *)quickLookPreviewableItemsInRanges:(NSArray *)r { return [NSArray array]; }
- (void)drawTextHighlightBackgroundForTextRange:(id)r origin:(NSPoint)o {}
@end
