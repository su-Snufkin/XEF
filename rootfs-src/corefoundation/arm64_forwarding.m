// arm64 message forwarding glue for Darling's CoreFoundation (the original CFForwardingPrep.S has no arm64 port).
//
// objc's _objc_msgForward calls _CF_forwarding_prep_0 with the original registers when a selector is not
// implemented.  This handles forwardingTargetForSelector: (re-sending to the new target) and unrecognized
// selectors (-doesNotRecognizeSelector:, which raises NSInvalidArgumentException).  Full NSInvocation based
// forwarding (-forwardInvocation:) needs an arm64 frame-walker and is not implemented yet.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdio.h>
#include <stdlib.h>

id xef_forwarding_target(id self, SEL sel) {
    Class cls = object_getClass(self);
    if (getenv("XEF_TRACE_FWD")) fprintf(stderr, "xef: forwarding %s %s\n", class_getName(cls), sel_getName(sel));
    if (class_respondsToSelector(cls, @selector(forwardingTargetForSelector:))) {
        id t = ((id (*)(id, SEL, SEL))objc_msgSend)(self, @selector(forwardingTargetForSelector:), sel);
        if (t && t != self) return t;
    }
    if (class_respondsToSelector(cls, @selector(methodSignatureForSelector:))) {
        id sig = ((id (*)(id, SEL, SEL))objc_msgSend)(self, @selector(methodSignatureForSelector:), sel);
        if (sig) {
            Method fi = class_getInstanceMethod(cls, @selector(forwardInvocation:));
            Method base = class_getInstanceMethod([NSObject class], @selector(forwardInvocation:));
            if (fi && fi != base) {
                fprintf(stderr, "xef: -forwardInvocation: forwarding is not supported on arm64 yet (-[%s %s])\n",
                        class_getName(cls), sel_getName(sel));
                abort();
            }
        }
    }
    ((void (*)(id, SEL, SEL))objc_msgSend)(self, @selector(doesNotRecognizeSelector:), sel);
    return nil;
}

__asm__(
    ".text\n"
    ".globl __CF_forwarding_prep_0\n"
    ".p2align 2\n"
    "__CF_forwarding_prep_0:\n"
    "  stp x29, x30, [sp, #-16]!\n"
    "  mov x29, sp\n"
    "  sub sp, sp, #144\n"
    "  stp x0, x1, [sp, #0]\n"
    "  stp x2, x3, [sp, #16]\n"
    "  stp x4, x5, [sp, #32]\n"
    "  stp x6, x7, [sp, #48]\n"
    "  stp d0, d1, [sp, #64]\n"
    "  stp d2, d3, [sp, #80]\n"
    "  stp d4, d5, [sp, #96]\n"
    "  stp d6, d7, [sp, #112]\n"
    "  str x8, [sp, #128]\n"
    "  bl _xef_forwarding_target\n"
    "  mov x9, x0\n"
    "  ldp x0, x1, [sp, #0]\n"
    "  ldp x2, x3, [sp, #16]\n"
    "  ldp x4, x5, [sp, #32]\n"
    "  ldp x6, x7, [sp, #48]\n"
    "  ldp d0, d1, [sp, #64]\n"
    "  ldp d2, d3, [sp, #80]\n"
    "  ldp d4, d5, [sp, #96]\n"
    "  ldp d6, d7, [sp, #112]\n"
    "  ldr x8, [sp, #128]\n"
    "  add sp, sp, #144\n"
    "  ldp x29, x30, [sp], #16\n"
    "  cbz x9, 1f\n"
    "  mov x0, x9\n"
    "  b _objc_msgSend\n"
    "1:\n"
    "  mov x0, #0\n"
    "  ret\n"
    ".globl __CF_forwarding_prep_1\n"
    ".p2align 2\n"
    "__CF_forwarding_prep_1:\n"
    "  b __CF_forwarding_prep_0\n"
    ".globl __CF_forwarding_prep_b\n"
    ".p2align 2\n"
    "__CF_forwarding_prep_b:\n"
    "  b __CF_forwarding_prep_0\n"
);
void __invoke__(void) { fprintf(stderr, "xef: NSInvocation is not supported on arm64 yet\n"); abort(); }
