/* AudioToolbox-lite for xef-osx (also answers the CoreAudio/AudioUnit names: those frameworks are not in the rootfs and
 * the loader finds their symbols here). There is no audio hardware: component lookups find nothing and every HAL /
 * queue / converter call fails, so OpenAL Soft's CoreAudio backend and SDL's audio report "no device" and the program
 * runs silent (as on a Mac without an output device). */
#include <stdint.h>
#include <stddef.h>

typedef int32_t OSStatus;
#define kAudioHardwareUnknownPropertyError 0x77686f3f   /* 'who?' */
#define kAudioHardwareBadObjectError       0x216f626a   /* '!obj' */
#define kAudioComponentErr_InstanceInvalidated (-66749)
#define kAudio_UnimplementedError          (-4)

/* AudioComponent / AudioUnit */
void *AudioComponentFindNext(void *after, const void *desc) { return NULL; }
OSStatus AudioComponentInstanceNew(void *comp, void **out) { if (out) *out = NULL; return kAudioComponentErr_InstanceInvalidated; }
OSStatus AudioComponentInstanceDispose(void *unit) { return 0; }
OSStatus AudioUnitInitialize(void *u) { return kAudio_UnimplementedError; }
OSStatus AudioUnitUninitialize(void *u) { return 0; }
OSStatus AudioUnitGetProperty(void *u, uint32_t id, uint32_t scope, uint32_t el, void *data, uint32_t *size) { return kAudio_UnimplementedError; }
OSStatus AudioUnitGetPropertyInfo(void *u, uint32_t id, uint32_t scope, uint32_t el, uint32_t *size, uint8_t *w) { return kAudio_UnimplementedError; }
OSStatus AudioUnitSetProperty(void *u, uint32_t id, uint32_t scope, uint32_t el, const void *data, uint32_t size) { return kAudio_UnimplementedError; }
OSStatus AudioUnitRender(void *u, uint32_t *flags, const void *ts, uint32_t bus, uint32_t frames, void *list) { return kAudio_UnimplementedError; }
OSStatus AudioOutputUnitStart(void *u) { return kAudio_UnimplementedError; }
OSStatus AudioOutputUnitStop(void *u) { return 0; }

/* CoreAudio HAL: the system object has no devices */
OSStatus AudioObjectGetPropertyDataSize(uint32_t obj, const void *addr, uint32_t qsize, const void *q, uint32_t *size) {
  if (size) *size = 0; return kAudioHardwareUnknownPropertyError; }
OSStatus AudioObjectGetPropertyData(uint32_t obj, const void *addr, uint32_t qsize, const void *q, uint32_t *size, void *data) {
  if (size) *size = 0; return kAudioHardwareUnknownPropertyError; }
OSStatus AudioObjectSetPropertyData(uint32_t obj, const void *addr, uint32_t qsize, const void *q, uint32_t size, const void *data) {
  return kAudioHardwareUnknownPropertyError; }
uint8_t AudioObjectHasProperty(uint32_t obj, const void *addr) { return 0; }
OSStatus AudioObjectAddPropertyListener(uint32_t obj, const void *addr, void *cb, void *ctx) { return 0; }
OSStatus AudioObjectRemovePropertyListener(uint32_t obj, const void *addr, void *cb, void *ctx) { return 0; }

/* AudioQueue */
OSStatus AudioQueueNewOutput(const void *fmt, void *cb, void *ud, void *rl, void *mode, uint32_t flags, void **q) { if (q) *q = NULL; return kAudio_UnimplementedError; }
OSStatus AudioQueueNewInput(const void *fmt, void *cb, void *ud, void *rl, void *mode, uint32_t flags, void **q) { if (q) *q = NULL; return kAudio_UnimplementedError; }
OSStatus AudioQueueAllocateBuffer(void *q, uint32_t size, void **buf) { if (buf) *buf = NULL; return kAudio_UnimplementedError; }
OSStatus AudioQueueEnqueueBuffer(void *q, void *buf, uint32_t n, const void *desc) { return kAudio_UnimplementedError; }
OSStatus AudioQueueSetProperty(void *q, uint32_t id, const void *data, uint32_t size) { return kAudio_UnimplementedError; }
OSStatus AudioQueueStart(void *q, const void *t) { return kAudio_UnimplementedError; }
OSStatus AudioQueueStop(void *q, uint8_t imm) { return 0; }
OSStatus AudioQueueFlush(void *q) { return 0; }
OSStatus AudioQueueDispose(void *q, uint8_t imm) { return 0; }

/* AudioConverter / AudioFormat */
OSStatus AudioConverterNew(const void *in, const void *out, void **conv) { if (conv) *conv = NULL; return kAudio_UnimplementedError; }
OSStatus AudioConverterDispose(void *c) { return 0; }
OSStatus AudioConverterReset(void *c) { return 0; }
OSStatus AudioConverterFillComplexBuffer(void *c, void *proc, void *ud, uint32_t *n, void *list, void *desc) { return kAudio_UnimplementedError; }
OSStatus AudioConverterGetProperty(void *c, uint32_t id, uint32_t *size, void *data) { return kAudio_UnimplementedError; }
OSStatus AudioConverterGetPropertyInfo(void *c, uint32_t id, uint32_t *size, uint8_t *w) { return kAudio_UnimplementedError; }
OSStatus AudioConverterSetProperty(void *c, uint32_t id, uint32_t size, const void *data) { return kAudio_UnimplementedError; }
OSStatus AudioFormatGetProperty(uint32_t id, uint32_t isize, const void *spec, uint32_t *size, void *data) { return kAudio_UnimplementedError; }
OSStatus AudioFormatGetPropertyInfo(uint32_t id, uint32_t isize, const void *spec, uint32_t *size) { return kAudio_UnimplementedError; }
