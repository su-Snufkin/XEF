// XEF — C helpers called from generated code (slow paths).
#include <cmath>

#include "backend/vec_ref.h"
#include "ir/ir.h"
#include "runtime/code_cache.h"
#include "runtime/cpu_state.h"
#include "runtime/dispatch.h"

namespace xef {

// ---- vector constant pool (inside the code cache, RIP-addressable) ----
static u8* g_pool;
static u8* g_pool_ptr;
static u8* g_pool_end;

void vconst_pool_init() {
    const size_t sz = 64 * 1024;
    g_pool = g_pool_ptr = g_cache.alloc_data(sz);
    g_pool_end = g_pool + sz;
}

u8* vconst_pool_get(u64 lo, u64 hi) {
    // called with the translation lock held
    for (u8* p = g_pool; p < g_pool_ptr; p += 16) {
        u64 a, b;
        memcpy(&a, p, 8);
        memcpy(&b, p + 8, 8);
        if (a == lo && b == hi) return p;
    }
    if (g_pool_ptr + 16 > g_pool_end) fatal("vector constant pool full");
    u8* p = g_pool_ptr;
    memcpy(p, &lo, 8);
    memcpy(p + 8, &hi, 8);
    g_pool_ptr += 16;
    return p;
}

u64 g_vec_helper_calls[4096];   // per (op, log2 element size) when --stats

extern "C" void xef_vec_helper(CpuState* st, u64 desc, u64 imm) {
    if (g_opt.stats) {
        u32 k = (u32)(desc & 0xffff) * 8 + (u32)__builtin_ctz(((desc >> 16) & 0xff) | 0x80);
        __atomic_fetch_add(&g_vec_helper_calls[k & 4095], 1, __ATOMIC_RELAXED);
    }
    V128 a, b, c, r;
    memcpy(&a, st->vtmp[0], 16);
    memcpy(&b, st->vtmp[1], 16);
    memcpy(&c, st->vtmp[2], 16);
    vec_ref((u32)(desc & 0xffff), (int)((desc >> 16) & 0xff), (u32)((desc >> 24) & 0xff), imm, a, b, c, r, st->fpcr);
    memcpy(st->vtmp[3], &r, 16);
}

extern "C" u64 xef_ftoi_helper(u64 bits, u64 desc, u64 fbits) {
    int fs = desc & 0xff, rnd = (desc >> 8) & 0xf, sgn = (desc >> 12) & 1, is = (desc >> 16) & 0xff;
    V128 a{}, r;
    memcpy(a.b, &bits, 8);
    if (fs == 2) {  // half -> convert to single first
        V128 t;
        vec_ref(ir::V_FCVTH2S, 2, 1, 0, a, a, a, t, 0);
        a = t;
        fs = 4;
    }
    u32 op = fbits ? (sgn ? ir::V_FCVTZS_FIX : ir::V_FCVTZU_FIX) : (sgn ? ir::V_FCVTZS : ir::V_FCVTZU);
    // element-size trick: convert as a scalar of the integer width
    if (fs == is) {
        vec_ref(op, fs, 1, fbits ? fbits : (u64)rnd, a, a, a, r, 0);
        u64 v = 0;
        memcpy(&v, r.b, is);
        return v;
    }
    // differing widths: compute in double precision
    double x = fs == 4 ? (double)({ float f; memcpy(&f, a.b, 4); f; }) : ({ double d; memcpy(&d, a.b, 8); d; });
    if (std::isnan(x)) return 0;
    x = ldexp(x, (int)fbits);
    double rr;
    switch (rnd) {
    case ir::FR_TIEEVEN: rr = nearbyint(x); break;
    case ir::FR_POSINF: rr = ceil(x); break;
    case ir::FR_NEGINF: rr = floor(x); break;
    case ir::FR_TIEAWAY: rr = round(x); break;
    default: rr = trunc(x); break;
    }
    if (sgn) {
        double hi = ldexp(1.0, is * 8 - 1);
        if (rr >= hi) return is == 8 ? (u64)INT64_MAX : 0x7fffffffu;
        if (rr < -hi) return is == 8 ? (u64)INT64_MIN : 0x80000000u;
        i64 v = (i64)rr;
        return is == 8 ? (u64)v : (u64)(u32)(i32)v;
    }
    double hi = ldexp(1.0, is * 8);
    if (rr >= hi) return is == 8 ? ~0ull : 0xffffffffu;
    if (rr <= 0) return 0;
    return (u64)rr;
}

extern "C" u64 xef_itof_helper(u64 v, u64 desc, u64 fbits) {
    int fs = desc & 0xff, sgn = (desc >> 12) & 1, srcsz = (desc >> 16) & 0xff;
    if (fs == 2) {
        // to half: via double
        double d = sgn ? (srcsz == 8 ? (double)(i64)v : (double)(i32)(u32)v) : (srcsz == 8 ? (double)v : (double)(u32)v);
        d = ldexp(d, -(int)fbits);
        V128 a{}, r;
        float f = (float)d;
        memcpy(a.b, &f, 4);
        vec_ref(ir::V_FCVTS2H, 4, 1, 0, a, a, a, r, 0);
        u64 out = 0;
        memcpy(&out, r.b, 2);
        return out;
    }
    if (fs == 4) {
        float f = sgn ? (srcsz == 8 ? (float)(i64)v : (float)(i32)(u32)v) : (srcsz == 8 ? (float)v : (float)(u32)v);
        if (fbits) f = ldexpf(f, -(int)fbits);
        u32 b;
        memcpy(&b, &f, 4);
        return b;
    }
    double d = sgn ? (srcsz == 8 ? (double)(i64)v : (double)(i32)(u32)v) : (srcsz == 8 ? (double)v : (double)(u32)v);
    if (fbits) d = ldexp(d, -(int)fbits);
    u64 b;
    memcpy(&b, &d, 8);
    return b;
}

}  // namespace xef
