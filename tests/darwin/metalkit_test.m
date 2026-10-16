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
    v.clearColor = MTLClearColorMake(0.1, 0.2, 0.3, 1.0);

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
