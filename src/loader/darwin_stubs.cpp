// XEF-OSX — small libSystem pieces CoreFoundation/Foundation need that have no Linux counterpart
// (uuid, sysctl, xpc/asl/bootstrap placeholders, misc BSD helpers).
#include "loader/darwin_hle.h"
#include "loader/macho_image.h"
#include "common/common.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/random.h>
#include <sys/sysinfo.h>
#include <sys/utsname.h>
#include <time.h>
#include <unistd.h>
#include <vector>
#include <string>
#include <pthread.h>

namespace xef {

bool darwin_sysctl_impl(const int* mib, int namelen, void* oldp, size_t* oldlenp, void* newp, size_t newlen);
int darwin_errno_from_linux(int e);

// ---- uuid ---------------------------------------------------------------------------------------
typedef unsigned char uuid_t_[16];
static void st_uuid_generate_random(uuid_t_ out) {
    getrandom(out, 16, 0);
    out[6] = (out[6] & 0x0F) | 0x40;
    out[8] = (out[8] & 0x3F) | 0x80;
}
static void st_uuid_clear(uuid_t_ u) { memset(u, 0, 16); }
static void st_uuid_copy(uuid_t_ d, const uuid_t_ s) { memcpy(d, s, 16); }
static int st_uuid_compare(const uuid_t_ a, const uuid_t_ b) { return memcmp(a, b, 16); }
static int st_uuid_is_null(const uuid_t_ u) { for (int i = 0; i < 16; i++) if (u[i]) return 0; return 1; }
static void st_uuid_unparse(const uuid_t_ u, char* out) {
    snprintf(out, 37, "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
             u[0], u[1], u[2], u[3], u[4], u[5], u[6], u[7], u[8], u[9], u[10], u[11], u[12], u[13], u[14], u[15]);
}
static void st_uuid_unparse_upper(const uuid_t_ u, char* out) {
    st_uuid_unparse(u, out);
    for (char* p = out; *p; p++) if (*p >= 'a' && *p <= 'f') *p -= 32;
}
static int st_uuid_parse(const char* s, uuid_t_ out) {
    unsigned b[16];
    if (sscanf(s, "%2x%2x%2x%2x-%2x%2x-%2x%2x-%2x%2x-%2x%2x%2x%2x%2x%2x", &b[0], &b[1], &b[2], &b[3], &b[4], &b[5], &b[6], &b[7],
               &b[8], &b[9], &b[10], &b[11], &b[12], &b[13], &b[14], &b[15]) != 16) return -1;
    for (int i = 0; i < 16; i++) out[i] = (unsigned char)b[i];
    return 0;
}

// ---- sysctl -------------------------------------------------------------------------------------------
static int st_sysctl(const int* mib, unsigned namelen, void* oldp, size_t* oldlenp, void* newp, size_t newlen) {
    if (darwin_sysctl_impl(mib, (int)namelen, oldp, oldlenp, newp, newlen)) return 0;
    errno = ENOENT;
    return -1;
}
struct SysctlName { const char* name; int mib[4]; int n; };
static const SysctlName kNames[] = {
    {"hw.ncpu", {6, 3}, 2}, {"hw.availcpu", {6, 25}, 2}, {"hw.machine", {6, 1}, 2}, {"hw.model", {6, 2}, 2},
    {"hw.pagesize", {6, 7}, 2}, {"hw.memsize", {6, 24}, 2}, {"hw.physmem", {6, 5}, 2}, {"hw.usermem", {6, 6}, 2},
    {"hw.byteorder", {6, 4}, 2}, {"kern.ostype", {1, 1}, 2}, {"kern.osrelease", {1, 2}, 2}, {"kern.osrevision", {1, 3}, 2},
    {"kern.version", {1, 4}, 2}, {"kern.hostname", {1, 10}, 2}, {"kern.osversion", {1, 65}, 2}, {"kern.argmax", {1, 8}, 2},
};
static int st_sysctlbyname(const char* name, void* oldp, size_t* oldlenp, void* newp, size_t newlen) {
    for (const SysctlName& n : kNames)
        if (!strcmp(n.name, name)) return st_sysctl(n.mib, n.n, oldp, oldlenp, newp, newlen);
    // names without a numeric MIB
    auto put32 = [&](uint32_t v) { if (oldlenp) { if (oldp && *oldlenp >= 4) memcpy(oldp, &v, 4); *oldlenp = 4; } return 0; };
    auto put64 = [&](uint64_t v) { if (oldlenp) { if (oldp && *oldlenp >= 8) memcpy(oldp, &v, 8); *oldlenp = 8; } return 0; };
    long ncpu = sysconf(_SC_NPROCESSORS_ONLN);
    if (!strcmp(name, "hw.logicalcpu") || !strcmp(name, "hw.logicalcpu_max") || !strcmp(name, "hw.physicalcpu") ||
        !strcmp(name, "hw.physicalcpu_max") || !strcmp(name, "hw.activecpu")) return put32((uint32_t)ncpu);
    if (!strcmp(name, "hw.cpufrequency") || !strcmp(name, "hw.cpufrequency_max")) return put64(3200000000ull);
    if (!strcmp(name, "hw.cachelinesize")) return put64(128);
    if (!strcmp(name, "hw.l1dcachesize")) return put64(65536);
    if (!strcmp(name, "hw.l2cachesize")) return put64(4194304);
    if (!strcmp(name, "hw.optional.arm64")) return put32(1);
    if (!strncmp(name, "hw.optional.", 12)) return put32(1);
    if (!strcmp(name, "hw.targettype")) { const char s[] = "J314sAP"; if (oldlenp) { if (oldp && *oldlenp >= sizeof s) memcpy(oldp, s, sizeof s); *oldlenp = sizeof s; } return 0; }
    if (!strcmp(name, "machdep.cpu.brand_string")) { const char s[] = "Apple M1"; if (oldlenp) { if (oldp && *oldlenp >= sizeof s) memcpy(oldp, s, sizeof s); *oldlenp = sizeof s; } return 0; }
    if (!strcmp(name, "kern.boottime")) {
        struct sysinfo si; sysinfo(&si);
        struct { int64_t sec; int32_t usec; int32_t pad; } bt = { (int64_t)time(nullptr) - si.uptime, 0, 0 };
        if (oldlenp) { if (oldp && *oldlenp >= sizeof bt) memcpy(oldp, &bt, sizeof bt); *oldlenp = sizeof bt; }
        return 0;
    }
    if (!strcmp(name, "kern.osproductversion")) { const char s[] = "26.0"; if (oldlenp) { if (oldp && *oldlenp >= sizeof s) memcpy(oldp, s, sizeof s); *oldlenp = sizeof s; } return 0; }
    if (!strcmp(name, "kern.proc_translated") || !strcmp(name, "sysctl.proc_translated")) return put32(0);
    errno = ENOENT;
    return -1;
}
static int st_sysctlnametomib(const char* name, int* mibp, size_t* sizep) {
    for (const SysctlName& n : kNames)
        if (!strcmp(n.name, name)) {
            if (*sizep < (size_t)n.n) { errno = ENOMEM; return -1; }
            memcpy(mibp, n.mib, n.n * sizeof(int)); *sizep = n.n; return 0;
        }
    errno = ENOENT;
    return -1;
}

// ---- misc ---------------------------------------------------------------------------------------------
static int st_flsl(long v) { return v ? 64 - __builtin_clzl((unsigned long)v) : 0; }
static int st_fls(int v) { return v ? 32 - __builtin_clz((unsigned)v) : 0; }
static int st_gethostuuid(unsigned char* uuid, const struct timespec*) { memset(uuid, 0x42, 16); uuid[6] = 0x40; uuid[8] = 0x80; return 0; }
struct SincosRet { double s, c; };
static SincosRet st_sincos_stret(double x) { return {__builtin_sin(x), __builtin_cos(x)}; }
static int st_dlopen_preflight(const char*) { return 1; }
static int st_zero() { return 0; }
static int st_one() { return 1; }
static void* st_null() { return nullptr; }
static int st_pthread_main_np() { return getpid() == (pid_t)syscall(186 /*gettid*/) ? 1 : 0; }
static int st_pthread_getugid_np(uint32_t* u, uint32_t* g) { *u = geteuid(); *g = getegid(); return 0; }
static const char* st_mach_error_string(int e) { return e == 0 ? "(os/kern) successful" : "(os/kern) failure"; }
static int st_kern_failure() { return 5; }                 // KERN_FAILURE
static int st_bootstrap_unknown() { return 1102; }          // BOOTSTRAP_UNKNOWN_SERVICE
static const char* st_bootstrap_strerror(int) { return "unknown bootstrap error"; }
static unsigned st_qos_class_self() { return 0x15; }       // QOS_CLASS_DEFAULT
static void st_noop() {}
static int st_fprintf_l_dummy() { return 0; }
static const char* st_getprogname() {
    static std::string n;
    if (n.empty()) { const char* p = strrchr(g_darwin_exe_path.c_str(), '/'); n = p ? p + 1 : g_darwin_exe_path; }
    return n.c_str();
}
static void* st_malloc_create_zone(size_t, unsigned) { return (void*)1; }
static pthread_t g_main_pthread = pthread_self();
static uint64_t st_pthread_main_thread_np() { return (uint64_t)g_main_pthread; }
static void* st_getsectbynamefromheader_64(const void* mh, const char* seg, const char* sect) {
    // returns a pointer to a Darwin `struct section_64`
    for (MachImage* im : dyld_images())
        if (im->header == (uint64_t)(uintptr_t)mh)
            for (const MachSection& s : im->sects)
                if (!strncmp(s.seg, seg, 16) && !strncmp(s.sect, sect, 16)) {
                    struct Sec { char sectname[16], segname[16]; uint64_t addr, size; uint32_t offset, align, reloff, nreloc, flags, r1, r2, r3; };
                    Sec* r = new Sec(); memset(r, 0, sizeof *r);
                    memcpy(r->sectname, s.sect, 16); memcpy(r->segname, s.seg, 16);
                    r->addr = s.addr - im->slide; r->size = s.size;
                    return r;
                }
    return nullptr;
}
static void* st_getsegbyname(const char* seg) {
    MachImage* im = dyld_images().empty() ? nullptr : dyld_images()[0];
    if (!im) return nullptr;
    for (const MachSegment& s : im->segs)
        if (!strncmp(s.name, seg, 16)) {
            struct Seg { uint32_t cmd, cmdsize; char segname[16]; uint64_t vmaddr, vmsize, fileoff, filesize; uint32_t maxprot, initprot, nsects, flags; };
            Seg* r = new Seg(); memset(r, 0, sizeof *r);
            memcpy(r->segname, s.name, 16); r->vmaddr = s.addr - im->slide; r->vmsize = s.size;
            return r;
        }
    return nullptr;
}

struct StubEntry { const char* name; void* fn; };
static const StubEntry kStubs[] = {
    {"_uuid_generate_random", (void*)&st_uuid_generate_random}, {"_uuid_generate", (void*)&st_uuid_generate_random},
    {"_uuid_generate_time", (void*)&st_uuid_generate_random}, {"_uuid_clear", (void*)&st_uuid_clear},
    {"_uuid_copy", (void*)&st_uuid_copy}, {"_uuid_compare", (void*)&st_uuid_compare}, {"_uuid_is_null", (void*)&st_uuid_is_null},
    {"_uuid_unparse", (void*)&st_uuid_unparse}, {"_uuid_unparse_lower", (void*)&st_uuid_unparse},
    {"_uuid_unparse_upper", (void*)&st_uuid_unparse_upper}, {"_uuid_parse", (void*)&st_uuid_parse},
    {"_sysctl", (void*)&st_sysctl}, {"_sysctlbyname", (void*)&st_sysctlbyname}, {"_sysctlnametomib", (void*)&st_sysctlnametomib},
    {"_flsl", (void*)&st_flsl}, {"_fls", (void*)&st_fls}, {"_gethostuuid", (void*)&st_gethostuuid},
    {"___sincos_stret", (void*)&st_sincos_stret}, {"_dlopen_preflight", (void*)&st_dlopen_preflight},
    {"_pthread_main_np", (void*)&st_pthread_main_np}, {"_pthread_getugid_np", (void*)&st_pthread_getugid_np},
    {"_mach_error_string", (void*)&st_mach_error_string}, {"_bootstrap_strerror", (void*)&st_bootstrap_strerror},
    {"_bootstrap_look_up2", (void*)&st_bootstrap_unknown}, {"_bootstrap_look_up", (void*)&st_bootstrap_unknown},
    {"_bootstrap_check_in", (void*)&st_bootstrap_unknown}, {"_bootstrap_register2", (void*)&st_bootstrap_unknown},
    {"_bootstrap_register", (void*)&st_bootstrap_unknown},
    {"_qos_class_self", (void*)&st_qos_class_self}, {"_qos_class_main", (void*)&st_qos_class_self},
    {"_pthread_attr_set_qos_class_np", (void*)&st_zero},
    // asl (system log): accepted and dropped
    {"_asl_open", (void*)&st_null}, {"_asl_close", (void*)&st_noop}, {"_asl_new", (void*)&st_null}, {"_asl_free", (void*)&st_noop},
    {"_asl_set", (void*)&st_zero}, {"_asl_send", (void*)&st_zero}, {"_asl_log", (void*)&st_zero}, {"_asl_set_filter", (void*)&st_zero},
    // xpc: no services
    {"_xpc_release", (void*)&st_noop}, {"_xpc_get_type", (void*)&st_null}, {"_xpc_null_create", (void*)&st_null},
    {"_xpc_bool_create", (void*)&st_null}, {"_xpc_bool_get_value", (void*)&st_zero}, {"_xpc_int64_create", (void*)&st_null},
    {"_xpc_int64_get_value", (void*)&st_zero}, {"_xpc_uint64_get_value", (void*)&st_zero}, {"_xpc_string_create", (void*)&st_null},
    {"_xpc_string_get_string_ptr", (void*)&st_null}, {"_xpc_data_create", (void*)&st_null}, {"_xpc_data_get_bytes_ptr", (void*)&st_null},
    {"_xpc_data_get_length", (void*)&st_zero}, {"_xpc_array_create", (void*)&st_null}, {"_xpc_array_get_count", (void*)&st_zero},
    {"_xpc_array_apply", (void*)&st_zero}, {"_xpc_dictionary_create", (void*)&st_null}, {"_xpc_dictionary_get_count", (void*)&st_zero},
    {"_xpc_dictionary_apply", (void*)&st_zero}, {"_os_release", (void*)&st_noop},
    // voucher / mach leftovers that always "fail"
    {"_voucher_copy", (void*)&st_null}, {"_voucher_mach_msg_adopt", (void*)&st_null}, {"_voucher_mach_msg_revert", (void*)&st_noop},
    {"_task_get_special_port", (void*)&st_kern_failure}, {"_thread_suspend", (void*)&st_kern_failure}, {"_thread_resume", (void*)&st_kern_failure},
    {"_vm_purgable_control", (void*)&st_kern_failure}, {"_mach_make_memory_entry_64", (void*)&st_kern_failure},
    {"_mach_vm_region", (void*)&st_kern_failure}, {"_mach_vm_map", (void*)&st_kern_failure},
    {"_mach_port_space_info", (void*)&st_kern_failure}, {"_mach_port_get_set_status", (void*)&st_kern_failure},
    {"___darwin_check_fd_set_overflow", (void*)&st_one},
    {"_NSStartSearchPathEnumeration", (void*)&st_zero}, {"_NSGetNextSearchPathEnumeration", (void*)&st_zero},
    {"_NXGetLocalArchInfo", (void*)&st_null}, {"_NXFindBestFatArch", (void*)&st_null},
};

static void st_noop2() {}
static int st_zero2() { return 0; }
static clockid_t darwin_clock_id(int id) {
    switch (id) {
        case 0: return CLOCK_REALTIME;
        case 4: case 5: case 8: case 9: return CLOCK_MONOTONIC_RAW;
        case 6: return CLOCK_MONOTONIC;
        case 12: return CLOCK_PROCESS_CPUTIME_ID;
        case 16: return CLOCK_THREAD_CPUTIME_ID;
        default: return (clockid_t)-1;
    }
}
static int st_clock_gettime(int id, struct timespec* ts) {
    clockid_t c = darwin_clock_id(id);
    if (c == (clockid_t)-1) { errno = EINVAL; return -1; }
    return clock_gettime(c, ts);
}
static int st_clock_getres(int id, struct timespec* ts) {
    clockid_t c = darwin_clock_id(id);
    if (c == (clockid_t)-1) { errno = EINVAL; return -1; }
    return clock_getres(c, ts);
}
static uint64_t st_clock_gettime_nsec_np(int id) {
    struct timespec ts;
    if (st_clock_gettime(id, &ts)) return 0;
    return (uint64_t)ts.tv_sec * 1000000000ull + ts.tv_nsec;
}
static void* st_null2() { return nullptr; }
static void st_memset_pattern4(void* b, const void* p, size_t n) {
    uint8_t* d = (uint8_t*)b; const uint8_t* s = (const uint8_t*)p;
    for (size_t i = 0; i < n; i++) d[i] = s[i & 3];
}
static int st_vm_copy(uint32_t, uint64_t src, uint64_t n, uint64_t dst) { memmove((void*)(uintptr_t)dst, (void*)(uintptr_t)src, n); return 0; }
static int st_task_info(uint32_t, int, void* info, uint32_t* cnt) { if (info && cnt) memset(info, 0, *cnt * 4); return 0; }
static int st_mb_cur_max() { return 1; }
static const char* st_querylocale(int, void*) { return "C"; }
static void* st_duplocale(void*) { return (void*)1; }
static const StubEntry kStubs2[] = {
    {"____mb_cur_max", (void*)&st_mb_cur_max}, {"_querylocale", (void*)&st_querylocale}, {"_duplocale", (void*)&st_duplocale},
    {"_clock_gettime", (void*)&st_clock_gettime}, {"_clock_getres", (void*)&st_clock_getres},
    {"_clock_gettime_nsec_np", (void*)&st_clock_gettime_nsec_np},
    {"_getprogname", (void*)&st_getprogname}, {"_malloc_create_zone", (void*)&st_malloc_create_zone},
    {"_malloc_destroy_zone", (void*)&st_noop2}, {"_malloc_set_zone_name", (void*)&st_noop2}, {"_malloc_get_zone_name", (void*)&st_null2},
    {"_pthread_main_thread_np", (void*)&st_pthread_main_thread_np}, {"_getsectbynamefromheader_64", (void*)&st_getsectbynamefromheader_64},
    {"_getsegbyname", (void*)&st_getsegbyname}, {"_memset_pattern4", (void*)&st_memset_pattern4}, {"_vm_copy", (void*)&st_vm_copy},
    {"_task_info", (void*)&st_task_info},
    {"_xpc_retain", (void*)&st_null2}, {"_xpc_copy_description", (void*)&st_null2}, {"_xpc_array_append_value", (void*)&st_noop2},
    {"_xpc_connection_create_mach_service", (void*)&st_null2}, {"_xpc_connection_resume", (void*)&st_noop2},
    {"_xpc_connection_send_message", (void*)&st_noop2}, {"_xpc_connection_send_message_with_reply", (void*)&st_noop2},
    {"_xpc_connection_send_message_with_reply_sync", (void*)&st_null2}, {"_xpc_connection_set_event_handler", (void*)&st_noop2},
    {"_xpc_dictionary_create_reply", (void*)&st_null2}, {"_xpc_dictionary_get_string", (void*)&st_null2},
    {"_xpc_dictionary_get_uint64", (void*)&st_zero2}, {"_xpc_dictionary_get_value", (void*)&st_null2},
    {"_xpc_dictionary_set_string", (void*)&st_noop2}, {"_xpc_dictionary_set_uint64", (void*)&st_noop2}, {"_xpc_dictionary_set_value", (void*)&st_noop2},
};

void* darwin_stub_lookup(const char* name) {
    for (const StubEntry& e : kStubs2) if (!strcmp(e.name, name)) return e.fn;
    for (const StubEntry& e : kStubs) if (!strcmp(e.name, name)) return e.fn;
    return nullptr;
}

// data symbols CoreFoundation / xpc expect
void* darwin_stub_data_lookup(const char* name) {
    static char xpc_types[16][64];
    static int n = 0;
    static std::vector<std::pair<std::string, void*>> made;
    if (!strcmp(name, "___mb_cur_max")) { static int v = 1; return &v; }
    if (!strcmp(name, "___mb_sb_limit")) { static int v = 128; return &v; }
    if (!strcmp(name, "_sys_nerr")) { static int v = 107; return &v; }
    if (!strcmp(name, "_vm_page_size")) { static uint64_t ps = 4096; return &ps; }
    if (!strncmp(name, "__xpc_type_", 11)) {
        for (auto& p : made) if (p.first == name) return p.second;
        void* d = xpc_types[n++ % 16];
        made.push_back({name, d});
        return d;
    }
    return nullptr;
}

} // namespace xef
