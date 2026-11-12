// NSImage / NSBitmapImageRep decoding through the host: size, pixels, drawing into a bitmap, failure on garbage.
// Plain C-level Objective-C (no SDK headers) so it builds on Linux against the SDK stubs.
typedef signed char BOOL;
typedef struct objc_class *Class;
typedef struct objc_object *id;
typedef struct objc_selector *SEL;
typedef struct { double x, y; } Pt;
typedef struct { double w, h; } Sz;
typedef struct { Pt o; Sz s; } Rc;
extern int printf(const char *, ...);
extern id objc_getClass(const char *);
extern id objc_msgSend(id, SEL, ...);
extern SEL sel_registerName(const char *);
extern const char *getenv(const char *);
#define S(s) sel_registerName(s)
#define M0(r, o, s) ((r (*)(id, SEL))objc_msgSend)(o, S(s))
#define M1(r, o, s, t, a) ((r (*)(id, SEL, t))objc_msgSend)(o, S(s), a)
@interface NSObject
+ (id)alloc;
@end
static int fails;
#define CHECK(c) do { if (!(c)) { printf("FAIL: %s (line %d)\n", #c, __LINE__); fails++; } } while (0)
static id str(const char *s) { return M1(id, (id)objc_getClass("NSString"), "stringWithUTF8String:", const char *, s); }
int main(void) {
    id pool = M0(id, M0(id, (id)objc_getClass("NSAutoreleasePool"), "alloc"), "init");
    id img = M1(id, M0(id, (id)objc_getClass("NSImage"), "alloc"), "initWithContentsOfFile:", id, str(getenv("XEF_TEST_PNG")));
    CHECK(img != 0);
    if (!img) { printf("FAIL image_test\n"); return 1; }
    Sz s = ((Sz (*)(id, SEL))objc_msgSend)(img, S("size")); printf("size %g x %g\n", s.w, s.h);
    CHECK(s.w == 4 && s.h == 2);
    id reps = M0(id, img, "representations");
    CHECK(M0(long, reps, "count") >= 1);
    id rep = M1(id, reps, "objectAtIndex:", long, 0);
    CHECK(M0(long, rep, "pixelsWide") == 4 && M0(long, rep, "pixelsHigh") == 2);
    unsigned char *d = M0(unsigned char *, rep, "bitmapData");
    printf("px0 %d %d %d %d\n", d[0], d[1], d[2], d[3]);
    CHECK(d[0] == 255 && d[1] == 0 && d[2] == 0 && d[3] == 255);
    unsigned char *g = d + 2 * 4; CHECK(g[0] == 0 && g[1] >= 127 && g[1] <= 129 && g[3] == 128);   /* green at 50% alpha, premultiplied */
    id raw = M1(id, (id)objc_getClass("NSData"), "dataWithContentsOfFile:", id, str(getenv("XEF_TEST_PNG")));
    id i2 = M1(id, M0(id, (id)objc_getClass("NSImage"), "alloc"), "initWithData:", id, raw);
    CHECK(i2 != 0);
    id junk = ((id (*)(id, SEL, const void *, unsigned long))objc_msgSend)((id)objc_getClass("NSData"), S("dataWithBytes:length:"), "garbage", 7);
    CHECK(M1(id, M0(id, (id)objc_getClass("NSImage"), "alloc"), "initWithData:", id, junk) == 0);
    CHECK(M1(id, M0(id, (id)objc_getClass("NSImage"), "alloc"), "initWithContentsOfFile:", id, str("/nonexistent.png")) == 0);
    id dst = ((id (*)(id, SEL, void *, long, long, long, long, BOOL, BOOL, id, long, long))objc_msgSend)(M0(id, (id)objc_getClass("NSBitmapImageRep"), "alloc"),
        S("initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:"), 0, 8, 4, 8, 4, 1, 0, str("NSDeviceRGBColorSpace"), 0, 0);
    CHECK(dst != 0);
    id gc = M1(id, (id)objc_getClass("NSGraphicsContext"), "graphicsContextWithBitmapImageRep:", id, dst);
    M0(void, (id)objc_getClass("NSGraphicsContext"), "saveGraphicsState");
    M1(void, (id)objc_getClass("NSGraphicsContext"), "setCurrentContext:", id, gc);
    Rc r = {{0, 0}, {8, 4}};
    M1(void, img, "drawInRect:", Rc, r);
    M0(void, (id)objc_getClass("NSGraphicsContext"), "restoreGraphicsState");
    unsigned char *o = M0(unsigned char *, dst, "bitmapData");
    unsigned char *c = o + (2 * 8 + 2) * 4, *e = o + (2 * 8 + 6) * 4;   /* interior of the red and the green half */
    printf("drawn %d %d %d %d | %d %d %d %d\n", c[0], c[1], c[2], c[3], e[0], e[1], e[2], e[3]);
    CHECK(c[0] >= 250 && c[1] < 5 && c[3] >= 250);
    CHECK(e[1] >= 120 && e[1] <= 136 && e[3] >= 120 && e[3] <= 136);
    M0(void, pool, "release");
    printf(fails ? "FAIL image_test\n" : "PASS image_test\n");
    return fails != 0;
}
