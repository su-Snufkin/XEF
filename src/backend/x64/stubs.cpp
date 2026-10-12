// XEF — shared runtime stubs (JIT entry/exit), generated once into the code cache.
#include <cstddef>

#include "backend/x64/codegen.h"
#include "runtime/cpu_state.h"

namespace xef::backend {

using namespace x64;
using regmap::host;
using regmap::mapped;

static void load_guest_regs(Assembler& as) {
    for (int g = 0; g < 32; g++)
        if (mapped(g)) as.mov(8, host(g), mem(R15, st_x(g)));
}
static void store_guest_regs(Assembler& as) {
    for (int g = 0; g < 32; g++)
        if (mapped(g)) as.mov(8, mem(R15, st_x(g)), host(g));
}

void emit_runtime_stubs(Assembler& as, RuntimeStubs& s) {
    // ---- enter(CpuState* rdi, void* host rsi) ----
    as.align(16);
    s.enter = as.cur();
    // pending guest signal: return immediately with EXIT_SIGNAL (st->pc unchanged). A signal that
    // arrives after this check finds RIP inside the code cache and is caught by single-stepping.
    as.alu_imm(CMP, 4, mem(RDI, (i32)offsetof(CpuState, pending_signal)), 0);
    Label nosig;
    as.jcc(CE, nosig);
    as.mov_imm(8, mem(RDI, (i32)offsetof(CpuState, exit_reason)), EXIT_SIGNAL);
    as.ret();
    as.bind(nosig);
    as.push(RBX); as.push(RBP); as.push(R12); as.push(R13); as.push(R14); as.push(R15);
    as.alu_imm(SUB, 8, RSP, 8);
    as.lea(8, R15, mem(RDI, kStateBias));
    as.mov(8, mem(R15, XEF_ST(host_sp)), RSP);
    as.mov(8, RAX, RSI);
    as.mov(8, RSP, mem(R15, XEF_ST(jit_sp)));
    load_guest_regs(as);
    as.push(mem(R15, XEF_ST(eflags)));
    as.popfq();
    as.jmp(RAX);

    // ---- exit_to_runtime: exit_reason (and pc/info) already stored ----
    as.align(16);
    s.exit_to_runtime = as.cur();
    store_guest_regs(as);
    as.pushfq();
    as.pop(mem(R15, XEF_ST(eflags)));
    as.mov(8, mem(R15, XEF_ST(jit_sp)), RSP);
    as.mov(8, RSP, mem(R15, XEF_ST(host_sp)));
    as.mov(8, RAX, mem(R15, XEF_ST(exit_reason)));
    as.alu_imm(ADD, 8, RSP, 8);
    as.pop(R15); as.pop(R14); as.pop(R13); as.pop(R12); as.pop(RBP); as.pop(RBX);
    as.ret();

    // ---- link_stub: rax = ExitInfo* ----
    as.align(16);
    s.link_stub = as.cur();
    as.mov(8, mem(R15, XEF_ST(exit_info)), RAX);
    as.mov_imm(8, mem(R15, XEF_ST(exit_reason)), EXIT_LINK);
    as.jmp_rel32(s.exit_to_runtime);

    // ---- ibtc_miss: rax = guest target ----
    as.align(16);
    s.ibtc_miss = as.cur();
    as.mov(8, mem(R15, XEF_ST(pc)), RAX);
    as.mov_imm(8, mem(R15, XEF_ST(exit_reason)), EXIT_LOOKUP);
    as.jmp_rel32(s.exit_to_runtime);

    // ---- syscall_exit: rax = next pc ----
    as.align(16);
    s.syscall_exit = as.cur();
    as.mov(8, mem(R15, XEF_ST(pc)), RAX);
    as.mov_imm(8, mem(R15, XEF_ST(exit_reason)), EXIT_SYSCALL);
    as.jmp_rel32(s.exit_to_runtime);
    as.align(16);
}

}  // namespace xef::backend
