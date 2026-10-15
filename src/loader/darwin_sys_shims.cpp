// XEF-OSX — libSystem / dyld / Mach functions needed by real Darwin libraries (libobjc, libdispatch, ...).
// Looked up by darwin_hle_resolve_symbol() after the explicit HLE table.
#include "loader/darwin_hle.h"
#include "loader/macho_image.h"
#include "thunks/thunks.h"
#include "os/thread.h"
#include "os/signals.h"
#include "runtime/cpu_state.h"
#include "common/common.h"

#include <errno.h>
#include <malloc.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <linux/futex.h>
#include <atomic>
#include <vector>

namespace xef {

static MachImage* exe_image() { return dyld_images().empty() ? nullptr : dyld_images()[0]; }

// ---- dyld private API -------------------------------------------------------------------------
static bool sh_false() { return false; }
static uint64_t sh_zero() { return 0; }
static uint32_t sh_active_platform() { return 1; }   // PLATFORM_MACOS
static bool sh_sdk_at_least(uint64_t) { return true; }
static const void* sh_prog_header() { return exe_image() ? (const void*)(uintptr_t)exe_image()->header : nullptr; }
static const void* sh_header_containing(const void* addr) {
    MachImage* im = dyld_image_containing((uint64_t)(uintptr_t)addr);
    return im ? (const void*)(uintptr_t)im->header : nullptr;
}
static intptr_t sh_image_slide(const void* mh) {
    for (MachImage* im : dyld_images()) if (im->header == (uint64_t)(uintptr_t)mh) return (intptr_t)im->slide;
    return 0;
}
static bool sh_image_uuid(const void*, uint8_t*) { return false; }
static const void* sh_mach_execute_header() { return sh_prog_header(); }
static const void** sh_NSGetMachExecuteHeader() { static const void* p; p = sh_prog_header(); return &p; }

static MachImage* image_for_header(const void* mh) {
    for (MachImage* im : dyld_images()) if (im->header == (uint64_t)(uintptr_t)mh) return im;
    return nullptr;
}
static uint8_t* sh_getsectdatafromheader_64(const void* mh, const char* seg, const char* sect, uint64_t* size) {
    MachImage* im = image_for_header(mh);
    if (!im) return nullptr;
    for (const MachSection& s : im->sects)
        if (!strncmp(s.seg, seg, 16) && !strncmp(s.sect, sect, 16)) {
            if (size) *size = s.size;
            return (uint8_t*)(uintptr_t)s.addr;
        }
    return nullptr;
}
static uint8_t* sh_getsegmentdata(const void* mh, const char* seg, uint64_t* size) {
    MachImage* im = image_for_header(mh);
    if (!im) return nullptr;
    for (const MachSegment& s : im->segs)
        if (!strncmp(s.name, seg, 16)) {
            if (size) *size = s.size;
            return (uint8_t*)(uintptr_t)s.addr;
        }
    return nullptr;
}
struct DyldSectionInfo { void* mh; uint64_t size; };
static bool sh_lookup_section_info(const void* mh, const char* seg, const char* sect, void** addr, uint64_t* size) {
    uint8_t* p = sh_getsectdatafromheader_64(mh, seg, sect, size);
    if (addr) *addr = p;
    return p != nullptr;
}

// ---- Mach ---------------------------------------------------------------------------------------
static uint32_t g_mach_task_self = 0x103;
static int sh_mach_port_deallocate(uint32_t, uint32_t) { return 0; }
static int sh_vm_allocate(uint32_t, uint64_t* addr, uint64_t size, int flags) {
    int mf = MAP_PRIVATE | MAP_ANONYMOUS;
    void* want = (flags & 1) ? nullptr : (void*)(uintptr_t)*addr;   // VM_FLAGS_ANYWHERE = 1
    if (!(flags & 1)) mf |= MAP_FIXED;
    void* r = mmap(want, size, PROT_READ | PROT_WRITE, mf, -1, 0);
    if (r == MAP_FAILED) return 3;   // KERN_NO_SPACE
    *addr = (uint64_t)(uintptr_t)r;
    return 0;
}
static int sh_vm_deallocate(uint32_t, uint64_t addr, uint64_t size) { return munmap((void*)(uintptr_t)addr, size) ? 4 : 0; }
// vm_remap(task, &target, size, mask, flags, src_task, src, copy, &cur_prot, &max_prot, inherit):
// emulated as a copy (libobjc uses it to clone the block-trampoline code page).
static int sh_vm_remap(uint32_t, uint64_t* target, uint64_t size, uint64_t, int flags, uint32_t, uint64_t src,
                       int, int* cur, int* max, int) {
    int mf = MAP_PRIVATE | MAP_ANONYMOUS;
    void* want = (flags & 1) ? nullptr : (void*)(uintptr_t)*target;
    if (!(flags & 1)) mf |= MAP_FIXED;
    void* r = mmap(want, size, PROT_READ | PROT_WRITE | PROT_EXEC, mf, -1, 0);
    if (r == MAP_FAILED) return 3;
    memcpy(r, (void*)(uintptr_t)src, size);
    *target = (uint64_t)(uintptr_t)r;
    if (cur) *cur = 7;
    if (max) *max = 7;
    return 0;
}
static int sh_task_threads(uint32_t, void** list, uint32_t* count) { *list = nullptr; *count = 0; return 0; }
static int sh_thread_get_state(uint32_t, int, void*, uint32_t*) { return 5; }   // KERN_INVALID_ARGUMENT

// ---- malloc / pthread -----------------------------------------------------------------------------
// malloc_zone_t: reserved1, reserved2, size, malloc, calloc, valloc, free, realloc, destroy, zone_name, batch_malloc,
// batch_free, introspect, version, memalign, free_definite_size, pressure_relief, claimed_address
static size_t zn_size(void*, const void* p) { return p ? malloc_usable_size((void*)p) : 0; }
static void* zn_malloc(void*, size_t n) { return malloc(n); }
static void* zn_calloc(void*, size_t n, size_t m) { return calloc(n, m); }
static void* zn_valloc(void*, size_t n) { return aligned_alloc(4096, (n + 4095) & ~4095ull); }
static void zn_free(void*, void* p) { free(p); }
static void* zn_realloc(void*, void* p, size_t n) { return realloc(p, n); }
static void zn_destroy(void*) {}
static void* zn_memalign(void*, size_t a, size_t n) { return aligned_alloc(a, (n + a - 1) & ~(a - 1)); }
static void zn_free_definite_size(void*, void* p, size_t) { free(p); }
static size_t zn_pressure_relief(void*, size_t) { return 0; }
static int zn_claimed_address(void*, void* p) { return p != nullptr; }
static unsigned zn_batch_malloc(void*, size_t n, void** r, unsigned c) { unsigned i = 0; for (; i < c; i++) if (!(r[i] = malloc(n))) break; return i; }
static void zn_batch_free(void*, void** to_be_freed, unsigned c) { for (unsigned i = 0; i < c; i++) free(to_be_freed[i]); }
static void* sh_malloc_default_zone() {
    static uint64_t* zone;
    if (!zone) {
        zone = (uint64_t*)calloc(24, sizeof(uint64_t));
        auto stub = [](const char* name, void* fn) { return (uint64_t)darwin_hle_register_function(name, fn); };
        zone[2] = stub("_xef_zone_size", (void*)&zn_size);
        zone[3] = stub("_xef_zone_malloc", (void*)&zn_malloc);
        zone[4] = stub("_xef_zone_calloc", (void*)&zn_calloc);
        zone[5] = stub("_xef_zone_valloc", (void*)&zn_valloc);
        zone[6] = stub("_xef_zone_free", (void*)&zn_free);
        zone[7] = stub("_xef_zone_realloc", (void*)&zn_realloc);
        zone[8] = stub("_xef_zone_destroy", (void*)&zn_destroy);
        zone[9] = (uint64_t)"DefaultMallocZone";
        zone[10] = stub("_xef_zone_batch_malloc", (void*)&zn_batch_malloc);
        zone[11] = stub("_xef_zone_batch_free", (void*)&zn_batch_free);
        *(uint32_t*)&zone[13] = 13;                        // version
        zone[14] = stub("_xef_zone_memalign", (void*)&zn_memalign);
        zone[15] = stub("_xef_zone_free_definite_size", (void*)&zn_free_definite_size);
        zone[16] = stub("_xef_zone_pressure_relief", (void*)&zn_pressure_relief);
        zone[17] = stub("_xef_zone_claimed_address", (void*)&zn_claimed_address);
    }
    return zone;
}
static size_t sh_malloc_size(const void* p) { return p ? malloc_usable_size((void*)p) : 0; }
static void* sh_reallocf(void* p, size_t n) {
    void* r = realloc(p, n);
    if (!r && n) free(p);
    return r;
}
static void* sh_malloc_zone_malloc_with_options(void*, size_t align, size_t size, uint64_t options) {
    void* p = align > 16 ? aligned_alloc(align, (size + align - 1) & ~(align - 1)) : malloc(size);
    if (p && (options & 1)) memset(p, 0, size);   // MALLOC_ZONE_MALLOC_OPTION_CLEAR
    return p;
}
static void* sh_malloc_zone_malloc(void*, size_t n) { return malloc(n); }
static void* sh_malloc_zone_calloc(void*, size_t n, size_t m) { return calloc(n, m); }
static void* sh_malloc_zone_realloc(void*, void* p, size_t n) { return realloc(p, n); }
static void* sh_malloc_zone_valloc(void*, size_t n) { return aligned_alloc(4096, (n + 4095) & ~4095ull); }
static void* sh_malloc_zone_memalign(void*, size_t a, size_t n) { return aligned_alloc(a, (n + a - 1) & ~(a - 1)); }
static void sh_malloc_zone_free(void*, void* p) { free(p); }
static void* sh_malloc_zone_from_ptr(const void* p) { return p ? (void*)1 : nullptr; }
static size_t sh_malloc_good_size(size_t n) { return (n + 15) & ~15ull; }
static int sh_pthread_is_threaded_np() { return 1; }
static int sh_pthread_key_init_np(int, void (*)(void*)) { return 0; }

// ---- os_unfair_lock extras ------------------------------------------------------------------------------
static inline uint32_t self_tid() { static thread_local uint32_t t = (uint32_t)syscall(SYS_gettid); return t; }
static void lock_word(std::atomic<uint32_t>* w) {
    uint32_t me = self_tid(), exp = 0;
    while (!w->compare_exchange_weak(exp, me)) {
        if (exp == me) return;
        syscall(SYS_futex, w, FUTEX_WAIT_PRIVATE, exp, nullptr, nullptr, 0);
        exp = 0;
    }
}
static void sh_unfair_lock_with_options(std::atomic<uint32_t>* w, uint32_t) { lock_word(w); }
struct RecLock { std::atomic<uint32_t> owner; uint32_t count; };
static void sh_rec_lock(RecLock* l, uint32_t) {
    if (l->owner.load() == self_tid()) { l->count++; return; }
    lock_word(&l->owner);
    l->count = 1;
}
static bool sh_rec_trylock(RecLock* l) {
    uint32_t me = self_tid(), exp = 0;
    if (l->owner.load() == me) { l->count++; return true; }
    if (l->owner.compare_exchange_strong(exp, me)) { l->count = 1; return true; }
    return false;
}
static void sh_rec_unlock(RecLock* l) {
    if (--l->count) return;
    l->owner.store(0);
    syscall(SYS_futex, &l->owner, FUTEX_WAKE_PRIVATE, 1, nullptr, nullptr, 0);
}
static bool sh_rec_tryunlock(RecLock* l) {
    if (l->owner.load() != self_tid()) return false;
    sh_rec_unlock(l);
    return true;
}
static void sh_rec_unlock_forked_child(RecLock* l) { l->owner.store(0); l->count = 0; }

static const char* sh_queue_label(void*) { return "com.apple.main-thread"; }
static void sh_abort_with_reason(uint32_t, uint64_t, const char* msg, uint64_t) {
    fprintf(stderr, "abort_with_reason: %s\n", msg ? msg : "");
    abort();
}
static void sh_fault_with_payload() {}
static void sh_abort() {
    ThreadCtx* t = tls_thread;
    u64 lr = t ? t->st->x[30] : 0;
    MachImage* im = dyld_image_containing(lr);
    fprintf(stderr, "xef-osx: abort() called from %s+%#lx\n", im ? im->path.c_str() : "?", (unsigned long)(im ? lr - im->header : lr));
    fflush(stdout);
    abort();
}

// ---- OSAtomic / OSSpinLock (libplatform) ----------------------------------------------------------
#define OSA_ADD(name, T) static T sh_##name(T a, volatile T* p) { return __atomic_add_fetch(p, a, __ATOMIC_SEQ_CST); }
OSA_ADD(OSAtomicAdd32, int32_t) OSA_ADD(OSAtomicAdd64, int64_t)
static int32_t sh_OSAtomicIncrement32(volatile int32_t* p) { return __atomic_add_fetch(p, 1, __ATOMIC_SEQ_CST); }
static int32_t sh_OSAtomicDecrement32(volatile int32_t* p) { return __atomic_sub_fetch(p, 1, __ATOMIC_SEQ_CST); }
static int64_t sh_OSAtomicIncrement64(volatile int64_t* p) { return __atomic_add_fetch(p, 1, __ATOMIC_SEQ_CST); }
static int64_t sh_OSAtomicDecrement64(volatile int64_t* p) { return __atomic_sub_fetch(p, 1, __ATOMIC_SEQ_CST); }
static bool sh_OSAtomicCAS32(int32_t o, int32_t n, volatile int32_t* p) { return __atomic_compare_exchange_n(p, &o, n, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST); }
static bool sh_OSAtomicCAS64(int64_t o, int64_t n, volatile int64_t* p) { return __atomic_compare_exchange_n(p, &o, n, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST); }
static int32_t sh_OSAtomicOr32(uint32_t m, volatile uint32_t* p) { return __atomic_or_fetch(p, m, __ATOMIC_SEQ_CST); }
static int32_t sh_OSAtomicAnd32(uint32_t m, volatile uint32_t* p) { return __atomic_and_fetch(p, m, __ATOMIC_SEQ_CST); }
static int32_t sh_OSAtomicXor32(uint32_t m, volatile uint32_t* p) { return __atomic_xor_fetch(p, m, __ATOMIC_SEQ_CST); }
static int32_t sh_OSAtomicOr32Orig(uint32_t m, volatile uint32_t* p) { return __atomic_fetch_or(p, m, __ATOMIC_SEQ_CST); }
static int32_t sh_OSAtomicAnd32Orig(uint32_t m, volatile uint32_t* p) { return __atomic_fetch_and(p, m, __ATOMIC_SEQ_CST); }
static int32_t sh_OSAtomicXor32Orig(uint32_t m, volatile uint32_t* p) { return __atomic_fetch_xor(p, m, __ATOMIC_SEQ_CST); }
static bool sh_OSAtomicTestAndSet(uint32_t n, volatile void* a) {
    volatile uint8_t* p = (volatile uint8_t*)a + (n >> 3); uint8_t m = 0x80 >> (n & 7);
    return __atomic_fetch_or(p, m, __ATOMIC_SEQ_CST) & m;
}
static bool sh_OSAtomicTestAndClear(uint32_t n, volatile void* a) {
    volatile uint8_t* p = (volatile uint8_t*)a + (n >> 3); uint8_t m = 0x80 >> (n & 7);
    return __atomic_fetch_and(p, (uint8_t)~m, __ATOMIC_SEQ_CST) & m;
}
static void sh_OSMemoryBarrier() { __atomic_thread_fence(__ATOMIC_SEQ_CST); }
static void sh_OSSpinLockLock(volatile int32_t* l) {
    int32_t e = 0;
    while (!__atomic_compare_exchange_n(l, &e, 1, false, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED)) { e = 0; sched_yield(); }
}
static bool sh_OSSpinLockTry(volatile int32_t* l) { int32_t e = 0; return __atomic_compare_exchange_n(l, &e, 1, false, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED); }
static void sh_OSSpinLockUnlock(volatile int32_t* l) { __atomic_store_n(l, 0, __ATOMIC_RELEASE); }

struct SysShim { const char* name; void* fn; };
static const SysShim kSys[] = {
    {"_OSAtomicAdd32", (void*)&sh_OSAtomicAdd32},
    {"_OSAtomicAdd32Barrier", (void*)&sh_OSAtomicAdd32},
    {"_OSAtomicAdd64", (void*)&sh_OSAtomicAdd64},
    {"_OSAtomicAdd64Barrier", (void*)&sh_OSAtomicAdd64},
    {"_OSAtomicIncrement32", (void*)&sh_OSAtomicIncrement32},
    {"_OSAtomicIncrement32Barrier", (void*)&sh_OSAtomicIncrement32},
    {"_OSAtomicDecrement32", (void*)&sh_OSAtomicDecrement32},
    {"_OSAtomicDecrement32Barrier", (void*)&sh_OSAtomicDecrement32},
    {"_OSAtomicIncrement64", (void*)&sh_OSAtomicIncrement64},
    {"_OSAtomicIncrement64Barrier", (void*)&sh_OSAtomicIncrement64},
    {"_OSAtomicDecrement64", (void*)&sh_OSAtomicDecrement64},
    {"_OSAtomicDecrement64Barrier", (void*)&sh_OSAtomicDecrement64},
    {"_OSAtomicCompareAndSwap32", (void*)&sh_OSAtomicCAS32},
    {"_OSAtomicCompareAndSwap32Barrier", (void*)&sh_OSAtomicCAS32},
    {"_OSAtomicCompareAndSwapInt", (void*)&sh_OSAtomicCAS32},
    {"_OSAtomicCompareAndSwapIntBarrier", (void*)&sh_OSAtomicCAS32},
    {"_OSAtomicCompareAndSwap64", (void*)&sh_OSAtomicCAS64},
    {"_OSAtomicCompareAndSwap64Barrier", (void*)&sh_OSAtomicCAS64},
    {"_OSAtomicCompareAndSwapLong", (void*)&sh_OSAtomicCAS64},
    {"_OSAtomicCompareAndSwapLongBarrier", (void*)&sh_OSAtomicCAS64},
    {"_OSAtomicCompareAndSwapPtr", (void*)&sh_OSAtomicCAS64},
    {"_OSAtomicCompareAndSwapPtrBarrier", (void*)&sh_OSAtomicCAS64},
    {"_OSAtomicOr32", (void*)&sh_OSAtomicOr32},
    {"_OSAtomicOr32Barrier", (void*)&sh_OSAtomicOr32},
    {"_OSAtomicAnd32", (void*)&sh_OSAtomicAnd32},
    {"_OSAtomicAnd32Barrier", (void*)&sh_OSAtomicAnd32},
    {"_OSAtomicXor32", (void*)&sh_OSAtomicXor32},
    {"_OSAtomicXor32Barrier", (void*)&sh_OSAtomicXor32},
    {"_OSAtomicOr32Orig", (void*)&sh_OSAtomicOr32Orig},
    {"_OSAtomicOr32OrigBarrier", (void*)&sh_OSAtomicOr32Orig},
    {"_OSAtomicAnd32Orig", (void*)&sh_OSAtomicAnd32Orig},
    {"_OSAtomicAnd32OrigBarrier", (void*)&sh_OSAtomicAnd32Orig},
    {"_OSAtomicXor32Orig", (void*)&sh_OSAtomicXor32Orig},
    {"_OSAtomicXor32OrigBarrier", (void*)&sh_OSAtomicXor32Orig},
    {"_OSAtomicTestAndSet", (void*)&sh_OSAtomicTestAndSet},
    {"_OSAtomicTestAndSetBarrier", (void*)&sh_OSAtomicTestAndSet},
    {"_OSAtomicTestAndClear", (void*)&sh_OSAtomicTestAndClear},
    {"_OSAtomicTestAndClearBarrier", (void*)&sh_OSAtomicTestAndClear},
    {"_OSMemoryBarrier", (void*)&sh_OSMemoryBarrier},
    {"_OSSpinLockLock", (void*)&sh_OSSpinLockLock},
    {"_OSSpinLockTry", (void*)&sh_OSSpinLockTry},
    {"_OSSpinLockUnlock", (void*)&sh_OSSpinLockUnlock},
    {"_spin_lock_try", (void*)&sh_OSSpinLockTry},
    {"_dyld_program_sdk_at_least", (void*)&sh_sdk_at_least},
    {"_dyld_get_active_platform", (void*)&sh_active_platform},
    {"_dyld_image_header_containing_address", (void*)&sh_header_containing},
    {"_dyld_shared_cache_some_image_overridden", (void*)&sh_false},
    {"__dyld_get_prog_image_header", (void*)&sh_prog_header},
    {"__dyld_get_dlopen_image_header", (void*)&sh_prog_header},
    {"__dyld_get_image_slide", (void*)&sh_image_slide},
    {"__dyld_get_image_uuid", (void*)&sh_image_uuid},
    {"__dyld_is_memory_immutable", (void*)&sh_false},
    {"__dyld_get_shared_cache_range", (void*)&sh_zero},
    {"__dyld_for_each_objc_class", (void*)&sh_false},
    {"__dyld_for_each_objc_protocol", (void*)&sh_false},
    {"__dyld_for_objc_header_opt_ro", (void*)&sh_false},
    {"__dyld_for_objc_header_opt_rw", (void*)&sh_false},
    {"__dyld_get_objc_selector", (void*)&sh_zero},
    {"__dyld_objc_class_count", (void*)&sh_zero},
    {"__NSGetMachExecuteHeader", (void*)&sh_NSGetMachExecuteHeader},
    {"_getsectdatafromheader_64", (void*)&sh_getsectdatafromheader_64},
    {"_getsegmentdata", (void*)&sh_getsegmentdata},
    {"_vm_remap", (void*)&sh_vm_remap},
    {"_task_threads", (void*)&sh_task_threads},
    {"_thread_get_state", (void*)&sh_thread_get_state},
    {"_malloc_default_zone", (void*)&sh_malloc_default_zone},
    {"_malloc_zone_malloc_with_options", (void*)&sh_malloc_zone_malloc_with_options},
    {"_malloc_zone_malloc", (void*)&sh_malloc_zone_malloc}, {"_malloc_zone_calloc", (void*)&sh_malloc_zone_calloc},
    {"_malloc_zone_realloc", (void*)&sh_malloc_zone_realloc}, {"_malloc_zone_valloc", (void*)&sh_malloc_zone_valloc},
    {"_malloc_zone_memalign", (void*)&sh_malloc_zone_memalign}, {"_malloc_zone_free", (void*)&sh_malloc_zone_free},
    {"_malloc_zone_from_ptr", (void*)&sh_malloc_zone_from_ptr}, {"_malloc_good_size", (void*)&sh_malloc_good_size},
    {"_malloc_size", (void*)&sh_malloc_size},
    {"_reallocf", (void*)&sh_reallocf},
    {"_pthread_is_threaded_np", (void*)&sh_pthread_is_threaded_np},
    {"_pthread_key_init_np", (void*)&sh_pthread_key_init_np},
    {"_os_unfair_lock_lock_with_options", (void*)&sh_unfair_lock_with_options},
    {"_os_unfair_recursive_lock_lock_with_options", (void*)&sh_rec_lock},
    {"_os_unfair_recursive_lock_trylock", (void*)&sh_rec_trylock},
    {"_os_unfair_recursive_lock_unlock", (void*)&sh_rec_unlock},
    {"_os_unfair_recursive_lock_tryunlock4objc", (void*)&sh_rec_tryunlock},
    {"_os_unfair_recursive_lock_unlock_forked_child", (void*)&sh_rec_unlock_forked_child},
    {"_os_variant_allows_internal_security_policies", (void*)&sh_false},
    {"_os_variant_has_internal_diagnostics", (void*)&sh_false},
    {"_os_fault_with_payload", (void*)&sh_fault_with_payload},
    {"_abort", (void*)&sh_abort},
    {"_abort_with_reason", (void*)&sh_abort_with_reason},
    {"_dispatch_queue_get_label", (void*)&sh_queue_label},
};

void* darwin_sys_shim_lookup(const char* name) {
    for (const SysShim& s : kSys) if (!strcmp(s.name, name)) return s.fn;
    return nullptr;
}
void* darwin_sys_data_lookup(const char* name) {
    if (!strcmp(name, "_mach_task_self_")) return &g_mach_task_self;
    if (!strcmp(name, "___progname")) {
        static const char* progname;
        const char* p = strrchr(g_darwin_exe_path.c_str(), '/');
        progname = p ? p + 1 : g_darwin_exe_path.c_str();
        return &progname;
    }
    if (!strcmp(name, "_NXArgc")) return &g_darwin_argc;
    if (!strcmp(name, "_NXArgv")) return &g_darwin_argv;
    return nullptr;
}

} // namespace xef
