/* Small model classes (AppKitMisc.m). */
#import "AppKitLite.h"
#include <objc/message.h>
#import "AppKitGraphics.h"
#import "AppKitControllers.h"

@interface NSUserInterfaceCompressionOptions : NSObject <NSCopying> { @public NSSet *_ids; }
- (id)initWithIdentifier:(NSString *)i; - (id)initWithCompressionOptions:(NSSet *)s;
- (BOOL)containsOptions:(NSUserInterfaceCompressionOptions *)o; - (BOOL)intersectsOptions:(NSUserInterfaceCompressionOptions *)o; - (BOOL)isEmpty;
- (NSUserInterfaceCompressionOptions *)optionsByAddingOptions:(NSUserInterfaceCompressionOptions *)o; - (NSUserInterfaceCompressionOptions *)optionsByRemovingOptions:(NSUserInterfaceCompressionOptions *)o;
+ (NSUserInterfaceCompressionOptions *)hideImagesOption; + (NSUserInterfaceCompressionOptions *)hideTextOption; + (NSUserInterfaceCompressionOptions *)reduceMetricsOption;
+ (NSUserInterfaceCompressionOptions *)breakEqualWidthsOption; + (NSUserInterfaceCompressionOptions *)standardOptions;
@end

@interface NSFontCollection : NSObject <NSCopying, NSMutableCopying> { @public NSArray *_query, *_excl; NSString *_name; BOOL _all; }
+ (NSFontCollection *)fontCollectionWithDescriptors:(NSArray *)d; + (NSFontCollection *)fontCollectionWithAllAvailableDescriptors; + (NSFontCollection *)fontCollectionWithLocale:(NSLocale *)l;
+ (BOOL)showFontCollection:(NSFontCollection *)c withName:(NSString *)n visibility:(NSInteger)v error:(NSError **)e; + (BOOL)hideFontCollectionWithName:(NSString *)n visibility:(NSInteger)v error:(NSError **)e;
+ (BOOL)renameFontCollectionWithName:(NSString *)n visibility:(NSInteger)v toName:(NSString *)t error:(NSError **)e; + (NSArray *)allFontCollectionNames;
+ (NSFontCollection *)fontCollectionWithName:(NSString *)n; + (NSFontCollection *)fontCollectionWithName:(NSString *)n visibility:(NSInteger)v;
- (NSArray *)queryDescriptors; - (NSArray *)exclusionDescriptors; - (NSArray *)matchingDescriptors; - (NSArray *)matchingDescriptorsWithOptions:(NSDictionary *)o;
- (NSArray *)matchingDescriptorsForFamily:(NSString *)f; - (NSArray *)matchingDescriptorsForFamily:(NSString *)f options:(NSDictionary *)o;
@end

@interface NSTitlebarAccessoryViewController : NSViewController { @public NSInteger _la; CGFloat _fsmin; BOOL _hidden, _auto; NSDictionary *_anims; }
- (NSInteger)layoutAttribute; - (void)setLayoutAttribute:(NSInteger)a; - (CGFloat)fullScreenMinHeight; - (void)setFullScreenMinHeight:(CGFloat)h;
- (BOOL)isHidden; - (void)setHidden:(BOOL)f; - (BOOL)automaticallyAdjustsSize; - (void)setAutomaticallyAdjustsSize:(BOOL)f;
- (id)animator; - (NSDictionary *)animations; - (void)setAnimations:(NSDictionary *)a; - (id)animationForKey:(NSString *)k; + (id)defaultAnimationForKey:(NSString *)k;
@end

@interface NSApplication (XEFMisc)
- (void)registerForRemoteNotifications; - (void)unregisterForRemoteNotifications; - (BOOL)isRegisteredForRemoteNotifications; - (void)registerForRemoteNotificationTypes:(NSUInteger)t; - (NSUInteger)enabledRemoteNotificationTypes;
- (void)beginSheet:(NSWindow *)s modalForWindow:(NSWindow *)w modalDelegate:(id)d didEndSelector:(SEL)sel contextInfo:(void *)ci; - (void)endSheet:(NSWindow *)s; - (void)endSheet:(NSWindow *)s returnCode:(NSInteger)rc;
- (void)makeWindowsPerform:(SEL)sel inOrder:(BOOL)o; - (id)context; - (BOOL)isAutomaticCustomizeTouchBarMenuItemEnabled; - (void)setAutomaticCustomizeTouchBarMenuItemEnabled:(BOOL)f;
- (void)toggleTouchBarCustomizationPalette:(id)s; - (void)unregisterUserInterfaceItemSearchHandler:(id)h;
- (BOOL)searchString:(NSString *)s inUserInterfaceItemString:(NSString *)i searchRange:(NSRange)r foundRange:(NSRange *)f;
- (void)restoreWindowWithIdentifier:(NSString *)i state:(NSCoder *)s completionHandler:(void (^)(NSWindow *, NSError *))h;
@end
