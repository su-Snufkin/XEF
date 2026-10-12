#include "loader/elf_loader.h"

#include <elf.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include <vector>

namespace xef {

std::string g_rootfs;

std::string resolve_guest_path(const char* path) {
    if (!path || path[0] != '/' || g_rootfs.empty()) return path ? path : "";
    std::string p = g_rootfs + path;
    struct stat st;
    if (lstat(p.c_str(), &st) == 0) return p;
    return path;
}

// HWCAP bits (arch/arm64/include/uapi/asm/hwcap.h)
enum : u64 {
    HWCAP_FP = 1 << 0, HWCAP_ASIMD = 1 << 1, HWCAP_EVTSTRM = 1 << 2, HWCAP_AES = 1 << 3,
    HWCAP_PMULL = 1 << 4, HWCAP_SHA1 = 1 << 5, HWCAP_SHA2 = 1 << 6, HWCAP_CRC32 = 1 << 7,
    HWCAP_ATOMICS = 1 << 8, HWCAP_FPHP = 1 << 9, HWCAP_ASIMDHP = 1 << 10, HWCAP_CPUID = 1 << 11,
};

// Advertise only what the frontend implements end to end (FP16 arithmetic is still missing).
u64 guest_hwcap() {
    return HWCAP_FP | HWCAP_ASIMD | HWCAP_AES | HWCAP_PMULL | HWCAP_SHA1 | HWCAP_SHA2 | HWCAP_CRC32 |
           HWCAP_ATOMICS;
}
u64 guest_hwcap2() { return 0; }

static constexpr u64 kPage = 4096;
static constexpr GuestAddr kPieBase = 0x5500000000ull;

static bool read_full(int fd, void* buf, size_t n, off_t off) {
    return pread(fd, buf, n, off) == (ssize_t)n;
}

// Maps one ELF object. Returns load bias.
static bool map_object(const char* host_path, GuestAddr want_base, Elf64_Ehdr& eh, std::vector<Elf64_Phdr>& ph,
                       GuestAddr& bias_out, GuestAddr& lo_out, GuestAddr& hi_out) {
    int fd = open(host_path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return false;
    if (!read_full(fd, &eh, sizeof eh, 0) || memcmp(eh.e_ident, ELFMAG, SELFMAG) != 0 ||
        eh.e_ident[EI_CLASS] != ELFCLASS64 || eh.e_machine != EM_AARCH64) {
        close(fd);
        fatal("%s: not an AArch64 ELF64 binary", host_path);
    }
    ph.resize(eh.e_phnum);
    if (!read_full(fd, ph.data(), sizeof(Elf64_Phdr) * eh.e_phnum, eh.e_phoff)) { close(fd); return false; }
    GuestAddr lo = ~0ull, hi = 0;
    u64 max_align = kPage;
    for (auto& p : ph) {
        if (p.p_type != PT_LOAD) continue;
        lo = std::min<GuestAddr>(lo, align_down<u64>(p.p_vaddr, kPage));
        hi = std::max<GuestAddr>(hi, align_up<u64>(p.p_vaddr + p.p_memsz, kPage));
        if (p.p_align > max_align) max_align = p.p_align;
    }
    if (lo == ~0ull) { close(fd); fatal("%s: no PT_LOAD segments", host_path); }
    GuestAddr bias = 0;
    if (eh.e_type == ET_DYN) {
        // reserve the whole range, aligned to the largest segment alignment (16K/64K guests)
        u64 span = hi - lo;
        void* hint = want_base ? (void*)want_base : nullptr;
        int flags = MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE;
        if (want_base) flags |= MAP_FIXED_NOREPLACE;
        void* r = mmap(hint, span + max_align, PROT_NONE, flags, -1, 0);
        if (r == MAP_FAILED && want_base) r = mmap(nullptr, span + max_align, PROT_NONE, flags & ~MAP_FIXED_NOREPLACE, -1, 0);
        if (r == MAP_FAILED) { close(fd); fatal("%s: cannot reserve address space", host_path); }
        GuestAddr start = align_up<u64>((u64)r, max_align);
        // trim the alignment slack
        if (start > (u64)r) munmap(r, start - (u64)r);
        u64 tail = (u64)r + span + max_align - (start + span);
        if (tail) munmap((void*)(start + span), tail);
        bias = start - lo;
    } else if (eh.e_type != ET_EXEC) {
        close(fd);
        fatal("%s: unsupported ELF type %d", host_path, eh.e_type);
    }
    for (auto& p : ph) {
        if (p.p_type != PT_LOAD) continue;
        int prot = 0;
        if (p.p_flags & PF_R) prot |= PROT_READ;
        if (p.p_flags & PF_W) prot |= PROT_WRITE;
        // Guest code is never executed natively; it only has to be readable for translation.
        if (p.p_flags & PF_X) prot |= PROT_READ;
        GuestAddr seg = bias + p.p_vaddr;
        GuestAddr map_start = align_down<u64>(seg, kPage);
        u64 file_off = align_down<u64>(p.p_offset, kPage);
        u64 file_end = seg + p.p_filesz;
        u64 map_len = align_up<u64>(file_end, kPage) - map_start;
        int fixed = eh.e_type == ET_DYN ? MAP_FIXED : MAP_FIXED_NOREPLACE;
        if (p.p_filesz) {
            void* r = mmap((void*)map_start, map_len, prot | PROT_WRITE, MAP_PRIVATE | fixed, fd, file_off);
            if (r == MAP_FAILED || (GuestAddr)r != map_start) {
                close(fd);
                fatal("%s: cannot map segment at %#lx", host_path, (unsigned long)map_start);
            }
        }
        // zero the tail of the last file page and map anonymous bss
        GuestAddr mem_end = seg + p.p_memsz;
        if (p.p_memsz > p.p_filesz) {
            GuestAddr zero_start = file_end;
            GuestAddr page_end = align_up<u64>(file_end, kPage);
            if (p.p_filesz && page_end > zero_start) memset((void*)zero_start, 0, page_end - zero_start);
            GuestAddr anon_start = p.p_filesz ? page_end : map_start;
            GuestAddr anon_end = align_up<u64>(mem_end, kPage);
            if (anon_end > anon_start) {
                void* r = mmap((void*)anon_start, anon_end - anon_start, prot | PROT_WRITE,
                               MAP_PRIVATE | MAP_ANONYMOUS | fixed, -1, 0);
                if (r == MAP_FAILED) { close(fd); fatal("%s: cannot map bss", host_path); }
            }
        }
        if (!(prot & PROT_WRITE)) mprotect((void*)map_start, align_up<u64>(mem_end, kPage) - map_start, prot);
    }
    close(fd);
    bias_out = bias;
    lo_out = lo + bias;
    hi_out = hi + bias;
    return true;
}

bool load_elf(const char* path, LoadedImage& img) {
    img.exe_path = path;
    img.host_path = resolve_guest_path(path);
    if (access(img.host_path.c_str(), R_OK) != 0) img.host_path = path;
    Elf64_Ehdr eh;
    std::vector<Elf64_Phdr> ph;
    GuestAddr bias, lo, hi;
    if (!map_object(img.host_path.c_str(), kPieBase, eh, ph, bias, lo, hi)) return false;
    img.exe_base = bias;
    img.exe_entry = eh.e_entry + bias;
    img.entry = img.exe_entry;
    img.phent = eh.e_phentsize;
    img.phnum = eh.e_phnum;
    img.min_addr = lo;
    img.max_addr = hi;
    img.brk_start = hi;
    // find PT_PHDR (or compute from first PT_LOAD)
    img.phdr = 0;
    for (auto& p : ph) if (p.p_type == PT_PHDR) img.phdr = p.p_vaddr + bias;
    if (!img.phdr) {
        for (auto& p : ph)
            if (p.p_type == PT_LOAD && p.p_offset == 0) { img.phdr = p.p_vaddr + bias + eh.e_phoff; break; }
    }
    // interpreter
    for (auto& p : ph) {
        if (p.p_type != PT_INTERP) continue;
        std::string interp(p.p_filesz, '\0');
        int fd = open(img.host_path.c_str(), O_RDONLY | O_CLOEXEC);
        if (fd < 0 || !read_full(fd, interp.data(), p.p_filesz, p.p_offset)) fatal("cannot read PT_INTERP");
        close(fd);
        interp.resize(strlen(interp.c_str()));
        std::string ihost = resolve_guest_path(interp.c_str());
        Elf64_Ehdr ieh;
        std::vector<Elf64_Phdr> iph;
        GuestAddr ibias, ilo, ihi;
        if (!map_object(ihost.c_str(), 0, ieh, iph, ibias, ilo, ihi))
            fatal("cannot load interpreter %s (use --rootfs / XEF_ROOTFS)", interp.c_str());
        img.interp_base = ibias;
        img.entry = ieh.e_entry + ibias;
    }
    XEF_LOG(1, "loaded %s: base=%#lx entry=%#lx interp=%#lx brk=%#lx", path, (unsigned long)img.exe_base,
            (unsigned long)img.entry, (unsigned long)img.interp_base, (unsigned long)img.brk_start);
    return true;
}

GuestAddr setup_stack(const LoadedImage& img, int argc, char** argv, char** envp) {
    const u64 stack_size = 8ull << 20, guard = 64 << 10;
    void* r = mmap(nullptr, stack_size + guard, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE,
                   -1, 0);
    if (r == MAP_FAILED) fatal("cannot allocate guest stack");
    mprotect(r, guard, PROT_NONE);   // overflow faults instead of running into a neighbouring mapping
    u8* top = (u8*)r + guard + stack_size;
    u8* sp = top;
    auto push_str = [&](const char* s) -> GuestAddr {
        size_t n = strlen(s) + 1;
        sp -= n;
        memcpy(sp, s, n);
        return (GuestAddr)sp;
    };
    GuestAddr execfn = push_str(img.exe_path.c_str());
    GuestAddr platform = push_str("aarch64");
    std::vector<GuestAddr> envs, args;
    int envc = 0;
    for (char** e = envp; *e; e++) envc++;
    for (int i = envc - 1; i >= 0; i--) envs.push_back(push_str(envp[i]));
    for (int i = argc - 1; i >= 0; i--) args.push_back(push_str(argv[i]));
    // 16 random bytes
    sp -= 16;
    for (int i = 0; i < 16; i++) sp[i] = (u8)(rand() ^ (i * 37));
    GuestAddr random = (GuestAddr)sp;
    sp = (u8*)((uintptr_t)sp & ~15ull);

    std::vector<u64> auxv = {
        AT_PHDR, img.phdr, AT_PHENT, img.phent, AT_PHNUM, img.phnum, AT_PAGESZ, kPage,
        AT_BASE, img.interp_base, AT_FLAGS, 0, AT_ENTRY, img.exe_entry,
        AT_UID, (u64)getuid(), AT_EUID, (u64)geteuid(), AT_GID, (u64)getgid(), AT_EGID, (u64)getegid(),
        AT_SECURE, 0, AT_RANDOM, random, AT_HWCAP, guest_hwcap(), AT_HWCAP2, guest_hwcap2(),
        AT_CLKTCK, (u64)sysconf(_SC_CLK_TCK), AT_PLATFORM, platform, AT_EXECFN, execfn,
        51 /*AT_MINSIGSTKSZ*/, 5120, AT_NULL, 0,
    };
    size_t words = 1 + args.size() + 1 + envs.size() + 1 + auxv.size();
    sp -= words * 8;
    sp = (u8*)((uintptr_t)sp & ~15ull);
    u64* w = (u64*)sp;
    *w++ = (u64)argc;
    for (int i = argc - 1; i >= 0; i--) *w++ = args[i];
    *w++ = 0;
    for (int i = envc - 1; i >= 0; i--) *w++ = envs[i];
    *w++ = 0;
    for (u64 a : auxv) *w++ = a;
    return (GuestAddr)sp;
}

}  // namespace xef
