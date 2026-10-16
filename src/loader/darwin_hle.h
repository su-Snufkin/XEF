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
void darwin_tsd_run_destructors();
// darwin_stdio.cpp: guest FILE* (Darwin struct __sFILE shell) <-> host FILE*
FILE* darwin_stdio_host(void* guest_file);
void* darwin_stdio_guest(FILE* host, const char* mode);
void darwin_stdio_sync(void* guest_file);
void darwin_stdio_fork_lock(bool take);
void* darwin_stdio_lookup(const char* name);
void* darwin_stdio_data_lookup(const char* name);
void* darwin_proc_lookup(const char* name);           // darwin_proc.cpp: libproc
void* darwin_termios_lookup(const char* name);        // darwin_termios.cpp
bool darwin_termios_ioctl(int fd, unsigned long req, void* arg, int* ret);
pid_t darwin_fork();                                  // fork with atfork handlers (darwin_hle.cpp)     // guest pthread key destructors of the exiting thread

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

// Creates a guest-callable stub for a host function and returns its guest address.
uint64_t darwin_hle_register_function(const char* name, void* host_fn);

uint64_t darwin_new_pthread_handle(void* stack_top, size_t stack_size);   // guest pthread_t (stored in TSD slot 0)
void darwin_set_pthread_host(uint64_t handle, pthread_t host, int tid);
int darwin_pthread_host(uint64_t th, pthread_t* host);    // 0 = current thread; ESRCH if not a pthread_t
uint64_t darwin_pthread_main_handle();
uint32_t darwin_thread_port(int tid);                     // mach port name of a thread

} // namespace xef
