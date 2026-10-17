#!/bin/bash
# Metal regression test suite
cd "$(dirname "$0")/../.." || exit 1
X=build/xef-osx
[ -x $X ] && [ -f tests/darwin/cand4_metal ] || { echo "FAIL: missing $X or tests/darwin/cand4_metal"; exit 1; }

OUT1=$(timeout 30 $X -L darwin-rootfs tests/darwin/cand4_metal 2>&1)
RC1=$?

if [ $RC1 -ne 0 ] || ! echo "$OUT1" | grep -q "frames=300"; then
  echo "FAIL metal_test (cand4_metal): rc=$RC1"
  echo "$OUT1"
  exit 1
fi

if [ -f tests/darwin/metallib_test ] && [ -f tests/darwin/AAPLShaders.metallib ]; then
  OUT2=$(timeout 15 $X -L darwin-rootfs tests/darwin/metallib_test tests/darwin/AAPLShaders.metallib 2>&1)
  RC2=$?
  if [ $RC2 -ne 0 ] || ! echo "$OUT2" | grep -q "PASS metallib_test"; then
    echo "FAIL metal_test (metallib_test): rc=$RC2"
    echo "$OUT2"
    exit 1
  fi
fi

if [ -f tests/darwin/metalkit_test ]; then
  OUT3=$(timeout 15 $X -L darwin-rootfs tests/darwin/metalkit_test 2>&1)
  RC3=$?
  if [ $RC3 -ne 0 ] || ! echo "$OUT3" | grep -q "PASS metalkit_test"; then
    echo "FAIL metal_test (metalkit_test): rc=$RC3"
    echo "$OUT3"
    exit 1
  fi
fi

if [ -f tests/darwin/compute_test ] && [ -f tests/darwin/add.metallib ]; then
  OUT4=$(timeout 15 $X -L darwin-rootfs tests/darwin/compute_test tests/darwin/add.metallib 2>&1)
  RC4=$?
  if [ $RC4 -ne 0 ] || ! echo "$OUT4" | grep -q "PASS compute_test"; then
    echo "FAIL metal_test (compute_test): rc=$RC4"
    echo "$OUT4"
    exit 1
  fi
fi

if [ -f tests/darwin/cube_test ] && [ -f tests/darwin/cube_shaders.metallib ]; then
  OUT5=$(timeout 15 $X -L darwin-rootfs tests/darwin/cube_test tests/darwin/cube_shaders.metallib 2>&1)
  RC5=$?
  if [ $RC5 -ne 0 ] || ! echo "$OUT5" | grep -q "PASS cube_test"; then
    echo "FAIL metal_test (cube_test): rc=$RC5"
    echo "$OUT5"
    exit 1
  fi
fi

if [ -f tests/darwin/heap_event_test ]; then
  OUT6=$(timeout 15 $X -L darwin-rootfs tests/darwin/heap_event_test 2>&1)
  RC6=$?
  if [ $RC6 -ne 0 ] || ! echo "$OUT6" | grep -q "PASS heap_event_test"; then
    echo "FAIL metal_test (heap_event_test): rc=$RC6"
    echo "$OUT6"
    exit 1
  fi
fi

# SDL3 GPU samples (github.com/TheSpydog/SDL_gpu_examples built on a Mac, installed with their Content/ and
# libSDL3.0.dylib under darwin-rootfs): every sample must reach its 30th presented frame
SGE=darwin-rootfs/Applications/SDL_gpu_examples
if [ -x $SGE/SDL_gpu_examples ]; then
  SHOT=$(mktemp -d)
  for n in BasicTriangle BasicStencil BasicCompute Blit2DArray BlitCube Bloom Clear3DSlice ComputeSampler ComputeSpriteBatch \
           CopyAndReadback Cubemap CustomSampling DepthSampler DrawIndirect GenerateMipmaps InstancedIndexed PullSpriteBatch \
           Texture2DArray TexturedAnimatedQuad TextureTypeTest ToneMapping TriangleMSAA; do
    OUT7=$(cd $SGE && XEF_MTL_SHOT=$SHOT/$n.ppm XEF_MTL_SHOT_FRAME=30 XEF_MTL_SHOT_EXIT=1 SDL_AUDIODRIVER=dummy \
           timeout 30 ../../../$X -L ../.. ./SDL_gpu_examples -name $n 2>&1)
    if [ ! -s $SHOT/$n.ppm ] || echo "$OUT7" | grep -qi "pipeline creation failed\|compilation failed\|fatal signal"; then
      echo "FAIL metal_test (SDL_gpu_examples $n)"
      echo "$OUT7" | tail -20
      rm -rf $SHOT
      exit 1
    fi
  done
  rm -rf $SHOT
fi

echo "PASS metal_test"
exit 0

