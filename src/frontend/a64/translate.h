// XEF — AArch64 → IR translator (frontend).
#pragma once
#include "ir/builder.h"
#include "runtime/code_cache.h"

namespace xef::a64 {

// While set, decode-ahead records the guest ranges it reads (code invalidation dependencies).
void set_peek_log(PeekLog* log);

struct TranslateOpts {
    int max_insts = 128;          // max guest instructions per block
    bool stop_at_page = false;
    bool flags_liveness = true;   // false: skip the NZCV lookahead (flags_live_out stays true)
};

// Reads guest code at `pc` and fills `blk`. Always produces a terminated block.
void translate_block(GuestAddr pc, ir::Block& blk, const TranslateOpts& opts);

// True if the guest page holding pc is mapped (cheap; caches the last page per thread).
bool guest_readable(GuestAddr pc);

// True if NZCV may be read at pc before being written (bounded decode-ahead scan).
bool nzcv_live_at(GuestAddr pc, int depth = 0);
bool nzcv_read_first(GuestAddr pc);
// RET of a function whose callers read NZCV on return (outlined helpers): flags must be kept (see translate.cpp).
void scan_flag_returning_calls(GuestAddr lo, GuestAddr hi);
bool ret_keeps_flags(GuestAddr ret_pc);
bool call_keeps_flags(GuestAddr target);   // a direct BL whose callee passes NZCV back to the return site
bool call_uses_flags(GuestAddr target);    // ... or whose callee reads NZCV on entry: live at the BL
extern bool g_abi_flags;   // NZCV dead at calls, returns and indirect branches (XEF_STRICT_FLAGS=1: no)

// Decode helpers shared with SIMD translation.
bool decode_bit_masks(u32 n, u32 imms, u32 immr, bool immediate, int datasize, u64* wmask);

class Translator {
public:
    Translator(ir::Block& b) : b_(b), ir_(b) {}

    // Translates one instruction. Returns false if it ended the block.
    bool step(GuestAddr pc, u32 insn);

    ir::Builder& ir() { return ir_; }

    // operand helpers
    ir::Val X(int r, ir::Type t) { return r == 31 ? ir_.cnst(t, 0) : ir_.get_reg(r, t); }
    ir::Val XSP(int r, ir::Type t) { return ir_.get_reg(r, t); }
    void setX(int r, ir::Val v) { if (r != 31) ir_.set_reg(r, v); }
    void setXSP(int r, ir::Val v) { ir_.set_reg(r, v); }

    void undef(GuestAddr pc, u32 insn);

    GuestAddr pc_ = 0;

private:
    bool dp_imm(u32 i);
    bool branch_sys(u32 i);
    bool ldst(u32 i);
    bool dp_reg(u32 i);
    bool simd_fp(u32 i);   // translate_simd.cpp

    bool ldst_exclusive(u32 i);
    bool ldst_pair(u32 i);
    bool ldst_reg(u32 i);
    bool ldst_atomic(u32 i);
    bool ldst_simd_struct(u32 i);  // translate_simd.cpp
    bool system(u32 i);

    ir::Val shift_reg(ir::Type t, ir::Val v, int type, int amount);
    ir::Val extend_reg(ir::Type t, ir::Val v, int option, int shift);
    void do_load(int rt, ir::Val addr, int size, bool sign, ir::Type dst, bool vec);
    void do_store(int rt, ir::Val addr, int size, bool vec);

    ir::Block& b_;
    ir::Builder ir_;
    bool ended_ = false;
};

}  // namespace xef::a64
