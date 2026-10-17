// Parser of the Metal library container (MTLB, "default.metallib"). Header-only, no LLVM dependency.
// Layout (little endian), as written by Apple's metallib tool:
//   header: "MTLB", u16 platform, u16 version major/minor, u8 file type, u8 os, u16 os version major/minor,
//           u64 file size, u64 function list offset/size, public metadata offset/size,
//           private metadata offset/size, bitcode offset/size
//   function list: u32 count, then per function: u32 entry size, tags (fourcc + u16 size + data) up to "ENDT"
//   tags: NAME (cstring), TYPE (u8: 0 vertex 1 fragment 2 kernel 3 unqualified/visible 7 mesh 8 object),
//         MDSZ (u64 bitcode size), OFFT (u64 public md, private md, bitcode offsets relative to their sections)
#pragma once
#include <cstdint>
#include <algorithm>
#include <cstring>
#include <string>
#include <vector>

namespace xef::metallib {

enum FnType : uint8_t { FN_VERTEX = 0, FN_FRAGMENT = 1, FN_KERNEL = 2, FN_VISIBLE = 3, FN_INTERSECTION = 4, FN_MESH = 7, FN_OBJECT = 8, FN_UNKNOWN = 0xff };

struct Function {
    std::string name;
    uint8_t type = FN_UNKNOWN;
    const uint8_t* bitcode = nullptr;   // points into the library data
    size_t bitcode_size = 0;
    uint8_t tess_patch = 0;             // TESS tag: 1 triangle, 2 quad
    uint8_t tess_cp = 0;
};

inline uint64_t rd64(const uint8_t* p) { uint64_t v; memcpy(&v, p, 8); return v; }
inline uint32_t rd32(const uint8_t* p) { uint32_t v; memcpy(&v, p, 4); return v; }
inline uint16_t rd16(const uint8_t* p) { uint16_t v; memcpy(&v, p, 2); return v; }

inline bool is_metallib(const void* data, size_t size) { return size >= 88 && memcmp(data, "MTLB", 4) == 0; }

// Fills `out`; returns false (with a message) on malformed data. Pointers refer into `data`.
inline bool parse(const void* data, size_t size, std::vector<Function>& out, std::string* err = nullptr) {
    auto fail = [&](const char* m) { if (err) *err = m; return false; };
    const uint8_t* d = (const uint8_t*)data;
    if (!is_metallib(data, size)) return fail("not a metallib (bad magic)");
    uint64_t fl_off = rd64(d + 24), fl_size = rd64(d + 32);
    uint64_t bc_off = rd64(d + 72), bc_size = rd64(d + 80);
    if (fl_off > size || fl_size > size - fl_off || bc_off > size || bc_size > size - bc_off) return fail("metallib: section out of range");
    const uint8_t* p = d + fl_off;
    // the list size does not include the leading u32 count
    const uint8_t* fend = d + std::min<uint64_t>(size, fl_off + 4 + fl_size);
    if (p + 4 > fend) return fail("metallib: empty function list");
    uint32_t count = rd32(p); p += 4;
    for (uint32_t i = 0; i < count; i++) {
        if (p + 4 > fend) return fail("metallib: truncated function list");
        uint32_t esize = rd32(p);
        const uint8_t* q = p + 4;
        const uint8_t* qend = p + esize;
        if (esize < 4 || qend > fend) return fail("metallib: bad function entry size");
        Function f;
        uint64_t bc_rel = ~0ull, bc_len = 0;
        while (q + 4 <= qend) {
            if (!memcmp(q, "ENDT", 4)) break;
            if (q + 6 > qend) break;
            uint16_t tsz = rd16(q + 4);
            const uint8_t* v = q + 6;
            if (v + tsz > qend) return fail("metallib: tag out of range");
            if (!memcmp(q, "NAME", 4)) f.name.assign((const char*)v, strnlen((const char*)v, tsz));
            else if (!memcmp(q, "TYPE", 4) && tsz >= 1) f.type = v[0];
            else if (!memcmp(q, "MDSZ", 4) && tsz >= 8) bc_len = rd64(v);
            else if (!memcmp(q, "OFFT", 4) && tsz >= 24) bc_rel = rd64(v + 16);
            else if (!memcmp(q, "TESS", 4) && tsz >= 1) { f.tess_patch = v[0] & 3; f.tess_cp = v[0] >> 2; }
            q = v + tsz;
        }
        // older libraries have no MDSZ tag: the size comes from the bitcode wrapper header
        if (bc_rel != ~0ull && bc_len == 0 && bc_rel + 20 <= bc_size && rd32(d + bc_off + bc_rel) == 0x0B17C0DEu)
            bc_len = (uint64_t)rd32(d + bc_off + bc_rel + 8) + rd32(d + bc_off + bc_rel + 12);
        if (bc_rel != ~0ull && bc_rel <= bc_size && bc_len <= bc_size - bc_rel) {
            f.bitcode = d + bc_off + bc_rel;
            f.bitcode_size = (size_t)bc_len;
        }
        out.push_back(std::move(f));
        p = qend;
    }
    return true;
}

inline const char* type_name(uint8_t t) {
    switch (t) {
    case FN_VERTEX: return "vertex"; case FN_FRAGMENT: return "fragment"; case FN_KERNEL: return "kernel";
    case FN_VISIBLE: return "visible"; case FN_INTERSECTION: return "intersection"; case FN_MESH: return "mesh";
    case FN_OBJECT: return "object"; default: return "unknown";
    }
}

} // namespace xef::metallib
