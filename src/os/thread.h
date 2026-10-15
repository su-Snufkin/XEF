// XEF — guest threads and processes.
#pragma once
#include <signal.h>

#include "common/common.h"
#include "ir/ir.h"
#include "runtime/code_cache.h"
#include "runtime/cpu_state.h"

namespace xef {

struct ThreadCtx {
    CpuState* st = nullptr;
    ir::Block* blk = nullptr;       // translation scratch
    u8* jit_stack = nullptr;
    size_t jit_stack_size = 0;
    int tid = 0;
    u64 clear_child_tid = 0;
    // signals
    u64 pending = 0;
    siginfo_t pending_info[65];
    volatile bool stepping = false;
    u64 ss_sp = 0, ss_size = 0;
    void* host_altstack = nullptr;  // XEF's own sigaltstack (signals_thread_init), kept for reuse
    int sync_sig = 0;               // synchronous fault waiting for frame setup
    timer_t prof_timer {};          // per-thread sampling timer (kSampleSig, tier2.cpp)
    bool prof_timer_ok = false;
    siginfo_t sync_info;
    u64* tsd = nullptr;             // Darwin: thread-specific data block behind TPIDRRO_EL0
};

ThreadCtx* thread_create(CpuState* parent);
void guest_tid_init();
bool is_guest_tid(int tid);
void thread_exit(CpuState* st, int code);
[[noreturn]] void guest_process_exit(int code);   // flush + exit_group (no static destructors)
void thread_set_retval(u64 v);   // return value of the exiting thread's start routine
i64 thread_clone(CpuState* st, u64 flags, u64 stack, u64 ptid, u64 tls, u64 ctid);
i64 process_execve(CpuState* st, u64 path, u64 argv, u64 envp);
int darwin_spawn_thread(uint64_t* th_out, void* attr, uint64_t start_routine, uint64_t arg);

extern int g_main_argc_xef;      // number of argv entries belonging to xef itself
extern char** g_xef_argv;

}  // namespace xef
