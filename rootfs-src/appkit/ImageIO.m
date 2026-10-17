/*
 * ImageIO implementation for XEF
 * Based on Darling / Apple ImageIO specifications
 */

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

const CFStringRef kCGImageDestinationLossyCompressionQuality = CFSTR("kCGImageDestinationLossyCompressionQuality");
const CFStringRef kCGImageDestinationBackgroundColor = CFSTR("kCGImageDestinationBackgroundColor");
const CFStringRef kCGImageDestinationDPI = CFSTR("kCGImageDestinationDPI");

const CFStringRef kCGImageSourceCreateThumbnailFromImageAlways = CFSTR("kCGImageSourceCreateThumbnailFromImageAlways");
const CFStringRef kCGImageSourceCreateThumbnailFromImageIfAbsent = CFSTR("kCGImageSourceCreateThumbnailFromImageIfAbsent");
const CFStringRef kCGImageSourceCreateThumbnailWithTransform = CFSTR("kCGImageSourceCreateThumbnailWithTransform");
const CFStringRef kCGImageSourceShouldAllowFloat = CFSTR("kCGImageSourceShouldAllowFloat");
const CFStringRef kCGImageSourceShouldCache = CFSTR("kCGImageSourceShouldCache");
const CFStringRef kCGImageSourceThumbnailMaxPixelSize = CFSTR("kCGImageSourceThumbnailMaxPixelSize");

const CFStringRef kCGImagePropertyDPIWidth = CFSTR("DPIWidth");
const CFStringRef kCGImagePropertyDPIHeight = CFSTR("DPIHeight");
const CFStringRef kCGImagePropertyPixelHeight = CFSTR("PixelHeight");
const CFStringRef kCGImagePropertyPixelWidth = CFSTR("PixelWidth");
const CFStringRef kCGImagePropertyOrientation = CFSTR("Orientation");
const CFStringRef kCGImagePropertyTIFFDictionary = CFSTR("{TIFF}");
const CFStringRef kCGImagePropertyExifDictionary = CFSTR("{Exif}");
const CFStringRef kCGImagePropertyTIFFXResolution = CFSTR("XResolution");
const CFStringRef kCGImagePropertyTIFFYResolution = CFSTR("YResolution");
const CFStringRef kCGImagePropertyTIFFOrientation = CFSTR("Orientation");
const CFStringRef kCGImagePropertyPNGDictionary = CFSTR("{PNG}");
const CFStringRef kCGImagePropertyPNGGamma = CFSTR("Gamma");
const CFStringRef kCGImagePropertyGIFDelayTime = CFSTR("DelayTime");
const CFStringRef kCGImagePropertyGIFDictionary = CFSTR("{GIF}");
const CFStringRef kCGImagePropertyGIFLoopCount = CFSTR("LoopCount");
const CFStringRef kCGImagePropertyGIFUnclampedDelayTime = CFSTR("UnclampedDelayTime");
const CFStringRef kCGImagePropertyHasAlpha = CFSTR("HasAlpha");
const CFStringRef kCGImagePropertyProfileName = CFSTR("ProfileName");
const CFStringRef kCGImagePropertyAPNGDelayTime = CFSTR("APNGDelayTime");
const CFStringRef kCGImagePropertyAPNGLoopCount = CFSTR("APNGLoopCount");

typedef struct CGImageSource {
    CFDataRef data;
    CFURLRef url;
    CFDictionaryRef options;
    size_t count;
} CGImageSource;

typedef struct CGImageDestination {
    CFMutableDataRef data;
    CFURLRef url;
    CFStringRef type;
    size_t imageCount;
    CFDictionaryRef options;
    NSMutableArray *images;
} CGImageDestination;

typedef CGImageSource *CGImageSourceRef;
typedef CGImageDestination *CGImageDestinationRef;

CGImageSourceRef CGImageSourceCreateWithData(CFDataRef data, CFDictionaryRef options) {
    if (!data) return NULL;
    CGImageSource *src = (CGImageSource *)malloc(sizeof(CGImageSource));
    if (!src) return NULL;
    src->data = (CFDataRef)CFRetain(data);
    src->url = NULL;
    src->options = options ? (CFDictionaryRef)CFRetain(options) : NULL;
    src->count = 1;
    return src;
}

CGImageSourceRef CGImageSourceCreateWithURL(CFURLRef url, CFDictionaryRef options) {
    if (!url) return NULL;
    CGImageSource *src = (CGImageSource *)malloc(sizeof(CGImageSource));
    if (!src) return NULL;
    src->data = NULL;
    src->url = (CFURLRef)CFRetain(url);
    src->options = options ? (CFDictionaryRef)CFRetain(options) : NULL;
    src->count = 1;
    return src;
}

CGImageSourceRef CGImageSourceCreateWithDataProvider(CGDataProviderRef provider, CFDictionaryRef options) {
    CGImageSource *src = (CGImageSource *)malloc(sizeof(CGImageSource));
    if (!src) return NULL;
    src->data = NULL;
    src->url = NULL;
    src->options = options ? (CFDictionaryRef)CFRetain(options) : NULL;
    src->count = 1;
    return src;
}

size_t CGImageSourceGetCount(CGImageSourceRef self) {
    return self ? self->count : 0;
}

CFStringRef CGImageSourceGetType(CGImageSourceRef self) {
    return CFSTR("public.png");
}

CGImageRef CGImageSourceCreateImageAtIndex(CGImageSourceRef self, size_t index, CFDictionaryRef options) {
    return NULL;
}

CFDictionaryRef CGImageSourceCopyPropertiesAtIndex(CGImageSourceRef self, size_t index, CFDictionaryRef options) {
    NSDictionary *dict = @{
        (id)kCGImagePropertyPixelWidth: @(800),
        (id)kCGImagePropertyPixelHeight: @(600),
        (id)kCGImagePropertyHasAlpha: @(YES)
    };
    return (CFDictionaryRef)[dict retain];
}

CFTypeID CGImageDestinationGetTypeID(void) {
    return 1001;
}

CFArrayRef CGImageDestinationCopyTypeIdentifiers(void) {
    NSArray *types = @[
        @"public.png",
        @"public.jpeg",
        @"public.tiff"
    ];
    return (CFArrayRef)[types retain];
}

CGImageDestinationRef CGImageDestinationCreateWithData(CFMutableDataRef data, CFStringRef type, size_t imageCount, CFDictionaryRef options) {
    CGImageDestination *dst = (CGImageDestination *)malloc(sizeof(CGImageDestination));
    if (!dst) return NULL;
    dst->data = data ? (CFMutableDataRef)CFRetain(data) : NULL;
    dst->url = NULL;
    dst->type = type ? (CFStringRef)CFRetain(type) : NULL;
    dst->imageCount = imageCount;
    dst->options = options ? (CFDictionaryRef)CFRetain(options) : NULL;
    dst->images = [[NSMutableArray alloc] init];
    return dst;
}

CGImageDestinationRef CGImageDestinationCreateWithDataConsumer(CGDataConsumerRef dataConsumer, CFStringRef type, size_t imageCount, CFDictionaryRef options) {
    return CGImageDestinationCreateWithData(NULL, type, imageCount, options);
}

CGImageDestinationRef CGImageDestinationCreateWithURL(CFURLRef url, CFStringRef type, size_t imageCount, CFDictionaryRef options) {
    CGImageDestination *dst = (CGImageDestination *)malloc(sizeof(CGImageDestination));
    if (!dst) return NULL;
    dst->data = NULL;
    dst->url = url ? (CFURLRef)CFRetain(url) : NULL;
    dst->type = type ? (CFStringRef)CFRetain(type) : NULL;
    dst->imageCount = imageCount;
    dst->options = options ? (CFDictionaryRef)CFRetain(options) : NULL;
    dst->images = [[NSMutableArray alloc] init];
    return dst;
}

void CGImageDestinationSetProperties(CGImageDestinationRef self, CFDictionaryRef properties) {
}

void CGImageDestinationAddImage(CGImageDestinationRef self, CGImageRef image, CFDictionaryRef properties) {
    if (self && self->images && image) {
        [self->images addObject:(id)image];
    }
}

void CGImageDestinationAddImageFromSource(CGImageDestinationRef self, CGImageSourceRef imageSource, size_t index, CFDictionaryRef properties) {
}

bool CGImageDestinationFinalize(CGImageDestinationRef self) {
    return true;
}

