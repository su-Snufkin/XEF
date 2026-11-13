/* Bindings controllers and assorted small classes; matched against macOS by tests/darwin/mac/appkit_misc7.m. */
#import "AppKitMisc3.h"
#include <objc/runtime.h>
#include <objc/message.h>

/* ---- NSUserDefaultsController ---- */
@implementation NSUserDefaultsControllerKeyedProxy
- (id)valueForUndefinedKey:(NSString *)k { return [(NSUserDefaultsController *)_c _xefValueForKey:k]; }
- (void)setValue:(id)v forUndefinedKey:(NSString *)k { [(NSUserDefaultsController *)_c _xefSetValue:v forKey:k]; }
- (id)valueForKey:(NSString *)k { return [(NSUserDefaultsController *)_c _xefValueForKey:k]; }
- (void)setValue:(id)v forKey:(NSString *)k { [(NSUserDefaultsController *)_c _xefSetValue:v forKey:k]; }
@end
@implementation NSUserDefaultsController
+ (id)sharedUserDefaultsController { static NSUserDefaultsController *s; if (!s) s = [[self alloc] initWithDefaults:nil initialValues:nil]; return s; }
- (id)initWithDefaults:(NSUserDefaults *)d initialValues:(NSDictionary *)i { self = [super init]; _defaults = [(d ? d : [NSUserDefaults standardUserDefaults]) retain]; _init = [i copy]; _applies = YES; _staged = [[NSMutableDictionary alloc] init]; return self; }
- (id)init { return [self initWithDefaults:nil initialValues:nil]; }
- (void)dealloc { [_defaults release]; [_init release]; [_staged release]; [_proxy release]; [super dealloc]; }
- (NSUserDefaults *)defaults { return _defaults; } - (NSDictionary *)initialValues { return _init; } - (void)setInitialValues:(NSDictionary *)v { [v retain]; [_init release]; _init = v; }
- (BOOL)appliesImmediately { return _applies; } - (void)setAppliesImmediately:(BOOL)f { _applies = f; }
- (BOOL)hasUnappliedChanges { return [_staged count] > 0; }
- (id)values { if (!_proxy) { NSUserDefaultsControllerKeyedProxy *p = [[NSUserDefaultsControllerKeyedProxy alloc] init]; p->_c = self; _proxy = p; } return _proxy; }
- (id)_xefValueForKey:(NSString *)k { id v = [_staged objectForKey:k]; if (v) return v == [NSNull null] ? nil : v; v = [_defaults objectForKey:k]; return v ? v : [_init objectForKey:k]; }
- (void)_xefSetValue:(id)v forKey:(NSString *)k {
  [self willChangeValueForKey:@"hasUnappliedChanges"];
  if (_applies) { if (v) [_defaults setObject:v forKey:k]; else [_defaults removeObjectForKey:k]; } else [_staged setObject:v ? v : (id)[NSNull null] forKey:k];
  [self didChangeValueForKey:@"hasUnappliedChanges"]; }
- (void)revert:(id)s { [_staged removeAllObjects]; }
- (void)save:(id)s { for (NSString *k in _staged) { id v = [_staged objectForKey:k]; if (v == [NSNull null]) [_defaults removeObjectForKey:k]; else [_defaults setObject:v forKey:k]; } [_staged removeAllObjects]; }
- (void)revertToInitialValues:(id)s { [_staged removeAllObjects]; for (NSString *k in _init) { if (_applies) [_defaults setObject:[_init objectForKey:k] forKey:k]; else [_staged setObject:[_init objectForKey:k] forKey:k]; } }
@end

/* ---- NSDictionaryController ---- */
@implementation NSDictionaryControllerKeyValuePair
- (void)dealloc { [_key release]; [_value release]; [_loc release]; [super dealloc]; }
- (NSString *)key { return _key; } - (void)setKey:(NSString *)k { [k retain]; [_key release]; _key = k; }
- (id)value { return _value; } - (void)setValue:(id)v { [v retain]; [_value release]; _value = v; }
- (NSString *)localizedKey { return _loc ? _loc : _key; } - (void)setLocalizedKey:(NSString *)k { [k retain]; [_loc release]; _loc = k; }
- (BOOL)isExplicitlyIncluded { return _inc; }
@end
@implementation NSDictionaryController
- (id)init { self = [super init]; _ik = @"key"; _iv = @"value"; _lkd = [[NSDictionary alloc] init]; return self; }
- (void)dealloc { [_ik release]; [_iv release]; [_inc release]; [_exc release]; [_lkd release]; [_lkt release]; [super dealloc]; }
- (NSString *)initialKey { return _ik; } - (void)setInitialKey:(NSString *)k { [k retain]; [_ik release]; _ik = k; }
- (id)initialValue { return _iv; } - (void)setInitialValue:(id)v { [v retain]; [_iv release]; _iv = v; }
- (NSArray *)includedKeys { return _inc ? _inc : [NSArray array]; } - (void)setIncludedKeys:(NSArray *)k { [self willChangeValueForKey:@"arrangedObjects"]; [k retain]; [_inc release]; _inc = k; [self didChangeValueForKey:@"arrangedObjects"]; }
- (NSArray *)excludedKeys { return _exc ? _exc : [NSArray array]; } - (void)setExcludedKeys:(NSArray *)k { [self willChangeValueForKey:@"arrangedObjects"]; [k retain]; [_exc release]; _exc = k; [self didChangeValueForKey:@"arrangedObjects"]; }
- (NSDictionary *)localizedKeyDictionary { return _lkd; } - (void)setLocalizedKeyDictionary:(NSDictionary *)d { [d retain]; [_lkd release]; _lkd = d; }
- (NSString *)localizedKeyTable { return _lkt; } - (void)setLocalizedKeyTable:(NSString *)t { [t retain]; [_lkt release]; _lkt = t; }
- (void)setContent:(id)c { [self willChangeValueForKey:@"content"]; [self willChangeValueForKey:@"arrangedObjects"]; [c retain]; [_content release]; _content = c; [self didChangeValueForKey:@"arrangedObjects"]; [self didChangeValueForKey:@"content"]; }
- (void)rearrangeObjects {}
- (NSArray *)arrangedObjects {
  id c = [self content]; if (![c isKindOfClass:[NSDictionary class]]) return [NSArray array];
  NSMutableArray *out = [NSMutableArray array];
  for (NSString *k in [[c allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    if ([_exc containsObject:k]) continue;
    NSDictionaryControllerKeyValuePair *p = [[[NSDictionaryControllerKeyValuePair alloc] init] autorelease]; p->_key = [k copy]; p->_value = [[c objectForKey:k] retain]; p->_inc = [_inc containsObject:k]; p->_loc = [[_lkd objectForKey:k] retain];
    [out addObject:p]; }
  return out; }
@end

/* ---- NSPDFInfo / NSSpeechRecognizer ---- */
@implementation NSPDFInfo
- (id)init { self = [super init]; _hide = YES; _paper = NSMakeSize(612, 792); _attrs = [[NSMutableDictionary alloc] init]; return self; }
- (void)dealloc { [_url release]; [_tags release]; [_attrs release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { NSPDFInfo *c = [[[self class] alloc] init]; c->_url = [_url copy]; c->_hide = _hide; c->_tags = [_tags copy]; c->_orient = _orient; c->_paper = _paper; [c->_attrs addEntriesFromDictionary:_attrs]; return c; }
- (NSURL *)URL { return _url; } - (void)setURL:(NSURL *)u { [u retain]; [_url release]; _url = u; }
- (BOOL)isFileExtensionHidden { return _hide; } - (void)setFileExtensionHidden:(BOOL)f { _hide = f; }
- (NSArray *)tagNames { return _tags ? _tags : [NSArray array]; } - (void)setTagNames:(NSArray *)t { [t retain]; [_tags release]; _tags = t; }
- (NSInteger)orientation { return _orient; } - (void)setOrientation:(NSInteger)o { _orient = o; }
- (NSSize)paperSize { return _paper; } - (void)setPaperSize:(NSSize)s { _paper = s; }
- (NSMutableDictionary *)attributes { return _attrs; }
@end
@implementation NSSpeechRecognizer
- (id)init { self = [super init]; _fg = YES; return self; }
- (void)dealloc { [_cmds release]; [_title release]; [super dealloc]; }
- (void)startListening {} - (void)stopListening {}
- (id)delegate { return _delegate; } - (void)setDelegate:(id)d { _delegate = d; }
- (NSArray *)commands { return _cmds; } - (void)setCommands:(NSArray *)c { [c retain]; [_cmds release]; _cmds = c; }
- (NSString *)displayedCommandsTitle { return _title; } - (void)setDisplayedCommandsTitle:(NSString *)t { [t retain]; [_title release]; _title = t; }
- (BOOL)listensInForegroundOnly { return _fg; } - (void)setListensInForegroundOnly:(BOOL)f { _fg = f; }
- (BOOL)blocksOtherRecognizers { return _block; } - (void)setBlocksOtherRecognizers:(BOOL)f { _block = f; }
@end

/* ---- categories ---- */
@implementation NSSliderCell (XEFMisc)
- (void)drawKnob:(NSRect)r { [[NSColor whiteColor] set]; NSRectFill(r); } - (void)drawKnob {}
- (void)drawBarInside:(NSRect)r flipped:(BOOL)f { [[NSColor grayColor] set]; NSRectFill(r); }
- (NSInteger)indexOfTickMarkAtPoint:(NSPoint)p { return NSNotFound; } - (void)drawTickMarks {}
- (void)setTitleCell:(id)c {} - (id)titleCell { return nil; } - (void)setTitleColor:(NSColor *)c {} - (NSColor *)titleColor { return nil; } - (void)setTitleFont:(NSFont *)f {} - (NSFont *)titleFont { return nil; }
@end
@implementation NSControl (XEFMisc)
- (void)takeFloatValueFrom:(id)s { [self setFloatValue:[s floatValue]]; } - (void)takeIntegerValueFrom:(id)s { [self setIntegerValue:[s integerValue]]; }
- (NSInteger)baseWritingDirection { return [objc_getAssociatedObject(self, "xef.bwd") integerValue]; } - (void)setBaseWritingDirection:(NSInteger)d { objc_setAssociatedObject(self, "xef.bwd", [NSNumber numberWithInteger:d], OBJC_ASSOCIATION_RETAIN); }
- (NSRect)expansionFrameWithFrame:(NSRect)f { return NSZeroRect; } - (void)drawWithExpansionFrame:(NSRect)f inView:(NSView *)v {}
- (void)editWithFrame:(NSRect)f editor:(NSText *)t delegate:(id)d event:(NSEvent *)e { [[self cell] editWithFrame:f inView:self editor:t delegate:d event:e]; }
- (void)selectWithFrame:(NSRect)f editor:(NSText *)t delegate:(id)d start:(NSInteger)s length:(NSInteger)l { [[self cell] selectWithFrame:f inView:self editor:t delegate:d start:s length:l]; }
- (void)endEditing:(NSText *)t { [[self cell] endEditing:t]; }
- (void)setFloatingPointFormat:(BOOL)a left:(NSUInteger)l right:(NSUInteger)r {} - (void)setNeedsDisplay { [self setNeedsDisplay:YES]; }
- (void)invalidateIntrinsicContentSizeForCell:(NSCell *)c { [self invalidateIntrinsicContentSize]; }
@end
@implementation NSFont (XEFMisc)
+ (NSFont *)fontWithName:(NSString *)n matrix:(const CGFloat *)m { return [self fontWithName:n size:m ? m[0] : 12]; }
+ (NSFont *)systemFontOfSize:(CGFloat)s weight:(CGFloat)w width:(CGFloat)wd { return w >= 0.4 ? [self boldSystemFontOfSize:s] : [self systemFontOfSize:s]; }
- (NSFont *)fontWithSize:(CGFloat)s { return [NSFont fontWithName:[self fontName] size:s]; }
- (unsigned int)glyphWithName:(NSString *)n { return [n length] == 1 ? (unsigned int)[n characterAtIndex:0] : 0; }
- (NSSize)advancementForCGGlyph:(unsigned short)g { NSString *s = [NSString stringWithCharacters:&g length:1]; NSSize z = [s sizeWithAttributes:[NSDictionary dictionaryWithObject:self forKey:NSFontAttributeName]]; return NSMakeSize(z.width, 0); }
- (NSRect)boundingRectForCGGlyph:(unsigned short)g { NSSize a = [self advancementForCGGlyph:g]; return NSMakeRect(0, [self descender], a.width, [self ascender] - [self descender]); }
- (void)getBoundingRects:(NSRect *)r forCGGlyphs:(const unsigned short *)g count:(NSUInteger)n { for (NSUInteger i = 0; i < n; i++) r[i] = [self boundingRectForCGGlyph:g[i]]; }
- (void)getAdvancements:(NSSize *)a forCGGlyphs:(const unsigned short *)g count:(NSUInteger)n { for (NSUInteger i = 0; i < n; i++) a[i] = [self advancementForCGGlyph:g[i]]; }
- (void)getBoundingRects:(NSRect *)r forGlyphs:(const unsigned int *)g count:(NSUInteger)n { for (NSUInteger i = 0; i < n; i++) r[i] = [self boundingRectForCGGlyph:(unsigned short)g[i]]; }
- (void)getAdvancements:(NSSize *)a forGlyphs:(const unsigned int *)g count:(NSUInteger)n { for (NSUInteger i = 0; i < n; i++) a[i] = [self advancementForCGGlyph:(unsigned short)g[i]]; }
- (void)getAdvancements:(NSSize *)a forPackedGlyphs:(const void *)g length:(NSUInteger)n { const unsigned char *p = (const unsigned char *)g; for (NSUInteger i = 0; i < n; i++) a[i] = [self advancementForCGGlyph:p[i]]; }
+ (NSFont *)preferredFontForTextStyle:(NSString *)s options:(NSDictionary *)o { return [self systemFontOfSize:13]; }
@end
@implementation NSPasteboard (XEFMisc)
- (NSInteger)accessBehavior { return 2; }
- (NSUInteger)indexOfPasteboardItem:(id)i {
  NSArray *a = [self pasteboardItems]; for (NSUInteger k = 0; k < [a count]; k++) { id x = [a objectAtIndex:k]; if (x == i) return k;
    if ([[x types] isEqual:[i types]]) return k; }
  return NSNotFound; }
- (void)detectPatternsForPatterns:(NSSet *)p completionHandler:(void (^)(NSSet *, NSError *))h { if (h) h([NSSet set], nil); }
- (void)detectValuesForPatterns:(NSSet *)p completionHandler:(void (^)(NSDictionary *, NSError *))h { if (h) h([NSDictionary dictionary], nil); }
- (void)detectMetadataForTypes:(NSSet *)t completionHandler:(void (^)(id, NSError *))h { if (h) h(nil, nil); }
+ (NSPasteboard *)pasteboardByFilteringFile:(NSString *)f { NSPasteboard *p = [self pasteboardWithUniqueName]; [p declareTypes:[NSArray arrayWithObject:NSPasteboardTypeString] owner:nil]; [p setString:f forType:NSPasteboardTypeString]; return p; }
+ (NSPasteboard *)pasteboardByFilteringData:(NSData *)d ofType:(NSString *)t { NSPasteboard *p = [self pasteboardWithUniqueName]; [p declareTypes:[NSArray arrayWithObject:t] owner:nil]; [p setData:d forType:t]; return p; }
+ (NSPasteboard *)pasteboardByFilteringTypesInPasteboard:(NSPasteboard *)o { NSPasteboard *p = [self pasteboardWithUniqueName]; NSArray *ts = [o types]; [p declareTypes:ts owner:nil]; for (NSString *t in ts) { NSData *d = [o dataForType:t]; if (d) [p setData:d forType:t]; } return p; }
- (BOOL)writeFileContents:(NSString *)f { NSData *d = [NSData dataWithContentsOfFile:f]; if (!d) return NO; [self declareTypes:[NSArray arrayWithObject:@"NXFileContentsPboardType"] owner:nil]; return [self setData:d forType:@"NXFileContentsPboardType"]; }
- (NSString *)readFileContentsType:(NSString *)t toFile:(NSString *)f { NSData *d = [self dataForType:t ? t : @"NXFileContentsPboardType"]; if (!d || ![d writeToFile:f atomically:YES]) return nil; return f; }
- (BOOL)writeFileWrapper:(NSFileWrapper *)w { NSData *d = [(id)w serializedRepresentation]; if (!d) return NO; [self declareTypes:[NSArray arrayWithObject:@"NXFileContentsPboardType"] owner:nil]; return [self setData:d forType:@"NXFileContentsPboardType"]; }
- (NSFileWrapper *)readFileWrapper { NSData *d = [self dataForType:@"NXFileContentsPboardType"]; return d ? [[[objc_getClass("NSFileWrapper") alloc] initWithSerializedRepresentation:d] autorelease] : nil; }
@end
@implementation NSImageView (XEFMisc)
static NSInteger g_ivdyn = 1;
+ (NSInteger)defaultPreferredImageDynamicRange { return g_ivdyn; } + (void)setDefaultPreferredImageDynamicRange:(NSInteger)r { g_ivdyn = r; }
- (BOOL)validateMenuItem:(NSMenuItem *)m { return YES; }
- (void)addSymbolEffect:(id)e options:(id)o {} - (void)addSymbolEffect:(id)e options:(id)o animated:(BOOL)a {} - (void)removeSymbolEffectOfType:(id)t options:(id)o {} - (void)removeSymbolEffectOfType:(id)t options:(id)o animated:(BOOL)a {}
- (void)removeAllSymbolEffectsWithOptions:(id)o {} - (void)removeAllSymbolEffectsWithOptions:(id)o animated:(BOOL)a {}
- (void)setSymbolImage:(NSImage *)i withContentTransition:(id)t { [self setImage:i]; } - (void)setSymbolImage:(NSImage *)i withContentTransition:(id)t options:(id)o { [self setImage:i]; }
@end
@implementation NSDocumentController (XEFMisc)
- (id)duplicateDocumentWithContentsOfURL:(NSURL *)u copying:(BOOL)c displayName:(NSString *)n error:(NSError **)e { NSDocument *d = [self makeDocumentWithContentsOfURL:u ofType:[self typeForContentsOfURL:u error:NULL] error:e]; if (d && n) [d setDisplayName:n]; return d; }
- (void)presentError:(NSError *)e modalForWindow:(NSWindow *)w delegate:(id)d didPresentSelector:(SEL)s contextInfo:(void *)ci { BOOL r = [self presentError:e]; if (d && s && [d respondsToSelector:s]) { void (*f)(id, SEL, BOOL, void *) = (void (*)(id, SEL, BOOL, void *))objc_msgSend; f(d, s, r, ci); } }
- (id)reopenDocumentForURL:(NSURL *)u withContentsOfURL:(NSURL *)c error:(NSError **)e { NSDocument *d = [self documentForURL:u]; if (d) return d; return [self makeDocumentWithContentsOfURL:c ? c : u ofType:[self typeForContentsOfURL:u error:NULL] error:e]; }
- (id)documentForFileName:(NSString *)f { return [self documentForURL:[NSURL fileURLWithPath:f]]; } - (NSArray *)fileNamesFromRunningOpenPanel { return nil; }
- (id)makeDocumentWithContentsOfFile:(NSString *)f ofType:(NSString *)t { return [self makeDocumentWithContentsOfURL:[NSURL fileURLWithPath:f] ofType:t error:NULL]; }
- (id)makeDocumentWithContentsOfURL:(NSURL *)u ofType:(NSString *)t { return [self makeDocumentWithContentsOfURL:u ofType:t error:NULL]; }
- (id)makeUntitledDocumentOfType:(NSString *)t { return [self makeUntitledDocumentOfType:t error:NULL]; }
- (id)openDocumentWithContentsOfFile:(NSString *)f display:(BOOL)d { return [self openDocumentWithContentsOfURL:[NSURL fileURLWithPath:f] display:d]; }
- (id)openDocumentWithContentsOfURL:(NSURL *)u display:(BOOL)d { NSDocument *doc = [self documentForURL:u]; if (!doc) { doc = [self makeDocumentWithContentsOfURL:u ofType:[self typeForContentsOfURL:u error:NULL] error:NULL]; if (doc) { [self addDocument:doc]; if (d) { [doc makeWindowControllers]; [doc showWindows]; } } } return doc; }
- (id)openUntitledDocumentOfType:(NSString *)t display:(BOOL)d { NSDocument *doc = [self makeUntitledDocumentOfType:t error:NULL]; if (doc) { [self addDocument:doc]; if (d) { [doc makeWindowControllers]; [doc showWindows]; } } return doc; }
- (void)setShouldCreateUI:(BOOL)f { objc_setAssociatedObject(self, "xef.scu", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); }
@end
@implementation NSOpenGLContext (XEFMisc)
- (id)initWithCGLContextObj:(void *)c { return [self initWithFormat:nil shareContext:nil]; }
- (void)setFullScreen {} - (void)setOffScreen:(void *)b width:(int)w height:(int)h rowbytes:(int)r {} - (void)copyAttributesFromContext:(NSOpenGLContext *)c withMask:(unsigned int)m {}
- (int)currentVirtualScreen { return 0; } - (void)setCurrentVirtualScreen:(int)s {} - (void)createTexture:(unsigned int)t fromView:(NSView *)v internalFormat:(unsigned int)f {}
- (void)setPixelBuffer:(id)p cubeMapFace:(unsigned int)f mipMapLevel:(int)l currentVirtualScreen:(int)s {} - (id)pixelBuffer { return nil; } - (unsigned int)pixelBufferCubeMapFace { return 0; } - (int)pixelBufferMipMapLevel { return 0; }
- (void)setTextureImageToPixelBuffer:(id)p colorBuffer:(unsigned int)b {}
@end
