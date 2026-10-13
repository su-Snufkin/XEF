# XEF benchmarks

Each benchmark is built from the same source with the same flags (-O2) for x86-64 (native) and AArch64 (static). Times are best-of-N wall clock. "XEF vs native" is native time / XEF time (100% = native speed). Newest results first. Regenerate with `bench/build.sh && bench/run.py`.

## 2026-10-13 — 13th Gen Intel(R) Core(TM) i7-13620H (commit 592b686)

| benchmark | native x86-64 [s] | XEF [s] | qemu-aarch64 [s] | XEF vs native | XEF speedup vs qemu |
|---|---:|---:|---:|---:|---:|
| coremark — CoreMark (200k iterations) | 6.514 | 8.342 | — | 78% | — |
| intloop — integer loops (sieve, hash, counting) | 0.579 | 0.516 | — | 112% | — |
| fploop — FP loops (matmul, n-body, mandelbrot) | 0.208 | 0.252 | — | 83% | — |
| calls — calls + indirect branches (fib, fn pointers, interpreter) | 0.408 | 0.555 | — | 74% | — |
| simd — auto-vectorized NEON loops (saxpy, dot, u8 blend, s16 saturate, SAD, clamp, cvt) | 0.142 | 0.230 | — | 62% | — |
| zstd-c — zstd -6 compress 48 MB text | 0.537 | 0.766 | — | 70% | — |
| zstd-d — zstd decompress 48 MB text | 0.044 | 0.079 | — | 55% | — |

## 2026-10-13 — 13th Gen Intel(R) Core(TM) i7-13620H (commit d811a25)

| benchmark | native x86-64 [s] | XEF [s] | qemu-aarch64 [s] | XEF vs native | XEF speedup vs qemu |
|---|---:|---:|---:|---:|---:|
| coremark — CoreMark (200k iterations) | 6.724 | 8.346 | — | 81% | — |
| intloop — integer loops (sieve, hash, counting) | 0.580 | 0.516 | — | 112% | — |
| fploop — FP loops (matmul, n-body, mandelbrot) | 0.208 | 0.251 | — | 83% | — |
| calls — calls + indirect branches (fib, fn pointers, interpreter) | 0.407 | 0.556 | — | 73% | — |
| simd — auto-vectorized NEON loops (saxpy, dot, u8 blend, s16 saturate, SAD, clamp, cvt) | 0.141 | 0.232 | — | 61% | — |
| zstd-c — zstd -6 compress 48 MB text | 0.538 | 0.764 | — | 70% | — |
| zstd-d — zstd decompress 48 MB text | 0.043 | 0.077 | — | 56% | — |

## 2026-10-13 — 13th Gen Intel(R) Core(TM) i7-13620H (commit acd0d64)

| benchmark | native x86-64 [s] | XEF [s] | qemu-aarch64 [s] | XEF vs native | XEF speedup vs qemu |
|---|---:|---:|---:|---:|---:|
| coremark — CoreMark (200k iterations) | 6.509 | 8.347 | — | 78% | — |
| intloop — integer loops (sieve, hash, counting) | 0.579 | 0.517 | — | 112% | — |
| fploop — FP loops (matmul, n-body, mandelbrot) | 0.207 | 0.253 | — | 82% | — |
| calls — calls + indirect branches (fib, fn pointers, interpreter) | 0.407 | 0.550 | — | 74% | — |
| simd — auto-vectorized NEON loops (saxpy, dot, u8 blend, s16 saturate, SAD, clamp, cvt) | 0.142 | 0.231 | — | 61% | — |
| zstd-c — zstd -6 compress 48 MB text | 0.540 | 0.807 | — | 67% | — |
| zstd-d — zstd decompress 48 MB text | 0.044 | 0.079 | — | 55% | — |

## 2026-10-13 — 13th Gen Intel(R) Core(TM) i7-13620H (commit 376a522)

| benchmark | native x86-64 [s] | XEF [s] | qemu-aarch64 [s] | XEF vs native | XEF speedup vs qemu |
|---|---:|---:|---:|---:|---:|
| coremark — CoreMark (200k iterations) | 6.868 | 8.361 | — | 82% | — |
| intloop — integer loops (sieve, hash, counting) | 0.579 | 0.517 | — | 112% | — |
| fploop — FP loops (matmul, n-body, mandelbrot) | 0.208 | 0.252 | — | 82% | — |
| calls — calls + indirect branches (fib, fn pointers, interpreter) | 0.408 | 0.553 | — | 74% | — |
| simd — auto-vectorized NEON loops (saxpy, dot, u8 blend, s16 saturate, SAD, clamp, cvt) | 0.142 | 0.231 | — | 61% | — |
| zstd-c — zstd -6 compress 48 MB text | 0.538 | 0.773 | — | 70% | — |
| zstd-d — zstd decompress 48 MB text | 0.044 | 0.077 | — | 57% | — |

## 2026-10-13 — 13th Gen Intel(R) Core(TM) i7-13620H (commit 60a1690)

| benchmark | native x86-64 [s] | XEF [s] | qemu-aarch64 [s] | XEF vs native | XEF speedup vs qemu |
|---|---:|---:|---:|---:|---:|
| coremark — CoreMark (200k iterations) | 6.618 | 8.378 | — | 79% | — |
| intloop — integer loops (sieve, hash, counting) | 0.579 | 0.516 | — | 112% | — |
| fploop — FP loops (matmul, n-body, mandelbrot) | 0.208 | 0.252 | — | 82% | — |
| calls — calls + indirect branches (fib, fn pointers, interpreter) | 0.407 | 0.597 | — | 68% | — |
| simd — auto-vectorized NEON loops (saxpy, dot, u8 blend, s16 saturate, SAD, clamp, cvt) | 0.141 | 0.229 | — | 62% | — |
| zstd-c — zstd -6 compress 48 MB text | 0.537 | 0.829 | — | 65% | — |
| zstd-d — zstd decompress 48 MB text | 0.043 | 0.076 | — | 57% | — |

## 2026-10-13 — 13th Gen Intel(R) Core(TM) i7-13620H (commit 56993b2)

| benchmark | native x86-64 [s] | XEF [s] | qemu-aarch64 [s] | XEF vs native | XEF speedup vs qemu |
|---|---:|---:|---:|---:|---:|
| coremark — CoreMark (200k iterations) | 6.510 | 8.350 | — | 78% | — |
| intloop — integer loops (sieve, hash, counting) | 0.579 | 0.517 | — | 112% | — |
| fploop — FP loops (matmul, n-body, mandelbrot) | 0.208 | 0.253 | — | 82% | — |
| calls — calls + indirect branches (fib, fn pointers, interpreter) | 0.408 | 0.597 | — | 68% | — |
| simd — auto-vectorized NEON loops (saxpy, dot, u8 blend, s16 saturate, SAD, clamp, cvt) | 0.142 | 0.232 | — | 61% | — |
| zstd-c — zstd -6 compress 48 MB text | 0.537 | 0.792 | — | 68% | — |
| zstd-d — zstd decompress 48 MB text | 0.045 | 0.077 | — | 58% | — |

## 2026-10-13 — 13th Gen Intel(R) Core(TM) i7-13620H (commit 75a6287) — byte-mul-shift-native

| benchmark | native x86-64 [s] | XEF [s] | qemu-aarch64 [s] | XEF vs native | XEF speedup vs qemu |
|---|---:|---:|---:|---:|---:|
| coremark — CoreMark (200k iterations) | 6.722 | 8.352 | — | 80% | — |
| intloop — integer loops (sieve, hash, counting) | 0.589 | 0.524 | — | 112% | — |
| fploop — FP loops (matmul, n-body, mandelbrot) | 0.209 | 0.253 | — | 83% | — |
| calls — calls + indirect branches (fib, fn pointers, interpreter) | 0.408 | 0.573 | — | 71% | — |
| simd — auto-vectorized NEON loops (saxpy, dot, u8 blend, s16 saturate, SAD, clamp, cvt) | 0.142 | 0.232 | — | 61% | — |
| zstd-c — zstd -6 compress 48 MB text | 0.540 | 0.801 | — | 67% | — |
| zstd-d — zstd decompress 48 MB text | 0.043 | 0.079 | — | 55% | — |

## 2026-10-13 — 13th Gen Intel(R) Core(TM) i7-13620H (commit 75a6287)

| benchmark | native x86-64 [s] | XEF [s] | qemu-aarch64 [s] | XEF vs native | XEF speedup vs qemu |
|---|---:|---:|---:|---:|---:|
| simd — auto-vectorized NEON loops (saxpy, dot, u8 blend, s16 saturate, SAD, clamp, cvt) | 0.142 | 0.230 | — | 62% | — |

## 2026-10-13 — 13th Gen Intel(R) Core(TM) i7-13620H (commit 75a6287)

| benchmark | native x86-64 [s] | XEF [s] | qemu-aarch64 [s] | XEF vs native | XEF speedup vs qemu |
|---|---:|---:|---:|---:|---:|
| coremark — CoreMark (200k iterations) | 6.656 | 8.358 | — | 80% | — |
| intloop — integer loops (sieve, hash, counting) | 0.587 | 0.525 | — | 112% | — |
| fploop — FP loops (matmul, n-body, mandelbrot) | 0.208 | 0.253 | — | 82% | — |
| calls — calls + indirect branches (fib, fn pointers, interpreter) | 0.408 | 0.555 | — | 73% | — |
| simd — auto-vectorized NEON loops (saxpy, dot, u8 blend, s16 saturate, SAD, clamp, cvt) | 0.142 | 0.230 | — | 62% | — |
| zstd-c — zstd -6 compress 48 MB text | 0.540 | 0.824 | — | 66% | — |
| zstd-d — zstd decompress 48 MB text | 0.044 | 0.078 | — | 56% | — |

## 2026-10-13 — 13th Gen Intel(R) Core(TM) i7-13620H (commit e9aa5f4) — flags at consumers, PRFM, BR flags dead, regmap per compiler, fall-through chains, crypto/CRC native

| benchmark | native x86-64 [s] | XEF [s] | qemu-aarch64 [s] | XEF vs native | XEF speedup vs qemu |
|---|---:|---:|---:|---:|---:|
| coremark — CoreMark (200k iterations) | 6.541 | 8.362 | — | 78% | — |
| intloop — integer loops (sieve, hash, counting) | 0.580 | 0.516 | — | 112% | — |
| fploop — FP loops (matmul, n-body, mandelbrot) | 0.207 | 0.252 | — | 82% | — |
| calls — calls + indirect branches (fib, fn pointers, interpreter) | 0.408 | 0.553 | — | 74% | — |
| simd — auto-vectorized NEON loops (saxpy, dot, u8 blend, s16 saturate, SAD, clamp, cvt) | 0.141 | 0.230 | — | 61% | — |
| zstd-c — zstd -6 compress 48 MB text | 0.537 | 0.781 | — | 69% | — |
| zstd-d — zstd decompress 48 MB text | 0.043 | 0.076 | — | 57% | — |

## 2026-10-13 — 13th Gen Intel(R) Core(TM) i7-13620H (commit 161053f) — optimized

| benchmark | native x86-64 [s] | XEF [s] | qemu-aarch64 [s] | XEF vs native | XEF speedup vs qemu |
|---|---:|---:|---:|---:|---:|
| coremark — CoreMark (200k iterations) | 6.512 | 9.741 | — | 67% | — |
| intloop — integer loops (sieve, hash, counting) | 0.590 | 0.522 | — | 113% | — |
| fploop — FP loops (matmul, n-body, mandelbrot) | 0.208 | 0.152 | — | 137%* | — |
| calls — calls + indirect branches (fib, fn pointers, interpreter) | 0.407 | 0.938 | — | 43% | — |
| zstd-c — zstd -6 compress 48 MB text | 0.541 | 1.131 | — | 48% | — |
| zstd-d — zstd decompress 48 MB text | 0.044 | 0.101 | — | 43% | — |

\* invalid: the tier-2 stale-XMM bug of 452f9a4 made the mandelbrot loop exit early (wrong result); fixed in b2cfb22.

## 2026-10-12 — Intel(R) Xeon(R) Processor @ 2.80GHz (commit 6b132b7) — flags dead at calls, DSE, spill fixes

| benchmark | native x86-64 [s] | XEF [s] | qemu-aarch64 [s] | XEF vs native | XEF speedup vs qemu |
|---|---:|---:|---:|---:|---:|
| coremark — CoreMark (200k iterations) | 8.837 | 16.701 | — | 53% | — |
| intloop — integer loops (sieve, hash, counting) | 0.850 | 0.740 | — | 115% | — |
| fploop — FP loops (matmul, n-body, mandelbrot) | 0.341 | 0.610 | — | 56% | — |
| calls — calls + indirect branches (fib, fn pointers, interpreter) | 0.626 | 1.266 | — | 49% | — |
| zstd-c — zstd -6 compress 48 MB text | 0.919 | 2.805 | — | 33% | — |
| zstd-d — zstd decompress 48 MB text | 0.075 | 0.204 | — | 37% | — |

## 2026-10-12 — 13th Gen Intel(R) Core(TM) i7-13620H (commit 9c10fe1) — tier 2 regions (regional regmap), flag remat

| benchmark | native x86-64 [s] | XEF [s] | qemu-aarch64 [s] | XEF vs native | XEF speedup vs qemu |
|---|---:|---:|---:|---:|---:|
| coremark — CoreMark (200k iterations) | 4.717 | 11.822 | — | 40% | — |
| intloop — integer loops (sieve, hash, counting) | 0.507 | 0.487 | — | 104% | — |
| fploop — FP loops (matmul, n-body, mandelbrot) | 0.188 | 0.411 | — | 46% | — |
| calls — calls + indirect branches (fib, fn pointers, interpreter) | 0.391 | 1.619 | — | 24% | — |
| zstd-c — zstd -6 compress 48 MB text | 0.546 | 1.309 | — | 42% | — |
| zstd-d — zstd decompress 48 MB text | 0.047 | 0.117 | — | 40% | — |

## 2026-10-12 — 13th Gen Intel(R) Core(TM) i7-13620H (commit 69bce9f) — milestone 2 baseline: tier-1 JIT, static regmap, block linking, IBTC, native RSB

| benchmark | native x86-64 [s] | XEF [s] | qemu-aarch64 [s] | XEF vs native | XEF speedup vs qemu |
|---|---:|---:|---:|---:|---:|
| coremark — CoreMark (200k iterations) | 5.033 | 23.212 | 28.722 | 22% | 1.2× |
| intloop — integer loops (sieve, hash, counting) | 0.496 | 0.576 | 0.876 | 86% | 1.5× |
| fploop — FP loops (matmul, n-body, mandelbrot) | 0.192 | 0.500 | 5.739 | 38% | 11.5× |
| calls — calls + indirect branches (fib, fn pointers, interpreter) | 0.398 | 1.798 | 8.754 | 22% | 4.9× |
| zstd-c — zstd -6 compress 48 MB text | 0.656 | 2.539 | 4.831 | 26% | 1.9× |
| zstd-d — zstd decompress 48 MB text | 0.056 | 0.167 | 0.295 | 34% | 1.8× |

