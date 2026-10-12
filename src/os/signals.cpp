// XEF — guest signals. Milestone-1 version: handlers are recorded, SIG_DFL/SIG_IGN
// are forwarded to the host; delivery to guest handlers comes with milestone 4.
#include "os/signals.h"

#include <errno.h>
#include <signal.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <sys/mman.h>
#include <ucontext.h>

#include "profile/stats.h"
#include "runtime/code_cache.h"

extern "C" char __executable_start;
#include <cstddef>

#include "os/thread.h"
#include "runtime/dispatch.h"

namespace xef {

struct GuestSigaction {
    u64 handler;
    u64 flags;
    u64 restorer;
    u64 mask;
};

static GuestSigaction g_actions[65];
static u64 g_sigreturn_tramp;   // guest code: mov x8, #139 (rt_sigreturn); svc #0  (like the vDSO sigtramp)
bool g_actions_handler(int sig);
static void async_handler(int sig, siginfo_t* si, void* ctx);
static void trap_handler(int sig, siginfo_t* si, void* ctx);

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
    void* p = mmap(nullptr, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p != MAP_FAILED) {
        u32* c = (u32*)p;
        c[0] = 0xd2801168;  // mov x8, #139
        c[1] = 0xd4000001;  // svc #0
        mprotect(p, 4096, PROT_READ);
        g_sigreturn_tramp = (u64)p;
    }
    struct sigaction sa {};
    sa.sa_sigaction = crash_handler;
    sa.sa_flags = SA_SIGINFO;
    sigaction(SIGSEGV, &sa, nullptr);
    sigaction(SIGBUS, &sa, nullptr);
    sigaction(SIGILL, &sa, nullptr);
    sigaction(SIGFPE, &sa, nullptr);
    struct sigaction tr {};
    tr.sa_sigaction = trap_handler;
    tr.sa_flags = SA_SIGINFO;
    sigaction(SIGTRAP, &tr, nullptr);
}

void signals_flush_output() {
    if (g_opt.stats) stats_print();
    if (g_opt.profile) profile_report();
}

// ------------------------------------------------------------------ guest signal delivery
//
// Asynchronous signals for which the guest installed a handler are caught by a host handler
// that marks them pending. If the thread is inside translated code, the trap flag (TF) is set
// and the thread single-steps to the next block entry, where the guest state is exactly the
// canonical register mapping; it is then redirected to exit to the runtime, which builds an
// AArch64 rt_sigframe on the guest stack and resumes at the guest handler.

thread_local ThreadCtx* tls_thread;

constexpr u64 kInternalSigs = (1ull << (SIGSEGV - 1)) | (1ull << (SIGBUS - 1)) | (1ull << (SIGILL - 1)) |
                              (1ull << (SIGFPE - 1)) | (1ull << (SIGPROF - 1)) | (1ull << (SIGTRAP - 1));
constexpr u64 G_SA_SIGINFO = 4, G_SA_ONSTACK = 0x08000000, G_SA_RESTART = 0x10000000, G_SA_NODEFER = 0x40000000,
              G_SA_RESETHAND = 0x80000000, G_SA_RESTORER = 0x04000000;

static inline u64 sigbit(int sig) { return 1ull << (sig - 1); }

u32 eflags_to_nzcv(u64 e) {
    u32 n = (e >> 7) & 1, z = (e >> 6) & 1, c = !(e & 1), v = (e >> 11) & 1;
    return (n << 31) | (z << 30) | (c << 29) | (v << 28);
}
u64 nzcv_to_eflags(u32 nzcv) {
    u64 e = 0x202;
    if (nzcv & (1u << 31)) e |= 0x80;
    if (nzcv & (1u << 30)) e |= 0x40;
    if (!(nzcv & (1u << 29))) e |= 0x01;
    if (nzcv & (1u << 28)) e |= 0x800;
    return e;
}

static void async_handler(int sig, siginfo_t* si, void* ctx) {
    ThreadCtx* t = tls_thread;
    if (!t) return;
    t->pending_info[sig] = *si;
    __atomic_or_fetch(&t->pending, sigbit(sig), __ATOMIC_SEQ_CST);
    t->st->pending_signal = 1;
    ucontext_t* uc = (ucontext_t*)ctx;
    u8* rip = (u8*)uc->uc_mcontext.gregs[REG_RIP];
    if (g_cache.contains(rip)) {
        t->stepping = true;
        uc->uc_mcontext.gregs[REG_EFL] |= 0x100;  // TF: single-step to the next block entry
    }
}

static void trap_handler(int sig, siginfo_t* si, void* ctx) {
    ThreadCtx* t = tls_thread;
    ucontext_t* uc = (ucontext_t*)ctx;
    if (!t || !t->stepping || si->si_code <= 0) {
        // a SIGTRAP sent by someone (kill/tgkill): treat as an ordinary async signal
        if (t && g_actions_handler(SIGTRAP)) async_handler(sig, si, ctx);
        return;
    }
    u8* rip = (u8*)uc->uc_mcontext.gregs[REG_RIP];
    if (!g_cache.contains(rip)) {
        // back in the runtime: it will see pending_signal
        t->stepping = false;
        uc->uc_mcontext.gregs[REG_EFL] &= ~0x100ull;
        return;
    }
    BlockMeta* b = g_cache.find_by_host(rip);
    if (!b || b->code != rip) return;  // keep stepping
    CpuState* st = t->st;
    u8* target = g_cache.stubs.exit_to_runtime;
    if (b->region && b != b->region->entry) {
        if (!b->region->sig_exit) return;
        target = b->region->sig_exit;
    }
    st->pc = b->start;
    st->exit_reason = EXIT_SIGNAL;
    uc->uc_mcontext.gregs[REG_RIP] = (greg_t)target;
    uc->uc_mcontext.gregs[REG_EFL] &= ~0x100ull;
    t->stepping = false;
}

bool g_actions_handler(int sig) { return g_actions[sig].handler > 1; }

i64 sig_rt_sigaction(CpuState*, int sig, u64 act, u64 oact, u64 sigsetsize) {
    if (sig < 1 || sig > 64 || sigsetsize != 8) return -EINVAL;
    if (oact) *(GuestSigaction*)oact = g_actions[sig];
    if (act) {
        GuestSigaction a = *(GuestSigaction*)act;
        if (sig == SIGKILL || sig == SIGSTOP) return -EINVAL;
        g_actions[sig] = a;
        if (sigbit(sig) & kInternalSigs) return 0;  // XEF keeps its own handler (synchronous delivery: TODO)
        struct sigaction h {};
        if (a.handler == (u64)SIG_DFL || a.handler == (u64)SIG_IGN) {
            h.sa_handler = (void (*)(int))a.handler;
        } else {
            h.sa_sigaction = async_handler;
            h.sa_flags = SA_SIGINFO | ((a.flags & G_SA_RESTART) ? SA_RESTART : 0);
            sigfillset(&h.sa_mask);
        }
        sigaction(sig, &h, nullptr);
    }
    return 0;
}

static u64 host_blocked() {
    u64 m = 0;
    syscall(SYS_rt_sigprocmask, SIG_BLOCK, nullptr, &m, 8);
    return m;
}
static void host_setmask(u64 m) {
    m &= ~kInternalSigs;
    syscall(SYS_rt_sigprocmask, SIG_SETMASK, &m, nullptr, 8);
}

i64 sig_rt_sigprocmask(CpuState*, int how, u64 set, u64 oset, u64 sigsetsize) {
    // Signals XEF itself depends on (faults, profiling) are never blocked on the host.
    u64 m;
    u64 hset = 0;
    if (set) {
        m = *(u64*)set & ~kInternalSigs;
        hset = (u64)&m;
    }
    return syscall(SYS_rt_sigprocmask, how, hset, oset, sigsetsize) < 0 ? -errno : 0;
}

// --- AArch64 signal frame layout (arch/arm64/include/uapi/asm/{sigcontext,ucontext}.h) ---
struct GSigcontext {
    u64 fault_address;
    u64 regs[31];
    u64 sp, pc, pstate;
    u8 pad[8];                 // __reserved is 16-byte aligned
    u8 reserved[4096];
};
struct GUcontext {
    u64 uc_flags;
    u64 uc_link;
    u64 ss_sp;
    u32 ss_flags, ss_pad;
    u64 ss_size;
    u64 uc_sigmask;
    u8 unused[120];
    u8 pad[8];
    GSigcontext mc;
};
struct GRtSigframe {
    u8 info[128];
    GUcontext uc;
};
static_assert(offsetof(GUcontext, mc) == 176, "ucontext layout");
static_assert(offsetof(GSigcontext, reserved) == 288, "sigcontext layout");
constexpr u32 FPSIMD_MAGIC = 0x46508001;

static void deliver_one(CpuState* st, int sig, const siginfo_t& si, u64 saved_mask) {
    ThreadCtx* t = st->thread;
    GuestSigaction& a = g_actions[sig];
    u64 sp = st->x[kGuestSP];
    if ((a.flags & G_SA_ONSTACK) && t->ss_size && !(sp > t->ss_sp && sp <= t->ss_sp + t->ss_size))
        sp = t->ss_sp + t->ss_size;
    sp -= 16;                               // frame record {fp, lr}
    u64 rec = sp & ~15ull;
    sp = (rec - sizeof(GRtSigframe)) & ~15ull;
    GRtSigframe* f = (GRtSigframe*)sp;
    memset(f, 0, sizeof *f);
    memcpy(f->info, &si, 128);              // siginfo layout is identical on arm64 and x86-64
    f->uc.ss_sp = t->ss_sp;
    f->uc.ss_size = t->ss_size;
    f->uc.ss_flags = t->ss_size ? 0 : 2;
    f->uc.uc_sigmask = saved_mask;
    GSigcontext& mc = f->uc.mc;
    for (int i = 0; i < 31; i++) mc.regs[i] = st->x[i];
    mc.sp = st->x[kGuestSP];
    mc.pc = st->pc;
    mc.pstate = eflags_to_nzcv(st->eflags);
    if (sig == SIGSEGV || sig == SIGBUS) mc.fault_address = (u64)si.si_addr;
    u32* hd = (u32*)mc.reserved;
    hd[0] = FPSIMD_MAGIC;
    hd[1] = 528;
    hd[2] = st->fpsr;
    hd[3] = st->fpcr;
    memcpy(mc.reserved + 16, st->v, 512);   // terminator (zero head) follows
    ((u64*)rec)[0] = st->x[29];
    ((u64*)rec)[1] = st->x[30];
    st->x[0] = (u64)sig;
    st->x[1] = (u64)&f->info;
    st->x[2] = (u64)&f->uc;
    st->x[29] = rec;
    st->x[30] = (a.flags & G_SA_RESTORER) && a.restorer ? a.restorer : g_sigreturn_tramp;
    st->x[kGuestSP] = sp;
    st->pc = a.handler;
    u64 nm = saved_mask | a.mask;
    if (!(a.flags & G_SA_NODEFER)) nm |= sigbit(sig);
    host_setmask(nm);
    if (a.flags & G_SA_RESETHAND) {
        a.handler = 0;
        struct sigaction h {};
        h.sa_handler = SIG_DFL;
        sigaction(sig, &h, nullptr);
    }
}

// override_mask: mask to restore on sigreturn (sigsuspend); select: signals deliverable now
static void deliver_pending_masked(CpuState* st, u64 saved_mask, u64 blocked) {
    ThreadCtx* t = st->thread;
    st->pending_signal = 0;
    u64 p = __atomic_load_n(&t->pending, __ATOMIC_SEQ_CST) & ~blocked;
    if (!p) return;
    int sig = __builtin_ctzll(p) + 1;
    __atomic_and_fetch(&t->pending, ~sigbit(sig), __ATOMIC_SEQ_CST);
    siginfo_t si = t->pending_info[sig];
    if (g_actions[sig].handler <= 1) return;  // action changed meanwhile
    deliver_one(st, sig, si, saved_mask);
    if (__atomic_load_n(&t->pending, __ATOMIC_SEQ_CST)) st->pending_signal = 1;
}

void signals_deliver_pending(CpuState* st) {
    // EXIT_SIGNAL clobbers nothing; strip TF that may have been captured by an exit stub
    st->eflags &= ~0x100ull;
    u64 m = host_blocked();
    deliver_pending_masked(st, m, m);
}

void sig_rt_sigreturn(CpuState* st) {
    GRtSigframe* f = (GRtSigframe*)st->x[kGuestSP];
    GSigcontext& mc = f->uc.mc;
    for (int i = 0; i < 31; i++) st->x[i] = mc.regs[i];
    st->x[kGuestSP] = mc.sp;
    st->pc = mc.pc;
    st->eflags = nzcv_to_eflags((u32)mc.pstate);
    u32* hd = (u32*)mc.reserved;
    if (hd[0] == FPSIMD_MAGIC) {
        st->fpsr = hd[2];
        st->fpcr = hd[3];
        memcpy(st->v, mc.reserved + 16, 512);
    }
    host_setmask(f->uc.uc_sigmask);
    if (__atomic_load_n(&st->thread->pending, __ATOMIC_SEQ_CST)) st->pending_signal = 1;
}

i64 sig_rt_sigsuspend(CpuState* st, u64 set, u64 sigsetsize) {
    if (sigsetsize != 8) return -EINVAL;
    u64 old = host_blocked();
    u64 tmp = *(u64*)set & ~kInternalSigs;
    long r = syscall(SYS_rt_sigsuspend, &tmp, 8);
    r = r < 0 ? -errno : r;
    // deliver now with the temporary mask; the handler's sigreturn restores the old mask
    st->x[0] = (u64)r;
    deliver_pending_masked(st, old, tmp);
    return r;
}

i64 sig_sigaltstack(CpuState* st, u64 ss, u64 oss) {
    ThreadCtx* t = st->thread;
    if (oss) {
        u64* o = (u64*)oss;
        o[0] = t->ss_sp;
        ((u32*)oss)[2] = t->ss_size ? 0 : 2;
        o[2] = t->ss_size;
    }
    if (ss) {
        u64* n = (u64*)ss;
        u32 flags = ((u32*)ss)[2];
        if (flags & 2) { t->ss_sp = 0; t->ss_size = 0; }
        else { t->ss_sp = n[0]; t->ss_size = n[2]; }
    }
    return 0;
}

void signals_thread_init(ThreadCtx* t) { tls_thread = t; }

}  // namespace xef
