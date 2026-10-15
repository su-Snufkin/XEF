// XEF-OSX — pthread mutex / condition variable / rwlock for Darwin guests, implemented in place on the guest's
// pthread_*_t memory with futexes (so static initializers, copies and process-shared use behave like on macOS).
#include "loader/darwin_hle.h"
#include "common/common.h"

#include <errno.h>
#include <limits.h>
#include <linux/futex.h>
#include <pthread.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

namespace xef {

static inline long futex(void* addr, int op, uint32_t val, const struct timespec* ts = nullptr, uint32_t val3 = 0) {
    return syscall(SYS_futex, addr, op, val, ts, nullptr, val3);
}
static inline uint32_t self_tid() { static thread_local uint32_t t = (uint32_t)syscall(SYS_gettid); return t; }

constexpr long kMutexSig = 0x4D555458, kCondSig = 0x434F4E44, kRwSig = 0x52574C4B;
constexpr long kMutexInitNormal = 0x32AAABA7, kMutexInitErrCheck = 0x32AAABA1, kMutexInitRecursive = 0x32AAABA2, kMutexInitFirstfit = 0x32AAABA3;
constexpr long kCondInit = 0x3CB0B1BB, kRwInit = 0x2DA8B3B4;

// ---- mutex -----------------------------------------------------------------------------------------------------
struct XMutex { long sig; uint32_t word, owner, count, type; };
static_assert(sizeof(XMutex) <= 64, "pthread_mutex_t");

static bool mutex_ready(XMutex* m) {
    long s = __atomic_load_n(&m->sig, __ATOMIC_ACQUIRE);
    if (s == kMutexSig) return true;
    uint32_t type;
    switch (s) {
        case kMutexInitNormal: case kMutexInitFirstfit: type = 0; break;
        case kMutexInitErrCheck: type = 1; break;
        case kMutexInitRecursive: type = 2; break;
        default: return false;
    }
    m->type = type;
    long expect = s;
    __atomic_compare_exchange_n(&m->sig, &expect, kMutexSig, false, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE);
    return true;
}

static int mutex_init(XMutex* m, const uint32_t* attr /* {sig lo,hi, type} */) {
    memset(m, 0, 64);
    m->type = attr && ((const long*)attr)[0] == 0x4D2AAAA5 ? attr[2] : 0;
    __atomic_store_n(&m->sig, kMutexSig, __ATOMIC_RELEASE);
    return 0;
}
static int mutex_destroy(XMutex* m) { m->sig = 0x99999999; return 0; }

static int mutex_lock_impl(XMutex* m, const struct timespec* abs_realtime, bool trylock) {
    if (!mutex_ready(m)) return EINVAL;
    uint32_t me = self_tid();
    if (m->type != 0 && __atomic_load_n(&m->owner, __ATOMIC_RELAXED) == me && m->word) {
        if (m->type == 2) { m->count++; return 0; }
        return trylock ? EBUSY : EDEADLK;
    }
    uint32_t c = 0;
    if (__atomic_compare_exchange_n(&m->word, &c, 1, false, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED)) {
        m->owner = me; m->count = 1; return 0;
    }
    if (trylock) return EBUSY;
    // contended: mark as "locked with waiters" (2) and sleep
    if (c != 2) c = __atomic_exchange_n(&m->word, 2, __ATOMIC_ACQUIRE);
    while (c != 0) {
        long r = futex(&m->word, FUTEX_WAIT_BITSET_PRIVATE | FUTEX_CLOCK_REALTIME, 2, abs_realtime, FUTEX_BITSET_MATCH_ANY);
        if (r < 0 && errno == ETIMEDOUT) return ETIMEDOUT;
        c = __atomic_exchange_n(&m->word, 2, __ATOMIC_ACQUIRE);
    }
    m->owner = me; m->count = 1;
    return 0;
}
static int mutex_lock(XMutex* m) { return mutex_lock_impl(m, nullptr, false); }
static int mutex_trylock(XMutex* m) { return mutex_lock_impl(m, nullptr, true); }
static int mutex_timedlock(XMutex* m, const struct timespec* ts) { return mutex_lock_impl(m, ts, false); }
static int mutex_unlock(XMutex* m) {
    if (!mutex_ready(m)) return EINVAL;
    if (m->type != 0) {
        if (m->owner != self_tid() || !m->word) return EPERM;
        if (m->type == 2 && --m->count) return 0;
    }
    m->owner = 0;
    if (__atomic_exchange_n(&m->word, 0, __ATOMIC_RELEASE) == 2) futex(&m->word, FUTEX_WAKE_PRIVATE, 1);
    return 0;
}

// ---- mutex attributes ------------------------------------------------------------------------------------------------
static int mattr_init(long* a) { a[0] = 0x4D2AAAA5; ((uint32_t*)a)[2] = 0; ((uint32_t*)a)[3] = 0; return 0; }
static int mattr_destroy(long* a) { a[0] = 0; return 0; }
static int mattr_settype(long* a, int t) { if (t < 0 || t > 2) return EINVAL; ((uint32_t*)a)[2] = (uint32_t)t; return 0; }
static int mattr_gettype(const long* a, int* t) { *t = (int)((const uint32_t*)a)[2]; return 0; }
static int mattr_nop(long*, int) { return 0; }
static int mattr_get0(const long*, int* v) { *v = 0; return 0; }

// ---- condition variables -------------------------------------------------------------------------------------------------
struct XCond { long sig; uint32_t seq, waiters; };
static void cond_ready(XCond* c) {
    long s = __atomic_load_n(&c->sig, __ATOMIC_ACQUIRE);
    if (s == kCondSig) return;
    if (s == kCondInit) { long e = s; __atomic_compare_exchange_n(&c->sig, &e, kCondSig, false, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE); }
    else if (s != kCondSig) { c->seq = 0; c->waiters = 0; __atomic_store_n(&c->sig, kCondSig, __ATOMIC_RELEASE); }
}
static int cond_init(XCond* c, const void*) { memset(c, 0, 48); c->sig = kCondSig; return 0; }
static int cond_destroy(XCond* c) { c->sig = 0x99999999; return 0; }
static int cond_signal(XCond* c) {
    cond_ready(c);
    __atomic_add_fetch(&c->seq, 1, __ATOMIC_SEQ_CST);
    if (__atomic_load_n(&c->waiters, __ATOMIC_SEQ_CST)) futex(&c->seq, FUTEX_WAKE_PRIVATE, 1);
    return 0;
}
static int cond_broadcast(XCond* c) {
    cond_ready(c);
    __atomic_add_fetch(&c->seq, 1, __ATOMIC_SEQ_CST);
    if (__atomic_load_n(&c->waiters, __ATOMIC_SEQ_CST)) futex(&c->seq, FUTEX_WAKE_PRIVATE, INT_MAX);
    return 0;
}
static int cond_wait_impl(XCond* c, XMutex* m, const struct timespec* abs_realtime) {
    cond_ready(c);
    uint32_t seq = __atomic_load_n(&c->seq, __ATOMIC_SEQ_CST);
    __atomic_add_fetch(&c->waiters, 1, __ATOMIC_SEQ_CST);
    mutex_unlock(m);
    int ret = 0;
    long r = futex(&c->seq, FUTEX_WAIT_BITSET_PRIVATE | FUTEX_CLOCK_REALTIME, seq, abs_realtime, FUTEX_BITSET_MATCH_ANY);
    if (r < 0 && errno == ETIMEDOUT) ret = ETIMEDOUT;
    __atomic_sub_fetch(&c->waiters, 1, __ATOMIC_SEQ_CST);
    mutex_lock(m);
    return ret;
}
static int cond_wait(XCond* c, XMutex* m) { return cond_wait_impl(c, m, nullptr); }
static int cond_timedwait(XCond* c, XMutex* m, const struct timespec* ts) {
    if (!ts) return cond_wait_impl(c, m, nullptr);
    if (ts->tv_sec > 100000000000ll) return cond_wait_impl(c, m, nullptr);     // "forever"
    return cond_wait_impl(c, m, ts);
}
static int cond_timedwait_relative(XCond* c, XMutex* m, const struct timespec* rel) {
    struct timespec abs;
    clock_gettime(CLOCK_REALTIME, &abs);
    abs.tv_sec += rel->tv_sec; abs.tv_nsec += rel->tv_nsec;
    if (abs.tv_nsec >= 1000000000) { abs.tv_sec++; abs.tv_nsec -= 1000000000; }
    return cond_wait_impl(c, m, &abs);
}
static int cattr_init(long* a) { a[0] = 0x3C000000; return 0; }
static int cattr_destroy(long* a) { a[0] = 0; return 0; }

// ---- rwlock ------------------------------------------------------------------------------------------------------------------
struct XRw { long sig; uint32_t state; uint32_t waiters; };      // state: readers, or 0x80000000 = writer
constexpr uint32_t kWriter = 0x80000000u;
static void rw_ready(XRw* r) {
    long s = __atomic_load_n(&r->sig, __ATOMIC_ACQUIRE);
    if (s == kRwSig) return;
    if (s == kRwInit) { long e = s; __atomic_compare_exchange_n(&r->sig, &e, kRwSig, false, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE); }
    else { r->state = 0; r->waiters = 0; __atomic_store_n(&r->sig, kRwSig, __ATOMIC_RELEASE); }
}
static int rw_init(XRw* r, const void*) { memset(r, 0, 200); r->sig = kRwSig; return 0; }
static int rw_destroy(XRw* r) { r->sig = 0x99999999; return 0; }
static int rw_tryrd(XRw* r) {
    rw_ready(r);
    uint32_t s = __atomic_load_n(&r->state, __ATOMIC_RELAXED);
    while (!(s & kWriter)) if (__atomic_compare_exchange_n(&r->state, &s, s + 1, false, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED)) return 0;
    return EBUSY;
}
static int rw_trywr(XRw* r) {
    rw_ready(r);
    uint32_t s = 0;
    return __atomic_compare_exchange_n(&r->state, &s, kWriter, false, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED) ? 0 : EBUSY;
}
static int rw_rd(XRw* r) {
    while (rw_tryrd(r) == EBUSY) {
        __atomic_add_fetch(&r->waiters, 1, __ATOMIC_SEQ_CST);
        uint32_t s = __atomic_load_n(&r->state, __ATOMIC_SEQ_CST);
        if (s & kWriter) futex(&r->state, FUTEX_WAIT_PRIVATE, s);
        __atomic_sub_fetch(&r->waiters, 1, __ATOMIC_SEQ_CST);
    }
    return 0;
}
static int rw_wr(XRw* r) {
    while (rw_trywr(r) == EBUSY) {
        __atomic_add_fetch(&r->waiters, 1, __ATOMIC_SEQ_CST);
        uint32_t s = __atomic_load_n(&r->state, __ATOMIC_SEQ_CST);
        if (s != 0) futex(&r->state, FUTEX_WAIT_PRIVATE, s);
        __atomic_sub_fetch(&r->waiters, 1, __ATOMIC_SEQ_CST);
    }
    return 0;
}
static int rw_unlock(XRw* r) {
    rw_ready(r);
    uint32_t s = __atomic_load_n(&r->state, __ATOMIC_RELAXED);
    if (s & kWriter) __atomic_store_n(&r->state, 0, __ATOMIC_RELEASE);
    else if (s) __atomic_sub_fetch(&r->state, 1, __ATOMIC_RELEASE);
    else return EPERM;
    if (__atomic_load_n(&r->waiters, __ATOMIC_SEQ_CST)) futex(&r->state, FUTEX_WAKE_PRIVATE, INT_MAX);
    return 0;
}
static int rwattr_init(long* a) { a[0] = 0x2DA8B3B4; return 0; }
static int rwattr_destroy(long* a) { a[0] = 0; return 0; }

// ---- thread attributes -----------------------------------------------------------------------------------------------
static int darwin_pthread_attr_init(pthread_attr_t* a) {
    if (!a) return EINVAL;
    memset(a, 0, 64);
    return pthread_attr_init(a);
}
static int darwin_pthread_attr_destroy(pthread_attr_t* a) {
    if (!a) return EINVAL;
    return pthread_attr_destroy(a);
}
static int darwin_pthread_attr_setdetachstate(pthread_attr_t* a, int dstate) {
    if (!a) return EINVAL;
    int linux_state;
    if (dstate == 1) linux_state = PTHREAD_CREATE_JOINABLE;        // Darwin 1 -> Linux 0
    else if (dstate == 2) linux_state = PTHREAD_CREATE_DETACHED;    // Darwin 2 -> Linux 1
    else return EINVAL;
    return pthread_attr_setdetachstate(a, linux_state);
}
static int darwin_pthread_attr_getdetachstate(const pthread_attr_t* a, int* dstate) {
    if (!a || !dstate) return EINVAL;
    int linux_state = 0;
    int r = pthread_attr_getdetachstate(a, &linux_state);
    if (r != 0) return r;
    *dstate = (linux_state == PTHREAD_CREATE_DETACHED) ? 2 : 1;
    return 0;
}
static int darwin_pthread_attr_setstacksize(pthread_attr_t* a, size_t stacksize) {
    if (!a) return EINVAL;
    return pthread_attr_setstacksize(a, stacksize);
}
static int darwin_pthread_attr_getstacksize(const pthread_attr_t* a, size_t* stacksize) {
    if (!a || !stacksize) return EINVAL;
    return pthread_attr_getstacksize(a, stacksize);
}
static int darwin_pthread_attr_setguardsize(pthread_attr_t* a, size_t guardsize) {
    if (!a) return EINVAL;
    return pthread_attr_setguardsize(a, guardsize);
}
static int darwin_pthread_attr_getguardsize(const pthread_attr_t* a, size_t* guardsize) {
    if (!a || !guardsize) return EINVAL;
    return pthread_attr_getguardsize(a, guardsize);
}

struct PtShim { const char* name; void* fn; };
static const PtShim kPt[] = {
    {"_pthread_mutex_init", (void*)&mutex_init}, {"_pthread_mutex_destroy", (void*)&mutex_destroy},
    {"_pthread_mutex_lock", (void*)&mutex_lock}, {"_pthread_mutex_trylock", (void*)&mutex_trylock},
    {"_pthread_mutex_unlock", (void*)&mutex_unlock}, {"_pthread_mutex_timedlock", (void*)&mutex_timedlock},
    {"_pthread_mutexattr_init", (void*)&mattr_init}, {"_pthread_mutexattr_destroy", (void*)&mattr_destroy},
    {"_pthread_mutexattr_settype", (void*)&mattr_settype}, {"_pthread_mutexattr_gettype", (void*)&mattr_gettype},
    {"_pthread_mutexattr_setprotocol", (void*)&mattr_nop}, {"_pthread_mutexattr_setpshared", (void*)&mattr_nop},
    {"_pthread_mutexattr_setprioceiling", (void*)&mattr_nop}, {"_pthread_mutexattr_setpolicy_np", (void*)&mattr_nop},
    {"_pthread_mutexattr_getprotocol", (void*)&mattr_get0}, {"_pthread_mutexattr_getpshared", (void*)&mattr_get0},
    {"_pthread_cond_init", (void*)&cond_init}, {"_pthread_cond_destroy", (void*)&cond_destroy},
    {"_pthread_cond_signal", (void*)&cond_signal}, {"_pthread_cond_broadcast", (void*)&cond_broadcast},
    {"_pthread_cond_wait", (void*)&cond_wait}, {"_pthread_cond_timedwait", (void*)&cond_timedwait},
    {"_pthread_cond_timedwait_relative_np", (void*)&cond_timedwait_relative},
    {"_pthread_condattr_init", (void*)&cattr_init}, {"_pthread_condattr_destroy", (void*)&cattr_destroy},
    {"_pthread_condattr_setpshared", (void*)&mattr_nop},
    {"_pthread_rwlock_init", (void*)&rw_init}, {"_pthread_rwlock_destroy", (void*)&rw_destroy},
    {"_pthread_rwlock_rdlock", (void*)&rw_rd}, {"_pthread_rwlock_tryrdlock", (void*)&rw_tryrd},
    {"_pthread_rwlock_wrlock", (void*)&rw_wr}, {"_pthread_rwlock_trywrlock", (void*)&rw_trywr},
    {"_pthread_rwlock_unlock", (void*)&rw_unlock},
    {"_pthread_rwlockattr_init", (void*)&rwattr_init}, {"_pthread_rwlockattr_destroy", (void*)&rwattr_destroy},
    {"_pthread_rwlockattr_setpshared", (void*)&mattr_nop},
    {"_pthread_attr_init", (void*)&darwin_pthread_attr_init},
    {"_pthread_attr_destroy", (void*)&darwin_pthread_attr_destroy},
    {"_pthread_attr_setdetachstate", (void*)&darwin_pthread_attr_setdetachstate},
    {"_pthread_attr_getdetachstate", (void*)&darwin_pthread_attr_getdetachstate},
    {"_pthread_attr_setstacksize", (void*)&darwin_pthread_attr_setstacksize},
    {"_pthread_attr_getstacksize", (void*)&darwin_pthread_attr_getstacksize},
    {"_pthread_attr_setguardsize", (void*)&darwin_pthread_attr_setguardsize},
    {"_pthread_attr_getguardsize", (void*)&darwin_pthread_attr_getguardsize},
};
void* darwin_pthread_lookup(const char* name) {
    for (const PtShim& s : kPt) if (!strcmp(s.name, name)) return s.fn;
    return nullptr;
}

} // namespace xef
