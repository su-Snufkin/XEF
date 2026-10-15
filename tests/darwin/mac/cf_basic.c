#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
int main(void) {
  CFStringRef s = CFStringCreateWithCString(NULL, "Hello CoreFoundation", kCFStringEncodingUTF8);
  char buf[64]; CFStringGetCString(s, buf, sizeof buf, kCFStringEncodingUTF8);
  printf("%s len=%ld\n", buf, (long)CFStringGetLength(s));
  CFMutableArrayRef a = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
  CFArrayAppendValue(a, s); CFArrayAppendValue(a, CFSTR("second"));
  printf("count=%ld\n", (long)CFArrayGetCount(a));
  CFMutableDictionaryRef d = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  int v = 42; CFNumberRef n = CFNumberCreate(NULL, kCFNumberIntType, &v);
  CFDictionarySetValue(d, CFSTR("answer"), n);
  CFNumberRef got = CFDictionaryGetValue(d, CFSTR("answer")); int out = 0; CFNumberGetValue(got, kCFNumberIntType, &out);
  printf("answer=%d\n", out);
  CFStringRef up = CFStringCreateMutableCopy(NULL, 0, s); CFStringUppercase((CFMutableStringRef)up, NULL);
  CFStringGetCString(up, buf, sizeof buf, kCFStringEncodingUTF8); printf("%s\n", buf);
  CFDataRef data = CFDataCreate(NULL, (const UInt8 *)"abc", 3); printf("data=%ld\n", (long)CFDataGetLength(data));
  CFAbsoluteTime t = 0; CFDateRef date = CFDateCreate(NULL, t); printf("date=%f\n", CFDateGetAbsoluteTime(date));
  CFShow(CFSTR("shown"));
  return 0; }
