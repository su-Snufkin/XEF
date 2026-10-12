#!/bin/sh
# Builds every benchmark natively (x86-64) and for AArch64 (static), same flags.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
S=$ROOT/.tools/sysroot-aarch64
SRC=$ROOT/.tools/src
OUT=$ROOT/bench/bin
mkdir -p $OUT/native $OUT/aarch64
CFLAGS="-O2"
build() {  # name, sources..., extra
  name=$1; shift
  clang $CFLAGS -march=x86-64-v2 "$@" -lm -o $OUT/native/$name
  clang $CFLAGS --target=aarch64-linux-gnu --sysroot=$S -fuse-ld=lld -static "$@" -lm -o $OUT/aarch64/$name
}
for b in intloop fploop calls; do build $b $ROOT/bench/micro/$b.c; done
CM=$SRC/coremark
build coremark -I$CM -I$CM/posix -DPERFORMANCE_RUN=1 -DITERATIONS=60000 -DFLAGS_STR='"-O2"' \
  $CM/core_list_join.c $CM/core_main.c $CM/core_matrix.c $CM/core_state.c $CM/core_util.c $CM/posix/core_portme.c
Z=$SRC/zstd/lib
ZS="$Z/common/*.c $Z/compress/*.c $Z/decompress/*.c $SRC/zstd/programs/zstdcli.c $SRC/zstd/programs/fileio*.c \
    $SRC/zstd/programs/util.c $SRC/zstd/programs/timefn.c $SRC/zstd/programs/benchfn.c $SRC/zstd/programs/benchzstd.c \
    $SRC/zstd/programs/datagen.c $SRC/zstd/programs/dibio.c $SRC/zstd/programs/lorem.c $Z/dictBuilder/*.c"
build zstd -I$Z -I$Z/common -DZSTD_DISABLE_ASM -DZSTD_MULTITHREAD_DISABLE -DZSTD_LEGACY_SUPPORT=0 -DZSTD_NOBENCH=0 -DZSTD_NOTRACE $ZS $SRC/zstd/programs/zstdcli_trace.c
echo built
