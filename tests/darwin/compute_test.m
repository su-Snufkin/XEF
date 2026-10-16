#import <Metal/Metal.h>
#import <Foundation/Foundation.h>

int main(int argc, char** argv) {
  @autoreleasepool {
    id<MTLDevice> d = MTLCreateSystemDefaultDevice();
    if (!d) {
      NSLog(@"FAIL: no Metal device");
      return 1;
    }
    NSLog(@"Device: %@", d.name);

    NSString *metallibPath = @"tests/darwin/add.metallib";
    if (argc > 1) {
      metallibPath = [NSString stringWithUTF8String:argv[1]];
    }

    NSError *err = nil;
    id<MTLLibrary> lib = [d newLibraryWithFile:metallibPath error:&err];
    if (!lib) {
      NSLog(@"FAIL: newLibraryWithFile failed: %@", err);
      return 2;
    }

    id<MTLFunction> fn = [lib newFunctionWithName:@"add_arrays"];
    if (!fn) {
      NSLog(@"FAIL: could not find function 'add_arrays'");
      return 3;
    }

    id<MTLComputePipelineState> pso = [d newComputePipelineStateWithFunction:fn error:&err];
    if (!pso) {
      NSLog(@"FAIL: newComputePipelineStateWithFunction failed: %@", err);
      return 4;
    }
    NSLog(@"Compute pipeline created: maxTotalThreadsPerThreadgroup=%lu, executionWidth=%lu",
          (unsigned long)pso.maxTotalThreadsPerThreadgroup, (unsigned long)pso.threadExecutionWidth);

    const NSUInteger count = 1024;
    const NSUInteger bufSize = count * sizeof(float);

    id<MTLBuffer> bufA = [d newBufferWithLength:bufSize options:MTLResourceStorageModeShared];
    id<MTLBuffer> bufB = [d newBufferWithLength:bufSize options:MTLResourceStorageModeShared];
    id<MTLBuffer> bufResult = [d newBufferWithLength:bufSize options:MTLResourceStorageModeShared];

    float *a = (float *)[bufA contents];
    float *b = (float *)[bufB contents];
    float *res = (float *)[bufResult contents];

    for (NSUInteger i = 0; i < count; i++) {
      a[i] = (float)i * 1.5f;
      b[i] = (float)(count - i) * 2.0f;
      res[i] = 0.0f;
    }

    id<MTLCommandQueue> queue = [d newCommandQueue];
    id<MTLCommandBuffer> cb = [queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [cb computeCommandEncoder];

    [encoder setComputePipelineState:pso];
    [encoder setBuffer:bufA offset:0 atIndex:0];
    [encoder setBuffer:bufB offset:0 atIndex:1];
    [encoder setBuffer:bufResult offset:0 atIndex:2];

    MTLSize gridSize = MTLSizeMake(count, 1, 1);
    NSUInteger threadGroupSize = pso.maxTotalThreadsPerThreadgroup;
    if (threadGroupSize > count) threadGroupSize = count;
    MTLSize tgSize = MTLSizeMake(threadGroupSize, 1, 1);

    [encoder dispatchThreads:gridSize threadsPerThreadgroup:tgSize];
    [encoder endEncoding];

    [cb commit];
    [cb waitUntilCompleted];

    BOOL ok = YES;
    for (NSUInteger i = 0; i < count; i++) {
      float expected = a[i] + b[i];
      if (fabsf(res[i] - expected) > 1e-4f) {
        NSLog(@"FAIL: mismatch at %lu: got %f, expected %f", (unsigned long)i, res[i], expected);
        ok = NO;
        break;
      }
    }

    if (!ok) return 5;

    [bufA release];
    [bufB release];
    [bufResult release];
    [pso release];
    [fn release];
    [lib release];
    [queue release];
    [d release];

    puts("PASS compute_test");
    return 0;
  }
}
