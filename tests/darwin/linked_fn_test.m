// [[visible]] functions supplied through linkedFunctions, and extern functions from a dynamic library.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
static int run(id<MTLDevice> dev, id<MTLComputePipelineState> ps, int mul, int add, const char *what) {
  id<MTLBuffer> b = [dev newBufferWithLength:64 * 4 options:MTLResourceStorageModeShared];
  int *p = b.contents; for (int i = 0; i < 64; i++) p[i] = i;
  id<MTLCommandQueue> q = [dev newCommandQueue];
  id<MTLCommandBuffer> cb = [q commandBuffer];
  id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
  [e setComputePipelineState:ps]; [e setBuffer:b offset:0 atIndex:0];
  [e dispatchThreads:MTLSizeMake(64, 1, 1) threadsPerThreadgroup:MTLSizeMake(32, 1, 1)];
  [e endEncoding]; [cb commit]; [cb waitUntilCompleted];
  for (int i = 0; i < 64; i++) if (p[i] != i * mul + add + i) { printf("%s: p[%d] = %d\n", what, i, p[i]); return 0; }
  printf("%s ok\n", what);
  return 1;
}
int main(void) { @autoreleasepool {
  id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
  NSError *err = nil;
  // 1. linkedFunctions
  id<MTLLibrary> fl = [dev newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\n"
      "[[visible]] int scale(int x, uint i) { return x * 2 + int(i); }\n" options:nil error:&err];
  id<MTLLibrary> kl = [dev newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\n"
      "[[visible]] int scale(int x, uint i);\n"
      "kernel void k(device int *p [[buffer(0)]], uint i [[thread_position_in_grid]]) { p[i] = scale(p[i], i) + 5; }\n" options:nil error:&err];
  if (!fl || !kl) { NSLog(@"FAIL compile %@", err); return 1; }
  MTLComputePipelineDescriptor *cd = [[MTLComputePipelineDescriptor alloc] init];
  cd.computeFunction = [kl newFunctionWithName:@"k"];
  MTLLinkedFunctions *lf = [MTLLinkedFunctions linkedFunctions];
  lf.functions = @[[fl newFunctionWithName:@"scale"]];
  cd.linkedFunctions = lf;
  id<MTLComputePipelineState> ps = [dev newComputePipelineStateWithDescriptor:cd options:0 reflection:nil error:&err];
  if (!ps) { NSLog(@"FAIL linked pipeline %@", err); return 2; }
  int ok = run(dev, ps, 2, 5, "linkedFunctions");
  // 2. dynamic library
  if (dev.supportsDynamicLibraries) {
    MTLCompileOptions *dopt = [[MTLCompileOptions alloc] init];
    dopt.libraryType = MTLLibraryTypeDynamic;
    dopt.installName = @"@executable_path/helper.metallib";
    id<MTLLibrary> hl = [dev newLibraryWithSource:@"#include <metal_stdlib>\nextern int helper(int x);\nint helper(int x) { return x * 3 + 1; }\n" options:dopt error:&err];
    printf("dynamic library functions: %s\n", [[hl.functionNames description] UTF8String]);
    id<MTLDynamicLibrary> dyn = hl ? [dev newDynamicLibrary:hl error:&err] : nil;
    if (!dyn) { NSLog(@"FAIL dynamic library %@", err); return 3; }
    NSString *exe = [[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent];
    [dyn serializeToURL:[NSURL fileURLWithPath:[exe stringByAppendingPathComponent:@"helper.metallib"]] error:nil];   /* where the install name points */
    MTLCompileOptions *kopt = [[MTLCompileOptions alloc] init];
    kopt.libraries = @[dyn];
    id<MTLLibrary> kl2 = [dev newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\nextern int helper(int x);\n"
        "kernel void k2(device int *p [[buffer(0)]], uint i [[thread_position_in_grid]]) { p[i] = helper(p[i]) + int(i); }\n" options:kopt error:&err];
    if (!kl2) { NSLog(@"FAIL compile 2 %@", err); return 4; }
    MTLComputePipelineDescriptor *cd2 = [[MTLComputePipelineDescriptor alloc] init];
    cd2.computeFunction = [kl2 newFunctionWithName:@"k2"];
    cd2.preloadedLibraries = @[dyn];
    id<MTLComputePipelineState> ps2 = [dev newComputePipelineStateWithDescriptor:cd2 options:0 reflection:nil error:&err];
    if (!ps2) { NSLog(@"FAIL dynamic pipeline %@", err); return 5; }
    ok &= run(dev, ps2, 3, 1, "dynamic library");
  }
  NSLog(ok ? @"PASS linked_fn_test" : @"FAIL linked_fn_test");
  return ok ? 0 : 6;
}}
