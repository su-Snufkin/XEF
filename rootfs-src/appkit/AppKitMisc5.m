/* Dock tile, menu badge, glyph info, accessibility actions/rotors, attachment cells, predicate row templates and small extras.
   Matched against macOS by tests/darwin/mac/appkit_misc9.m. */
#import "AppKitMisc5.h"
#include <objc/runtime.h>

@implementation NSDockTile
- (id)init { self = [super init]; _owner = NSApp; return self; }
- (void)dealloc { [_cv release]; [_badge release]; [super dealloc]; }
- (NSSize)size { return NSMakeSize(128, 128); } - (NSView *)contentView { return _cv; } - (void)setContentView:(NSView *)v { [v retain]; [_cv release]; _cv = v; }
- (void)display {} - (BOOL)showsApplicationBadge { return _showsBadge; } - (void)setShowsApplicationBadge:(BOOL)f { _showsBadge = f; }
- (NSString *)badgeLabel { return _badge; } - (void)setBadgeLabel:(NSString *)l { [l retain]; [_badge release]; _badge = l; } - (id)owner { return _owner; }
@end

@implementation NSMenuItemBadge
+ (id)_t:(NSInteger)t n:(NSInteger)n { return [[[self alloc] initWithCount:n type:t] autorelease]; }
+ (id)updatesWithCount:(NSInteger)n { return [self _t:1 n:n]; } + (id)newItemsWithCount:(NSInteger)n { return [[self alloc] initWithCount:n type:2]; }   /* "new" family: the caller owns the result */ + (id)alertsWithCount:(NSInteger)n { return [self _t:3 n:n]; }
- (id)initWithCount:(NSInteger)n type:(NSInteger)t { self = [super init]; _count = n; _type = t; return self; } - (id)initWithCount:(NSInteger)n { return [self initWithCount:n type:0]; }
- (id)initWithString:(NSString *)s { self = [super init]; _str = [s copy]; return self; }
- (void)dealloc { [_str release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (NSInteger)itemCount { return _count; } - (NSInteger)type { return _type; }
- (NSString *)stringValue { if (_str) return _str; switch (_type) { case 1: return [NSString stringWithFormat:@"%ld updates", (long)_count]; case 2: return [NSString stringWithFormat:@"%ld new items", (long)_count]; case 3: return [NSString stringWithFormat:@"%ld alerts", (long)_count]; default: return [NSString stringWithFormat:@"%ld", (long)_count]; } }
@end

@implementation NSGlyphInfo
+ (id)_m:(NSString *)b { NSGlyphInfo *g = [[[self alloc] init] autorelease]; g->_base = [b copy]; return g; }
+ (id)glyphInfoWithCGGlyph:(unsigned short)g forFont:(NSFont *)f baseString:(NSString *)b { NSGlyphInfo *x = [self _m:b]; x->_gid = g; return x; }
+ (id)glyphInfoWithGlyphName:(NSString *)n forFont:(NSFont *)f baseString:(NSString *)b { NSGlyphInfo *x = [self _m:b]; x->_name = [n copy]; return x; }
+ (id)glyphInfoWithGlyph:(unsigned int)g forFont:(NSFont *)f baseString:(NSString *)b { NSGlyphInfo *x = [self _m:b]; x->_gid = (unsigned short)g; return x; }
+ (id)glyphInfoWithCharacterIdentifier:(NSUInteger)c collection:(NSInteger)col baseString:(NSString *)b { NSGlyphInfo *x = [self _m:b]; x->_cid = c; x->_coll = (NSUInteger)col; return x; }
- (void)dealloc { [_base release]; [_name release]; [super dealloc]; } - (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (unsigned short)glyphID { return _gid; } - (NSString *)baseString { return _base; } - (NSString *)glyphName { return _name; } - (NSUInteger)characterIdentifier { return _cid; } - (NSInteger)characterCollection { return (NSInteger)_coll; }
@end

@implementation NSAccessibilityCustomAction
- (id)initWithName:(NSString *)n handler:(BOOL (^)(void))h { self = [super init]; _name = [n copy]; _handler = h ? Block_copy(h) : NULL; return self; }
- (id)initWithName:(NSString *)n target:(id)t selector:(SEL)s { self = [super init]; _name = [n copy]; _target = t; _sel = s; return self; }
- (void)dealloc { [_name release]; if (_handler) Block_release(_handler); [super dealloc]; }
- (NSString *)name { return _name; } - (void)setName:(NSString *)n { [n retain]; [_name release]; _name = n; }
- (id)handler { return _handler; } - (void)setHandler:(id)h { if (_handler) Block_release(_handler); _handler = h ? Block_copy(h) : NULL; }
- (id)target { return _target; } - (void)setTarget:(id)t { _target = t; } - (SEL)selector { return _sel; } - (void)setSelector:(SEL)s { _sel = s; }
@end
static NSString *RotorLabel(NSInteger t) {
  static NSArray *l; if (!l) l = [[NSArray arrayWithObjects:@"", @"Any", @"Annotation", @"Bold Text", @"Heading", @"Heading Level 1", @"Heading Level 2", @"Heading Level 3", @"Heading Level 4", @"Heading Level 5", @"Heading Level 6", @"Image", @"Italic Text", @"Landmark", @"Link", @"List", @"Misspelled Word", @"Table", @"Text Field", @"Underlined Text", @"Visited Link", nil] retain];
  return t > 0 && t < (NSInteger)[l count] ? [l objectAtIndex:(NSUInteger)t] : @""; }
@implementation NSAccessibilityCustomRotor
- (id)initWithLabel:(NSString *)l itemSearchDelegate:(id)d { self = [super init]; _label = [l copy]; _del = d; return self; }
- (id)initWithRotorType:(NSInteger)t itemSearchDelegate:(id)d { self = [super init]; _type = t; _label = [RotorLabel(t) copy]; _del = d; return self; }
- (void)dealloc { [_label release]; [super dealloc]; }
- (NSInteger)type { return _type; } - (void)setType:(NSInteger)t { _type = t; } - (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (id)itemSearchDelegate { return _del; } - (void)setItemSearchDelegate:(id)d { _del = d; } - (id)itemLoadingDelegate { return _load; } - (void)setItemLoadingDelegate:(id)d { _load = d; }
@end

@implementation NSTextAttachmentCell
- (BOOL)wantsToTrackMouse { return YES; } - (NSPoint)cellBaselineOffset { return NSZeroPoint; }
- (id)attachment { return _att; } - (void)setAttachment:(id)a { _att = a; }
- (void)drawWithFrame:(NSRect)f inView:(NSView *)v characterIndex:(NSUInteger)i { [self drawWithFrame:f inView:v]; }
- (void)drawWithFrame:(NSRect)f inView:(NSView *)v characterIndex:(NSUInteger)i layoutManager:(NSLayoutManager *)lm { [self drawWithFrame:f inView:v]; }
- (BOOL)wantsToTrackMouseForEvent:(NSEvent *)e inRect:(NSRect)r ofView:(NSView *)v atCharacterIndex:(NSUInteger)i { return NO; }
- (BOOL)trackMouse:(NSEvent *)e inRect:(NSRect)r ofView:(NSView *)v atCharacterIndex:(NSUInteger)i untilMouseUp:(BOOL)u { return NO; }
- (NSRect)cellFrameForTextContainer:(NSTextContainer *)c proposedLineFragment:(NSRect)l glyphPosition:(NSPoint)g characterIndex:(NSUInteger)i { NSSize s = [self cellSize]; return NSMakeRect(0, 0, s.width, s.height); }
@end
@implementation NSTextAttachmentViewProvider
- (id)initWithTextAttachment:(NSTextAttachment *)a parentView:(NSView *)p textLayoutManager:(id)m location:(id)l { self = [super init]; _att = a; _parent = p; _tlm = m; _loc = [l retain]; return self; }
- (void)dealloc { [_loc release]; [_view release]; [super dealloc]; }
- (NSTextAttachment *)textAttachment { return _att; } - (id)textLayoutManager { return _tlm; } - (id)location { return _loc; }
- (NSView *)view { return _view; } - (void)setView:(NSView *)v { [v retain]; [_view release]; _view = v; } - (void)loadView {}
- (BOOL)tracksTextAttachmentViewBounds { return _tracks; } - (void)setTracksTextAttachmentViewBounds:(BOOL)f { _tracks = f; }
- (NSRect)attachmentBoundsForAttributes:(NSDictionary *)a location:(id)l textContainer:(NSTextContainer *)c proposedLineFragment:(NSRect)r position:(NSPoint)p { return _view ? [_view bounds] : NSZeroRect; }
@end
@implementation NSOpenGLLayer
- (void)dealloc { [_pf release]; [_ctx release]; [super dealloc]; }
- (NSView *)view { return _view; } - (void)setView:(NSView *)v { _view = v; }
- (NSOpenGLPixelFormat *)openGLPixelFormat { return _pf; } - (void)setOpenGLPixelFormat:(NSOpenGLPixelFormat *)p { [p retain]; [_pf release]; _pf = p; }
- (NSOpenGLContext *)openGLContext { return _ctx; } - (void)setOpenGLContext:(NSOpenGLContext *)c { [c retain]; [_ctx release]; _ctx = c; }
- (NSOpenGLPixelFormat *)openGLPixelFormatForDisplayMask:(unsigned int)m { return nil; } - (NSOpenGLContext *)openGLContextForPixelFormat:(NSOpenGLPixelFormat *)p { return [[[NSOpenGLContext alloc] initWithFormat:p shareContext:nil] autorelease]; }
- (BOOL)canDrawInOpenGLContext:(NSOpenGLContext *)c pixelFormat:(NSOpenGLPixelFormat *)p forLayerTime:(double)t displayTime:(const void *)d { return YES; }
- (void)drawInOpenGLContext:(NSOpenGLContext *)c pixelFormat:(NSOpenGLPixelFormat *)p forLayerTime:(double)t displayTime:(const void *)d {}
@end
@implementation NSColorPicker
- (id)initWithPickerMask:(NSUInteger)m colorPanel:(NSColorPanel *)p { self = [super init]; _mask = m; _panel = p; return self; }
- (NSColorPanel *)colorPanel { return _panel; } - (id)provideNewButtonImage { return nil; } - (void)insertNewButtonImage:(NSImage *)i in:(NSButtonCell *)c { [c setImage:i]; } - (void)viewSizeChanged:(id)s {}
- (void)attachColorList:(id)l {} - (void)detachColorList:(id)l {} - (void)setMode:(NSInteger)m {} - (NSString *)buttonToolTip { return nil; } - (NSSize)minContentSize { return NSZeroSize; } - (void)alphaControlAddedOrRemoved:(id)s {}
@end
@implementation NSTouch
- (id)identity { return _identity; } - (NSUInteger)phase { return _phase; } - (NSPoint)normalizedPosition { return _np; } - (BOOL)isResting { return _resting; } - (id)device { return nil; }
- (NSSize)deviceSize { return _dsz; } - (NSInteger)type { return _type; } - (NSPoint)locationInView:(NSView *)v { NSRect b = v ? [v bounds] : NSZeroRect; return NSMakePoint(_np.x * b.size.width, _np.y * b.size.height); } - (NSPoint)previousLocationInView:(NSView *)v { return [self locationInView:v]; }
@end
@implementation NSDraggingSession
- (NSInteger)draggingFormation { return _form; } - (void)setDraggingFormation:(NSInteger)f { _form = f; }
- (BOOL)animatesToStartingPositionsOnCancelOrFail { return _anim; } - (void)setAnimatesToStartingPositionsOnCancelOrFail:(BOOL)f { _anim = f; }
- (NSInteger)draggingLeaderIndex { return _leader; } - (void)setDraggingLeaderIndex:(NSInteger)i { _leader = i; }
- (NSPasteboard *)draggingPasteboard { return _pb; } - (NSInteger)draggingSequenceNumber { return _seq; } - (NSPoint)draggingLocation { return _loc; }
- (void)enumerateDraggingItemsWithOptions:(NSUInteger)o forView:(NSView *)v classes:(NSArray *)c searchOptions:(NSDictionary *)s usingBlock:(void (^)(id, NSInteger, BOOL *))b {}
@end

/* ---- predicate row templates ---- */
@implementation NSPredicateEditorRowTemplate
- (id)initWithLeftExpressions:(NSArray *)l rightExpressions:(NSArray *)r modifier:(NSUInteger)m operators:(NSArray *)o options:(NSUInteger)opt { self = [super init]; _left = [l copy]; _right = [r copy]; _mod = m; _ops = [o copy]; _opts = opt; return self; }
- (id)initWithLeftExpressions:(NSArray *)l rightExpressionAttributeType:(NSUInteger)t modifier:(NSUInteger)m operators:(NSArray *)o options:(NSUInteger)opt { self = [super init]; _left = [l copy]; _rtype = (NSInteger)t; _mod = m; _ops = [o copy]; _opts = opt; return self; }
- (id)initWithCompoundTypes:(NSArray *)t { self = [super init]; _compound = [t copy]; return self; }
- (void)dealloc { [_left release]; [_right release]; [_ops release]; [_compound release]; [_pred release]; [super dealloc]; }
- (NSArray *)leftExpressions { return _left; } - (NSArray *)rightExpressions { return _right; } - (NSUInteger)rightExpressionAttributeType { return (NSUInteger)_rtype; }
- (NSUInteger)modifier { return _mod; } - (NSArray *)operators { return _ops; } - (NSUInteger)options { return _opts; } - (NSArray *)compoundTypes { return _compound; }
- (double)matchForPredicate:(NSPredicate *)p {
  if (_compound) { if ([p isKindOfClass:[NSCompoundPredicate class]] && [_compound containsObject:[NSNumber numberWithUnsignedInteger:[(NSCompoundPredicate *)p compoundPredicateType]]]) return 0.5; return 0; }
  if (![p isKindOfClass:[NSComparisonPredicate class]]) return 0; NSComparisonPredicate *c = (NSComparisonPredicate *)p;
  if ([c comparisonPredicateModifier] != _mod) return 0;
  BOOL lm = NO; for (NSExpression *e in _left) if ([[e description] isEqual:[[c leftExpression] description]]) lm = YES; if (!lm) return 0;
  if (![_ops containsObject:[NSNumber numberWithUnsignedInteger:[c predicateOperatorType]]]) return 0;
  return 0.99; }
- (NSArray *)templateViews {
  if (_compound) { NSPopUpButton *b = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 20) pullsDown:NO] autorelease]; return [NSArray arrayWithObject:b]; }
  NSPopUpButton *l = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 20) pullsDown:NO] autorelease]; for (NSExpression *e in _left) [l addItemWithTitle:[[e keyPath] length] ? [e keyPath] : [e description]];
  NSPopUpButton *o = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 20) pullsDown:NO] autorelease]; for (NSNumber *n in _ops) [o addItemWithTitle:[NSString stringWithFormat:@"%@", n]];
  NSTextField *t = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 22)] autorelease];
  return [NSArray arrayWithObjects:l, o, t, nil]; }
- (void)setPredicate:(NSPredicate *)p { [p retain]; [_pred release]; _pred = p; }
- (NSPredicate *)predicateWithSubpredicates:(NSArray *)s {
  if (_compound) return [[[NSCompoundPredicate alloc] initWithType:[[_compound firstObject] unsignedIntegerValue] subpredicates:s ? s : [NSArray array]] autorelease];
  if ([_pred isKindOfClass:[NSComparisonPredicate class]]) return _pred;
  NSExpression *l = [_left firstObject], *r = [_right firstObject]; if (!l) return nil; if (!r) r = [NSExpression expressionForConstantValue:@""];
  return [NSComparisonPredicate predicateWithLeftExpression:l rightExpression:r modifier:_mod type:[[_ops firstObject] unsignedIntegerValue] options:_opts]; }
- (NSArray *)displayableSubpredicatesOfPredicate:(NSPredicate *)p { return [p isKindOfClass:[NSCompoundPredicate class]] ? [(NSCompoundPredicate *)p subpredicates] : nil; }
+ (NSArray *)templatesWithAttributeKeyPaths:(NSArray *)k inEntityDescription:(id)e { return [NSArray array]; }
@end

/* ---- small extras on existing classes ---- */
@implementation NSTokenFieldCell (XEFMisc)
- (NSInteger)tokenStyle { return [objc_getAssociatedObject(self, "xef.ts") integerValue]; } - (void)setTokenStyle:(NSInteger)s { objc_setAssociatedObject(self, "xef.ts", [NSNumber numberWithInteger:s], OBJC_ASSOCIATION_RETAIN); }
- (NSTimeInterval)completionDelay { return [objc_getAssociatedObject(self, "xef.cd") doubleValue]; } - (void)setCompletionDelay:(NSTimeInterval)d { objc_setAssociatedObject(self, "xef.cd", [NSNumber numberWithDouble:d], OBJC_ASSOCIATION_RETAIN); }
+ (NSTimeInterval)defaultCompletionDelay { return 0; }
- (NSCharacterSet *)tokenizingCharacterSet { NSCharacterSet *c = objc_getAssociatedObject(self, "xef.tcs"); return c ? c : [NSCharacterSet characterSetWithCharactersInString:@","]; } - (void)setTokenizingCharacterSet:(NSCharacterSet *)c { objc_setAssociatedObject(self, "xef.tcs", c, OBJC_ASSOCIATION_RETAIN); }
- (id)delegate { return objc_getAssociatedObject(self, "xef.del"); } - (void)setDelegate:(id)d { objc_setAssociatedObject(self, "xef.del", d, OBJC_ASSOCIATION_ASSIGN); }
@end
@implementation NSSound (XEFMisc)
+ (BOOL)canInitWithPasteboard:(NSPasteboard *)p { return [p dataForType:@"com.apple.coreaudio-format"] != nil || [p dataForType:@"public.audio"] != nil; }
- (id)initWithPasteboard:(NSPasteboard *)p { NSData *d = [p dataForType:@"com.apple.coreaudio-format"]; if (!d) d = [p dataForType:@"public.audio"]; if (!d) { [self release]; return nil; } return [self initWithData:d]; }
- (void)writeToPasteboard:(NSPasteboard *)p { if (_data) { [p declareTypes:[NSArray arrayWithObject:@"com.apple.coreaudio-format"] owner:nil]; [p setData:_data forType:@"com.apple.coreaudio-format"]; } }
- (NSString *)playbackDeviceIdentifier { return objc_getAssociatedObject(self, "xef.pdi"); } - (void)setPlaybackDeviceIdentifier:(NSString *)i { objc_setAssociatedObject(self, "xef.pdi", i, OBJC_ASSOCIATION_COPY); }
- (void)setChannelMapping:(NSArray *)m { objc_setAssociatedObject(self, "xef.cm", m, OBJC_ASSOCIATION_COPY); } - (NSArray *)channelMapping { return objc_getAssociatedObject(self, "xef.cm"); }
+ (NSArray *)readableTypesForPasteboard:(NSPasteboard *)p { return [NSArray arrayWithObjects:@"com.apple.coreaudio-format", @"public.audio", nil]; }
- (NSArray *)writableTypesForPasteboard:(NSPasteboard *)p { return [NSArray arrayWithObject:@"com.apple.coreaudio-format"]; }
@end
@implementation NSPopUpButton (XEFMisc)
+ (id)popUpButtonWithMenu:(NSMenu *)m target:(id)t action:(SEL)a { NSPopUpButton *b = [[[self alloc] initWithFrame:NSMakeRect(0, 0, 100, 24) pullsDown:NO] autorelease]; [b setMenu:m]; [b setTarget:t]; [b setAction:a]; if ([b numberOfItems] > 0) [b selectItemAtIndex:0]; return b; }
+ (id)pullDownButtonWithTitle:(NSString *)t menu:(NSMenu *)m { NSPopUpButton *b = [[[self alloc] initWithFrame:NSMakeRect(0, 0, 100, 24) pullsDown:YES] autorelease]; [b setMenu:m]; if ([b numberOfItems] > 0) [b selectItemAtIndex:0]; return b; }
+ (id)pullDownButtonWithImage:(NSImage *)i menu:(NSMenu *)m { return [self pullDownButtonWithTitle:nil menu:m]; } + (id)pullDownButtonWithTitle:(NSString *)t image:(NSImage *)i menu:(NSMenu *)m { return [self pullDownButtonWithTitle:t menu:m]; }
- (BOOL)usesItemFromMenu { NSNumber *n = objc_getAssociatedObject(self, "xef.uim"); return n ? [n boolValue] : YES; } - (void)setUsesItemFromMenu:(BOOL)f { objc_setAssociatedObject(self, "xef.uim", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); }
- (BOOL)altersStateOfSelectedItem { NSNumber *n = objc_getAssociatedObject(self, "xef.aso"); return n ? [n boolValue] : YES; } - (void)setAltersStateOfSelectedItem:(BOOL)f { objc_setAssociatedObject(self, "xef.aso", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); }
- (NSInteger)indexOfItemWithTarget:(id)t andAction:(SEL)a { NSArray *it = [self itemArray]; for (NSUInteger i = 0; i < [it count]; i++) { NSMenuItem *m = [it objectAtIndex:i]; if ([m target] == t && [m action] == a) return (NSInteger)i; } return -1; }
@end
@implementation NSPasteboardItem (XEFMisc)
- (NSString *)availableTypeFromArray:(NSArray *)a { NSArray *mine = [self types]; for (NSString *t in a) if ([mine containsObject:t]) return t; return nil; }
- (void)setDataProvider:(id)p forTypes:(NSArray *)t {}
- (BOOL)setPropertyList:(id)l forType:(NSString *)t { NSData *d = [NSPropertyListSerialization dataWithPropertyList:l format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL]; return d ? [self setData:d forType:t] : NO; }
- (id)propertyListForType:(NSString *)t { NSData *d = [self dataForType:t]; return d ? [NSPropertyListSerialization propertyListWithData:d options:0 format:NULL error:NULL] : nil; }
- (void)detectPatternsForPatterns:(NSSet *)p completionHandler:(void (^)(NSSet *, NSError *))h { if (h) h([NSSet set], nil); }
- (void)detectValuesForPatterns:(NSSet *)p completionHandler:(void (^)(NSDictionary *, NSError *))h { if (h) h([NSDictionary dictionary], nil); }
- (void)detectMetadataForTypes:(NSSet *)t completionHandler:(void (^)(id, NSError *))h { if (h) h(nil, nil); }
- (NSArray *)writableTypesForPasteboard:(NSPasteboard *)p { return [self types]; } + (NSArray *)readableTypesForPasteboard:(NSPasteboard *)p { return [NSArray arrayWithObject:NSPasteboardTypeString]; }
@end
