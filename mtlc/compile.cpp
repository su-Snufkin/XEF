// Request-level driver: parse AIR modules, run the per-stage pipeline, link vertex outputs to fragment inputs.
#include "mtlc.h"
#include "llvm/Bitcode/BitcodeReader.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Verifier.h"
#include "llvm/Linker/Linker.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/raw_ostream.h"
#include <spirv-tools/libspirv.hpp>
#include <cstdio>

namespace mtlc {
using namespace llvm;
using namespace xef::mtlabi;

static bool validate(const std::vector<uint32_t>& words, std::string& msg) {
    spvtools::SpirvTools tools(SPV_ENV_VULKAN_1_3);
    std::string log;
    tools.SetMessageConsumer([&](spv_message_level_t, const char*, const spv_position_t& pos, const char* m) {
        log += "spirv-val: " + std::string(m) + " (word " + std::to_string(pos.index) + ")\n";
    });
    spvtools::ValidatorOptions opts;
    opts.SetScalarBlockLayout(true);
    bool ok = tools.Validate(words.data(), words.size(), opts);
    if (!ok) msg += log;
    return ok;
}

std::string disassemble(const std::vector<uint32_t>& words) {
    spvtools::SpirvTools tools(SPV_ENV_VULKAN_1_3);
    std::string text;
    tools.Disassemble(words, &text, SPV_BINARY_TO_TEXT_OPTION_FRIENDLY_NAMES);
    return text;
}

// calls to `X.MTL_VISIBLE_FN_REF` reach [[visible]] functions supplied at pipeline creation: link their
// modules in (only what is referenced) and call the definitions directly
static bool link_visible_functions(Module& m, const std::vector<const StageSource*>& linked, LLVMContext& ctx, std::string& err) {
    // function tables can reach any linked function: then everything is linked in
    bool tables = false;
    for (Function& f : m)
        if (f.getName().starts_with("air.get_function_pointer_") && !f.use_empty()) tables = true;
    for (const StageSource* l : linked) {
        if (Function* own = m.getFunction(l->function); own && !own->isDeclaration()) {   // same library: already here
            own->addFnAttr("xef-visible");
            continue;
        }
        Function* ref = m.getFunction(l->function + ".MTL_VISIBLE_FN_REF");
        if (ref && m.getFunction(l->function)) continue;
        if (!ref) {   // dynamic libraries: an external declaration with the same name
            ref = m.getFunction(l->function);
            if (ref && !ref->isDeclaration()) continue;
            if (!ref && !tables) continue;
        }
        auto buf = MemoryBuffer::getMemBuffer(StringRef((const char*)l->bitcode.data(), l->bitcode.size()), "linked", false);
        auto lm = parseBitcodeFile(buf->getMemBufferRef(), ctx);
        if (!lm) { std::string e; raw_string_ostream os(e); os << lm.takeError(); err = l->function + ": " + e; return false; }
        std::unique_ptr<Module> mod = std::move(*lm);
        Function* def = mod->getFunction(l->function);
        if (!def || def->isDeclaration()) continue;
        // only the function body matters: drop the linked module's entry metadata
        for (const char* md : {"air.vertex", "air.fragment", "air.kernel", "air.visible", "air.intersection", "llvm.ident", "air.version",
                               "air.language_version", "air.compile_options", "air.source_file_name"})
            if (NamedMDNode* nm = mod->getNamedMetadata(md)) nm->eraseFromParent();
        mod->setDataLayout(m.getDataLayout());
        mod->setTargetTriple(m.getTargetTriple());
        if (ref && ref->getName() != l->function) ref->setName(l->function);   // the declaration now names the definition being linked in
        def->addFnAttr("xef-visible");
        if (Linker::linkModules(m, std::move(mod), ref ? Linker::Flags::LinkOnlyNeeded : Linker::Flags::None)) {
            err = "cannot link " + l->function;
            return false;
        }
        if (Function* f = m.getFunction(l->function)) f->addFnAttr("xef-visible");
    }
    return true;
}

bool compile(const CompileRequest& req, CompileResult& res) {
    res.ok = false;
    res.stages.clear();
    LLVMContext ctx;
    LinkInfo link;
    // vertex first so fragment inputs can be matched by name; linked functions are not stages
    std::vector<size_t> order;
    std::vector<const StageSource*> linked;
    for (size_t i = 0; i < req.stages.size(); i++) if (req.stages[i].stage == STAGE_VERTEX) order.push_back(i);
    for (size_t i = 0; i < req.stages.size(); i++)
        if (req.stages[i].stage == STAGE_LINKED) linked.push_back(&req.stages[i]);
        else if (req.stages[i].stage != STAGE_VERTEX) order.push_back(i);
    std::vector<size_t> slot(req.stages.size(), 0);
    {
        size_t n = 0;
        for (size_t i = 0; i < req.stages.size(); i++) if (req.stages[i].stage != STAGE_LINKED) slot[i] = n++;
        res.stages.resize(n);
    }
    bool dump = (req.flags & REQ_DUMP) != 0;
    for (size_t idx : order) {
        const StageSource& src = req.stages[idx];
        StageResult& sr = res.stages[slot[idx]];
        sr.stage = src.stage;
        std::string err;
        auto buf = MemoryBuffer::getMemBuffer(StringRef((const char*)src.bitcode.data(), src.bitcode.size()), "air", false);
        auto mod_or = parseBitcodeFile(buf->getMemBufferRef(), ctx);
        if (!mod_or) {
            std::string e;
            raw_string_ostream os(e);
            os << mod_or.takeError();
            res.log += "bitcode: " + e + "\n";
            return false;
        }
        std::unique_ptr<Module> mod = std::move(*mod_or);
        if (!linked.empty() && !link_visible_functions(*mod, linked, ctx, err)) { res.log += "link [" + src.function + "]: " + err + "\n"; return false; }
        AirEntry entry;
        if (!find_entry(*mod, src.function, entry)) {
            res.log += "entry point '" + src.function + "' not found\n";
            return false;
        }
        PreparedStage ps;
        ps.res = &sr;
        ps.table_slot = src.stage == STAGE_FRAGMENT ? 1 : 0;
        auto stage_fail = [&](const char* phase) {
            res.log += std::string(phase) + " [" + src.function + "]: " + err + "\n";
            if (dump && ps.main) { std::string s; raw_string_ostream os(s); ps.main->print(os); fprintf(stderr, "%s\n", s.c_str()); }
            return false;
        };
        if (!prepare_stage(*mod, entry, req, link, ps, err)) return stage_fail("prepare");
        if (dump) { fprintf(stderr, "=== prepared %s\n", src.function.c_str()); ps.main->print(errs()); }
        if (!lower_memory(ps, err)) return stage_fail("memory");
        if (!structurize(*ps.main, err)) return stage_fail("structurize");
        if (!legalize_ints(*ps.main, err)) return stage_fail("legalize");
        if (dump) { fprintf(stderr, "=== lowered %s\n", src.function.c_str()); ps.main->print(errs()); }
        {
            std::string verr;
            raw_string_ostream vos(verr);
            if (verifyFunction(*ps.main, &vos)) { err = "IR verifier: " + verr; return stage_fail("verify"); }
        }
        if (!emit_spirv(ps, sr.spirv, err)) return stage_fail("emit");
        if (dump) fprintf(stderr, "=== spirv %s\n%s\n", src.function.c_str(), disassemble(sr.spirv).c_str());
        if (req.flags & REQ_VALIDATE) {
            std::string vmsg;
            if (!validate(sr.spirv, vmsg)) {
                res.log += "validation [" + src.function + "]:\n" + vmsg;
                if (!dump) fprintf(stderr, "%s\n", disassemble(sr.spirv).c_str());
                return false;
            }
        }
    }
    res.ok = true;
    return true;
}

} // namespace mtlc
