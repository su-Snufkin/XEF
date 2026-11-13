/* Small model classes: NSUserInterfaceCompressionOptions, NSFontCollection, NSTitlebarAccessoryViewController, NSApplication extras.
   Behaviours matched against macOS (tests/darwin/mac/appkit_misc3.m). */
#import "AppKitMisc.h"
#include <objc/runtime.h>
#import "AppKitText.h"
@interface NSMutableFontCollection : NSFontCollection @end
@class CABasicAnimation;

/* ---- compression options ---- */
@implementation NSUserInterfaceCompressionOptions
- (id)init { return [self initWithCompressionOptions:[NSSet set]]; }
- (id)initWithCoder:(NSCoder *)c { return [self init]; }
- (id)initWithIdentifier:(NSString *)i { return [self initWithCompressionOptions:[NSSet setWithObject:i]]; }
- (id)initWithCompressionOptions:(NSSet *)s {
  self = [super init]; NSMutableSet *ids = [NSMutableSet set];
  for (id o in s) { if ([o isKindOfClass:[NSUserInterfaceCompressionOptions class]]) [ids unionSet:((NSUserInterfaceCompressionOptions *)o)->_ids]; else if ([o isKindOfClass:[NSString class]]) [ids addObject:o]; }
  _ids = [ids copy]; return self; }
- (void)dealloc { [_ids release]; [super dealloc]; }
- (BOOL)containsOptions:(NSUserInterfaceCompressionOptions *)o { return [o->_ids isSubsetOfSet:_ids]; }
- (BOOL)intersectsOptions:(NSUserInterfaceCompressionOptions *)o { return [_ids intersectsSet:o->_ids]; }
- (BOOL)isEmpty { return [_ids count] == 0; }
- (NSUserInterfaceCompressionOptions *)optionsByAddingOptions:(NSUserInterfaceCompressionOptions *)o { NSMutableSet *s = [NSMutableSet setWithSet:_ids]; [s unionSet:o->_ids]; return [[[NSUserInterfaceCompressionOptions alloc] initWithCompressionOptions:s] autorelease]; }
- (NSUserInterfaceCompressionOptions *)optionsByRemovingOptions:(NSUserInterfaceCompressionOptions *)o { NSMutableSet *s = [NSMutableSet setWithSet:_ids]; [s minusSet:o->_ids]; return [[[NSUserInterfaceCompressionOptions alloc] initWithCompressionOptions:s] autorelease]; }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[NSUserInterfaceCompressionOptions class]] && [_ids isEqualToSet:((NSUserInterfaceCompressionOptions *)o)->_ids]; }
- (NSUInteger)hash { return [_ids hash]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
+ (NSUserInterfaceCompressionOptions *)_opt:(NSString *)i { return [[[self alloc] initWithIdentifier:i] autorelease]; }
+ (NSUserInterfaceCompressionOptions *)hideImagesOption { return [self _opt:@"NSUserInterfaceCompressionHideImages"]; }
+ (NSUserInterfaceCompressionOptions *)hideTextOption { return [self _opt:@"NSUserInterfaceCompressionHideText"]; }
+ (NSUserInterfaceCompressionOptions *)reduceMetricsOption { return [self _opt:@"NSUserInterfaceCompressionReduceMetrics"]; }
+ (NSUserInterfaceCompressionOptions *)breakEqualWidthsOption { return [self _opt:@"NSUserInterfaceCompressionBreakEqualWidths"]; }
+ (NSUserInterfaceCompressionOptions *)standardOptions { return [[[self alloc] initWithCompressionOptions:[NSSet setWithObjects:@"NSUserInterfaceCompressionHideImages", @"NSUserInterfaceCompressionHideText", @"NSUserInterfaceCompressionReduceMetrics", @"NSUserInterfaceCompressionBreakEqualWidths", nil]] autorelease]; }
@end

/* ---- font collections ---- */
static NSMutableDictionary *g_fc_named;
static NSArray *StdCollectionNames(void) { return [NSArray arrayWithObjects:@"com.apple.AllFonts", @"com.apple.UserFonts", @"com.apple.Favorites", @"com.apple.Recents", @"Fun", @"Web", @"Modern", @"PDF", @"Fixed Width", @"Traditional", nil]; }
@implementation NSFontCollection
+ (NSFontCollection *)fontCollectionWithDescriptors:(NSArray *)d { NSFontCollection *c = [[[self alloc] init] autorelease]; c->_query = [d copy]; return c; }
+ (NSFontCollection *)fontCollectionWithAllAvailableDescriptors { NSFontCollection *c = [[[self alloc] init] autorelease]; c->_all = YES; return c; }
+ (NSFontCollection *)fontCollectionWithLocale:(NSLocale *)l { return [self fontCollectionWithAllAvailableDescriptors]; }
+ (BOOL)showFontCollection:(NSFontCollection *)c withName:(NSString *)n visibility:(NSInteger)v error:(NSError **)e { if (!g_fc_named) g_fc_named = [[NSMutableDictionary alloc] init]; [g_fc_named setObject:c forKey:n]; return YES; }
+ (BOOL)hideFontCollectionWithName:(NSString *)n visibility:(NSInteger)v error:(NSError **)e { if (![g_fc_named objectForKey:n]) return NO; [g_fc_named removeObjectForKey:n]; return YES; }
+ (BOOL)renameFontCollectionWithName:(NSString *)n visibility:(NSInteger)v toName:(NSString *)t error:(NSError **)e { id c = [g_fc_named objectForKey:n]; if (!c) return NO; [c retain]; [g_fc_named removeObjectForKey:n]; [g_fc_named setObject:c forKey:t]; [c release]; return YES; }
+ (NSArray *)allFontCollectionNames { NSMutableArray *a = [NSMutableArray arrayWithArray:StdCollectionNames()]; [a addObjectsFromArray:[g_fc_named allKeys]]; return a; }
+ (NSFontCollection *)fontCollectionWithName:(NSString *)n { return [self fontCollectionWithName:n visibility:0]; }
+ (NSFontCollection *)fontCollectionWithName:(NSString *)n visibility:(NSInteger)v {
  NSFontCollection *c = [g_fc_named objectForKey:n]; if (c) return c;
  if ([StdCollectionNames() containsObject:n]) { c = [self fontCollectionWithAllAvailableDescriptors]; return c; }
  return nil; }
- (void)dealloc { [_query release]; [_excl release]; [_name release]; [super dealloc]; }
- (id)copyWithZone:(NSZone *)z { return [self retain]; }
- (id)mutableCopyWithZone:(NSZone *)z { NSFontCollection *c = [[NSMutableFontCollection alloc] init]; c->_query = [_query copy]; c->_excl = [_excl copy]; c->_all = _all; return c; }
- (NSArray *)queryDescriptors { return _query; } - (NSArray *)exclusionDescriptors { return _excl; }
- (NSArray *)matchingDescriptors { return [self matchingDescriptorsWithOptions:nil]; }
- (NSArray *)matchingDescriptorsWithOptions:(NSDictionary *)o {
  NSMutableArray *out = [NSMutableArray array];
  if (_all) { for (NSString *n in [[NSFontManager sharedFontManager] availableFonts]) [out addObject:[NSFontDescriptor fontDescriptorWithName:n size:12]]; return out; }
  NSArray *all = [[NSFontManager sharedFontManager] availableFonts];
  for (NSFontDescriptor *q in _query) { NSString *n = [q postscriptName] ? [q postscriptName] : [[q fontAttributes] objectForKey:NSFontNameAttribute]; NSString *fam = [[q fontAttributes] objectForKey:NSFontFamilyAttribute];
    for (NSString *f in all) if ((n && [f isEqualToString:n]) || (fam && [f hasPrefix:fam]) || (!n && !fam)) [out addObject:[NSFontDescriptor fontDescriptorWithName:f size:12]]; }
  return out; }
- (NSArray *)matchingDescriptorsForFamily:(NSString *)f { return [self matchingDescriptorsForFamily:f options:nil]; }
- (NSArray *)matchingDescriptorsForFamily:(NSString *)f options:(NSDictionary *)o {
  NSMutableArray *out = [NSMutableArray array]; for (NSFontDescriptor *d in [self matchingDescriptorsWithOptions:o]) { NSString *n = [d postscriptName]; if (!n) n = [[d fontAttributes] objectForKey:NSFontNameAttribute]; if ([n hasPrefix:f]) [out addObject:d]; }
  return [out count] ? out : nil; }
@end

/* ---- titlebar accessory ---- */
@implementation NSTitlebarAccessoryViewController
- (id)initWithNibName:(NSString *)n bundle:(NSBundle *)b { self = [super initWithNibName:n bundle:b]; _la = 4; _auto = YES; return self; }
- (id)init { return [self initWithNibName:nil bundle:nil]; }
- (void)dealloc { [_anims release]; [super dealloc]; }
- (NSInteger)layoutAttribute { return _la; } - (void)setLayoutAttribute:(NSInteger)a { _la = a; }
- (CGFloat)fullScreenMinHeight { return _fsmin; } - (void)setFullScreenMinHeight:(CGFloat)h { _fsmin = h; }
- (BOOL)isHidden { return _hidden; } - (void)setHidden:(BOOL)f { _hidden = f; if ([self isViewLoaded]) [[self view] setHidden:f]; }
- (BOOL)automaticallyAdjustsSize { return _auto; } - (void)setAutomaticallyAdjustsSize:(BOOL)f { _auto = f; }
- (id)animator { return self; }
- (NSDictionary *)animations { return _anims ? _anims : [NSDictionary dictionary]; } - (void)setAnimations:(NSDictionary *)a { [a retain]; [_anims release]; _anims = a; }
- (id)animationForKey:(NSString *)k { id a = [_anims objectForKey:k]; return a ? a : [[self class] defaultAnimationForKey:k]; }
+ (id)defaultAnimationForKey:(NSString *)k { return [k isEqualToString:@"hidden"] ? [NSNull null] : nil; }
@end

/* ---- NSApplication extras ---- */
@implementation NSApplication (XEFMisc)
- (void)registerForRemoteNotifications {} - (void)unregisterForRemoteNotifications {} - (BOOL)isRegisteredForRemoteNotifications { return NO; }
- (void)registerForRemoteNotificationTypes:(NSUInteger)t {} - (NSUInteger)enabledRemoteNotificationTypes { return 0; }
- (void)beginSheet:(NSWindow *)s modalForWindow:(NSWindow *)w modalDelegate:(id)d didEndSelector:(SEL)sel contextInfo:(void *)ci {
  [w beginSheet:s completionHandler:^(NSModalResponse rc) { if (d && sel && [d respondsToSelector:sel]) { void (*f)(id, SEL, id, NSInteger, void *) = (void (*)(id, SEL, id, NSInteger, void *))objc_msgSend; f(d, sel, s, (NSInteger)rc, ci); } }]; }
- (void)endSheet:(NSWindow *)s { [self endSheet:s returnCode:0]; }
- (void)endSheet:(NSWindow *)s returnCode:(NSInteger)rc { NSWindow *p = [s sheetParent]; if (p) [p endSheet:s returnCode:rc]; else [s orderOut:nil]; }
- (void)makeWindowsPerform:(SEL)sel inOrder:(BOOL)o { for (NSWindow *w in [self orderedWindows]) if ([w respondsToSelector:sel] && [w performSelector:sel]) return; }
- (id)context { return nil; }
- (BOOL)isAutomaticCustomizeTouchBarMenuItemEnabled { return [objc_getAssociatedObject(self, "xef.autotb") boolValue]; }
- (void)setAutomaticCustomizeTouchBarMenuItemEnabled:(BOOL)f { objc_setAssociatedObject(self, "xef.autotb", [NSNumber numberWithBool:f], OBJC_ASSOCIATION_RETAIN); }
- (void)toggleTouchBarCustomizationPalette:(id)s {} - (void)unregisterUserInterfaceItemSearchHandler:(id)h {}
- (BOOL)searchString:(NSString *)s inUserInterfaceItemString:(NSString *)i searchRange:(NSRange)r foundRange:(NSRange *)f {
  if (NSMaxRange(r) > [i length]) return NO; NSRange x = [i rangeOfString:s options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch range:r];
  if (x.location == NSNotFound) return NO; if (f) *f = x; return YES; }
- (void)restoreWindowWithIdentifier:(NSString *)i state:(NSCoder *)s completionHandler:(void (^)(NSWindow *, NSError *))h { if (h) h(nil, nil); }
@end
