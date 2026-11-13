/* Bindings controllers and assorted small classes (AppKitMisc3.m). */
#import "AppKitMisc2.h"
@class NSFileWrapper;

@interface NSUserDefaultsControllerKeyedProxy : NSObject { @public id _c; }
@end
@interface NSUserDefaultsController : NSController { @public NSUserDefaults *_defaults; NSDictionary *_init; BOOL _applies; NSMutableDictionary *_staged; id _proxy; }
+ (id)sharedUserDefaultsController; - (id)initWithDefaults:(NSUserDefaults *)d initialValues:(NSDictionary *)i; - (NSUserDefaults *)defaults; - (NSDictionary *)initialValues; - (void)setInitialValues:(NSDictionary *)v;
- (BOOL)appliesImmediately; - (void)setAppliesImmediately:(BOOL)f; - (BOOL)hasUnappliedChanges; - (id)values; - (id)_xefValueForKey:(NSString *)k; - (void)_xefSetValue:(id)v forKey:(NSString *)k; - (void)revert:(id)s; - (void)save:(id)s; - (void)revertToInitialValues:(id)s;
@end

@interface NSDictionaryControllerKeyValuePair : NSObject { @public NSString *_key; id _value; NSString *_loc; BOOL _inc; NSDictionary *_owner; }
- (NSString *)key; - (void)setKey:(NSString *)k; - (id)value; - (void)setValue:(id)v; - (NSString *)localizedKey; - (void)setLocalizedKey:(NSString *)k; - (BOOL)isExplicitlyIncluded;
@end
@interface NSDictionaryController : NSArrayController { @public NSString *_ik; id _iv; NSArray *_inc, *_exc; NSDictionary *_lkd; NSString *_lkt; }
- (NSString *)initialKey; - (void)setInitialKey:(NSString *)k; - (id)initialValue; - (void)setInitialValue:(id)v; - (NSArray *)includedKeys; - (void)setIncludedKeys:(NSArray *)k;
- (NSArray *)excludedKeys; - (void)setExcludedKeys:(NSArray *)k; - (NSDictionary *)localizedKeyDictionary; - (void)setLocalizedKeyDictionary:(NSDictionary *)d; - (NSString *)localizedKeyTable; - (void)setLocalizedKeyTable:(NSString *)t;
@end

@interface NSPDFInfo : NSObject <NSCopying> { @public NSURL *_url; BOOL _hide; NSArray *_tags; NSInteger _orient; NSSize _paper; NSMutableDictionary *_attrs; }
- (NSURL *)URL; - (void)setURL:(NSURL *)u; - (BOOL)isFileExtensionHidden; - (void)setFileExtensionHidden:(BOOL)f; - (NSArray *)tagNames; - (void)setTagNames:(NSArray *)t;
- (NSInteger)orientation; - (void)setOrientation:(NSInteger)o; - (NSSize)paperSize; - (void)setPaperSize:(NSSize)s; - (NSMutableDictionary *)attributes;
@end

@interface NSSpeechRecognizer : NSObject { @public id _delegate; NSArray *_cmds; NSString *_title; BOOL _fg, _block; }
- (void)startListening; - (void)stopListening; - (id)delegate; - (void)setDelegate:(id)d; - (NSArray *)commands; - (void)setCommands:(NSArray *)c; - (NSString *)displayedCommandsTitle; - (void)setDisplayedCommandsTitle:(NSString *)t;
- (BOOL)listensInForegroundOnly; - (void)setListensInForegroundOnly:(BOOL)f; - (BOOL)blocksOtherRecognizers; - (void)setBlocksOtherRecognizers:(BOOL)f;
@end

@interface NSSliderCell (XEFMisc)
- (void)drawKnob:(NSRect)r; - (void)drawKnob; - (void)drawBarInside:(NSRect)r flipped:(BOOL)f; - (NSInteger)indexOfTickMarkAtPoint:(NSPoint)p; - (void)drawTickMarks;
- (void)setTitleCell:(id)c; - (id)titleCell; - (void)setTitleColor:(NSColor *)c; - (NSColor *)titleColor; - (void)setTitleFont:(NSFont *)f; - (NSFont *)titleFont;
@end
@interface NSControl (XEFMisc)
- (void)takeFloatValueFrom:(id)s; - (void)takeIntegerValueFrom:(id)s; - (NSInteger)baseWritingDirection; - (void)setBaseWritingDirection:(NSInteger)d;
- (NSRect)expansionFrameWithFrame:(NSRect)f; - (void)drawWithExpansionFrame:(NSRect)f inView:(NSView *)v; - (void)editWithFrame:(NSRect)f editor:(NSText *)t delegate:(id)d event:(NSEvent *)e;
- (void)selectWithFrame:(NSRect)f editor:(NSText *)t delegate:(id)d start:(NSInteger)s length:(NSInteger)l; - (void)endEditing:(NSText *)t; - (void)setFloatingPointFormat:(BOOL)a left:(NSUInteger)l right:(NSUInteger)r;
- (void)setNeedsDisplay; - (void)invalidateIntrinsicContentSizeForCell:(NSCell *)c;
@end
@interface NSFont (XEFMisc)
+ (NSFont *)fontWithName:(NSString *)n matrix:(const CGFloat *)m; + (NSFont *)systemFontOfSize:(CGFloat)s weight:(CGFloat)w width:(CGFloat)wd; - (NSFont *)fontWithSize:(CGFloat)s;
- (NSRect)boundingRectForCGGlyph:(unsigned short)g; - (NSSize)advancementForCGGlyph:(unsigned short)g; - (void)getBoundingRects:(NSRect *)r forCGGlyphs:(const unsigned short *)g count:(NSUInteger)n;
- (void)getAdvancements:(NSSize *)a forCGGlyphs:(const unsigned short *)g count:(NSUInteger)n; - (unsigned int)glyphWithName:(NSString *)n;
- (void)getBoundingRects:(NSRect *)r forGlyphs:(const unsigned int *)g count:(NSUInteger)n; - (void)getAdvancements:(NSSize *)a forGlyphs:(const unsigned int *)g count:(NSUInteger)n;
- (void)getAdvancements:(NSSize *)a forPackedGlyphs:(const void *)g length:(NSUInteger)n; + (NSFont *)preferredFontForTextStyle:(NSString *)s options:(NSDictionary *)o;
@end
@interface NSPasteboard (XEFMisc)
- (NSInteger)accessBehavior; - (NSUInteger)indexOfPasteboardItem:(id)i; - (void)detectPatternsForPatterns:(NSSet *)p completionHandler:(void (^)(NSSet *, NSError *))h;
- (void)detectValuesForPatterns:(NSSet *)p completionHandler:(void (^)(NSDictionary *, NSError *))h; - (void)detectMetadataForTypes:(NSSet *)t completionHandler:(void (^)(id, NSError *))h;
+ (NSPasteboard *)pasteboardByFilteringFile:(NSString *)f; + (NSPasteboard *)pasteboardByFilteringData:(NSData *)d ofType:(NSString *)t; + (NSPasteboard *)pasteboardByFilteringTypesInPasteboard:(NSPasteboard *)p;
- (BOOL)writeFileContents:(NSString *)f; - (NSString *)readFileContentsType:(NSString *)t toFile:(NSString *)f; - (BOOL)writeFileWrapper:(NSFileWrapper *)w; - (NSFileWrapper *)readFileWrapper;
@end
@interface NSImageView (XEFMisc)
+ (NSInteger)defaultPreferredImageDynamicRange; + (void)setDefaultPreferredImageDynamicRange:(NSInteger)r; - (BOOL)validateMenuItem:(NSMenuItem *)m;
- (void)addSymbolEffect:(id)e options:(id)o; - (void)addSymbolEffect:(id)e options:(id)o animated:(BOOL)a; - (void)removeSymbolEffectOfType:(id)t options:(id)o; - (void)removeSymbolEffectOfType:(id)t options:(id)o animated:(BOOL)a;
- (void)removeAllSymbolEffectsWithOptions:(id)o; - (void)removeAllSymbolEffectsWithOptions:(id)o animated:(BOOL)a; - (void)setSymbolImage:(NSImage *)i withContentTransition:(id)t; - (void)setSymbolImage:(NSImage *)i withContentTransition:(id)t options:(id)o;
@end
@interface NSDocumentController (XEFMisc)
- (id)duplicateDocumentWithContentsOfURL:(NSURL *)u copying:(BOOL)c displayName:(NSString *)n error:(NSError **)e; - (void)presentError:(NSError *)e modalForWindow:(NSWindow *)w delegate:(id)d didPresentSelector:(SEL)s contextInfo:(void *)ci;
- (id)reopenDocumentForURL:(NSURL *)u withContentsOfURL:(NSURL *)c error:(NSError **)e; - (id)documentForFileName:(NSString *)f; - (NSArray *)fileNamesFromRunningOpenPanel;
- (id)makeDocumentWithContentsOfFile:(NSString *)f ofType:(NSString *)t; - (id)makeDocumentWithContentsOfURL:(NSURL *)u ofType:(NSString *)t; - (id)makeUntitledDocumentOfType:(NSString *)t;
- (id)openDocumentWithContentsOfFile:(NSString *)f display:(BOOL)d; - (id)openDocumentWithContentsOfURL:(NSURL *)u display:(BOOL)d; - (id)openUntitledDocumentOfType:(NSString *)t display:(BOOL)d; - (void)setShouldCreateUI:(BOOL)f;
@end
@interface NSOpenGLContext (XEFMisc)
- (id)initWithCGLContextObj:(void *)c; - (void)setFullScreen; - (void)setOffScreen:(void *)b width:(int)w height:(int)h rowbytes:(int)r; - (void)copyAttributesFromContext:(NSOpenGLContext *)c withMask:(unsigned int)m;
- (int)currentVirtualScreen; - (void)setCurrentVirtualScreen:(int)s; - (void)createTexture:(unsigned int)t fromView:(NSView *)v internalFormat:(unsigned int)f;
- (void)setPixelBuffer:(id)p cubeMapFace:(unsigned int)f mipMapLevel:(int)l currentVirtualScreen:(int)s; - (id)pixelBuffer; - (unsigned int)pixelBufferCubeMapFace; - (int)pixelBufferMipMapLevel; - (void)setTextureImageToPixelBuffer:(id)p colorBuffer:(unsigned int)b;
@end
