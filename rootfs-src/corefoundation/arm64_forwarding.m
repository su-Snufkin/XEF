// NSInvocation and message forwarding for arm64 (replaces Darling's NSInvocation.m, which needs an x86-only
// __invoke__ and a CFForwardingPrep.S that has no arm64 port).
//
// The calling convention is Apple's AAPCS64: integer and pointer arguments in x0-x7, float, double and homogeneous
// float aggregates (HFAs of up to four members) in d0-d7, other aggregates of up to 16 bytes in one or two integer
// registers, larger ones by reference; what does not fit goes to the stack at the type's natural alignment (aggregates
// in 8-byte slots). A result comes back in x0 / x1, d0-d3, or through the buffer x8 points to.
//
// * NSInvocation: arguments are kept in buffers; -invoke places them in registers and on the stack and calls
//   objc_msgSend (or an IMP) through xef_invoke_asm.
// * _CF_forwarding_prep_0 (objc's forward handler): re-sends to -forwardingTargetForSelector:, or builds an
//   NSInvocation from the saved registers and the caller's stack arguments, calls -forwardInvocation: and returns the
//   invocation's return value in the registers the caller expects.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef enum { K_VOID, K_INT, K_FLT, K_DBL, K_HFA, K_SMALL, K_BIG } Kind;
typedef struct {
  Kind kind; size_t size, align; int n; char base;   /* HFA: n members of float ('f') or double ('d') */
  char t0; int gp, fp; size_t stack; int where;       /* where: 0 registers, 1 stack */
} Loc;

typedef struct { uint64_t gp[8]; uint64_t fp[8]; uint64_t x8; uint64_t rgp[2]; uint64_t rfp[4]; } Regs;   /* 184 bytes */
extern void xef_invoke_asm(void *fn, Regs *r, const void *stack, size_t stackSize);

/* ------------------------------------------------------------------------------------------------ classification */
static const char *skip_qual(const char *t) { while (*t && strchr("rnNoORV", *t)) t++; return t; }

/* all members of the aggregate are floats of one kind? (consumes one type from *pp) */
static BOOL flatten(const char **pp, char *base, int *count) {
  const char *p = skip_qual(*pp);
  switch (*p) {
    case 'f': case 'd': case 'D': { char b = *p == 'f' ? 'f' : 'd'; if (*base && *base != b) return NO; *base = b; (*count)++; NSUInteger sz, al; *pp = NSGetSizeAndAlignment(p, &sz, &al); return YES; }
    case '{': {
      const char *q = p + 1; while (*q && *q != '=' && *q != '}') q++;
      if (*q == '=') q++;
      while (*q && *q != '}') if (!flatten(&q, base, count)) return NO;
      NSUInteger sz, al; *pp = NSGetSizeAndAlignment(p, &sz, &al); return YES; }
    case '[': {
      int n = atoi(p + 1); const char *q = p + 1; while (*q >= '0' && *q <= '9') q++;
      for (int i = 0; i < n; i++) { const char *r = q; if (!flatten(&r, base, count)) return NO; }
      NSUInteger sz, al; *pp = NSGetSizeAndAlignment(p, &sz, &al); return YES; }
    default: return NO; } }

static void classify(const char *type, Loc *l) {
  const char *t = skip_qual(type); NSUInteger sz = 0, al = 1;
  memset(l, 0, sizeof *l); l->t0 = *t;
  if (*t == 'v') { l->kind = K_VOID; return; }
  NSGetSizeAndAlignment(t, &sz, &al); l->size = sz; l->align = al ? al : 1;
  switch (*t) {
    case 'f': l->kind = K_FLT; return;
    case 'd': case 'D': l->kind = K_DBL; return;
    case '{': case '(': case '[': {
      char base = 0; int n = 0; const char *p = t;
      if (*t != '(' && flatten(&p, &base, &n) && n >= 1 && n <= 4) { l->kind = K_HFA; l->base = base; l->n = n; return; }
      l->kind = sz <= 16 ? K_SMALL : K_BIG; return; }
    default: l->kind = K_INT; return; } }

/* places every argument: index 0 is the return value, 1 + i is argument i */
static size_t layout(NSMethodSignature *sig, Loc *loc) {
  classify([sig methodReturnType], &loc[0]);
  NSUInteger n = [sig numberOfArguments]; int gp = 0, fp = 0; size_t stack = 0;
  for (NSUInteger i = 0; i < n; i++) {
    Loc *l = &loc[1 + i]; classify([sig getArgumentTypeAtIndex:i], l);
    size_t align = l->align, size = l->size;
    switch (l->kind) {
      case K_FLT: case K_DBL: case K_HFA: {
        int need = l->kind == K_HFA ? l->n : 1;
        if (fp + need <= 8) { l->where = 0; l->fp = fp; fp += need; break; }
        fp = 8; l->where = 1; if (l->kind == K_HFA) size = (size + 7) & ~(size_t)7; stack = (stack + align - 1) & ~(align - 1); l->stack = stack; stack += size; break; }
      case K_SMALL: {
        int need = (int)((size + 7) / 8);
        if (align >= 16 && (gp & 1)) gp++;
        if (gp + need <= 8) { l->where = 0; l->gp = gp; gp += need; break; }
        gp = 8; l->where = 1; size = (size + 7) & ~(size_t)7; stack = (stack + 7) & ~(size_t)7; l->stack = stack; stack += size; break; }
      case K_BIG:
        if (gp < 8) { l->where = 0; l->gp = gp++; break; }
        l->where = 1; stack = (stack + 7) & ~(size_t)7; l->stack = stack; stack += 8; break;
      default:
        if (gp < 8) { l->where = 0; l->gp = gp++; break; }
        l->where = 1; if (size < 1) size = 1; stack = (stack + align - 1) & ~(align - 1); l->stack = stack; stack += size; break; } }
  return (stack + 15) & ~(size_t)15; }

/* value <-> registers */
static void put_scalar(uint64_t *reg, const char *type, const void *src, size_t size) {
  uint64_t v = 0; const char *t = skip_qual(type);
  switch (*t) {
    case 'c': v = (uint64_t)(int64_t)*(const signed char *)src; break; case 'C': case 'B': v = *(const unsigned char *)src; break;
    case 's': v = (uint64_t)(int64_t)*(const short *)src; break; case 'S': v = *(const unsigned short *)src; break;
    case 'i': v = (uint64_t)(int64_t)*(const int *)src; break; case 'I': v = *(const unsigned int *)src; break;
    default: memcpy(&v, src, size > 8 ? 8 : size); break; }
  *reg = v; }

static void fill_arg(Regs *r, uint8_t *stack, const Loc *l, const char *type, const void *src, void **temps, int *ntemps) {
  switch (l->kind) {
    case K_INT: if (l->where == 0) put_scalar(&r->gp[l->gp], type, src, l->size); else { uint64_t v; put_scalar(&v, type, src, l->size); memcpy(stack + l->stack, &v, l->size); } break;
    case K_FLT: if (l->where == 0) { uint64_t v = 0; memcpy(&v, src, 4); r->fp[l->fp] = v; } else memcpy(stack + l->stack, src, 4); break;
    case K_DBL: if (l->where == 0) memcpy(&r->fp[l->fp], src, 8); else memcpy(stack + l->stack, src, 8); break;
    case K_HFA: {
      if (l->where == 0) { size_t m = l->base == 'f' ? 4 : 8; for (int i = 0; i < l->n; i++) { uint64_t v = 0; memcpy(&v, (const uint8_t *)src + i * m, m); r->fp[l->fp + i] = v; } }
      else memcpy(stack + l->stack, src, l->size);
      break; }
    case K_SMALL: {
      if (l->where == 0) { uint64_t v[2] = { 0, 0 }; memcpy(v, src, l->size); r->gp[l->gp] = v[0]; if (l->size > 8) r->gp[l->gp + 1] = v[1]; }
      else memcpy(stack + l->stack, src, l->size);
      break; }
    case K_BIG: {
      void *copy = malloc(l->size); memcpy(copy, src, l->size); temps[(*ntemps)++] = copy;
      if (l->where == 0) r->gp[l->gp] = (uint64_t)copy; else memcpy(stack + l->stack, &copy, 8);
      break; }
    default: break; } }

static void fetch_arg(const Regs *r, const uint8_t *stack, const Loc *l, void *dst) {
  switch (l->kind) {
    case K_INT: if (l->where == 0) memcpy(dst, &r->gp[l->gp], l->size > 8 ? 8 : l->size); else memcpy(dst, stack + l->stack, l->size); break;
    case K_FLT: if (l->where == 0) memcpy(dst, &r->fp[l->fp], 4); else memcpy(dst, stack + l->stack, 4); break;
    case K_DBL: if (l->where == 0) memcpy(dst, &r->fp[l->fp], 8); else memcpy(dst, stack + l->stack, 8); break;
    case K_HFA: {
      if (l->where == 0) { size_t m = l->base == 'f' ? 4 : 8; for (int i = 0; i < l->n; i++) memcpy((uint8_t *)dst + i * m, &r->fp[l->fp + i], m); }
      else memcpy(dst, stack + l->stack, l->size);
      break; }
    case K_SMALL: {
      if (l->where == 0) { uint64_t v[2] = { r->gp[l->gp], l->size > 8 ? r->gp[l->gp + 1] : 0 }; memcpy(dst, v, l->size); }
      else memcpy(dst, stack + l->stack, l->size);
      break; }
    case K_BIG: { void *p; if (l->where == 0) p = (void *)r->gp[l->gp]; else memcpy(&p, stack + l->stack, 8); memcpy(dst, p, l->size); break; }
    default: break; } }

static void take_result(const Regs *r, const Loc *l, void *dst) {
  switch (l->kind) {
    case K_INT: memcpy(dst, &r->rgp[0], l->size > 8 ? 8 : l->size); break;
    case K_FLT: memcpy(dst, &r->rfp[0], 4); break;
    case K_DBL: memcpy(dst, &r->rfp[0], 8); break;
    case K_HFA: { size_t m = l->base == 'f' ? 4 : 8; for (int i = 0; i < l->n; i++) memcpy((uint8_t *)dst + i * m, &r->rfp[i], m); break; }
    case K_SMALL: { uint64_t v[2] = { r->rgp[0], r->rgp[1] }; memcpy(dst, v, l->size); break; }
    default: break; } }                               /* K_BIG: the callee wrote through x8 */

static void give_result(Regs *r, const Loc *l, const char *type, const void *src) {
  switch (l->kind) {
    case K_INT: put_scalar(&r->rgp[0], type, src, l->size); break;
    case K_FLT: { uint64_t v = 0; memcpy(&v, src, 4); r->rfp[0] = v; break; }
    case K_DBL: memcpy(&r->rfp[0], src, 8); break;
    case K_HFA: { size_t m = l->base == 'f' ? 4 : 8; for (int i = 0; i < l->n; i++) { uint64_t v = 0; memcpy(&v, (const uint8_t *)src + i * m, m); r->rfp[i] = v; } break; }
    case K_SMALL: { uint64_t v[2] = { 0, 0 }; memcpy(v, src, l->size); r->rgp[0] = v[0]; r->rgp[1] = v[1]; break; }
    case K_BIG: memcpy((void *)r->x8, src, l->size); break;
    default: break; } }

/* ------------------------------------------------------------------------------------------------ NSInvocation */
/* the header's ivars hold the state: _frame points to this block */
typedef struct { NSMethodSignature *sig; void **args; void *ret; Loc *loc; size_t stack; NSUInteger n; BOOL retained; } State;
#define ST ((State *)_frame)

extern void _CF_forwarding_prep_0(void);
extern void _CF_forwarding_prep_1(void);
extern void objc_setForwardHandler(void *fwd, void *fwd_stret);

@implementation NSInvocation
+ (void)load { objc_setForwardHandler((void *)&_CF_forwarding_prep_0, (void *)&_CF_forwarding_prep_1); }
+ (NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)sig {
  if (!sig) [NSException raise:NSInvalidArgumentException format:@"+[NSInvocation invocationWithMethodSignature:]: method signature argument cannot be nil"];
  NSInvocation *i = [[self alloc] init];
  State *s = calloc(1, sizeof(State)); i->_frame = s; i->_signature = [sig retain];
  s->sig = sig; s->n = [sig numberOfArguments];
  s->loc = calloc(s->n + 1, sizeof(Loc)); s->stack = layout(sig, s->loc);
  s->args = calloc(s->n ? s->n : 1, sizeof(void *));
  for (NSUInteger k = 0; k < s->n; k++) s->args[k] = calloc(1, s->loc[1 + k].size < 8 ? 8 : s->loc[1 + k].size);
  s->ret = calloc(1, s->loc[0].size < 8 ? 8 : s->loc[0].size);
  return [i autorelease]; }
- (void)dealloc {
  State *s = ST;
  if (s) {
    if (s->retained) for (NSUInteger k = 0; k < s->n; k++) if (s->loc[1 + k].t0 == '@' && *(id *)s->args[k]) [*(id *)s->args[k] release];
    for (NSUInteger k = 0; k < s->n; k++) free(s->args[k]);
    free(s->args); free(s->ret); free(s->loc); free(s); }
  [_signature release]; [super dealloc]; }
- (NSMethodSignature *)methodSignature { return _signature; }
- (id)target { return *(id *)ST->args[0]; } - (SEL)selector { return *(SEL *)ST->args[1]; }
- (void)setTarget:(id)t { [self setArgument:&t atIndex:0]; } - (void)setSelector:(SEL)sel { [self setArgument:&sel atIndex:1]; }
- (void)setArgument:(void *)buf atIndex:(NSInteger)i {
  State *s = ST;
  if (i < 0 || i >= (NSInteger)s->n) [NSException raise:NSInvalidArgumentException format:@"NSInvocation: index (%ld) out of bounds [-1, %lu]", (long)i, (unsigned long)s->n - 1];
  if (s->retained && s->loc[1 + i].t0 == '@') { id n = *(id *)buf, o = *(id *)s->args[i]; [n retain]; [o release]; }
  memcpy(s->args[i], buf, s->loc[1 + i].size); }
- (void)getArgument:(void *)buf atIndex:(NSInteger)i {
  State *s = ST;
  if (i < 0 || i >= (NSInteger)s->n) [NSException raise:NSInvalidArgumentException format:@"NSInvocation: index (%ld) out of bounds [-1, %lu]", (long)i, (unsigned long)s->n - 1];
  memcpy(buf, s->args[i], s->loc[1 + i].size); }
- (void)setReturnValue:(void *)buf { memcpy(ST->ret, buf, ST->loc[0].size); }
- (void)getReturnValue:(void *)buf { memcpy(buf, ST->ret, ST->loc[0].size); }
- (BOOL)argumentsRetained { return ST->retained; }
- (void)retainArguments {
  State *s = ST; if (s->retained) return;
  s->retained = YES;
  for (NSUInteger k = 0; k < s->n; k++) if (s->loc[1 + k].t0 == '@' && *(id *)s->args[k]) [*(id *)s->args[k] retain]; }
- (void)_xefCall:(void *)fn receiver:(id)receiver {
  State *s = ST; Regs r; memset(&r, 0, sizeof r);
  uint8_t *stack = s->stack ? calloc(1, s->stack) : NULL; void *temps[16]; int ntemps = 0;
  for (NSUInteger k = 0; k < s->n; k++) {
    void *src = s->args[k]; if (k == 0) src = &receiver;
    fill_arg(&r, stack, &s->loc[1 + k], [s->sig getArgumentTypeAtIndex:k], src, temps, &ntemps); }
  if (s->loc[0].kind == K_BIG) r.x8 = (uint64_t)s->ret;
  xef_invoke_asm(fn, &r, stack, s->stack);
  take_result(&r, &s->loc[0], s->ret);
  free(stack); for (int k = 0; k < ntemps; k++) free(temps[k]); }
- (void)invokeUsingIMP:(IMP)imp { [self _xefCall:(void *)imp receiver:[self target]]; }
- (void)invoke { id t = [self target]; if (!t) return; [self _xefCall:(void *)&objc_msgSend receiver:t]; }
- (void)invokeWithTarget:(id)t { [self setTarget:t]; [self invoke]; }
- (void)invokeSuper {
  id t = [self target]; if (!t) return;
  struct objc_super sup = { t, class_getSuperclass(object_getClass(t)) };
  [self _xefCall:(void *)&objc_msgSendSuper receiver:(id)&sup]; }
- (NSString *)description { return [NSString stringWithFormat:@"<%@: %p>", [self class], self]; }
- (Loc *)_xefLocs { return ST->loc; } - (void **)_xefArgs { return ST->args; } - (void *)_xefRet { return ST->ret; }
@end

/* ------------------------------------------------------------------------------------------------ forwarding */
/* returns 0 to re-send to the (new) receiver in r->gp[0], 1 when the result is in r->rgp / r->rfp / *x8 */
int xef_forwarding_dispatch(Regs *r, const uint8_t *stack) {
  id self = (id)r->gp[0]; SEL sel = (SEL)r->gp[1]; Class cls = object_getClass(self);
  if (getenv("XEF_TRACE_FWD")) fprintf(stderr, "xef: forwarding %s %s\n", class_getName(cls), sel_getName(sel));
  if (class_respondsToSelector(cls, @selector(forwardingTargetForSelector:))) {
    id t = ((id (*)(id, SEL, SEL))objc_msgSend)(self, @selector(forwardingTargetForSelector:), sel);
    if (t && t != self) { r->gp[0] = (uint64_t)t; return 0; } }
  NSMethodSignature *sig = class_respondsToSelector(cls, @selector(methodSignatureForSelector:))
      ? ((id (*)(id, SEL, SEL))objc_msgSend)(self, @selector(methodSignatureForSelector:), sel) : nil;
  Method fi = class_getInstanceMethod(cls, @selector(forwardInvocation:)), base = class_getInstanceMethod([NSObject class], @selector(forwardInvocation:));
  if (!sig || !fi || fi == base) {
    ((void (*)(id, SEL, SEL))objc_msgSend)(self, @selector(doesNotRecognizeSelector:), sel);
    return 1; }
  NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
  Loc *loc = ((Loc *(*)(id, SEL))objc_msgSend)(inv, sel_registerName("_xefLocs"));
  void **args = ((void **(*)(id, SEL))objc_msgSend)(inv, sel_registerName("_xefArgs"));
  NSUInteger n = [sig numberOfArguments];
  for (NSUInteger k = 0; k < n; k++) fetch_arg(r, stack, &loc[1 + k], args[k]);
  [self forwardInvocation:inv];
  void *ret = ((void *(*)(id, SEL))objc_msgSend)(inv, sel_registerName("_xefRet"));
  give_result(r, &loc[0], [sig methodReturnType], ret);
  return 1; }

@interface NSInvocation (XEFForwarding)
- (Loc *)_xefLocs; - (void **)_xefArgs; - (void *)_xefRet;
@end

__asm__(
    ".text\n"
    ".globl _xef_invoke_asm\n"
    ".p2align 2\n"
    "_xef_invoke_asm:\n"                    /* x0 fn, x1 Regs *, x2 stack, x3 stack size (multiple of 16) */
    "  .cfi_startproc\n"
    "  stp x29, x30, [sp, #-32]!\n"
    "  .cfi_def_cfa_offset 32\n  .cfi_offset x29, -32\n  .cfi_offset x30, -24\n"
    "  stp x19, x20, [sp, #16]\n"
    "  .cfi_offset x19, -16\n  .cfi_offset x20, -8\n"
    "  mov x29, sp\n"
    "  .cfi_def_cfa x29, 32\n"
    "  mov x19, x1\n"
    "  mov x16, x0\n"
    "  sub sp, sp, x3\n"
    "  mov x9, #0\n"
    "1: cmp x9, x3\n"
    "  b.hs 2f\n"
    "  ldr x10, [x2, x9]\n"
    "  str x10, [sp, x9]\n"
    "  add x9, x9, #8\n"
    "  b 1b\n"
    "2: ldp d0, d1, [x19, #64]\n  ldp d2, d3, [x19, #80]\n  ldp d4, d5, [x19, #96]\n  ldp d6, d7, [x19, #112]\n"
    "  ldr x8, [x19, #128]\n"
    "  ldp x0, x1, [x19, #0]\n  ldp x2, x3, [x19, #16]\n  ldp x4, x5, [x19, #32]\n  ldp x6, x7, [x19, #48]\n"
    "  blr x16\n"
    "  stp x0, x1, [x19, #136]\n"
    "  stp d0, d1, [x19, #152]\n  stp d2, d3, [x19, #168]\n"
    "  mov sp, x29\n"
    "  ldp x19, x20, [sp, #16]\n"
    "  ldp x29, x30, [sp], #32\n"
    "  ret\n"
    "  .cfi_endproc\n"
    ".globl __CF_forwarding_prep_0\n"
    ".p2align 2\n"
    "__CF_forwarding_prep_0:\n"
    "  .cfi_startproc\n"
    "  stp x29, x30, [sp, #-16]!\n"
    "  .cfi_def_cfa_offset 16\n  .cfi_offset x29, -16\n  .cfi_offset x30, -8\n"
    "  mov x29, sp\n"
    "  .cfi_def_cfa x29, 16\n"
    "  sub sp, sp, #192\n"
    "  stp x0, x1, [sp, #0]\n  stp x2, x3, [sp, #16]\n  stp x4, x5, [sp, #32]\n  stp x6, x7, [sp, #48]\n"
    "  stp d0, d1, [sp, #64]\n  stp d2, d3, [sp, #80]\n  stp d4, d5, [sp, #96]\n  stp d6, d7, [sp, #112]\n"
    "  str x8, [sp, #128]\n"
    "  mov x0, sp\n"
    "  add x1, x29, #16\n"                    /* the caller's stack arguments */
    "  bl _xef_forwarding_dispatch\n"
    "  cbnz w0, 1f\n"
    "  ldp x0, x1, [sp, #0]\n  ldp x2, x3, [sp, #16]\n  ldp x4, x5, [sp, #32]\n  ldp x6, x7, [sp, #48]\n"
    "  ldp d0, d1, [sp, #64]\n  ldp d2, d3, [sp, #80]\n  ldp d4, d5, [sp, #96]\n  ldp d6, d7, [sp, #112]\n"
    "  ldr x8, [sp, #128]\n"
    "  mov sp, x29\n  ldp x29, x30, [sp], #16\n"
    "  b _objc_msgSend\n"
    "1: ldp x0, x1, [sp, #136]\n  ldp d0, d1, [sp, #152]\n  ldp d2, d3, [sp, #168]\n"
    "  mov sp, x29\n  ldp x29, x30, [sp], #16\n"
    "  ret\n"
    "  .cfi_endproc\n"
    ".globl __CF_forwarding_prep_1\n"
    ".p2align 2\n"
    "__CF_forwarding_prep_1:\n"
    "  b __CF_forwarding_prep_0\n"
    ".globl __CF_forwarding_prep_b\n"
    ".p2align 2\n"
    "__CF_forwarding_prep_b:\n"
    "  b __CF_forwarding_prep_0\n"
);
