// XEF — guest signal handling.
#pragma once
#include "common/common.h"
#include "runtime/cpu_state.h"

namespace xef {

// Host signal of XEF's per-thread sampling timers (tier-2 hotness, --profile): the last real-time
// signal, so that SIGPROF (ITIMER_PROF, profilers) stays the guest's.
constexpr int kSampleSig = 64;

struct ThreadCtx;
void signals_thread_init(ThreadCtx* t);
u32 eflags_to_nzcv(u64 e);
u64 nzcv_to_eflags(u32 nzcv);

void signals_init();
void signals_flush_output();
extern thread_local struct ThreadCtx* tls_thread;
void signals_report_on_interrupt();
i64 sig_rt_sigaction(CpuState* st, int sig, u64 act, u64 oact, u64 sigsetsize);
i64 sig_rt_sigprocmask(CpuState* st, int how, u64 set, u64 oset, u64 sigsetsize);
void sig_rt_sigreturn(CpuState* st);
i64 sig_rt_sigsuspend(CpuState* st, u64 set, u64 sigsetsize);
i64 sig_sigaltstack(CpuState* st, u64 ss, u64 oss);
// Deliver pending guest signals at a safe point (between blocks).
void signals_deliver_pending(CpuState* st);
bool g_actions_handler(int sig);   // the guest installed a handler (not SIG_DFL / SIG_IGN)
void signals_fork_lock(bool lock);   // hold the sigaction table across fork (no torn copy in the child)

}  // namespace xef
