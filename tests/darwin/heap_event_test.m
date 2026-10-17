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

    /* 7. Test Command Buffer Deferred Event Signal & Wait */
    id<MTLSharedEvent> cmdEvent = [device newSharedEvent];
    id<MTLCommandBuffer> sigBuf = [queue commandBuffer];
    [sigBuf encodeSignalEvent:cmdEvent value:100];
    if (cmdEvent.signaledValue != 0) {
      NSLog(@"FAIL: encodeSignalEvent prematurely signaled value before commit");
      return 15;
    }
    [sigBuf commit];
    if (cmdEvent.signaledValue != 100) {
      NSLog(@"FAIL: encodeSignalEvent did not signal value on commit");
      return 16;
    }

    id<MTLCommandBuffer> waitBuf = [queue commandBuffer];
    [waitBuf encodeWaitForEvent:cmdEvent value:100];
    [waitBuf commit];
    NSLog(@"Command buffer event synchronization verified: val=%llu", (unsigned long long)cmdEvent.signaledValue);

    /* 8. Test Sampler Descriptor and State */
    MTLSamplerDescriptor *sampDesc = [[[MTLSamplerDescriptor alloc] init] autorelease];
    sampDesc.label = @"TestSampler";
    sampDesc.minFilter = MTLSamplerMinMagFilterNearest;
    sampDesc.magFilter = MTLSamplerMinMagFilterLinear;
    sampDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
    sampDesc.tAddressMode = MTLSamplerAddressModeRepeat;
    sampDesc.lodMinClamp = 1.0f;
    sampDesc.lodMaxClamp = 5.0f;
    sampDesc.maxAnisotropy = 4;
    id<MTLSamplerState> sampState = [device newSamplerStateWithDescriptor:sampDesc];
    if (!sampState || ![sampState.label isEqualToString:@"TestSampler"] || [sampState device] != device) {
      NSLog(@"FAIL: newSamplerStateWithDescriptor failed");
      return 17;
    }
    NSLog(@"MTLSamplerState verified: label=%@, device=%@", sampState.label, [sampState.device name]);

    /* 9. Test Command Buffer Descriptors */
    MTLCommandBufferDescriptor *cbDesc = [[[MTLCommandBufferDescriptor alloc] init] autorelease];
    cbDesc.retainedReferences = NO;
    cbDesc.errorOptions = MTLCommandBufferErrorOptionEncoderExecutionStatus;
    id<MTLCommandBuffer> descBuf = [queue commandBufferWithDescriptor:cbDesc];
    if (!descBuf) {
      NSLog(@"FAIL: commandBufferWithDescriptor returned nil");
      return 18;
    }
    id<MTLCommandBuffer> unretBuf = [queue commandBufferWithUnretainedReferences];
    if (!unretBuf) {
      NSLog(@"FAIL: commandBufferWithUnretainedReferences returned nil");
      return 19;
    }
    NSLog(@"MTLCommandBufferDescriptor verified: descBuf=%@, unretBuf=%@", descBuf, unretBuf);

    /* 10. Test Binary Archive and Dynamic Library */
    MTLBinaryArchiveDescriptor *archDesc = [[[MTLBinaryArchiveDescriptor alloc] init] autorelease];
    id<MTLBinaryArchive> archive = [device newBinaryArchiveWithDescriptor:archDesc error:nil];
    if (!archive || [archive device] != device) {
      NSLog(@"FAIL: newBinaryArchiveWithDescriptor returned nil");
      return 20;
    }
    [archive setLabel:@"TestArchive"];
    if (![archive.label isEqualToString:@"TestArchive"]) {
      NSLog(@"FAIL: archive label mismatch");
      return 21;
    }

    MTLRenderPipelineDescriptor *rpDesc = [[[MTLRenderPipelineDescriptor alloc] init] autorelease];
    BOOL addedRP = [archive addRenderPipelineFunctionsWithDescriptor:rpDesc error:nil];
    if (!addedRP) {
      NSLog(@"FAIL: addRenderPipelineFunctionsWithDescriptor failed");
      return 22;
    }

    MTLComputePipelineDescriptor *cpDesc = [[[MTLComputePipelineDescriptor alloc] init] autorelease];
    BOOL addedCP = [archive addComputePipelineFunctionsWithDescriptor:cpDesc error:nil];
    if (!addedCP) {
      NSLog(@"FAIL: addComputePipelineFunctionsWithDescriptor failed");
      return 23;
    }

    id<MTLDynamicLibrary> dynLib = [device newDynamicLibrary:nil error:nil];
    if (!dynLib || [dynLib device] != device) {
      NSLog(@"FAIL: newDynamicLibrary returned nil");
      return 24;
    }
    [dynLib setLabel:@"TestDynamicLib"];
    if (![dynLib.label isEqualToString:@"TestDynamicLib"] || ![dynLib.installName containsString:@"dynamic.metallib"]) {
      NSLog(@"FAIL: dynLib properties mismatch");
      return 25;
    }
    NSLog(@"MTLBinaryArchive and MTLDynamicLibrary verified: archive=%@, dynLib=%@", archive.label, dynLib.label);

    /* 11. Test Indirect Command Buffer, Indirect Drawing/Dispatch, and Fences */
    id<MTLFence> fence = [device newFence];
    if (!fence || [fence device] != device) {
      NSLog(@"FAIL: newFence failed");
      return 26;
    }
    [fence setLabel:@"TestFence"];

    MTLIndirectCommandBufferDescriptor *icbDesc = [[[MTLIndirectCommandBufferDescriptor alloc] init] autorelease];
    icbDesc.commandTypes = MTLIndirectCommandTypeDraw | MTLIndirectCommandTypeDrawIndexed;
    icbDesc.inheritBuffers = NO;
    icbDesc.inheritPipelineState = NO;
    icbDesc.maxVertexBufferBindCount = 4;
    icbDesc.maxFragmentBufferBindCount = 4;

    id<MTLIndirectCommandBuffer> icb = [device newIndirectCommandBufferWithDescriptor:icbDesc maxCommandCount:8 options:MTLResourceStorageModeShared];
    if (!icb || icb.size != 8 || [icb device] != device) {
      NSLog(@"FAIL: newIndirectCommandBufferWithDescriptor failed");
      return 27;
    }
    [icb setLabel:@"TestICB"];

    id<MTLIndirectRenderCommand> irc = [icb indirectRenderCommandAtIndex:0];
    if (!irc) {
      NSLog(@"FAIL: indirectRenderCommandAtIndex failed");
      return 28;
    }
    [irc setVertexBuffer:hbuf offset:0 atIndex:0];
    [irc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3 instanceCount:1 baseInstance:0];

    /* Test indirect buffer encoding */
    MTLDrawPrimitivesIndirectArguments primArgs = { 3, 1, 0, 0 };
    MTLDrawIndexedPrimitivesIndirectArguments idxArgs = { 3, 1, 0, 0, 0 };
    MTLDispatchThreadgroupsIndirectArguments tgArgs = { { 1, 1, 1 } };
    NSMutableData *indData = [NSMutableData dataWithBytes:&primArgs length:sizeof(primArgs)];
    [indData appendBytes:&idxArgs length:sizeof(idxArgs)];
    [indData appendBytes:&tgArgs length:sizeof(tgArgs)];
    id<MTLBuffer> indirectArgsBuf = [device newBufferWithBytes:[indData bytes] length:[indData length] options:MTLResourceStorageModeShared];

    id<MTLCommandBuffer> cmdBuf2 = [queue commandBuffer];
    id<MTLRenderCommandEncoder> rce2 = [cmdBuf2 renderCommandEncoderWithDescriptor:passDesc];
    [rce2 updateFence:fence afterStages:MTLRenderStageFragment];
    [rce2 waitForFence:fence beforeStages:MTLRenderStageVertex];
    [rce2 useResource:htex usage:MTLResourceUsageRead stages:MTLRenderStageFragment];
    [rce2 useHeap:heap stages:MTLRenderStageFragment];
    [rce2 memoryBarrierWithScope:MTLBarrierScopeBuffers afterStages:MTLRenderStageFragment beforeStages:MTLRenderStageVertex];
    [rce2 drawPrimitives:MTLPrimitiveTypeTriangle indirectBuffer:indirectArgsBuf indirectBufferOffset:0];
    [rce2 drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexType:MTLIndexTypeUInt16 indexBuffer:hbuf indexBufferOffset:0 indirectBuffer:indirectArgsBuf indirectBufferOffset:sizeof(MTLDrawPrimitivesIndirectArguments)];
    [rce2 executeCommandsInBuffer:icb withRange:NSMakeRange(0, 1)];
    [rce2 endEncoding];

    id<MTLComputeCommandEncoder> cce2 = [cmdBuf2 computeCommandEncoder];
    [cce2 updateFence:fence];
    [cce2 waitForFence:fence];
    [cce2 useResource:hbuf usage:MTLResourceUsageRead];
    [cce2 useHeap:heap];
    [cce2 dispatchThreadgroupsWithIndirectBuffer:indirectArgsBuf indirectBufferOffset:sizeof(primArgs)+sizeof(idxArgs) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
    [cce2 endEncoding];

    id<MTLBlitCommandEncoder> bce2 = [cmdBuf2 blitCommandEncoder];
    [bce2 updateFence:fence];
    [bce2 waitForFence:fence];
    [bce2 resetCommandsInBuffer:icb withRange:NSMakeRange(0, 1)];
    [bce2 endEncoding];

    [cmdBuf2 commit];
    [cmdBuf2 waitUntilCompleted];

    NSLog(@"MTLIndirectCommandBuffer and indirect execution verified: icb=%@, fence=%@", icb.label, fence.label);

    /* 12. Test Pipeline Buffer Descriptors and Pipeline Configuration */
    MTLRenderPipelineDescriptor *rpd = [[[MTLRenderPipelineDescriptor alloc] init] autorelease];
    rpd.supportIndirectCommandBuffers = YES;
    rpd.maxVertexCallStackDepth = 2;
    rpd.maxFragmentCallStackDepth = 2;
    rpd.vertexBuffers[0].mutability = MTLMutabilityImmutable;
    rpd.fragmentBuffers[1].mutability = MTLMutabilityMutable;
    if (!rpd.supportIndirectCommandBuffers || rpd.vertexBuffers[0].mutability != MTLMutabilityImmutable || rpd.fragmentBuffers[1].mutability != MTLMutabilityMutable) {
      NSLog(@"FAIL: MTLRenderPipelineDescriptor buffer mutability check failed");
      return 29;
    }

    MTLComputePipelineDescriptor *cpd = [[[MTLComputePipelineDescriptor alloc] init] autorelease];
    cpd.supportIndirectCommandBuffers = YES;
    cpd.buffers[0].mutability = MTLMutabilityImmutable;
    cpd.maxTotalThreadsPerThreadgroup = 512;
    if (!cpd.supportIndirectCommandBuffers || cpd.buffers[0].mutability != MTLMutabilityImmutable || cpd.maxTotalThreadsPerThreadgroup != 512) {
      NSLog(@"FAIL: MTLComputePipelineDescriptor buffer mutability check failed");
      return 30;
    }
    NSLog(@"PipelineBufferDescriptors verified: rpd_buf0_mut=%lu, cpd_buf0_mut=%lu", (unsigned long)rpd.vertexBuffers[0].mutability, (unsigned long)cpd.buffers[0].mutability);

    /* 13. Test MTLCounterSampleBuffer, Command Encoder Sampling and Blit Resolving */
    if (![device supportsCounterSampling:MTLCounterSamplingPointAtStageBoundary]) {
      NSLog(@"FAIL: supportsCounterSampling check failed");
      return 31;
    }
    NSArray<id<MTLCounterSet>> *sets = device.counterSets;
    if (!sets || sets.count == 0) {
      NSLog(@"FAIL: device counterSets is empty");
      return 32;
    }
    id<MTLCounterSet> timestampSet = sets[0];
    MTLCounterSampleBufferDescriptor *csbDesc = [[[MTLCounterSampleBufferDescriptor alloc] init] autorelease];
    csbDesc.counterSet = timestampSet;
    csbDesc.label = @"TestCounterSampleBuffer";
    csbDesc.storageMode = MTLStorageModeShared;
    csbDesc.sampleCount = 4;

    id<MTLCounterSampleBuffer> sampleBuffer = [device newCounterSampleBufferWithDescriptor:csbDesc error:nil];
    if (!sampleBuffer || sampleBuffer.sampleCount != 4 || ![sampleBuffer.label isEqualToString:@"TestCounterSampleBuffer"]) {
      NSLog(@"FAIL: newCounterSampleBufferWithDescriptor failed");
      return 33;
    }

    id<MTLCommandBuffer> cmdBuf3 = [queue commandBuffer];
    id<MTLBlitCommandEncoder> bce3 = [cmdBuf3 blitCommandEncoder];
    [bce3 sampleCountersInBuffer:sampleBuffer atSampleIndex:0 withBarrier:YES];
    id<MTLBuffer> resolveDstBuf = [device newBufferWithLength:32 options:MTLResourceStorageModeShared];
    [bce3 resolveCounters:sampleBuffer inRange:NSMakeRange(0, 4) destinationBuffer:resolveDstBuf destinationOffset:0];
    [bce3 endEncoding];

    [cmdBuf3 commit];
    [cmdBuf3 waitUntilCompleted];

    uint64_t *resolvedTimestamps = (uint64_t *)[resolveDstBuf contents];
    if (resolvedTimestamps[0] == 0) {
      NSLog(@"FAIL: resolved timestamp is 0");
      return 34;
    }
    NSLog(@"MTLCounterSampleBuffer verified: sampleCount=%lu, firstSample=%llu", (unsigned long)sampleBuffer.sampleCount, (unsigned long long)resolvedTimestamps[0]);

    [resolveDstBuf release];

    NSLog(@"PASS heap_event_test");
    return 0;
  }
}
