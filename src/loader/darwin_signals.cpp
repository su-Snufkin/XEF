// XEF-OSX — Darwin signal API (signal/sigaction/sigprocmask/kill/...) on top of XEF's guest signal machinery.
#include "loader/darwin_hle.h"
#include "os/signals.h"
#include "os/thread.h"
#include "common/common.h"

#include <errno.h>
#include <signal.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

namespace xef {

struct DarwinSigaction { u64 handler; uint32_t mask; int32_t flags; };
struct DarwinSigaltstack { u64 ss_sp; u64 ss_size; int32_t ss_flags; int32_t pad; };

static u64 translate_flags(int32_t f) {
    u64 r = 0;
    if (f & 0x01) r |= 0x08000000;     // SA_ONSTACK
    if (f & 0x02) r |= 0x10000000;     // SA_RESTART
    if (f & 0x04) r |= 0x80000000;     // SA_RESETHAND
    if (f & 0x10) r |= 0x40000000;     // SA_NODEFER
    if (f & 0x40) r |= 4;              // SA_SIGINFO
    if (f & 0x08) r |= 1;              // SA_NOCLDSTOP
    if (f & 0x20) r |= 2;              // SA_NOCLDWAIT
    return r;
}
static int32_t untranslate_flags(u64 r) {
    int32_t f = 0;
    if (r & 0x08000000) f |= 0x01;
    if (r & 0x10000000) f |= 0x02;
    if (r & 0x80000000) f |= 0x04;
    if (r & 0x40000000) f |= 0x10;
    if (r & 4) f |= 0x40;
    if (r & 1) f |= 0x08;
    if (r & 2) f |= 0x20;
    return f;
}

static int err(int e) { errno = e; return -1; }

static int ds_sigaction(int dsig, const DarwinSigaction* act, DarwinSigaction* oact) {
    int l = darwin_to_linux_sig(dsig);
    if (l <= 0 && (dsig == 7 || dsig == 29)) {   // SIGEMT / SIGINFO do not exist on Linux: accept and ignore
        if (oact) { oact->handler = 0; oact->mask = 0; oact->flags = 0; }
        return 0;
    }
    if (l <= 0 || dsig == 9 || dsig == 17) return err(EINVAL);
    u64 oh = 0, of = 0, om = 0;
    i64 r;
    if (act) r = sig_darwin_sigaction(l, act->handler, translate_flags(act->flags), darwin_mask_to_linux(act->mask), &oh, &of, &om);
    else {
        // query only: re-apply the current action unchanged
        u64 h0, f0, m0;
        r = sig_darwin_sigaction(l, 0, 0, 0, &h0, &f0, &m0);
        sig_darwin_sigaction(l, h0, f0, m0, nullptr, nullptr, nullptr);
        oh = h0; of = f0; om = m0;
    }
    if (r < 0) return err((int)-r);
    if (oact) { oact->handler = oh; oact->flags = untranslate_flags(of); oact->mask = (uint32_t)linux_mask_to_darwin(om); }
    return 0;
}

static u64 ds_signal(int dsig, u64 handler) {
    DarwinSigaction a = {handler, 0, 0x02 /*SA_RESTART*/}, o;
    if (ds_sigaction(dsig, &a, &o) < 0) return (u64)-1;    // SIG_ERR
    return o.handler;
}

static CpuState* cur_state() { return tls_thread ? tls_thread->st : nullptr; }

static int ds_sigprocmask(int how, const uint32_t* set, uint32_t* oset) {
    u64 lset = set ? darwin_mask_to_linux(*set) : 0, lold = 0;
    int lhow = how == 1 ? SIG_BLOCK : how == 2 ? SIG_UNBLOCK : SIG_SETMASK;
    i64 r = sig_rt_sigprocmask(cur_state(), lhow, set ? (u64)&lset : 0, oset ? (u64)&lold : 0, 8);
    if (r < 0) return err((int)-r);
    if (oset) *oset = (uint32_t)linux_mask_to_darwin(lold);
    return 0;
}
static int ds_pthread_sigmask(int how, const uint32_t* set, uint32_t* oset) { int r = ds_sigprocmask(how, set, oset); return r ? errno : 0; }

static int ds_sigemptyset(uint32_t* s) { *s = 0; return 0; }
static int ds_sigfillset(uint32_t* s) { *s = 0xFFFFFFFFu; return 0; }
static int ds_sigaddset(uint32_t* s, int sig) { if (sig < 1 || sig > 31) return err(EINVAL); *s |= 1u << (sig - 1); return 0; }
static int ds_sigdelset(uint32_t* s, int sig) { if (sig < 1 || sig > 31) return err(EINVAL); *s &= ~(1u << (sig - 1)); return 0; }
static int ds_sigismember(const uint32_t* s, int sig) { if (sig < 1 || sig > 31) return err(EINVAL); return (*s >> (sig - 1)) & 1; }

static int ds_sigsuspend(const uint32_t* set) {
    u64 l = darwin_mask_to_linux(*set);
    i64 r = sig_rt_sigsuspend(cur_state(), (u64)&l, 8);
    return err((int)-r);
}
static int ds_sigpending(uint32_t* set) {
    sigset_t p;
    sigpending(&p);
    u64 m = 0;
    for (int s = 1; s < 32; s++) if (sigismember(&p, s)) m |= 1ull << (s - 1);
    *set = (uint32_t)linux_mask_to_darwin(m);
    return 0;
}
static int ds_sigaltstack(const DarwinSigaltstack* ss, DarwinSigaltstack* oss) {
    struct { u64 sp; int32_t flags; int32_t pad; u64 size; } lss, loss;
    if (ss) { lss.sp = ss->ss_sp; lss.size = ss->ss_size; lss.flags = (ss->ss_flags & 4) ? 2 /*SS_DISABLE*/ : 0; lss.pad = 0; }
    i64 r = sig_sigaltstack(cur_state(), ss ? (u64)&lss : 0, oss ? (u64)&loss : 0);
    if (r < 0) return err((int)-r);
    if (oss) { oss->ss_sp = loss.sp; oss->ss_size = loss.size; oss->ss_flags = (loss.flags & 2) ? 4 : 0; }
    return 0;
}

static int ds_kill(int pid, int dsig) {
    int l = dsig == 0 ? 0 : darwin_to_linux_sig(dsig);
    if (dsig != 0 && l <= 0) return err(EINVAL);
    if (pid == (int)getpid() || pid == 0) return (int)syscall(SYS_tgkill, getpid(), syscall(SYS_gettid), l) == 0 ? 0 : -1;
    return kill(pid, l);
}
static int ds_killpg(int pgrp, int dsig) { int l = darwin_to_linux_sig(dsig); return kill(-pgrp, l); }
static int ds_raise(int dsig) {
    if (getenv("XEF_DBG_RAISE")) fprintf(stderr, "xef: guest raise(%d)\n", dsig);
    int l = darwin_to_linux_sig(dsig);
    if (l <= 0) return err(EINVAL);
    return syscall(SYS_tgkill, getpid(), syscall(SYS_gettid), l) == 0 ? 0 : -1;
}
static int ds_pthread_kill(u64 th, int dsig) {
    if (dsig == 0) return 0;
    int l = darwin_to_linux_sig(dsig);
    if (l <= 0) return EINVAL;
    return pthread_kill((pthread_t)th, l);
}

struct SigShim { const char* name; void* fn; };
static const SigShim kSig[] = {
    {"_sigaction", (void*)&ds_sigaction}, {"_signal", (void*)&ds_signal}, {"_bsd_signal", (void*)&ds_signal},
    {"_sigprocmask", (void*)&ds_sigprocmask}, {"_pthread_sigmask", (void*)&ds_pthread_sigmask},
    {"_sigemptyset", (void*)&ds_sigemptyset}, {"_sigfillset", (void*)&ds_sigfillset}, {"_sigaddset", (void*)&ds_sigaddset},
    {"_sigdelset", (void*)&ds_sigdelset}, {"_sigismember", (void*)&ds_sigismember},
    {"_sigsuspend", (void*)&ds_sigsuspend}, {"_sigpending", (void*)&ds_sigpending}, {"_sigaltstack", (void*)&ds_sigaltstack},
    {"_kill", (void*)&ds_kill}, {"_killpg", (void*)&ds_killpg}, {"_raise", (void*)&ds_raise}, {"_pthread_kill", (void*)&ds_pthread_kill},
};

void* darwin_signal_lookup(const char* name) {
    for (const SigShim& s : kSig) if (!strcmp(s.name, name)) return s.fn;
    return nullptr;
}

// guest stub that ends a signal handler: ucontext lives at a fixed offset from the handler-entry sp
void darwin_signals_init(uint8_t* stub) {
    uint32_t* i = (uint32_t*)stub;
    i[0] = 0x910003E0u | ((uint32_t)sig_darwin_ucontext_offset() << 10);   // add x0, sp, #off
    i[1] = 0xD2800021u;                                                    // mov x1, #1 (UC_FLAVOR)
    i[2] = 0xD2801710u;                                                    // mov x16, #184 (sigreturn)
    i[3] = 0xD4001001u;                                                    // svc #0x80
    sig_darwin_set_tramp((u64)(uintptr_t)stub);
}

} // namespace xef
