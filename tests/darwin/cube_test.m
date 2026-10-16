#import <Metal/Metal.h>
#import <Foundation/Foundation.h>

struct Vertex {
  float position[4];
  float color[4];
};

struct Uniforms {
  float modelViewProjectionMatrix[16];
};

static const struct Vertex cubeVertices[] = {
  { { -1,  1,  1, 1 }, { 0, 1, 1, 1 } },
  { { -1, -1,  1, 1 }, { 0, 0, 1, 1 } },
  { {  1, -1,  1, 1 }, { 1, 0, 1, 1 } },
  { {  1,  1,  1, 1 }, { 1, 1, 1, 1 } },
  { { -1,  1, -1, 1 }, { 0, 1, 0, 1 } },
  { { -1, -1, -1, 1 }, { 0, 0, 0, 1 } },
  { {  1, -1, -1, 1 }, { 1, 0, 0, 1 } },
  { {  1,  1, -1, 1 }, { 1, 1, 0, 1 } }
};

static const uint16_t cubeIndices[] = {
  3, 2, 6, 6, 7, 3,
  4, 5, 1, 1, 0, 4,
  4, 0, 3, 3, 7, 4,
  1, 5, 6, 6, 2, 1,
  0, 1, 2, 2, 3, 0,
  7, 6, 5, 5, 4, 7,
};

int main(int argc, char** argv) {
  @autoreleasepool {
    id<MTLDevice> d = MTLCreateSystemDefaultDevice();
    if (!d) {
      NSLog(@"FAIL: no Metal device");
      return 1;
    }
    NSLog(@"Device: %@", d.name);

    NSString *metallibPath = @"tests/darwin/cube_shaders.metallib";
    if (argc > 1) metallibPath = [NSString stringWithUTF8String:argv[1]];

    NSError *err = nil;
    id<MTLLibrary> lib = [d newLibraryWithFile:metallibPath error:&err];
    if (!lib) {
      NSLog(@"FAIL: newLibraryWithFile: %@", err);
      return 2;
    }

    id<MTLFunction> vf = [lib newFunctionWithName:@"vertex_project"];
    id<MTLFunction> ff = [lib newFunctionWithName:@"fragment_flatcolor"];
    if (!vf || !ff) {
      NSLog(@"FAIL: functions not found in cube_shaders.metallib");
      return 3;
    }

    MTLRenderPipelineDescriptor *pdesc = [[MTLRenderPipelineDescriptor alloc] init];
    pdesc.vertexFunction = vf;
    pdesc.fragmentFunction = ff;
    pdesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    pdesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

    id<MTLRenderPipelineState> pso = [d newRenderPipelineStateWithDescriptor:pdesc error:&err];
    if (!pso) {
      NSLog(@"FAIL: newRenderPipelineStateWithDescriptor: %@", err);
      return 4;
    }

    MTLDepthStencilDescriptor *dsDesc = [[MTLDepthStencilDescriptor alloc] init];
    dsDesc.depthCompareFunction = MTLCompareFunctionLess;
    dsDesc.depthWriteEnabled = YES;
    id<MTLDepthStencilState> dss = [d newDepthStencilStateWithDescriptor:dsDesc];

    MTLTextureDescriptor *cdesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                     width:256 height:256 mipmapped:NO];
    cdesc.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> colorTex = [d newTextureWithDescriptor:cdesc];

    MTLTextureDescriptor *ddesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                                                     width:256 height:256 mipmapped:NO];
    ddesc.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> depthTex = [d newTextureWithDescriptor:ddesc];

    id<MTLBuffer> vbuf = [d newBufferWithBytes:cubeVertices length:sizeof(cubeVertices) options:MTLResourceStorageModeShared];
    id<MTLBuffer> ibuf = [d newBufferWithBytes:cubeIndices length:sizeof(cubeIndices) options:MTLResourceStorageModeShared];

    struct Uniforms uniforms;
    /* Identity matrix */
    memset(&uniforms, 0, sizeof(uniforms));
    uniforms.modelViewProjectionMatrix[0]  = 0.5f;
    uniforms.modelViewProjectionMatrix[5]  = 0.5f;
    uniforms.modelViewProjectionMatrix[10] = 0.5f;
    uniforms.modelViewProjectionMatrix[15] = 1.0f;

    id<MTLBuffer> ubuf = [d newBufferWithBytes:&uniforms length:sizeof(uniforms) options:MTLResourceStorageModeShared];

    id<MTLCommandQueue> queue = [d newCommandQueue];
    id<MTLCommandBuffer> cb = [queue commandBuffer];

    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = colorTex;
    rp.colorAttachments[0].loadAction = MTLLoadActionClear;
    rp.colorAttachments[0].clearColor = MTLClearColorMake(0.1, 0.2, 0.3, 1.0);
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;

    rp.depthAttachment.texture = depthTex;
    rp.depthAttachment.loadAction = MTLLoadActionClear;
    rp.depthAttachment.clearDepth = 1.0;
    rp.depthAttachment.storeAction = MTLStoreActionStore;

    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
    [enc setRenderPipelineState:pso];
    [enc setDepthStencilState:dss];
    [enc setVertexBuffer:vbuf offset:0 atIndex:0];
    [enc setVertexBuffer:ubuf offset:0 atIndex:1];

    [enc drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                    indexCount:sizeof(cubeIndices) / sizeof(uint16_t)
                     indexType:MTLIndexTypeUInt16
                   indexBuffer:ibuf
             indexBufferOffset:0];

    [enc endEncoding];
    [cb commit];
    [cb waitUntilCompleted];

    /* Verify rendering produced pixels */
    uint32_t pixels[256 * 256];
    [colorTex getBytes:pixels bytesPerRow:256 * 4 fromRegion:MTLRegionMake2D(0, 0, 256, 256) mipmapLevel:0];

    int nonClearPixels = 0;
    uint32_t clearPixel = pixels[0]; /* corner pixel */
    for (int i = 0; i < 256 * 256; i++) {
      if (pixels[i] != clearPixel) nonClearPixels++;
    }

    NSLog(@"Rendered 3D indexed cube: nonClearPixels=%d, clearPixel=0x%08x, pixels[32768]=0x%08x",
          nonClearPixels, clearPixel, pixels[128 * 256 + 128]);
    if (nonClearPixels == 0) {
      NSLog(@"FAIL: cube did not rasterize any pixels");
      return 5;
    }

    [dsDesc release];
    [dss release];
    [pdesc release];
    [pso release];
    [vf release];
    [ff release];
    [lib release];
    [colorTex release];
    [depthTex release];
    [vbuf release];
    [ibuf release];
    [ubuf release];
    [queue release];
    [d release];

    puts("PASS cube_test");
    return 0;
  }
}
