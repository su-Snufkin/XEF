// XEF-OSX — libproc (proc_pidinfo, proc_listpids, proc_name, proc_pidpath, ...) on top of Linux /proc.
// Structure layouts and flavor numbers are <sys/proc_info.h> (checked against the macOS SDK). A process run
// under XEF is reported as its guest program (name and path from the XEF command line), not as "xef".
#include "loader/darwin_hle.h"
#include "loader/elf_loader.h"
#include "os/thread.h"
#include "common/common.h"

#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include <algorithm>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace xef {

struct ProcBsdInfo {          // struct proc_bsdinfo (136)
    uint32_t pbi_flags, pbi_status, pbi_xstatus, pbi_pid, pbi_ppid, pbi_uid, pbi_gid, pbi_ruid, pbi_rgid, pbi_svuid,
        pbi_svgid, rfu_1;
    char pbi_comm[16], pbi_name[32];
    uint32_t pbi_nfiles, pbi_pgid, pbi_pjobc, e_tdev, e_tpgid;
    int32_t pbi_nice;
    uint64_t pbi_start_tvsec, pbi_start_tvusec;
};
struct ProcTaskInfo {         // struct proc_taskinfo (96)
    uint64_t pti_virtual_size, pti_resident_size, pti_total_user, pti_total_system, pti_threads_user, pti_threads_system;
    int32_t pti_policy, pti_faults, pti_pageins, pti_cow_faults, pti_messages_sent, pti_messages_received,
        pti_syscalls_mach, pti_syscalls_unix, pti_csw, pti_threadnum, pti_numrunning, pti_priority;
};
struct ProcBsdShortInfo {     // struct proc_bsdshortinfo (64)
    uint32_t pbsi_pid, pbsi_ppid, pbsi_pgid, pbsi_status;
    char pbsi_comm[16];
    uint32_t pbsi_flags, pbsi_uid, pbsi_gid, pbsi_ruid, pbsi_rgid, pbsi_svuid, pbsi_svgid, pbsi_rfu;
};
struct ProcFdInfo { int32_t proc_fd; uint32_t proc_fdtype; };
static_assert(sizeof(ProcBsdInfo) == 136 && offsetof(ProcBsdInfo, pbi_start_tvsec) == 120, "proc_bsdinfo");
static_assert(sizeof(ProcTaskInfo) == 96 && offsetof(ProcTaskInfo, pti_csw) == 80, "proc_taskinfo");
static_assert(sizeof(ProcBsdShortInfo) == 64 && offsetof(ProcBsdShortInfo, pbsi_flags) == 32, "proc_bsdshortinfo");
constexpr size_t kVnodeInfo = 152, kVnodeInfoPath = 1176, kVnodePathInfo = 2 * kVnodeInfoPath;

enum { kListFds = 1, kTaskAll = 2, kTbsd = 3, kTask = 4, kVnodePath = 9, kPath = 11, kShortBsd = 13 };
enum { kSRUN = 2, kSSTOP = 4, kSZOMB = 5 };
constexpr uint32_t kPProcSystem = 0x0001, kPCtty = 0x0002, kPLP64 = 0x0004;   // PROC_FLAG_*

static std::string read_file(const std::string& p) {
    std::ifstream f(p, std::ios::binary);
    std::stringstream ss;
    ss << f.rdbuf();
    return ss.str();
}
static std::string to_guest(const std::string& host) {
    if (!g_rootfs.empty() && host.rfind(g_rootfs, 0) == 0) {
        std::string g = host.substr(g_rootfs.size());
        return g.empty() || g[0] != '/' ? "/" + g : g;
    }
    return host;
}

// Executable of pid as the guest sees it. Under XEF the command line is `xef [opts] <program> args...`.
static std::string guest_exe(int pid) {
    if (pid == getpid()) return g_darwin_exe_path;
    char tmp[PATH_MAX];
    ssize_t n = readlink(("/proc/" + std::to_string(pid) + "/exe").c_str(), tmp, sizeof tmp - 1);
    if (n < 0) return {};
    std::string exe(tmp, (size_t)n);
    char self[PATH_MAX];
    ssize_t sn = readlink("/proc/self/exe", self, sizeof self - 1);
    if (sn > 0 && exe == std::string(self, (size_t)sn)) {
        std::string cl = read_file("/proc/" + std::to_string(pid) + "/cmdline");
        std::vector<std::string> av;
        for (size_t i = 0; i < cl.size();) { size_t e = cl.find('\0', i); if (e == std::string::npos) e = cl.size(); av.push_back(cl.substr(i, e - i)); i = e + 1; }
        for (size_t i = 1; i < av.size(); i++) {
            const std::string& a = av[i];
            if (a == "-L" || a == "--argv0" || a == "--tier2-threshold" || a == "--max-block") { i++; continue; }
            if (!a.empty() && a[0] == '-') continue;
            char rp[PATH_MAX];
            std::string p = realpath(a.c_str(), rp) ? std::string(rp) : a;
            return to_guest(p);
        }
    }
    return to_guest(exe);
}
static std::string base_name(const std::string& p) { size_t s = p.rfind('/'); return s == std::string::npos ? p : p.substr(s + 1); }

struct LinuxStat {
    bool ok = false;
    char state = 0;
    int ppid = 0, pgrp = 0, tty = 0, tpgid = 0, nice = 0, threads = 0;
    uint64_t utime = 0, stime = 0, minflt = 0, majflt = 0, start = 0, vsize = 0, rss = 0;
    uint32_t uid[3] = {}, gid[3] = {};
    uint64_t csw = 0;
};
static LinuxStat read_stat(int pid) {
    LinuxStat r;
    std::string base = "/proc/" + std::to_string(pid);
    std::string st = read_file(base + "/stat");
    size_t rp = st.rfind(')');
    if (st.empty() || rp == std::string::npos) return r;
    std::istringstream in(st.substr(rp + 2));
    long long v[50] = {};
    in >> r.state;
    for (int i = 0; i < 40 && in >> v[i]; i++) {}
    // after state: ppid pgrp session tty tpgid flags minflt cminflt majflt cmajflt utime stime cutime cstime prio nice
    // threads itreal starttime vsize rss
    r.ppid = (int)v[0]; r.pgrp = (int)v[1]; r.tty = (int)v[3]; r.tpgid = (int)v[4]; r.minflt = v[6]; r.majflt = v[8];
    r.utime = v[10]; r.stime = v[11]; r.nice = (int)v[15]; r.threads = (int)v[16]; r.start = v[18]; r.vsize = v[19];
    r.rss = v[20];
    std::istringstream ss(read_file(base + "/status"));
    std::string line;
    while (std::getline(ss, line)) {
        if (!line.compare(0, 4, "Uid:")) sscanf(line.c_str() + 4, "%u %u %u", &r.uid[0], &r.uid[1], &r.uid[2]);
        else if (!line.compare(0, 4, "Gid:")) sscanf(line.c_str() + 4, "%u %u %u", &r.gid[0], &r.gid[1], &r.gid[2]);
        else if (line.find("ctxt_switches:") != std::string::npos) r.csw += strtoull(line.c_str() + line.find(':') + 1, nullptr, 10);
    }
    r.ok = true;
    return r;
}
static uint32_t darwin_status(char s) {
    // macOS keeps p_stat at SRUN for running and sleeping processes (sleep is per-thread state)
    switch (s) { case 'T': case 't': return kSSTOP; case 'Z': case 'X': return kSZOMB; default: return kSRUN; }
}
static int count_fds(int pid) {
    DIR* d = opendir(("/proc/" + std::to_string(pid) + "/fd").c_str());
    if (!d) return 0;
    int n = 0;
    while (dirent* e = readdir(d)) if (e->d_name[0] != '.' && atoi(e->d_name) < 1000) n++;   // >= 1000: XEF's own
    closedir(d);
    return n;
}

static void fill_bsd(int pid, const LinuxStat& s, ProcBsdInfo* b) {
    memset(b, 0, sizeof *b);
    std::string name = base_name(guest_exe(pid));
    b->pbi_flags = kPLP64 | (s.tty ? kPCtty : 0);
    b->pbi_status = darwin_status(s.state);
    b->pbi_pid = (uint32_t)pid; b->pbi_ppid = (uint32_t)s.ppid;
    b->pbi_uid = s.uid[1]; b->pbi_ruid = s.uid[0]; b->pbi_svuid = s.uid[2];
    b->pbi_gid = s.gid[1]; b->pbi_rgid = s.gid[0]; b->pbi_svgid = s.gid[2];
    strncpy(b->pbi_comm, name.c_str(), sizeof b->pbi_comm - 1);
    strncpy(b->pbi_name, name.c_str(), sizeof b->pbi_name - 1);
    b->pbi_nfiles = (uint32_t)count_fds(pid);
    b->pbi_pgid = (uint32_t)s.pgrp;
    b->e_tdev = s.tty ? (uint32_t)s.tty : ~0u;   // NODEV when no controlling terminal
    b->e_tpgid = (uint32_t)s.tpgid;
    b->pbi_nice = s.nice;
    struct timespec now_rt, now_bt;
    clock_gettime(CLOCK_REALTIME, &now_rt);
    clock_gettime(CLOCK_BOOTTIME, &now_bt);
    long hz = sysconf(_SC_CLK_TCK);
    double boot = (double)now_rt.tv_sec + now_rt.tv_nsec / 1e9 - ((double)now_bt.tv_sec + now_bt.tv_nsec / 1e9);
    double start = boot + (double)s.start / (double)hz;
    b->pbi_start_tvsec = (uint64_t)start;
    b->pbi_start_tvusec = (uint64_t)((start - (double)(uint64_t)start) * 1e6);
}
static void fill_task(int pid, const LinuxStat& s, ProcTaskInfo* t) {
    memset(t, 0, sizeof *t);
    long hz = sysconf(_SC_CLK_TCK);
    t->pti_virtual_size = s.vsize;
    t->pti_resident_size = s.rss * (uint64_t)sysconf(_SC_PAGESIZE);
    t->pti_total_user = s.utime * 1000000000ull / (uint64_t)hz;
    t->pti_total_system = s.stime * 1000000000ull / (uint64_t)hz;
    t->pti_threads_user = t->pti_total_user;
    t->pti_threads_system = t->pti_total_system;
    t->pti_faults = (int32_t)(s.minflt + s.majflt);
    t->pti_pageins = (int32_t)s.majflt;
    t->pti_csw = (int32_t)s.csw;
    t->pti_threadnum = s.threads;
    int running = 0;
    if (DIR* d = opendir(("/proc/" + std::to_string(pid) + "/task").c_str())) {
        while (dirent* e = readdir(d)) {
            if (e->d_name[0] == '.') continue;
            if (pid == getpid() && !is_guest_tid(atoi(e->d_name))) continue;
            std::string st = read_file("/proc/" + std::to_string(pid) + "/task/" + e->d_name + "/stat");
            size_t rp = st.rfind(')');
            if (rp != std::string::npos && rp + 2 < st.size() && st[rp + 2] == 'R') running++;
        }
        closedir(d);
    }
    t->pti_numrunning = running;
    if (pid == getpid()) {   // XEF's own threads (tier 2 compiler, ...) are not the guest's
        int guest = 0;
        if (DIR* d = opendir("/proc/self/task")) {
            while (dirent* e = readdir(d)) if (e->d_name[0] != '.' && is_guest_tid(atoi(e->d_name))) guest++;
            closedir(d);
        }
        t->pti_threadnum = guest;
    }
    t->pti_priority = 31;   // BASEPRI_DEFAULT
}
static uint32_t fd_type(int pid, int fd) {
    char tmp[256];
    ssize_t n = readlink(("/proc/" + std::to_string(pid) + "/fd/" + std::to_string(fd)).c_str(), tmp, sizeof tmp - 1);
    if (n < 0) return 1;
    tmp[n] = 0;
    if (!strncmp(tmp, "socket:", 7)) return 2;
    if (!strncmp(tmp, "pipe:", 5)) return 6;
    if (!strcmp(tmp, "anon_inode:[eventpoll]")) return 5;   // our kqueues
    if (!strncmp(tmp, "/dev/shm/", 9)) return 3;
    return 1;
}

static int pp_listfds(int pid, void* buf, int size) {
    DIR* d = opendir(("/proc/" + std::to_string(pid) + "/fd").c_str());
    if (!d) { errno = ESRCH; return 0; }
    std::vector<ProcFdInfo> v;
    while (dirent* e = readdir(d)) {
        if (e->d_name[0] == '.') continue;
        int fd = atoi(e->d_name);
        if (fd >= 1000 || (pid == getpid() && fd == dirfd(d))) continue;
        v.push_back({fd, fd_type(pid, fd)});
    }
    closedir(d);
    std::sort(v.begin(), v.end(), [](const ProcFdInfo& a, const ProcFdInfo& b) { return a.proc_fd < b.proc_fd; });
    if (!buf) return (int)((v.size() + 20) * sizeof(ProcFdInfo));   // like the kernel: an estimate with headroom
    size_t n = std::min(v.size(), (size_t)size / sizeof(ProcFdInfo));
    memcpy(buf, v.data(), n * sizeof(ProcFdInfo));
    return (int)(n * sizeof(ProcFdInfo));
}

static int sh_proc_pidinfo(int pid, int flavor, uint64_t arg, void* buf, int size) {
    (void)arg;
    if (pid == 0) pid = getpid();
    if (flavor == kListFds) return pp_listfds(pid, buf, size);
    size_t need;
    switch (flavor) {
        case kTbsd: need = sizeof(ProcBsdInfo); break;
        case kTask: need = sizeof(ProcTaskInfo); break;
        case kTaskAll: need = sizeof(ProcBsdInfo) + sizeof(ProcTaskInfo); break;
        case kShortBsd: need = sizeof(ProcBsdShortInfo); break;
        case kVnodePath: need = kVnodePathInfo; break;
        case kPath: need = 1; break;
        default: errno = ENOTSUP; return 0;
    }
    if (!buf || (size_t)size < need) { errno = ENOMEM; return 0; }
    LinuxStat s = read_stat(pid);
    if (!s.ok) { errno = ESRCH; return 0; }
    switch (flavor) {
        case kTbsd: fill_bsd(pid, s, (ProcBsdInfo*)buf); return (int)need;
        case kTask: fill_task(pid, s, (ProcTaskInfo*)buf); return (int)need;
        case kTaskAll:
            fill_bsd(pid, s, (ProcBsdInfo*)buf);
            fill_task(pid, s, (ProcTaskInfo*)((char*)buf + sizeof(ProcBsdInfo)));
            return (int)need;
        case kShortBsd: {
            ProcBsdInfo b;
            fill_bsd(pid, s, &b);
            ProcBsdShortInfo* o = (ProcBsdShortInfo*)buf;
            memset(o, 0, sizeof *o);
            o->pbsi_pid = b.pbi_pid; o->pbsi_ppid = b.pbi_ppid; o->pbsi_pgid = b.pbi_pgid; o->pbsi_status = b.pbi_status;
            memcpy(o->pbsi_comm, b.pbi_comm, sizeof o->pbsi_comm);
            o->pbsi_flags = b.pbi_flags; o->pbsi_uid = b.pbi_uid; o->pbsi_gid = b.pbi_gid; o->pbsi_ruid = b.pbi_ruid;
            o->pbsi_rgid = b.pbi_rgid; o->pbsi_svuid = b.pbi_svuid; o->pbsi_svgid = b.pbi_svgid;
            return (int)need;
        }
        case kVnodePath: {
            // vnode_info is left zero; vip_path holds the current / root directory as the guest sees them
            memset(buf, 0, need);
            char tmp[PATH_MAX];
            const char* links[2] = {"cwd", "root"};
            for (int i = 0; i < 2; i++) {
                ssize_t n = readlink(("/proc/" + std::to_string(pid) + "/" + links[i]).c_str(), tmp, sizeof tmp - 1);
                std::string p = n > 0 ? to_guest(std::string(tmp, (size_t)n)) : std::string();
                if (i == 1) p.clear();   // no chroot: macOS leaves the root directory path empty
                strncpy((char*)buf + i * kVnodeInfoPath + kVnodeInfo, p.c_str(), 1023);
            }
            return (int)need;
        }
        case kPath: {
            std::string p = guest_exe(pid);
            if (p.empty()) { errno = ESRCH; return 0; }
            size_t n = std::min(p.size(), (size_t)size - 1);
            memcpy(buf, p.data(), n);
            ((char*)buf)[n] = 0;
            return (int)n;
        }
    }
    return 0;
}

static int sh_proc_pidpath(int pid, char* buf, uint32_t size) {
    if (!buf || size == 0) { errno = EINVAL; return 0; }
    std::string p = guest_exe(pid ? pid : getpid());
    if (p.empty()) { errno = ESRCH; return 0; }
    size_t n = std::min<size_t>(p.size(), size - 1);
    memcpy(buf, p.data(), n);
    buf[n] = 0;
    return (int)n;
}
static int sh_proc_name(int pid, char* buf, uint32_t size) {
    if (!buf || size == 0) return 0;
    LinuxStat s = read_stat(pid ? pid : getpid());
    if (!s.ok) { errno = ESRCH; return 0; }
    std::string n = base_name(guest_exe(pid ? pid : getpid())).substr(0, 31);
    size_t k = std::min<size_t>(n.size(), size - 1);
    memcpy(buf, n.data(), k);
    buf[k] = 0;
    return (int)k;
}

// proc_listpids(type, typeinfo, buffer, size): PROC_ALL_PIDS 1, PGRP 2, TTY 3, UID 4, RUID 5, PPID 6; returns bytes
static std::vector<int32_t> list_pids(uint32_t type, uint32_t info) {
    std::vector<int32_t> v;
    DIR* d = opendir("/proc");
    if (!d) return v;
    while (dirent* e = readdir(d)) {
        if (e->d_name[0] < '1' || e->d_name[0] > '9') continue;
        int pid = atoi(e->d_name);
        if (type != 1) {
            LinuxStat s = read_stat(pid);
            if (!s.ok) continue;
            bool keep = (type == 2 && (uint32_t)s.pgrp == info) || (type == 3 && (uint32_t)s.tty == info) ||
                        (type == 4 && s.uid[1] == info) || (type == 5 && s.uid[0] == info) || (type == 6 && (uint32_t)s.ppid == info);
            if (!keep) continue;
        }
        v.push_back(pid);
    }
    closedir(d);
    return v;
}
static int sh_proc_listpids(uint32_t type, uint32_t info, void* buf, int size) {
    if (type < 1 || type > 6) { errno = EINVAL; return -1; }
    std::vector<int32_t> v = list_pids(type, info);
    if (!buf) return (int)((v.size() + 32) * 4);
    size_t n = std::min(v.size(), (size_t)size / 4);
    memcpy(buf, v.data(), n * 4);
    return (int)(n * 4);
}
static int sh_proc_listallpids(void* buf, int size) {   // returns a count
    std::vector<int32_t> v = list_pids(1, 0);
    if (!buf) return (int)v.size() + 32;
    size_t n = std::min(v.size(), (size_t)size / 4);
    memcpy(buf, v.data(), n * 4);
    return (int)n;
}
static int sh_proc_listchildpids(int ppid, void* buf, int size) {
    std::vector<int32_t> v = list_pids(6, (uint32_t)ppid);
    if (!buf) return (int)v.size() + 32;
    size_t n = std::min(v.size(), (size_t)size / 4);
    memcpy(buf, v.data(), n * 4);
    return (int)n;
}

void* darwin_proc_lookup(const char* name) {
    struct E { const char* n; void* f; };
    static const E k[] = {
        {"_proc_pidinfo", (void*)&sh_proc_pidinfo}, {"_proc_pidpath", (void*)&sh_proc_pidpath},
        {"_proc_name", (void*)&sh_proc_name}, {"_proc_listpids", (void*)&sh_proc_listpids},
        {"_proc_listallpids", (void*)&sh_proc_listallpids}, {"_proc_listchildpids", (void*)&sh_proc_listchildpids},
    };
    for (const E& e : k) if (!strcmp(e.n, name)) return e.f;
    return nullptr;
}

}  // namespace xef
