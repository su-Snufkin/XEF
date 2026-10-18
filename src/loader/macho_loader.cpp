// XEF-OSX — Mach-O ARM64 loader and the dyld part of the Darwin layer:
// image loading (executable + dylibs from the rootfs), rebases, chained fixups / bind opcodes with
// two-level-namespace ordinals, exports tries, re-exports, initializers, TLV and dlopen.
#include "loader/macho_loader.h"
#include "loader/macho_image.h"
#include "frontend/a64/translate.h"
#include "loader/macho_types.h"
#include "loader/commpage.h"
#include "loader/darwin_hle.h"
#include "thunks/thunks.h"

#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <vector>
#include <algorithm>
#include <mutex>
#include <memory>
#include <unordered_map>
#include <climits>

namespace xef {

static constexpr u64 kPageSize = 4096;
static inline u64 page_align_down(u64 x) { return x & ~(kPageSize - 1); }
static inline u64 page_align_up(u64 x) { return (x + kPageSize - 1) & ~(kPageSize - 1); }

static inline uint32_t bswap32(uint32_t x) { return __builtin_bswap32(x); }
static inline uint64_t bswap64(uint64_t x) { return __builtin_bswap64(x); }

static inline uint64_t read_uleb128(const uint8_t*& p, const uint8_t* end) {
    uint64_t res = 0;
    int shift = 0;
    while (p < end) {
        uint8_t b = *p++;
        if (shift < 64) res |= (uint64_t)(b & 0x7F) << shift;
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
        if (shift < 64) res |= (int64_t)(b & 0x7F) << shift;
        shift += 7;
        if ((b & 0x80) == 0) {
            if ((b & 0x40) && shift < 64) res |= -(1LL << shift);
            break;
        }
    }
    return res;
}

// ---------------------------------------------------------------------------------------------
// Registry
// ---------------------------------------------------------------------------------------------
static std::recursive_mutex g_dyld_lock;
static std::vector<MachImage*> g_images;
static std::unordered_map<std::string, MachImage*> g_by_name;   // install name / path -> image
static std::string g_exe_dir;
static std::string g_exe_real_dir;

const std::vector<MachImage*>& dyld_images() { return g_images; }

MachImage* dyld_image_containing(uint64_t addr) {
    for (MachImage* im : g_images)
        for (const MachSegment& s : im->segs)
            if (addr >= s.addr && addr < s.addr + s.size) return im;
    return nullptr;
}

std::string dyld_describe(uint64_t addr) {
    MachImage* im = dyld_image_containing(addr);
    if (!im) return "";
    char b[64];
    snprintf(b, sizeof b, "+%#lx", (unsigned long)(addr - im->header));
    return im->path + b;
}

// ---------------------------------------------------------------------------------------------
// Exports trie
// ---------------------------------------------------------------------------------------------
enum { EXPORT_REEXPORT = 0x08, EXPORT_STUB_AND_RESOLVER = 0x10, EXPORT_KIND_MASK = 0x03,
       EXPORT_KIND_ABSOLUTE = 0x02 };

static bool trie_lookup(const uint8_t* start, size_t size, const char* name, uint64_t& flags,
                        uint64_t& value, uint64_t& reexport_ord, const char*& reexport_name) {
    if (!start || !size) return false;
    const uint8_t* end = start + size;
    const uint8_t* node = start;
    const char* s = name;
    for (;;) {
        if (node >= end) return false;
        const uint8_t* p = node;
        uint64_t term_size = read_uleb128(p, end);
        if (*s == 0) {
            if (!term_size) return false;
            flags = read_uleb128(p, end);
            reexport_name = nullptr;
            reexport_ord = 0;
            if (flags & EXPORT_REEXPORT) {
                reexport_ord = read_uleb128(p, end);
                reexport_name = (const char*)p;
                value = 0;
            } else {
                value = read_uleb128(p, end);
            }
            return true;
        }
        p += term_size;
        if (p >= end) return false;
        unsigned nchild = *p++;
        const uint8_t* next = nullptr;
        for (unsigned i = 0; i < nchild; i++) {
            const char* edge = (const char*)p;
            size_t elen = strnlen(edge, end - p);
            p += elen + 1;
            uint64_t off = read_uleb128(p, end);
            if (!next && strncmp(s, edge, elen) == 0) {
                next = start + off;
                s += elen;
                break;
            }
        }
        if (!next) return false;
        node = next;
    }
}

static uint64_t dyld_lookup_rec(MachImage* img, const char* name, int depth) {
    if (!img || depth > 16) return 0;
    uint64_t flags, value, ord;
    const char* rname;
    if (trie_lookup(img->exports, img->exports_size, name, flags, value, ord, rname)) {
        if (flags & EXPORT_REEXPORT) {
            if (ord == 0 || ord > img->deps.size()) return 0;
            MachImage* d = img->deps[ord - 1].image;
            return dyld_lookup_rec(d, (rname && *rname) ? rname : name, depth + 1);
        }
        if ((flags & EXPORT_KIND_MASK) == EXPORT_KIND_ABSOLUTE) return value;
        return img->header + value;
    }
    if (!img->symtab_exports.empty()) {
        auto it = img->symtab_exports.find(name);
        if (it != img->symtab_exports.end()) return it->second;
    }
    // names exported through a re-exported dependency (umbrella libraries)
    for (MachDep& d : img->deps) {
        if (!d.reexport || !d.image) continue;
        if (uint64_t r = dyld_lookup_rec(d.image, name, depth + 1)) return r;
    }
    return 0;
}

uint64_t dyld_image_lookup(MachImage* img, const char* name) {
    return dyld_lookup_rec(img, name, 0);
}

uint64_t dyld_flat_lookup(const char* name) {
    std::lock_guard<std::recursive_mutex> lk(g_dyld_lock);
    for (MachImage* im : g_images)
        if (uint64_t r = dyld_lookup_rec(im, name, 0)) return r;
    return 0;
}

// ---------------------------------------------------------------------------------------------
// Imports
// ---------------------------------------------------------------------------------------------
// ordinal: >0 dependency, 0 self, -1 main executable, -2 flat lookup, -3 weak lookup
static uint64_t resolve_import(MachImage* img, int ordinal, const char* name, bool weak_import) {
    uint64_t r = 0;
    bool hle_dep = false;
    if (ordinal > 0) {
        if ((size_t)ordinal <= img->deps.size()) {
            MachImage* d = img->deps[ordinal - 1].image;
            if (d) r = dyld_image_lookup(d, name);
            else {
                hle_dep = true;
                if (img->deps[ordinal - 1].weak) weak_import = true;
            }
        }
    } else if (ordinal == 0) {
        r = dyld_image_lookup(img, name);
    } else if (ordinal == -1) {
        r = dyld_image_lookup(g_images.empty() ? nullptr : g_images[0], name);
    }
    if (r) return r;
    if (hle_dep) {
        // libSystem's names: a real system dylib in the rootfs (libdispatch-lite, libunwind, blocks, ...)
        // wins over the HLE; then the explicit HLE implementations; then the host libc fallback
        for (size_t i = 1; i < g_images.size() && !r; i++)
            r = dyld_lookup_rec(g_images[i], name, 0);
        if (r) return r;
        r = darwin_hle_resolve_symbol(name, true, true);
        if (r) return r;
    }
    r = dyld_flat_lookup(name);
    if (r) return r;
    if (strncmp(name, "_OBJC_CLASS_$_", 14) == 0 || strncmp(name, "_OBJC_METACLASS_$_", 18) == 0) {
        return 0;
    }
    return darwin_hle_resolve_symbol(name, weak_import);
}

// ---------------------------------------------------------------------------------------------
// Fixups
// ---------------------------------------------------------------------------------------------
struct ChainedFixupsHeader {
    uint32_t fixups_version;
    uint32_t starts_offset;
    uint32_t imports_offset;
    uint32_t symbols_offset;
    uint32_t imports_count;
    uint32_t imports_format;
    uint32_t symbols_format;
};

static void apply_chained_fixups(MachImage* img) {
    const uint8_t* buf = img->chained;
    size_t fixup_size = img->chained_size;
    if (!buf || fixup_size < sizeof(ChainedFixupsHeader)) return;
    const ChainedFixupsHeader* hdr = (const ChainedFixupsHeader*)buf;
    if (hdr->imports_offset >= fixup_size || hdr->symbols_offset >= fixup_size) return;

    const uint8_t* symbols_buf = buf + hdr->symbols_offset;
    std::vector<uint64_t> imp_addr(hdr->imports_count, 0);
    std::vector<int64_t> imp_addend(hdr->imports_count, 0);

    for (uint32_t i = 0; i < hdr->imports_count; i++) {
        uint32_t name_off = 0;
        int ordinal = 0;
        bool weak = false;
        int64_t addend = 0;
        if (hdr->imports_format == 1) {            // DYLD_CHAINED_IMPORT
            uint32_t v = ((const uint32_t*)(buf + hdr->imports_offset))[i];
            ordinal = (int8_t)(v & 0xFF);
            weak = (v >> 8) & 1;
            name_off = v >> 9;
        } else if (hdr->imports_format == 2) {     // DYLD_CHAINED_IMPORT_ADDEND
            const uint32_t* v = (const uint32_t*)(buf + hdr->imports_offset) + i * 2;
            ordinal = (int8_t)(v[0] & 0xFF);
            weak = (v[0] >> 8) & 1;
            name_off = v[0] >> 9;
            addend = (int32_t)v[1];
        } else if (hdr->imports_format == 3) {     // DYLD_CHAINED_IMPORT_ADDEND64
            const uint64_t* v = (const uint64_t*)(buf + hdr->imports_offset) + i * 2;
            ordinal = (int16_t)(v[0] & 0xFFFF);
            weak = (v[0] >> 16) & 1;
            name_off = (uint32_t)(v[0] >> 32);
            addend = (int64_t)v[1];
        } else {
            continue;
        }
        if (hdr->symbols_offset + name_off >= fixup_size) continue;
        const char* name = (const char*)(symbols_buf + name_off);
        imp_addr[i] = resolve_import(img, ordinal, name, weak);
        imp_addend[i] = addend;
    }

    if (hdr->starts_offset >= fixup_size) return;
    const uint8_t* starts_img = buf + hdr->starts_offset;
    uint32_t seg_count = *(const uint32_t*)starts_img;
    const uint32_t* seg_offsets = (const uint32_t*)starts_img + 1;

    for (uint32_t s = 0; s < seg_count; s++) {
        uint32_t soff = seg_offsets[s];
        if (soff == 0 || hdr->starts_offset + soff >= fixup_size) continue;
        const uint8_t* seg_info = starts_img + soff;
        uint16_t page_size = *(const uint16_t*)(seg_info + 4);
        uint16_t ptr_format = *(const uint16_t*)(seg_info + 6);
        uint64_t segment_offset = *(const uint64_t*)(seg_info + 8);
        uint16_t page_count = *(const uint16_t*)(seg_info + 20);
        const uint16_t* page_starts = (const uint16_t*)(seg_info + 22);
        if (ptr_format != 1 && ptr_format != 2 && ptr_format != 6 && ptr_format != 9 && ptr_format != 12) {
            XEF_LOG(1, "xef-osx: %s: unsupported chained pointer format %u", img->path.c_str(), ptr_format);
            continue;
        }

        uint64_t seg_mem_base = img->header + segment_offset;

        auto walk = [&](uint64_t chain_addr) {
            for (;;) {
                uint64_t raw = *(uint64_t*)chain_addr;
                uint64_t next = 0;
                if (ptr_format == 2 || ptr_format == 6) {
                    bool is_bind = (raw >> 63) & 1;
                    next = (raw >> 51) & 0xFFF;
                    if (is_bind) {
                        uint32_t ord = raw & 0xFFFFFF;
                        uint64_t addend8 = (raw >> 24) & 0xFF;
                        uint64_t v = 0;
                        if (ord < hdr->imports_count) v = imp_addr[ord] + imp_addend[ord] + addend8;
                        *(uint64_t*)chain_addr = v;
                    } else {
                        uint64_t target = raw & 0xFFFFFFFFFULL;
                        uint64_t high8 = (raw >> 36) & 0xFF;
                        uint64_t v = (ptr_format == 6) ? img->header + target : target + img->slide;
                        *(uint64_t*)chain_addr = v | (high8 << 56);
                    }
                    if (next == 0) break;
                    chain_addr += next * 4;
                } else if (ptr_format == 1 || ptr_format == 9 || ptr_format == 12) {
                    // DYLD_CHAINED_PTR_ARM64E / ARM64E_USERLAND / ARM64E_USERLAND24
                    bool auth = (raw >> 63) & 1;
                    bool bind = (raw >> 62) & 1;
                    next = (raw >> 51) & 0x7FF;
                    uint64_t v = 0;
                    if (auth) {
                        if (bind) {
                            uint32_t ord = (ptr_format == 12) ? (raw & 0xFFFFFF) : (raw & 0xFFFF);
                            if (ord < hdr->imports_count) v = imp_addr[ord] + imp_addend[ord];
                        } else {
                            uint64_t target = raw & 0xFFFFFFFFULL;
                            v = (ptr_format == 1) ? target + img->slide : img->header + target;
                        }
                    } else {
                        if (bind) {
                            uint32_t ord = (ptr_format == 12) ? (raw & 0xFFFFFF) : (raw & 0xFFFF);
                            uint64_t add19 = (raw >> 32) & 0x7FFFF;
                            int64_t addend19 = (add19 & 0x40000) ? (int64_t)(add19 | ~0x7FFFFULL) : (int64_t)add19;
                            if (ord < hdr->imports_count) v = imp_addr[ord] + imp_addend[ord] + addend19;
                        } else {
                            uint64_t target = raw & 0x7FFFFFFFFFFULL;
                            uint64_t high8 = (raw >> 43) & 0xFF;
                            v = (ptr_format == 1) ? target + img->slide : img->header + target;
                            v |= (high8 << 56);
                        }
                    }
                    *(uint64_t*)chain_addr = v;
                    if (next == 0) break;
                    chain_addr += next * 8;
                }
            }
        };

        for (uint16_t p = 0; p < page_count; p++) {
            uint16_t pstart = page_starts[p];
            if (pstart == 0xFFFF) continue;
            uint64_t page_addr = seg_mem_base + (uint64_t)p * page_size;
            if (pstart & 0x8000) {   // DYLD_CHAINED_PTR_START_MULTI: overflow list
                uint32_t idx = pstart & 0x7FFF;
                for (;;) {
                    uint16_t v = page_starts[idx++];
                    walk(page_addr + (v & 0x7FFF));
                    if (v & 0x8000) break;
                }
            } else {
                walk(page_addr + pstart);
            }
        }
    }
}

static void apply_rebase_opcodes(MachImage* img) {
    if (!img->rebase || !img->rebase_size || img->slide == 0) return;
    const uint8_t* p = img->rebase;
    const uint8_t* end = p + img->rebase_size;
    uint32_t seg_idx = 0;
    uint64_t seg_off = 0;
    auto do_rebase = [&]() {
        if (seg_idx < img->segs.size()) *(uint64_t*)(img->segs[seg_idx].addr + seg_off) += img->slide;
        seg_off += sizeof(uint64_t);
    };
    while (p < end) {
        uint8_t b = *p++;
        uint8_t op = b & REBASE_OPCODE_MASK, imm = b & REBASE_IMMEDIATE_MASK;
        switch (op) {
            case REBASE_OPCODE_DONE: return;
            case REBASE_OPCODE_SET_TYPE_IMM: break;
            case REBASE_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB:
                seg_idx = imm;
                seg_off = read_uleb128(p, end);
                break;
            case REBASE_OPCODE_ADD_ADDR_ULEB: seg_off += read_uleb128(p, end); break;
            case REBASE_OPCODE_ADD_ADDR_IMM_SCALED: seg_off += (uint64_t)imm * 8; break;
            case REBASE_OPCODE_DO_REBASE_IMM_TIMES:
                for (uint32_t i = 0; i < imm; i++) do_rebase();
                break;
            case REBASE_OPCODE_DO_REBASE_ULEB_TIMES: {
                uint64_t n = read_uleb128(p, end);
                for (uint64_t i = 0; i < n; i++) do_rebase();
                break;
            }
            case REBASE_OPCODE_DO_REBASE_ADD_ADDR_ULEB:
                do_rebase();
                seg_off += read_uleb128(p, end);
                break;
            case REBASE_OPCODE_DO_REBASE_ULEB_TIMES_SKIPPING_ULEB: {
                uint64_t n = read_uleb128(p, end);
                uint64_t skip = read_uleb128(p, end);
                for (uint64_t i = 0; i < n; i++) { do_rebase(); seg_off += skip; }
                break;
            }
            default: break;
        }
    }
}

static void apply_bind_opcodes(MachImage* img, const uint8_t* buf, size_t size) {
    if (!buf || !size) return;
    const uint8_t* p = buf;
    const uint8_t* end = buf + size;
    uint32_t seg_idx = 0;
    uint64_t seg_off = 0;
    const char* sym = "";
    int64_t addend = 0;
    int ordinal = 0;
    bool weak_import = false;

    auto bind_at = [&](uint64_t off) {
        if (seg_idx >= img->segs.size()) return;
        uint64_t addr = img->segs[seg_idx].addr + off;
        uint64_t v = resolve_import(img, ordinal, sym, weak_import);
        *(uint64_t*)addr = v ? v + addend : 0;   // an absent weak import binds to NULL
    };

    while (p < end) {
        uint8_t b = *p++;
        uint8_t op = b & BIND_OPCODE_MASK, imm = b & BIND_IMMEDIATE_MASK;
        switch (op) {
            case BIND_OPCODE_DONE: break;
            case BIND_OPCODE_SET_DYLIB_ORDINAL_IMM: ordinal = imm; break;
            case BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB: ordinal = (int)read_uleb128(p, end); break;
            case BIND_OPCODE_SET_DYLIB_SPECIAL_IMM: ordinal = imm ? (int8_t)(0xF0 | imm) : 0; break;
            case BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM:
                sym = (const char*)p;
                weak_import = imm & 1;
                while (p < end && *p) p++;
                if (p < end) p++;
                break;
            case BIND_OPCODE_SET_TYPE_IMM: break;
            case BIND_OPCODE_SET_ADDEND_SLEB: addend = read_sleb128(p, end); break;
            case BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB:
                seg_idx = imm;
                seg_off = read_uleb128(p, end);
                break;
            case BIND_OPCODE_ADD_ADDR_ULEB: seg_off += read_uleb128(p, end); break;
            case BIND_OPCODE_DO_BIND:
                bind_at(seg_off);
                seg_off += 8;
                break;
            case BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB: {
                bind_at(seg_off);
                seg_off += 8 + read_uleb128(p, end);
                break;
            }
            case BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED:
                bind_at(seg_off);
                seg_off += 8 + (uint64_t)imm * 8;
                break;
            case BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB: {
                uint64_t n = read_uleb128(p, end);
                uint64_t skip = read_uleb128(p, end);
                for (uint64_t i = 0; i < n; i++) { bind_at(seg_off); seg_off += 8 + skip; }
                break;
            }
            default: break;
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Image loading
// ---------------------------------------------------------------------------------------------
static int prot_from_macho(uint32_t p) {
    int r = 0;
    if (p & 1) r |= PROT_READ;
    if (p & 2) r |= PROT_WRITE;
    if (p & 4) r |= PROT_EXEC;
    return r;
}

static std::string dir_of(const std::string& p) {
    size_t s = p.rfind('/');
    return s == std::string::npos ? "." : (s == 0 ? "/" : p.substr(0, s));
}

// Opens a Mach-O file and finds its ARM64 slice. Returns the fd (or -1).
static int open_arm64_slice(const std::string& host_path, uint64_t& slice_offset) {
    int fd = open(host_path.c_str(), O_RDONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    uint32_t magic = 0;
    slice_offset = 0;
    if (pread(fd, &magic, 4, 0) != 4) { close(fd); return -1; }
    if (magic == FAT_MAGIC || magic == FAT_CIGAM || magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64) {
        bool swap = (magic == FAT_CIGAM || magic == FAT_CIGAM_64);
        bool is64 = (magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64);
        fat_header fh;
        if (pread(fd, &fh, sizeof(fh), 0) != sizeof(fh)) { close(fd); return -1; }
        uint32_t narch = swap ? bswap32(fh.nfat_arch) : fh.nfat_arch;
        bool found = false;
        off_t pos = sizeof(fh);
        for (uint32_t i = 0; i < narch && !found; i++) {
            if (is64) {
                fat_arch_64 fa;
                if (pread(fd, &fa, sizeof(fa), pos) != sizeof(fa)) break;
                pos += sizeof(fa);
                if ((swap ? bswap32(fa.cputype) : fa.cputype) == CPU_TYPE_ARM64) {
                    slice_offset = swap ? bswap64(fa.offset) : fa.offset;
                    found = true;
                }
            } else {
                fat_arch fa;
                if (pread(fd, &fa, sizeof(fa), pos) != sizeof(fa)) break;
                pos += sizeof(fa);
                if ((swap ? bswap32(fa.cputype) : fa.cputype) == CPU_TYPE_ARM64) {
                    slice_offset = swap ? bswap32(fa.offset) : fa.offset;
                    found = true;
                }
            }
        }
        if (!found) { close(fd); return -1; }
    }
    return fd;
}

static MachImage* load_dependency(MachImage* from, const std::string& name, bool weak);

// Homebrew bottles not relocated by `brew pour` keep @@HOMEBREW_CELLAR@@ / @@HOMEBREW_PREFIX@@ in load commands
// (tools/fetch_bottle.py patches only what fits in place); resolve them to the default /opt/homebrew prefix.
static std::string homebrew_placeholders(std::string s) {
    static const std::pair<const char*, const char*> kMap[] = {
        {"@@HOMEBREW_CELLAR@@", "/opt/homebrew/Cellar"}, {"@@HOMEBREW_PREFIX@@", "/opt/homebrew"}};
    for (const auto& [from, to] : kMap)
        for (size_t p; (p = s.find(from)) != std::string::npos;) s.replace(p, strlen(from), to);
    return s;
}

static std::vector<std::string> expand_candidates(const std::string& name_in, MachImage* from) {
    std::vector<std::string> out;
    const std::string name = homebrew_placeholders(name_in);
    auto subst = [&](const std::string& s_in, MachImage* ctx) -> std::vector<std::string> {
        const std::string s = homebrew_placeholders(s_in);
        std::vector<std::string> res;
        auto add_path = [&](const std::string& dir, const std::string& rel) {
            res.push_back(dir + "/" + rel);
        };
        if (s.rfind("@executable_path/", 0) == 0) {
            add_path(g_exe_dir, s.substr(17));
            if (!g_exe_real_dir.empty() && g_exe_real_dir != g_exe_dir)
                add_path(g_exe_real_dir, s.substr(17));
        } else if (s.rfind("@loader_path/", 0) == 0) {
            std::string d1 = dir_of(ctx ? ctx->path : g_exe_dir);
            add_path(d1, s.substr(13));
            if (ctx && !ctx->real_path.empty()) {
                std::string d2 = dir_of(ctx->real_path);
                if (d2 != d1) add_path(d2, s.substr(13));
            }
        } else {
            res.push_back(s);
        }
        return res;
    };
    if (name.rfind("@rpath/", 0) == 0) {
        std::string tail = name.substr(7);
        std::vector<MachImage*> ctxs;
        if (from) ctxs.push_back(from);
        if (!g_images.empty() && (from != g_images[0])) ctxs.push_back(g_images[0]);
        for (MachImage* c : ctxs) {
            for (const std::string& rp : c->rpaths) {
                for (const std::string& exp : subst(rp, c))
                    out.push_back(exp + "/" + tail);
            }
        }
    } else {
        for (const std::string& exp : subst(name, from))
            out.push_back(exp);
    }
    return out;
}

static MachImage* map_image(const std::string& guest_path, const std::string& host_path, bool is_main);

static MachImage* find_loaded(const std::string& key) {
    auto it = g_by_name.find(key);
    return it == g_by_name.end() ? nullptr : it->second;
}

// host realpath -> image: like dyld (which compares inodes), a dylib reached through a symlink
// (libosgDB.162.dylib -> libosgDB.3.6.5.dylib) is the same image, not a second copy with its own globals
static std::unordered_map<std::string, MachImage*> g_by_host_real;

static MachImage* load_dependency(MachImage* from, const std::string& name, bool weak) {
    if (MachImage* im = find_loaded(name)) return im;
    for (const std::string& cand : expand_candidates(name, from)) {
        if (MachImage* im = find_loaded(cand)) return im;
        std::string host = resolve_guest_path(cand.c_str());
        if (access(host.c_str(), R_OK) != 0) continue;
        char rp[PATH_MAX];
        std::string real = realpath(host.c_str(), rp) ? std::string(rp) : host;
        auto same = g_by_host_real.find(real);
        if (same != g_by_host_real.end()) {
            g_by_name[name] = same->second;
            return same->second;
        }
        bool fat, arm;
        if (!is_macho_binary(host.c_str(), fat, arm) || !arm) continue;
        MachImage* im = map_image(cand, host, false);
        if (im) {
            g_by_name[name] = im;
            g_by_host_real[real] = im;
            return im;
        }
    }
    XEF_LOG(weak ? 2 : 1, "xef-osx: dependency %s not found in the rootfs (HLE)", name.c_str());
    return nullptr;
}

static MachImage* map_image(const std::string& guest_path, const std::string& host_path, bool is_main) {
    uint64_t slice_offset = 0;
    int fd = open_arm64_slice(host_path, slice_offset);
    if (fd < 0) return nullptr;

    mach_header_64 mh;
    if (pread(fd, &mh, sizeof(mh), slice_offset) != sizeof(mh) || mh.magic != MH_MAGIC_64 ||
        mh.cputype != CPU_TYPE_ARM64) {
        close(fd);
        return nullptr;
    }
    std::vector<uint8_t> cmds(mh.sizeofcmds);
    if (pread(fd, cmds.data(), mh.sizeofcmds, slice_offset + sizeof(mh)) != (ssize_t)mh.sizeofcmds) {
        close(fd);
        return nullptr;
    }

    std::unique_ptr<MachImage> im(new MachImage());
    im->path = guest_path;
    im->install_name = guest_path;
    std::string real_guest = guest_path;
    if (!g_rootfs.empty() && host_path.rfind(g_rootfs, 0) == 0) {
        real_guest = host_path.substr(g_rootfs.size());
        if (real_guest.empty() || real_guest[0] != '/') real_guest = "/" + real_guest;
    }
    im->real_path = real_guest;
    im->filetype = mh.filetype;

    // pass 1: segments -> address range
    uint64_t lo = ~0ull, hi = 0;
    uint64_t text_vmaddr = 0;
    uint32_t off = 0;
    for (uint32_t i = 0; i < mh.ncmds && off + sizeof(load_command) <= mh.sizeofcmds; i++) {
        const load_command* lc = (const load_command*)&cmds[off];
        if (lc->cmdsize < 8 || off + lc->cmdsize > mh.sizeofcmds) break;
        if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(segment_command_64)) {
            const segment_command_64* sg = (const segment_command_64*)lc;
            if (strncmp(sg->segname, "__PAGEZERO", 16) != 0 && sg->vmsize) {
                lo = std::min<uint64_t>(lo, sg->vmaddr);
                hi = std::max<uint64_t>(hi, sg->vmaddr + sg->vmsize);
            }
            if (strncmp(sg->segname, "__TEXT", 16) == 0) text_vmaddr = sg->vmaddr;
        }
        off += lc->cmdsize;
    }
    if (lo == ~0ull) { close(fd); return nullptr; }

    // placement: the executable at its preferred address, dylibs wherever the host has room
    uint64_t slide = 0;
    if (!is_main) {
        const uint64_t align = 0x4000;
        uint64_t span = page_align_up(hi - lo) + align;
        void* r = mmap(nullptr, span, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
        if (r == MAP_FAILED) { close(fd); return nullptr; }
        uint64_t base = ((uint64_t)r + align - 1) & ~(align - 1);
        slide = base - lo;
    }
    im->slide = slide;
    im->header = text_vmaddr + slide;

    // pass 2: map
    off = 0;
    for (uint32_t i = 0; i < mh.ncmds && off + sizeof(load_command) <= mh.sizeofcmds; i++) {
        const load_command* lc = (const load_command*)&cmds[off];
        if (lc->cmdsize < 8 || off + lc->cmdsize > mh.sizeofcmds) break;
        uint32_t cmd = lc->cmd;

        if (cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(segment_command_64)) {
            const segment_command_64* sg = (const segment_command_64*)lc;
            MachSegment ms = {};
            memcpy(ms.name, sg->segname, 16);
            ms.addr = sg->vmaddr + slide;
            ms.size = sg->vmsize;
            ms.fileoff = sg->fileoff;
            ms.filesize = sg->filesize;
            ms.initprot = sg->initprot;
            im->segs.push_back(ms);

            if (strncmp(sg->segname, "__PAGEZERO", 16) == 0) {
                if (sg->vmsize)
                    mmap((void*)sg->vmaddr, sg->vmsize, PROT_NONE,
                         MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
            } else if (sg->vmsize) {
                uint64_t target = sg->vmaddr + slide;
                int prot = prot_from_macho(sg->initprot) | PROT_WRITE;   // writable while fixups run
                if (sg->filesize) {
                    uint64_t start = page_align_down(target);
                    uint64_t file_start = page_align_down(slice_offset + sg->fileoff);
                    uint64_t len = page_align_up(sg->filesize + (target - start));
                    void* r = mmap((void*)start, len, prot, MAP_PRIVATE | MAP_FIXED, fd, file_start);
                    if (r == MAP_FAILED) {
                        fprintf(stderr, "xef-osx: cannot map segment %.16s of %s: %m\n", sg->segname,
                                host_path.c_str());
                        close(fd);
                        return nullptr;
                    }
                    if (sg->vmsize > sg->filesize) {
                        uint64_t bss = target + sg->filesize;
                        uint64_t bss_page = page_align_up(bss);
                        if (bss_page > bss) memset((void*)bss, 0, bss_page - bss);
                        uint64_t bss_end = page_align_up(target + sg->vmsize);
                        if (bss_end > bss_page)
                            mmap((void*)bss_page, bss_end - bss_page, prot,
                                 MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
                    }
                } else {
                    mmap((void*)page_align_down(target), page_align_up(sg->vmsize), prot,
                         MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
                }
            }

            // sections of interest
            const section_64* sects = (const section_64*)(sg + 1);
            for (uint32_t s = 0; s < sg->nsects && (const uint8_t*)(sects + s + 1) <= (const uint8_t*)lc + lc->cmdsize; s++) {
                const section_64& sc = sects[s];
                uint64_t a = sc.addr + slide;
                {
                    MachSection ms2 = {};
                    memcpy(ms2.seg, sc.segname, 16); memcpy(ms2.sect, sc.sectname, 16);
                    ms2.addr = a; ms2.size = sc.size;
                    im->sects.push_back(ms2);
                }
                uint32_t type = sc.flags & 0xFF;
                if (!strncmp(sc.sectname, "__unwind_info", 16)) { im->unwind_info = a; im->unwind_info_size = sc.size; }
                else if (!strncmp(sc.sectname, "__eh_frame", 16)) { im->eh_frame = a; im->eh_frame_size = sc.size; }
                else if (type == 0x13) { im->tlv_vars = a; im->tlv_vars_size = sc.size; }   // S_THREAD_LOCAL_VARIABLES
                else if (type == 0x11) {                                                     // S_THREAD_LOCAL_REGULAR
                    im->tlv_init = a; im->tlv_init_size = sc.size;
                    im->tlv_total = std::max<uint64_t>(im->tlv_total, sc.size);
                } else if (type == 0x12) {                                                   // S_THREAD_LOCAL_ZEROFILL
                    if (!im->tlv_init) im->tlv_init = a;
                    im->tlv_total = std::max<uint64_t>(im->tlv_total, a + sc.size - im->tlv_init);
                } else if (type == 0x09 || type == 0x16) {   // S_MOD_INIT_FUNC_POINTERS / S_INIT_FUNC_OFFSETS
                    im->init_sections.push_back({a, sc.size, type});
                }
            }
        } else if (cmd == LC_LOAD_DYLIB || cmd == LC_LOAD_WEAK_DYLIB || cmd == LC_REEXPORT_DYLIB ||
                   cmd == LC_LOAD_UPWARD_DYLIB) {
            const dylib_command* dc = (const dylib_command*)lc;
            MachDep d;
            d.name = (const char*)lc + dc->dylib_info.name.offset;
            d.reexport = cmd == LC_REEXPORT_DYLIB;
            d.weak = cmd == LC_LOAD_WEAK_DYLIB;
            im->deps.push_back(d);
        } else if (cmd == LC_ID_DYLIB) {
            const dylib_command* dc = (const dylib_command*)lc;
            im->install_name = (const char*)lc + dc->dylib_info.name.offset;
        } else if (cmd == LC_RPATH) {
            im->rpaths.push_back((const char*)lc + 12);
        } else if (cmd == LC_MAIN && lc->cmdsize >= sizeof(entry_point_command)) {
            im->entry = text_vmaddr + slide + ((const entry_point_command*)lc)->entryoff;
        } else if (cmd == LC_ROUTINES_64 && lc->cmdsize >= 24) {
            // `ld -init`: the library's initializer routine runs before the __mod_init_func entries
            im->routines_init = *(const uint64_t*)((const uint8_t*)lc + 8) + slide;
        } else if (cmd == LC_UNIXTHREAD) {
            const uint32_t* p = (const uint32_t*)(lc + 1);
            if (p[0] == ARM_THREAD_STATE64 && p[1] >= sizeof(arm_thread_state64_t) / 4)
                im->entry = ((const arm_thread_state64_t*)(p + 2))->pc + slide;
        }
        off += lc->cmdsize;
    }

    // pass 3: dyld metadata -> pointers into the mapped __LINKEDIT
    const MachSegment* le = nullptr;
    for (const MachSegment& s : im->segs)
        if (!strncmp(s.name, "__LINKEDIT", 16)) le = &s;
    auto le_ptr = [&](uint32_t fileoff) -> const uint8_t* {
        return le ? (const uint8_t*)(le->addr + (fileoff - le->fileoff)) : nullptr;
    };
    off = 0;
    for (uint32_t i = 0; i < mh.ncmds && off + sizeof(load_command) <= mh.sizeofcmds; i++) {
        const load_command* lc = (const load_command*)&cmds[off];
        if (lc->cmdsize < 8 || off + lc->cmdsize > mh.sizeofcmds) break;
        if (lc->cmd == LC_DYLD_CHAINED_FIXUPS) {
            const linkedit_data_command* d = (const linkedit_data_command*)lc;
            im->chained = le_ptr(d->dataoff);
            im->chained_size = d->datasize;
        } else if (lc->cmd == LC_DYLD_EXPORTS_TRIE) {
            const linkedit_data_command* d = (const linkedit_data_command*)lc;
            im->exports = le_ptr(d->dataoff);
            im->exports_size = d->datasize;
        } else if (lc->cmd == LC_DYLD_INFO || lc->cmd == LC_DYLD_INFO_ONLY) {
            const dyld_info_command* d = (const dyld_info_command*)lc;
            if (d->rebase_size) { im->rebase = le_ptr(d->rebase_off); im->rebase_size = d->rebase_size; }
            if (d->bind_size) { im->bind = le_ptr(d->bind_off); im->bind_size = d->bind_size; }
            if (d->weak_bind_size) { im->weak_bind = le_ptr(d->weak_bind_off); im->weak_bind_size = d->weak_bind_size; }
            if (d->lazy_bind_size) { im->lazy_bind = le_ptr(d->lazy_bind_off); im->lazy_bind_size = d->lazy_bind_size; }
            if (d->export_size && !im->exports) { im->exports = le_ptr(d->export_off); im->exports_size = d->export_size; }
        } else if (lc->cmd == LC_SYMTAB) {
            const symtab_command* st = (const symtab_command*)lc;
            const nlist_64* nl = (const nlist_64*)le_ptr(st->symoff);
            const char* strs = (const char*)le_ptr(st->stroff);
            if (nl && strs) {
                for (uint32_t j = 0; j < st->nsyms; j++) {
                    uint8_t type = nl[j].n_type;
                    if ((type & N_STAB) == 0 && (type & N_EXT)) {
                        if (nl[j].n_un.n_strx < st->strsize) {
                            const char* sname = strs + nl[j].n_un.n_strx;
                            if (*sname) {
                                if ((type & N_TYPE) == N_SECT) {
                                    im->symtab_exports[sname] = nl[j].n_value + slide;
                                } else if ((type & N_TYPE) == N_ABS) {
                                    im->symtab_exports[sname] = nl[j].n_value;
                                }
                            }
                        }
                    }
                }
            }
        }
        off += lc->cmdsize;
    }
    close(fd);

    MachImage* raw = im.release();
    raw->index = (uint32_t)g_images.size();
    g_images.push_back(raw);
    g_by_name[guest_path] = raw;
    if (raw->install_name != guest_path) g_by_name[raw->install_name] = raw;
    XEF_LOG(1, "xef-osx: mapped %s at %#lx (slide %#lx, %zu deps)", guest_path.c_str(),
            (unsigned long)raw->header, (unsigned long)raw->slide, raw->deps.size());
    return raw;
}

// Maps the dependencies of `im` (depth first) after the image itself is registered.
static void load_dependencies(MachImage* im) {
    for (size_t i = 0; i < im->deps.size(); i++) {
        size_t before = g_images.size();
        MachImage* d = load_dependency(im, im->deps[i].name, im->deps[i].weak);
        im->deps[i].image = d;
        if (d && g_images.size() > before) load_dependencies(d);
    }
}

// Rebase + bind one image, then restore the segment protections.
static void link_image(MachImage* im) {
    if (im->bound) return;
    im->bound = true;
    // dependencies first so that re-exports resolve
    for (MachDep& d : im->deps)
        if (d.image && !d.image->bound) link_image(d.image);

    apply_rebase_opcodes(im);
    apply_bind_opcodes(im, im->bind, im->bind_size);
    apply_bind_opcodes(im, im->weak_bind, im->weak_bind_size);
    apply_bind_opcodes(im, im->lazy_bind, im->lazy_bind_size);
    apply_chained_fixups(im);

    // initializers (pointers are final now)
    if (im->routines_init) im->inits.push_back(im->routines_init);
    for (const MachImage::InitSection& s : im->init_sections) {
        if (s.type == 0x09) {
            for (uint64_t o = 0; o + 8 <= s.size; o += 8)
                if (uint64_t f = *(uint64_t*)(s.addr + o)) im->inits.push_back(f);
        } else {
            for (uint64_t o = 0; o + 4 <= s.size; o += 4)
                im->inits.push_back(im->header + *(uint32_t*)(s.addr + o));
        }
    }

    // thread-local descriptors: key = image index + 1 (see dyld_tlv_address)
    for (uint64_t o = 0; o + 24 <= im->tlv_vars_size; o += 24)
        ((uint64_t*)(im->tlv_vars + o))[1] = im->index + 1;

    for (const MachSegment& s : im->segs) {
        if (!s.size || !strncmp(s.name, "__PAGEZERO", 16)) continue;
        mprotect((void*)page_align_down(s.addr), page_align_up(s.size + (s.addr & 4095)),
                 prot_from_macho(s.initprot));
    }
    // outlined helpers that return a value in NZCV need their RETs to keep the flags (a64::ret_keeps_flags)
    for (const MachSection& sc : im->sects) {
        if (!strncmp(sc.seg, "__TEXT", 16) && !strncmp(sc.sect, "__text", 16)) a64::scan_flag_returning_calls(sc.addr, sc.addr + sc.size);
        // Go's compiler does not follow AAPCS64 for NZCV: type-switch jump tables branch (BR) with the flags of an
        // earlier CMP still live at the target. Translate the whole process with strict flag semantics.
        if (!strncmp(sc.sect, "__go_buildinfo", 16) && a64::g_abi_flags) {
            a64::g_abi_flags = false;
            XEF_LOG(1, "xef-osx: %s is a Go binary: NZCV kept across calls/returns/indirect branches", im->path.c_str());
        }
    }
}

static void link_all() {
    for (size_t i = 0; i < g_images.size(); i++) link_image(g_images[i]);
}

// Dylibs that libSystem would provide but that live as separate files in our rootfs.
static void load_implicit_images() {
    static const char* const kImplicit[] = {"/usr/lib/libunwind.1.dylib", "/usr/lib/system/libsystem_blocks.dylib",
                                            "/usr/lib/libobjc.A.dylib", "/usr/lib/system/libdispatch.dylib",
                                            "/usr/lib/system/libsystem_fts.dylib"};
    for (const char* n : kImplicit) {
        if (find_loaded(n)) continue;
        std::string host = resolve_guest_path(n);
        if (access(host.c_str(), R_OK) != 0) continue;
        if (MachImage* im = map_image(n, host, false)) load_dependencies(im);
    }
}

bool load_macho(const char* path, LoadedImage& img) {
    std::lock_guard<std::recursive_mutex> lk(g_dyld_lock);
    img.exe_path = path;
    img.host_path = resolve_guest_path(path, true);
    if (access(img.host_path.c_str(), R_OK) != 0) img.host_path = path;

    // Initialize commpage for macOS guest
    commpage_init();
    darwin_hle_init();

    char rp[4096];
    g_exe_dir = dir_of(realpath(path, rp) ? std::string(rp) : std::string(path));
    if (realpath(img.host_path.c_str(), rp)) {
        std::string rh = rp;
        if (!g_rootfs.empty() && rh.rfind(g_rootfs, 0) == 0) {
            rh = rh.substr(g_rootfs.size());
            if (rh.empty() || rh[0] != '/') rh = "/" + rh;
        }
        g_exe_real_dir = dir_of(rh);
    } else {
        g_exe_real_dir = g_exe_dir;
    }

    MachImage* exe = map_image(path, img.host_path, true);
    if (!exe) return false;
    if (!exe->entry) {
        fprintf(stderr, "xef-osx: No entry point found in Mach-O binary\n");
        return false;
    }
    load_dependencies(exe);
    load_implicit_images();
    link_all();

    img.exe_base = exe->header;
    img.min_addr = ~0ull;
    img.max_addr = 0;
    for (const MachSegment& s : exe->segs) {
        if (!s.size || !strncmp(s.name, "__PAGEZERO", 16)) continue;
        img.min_addr = std::min<GuestAddr>(img.min_addr, s.addr);
        img.max_addr = std::max<GuestAddr>(img.max_addr, s.addr + s.size);
    }
    img.entry = exe->entry;
    img.exe_entry = exe->entry;
    img.brk_start = page_align_up(img.max_addr);
    XEF_LOG(1, "xef-osx: Mach-O ARM64 loaded %s: base=%#lx entry=%#lx min=%#lx max=%#lx (%zu images)",
            path, (unsigned long)img.exe_base, (unsigned long)img.entry,
            (unsigned long)img.min_addr, (unsigned long)img.max_addr, g_images.size());
    return true;
}

// ---------------------------------------------------------------------------------------------
// Initializers, dlopen, TLV
// ---------------------------------------------------------------------------------------------
static u64 g_objc_map = 0, g_objc_init = 0, g_objc_unmap = 0;
static bool g_objc_v4 = false;   // dyld_objc_register_callbacks(): load_images takes a mapped_info

// struct _dyld_objc_notify_mapped_info
struct ObjcMappedInfo { uint64_t mh; const char* path; uint64_t section_metadata; uint32_t flags; uint32_t pad; };

static void objc_map_images(const std::vector<MachImage*>& imgs) {
    if (imgs.empty()) return;
    std::vector<const char*> paths;
    std::vector<uint64_t> mhdrs;
    for (MachImage* im : imgs) { paths.push_back(im->path.c_str()); mhdrs.push_back(im->header); }
    u64 a[3] = {(u64)imgs.size(), (u64)(uintptr_t)paths.data(), (u64)(uintptr_t)mhdrs.data()};
    // libobjc exports _objc_map_images(count, paths, mhdrs), which builds the infos and the block itself
    if (g_objc_v4) {
        if (uint64_t f = dyld_flat_lookup("__objc_map_images")) guest_call(f, 3, a);
    } else if (g_objc_map) {
        guest_call(g_objc_map, 3, a);
    }
}

static void objc_notify_init(MachImage* im) {
    if (!g_objc_init) return;
    if (g_objc_v4) {
        ObjcMappedInfo info = {im->header, im->path.c_str(), 0, 0, 0};
        u64 a[1] = {(u64)(uintptr_t)&info};
        guest_call(g_objc_init, 1, a);
    } else {
        u64 a[2] = {(u64)(uintptr_t)im->path.c_str(), im->header};
        guest_call(g_objc_init, 2, a);
    }
}

static void fixup_tagged_pointer_classes() {
    uint64_t fn_register = dyld_flat_lookup("__objc_registerTaggedPointerClass");
    if (!fn_register) return;

    uint64_t fn_objc_getclass = dyld_flat_lookup("_objc_getClass");
    auto get_objc_class = [&](const char* name) -> uint64_t {
        std::string sym = std::string("_OBJC_CLASS_$_") + name;
        uint64_t c = dyld_flat_lookup(sym.c_str());
        if (!c) c = dyld_flat_lookup((std::string("OBJC_CLASS_$_") + name).c_str());
        if (!c && fn_objc_getclass) {
            uint64_t a[1] = {(uint64_t)(uintptr_t)name};
            c = guest_call(fn_objc_getclass, 1, a);
        }
        return c;
    };

    uint64_t cls_ind_str = get_objc_class("NSIndirectTaggedPointerString");
    uint64_t cls_tag_str = get_objc_class("NSTaggedPointerString");
    if (!cls_tag_str) cls_tag_str = get_objc_class("__NSCFConstantString");
    if (!cls_tag_str) cls_tag_str = get_objc_class("__NSCFString");
    if (!cls_ind_str) cls_ind_str = cls_tag_str;
    uint64_t cls_cf_num  = get_objc_class("__NSCFNumber");
    uint64_t cls_tag_date = get_objc_class("__NSTaggedDate");

    uint64_t fn_getclass_tag = dyld_flat_lookup("__objc_getClassForTag");

    auto try_register = [&](uint64_t tag, uint64_t cls) {
        if (!cls) return;
        if (fn_getclass_tag) {
            uint64_t a[1] = {tag};
            if (guest_call(fn_getclass_tag, 1, a) != 0) return;
        }
        uint64_t args[2] = {tag, cls};
        guest_call(fn_register, 2, args);
    };

    // In addition, populate objc_debug_taggedpointer_classes slots directly:
    // _objc_msgSend on ARM64 directly indexes objc_debug_taggedpointer_classes[x0 & 7]
    uint64_t dbg_classes = dyld_flat_lookup("_objc_debug_taggedpointer_classes");
    uint64_t dbg_perms   = dyld_flat_lookup("_objc_debug_tag60_permutations");

    if (dbg_perms) {
        // Set identity permutation so tag == slot
        for (int i = 0; i < 8; i++) {
            ((uint8_t*)(uintptr_t)dbg_perms)[i] = (uint8_t)i;
        }
    }

    try_register(0, cls_ind_str ? cls_ind_str : cls_cf_num);
    try_register(1, cls_cf_num);
    try_register(2, cls_tag_str ? cls_tag_str : cls_cf_num);
    try_register(3, cls_cf_num);
    if (cls_tag_date) try_register(4, cls_tag_date);
    try_register(5, cls_cf_num);
    try_register(6, cls_cf_num);

    if (dbg_classes && cls_cf_num) {
        uint64_t* slots = (uint64_t*)(uintptr_t)dbg_classes;
        if (cls_ind_str) slots[0] = cls_ind_str;
        if (!slots[1]) slots[1] = cls_cf_num;
        if (cls_tag_str) slots[2] = cls_tag_str;
        if (!slots[3]) slots[3] = cls_cf_num;
        if (cls_tag_date) slots[4] = cls_tag_date;
        for (int i = 0; i < 8; i++) {
            if (!slots[i]) slots[i] = cls_cf_num;
        }
    }

    uint64_t dbg_ext = dyld_flat_lookup("_objc_debug_taggedpointer_ext_classes");
    if (dbg_ext && cls_cf_num) {
        uint64_t* ext_slots = (uint64_t*)(uintptr_t)dbg_ext;
        for (int i = 0; i < 256; i++) {
            if (!ext_slots[i]) ext_slots[i] = cls_cf_num;
        }
    }

    XEF_LOG(1, "xef-osx: registered tagged pointer classes (str=%#lx, num=%#lx, dbg_classes=%#lx)",
            (unsigned long)cls_tag_str, (unsigned long)cls_cf_num, (unsigned long)dbg_classes);
}

static void objc_registered() {
    std::vector<MachImage*> all(g_images.begin(), g_images.end());
    objc_map_images(all);
    for (MachImage* im : all)
        if (im->initialized && im->install_name != "/usr/lib/libobjc.A.dylib") objc_notify_init(im);
}

void dyld_objc_notify_register(uint64_t map, uint64_t init, uint64_t unmap) {
    g_objc_map = map; g_objc_init = init; g_objc_unmap = unmap;
    g_objc_v4 = false;
    objc_registered();
}

// _dyld_objc_register_callbacks(const struct _dyld_objc_callbacks*): version 2..4 layout
void dyld_objc_register_callbacks(uint64_t cbs) {
    const uint64_t* c = (const uint64_t*)cbs;
    g_objc_map = c[1]; g_objc_init = c[2]; g_objc_unmap = c[3];
    g_objc_v4 = true;
    objc_registered();
}

static void run_inits_of(MachImage* im, std::vector<MachImage*>& seen, const u64* args) {
    if (im->initialized) return;
    for (MachImage* s : seen) if (s == im) return;
    seen.push_back(im);
    for (MachDep& d : im->deps)
        if (d.image) run_inits_of(d.image, seen, args);
    im->initialized = true;
    objc_notify_init(im);
    for (uint64_t f : im->inits) {
        XEF_LOG(2, "xef-osx: init %s: %#lx", im->path.c_str(), (unsigned long)f);
        guest_call(f, 4, args);
    }
    if (im->install_name == "/usr/lib/libobjc.A.dylib") {
        // Disable tagged pointer obfuscation so tags and pointers are standard and predictable
        if (uint64_t dis = dyld_image_lookup(im, "_DisableTaggedPointerObfuscation")) {
            *(uint32_t*)(uintptr_t)dis = 1;
        }
        // libSystem's initializer would call _objc_init(); it registers the dyld notifications
        if (uint64_t f = dyld_image_lookup(im, "__objc_init")) guest_call(f, 0, nullptr);
    }
}

void dyld_run_initializers(uint64_t argc, uint64_t argv, uint64_t envp, uint64_t apple) {
    std::lock_guard<std::recursive_mutex> lk(g_dyld_lock);
    u64 args[4] = {argc, argv, envp, apple};
    std::vector<MachImage*> seen;
    // implicit images (libunwind) first, then the executable's tree
    for (size_t i = g_images.size(); i-- > 1;) run_inits_of(g_images[i], seen, args);
    if (!g_images.empty()) run_inits_of(g_images[0], seen, args);
    fixup_tagged_pointer_classes();
}

MachImage* dyld_dlopen(const char* path) {
    std::lock_guard<std::recursive_mutex> lk(g_dyld_lock);
    if (!path) return g_images.empty() ? nullptr : g_images[0];
    size_t before = g_images.size();
    MachImage* im = load_dependency(g_images.empty() ? nullptr : g_images[0], path, false);
    if (!im) return nullptr;
    if (g_images.size() > before || !im->bound) {
        for (size_t i = before; i < g_images.size(); i++) load_dependencies(g_images[i]);
        link_all();
        fixup_tagged_pointer_classes();
        u64 args[4] = {(u64)g_darwin_argc, (u64)(uintptr_t)g_darwin_argv, (u64)(uintptr_t)g_darwin_envp, 0};
        std::vector<MachImage*> seen;
        objc_map_images(std::vector<MachImage*>(g_images.begin() + before, g_images.end()));
        for (size_t i = before; i < g_images.size(); i++) run_inits_of(g_images[i], seen, args);
        run_inits_of(im, seen, args);
    }
    return im;
}

void* dyld_tlv_address(uint64_t desc_addr) {
    struct Desc { uint64_t thunk, key, offset; };
    const Desc* d = (const Desc*)desc_addr;
    MachImage* im = nullptr;
    if (d->key >= 1 && d->key <= g_images.size()) im = g_images[d->key - 1];
    if (!im) im = dyld_image_containing(desc_addr);
    if (!im) return nullptr;
    static thread_local std::vector<void*> blocks;
    if (blocks.size() <= im->index) blocks.resize(im->index + 1, nullptr);
    void*& b = blocks[im->index];
    if (!b) {
        size_t total = std::max<uint64_t>(im->tlv_total, 16);
        b = calloc(1, total + 64);
        if (im->tlv_init && im->tlv_init_size) memcpy(b, (void*)im->tlv_init, im->tlv_init_size);
    }
    return (uint8_t*)b + d->offset;
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

GuestAddr setup_darwin_stack(const LoadedImage& img, int argc, char** argv, char** envp, CpuState* st) {
    const u64 stack_size = 8ull << 20, guard = 64 << 10;
    void* r = mmap(nullptr, stack_size + guard, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    if (r == MAP_FAILED) fatal("cannot allocate guest stack");
    mprotect(r, guard, PROT_NONE);

    u8* top = (u8*)r + guard + stack_size;
    u8* sp = top;

    // Prepare Apple auxiliary strings
    std::string exec_path_str = "executable_path=" + img.exe_path;
    std::vector<std::string> apple_strs;
    apple_strs.push_back(exec_path_str);
    apple_strs.push_back("pf=Darwin");

    // Strings go in ascending order like XNU lays them out: argv, then envp, then the apple strings,
    // contiguous (libuv's uv_set_process_title reuses argv[0]..argv[argc-1] as one buffer).
    size_t total = 0;
    for (int j = 0; j < argc; j++) total += strlen(argv[j]) + 1;
    for (int j = 0; envp && envp[j]; j++) total += strlen(envp[j]) + 1;
    for (const auto& as : apple_strs) total += as.size() + 1;
    sp -= (total + 15) & ~(size_t)15;
    u8* wp = sp;
    auto put_str = [&](const char* s) -> GuestAddr {
        size_t n = strlen(s) + 1;
        memcpy(wp, s, n);
        GuestAddr r = (GuestAddr)(uintptr_t)wp;
        wp += n;
        return r;
    };

    std::vector<GuestAddr> argv_addrs;
    for (int j = 0; j < argc; j++) {
        GuestAddr a = put_str(argv[j]);
        XEF_LOG(2, "setup_darwin_stack: argv[%d] = '%s' at %#lx", j, argv[j], (unsigned long)a);
        argv_addrs.push_back(a);
    }
    std::vector<GuestAddr> envp_addrs;
    for (int j = 0; envp && envp[j]; j++) envp_addrs.push_back(put_str(envp[j]));
    std::vector<GuestAddr> apple_addrs;
    for (const auto& as : apple_strs) apple_addrs.push_back(put_str(as.c_str()));

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
        // the start stub runs the images' initializers, then branches to the entry point
        g_darwin_start_target = img.entry;
        st->pc = g_darwin_start_stub;
        st->eflags = 0x203; // Canonical flags (AArch64 NZCV = 0, Carry = 0)
    }

    return final_sp;
}

} // namespace xef
