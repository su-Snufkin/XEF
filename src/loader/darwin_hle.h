// XEF-OSX — Darwin High-Level Emulation (HLE) Runtime for libSystem / dynamic libraries.
#pragma once
#include <stdint.h>
#include <string>
#include "runtime/cpu_state.h"

namespace xef {

// Initialize Darwin HLE subsystem
void darwin_hle_init();

// Resolve a Darwin Mach-O imported symbol name (e.g. "_printf", "___error", "___stdoutp")
// Returns guest ARM64 virtual address of a callable stub or data variable.
// If is_weak is true and symbol is unknown, returns 0 instead of creating a fallback stub.
uint64_t darwin_hle_resolve_symbol(const char* name, bool is_weak = false, bool explicit_only = false);

// Runs the atexit / __cxa_atexit handlers registered by the guest (reverse order).
void darwin_run_exit_handlers();

// Dispatches an HLE thunk call (st->x[17] = thunk ID)
void darwin_hle_dispatch(CpuState* st);

// The HLE function the calling guest thread is currently executing (for crash reports).
bool darwin_hle_current(const char** name, uint64_t* lr);

extern uint64_t g_darwin_stack_top;
extern uint64_t g_darwin_stack_size;
extern uint64_t g_darwin_mach_header;
extern int g_darwin_argc;
extern char** g_darwin_argv;
extern char** g_darwin_envp;
extern std::string g_darwin_exe_path;
extern uint64_t g_darwin_exit_trampoline;
extern uint64_t g_darwin_start_stub;     // runs the initializers, then branches to g_darwin_start_target
extern uint64_t g_darwin_start_target;
extern uint64_t g_darwin_thread_exit_trampoline;
extern const uint8_t* g_darwin_tlv_template;
extern size_t g_darwin_tlv_template_size;

void darwin_register_thread_stack(pthread_t th, void* stack_top, size_t stack_size);

} // namespace xef
