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

@protocol MTLDevice;
@protocol MTLTexture;
@class MTLTextureDescriptor;

extern id<MTLDevice> MTLCreateSystemDefaultDevice(void);

// libcompression
typedef enum { COMPRESSION_LZ4 = 0x100 } compression_algorithm;
extern size_t compression_encode_buffer(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size, void *scratch, compression_algorithm alg);

// libcache
typedef struct _cache_s *cache_t;
extern int cache_create(const char *name, void *attr, cache_t *out_cache);
extern int cache_destroy(cache_t c);

// libsandbox
extern int sandbox_init(const char *profile, uint64_t flags, char **errbuf);

// AGL
extern void *aglCreateContext(void *pix, void *share);

int main(int argc, char **argv) {
    @autoreleasepool {
        NSLog(@"[full_darling_test] Starting verification of all Darling additions...");

        // 1. Verify system dylibs
        uint8_t src[16] = "Hello Darling!";
        uint8_t dst[32] = {0};
        size_t encoded = compression_encode_buffer(dst, sizeof(dst), src, sizeof(src), NULL, COMPRESSION_LZ4);
        if (encoded != sizeof(src)) {
            NSLog(@"FAIL: libcompression failed");
            return 1;
        }
        NSLog(@"[full_darling_test] PASS: libcompression");

        cache_t cache = NULL;
        if (cache_create("test_cache", NULL, &cache) != 0 || !cache) {
            NSLog(@"FAIL: libcache failed");
            return 1;
        }
        cache_destroy(cache);
        NSLog(@"[full_darling_test] PASS: libcache");

        if (sandbox_init("kLibrary", 0, NULL) != 0) {
            NSLog(@"FAIL: libsandbox failed");
            return 1;
        }
        NSLog(@"[full_darling_test] PASS: libsandbox");

        // 2. Verify IOSurface
        NSDictionary *props = @{
            (id)kIOSurfaceWidth: @(128),
            (id)kIOSurfaceHeight: @(128)
        };
        void *surf = IOSurfaceCreate((CFDictionaryRef)props);
        if (!surf) {
            NSLog(@"FAIL: IOSurfaceCreate failed");
            return 1;
        }
        NSLog(@"[full_darling_test] PASS: IOSurface id=%u", IOSurfaceGetID(surf));

        // 3. Verify Metal Device
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        if (!dev) {
            NSLog(@"FAIL: MTLCreateSystemDefaultDevice failed");
            return 1;
        }
        NSLog(@"[full_darling_test] PASS: MTLDevice acquired: %@", dev);

        // 4. Verify AGL C function
        void *aglCtx = aglCreateContext(NULL, NULL);
        if (!aglCtx) {
            NSLog(@"FAIL: aglCreateContext failed");
            return 1;
        }
        NSLog(@"[full_darling_test] PASS: AGL context created");

        // 5. Verify a broad cross-section of the 93 frameworks
        NSArray *classesToTest = @[
            @"CIContext", @"WKWebView", @"AVPlayer", @"SCNView", @"SKView",
            @"MKMapView", @"PHPhotoLibrary", @"CKContainer", @"CNContact",
            @"EKEventStore", @"GCController", @"SKPaymentQueue", @"UNUserNotificationCenter",
            @"VNDetectFaceRectanglesRequest", @"AVAudioPlayer",
            @"ABAddressBook", @"ASAuthorizationController", @"AMWorkflow",
            @"CBManager", @"CLLocationManager", @"MIDINetworkSession",
            @"IOBluetoothDevice", @"PDFDocument", @"QTMovie", @"QLPreview"
        ];

        for (NSString *cname in classesToTest) {
            Class cls = NSClassFromString(cname);
            if (!cls) {
                NSLog(@"FAIL: Could not load class %@", cname);
                return 1;
            }
        }
        NSLog(@"[full_darling_test] PASS: Verified 25 classes across audio, video, graphics, web, bluetooth, location, notifications, quicklook");

        NSLog(@"PASS full_darling_test");
        return 0;
    }
}
