#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <Foundation/Foundation.h>

@interface DummyDelegate : NSObject <MTKViewDelegate>
@property (nonatomic) BOOL drew;
@end

@implementation DummyDelegate
- (void)mtkView:(id)view drawableSizeWillChange:(CGSize)size {
  NSLog(@"Drawable size will change: %f x %f", size.width, size.height);
}
- (void)drawInMTKView:(id)view {
  NSLog(@"drawInMTKView invoked!");
  self.drew = YES;
}
@end

int main(void) {
  @autoreleasepool {
    id<MTLDevice> d = MTLCreateSystemDefaultDevice();
    if (!d) {
      NSLog(@"FAIL: no Metal device");
      return 1;
    }

    NSRect frame = NSMakeRect(0, 0, 800, 600);
    MTKView *v = [[MTKView alloc] initWithFrame:frame device:d];
    if (!v) {
      NSLog(@"FAIL: could not instantiate MTKView");
      return 2;
    }

    NSLog(@"MTKView created with device: %@", v.device.name);
    v.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    v.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
    v.clearColor = MTLClearColorMake(0.1, 0.2, 0.3, 1.0);

    id<MTLTexture> dt = v.depthStencilTexture;
    if (!dt || dt.pixelFormat != MTLPixelFormatDepth32Float) {
      NSLog(@"FAIL: depthStencilTexture invalid or nil");
      return 4;
    }
    NSLog(@"Verified MTKView depthStencilTexture: %lu x %lu", (unsigned long)dt.width, (unsigned long)dt.height);

    MTLRenderPassDescriptor *rpd = v.currentRenderPassDescriptor;
    if (!rpd || rpd.depthAttachment.texture != dt) {
      NSLog(@"FAIL: currentRenderPassDescriptor missing depth attachment");
      return 5;
    }
    NSLog(@"Verified MTKView currentRenderPassDescriptor depth attachment attached");

    /* Test MTKTextureLoader */
    MTKTextureLoader *loader = [[MTKTextureLoader alloc] initWithDevice:d];
    if (!loader) {
      NSLog(@"FAIL: could not instantiate MTKTextureLoader");
      return 6;
    }

    /* Build a synthetic 4x4 32-bit TGA in memory */
    uint8_t tgaHeader[18] = {0};
    tgaHeader[2] = 2; /* uncompressed true-color */
    tgaHeader[12] = 4; tgaHeader[13] = 0; /* width = 4 */
    tgaHeader[14] = 4; tgaHeader[15] = 0; /* height = 4 */
    tgaHeader[16] = 32; /* 32 bits per pixel */
    tgaHeader[17] = 0x20; /* top-down */

    uint32_t tgaPixels[16];
    for (int i = 0; i < 16; i++) {
      tgaPixels[i] = 0xFF00FF00; /* Green with alpha */
    }

    NSMutableData *tgaData = [NSMutableData dataWithBytes:tgaHeader length:sizeof(tgaHeader)];
    [tgaData appendBytes:tgaPixels length:sizeof(tgaPixels)];

    NSError *texErr = nil;
    id<MTLTexture> loadedTex = [loader newTextureWithData:tgaData options:nil error:&texErr];
    if (!loadedTex || texErr) {
      NSLog(@"FAIL: MTKTextureLoader failed to load TGA: %@", texErr);
      return 7;
    }
    if (loadedTex.width != 4 || loadedTex.height != 4) {
      NSLog(@"FAIL: loadedTex dimensions mismatch: %lu x %lu", (unsigned long)loadedTex.width, (unsigned long)loadedTex.height);
      return 8;
    }

    uint32_t readback[16] = {0};
    [loadedTex getBytes:readback bytesPerRow:16 fromRegion:MTLRegionMake2D(0, 0, 4, 4) mipmapLevel:0];
    if (readback[0] != 0xFF00FF00) {
      NSLog(@"FAIL: loadedTex pixel mismatch: 0x%08x != 0xFF00FF00", readback[0]);
      return 9;
    }
    NSLog(@"Verified MTKTextureLoader loaded TGA correctly (pixel=0x%08x)", readback[0]);

    /* Test blit encoder mipmap generation */
    id<MTLCommandQueue> queue = [d newCommandQueue];
    id<MTLCommandBuffer> cmdBuf = [queue commandBuffer];
    id<MTLBlitCommandEncoder> blit = [cmdBuf blitCommandEncoder];
    if (!blit) {
      NSLog(@"FAIL: could not create blitCommandEncoder");
      return 10;
    }
    [blit generateMipmapsForTexture:loadedTex];
    [blit endEncoding];
    [cmdBuf commit];
    [cmdBuf waitUntilCompleted];
    NSLog(@"Verified hardware blit generateMipmapsForTexture execution");
    [queue release];
    [loader release];

    /* Test MTKMeshBufferAllocator and MTKMeshBuffer */
    MTKMeshBufferAllocator *allocator = [[MTKMeshBufferAllocator alloc] initWithDevice:d];
    if (!allocator || allocator.device != d) {
      NSLog(@"FAIL: MTKMeshBufferAllocator init failed");
      return 11;
    }

    id<MDLMeshBuffer> meshBuf = [allocator newBuffer:256 type:MDLMeshBufferTypeVertex];
    if (!meshBuf || meshBuf.length != 256 || meshBuf.allocator != allocator) {
      NSLog(@"FAIL: allocator newBuffer failed");
      return 12;
    }
    float testVerts[6] = { 0.0f, 0.5f, -0.5f, -0.5f, 0.5f, -0.5f };
    [meshBuf fillData:[NSData dataWithBytes:testVerts length:sizeof(testVerts)] offset:0];

    MDLMeshBufferMap *map = [meshBuf map];
    if (!map || memcmp([map bytes], testVerts, sizeof(testVerts)) != 0) {
      NSLog(@"FAIL: meshBuffer map memory verification failed");
      return 13;
    }
    NSLog(@"Verified MTKMeshBufferAllocator and MTKMeshBuffer memory mapping");

    /* Test MDLVertexDescriptor to MTLVertexDescriptor conversion */
    MDLVertexDescriptor *mdlDesc = [[[MDLVertexDescriptor alloc] init] autorelease];
    MDLVertexAttribute *attr0 = [mdlDesc.attributes objectAtIndexedSubscript:0];
    attr0.format = MDLVertexFormatFloat3;
    attr0.offset = 0;
    attr0.bufferIndex = 0;
    MDLVertexBufferLayout *lay0 = [mdlDesc.layouts objectAtIndexedSubscript:0];
    lay0.stride = 12;

    MTLVertexDescriptor *mtlDesc = MTKMetalVertexDescriptorFromModelIO(mdlDesc);
    if (!mtlDesc || mtlDesc.attributes[0].format != MTLVertexFormatFloat3 || mtlDesc.layouts[0].stride != 12) {
      NSLog(@"FAIL: MTKMetalVertexDescriptorFromModelIO conversion failed");
      return 14;
    }
    NSLog(@"Verified MTKMetalVertexDescriptorFromModelIO format conversion: fmt=%lu, stride=%lu", (unsigned long)mtlDesc.attributes[0].format, (unsigned long)mtlDesc.layouts[0].stride);
    [allocator release];

    DummyDelegate *del = [[DummyDelegate alloc] init];
    v.delegate = del;

    [v draw];
    if (!del.drew) {
      NSLog(@"FAIL: delegate drawInMTKView was not called");
      return 3;
    }

    [del release];
    [v release];
    [d release];
    puts("PASS metalkit_test");
    return 0;
  }
}
