// XEF — shared runtime stubs (JIT entry/exit), generated once into the code cache.
#include <cstddef>

#include "backend/x64/codegen.h"
#include "runtime/cpu_state.h"

namespace xef::backend {

extern "C" u8* xef_syscall_fast(CpuState* st);   // dispatch.cpp

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
    as.mov_imm(4, mem(R15, XEF_ST(in_jit)), 1);
    as.push(mem(R15, XEF_ST(eflags)));
    as.popfq();
    // A signal between the check at the top and popfq set TF in a context that popfq then
    // overwrote: look again, flag-free (rcx is free at block entry). After this point a signal
    // finds RIP in the code cache and single-steps to the block entry.
    Label late_sig;
    as.mov(4, RCX, mem(R15, XEF_ST(pending_signal)));
    u8* go = as.jrcxz_fwd();
    as.jmp(late_sig);
    as.patch_rel8_here(go);
    as.jmp(RAX);
    as.bind(late_sig);
    as.mov_imm(8, mem(R15, XEF_ST(exit_reason)), EXIT_SIGNAL);

    // ---- exit_to_runtime: exit_reason (and pc/info) already stored ----
    // (the late-signal path above falls through into it: no padding in between)
    s.exit_to_runtime = as.cur();
    as.mov_imm(4, mem(R15, XEF_ST(in_jit)), 0);
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
    // SVC #0 without leaving enter()'s frame: leave the JIT as exit_to_runtime does, call
    // xef_syscall_fast on the C++ stack (callee-saved registers, R15 included, survive the call),
    // then re-enter at the returned code as enter does, late pending-signal check included.
    as.align(16);
    s.syscall_exit = as.cur();
    as.mov(8, mem(R15, XEF_ST(pc)), RAX);
    as.mov_imm(4, mem(R15, XEF_ST(in_jit)), 0);
    store_guest_regs(as);
    as.pushfq();
    as.pop(mem(R15, XEF_ST(eflags)));
    as.mov(8, mem(R15, XEF_ST(jit_sp)), RSP);
    as.mov(8, RSP, mem(R15, XEF_ST(host_sp)));
    as.lea(8, RDI, mem(R15, -kStateBias));
    as.mov_imm(RAX, (u64)&xef_syscall_fast);
    as.call(RAX);
    as.mov(8, RSP, mem(R15, XEF_ST(jit_sp)));
    load_guest_regs(as);
    as.mov_imm(4, mem(R15, XEF_ST(in_jit)), 1);
    as.push(mem(R15, XEF_ST(eflags)));
    as.popfq();
    Label late_sig2;
    as.mov(4, RCX, mem(R15, XEF_ST(pending_signal)));
    u8* go2 = as.jrcxz_fwd();
    as.jmp(late_sig2);
    as.patch_rel8_here(go2);
    as.jmp(RAX);
    as.bind(late_sig2);   // st->pc is the pc after the syscall: deliver from the runtime
    as.mov_imm(8, mem(R15, XEF_ST(exit_reason)), EXIT_SIGNAL);
    as.jmp_rel32(s.exit_to_runtime);
    as.align(16);
}

}  // namespace xef::backend
