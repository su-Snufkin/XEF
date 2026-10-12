// XEF — translation driver and the per-thread execution loop.
#pragma once
#include "common/common.h"
#include "os/thread.h"

namespace xef {

struct Options {
    bool dump_ir = false;
    bool dump_code = false;
    bool stats = false;
    bool profile = false;
    bool tier2 = true;
    bool trace = false;   // debugging: no block linking / IBTC, remember the last blocks entered
    int max_block_insts = 128;
};
extern Options g_opt;

void runtime_init();
[[noreturn]] void cpu_loop(ThreadCtx* t);
u8* get_or_translate(ThreadCtx* t, GuestAddr pc);
void code_invalidate_range(GuestAddr start, u64 len);

using EnterFn = void (*)(CpuState*, void*);

}  // namespace xef
