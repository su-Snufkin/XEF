// XEF-OSX — <fenv.h> for Darwin arm64 guests.
//
// Darwin arm64: fenv_t = { u64 __fpsr; u64 __fpcr; } (16 bytes; glibc's x86 fenv_t is 32 and overran guest buffers),
// FE_INVALID 1, FE_DIVBYZERO 2, FE_OVERFLOW 4, FE_UNDERFLOW 8, FE_INEXACT 0x10, FE_DENORMAL 0x80 (= FPSR cumulative
// bits), rounding FE_TONEAREST 0, FE_UPWARD 0x400000, FE_DOWNWARD 0x800000, FE_TOWARDZERO 0xC00000 (= FPCR.RMode).
// The guest's FPCR lives in CpuState and drives the host MXCSR (as MSR FPCR does in translated code). Exception flags
// raised by translated FP code land in the host MXCSR, so the guest's flags are FPSR's plus MXCSR's.
#include "loader/darwin_hle.h"
#include "os/thread.h"
#include "runtime/cpu_state.h"
#include "common/common.h"

#include <string.h>

namespace xef {

extern thread_local ThreadCtx* tls_thread;

namespace {

struct DarwinFenv { uint64_t fpsr, fpcr; };
constexpr uint32_t kExcept = 0x1F | 0x80;
constexpr uint32_t kRound = 0xC00000;
const DarwinFenv kDflEnv = {0, 0};   // _FE_DFL_ENV: round to nearest, no flags, no traps, no flush-to-zero

CpuState* cur() { return tls_thread ? tls_thread->st : nullptr; }

uint32_t mxcsr() { return __builtin_ia32_stmxcsr(); }
// MXCSR status IE 1, DE 2, ZE 4, OE 8, UE 0x10, PE 0x20 -> FPSR IOC 1, IDC 0x80, DZC 2, OFC 4, UFC 8, IXC 0x10
uint32_t mx_to_fe(uint32_t m) {
    return (m & 1) | ((m & 2) ? 0x80 : 0) | ((m & 4) ? 2 : 0) | ((m & 8) ? 4 : 0) | ((m & 0x10) ? 8 : 0) | ((m & 0x20) ? 0x10 : 0);
}
uint32_t fe_to_mx(uint32_t f) {
    return (f & 1) | ((f & 0x80) ? 2 : 0) | ((f & 2) ? 4 : 0) | ((f & 4) ? 8 : 0) | ((f & 8) ? 0x10 : 0) | ((f & 0x10) ? 0x20 : 0);
}
uint32_t flags_now(CpuState* st) { return ((st ? st->fpsr : 0) | mx_to_fe(mxcsr())) & kExcept; }
void set_flags(CpuState* st, uint32_t f) {   // the guest's flags become exactly f
    f &= kExcept;
    if (st) st->fpsr = (st->fpsr & ~kExcept) | f;
    __builtin_ia32_ldmxcsr((mxcsr() & ~0x3Fu) | fe_to_mx(f));
}
void set_fpcr(CpuState* st, uint32_t fpcr) {   // as MSR FPCR: RMode -> RC, FZ -> FTZ|DAZ, exceptions masked
    if (st) st->fpcr = fpcr;
    uint32_t rm = (fpcr >> 22) & 3, rc = ((rm & 1) << 1) | (rm >> 1);
    __builtin_ia32_ldmxcsr((mxcsr() & 0x3F) | 0x1F80 | (rc << 13) | (((fpcr >> 24) & 1) ? 0x8040 : 0));
    // the x87 control word too: host library code the guest calls (printf's decimal conversion) reads it
    uint16_t cw;
    __asm__ volatile("fnstcw %0" : "=m"(cw));
    cw = (uint16_t)((cw & ~0x0C00) | (rc << 10));
    __asm__ volatile("fldcw %0" : : "m"(cw));
}

int fe_getenv(DarwinFenv* e) {
    if (!e) return -1;
    CpuState* st = cur();
    e->fpsr = flags_now(st) | (st ? st->fpsr & ~kExcept : 0);
    e->fpcr = st ? st->fpcr : 0;
    return 0;
}
int fe_setenv(const DarwinFenv* e) {
    if (!e) return -1;
    CpuState* st = cur();
    set_fpcr(st, (uint32_t)e->fpcr);
    if (st) st->fpsr = (uint32_t)e->fpsr;
    set_flags(st, (uint32_t)e->fpsr);
    return 0;
}
int fe_holdexcept(DarwinFenv* e) {
    fe_getenv(e);
    CpuState* st = cur();
    set_flags(st, 0);
    if (st) set_fpcr(st, st->fpcr & ~0x9F00u);   // non-stop: trap enables off
    return 0;
}
int fe_updateenv(const DarwinFenv* e) {
    uint32_t raised = flags_now(cur());
    fe_setenv(e);
    set_flags(cur(), flags_now(cur()) | raised);
    return 0;
}
int fe_clearexcept(int ex) { CpuState* st = cur(); set_flags(st, flags_now(st) & ~(uint32_t)ex); return 0; }
int fe_raiseexcept(int ex) { CpuState* st = cur(); set_flags(st, flags_now(st) | ((uint32_t)ex & kExcept)); return 0; }
int fe_testexcept(int ex) { return (int)(flags_now(cur()) & (uint32_t)ex & kExcept); }
int fe_getexceptflag(uint16_t* fl, int ex) { if (fl) *fl = (uint16_t)(flags_now(cur()) & (uint32_t)ex & kExcept); return 0; }
int fe_setexceptflag(const uint16_t* fl, int ex) {
    if (!fl) return -1;
    CpuState* st = cur();
    uint32_t m = (uint32_t)ex & kExcept;
    set_flags(st, (flags_now(st) & ~m) | (*fl & m));
    return 0;
}
int fe_getround() { CpuState* st = cur(); return st ? (int)(st->fpcr & kRound) : 0; }
int fe_setround(int r) {
    if ((uint32_t)r & ~kRound) return (int)((uint32_t)r & ~kRound);   // as Apple's: the invalid bits
    CpuState* st = cur();
    set_fpcr(st, ((st ? st->fpcr : 0) & ~kRound) | (uint32_t)r);
    return 0;
}

struct FenvShim { const char* name; void* fn; };
const FenvShim kFenv[] = {
    {"_fegetenv", (void*)&fe_getenv}, {"_fesetenv", (void*)&fe_setenv}, {"_feholdexcept", (void*)&fe_holdexcept},
    {"_feupdateenv", (void*)&fe_updateenv}, {"_feclearexcept", (void*)&fe_clearexcept},
    {"_feraiseexcept", (void*)&fe_raiseexcept}, {"_fetestexcept", (void*)&fe_testexcept},
    {"_fegetexceptflag", (void*)&fe_getexceptflag}, {"_fesetexceptflag", (void*)&fe_setexceptflag},
    {"_fegetround", (void*)&fe_getround}, {"_fesetround", (void*)&fe_setround},
};

}  // namespace

void* darwin_fenv_data_lookup(const char* name) { return !strcmp(name, "__FE_DFL_ENV") ? (void*)&kDflEnv : nullptr; }
void* darwin_fenv_lookup(const char* name) {
    for (const FenvShim& s : kFenv) if (!strcmp(s.name, name)) return s.fn;
    return nullptr;
}

}  // namespace xef
