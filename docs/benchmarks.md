# XEF benchmarks

Each benchmark is built from the same source with the same flags (-O2) for x86-64 (native) and AArch64 (static). Times are best-of-N wall clock. "XEF vs native" is native time / XEF time (100% = native speed). Newest results first. Regenerate with `bench/build.sh && bench/run.py`.

## 2026-10-12 — 13th Gen Intel(R) Core(TM) i7-13620H (commit 69bce9f) — milestone 2 baseline: tier-1 JIT, static regmap, block linking, IBTC, native RSB

| benchmark | native x86-64 [s] | XEF [s] | qemu-aarch64 [s] | XEF vs native | XEF speedup vs qemu |
|---|---:|---:|---:|---:|---:|
| coremark — CoreMark (200k iterations) | 5.033 | 23.212 | 28.722 | 22% | 1.2× |
| intloop — integer loops (sieve, hash, counting) | 0.496 | 0.576 | 0.876 | 86% | 1.5× |
| fploop — FP loops (matmul, n-body, mandelbrot) | 0.192 | 0.500 | 5.739 | 38% | 11.5× |
| calls — calls + indirect branches (fib, fn pointers, interpreter) | 0.398 | 1.798 | 8.754 | 22% | 4.9× |
| zstd-c — zstd -6 compress 48 MB text | 0.656 | 2.539 | 4.831 | 26% | 1.9× |
| zstd-d — zstd decompress 48 MB text | 0.056 | 0.167 | 0.295 | 34% | 1.8× |

