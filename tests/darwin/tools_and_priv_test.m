#import <Foundation/Foundation.h>

extern const char *sw_vers_test(void);

int main(int argc, char **argv) {
    @autoreleasepool {
        NSLog(@"[tools_and_priv_test] Testing tools and PrivateFrameworks presence...");

        // 1. Verify SystemVersion.plist
        NSString *plistPath = @"/System/Library/CoreServices/SystemVersion.plist";
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:plistPath];
        if (!dict) {
            NSLog(@"FAIL: Could not load %@", plistPath);
            return 1;
        }
        NSLog(@"[tools_and_priv_test] SystemVersion: ProductName=%@ ProductVersion=%@ BuildVersion=%@",
              [dict objectForKey:@"ProductName"],
              [dict objectForKey:@"ProductVersion"],
              [dict objectForKey:@"BuildVersion"]);

        // 2. Verify PrivateFramework bundle lookup
        NSBundle *coreUIBundle = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/CoreUI.framework"];
        NSBundle *skyLightBundle = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/SkyLight.framework"];
        NSBundle *uiFoundBundle = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/UIFoundation.framework"];

        NSLog(@"[tools_and_priv_test] CoreUI bundle: %@", coreUIBundle);
        NSLog(@"[tools_and_priv_test] SkyLight bundle: %@", skyLightBundle);
        NSLog(@"[tools_and_priv_test] UIFoundation bundle: %@", uiFoundBundle);

        if (!coreUIBundle || !skyLightBundle || !uiFoundBundle) {
            NSLog(@"FAIL: Could not locate PrivateFramework bundles");
            return 1;
        }

        NSLog(@"PASS tools_and_priv_test");
        return 0;
    }
}
