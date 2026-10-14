// XEF — reference implementation of vector / FP operations (exact AArch64 semantics).
#include "backend/vec_ref.h"

#include <cfenv>
#include <cmath>

#include "ir/ir.h"

namespace xef {

using namespace ir;

namespace {

constexpr u32 F_SCALAR = 1, F_HALF = 2;

inline u64 get(const V128& v, int i, int es) {
    u64 x = 0;
    memcpy(&x, v.b + i * es, es);
    return x;
}
inline void put(V128& v, int i, int es, u64 x) { memcpy(v.b + i * es, &x, es); }
inline i64 sx(u64 x, int es) { return es == 8 ? (i64)x : sext(x, es * 8); }
inline u64 emask(int es) { return es == 8 ? ~0ull : ((1ull << (es * 8)) - 1); }
inline i64 smax_of(int es) { return es == 8 ? INT64_MAX : (i64)((1ull << (es * 8 - 1)) - 1); }
inline i64 smin_of(int es) { return es == 8 ? INT64_MIN : -(i64)(1ull << (es * 8 - 1)); }

inline u64 sat_s(__int128 v, int es) {
    if (v > smax_of(es)) return (u64)smax_of(es) & emask(es);
    if (v < smin_of(es)) return (u64)smin_of(es) & emask(es);
    return (u64)v & emask(es);
}
inline u64 sat_u(__int128 v, int es) {
    if (v < 0) return 0;
    if ((unsigned __int128)v > emask(es)) return emask(es);
    return (u64)v;
}

// ---------------- floating point helpers ----------------
inline bool is_nan32(u32 x) { return (x & 0x7f800000) == 0x7f800000 && (x & 0x7fffff); }
inline bool is_snan32(u32 x) { return is_nan32(x) && !(x & 0x400000); }
inline bool is_nan64(u64 x) { return (x & 0x7ff0000000000000ull) == 0x7ff0000000000000ull && (x & 0xfffffffffffffull); }
inline bool is_snan64(u64 x) { return is_nan64(x) && !(x & 0x8000000000000ull); }
inline float f32(u64 x) { float f; u32 v = (u32)x; memcpy(&f, &v, 4); return f; }
inline double f64(u64 x) { double d; memcpy(&d, &x, 8); return d; }
inline u64 bits32(float f) { u32 v; memcpy(&v, &f, 4); return v; }
inline u64 bits64(double d) { u64 v; memcpy(&v, &d, 8); return v; }

struct FP {
    int es;
    u32 fpcr;
    bool dn() const { return fpcr & (1u << 25); }
    bool fz() const { return fpcr & (1u << 24); }
    bool is_denormal(u64 x) const { return es == 4 ? (x & 0x7f800000) == 0 && abs(x) : (x & 0x7ff0000000000000ull) == 0 && abs(x); }
    bool is_nan(u64 x) const { return es == 4 ? is_nan32((u32)x) : is_nan64(x); }
    bool is_snan(u64 x) const { return es == 4 ? is_snan32((u32)x) : is_snan64(x); }
    u64 quiet(u64 x) const { return es == 4 ? (x | 0x400000) : (x | 0x8000000000000ull); }
    u64 defnan() const { return es == 4 ? 0x7fc00000ull : 0x7ff8000000000000ull; }
    u64 sign() const { return es == 4 ? 0x80000000ull : 0x8000000000000000ull; }
    u64 abs(u64 x) const { return x & ~sign(); }
    bool is_zero(u64 x) const { return abs(x) == 0; }
    bool is_inf(u64 x) const { return es == 4 ? abs(x) == 0x7f800000ull : abs(x) == 0x7ff0000000000000ull; }
    double d(u64 x) const { return es == 4 ? (double)f32(x) : f64(x); }
    u64 nanres(u64 x) const { return dn() ? defnan() : quiet(x); }
    // FPProcessNaNs; returns true if a NaN result was produced in *r
    bool nans2(u64 a, u64 b, u64* r) const {
        if (is_snan(a)) { *r = nanres(a); return true; }
        if (is_snan(b)) { *r = nanres(b); return true; }
        if (is_nan(a)) { *r = nanres(a); return true; }
        if (is_nan(b)) { *r = nanres(b); return true; }
        return false;
    }
    bool nans3(u64 a, u64 b, u64 c, u64* r) const {
        if (is_snan(a)) { *r = nanres(a); return true; }
        if (is_snan(b)) { *r = nanres(b); return true; }
        if (is_snan(c)) { *r = nanres(c); return true; }
        if (is_nan(a)) { *r = nanres(a); return true; }
        if (is_nan(b)) { *r = nanres(b); return true; }
        if (is_nan(c)) { *r = nanres(c); return true; }
        return false;
    }
    // canonicalize host result: generated NaN -> default NaN
    u64 fix(u64 r) const { return is_nan(r) ? defnan() : r; }
    u64 add(u64 a, u64 b) const {
        u64 r;
        if (nans2(a, b, &r)) return r;
        return fix(es == 4 ? bits32(f32(a) + f32(b)) : bits64(f64(a) + f64(b)));
    }
    u64 sub(u64 a, u64 b) const {
        u64 r;
        if (nans2(a, b, &r)) return r;
        return fix(es == 4 ? bits32(f32(a) - f32(b)) : bits64(f64(a) - f64(b)));
    }
    u64 mul(u64 a, u64 b) const {
        u64 r;
        if (nans2(a, b, &r)) return r;
        return fix(es == 4 ? bits32(f32(a) * f32(b)) : bits64(f64(a) * f64(b)));
    }
    u64 mulx(u64 a, u64 b) const {
        u64 r;
        if (nans2(a, b, &r)) return r;
        if ((is_inf(a) && is_zero(b)) || (is_zero(a) && is_inf(b))) {
            u64 s = (a ^ b) & sign();
            return s | (es == 4 ? 0x40000000ull : 0x4000000000000000ull);
        }
        return mul(a, b);
    }
    u64 div(u64 a, u64 b) const {
        u64 r;
        if (nans2(a, b, &r)) return r;
        return fix(es == 4 ? bits32(f32(a) / f32(b)) : bits64(f64(a) / f64(b)));
    }
    u64 sqrt(u64 a) const {
        if (is_nan(a)) return nanres(a);
        return fix(es == 4 ? bits32(sqrtf(f32(a))) : bits64(::sqrt(f64(a))));
    }
    // fused: addend + a*b
    u64 fma(u64 addend, u64 a, u64 b) const {
        u64 r;
        // inf*0 + qnan -> default NaN (invalid), checked before NaN propagation
        if (is_nan(addend) && !is_snan(addend) && !is_snan(a) && !is_snan(b) &&
            ((is_inf(a) && is_zero(b)) || (is_zero(a) && is_inf(b))))
            return defnan();
        if (nans3(addend, a, b, &r)) return r;
        return fix(es == 4 ? bits32(fmaf(f32(a), f32(b), f32(addend))) : bits64(::fma(f64(a), f64(b), f64(addend))));
    }
    u64 neg(u64 a) const { return a ^ sign(); }
    int cmp(u64 a, u64 b) const {  // -1 less, 0 eq, 1 greater, 2 unordered
        if (is_nan(a) || is_nan(b)) return 2;
        double x = d(a), y = d(b);
        return x < y ? -1 : x > y ? 1 : 0;
    }
    u64 max(u64 a, u64 b) const {
        u64 r;
        if (nans2(a, b, &r)) return r;
        if (is_zero(a) && is_zero(b)) return a & b;  // +0 wins
        return d(a) > d(b) ? a : b;
    }
    u64 min(u64 a, u64 b) const {
        u64 r;
        if (nans2(a, b, &r)) return r;
        if (is_zero(a) && is_zero(b)) return a | b;  // -0 wins
        return d(a) < d(b) ? a : b;
    }
    u64 maxnm(u64 a, u64 b) const {
        bool qa = is_nan(a) && !is_snan(a), qb = is_nan(b) && !is_snan(b);
        if (qa && !is_nan(b)) return b;
        if (qb && !is_nan(a)) return a;
        return max(a, b);
    }
    u64 minnm(u64 a, u64 b) const {
        bool qa = is_nan(a) && !is_snan(a), qb = is_nan(b) && !is_snan(b);
        if (qa && !is_nan(b)) return b;
        if (qb && !is_nan(a)) return a;
        return min(a, b);
    }
    u64 round_int(u64 a, int mode, bool exact) const {
        (void)exact;
        if (is_nan(a)) return nanres(a);
        if (is_inf(a) || is_zero(a)) return a;
        double x = d(a), r;
        if (mode == FR_CURRENT) mode = (int)((fpcr >> 22) & 3);
        switch (mode) {
        case FR_TIEEVEN: r = nearbyint_even(x); break;
        case FR_POSINF: r = ceil(x); break;
        case FR_NEGINF: r = floor(x); break;
        case FR_ZERO: r = trunc(x); break;
        case FR_TIEAWAY: r = ::round(x); break;
        default: r = nearbyint_even(x); break;
        }
        u64 out = es == 4 ? bits32((float)r) : bits64(r);
        if (r == 0) out = (a & sign());  // keep sign of zero
        return out;
    }
    static double nearbyint_even(double x) {
        double r = ::floor(x);
        double diff = x - r;
        if (diff > 0.5) r += 1;
        else if (diff == 0.5 && fmod(r, 2.0) != 0) r += 1;
        return r;
    }
    // float -> integer with rounding and saturation (to signed/unsigned of `ibits`)
    u64 to_int(u64 a, int mode, bool is_signed, int ibits, int fbits = 0) const {
        if (is_nan(a)) return 0;
        double x = d(a);
        if (fbits) x = ldexp(x, fbits);
        if (mode == FR_CURRENT) mode = (int)((fpcr >> 22) & 3);
        double r;
        switch (mode) {
        case FR_TIEEVEN: r = nearbyint_even(x); break;
        case FR_POSINF: r = ceil(x); break;
        case FR_NEGINF: r = floor(x); break;
        case FR_ZERO: r = trunc(x); break;
        case FR_TIEAWAY: r = ::round(x); break;
        default: r = trunc(x); break;
        }
        if (is_signed) {
            double hi = ldexp(1.0, ibits - 1);
            if (r >= hi) return ibits == 64 ? (u64)INT64_MAX : ((1ull << (ibits - 1)) - 1);
            if (r < -hi) return ibits == 64 ? (u64)INT64_MIN : (u64)(-(i64)(1ull << (ibits - 1))) & ((1ull << ibits) - 1);
            i64 v = (i64)r;
            return ibits == 64 ? (u64)v : ((u64)v & ((1ull << ibits) - 1));
        }
        double hi = ldexp(1.0, ibits);
        if (r >= hi) return ibits == 64 ? ~0ull : ((1ull << ibits) - 1);
        if (r <= 0) return 0;
        return (u64)r;
    }
    u64 from_int(u64 v, bool is_signed, int ibits, int fbits = 0) const {
        // exact rounding in current rounding mode
        if (es == 4) {
            float f;
            if (is_signed) f = ibits == 64 ? (float)(i64)v : (float)(i32)(u32)v;
            else f = ibits == 64 ? (float)v : (float)(u32)v;
            if (fbits) f = ldexpf(f, -fbits);
            return bits32(f);
        }
        double d;
        if (is_signed) d = ibits == 64 ? (double)(i64)v : (double)(i32)(u32)v;
        else d = ibits == 64 ? (double)v : (double)(u32)v;
        if (fbits) d = ldexp(d, -fbits);
        return bits64(d);
    }
};

// half precision conversions (IEEE binary16)
u32 h2f(u16 h) {
    u32 s = (h >> 15) & 1, e = (h >> 10) & 0x1f, m = h & 0x3ff;
    u32 r;
    if (e == 0) {
        if (m == 0) r = s << 31;
        else {
            int sh = 0;
            while (!(m & 0x400)) { m <<= 1; sh++; }
            m &= 0x3ff;
            r = (s << 31) | ((127 - 15 - sh + 1) << 23) | (m << 13);
        }
    } else if (e == 31) r = (s << 31) | 0x7f800000 | (m << 13) | (m ? 0x400000 : 0);
    else r = (s << 31) | ((e - 15 + 127) << 23) | (m << 13);
    return r;
}
u16 f2h(u32 f) {
    u32 s = (f >> 16) & 0x8000;
    i32 e = (i32)((f >> 23) & 0xff) - 127 + 15;
    u32 m = f & 0x7fffff;
    if (((f >> 23) & 0xff) == 0xff) return (u16)(s | 0x7c00 | (m ? (0x200 | (m >> 13)) : 0));
    if (e >= 31) return (u16)(s | 0x7c00);
    if (e <= 0) {
        if (e < -10) return (u16)s;
        m |= 0x800000;
        int shift = 14 - e;
        u32 hm = m >> shift;
        u32 rem = m & ((1u << shift) - 1), half = 1u << (shift - 1);
        if (rem > half || (rem == half && (hm & 1))) hm++;
        return (u16)(s | hm);
    }
    u32 hm = m >> 13, rem = m & 0x1fff;
    u32 r = s | ((u32)e << 10) | hm;
    if (rem > 0x1000 || (rem == 0x1000 && (hm & 1))) r++;
    return (u16)r;
}

// ---------------- AES ----------------
const u8 kSbox[256] = {
    0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,
    0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
    0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,
    0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
    0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,
    0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
    0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,
    0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
    0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,
    0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
    0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16};
u8 inv_sbox[256];
bool inv_init = [] { for (int i = 0; i < 256; i++) inv_sbox[kSbox[i]] = (u8)i; return true; }();
inline u8 xt(u8 x) { return (u8)((x << 1) ^ ((x & 0x80) ? 0x1b : 0)); }
inline u32 rol32(u32 x, int n) { return (x << n) | (x >> (32 - n)); }
inline u32 ror32(u32 x, int n) { return (x >> n) | (x << (32 - n)); }
inline u32 sha_choose(u32 x, u32 y, u32 z) { return ((y ^ z) & x) ^ z; }
inline u32 sha_majority(u32 x, u32 y, u32 z) { return (x & y) | ((x | y) & z); }
inline u8 gmul(u8 a, u8 b) {
    u8 p = 0;
    for (int i = 0; i < 8; i++) { if (b & 1) p ^= a; a = xt(a); b >>= 1; }
    return p;
}

int clz_es(u64 x, int es) {
    int bits = es * 8;
    for (int i = bits - 1; i >= 0; i--) if (x >> i & 1) return bits - 1 - i;
    return bits;
}

// ARM UnsignedRecipEstimate / RecipEstimate tables (8-bit precision)
u32 recip_estimate(u32 a) {  // a in [256, 511]
    a = a * 2 + 1;
    u32 b = (1u << 19) / a;
    return (b + 1) / 2;  // in [256, 511]
}
u32 rsqrt_estimate(u32 a) {  // a in [128, 511]
    if (a < 256) a = a * 2 + 1;
    else { a = (a >> 1) << 1; a = (a + 1) * 2; }
    u32 b = 512;
    while (a * (b + 1) * (b + 1) < (1u << 28)) b++;
    return (b + 1) / 2;
}

}  // namespace

u32 fp_estimate_recip32(u32 x, u32 fpcr) {
    (void)fpcr;
    return x;
}

static u64 frecpe(u64 x, int es, u32 fpcr) {
    FP fp{es, fpcr};
    if (fp.is_nan(x)) return fp.nanres(x);
    u64 sgn = x & fp.sign();
    if (fp.is_inf(x)) return sgn;
    if (fp.is_zero(x) || (fp.fz() && fp.is_denormal(x))) return sgn | (es == 4 ? 0x7f800000ull : 0x7ff0000000000000ull);
    // |x| < 2^-128 (single) / 2^-1024 (double): the estimate overflows, to infinity unless
    // rounding toward zero or away from the sign (then the largest normal number)
    if (fp.abs(x) < (es == 4 ? 0x00200000ull : 0x0004000000000000ull)) {
        u32 rm = (fpcr >> 22) & 3;
        bool inf = rm == 0 || (rm == 1 && !sgn) || (rm == 2 && sgn);
        u64 r = es == 4 ? 0x7f800000ull : 0x7ff0000000000000ull;
        return sgn | (inf ? r : r - 1);
    }
    if (es == 4) {
        u32 v = (u32)x;
        int exp = (v >> 23) & 0xff;
        u64 frac = (u64)(v & 0x7fffff) << 29;   // as 52-bit fraction
        if (exp == 0) {  // denormal
            if (!(frac & (1ull << 51))) { exp = -1; frac = (frac << 2) & 0xfffffffffffffull; }
            else frac = (frac << 1) & 0xfffffffffffffull;
        }
        if (exp >= 253 && fp.fz()) return sgn;  // |x| >= 2^126: the estimate underflows (else denormal)
        u32 scaled = (u32)(0x100 | (frac >> 44));
        int res_exp = 253 - exp;
        u32 est = recip_estimate(scaled);
        u64 res_frac = (u64)(est & 0xff) << 44;
        if (res_exp == 0) res_frac = (1ull << 51) | (res_frac >> 1);
        else if (res_exp == -1) { res_frac = (1ull << 50) | (res_frac >> 2); res_exp = 0; }
        return sgn | ((u64)(res_exp & 0xff) << 23) | (res_frac >> 29);
    }
    int exp = (int)((x >> 52) & 0x7ff);
    u64 frac = x & 0xfffffffffffffull;
    if (exp == 0) {
        if (!(frac & (1ull << 51))) { exp = -1; frac = (frac << 2) & 0xfffffffffffffull; }
        else frac = (frac << 1) & 0xfffffffffffffull;
    }
    if (exp >= 2045 && fp.fz()) return sgn;
    u32 scaled = (u32)(0x100 | (frac >> 44));
    int res_exp = 2045 - exp;
    u32 est = recip_estimate(scaled);
    u64 res_frac = (u64)(est & 0xff) << 44;
    if (res_exp == 0) res_frac = (1ull << 51) | (res_frac >> 1);
    else if (res_exp == -1) { res_frac = (1ull << 50) | (res_frac >> 2); res_exp = 0; }
    return sgn | ((u64)(res_exp & 0x7ff) << 52) | res_frac;
}

static u64 frsqrte(u64 x, int es, u32 fpcr) {
    FP fp{es, fpcr};
    if (fp.is_nan(x)) return fp.nanres(x);
    u64 sgn = x & fp.sign();
    if (fp.is_zero(x) || (fp.fz() && fp.is_denormal(x))) return sgn | (es == 4 ? 0x7f800000ull : 0x7ff0000000000000ull);
    if (sgn) return fp.defnan();
    if (fp.is_inf(x)) return 0;
    int exp;
    u64 frac;
    if (es == 4) { exp = (int)((x >> 23) & 0xff); frac = (x & 0x7fffff) << 29; }
    else { exp = (int)((x >> 52) & 0x7ff); frac = x & 0xfffffffffffffull; }
    if (exp == 0) {
        while (!(frac & (1ull << 51))) { frac <<= 1; exp--; }
        frac = (frac << 1) & 0xfffffffffffffull;
    }
    u32 scaled = (exp & 1) == 0 ? (u32)(0x100 | (frac >> 44)) : (u32)(0x80 | (frac >> 45));
    int res_exp = es == 4 ? (380 - exp) / 2 : (3068 - exp) / 2;
    u32 est = rsqrt_estimate(scaled);
    if (es == 4) return ((u64)(res_exp & 0xff) << 23) | ((u64)(est & 0xff) << 15);
    return ((u64)(res_exp & 0x7ff) << 52) | ((u64)(est & 0xff) << 44);
}

void vec_ref(u32 op, int es, u32 flags, u64 imm, const V128& a, const V128& b, const V128& c, V128& out,
             u32 fpcr) {
    V128 r{};
    bool scalar = flags & F_SCALAR;
    int bytes = (flags & F_HALF) ? 8 : 16;
    int n = scalar ? 1 : bytes / (es > 8 ? 8 : es);
    FP fp{es, fpcr};
    auto elementwise = [&](auto f) {
        for (int i = 0; i < n; i++) put(r, i, es, f(get(a, i, es), get(b, i, es), get(c, i, es)) & emask(es));
    };
    auto bitwise = [&](auto f) {
        int nb = scalar ? 8 : bytes;
        for (int i = 0; i < nb; i++) r.b[i] = f(a.b[i], b.b[i], c.b[i]);
    };
    auto pairwise = [&](auto f) {
        if (scalar) { put(r, 0, es, f(get(a, 0, es), get(a, 1, es)) & emask(es)); return; }
        int half = n / 2;
        for (int i = 0; i < half; i++) put(r, i, es, f(get(a, 2 * i, es), get(a, 2 * i + 1, es)) & emask(es));
        for (int i = 0; i < half; i++) put(r, half + i, es, f(get(b, 2 * i, es), get(b, 2 * i + 1, es)) & emask(es));
    };
    int eb = es * 8;
    switch (op) {
    case V_AND: bitwise([](u8 x, u8 y, u8) { return (u8)(x & y); }); break;
    case V_ORR: bitwise([](u8 x, u8 y, u8) { return (u8)(x | y); }); break;
    case V_EOR: bitwise([](u8 x, u8 y, u8) { return (u8)(x ^ y); }); break;
    case V_BIC: bitwise([](u8 x, u8 y, u8) { return (u8)(x & ~y); }); break;
    case V_ORN: bitwise([](u8 x, u8 y, u8) { return (u8)(x | ~y); }); break;
    case V_NOT: bitwise([](u8 x, u8, u8) { return (u8)~x; }); break;
    case V_BSL: bitwise([](u8 m, u8 x, u8 y) { return (u8)((m & x) | (~m & y)); }); break;
    case V_ADD: elementwise([](u64 x, u64 y, u64) { return x + y; }); break;
    case V_SUB: elementwise([](u64 x, u64 y, u64) { return x - y; }); break;
    case V_MUL: elementwise([](u64 x, u64 y, u64) { return x * y; }); break;
    case V_MLA: elementwise([](u64 x, u64 y, u64 z) { return z + x * y; }); break;
    case V_MLS: elementwise([](u64 x, u64 y, u64 z) { return z - x * y; }); break;
    case V_NEG: elementwise([](u64 x, u64, u64) { return -x; }); break;
    case V_ABS: elementwise([&](u64 x, u64, u64) { i64 v = sx(x, es); return (u64)(v < 0 ? -v : v); }); break;
    case V_SQABS: elementwise([&](u64 x, u64, u64) { __int128 v = sx(x, es); return sat_s(v < 0 ? -v : v, es); }); break;
    case V_SQNEG: elementwise([&](u64 x, u64, u64) { return sat_s(-(__int128)sx(x, es), es); }); break;
    case V_SMAX: elementwise([&](u64 x, u64 y, u64) { return sx(x, es) > sx(y, es) ? x : y; }); break;
    case V_SMIN: elementwise([&](u64 x, u64 y, u64) { return sx(x, es) < sx(y, es) ? x : y; }); break;
    case V_UMAX: elementwise([](u64 x, u64 y, u64) { return x > y ? x : y; }); break;
    case V_UMIN: elementwise([](u64 x, u64 y, u64) { return x < y ? x : y; }); break;
    case V_ADDP: pairwise([](u64 x, u64 y) { return x + y; }); break;
    case V_SMAXP: pairwise([&](u64 x, u64 y) { return sx(x, es) > sx(y, es) ? x : y; }); break;
    case V_SMINP: pairwise([&](u64 x, u64 y) { return sx(x, es) < sx(y, es) ? x : y; }); break;
    case V_UMAXP: pairwise([](u64 x, u64 y) { return x > y ? x : y; }); break;
    case V_UMINP: pairwise([](u64 x, u64 y) { return x < y ? x : y; }); break;
    case V_UQADD: elementwise([&](u64 x, u64 y, u64) { return sat_u((__int128)x + y, es); }); break;
    case V_SQADD: elementwise([&](u64 x, u64 y, u64) { return sat_s((__int128)sx(x, es) + sx(y, es), es); }); break;
    case V_UQSUB: elementwise([&](u64 x, u64 y, u64) { return sat_u((__int128)x - y, es); }); break;
    case V_SQSUB: elementwise([&](u64 x, u64 y, u64) { return sat_s((__int128)sx(x, es) - sx(y, es), es); }); break;
    case V_SUQADD: elementwise([&](u64 x, u64, u64 z) { return sat_s((__int128)sx(z, es) + x, es); }); break;
    case V_USQADD: elementwise([&](u64 x, u64, u64 z) { return sat_u((__int128)z + sx(x, es), es); }); break;
    case V_URHADD: elementwise([](u64 x, u64 y, u64) { return (u64)(((unsigned __int128)x + y + 1) >> 1); }); break;
    case V_SRHADD: elementwise([&](u64 x, u64 y, u64) { return (u64)(((__int128)sx(x, es) + sx(y, es) + 1) >> 1); }); break;
    case V_UHADD: elementwise([](u64 x, u64 y, u64) { return (u64)(((unsigned __int128)x + y) >> 1); }); break;
    case V_SHADD: elementwise([&](u64 x, u64 y, u64) { return (u64)(((__int128)sx(x, es) + sx(y, es)) >> 1); }); break;
    case V_UHSUB: elementwise([](u64 x, u64 y, u64) { return (u64)(((__int128)x - (__int128)y) >> 1); }); break;
    case V_SHSUB: elementwise([&](u64 x, u64 y, u64) { return (u64)(((__int128)sx(x, es) - sx(y, es)) >> 1); }); break;
    case V_SABD: elementwise([&](u64 x, u64 y, u64) { __int128 d = (__int128)sx(x, es) - sx(y, es); return (u64)(d < 0 ? -d : d); }); break;
    case V_UABD: elementwise([](u64 x, u64 y, u64) { return x > y ? x - y : y - x; }); break;
    case V_SABA: elementwise([&](u64 x, u64 y, u64 z) { __int128 d = (__int128)sx(x, es) - sx(y, es); return z + (u64)(d < 0 ? -d : d); }); break;
    case V_UABA: elementwise([](u64 x, u64 y, u64 z) { return z + (x > y ? x - y : y - x); }); break;
    case V_CMEQ: elementwise([](u64 x, u64 y, u64) { return x == y ? ~0ull : 0; }); break;
    case V_CMGT: elementwise([&](u64 x, u64 y, u64) { return sx(x, es) > sx(y, es) ? ~0ull : 0; }); break;
    case V_CMGE: elementwise([&](u64 x, u64 y, u64) { return sx(x, es) >= sx(y, es) ? ~0ull : 0; }); break;
    case V_CMHI: elementwise([](u64 x, u64 y, u64) { return x > y ? ~0ull : 0; }); break;
    case V_CMHS: elementwise([](u64 x, u64 y, u64) { return x >= y ? ~0ull : 0; }); break;
    case V_CMTST: elementwise([](u64 x, u64 y, u64) { return (x & y) ? ~0ull : 0; }); break;
    case V_SSHL: case V_USHL: case V_SRSHL: case V_URSHL: case V_SQSHL: case V_UQSHL: case V_SQRSHL: case V_UQRSHL: {
        bool sg = op == V_SSHL || op == V_SRSHL || op == V_SQSHL || op == V_SQRSHL;
        bool rnd = op == V_SRSHL || op == V_URSHL || op == V_SQRSHL || op == V_UQRSHL;
        bool sat = op == V_SQSHL || op == V_UQSHL || op == V_SQRSHL || op == V_UQRSHL;
        elementwise([&](u64 x, u64 y, u64) -> u64 {
            int sh = (int)(i8)(y & 0xff);
            __int128 v = sg ? (__int128)sx(x, es) : (__int128)x;
            if (sh >= 0) {
                __int128 res = sh >= 64 ? (v == 0 ? 0 : (v > 0 ? ((__int128)1 << 100) : -((__int128)1 << 100))) : v * ((__int128)1 << sh);
                if (sat) return sg ? sat_s(res, es) : sat_u(res, es);
                return sh >= eb ? 0 : (u64)res;
            }
            int rs = -sh;
            if (rnd) {
                if (rs > eb) return 0;
                __int128 rv = (v + ((__int128)1 << (rs - 1))) >> rs;
                return sat ? (sg ? sat_s(rv, es) : sat_u(rv, es)) : (u64)rv;
            }
            if (rs >= eb) return sg ? (u64)(v < 0 ? -1 : 0) : 0;
            return (u64)(v >> rs);
        });
        break;
    }
    case V_SHL_I: elementwise([&](u64 x, u64, u64) { return imm >= (u64)eb ? 0 : x << imm; }); break;
    case V_USHR_I: elementwise([&](u64 x, u64, u64) { return imm >= (u64)eb ? 0 : x >> imm; }); break;
    case V_SSHR_I: elementwise([&](u64 x, u64, u64) { return (u64)(sx(x, es) >> (imm >= (u64)eb ? eb - 1 : imm)); }); break;
    case V_URSHR_I: elementwise([&](u64 x, u64, u64) { return (u64)(((unsigned __int128)x + ((unsigned __int128)1 << (imm - 1))) >> imm); }); break;
    case V_SRSHR_I: elementwise([&](u64 x, u64, u64) { return (u64)(((__int128)sx(x, es) + ((__int128)1 << (imm - 1))) >> imm); }); break;
    case V_USRA: elementwise([&](u64 x, u64, u64 z) { return z + (imm >= (u64)eb ? 0 : x >> imm); }); break;
    case V_SSRA: elementwise([&](u64 x, u64, u64 z) { return z + (u64)(sx(x, es) >> (imm >= (u64)eb ? eb - 1 : imm)); }); break;
    case V_URSRA: elementwise([&](u64 x, u64, u64 z) { return z + (u64)(((unsigned __int128)x + ((unsigned __int128)1 << (imm - 1))) >> imm); }); break;
    case V_SRSRA: elementwise([&](u64 x, u64, u64 z) { return z + (u64)(((__int128)sx(x, es) + ((__int128)1 << (imm - 1))) >> imm); }); break;
    case V_SRI: elementwise([&](u64 x, u64, u64 z) {
        if (imm >= (u64)eb) return z;
        u64 m = emask(es) >> imm;
        return (z & ~m) | (x >> imm);
    }); break;
    case V_SLI: elementwise([&](u64 x, u64, u64 z) {
        u64 m = (emask(es) << imm) & emask(es);
        return (z & ~m) | ((x << imm) & m);
    }); break;
    case V_SQSHL_I: elementwise([&](u64 x, u64, u64) { return sat_s((__int128)sx(x, es) << imm, es); }); break;
    case V_UQSHL_I: elementwise([&](u64 x, u64, u64) { return sat_u((__int128)x << imm, es); }); break;
    case V_SQSHLU_I: elementwise([&](u64 x, u64, u64) { return sat_u((__int128)sx(x, es) << imm, es); }); break;
    case V_XTN: case V_SQXTN: case V_UQXTN: case V_SQXTUN: {
        int ws = es * 2;  // source element size
        int ln = scalar ? 1 : 8 / es;
        for (int i = 0; i < ln; i++) {
            u64 x = get(a, i, ws);
            u64 v;
            if (op == V_XTN) v = x & emask(es);
            else if (op == V_SQXTN) v = sat_s(sx(x, ws), es);
            else if (op == V_UQXTN) v = sat_u(x, es);
            else v = sat_u(sx(x, ws), es);
            put(r, i, es, v);
        }
        break;
    }
    case V_SHRN: case V_RSHRN: case V_SQSHRN: case V_SQRSHRN: case V_UQSHRN: case V_UQRSHRN: case V_SQSHRUN:
    case V_SQRSHRUN: {
        int ws = es * 2;
        int ln = scalar ? 1 : 8 / es;
        bool rnd = op == V_RSHRN || op == V_SQRSHRN || op == V_UQRSHRN || op == V_SQRSHRUN;
        bool sg = op == V_SQSHRN || op == V_SQRSHRN || op == V_SQSHRUN || op == V_SQRSHRUN;
        for (int i = 0; i < ln; i++) {
            u64 x = get(a, i, ws);
            __int128 v = sg ? (__int128)sx(x, ws) : (__int128)x;
            if (rnd) v += (__int128)1 << (imm - 1);
            v >>= imm;
            u64 o;
            if (op == V_SHRN || op == V_RSHRN) o = (u64)v & emask(es);
            else if (op == V_SQSHRN || op == V_SQRSHRN) o = sat_s(v, es);
            else o = sat_u(v, es);
            put(r, i, es, o);
        }
        break;
    }
    case V_UXTL: case V_SXTL: case V_SHLL: {
        int ln = 8 / es;
        for (int i = 0; i < ln; i++) {
            u64 x = get(a, i, es);
            u64 v = op == V_SXTL ? (u64)sx(x, es) : x;
            if (op == V_SHLL) v <<= eb;
            put(r, i, es * 2, v & emask(es * 2));
        }
        break;
    }
    case V_UMULL: case V_SMULL: case V_UMLAL: case V_SMLAL: case V_UMLSL: case V_SMLSL:
    case V_UADDL: case V_SADDL: case V_USUBL: case V_SSUBL: case V_UABDL: case V_SABDL: case V_UABAL: case V_SABAL:
    case V_UADDW: case V_SADDW: case V_USUBW: case V_SSUBW: {
        int ws = es * 2;
        int ln = 8 / es;
        bool sg = op == V_SMULL || op == V_SMLAL || op == V_SMLSL || op == V_SADDL || op == V_SSUBL || op == V_SABDL ||
                  op == V_SABAL || op == V_SADDW || op == V_SSUBW;
        bool wide = op == V_UADDW || op == V_SADDW || op == V_USUBW || op == V_SSUBW;
        for (int i = 0; i < ln; i++) {
            i64 x = wide ? (i64)get(a, i, ws) : (sg ? sx(get(a, i, es), es) : (i64)get(a, i, es));
            i64 y = sg ? sx(get(b, i, es), es) : (i64)get(b, i, es);
            u64 z = get(c, i, ws);
            u64 v;
            switch (op) {
            case V_UMULL: case V_SMULL: v = (u64)(x * y); break;
            case V_UMLAL: case V_SMLAL: v = z + (u64)(x * y); break;
            case V_UMLSL: case V_SMLSL: v = z - (u64)(x * y); break;
            case V_UADDL: case V_SADDL: case V_UADDW: case V_SADDW: v = (u64)(x + y); break;
            case V_USUBL: case V_SSUBL: case V_USUBW: case V_SSUBW: v = (u64)(x - y); break;
            case V_UABDL: case V_SABDL: v = (u64)(x > y ? x - y : y - x); break;
            default: v = z + (u64)(x > y ? x - y : y - x); break;
            }
            put(r, i, ws, v & emask(ws));
        }
        break;
    }
    case V_SQDMULL: case V_SQDMLAL: case V_SQDMLSL: {
        int ws = es * 2;
        int ln = scalar ? 1 : 8 / es;
        for (int i = 0; i < ln; i++) {
            __int128 p = (__int128)2 * sx(get(a, i, es), es) * sx(get(b, i, es), es);
            u64 pr = sat_s(p, ws);
            if (op == V_SQDMULL) { put(r, i, ws, pr); continue; }
            __int128 acc = sx(get(c, i, ws), ws);
            __int128 res = op == V_SQDMLAL ? acc + sx(pr, ws) : acc - sx(pr, ws);
            put(r, i, ws, sat_s(res, ws));
        }
        break;
    }
    case V_ADDHN: case V_SUBHN: case V_RADDHN: case V_RSUBHN: {
        int ws = es * 2;
        int ln = 8 / es;
        for (int i = 0; i < ln; i++) {
            unsigned __int128 x = get(a, i, ws), y = get(b, i, ws);
            unsigned __int128 v = (op == V_ADDHN || op == V_RADDHN) ? x + y : x - y;
            if (op == V_RADDHN || op == V_RSUBHN) v += (unsigned __int128)1 << (eb - 1);
            put(r, i, es, (u64)(v >> eb) & emask(es));
        }
        break;
    }
    case V_PMUL: elementwise([&](u64 x, u64 y, u64) {
        u64 p = 0;
        for (int k = 0; k < eb; k++) if (y >> k & 1) p ^= x << k;
        return p;
    }); break;
    case V_PMULL: {
        if (es == 8) {
            unsigned __int128 p = 0, x = get(a, 0, 8);
            u64 y = get(b, 0, 8);
            for (int k = 0; k < 64; k++) if (y >> k & 1) p ^= x << k;
            memcpy(r.b, &p, 16);
        } else {
            for (int i = 0; i < 8; i++) {
                u64 x = a.b[i], y = b.b[i], p = 0;
                for (int k = 0; k < 8; k++) if (y >> k & 1) p ^= x << k;
                put(r, i, 2, p & 0xffff);
            }
        }
        break;
    }
    case V_UZP1: case V_UZP2: case V_ZIP1: case V_ZIP2: case V_TRN1: case V_TRN2: {
        int ln = bytes / es;
        u64 x[32];
        for (int i = 0; i < ln; i++) { x[i] = get(a, i, es); x[ln + i] = get(b, i, es); }
        for (int i = 0; i < ln; i++) {
            u64 v;
            switch (op) {
            case V_UZP1: v = x[2 * i]; break;
            case V_UZP2: v = x[2 * i + 1]; break;
            case V_ZIP1: v = (i & 1) ? x[ln + i / 2] : x[i / 2]; break;
            case V_ZIP2: v = (i & 1) ? x[ln + ln / 2 + i / 2] : x[ln / 2 + i / 2]; break;
            case V_TRN1: v = (i & 1) ? x[ln + (i & ~1)] : x[i]; break;
            default: v = (i & 1) ? x[ln + i] : x[i | 1]; break;
            }
            put(r, i, es, v);
        }
        break;
    }
    case V_EXT: {
        u8 x[32];
        memcpy(x, a.b, bytes);
        memcpy(x + bytes, b.b, bytes);
        for (int i = 0; i < bytes; i++) r.b[i] = x[i + imm];
        break;
    }
    case V_TBL: case V_TBX: {
        for (int i = 0; i < 16; i++) {
            u8 idx = (u8)(b.b[i] - (u8)imm);
            r.b[i] = idx < 16 ? a.b[idx] : c.b[i];
        }
        break;
    }
    case V_REV16: case V_REV32: case V_REV64: {
        int cont = op == V_REV16 ? 2 : op == V_REV32 ? 4 : 8;
        int per = cont / es;
        for (int i = 0; i < n; i++) {
            int base = (i / per) * per;
            put(r, i, es, get(a, base + per - 1 - (i - base), es));
        }
        break;
    }
    case V_CNT: elementwise([](u64 x, u64, u64) { return (u64)__builtin_popcountll(x); }); break;
    case V_CLZ: elementwise([&](u64 x, u64, u64) { return (u64)clz_es(x, es); }); break;
    case V_CLS: elementwise([&](u64 x, u64, u64) {
        u64 y = (x ^ (x >> 1)) & (emask(es) >> 1);
        return (u64)(clz_es(y, es) - 1);
    }); break;
    case V_RBIT: elementwise([](u64 x, u64, u64) {
        u8 v = (u8)x, o = 0;
        for (int k = 0; k < 8; k++) if (v >> k & 1) o |= (u8)(0x80 >> k);
        return (u64)o;
    }); break;
    case V_ADDV: case V_UMAXV: case V_UMINV: case V_SMAXV: case V_SMINV: case V_UADDLV: case V_SADDLV: {
        int ln = bytes / es;
        u64 acc = get(a, 0, es);
        i64 sacc = sx(acc, es);
        for (int i = 1; i < ln; i++) {
            u64 x = get(a, i, es);
            switch (op) {
            case V_ADDV: case V_UADDLV: acc += x; break;
            case V_SADDLV: sacc += sx(x, es); break;
            case V_UMAXV: if (x > acc) acc = x; break;
            case V_UMINV: if (x < acc) acc = x; break;
            case V_SMAXV: if (sx(x, es) > sacc) sacc = sx(x, es); break;
            case V_SMINV: if (sx(x, es) < sacc) sacc = sx(x, es); break;
            }
        }
        if (op == V_SMAXV || op == V_SMINV) put(r, 0, es, (u64)sacc & emask(es));
        else if (op == V_SADDLV) put(r, 0, es * 2, (u64)sacc & emask(es * 2));
        else if (op == V_UADDLV) put(r, 0, es * 2, acc & emask(es * 2));
        else put(r, 0, es, acc & emask(es));
        break;
    }
    case V_UADDLP: case V_SADDLP: case V_UADALP: case V_SADALP: {
        int ln = bytes / es / 2;
        bool sg = op == V_SADDLP || op == V_SADALP;
        bool acc = op == V_UADALP || op == V_SADALP;
        for (int i = 0; i < ln; i++) {
            u64 x = get(a, 2 * i, es), y = get(a, 2 * i + 1, es);
            u64 v = sg ? (u64)(sx(x, es) + sx(y, es)) : x + y;
            if (acc) v += get(c, i, es * 2);
            put(r, i, es * 2, v & emask(es * 2));
        }
        break;
    }
    case V_DUPELEM: {
        u64 x = get(a, (int)imm, es);
        for (int i = 0; i < n; i++) put(r, i, es, x);
        break;
    }
    case V_INSELEM: {
        r = a;
        put(r, (int)(imm & 0xff), es, get(b, (int)(imm >> 8), es));
        out = r;
        return;
    }
    case V_ZEXT: memcpy(r.b, a.b, es); break;
    // ---- floating point ----
    case V_FADD: elementwise([&](u64 x, u64 y, u64) { return fp.add(x, y); }); break;
    case V_FSUB: elementwise([&](u64 x, u64 y, u64) { return fp.sub(x, y); }); break;
    case V_FMUL: elementwise([&](u64 x, u64 y, u64) { return fp.mul(x, y); }); break;
    case V_FMULX: elementwise([&](u64 x, u64 y, u64) { return fp.mulx(x, y); }); break;
    case V_FDIV: elementwise([&](u64 x, u64 y, u64) { return fp.div(x, y); }); break;
    case V_FMAX: elementwise([&](u64 x, u64 y, u64) { return fp.max(x, y); }); break;
    case V_FMIN: elementwise([&](u64 x, u64 y, u64) { return fp.min(x, y); }); break;
    case V_FMAXNM: elementwise([&](u64 x, u64 y, u64) { return fp.maxnm(x, y); }); break;
    case V_FMINNM: elementwise([&](u64 x, u64 y, u64) { return fp.minnm(x, y); }); break;
    case V_FSQRT: elementwise([&](u64 x, u64, u64) { return fp.sqrt(x); }); break;
    case V_FABS: elementwise([&](u64 x, u64, u64) { return fp.abs(x); }); break;
    case V_FNEG: elementwise([&](u64 x, u64, u64) { return fp.neg(x); }); break;
    case V_FMLA: elementwise([&](u64 x, u64 y, u64 z) { return fp.fma(z, x, y); }); break;
    case V_FMLS: elementwise([&](u64 x, u64 y, u64 z) { return fp.fma(z, fp.neg(x), y); }); break;
    case V_FNMUL: elementwise([&](u64 x, u64 y, u64) { return fp.neg(fp.mul(x, y)); }); break;
    case V_FMADD: elementwise([&](u64 x, u64 y, u64 z) { return fp.fma(z, x, y); }); break;
    case V_FMSUB: elementwise([&](u64 x, u64 y, u64 z) { return fp.fma(z, fp.neg(x), y); }); break;
    case V_FNMADD: elementwise([&](u64 x, u64 y, u64 z) { return fp.fma(fp.neg(z), fp.neg(x), y); }); break;
    case V_FNMSUB: elementwise([&](u64 x, u64 y, u64 z) { return fp.fma(fp.neg(z), x, y); }); break;
    case V_FCMEQ: elementwise([&](u64 x, u64 y, u64) { return fp.cmp(x, y) == 0 ? ~0ull : 0; }); break;
    case V_FCMGE: elementwise([&](u64 x, u64 y, u64) { int k = fp.cmp(x, y); return (k == 0 || k == 1) ? ~0ull : 0; }); break;
    case V_FCMGT: elementwise([&](u64 x, u64 y, u64) { return fp.cmp(x, y) == 1 ? ~0ull : 0; }); break;
    case V_FACGE: elementwise([&](u64 x, u64 y, u64) { int k = fp.cmp(fp.abs(x), fp.abs(y)); return (k == 0 || k == 1) ? ~0ull : 0; }); break;
    case V_FACGT: elementwise([&](u64 x, u64 y, u64) { return fp.cmp(fp.abs(x), fp.abs(y)) == 1 ? ~0ull : 0; }); break;
    case V_FABD: elementwise([&](u64 x, u64 y, u64) { return fp.abs(fp.sub(x, y)); }); break;
    case V_FADDP: pairwise([&](u64 x, u64 y) { return fp.add(x, y); }); break;
    case V_FMAXP: pairwise([&](u64 x, u64 y) { return fp.max(x, y); }); break;
    case V_FMINP: pairwise([&](u64 x, u64 y) { return fp.min(x, y); }); break;
    case V_FMAXNMP: pairwise([&](u64 x, u64 y) { return fp.maxnm(x, y); }); break;
    case V_FMINNMP: pairwise([&](u64 x, u64 y) { return fp.minnm(x, y); }); break;
    case V_FMAXV: case V_FMINV: case V_FMAXNMV: case V_FMINNMV: {
        u64 x0 = get(a, 0, 4), x1 = get(a, 1, 4), x2 = get(a, 2, 4), x3 = get(a, 3, 4);
        auto f = [&](u64 x, u64 y) {
            return op == V_FMAXV ? fp.max(x, y) : op == V_FMINV ? fp.min(x, y) : op == V_FMAXNMV ? fp.maxnm(x, y) : fp.minnm(x, y);
        };
        put(r, 0, 4, f(f(x0, x1), f(x2, x3)));
        break;
    }
    case V_FRECPS: elementwise([&](u64 x, u64 y, u64) {
        u64 two = es == 4 ? 0x40000000ull : 0x4000000000000000ull;
        u64 rr;
        if (fp.nans2(x, y, &rr)) return rr;
        if ((fp.is_inf(x) && fp.is_zero(y)) || (fp.is_zero(x) && fp.is_inf(y))) return two;
        return fp.fma(two, fp.neg(x), y);
    }); break;
    case V_FRSQRTS: elementwise([&](u64 x, u64 y, u64) {
        u64 three = es == 4 ? 0x40400000ull : 0x4008000000000000ull;
        u64 onehalf = es == 4 ? 0x3fc00000ull : 0x3ff8000000000000ull;
        u64 rr;
        if (fp.nans2(x, y, &rr)) return rr;
        if ((fp.is_inf(x) && fp.is_zero(y)) || (fp.is_zero(x) && fp.is_inf(y))) return onehalf;
        // (3 - x*y) / 2 computed fused
        u64 t = fp.fma(three, fp.neg(x), y);
        return es == 4 ? bits32(f32(t) / 2) : bits64(f64(t) / 2);
    }); break;
    case V_FRECPE: elementwise([&](u64 x, u64, u64) { return frecpe(x, es, fpcr); }); break;
    case V_FRSQRTE: elementwise([&](u64 x, u64, u64) { return frsqrte(x, es, fpcr); }); break;
    case V_URECPE: elementwise([&](u64 x, u64, u64) -> u64 {
        u32 v = (u32)x;
        if (!(v & 0x80000000u)) return 0xffffffffu;
        u32 est = recip_estimate(v >> 23);
        return (u64)est << 23;
    }); break;
    case V_URSQRTE: elementwise([&](u64 x, u64, u64) -> u64 {
        u32 v = (u32)x;
        if (!(v & 0xc0000000u)) return 0xffffffffu;
        u32 est = rsqrt_estimate(v >> 23);
        return (u64)est << 23;
    }); break;
    case V_SCVTF: elementwise([&](u64 x, u64, u64) { return fp.from_int(x, true, eb); }); break;
    case V_UCVTF: elementwise([&](u64 x, u64, u64) { return fp.from_int(x, false, eb); }); break;
    case V_SCVTF_FIX: elementwise([&](u64 x, u64, u64) { return fp.from_int(x, true, eb, (int)imm); }); break;
    case V_UCVTF_FIX: elementwise([&](u64 x, u64, u64) { return fp.from_int(x, false, eb, (int)imm); }); break;
    case V_FCVTZS: elementwise([&](u64 x, u64, u64) { return fp.to_int(x, (int)imm, true, eb); }); break;
    case V_FCVTZU: elementwise([&](u64 x, u64, u64) { return fp.to_int(x, (int)imm, false, eb); }); break;
    case V_FCVTZS_FIX: elementwise([&](u64 x, u64, u64) { return fp.to_int(x, FR_ZERO, true, eb, (int)imm); }); break;
    case V_FCVTZU_FIX: elementwise([&](u64 x, u64, u64) { return fp.to_int(x, FR_ZERO, false, eb, (int)imm); }); break;
    case V_FRINT: case V_FRINTX: elementwise([&](u64 x, u64, u64) { return fp.round_int(x, (int)imm, op == V_FRINTX); }); break;
    case V_FCVTS2D: {
        u32 x = (u32)get(a, 0, 4);
        u64 v;
        if (is_nan32(x)) v = (fpcr & (1u << 25)) ? 0x7ff8000000000000ull
                           : (((u64)(x >> 31) << 63) | 0x7ff8000000000000ull | ((u64)(x & 0x3fffff) << 29));
        else v = bits64((double)f32(x));
        put(r, 0, 8, v);
        break;
    }
    case V_FCVTD2S: {
        u64 x = get(a, 0, 8);
        u64 v;
        if (is_nan64(x)) v = (fpcr & (1u << 25)) ? 0x7fc00000ull
                           : (((x >> 63) << 31) | 0x7fc00000ull | ((x >> 29) & 0x3fffff));
        else v = bits32((float)f64(x));
        put(r, 0, 4, v);
        break;
    }
    case V_FCVTH2S: put(r, 0, 4, h2f((u16)get(a, 0, 2))); break;
    case V_FCVTS2H: put(r, 0, 2, f2h((u32)get(a, 0, 4))); break;
    case V_FCVTH2D: put(r, 0, 8, bits64((double)f32(h2f((u16)get(a, 0, 2))))); break;
    case V_FCVTD2H: put(r, 0, 2, f2h((u32)bits32((float)f64(get(a, 0, 8))))); break;
    case V_FCVTN: {
        if (es == 8) {
            for (int i = 0; i < 2; i++) {
                V128 t{}, o;
                put(t, 0, 8, get(a, i, 8));
                vec_ref(V_FCVTD2S, 8, F_SCALAR, 0, t, t, t, o, fpcr);
                put(r, i, 4, get(o, 0, 4));
            }
        } else {
            for (int i = 0; i < 4; i++) put(r, i, 2, f2h((u32)get(a, i, 4)));
        }
        break;
    }
    case V_FCVTL: {
        if (es == 8) {
            for (int i = 0; i < 2; i++) {
                V128 t{}, o;
                put(t, 0, 4, get(a, i, 4));
                vec_ref(V_FCVTS2D, 4, F_SCALAR, 0, t, t, t, o, fpcr);
                put(r, i, 8, get(o, 0, 8));
            }
        } else {
            for (int i = 0; i < 4; i++) put(r, i, 4, h2f((u16)get(a, i, 2)));
        }
        break;
    }
    case V_SQDMULH: case V_SQRDMULH: elementwise([&](u64 x, u64 y, u64) {
        __int128 p = (__int128)2 * sx(x, es) * sx(y, es);
        if (op == V_SQRDMULH) p += (__int128)1 << (eb - 1);
        return sat_s(p >> eb, es);
    }); break;
    case V_AESE: case V_AESD: {
        u8 st[16];
        for (int i = 0; i < 16; i++) st[i] = a.b[i] ^ b.b[i];
        if (op == V_AESE) {
            static const int sr[16] = {0, 5, 10, 15, 4, 9, 14, 3, 8, 13, 2, 7, 12, 1, 6, 11};
            for (int i = 0; i < 16; i++) r.b[i] = kSbox[st[sr[i]]];
        } else {
            static const int isr[16] = {0, 13, 10, 7, 4, 1, 14, 11, 8, 5, 2, 15, 12, 9, 6, 3};
            for (int i = 0; i < 16; i++) r.b[i] = inv_sbox[st[isr[i]]];
        }
        break;
    }
    case V_AESMC: case V_AESIMC: {
        for (int col = 0; col < 4; col++) {
            const u8* s = a.b + col * 4;
            u8* d = r.b + col * 4;
            if (op == V_AESMC) {
                d[0] = (u8)(xt(s[0]) ^ (xt(s[1]) ^ s[1]) ^ s[2] ^ s[3]);
                d[1] = (u8)(s[0] ^ xt(s[1]) ^ (xt(s[2]) ^ s[2]) ^ s[3]);
                d[2] = (u8)(s[0] ^ s[1] ^ xt(s[2]) ^ (xt(s[3]) ^ s[3]));
                d[3] = (u8)((xt(s[0]) ^ s[0]) ^ s[1] ^ s[2] ^ xt(s[3]));
            } else {
                d[0] = gmul(s[0], 14) ^ gmul(s[1], 11) ^ gmul(s[2], 13) ^ gmul(s[3], 9);
                d[1] = gmul(s[0], 9) ^ gmul(s[1], 14) ^ gmul(s[2], 11) ^ gmul(s[3], 13);
                d[2] = gmul(s[0], 13) ^ gmul(s[1], 9) ^ gmul(s[2], 14) ^ gmul(s[3], 11);
                d[3] = gmul(s[0], 11) ^ gmul(s[1], 13) ^ gmul(s[2], 9) ^ gmul(s[3], 14);
            }
        }
        break;
    }
    case V_SHA1C: case V_SHA1P: case V_SHA1M: {   // a = Qd (hash state), b = Sn, c = Vm (schedule)
        u32 x[4], y = (u32)get(b, 0, 4);
        for (int e = 0; e < 4; e++) x[e] = (u32)get(a, e, 4);
        for (int e = 0; e < 4; e++) {
            u32 f = op == V_SHA1C ? sha_choose(x[1], x[2], x[3])
                  : op == V_SHA1P ? (x[1] ^ x[2] ^ x[3]) : sha_majority(x[1], x[2], x[3]);
            y += rol32(x[0], 5) + f + (u32)get(c, e, 4);
            x[1] = rol32(x[1], 30);
            u32 top = x[3];                       // <Y,X> = ROL(Y:X, 32)
            x[3] = x[2]; x[2] = x[1]; x[1] = x[0]; x[0] = y; y = top;
        }
        r = V128{};
        for (int e = 0; e < 4; e++) put(r, e, 4, x[e]);
        break;
    }
    case V_SHA1H: r = V128{}; put(r, 0, 4, rol32((u32)get(a, 0, 4), 30)); break;
    case V_SHA1SU0: {
        V128 t;
        put(t, 0, 8, get(a, 1, 8));
        put(t, 1, 8, get(b, 0, 8));
        for (int e = 0; e < 2; e++) put(r, e, 8, get(t, e, 8) ^ get(a, e, 8) ^ get(c, e, 8));
        break;
    }
    case V_SHA1SU1: {
        u32 t[4];
        for (int e = 0; e < 4; e++) t[e] = (u32)get(a, e, 4) ^ (e < 3 ? (u32)get(b, e + 1, 4) : 0);
        for (int e = 0; e < 3; e++) put(r, e, 4, rol32(t[e], 1));
        put(r, 3, 4, rol32(t[3], 1) ^ rol32(t[0], 2));
        break;
    }
    case V_SHA256H: case V_SHA256H2: {
        // SHA256H: X = Qd, Y = Qn -> X;  SHA256H2: X = Qn, Y = Qd -> Y
        u32 x[4], y[4];
        const V128& xs = op == V_SHA256H ? a : b;
        const V128& ys = op == V_SHA256H ? b : a;
        for (int e = 0; e < 4; e++) { x[e] = (u32)get(xs, e, 4); y[e] = (u32)get(ys, e, 4); }
        for (int e = 0; e < 4; e++) {
            u32 chs = sha_choose(y[0], y[1], y[2]);
            u32 maj = sha_majority(x[0], x[1], x[2]);
            u32 s1 = ror32(y[0], 6) ^ ror32(y[0], 11) ^ ror32(y[0], 25);
            u32 s0 = ror32(x[0], 2) ^ ror32(x[0], 13) ^ ror32(x[0], 22);
            u32 tt = y[3] + s1 + chs + (u32)get(c, e, 4);
            x[3] += tt;
            y[3] = tt + s0 + maj;
            u32 ytop = y[3], xtop = x[3];          // <Y,X> = ROL(Y:X, 32)
            y[3] = y[2]; y[2] = y[1]; y[1] = y[0]; y[0] = xtop;
            x[3] = x[2]; x[2] = x[1]; x[1] = x[0]; x[0] = ytop;
        }
        const u32* res = op == V_SHA256H ? x : y;
        for (int e = 0; e < 4; e++) put(r, e, 4, res[e]);
        break;
    }
    case V_SHA256SU0: {
        u32 t[4] = {(u32)get(a, 1, 4), (u32)get(a, 2, 4), (u32)get(a, 3, 4), (u32)get(b, 0, 4)};
        for (int e = 0; e < 4; e++)
            put(r, e, 4, (ror32(t[e], 7) ^ ror32(t[e], 18) ^ (t[e] >> 3)) + (u32)get(a, e, 4));
        break;
    }
    case V_SHA256SU1: {
        u32 t0[4] = {(u32)get(b, 1, 4), (u32)get(b, 2, 4), (u32)get(b, 3, 4), (u32)get(c, 0, 4)};
        u32 res[4];
        for (int e = 0; e < 4; e++) {
            u32 x = e < 2 ? (u32)get(c, e + 2, 4) : res[e - 2];
            res[e] = (ror32(x, 17) ^ ror32(x, 19) ^ (x >> 10)) + (u32)get(a, e, 4) + t0[e];
        }
        for (int e = 0; e < 4; e++) put(r, e, 4, res[e]);
        break;
    }
    default:
        fatal("vec_ref: unimplemented vector op %s", vec_op_name((u16)op));
    }
    out = r;
}

}  // namespace xef
