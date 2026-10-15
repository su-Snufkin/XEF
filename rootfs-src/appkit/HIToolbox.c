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
