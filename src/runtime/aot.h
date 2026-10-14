// XEF — persistent translation cache (XEF_AOT=1): tier-1 translations saved at exit and reused
// by later runs of the same program when the guest code they were made from is unchanged.
#pragma once
#include "backend/x64/assembler.h"
#include "runtime/code_cache.h"

namespace xef::aot {

bool enabled();
// After regmap::select / runtime_init: opens the cache of this guest executable.
void init(const char* guest_exe_host_path);

// Capture (translate(), with g_cache.lock held): a tier-1 chain just generated at `code`
// (bodies and cold stubs, exits not linked yet), with the relocations recorded by its assembler.
x64::RelocSink* sink();   // per thread; nullptr when disabled
void capture(int nc, const GuestAddr* pcs, const GuestAddr* ends, BlockMeta* const* metas,
             const PeekLog* peeks, const PcMapEntry* const* pcmaps, const int* npcmaps, const u8* code, size_t size,
             const x64::RelocSink& rs);

// A cached chain one of whose members starts at pc, instantiated and published if the guest
// code it depends on is unchanged (no lock held by the caller); nullptr otherwise.
BlockMeta* try_load(GuestAddr pc);

void save();         // exit_group, execve: append this process's new translations
void after_fork();   // child: the parent saves what was captured before the fork

// Deterministic address for a file mapping without a fixed address (0: let the kernel choose),
// so that libraries land where they were when their translations were saved.
u64 mmap_hint(u64 len);

}  // namespace xef::aot
