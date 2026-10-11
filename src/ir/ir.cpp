#include "ir/ir.h"

namespace xef::ir {

const char* op_name(Op op) {
    static const char* names[] = {
#define X(n) #n,
        XEF_IR_OPS(X)
#undef X
    };
    return (size_t)op < sizeof names / sizeof names[0] ? names[(size_t)op] : "?";
}

const char* vec_op_name(u16 op) {
    static const char* names[] = {
#define X(n) #n,
        XEF_VEC_OPS(X)
#undef X
    };
    return op < sizeof names / sizeof names[0] ? names[op] : "?";
}

static const char* type_name(Type t) {
    switch (t) {
    case Type::None: return "";
    case Type::I32: return "i32";
    case Type::I64: return "i64";
    case Type::Flags: return "flags";
    case Type::F32: return "f32";
    case Type::F64: return "f64";
    case Type::V128: return "v128";
    }
    return "?";
}

void dump(const Block& b, FILE* f) {
    fprintf(f, "block %#lx..%#lx (%d guest insts)\n", (unsigned long)b.start, (unsigned long)b.end, b.guest_insts);
    for (int v = 1; v < b.n; v++) {
        const Inst& i = b.insts[v];
        if (i.op == Op::Nop) continue;
        if (i.op == Op::VOp) fprintf(f, "  %%%-4d = V.%-12s %-5s", v, vec_op_name(i.sub), type_name(i.ty));
        else fprintf(f, "  %%%-4d = %-14s %-5s", v, op_name(i.op), type_name(i.ty));
        if (i.a) fprintf(f, " %%%d", i.a);
        if (i.b) fprintf(f, " %%%d", i.b);
        if (i.c) fprintf(f, " %%%d", i.c);
        fprintf(f, "  aux=%d size=%d sub=%d imm=%#lx", i.aux, i.size, i.sub, (unsigned long)i.imm);
        if (i.imm2) fprintf(f, " imm2=%#lx", (unsigned long)i.imm2);
        fprintf(f, "   @+%u\n", b.pc_off[v]);
    }
}

}  // namespace xef::ir
