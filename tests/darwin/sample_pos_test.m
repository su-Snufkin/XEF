// get_sample_position / get_num_samples in a 4x MSAA pass (resolved and read back).
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
static NSString *src = @"#include <metal_stdlib>\nusing namespace metal;\n"
  "vertex float4 v(uint i [[vertex_id]]) { return float4(i == 1 ? 3.0 : -1.0, i == 2 ? 3.0 : -1.0, 0, 1); }\n"
  "fragment float4 f() { float2 a = get_sample_position(1), b = get_sample_position(2); return float4(a, b.x, float(get_num_samples()) / 8.0); }\n";
int main(void) { @autoreleasepool {
  id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
  NSError *err = nil;
  id<MTLLibrary> lib = [dev newLibraryWithSource:src options:nil error:&err];
  if (!lib) { NSLog(@"FAIL compile %@", err); return 1; }
  MTLRenderPipelineDescriptor *pd = [[MTLRenderPipelineDescriptor alloc] init];
  pd.vertexFunction = [lib newFunctionWithName:@"v"]; pd.fragmentFunction = [lib newFunctionWithName:@"f"];
  pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA32Float; pd.rasterSampleCount = 4;
  id<MTLRenderPipelineState> ps = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
  if (!ps) { NSLog(@"FAIL pipeline %@", err); return 2; }
  MTLTextureDescriptor *md = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float width:4 height:4 mipmapped:NO];
  md.textureType = MTLTextureType2DMultisample; md.sampleCount = 4; md.usage = MTLTextureUsageRenderTarget; md.storageMode = MTLStorageModePrivate;
  id<MTLTexture> ms = [dev newTextureWithDescriptor:md];
  MTLTextureDescriptor *rd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float width:4 height:4 mipmapped:NO];
  rd.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead; rd.storageMode = MTLStorageModeShared;
  id<MTLTexture> res = [dev newTextureWithDescriptor:rd];
  MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
  rp.colorAttachments[0].texture = ms; rp.colorAttachments[0].resolveTexture = res;
  rp.colorAttachments[0].loadAction = MTLLoadActionClear; rp.colorAttachments[0].storeAction = MTLStoreActionMultisampleResolve;
  id<MTLCommandQueue> q = [dev newCommandQueue];
  id<MTLCommandBuffer> cb = [q commandBuffer];
  id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
  [e setRenderPipelineState:ps]; [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3]; [e endEncoding];
  [cb commit]; [cb waitUntilCompleted];
  float px[4];
  [res getBytes:px bytesPerRow:64 fromRegion:MTLRegionMake2D(1, 1, 1, 1) mipmapLevel:0];
  printf("%g %g %g %g\n", px[0], px[1], px[2], px[3]);
  BOOL ok = px[0] == 0.875f && px[1] == 0.375f && px[2] == 0.125f && px[3] == 0.5f;
  NSLog(ok ? @"PASS sample_pos_test" : @"FAIL sample_pos_test");
  return ok ? 0 : 3;
}}
