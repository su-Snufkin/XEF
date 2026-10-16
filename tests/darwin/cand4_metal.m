#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Foundation/Foundation.h>

static NSString* src =
    @"#include <metal_stdlib>\n"
    @"using namespace metal;\n"
    @"vertex float4 vs(uint i[[vertex_id]]){float2 p[3]={float2(-.5,-.5),float2(.5,-.5),float2(0,.5)};return float4(p[i],0,1);}\n"
    @"fragment float4 fs(){return float4(1,0,0,1);}\n";

int main(void) {
  @autoreleasepool {
    id<MTLDevice> d = MTLCreateSystemDefaultDevice();
    if (!d) {
      puts("no device");
      return 2;
    }
    NSLog(@"device %@", d.name);
    NSError *e = nil;
    id<MTLLibrary> lib = [d newLibraryWithSource:src options:nil error:&e];
    if (!lib) {
      NSLog(@"lib err %@", e);
      return 3;
    }
    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
    pd.vertexFunction = [lib newFunctionWithName:@"vs"];
    pd.fragmentFunction = [lib newFunctionWithName:@"fs"];
    pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    id<MTLRenderPipelineState> ps = [d newRenderPipelineStateWithDescriptor:pd error:&e];
    id<MTLCommandQueue> q = [d newCommandQueue];
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                  width:256
                                                                                 height:256
                                                                              mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget;
    td.storageMode = MTLStorageModePrivate;
    id<MTLTexture> t = [d newTextureWithDescriptor:td];
    int n = 0;
    for (; n < 300; n++) {
      MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
      rp.colorAttachments[0].texture = t;
      rp.colorAttachments[0].loadAction = MTLLoadActionClear;
      rp.colorAttachments[0].storeAction = MTLStoreActionStore;
      id<MTLCommandBuffer> cb = [q commandBuffer];
      id<MTLRenderCommandEncoder> en = [cb renderCommandEncoderWithDescriptor:rp];
      [en setRenderPipelineState:ps];
      [en drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
      [en endEncoding];
      [cb commit];
      [cb waitUntilCompleted];
    }
    printf("frames=%d (offscreen, no window)\n", n);
    return 0;
  }
}
