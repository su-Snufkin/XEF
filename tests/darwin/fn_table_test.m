// visible_function_table calls: two [[visible]] functions linked into a compute pipeline, picked per thread.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
int main(void) { @autoreleasepool {
  id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
  if (!dev.supportsFunctionPointers) { NSLog(@"PASS fn_table_test (function pointers not supported)"); return 0; }
  NSError *err = nil;
  id<MTLLibrary> lib = [dev newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\n"
      "[[visible]] int twice(int x) { return x * 2; }\n[[visible]] int plus7(int x) { return x + 7; }\n"
      "kernel void k(device int *p [[buffer(0)]], visible_function_table<int(int)> t [[buffer(1)]], uint i [[thread_position_in_grid]]) {\n"
      "  p[i] = t[i & 1](p[i]);\n}\n" options:nil error:&err];
  if (!lib) { NSLog(@"FAIL compile %@", err); return 1; }
  id<MTLFunction> f1 = [lib newFunctionWithName:@"twice"], f2 = [lib newFunctionWithName:@"plus7"];
  MTLComputePipelineDescriptor *cd = [[MTLComputePipelineDescriptor alloc] init];
  cd.computeFunction = [lib newFunctionWithName:@"k"];
  MTLLinkedFunctions *lf = [MTLLinkedFunctions linkedFunctions];
  lf.functions = @[f1, f2];
  cd.linkedFunctions = lf;
  id<MTLComputePipelineState> ps = [dev newComputePipelineStateWithDescriptor:cd options:0 reflection:nil error:&err];
  if (!ps) { NSLog(@"FAIL pipeline %@", err); return 2; }
  MTLVisibleFunctionTableDescriptor *td = [MTLVisibleFunctionTableDescriptor visibleFunctionTableDescriptor];
  td.functionCount = 2;
  id<MTLVisibleFunctionTable> t = [ps newVisibleFunctionTableWithDescriptor:td];
  [t setFunction:[ps functionHandleWithFunction:f1] atIndex:0];
  [t setFunction:[ps functionHandleWithFunction:f2] atIndex:1];
  id<MTLBuffer> b = [dev newBufferWithLength:64 * 4 options:MTLResourceStorageModeShared];
  int *p = b.contents; for (int i = 0; i < 64; i++) p[i] = i;
  id<MTLCommandQueue> q = [dev newCommandQueue];
  id<MTLCommandBuffer> cb = [q commandBuffer];
  id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
  [e setComputePipelineState:ps]; [e setBuffer:b offset:0 atIndex:0]; [e setVisibleFunctionTable:t atBufferIndex:1];
  [e useResource:t usage:MTLResourceUsageRead];
  [e dispatchThreads:MTLSizeMake(64, 1, 1) threadsPerThreadgroup:MTLSizeMake(32, 1, 1)];
  [e endEncoding]; [cb commit]; [cb waitUntilCompleted];
  for (int i = 0; i < 64; i++) if (p[i] != ((i & 1) ? i + 7 : i * 2)) { NSLog(@"FAIL fn_table_test p[%d] = %d", i, p[i]); return 3; }
  NSLog(@"PASS fn_table_test");
  return 0;
}}
