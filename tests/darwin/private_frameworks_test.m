#import <Foundation/Foundation.h>
#import <objc/runtime.h>

int main(int argc, char **argv) {
    @autoreleasepool {
        NSLog(@"[priv_fw_test] Testing PrivateFrameworks resolution...");

        const char *classes[] = {
            "CUICommonAssetStorage",   // CoreUI
            "SLSTransaction",           // SkyLight
            "UIFont",                  // UIFoundation
            "ISIcon",                  // IconServices
            "PKInstallRequest",        // PackageKit
            "DIImage",                 // DiskImages
            "ETModelDefinition",       // Espresso
            "TCCAccessInfo"            // TCC
        };

        for (int i = 0; i < 8; i++) {
            Class cls = objc_getClass(classes[i]);
            if (!cls) {
                NSLog(@"FAIL: Could not load PrivateFramework class %s", classes[i]);
                return 1;
            }
            NSLog(@"[priv_fw_test] Loaded class: %s -> %p", classes[i], cls);
        }

        NSLog(@"PASS private_frameworks_test");
        return 0;
    }
}
