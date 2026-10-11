// XEF — guest threads and processes.
#include "os/thread.h"

#include <errno.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

#include "os/signals.h"

namespace xef {

int g_main_argc_xef = 0;
char** g_xef_argv = nullptr;

ThreadCtx* thread_create(CpuState* parent) {
    ThreadCtx* t = new ThreadCtx();
    void* sp = mmap(nullptr, sizeof(CpuState), PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (sp == MAP_FAILED) fatal("cannot allocate CpuState");
    t->st = (CpuState*)sp;
    if (parent) memcpy(t->st, parent, sizeof(CpuState));
    t->st->thread = t;
    t->blk = new ir::Block();
    // JIT stack: native return-address stack for BL/RET prediction (+ guard page)
    t->jit_stack_size = 1 << 20;
    u8* s = (u8*)mmap(nullptr, t->jit_stack_size + 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (s == MAP_FAILED) fatal("cannot allocate JIT stack");
    mprotect(s, 4096, PROT_NONE);
    t->jit_stack = s;
    u8* top = s + 4096 + t->jit_stack_size - 64;
    // sentinel entry that never matches a guest return address
    ((u64*)top)[0] = 0;
    ((u64*)top)[1] = ~0ull;
    t->st->jit_stack_top = (u64)top;
    t->st->jit_sp = (u64)top;
    t->st->ibtc = g_cache.new_ibtc();
    return t;
}

void thread_exit(CpuState*, int code) {
    // milestone 1: single-threaded
    signals_flush_output();
    syscall(SYS_exit_group, code);
    __builtin_unreachable();
}

i64 thread_clone(CpuState*, u64, u64, u64, u64, u64) { return -ENOSYS; }

i64 process_execve(CpuState*, u64, u64, u64) { return -ENOSYS; }

}  // namespace xef
