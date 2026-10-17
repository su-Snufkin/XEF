#import <Metal/Metal.h>
#import <Foundation/Foundation.h>

int main(void) {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
      NSLog(@"FAIL: no Metal device");
      return 1;
    }
    NSLog(@"Device: %@", device.name);

    /* 1. Test MTLHeap size and alignment queries */
    MTLSizeAndAlign bufAlign = [device heapBufferSizeAndAlignWithLength:1000 options:0];
    if (bufAlign.size < 1000 || bufAlign.align == 0) {
      NSLog(@"FAIL: heapBufferSizeAndAlign error");
      return 2;
    }

    MTLTextureDescriptor *texDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:64 height:64 mipmapped:NO];
    MTLSizeAndAlign texAlign = [device heapTextureSizeAndAlignWithDescriptor:texDesc];
    if (texAlign.size < 64 * 64 * 4 || texAlign.align == 0) {
      NSLog(@"FAIL: heapTextureSizeAndAlign error");
      return 3;
    }

    /* 2. Test MTLHeap creation and resource suballocation */
    MTLHeapDescriptor *heapDesc = [[[MTLHeapDescriptor alloc] init] autorelease];
    heapDesc.size = 1024 * 1024;
    heapDesc.storageMode = MTLStorageModeShared;
    id<MTLHeap> heap = [device newHeapWithDescriptor:heapDesc];
    if (!heap || heap.size != 1024 * 1024) {
      NSLog(@"FAIL: could not create MTLHeap");
      return 4;
    }

    id<MTLBuffer> hbuf = [heap newBufferWithLength:512 options:0];
    if (!hbuf || [hbuf heap] != heap) {
      NSLog(@"FAIL: buffer heap reference missing");
      return 5;
    }

    id<MTLTexture> htex = [heap newTextureWithDescriptor:texDesc];
    if (!htex || [htex heap] != heap) {
      NSLog(@"FAIL: texture heap reference missing");
      return 6;
    }

    if ([heap usedSize] == 0 || [heap maxAvailableSizeWithAlignment:256] == 0) {
      NSLog(@"FAIL: heap usedSize / maxAvailableSize error");
      return 7;
    }
    NSLog(@"MTLHeap verified: size=%lu, used=%lu", (unsigned long)heap.size, (unsigned long)heap.usedSize);

    /* 3. Test MTLSharedEvent and MTLSharedEventListener */
    id<MTLSharedEvent> sharedEvent = [device newSharedEvent];
    if (!sharedEvent || sharedEvent.signaledValue != 0) {
      NSLog(@"FAIL: newSharedEvent error");
      return 8;
    }

    MTLSharedEventListener *listener = [MTLSharedEventListener sharedListener];
    if (!listener || !listener.dispatchQueue) {
      NSLog(@"FAIL: sharedListener missing dispatchQueue");
      return 9;
    }

    __block BOOL blockFired = NO;
    __block uint64_t firedValue = 0;
    [sharedEvent notifyListener:listener atValue:42 block:^(id<MTLSharedEvent> ev, uint64_t val) {
      blockFired = YES;
      firedValue = val;
    }];

    sharedEvent.signaledValue = 42;
    if (![sharedEvent waitUntilSignaledValue:42 timeoutMS:500]) {
      NSLog(@"FAIL: waitUntilSignaledValue timed out");
      return 10;
    }

    MTLSharedEventHandle *handle = [sharedEvent newSharedEventHandle];
    id<MTLSharedEvent> sharedEvent2 = [device newSharedEventWithHandle:handle];
    if (!sharedEvent2 || sharedEvent2.signaledValue != 42) {
      NSLog(@"FAIL: newSharedEventWithHandle error");
      return 11;
    }
    NSLog(@"MTLSharedEvent verified: signaledValue=%llu", (unsigned long long)sharedEvent.signaledValue);

    /* 4. Test MTLRenderCommandEncoder dynamic fill mode, depth bias, blend color, and blit copy */
    id<MTLCommandQueue> queue = [device newCommandQueue];
    id<MTLCommandBuffer> cmdBuf = [queue commandBuffer];

    MTLRenderPassDescriptor *passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    passDesc.colorAttachments[0].texture = htex;
    passDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
    passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
    passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);

    id<MTLRenderCommandEncoder> rce = [cmdBuf renderCommandEncoderWithDescriptor:passDesc];
    MTLDepthStencilDescriptor *dsDesc = [[MTLDepthStencilDescriptor alloc] init];
    dsDesc.depthCompareFunction = MTLCompareFunctionLess;
    dsDesc.depthWriteEnabled = YES;
    dsDesc.frontFaceStencil.stencilCompareFunction = MTLCompareFunctionEqual;
    dsDesc.frontFaceStencil.stencilFailureOperation = MTLStencilOperationKeep;
    dsDesc.frontFaceStencil.depthFailureOperation = MTLStencilOperationIncrementClamp;
    dsDesc.frontFaceStencil.depthStencilPassOperation = MTLStencilOperationReplace;
    dsDesc.frontFaceStencil.readMask = 0xFF;
    dsDesc.frontFaceStencil.writeMask = 0xFF;

    dsDesc.backFaceStencil.stencilCompareFunction = MTLCompareFunctionNotEqual;
    dsDesc.backFaceStencil.stencilFailureOperation = MTLStencilOperationZero;
    dsDesc.backFaceStencil.depthFailureOperation = MTLStencilOperationDecrementClamp;
    dsDesc.backFaceStencil.depthStencilPassOperation = MTLStencilOperationInvert;
    dsDesc.backFaceStencil.readMask = 0xFE;
    dsDesc.backFaceStencil.writeMask = 0xFE;

    id<MTLDepthStencilState> dsState = [device newDepthStencilStateWithDescriptor:dsDesc];
    [rce setDepthStencilState:dsState];
    [rce setStencilFrontReferenceValue:128 backReferenceValue:64];
    [rce setTriangleFillMode:MTLTriangleFillModeLines];
    [rce setDepthBias:2.0f slopeScale:1.5f clamp:0.5f];
    [rce setBlendColorRed:0.8f green:0.6f blue:0.4f alpha:1.0f];
    [rce endEncoding];
    [dsDesc release];

    /* Blit copy test */
    id<MTLTexture> dstTex = [device newTextureWithDescriptor:texDesc];
    id<MTLBlitCommandEncoder> bce = [cmdBuf blitCommandEncoder];
    [bce copyFromTexture:htex
             sourceSlice:0
             sourceLevel:0
            sourceOrigin:MTLOriginMake(0, 0, 0)
              sourceSize:MTLSizeMake(64, 64, 1)
               toTexture:dstTex
        destinationSlice:0
        destinationLevel:0
       destinationOrigin:MTLOriginMake(0, 0, 0)];
    [bce endEncoding];

    /* 5. Test Texture View and Swizzle */
    MTLTextureSwizzleChannels swz = MTLTextureSwizzleChannelsMake(MTLTextureSwizzleBlue, MTLTextureSwizzleGreen, MTLTextureSwizzleRed, MTLTextureSwizzleOne);
    id<MTLTexture> swzView = [htex newTextureViewWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                     textureType:MTLTextureType2D
                                                          levels:NSMakeRange(0, 1)
                                                          slices:NSMakeRange(0, 1)
                                                         swizzle:swz];
    if (!swzView) {
      NSLog(@"FAIL: newTextureViewWithPixelFormat:textureType:levels:slices:swizzle: returned nil");
      return 12;
    }
    if (swzView.swizzle.red != MTLTextureSwizzleBlue || swzView.swizzle.alpha != MTLTextureSwizzleOne) {
      NSLog(@"FAIL: swizzle mismatch on texture view");
      return 13;
    }
    /* 6. Test Subresource Update and Readback */
    uint32_t testPixels[4 * 4];
    for (int i = 0; i < 16; i++) testPixels[i] = 0xFF00AA55;
    [htex replaceRegion:MTLRegionMake2D(0, 0, 4, 4) mipmapLevel:0 slice:0 withBytes:testPixels bytesPerRow:4 * 4 bytesPerImage:0];

    uint32_t readPixels[4 * 4] = {0};
    [htex getBytes:readPixels bytesPerRow:4 * 4 bytesPerImage:0 fromRegion:MTLRegionMake2D(0, 0, 4, 4) mipmapLevel:0 slice:0];
    if (readPixels[0] != 0xFF00AA55) {
      NSLog(@"FAIL: subresource readback mismatch (got 0x%08X, expected 0x%08X)", readPixels[0], 0xFF00AA55);
      return 14;
    }
    NSLog(@"Subresource update/readback verified: pixel[0]=0x%08X", readPixels[0]);

    NSLog(@"PASS heap_event_test");
    return 0;
  }
}
