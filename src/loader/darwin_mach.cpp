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
#include <thread>
#include <vector>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <semaphore.h>

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
};

static std::mutex g_mach_lock;
static std::condition_variable g_mach_cv;
static std::map<uint32_t, std::unique_ptr<Port>> g_ports;
static uint32_t g_next_port = 0x1103;

static Port* find_port(uint32_t name) {
    auto it = g_ports.find(name);
    return it == g_ports.end() ? nullptr : it->second.get();
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
static int mach_port_destroy_(uint32_t, uint32_t name) {
    std::lock_guard<std::mutex> lk(g_mach_lock);
    Port* p = find_port(name);
    if (!p) return KERN_INVALID_NAME_;
    if (p->in_set) if (Port* s = find_port(p->in_set)) {
        for (auto it = s->members.begin(); it != s->members.end(); ++it) if (*it == name) { s->members.erase(it); break; }
    }
    p->timer_gen++;
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
    g_mach_cv.notify_all();
    return KERN_SUCCESS_;
}
static int mach_port_extract_member_(uint32_t, uint32_t name, uint32_t pset) {
    std::lock_guard<std::mutex> lk(g_mach_lock);
    Port *p = find_port(name), *s = find_port(pset);
    if (!p || !s) return KERN_INVALID_NAME_;
    for (auto it = s->members.begin(); it != s->members.end(); ++it) if (*it == name) { s->members.erase(it); break; }
    p->in_set = 0;
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
                    if (!(option & MACH_RCV_LARGE_)) src->msgs.pop_front();
                    return MACH_RCV_TOO_LARGE_;
                }
                memcpy(msg, front.data(), front.size());
                ((MachMsgHeader*)msg)->local = src->name;
                src->msgs.pop_front();
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
static int mach_vm_allocate_(uint32_t, uint64_t* addr, uint64_t size, int flags) {
    void* want = (flags & 1) ? nullptr : (void*)(uintptr_t)*addr;
    void* r = mmap(want, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | ((flags & 1) ? 0 : MAP_FIXED), -1, 0);
    if (r == MAP_FAILED) return 3;
    *addr = (uint64_t)(uintptr_t)r;
    return 0;
}
static int mach_vm_deallocate_(uint32_t, uint64_t addr, uint64_t size) { return munmap((void*)(uintptr_t)addr, size) ? 4 : 0; }
static int mach_vm_protect_(uint32_t, uint64_t addr, uint64_t size, int, int prot) { return mprotect((void*)(uintptr_t)addr, size, prot & 7) ? 4 : 0; }
static uint32_t mach_thread_self_() { return darwin_thread_port((int)syscall(SYS_gettid)); }
static uint32_t mach_host_self_() { return 0x100; }
static uint32_t mach_task_self__() { return 0x103; }

struct MachShim { const char* name; void* fn; };
static const MachShim kMach[] = {
    {"_mach_port_allocate", (void*)&mach_port_allocate_}, {"_mach_port_destroy", (void*)&mach_port_destroy_},
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
    {"_mach_vm_allocate", (void*)&mach_vm_allocate_}, {"_mach_vm_deallocate", (void*)&mach_vm_deallocate_},
    {"_mach_vm_protect", (void*)&mach_vm_protect_}, {"_vm_allocate", (void*)&mach_vm_allocate_},
    {"_vm_deallocate", (void*)&mach_vm_deallocate_}, {"_vm_protect", (void*)&mach_vm_protect_},
    {"_mach_thread_self", (void*)&mach_thread_self_}, {"_mach_host_self", (void*)&mach_host_self_},
    {"_mach_task_self", (void*)&mach_task_self__},
};

void* darwin_mach_lookup(const char* name) {
    for (const MachShim& s : kMach) if (!strcmp(s.name, name)) return s.fn;
    return nullptr;
}

} // namespace xef
