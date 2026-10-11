// XEF — reference (C) implementation of IR vector/FP operations with exact
// AArch64 semantics. Used as the JIT fallback for rare operations and as the
// oracle when testing the inline SSE/AVX lowerings.
#pragma once
#include "common/common.h"

namespace xef {

struct alignas(16) V128 {
    u8 b[16];
};

// desc = op | esize << 16 | flags << 24
void vec_ref(u32 op, int esize, u32 flags, u64 imm, const V128& a, const V128& b, const V128& c, V128& out,
             u32 fpcr);

u32 fp_estimate_recip32(u32 x, u32 fpcr);

}  // namespace xef
