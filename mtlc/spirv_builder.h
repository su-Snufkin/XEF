// Minimal SPIR-V module builder: id allocation, logical sections, type/constant deduplication.
#pragma once
#include "third_party/spirv/spirv.hpp"
#include <cstdint>
#include <cstring>
#include <map>
#include <set>
#include <string>
#include <vector>

namespace mtlc {

using Id = uint32_t;
using Words = std::vector<uint32_t>;

class SpvBuilder {
public:
    // sections in module order
    Words capabilities, extensions, ext_imports, memory_model, entry_points, exec_modes, debug, annotations, globals, functions;

    Id next_id = 1;
    Id alloc() { return next_id++; }

    static void inst(Words& w, spv::Op op, std::initializer_list<uint32_t> ops) {
        w.push_back(((uint32_t)(ops.size() + 1) << 16) | (uint32_t)op);
        w.insert(w.end(), ops.begin(), ops.end());
    }
    static void inst(Words& w, spv::Op op, const Words& ops) {
        w.push_back(((uint32_t)(ops.size() + 1) << 16) | (uint32_t)op);
        w.insert(w.end(), ops.begin(), ops.end());
    }
    static void append_string(Words& w, const std::string& s) {
        size_t n = s.size() / 4 + 1;
        size_t at = w.size();
        w.resize(at + n, 0);
        memcpy(&w[at], s.data(), s.size());
    }

    // ---- capabilities / extensions ----
    std::set<uint32_t> caps_set;
    std::set<std::string> ext_set;
    void cap(spv::Capability c) {
        if (caps_set.insert((uint32_t)c).second) inst(capabilities, spv::OpCapability, {(uint32_t)c});
    }
    void ext(const std::string& e) {
        if (!ext_set.insert(e).second) return;
        Words w; append_string(w, e); inst(extensions, spv::OpExtension, w);
    }
    Id glsl_std = 0;
    Id glsl() {
        if (!glsl_std) {
            glsl_std = alloc();
            Words w{glsl_std}; append_string(w, "GLSL.std.450");
            inst(ext_imports, spv::OpExtInstImport, w);
        }
        return glsl_std;
    }

    void name(Id id, const std::string& n) {
        if (n.empty()) return;
        Words w{id}; append_string(w, n); inst(debug, spv::OpName, w);
    }
    void decorate(Id id, spv::Decoration d, std::initializer_list<uint32_t> extra = {}) {
        Words w{id, (uint32_t)d}; w.insert(w.end(), extra.begin(), extra.end());
        inst(annotations, spv::OpDecorate, w);
    }
    void member_decorate(Id id, uint32_t member, spv::Decoration d, std::initializer_list<uint32_t> extra = {}) {
        Words w{id, member, (uint32_t)d}; w.insert(w.end(), extra.begin(), extra.end());
        inst(annotations, spv::OpMemberDecorate, w);
    }

    // ---- types (deduplicated by their operand words) ----
    std::map<Words, Id> type_cache;
    Id type(spv::Op op, Words ops) {
        Words key = ops; key.insert(key.begin(), (uint32_t)op);
        auto it = type_cache.find(key);
        if (it != type_cache.end()) return it->second;
        Id id = alloc();
        Words w{id}; w.insert(w.end(), ops.begin(), ops.end());
        inst(globals, op, w);
        type_cache[key] = id;
        return id;
    }
    // a fresh (non-deduplicated) type, for types that get decorations (structs with offsets, arrays with stride)
    Id unique_type(spv::Op op, Words ops) {
        Id id = alloc();
        Words w{id}; w.insert(w.end(), ops.begin(), ops.end());
        inst(globals, op, w);
        return id;
    }
    Id t_void() { return type(spv::OpTypeVoid, {}); }
    Id t_bool() { return type(spv::OpTypeBool, {}); }
    Id t_int(uint32_t bits) {
        if (bits == 8) cap(spv::CapabilityInt8);
        if (bits == 16) cap(spv::CapabilityInt16);
        if (bits == 64) cap(spv::CapabilityInt64);
        return type(spv::OpTypeInt, {bits, 0});
    }
    Id t_float(uint32_t bits) {
        if (bits == 16) cap(spv::CapabilityFloat16);
        if (bits == 64) cap(spv::CapabilityFloat64);
        return type(spv::OpTypeFloat, {bits});
    }
    Id t_vec(Id elem, uint32_t n) { return n == 1 ? elem : type(spv::OpTypeVector, {elem, n}); }
    Id t_ptr(spv::StorageClass sc, Id pointee) {
        if (sc == spv::StorageClassPhysicalStorageBuffer) {
            cap(spv::CapabilityPhysicalStorageBufferAddresses);
        }
        return type(spv::OpTypePointer, {(uint32_t)sc, pointee});
    }
    Id t_func(Id ret, Words params = {}) { params.insert(params.begin(), ret); return type(spv::OpTypeFunction, params); }
    Id t_array(Id elem, uint32_t n) { return type(spv::OpTypeArray, {elem, const_u32(n)}); }
    Id t_rtarray(Id elem) { return type(spv::OpTypeRuntimeArray, {elem}); }
    Id t_struct(const Words& members) { return type(spv::OpTypeStruct, members); }
    Id t_sampler() { return type(spv::OpTypeSampler, {}); }
    Id t_image(Id sampled, spv::Dim dim, uint32_t depth, uint32_t arrayed, uint32_t ms, uint32_t sampled_kind, spv::ImageFormat fmt) {
        return type(spv::OpTypeImage, {sampled, (uint32_t)dim, depth, arrayed, ms, sampled_kind, (uint32_t)fmt});
    }
    Id t_sampled_image(Id img) { return type(spv::OpTypeSampledImage, {img}); }

    // ---- constants ----
    std::map<Words, Id> const_cache;
    Id constant(Id ty, Words bits) {
        Words key = bits; key.insert(key.begin(), ty); key.insert(key.begin(), (uint32_t)spv::OpConstant);
        auto it = const_cache.find(key);
        if (it != const_cache.end()) return it->second;
        Id id = alloc();
        Words w{ty, id}; w.insert(w.end(), bits.begin(), bits.end());
        inst(globals, spv::OpConstant, w);
        const_cache[key] = id;
        return id;
    }
    Id const_u32(uint32_t v) { return constant(t_int(32), {v}); }
    Id const_u64(uint64_t v) { return constant(t_int(64), {(uint32_t)v, (uint32_t)(v >> 32)}); }
    Id const_f32(float f) { uint32_t b; memcpy(&b, &f, 4); return constant(t_float(32), {b}); }
    Id const_bool(bool b) {
        Words key{(uint32_t)(b ? spv::OpConstantTrue : spv::OpConstantFalse), t_bool()};
        auto it = const_cache.find(key);
        if (it != const_cache.end()) return it->second;
        Id id = alloc();
        inst(globals, b ? spv::OpConstantTrue : spv::OpConstantFalse, {t_bool(), id});
        const_cache[key] = id;
        return id;
    }
    Id const_composite(Id ty, const Words& parts) {
        Words key = parts; key.insert(key.begin(), ty); key.insert(key.begin(), (uint32_t)spv::OpConstantComposite);
        auto it = const_cache.find(key);
        if (it != const_cache.end()) return it->second;
        Id id = alloc();
        Words w{ty, id}; w.insert(w.end(), parts.begin(), parts.end());
        inst(globals, spv::OpConstantComposite, w);
        const_cache[key] = id;
        return id;
    }
    Id const_null(Id ty) {
        Words key{(uint32_t)spv::OpConstantNull, ty};
        auto it = const_cache.find(key);
        if (it != const_cache.end()) return it->second;
        Id id = alloc();
        inst(globals, spv::OpConstantNull, {ty, id});
        const_cache[key] = id;
        return id;
    }
    Id undef(Id ty) {
        Words key{(uint32_t)spv::OpUndef, ty};
        auto it = const_cache.find(key);
        if (it != const_cache.end()) return it->second;
        Id id = alloc();
        inst(globals, spv::OpUndef, {ty, id});
        const_cache[key] = id;
        return id;
    }

    Id variable(Id ptr_type, spv::StorageClass sc, Id initializer = 0) {
        Id id = alloc();
        if (initializer) inst(globals, spv::OpVariable, {ptr_type, id, (uint32_t)sc, initializer});
        else inst(globals, spv::OpVariable, {ptr_type, id, (uint32_t)sc});
        return id;
    }

    Words finish() const {
        Words out{spv::MagicNumber, 0x00010600u, 0x00580000u /* generator: XEF */, next_id, 0};
        for (const Words* s : {&capabilities, &extensions, &ext_imports, &memory_model, &entry_points, &exec_modes,
                               &debug, &annotations, &globals, &functions})
            out.insert(out.end(), s->begin(), s->end());
        return out;
    }
};

} // namespace mtlc
