// arm64 forbids calling objc_msgSend through its (variadic) prototype; Darling's sources do exactly that.
// Rewrite `objc_msgSend(recv, sel, a, b, ...)` calls into correctly typed non-variadic calls.
#pragma once
#include <objc/objc.h>
#include <objc/runtime.h>
#include <objc/message.h>

#define _XEF_MS0(r, s)                      (((id (*)(id, SEL))objc_msgSend)((id)(r), (s)))
#define _XEF_MS1(r, s, a)                   (((id (*)(id, SEL, __typeof__(a)))objc_msgSend)((id)(r), (s), (a)))
#define _XEF_MS2(r, s, a, b)                (((id (*)(id, SEL, __typeof__(a), __typeof__(b)))objc_msgSend)((id)(r), (s), (a), (b)))
#define _XEF_MS3(r, s, a, b, c)             (((id (*)(id, SEL, __typeof__(a), __typeof__(b), __typeof__(c)))objc_msgSend)((id)(r), (s), (a), (b), (c)))
#define _XEF_MS4(r, s, a, b, c, d)          (((id (*)(id, SEL, __typeof__(a), __typeof__(b), __typeof__(c), __typeof__(d)))objc_msgSend)((id)(r), (s), (a), (b), (c), (d)))
#define _XEF_MS5(r, s, a, b, c, d, e)       (((id (*)(id, SEL, __typeof__(a), __typeof__(b), __typeof__(c), __typeof__(d), __typeof__(e)))objc_msgSend)((id)(r), (s), (a), (b), (c), (d), (e)))
#define _XEF_MS6(r, s, a, b, c, d, e, f)    (((id (*)(id, SEL, __typeof__(a), __typeof__(b), __typeof__(c), __typeof__(d), __typeof__(e), __typeof__(f)))objc_msgSend)((id)(r), (s), (a), (b), (c), (d), (e), (f)))
#define _XEF_MS_PICK(_1, _2, _3, _4, _5, _6, _7, _8, NAME, ...) NAME
#define objc_msgSend(...) _XEF_MS_PICK(__VA_ARGS__, _XEF_MS6, _XEF_MS5, _XEF_MS4, _XEF_MS3, _XEF_MS2, _XEF_MS1, _XEF_MS0, _unused)(__VA_ARGS__)

#define _XEF_MI0(r, m)           (((id (*)(id, Method))method_invoke)((id)(r), (m)))
#define _XEF_MI1(r, m, a)        (((id (*)(id, Method, __typeof__(a)))method_invoke)((id)(r), (m), (a)))
#define _XEF_MI2(r, m, a, b)     (((id (*)(id, Method, __typeof__(a), __typeof__(b)))method_invoke)((id)(r), (m), (a), (b)))
#define _XEF_MI3(r, m, a, b, c)  (((id (*)(id, Method, __typeof__(a), __typeof__(b), __typeof__(c)))method_invoke)((id)(r), (m), (a), (b), (c)))
#define _XEF_MI_PICK(_1, _2, _3, _4, _5, NAME, ...) NAME
#define method_invoke(...) _XEF_MI_PICK(__VA_ARGS__, _XEF_MI3, _XEF_MI2, _XEF_MI1, _XEF_MI0, _unused)(__VA_ARGS__)
#define method_invoke_stret method_invoke
#define marg_list void *
