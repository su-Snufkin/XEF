/* Mac-oracle implementation of the xef_win_* shim (NSWindow + NSOpenGLContext). Not used under XEF. */
#import <Cocoa/Cocoa.h>
#define GL_SILENCE_DEPRECATION 1
#include <OpenGL/gl.h>
#include <stdio.h>
#include <stdlib.h>

static NSWindow *win; static NSOpenGLContext *ctx; static int W, H;

static int win_create(int w, int h, const char *title, int core) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        W = w; H = h;
        win = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, w, h)
                  styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        [win setTitle:[NSString stringWithUTF8String:title]];
        NSOpenGLPixelFormatAttribute a[] = {NSOpenGLPFAAccelerated, NSOpenGLPFADoubleBuffer,
            NSOpenGLPFAColorSize, 24, NSOpenGLPFADepthSize, 24,
            NSOpenGLPFAOpenGLProfile, core ? NSOpenGLProfileVersion3_2Core : NSOpenGLProfileVersionLegacy, 0};
        NSOpenGLPixelFormat *pf = [[NSOpenGLPixelFormat alloc] initWithAttributes:a];
        if (!pf) return -1;
        ctx = [[NSOpenGLContext alloc] initWithFormat:pf shareContext:nil];
        [ctx setView:[win contentView]];
        [win makeKeyAndOrderFront:nil];
        [ctx makeCurrentContext];
        [ctx update];
    }
    return 0;
}
int xef_win_create(int w, int h, const char *title) { return win_create(w, h, title, 0); }
/* Apple only offers 3.2 core (or 4.1 on newer Macs); major/minor are advisory here */
int xef_win_create_core(int w, int h, const char *title, int major, int minor) {
    (void)major; (void)minor; return win_create(w, h, title, 1);
}
void xef_win_swap(void) { [ctx flushBuffer]; }
int xef_win_poll(void) {
    @autoreleasepool {
        NSEvent *e;
        while ((e = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:nil
                        inMode:NSDefaultRunLoopMode dequeue:YES])) [NSApp sendEvent:e];
    }
    return 0;
}
int xef_win_dump(const char *path) {
    unsigned char *px = malloc((size_t)W * H * 3);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, W, H, GL_RGB, GL_UNSIGNED_BYTE, px);
    FILE *f = fopen(path, "wb"); if (!f) { free(px); return -1; }
    fprintf(f, "P6\n%d %d\n255\n", W, H);
    for (int y = H - 1; y >= 0; y--) fwrite(px + (size_t)y * W * 3, 3, W, f);
    fclose(f); free(px); return 0;
}
