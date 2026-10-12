// XEF — guest threads and processes.
#include "os/thread.h"
#include "thunks/thunks.h"

#include <errno.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <fcntl.h>
#include <linux/futex.h>
#include <pthread.h>
#include <sys/time.h>

#include <atomic>
#include <mutex>
#include <string>
#include <vector>

#include "loader/elf_loader.h"
#include "os/signals.h"
#include "os/syscalls.h"
#include "runtime/dispatch.h"
#include "runtime/tier2.h"

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

static std::atomic<int> g_live_threads{1};
int guest_thread_count() { return g_live_threads.load(); }

void thread_exit(CpuState* st, int code) {
    ThreadCtx* t = st->thread;
    if (g_live_threads.fetch_sub(1) == 1) {
        // last guest thread: the process ends (the tier-2 compiler thread must not keep it alive)
        signals_flush_output();
        syscall(SYS_exit_group, code);
    }
    tier2_thread_stop(t);
    if (t && t->clear_child_tid) {
        __atomic_store_n((u32*)t->clear_child_tid, 0, __ATOMIC_SEQ_CST);
        syscall(SYS_futex, t->clear_child_tid, FUTEX_WAKE, 1, nullptr, nullptr, 0);
    }
    syscall(SYS_exit, code);
    __builtin_unreachable();
}

// ---- clone ----
// Linux clone flags (identical on arm64 and x86-64)
constexpr u64 kCloneVM = 0x100, kCloneVfork = 0x4000, kCloneSettls = 0x80000, kCloneParentSettid = 0x100000,
              kCloneChildCleartid = 0x200000, kCloneChildSettid = 0x1000000, kCloneThread = 0x10000;

struct ThreadStart {
    ThreadCtx* t;
    u64 flags, ptid, ctid;
    volatile int tid;
};

static void* thread_trampoline(void* arg) {
    ThreadStart* ts = (ThreadStart*)arg;
    ThreadCtx* t = ts->t;
    int tid = (int)syscall(SYS_gettid);
    t->tid = tid;
    // like the kernel: both tid stores happen before the new thread runs guest code. (glibc passes
    // the same address as ptid and ctid; a parent-side store after the child started could
    // overwrite the 0 written when the thread exits, and pthread_join would wait forever.)
    if (ts->flags & kCloneParentSettid) *(u32*)ts->ptid = (u32)tid;
    if (ts->flags & kCloneChildSettid) *(u32*)ts->ctid = (u32)tid;
    if (ts->flags & kCloneChildCleartid) t->clear_child_tid = ts->ctid;
    __atomic_store_n(&ts->tid, tid, __ATOMIC_RELEASE);
    syscall(SYS_futex, &ts->tid, FUTEX_WAKE, 1, nullptr, nullptr, 0);
    // ts is owned by the parent's stack from here on: don't touch it
    signals_thread_init(t);
    tier2_thread_start(t);
    cpu_loop(t);
}

i64 thread_clone(CpuState* st, u64 flags, u64 stack, u64 ptid, u64 tls, u64 ctid) {
    if (flags & kCloneVM && !(flags & kCloneVfork)) {
        if (!(flags & kCloneThread)) return -EINVAL;  // CLONE_VM without CLONE_THREAD: not supported yet
        ThreadCtx* t = thread_create(st);
        t->ss_sp = t->ss_size = 0;   // new threads start without an alternate stack
        CpuState* cs = t->st;
        cs->x[0] = 0;
        if (stack) cs->x[kGuestSP] = stack;
        if (flags & kCloneSettls) cs->tpidr_el0 = tls;
        cs->pc = st->pc;
        cs->exit_reason = 0;
        ThreadStart ts{t, flags, ptid, ctid, 0};
        pthread_t th;
        pthread_attr_t attr;
        pthread_attr_init(&attr);
        pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
        pthread_attr_setstacksize(&attr, 1 << 20);
        g_live_threads.fetch_add(1);
        if (pthread_create(&th, &attr, thread_trampoline, &ts) != 0) {
            g_live_threads.fetch_sub(1);
            return -EAGAIN;
        }
        while (__atomic_load_n(&ts.tid, __ATOMIC_ACQUIRE) == 0)
            syscall(SYS_futex, &ts.tid, FUTEX_WAIT, 0, nullptr, nullptr, 0);
        return ts.tid;
    }
    // fork / vfork: a separate process. vfork's shared address space is emulated with a copy
    // (the child normally calls execve or _exit right away).
    u64 hflags = flags & ~(kCloneVM | kCloneVfork | kCloneSettls);
    i64 r;
    {
        std::lock_guard<std::mutex> lk(g_cache.lock);  // no translation in flight across fork
        r = syscall(SYS_clone, hflags, 0, ptid, ctid, 0);
    }
    if (r < 0) return -errno;
    if (r == 0) {
        // child
        if (stack) st->x[kGuestSP] = stack;
        if (flags & kCloneSettls) st->tpidr_el0 = tls;
        g_live_threads.store(1);
        if (st->thread) st->thread->tid = (int)syscall(SYS_gettid);
        tier2_after_fork(st->thread);
        return 0;
    }
    return r;
}

// ---- execve: run the new image under XEF (or natively if it is an x86-64 binary) ----

i64 process_execve(CpuState*, u64 gpath, u64 gargv, u64 genvp) {
    const char* path = (const char*)gpath;
    std::string selfexe = guest_exe_path();
    if (!strcmp(path, "/proc/self/exe")) path = selfexe.c_str();
    std::string host = resolve_guest_path(path);
    int fd = open(host.c_str(), O_RDONLY | O_CLOEXEC);
    if (fd < 0) return -errno;
    u8 hdr[256] = {0};
    ssize_t n = read(fd, hdr, sizeof hdr - 1);
    close(fd);
    if (n < 4) return -ENOEXEC;
    std::vector<std::string> args;
    for (char** a = (char**)gargv; a && *a; a++) args.push_back(*a);
    std::vector<char*> envp;
    for (char** e = (char**)genvp; e && *e; e++)
        if (strncmp(*e, "XEF_ROOTFS=", 11)) envp.push_back(*e);   // ours (below) must be the one seen
    std::string rootenv;
    if (!g_rootfs.empty()) { rootenv = "XEF_ROOTFS=" + g_rootfs; envp.push_back((char*)rootenv.c_str()); }
    static char hostgl[] = "XEF_HOST_GL=1";
    if (g_host_gl) envp.push_back(hostgl);
    envp.push_back(nullptr);
    std::string guest_exe = path;
    if (hdr[0] == '#' && hdr[1] == '!') {
        // script: interpreter [arg] script args...
        std::string line((char*)hdr + 2, strnlen((char*)hdr + 2, n - 2));
        line = line.substr(0, line.find('\n'));
        size_t b = line.find_first_not_of(" \t");
        if (b == std::string::npos) return -ENOEXEC;
        line = line.substr(b);
        size_t sp = line.find_first_of(" \t");
        std::string interp = line.substr(0, sp);
        std::vector<std::string> nargs{interp};
        if (sp != std::string::npos) {
            std::string rest = line.substr(line.find_first_not_of(" \t", sp));
            while (!rest.empty() && (rest.back() == ' ' || rest.back() == '\t' || rest.back() == '\r')) rest.pop_back();
            if (!rest.empty()) nargs.push_back(rest);
        }
        nargs.push_back(path);
        for (size_t i = 1; i < args.size(); i++) nargs.push_back(args[i]);
        args = nargs;
        guest_exe = interp;
        host = resolve_guest_path(interp.c_str());
        fd = open(host.c_str(), O_RDONLY | O_CLOEXEC);
        if (fd < 0) return -errno;
        n = read(fd, hdr, sizeof hdr - 1);
        close(fd);
    }
    if (n >= 20 && memcmp(hdr, "\x7f" "ELF", 4) == 0) {
        u16 machine = (u16)(hdr[18] | (hdr[19] << 8));
        if (machine == 62) {  // EM_X86_64: run natively
            std::vector<char*> av;
            for (auto& a : args) av.push_back((char*)a.c_str());
            av.push_back(nullptr);
            syscall(SYS_execve, host.c_str(), av.data(), envp.data());
            return -errno;
        }
        if (machine != 183) return -ENOEXEC;
    } else return -ENOEXEC;
    char self[4096];
    ssize_t sl = readlink("/proc/self/exe", self, sizeof self - 1);
    if (sl < 0) return -errno;
    self[sl] = 0;
    std::vector<char*> av;
    av.push_back(self);
    av.push_back((char*)"--");
    av.push_back((char*)guest_exe.c_str());
    for (size_t i = 1; i < args.size(); i++) av.push_back((char*)args[i].c_str());
    // argv[0] of the guest is preserved by the loader using the path; pass original argv0 via env
    av.push_back(nullptr);
    signals_flush_output();
    syscall(SYS_execve, self, av.data(), envp.data());
    return -errno;
}

}  // namespace xef
