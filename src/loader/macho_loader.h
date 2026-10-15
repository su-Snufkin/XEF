// XEF-OSX — Mach-O loader for AArch64 macOS binaries.
#pragma once
#include <string>
#include "common/common.h"
#include "loader/elf_loader.h"
#include "runtime/cpu_state.h"

namespace xef {

// Check if file is a Mach-O or FAT binary containing ARM64 code
bool is_macho_binary(const char* path, bool& is_fat, bool& is_arm64);

// Load Mach-O ARM64 binary into memory
bool load_macho(const char* path, LoadedImage& img);

// Setup initial stack for macOS Darwin ARM64 execution
GuestAddr setup_darwin_stack(const LoadedImage& img, int argc, char** argv, char** envp, CpuState* st);

} // namespace xef
