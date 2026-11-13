/* A long tail of small AppKit classes (AppKitMisc6.m). */
#import "AppKitMisc5.h"

@interface NSSharingCollaborationModeRestriction : NSObject { @public NSInteger _mode; NSString *_t, *_m, *_d, *_r; NSURL *_u; }
- (id)initWithDisabledMode:(NSInteger)m; - (id)initWithDisabledMode:(NSInteger)m alertTitle:(NSString *)t alertMessage:(NSString *)msg; - (id)initWithDisabledMode:(NSInteger)m alertTitle:(NSString *)t alertMessage:(NSString *)msg alertDismissButtonTitle:(NSString *)d;
- (id)initWithDisabledMode:(NSInteger)m alertTitle:(NSString *)t alertMessage:(NSString *)msg alertDismissButtonTitle:(NSString *)d alertRecoverySuggestionButtonTitle:(NSString *)r alertRecoverySuggestionButtonLaunchURL:(NSURL *)u;
- (NSInteger)disabledMode; - (NSString *)alertTitle; - (NSString *)alertMessage; - (NSString *)alertDismissButtonTitle; - (NSString *)alertRecoverySuggestionButtonTitle; - (NSURL *)alertRecoverySuggestionButtonLaunchURL;
@end
@interface NSSplitViewItemAccessoryViewController : NSViewController { @public BOOL _hid, _auto; NSDictionary *_anims; }
- (BOOL)isHidden; - (void)setHidden:(BOOL)f; - (BOOL)automaticallyAppliesContentInsets; - (void)setAutomaticallyAppliesContentInsets:(BOOL)f; - (id)animator; - (NSDictionary *)animations; - (void)setAnimations:(NSDictionary *)a; - (id)animationForKey:(NSString *)k; + (id)defaultAnimationForKey:(NSString *)k;
@end
@interface NSWindowTab : NSObject { @public NSString *_title, *_tip; NSAttributedString *_attr; NSView *_acc; }
- (NSString *)title; - (void)setTitle:(NSString *)t; - (NSAttributedString *)attributedTitle; - (void)setAttributedTitle:(NSAttributedString *)a; - (NSString *)toolTip; - (void)setToolTip:(NSString *)t; - (NSView *)accessoryView; - (void)setAccessoryView:(NSView *)v;
@end
@interface NSTextInsertionIndicator : NSView { @public NSInteger _mode; NSColor *_color; NSUInteger _opts; id _ins; }
- (NSInteger)displayMode; - (void)setDisplayMode:(NSInteger)m; - (NSColor *)color; - (void)setColor:(NSColor *)c; - (NSUInteger)automaticModeOptions; - (void)setAutomaticModeOptions:(NSUInteger)o; - (id)effectsViewInserter; - (void)setEffectsViewInserter:(id)i;
@end
@interface NSTableViewRowAction : NSObject <NSCopying> { @public NSInteger _style; NSString *_title; NSColor *_bg; NSImage *_img; id _h; }
+ (id)rowActionWithStyle:(NSInteger)s title:(NSString *)t handler:(id)h; - (NSInteger)style; - (NSString *)title; - (void)setTitle:(NSString *)t; - (NSColor *)backgroundColor; - (void)setBackgroundColor:(NSColor *)c; - (NSImage *)image; - (void)setImage:(NSImage *)i;
@end
@interface NSPDFPanel : NSObject { @public id _acc; NSUInteger _opts; NSString *_name; }
+ (id)panel; - (id)accessoryController; - (void)setAccessoryController:(id)c; - (NSUInteger)options; - (void)setOptions:(NSUInteger)o; - (NSString *)defaultFileName; - (void)setDefaultFileName:(NSString *)n;
- (void)beginSheetWithPDFInfo:(NSPDFInfo *)i modalForWindow:(NSWindow *)w completionHandler:(void (^)(NSInteger))h;
@end
@interface NSDraggingImageComponent : NSObject { @public NSString *_key; id _contents; NSRect _frame; }
+ (id)draggingImageComponentWithKey:(NSString *)k; - (id)initWithKey:(NSString *)k; - (NSString *)key; - (void)setKey:(NSString *)k; - (id)contents; - (void)setContents:(id)c; - (NSRect)frame; - (void)setFrame:(NSRect)f;
@end
@interface NSDraggingItem : NSObject { @public id _item; NSRect _frame; id _provider; }
- (id)initWithPasteboardWriter:(id)w; - (id)item; - (NSRect)draggingFrame; - (void)setDraggingFrame:(NSRect)f; - (id)imageComponentsProvider; - (void)setImageComponentsProvider:(id)p; - (void)setDraggingFrame:(NSRect)f contents:(id)c; - (NSArray *)imageComponents;
@end
@interface NSFilePromiseProvider : NSObject { @public NSString *_type; id _delegate, _info; }
- (id)initWithFileType:(NSString *)t delegate:(id)d; - (NSString *)fileType; - (void)setFileType:(NSString *)t; - (id)delegate; - (void)setDelegate:(id)d; - (id)userInfo; - (void)setUserInfo:(id)u; - (NSArray *)writableTypesForPasteboard:(NSPasteboard *)p;
@end
@interface NSTintConfiguration : NSObject { @public NSColor *_base; BOOL _adapts, _fixed; }
+ (id)defaultTintConfiguration; + (id)monochromeTintConfiguration; + (id)tintConfigurationWithPreferredColor:(NSColor *)c; + (id)tintConfigurationWithFixedColor:(NSColor *)c; - (NSColor *)baseTintColor; - (NSColor *)equivalentContentTintColor; - (BOOL)adaptsToUserAccentColor;
@end
@interface NSScrubberLayoutAttributes : NSObject <NSCopying> { @public NSInteger _i; NSRect _f; CGFloat _a; }
+ (id)layoutAttributesForItemAtIndex:(NSInteger)i; - (NSInteger)itemIndex; - (void)setItemIndex:(NSInteger)i; - (NSRect)frame; - (void)setFrame:(NSRect)f; - (CGFloat)alpha; - (void)setAlpha:(CGFloat)a;
@end
@interface NSSearchToolbarItem : NSToolbarItem { @public NSSearchField *_sf; BOOL _resigns; CGFloat _pw; }
- (NSSearchField *)searchField; - (void)setSearchField:(NSSearchField *)f; - (BOOL)resignsFirstResponderWithCancel; - (void)setResignsFirstResponderWithCancel:(BOOL)f; - (CGFloat)preferredWidthForSearchField; - (void)setPreferredWidthForSearchField:(CGFloat)w;
- (void)beginSearchInteraction; - (void)endSearchInteraction;
@end
@interface NSGlassEffectView : NSView { @public NSView *_cv; CGFloat _cr; NSColor *_tint; NSInteger _style; }
- (NSView *)contentView; - (void)setContentView:(NSView *)v; - (CGFloat)cornerRadius; - (void)setCornerRadius:(CGFloat)r; - (NSColor *)tintColor; - (void)setTintColor:(NSColor *)c; - (NSInteger)style; - (void)setStyle:(NSInteger)s;
@end
@interface NSNibConnector : NSObject { @public id _src, _dst; NSString *_label; }
- (id)source; - (void)setSource:(id)s; - (id)destination; - (void)setDestination:(id)d; - (NSString *)label; - (void)setLabel:(NSString *)l; - (void)replaceObject:(id)o withObject:(id)n; - (void)establishConnection;
@end
@interface NSOpenGLPixelBuffer : NSObject { @public NSInteger _w, _h, _tgt, _fmt, _mip; }
- (id)initWithTextureTarget:(unsigned int)t textureInternalFormat:(unsigned int)f textureMaxMipMapLevel:(int)m pixelsWide:(int)w pixelsHigh:(int)h; - (id)initWithCGLPBufferObj:(void *)o; - (void *)CGLPBufferObj;
- (int)pixelsWide; - (int)pixelsHigh; - (unsigned int)textureTarget; - (unsigned int)textureInternalFormat; - (int)textureMaxMipMapLevel;
@end
@interface NSMediaLibraryBrowserController : NSObject { @public BOOL _vis; NSRect _f; NSUInteger _libs; }
+ (id)sharedMediaLibraryBrowserController; - (BOOL)isVisible; - (void)setVisible:(BOOL)f; - (NSRect)frame; - (void)setFrame:(NSRect)f; - (NSUInteger)mediaLibraries; - (void)setMediaLibraries:(NSUInteger)m; - (void)togglePanel:(id)s;
@end
@interface NSAccessibilityCustomRotorItemResult : NSObject { @public id _tgt, _tok; NSRange _range; NSString *_label; }
- (id)initWithTargetElement:(id)e; - (id)initWithItemLoadingToken:(id)t customLabel:(NSString *)l; - (id)targetElement; - (id)itemLoadingToken; - (NSRange)targetRange; - (void)setTargetRange:(NSRange)r; - (NSString *)customLabel; - (void)setCustomLabel:(NSString *)l;
@end
@interface NSSharingServicePickerTouchBarItem : NSTouchBarItem { @public id _delegate; BOOL _en; NSString *_title; NSImage *_img; }
- (id)delegate; - (void)setDelegate:(id)d; - (BOOL)isEnabled; - (void)setEnabled:(BOOL)f; - (NSString *)buttonTitle; - (void)setButtonTitle:(NSString *)t; - (NSImage *)buttonImage; - (void)setButtonImage:(NSImage *)i;
@end
@interface NSTokenField (XEFMisc)
- (NSInteger)tokenStyle; - (void)setTokenStyle:(NSInteger)s; - (NSTimeInterval)completionDelay; - (void)setCompletionDelay:(NSTimeInterval)d; + (NSTimeInterval)defaultCompletionDelay; - (NSCharacterSet *)tokenizingCharacterSet; - (void)setTokenizingCharacterSet:(NSCharacterSet *)c;
@end
@interface NSObjectController (XEFMisc)
- (BOOL)validateUserInterfaceItem:(id)i; - (void)setManagedObjectContext:(id)c; - (NSString *)entityName; - (void)setEntityName:(NSString *)n; - (NSPredicate *)fetchPredicate; - (void)setFetchPredicate:(NSPredicate *)p; - (id)defaultFetchRequest;
@end
@interface NSCollectionView (XEFMisc2)
- (id)newItemForRepresentedObject:(id)o; - (id)itemPrototype; - (void)setItemPrototype:(id)p; - (NSUInteger)maxNumberOfRows; - (void)setMaxNumberOfRows:(NSUInteger)n; - (NSUInteger)maxNumberOfColumns; - (void)setMaxNumberOfColumns:(NSUInteger)n;
- (NSSize)minItemSize; - (void)setMinItemSize:(NSSize)s; - (NSSize)maxItemSize; - (void)setMaxItemSize:(NSSize)s;
@end
@interface NSTextView (XEFMisc2)
- (id)initUsingTextLayoutManager:(BOOL)f; + (id)textViewUsingTextLayoutManager:(BOOL)f; - (void)toggleTraditionalCharacterShape:(id)s; - (NSUInteger)draggingSession:(id)s sourceOperationMaskForDraggingContext:(NSInteger)c;
- (NSInteger)conversationIdentifier; - (BOOL)dragSelectionWithEvent:(NSEvent *)e offset:(NSSize)o slideBack:(BOOL)b; - (NSImage *)dragImageForSelectionWithEvent:(NSEvent *)e origin:(NSPointPointer)o; - (NSUInteger)dragOperationForDraggingInfo:(id)i type:(NSString *)t;
- (NSInteger)allowedWritingToolsResultOptions; - (void)handleTextCheckingResults:(NSArray *)r forRange:(NSRange)rg types:(NSUInteger)t options:(NSDictionary *)o orthography:(id)or wordCount:(NSInteger)n;
- (NSInteger)inlinePredictionType; - (NSInteger)mathExpressionCompletionType; - (NSArray *)quickLookPreviewableItemsInRanges:(NSArray *)r; - (void)drawTextHighlightBackgroundForTextRange:(id)r origin:(NSPoint)o;
@end
