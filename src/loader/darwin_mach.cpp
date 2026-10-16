// XEF-OSX — in-process Mach IPC for the HLE libSystem: ports, port sets, mach_msg, mk_timer, semaphores and a few
// vm calls.  Enough for CFRunLoop / libdispatch / NSRunLoop to wait on ports inside one process.
#include "loader/darwin_hle.h"
#include "common/common.h"

#include <condition_variable>
#include <chrono>
#include <deque>
#include <map>
#include <memory>
#include <mutex>
#include <sys/eventfd.h>
#include <fcntl.h>
#include <unistd.h>
#include <thread>
#include <vector>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <semaphore.h>
#include <sched.h>
#include <stdio.h>
#include <string>

namespace xef {

enum : uint32_t {
    KERN_SUCCESS_ = 0, KERN_INVALID_ARGUMENT_ = 4, KERN_FAILURE_ = 5, KERN_INVALID_NAME_ = 15, KERN_INVALID_RIGHT_ = 17,
    KERN_OPERATION_TIMED_OUT_ = 49,
    MACH_SEND_MSG_ = 1, MACH_RCV_MSG_ = 2, MACH_SEND_TIMEOUT_ = 0x10, MACH_RCV_TIMEOUT_ = 0x100, MACH_RCV_LARGE_ = 0x800,
    MACH_SEND_INVALID_DEST_ = 0x10000003, MACH_SEND_TIMED_OUT_ = 0x10000004, MACH_RCV_INVALID_NAME_ = 0x10004002,
    MACH_RCV_TIMED_OUT_ = 0x10004003, MACH_RCV_TOO_LARGE_ = 0x10004004,
};

struct MachMsgHeader { uint32_t bits, size, remote, local, voucher; int32_t id; };

struct Port {
    uint32_t name;
    bool is_set = false;
    bool dead = false;
    std::vector<uint32_t> members;          // for sets
    uint32_t in_set = 0;                    // set this port belongs to
    std::deque<std::vector<uint8_t>> msgs;
    uint32_t qlimit = 5;
    uint64_t timer_gen = 0;                 // mk_timer
    bool is_timer = false;
    int evfd = -1;                          // kqueue EVFILT_MACHPORT: readable while a message is queued
};

static std::mutex g_mach_lock;
static std::condition_variable g_mach_cv;
static std::map<uint32_t, std::unique_ptr<Port>> g_ports;
static uint32_t g_next_port = 0x1103;

static Port* find_port(uint32_t name) {
    auto it = g_ports.find(name);
    return it == g_ports.end() ? nullptr : it->second.get();
}

// The notification eventfd of a port (or set) is readable exactly while it has a message to receive.
static bool has_msgs_locked(Port* p) {
    if (!p->is_set) return !p->msgs.empty();
    for (uint32_t m : p->members) { Port* mp = find_port(m); if (mp && !mp->msgs.empty()) return true; }
    return false;
}
static void sync_evfd_locked(Port* p) {
    if (!p || p->evfd < 0) return;
    uint64_t v;
    bool readable = read(p->evfd, &v, 8) == 8;    // (drained, then set again if still non-empty)
    (void)readable;
    if (has_msgs_locked(p)) { uint64_t one = 1; if (write(p->evfd, &one, 8) < 0) {} }
}
static void queue_changed_locked(Port* p) {
    sync_evfd_locked(p);
    if (p->in_set) sync_evfd_locked(find_port(p->in_set));
}

static uint32_t new_port_locked(bool is_set) {
    uint32_t n = g_next_port;
    g_next_port += 0x100;
    auto p = std::make_unique<Port>();
    p->name = n; p->is_set = is_set;
    g_ports[n] = std::move(p);
    return n;
}

static int mach_port_allocate_(uint32_t, uint32_t right, uint32_t* name) {
    if (!name) return KERN_INVALID_ARGUMENT_;
    std::lock_guard<std::mutex> lk(g_mach_lock);
    if (right == 1 || right == 3 || right == 2) { *name = new_port_locked(right == 3); return KERN_SUCCESS_; }
    return KERN_INVALID_ARGUMENT_;
}
// mach_port_construct(task, options, context, *name): a receive right; MPO_QLIMIT (2) sets the queue limit,
// MPO_PORT_SET... is not an option here (sets come from mach_port_allocate). mach_port_destruct destroys it.
struct MachPortOptions { uint32_t flags; uint32_t qlimit; uint64_t reserved[2]; };
static int mach_port_construct_(uint32_t, const MachPortOptions* opt, uint64_t, uint32_t* name) {
    if (!name || !opt) return KERN_INVALID_ARGUMENT_;
    std::lock_guard<std::mutex> lk(g_mach_lock);
    *name = new_port_locked(false);
    if (opt->flags & 2) find_port(*name)->qlimit = opt->qlimit ? opt->qlimit : 1;
    return KERN_SUCCESS_;
}
static int mach_port_destroy_(uint32_t, uint32_t name);
static int mach_port_destruct_(uint32_t t, uint32_t name, int32_t, uint64_t) { return mach_port_destroy_(t, name); }

static int mach_port_destroy_(uint32_t, uint32_t name) {
    std::lock_guard<std::mutex> lk(g_mach_lock);
    Port* p = find_port(name);
    if (!p) return KERN_INVALID_NAME_;
    if (p->in_set) if (Port* s = find_port(p->in_set)) {
        for (auto it = s->members.begin(); it != s->members.end(); ++it) if (*it == name) { s->members.erase(it); break; }
    }
    p->timer_gen++;
    if (p->evfd >= 0) close(p->evfd);
    g_ports.erase(name);
    return KERN_SUCCESS_;
}
static int mach_port_deallocate_(uint32_t, uint32_t name) { (void)name; return KERN_SUCCESS_; }
static int mach_port_insert_right_(uint32_t, uint32_t name, uint32_t poly, uint32_t) {
    std::lock_guard<std::mutex> lk(g_mach_lock);
    return find_port(name) || poly ? KERN_SUCCESS_ : KERN_INVALID_NAME_;
}
static int mach_port_mod_refs_(uint32_t, uint32_t name, uint32_t, int32_t) {
    std::lock_guard<std::mutex> lk(g_mach_lock);
    return find_port(name) ? KERN_SUCCESS_ : KERN_INVALID_NAME_;
}
static int mach_port_type_(uint32_t, uint32_t name, uint32_t* type) {
    std::lock_guard<std::mutex> lk(g_mach_lock);
    Port* p = find_port(name);
    if (!p) return KERN_INVALID_NAME_;
    *type = p->is_set ? 0x00080000 : 0x00030000;   // PORT_SET / RECEIVE|SEND
    return KERN_SUCCESS_;
}
static int mach_port_get_attributes_(uint32_t, uint32_t name, int flavor, int* info, uint32_t* cnt) {
    std::lock_guard<std::mutex> lk(g_mach_lock);
    Port* p = find_port(name);
    if (!p) return KERN_INVALID_NAME_;
    (void)flavor;   // MACH_PORT_LIMITS_INFO(1)/QLIMIT, MACH_PORT_RECEIVE_STATUS(2): report the queue limit and depth
    if (info && cnt && *cnt >= 1) { memset(info, 0, *cnt * 4); info[0] = (int)p->qlimit; }
    return KERN_SUCCESS_;
}
static int mach_port_set_attributes_(uint32_t, uint32_t name, int, int* info, uint32_t) {
    std::lock_guard<std::mutex> lk(g_mach_lock);
    Port* p = find_port(name);
    if (!p) return KERN_INVALID_NAME_;
    if (info && info[0] > 0) p->qlimit = (uint32_t)info[0];
    return KERN_SUCCESS_;
}
static int mach_port_insert_member_(uint32_t, uint32_t name, uint32_t pset) {
    std::lock_guard<std::mutex> lk(g_mach_lock);
    Port *p = find_port(name), *s = find_port(pset);
    if (!p || !s || !s->is_set) return KERN_INVALID_NAME_;
    if (p->in_set == pset) return KERN_SUCCESS_;
    p->in_set = pset;
    s->members.push_back(name);
    sync_evfd_locked(s);
    g_mach_cv.notify_all();
    return KERN_SUCCESS_;
}
static int mach_port_extract_member_(uint32_t, uint32_t name, uint32_t pset) {
    std::lock_guard<std::mutex> lk(g_mach_lock);
    Port *p = find_port(name), *s = find_port(pset);
    if (!p || !s) return KERN_INVALID_NAME_;
    for (auto it = s->members.begin(); it != s->members.end(); ++it) if (*it == name) { s->members.erase(it); break; }
    p->in_set = 0;
    sync_evfd_locked(s);
    return KERN_SUCCESS_;
}
static int mach_port_request_notification_(uint32_t, uint32_t, int, uint32_t, uint32_t, uint32_t, uint32_t* prev) {
    if (prev) *prev = 0;
    return KERN_SUCCESS_;
}

// ---- messages ----------------------------------------------------------------------------------------
static int mach_msg_(MachMsgHeader* msg, uint32_t option, uint32_t send_size, uint32_t rcv_size, uint32_t rcv_name,
                     uint32_t timeout_ms, uint32_t) {
    if (option & MACH_SEND_MSG_) {
        if (!msg || send_size < sizeof(MachMsgHeader)) return 0x10000008;   // MACH_SEND_MSG_TOO_SMALL
        std::lock_guard<std::mutex> lk(g_mach_lock);
        Port* dest = find_port(msg->remote);
        if (!dest) return MACH_SEND_INVALID_DEST_;
        std::vector<uint8_t> copy((uint8_t*)msg, (uint8_t*)msg + send_size);
        MachMsgHeader* h = (MachMsgHeader*)copy.data();
        uint32_t reply = h->local;
        h->remote = reply;          // the receiver sees the sender's reply port as the remote port
        h->local = dest->name;
        h->bits &= 0x00FF00FFu;
        if (dest->msgs.size() >= dest->qlimit && (option & MACH_SEND_TIMEOUT_)) return MACH_SEND_TIMED_OUT_;
        dest->msgs.push_back(std::move(copy));
        queue_changed_locked(dest);
        g_mach_cv.notify_all();
    }
    if (option & MACH_RCV_MSG_) {
        std::unique_lock<std::mutex> lk(g_mach_lock);
        auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeout_ms);
        for (;;) {
            Port* p = find_port(rcv_name);
            if (!p) return MACH_RCV_INVALID_NAME_;
            Port* src = nullptr;
            if (p->is_set) {
                for (uint32_t m : p->members) { Port* mp = find_port(m); if (mp && !mp->msgs.empty()) { src = mp; break; } }
            } else if (!p->msgs.empty()) src = p;
            if (src) {
                std::vector<uint8_t>& front = src->msgs.front();
                if (front.size() > rcv_size) {
                    if (!(option & MACH_RCV_LARGE_)) { src->msgs.pop_front(); queue_changed_locked(src); }
                    return MACH_RCV_TOO_LARGE_;
                }
                memcpy(msg, front.data(), front.size());
                ((MachMsgHeader*)msg)->local = src->name;
                src->msgs.pop_front();
                queue_changed_locked(src);
                return 0;
            }
            if ((option & MACH_RCV_TIMEOUT_)) {
                if (timeout_ms == 0 || g_mach_cv.wait_until(lk, deadline) == std::cv_status::timeout) {
                    // one last look, then give up
                    Port* q = find_port(rcv_name);
                    bool any = false;
                    if (q) {
                        if (q->is_set) { for (uint32_t m : q->members) { Port* mp = find_port(m); if (mp && !mp->msgs.empty()) any = true; } }
                        else any = !q->msgs.empty();
                    }
                    if (!any) return MACH_RCV_TIMED_OUT_;
                }
            } else {
                g_mach_cv.wait(lk);
            }
        }
    }
    return 0;
}
static int mach_msg_overwrite_(MachMsgHeader* msg, uint32_t opt, uint32_t ss, uint32_t rs, uint32_t rn, uint32_t to, uint32_t nt,
                               MachMsgHeader*, uint32_t) {
    return mach_msg_(msg, opt, ss, rs, rn, to, nt);
}
static void mach_msg_destroy_(MachMsgHeader*) {}

// ---- mk_timer ----------------------------------------------------------------------------------------------
static uint64_t now_abs() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + ts.tv_nsec;
}
static uint32_t mk_timer_create_() {
    std::lock_guard<std::mutex> lk(g_mach_lock);
    uint32_t n = new_port_locked(false);
    find_port(n)->is_timer = true;
    return n;
}
static int mk_timer_destroy_(uint32_t name) { return mach_port_destroy_(0, name); }
static int mk_timer_arm_(uint32_t name, uint64_t expire) {
    uint64_t gen;
    {
        std::lock_guard<std::mutex> lk(g_mach_lock);
        Port* p = find_port(name);
        if (!p) return KERN_INVALID_NAME_;
        gen = ++p->timer_gen;
    }
    std::thread([name, gen, expire] {
        uint64_t now = now_abs();
        if (expire > now) std::this_thread::sleep_for(std::chrono::nanoseconds(expire - now));
        std::lock_guard<std::mutex> lk(g_mach_lock);
        Port* p = find_port(name);
        if (!p || p->timer_gen != gen) return;
        MachMsgHeader h = {0, sizeof h + 8, name, 0, 0, 0};
        std::vector<uint8_t> m(sizeof h + 8, 0);
        memcpy(m.data(), &h, sizeof h);
        p->msgs.push_back(std::move(m));
        queue_changed_locked(p);
        g_mach_cv.notify_all();
    }).detach();
    return KERN_SUCCESS_;
}
static int mk_timer_cancel_(uint32_t name, uint64_t* result) {
    std::lock_guard<std::mutex> lk(g_mach_lock);
    Port* p = find_port(name);
    if (!p) return KERN_INVALID_NAME_;
    p->timer_gen++;
    if (result) *result = 0;
    return KERN_SUCCESS_;
}

// ---- semaphores -----------------------------------------------------------------------------------------------
struct MSem { sem_t s; };
static std::map<uint32_t, MSem*> g_sems;
static uint32_t semaphore_create_(uint32_t, uint32_t* out, int, int value) {
    std::lock_guard<std::mutex> lk(g_mach_lock);
    MSem* m = new MSem; sem_init(&m->s, 0, value);
    uint32_t n = g_next_port; g_next_port += 0x100;
    g_sems[n] = m; *out = n;
    return KERN_SUCCESS_;
}
static MSem* sem_find(uint32_t n) { std::lock_guard<std::mutex> lk(g_mach_lock); auto it = g_sems.find(n); return it == g_sems.end() ? nullptr : it->second; }
static int semaphore_destroy_(uint32_t, uint32_t n) { std::lock_guard<std::mutex> lk(g_mach_lock); g_sems.erase(n); return 0; }
static int semaphore_signal_(uint32_t n) { MSem* m = sem_find(n); if (!m) return KERN_INVALID_NAME_; sem_post(&m->s); return 0; }
static int semaphore_signal_all_(uint32_t n) { MSem* m = sem_find(n); if (!m) return KERN_INVALID_NAME_; for (int i = 0; i < 8; i++) sem_post(&m->s); return 0; }
static int semaphore_wait_(uint32_t n) { MSem* m = sem_find(n); if (!m) return KERN_INVALID_NAME_; while (sem_wait(&m->s) < 0) {} return 0; }
static int semaphore_timedwait_(uint32_t n, uint32_t sec, int32_t nsec) {
    MSem* m = sem_find(n); if (!m) return KERN_INVALID_NAME_;
    struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
    ts.tv_sec += sec; ts.tv_nsec += nsec; if (ts.tv_nsec >= 1000000000) { ts.tv_sec++; ts.tv_nsec -= 1000000000; }
    return sem_timedwait(&m->s, &ts) == 0 ? 0 : KERN_OPERATION_TIMED_OUT_;
}

// ---- vm ----------------------------------------------------------------------------------------------------------
// vm_allocate & co. work in 16K pages. Without VM_FLAGS_ANYWHERE (1) the range at *addr must be free (KERN_NO_SPACE 3
// otherwise), never replaced.
static int mach_vm_allocate_(uint32_t, uint64_t* addr, uint64_t size, int flags) {
    if (!addr) return 4;                                       // KERN_INVALID_ARGUMENT
    uint64_t len = (size + 16383) & ~16383ull;
    if (!len) { *addr = 0; return 0; }
    void* r;
    if (flags & 1) {
        void* res = mmap(nullptr, len + 16384, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
        if (res == MAP_FAILED) return 3;
        uintptr_t u = (uintptr_t)res, a = (u + 16383) & ~(uintptr_t)16383;
        if (a > u) munmap(res, a - u);
        if (u + 16384 > a) munmap((void*)(a + len), u + 16384 - a);
        r = mmap((void*)a, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
    } else {
        if (*addr & 16383) return 4;
        r = mmap((void*)(uintptr_t)*addr, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
        if (r != MAP_FAILED && (uint64_t)(uintptr_t)r != *addr) { munmap(r, len); r = MAP_FAILED; }
    }
    if (r == MAP_FAILED) return 3;
    *addr = (uint64_t)(uintptr_t)r;
    return 0;
}
// thread_switch(hint thread, option, time): SWITCH_OPTION_NONE 0 / DEPRESS 1 yield, SWITCH_OPTION_WAIT 2 also blocks
// for `time` ms (the handoff hint has no Linux counterpart: the scheduler picks the next thread).
static int thread_switch_(uint32_t, int option, uint32_t time_ms) {
    if (option < 0 || option > 5) return KERN_INVALID_ARGUMENT_;
    if (option == 2 && time_ms) {
        struct timespec ts = {(time_t)(time_ms / 1000), (long)(time_ms % 1000) * 1000000};
        nanosleep(&ts, nullptr);
    } else {
        sched_yield();
    }
    return KERN_SUCCESS_;
}
// mach_vm_map / vm_map for anonymous memory (object MACH_PORT_NULL): `mask` is the alignment - 1 (at least a 16K
// page), VM_FLAGS_ANYWHERE 1 or a fixed address that must be free unless VM_FLAGS_OVERWRITE 0x4000. The last three
// parameters are ints the caller packed into the stack (Apple's arm64 ABI): cur/max protection share the first slot.
static int mach_vm_map_(uint32_t, uint64_t* addr, uint64_t size, uint64_t mask, int flags, uint32_t object, uint64_t,
                        int, uint64_t prot_pair, uint64_t) {
    if (!addr || !size) return 4;                              // KERN_INVALID_ARGUMENT
    if (object != 0) return 4;                                 // memory entries / shared objects: not supported
    int prot = (int)(prot_pair & 7);
    uint64_t len = (size + 16383) & ~16383ull;
    uint64_t align = (mask | 16383) + 1;
    if (align & (align - 1)) return 4;
    void* r;
    if (flags & 1) {
        void* res = mmap(nullptr, len + align, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
        if (res == MAP_FAILED) return 3;                       // KERN_NO_SPACE
        uintptr_t u = (uintptr_t)res, a = (u + align - 1) & ~(uintptr_t)(align - 1);
        if (a > u) munmap(res, a - u);
        if (u + len + align > a + len) munmap((void*)(a + len), u + len + align - (a + len));
        r = mmap((void*)a, len, prot, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE | MAP_FIXED, -1, 0);
    } else {
        if (*addr & (align - 1)) return 4;
        r = mmap((void*)(uintptr_t)*addr, len, prot, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE |
                 ((flags & 0x4000) ? MAP_FIXED : MAP_FIXED_NOREPLACE), -1, 0);
        if (r != MAP_FAILED && (uint64_t)(uintptr_t)r != *addr) { munmap(r, len); r = MAP_FAILED; }
    }
    if (r == MAP_FAILED) return 3;
    *addr = (uint64_t)(uintptr_t)r;
    return 0;
}
static void page_range(uint64_t addr, uint64_t size, uint64_t* a, uint64_t* n) {
    *a = addr & ~16383ull;
    *n = ((addr + size + 16383) & ~16383ull) - *a;
}
// vm_inherit: VM_INHERIT_COPY 1 / NONE 2 map to MADV_DOFORK / MADV_DONTFORK; SHARE 0 (turning private memory into
// memory shared with children) has no Linux equivalent.
static int mach_vm_inherit_(uint32_t, uint64_t addr, uint64_t size, uint32_t inh) {
    if (!size) return 0;
    uint64_t a, n;
    page_range(addr, size, &a, &n);
    if (inh == 1) return madvise((void*)(uintptr_t)a, n, MADV_DOFORK) ? 1 : 0;      // KERN_INVALID_ADDRESS
    if (inh == 2) return madvise((void*)(uintptr_t)a, n, MADV_DONTFORK) ? 1 : 0;
    return 4;
}
static int mach_vm_deallocate_(uint32_t, uint64_t addr, uint64_t size) {
    if (!size) return 0;
    uint64_t a, n;
    page_range(addr, size, &a, &n);
    return munmap((void*)(uintptr_t)a, n) ? 4 : 0;
}
static int mach_vm_protect_(uint32_t, uint64_t addr, uint64_t size, int, int prot) {
    if (!size) return 0;
    uint64_t a, n;
    page_range(addr, size, &a, &n);
    return mprotect((void*)(uintptr_t)a, n, prot & 7) ? 2 /*KERN_PROTECTION_FAILURE*/ : 0;
}
// Exception ports: registrations are kept per exception type and reported by the getters, but no Mach exception
// message is ever sent - faults reach the guest as Unix signals, which is what programs that clear these ports
// (HotSpot: EXC_MASK_BAD_ACCESS etc. -> MACH_PORT_NULL) arrange for on macOS.
struct ExcPort { uint32_t port; int32_t behavior, flavor; };
static std::mutex g_exc_lock;
static ExcPort g_task_exc[32];
static int set_exc_ports(ExcPort* tab, uint32_t mask, uint32_t port, int behavior, int flavor) {
    if (mask & ~0x7FFEu) return 4;                             // KERN_INVALID_ARGUMENT: EXC_* are 1..14
    std::lock_guard<std::mutex> lk(g_exc_lock);
    for (int e = 1; e < 15; e++) if (mask & (1u << e)) tab[e] = ExcPort{port, behavior, flavor};
    return 0;
}
static int get_exc_ports(ExcPort* tab, uint32_t mask, uint32_t* masks, uint32_t* count, uint32_t* ports, int32_t* behaviors,
                         int32_t* flavors) {
    if (!count) return 4;
    std::lock_guard<std::mutex> lk(g_exc_lock);
    uint32_t n = 0;
    for (int e = 1; e < 15; e++) {
        if (!(mask & (1u << e))) continue;
        uint32_t i = 0;                                        // types with the same registration share one entry
        for (; i < n; i++)
            if (ports[i] == tab[e].port && behaviors[i] == tab[e].behavior && flavors[i] == tab[e].flavor) break;
        if (i < n) { masks[i] |= 1u << e; continue; }
        if (n >= *count) break;
        masks[n] = 1u << e; ports[n] = tab[e].port; behaviors[n] = tab[e].behavior; flavors[n] = tab[e].flavor;
        n++;
    }
    *count = n;
    return 0;
}
static int task_set_exception_ports_(uint32_t, uint32_t mask, uint32_t port, int behavior, int flavor) {
    return set_exc_ports(g_task_exc, mask, port, behavior, flavor);
}
static int task_get_exception_ports_(uint32_t, uint32_t mask, uint32_t* masks, uint32_t* count, uint32_t* ports,
                                     int32_t* behaviors, int32_t* flavors) {
    return get_exc_ports(g_task_exc, mask, masks, count, ports, behaviors, flavors);
}
static int task_swap_exception_ports_(uint32_t t, uint32_t mask, uint32_t port, int behavior, int flavor, uint32_t* masks,
                                      uint32_t* count, uint32_t* ports, int32_t* behaviors, int32_t* flavors) {
    int r = get_exc_ports(g_task_exc, mask, masks, count, ports, behaviors, flavors);
    return r ? r : task_set_exception_ports_(t, mask, port, behavior, flavor);
}
static thread_local ExcPort t_thread_exc[32];
static int thread_set_exception_ports_(uint32_t, uint32_t mask, uint32_t port, int behavior, int flavor) {
    return set_exc_ports(t_thread_exc, mask, port, behavior, flavor);   // (the calling thread's own port only)
}
static int thread_get_exception_ports_(uint32_t, uint32_t mask, uint32_t* masks, uint32_t* count, uint32_t* ports,
                                       int32_t* behaviors, int32_t* flavors) {
    return get_exc_ports(t_thread_exc, mask, masks, count, ports, behaviors, flavors);
}
static uint32_t mach_thread_self_() { return darwin_thread_port((int)syscall(SYS_gettid)); }
static uint32_t mach_host_self_() { return 0x100; }
static uint32_t mach_task_self__() { return 0x103; }

// ---- host_statistics / host_statistics64 / host_processor_info from /proc ----------------------------------------
// Page counts are in Darwin's 16 KiB pages (vm_page_size). Layouts: <mach/vm_statistics.h>, <mach/host_info.h>.
static std::map<std::string, uint64_t> read_kv(const char* path, bool kb) {
    std::map<std::string, uint64_t> m;
    FILE* f = fopen(path, "r");
    if (!f) return m;
    char k[128]; unsigned long long v;
    while (fscanf(f, "%127s %llu%*[^\n]", k, &v) == 2) {
        std::string key(k);
        if (!key.empty() && key.back() == ':') key.pop_back();
        m[key] = kb ? v * 1024 : v;
    }
    fclose(f);
    return m;
}
struct VmStat64 {
    uint32_t free_count, active_count, inactive_count, wire_count;
    uint64_t zero_fill_count, reactivations, pageins, pageouts, faults, cow_faults, lookups, hits, purges;
    uint32_t purgeable_count, speculative_count;
    uint64_t decompressions, compressions, swapins, swapouts;
    uint32_t compressor_page_count, throttled_count, external_page_count, internal_page_count;
    uint64_t total_uncompressed_pages_in_compressor;
    uint64_t pad;   // sizeof == 160 in the SDK (trailing alignment)
};
static_assert(offsetof(VmStat64, total_uncompressed_pages_in_compressor) == 144 && sizeof(VmStat64) == 160, "vm_statistics64");
static void vm_stat64(VmStat64* v) {
    memset(v, 0, sizeof *v);
    auto mi = read_kv("/proc/meminfo", true);
    auto vs = read_kv("/proc/vmstat", false);
    const uint64_t pg = 16384;
    uint64_t total = mi["MemTotal"], fr = mi["MemFree"], act = mi["Active"], inact = mi["Inactive"];
    v->free_count = (uint32_t)(fr / pg);
    v->active_count = (uint32_t)(act / pg);
    v->inactive_count = (uint32_t)(inact / pg);
    uint64_t used = total > fr + act + inact ? total - fr - act - inact : 0;
    v->wire_count = (uint32_t)(used / pg);
    v->faults = vs["pgfault"];
    v->pageins = vs["pgmajfault"];
    v->pageouts = vs["pswpout"];
    v->swapins = vs["pswpin"];
    v->swapouts = vs["pswpout"];
    v->external_page_count = (uint32_t)((mi["Active(file)"] + mi["Inactive(file)"]) / pg);
    v->internal_page_count = (uint32_t)((mi["Active(anon)"] + mi["Inactive(anon)"]) / pg);
}
static void cpu_ticks(std::vector<uint32_t>& out, bool per_cpu) {   // USER, SYSTEM, IDLE, NICE per entry
    FILE* f = fopen("/proc/stat", "r");
    if (!f) return;
    char line[512];
    while (fgets(line, sizeof line, f)) {
        if (strncmp(line, "cpu", 3)) break;
        bool total = line[3] == ' ';
        if (total == per_cpu) continue;
        unsigned long long u = 0, n = 0, sy = 0, id = 0, io = 0, irq = 0, sirq = 0;
        sscanf(line + (total ? 3 : 4 + strcspn(line + 3, " ")), "%llu %llu %llu %llu %llu %llu %llu", &u, &n, &sy, &id, &io, &irq, &sirq);
        out.push_back((uint32_t)u); out.push_back((uint32_t)(sy + irq + sirq)); out.push_back((uint32_t)(id + io)); out.push_back((uint32_t)n);
    }
    fclose(f);
}
static uint32_t host_statistics64_(uint32_t, int flavor, void* info, uint32_t* count) {
    if (!info || !count) return KERN_INVALID_ARGUMENT_;
    if (flavor == 4) {   // HOST_VM_INFO64
        if (*count < 38) return KERN_INVALID_ARGUMENT_;
        VmStat64 v;
        vm_stat64(&v);
        size_t n = std::min<size_t>(*count, 40) * 4;
        memcpy(info, &v, n);
        *count = (uint32_t)(n / 4);
        return KERN_SUCCESS_;
    }
    return KERN_INVALID_ARGUMENT_;
}
static uint32_t host_statistics_(uint32_t host, int flavor, void* info, uint32_t* count) {
    if (!info || !count) return KERN_INVALID_ARGUMENT_;
    if (flavor == 2) {   // HOST_VM_INFO: 32-bit vm_statistics (15 natural_t)
        if (*count < 15) return KERN_INVALID_ARGUMENT_;
        VmStat64 v;
        vm_stat64(&v);
        uint32_t o[15] = {v.free_count, v.active_count, v.inactive_count, v.wire_count, (uint32_t)v.zero_fill_count,
                          (uint32_t)v.reactivations, (uint32_t)v.pageins, (uint32_t)v.pageouts, (uint32_t)v.faults,
                          (uint32_t)v.cow_faults, (uint32_t)v.lookups, (uint32_t)v.hits, v.purgeable_count, (uint32_t)v.purges,
                          v.speculative_count};
        memcpy(info, o, sizeof o);
        *count = 15;
        return KERN_SUCCESS_;
    }
    if (flavor == 3) {   // HOST_CPU_LOAD_INFO
        if (*count < 4) return KERN_INVALID_ARGUMENT_;
        std::vector<uint32_t> t;
        cpu_ticks(t, false);
        if (t.size() < 4) return KERN_FAILURE_;
        memcpy(info, t.data(), 16);
        *count = 4;
        return KERN_SUCCESS_;
    }
    return host_statistics64_(host, flavor, info, count);
}
// host_processor_info(host, PROCESSOR_CPU_LOAD_INFO(2), &ncpu, &info, &count): info is vm_allocate'd (freed by vm_deallocate)
static uint32_t host_processor_info_(uint32_t, int flavor, uint32_t* ncpu, uint64_t* info, uint32_t* count) {
    if (flavor != 2 || !ncpu || !info || !count) return KERN_INVALID_ARGUMENT_;
    std::vector<uint32_t> t;
    cpu_ticks(t, true);
    if (t.empty()) return KERN_FAILURE_;
    size_t bytes = (t.size() * 4 + 16383) & ~(size_t)16383;
    void* p = mmap(nullptr, bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) return 3;   // KERN_NO_SPACE
    memcpy(p, t.data(), t.size() * 4);
    *ncpu = (uint32_t)(t.size() / 4);
    *info = (uint64_t)(uintptr_t)p;
    *count = (uint32_t)t.size();
    return KERN_SUCCESS_;
}

// host_info: HOST_BASIC_INFO (12 ints), HOST_SCHED_INFO (2 ints)
static uint32_t host_info_(uint32_t, int flavor, int32_t* info, uint32_t* count) {
    if (!info || !count) return KERN_INVALID_ARGUMENT_;
    if (flavor == 1) {
        if (*count < 12) return KERN_FAILURE_;   // as macOS for a too-small buffer
        long conf = sysconf(_SC_NPROCESSORS_CONF), onl = sysconf(_SC_NPROCESSORS_ONLN);
        uint64_t mem = (uint64_t)sysconf(_SC_PHYS_PAGES) * (uint64_t)sysconf(_SC_PAGESIZE);
        memset(info, 0, 48);
        info[0] = (int32_t)conf; info[1] = (int32_t)onl;
        info[2] = (int32_t)(uint32_t)std::min<uint64_t>(mem, 0xffffffffu);
        info[3] = 0x0100000c;          // CPU_TYPE_ARM64
        info[4] = 2;                   // CPU_SUBTYPE_ARM64E (Apple silicon reports it)
        info[5] = 0;
        info[6] = (int32_t)onl; info[7] = (int32_t)conf; info[8] = (int32_t)onl; info[9] = (int32_t)conf;
        memcpy(&info[10], &mem, 8);
        *count = 12;
        return KERN_SUCCESS_;
    }
    if (flavor == 3) {
        if (*count < 2) return KERN_FAILURE_;
        info[0] = 10; info[1] = 10;    // min_timeout, min_quantum (ms)
        *count = 2;
        return KERN_SUCCESS_;
    }
    return KERN_INVALID_ARGUMENT_;
}
// clock services: SYSTEM_CLOCK (0, = REALTIME_CLOCK 2) counts uptime like mach_absolute_time, CALENDAR_CLOCK (1) is wall time
constexpr uint32_t kSysClockPort = 0x1f03, kCalClockPort = 0x1f07;
static uint32_t host_get_clock_service_(uint32_t, int id, uint32_t* port) {
    if (!port) return KERN_INVALID_ARGUMENT_;
    if (id == 0 || id == 2) *port = kSysClockPort;
    else if (id == 1) *port = kCalClockPort;
    else return KERN_INVALID_ARGUMENT_;
    return KERN_SUCCESS_;
}
struct MachTimespec { uint32_t tv_sec; int32_t tv_nsec; };
static uint32_t clock_get_time_(uint32_t port, MachTimespec* t) {
    if (!t) return KERN_INVALID_ARGUMENT_;
    struct timespec ts;
    if (port == kSysClockPort) clock_gettime(CLOCK_MONOTONIC, &ts);
    else if (port == kCalClockPort) clock_gettime(CLOCK_REALTIME, &ts);
    else return KERN_INVALID_ARGUMENT_;
    t->tv_sec = (uint32_t)ts.tv_sec;
    t->tv_nsec = (int32_t)ts.tv_nsec;
    return KERN_SUCCESS_;
}

struct MachShim { const char* name; void* fn; };
static const MachShim kMach[] = {
    {"_host_statistics", (void*)&host_statistics_}, {"_host_statistics64", (void*)&host_statistics64_},
    {"_host_processor_info", (void*)&host_processor_info_}, {"_host_info", (void*)&host_info_},
    {"_host_get_clock_service", (void*)&host_get_clock_service_}, {"_clock_get_time", (void*)&clock_get_time_},
    {"_mach_port_allocate", (void*)&mach_port_allocate_}, {"_mach_port_construct", (void*)&mach_port_construct_},
    {"_mach_port_destruct", (void*)&mach_port_destruct_}, {"_mach_port_destroy", (void*)&mach_port_destroy_},
    {"_mach_port_deallocate", (void*)&mach_port_deallocate_}, {"_mach_port_insert_right", (void*)&mach_port_insert_right_},
    {"_mach_port_mod_refs", (void*)&mach_port_mod_refs_}, {"_mach_port_type", (void*)&mach_port_type_},
    {"_mach_port_get_attributes", (void*)&mach_port_get_attributes_}, {"_mach_port_set_attributes", (void*)&mach_port_set_attributes_},
    {"_mach_port_insert_member", (void*)&mach_port_insert_member_}, {"_mach_port_extract_member", (void*)&mach_port_extract_member_},
    {"_mach_port_request_notification", (void*)&mach_port_request_notification_},
    {"_mach_msg", (void*)&mach_msg_}, {"_mach_msg_overwrite", (void*)&mach_msg_overwrite_}, {"_mach_msg_destroy", (void*)&mach_msg_destroy_},
    {"_mk_timer_create", (void*)&mk_timer_create_}, {"_mk_timer_destroy", (void*)&mk_timer_destroy_},
    {"_mk_timer_arm", (void*)&mk_timer_arm_}, {"_mk_timer_cancel", (void*)&mk_timer_cancel_},
    {"_semaphore_create", (void*)&semaphore_create_}, {"_semaphore_destroy", (void*)&semaphore_destroy_},
    {"_semaphore_signal", (void*)&semaphore_signal_}, {"_semaphore_signal_all", (void*)&semaphore_signal_all_},
    {"_semaphore_wait", (void*)&semaphore_wait_}, {"_semaphore_timedwait", (void*)&semaphore_timedwait_},
    {"_mach_vm_allocate", (void*)&mach_vm_allocate_}, {"_mach_vm_map", (void*)&mach_vm_map_}, {"_vm_map", (void*)&mach_vm_map_}, {"_thread_switch", (void*)&thread_switch_}, {"_vm_inherit", (void*)&mach_vm_inherit_}, {"_mach_vm_inherit", (void*)&mach_vm_inherit_}, {"_mach_vm_deallocate", (void*)&mach_vm_deallocate_},
    {"_mach_vm_protect", (void*)&mach_vm_protect_}, {"_vm_allocate", (void*)&mach_vm_allocate_},
    {"_vm_deallocate", (void*)&mach_vm_deallocate_}, {"_vm_protect", (void*)&mach_vm_protect_},
    {"_mach_thread_self", (void*)&mach_thread_self_}, {"_mach_host_self", (void*)&mach_host_self_},
    {"_mach_task_self", (void*)&mach_task_self__},
    {"_task_set_exception_ports", (void*)&task_set_exception_ports_}, {"_task_get_exception_ports", (void*)&task_get_exception_ports_},
    {"_task_swap_exception_ports", (void*)&task_swap_exception_ports_},
    {"_thread_set_exception_ports", (void*)&thread_set_exception_ports_}, {"_thread_get_exception_ports", (void*)&thread_get_exception_ports_},
};

// kqueue EVFILT_MACHPORT: a dup of the port's notification eventfd (readable while it has messages), or -1
int darwin_mach_port_notify_fd(uint32_t name) {
    std::lock_guard<std::mutex> lk(g_mach_lock);
    Port* p = find_port(name);
    if (!p) return -1;
    if (p->evfd < 0) {
        p->evfd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
        if (p->evfd < 0) return -1;
        sync_evfd_locked(p);
    }
    return fcntl(p->evfd, F_DUPFD_CLOEXEC, 1000);
}
uint32_t darwin_mach_port_pending_size(uint32_t name) {   // size of the next message (0: none)
    std::lock_guard<std::mutex> lk(g_mach_lock);
    Port* p = find_port(name);
    if (!p) return 0;
    if (!p->is_set) return p->msgs.empty() ? 0 : (uint32_t)p->msgs.front().size();
    for (uint32_t m : p->members) { Port* mp = find_port(m); if (mp && !mp->msgs.empty()) return (uint32_t)mp->msgs.front().size(); }
    return 0;
}

void* darwin_mach_lookup(const char* name) {
    for (const MachShim& s : kMach) if (!strcmp(s.name, name)) return s.fn;
    return nullptr;
}

} // namespace xef
