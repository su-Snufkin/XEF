// XEF — guest (AArch64 Linux) system call emulation on top of the host kernel.
#pragma once
#include <string>

#include "common/common.h"
#include "runtime/cpu_state.h"

namespace xef {

struct LoadedImage;

void syscalls_init(const LoadedImage& img);
std::string guest_exe_path();
// Executes the syscall described by st->x[8] / x0..x5; result in st->x[0].
void do_syscall(CpuState* st);

// Host syscall numbers for guest numbers where the call can be passed through
// unchanged (no argument conversion). -1 = needs emulation / unsupported.
extern i16 g_passthrough_nr[512];

}  // namespace xef
