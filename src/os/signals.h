// XEF — guest signal handling.
#pragma once
#include "common/common.h"
#include "runtime/cpu_state.h"

namespace xef {

void signals_init();
void signals_flush_output();
i64 sig_rt_sigaction(CpuState* st, int sig, u64 act, u64 oact, u64 sigsetsize);
i64 sig_rt_sigprocmask(CpuState* st, int how, u64 set, u64 oset, u64 sigsetsize);
void sig_rt_sigreturn(CpuState* st);
i64 sig_rt_sigsuspend(CpuState* st, u64 set, u64 sigsetsize);
i64 sig_sigaltstack(CpuState* st, u64 ss, u64 oss);
// Deliver pending guest signals at a safe point (between blocks).
void signals_deliver_pending(CpuState* st);

}  // namespace xef
