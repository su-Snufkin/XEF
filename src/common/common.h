// XEF — common definitions.
#pragma once
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace xef {

using u8 = uint8_t;
using u16 = uint16_t;
using u32 = uint32_t;
using u64 = uint64_t;
using i8 = int8_t;
using i16 = int16_t;
using i32 = int32_t;
using i64 = int64_t;
using GuestAddr = u64;

#define XEF_LIKELY(x) __builtin_expect(!!(x), 1)
#define XEF_UNLIKELY(x) __builtin_expect(!!(x), 0)
#define XEF_NOINLINE __attribute__((noinline))
#define XEF_ALWAYS_INLINE inline __attribute__((always_inline))
#define XEF_COLD __attribute__((cold, noinline))

[[noreturn]] void fatal(const char* fmt, ...) __attribute__((format(printf, 1, 2)));
void log_msg(const char* fmt, ...) __attribute__((format(printf, 1, 2)));

extern int g_verbose;  // 0 = quiet, 1 = info, 2 = debug, 3 = trace
#define XEF_LOG(level, ...)                         \
    do {                                            \
        if (XEF_UNLIKELY(::xef::g_verbose >= (level))) ::xef::log_msg(__VA_ARGS__); \
    } while (0)

#define XEF_ASSERT(c)                                                            \
    do {                                                                         \
        if (XEF_UNLIKELY(!(c))) ::xef::fatal("assertion failed: %s (%s:%d)", #c, __FILE__, __LINE__); \
    } while (0)

template <typename T>
constexpr T align_up(T v, T a) { return (v + a - 1) & ~(a - 1); }
template <typename T>
constexpr T align_down(T v, T a) { return v & ~(a - 1); }

constexpr u64 bits(u32 v, int hi, int lo) { return (v >> lo) & ((1ull << (hi - lo + 1)) - 1); }
constexpr bool bit(u32 v, int b) { return (v >> b) & 1; }
constexpr i64 sext(u64 v, int width) { return (i64)(v << (64 - width)) >> (64 - width); }

}  // namespace xef
