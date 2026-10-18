// Texture atomics: 256 threads hammer a 4x4 R32Uint texture with atomic_fetch_add/max and a compare-exchange
// loop, then the texels are read back.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
static NSString *src = @"#include <metal_stdlib>\nusing namespace metal;\n"
  "kernel void k(texture2d<uint, access::read_write> t [[texture(0)]], uint i [[thread_position_in_grid]]) {\n"
  "  t.atomic_fetch_add(uint2(i % 4, 0), 1u);\n"
  "  t.atomic_fetch_max(uint2(i % 4, 1), i);\n"
  "  uint4 e = t.read(uint2(0, 2));\n"
  "  while (!t.atomic_compare_exchange_weak(uint2(0, 2), &e, e + 2u)) {}\n"
  "  t.atomic_fetch_or(uint2(1, 2), 1u << (i % 32));\n"
  "}\n";
int main(void) { @autoreleasepool {
  id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
  MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR32Uint width:4 height:4 mipmapped:NO];
  td.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageShaderAtomic;
  td.storageMode = MTLStorageModeShared;
  id<MTLTexture> tex = [dev newTextureWithDescriptor:td];
  uint32_t zero[16] = {0};
  [tex replaceRegion:MTLRegionMake2D(0, 0, 4, 4) mipmapLevel:0 withBytes:zero bytesPerRow:16];
  NSError *err = nil;
  id<MTLLibrary> lib = [dev newLibraryWithSource:src options:nil error:&err];
  if (!lib) { NSLog(@"FAIL compile %@", err); return 1; }
  id<MTLComputePipelineState> ps = [dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"k"] error:&err];
  if (!ps) { NSLog(@"FAIL pipeline %@", err); return 2; }
  id<MTLCommandQueue> q = [dev newCommandQueue];
  id<MTLCommandBuffer> cb = [q commandBuffer];
  id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
  [e setComputePipelineState:ps]; [e setTexture:tex atIndex:0];
  [e dispatchThreads:MTLSizeMake(256, 1, 1) threadsPerThreadgroup:MTLSizeMake(64, 1, 1)];
  [e endEncoding]; [cb commit]; [cb waitUntilCompleted];
  uint32_t r[16];
  [tex getBytes:r bytesPerRow:16 fromRegion:MTLRegionMake2D(0, 0, 4, 4) mipmapLevel:0];
  printf("add %u %u %u %u  max %u %u %u %u  cas %u  or %08x\n", r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]);
  BOOL ok = r[0] == 64 && r[1] == 64 && r[2] == 64 && r[3] == 64 && r[4] == 252 && r[5] == 253 && r[6] == 254 && r[7] == 255 &&
            r[8] == 512 && r[9] == 0xffffffffu;
  NSLog(ok ? @"PASS tex_atomic_test" : @"FAIL tex_atomic_test");
  return ok ? 0 : 3;
}}
