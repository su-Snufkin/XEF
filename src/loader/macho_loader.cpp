// XEF-OSX — Mach-O ARM64 loader implementation.
#include "loader/macho_loader.h"
#include "loader/macho_types.h"
#include "loader/commpage.h"
#include "loader/darwin_hle.h"

#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <vector>
#include <algorithm>

namespace xef {

static constexpr u64 kPageSize = 4096;
static inline u64 page_align_down(u64 x) { return x & ~(kPageSize - 1); }
static inline u64 page_align_up(u64 x) { return (x + kPageSize - 1) & ~(kPageSize - 1); }

static inline uint32_t bswap32(uint32_t x) { return __builtin_bswap32(x); }
static inline uint64_t bswap64(uint64_t x) { return __builtin_bswap64(x); }

struct ChainedFixupsHeader {
    uint32_t fixups_version;
    uint32_t starts_offset;
    uint32_t imports_offset;
    uint32_t symbols_offset;
    uint32_t imports_count;
    uint32_t imports_format;
    uint32_t symbols_format;
};

static void resolve_chained_fixups(int fd, uint64_t slice_offset, uint64_t fixup_off, uint64_t fixup_size, uint64_t exe_base) {
    if (fixup_size < sizeof(ChainedFixupsHeader)) return;
    std::vector<uint8_t> buf(fixup_size);
    lseek(fd, slice_offset + fixup_off, SEEK_SET);
    if (read(fd, buf.data(), fixup_size) != (ssize_t)fixup_size) return;

    const ChainedFixupsHeader* hdr = (const ChainedFixupsHeader*)buf.data();
    if (hdr->imports_offset >= fixup_size || hdr->symbols_offset >= fixup_size) return;

    const uint8_t* symbols_buf = buf.data() + hdr->symbols_offset;
    std::vector<uint64_t> imported_addrs(hdr->imports_count, 0);

    for (uint32_t i = 0; i < hdr->imports_count; i++) {
        uint32_t name_off = 0;
        if (hdr->imports_format == 1) { // DYLD_CHAINED_IMPORT
            const uint32_t* imp = (const uint32_t*)(buf.data() + hdr->imports_offset);
            uint32_t val = imp[i];
            name_off = val >> 9;
        } else if (hdr->imports_format == 2) { // DYLD_CHAINED_IMPORT_ADDEND
            const uint64_t* imp = (const uint64_t*)(buf.data() + hdr->imports_offset);
            uint64_t val = imp[i];
            name_off = (val >> 9) & 0x7FFFFF;
        }
        if (hdr->symbols_offset + name_off < fixup_size) {
            const char* name = (const char*)(symbols_buf + name_off);
            imported_addrs[i] = darwin_hle_resolve_symbol(name);
        }
    }

    if (hdr->starts_offset >= fixup_size) return;
    const uint32_t* starts_img = (const uint32_t*)(buf.data() + hdr->starts_offset);
    uint32_t seg_count = starts_img[0];
    const uint32_t* seg_offsets = starts_img + 1;

    for (uint32_t s = 0; s < seg_count; s++) {
        uint32_t soff = seg_offsets[s];
        if (soff == 0 || hdr->starts_offset + soff >= fixup_size) continue;

        const uint8_t* seg_info = buf.data() + hdr->starts_offset + soff;
        uint16_t page_size = *(const uint16_t*)(seg_info + 4);
        uint64_t segment_offset = *(const uint64_t*)(seg_info + 8);
        uint16_t page_count = *(const uint16_t*)(seg_info + 20);
        const uint16_t* page_starts = (const uint16_t*)(seg_info + 22);

        uint64_t seg_mem_base = exe_base + segment_offset;
        size_t seg_protect_len = (size_t)page_size * page_count;
        mprotect((void*)page_align_down(seg_mem_base), page_align_up(seg_protect_len + 4096), PROT_READ | PROT_WRITE);

        for (uint16_t p = 0; p < page_count; p++) {
            uint16_t pstart = page_starts[p];
            if (pstart == 0xFFFF) continue; // no fixups on this page

            uint64_t chain_addr = seg_mem_base + (uint64_t)p * page_size + pstart;
            for (;;) {
                uint64_t raw_val = *(uint64_t*)chain_addr;
                bool is_bind = (raw_val >> 63) & 1;
                uint64_t next = (raw_val >> 51) & 0xFFF;

                if (is_bind) {
                    uint32_t ordinal = raw_val & 0xFFFFFF;
                    if (ordinal < hdr->imports_count && imported_addrs[ordinal] != 0) {
                        *(uint64_t*)chain_addr = imported_addrs[ordinal];
                    }
                } else {
                    uint64_t target = raw_val & 0xFFFFFFFFFLL;
                    *(uint64_t*)chain_addr = exe_base + target;
                }

                if (next == 0) break;
                chain_addr += next * 4;
            }
        }
    }
}

static inline uint64_t read_uleb128(const uint8_t*& p, const uint8_t* end) {
    uint64_t res = 0;
    int shift = 0;
    while (p < end) {
        uint8_t b = *p++;
        res |= (uint64_t)(b & 0x7F) << shift;
        if ((b & 0x80) == 0) break;
        shift += 7;
    }
    return res;
}

static inline int64_t read_sleb128(const uint8_t*& p, const uint8_t* end) {
    int64_t res = 0;
    int shift = 0;
    while (p < end) {
        uint8_t b = *p++;
        res |= (int64_t)(b & 0x7F) << shift;
        shift += 7;
        if ((b & 0x80) == 0) {
            if (b & 0x40) res |= -(1LL << shift);
            break;
        }
    }
    return res;
}

static void execute_dyld_rebase(const uint8_t* buf, size_t size,
                                const std::vector<uint64_t>& seg_vmaddrs, uint64_t slide) {
    if (!buf || size == 0 || slide == 0) return;
    const uint8_t* p = buf;
    const uint8_t* end = buf + size;

    uint32_t seg_idx = 0;
    uint64_t seg_off = 0;

    while (p < end) {
        uint8_t b = *p++;
        uint8_t op = b & REBASE_OPCODE_MASK;
        uint8_t imm = b & REBASE_IMMEDIATE_MASK;

        switch (op) {
            case REBASE_OPCODE_DONE:
                return;
            case REBASE_OPCODE_SET_TYPE_IMM:
                break;
            case REBASE_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB:
                seg_idx = imm;
                seg_off = read_uleb128(p, end);
                break;
            case REBASE_OPCODE_ADD_ADDR_ULEB:
                seg_off += read_uleb128(p, end);
                break;
            case REBASE_OPCODE_ADD_ADDR_IMM_SCALED:
                seg_off += (uint64_t)imm * sizeof(uint64_t);
                break;
            case REBASE_OPCODE_DO_REBASE_IMM_TIMES: {
                for (uint32_t i = 0; i < imm; i++) {
                    if (seg_idx < seg_vmaddrs.size()) {
                        uint64_t target_addr = seg_vmaddrs[seg_idx] + seg_off;
                        mprotect((void*)page_align_down(target_addr), 4096, PROT_READ | PROT_WRITE);
                        *(uint64_t*)target_addr += slide;
                    }
                    seg_off += sizeof(uint64_t);
                }
                break;
            }
            case REBASE_OPCODE_DO_REBASE_ULEB_TIMES: {
                uint64_t count = read_uleb128(p, end);
                for (uint64_t i = 0; i < count; i++) {
                    if (seg_idx < seg_vmaddrs.size()) {
                        uint64_t target_addr = seg_vmaddrs[seg_idx] + seg_off;
                        mprotect((void*)page_align_down(target_addr), 4096, PROT_READ | PROT_WRITE);
                        *(uint64_t*)target_addr += slide;
                    }
                    seg_off += sizeof(uint64_t);
                }
                break;
            }
            case REBASE_OPCODE_DO_REBASE_ADD_ADDR_ULEB: {
                uint64_t extra = read_uleb128(p, end);
                if (seg_idx < seg_vmaddrs.size()) {
                    uint64_t target_addr = seg_vmaddrs[seg_idx] + seg_off;
                    mprotect((void*)page_align_down(target_addr), 4096, PROT_READ | PROT_WRITE);
                    *(uint64_t*)target_addr += slide;
                }
                seg_off += sizeof(uint64_t) + extra;
                break;
            }
            case REBASE_OPCODE_DO_REBASE_ULEB_TIMES_SKIPPING_ULEB: {
                uint64_t count = read_uleb128(p, end);
                uint64_t skip = read_uleb128(p, end);
                for (uint64_t i = 0; i < count; i++) {
                    if (seg_idx < seg_vmaddrs.size()) {
                        uint64_t target_addr = seg_vmaddrs[seg_idx] + seg_off;
                        mprotect((void*)page_align_down(target_addr), 4096, PROT_READ | PROT_WRITE);
                        *(uint64_t*)target_addr += slide;
                    }
                    seg_off += sizeof(uint64_t) + skip;
                }
                break;
            }
            default:
                break;
        }
    }
}

static void execute_dyld_bind(const uint8_t* buf, size_t size,
                              const std::vector<uint64_t>& seg_vmaddrs, bool is_weak = false) {
    if (!buf || size == 0) return;
    const uint8_t* p = buf;
    const uint8_t* end = buf + size;

    uint32_t seg_idx = 0;
    uint64_t seg_off = 0;
    const char* sym_name = "";
    int64_t addend = 0;

    auto do_bind_at = [&](uint64_t addr) {
        uint64_t sym_val = darwin_hle_resolve_symbol(sym_name, is_weak);
        if (sym_val != 0) {
            mprotect((void*)page_align_down(addr), 4096, PROT_READ | PROT_WRITE);
            *(uint64_t*)addr = sym_val + addend;
        }
    };

    while (p < end) {
        uint8_t b = *p++;
        uint8_t op = b & BIND_OPCODE_MASK;
        uint8_t imm = b & BIND_IMMEDIATE_MASK;

        switch (op) {
            case BIND_OPCODE_DONE:
                // Note: in lazy binding opcodes, DONE ends one symbol's instructions, but we continue till end of buffer
                break;
            case BIND_OPCODE_SET_DYLIB_ORDINAL_IMM:
                break;
            case BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB:
                read_uleb128(p, end);
                break;
            case BIND_OPCODE_SET_DYLIB_SPECIAL_IMM:
                break;
            case BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM: {
                sym_name = (const char*)p;
                while (p < end && *p != 0) p++;
                if (p < end) p++; // skip null
                break;
            }
            case BIND_OPCODE_SET_TYPE_IMM:
                break;
            case BIND_OPCODE_SET_ADDEND_SLEB:
                addend = read_sleb128(p, end);
                break;
            case BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB:
                seg_idx = imm;
                seg_off = read_uleb128(p, end);
                break;
            case BIND_OPCODE_ADD_ADDR_ULEB:
                seg_off += read_uleb128(p, end);
                break;
            case BIND_OPCODE_DO_BIND: {
                if (seg_idx < seg_vmaddrs.size()) {
                    do_bind_at(seg_vmaddrs[seg_idx] + seg_off);
                }
                seg_off += sizeof(uint64_t);
                break;
            }
            case BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB: {
                uint64_t extra = read_uleb128(p, end);
                if (seg_idx < seg_vmaddrs.size()) {
                    do_bind_at(seg_vmaddrs[seg_idx] + seg_off);
                }
                seg_off += sizeof(uint64_t) + extra;
                break;
            }
            case BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED: {
                if (seg_idx < seg_vmaddrs.size()) {
                    do_bind_at(seg_vmaddrs[seg_idx] + seg_off);
                }
                seg_off += sizeof(uint64_t) + (uint64_t)imm * sizeof(uint64_t);
                break;
            }
            case BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB: {
                uint64_t count = read_uleb128(p, end);
                uint64_t skip = read_uleb128(p, end);
                for (uint64_t i = 0; i < count; i++) {
                    if (seg_idx < seg_vmaddrs.size()) {
                        do_bind_at(seg_vmaddrs[seg_idx] + seg_off);
                    }
                    seg_off += sizeof(uint64_t) + skip;
                }
                break;
            }
            default:
                break;
        }
    }
}

bool is_macho_binary(const char* path, bool& is_fat, bool& is_arm64) {
    is_fat = false;
    is_arm64 = false;
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return false;

    uint32_t magic = 0;
    if (read(fd, &magic, sizeof(magic)) != sizeof(magic)) {
        close(fd);
        return false;
    }

    if (magic == FAT_MAGIC || magic == FAT_CIGAM || magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64) {
        is_fat = true;
        bool swap = (magic == FAT_CIGAM || magic == FAT_CIGAM_64);
        fat_header fh;
        lseek(fd, 0, SEEK_SET);
        if (read(fd, &fh, sizeof(fh)) == sizeof(fh)) {
            uint32_t narch = swap ? bswap32(fh.nfat_arch) : fh.nfat_arch;
            for (uint32_t i = 0; i < narch; i++) {
                fat_arch fa;
                if (read(fd, &fa, sizeof(fa)) != sizeof(fa)) break;
                uint32_t cpu = swap ? bswap32(fa.cputype) : fa.cputype;
                if (cpu == CPU_TYPE_ARM64) {
                    is_arm64 = true;
                    break;
                }
            }
        }
        close(fd);
        return true;
    }

    if (magic == MH_MAGIC_64 || magic == MH_CIGAM_64) {
        mach_header_64 mh;
        lseek(fd, 0, SEEK_SET);
        if (read(fd, &mh, sizeof(mh)) == sizeof(mh)) {
            bool swap = (magic == MH_CIGAM_64);
            uint32_t cpu = swap ? bswap32(mh.cputype) : mh.cputype;
            if (cpu == CPU_TYPE_ARM64) is_arm64 = true;
        }
        close(fd);
        return true;
    }

    close(fd);
    return false;
}

static int prot_from_macho(uint32_t p) {
    int r = 0;
    if (p & 1) r |= PROT_READ;
    if (p & 2) r |= PROT_WRITE;
    if (p & 4) r |= PROT_EXEC;
    return r;
}

bool load_macho(const char* path, LoadedImage& img) {
    img.exe_path = path;
    img.host_path = resolve_guest_path(path);
    if (access(img.host_path.c_str(), R_OK) != 0) img.host_path = path;

    int fd = open(img.host_path.c_str(), O_RDONLY | O_CLOEXEC);
    if (fd < 0) return false;

    uint32_t magic = 0;
    if (read(fd, &magic, sizeof(magic)) != sizeof(magic)) {
        close(fd);
        return false;
    }

    uint64_t slice_offset = 0;
    uint64_t slice_size = 0;

    if (magic == FAT_MAGIC || magic == FAT_CIGAM) {
        bool swap = (magic == FAT_CIGAM);
        fat_header fh;
        lseek(fd, 0, SEEK_SET);
        if (read(fd, &fh, sizeof(fh)) != sizeof(fh)) { close(fd); return false; }
        uint32_t narch = swap ? bswap32(fh.nfat_arch) : fh.nfat_arch;
        bool found = false;
        for (uint32_t i = 0; i < narch; i++) {
            fat_arch fa;
            if (read(fd, &fa, sizeof(fa)) != sizeof(fa)) break;
            uint32_t cpu = swap ? bswap32(fa.cputype) : fa.cputype;
            if (cpu == CPU_TYPE_ARM64) {
                slice_offset = swap ? bswap32(fa.offset) : fa.offset;
                slice_size   = swap ? bswap32(fa.size)   : fa.size;
                found = true;
                break;
            }
        }
        if (!found) {
            fprintf(stderr, "xef-osx: FAT binary contains no ARM64 slice\n");
            close(fd);
            return false;
        }
    } else if (magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64) {
        bool swap = (magic == FAT_CIGAM_64);
        fat_header fh;
        lseek(fd, 0, SEEK_SET);
        if (read(fd, &fh, sizeof(fh)) != sizeof(fh)) { close(fd); return false; }
        uint32_t narch = swap ? bswap32(fh.nfat_arch) : fh.nfat_arch;
        bool found = false;
        for (uint32_t i = 0; i < narch; i++) {
            fat_arch_64 fa64;
            if (read(fd, &fa64, sizeof(fa64)) != sizeof(fa64)) break;
            uint32_t cpu = swap ? bswap32(fa64.cputype) : fa64.cputype;
            if (cpu == CPU_TYPE_ARM64) {
                slice_offset = swap ? bswap64(fa64.offset) : fa64.offset;
                slice_size   = swap ? bswap64(fa64.size)   : fa64.size;
                found = true;
                break;
            }
        }
        if (!found) {
            fprintf(stderr, "xef-osx: FAT64 binary contains no ARM64 slice\n");
            close(fd);
            return false;
        }
    }

    lseek(fd, slice_offset, SEEK_SET);
    mach_header_64 mh;
    if (read(fd, &mh, sizeof(mh)) != sizeof(mh)) {
        close(fd);
        return false;
    }

    bool swap = (mh.magic == MH_CIGAM_64);
    uint32_t cputype    = swap ? bswap32(mh.cputype) : mh.cputype;
    uint32_t filetype   = swap ? bswap32(mh.filetype) : mh.filetype;
    uint32_t ncmds      = swap ? bswap32(mh.ncmds) : mh.ncmds;
    uint32_t sizeofcmds = swap ? bswap32(mh.sizeofcmds) : mh.sizeofcmds;
    uint32_t flags      = swap ? bswap32(mh.flags) : mh.flags;
    (void)filetype; (void)flags; (void)slice_size;

    if (cputype != CPU_TYPE_ARM64) {
        fprintf(stderr, "xef-osx: Unsupported Mach-O CPU type: %u (expected ARM64)\n", cputype);
        close(fd);
        return false;
    }

    std::vector<uint8_t> cmdbuf(sizeofcmds);
    if (read(fd, cmdbuf.data(), sizeofcmds) != (ssize_t)sizeofcmds) {
        close(fd);
        return false;
    }

    // Initialize commpage for macOS guest
    commpage_init();

    uint64_t text_vmaddr = 0;
    uint64_t entry_offset = 0;
    bool has_main = false;
    bool has_unixthread = false;
    uint64_t unixthread_pc = 0;
    uint64_t slide = 0;

    uint64_t chained_fixups_offset = 0;
    uint64_t chained_fixups_size = 0;
    bool has_chained_fixups = false;

    dyld_info_command dyld_info = {};
    bool has_dyld_info = false;
    std::vector<uint64_t> seg_vmaddrs;

    // Scan segments to determine addresses
    img.min_addr = ~0ull;
    img.max_addr = 0;

    // First pass: locate __TEXT segment to know base
    uint32_t off = 0;
    for (uint32_t i = 0; i < ncmds && off + sizeof(load_command) <= sizeofcmds; i++) {
        const load_command* lc = (const load_command*)&cmdbuf[off];
        uint32_t cmd = swap ? bswap32(lc->cmd) : lc->cmd;
        uint32_t cmdsize = swap ? bswap32(lc->cmdsize) : lc->cmdsize;
        if (cmd == LC_SEGMENT_64 && cmdsize >= sizeof(segment_command_64)) {
            const segment_command_64* seg = (const segment_command_64*)lc;
            uint64_t vmaddr = swap ? bswap64(seg->vmaddr) : seg->vmaddr;
            if (strncmp(seg->segname, "__TEXT", 16) == 0) {
                text_vmaddr = vmaddr;
                img.exe_base = text_vmaddr + slide;
            }
        }
        off += cmdsize;
    }

    // Second pass: map segments
    off = 0;
    for (uint32_t i = 0; i < ncmds && off + sizeof(load_command) <= sizeofcmds; i++) {
        const load_command* lc = (const load_command*)&cmdbuf[off];
        uint32_t cmd = swap ? bswap32(lc->cmd) : lc->cmd;
        uint32_t cmdsize = swap ? bswap32(lc->cmdsize) : lc->cmdsize;

        if (cmd == LC_SEGMENT_64 && cmdsize >= sizeof(segment_command_64)) {
            const segment_command_64* seg = (const segment_command_64*)lc;
            uint64_t vmaddr   = swap ? bswap64(seg->vmaddr) : seg->vmaddr;
            uint64_t vmsize   = swap ? bswap64(seg->vmsize) : seg->vmsize;
            uint64_t fileoff  = swap ? bswap64(seg->fileoff) : seg->fileoff;
            uint64_t filesize = swap ? bswap64(seg->filesize) : seg->filesize;
            uint32_t initprot = swap ? bswap32(seg->initprot) : seg->initprot;
            uint32_t maxprot  = swap ? bswap32(seg->maxprot) : seg->maxprot;
            (void)maxprot;

            if (strncmp(seg->segname, "__PAGEZERO", 16) == 0) {
                // Protect PAGEZERO area (typically 4GB on 64-bit Mach-O)
                if (vmsize > 0) {
                    mmap((void*)vmaddr, vmsize, PROT_NONE,
                         MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
                }
                seg_vmaddrs.push_back(vmaddr);
                off += cmdsize;
                continue;
            }

            uint64_t target_addr = vmaddr + slide;
            int prot = prot_from_macho(initprot);

            if (filesize > 0) {
                uint64_t map_page_start = page_align_down(target_addr);
                uint64_t page_offset    = target_addr - map_page_start;
                uint64_t file_page_start = page_align_down(slice_offset + fileoff);
                uint64_t map_len        = page_align_up(filesize + page_offset);

                void* r = mmap((void*)map_page_start, map_len, prot | PROT_WRITE,
                               MAP_PRIVATE | MAP_FIXED, fd, file_page_start);
                if (r == MAP_FAILED) {
                    fprintf(stderr, "xef-osx: Failed to mmap segment %s at %#lx (len %#lx): %m\n",
                            seg->segname, (unsigned long)map_page_start, (unsigned long)map_len);
                    close(fd);
                    return false;
                }

                // If vmsize > filesize, allocate zeroed memory for BSS
                if (vmsize > filesize) {
                    uint64_t bss_start = target_addr + filesize;
                    uint64_t bss_page_start = page_align_up(bss_start);
                    // Zero end of mapped file page
                    if (bss_page_start > bss_start) {
                        memset((void*)bss_start, 0, bss_page_start - bss_start);
                    }
                    uint64_t bss_page_end = page_align_up(target_addr + vmsize);
                    if (bss_page_end > bss_page_start) {
                        void* b = mmap((void*)bss_page_start, bss_page_end - bss_page_start,
                                       prot | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
                        if (b == MAP_FAILED) {
                            fprintf(stderr, "xef-osx: Failed to mmap BSS for %s\n", seg->segname);
                            close(fd);
                            return false;
                        }
                    }
                }

                if (!(prot & PROT_WRITE)) {
                    mprotect((void*)map_page_start, page_align_up(vmsize + page_offset), prot);
                }
            } else if (vmsize > 0) {
                // Pure anonymous segment
                uint64_t map_page_start = page_align_down(target_addr);
                uint64_t map_len = page_align_up(vmsize);
                void* r = mmap((void*)map_page_start, map_len, prot,
                               MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
                if (r == MAP_FAILED) {
                    fprintf(stderr, "xef-osx: Failed to mmap anon segment %s\n", seg->segname);
                    close(fd);
                    return false;
                }
            }

            // Inspect sections in this segment for __thread_data
            uint32_t nsects = swap ? bswap32(seg->nsects) : seg->nsects;
            if (nsects > 0 && cmdsize >= sizeof(segment_command_64) + nsects * sizeof(section_64)) {
                const section_64* scts = (const section_64*)(seg + 1);
                for (uint32_t s = 0; s < nsects; s++) {
                    const section_64& sct = scts[s];
                    if (strncmp(sct.sectname, "__thread_data", 16) == 0) {
                        uint64_t saddr = swap ? bswap64(sct.addr) : sct.addr;
                        uint64_t ssize = swap ? bswap64(sct.size) : sct.size;
                        g_darwin_tlv_template = (const uint8_t*)(saddr + slide);
                        g_darwin_tlv_template_size = (size_t)ssize;
                        XEF_LOG(2, "xef-osx: found __thread_data template at %p (size %#zx)",
                                g_darwin_tlv_template, g_darwin_tlv_template_size);
                    }
                }
            }

            img.min_addr = std::min(img.min_addr, (GuestAddr)target_addr);
            img.max_addr = std::max(img.max_addr, (GuestAddr)(target_addr + vmsize));
            seg_vmaddrs.push_back(target_addr);
        } else if (cmd == LC_MAIN && cmdsize >= sizeof(entry_point_command)) {
            const entry_point_command* ep = (const entry_point_command*)lc;
            entry_offset = swap ? bswap64(ep->entryoff) : ep->entryoff;
            has_main = true;
        } else if (cmd == LC_DYLD_CHAINED_FIXUPS && cmdsize >= sizeof(linkedit_data_command)) {
            const linkedit_data_command* ldc = (const linkedit_data_command*)lc;
            chained_fixups_offset = swap ? bswap32(ldc->dataoff) : ldc->dataoff;
            chained_fixups_size   = swap ? bswap32(ldc->datasize) : ldc->datasize;
            has_chained_fixups    = true;
        } else if ((cmd == LC_DYLD_INFO || cmd == LC_DYLD_INFO_ONLY) && cmdsize >= sizeof(dyld_info_command)) {
            const dyld_info_command* dic = (const dyld_info_command*)lc;
            dyld_info = *dic;
            if (swap) {
                dyld_info.rebase_off    = bswap32(dyld_info.rebase_off);
                dyld_info.rebase_size   = bswap32(dyld_info.rebase_size);
                dyld_info.bind_off      = bswap32(dyld_info.bind_off);
                dyld_info.bind_size     = bswap32(dyld_info.bind_size);
                dyld_info.weak_bind_off = bswap32(dyld_info.weak_bind_off);
                dyld_info.weak_bind_size= bswap32(dyld_info.weak_bind_size);
                dyld_info.lazy_bind_off = bswap32(dyld_info.lazy_bind_off);
                dyld_info.lazy_bind_size= bswap32(dyld_info.lazy_bind_size);
                dyld_info.export_off    = bswap32(dyld_info.export_off);
                dyld_info.export_size   = bswap32(dyld_info.export_size);
            }
            has_dyld_info = true;
        } else if (cmd == LC_UNIXTHREAD) {
            // flavor and count follow load_command
            const uint32_t* p = (const uint32_t*)(lc + 1);
            uint32_t flavor = swap ? bswap32(p[0]) : p[0];
            uint32_t count  = swap ? bswap32(p[1]) : p[1];
            if (flavor == ARM_THREAD_STATE64 && count >= sizeof(arm_thread_state64_t) / 4) {
                const arm_thread_state64_t* ts = (const arm_thread_state64_t*)(p + 2);
                unixthread_pc = swap ? bswap64(ts->pc) : ts->pc;
                has_unixthread = true;
            }
        }

        off += cmdsize;
    }

    if (has_chained_fixups && chained_fixups_size > 0) {
        resolve_chained_fixups(fd, slice_offset, chained_fixups_offset, chained_fixups_size, img.exe_base);
    }

    if (has_dyld_info) {
        auto read_and_exec = [&](uint32_t fileoff, uint32_t size, auto fn) {
            if (size == 0) return;
            std::vector<uint8_t> buf(size);
            lseek(fd, slice_offset + fileoff, SEEK_SET);
            if (read(fd, buf.data(), size) == (ssize_t)size) {
                fn(buf.data(), size);
            }
        };

        if (dyld_info.rebase_size > 0 && slide != 0) {
            read_and_exec(dyld_info.rebase_off, dyld_info.rebase_size, [&](const uint8_t* b, size_t s) {
                execute_dyld_rebase(b, s, seg_vmaddrs, slide);
            });
        }
        if (dyld_info.bind_size > 0) {
            read_and_exec(dyld_info.bind_off, dyld_info.bind_size, [&](const uint8_t* b, size_t s) {
                execute_dyld_bind(b, s, seg_vmaddrs);
            });
        }
        if (dyld_info.weak_bind_size > 0) {
            read_and_exec(dyld_info.weak_bind_off, dyld_info.weak_bind_size, [&](const uint8_t* b, size_t s) {
                execute_dyld_bind(b, s, seg_vmaddrs, true);
            });
        }
        if (dyld_info.lazy_bind_size > 0) {
            read_and_exec(dyld_info.lazy_bind_off, dyld_info.lazy_bind_size, [&](const uint8_t* b, size_t s) {
                execute_dyld_bind(b, s, seg_vmaddrs);
            });
        }
    }

    close(fd);

    if (has_main) {
        img.entry = text_vmaddr + slide + entry_offset;
        img.exe_entry = img.entry;
    } else if (has_unixthread) {
        img.entry = unixthread_pc + slide;
        img.exe_entry = img.entry;
    } else {
        fprintf(stderr, "xef-osx: No entry point found in Mach-O binary\n");
        return false;
    }

    img.brk_start = page_align_up(img.max_addr);
    XEF_LOG(1, "xef-osx: Mach-O ARM64 loaded %s: base=%#lx entry=%#lx min=%#lx max=%#lx",
            path, (unsigned long)img.exe_base, (unsigned long)img.entry,
            (unsigned long)img.min_addr, (unsigned long)img.max_addr);
    return true;
}

GuestAddr setup_darwin_stack(const LoadedImage& img, int argc, char** argv, char** envp, CpuState* st) {
    const u64 stack_size = 8ull << 20, guard = 64 << 10;
    void* r = mmap(nullptr, stack_size + guard, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    if (r == MAP_FAILED) fatal("cannot allocate guest stack");
    mprotect(r, guard, PROT_NONE);

    u8* top = (u8*)r + guard + stack_size;
    u8* sp = top;

    auto push_str = [&](const char* s) -> GuestAddr {
        size_t n = strlen(s) + 1;
        sp -= n;
        memcpy(sp, s, n);
        return (GuestAddr)(uintptr_t)sp;
    };

    // Prepare Apple auxiliary strings
    std::string exec_path_str = "executable_path=" + img.exe_path;
    std::vector<std::string> apple_strs;
    apple_strs.push_back(exec_path_str);
    apple_strs.push_back("pf=Darwin");

    // Copy apple strings
    std::vector<GuestAddr> apple_addrs;
    for (const auto& as : apple_strs) {
        apple_addrs.push_back(push_str(as.c_str()));
    }

    // Copy environment strings
    std::vector<GuestAddr> envp_addrs;
    for (int j = 0; envp && envp[j]; j++) {
        envp_addrs.push_back(push_str(envp[j]));
    }

    // Copy argument strings
    std::vector<GuestAddr> argv_addrs;
    for (int j = 0; j < argc; j++) {
        GuestAddr a = push_str(argv[j]);
        XEF_LOG(2, "setup_darwin_stack: argv[%d] = '%s' pushed at %#lx", j, argv[j], (unsigned long)a);
        argv_addrs.push_back(a);
    }

    // Align stack to 16 bytes before writing pointer tables
    sp = (u8*)((uintptr_t)sp & ~15ull);

    // Calculate space for pointers:
    // argc (1 word)
    // argv pointers (argc + 1 null)
    // envp pointers (envc + 1 null)
    // apple pointers (applec + 1 null)
    size_t words = 1 + (argc + 1) + (envp_addrs.size() + 1) + (apple_addrs.size() + 1);
    if (words % 2 != 0) words++; // keep 16-byte alignment

    sp -= words * sizeof(u64);
    u64* ptr = (u64*)sp;

    // sp[0] = argc
    *ptr++ = (u64)argc;

    // argv array
    u64* argv_base = ptr;
    for (GuestAddr a : argv_addrs) *ptr++ = a;
    *ptr++ = 0; // null terminator
    XEF_LOG(2, "setup_darwin_stack: argv_base=%p, [0]=%#lx, [1]=%#lx",
            argv_base, (unsigned long)argv_base[0], (unsigned long)argv_base[1]);

    // envp array
    u64* envp_base = ptr;
    for (GuestAddr a : envp_addrs) *ptr++ = a;
    *ptr++ = 0; // null terminator

    // apple array
    u64* apple_base = ptr;
    for (GuestAddr a : apple_addrs) *ptr++ = a;
    *ptr++ = 0; // null terminator

    GuestAddr final_sp = (GuestAddr)(uintptr_t)sp;

    g_darwin_stack_top = (uint64_t)(uintptr_t)top;
    g_darwin_stack_size = stack_size;
    g_darwin_mach_header = img.exe_base;
    g_darwin_argc = argc;

    // Allocate persistent host storage for g_darwin_argv and g_darwin_envp
    // so they are not corrupted if the guest stack frame grows or overwrites stack.
    static std::vector<char*> s_darwin_argv_storage;
    s_darwin_argv_storage.clear();
    for (GuestAddr a : argv_addrs) {
        s_darwin_argv_storage.push_back((char*)(uintptr_t)a);
    }
    s_darwin_argv_storage.push_back(nullptr);
    g_darwin_argv = s_darwin_argv_storage.data();

    static std::vector<char*> s_darwin_envp_storage;
    s_darwin_envp_storage.clear();
    for (GuestAddr a : envp_addrs) {
        s_darwin_envp_storage.push_back((char*)(uintptr_t)a);
    }
    s_darwin_envp_storage.push_back(nullptr);
    g_darwin_envp = s_darwin_envp_storage.data();

    g_darwin_exe_path = img.exe_path;

    // In macOS Darwin ARM64 ABI, initial registers at entry are:
    // x0 = argc
    // x1 = argv
    // x2 = envp
    // x3 = apple
    // SP = 16-byte aligned stack pointer
    if (st) {
        st->x[0] = (u64)argc;
        st->x[1] = (GuestAddr)(uintptr_t)argv_base;
        st->x[2] = (GuestAddr)(uintptr_t)envp_base;
        st->x[3] = (GuestAddr)(uintptr_t)apple_base;
        st->x[30] = g_darwin_exit_trampoline;
        XEF_LOG(1, "xef-osx: setting initial lr=%#lx", (unsigned long)g_darwin_exit_trampoline);
        st->x[kGuestSP] = final_sp;
        st->pc = img.entry;
        st->eflags = 0x203; // Canonical flags (AArch64 NZCV = 0, Carry = 0)
    }

    return final_sp;
}

} // namespace xef
