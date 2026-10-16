/* MetalKit-lite for XEF-OSX: MTKView, MTKTextureLoader, etc. */
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>

@protocol MTKViewDelegate <NSObject>
- (void)mtkView:(id)view drawableSizeWillChange:(CGSize)size;
- (void)drawInMTKView:(id)view;
@end

@interface MTKView : NSView {
  id<MTLDevice> _device;
  id<MTKViewDelegate> _delegate;
  CAMetalLayer *_metalLayer;
  id<CAMetalDrawable> _currentDrawable;
  MTLRenderPassDescriptor *_currentRenderPassDescriptor;
  MTLPixelFormat _colorPixelFormat;
  MTLPixelFormat _depthStencilPixelFormat;
  MTLClearColor _clearColor;
  double _clearDepth;
  uint32_t _clearStencil;
  NSInteger _preferredFramesPerSecond;
  BOOL _paused;
  BOOL _enableSetNeedsDisplay;
  BOOL _autoResizeDrawable;
  id<MTLTexture> _depthStencilTexture;
  NSTimer *_timer;
}

@property (nonatomic, retain) id<MTLDevice> device;
@property (nonatomic, assign) id<MTKViewDelegate> delegate;
@property (nonatomic, readonly) id<CAMetalDrawable> currentDrawable;
@property (nonatomic, readonly) MTLRenderPassDescriptor *currentRenderPassDescriptor;
@property (nonatomic, readonly) id<MTLTexture> depthStencilTexture;
@property (nonatomic) MTLPixelFormat colorPixelFormat;
@property (nonatomic) MTLPixelFormat depthStencilPixelFormat;
@property (nonatomic) MTLClearColor clearColor;
@property (nonatomic) double clearDepth;
@property (nonatomic) uint32_t clearStencil;
@property (nonatomic) NSInteger preferredFramesPerSecond;
@property (nonatomic, getter=isPaused) BOOL paused;
@property (nonatomic) BOOL enableSetNeedsDisplay;
@property (nonatomic) BOOL autoResizeDrawable;
@property (nonatomic) CGSize drawableSize;

- (void)draw;
@end

@implementation MTKView

+ (Class)layerClass {
  return [CAMetalLayer class];
}

- (CALayer *)makeBackingLayer {
  return [CAMetalLayer layer];
}

- (void)_initCommon {
  [self setWantsLayer:YES];
  _metalLayer = (CAMetalLayer *)[self layer];
  if (![_metalLayer isKindOfClass:[CAMetalLayer class]]) {
    _metalLayer = [CAMetalLayer layer];
    [self setLayer:_metalLayer];
  }
  _colorPixelFormat = MTLPixelFormatBGRA8Unorm;
  _depthStencilPixelFormat = MTLPixelFormatInvalid;
  _clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
  _clearDepth = 1.0;
  _clearStencil = 0;
  _preferredFramesPerSecond = 60;
  _paused = NO;
  _enableSetNeedsDisplay = NO;
  _autoResizeDrawable = YES;

  if (_device) {
    _metalLayer.device = _device;
  }
  _metalLayer.pixelFormat = _colorPixelFormat;
}

- (instancetype)initWithFrame:(NSRect)frameRect device:(id<MTLDevice>)device {
  if ((self = [super initWithFrame:frameRect])) {
    _device = [device retain];
    [self _initCommon];
  }
  return self;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
  return [self initWithFrame:frameRect device:MTLCreateSystemDefaultDevice()];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  if ((self = [super initWithCoder:coder])) {
    [self _initCommon];
  }
  return self;
}

- (id<MTLDevice>)device {
  return _device;
}

- (void)setDevice:(id<MTLDevice>)device {
  if (_device != device) {
    [_device release];
    _device = [device retain];
    if (_metalLayer) {
      _metalLayer.device = _device;
    }
  }
}

- (id<MTKViewDelegate>)delegate {
  return _delegate;
}

- (void)setDelegate:(id<MTKViewDelegate>)delegate {
  _delegate = delegate;
}

- (MTLPixelFormat)colorPixelFormat {
  return _colorPixelFormat;
}

- (void)setColorPixelFormat:(MTLPixelFormat)fmt {
  _colorPixelFormat = fmt;
  if (_metalLayer) _metalLayer.pixelFormat = fmt;
}

- (MTLPixelFormat)depthStencilPixelFormat {
  return _depthStencilPixelFormat;
}

- (void)setDepthStencilPixelFormat:(MTLPixelFormat)fmt {
  _depthStencilPixelFormat = fmt;
}

- (MTLClearColor)clearColor {
  return _clearColor;
}

- (void)setClearColor:(MTLClearColor)c {
  _clearColor = c;
}

- (double)clearDepth {
  return _clearDepth;
}

- (void)setClearDepth:(double)d {
  _clearDepth = d;
}

- (uint32_t)clearStencil {
  return _clearStencil;
}

- (void)setClearStencil:(uint32_t)s {
  _clearStencil = s;
}

- (NSInteger)preferredFramesPerSecond {
  return _preferredFramesPerSecond;
}

- (void)setPreferredFramesPerSecond:(NSInteger)fps {
  _preferredFramesPerSecond = fps;
}

- (BOOL)isPaused {
  return _paused;
}

- (void)setPaused:(BOOL)p {
  _paused = p;
}

- (BOOL)enableSetNeedsDisplay {
  return _enableSetNeedsDisplay;
}

- (void)setEnableSetNeedsDisplay:(BOOL)e {
  _enableSetNeedsDisplay = e;
}

- (BOOL)autoResizeDrawable {
  return _autoResizeDrawable;
}

- (void)setAutoResizeDrawable:(BOOL)a {
  _autoResizeDrawable = a;
}

- (CGSize)drawableSize {
  return _metalLayer ? _metalLayer.drawableSize : [self bounds].size;
}

- (void)setDrawableSize:(CGSize)size {
  if (_metalLayer) {
    _metalLayer.drawableSize = size;
  }
  if (_delegate && [_delegate respondsToSelector:@selector(mtkView:drawableSizeWillChange:)]) {
    [_delegate mtkView:self drawableSizeWillChange:size];
  }
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize {
  [super resizeWithOldSuperviewSize:oldSize];
  if (_autoResizeDrawable) {
    [self setDrawableSize:[self bounds].size];
  }
}

- (id<MTLTexture>)depthStencilTexture {
  if (_depthStencilPixelFormat == MTLPixelFormatInvalid || !_device) return nil;
  CGSize sz = self.drawableSize;
  NSUInteger w = sz.width > 0 ? (NSUInteger)sz.width : 1;
  NSUInteger h = sz.height > 0 ? (NSUInteger)sz.height : 1;
  if (!_depthStencilTexture || [_depthStencilTexture width] != w || [_depthStencilTexture height] != h || [_depthStencilTexture pixelFormat] != _depthStencilPixelFormat) {
    [_depthStencilTexture release];
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:_depthStencilPixelFormat width:w height:h mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget;
    _depthStencilTexture = [[_device newTextureWithDescriptor:td] retain];
  }
  return _depthStencilTexture;
}

- (id<CAMetalDrawable>)currentDrawable {
  if (!_currentDrawable && _metalLayer) {
    _currentDrawable = [_metalLayer nextDrawable];
  }
  return _currentDrawable;
}

- (MTLRenderPassDescriptor *)currentRenderPassDescriptor {
  id<CAMetalDrawable> drawable = [self currentDrawable];
  if (!drawable) return nil;

  if (!_currentRenderPassDescriptor) {
    _currentRenderPassDescriptor = [[MTLRenderPassDescriptor renderPassDescriptor] retain];
  }

  MTLRenderPassColorAttachmentDescriptor *colorAtt = _currentRenderPassDescriptor.colorAttachments[0];
  colorAtt.texture = drawable.texture;
  colorAtt.loadAction = MTLLoadActionClear;
  colorAtt.storeAction = MTLStoreActionStore;
  colorAtt.clearColor = _clearColor;

  if (_depthStencilPixelFormat != MTLPixelFormatInvalid) {
    id<MTLTexture> dt = [self depthStencilTexture];
    if (dt) {
      _currentRenderPassDescriptor.depthAttachment.texture = dt;
      _currentRenderPassDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
      _currentRenderPassDescriptor.depthAttachment.storeAction = MTLStoreActionDontCare;
      _currentRenderPassDescriptor.depthAttachment.clearDepth = _clearDepth;
    }
  }

  return _currentRenderPassDescriptor;
}

- (void)draw {
  _currentDrawable = nil;
  if (_delegate && [_delegate respondsToSelector:@selector(drawInMTKView:)]) {
    [_delegate drawInMTKView:self];
  }
}

- (void)drawRect:(NSRect)dirtyRect {
  [self draw];
}

- (void)dealloc {
  [_timer invalidate];
  [_timer release];
  [_device release];
  [_depthStencilTexture release];
  [_currentRenderPassDescriptor release];
  [super dealloc];
}
@end

/* ------------------------------------------------------------- MTKTextureLoader */

NSString * const MTKTextureLoaderOptionAllocateMipmaps = @"MTKTextureLoaderOptionAllocateMipmaps";
NSString * const MTKTextureLoaderOptionGenerateMipmaps = @"MTKTextureLoaderOptionGenerateMipmaps";
NSString * const MTKTextureLoaderOptionSRGB = @"MTKTextureLoaderOptionSRGB";
NSString * const MTKTextureLoaderOptionTextureUsage = @"MTKTextureLoaderOptionTextureUsage";
NSString * const MTKTextureLoaderOptionTextureCPUCacheMode = @"MTKTextureLoaderOptionTextureCPUCacheMode";
NSString * const MTKTextureLoaderOptionTextureStorageMode = @"MTKTextureLoaderOptionTextureStorageMode";
NSString * const MTKTextureLoaderOptionOrigin = @"MTKTextureLoaderOptionOrigin";
NSString * const MTKTextureLoaderOptionOriginTopLeft = @"MTKTextureLoaderOptionOriginTopLeft";
NSString * const MTKTextureLoaderOptionOriginBottomLeft = @"MTKTextureLoaderOptionOriginBottomLeft";
NSString * const MTKTextureLoaderErrorDomain = @"MTKTextureLoaderErrorDomain";

typedef void (^MTKTextureLoaderCallback)(id<MTLTexture> texture, NSError *error);

@interface MTKTextureLoader : NSObject {
  id<MTLDevice> _device;
}
@property (nonatomic, readonly) id<MTLDevice> device;
- (instancetype)initWithDevice:(id<MTLDevice>)device;
- (id<MTLTexture>)newTextureWithContentsOfURL:(NSURL *)URL options:(NSDictionary *)options error:(NSError **)error;
- (id<MTLTexture>)newTextureWithData:(NSData *)data options:(NSDictionary *)options error:(NSError **)error;
- (id<MTLTexture>)newTextureWithCGImage:(CGImageRef)cgImage options:(NSDictionary *)options error:(NSError **)error;
- (id<MTLTexture>)newTextureWithName:(NSString *)name scaleFactor:(CGFloat)scaleFactor bundle:(NSBundle *)bundle options:(NSDictionary *)options error:(NSError **)error;
- (void)newTextureWithContentsOfURL:(NSURL *)URL options:(NSDictionary *)options completionHandler:(MTKTextureLoaderCallback)completionHandler;
- (void)newTextureWithData:(NSData *)data options:(NSDictionary *)options completionHandler:(MTKTextureLoaderCallback)completionHandler;
- (void)newTextureWithCGImage:(CGImageRef)cgImage options:(NSDictionary *)options completionHandler:(MTKTextureLoaderCallback)completionHandler;
- (void)newTextureWithName:(NSString *)name scaleFactor:(CGFloat)scaleFactor bundle:(NSBundle *)bundle options:(NSDictionary *)options completionHandler:(MTKTextureLoaderCallback)completionHandler;
@end

@implementation MTKTextureLoader

- (instancetype)initWithDevice:(id<MTLDevice>)device {
  if ((self = [super init])) {
    _device = [device retain];
  }
  return self;
}

- (id<MTLDevice>)device {
  return _device;
}

- (id<MTLTexture>)newTextureWithData:(NSData *)data options:(NSDictionary *)options error:(NSError **)error {
  if (error) *error = nil;
  if (!data || [data length] < 4) {
    if (error) *error = [NSError errorWithDomain:MTKTextureLoaderErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Empty or invalid image data"}];
    return nil;
  }

  const uint8_t *raw = (const uint8_t *)[data bytes];
  size_t len = [data length];
  int width = 0, height = 0;
  uint32_t *pixelBuffer = NULL;
  BOOL allocatedPixels = NO;

  /* Check for BMP ('BM') */
  if (len >= 54 && raw[0] == 'B' && raw[1] == 'M') {
    uint32_t dataOff = *(const uint32_t *)(raw + 10);
    int32_t w = *(const int32_t *)(raw + 18);
    int32_t h = *(const int32_t *)(raw + 22);
    uint16_t bpp = *(const uint16_t *)(raw + 28);
    if (w > 0 && h != 0 && dataOff < len && (bpp == 24 || bpp == 32)) {
      int absH = h > 0 ? h : -h;
      width = w; height = absH;
      pixelBuffer = (uint32_t *)malloc(width * height * 4);
      allocatedPixels = YES;
      size_t rowBytes = ((size_t)width * (bpp / 8) + 3) & ~3;
      for (int y = 0; y < absH; y++) {
        int srcY = (h > 0) ? (absH - 1 - y) : y;
        const uint8_t *srcRow = raw + dataOff + srcY * rowBytes;
        uint32_t *dstRow = pixelBuffer + y * width;
        if (bpp == 32) {
          memcpy(dstRow, srcRow, width * 4);
        } else {
          for (int x = 0; x < width; x++) {
            dstRow[x] = (uint32_t)srcRow[x*3] | ((uint32_t)srcRow[x*3+1] << 8) | ((uint32_t)srcRow[x*3+2] << 16) | 0xFF000000;
          }
        }
      }
    }
  }

  /* Check for TGA (uncompressed true-color) */
  if (!pixelBuffer && len >= 18 && (raw[2] == 2 || raw[2] == 3)) {
    int w = raw[12] | (raw[13] << 8);
    int h = raw[14] | (raw[15] << 8);
    int bpp = raw[16];
    size_t dataOff = 18 + raw[0];
    if (w > 0 && h > 0 && (bpp == 24 || bpp == 32 || bpp == 8) && dataOff < len) {
      width = w; height = h;
      pixelBuffer = (uint32_t *)malloc(width * height * 4);
      allocatedPixels = YES;
      BOOL topDown = (raw[17] & 0x20) != 0;
      size_t bpr = (size_t)width * (bpp / 8);
      for (int y = 0; y < height; y++) {
        int srcY = topDown ? y : (height - 1 - y);
        const uint8_t *srcRow = raw + dataOff + srcY * bpr;
        uint32_t *dstRow = pixelBuffer + y * width;
        if (bpp == 32) {
          memcpy(dstRow, srcRow, width * 4);
        } else if (bpp == 24) {
          for (int x = 0; x < width; x++) {
            dstRow[x] = (uint32_t)srcRow[x*3] | ((uint32_t)srcRow[x*3+1] << 8) | ((uint32_t)srcRow[x*3+2] << 16) | 0xFF000000;
          }
        } else {
          for (int x = 0; x < width; x++) {
            uint32_t g = srcRow[x];
            dstRow[x] = g | (g << 8) | (g << 16) | 0xFF000000;
          }
        }
      }
    }
  }

  /* Check for PPM ('P6') */
  if (!pixelBuffer && len >= 16 && raw[0] == 'P' && raw[1] == '6') {
    const char *p = (const char *)raw + 2;
    while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
    int w = atoi(p);
    while (*p >= '0' && *p <= '9') p++;
    while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
    int h = atoi(p);
    while (*p >= '0' && *p <= '9') p++;
    while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
    int maxval = atoi(p);
    while (*p >= '0' && *p <= '9') p++;
    if (*p == '\r') p++;
    if (*p == '\n') p++;
    const uint8_t *srcPixels = (const uint8_t *)p;
    if (w > 0 && h > 0 && maxval > 0 && (size_t)(srcPixels - raw + w * h * 3) <= len) {
      width = w; height = h;
      pixelBuffer = (uint32_t *)malloc(width * height * 4);
      allocatedPixels = YES;
      for (int i = 0; i < width * height; i++) {
        pixelBuffer[i] = (uint32_t)srcPixels[i*3+2] | ((uint32_t)srcPixels[i*3+1] << 8) | ((uint32_t)srcPixels[i*3] << 16) | 0xFF000000;
      }
    }
  }

  /* Fallback: treat as raw RGBA/BGRA pixels (square or known aspect) */
  if (!pixelBuffer) {
    size_t pixelCount = len / 4;
    int side = (int)sqrt((double)pixelCount);
    if (side > 0 && (size_t)(side * side * 4) == len) {
      width = side; height = side;
      pixelBuffer = (uint32_t *)raw;
    } else {
      /* Minimal 1x1 fallback if data has at least 4 bytes */
      width = 1; height = 1;
      pixelBuffer = (uint32_t *)raw;
    }
  }

  BOOL allocateMipmaps = NO;
  if (options && [options[MTKTextureLoaderOptionAllocateMipmaps] boolValue]) allocateMipmaps = YES;
  if (options && [options[MTKTextureLoaderOptionGenerateMipmaps] boolValue]) allocateMipmaps = YES;

  MTLPixelFormat format = MTLPixelFormatBGRA8Unorm;
  if (options && [options[MTKTextureLoaderOptionSRGB] boolValue]) format = MTLPixelFormatBGRA8Unorm_sRGB;

  MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format
                                                                                width:width
                                                                               height:height
                                                                            mipmapped:allocateMipmaps];
  if (options && options[MTKTextureLoaderOptionTextureUsage]) {
    td.usage = [options[MTKTextureLoaderOptionTextureUsage] unsignedIntegerValue];
  }
  if (options && options[MTKTextureLoaderOptionTextureStorageMode]) {
    td.storageMode = [options[MTKTextureLoaderOptionTextureStorageMode] unsignedIntegerValue];
  }

  id<MTLTexture> tex = [_device newTextureWithDescriptor:td];
  if (tex && pixelBuffer) {
    [tex replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:pixelBuffer bytesPerRow:width * 4];
  }

  if (allocatedPixels && pixelBuffer) free(pixelBuffer);
  return tex;
}

- (id<MTLTexture>)newTextureWithContentsOfURL:(NSURL *)URL options:(NSDictionary *)options error:(NSError **)error {
  if (!URL) {
    if (error) *error = [NSError errorWithDomain:MTKTextureLoaderErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: @"Nil URL"}];
    return nil;
  }
  NSData *data = [NSData dataWithContentsOfURL:URL];
  return [self newTextureWithData:data options:options error:error];
}

- (id<MTLTexture>)newTextureWithCGImage:(CGImageRef)cgImage options:(NSDictionary *)options error:(NSError **)error {
  /* Fallback 1x1 texture if no CoreGraphics rasterizer */
  uint32_t white = 0xFFFFFFFF;
  NSData *d = [NSData dataWithBytes:&white length:sizeof(white)];
  return [self newTextureWithData:d options:options error:error];
}

- (id<MTLTexture>)newTextureWithName:(NSString *)name scaleFactor:(CGFloat)scaleFactor bundle:(NSBundle *)bundle options:(NSDictionary *)options error:(NSError **)error {
  if (!bundle) bundle = [NSBundle mainBundle];
  NSString *path = [bundle pathForResource:name ofType:@"png"];
  if (!path) path = [bundle pathForResource:name ofType:@"bmp"];
  if (!path) path = [bundle pathForResource:name ofType:@"tga"];
  if (!path) path = [bundle pathForResource:name ofType:@"ppm"];
  if (!path) path = [bundle pathForResource:name ofType:nil];
  if (path) {
    return [self newTextureWithContentsOfURL:[NSURL fileURLWithPath:path] options:options error:error];
  }
  if (error) *error = [NSError errorWithDomain:MTKTextureLoaderErrorDomain code:3 userInfo:@{NSLocalizedDescriptionKey: @"Resource not found"}];
  return nil;
}

- (void)newTextureWithContentsOfURL:(NSURL *)URL options:(NSDictionary *)options completionHandler:(MTKTextureLoaderCallback)completionHandler {
  NSError *err = nil;
  id<MTLTexture> tex = [self newTextureWithContentsOfURL:URL options:options error:&err];
  if (completionHandler) completionHandler(tex, err);
}

- (void)newTextureWithData:(NSData *)data options:(NSDictionary *)options completionHandler:(MTKTextureLoaderCallback)completionHandler {
  NSError *err = nil;
  id<MTLTexture> tex = [self newTextureWithData:data options:options error:&err];
  if (completionHandler) completionHandler(tex, err);
}

- (void)newTextureWithCGImage:(CGImageRef)cgImage options:(NSDictionary *)options completionHandler:(MTKTextureLoaderCallback)completionHandler {
  NSError *err = nil;
  id<MTLTexture> tex = [self newTextureWithCGImage:cgImage options:options error:&err];
  if (completionHandler) completionHandler(tex, err);
}

- (void)newTextureWithName:(NSString *)name scaleFactor:(CGFloat)scaleFactor bundle:(NSBundle *)bundle options:(NSDictionary *)options completionHandler:(MTKTextureLoaderCallback)completionHandler {
  NSError *err = nil;
  id<MTLTexture> tex = [self newTextureWithName:name scaleFactor:scaleFactor bundle:bundle options:options error:&err];
  if (completionHandler) completionHandler(tex, err);
}

- (void)dealloc {
  [_device release];
  [super dealloc];
}

@end

