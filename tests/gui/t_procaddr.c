// glXGetProcAddressARB / eglGetProcAddress must also return the functions the shim implements
// itself (libepoxy fetches glXGetProcAddressARB through glXGetProcAddressARB).
#include <dlfcn.h>
#include <stdio.h>
typedef void* (*GPA)(const unsigned char*);
int main(void) {
    void* h = dlopen("libGL.so.1", RTLD_LAZY);
    GPA gpa = h ? (GPA)dlsym(h, "glXGetProcAddressARB") : 0;
    void* e = dlopen("libEGL.so.1", RTLD_LAZY);
    GPA egpa = e ? (GPA)dlsym(e, "eglGetProcAddress") : 0;
    if (!gpa || !egpa) { printf("missing\n"); return 1; }
    const char* names[] = {"glXGetProcAddressARB", "glXGetProcAddress", "glXChooseVisual", "glXChooseFBConfig",
                           "glClear", "eglGetDisplay", "eglGetProcAddress"};
    int ok = 0;
    for (unsigned i = 0; i < sizeof names / sizeof *names; i++) ok += gpa((const unsigned char*)names[i]) != 0;
    printf("procaddr: %d/7 self=%d egl=%d\n", ok, gpa((const unsigned char*)"glXGetProcAddressARB") == (void*)gpa,
           egpa((const unsigned char*)"glClear") != 0);
    return 0;
}
