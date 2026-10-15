/* CoreVideo-lite for xef-osx: CVDisplayLink for the single host display (60 Hz assumed, as in CoreGraphics-lite).
 * A started link calls its output callback from its own thread every 1/60 s like the real one (SDL2's Cocoa GL
 * backend waits on it to emulate swap intervals). CVPixelBuffer & co. are not provided (only FFmpeg's VideoToolbox
 * hwaccel uses them, which is never selected without VideoToolbox). */
#include <CoreFoundation/CoreFoundation.h>
#include <CoreVideo/CoreVideo.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define REFRESH_HZ 60
typedef struct XLink {
  CVDisplayLinkOutputCallback cb; void *ctx;
  pthread_t thread; pthread_mutex_t lock; volatile int running, refs;
} XLink;

static uint64_t now_ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (uint64_t)t.tv_sec * 1000000000ull + t.tv_nsec; }
static void stamp(CVTimeStamp *ts, uint64_t ns) {
  memset(ts, 0, sizeof *ts); ts->version = 0; ts->videoTimeScale = 1000000000; ts->videoTime = (int64_t)ns;
  ts->hostTime = ns; ts->rateScalar = 1.0; ts->videoRefreshPeriod = 1000000000 / REFRESH_HZ;
  ts->flags = kCVTimeStampVideoTimeValid | kCVTimeStampHostTimeValid | kCVTimeStampVideoRefreshPeriodValid | kCVTimeStampRateScalarValid; }

static void *link_thread(void *arg) {
  XLink *l = (XLink *)arg; const uint64_t period = 1000000000ull / REFRESH_HZ; uint64_t next = now_ns() + period;
  while (l->running) {
    uint64_t n0 = now_ns();
    if (next > n0) { struct timespec ts = { (time_t)((next - n0) / 1000000000ull), (long)((next - n0) % 1000000000ull) }; nanosleep(&ts, NULL); }
    if (!l->running) break;
    CVTimeStamp in, out; stamp(&in, now_ns()); stamp(&out, next + period); CVOptionFlags fo = 0;
    pthread_mutex_lock(&l->lock); CVDisplayLinkOutputCallback cb = l->cb; void *ctx = l->ctx; pthread_mutex_unlock(&l->lock);
    if (cb) cb((CVDisplayLinkRef)l, &in, &out, 0, &fo, ctx);
    next += period; uint64_t n = now_ns(); if (next < n) next = n + period;   /* skip missed frames */
  }
  return NULL; }

static CVReturn make(CVDisplayLinkRef *out) {
  if (!out) return kCVReturnInvalidArgument;
  XLink *l = (XLink *)calloc(1, sizeof *l); if (!l) return kCVReturnAllocationFailed;
  pthread_mutex_init(&l->lock, NULL); l->refs = 1; *out = (CVDisplayLinkRef)l; return kCVReturnSuccess; }
CVReturn CVDisplayLinkCreateWithCGDisplay(CGDirectDisplayID d, CVDisplayLinkRef *out) { return make(out); }
CVReturn CVDisplayLinkCreateWithActiveCGDisplays(CVDisplayLinkRef *out) { return make(out); }
CVReturn CVDisplayLinkCreateWithCGDisplays(CGDirectDisplayID *ids, CFIndex n, CVDisplayLinkRef *out) { return make(out); }
CVReturn CVDisplayLinkSetCurrentCGDisplay(CVDisplayLinkRef l, CGDirectDisplayID d) { return kCVReturnSuccess; }
CVReturn CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(CVDisplayLinkRef l, CGLContextObj c, CGLPixelFormatObj p) { return kCVReturnSuccess; }
CGDirectDisplayID CVDisplayLinkGetCurrentCGDisplay(CVDisplayLinkRef l) { return 1; }
CVReturn CVDisplayLinkSetOutputCallback(CVDisplayLinkRef link, CVDisplayLinkOutputCallback cb, void *ctx) {
  XLink *l = (XLink *)link; pthread_mutex_lock(&l->lock); l->cb = cb; l->ctx = ctx; pthread_mutex_unlock(&l->lock); return kCVReturnSuccess; }
CVReturn CVDisplayLinkStart(CVDisplayLinkRef link) {
  XLink *l = (XLink *)link; if (l->running) return kCVReturnSuccess;
  l->running = 1;
  if (pthread_create(&l->thread, NULL, link_thread, l)) { l->running = 0; return kCVReturnError; }
  return kCVReturnSuccess; }
CVReturn CVDisplayLinkStop(CVDisplayLinkRef link) {
  XLink *l = (XLink *)link; if (!l->running) return kCVReturnSuccess;
  l->running = 0; if (!pthread_equal(pthread_self(), l->thread)) pthread_join(l->thread, NULL); else pthread_detach(l->thread);
  return kCVReturnSuccess; }
Boolean CVDisplayLinkIsRunning(CVDisplayLinkRef link) { return ((XLink *)link)->running != 0; }
CVDisplayLinkRef CVDisplayLinkRetain(CVDisplayLinkRef link) { if (link) __sync_fetch_and_add(&((XLink *)link)->refs, 1); return link; }
void CVDisplayLinkRelease(CVDisplayLinkRef link) {
  XLink *l = (XLink *)link; if (!l || __sync_sub_and_fetch(&l->refs, 1) > 0) return;
  CVDisplayLinkStop(link); pthread_mutex_destroy(&l->lock); free(l); }
CVTime CVDisplayLinkGetNominalOutputVideoRefreshPeriod(CVDisplayLinkRef l) { CVTime t = { 1, REFRESH_HZ, 0 }; return t; }
double CVDisplayLinkGetActualOutputVideoRefreshPeriod(CVDisplayLinkRef l) { return 1.0 / REFRESH_HZ; }
CVReturn CVDisplayLinkGetCurrentTime(CVDisplayLinkRef l, CVTimeStamp *out) { if (out) stamp(out, now_ns()); return kCVReturnSuccess; }
