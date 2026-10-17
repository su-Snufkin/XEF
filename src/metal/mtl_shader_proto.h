// Compile request/result structures exchanged between the engine and xef-mtlc, with a tiny serializer.
// Header-only; built with exceptions off on the xef side.
#pragma once
#include "mtl_shader_abi.h"
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

namespace xef::mtlabi {

struct FnConstant {
    uint32_t index = 0;
    std::string name;
    uint32_t type = 0;              // MTLDataType
    std::vector<uint8_t> value;
};

struct StageSource {
    uint32_t stage = STAGE_VERTEX;
    std::string function;           // entry name inside the module
    std::vector<uint8_t> bitcode;   // AIR bitcode (with or without the 0x0B17C0DE wrapper)
    std::vector<FnConstant> constants;   // MTLFunctionConstantValues of this function
};

enum RequestFlags : uint32_t { REQ_RASTER_DISABLED = 1, REQ_VALIDATE = 2, REQ_DUMP = 4 };

struct CompileRequest {
    std::vector<StageSource> stages;
    std::vector<FnConstant> constants;
    uint32_t tg_size[3] = {0, 0, 0};    // kernel: threads per threadgroup (0 = take from the function / 1)
    std::vector<uint32_t> tg_mem;       // kernel: setThreadgroupMemoryLength:atIndex:
    uint32_t flags = 0;
};

struct StageResult {
    uint32_t stage = STAGE_VERTEX;
    std::vector<uint32_t> spirv;
    uint32_t table_size = 0;
    std::vector<TableEntry> table;
    std::vector<VertexAttrib> attribs;
    std::vector<ColorOutput> colors;
    uint32_t flags = 0;
    std::vector<uint8_t> const_data;
    std::vector<ConstSampler> const_samplers;
    uint32_t tg_size[3] = {1, 1, 1};
    uint32_t tg_mem_size = 0;
};

struct CompileResult {
    bool ok = false;
    std::string log;
    std::vector<StageResult> stages;
};

class ByteWriter {
public:
    std::vector<uint8_t> buf;
    void raw(const void* p, size_t n) { const uint8_t* b = (const uint8_t*)p; buf.insert(buf.end(), b, b + n); }
    void u32(uint32_t v) { raw(&v, 4); }
    void str(const std::string& s) { u32((uint32_t)s.size()); raw(s.data(), s.size()); }
    template <class T> void vec(const std::vector<T>& v) { u32((uint32_t)v.size()); if (!v.empty()) raw(v.data(), v.size() * sizeof(T)); }
};

class ByteReader {
public:
    const uint8_t* p; const uint8_t* end; bool bad = false;
    ByteReader(const void* d, size_t n) : p((const uint8_t*)d), end((const uint8_t*)d + n) {}
    bool raw(void* out, size_t n) { if ((size_t)(end - p) < n) { bad = true; memset(out, 0, n); return false; } memcpy(out, p, n); p += n; return true; }
    uint32_t u32() { uint32_t v = 0; raw(&v, 4); return v; }
    std::string str() { uint32_t n = u32(); if ((size_t)(end - p) < n) { bad = true; return {}; } std::string s((const char*)p, n); p += n; return s; }
    template <class T> std::vector<T> vec() {
        uint32_t n = u32(); std::vector<T> v;
        if ((size_t)(end - p) < (size_t)n * sizeof(T)) { bad = true; return v; }
        v.resize(n); if (n) raw(v.data(), n * sizeof(T)); return v;
    }
};

inline std::vector<uint8_t> serialize(const CompileRequest& r) {
    ByteWriter w;
    w.u32(kProtoVersion);
    w.u32((uint32_t)r.stages.size());
    for (auto& s : r.stages) {
        w.u32(s.stage); w.str(s.function); w.vec(s.bitcode);
        w.u32((uint32_t)s.constants.size());
        for (auto& c : s.constants) { w.u32(c.index); w.str(c.name); w.u32(c.type); w.vec(c.value); }
    }
    w.u32((uint32_t)r.constants.size());
    for (auto& c : r.constants) { w.u32(c.index); w.str(c.name); w.u32(c.type); w.vec(c.value); }
    w.raw(r.tg_size, sizeof(r.tg_size));
    w.vec(r.tg_mem);
    w.u32(r.flags);
    return std::move(w.buf);
}

inline bool deserialize(const void* d, size_t n, CompileRequest& r) {
    ByteReader rd(d, n);
    if (rd.u32() != kProtoVersion) return false;
    uint32_t ns = rd.u32();
    if (ns > 8) return false;
    r.stages.resize(ns);
    for (auto& s : r.stages) {
        s.stage = rd.u32(); s.function = rd.str(); s.bitcode = rd.vec<uint8_t>();
        uint32_t snc = rd.u32();
        if (snc > 65536) return false;
        s.constants.resize(snc);
        for (auto& c : s.constants) { c.index = rd.u32(); c.name = rd.str(); c.type = rd.u32(); c.value = rd.vec<uint8_t>(); }
    }
    uint32_t nc = rd.u32();
    if (nc > 65536) return false;
    r.constants.resize(nc);
    for (auto& c : r.constants) { c.index = rd.u32(); c.name = rd.str(); c.type = rd.u32(); c.value = rd.vec<uint8_t>(); }
    rd.raw(r.tg_size, sizeof(r.tg_size));
    r.tg_mem = rd.vec<uint32_t>();
    r.flags = rd.u32();
    return !rd.bad;
}

inline std::vector<uint8_t> serialize(const CompileResult& r) {
    ByteWriter w;
    w.u32(kProtoVersion);
    w.u32(r.ok ? 1 : 0);
    w.str(r.log);
    w.u32((uint32_t)r.stages.size());
    for (auto& s : r.stages) {
        w.u32(s.stage); w.vec(s.spirv); w.u32(s.table_size); w.vec(s.table); w.vec(s.attribs); w.vec(s.colors);
        w.u32(s.flags); w.vec(s.const_data); w.vec(s.const_samplers); w.raw(s.tg_size, sizeof(s.tg_size)); w.u32(s.tg_mem_size);
    }
    return std::move(w.buf);
}

inline bool deserialize(const void* d, size_t n, CompileResult& r) {
    ByteReader rd(d, n);
    if (rd.u32() != kProtoVersion) return false;
    r.ok = rd.u32() != 0;
    r.log = rd.str();
    uint32_t ns = rd.u32();
    if (ns > 8) return false;
    r.stages.resize(ns);
    for (auto& s : r.stages) {
        s.stage = rd.u32(); s.spirv = rd.vec<uint32_t>(); s.table_size = rd.u32(); s.table = rd.vec<TableEntry>();
        s.attribs = rd.vec<VertexAttrib>(); s.colors = rd.vec<ColorOutput>(); s.flags = rd.u32();
        s.const_data = rd.vec<uint8_t>(); s.const_samplers = rd.vec<ConstSampler>(); rd.raw(s.tg_size, sizeof(s.tg_size));
        s.tg_mem_size = rd.u32();
    }
    return !rd.bad;
}

struct SourceRequest {
    std::string source;
    std::vector<std::string> defines;   // "NAME" or "NAME=VALUE" (MTLCompileOptions.preprocessorMacros)
};

struct SourceResult {
    bool ok = false;
    std::string log;
    std::vector<uint8_t> metallib;
};

inline std::vector<uint8_t> serialize(const SourceRequest& r) {
    ByteWriter w;
    w.u32(kProtoVersion);
    w.str(r.source);
    w.u32((uint32_t)r.defines.size());
    for (auto& d : r.defines) w.str(d);
    return std::move(w.buf);
}

inline bool deserialize(const void* d, size_t n, SourceRequest& r) {
    ByteReader rd(d, n);
    if (rd.u32() != kProtoVersion) return false;
    r.source = rd.str();
    uint32_t nd = rd.u32();
    if (nd > 65536) return false;
    r.defines.resize(nd);
    for (auto& s : r.defines) s = rd.str();
    return !rd.bad;
}

inline std::vector<uint8_t> serialize(const SourceResult& r) {
    ByteWriter w;
    w.u32(kProtoVersion);
    w.u32(r.ok ? 1 : 0);
    w.str(r.log);
    w.vec(r.metallib);
    return std::move(w.buf);
}

inline bool deserialize(const void* d, size_t n, SourceResult& r) {
    ByteReader rd(d, n);
    if (rd.u32() != kProtoVersion) return false;
    r.ok = rd.u32() != 0;
    r.log = rd.str();
    r.metallib = rd.vec<uint8_t>();
    return !rd.bad;
}

} // namespace xef::mtlabi
