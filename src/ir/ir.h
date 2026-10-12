// XEF — SSA intermediate representation.
//
// A block is a flat array of instructions; values are referenced by index
// (Val). Instruction 0 is a reserved "none". The representation is compact
// (32 bytes per instruction) and allocation-free so tier-1 translation stays
// cheap. Guest registers are accessed through GetReg/SetReg, guest NZCV
// through GetFlags/SetFlags; flags are first-class SSA values (Type::Flags)
// so the backend can keep them in host EFLAGS.
#pragma once
#include "common/common.h"

namespace xef::ir {

using Val = u16;
constexpr Val kNone = 0;

enum class Type : u8 { None, I32, I64, Flags, F32, F64, V128 };

// AArch64 condition codes (as encoded).
enum Cond : u8 { EQ, NE, HS, LO, MI, PL, VS, VC, HI, LS, GE, LT, GT, LE, AL, NV };

#define XEF_IR_OPS(X)                                                     \
    X(Nop) X(Const)                                                       \
    X(GetReg) X(SetReg) X(GetFlags) X(SetFlags)                           \
    X(Add) X(Sub) X(And) X(Or) X(Xor) X(AndNot) X(OrNot) X(XorNot)        \
    X(Shl) X(Lshr) X(Ashr) X(Ror) X(Not) X(Neg)                           \
    X(Mul) X(UMulH) X(SMulH) X(UDiv) X(SDiv)                              \
    X(Clz) X(Cls) X(Rbit) X(Bswap) X(Rev16) X(Rev32InWords)               \
    X(Sext) X(Zext)                                                       \
    X(Select)                                                             \
    X(FlagsSub) X(FlagsAdd) X(FlagsLogic) X(FlagsAdc) X(FlagsSbc)         \
    X(FlagsCCmp) X(FlagsFromNZCV) X(NZCVFromFlags)                        \
    X(Adc) X(Sbc)                                                         \
    X(Load) X(Store)                                                      \
    X(LoadExcl) X(StoreExcl) X(ClearExcl) X(AtomicRMW) X(Cas)             \
    X(Barrier)                                                            \
    X(GetSys) X(SetSys)                                                   \
    X(VGet) X(VSet) X(VLoad) X(VStore) X(VOp) X(VToGpr) X(GprToV)         \
    X(VConst) X(VSelect) X(FToI) X(IToF)                                  \
    X(FCmpFlags) X(FCCmpFlags)                                            \
    X(Helper)                                                             \
    X(ExitJump) X(ExitCond) X(ExitCbz) X(ExitTbz) X(ExitIndirect)         \
    X(ExitCall) X(ExitCallIndirect) X(ExitRet) X(ExitSyscall)             \
    X(ExitUndef) X(ExitBrk)

enum class Op : u8 {
#define X(n) n,
    XEF_IR_OPS(X)
#undef X
    Count
};

const char* op_name(Op op);

inline bool is_terminator(Op op) { return op >= Op::ExitJump; }

// Atomic RMW sub-operations (LSE).
enum AtomicOp : u8 { AT_ADD, AT_CLR, AT_EOR, AT_SET, AT_SMAX, AT_SMIN, AT_UMAX, AT_UMIN, AT_SWP };

// Barrier kinds.
enum BarrierKind : u8 { BAR_FULL, BAR_LOAD, BAR_STORE, BAR_ISB };

// System registers we model.
enum SysReg : u8 { SYS_TPIDR_EL0, SYS_TPIDRRO_EL0, SYS_FPCR, SYS_FPSR, SYS_CNTVCT, SYS_CNTFRQ,
                   SYS_MIDR, SYS_DCZID, SYS_CTR, SYS_MPIDR, SYS_RNDR };

// Vector / FP sub-operations (Inst::sub for Op::VOp). Element size in bytes in Inst::size.
// Flags in Inst::aux: bit0 = scalar (operate on element 0 only), bit1 = 64-bit vector (zero upper half).
#define XEF_VEC_OPS(X)                                                                \
    X(AND) X(ORR) X(EOR) X(BIC) X(ORN) X(NOT) X(BSL)                                  \
    X(ADD) X(SUB) X(MUL) X(NEG) X(ABS)                                                \
    X(SMAX) X(SMIN) X(UMAX) X(UMIN)                                                   \
    X(ADDP) X(SMAXP) X(SMINP) X(UMAXP) X(UMINP)                                       \
    X(UQADD) X(SQADD) X(UQSUB) X(SQSUB) X(URHADD) X(SRHADD) X(UHADD) X(SHADD)         \
    X(UHSUB) X(SHSUB) X(SABD) X(UABD)                                                 \
    X(CMEQ) X(CMGT) X(CMGE) X(CMHI) X(CMHS) X(CMTST)                                  \
    X(SSHL) X(USHL)                                                                   \
    X(SHL_I) X(USHR_I) X(SSHR_I) X(URSHR_I) X(SRSHR_I) X(SRI) X(SLI)                  \
    X(XTN) X(SQXTN) X(UQXTN) X(SQXTUN) X(UXTL) X(SXTL) X(SHRN) X(RSHRN)               \
    X(UMULL) X(SMULL) X(UADDL) X(SADDL) X(USUBL) X(SSUBL) X(UADDW) X(SADDW)           \
    X(USUBW) X(SSUBW) X(UABDL) X(SABDL) X(PMULL)                                      \
    X(UZP1) X(UZP2) X(ZIP1) X(ZIP2) X(TRN1) X(TRN2) X(EXT) X(TBL) X(TBX)              \
    X(REV16) X(REV32) X(REV64) X(CNT) X(CLZ) X(CLS) X(RBIT)                           \
    X(ADDV) X(UMAXV) X(UMINV) X(SMAXV) X(SMINV) X(UADDLV) X(SADDLV)                   \
    X(UADDLP) X(SADDLP) X(UADALP) X(SADALP)                                           \
    X(DUPELEM) X(INSELEM) X(ZEXT)                                                     \
    X(FADD) X(FSUB) X(FMUL) X(FDIV) X(FMAX) X(FMIN) X(FMAXNM) X(FMINNM)               \
    X(FSQRT) X(FABS) X(FNEG) X(FMLA) X(FMLS) X(FNMUL) X(FMADD) X(FMSUB)               \
    X(FNMADD) X(FNMSUB) X(FCMEQ) X(FCMGE) X(FCMGT) X(FACGE) X(FACGT) X(FABD)          \
    X(FADDP) X(FMAXP) X(FMINP) X(FMAXNMP) X(FMINNMP) X(FMAXV) X(FMINV)                \
    X(FMAXNMV) X(FMINNMV) X(SCVTF) X(UCVTF) X(FCVTZS) X(FCVTZU) X(FCVTS2D)            \
    X(FCVTD2S) X(FRINT) X(FCVTN) X(FCVTL) X(FRECPE) X(FRSQRTE) X(FRECPS) X(FRSQRTS)   \
    X(MLA) X(MLS) X(UMLAL) X(SMLAL) X(UMLSL) X(SMLSL) X(SQDMULH) X(SQRDMULH)          \
    X(FCVTH2S) X(FCVTS2H) X(FCVTH2D) X(FCVTD2H) X(AESE) X(AESD) X(AESMC) X(AESIMC)    \
    X(USRA) X(SSRA) X(URSRA) X(SRSRA) X(UQSHL_I) X(SQSHL_I) X(SQSHLU_I)               \
    X(UQSHRN) X(SQSHRN) X(SQSHRUN) X(UQRSHRN) X(SQRSHRN) X(SQRSHRUN) X(URSHL) X(SRSHL)\
    X(UQSHL) X(SQSHL) X(SQABS) X(SQNEG) X(SUQADD) X(USQADD) X(ADDHN) X(SUBHN)         \
    X(RADDHN) X(RSUBHN) X(UABA) X(SABA) X(UABAL) X(SABAL) X(PMUL) X(FMULX) X(FCMLT0)  \
    X(SHLL) X(SHA1C) X(SHA1P) X(SHA1M) X(SHA1H) X(SHA1SU0) X(SHA1SU1) X(SHA256H)      \
    X(SHA256H2) X(SHA256SU0) X(SHA256SU1) X(FRINTX) X(FCVTZS_FIX) X(FCVTZU_FIX)       \
    X(SCVTF_FIX) X(UCVTF_FIX) X(URECPE) X(URSQRTE) X(SQRSHL) X(UQRSHL) X(SQDMULL) X(SQDMLAL) X(SQDMLSL)

enum VecOp : u16 {
#define X(n) V_##n,
    XEF_VEC_OPS(X)
#undef X
    V_Count
};
const char* vec_op_name(u16 op);

// FP rounding modes for FRINT/FCVT*: values match AArch64 FPRounding.
enum FpRound : u8 { FR_TIEEVEN = 0, FR_POSINF = 1, FR_NEGINF = 2, FR_ZERO = 3, FR_TIEAWAY = 4, FR_ODD = 5,
                    FR_CURRENT = 7 };

struct Inst {
    Op op = Op::Nop;
    Type ty = Type::None;
    u8 size = 0;      // memory access size in bytes / ext bits / bit index
    u8 aux = 0;       // reg index, cond, flags, sub-op
    Val a = kNone, b = kNone, c = kNone;
    u16 sub = 0;      // vector sub-op / misc
    u64 imm = 0;
    u64 imm2 = 0;
};
static_assert(sizeof(Inst) == 32);

constexpr int kMaxBlockInsts = 4096;
constexpr int kMaxGuestInsts = 256;

struct Block {
    GuestAddr start = 0;
    GuestAddr end = 0;           // address after last guest instruction
    int n = 1;                   // insts[0] is reserved
    int guest_insts = 0;
    bool flags_live_out = true;  // false: no successor reads NZCV before writing it
    Inst insts[kMaxBlockInsts];
    // guest PC of the guest instruction each IR inst belongs to (for fault mapping)
    u32 pc_off[kMaxBlockInsts];

    void clear(GuestAddr s) { start = end = s; n = 1; guest_insts = 0; flags_live_out = true; }
    Inst& operator[](Val v) { return insts[v]; }
    const Inst& operator[](Val v) const { return insts[v]; }
};

void dump(const Block& b, FILE* f);

}  // namespace xef::ir
