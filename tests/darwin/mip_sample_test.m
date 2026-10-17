// Mipmapped texture uploads and explicit-LOD sampling: fills each level of an RGBA8 texture with a
// distinct color through replaceRegion and reads level 0..N-1 back through a compute kernel.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
static NSString *src = @"#include <metal_stdlib>\nusing namespace metal;\n"
  "kernel void probe(texture2d<float> t [[texture(0)]], device float4 *out [[buffer(0)]], uint i [[thread_position_in_grid]]) {\n"
  "  constexpr sampler s(mip_filter::nearest, mag_filter::nearest, min_filter::nearest);\n"
  "  out[i] = t.sample(s, float2(0.5, 0.5), level(float(i)));\n}\n";
int main(void) { @autoreleasepool {
  id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
  const int W = 64, L = 7;
  MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:W height:W mipmapped:YES];
  td.usage = MTLTextureUsageShaderRead;
  id<MTLTexture> tex = [dev newTextureWithDescriptor:td];
  if (tex.mipmapLevelCount != L) { NSLog(@"FAIL mip count %lu", (unsigned long)tex.mipmapLevelCount); return 1; }
  for (int l = 0; l < L; l++) {
    int w = W >> l; uint32_t *px = malloc(w * w * 4);
    for (int i = 0; i < w * w; i++) px[i] = 0xff000000u | (uint32_t)(l * 40) | ((uint32_t)(255 - l * 30) << 8);
    [tex replaceRegion:MTLRegionMake2D(0, 0, w, w) mipmapLevel:l withBytes:px bytesPerRow:w * 4];
    free(px);
  }
  NSError *err = nil;
  id<MTLLibrary> lib = [dev newLibraryWithSource:src options:nil error:&err];
  id<MTLComputePipelineState> ps = [dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"probe"] error:&err];
  if (!ps) { NSLog(@"FAIL pipeline %@", err); return 2; }
  id<MTLBuffer> out = [dev newBufferWithLength:16 * L options:MTLResourceStorageModeShared];
  id<MTLCommandQueue> q = [dev newCommandQueue];
  id<MTLCommandBuffer> cb = [q commandBuffer];
  id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
  [e setComputePipelineState:ps]; [e setTexture:tex atIndex:0]; [e setBuffer:out offset:0 atIndex:0];
  [e dispatchThreads:MTLSizeMake(L, 1, 1) threadsPerThreadgroup:MTLSizeMake(L, 1, 1)];
  [e endEncoding]; [cb commit]; [cb waitUntilCompleted];
  float *r = out.contents; int bad = 0;
  for (int l = 0; l < L; l++) {
    float er = l * 40 / 255.0f, eg = (255 - l * 30) / 255.0f;
    printf("level %d: %.3f %.3f %.3f %.3f (want %.3f %.3f)\n", l, r[4*l], r[4*l+1], r[4*l+2], r[4*l+3], er, eg);
    if (fabsf(r[4*l] - er) > 0.01f || fabsf(r[4*l+1] - eg) > 0.01f) bad++;
  }
  if (bad) { NSLog(@"FAIL mip_sample_test"); return 3; }
  NSLog(@"PASS mip_sample_test");
  return 0;
}}
