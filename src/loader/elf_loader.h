// XEF — ELF loader for AArch64 guest binaries (static, static-pie, dynamic).
#pragma once
#include <string>

#include "common/common.h"

namespace xef {

struct LoadedImage {
    GuestAddr entry = 0;        // initial PC (interpreter entry for dynamic binaries)
    GuestAddr exe_entry = 0;    // AT_ENTRY
    GuestAddr exe_base = 0;
    GuestAddr phdr = 0;
    u64 phnum = 0, phent = 0;
    GuestAddr interp_base = 0;
    GuestAddr brk_start = 0;
    GuestAddr min_addr = ~0ull, max_addr = 0;
    std::string exe_path;       // as given (guest-visible)
    std::string host_path;      // resolved on host
};

// Guest root filesystem prefix (like qemu -L). Empty = host root.
extern std::string g_rootfs;
// Resolve a guest absolute path to a host path (rootfs-redirected if the file exists there).
// Host path of guest path `path`: inside the rootfs when it exists there, symlinks resolved as if
// the rootfs were / (follow_last=false leaves a final symlink itself, for lstat/readlink/unlink).
std::string resolve_guest_path(const char* path, bool follow_last = true);
bool resolve_guest_realpath(const char* path, std::string& out);
void guest_path_cache_clear();

bool load_elf(const char* path, LoadedImage& img);
GuestAddr setup_stack(const LoadedImage& img, int argc, char** argv, char** envp);

// Guest-visible hwcaps we advertise.
u64 guest_hwcap();
u64 guest_hwcap2();

}  // namespace xef
