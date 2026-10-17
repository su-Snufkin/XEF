#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

@interface IOSurface : NSObject
- (uint32_t)surfaceID;
- (size_t)width;
- (size_t)height;
@end

extern void *IOSurfaceCreate(CFDictionaryRef properties);
extern uint32_t IOSurfaceGetID(void *surface);
extern const CFStringRef kIOSurfaceWidth;
extern const CFStringRef kIOSurfaceHeight;

extern const CFStringRef kCGImagePropertyPixelWidth;
extern const CFStringRef kCTFontAttributeName;

int main(int argc, char **argv) {
    @autoreleasepool {
        NSLog(@"[test] Testing Frameworks compatibility...");

        // 1. Test IOSurface
        NSDictionary *props = @{
            (id)kIOSurfaceWidth: @(1920),
            (id)kIOSurfaceHeight: @(1080)
        };
        void *surf = IOSurfaceCreate((CFDictionaryRef)props);
        if (!surf) {
            NSLog(@"FAIL: IOSurfaceCreate returned NULL");
            return 1;
        }
        uint32_t sid = IOSurfaceGetID(surf);
        NSLog(@"[test] IOSurface created successfully, id=%u", sid);

        // 2. Test ImageIO constant
        if (!kCGImagePropertyPixelWidth) {
            NSLog(@"FAIL: kCGImagePropertyPixelWidth is NULL");
            return 1;
        }
        NSLog(@"[test] ImageIO constant verified: %@", (id)kCGImagePropertyPixelWidth);

        // 3. Test CoreText constant
        if (!kCTFontAttributeName) {
            NSLog(@"FAIL: kCTFontAttributeName is NULL");
            return 1;
        }
        NSLog(@"[test] CoreText constant verified: %@", (id)kCTFontAttributeName);

        // 4. Test Dynamic resolution of classes from newly added frameworks
        Class ciColorClass = NSClassFromString(@"CIColor");
        Class wkWebViewClass = NSClassFromString(@"WKWebView");
        Class avPlayerClass = NSClassFromString(@"AVPlayer");
        Class scnViewClass = NSClassFromString(@"SCNView");
        Class moContextClass = NSClassFromString(@"NSManagedObjectContext");

        NSLog(@"[test] CIColor: %@", ciColorClass);
        NSLog(@"[test] WKWebView: %@", wkWebViewClass);
        NSLog(@"[test] AVPlayer: %@", avPlayerClass);
        NSLog(@"[test] SCNView: %@", scnViewClass);
        NSLog(@"[test] NSManagedObjectContext: %@", moContextClass);

        if (!ciColorClass || !wkWebViewClass || !avPlayerClass || !scnViewClass || !moContextClass) {
            NSLog(@"FAIL: Some framework classes could not be loaded");
            return 1;
        }

        NSLog(@"PASS frameworks_test");
        return 0;
    }
}
