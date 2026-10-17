/*
 * IOSurface implementation for XEF
 * Based on Apple IOSurface framework and Darling specifications
 */

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <mach/mach.h>

const CFStringRef kIOSurfaceAllocSize = CFSTR("IOSurfaceAllocSize");
const CFStringRef kIOSurfaceWidth = CFSTR("IOSurfaceWidth");
const CFStringRef kIOSurfaceHeight = CFSTR("IOSurfaceHeight");
const CFStringRef kIOSurfaceBytesPerRow = CFSTR("IOSurfaceBytesPerRow");
const CFStringRef kIOSurfaceBytesPerElement = CFSTR("IOSurfaceBytesPerElement");
const CFStringRef kIOSurfaceElementWidth = CFSTR("IOSurfaceElementWidth");
const CFStringRef kIOSurfaceElementHeight = CFSTR("IOSurfaceElementHeight");
const CFStringRef kIOSurfaceOffset = CFSTR("IOSurfaceOffset");
const CFStringRef kIOSurfacePlaneInfo = CFSTR("IOSurfacePlaneInfo");
const CFStringRef kIOSurfacePlaneWidth = CFSTR("IOSurfacePlaneWidth");
const CFStringRef kIOSurfacePlaneHeight = CFSTR("IOSurfacePlaneHeight");
const CFStringRef kIOSurfacePlaneBytesPerRow = CFSTR("IOSurfacePlaneBytesPerRow");
const CFStringRef kIOSurfacePlaneOffset = CFSTR("IOSurfacePlaneOffset");
const CFStringRef kIOSurfacePlaneSize = CFSTR("IOSurfacePlaneSize");
const CFStringRef kIOSurfacePlaneBase = CFSTR("IOSurfacePlaneBase");
const CFStringRef kIOSurfacePlaneBitsPerElement = CFSTR("IOSurfacePlaneBitsPerElement");
const CFStringRef kIOSurfacePlaneBytesPerElement = CFSTR("IOSurfacePlaneBytesPerElement");
const CFStringRef kIOSurfacePlaneElementWidth = CFSTR("IOSurfacePlaneElementWidth");
const CFStringRef kIOSurfacePlaneElementHeight = CFSTR("IOSurfacePlaneElementHeight");
const CFStringRef kIOSurfaceCacheMode = CFSTR("IOSurfaceCacheMode");
const CFStringRef kIOSurfaceIsGlobal = CFSTR("IOSurfaceIsGlobal");
const CFStringRef kIOSurfacePixelFormat = CFSTR("IOSurfacePixelFormat");
const CFStringRef kIOSurfacePixelSizeCastingAllowed = CFSTR("IOSurfacePixelSizeCastingAllowed");
const CFStringRef kIOSurfacePlaneComponentBitDepths = CFSTR("IOSurfacePlaneComponentBitDepths");
const CFStringRef kIOSurfacePlaneComponentBitOffsets = CFSTR("IOSurfacePlaneComponentBitOffsets");
const CFStringRef kIOSurfaceColorSpace = CFSTR("IOSurfaceColorSpace");
const CFStringRef kIOSurfaceIsDisplayable = CFSTR("IsDisplayable");
const CFStringRef kIOSurfaceName = CFSTR("IOSurfaceName");
const CFStringRef kIOSurfacePixelCastingAllowed = CFSTR("IOSurfacePixelSizeCastingAllowed");
const CFStringRef kIOSurfaceProtectionOptions = CFSTR("IOSurfaceProtectionOptions");
const CFStringRef kIOSurfaceYCbCrMatrix = CFSTR("IOSurfaceYCbCrMatrix");
const CFStringRef kIOSurfaceYCbCrMatrix_ITU_R_601_4_String = CFSTR("ITU_R_601_4");
const CFStringRef kIOSurfaceYCbCrMatrix_ITU_R_709_2_String = CFSTR("ITU_R_709_2");

NSString *const IOSurfacePropertyKeyAllocSize = @"IOSurfacePropertyKeyAllocSize";
NSString *const IOSurfacePropertyKeyWidth = @"IOSurfacePropertyKeyWidth";
NSString *const IOSurfacePropertyKeyHeight = @"IOSurfacePropertyKeyHeight";
NSString *const IOSurfacePropertyKeyBytesPerRow = @"IOSurfacePropertyKeyBytesPerRow";
NSString *const IOSurfacePropertyKeyBytesPerElement = @"IOSurfacePropertyKeyBytesPerElement";
NSString *const IOSurfacePropertyKeyElementWidth = @"IOSurfacePropertyKeyElementWidth";
NSString *const IOSurfacePropertyKeyElementHeight = @"IOSurfacePropertyKeyElementHeight";
NSString *const IOSurfacePropertyKeyOffset = @"IOSurfacePropertyKeyOffset";
NSString *const IOSurfacePropertyKeyPlaneInfo = @"IOSurfacePropertyKeyPlaneInfo";
NSString *const IOSurfacePropertyKeyPlaneWidth = @"IOSurfacePropertyKeyPlaneWidth";
NSString *const IOSurfacePropertyKeyPlaneHeight = @"IOSurfacePropertyKeyPlaneHeight";
NSString *const IOSurfacePropertyKeyPlaneBytesPerRow = @"IOSurfacePropertyKeyPlaneBytesPerRow";
NSString *const IOSurfacePropertyKeyPlaneOffset = @"IOSurfacePropertyKeyPlaneOffset";
NSString *const IOSurfacePropertyKeyPlaneSize = @"IOSurfacePropertyKeyPlaneSize";
NSString *const IOSurfacePropertyKeyPlaneBase = @"IOSurfacePropertyKeyPlaneBase";
NSString *const IOSurfacePropertyKeyPlaneBytesPerElement = @"IOSurfacePropertyKeyPlaneBytesPerElement";
NSString *const IOSurfacePropertyKeyPlaneElementWidth = @"IOSurfacePropertyKeyPlaneElementWidth";
NSString *const IOSurfacePropertyKeyPlaneElementHeight = @"IOSurfacePropertyKeyPlaneElementHeight";
NSString *const IOSurfacePropertyKeyCacheMode = @"IOSurfacePropertyKeyCacheMode";
NSString *const IOSurfacePropertyKeyPixelFormat = @"IOSurfacePropertyKeyPixelFormat";
NSString *const IOSurfacePropertyKeyPixelSizeCastingAllowed = @"IOSurfacePropertyKeyPixelSizeCastingAllowed";

@interface IOSurface : NSObject {
@public
    uint32_t _surfaceID;
    size_t _width;
    size_t _height;
    size_t _bytesPerRow;
    size_t _bytesPerElement;
    uint32_t _pixelFormat;
    size_t _allocSize;
    void *_baseAddress;
    int _lockCount;
}
- (instancetype)initWithProperties:(NSDictionary *)properties;
- (uint32_t)surfaceID;
- (size_t)width;
- (size_t)height;
- (size_t)bytesPerRow;
- (size_t)allocationSize;
- (void *)baseAddress;
- (int)lockWithOptions:(uint32_t)options seed:(uint32_t *)seed;
- (int)unlockWithOptions:(uint32_t)options seed:(uint32_t *)seed;
@end

static uint32_t g_nextSurfaceID = 100;

@implementation IOSurface

- (instancetype)initWithProperties:(NSDictionary *)properties {
    self = [super init];
    if (self) {
        _surfaceID = ++g_nextSurfaceID;
        NSNumber *w = [properties objectForKey:(id)kIOSurfaceWidth];
        NSNumber *h = [properties objectForKey:(id)kIOSurfaceHeight];
        NSNumber *bpr = [properties objectForKey:(id)kIOSurfaceBytesPerRow];
        NSNumber *bpe = [properties objectForKey:(id)kIOSurfaceBytesPerElement];
        NSNumber *pf = [properties objectForKey:(id)kIOSurfacePixelFormat];
        NSNumber *as = [properties objectForKey:(id)kIOSurfaceAllocSize];

        _width = w ? [w unsignedLongValue] : 1;
        _height = h ? [h unsignedLongValue] : 1;
        _bytesPerElement = bpe ? [bpe unsignedLongValue] : 4;
        _bytesPerRow = bpr ? [bpr unsignedLongValue] : (_width * _bytesPerElement);
        _pixelFormat = pf ? [pf unsignedIntValue] : 0x42475241; // 'BGRA'
        _allocSize = as ? [as unsignedLongValue] : (_bytesPerRow * _height);

        _baseAddress = calloc(1, _allocSize ? _allocSize : 4096);
        _lockCount = 0;
    }
    return self;
}

- (void)dealloc {
    if (_baseAddress) {
        free(_baseAddress);
        _baseAddress = NULL;
    }
    [super dealloc];
}

- (uint32_t)surfaceID { return _surfaceID; }
- (size_t)width { return _width; }
- (size_t)height { return _height; }
- (size_t)bytesPerRow { return _bytesPerRow; }
- (size_t)allocationSize { return _allocSize; }
- (void *)baseAddress { return _baseAddress; }

- (int)lockWithOptions:(uint32_t)options seed:(uint32_t *)seed {
    _lockCount++;
    if (seed) *seed = 1;
    return 0;
}

- (int)unlockWithOptions:(uint32_t)options seed:(uint32_t *)seed {
    if (_lockCount > 0) _lockCount--;
    if (seed) *seed = 1;
    return 0;
}

@end

/* ---- C API ---- */
CFTypeID IOSurfaceGetTypeID(void) {
    return (CFTypeID)[IOSurface class];
}

void *IOSurfaceCreate(CFDictionaryRef properties) {
    return [[IOSurface alloc] initWithProperties:(NSDictionary *)properties];
}

void *IOSurfaceLookup(uint32_t csid) {
    return NULL;
}

uint32_t IOSurfaceGetID(void *surface) {
    return surface ? ((IOSurface *)surface)->_surfaceID : 0;
}

size_t IOSurfaceGetWidth(void *surface) {
    return surface ? ((IOSurface *)surface)->_width : 0;
}

size_t IOSurfaceGetHeight(void *surface) {
    return surface ? ((IOSurface *)surface)->_height : 0;
}

size_t IOSurfaceGetBytesPerRow(void *surface) {
    return surface ? ((IOSurface *)surface)->_bytesPerRow : 0;
}

size_t IOSurfaceGetAllocSize(void *surface) {
    return surface ? ((IOSurface *)surface)->_allocSize : 0;
}

void *IOSurfaceGetBaseAddress(void *surface) {
    return surface ? ((IOSurface *)surface)->_baseAddress : NULL;
}

uint32_t IOSurfaceGetPixelFormat(void *surface) {
    return surface ? ((IOSurface *)surface)->_pixelFormat : 0;
}

size_t IOSurfaceGetPlaneCount(void *surface) {
    return 0;
}

void *IOSurfaceGetBaseAddressOfPlane(void *surface, size_t planeIndex) {
    return surface ? ((IOSurface *)surface)->_baseAddress : NULL;
}

size_t IOSurfaceGetBytesPerRowOfPlane(void *surface, size_t planeIndex) {
    return surface ? ((IOSurface *)surface)->_bytesPerRow : 0;
}

size_t IOSurfaceGetWidthOfPlane(void *surface, size_t planeIndex) {
    return surface ? ((IOSurface *)surface)->_width : 0;
}

size_t IOSurfaceGetHeightOfPlane(void *surface, size_t planeIndex) {
    return surface ? ((IOSurface *)surface)->_height : 0;
}

kern_return_t IOSurfaceLock(void *surface, uint32_t options, uint32_t *seed) {
    return surface ? [((IOSurface *)surface) lockWithOptions:options seed:seed] : KERN_FAILURE;
}

kern_return_t IOSurfaceUnlock(void *surface, uint32_t options, uint32_t *seed) {
    return surface ? [((IOSurface *)surface) unlockWithOptions:options seed:seed] : KERN_FAILURE;
}

mach_port_t IOSurfaceCreateMachPort(void *surface) {
    return (mach_port_t)(surface ? ((IOSurface *)surface)->_surfaceID : 0);
}

void *IOSurfaceLookupFromMachPort(mach_port_t port) {
    return NULL;
}

