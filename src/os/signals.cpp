// XEF — guest signals. Milestone-1 version: handlers are recorded, SIG_DFL/SIG_IGN
// are forwarded to the host; delivery to guest handlers comes with milestone 4.
#include "os/signals.h"

#include <errno.h>
#include <signal.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <ucontext.h>

#include "profile/stats.h"
#include "runtime/code_cache.h"

extern "C" char __executable_start;
#include "runtime/dispatch.h"

namespace xef {

struct GuestSigaction {
    u64 handler;
    u64 flags;
    u64 restorer;
    u64 mask;
};

static GuestSigaction g_actions[65];

static const char* kGuestRegNames[32] = {
    "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15",
    "x16", "x17", "x18", "x19", "x20", "x21", "x22", "x23", "x24", "x25", "x26", "x27", "x28", "fp", "lr", "sp"};

static int host_greg_index(x64::Reg r) {
    switch (r) {
    case x64::RAX: return REG_RAX; case x64::RCX: return REG_RCX; case x64::RDX: return REG_RDX;
    case x64::RBX: return REG_RBX; case x64::RSP: return REG_RSP; case x64::RBP: return REG_RBP;
    case x64::RSI: return REG_RSI; case x64::RDI: return REG_RDI; case x64::R8: return REG_R8;
    case x64::R9: return REG_R9; case x64::R10: return REG_R10; case x64::R11: return REG_R11;
    case x64::R12: return REG_R12; case x64::R13: return REG_R13; case x64::R14: return REG_R14;
    default: return REG_R15;
    }
}

static void crash_handler(int sig, siginfo_t* si, void* ctx) {
    ucontext_t* uc = (ucontext_t*)ctx;
    u8* rip = (u8*)uc->uc_mcontext.gregs[REG_RIP];
    char buf[512];
    int n = snprintf(buf, sizeof buf, "xef: fatal signal %d at host %p [xef+%#lx] (fault addr %p)\n", sig, rip,
                     (unsigned long)(rip - (u8*)&__executable_start), si->si_addr);
    write(2, buf, n);
    if (g_cache.contains(rip)) {
        BlockMeta* b = g_cache.find_by_host(rip);
        if (b) {
            n = snprintf(buf, sizeof buf, "xef:   in translated block guest %#lx..%#lx (host %p +%#lx)\n",
                         (unsigned long)b->start, (unsigned long)b->end, b->code, (unsigned long)(rip - b->code));
            write(2, buf, n);
        }
        CpuState* st = (CpuState*)(uc->uc_mcontext.gregs[REG_R15] - kStateBias);
        for (int g = 0; g < 32; g++) {
            u64 v = regmap::mapped(g) ? (u64)uc->uc_mcontext.gregs[host_greg_index(regmap::host(g))] : st->x[g];
            n = snprintf(buf, sizeof buf, "  %-3s=%016lx%s", kGuestRegNames[g], (unsigned long)v, (g % 4 == 3) ? "\n" : "");
            write(2, buf, n);
        }
    }
    _exit(128 + sig);
}

void signals_init() {
    struct sigaction sa {};
    sa.sa_sigaction = crash_handler;
    sa.sa_flags = SA_SIGINFO;
    sigaction(SIGSEGV, &sa, nullptr);
    sigaction(SIGBUS, &sa, nullptr);
    sigaction(SIGILL, &sa, nullptr);
    sigaction(SIGFPE, &sa, nullptr);
}

void signals_flush_output() {
    if (g_opt.stats) stats_print();
    if (g_opt.profile) profile_report();
}

i64 sig_rt_sigaction(CpuState*, int sig, u64 act, u64 oact, u64 sigsetsize) {
    if (sig < 1 || sig > 64 || sigsetsize != 8) return -EINVAL;
    if (oact) *(GuestSigaction*)oact = g_actions[sig];
    if (act) {
        GuestSigaction a = *(GuestSigaction*)act;
        if (sig == SIGKILL || sig == SIGSTOP) return -EINVAL;
        g_actions[sig] = a;
        if (a.handler == (u64)SIG_DFL || a.handler == (u64)SIG_IGN) {
            struct sigaction h {};
            h.sa_handler = (void (*)(int))a.handler;
            sigaction(sig, &h, nullptr);
        }
    }
    return 0;
}

i64 sig_rt_sigprocmask(CpuState*, int how, u64 set, u64 oset, u64 sigsetsize) {
    // Signals XEF itself depends on (faults, profiling) are never blocked on the host.
    u64 m;
    u64 hset = 0;
    if (set) {
        m = *(u64*)set;
        m &= ~((1ull << (SIGSEGV - 1)) | (1ull << (SIGBUS - 1)) | (1ull << (SIGILL - 1)) | (1ull << (SIGFPE - 1)) |
               (1ull << (SIGPROF - 1)));
        hset = (u64)&m;
    }
    return syscall(SYS_rt_sigprocmask, how, hset, oset, sigsetsize) < 0 ? -errno : 0;
}

void sig_rt_sigreturn(CpuState*) { fatal("rt_sigreturn: signal delivery not implemented yet"); }

i64 sig_rt_sigsuspend(CpuState*, u64 set, u64 sigsetsize) {
    long r = syscall(SYS_rt_sigsuspend, set, sigsetsize);
    return r < 0 ? -errno : r;
}

i64 sig_sigaltstack(CpuState*, u64 ss, u64 oss) {
    (void)ss;
    if (oss) memset((void*)oss, 0, 24), ((u32*)oss)[2] = 2 /*SS_DISABLE*/;
    return 0;
}

void signals_deliver_pending(CpuState* st) { st->pending_signal = 0; }

}  // namespace xef
