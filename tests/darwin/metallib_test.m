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

    NSString *metallibPath = @"tests/darwin/AAPLShaders.metallib";
    if (argc > 1) {
      metallibPath = [NSString stringWithUTF8String:argv[1]];
    }

    NSError *err = nil;
    id<MTLLibrary> lib = [d newLibraryWithFile:metallibPath error:&err];
    if (!lib) {
      NSLog(@"FAIL: newLibraryWithFile failed: %@", err);
      return 2;
    }

    NSArray<NSString *> *names = [lib functionNames];
    NSLog(@"Found %lu functions in metallib: %@", (unsigned long)[names count], names);

    if ([names count] == 0) {
      NSLog(@"FAIL: expected at least 1 function in metallib");
      return 3;
    }

    for (NSString *fnName in names) {
      id<MTLFunction> fn = [lib newFunctionWithName:fnName];
      if (!fn) {
        NSLog(@"FAIL: could not get function '%@'", fnName);
        return 4;
      }
      const char *typeStr = (fn.functionType == MTLFunctionTypeVertex) ? "vertex" :
                            (fn.functionType == MTLFunctionTypeFragment) ? "fragment" : "kernel";
      NSLog(@"Function: name='%@', type=%s", fn.name, typeStr);
      [fn release];
    }

    MTLRenderPipelineDescriptor *pd = [[MTLRenderPipelineDescriptor alloc] init];
    pd.vertexFunction = [lib newFunctionWithName:@"vertexShader"];
    pd.fragmentFunction = [lib newFunctionWithName:@"fragmentShader"];
    pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    id<MTLRenderPipelineState> ps = [d newRenderPipelineStateWithDescriptor:pd error:&err];
    if (!ps) {
      NSLog(@"FAIL: could not create render pipeline state: %@", err);
      return 5;
    }
    NSLog(@"Successfully created MTLRenderPipelineState with metallib functions!");

    if ([lib respondsToSelector:@selector(spirvData)]) {
      NSData *spv = [(id)lib performSelector:@selector(spirvData)];
      if (spv && [spv length] >= 4) {
        const uint32_t *spvWords = (const uint32_t *)[spv bytes];
        if (spvWords[0] == 0x07230203) {
          NSLog(@"PASS: JIT translated metallib to valid Vulkan SPIR-V binary (%lu bytes, magic=0x%08X)",
                (unsigned long)[spv length], spvWords[0]);
        } else {
          NSLog(@"FAIL: invalid SPIR-V magic: 0x%08X", spvWords[0]);
          return 6;
        }
      }
    }

    [pd release];
    [lib release];
    [d release];
    puts("PASS metallib_test");
    return 0;
  }
}
