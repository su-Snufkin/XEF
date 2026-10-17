/*
 * sw_vers implementation for XEF
 * Based on Darling specifications
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <CoreFoundation/CoreFoundation.h>

int main(int argc, char *argv[]) {
    CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, CFSTR("/System/Library/CoreServices/SystemVersion.plist"), kCFURLPOSIXPathStyle, false);
    CFReadStreamRef stream = url ? CFReadStreamCreateWithFile(kCFAllocatorDefault, url) : NULL;
    CFDictionaryRef dict = NULL;
    if (stream) {
        if (CFReadStreamOpen(stream)) {
            dict = (CFDictionaryRef)CFPropertyListCreateWithStream(kCFAllocatorDefault, stream, 0, kCFPropertyListImmutable, NULL, NULL);
        }
        CFRelease(stream);
    }
    if (url) CFRelease(url);

    const char *prodName = "macOS";
    const char *prodVer = "14.0";
    const char *buildVer = "23A344";

    char buf[256];
    if (dict) {
        CFStringRef s = (CFStringRef)CFDictionaryGetValue(dict, CFSTR("ProductName"));
        if (s && CFStringGetCString(s, buf, sizeof(buf), kCFStringEncodingUTF8)) prodName = strdup(buf);
        s = (CFStringRef)CFDictionaryGetValue(dict, CFSTR("ProductVersion"));
        if (s && CFStringGetCString(s, buf, sizeof(buf), kCFStringEncodingUTF8)) prodVer = strdup(buf);
        s = (CFStringRef)CFDictionaryGetValue(dict, CFSTR("BuildVersion"));
        if (s && CFStringGetCString(s, buf, sizeof(buf), kCFStringEncodingUTF8)) buildVer = strdup(buf);
        CFRelease(dict);
    }

    if (argc >= 2) {
        if (!strcmp(argv[1], "-productName")) {
            printf("%s\n", prodName);
        } else if (!strcmp(argv[1], "-productVersion")) {
            printf("%s\n", prodVer);
        } else if (!strcmp(argv[1], "-buildVersion")) {
            printf("%s\n", buildVer);
        } else {
            fprintf(stderr, "Usage: %s [-productName|-productVersion|-buildVersion]\n", argv[0]);
            return 1;
        }
    } else {
        printf("ProductName:    %s\n", prodName);
        printf("ProductVersion: %s\n", prodVer);
        printf("BuildVersion:   %s\n", buildVer);
    }
    return 0;
}
