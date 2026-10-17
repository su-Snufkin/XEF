// Parsed form of the AIR entry point metadata (!air.vertex / !air.fragment / !air.kernel).
#pragma once
#include "llvm/IR/Constants.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Metadata.h"
#include "llvm/IR/Module.h"
#include <string>
#include <vector>

namespace mtlc {

enum class StageKind { Vertex, Fragment, Kernel, Visible };

// One argument or return-value element. `kind` is the AIR tag ("air.buffer", "air.position", ...).
struct AirElem {
    std::string kind;
    int arg_index = -1;                 // function argument number (inputs) / struct member (outputs)
    int location = -1;                  // air.location_index first value / render_target index / attribute
    int location_count = 1;
    int rt_index = 0;                   // dual source blending index (air.render_target second value)
    std::string user_name;              // vertex_output / fragment_input identifier ("generated(...)", "user(x)")
    std::string type_name;              // air.arg_type_name
    std::string arg_name;
    std::string access;                 // "air.read" / "air.write" / "air.read_write" / "air.sample"
    int address_space = -1;
    int type_size = 0, type_align = 0;
    bool flat = false, no_perspective = false, centroid = false, sample = false;
    bool invariant = false;
    std::string depth_qualifier;        // air.depth: "air.depth_qualifier" any/greater/less
    llvm::Metadata* fc_predicate = nullptr;   // argument guarded by a function constant
    llvm::GlobalVariable* location_expr = nullptr;   // [[color(expr)]]: location computed from function constants
    int array_size = 0;                 // clip distances etc.
};

struct AirEntry {
    StageKind stage = StageKind::Vertex;
    llvm::Function* fn = nullptr;
    std::vector<AirElem> outputs;       // in return struct member order
    std::vector<AirElem> inputs;        // in argument order
    bool early_fragment_tests = false;
    std::string patch;                  // post-tessellation vertex functions
};

inline std::string md_str(const llvm::Metadata* m) {
    if (auto* s = llvm::dyn_cast_or_null<llvm::MDString>(m)) return s->getString().str();
    return {};
}
inline bool md_int(const llvm::Metadata* m, int64_t& out) {
    if (auto* c = llvm::dyn_cast_or_null<llvm::ConstantAsMetadata>(m))
        if (auto* ci = llvm::dyn_cast<llvm::ConstantInt>(c->getValue())) { out = ci->getSExtValue(); return true; }
    return false;
}

inline AirElem parse_elem(const llvm::MDNode* n, bool is_input) {
    AirElem e;
    unsigned i = 0, num = n->getNumOperands();
    int64_t v;
    if (is_input && i < num && md_int(n->getOperand(i), v)) { e.arg_index = (int)v; i++; }
    // optional function-constant guard
    if (i < num && md_str(n->getOperand(i)) == "air.function_constant") {
        if (i + 1 < num) e.fc_predicate = n->getOperand(i + 1);
        i += 2;
    }
    if (i < num) e.kind = md_str(n->getOperand(i++));
    // kind-specific positional operands
    if (e.kind == "air.render_target") {
        if (i < num && md_int(n->getOperand(i), v)) { e.location = (int)v; i++; }
        else if (i < num)
            if (auto* vm = llvm::dyn_cast_or_null<llvm::ValueAsMetadata>(n->getOperand(i)))
                if (auto* g = llvm::dyn_cast<llvm::GlobalVariable>(vm->getValue())) { e.location_expr = g; i++; }
        if (i < num && md_int(n->getOperand(i), v)) { e.rt_index = (int)v; i++; }
    } else if (e.kind == "air.vertex_output" || e.kind == "air.fragment_input") {
        if (i < num && llvm::isa<llvm::MDString>(n->getOperand(i))) {
            std::string s = md_str(n->getOperand(i));
            if (s.rfind("air.", 0) != 0) { e.user_name = s; i++; }
        }
    }
    while (i < num) {
        std::string key = md_str(n->getOperand(i));
        if (key.empty()) { i++; continue; }
        if (key == "air.location_index") {
            if (i + 1 < num && md_int(n->getOperand(i + 1), v)) e.location = (int)v;
            if (i + 2 < num && md_int(n->getOperand(i + 2), v)) { e.location_count = (int)v; i += 3; } else i += 2;
            continue;
        }
        if (key == "air.arg_type_name" || key == "air.arg_name" || key == "air.depth_qualifier") {
            std::string val = i + 1 < num ? md_str(n->getOperand(i + 1)) : "";
            if (key == "air.arg_type_name") e.type_name = val;
            else if (key == "air.arg_name") e.arg_name = val;
            else e.depth_qualifier = val;
            i += 2; continue;
        }
        if (key == "air.address_space" || key == "air.arg_type_size" || key == "air.arg_type_align_size" ||
            key == "air.array_size" || key == "air.buffer_size") {
            if (i + 1 < num && md_int(n->getOperand(i + 1), v)) {
                if (key == "air.address_space") e.address_space = (int)v;
                else if (key == "air.arg_type_size") e.type_size = (int)v;
                else if (key == "air.arg_type_align_size") e.type_align = (int)v;
                else if (key == "air.array_size") e.array_size = (int)v;
                i += 2;
            } else i++;
            continue;
        }
        if (key == "air.read" || key == "air.write" || key == "air.read_write" || key == "air.sample") e.access = key;
        else if (key == "air.flat") e.flat = true;
        else if (key == "air.no_perspective") e.no_perspective = true;
        else if (key == "air.centroid") e.centroid = true;
        else if (key == "air.sample") e.sample = true;
        else if (key == "air.invariant") e.invariant = true;
        else if (key == "air.struct_type_info" || key == "air.indirect_argument") { i += 2; continue; }
        i++;
    }
    return e;
}

// Finds the entry `name` (or the only entry when name is empty). Returns false when not found.
inline bool find_entry(llvm::Module& m, const std::string& name, AirEntry& out) {
    struct { const char* md; StageKind k; } kinds[] = {
        {"air.vertex", StageKind::Vertex}, {"air.fragment", StageKind::Fragment}, {"air.kernel", StageKind::Kernel},
    };
    for (auto& k : kinds) {
        llvm::NamedMDNode* nm = m.getNamedMetadata(k.md);
        if (!nm) continue;
        for (llvm::MDNode* n : nm->operands()) {
            if (n->getNumOperands() < 3) continue;
            auto* fm = llvm::dyn_cast_or_null<llvm::ValueAsMetadata>(n->getOperand(0));
            auto* fn = fm ? llvm::dyn_cast<llvm::Function>(fm->getValue()) : nullptr;
            if (!fn || (!name.empty() && fn->getName() != name)) continue;
            out.stage = k.k;
            out.fn = fn;
            if (auto* outs = llvm::dyn_cast_or_null<llvm::MDNode>(n->getOperand(1)))
                for (auto& o : outs->operands())
                    if (auto* on = llvm::dyn_cast_or_null<llvm::MDNode>(o.get())) out.outputs.push_back(parse_elem(on, false));
            if (auto* ins = llvm::dyn_cast_or_null<llvm::MDNode>(n->getOperand(2)))
                for (auto& o : ins->operands())
                    if (auto* in = llvm::dyn_cast_or_null<llvm::MDNode>(o.get())) out.inputs.push_back(parse_elem(in, true));
            for (unsigned j = 3; j < n->getNumOperands(); j++) {
                auto* t = llvm::dyn_cast_or_null<llvm::MDNode>(n->getOperand(j));
                std::string s = t && t->getNumOperands() ? md_str(t->getOperand(0)) : md_str(n->getOperand(j));
                if (s == "early_fragment_tests" || s == "air.early_fragment_tests") out.early_fragment_tests = true;   // Apple: bare string
                if (s == "air.patch" && t && t->getNumOperands() > 1) out.patch = md_str(t->getOperand(1));
            }
            return true;
        }
    }
    return false;
}

} // namespace mtlc
