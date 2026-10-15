/* HIToolbox-lite for xef-osx: the Text Input Source (TIS) entry points GLFW fetches through CFBundle
 * (com.apple.HIToolbox) to query the keyboard layout. The current layout is fixed to "U.S." (see UCKeyTranslate in
 * CoreServices-lite; the layout-data blob is an opaque token that UCKeyTranslate ignores). */
#include <CoreFoundation/CoreFoundation.h>

CFStringRef kTISPropertyUnicodeKeyLayoutData = CFSTR("TISPropertyUnicodeKeyLayoutData");
CFStringRef kTISPropertyInputSourceID = CFSTR("TISPropertyInputSourceID");

CFTypeRef TISCopyCurrentKeyboardLayoutInputSource(void) {
  static const unsigned char uchr[] = { 0x10, 0x02, 0, 0, 'U', '.', 'S', '.' };   /* placeholder 'uchr' header (version 0x1002) */
  CFMutableDictionaryRef d = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  CFDataRef data = CFDataCreate(kCFAllocatorDefault, uchr, sizeof uchr);
  CFDictionarySetValue(d, kTISPropertyUnicodeKeyLayoutData, data); CFRelease(data);
  CFDictionarySetValue(d, kTISPropertyInputSourceID, CFSTR("com.apple.keylayout.US"));
  return d; }
CFTypeRef TISGetInputSourceProperty(CFTypeRef src, CFStringRef key) { return src ? CFDictionaryGetValue((CFDictionaryRef)src, key) : NULL; }
unsigned char LMGetKbdType(void) { return 40; }   /* ANSI keyboard */

/* SDL2 asks for the physical layout of the keyboard type to swap the ISO section key: ANSI, as LMGetKbdType says */
int16_t KBGetLayoutType(int16_t kbdType) { return 0; }   /* kKeyboardANSI */

/* Process Manager (HIServices, re-exported through Carbon/ApplicationServices): there is exactly one process and it
 * is always a foreground application; X11 decides activation, so making it frontmost is a no-op. */
typedef struct { uint32_t highLongOfPSN, lowLongOfPSN; } XProcessSerialNumber;
int16_t GetCurrentProcess(XProcessSerialNumber *psn) { if (psn) { psn->highLongOfPSN = 0; psn->lowLongOfPSN = 2; } return 0; }   /* kCurrentProcess */
int16_t SetFrontProcess(const XProcessSerialNumber *psn) { return 0; }
int32_t TransformProcessType(const XProcessSerialNumber *psn, uint32_t type) { return 0; }
