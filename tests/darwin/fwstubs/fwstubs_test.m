// Generated stub frameworks (tools/gen_framework_stubs.py): a framework the rootfs has no implementation of
// (GameKit, CoreAudio) and names AppKit-lite lacks (AppKit.xefstubs). No SDK headers: built on Linux by build.sh.
typedef signed char BOOL;
typedef struct objc_class *Class;
typedef struct objc_object *id;
typedef struct objc_selector *SEL;
extern int printf(const char *, ...);
extern int strcmp(const char *, const char *);
extern id objc_getClass(const char *);
extern Class class_getSuperclass(Class);
extern const char *class_getName(Class);
extern id objc_msgSend(id, SEL, ...);
extern SEL sel_registerName(const char *);
extern const char *CFStringGetCStringPtr(const void *, unsigned);

@interface NSObject
+ (id)alloc;
- (id)init;
@end
@interface GKPlayer : NSObject
@end
@interface GKLocalPlayer : GKPlayer
+ (id)localPlayer;
- (BOOL)isAuthenticated;
- (id)displayName;
@end
@interface NSTextFinder : NSObject
- (id)client;
@end
@interface MyPlayer : GKLocalPlayer
- (int)answer;
@end
@implementation MyPlayer
- (int)answer { return 42; }
@end

extern const void *const GKErrorDomain;                    // GameKit: string constant with the real value
extern const void *const NSTextFinderCaseInsensitiveKey;   // AppKit, not in AppKit-lite; its real value differs from its name
extern int AudioHardwareUnload(void);                       // CoreAudio: a function that returns 0
extern const double NSFontWeightBold;                       // AppKit: constant bytes (0.4)

static int fails;
#define CHECK(c) do { if (!(c)) { printf("FAIL: %s\n", #c); fails++; } } while (0)

int main(void) {
    Class lp = (Class)objc_getClass("GKLocalPlayer");
    CHECK(lp != 0);
    CHECK(lp && strcmp(class_getName(class_getSuperclass(lp)), "GKPlayer") == 0);
    CHECK([GKLocalPlayer localPlayer] == 0);                // unknown class message: nil
    GKLocalPlayer *p = [[GKLocalPlayer alloc] init];
    CHECK(p != 0);
    CHECK([p isAuthenticated] == 0);                        // unknown instance message: 0
    CHECK([p displayName] == 0);
    MyPlayer *m = [[MyPlayer alloc] init];                  // an application subclass of a stub class
    CHECK(m != 0 && [m answer] == 42 && [m displayName] == 0);
    const char *d = GKErrorDomain ? CFStringGetCStringPtr(GKErrorDomain, 0x600) : 0;
    CHECK(d && strcmp(d, "GKErrorDomain") == 0);
    CHECK(AudioHardwareUnload() == 0);
    CHECK(objc_getClass("NSTextFinder") != 0);
    CHECK([[[NSTextFinder alloc] init] client] == 0);
    const char *k = NSTextFinderCaseInsensitiveKey ? CFStringGetCStringPtr(NSTextFinderCaseInsensitiveKey, 0x600) : 0;
    CHECK(k && strcmp(k, "NSFindPanelCaseInsensitiveSearch") == 0);
    CHECK(NSFontWeightBold > 0.39 && NSFontWeightBold < 0.41);
    printf(fails ? "FAIL fwstubs_test\n" : "PASS fwstubs_test\n");
    return fails != 0;
}
