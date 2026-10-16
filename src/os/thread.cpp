// XEF — guest threads and processes.
#include "os/thread.h"
#include "runtime/aot.h"
#include "thunks/thunks.h"

#include <errno.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <fcntl.h>
#include <setjmp.h>
#include <linux/futex.h>
#include <pthread.h>
#include <signal.h>
#include <sys/time.h>

#include <atomic>
#include <mutex>
#include <string>
#include <vector>

#include "loader/elf_loader.h"
#include "loader/darwin_hle.h"
#include "os/signals.h"
#include "os/syscalls.h"
#include "os/darwin/darwin_syscalls.h"
#include "runtime/dispatch.h"
#include "runtime/tier2.h"

namespace xef {

int g_main_argc_xef = 0;
char** g_xef_argv = nullptr;

static_assert(sizeof(IbtcEntry) * kIbtcEntries == kIbtcBytes, "IBTC layout (cpu_state.h)");

// Contexts of exited threads (CpuState + IBTC, JIT stack, IR scratch, sigaltstack) are reused:
// freeing them under a thread that is still running is unsafe, and leaking them cost ~0.5 MB of
// RSS per thread (programs creating threads in a loop ran out of memory or mappings).
static std::mutex g_pool_lock;
static std::vector<ThreadCtx*> g_pool;

static ThreadCtx* thread_reuse(CpuState* parent) {
    ThreadCtx* t;
    {
        std::lock_guard<std::mutex> lk(g_pool_lock);
        if (g_pool.empty()) return nullptr;
        t = g_pool.back();
        g_pool.pop_back();
    }
    CpuState* st = t->st;
    ir::Block* blk = t->blk;
    u8* js = t->jit_stack;
    size_t jss = t->jit_stack_size;
    void* alt = t->host_altstack;
    *t = ThreadCtx();
    t->st = st; t->blk = blk; t->jit_stack = js; t->jit_stack_size = jss; t->host_altstack = alt;
    void* ibtc = st->ibtc;   // still registered with the code cache (and scrubbed with the others)
    if (parent) memcpy(st, parent, sizeof(CpuState));
    else memset(st, 0, sizeof(CpuState));
    st->thread = t;
    st->ibtc = ibtc;
    return t;
}

// Darwin keeps the pthread TSD array behind TPIDRRO_EL0 (slot 0 = pthread_self); libobjc and libdispatch
// read it directly with MRS. Each guest thread gets its own zeroed block.
static void darwin_thread_tsd(ThreadCtx* t) {
    if (!g_is_darwin) return;
    if (!t->tsd) t->tsd = (u64*)calloc(768, 8);   // libpthread: _INTERNAL_POSIX_THREAD_KEYS_END
    else memset(t->tsd, 0, 768 * 8);
    t->tsd[0] = (u64)t->tsd;
    t->st->tpidrro_el0 = (u64)t->tsd;
    t->st->tpidr_el0 = (u64)t->tsd;
}

ThreadCtx* thread_create(CpuState* parent) {
    if (ThreadCtx* t = thread_reuse(parent)) {
        darwin_thread_tsd(t);
        u8* top = t->jit_stack + 4096 + t->jit_stack_size - 64;
        ((u64*)top)[0] = 0;
        ((u64*)top)[1] = ~0ull;
        t->st->jit_stack_top = (u64)top;
        t->st->jit_sp = (u64)top;
        return t;
    }
    ThreadCtx* t = new ThreadCtx();
    void* sp = mmap(nullptr, kIbtcOffset + kIbtcBytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
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
    t->st->ibtc = g_cache.init_ibtc((u8*)t->st + kIbtcOffset);
    darwin_thread_tsd(t);
    return t;
}

static std::atomic<int> g_live_threads{1};
static thread_local jmp_buf* tls_exit_jmp;
thread_local u64 tls_thread_retval = 0;   // value the guest start routine returned (Darwin pthread_join)

int guest_thread_count() { return g_live_threads.load(); }

// TIDs of the guest's threads (not XEF's compiler thread or host library workers): /proc/self/task
// lists only these, or programs signalling every thread (Firefox's sandbox setup) wait forever
static constexpr int kMaxTids = 8192;
static std::atomic<int> g_tids[kMaxTids];
static void guest_tid_add(int tid) {
    for (auto& e : g_tids) {
        int z = 0;
        if (e.compare_exchange_strong(z, tid)) return;
    }
}
static void guest_tid_remove(int tid) {
    for (auto& e : g_tids) {
        int x = tid;
        if (e.compare_exchange_strong(x, 0)) return;
    }
}
bool is_guest_tid(int tid) {
    for (auto& e : g_tids) if (e.load(std::memory_order_relaxed) == tid) return true;
    return false;
}
void guest_tid_init() {   // process start and fork child: just the calling thread
    for (auto& e : g_tids) e.store(0, std::memory_order_relaxed);
    guest_tid_add((int)syscall(SYS_gettid));
}

extern thread_local u64 tls_thread_retval;
void thread_set_retval(u64 v) { tls_thread_retval = v; }

// Ends the whole guest process without running C++ static destructors (background threads of the HLE,
// dispatch workers and timers may still be using them).
void guest_process_exit(int code) {
    fflush(nullptr);
    aot::save();
    signals_flush_output();
    syscall(SYS_exit_group, code);
    __builtin_unreachable();
}

void thread_exit(CpuState* st, int code) {
    ThreadCtx* t = st->thread;
    if (g_live_threads.fetch_sub(1) == 1) {
        // last guest thread: the process ends (the tier-2 compiler thread must not keep it alive)
        aot::save();
        signals_flush_output();
        syscall(SYS_exit_group, code);
    }
    tier2_thread_stop(t);
    guest_tid_remove((int)syscall(SYS_gettid));
    // no handler may touch the context once it is back in the pool
    sigset_t all;
    sigfillset(&all);
    pthread_sigmask(SIG_BLOCK, &all, nullptr);
    if (t && t->clear_child_tid) {
        __atomic_store_n((u32*)t->clear_child_tid, 0, __ATOMIC_SEQ_CST);
        syscall(SYS_futex, t->clear_child_tid, FUTEX_WAKE, 1, nullptr, nullptr, 0);
    }
    if (t) {
        std::lock_guard<std::mutex> lk(g_pool_lock);
        g_pool.push_back(t);
    }
    // threads started by thread_clone return from their pthread start routine, so that glibc
    // frees the pthread stack (a raw SYS_exit leaked it)
    if (tls_exit_jmp) longjmp(*tls_exit_jmp, 1);
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
    guest_tid_add(tid);
    // like the kernel: both tid stores happen before the new thread runs guest code. (glibc passes
    // the same address as ptid and ctid; a parent-side store after the child started could
    // overwrite the 0 written when the thread exits, and pthread_join would wait forever.)
    if (ts->flags & kCloneParentSettid) *(u32*)ts->ptid = (u32)tid;
    if (ts->flags & kCloneChildSettid) *(u32*)ts->ctid = (u32)tid;
    if (ts->flags & kCloneChildCleartid) t->clear_child_tid = ts->ctid;
    __atomic_store_n(&ts->tid, tid, __ATOMIC_RELEASE);
    syscall(SYS_futex, &ts->tid, FUTEX_WAKE, 1, nullptr, nullptr, 0);
    // ts is owned by the parent's stack from here on: don't touch it
    jmp_buf exit_jmp;
    if (setjmp(exit_jmp)) return (void*)tls_thread_retval;   // thread_exit: the context is already back in the pool
    tls_exit_jmp = &exit_jmp;
    signals_thread_init(t);
    tier2_thread_start(t);
    cpu_loop(t);
}

static void fork_child_fixup(CpuState* st) {
    g_live_threads.store(1);
    guest_tid_init();
    if (st->thread) st->thread->tid = (int)syscall(SYS_gettid);
    tier2_after_fork(st->thread);
    aot::after_fork();
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
        std::lock_guard<std::mutex> pl(g_pool_lock);   // nor a pool update
        signals_fork_lock(true);                        // nor a sigaction
        r = syscall(SYS_clone, hflags, 0, ptid, ctid, 0);
        signals_fork_lock(false);
    }
    if (r < 0) return -errno;
    if (r == 0) {
        // child
        if (stack) st->x[kGuestSP] = stack;
        if (flags & kCloneSettls) st->tpidr_el0 = tls;
        fork_child_fixup(st);
        return 0;
    }
    return r;
}

// Darwin fork(): the guest's malloc/stdio are the host libc's, so go through glibc's fork() (it resets its own
// locks in the child) while holding XEF's; `hold` takes/releases the HLE layer's locks around it.
i64 process_fork(CpuState* st, void (*hold)(bool)) {
    pid_t r;
    {
        std::lock_guard<std::mutex> lk(g_cache.lock);
        std::lock_guard<std::mutex> pl(g_pool_lock);
        signals_fork_lock(true);
        if (hold) hold(true);
        r = fork();
        int e = errno;
        if (hold) hold(false);
        signals_fork_lock(false);
        errno = e;
    }
    if (r < 0) return -errno;
    if (r == 0 && st) fork_child_fixup(st);
    return r;
}

extern std::atomic<int> g_darwin_is_threaded;

int darwin_spawn_thread(uint64_t* th_out, void* attr, uint64_t start_routine, uint64_t arg) {
    (void)attr;
    g_darwin_is_threaded.store(1);
    const size_t stack_size = 2ull * 1024 * 1024; // 2MB guest stack
    const size_t guard = 64 * 1024;
    void* r = mmap(nullptr, stack_size + guard, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    if (r == MAP_FAILED) return EAGAIN;
    mprotect(r, guard, PROT_NONE);

    uint64_t sp = (uint64_t)(uintptr_t)r + guard + stack_size;
    sp = (sp - 128) & ~15ull;

    ThreadCtx* parent_t = tls_thread;
    CpuState* parent_st = parent_t ? parent_t->st : nullptr;
    ThreadCtx* t = thread_create(parent_st);
    t->ss_sp = t->ss_size = 0;
    CpuState* cs = t->st;
    cs->x[0] = arg;
    cs->x[30] = g_darwin_thread_exit_trampoline;
    cs->x[kGuestSP] = sp;
    cs->pc = start_routine;
    cs->eflags = 0x203;
    uint64_t handle = darwin_new_pthread_handle((void*)((uintptr_t)r + guard + stack_size), stack_size);
    t->tsd[0] = handle;

    ThreadStart ts{t, 0, 0, 0, 0};
    pthread_t th;
    pthread_attr_t pattr;
    pthread_attr_init(&pattr);
    pthread_attr_setstacksize(&pattr, 1 << 20); // 1MB host stack
    g_live_threads.fetch_add(1);
    if (pthread_create(&th, &pattr, thread_trampoline, &ts) != 0) {
        g_live_threads.fetch_sub(1);
        munmap(r, stack_size + guard);
        pthread_attr_destroy(&pattr);
        return EAGAIN;
    }
    pthread_attr_destroy(&pattr);

    while (__atomic_load_n(&ts.tid, __ATOMIC_ACQUIRE) == 0)
        syscall(SYS_futex, &ts.tid, FUTEX_WAIT, 0, nullptr, nullptr, 0);

    darwin_set_pthread_host(handle, th, ts.tid);
    if (th_out) *th_out = handle;
    return 0;
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
    bool script = hdr[0] == '#' && hdr[1] == '!';
    if (script) {
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
    bool is_macho = false;
    if (n >= 4) {
        uint32_t magic = *(const uint32_t*)hdr;
        if (magic == 0xfeedfacf || magic == 0xcffaedfe || magic == 0xcafebabe || magic == 0xbebafeca) {
            is_macho = true;
        }
    }
    if (n >= 20 && memcmp(hdr, "\x7f" "ELF", 4) == 0) {
        u16 machine = (u16)(hdr[18] | (hdr[19] << 8));
        if (machine == 62) {  // EM_X86_64: run natively
            std::vector<char*> av;
            for (auto& a : args) av.push_back((char*)a.c_str());
            av.push_back(nullptr);
            aot::save();
            syscall(SYS_execve, host.c_str(), av.data(), envp.data());
            return -errno;
        }
        if (machine != 183) return -ENOEXEC;
    } else if (!is_macho) return -ENOEXEC;
    char self[4096];
    ssize_t sl = readlink("/proc/self/exe", self, sizeof self - 1);
    if (sl < 0) return -errno;
    self[sl] = 0;
    std::vector<char*> av;
    av.push_back(self);
    std::string root_opt;
    if (!g_rootfs.empty()) {
        static char o_l[] = "-L";
        av.push_back(o_l);
        root_opt = g_rootfs;
        av.push_back((char*)root_opt.c_str());
    }

    // the new image runs with the same XEF options
    static char o_stats[] = "--stats", o_prof[] = "--profile", o_not2[] = "--no-tier2", o_trace[] = "--trace",
                o_ir[] = "--dump-ir", o_code[] = "--dump-code", o_mb[] = "--max-block", o_t2t[] = "--tier2-threshold";
    std::string mb = std::to_string(g_opt.max_block_insts), t2t = std::to_string(g_tier2_threshold);
    if (g_opt.stats) av.push_back(o_stats);
    if (g_opt.profile) av.push_back(o_prof);
    if (g_opt.trace) av.push_back(o_trace);
    else if (!g_opt.tier2) av.push_back(o_not2);
    if (g_opt.dump_ir) av.push_back(o_ir);
    if (g_opt.dump_code) av.push_back(o_code);
    av.push_back(o_mb);
    av.push_back((char*)mb.c_str());
    av.push_back(o_t2t);
    av.push_back((char*)t2t.c_str());
    // argv[0] need not be the path (multi-call binaries, login shells' "-sh"); for scripts the
    // kernel's argv[0] is the interpreter as named in "#!", which guest_exe already is
    static char o_argv0[] = "--argv0";
    if (!script && !args.empty() && args[0] != guest_exe) {
        av.push_back(o_argv0);
        av.push_back((char*)args[0].c_str());
    }
    av.push_back((char*)"--");
    av.push_back((char*)guest_exe.c_str());
    for (size_t i = 1; i < args.size(); i++) av.push_back((char*)args[i].c_str());
    av.push_back(nullptr);
    signals_flush_output();
    aot::save();
    syscall(SYS_execve, self, av.data(), envp.data());
    return -errno;
}

}  // namespace xef
