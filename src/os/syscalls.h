// XEF — guest (AArch64 Linux) system call emulation on top of the host kernel.
#pragma once
#include <string>

#include "common/common.h"
#include "runtime/cpu_state.h"
#include "os/darwin/darwin_syscalls.h"

namespace xef {

struct LoadedImage;

void syscalls_init(const LoadedImage& img);
std::string guest_exe_path();
// Executes the syscall described by st->x[8] / x0..x5; result in st->x[0].
void do_syscall(CpuState* st);

// Host syscall numbers for guest numbers where the call can be passed through
// unchanged (no argument conversion). -1 = needs emulation / unsupported.
extern i16 g_passthrough_nr[512];

// File descriptors XEF itself keeps open (tier-2 pipe, host X connections): moved out of the way
// of the guest's numbers and protected from its close / close_range / dup2. Returns the new fd.
int reserve_host_fd(int fd);
void protect_host_fd(int fd);   // the same, in place (descriptors a host library keeps)
void release_host_fd(int fd);

}  // namespace xef
