/* IOKit-lite for xef-osx: IORegistry/IOHID entry points used by GLFW (joysticks, monitor names, fallback refresh rate).
 * The host exposes no IORegistry entries and no HID devices: every matching query succeeds with an EMPTY iterator and
 * the HID manager never reports a device (on the Mac without a gamepad GLFW behaves identically: no joysticks). */
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/hid/IOHIDLib.h>
#include <IOKit/graphics/IOGraphicsLib.h>
#include <stdlib.h>

typedef struct { uintptr_t _cfisa; uint8_t _cfinfo[4]; uint32_t _rc; } XBase;
typedef struct { CFIndex version; const char *className; void *init; void *copy; void *finalize; void *equal; void *hash;
                 void *copyFormattingDesc; void *copyDebugDesc; void *reclaim; void *refcount; } XClass;
extern CFTypeID _CFRuntimeRegisterClass(const XClass *cls);
extern CFTypeRef _CFRuntimeCreateInstance(CFAllocatorRef a, CFTypeID id, CFIndex extra, unsigned char *category);

typedef struct { XBase b; IOHIDDeviceCallback match_cb, remove_cb; void *match_ctx, *remove_ctx; CFArrayRef matching; } XManager;
static CFTypeID manager_id, element_id;
static void classes_init(void) {
  if (manager_id) return;
  static XClass m = { 0, "IOHIDManager" }, e = { 0, "IOHIDElement" };   /* CF keeps the pointer */
  manager_id = _CFRuntimeRegisterClass(&m); element_id = _CFRuntimeRegisterClass(&e); }

/* ---- IORegistry: empty ----------------------------------------------------------------------------------------- */
CFMutableDictionaryRef IOServiceMatching(const char *name) {
  CFMutableDictionaryRef d = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  CFStringRef n = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingUTF8);
  CFDictionarySetValue(d, CFSTR("IOProviderClass"), n); CFRelease(n); return d; }
kern_return_t IOServiceGetMatchingServices(mach_port_t port, CFDictionaryRef matching, io_iterator_t *it) {
  if (matching) CFRelease(matching);   /* consumed, as documented */
  if (it) *it = 1;                     /* iterator object that yields nothing */
  return kIOReturnSuccess; }
io_object_t IOIteratorNext(io_iterator_t it) { return 0; }
kern_return_t IOObjectRelease(io_object_t o) { return kIOReturnSuccess; }
CFTypeRef IORegistryEntryCreateCFProperty(io_registry_entry_t e, CFStringRef key, CFAllocatorRef a, IOOptionBits o) { return NULL; }
CFDictionaryRef IODisplayCreateInfoDictionary(io_service_t framebuffer, IOOptionBits options) { return NULL; }   /* no display service exists */

/* ---- IOHID: a manager that never sees a device ------------------------------------------------------------------ */
IOHIDManagerRef IOHIDManagerCreate(CFAllocatorRef a, IOOptionBits o) {
  classes_init(); return (IOHIDManagerRef)_CFRuntimeCreateInstance(a ? a : kCFAllocatorDefault, manager_id, sizeof(XManager) - sizeof(XBase), NULL); }
IOReturn IOHIDManagerOpen(IOHIDManagerRef m, IOOptionBits o) { return kIOReturnSuccess; }
void IOHIDManagerSetDeviceMatchingMultiple(IOHIDManagerRef m, CFArrayRef a) {
  XManager *x = (XManager *)m; if (a) CFRetain(a); if (x->matching) CFRelease(x->matching); x->matching = a; }
void IOHIDManagerRegisterDeviceMatchingCallback(IOHIDManagerRef m, IOHIDDeviceCallback cb, void *ctx) { ((XManager *)m)->match_cb = cb; ((XManager *)m)->match_ctx = ctx; }
void IOHIDManagerRegisterDeviceRemovalCallback(IOHIDManagerRef m, IOHIDDeviceCallback cb, void *ctx) { ((XManager *)m)->remove_cb = cb; ((XManager *)m)->remove_ctx = ctx; }
void IOHIDManagerScheduleWithRunLoop(IOHIDManagerRef m, CFRunLoopRef rl, CFStringRef mode) {}   /* nothing to deliver */

/* Device/element/value accessors: unreachable without devices; they answer as for an unknown device. */
CFArrayRef IOHIDDeviceCopyMatchingElements(IOHIDDeviceRef d, CFDictionaryRef m, IOOptionBits o) { return NULL; }
CFTypeRef IOHIDDeviceGetProperty(IOHIDDeviceRef d, CFStringRef key) { return NULL; }
IOReturn IOHIDDeviceGetValue(IOHIDDeviceRef d, IOHIDElementRef e, IOHIDValueRef *v) { return kIOReturnNoDevice; }
CFTypeID IOHIDElementGetTypeID(void) { classes_init(); return element_id; }
IOHIDElementType IOHIDElementGetType(IOHIDElementRef e) { return 0; }
uint32_t IOHIDElementGetUsage(IOHIDElementRef e) { return 0; }
uint32_t IOHIDElementGetUsagePage(IOHIDElementRef e) { return 0; }
CFIndex IOHIDElementGetLogicalMin(IOHIDElementRef e) { return 0; }
CFIndex IOHIDElementGetLogicalMax(IOHIDElementRef e) { return 0; }
CFIndex IOHIDValueGetIntegerValue(IOHIDValueRef v) { return 0; }
