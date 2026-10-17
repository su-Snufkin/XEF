/*
 * CoreText implementation for XEF
 * Based on Darling / Apple CoreText specifications
 */

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>

const CFStringRef kCTFontAttributeName = CFSTR("NSFont");
const CFStringRef kCTForegroundColorAttributeName = CFSTR("NSColor");
const CFStringRef kCTParagraphStyleAttributeName = CFSTR("NSParagraphStyle");
const CFStringRef kCTFontFamilyNameAttribute = CFSTR("NSFontFamilyName");

typedef const struct __CTFont *CTFontRef;
typedef const struct __CTFontDescriptor *CTFontDescriptorRef;
typedef const struct __CTLine *CTLineRef;
typedef const struct __CTRun *CTRunRef;
typedef const struct __CTTypesetter *CTTypesetterRef;
typedef const struct __CTFrame *CTFrameRef;
typedef const struct __CTFramesetter *CTFramesetterRef;

typedef struct __CTFont {
    uintptr_t _cfisa;
    uint8_t _cfinfo[4];
    uint32_t _rc;
    CFStringRef name;
    CGFloat size;
} CTFont;

typedef struct __CTLine {
    uintptr_t _cfisa;
    uint8_t _cfinfo[4];
    uint32_t _rc;
    CFAttributedStringRef attrStr;
} CTLine;

CTFontRef CTFontCreateWithName(CFStringRef name, CGFloat size, const CGAffineTransform *matrix) {
    CTFont *f = (CTFont *)calloc(1, sizeof(CTFont));
    if (f) {
        f->name = name ? CFStringCreateCopy(kCFAllocatorDefault, name) : CFSTR("Helvetica");
        f->size = size > 0 ? size : 12.0;
    }
    return (CTFontRef)f;
}

CTFontRef CTFontCreateUIFontForType(uint32_t uiType, CGFloat size, CFStringRef language) {
    return CTFontCreateWithName(CFSTR("Helvetica"), size, NULL);
}

CGFloat CTFontGetSize(CTFontRef font) {
    return font ? font->size : 12.0;
}

CFStringRef CTFontCopyPostScriptName(CTFontRef font) {
    return font && font->name ? CFStringCreateCopy(kCFAllocatorDefault, font->name) : CFSTR("Helvetica");
}

CFStringRef CTFontCopyFamilyName(CTFontRef font) {
    return font && font->name ? CFStringCreateCopy(kCFAllocatorDefault, font->name) : CFSTR("Helvetica");
}

CTLineRef CTLineCreateWithAttributedString(CFAttributedStringRef attrString) {
    CTLine *l = (CTLine *)calloc(1, sizeof(CTLine));
    if (l) {
        l->attrStr = attrString ? (CFAttributedStringRef)CFRetain(attrString) : NULL;
    }
    return (CTLineRef)l;
}

double CTLineGetTypographicBounds(CTLineRef line, CGFloat *ascent, CGFloat *descent, CGFloat *leading) {
    if (ascent) *ascent = 10.0;
    if (descent) *descent = 3.0;
    if (leading) *leading = 2.0;
    return 100.0;
}

void CTLineDraw(CTLineRef line, CGContextRef context) {
}

CFArrayRef CTLineGetGlyphRuns(CTLineRef line) {
    return CFArrayCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks);
}

CTTypesetterRef CTTypesetterCreateWithAttributedString(CFAttributedStringRef attrString) {
    return (CTTypesetterRef)calloc(1, 64);
}

CTLineRef CTTypesetterCreateLine(CTTypesetterRef ts, CFRange range) {
    return CTLineCreateWithAttributedString(NULL);
}

CTFramesetterRef CTFramesetterCreateWithAttributedString(CFAttributedStringRef attrString) {
    return (CTFramesetterRef)calloc(1, 64);
}

CTFrameRef CTFramesetterCreateFrame(CTFramesetterRef fs, CFRange range, CGPathRef path, CFDictionaryRef frameAttributes) {
    return (CTFrameRef)calloc(1, 64);
}

void CTFrameDraw(CTFrameRef frame, CGContextRef context) {
}

CFArrayRef CTFrameGetLines(CTFrameRef frame) {
    return CFArrayCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks);
}

void CTFrameGetLineOrigins(CTFrameRef frame, CFRange range, CGPoint *origins) {
    if (origins && range.length > 0) {
        for (CFIndex i = 0; i < range.length; i++) {
            origins[i] = CGPointZero;
        }
    }
}

