// XEF — guest signals. Milestone-1 version: handlers are recorded, SIG_DFL/SIG_IGN
// are forwarded to the host; delivery to guest handlers comes with milestone 4.
#include "os/signals.h"
#include "loader/macho_image.h"
#include "loader/darwin_hle.h"
#include "os/darwin/darwin_syscalls.h"
#include "runtime/verify.h"

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
#include <mutex>

#include "os/thread.h"
#include "runtime/dispatch.h"

namespace xef {

struct GuestSigaction {
    u64 handler;
    u64 flags;
    u64 restorer;
    u64 mask;
    u64 darwin;     // 1: delivered with a Darwin (xnu arm64) signal frame
};

static GuestSigaction g_actions[65];
// guards whole-entry reads/writes of g_actions (32 bytes: a reader must not see a new handler
// with the old flags/restorer); signal handlers only read the handler word (g_actions_handler)
static std::mutex g_actions_lock;
void signals_fork_lock(bool lock) { if (lock) g_actions_lock.lock(); else g_actions_lock.unlock(); }
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

extern thread_local ThreadCtx* tls_thread;
static bool deliver_sync_fault(int sig, siginfo_t* si, ucontext_t* uc);

// guest reg -> host reg for the code at `b` (canonical, or the region's own mapping)
static x64::Reg block_host_reg(const BlockMeta* b, int g) {
    return b && b->region ? (x64::Reg)b->region->map[g] : regmap::host(g);
}

// Deep guest recursion fills the JIT stack (one native return-stack entry per BL). On a fault in
// its guard page, move the newest bytes back to the top and continue: entries that are dropped
// only turn later RETs into return-stack mismatches, which fall back to the IBTC.
static bool relocate_jit_stack(int sig, siginfo_t* si, ucontext_t* uc) {
    ThreadCtx* t = tls_thread;
    greg_t* gr = uc->uc_mcontext.gregs;
    if (!t || sig != SIGSEGV || !g_cache.contains((u8*)gr[REG_RIP])) return false;
    u8* a = (u8*)si->si_addr;
    if (a < t->jit_stack || a >= t->jit_stack + 4096) return false;
    u8* rsp = (u8*)gr[REG_RSP];
    u8* top = (u8*)t->st->jit_stack_top;
    const size_t keep = 256;   // covers push/pop sequences in progress
    u8* nsp = top - keep - 16 + ((uintptr_t)rsp & 15);
    memmove(nsp, rsp, keep);
    gr[REG_RSP] = (greg_t)nsp;
    return true;
}

static void crash_handler(int sig, siginfo_t* si, void* ctx) {
    ucontext_t* uc = (ucontext_t*)ctx;
    if (relocate_jit_stack(sig, si, uc)) return;
    if (deliver_sync_fault(sig, si, uc)) return;
    u8* rip = (u8*)uc->uc_mcontext.gregs[REG_RIP];
    char buf[512];
    int n = snprintf(buf, sizeof buf, "xef: fatal signal %d at host %p [xef+%#lx] (fault addr %p)\n", sig, rip,
                     (unsigned long)(rip - (u8*)&__executable_start), si->si_addr);
    write(2, buf, n);
    if (g_is_darwin) {
        const char* hn; u64 hlr;
        if (darwin_hle_current(&hn, &hlr)) {
            std::string d = dyld_describe(hlr);
            n = snprintf(buf, sizeof buf, "xef:   inside HLE function %s called from %s\n", hn, d.empty() ? "?" : d.c_str());
            write(2, buf, n);
            if (tls_thread) {   // guest frame-pointer chain
                u64 fp = tls_thread->st->x[29];
                for (int depth = 0; depth < 12 && fp && !(fp & 7); depth++) {
                    u64 lr = ((u64*)fp)[1];
                    std::string fd = dyld_describe(lr);
                    n = snprintf(buf, sizeof buf, "xef:     #%d %s\n", depth, fd.empty() ? "?" : fd.c_str());
                    write(2, buf, n);
                    u64 nfp = ((u64*)fp)[0];
                    if (nfp <= fp) break;
                    fp = nfp;
                }
            }
        }
    }
    if (g_cache.contains(rip)) {
        BlockMeta* b = g_cache.find_by_host(rip);
        const PcMapEntry* pe = b ? g_cache.find_pc(b, rip) : nullptr;
        if (b) {
            n = snprintf(buf, sizeof buf, "xef:   in translated block guest %#lx..%#lx (host %p +%#lx)\n",
                         (unsigned long)b->start, (unsigned long)b->end, b->code, (unsigned long)(rip - b->code));
            write(2, buf, n);
            if (pe) {
                n = snprintf(buf, sizeof buf, "xef:   guest pc %#lx%s\n", (unsigned long)(b->start + pe->guest_off),
                             b->region ? " (tier-2 region)" : "");
                write(2, buf, n);
                if (g_is_darwin) {
                    std::string d = dyld_describe(b->start + pe->guest_off);
                    if (!d.empty()) { n = snprintf(buf, sizeof buf, "xef:   in %s\n", d.c_str()); write(2, buf, n); }
                }
            }
        }
        CpuState* st = (CpuState*)(uc->uc_mcontext.gregs[REG_R15] - kStateBias);
        for (int g = 0; g < 32; g++) {
            x64::Reg h = block_host_reg(b, g);
            bool in_reg = h != x64::NOREG && !(pe && (pe->borrowed & (1 << h)));
            u64 v = in_reg ? (u64)uc->uc_mcontext.gregs[host_greg_index(h)] : st->x[g];
            n = snprintf(buf, sizeof buf, "  %-3s=%016lx%s", kGuestRegNames[g], (unsigned long)v, (g % 4 == 3) ? "\n" : "");
            write(2, buf, n);
        }
        // block temporaries (unmapped guest values may live there) and the faulting host instruction
        const greg_t* gr = uc->uc_mcontext.gregs;
        n = snprintf(buf, sizeof buf, "  host rax=%016lx rcx=%016lx r11=%016lx  code:", (unsigned long)gr[REG_RAX],
                     (unsigned long)gr[REG_RCX], (unsigned long)gr[REG_R11]);
        for (int k = 0; k < 12 && n < (int)sizeof buf - 4; k++) n += snprintf(buf + n, sizeof buf - n, " %02x", rip[k]);
        buf[n++] = '\n';
        write(2, buf, n);
        if (g_is_darwin) {
            u64 fp = (block_host_reg(b, 29) != x64::NOREG) ? (u64)uc->uc_mcontext.gregs[host_greg_index(block_host_reg(b, 29))] : st->x[29];
            for (int depth = 0; depth < 16 && fp && !(fp & 7); depth++) {
                u64 lr = ((u64*)fp)[1];
                std::string fd = dyld_describe(lr);
                n = snprintf(buf, sizeof buf, "xef:     #%d %s (fp=%#lx, lr=%#lx)\n", depth, fd.empty() ? "?" : fd.c_str(), (unsigned long)fp, (unsigned long)lr);
                write(2, buf, n);
                u64 nfp = ((u64*)fp)[0];
                if (nfp <= fp || nfp >= fp + 0x10000000) break;
                fp = nfp;
            }
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
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigaction(SIGSEGV, &sa, nullptr);
    sigaction(SIGBUS, &sa, nullptr);
    sigaction(SIGILL, &sa, nullptr);
    sigaction(SIGFPE, &sa, nullptr);
    struct sigaction tr {};
    tr.sa_sigaction = trap_handler;
    tr.sa_flags = SA_SIGINFO | SA_ONSTACK;
    // a guest signal arriving inside this handler would set TF in the handler's context, which
    // its sigreturn discards: hold signals until the JIT context is current again
    sigfillset(&tr.sa_mask);
    sigaction(SIGTRAP, &tr, nullptr);
}

// --stats / --profile: report also when the program is interrupted (until the guest installs
// its own handler for these signals)
static void report_and_die(int sig) {
    signals_flush_output();
    signal(sig, SIG_DFL);
    raise(sig);
}

void signals_report_on_interrupt() {
    signal(SIGINT, report_and_die);
    signal(SIGTERM, report_and_die);
}

void signals_flush_output() {
    if (verify_enabled()) verify_report();
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
                              (1ull << (SIGFPE - 1)) | (1ull << (kSampleSig - 1)) | (1ull << (SIGTRAP - 1));
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
    // in translated code, or in a helper it called (which returns into translated code)
    if (g_cache.contains(rip) || t->st->in_jit) {
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
        if (t->st->in_jit) return;   // a helper called from translated code: keep stepping until it returns
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

// Synchronous SIGSEGV/SIGBUS raised by a guest memory access in translated code, with a guest
// handler installed: rebuild the precise guest state at the faulting instruction from the
// block's pc map (GPRs from the block's register mapping, NZCV from EFLAGS or its spill slot;
// SetReg is never deferred past a later memory access, and vector registers live in CpuState),
// then leave the JIT through exit_to_runtime; the runtime builds the signal frame.
static bool deliver_sync_fault(int sig, siginfo_t* si, ucontext_t* uc) {
    ThreadCtx* t = tls_thread;
    if (!t || (sig != SIGSEGV && sig != SIGBUS) || !g_actions_handler(sig)) return false;
    greg_t* gr = uc->uc_mcontext.gregs;
    u8* rip = (u8*)gr[REG_RIP];
    if (!g_cache.contains(rip)) return false;
    CpuState* st = t->st;
    if ((u64)gr[REG_R15] != (u64)st + kStateBias) return false;
    BlockMeta* b = g_cache.find_by_host(rip);
    const PcMapEntry* e = b ? g_cache.find_pc(b, rip) : nullptr;
    if (!e) return false;
    for (int g = 0; g < 32; g++) {
        x64::Reg h = block_host_reg(b, g);
        if (h != x64::NOREG && !(e->borrowed & (1 << h))) st->x[g] = (u64)gr[host_greg_index(h)];
        if (b && b->region && b->region->vmap[g] != x64::NOREG && uc->uc_mcontext.fpregs)
            memcpy(&st->v[g], &uc->uc_mcontext.fpregs->_xmm[b->region->vmap[g]], 16);
    }
    st->pc = b->start + e->guest_off;
    u64 efl = e->flags_loc == PCF_SPILL ? st->flags_spill : (u64)gr[REG_EFL];
    st->eflags = (efl & 0x8c1) | 0x202;      // NZCV lives in SF/ZF/CF/OF
    for (int g = 0; g < 32; g++)
        if (regmap::mapped(g)) gr[host_greg_index(regmap::host(g))] = (greg_t)st->x[g];
    gr[REG_EFL] = (greg_t)st->eflags;
    t->sync_sig = sig;
    t->sync_info = *si;
    st->exit_reason = EXIT_SIGNAL;
    st->pending_signal = 1;
    gr[REG_RIP] = (greg_t)g_cache.stubs.exit_to_runtime;
    return true;
}

i64 sig_rt_sigaction(CpuState*, int sig, u64 act, u64 oact, u64 sigsetsize) {
    if (sig < 1 || sig > 64 || sigsetsize != 8) return -EINVAL;
    GuestSigaction a, old;
    if (act) {
        memcpy(&a, (void*)act, 32);          // the Linux ABI struct has 4 words
        a.darwin = 0;
        if (sig == SIGKILL || sig == SIGSTOP) return -EINVAL;
    }
    {
        std::lock_guard<std::mutex> lk(g_actions_lock);
        old = g_actions[sig];
        if (act) g_actions[sig] = a;
    }
    if (oact) memcpy((void*)oact, &old, 32);
    if (act) {
        if (sigbit(sig) & kInternalSigs) return 0;  // XEF keeps its own handler (synchronous delivery: TODO)
        struct sigaction h {};
        if (a.handler == (u64)SIG_DFL || a.handler == (u64)SIG_IGN) {
            h.sa_handler = (void (*)(int))a.handler;
        } else {
            h.sa_sigaction = async_handler;
            h.sa_flags = SA_SIGINFO | SA_ONSTACK | ((a.flags & G_SA_RESTART) ? SA_RESTART : 0);
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

i64 sig_rt_sigprocmask(CpuState* st, int how, u64 set, u64 oset, u64 sigsetsize) {
    // Signals XEF itself depends on (faults, profiling) are never blocked on the host.
    u64 m;
    u64 hset = 0;
    if (set) {
        m = *(u64*)set & ~kInternalSigs;
        hset = (u64)&m;
    }
    if (syscall(SYS_rt_sigprocmask, how, hset, oset, sigsetsize) < 0) return -errno;
    // signals received earlier and held back by the guest mask may be deliverable now
    if (set && st && st->thread && (__atomic_load_n(&st->thread->pending, __ATOMIC_SEQ_CST) & ~host_blocked()))
        st->pending_signal = 1;
    return 0;
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


// ---- Darwin (xnu arm64) signal frames ---------------------------------------------------------------------
struct DSiginfo {
    int32_t d_signo, d_errno, d_code, d_pid;
    uint32_t d_uid; int32_t d_status;
    u64 d_addr, d_value, d_band, pad[7];
};
struct DMcontext {
    u64 far; u32 esr, exception;               // exception state
    u64 x[29], fp, lr, sp, pc; u32 cpsr, flags;   // thread state
    u8 neon[32 * 16]; u32 fpsr, fpcr;          // neon state
};
struct DUcontext {
    int32_t uc_onstack; uint32_t uc_sigmask;
    u64 ss_sp, ss_size; int32_t ss_flags, ss_pad;
    u64 uc_link, uc_mcsize, uc_mcontext;
};
struct DFrame {
    DSiginfo info;      // 104 -> 112
    u8 pad0[8];
    DUcontext uc;       // 56
    u8 pad1[8];
    DMcontext mc;
    u64 rec[2];
};
constexpr u64 kDarwinUcOffset = offsetof(DFrame, uc);
static u64 g_darwin_sigreturn_tramp;

int linux_to_darwin_sig(int l) {
    switch (l) {
        case SIGBUS: return 10; case SIGSYS: return 12; case SIGURG: return 16; case SIGSTOP: return 17;
        case SIGTSTP: return 18; case SIGCONT: return 19; case SIGCHLD: return 20; case SIGIO: return 23;
        case SIGUSR1: return 30; case SIGUSR2: return 31; default: return l;
    }
}
int darwin_to_linux_sig(int d) {
    switch (d) {
        case 10: return SIGBUS; case 12: return SIGSYS; case 16: return SIGURG; case 17: return SIGSTOP;
        case 18: return SIGTSTP; case 19: return SIGCONT; case 20: return SIGCHLD; case 23: return SIGIO;
        case 30: return SIGUSR1; case 31: return SIGUSR2; case 7: return 0 /*SIGEMT*/; case 29: return 0 /*SIGINFO*/;
        default: return d;
    }
}
u64 linux_mask_to_darwin(u64 m) {
    u32 r = 0;
    for (int l = 1; l <= 31; l++) if (m & sigbit(l)) { int d = linux_to_darwin_sig(l); if (d >= 1 && d <= 32) r |= 1u << (d - 1); }
    return r;
}
u64 darwin_mask_to_linux(u64 dm) {
    u64 r = 0;
    for (int d = 1; d <= 32; d++) if (dm & (1ull << (d - 1))) { int l = darwin_to_linux_sig(d); if (l > 0) r |= sigbit(l); }
    return r;
}

void sig_darwin_set_tramp(u64 tramp) { g_darwin_sigreturn_tramp = tramp; }

// act: Darwin sigaction fields already converted by the caller to (handler, linux-style flags, linux mask)
i64 sig_darwin_sigaction(int lsig, u64 handler, u64 flags, u64 mask, u64* old_handler, u64* old_flags, u64* old_mask) {
    if (lsig < 1 || lsig > 64) return -EINVAL;
    GuestSigaction old;
    {
        std::lock_guard<std::mutex> lk(g_actions_lock);
        old = g_actions[lsig];
        g_actions[lsig] = GuestSigaction{handler, flags, g_darwin_sigreturn_tramp, mask, 1};
    }
    if (old_handler) { *old_handler = old.handler; *old_flags = old.flags; *old_mask = old.mask; }
    if (sigbit(lsig) & kInternalSigs) return 0;
    struct sigaction h {};
    if (handler == (u64)SIG_DFL || handler == (u64)SIG_IGN) {
        h.sa_handler = (void (*)(int))handler;
    } else {
        h.sa_sigaction = async_handler;
        h.sa_flags = SA_SIGINFO | SA_ONSTACK | ((flags & G_SA_RESTART) ? SA_RESTART : 0);
        sigfillset(&h.sa_mask);
    }
    sigaction(lsig, &h, nullptr);
    return 0;
}


// Debug helper for XEF_DBG_SEGV_FRAMES: safe self-read (guest memory is host memory) and a best-effort V8 name dump.
#include <sys/uio.h>
static bool dbg_rd(u64 a, void* out, size_t n) {
    struct iovec l{out, n}, r{(void*)a, n};
    return process_vm_readv(getpid(), &l, 1, &r, 1, 0) == (ssize_t)n;
}
static void dbg_v8_str(u64 tagged) {   // flat one-byte V8 string (length at +0xb, chars at +0xf from the tagged pointer)
    char b[48]; u32 len;
    if (!(tagged & 1) || !dbg_rd(tagged + 0xb, &len, 4) || len > 40 || !dbg_rd(tagged + 0xf, b, len ? len : 1)) return;
    for (u32 i = 0; i < len; i++) if (b[i] < 32 || b[i] > 126) return;
    b[len] = 0; fprintf(stderr, " '%s'", b);
}
static void dbg_frames(CpuState* st) {   // walk the AAPCS64 frame chain; JS interpreter frames hold the JSFunction at fp-16
    u64 fp = st->x[29];
    for (int i = 0; i < 40 && fp; i++) {
        u64 f[2], fn = 0, off = 0;
        if (!dbg_rd(fp, f, 16)) break;
        dbg_rd(fp - 16, &fn, 8); dbg_rd(fp - 40, &off, 8);
        fprintf(stderr, "  frame fp=%#lx ret=%#lx fn=%#lx off=%#lx", (unsigned long)fp, (unsigned long)f[1], (unsigned long)fn, (unsigned long)off);
        u64 sfi = 0;
        if ((fn & 7) == 1 && dbg_rd(fn + 0x20 - 1, &sfi, 8) && (sfi & 1))
            for (int k = 1; k < 6; k++) {
                u64 w = 0; if (!dbg_rd(sfi - 1 + 8 * k, &w, 8)) continue;
                dbg_v8_str(w);
                if (k == 3 && (w & 1))   // ScopeInfo: look for strings (variable / function names) in its first words
                    for (int j = 1; j < 14; j++) { u64 v = 0; if (dbg_rd(w - 1 + 8 * j, &v, 8)) dbg_v8_str(v); }
            }
        fprintf(stderr, "\n");
        if (f[0] <= fp) break;
        fp = f[0];
    }
}
static void deliver_darwin(CpuState* st, int sig, const siginfo_t& si, u64 saved_mask, const GuestSigaction& a) {
    ThreadCtx* t = st->thread;
    if (getenv("XEF_DBG_SEGV") && (sig == SIGSEGV || sig == SIGBUS)) {
        fprintf(stderr, "xef: guest fault sig=%d addr=%p pc=%#lx\n", sig, si.si_addr, (unsigned long)st->pc);
        for (int r = 0; r < 31; r++) fprintf(stderr, " x%d=%#lx%s", r, (unsigned long)st->x[r], r % 4 == 3 ? "\n" : "");
        fprintf(stderr, "\n");
        if (getenv("XEF_DBG_SEGV_SCAN")) {   // find 8-byte slots equal to x20 followed by 0 (cons string with null second)
            FILE* m = fopen("/proc/self/maps", "r"); char ln[512];
            while (m && fgets(ln, sizeof ln, m)) {
                unsigned long lo, hi; char pr[8];
                if (sscanf(ln, "%lx-%lx %7s", &lo, &hi, pr) != 3 || pr[0] != 'r' || hi - lo > (1ul << 36) || strstr(ln, "[stack") || strstr(ln, "xef")) continue;
                for (u64* q = (u64*)lo; q + 1 < (u64*)hi; q++)
                    if (getenv("XEF_DBG_SEGV_VAL") && q[0] == strtoull(getenv("XEF_DBG_SEGV_VAL"), nullptr, 16))
                        { if (q[-2] < (1ul<<40) && (q[-3] & 1)) fprintf(stderr, " val %p: map=%#lx hl=%#lx first=%#lx second=%#lx\n", (void*)(q-3), (unsigned long)q[-3], (unsigned long)q[-2], (unsigned long)q[-1], (unsigned long)q[0]); }
                    else if (q[0] == st->x[20] && (q[1] == 0 || getenv("XEF_DBG_SEGV_ANY"))) fprintf(stderr, " cand %p: map=%#lx hash/len=%#lx first=%#lx second=%#lx\n", (void*)q, (unsigned long)q[-2], (unsigned long)q[-1], (unsigned long)q[0], (unsigned long)q[1]);
            }
            if (m) fclose(m);
        }
        if (getenv("XEF_DBG_SEGV_FRAMES")) dbg_frames(st);
        if (const char* e = getenv("XEF_DBG_SEGV_ADDR")) {   // dump 0x100 bytes starting at hex address
            u64 a = strtoull(e, nullptr, 16) & ~7ull;
            int n = getenv("XEF_DBG_SEGV_N") ? atoi(getenv("XEF_DBG_SEGV_N")) : 32;
            for (int k = 0; k < n; k++) fprintf(stderr, " %#lx: %#lx\n", (unsigned long)(a + k * 8), (unsigned long)((u64*)a)[k]);
        }
        if (const char* e = getenv("XEF_DBG_SEGV_REG")) {   // dump 0x80 bytes around guest register xN (tag bit cleared)
            int r = atoi(e); u64 a = (st->x[r] & ~7ull) - 0x40;
            for (int k = 0; k < 16; k++) fprintf(stderr, " %#lx: %#lx\n", (unsigned long)(a + k * 8), (unsigned long)((u64*)a)[k]);
        }
    }
    u64 sp = st->x[kGuestSP];
    if ((a.flags & G_SA_ONSTACK) && t->ss_size && !(sp > t->ss_sp && sp <= t->ss_sp + t->ss_size))
        sp = t->ss_sp + t->ss_size;
    else
        sp -= 128;                      // the arm64 red zone
    sp = (sp - sizeof(DFrame)) & ~15ull;
    DFrame* f = (DFrame*)sp;
    memset(f, 0, sizeof *f);
    f->info.d_signo = linux_to_darwin_sig(sig);
    f->info.d_code = si.si_code;
    f->info.d_pid = si.si_pid;
    f->info.d_uid = si.si_uid;
    if (sig == SIGSEGV || sig == SIGBUS || sig == SIGILL || sig == SIGFPE) f->info.d_addr = (u64)si.si_addr;
    f->uc.uc_sigmask = (u32)linux_mask_to_darwin(saved_mask);
    f->uc.ss_sp = t->ss_sp; f->uc.ss_size = t->ss_size; f->uc.ss_flags = t->ss_size ? 0 : 4;   // SS_DISABLE
    f->uc.uc_mcsize = sizeof(DMcontext);
    f->uc.uc_mcontext = (u64)&f->mc;
    DMcontext& mc = f->mc;
    if (sig == SIGSEGV || sig == SIGBUS) mc.far = (u64)si.si_addr;
    for (int i = 0; i < 29; i++) mc.x[i] = st->x[i];
    mc.fp = st->x[29]; mc.lr = st->x[30]; mc.sp = st->x[kGuestSP]; mc.pc = st->pc;
    mc.cpsr = eflags_to_nzcv(st->eflags);
    memcpy(mc.neon, st->v, 512);
    mc.fpsr = st->fpsr; mc.fpcr = st->fpcr;
    f->rec[0] = st->x[29]; f->rec[1] = st->x[30];
    st->x[0] = (u64)linux_to_darwin_sig(sig);
    st->x[1] = (u64)&f->info;
    st->x[2] = (u64)&f->uc;
    st->x[29] = (u64)f->rec;
    st->x[30] = g_darwin_sigreturn_tramp;
    st->x[kGuestSP] = sp;
    st->pc = a.handler;
    u64 nm = saved_mask | a.mask;
    if (!(a.flags & G_SA_NODEFER)) nm |= sigbit(sig);
    host_setmask(nm);
    if (a.flags & G_SA_RESETHAND) {
        struct sigaction h {};
        h.sa_handler = SIG_DFL;
        sigaction(sig, &h, nullptr);
    }
}

void sig_darwin_sigreturn(CpuState* st, u64 uctx) {
    DUcontext* uc = (DUcontext*)uctx;
    DMcontext& mc = *(DMcontext*)uc->uc_mcontext;
    for (int i = 0; i < 29; i++) st->x[i] = mc.x[i];
    st->x[29] = mc.fp; st->x[30] = mc.lr; st->x[kGuestSP] = mc.sp; st->pc = mc.pc;
    st->eflags = nzcv_to_eflags(mc.cpsr);
    memcpy(st->v, mc.neon, 512);
    st->fpsr = mc.fpsr; st->fpcr = mc.fpcr;
    u32 rm = (st->fpcr >> 22) & 3, rc = ((rm & 1) << 1) | (rm >> 1);
    __builtin_ia32_ldmxcsr(0x1F80 | (rc << 13) | ((st->fpcr >> 24) & 1 ? 0x8040 : 0));
    host_setmask(darwin_mask_to_linux(uc->uc_sigmask));
    if (__atomic_load_n(&st->thread->pending, __ATOMIC_SEQ_CST)) st->pending_signal = 1;
}
u64 sig_darwin_ucontext_offset() { return kDarwinUcOffset; }

static void deliver_one(CpuState* st, int sig, const siginfo_t& si, u64 saved_mask) {
    ThreadCtx* t = st->thread;
    GuestSigaction a;   // a copy: the guest may change it concurrently
    {
        std::lock_guard<std::mutex> lk(g_actions_lock);
        a = g_actions[sig];
        if (a.handler > 1 && (a.flags & G_SA_RESETHAND)) g_actions[sig].handler = 0;
    }
    // the disposition may have changed since the signal was queued
    if (a.handler == (u64)SIG_IGN) return;
    if (a.handler == (u64)SIG_DFL) {
        if (sig == SIGCHLD || sig == SIGURG || sig == SIGWINCH || sig == SIGCONT) return;   // default: ignore
        signal(sig, SIG_DFL);   // default: terminate (or stop / core) like the host would
        sigset_t one;
        sigemptyset(&one);
        sigaddset(&one, sig);
        pthread_sigmask(SIG_UNBLOCK, &one, nullptr);
        raise(sig);
        return;
    }
    if (a.darwin) { deliver_darwin(st, sig, si, saved_mask, a); return; }
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
    if (a.flags & G_SA_RESETHAND) {   // (g_actions was reset above, with the copy)
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
    deliver_one(st, sig, si, saved_mask);   // also handles an action changed to SIG_IGN / SIG_DFL
    // more to deliver now? (signals still blocked are re-checked when the mask changes)
    if (__atomic_load_n(&t->pending, __ATOMIC_SEQ_CST) & ~host_blocked()) st->pending_signal = 1;
}

void signals_deliver_pending(CpuState* st) {
    // EXIT_SIGNAL clobbers nothing; strip TF that may have been captured by an exit stub
    st->eflags &= ~0x100ull;
    u64 m = host_blocked();
    ThreadCtx* t = st->thread;
    if (int sig = t->sync_sig) {   // synchronous fault: delivered first, even if blocked
        t->sync_sig = 0;
        deliver_one(st, sig, t->sync_info, m);
        st->pending_signal = __atomic_load_n(&t->pending, __ATOMIC_SEQ_CST) != 0;
        return;
    }
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
        // the host MXCSR follows FPCR (see emit_sys: RMode -> RC, FZ -> FTZ|DAZ)
        u32 rm = (st->fpcr >> 22) & 3, rc = ((rm & 1) << 1) | (rm >> 1);
        u32 mx = 0x1F80 | (rc << 13) | ((st->fpcr >> 24) & 1 ? 0x8040 : 0);
        __builtin_ia32_ldmxcsr(mx);
        memcpy(st->v, mc.reserved + 16, 512);
    }
    host_setmask(f->uc.uc_sigmask);
    if (__atomic_load_n(&st->thread->pending, __ATOMIC_SEQ_CST)) st->pending_signal = 1;
}

i64 sig_rt_sigsuspend(CpuState* st, u64 set, u64 sigsetsize) {
    if (sigsetsize != 8) return -EINVAL;
    u64 old = host_blocked();
    u64 tmp = *(u64*)set & ~kInternalSigs;
    // XEF's own signals (the tier-2 sampling timer, ...) stay unblocked and also end the host
    // sigsuspend: wait again until a signal for the guest is pending
    long r;
    do {
        r = syscall(SYS_rt_sigsuspend, &tmp, 8);
        r = r < 0 ? -errno : r;
    } while (r == -EINTR && !(__atomic_load_n(&st->thread->pending, __ATOMIC_SEQ_CST) & ~tmp));
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

// XEF's own handlers run on a per-thread alternate stack: the JIT stack may be the one that
// overflowed, and guest code must not see host frames on its stack.
void signals_thread_init(ThreadCtx* t) {
    tls_thread = t;
    const size_t sz = 64 << 10;
    void* p = t ? t->host_altstack : nullptr;   // a recycled context keeps its stack
    if (!p) {
        p = mmap(nullptr, sz, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (p == MAP_FAILED) return;
        if (t) t->host_altstack = p;
    }
    stack_t ss {};
    ss.ss_sp = p;
    ss.ss_size = sz;
    sigaltstack(&ss, nullptr);
}

}  // namespace xef
