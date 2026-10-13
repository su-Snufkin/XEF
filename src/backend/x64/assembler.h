// XEF — minimal, fast x86-64 assembler.
//
// Single pass, emits directly into a caller-provided buffer, no allocations.
// Only the subset XEF's code generators need. All encodings choose the
// shortest form (imm8 / disp8 / no-REX where possible).
#pragma once
#include <initializer_list>

#include "common/common.h"

namespace xef::x64 {

enum Reg : u8 {
    RAX, RCX, RDX, RBX, RSP, RBP, RSI, RDI,
    R8, R9, R10, R11, R12, R13, R14, R15,
    NOREG = 0xff
};
enum Xmm : u8 { XMM0, XMM1, XMM2, XMM3, XMM4, XMM5, XMM6, XMM7,
                XMM8, XMM9, XMM10, XMM11, XMM12, XMM13, XMM14, XMM15 };

enum Cond : u8 { CO, CNO, CB, CAE, CE, CNE, CBE, CA, CS, CNS, CP, CNP, CL, CGE, CLE, CG };
inline Cond invert(Cond c) { return Cond(c ^ 1); }

enum AluOp : u8 { ADD = 0, OR = 1, ADC = 2, SBB = 3, AND = 4, SUB = 5, XOR = 6, CMP = 7 };
enum ShiftOp : u8 { ROL = 0, ROR = 1, RCL = 2, RCR = 3, SHL = 4, SHR = 5, SAR = 7 };

struct Mem {
    u8 base = NOREG;
    u8 index = NOREG;
    u8 scale = 0;  // log2
    bool rip = false;
    i32 disp = 0;
    const u8* target = nullptr;  // for rip-relative: absolute address
};
inline Mem mem(Reg base, i32 disp = 0) { Mem m; m.base = base; m.disp = disp; return m; }
inline Mem mem(Reg base, Reg index, int scale, i32 disp = 0) {
    Mem m; m.base = base; m.index = index; m.scale = (u8)scale; m.disp = disp; return m;
}
inline Mem mem_idx(Reg index, int scale, i32 disp) {
    Mem m; m.index = index; m.scale = (u8)scale; m.disp = disp; return m;
}
inline Mem rip(const void* target) { Mem m; m.rip = true; m.target = (const u8*)target; return m; }

// SSE/AVX instruction descriptor: mandatory prefix, opcode map (1=0F, 2=0F38, 3=0F3A), opcode, W bit.
struct SseOp {
    u8 pfx;
    u8 map;
    u8 op;
    u8 w;
};

struct Label {
    i32 pos = -1;               // bound offset or -1
    u16 nfix = 0;
    i32 fix[14];                // offsets of rel32 fields that refer to this label
};

class Assembler {
public:
    Assembler() = default;
    Assembler(u8* buf, size_t size) { reset(buf, size); }
    void reset(u8* buf, size_t size) { start_ = p_ = buf; end_ = buf + size; }

    u8* start() const { return start_; }
    u8* cur() const { return p_; }
    size_t size() const { return p_ - start_; }
    i32 offset() const { return (i32)(p_ - start_); }
    bool overflow() const { return p_ > end_ - 64; }
    void set_cur(u8* p) { p_ = p; }

    // ---- raw ----
    void db(u8 v) { *p_++ = v; }
    void dw(u16 v) { memcpy(p_, &v, 2); p_ += 2; }
    void dd(u32 v) { memcpy(p_, &v, 4); p_ += 4; }
    void dq(u64 v) { memcpy(p_, &v, 8); p_ += 8; }

    // ---- labels ----
    void bind(Label& l) {
        l.pos = offset();
        for (int i = 0; i < l.nfix; i++) patch_rel32(start_ + l.fix[i], p_);
        l.nfix = 0;
    }
    static void patch_rel32(u8* field, const u8* target) {
        i32 rel = (i32)(target - (field + 4));
        memcpy(field, &rel, 4);
    }

    // ---- encoding helpers ----
    void rex(bool w, int reg, int index, int base, bool force = false) {
        u8 r = 0x40 | (w << 3) | (((reg >> 3) & 1) << 2) | (((index >> 3) & 1) << 1) | ((base >> 3) & 1);
        if (r != 0x40 || force) db(r);
    }
    static bool needs_byte_rex(int r) { return r >= 4 && r < 8; }

    // ModRM + SIB + disp for a memory operand. `trailing` = bytes after disp (immediates), for RIP-rel.
    void modrm_mem(int reg, const Mem& m, int trailing = 0) {
        reg &= 7;
        if (m.rip) {
            db((u8)((0 << 6) | (reg << 3) | 5));
            const u8* next = p_ + 4 + trailing;
            i64 rel = m.target - next;
            XEF_ASSERT(rel == (i32)rel);
            dd((u32)(i32)rel);
            return;
        }
        if (m.base == NOREG) {
            if (m.index == NOREG) {
                db((u8)((reg << 3) | 4));
                db(0x25);
            } else {
                db((u8)((reg << 3) | 4));
                db((u8)((m.scale << 6) | ((m.index & 7) << 3) | 5));
            }
            dd((u32)m.disp);
            return;
        }
        int b = m.base & 7;
        int mod;
        if (m.disp == 0 && b != 5) mod = 0;
        else if (m.disp == (i8)m.disp) mod = 1;
        else mod = 2;
        if (m.index == NOREG && b != 4) {
            db((u8)((mod << 6) | (reg << 3) | b));
        } else {
            int idx = m.index == NOREG ? 4 : (m.index & 7);
            XEF_ASSERT(m.index != RSP);
            db((u8)((mod << 6) | (reg << 3) | 4));
            db((u8)(((m.index == NOREG ? 0 : m.scale) << 6) | (idx << 3) | b));
        }
        if (mod == 1) db((u8)(i8)m.disp);
        else if (mod == 2) dd((u32)m.disp);
    }
    void modrm_rr(int reg, int rm) { db((u8)(0xC0 | ((reg & 7) << 3) | (rm & 7))); }
    static int mbase(const Mem& m) { return m.base == NOREG ? 0 : m.base; }
    static int midx(const Mem& m) { return m.index == NOREG ? 0 : m.index; }

    // generic: [prefix] [rex] opcode... modrm(reg, rm)
    void op_rr(int size, std::initializer_list<u8> opc, int reg, int rm, u8 prefix = 0) {
        if (size == 2) db(0x66);
        if (prefix) db(prefix);
        rex(size == 8, reg, 0, rm, size == 1 && (needs_byte_rex(reg) || needs_byte_rex(rm)));
        for (u8 o : opc) db(o);
        modrm_rr(reg, rm);
    }
    void op_rm(int size, std::initializer_list<u8> opc, int reg, const Mem& m, int trailing = 0, u8 prefix = 0) {
        if (size == 2) db(0x66);
        if (prefix) db(prefix);
        rex(size == 8, reg, midx(m), mbase(m), size == 1 && needs_byte_rex(reg));
        for (u8 o : opc) db(o);
        modrm_mem(reg, m, trailing);
    }

    // VEX (3-byte form always; simple and correct). mm: 1=0F 2=0F38 3=0F3A; pp: 0 none 1 66 2 F3 3 F2
    void vex(int mm, int pp, bool w, int l, int reg, int vvvv, int index, int base) {
        bool r = reg & 8, x = index & 8, b = base & 8;
        if (!x && !b && mm == 1 && !w) {
            db(0xC5);
            db((u8)(((!r) << 7) | ((~vvvv & 15) << 3) | (l << 2) | pp));
        } else {
            db(0xC4);
            db((u8)(((!r) << 7) | ((!x) << 6) | ((!b) << 5) | mm));
            db((u8)((w << 7) | ((~vvvv & 15) << 3) | (l << 2) | pp));
        }
    }
    void vex_rr(int mm, int pp, bool w, int l, u8 opc, int reg, int vvvv, int rm) {
        vex(mm, pp, w, l, reg, vvvv, 0, rm);
        db(opc);
        modrm_rr(reg, rm);
    }
    void vex_rm(int mm, int pp, bool w, int l, u8 opc, int reg, int vvvv, const Mem& m, int trailing = 0) {
        vex(mm, pp, w, l, reg, vvvv, midx(m), mbase(m));
        db(opc);
        modrm_mem(reg, m, trailing);
    }

    // ---- moves ----
    void mov(int size, Reg dst, Reg src) {
        if (size == 8 || size == 4) op_rr(size, {0x89}, src, dst);
        else if (size == 2) op_rr(2, {0x89}, src, dst);
        else op_rr(1, {0x88}, src, dst);
    }
    void mov(int size, Reg dst, const Mem& m) {  // load
        op_rm(size, {(u8)(size == 1 ? 0x8A : 0x8B)}, dst, m);
    }
    void mov(int size, const Mem& m, Reg src) {  // store
        op_rm(size, {(u8)(size == 1 ? 0x88 : 0x89)}, src, m);
    }
    void mov_imm(int size, const Mem& m, i32 imm) {
        int isz = size == 1 ? 1 : size == 2 ? 2 : 4;
        op_rm(size, {(u8)(size == 1 ? 0xC6 : 0xC7)}, 0, m, isz);
        if (isz == 1) db((u8)imm); else if (isz == 2) dw((u16)imm); else dd((u32)imm);
    }
    // load immediate into register, shortest form (may clobber flags if `allow_xor`)
    void mov_imm(Reg dst, u64 imm, bool allow_xor = false) {
        if (imm == 0 && allow_xor) { op_rr(4, {0x31}, dst, dst); return; }
        if (imm <= 0xffffffffull) {
            rex(false, 0, 0, dst);
            db((u8)(0xB8 + (dst & 7)));
            dd((u32)imm);
        } else if ((i64)imm == (i32)imm) {
            rex(true, 0, 0, dst);
            db(0xC7);
            modrm_rr(0, dst);
            dd((u32)imm);
        } else {
            rex(true, 0, 0, dst);
            db((u8)(0xB8 + (dst & 7)));
            dq(imm);
        }
    }
    void mov_imm64_fixed(Reg dst, u64 imm) {  // always 10 bytes (patchable)
        rex(true, 0, 0, dst);
        db((u8)(0xB8 + (dst & 7)));
        dq(imm);
    }
    void movzx(Reg dst, Reg src, int from) {
        if (from == 1) movzx8(dst, src);
        else if (from == 2) op_rr(4, {0x0F, 0xB7}, dst, src);
        else mov(4, dst, src);
    }
    // byte movzx needs REX for spl..dil source
    void movzx8(Reg dst, Reg src) {
        rex(false, dst, 0, src, needs_byte_rex(src));
        db(0x0F); db(0xB6); modrm_rr(dst, src);
    }
    void movzx16(Reg dst, Reg src) { op_rr(4, {0x0F, 0xB7}, dst, src); }
    void movzx_load(Reg dst, const Mem& m, int from) {
        if (from == 1) op_rm(4, {0x0F, 0xB6}, dst, m);
        else if (from == 2) op_rm(4, {0x0F, 0xB7}, dst, m);
        else mov(from == 4 ? 4 : 8, dst, m);
    }
    void movsx(int size, Reg dst, Reg src, int from) {
        if (from == 1) { rex(size == 8, dst, 0, src, needs_byte_rex(src)); db(0x0F); db(0xBE); modrm_rr(dst, src); }
        else if (from == 2) op_rr(size, {0x0F, 0xBF}, dst, src);
        else if (from == 4) op_rr(8, {0x63}, dst, src);
        else mov(size, dst, src);
    }
    void movsx_load(int size, Reg dst, const Mem& m, int from) {
        if (from == 1) op_rm(size, {0x0F, 0xBE}, dst, m);
        else if (from == 2) op_rm(size, {0x0F, 0xBF}, dst, m);
        else if (from == 4) op_rm(8, {0x63}, dst, m);
        else mov(8, dst, m);
    }
    void lea(int size, Reg dst, const Mem& m) { op_rm(size, {0x8D}, dst, m); }

    // ---- ALU ----
    void alu(AluOp op, int size, Reg dst, Reg src) {
        op_rr(size, {(u8)((op << 3) | (size == 1 ? 0 : 1))}, src, dst);
    }
    void alu(AluOp op, int size, Reg dst, const Mem& m) {
        op_rm(size, {(u8)((op << 3) | (size == 1 ? 2 : 3))}, dst, m);
    }
    void alu(AluOp op, int size, const Mem& m, Reg src) {
        op_rm(size, {(u8)((op << 3) | (size == 1 ? 0 : 1))}, src, m);
    }
    void alu_imm(AluOp op, int size, Reg dst, i32 imm) {
        if (size == 1) { op_rr(1, {0x80}, op, dst); db((u8)imm); return; }
        if (imm == (i8)imm) { op_rr(size, {0x83}, op, dst); db((u8)imm); }
        else if (dst == RAX) { if (size == 2) db(0x66); rex(size == 8, 0, 0, 0); db((u8)((op << 3) | 5)); if (size == 2) dw((u16)imm); else dd((u32)imm); }
        else { op_rr(size, {0x81}, op, dst); if (size == 2) dw((u16)imm); else dd((u32)imm); }
    }
    void alu_imm(AluOp op, int size, const Mem& m, i32 imm) {
        if (size == 1) { op_rm(1, {0x80}, op, m, 1); db((u8)imm); return; }
        if (imm == (i8)imm) { op_rm(size, {0x83}, op, m, 1); db((u8)imm); }
        else { op_rm(size, {0x81}, op, m, size == 2 ? 2 : 4); if (size == 2) dw((u16)imm); else dd((u32)imm); }
    }
    void test(int size, Reg a, Reg b) { op_rr(size, {(u8)(size == 1 ? 0x84 : 0x85)}, b, a); }
    void test_imm(int size, Reg a, i32 imm) {
        if (size == 1) { op_rr(1, {0xF6}, 0, a); db((u8)imm); return; }
        if (a == RAX) { rex(size == 8, 0, 0, 0); db(0xA9); dd((u32)imm); return; }
        op_rr(size, {0xF7}, 0, a); dd((u32)imm);
    }
    void test_imm(int size, const Mem& m, i32 imm) {
        if (size == 1) { op_rm(1, {0xF6}, 0, m, 1); db((u8)imm); return; }
        op_rm(size, {0xF7}, 0, m, 4); dd((u32)imm);
    }
    void not_(int size, Reg r) { op_rr(size, {0xF7}, 2, r); }
    void neg(int size, Reg r) { op_rr(size, {0xF7}, 3, r); }
    void inc(int size, Reg r) { op_rr(size, {0xFF}, 0, r); }
    void dec(int size, Reg r) { op_rr(size, {0xFF}, 1, r); }
    void dec(int size, const Mem& m) { op_rm(size, {0xFF}, 1, m); }
    void imul(int size, Reg dst, Reg src) { op_rr(size, {0x0F, 0xAF}, dst, src); }
    void imul(int size, Reg dst, const Mem& m) { op_rm(size, {0x0F, 0xAF}, dst, m); }
    void imul_imm(int size, Reg dst, Reg src, i32 imm) {
        if (imm == (i8)imm) { op_rr(size, {0x6B}, dst, src); db((u8)imm); }
        else { op_rr(size, {0x69}, dst, src); dd((u32)imm); }
    }
    void mul1(int size, Reg src) { op_rr(size, {0xF7}, 4, src); }   // rdx:rax = rax * src
    void imul1(int size, Reg src) { op_rr(size, {0xF7}, 5, src); }
    void div1(int size, Reg src) { op_rr(size, {0xF7}, 6, src); }
    void idiv1(int size, Reg src) { op_rr(size, {0xF7}, 7, src); }
    void cqo() { db(0x48); db(0x99); }
    void cdq() { db(0x99); }

    void shift_imm(ShiftOp op, int size, Reg r, u8 imm) {
        if (imm == 1) op_rr(size, {(u8)(size == 1 ? 0xD0 : 0xD1)}, op, r);
        else { op_rr(size, {(u8)(size == 1 ? 0xC0 : 0xC1)}, op, r); db(imm); }
    }
    void shift_cl(ShiftOp op, int size, Reg r) { op_rr(size, {(u8)(size == 1 ? 0xD2 : 0xD3)}, op, r); }
    void shld_imm(int size, Reg dst, Reg src, u8 imm) { op_rr(size, {0x0F, 0xA4}, src, dst); db(imm); }
    void shrd_imm(int size, Reg dst, Reg src, u8 imm) { op_rr(size, {0x0F, 0xAC}, src, dst); db(imm); }

    // BMI2 (flag-free shifts)
    void shlx(int size, Reg dst, Reg src, Reg cnt) { vex_rr(2, 1, size == 8, 0, 0xF7, dst, cnt, src); }
    void shrx(int size, Reg dst, Reg src, Reg cnt) { vex_rr(2, 3, size == 8, 0, 0xF7, dst, cnt, src); }
    void sarx(int size, Reg dst, Reg src, Reg cnt) { vex_rr(2, 2, size == 8, 0, 0xF7, dst, cnt, src); }
    void rorx(int size, Reg dst, Reg src, u8 imm) { vex_rr(3, 3, size == 8, 0, 0xF0, dst, 0, src); db(imm); }
    void mulx(int size, Reg hi, Reg lo, Reg src) { vex_rr(2, 3, size == 8, 0, 0xF6, hi, lo, src); }
    void andn(int size, Reg dst, Reg a_inv, Reg b) { vex_rr(2, 0, size == 8, 0, 0xF2, dst, a_inv, b); }
    void bzhi(int size, Reg dst, Reg src, Reg idx) { vex_rr(2, 0, size == 8, 0, 0xF5, dst, idx, src); }
    void lzcnt(int size, Reg dst, Reg src) { op_rr(size, {0x0F, 0xBD}, dst, src, 0xF3); }
    void tzcnt(int size, Reg dst, Reg src) { op_rr(size, {0x0F, 0xBC}, dst, src, 0xF3); }
    void popcnt(int size, Reg dst, Reg src) { op_rr(size, {0x0F, 0xB8}, dst, src, 0xF3); }
    void bsr(int size, Reg dst, Reg src) { op_rr(size, {0x0F, 0xBD}, dst, src); }
    void bsf(int size, Reg dst, Reg src) { op_rr(size, {0x0F, 0xBC}, dst, src); }
    void bswap(int size, Reg r) { rex(size == 8, 0, 0, r); db(0x0F); db((u8)(0xC8 + (r & 7))); }
    void bt_imm(int size, Reg r, u8 b) { op_rr(size, {0x0F, 0xBA}, 4, r); db(b); }

    void cmov(Cond c, int size, Reg dst, Reg src) { op_rr(size, {0x0F, (u8)(0x40 | c)}, dst, src); }
    void cmov(Cond c, int size, Reg dst, const Mem& m) { op_rm(size, {0x0F, (u8)(0x40 | c)}, dst, m); }
    void setcc(Cond c, Reg r) { rex(false, 0, 0, r, needs_byte_rex(r)); db(0x0F); db((u8)(0x90 | c)); modrm_rr(0, r); }

    // ---- flags ----
    void pushfq() { db(0x9C); }
    void popfq() { db(0x9D); }
    void lahf() { db(0x9F); }
    void sahf() { db(0x9E); }
    void cmc() { db(0xF5); }
    void stc() { db(0xF9); }
    void clc() { db(0xF8); }

    // ---- stack ----
    void push(Reg r) { rex(false, 0, 0, r); db((u8)(0x50 + (r & 7))); }
    void pop(Reg r) { rex(false, 0, 0, r); db((u8)(0x58 + (r & 7))); }
    void push(const Mem& m) { op_rm(4, {0xFF}, 6, m); }
    void pop(const Mem& m) { op_rm(4, {0x8F}, 0, m); }
    void push_imm32(i32 v) { db(0x68); dd((u32)v); }

    // ---- control flow ----
    // Returns pointer to the rel32 field.
    u8* jmp_rel32(const void* target) {
        db(0xE9); u8* f = p_; dd(0); patch_rel32(f, (const u8*)target); return f;
    }
    u8* jcc_rel32(Cond c, const void* target) {
        db(0x0F); db((u8)(0x80 | c)); u8* f = p_; dd(0); patch_rel32(f, (const u8*)target); return f;
    }
    u8* call_rel32(const void* target) {
        db(0xE8); u8* f = p_; dd(0); patch_rel32(f, (const u8*)target); return f;
    }
    void jmp(Label& l) { db(0xE9); use_label(l); }
    void jcc(Cond c, Label& l) { db(0x0F); db((u8)(0x80 | c)); use_label(l); }
    void call(Label& l) { db(0xE8); use_label(l); }
    void jmp_short(Label& l) {  // only for backward/known-near; falls back to rel32 if unbound
        if (l.pos >= 0) {
            i32 rel = l.pos - (offset() + 2);
            if (rel == (i8)rel) { db(0xEB); db((u8)(i8)rel); return; }
        }
        jmp(l);
    }
    void jrcxz_short(i8 rel) { db(0xE3); db((u8)rel); }
    u8* jrcxz_fwd() { db(0xE3); db(0); return p_ - 1; }   // patch with patch_rel8
    u8* jcc_fwd8(Cond c) { db((u8)(0x70 | c)); db(0); return p_ - 1; }
    u8* jmp_fwd8() { db(0xEB); db(0); return p_ - 1; }
    void patch_rel8_here(u8* field) {
        i64 rel = p_ - (field + 1);
        XEF_ASSERT(rel == (i8)rel);
        *field = (u8)(i8)rel;
    }
    void jmp(Reg r) { rex(false, 0, 0, r); db(0xFF); modrm_rr(4, r); }
    void jmp(const Mem& m) { rex(false, 0, midx(m), mbase(m)); db(0xFF); modrm_mem(4, m); }
    void call(Reg r) { rex(false, 0, 0, r); db(0xFF); modrm_rr(2, r); }
    void call(const Mem& m) { rex(false, 0, midx(m), mbase(m)); db(0xFF); modrm_mem(2, m); }
    void ret() { db(0xC3); }
    void ud2() { db(0x0F); db(0x0B); }
    void int3() { db(0xCC); }
    void syscall() { db(0x0F); db(0x05); }

    void nop(int n = 1) {
        static const u8 nops[9][9] = {
            {}, {0x90}, {0x66, 0x90}, {0x0F, 0x1F, 0x00}, {0x0F, 0x1F, 0x40, 0x00},
            {0x0F, 0x1F, 0x44, 0x00, 0x00}, {0x66, 0x0F, 0x1F, 0x44, 0x00, 0x00},
            {0x0F, 0x1F, 0x80, 0x00, 0x00, 0x00, 0x00},
            {0x0F, 0x1F, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00}};
        while (n > 0) { int k = n > 8 ? 8 : n; for (int i = 0; i < k; i++) db(nops[k][i]); n -= k; }
    }
    // Pad so that the byte at (cur + skip) is aligned to `a`.
    void align_field(int skip, int a = 4) {
        uintptr_t x = (uintptr_t)(p_ + skip);
        int pad = (int)((a - (x & (a - 1))) & (a - 1));
        nop(pad);
    }
    void align(int a) { align_field(0, a); }
    // Pads only if a 4-byte field at cur()+skip would straddle a cache line (stores that stay
    // within a line are atomic on x86, so it can be patched while other threads execute it).
    void keep_field_in_line(int skip) {
        uintptr_t x = (uintptr_t)(p_ + skip) & 63;
        if (x > 60) nop((int)(64 - x));
    }

    // ---- atomics / barriers ----
    void lock() { db(0xF0); }
    void xchg(int size, const Mem& m, Reg r) { op_rm(size, {(u8)(size == 1 ? 0x86 : 0x87)}, r, m); }
    void xchg(int size, Reg a, Reg b) { op_rr(size, {(u8)(size == 1 ? 0x86 : 0x87)}, a, b); }
    void cmpxchg(int size, const Mem& m, Reg r) { lock(); op_rm(size, {0x0F, (u8)(size == 1 ? 0xB0 : 0xB1)}, r, m); }
    void xadd(int size, const Mem& m, Reg r) { lock(); op_rm(size, {0x0F, (u8)(size == 1 ? 0xC0 : 0xC1)}, r, m); }
    void cmpxchg16b(const Mem& m) { lock(); op_rm(8, {0x0F, 0xC7}, 1, m); }
    void mfence() { db(0x0F); db(0xAE); db(0xF0); }
    // prefetch{nta,t0,t1,t2} [m] (0F 18 /hint), prefetchw [m] (0F 0D /1)
    void prefetch(bool write, int hint, const Mem& m) { op_rm(4, {0x0F, (u8)(write ? 0x0D : 0x18)}, hint, m); }
    void lock_or_rsp() { db(0xF0); db(0x83); db(0x0C); db(0x24); db(0x00); }  // lock or dword [rsp], 0

    // ---- SSE / AVX (xmm) ----
    // legacy SSE: [pfx] [rex] 0F op /r
    void sse_rr(u8 pfx, std::initializer_list<u8> opc, int dst, int src, bool w = false) {
        if (pfx) db(pfx);
        rex(w, dst, 0, src);
        for (u8 o : opc) db(o);
        modrm_rr(dst, src);
    }
    void sse_rm(u8 pfx, std::initializer_list<u8> opc, int dst, const Mem& m, bool w = false, int trailing = 0) {
        if (pfx) db(pfx);
        rex(w, dst, midx(m), mbase(m));
        for (u8 o : opc) db(o);
        modrm_mem(dst, m, trailing);
    }
    void movdqu_load(Xmm d, const Mem& m) { sse_rm(0xF3, {0x0F, 0x6F}, d, m); }
    void movdqu_store(const Mem& m, Xmm s) { sse_rm(0xF3, {0x0F, 0x7F}, s, m); }
    void movdqa(Xmm d, Xmm s) { sse_rr(0x66, {0x0F, 0x6F}, d, s); }
    void movaps(Xmm d, Xmm s) { sse_rr(0, {0x0F, 0x28}, d, s); }
    void movq_load(Xmm d, const Mem& m) { sse_rm(0xF3, {0x0F, 0x7E}, d, m); }   // zero-extends
    void movq_store(const Mem& m, Xmm s) { sse_rm(0x66, {0x0F, 0xD6}, s, m); }
    void movd_load(Xmm d, const Mem& m) { sse_rm(0x66, {0x0F, 0x6E}, d, m); }   // zero-extends
    void movd_store(const Mem& m, Xmm s) { sse_rm(0x66, {0x0F, 0x7E}, s, m); }
    void movq_xr(Xmm d, Reg s) { sse_rr(0x66, {0x0F, 0x6E}, d, s, true); }   // movq xmm, r64
    void movd_xr(Xmm d, Reg s) { sse_rr(0x66, {0x0F, 0x6E}, d, s, false); }
    void movq_rx(Reg d, Xmm s) { sse_rr(0x66, {0x0F, 0x7E}, s, d, true); }   // movq r64, xmm
    void movd_rx(Reg d, Xmm s) { sse_rr(0x66, {0x0F, 0x7E}, s, d, false); }
    void movq_xx(Xmm d, Xmm s) { sse_rr(0xF3, {0x0F, 0x7E}, d, s); }          // zero upper 64
    void pxor(Xmm d, Xmm s) { sse_rr(0x66, {0x0F, 0xEF}, d, s); }

    // ---- generic SSE/AVX ----
    bool avx = false;   // use VEX encodings (3-operand)
    static int vex_pp(u8 pfx) { return pfx == 0x66 ? 1 : pfx == 0xF3 ? 2 : pfx == 0xF2 ? 3 : 0; }
    // dst = src1 OP src2 (binary). Legacy form requires dst == src1 (caller guarantees or we copy).
    void xop(SseOp o, int d, int s1, int s2, int imm = -1) {
        if (avx) {
            vex(o.map, vex_pp(o.pfx), o.w, 0, d, s1, 0, s2);
            db(o.op);
            modrm_rr(d, s2);
        } else {
            if (d != s1) movaps((Xmm)d, (Xmm)s1);
            legacy_rr(o, d, s2);
        }
        if (imm >= 0) db((u8)imm);
    }
    void xop_m(SseOp o, int d, int s1, const Mem& m, int imm = -1) {
        if (avx) {
            vex(o.map, vex_pp(o.pfx), o.w, 0, d, s1, midx(m), mbase(m));
            db(o.op);
            modrm_mem(d, m, imm >= 0 ? 1 : 0);
        } else {
            if (d != s1) movaps((Xmm)d, (Xmm)s1);
            legacy_rm(o, d, m, imm >= 0 ? 1 : 0);
        }
        if (imm >= 0) db((u8)imm);
    }
    // dst = OP(src) (unary: VEX.vvvv unused)
    void xop1(SseOp o, int d, int s, int imm = -1) {
        if (avx) {
            vex(o.map, vex_pp(o.pfx), o.w, 0, d, 0, 0, s);
            db(o.op);
            modrm_rr(d, s);
        } else legacy_rr(o, d, s);
        if (imm >= 0) db((u8)imm);
    }
    void xop1_m(SseOp o, int d, const Mem& m, int imm = -1) {
        if (avx) {
            vex(o.map, vex_pp(o.pfx), o.w, 0, d, 0, midx(m), mbase(m));
            db(o.op);
            modrm_mem(d, m, imm >= 0 ? 1 : 0);
        } else legacy_rm(o, d, m, imm >= 0 ? 1 : 0);
        if (imm >= 0) db((u8)imm);
    }
    // AVX vblendvps/vblendvpd d, s1, s2, mask: d = mask (sign bit per lane) ? s2 : s1
    void vblendv(bool pd, int d, int s1, int s2, int mask) {
        vex(3, 1, false, 0, d, s1, 0, s2);
        db(pd ? 0x4B : 0x4A);
        modrm_rr(d, s2);
        db((u8)(mask << 4));
    }
    // shift-by-immediate group (66 0F 71/72/73 /ext ib): dst = src SHIFT imm
    void xshift_imm(u8 opc, int ext, int d, int s, u8 imm) {
        if (avx) {
            vex(1, 1, false, 0, ext, d, 0, s);
            db(opc);
            modrm_rr(ext, s);
        } else {
            if (d != s) movaps((Xmm)d, (Xmm)s);
            db(0x66);
            rex(false, 0, 0, d);
            db(0x0F); db(opc);
            modrm_rr(ext, d);
        }
        db(imm);
    }
    void legacy_rr(SseOp o, int d, int s) {
        if (o.pfx) db(o.pfx);
        rex(o.w, d, 0, s);
        db(0x0F);
        if (o.map == 2) db(0x38); else if (o.map == 3) db(0x3A);
        db(o.op);
        modrm_rr(d, s);
    }
    void legacy_rm(SseOp o, int d, const Mem& m, int trailing) {
        if (o.pfx) db(o.pfx);
        rex(o.w, d, midx(m), mbase(m));
        db(0x0F);
        if (o.map == 2) db(0x38); else if (o.map == 3) db(0x3A);
        db(o.op);
        modrm_mem(d, m, trailing);
    }
    // GPR <-> XMM with optional imm (pinsr/pextr, cvtsi2sd, cvttsd2si, movd/movq)
    // reg field = first operand, rm = second
    void xop_gx(SseOp o, int reg, int rm, int imm = -1, int vvvv = 0) {
        if (avx) {
            vex(o.map, vex_pp(o.pfx), o.w, 0, reg, vvvv, 0, rm);
            db(o.op);
            modrm_rr(reg, rm);
        } else legacy_rr(o, reg, rm);
        if (imm >= 0) db((u8)imm);
    }

private:
    void use_label(Label& l) {
        u8* f = p_;
        dd(0);
        if (l.pos >= 0) patch_rel32(f, start_ + l.pos);
        else { XEF_ASSERT(l.nfix < 14); l.fix[l.nfix++] = (i32)(f - start_); }
    }

    u8* start_ = nullptr;
    u8* p_ = nullptr;
    u8* end_ = nullptr;
};

}  // namespace xef::x64
