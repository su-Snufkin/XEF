#include <objc/message.h>
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
  MTLStorageMode _depthStencilStorageMode;
  MTLTextureUsage _depthStencilAttachmentTextureUsage;
  MTLTextureUsage _multisampleColorAttachmentTextureUsage;
  NSUInteger _sampleCount;
  MTLClearColor _clearColor;
  double _clearDepth;
  uint32_t _clearStencil;
  NSInteger _preferredFramesPerSecond;
  BOOL _paused;
  BOOL _enableSetNeedsDisplay;
  BOOL _autoResizeDrawable;
  id<MTLTexture> _depthStencilTexture;
  id<MTLTexture> _multisampleColorTexture;
  NSTimer *_timer;
}

@property (nonatomic, retain) id<MTLDevice> device;
@property (nonatomic, readonly) id<MTLDevice> preferredDevice;
@property (nonatomic, assign) id<MTKViewDelegate> delegate;
@property (nonatomic, readonly) id<CAMetalDrawable> currentDrawable;
@property (nonatomic, readonly) MTLRenderPassDescriptor *currentRenderPassDescriptor;
@property (nonatomic, readonly) id<MTLTexture> depthStencilTexture;
@property (nonatomic, readonly) id<MTLTexture> multisampleColorTexture;
@property (nonatomic) MTLPixelFormat colorPixelFormat;
@property (nonatomic) MTLPixelFormat depthStencilPixelFormat;
@property (nonatomic) MTLStorageMode depthStencilStorageMode;
@property (nonatomic) MTLTextureUsage depthStencilAttachmentTextureUsage;
@property (nonatomic) MTLTextureUsage multisampleColorAttachmentTextureUsage;
@property (nonatomic) NSUInteger sampleCount;
@property (nonatomic) MTLClearColor clearColor;
@property (nonatomic) double clearDepth;
@property (nonatomic) uint32_t clearStencil;
@property (nonatomic) NSInteger preferredFramesPerSecond;
@property (nonatomic, getter=isPaused) BOOL paused;
@property (nonatomic) BOOL enableSetNeedsDisplay;
@property (nonatomic) BOOL autoResizeDrawable;
@property (nonatomic) CGSize drawableSize;
@property (nonatomic, readonly) CGSize preferredDrawableSize;
@property (nonatomic) BOOL framebufferOnly;
@property (nonatomic) BOOL presentsWithTransaction;
@property (nonatomic) CGColorSpaceRef colorspace;

- (void)draw;
- (void)releaseDrawables;
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
  _depthStencilStorageMode = MTLStorageModePrivate;
  _depthStencilAttachmentTextureUsage = MTLTextureUsageRenderTarget;
  _multisampleColorAttachmentTextureUsage = MTLTextureUsageRenderTarget;
  _sampleCount = 1;
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

- (id<MTLDevice>)preferredDevice {
  return _metalLayer ? _metalLayer.preferredDevice : (_device ? _device : MTLCreateSystemDefaultDevice());
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

- (MTLStorageMode)depthStencilStorageMode {
  return _depthStencilStorageMode;
}

- (void)setDepthStencilStorageMode:(MTLStorageMode)mode {
  _depthStencilStorageMode = mode;
}

- (MTLTextureUsage)depthStencilAttachmentTextureUsage {
  return _depthStencilAttachmentTextureUsage;
}

- (void)setDepthStencilAttachmentTextureUsage:(MTLTextureUsage)usage {
  _depthStencilAttachmentTextureUsage = usage;
}

- (MTLTextureUsage)multisampleColorAttachmentTextureUsage {
  return _multisampleColorAttachmentTextureUsage;
}

- (void)setMultisampleColorAttachmentTextureUsage:(MTLTextureUsage)usage {
  _multisampleColorAttachmentTextureUsage = usage;
}

- (NSUInteger)sampleCount {
  return _sampleCount;
}

- (void)setSampleCount:(NSUInteger)sc {
  if (_sampleCount != sc) {
    _sampleCount = sc;
    [_multisampleColorTexture release];
    _multisampleColorTexture = nil;
  }
}

- (BOOL)framebufferOnly {
  return _metalLayer ? _metalLayer.framebufferOnly : YES;
}

- (void)setFramebufferOnly:(BOOL)fo {
  if (_metalLayer) _metalLayer.framebufferOnly = fo;
}

- (BOOL)presentsWithTransaction {
  return _metalLayer ? _metalLayer.presentsWithTransaction : NO;
}

- (void)setPresentsWithTransaction:(BOOL)pwt {
  if (_metalLayer) _metalLayer.presentsWithTransaction = pwt;
}

- (CGColorSpaceRef)colorspace {
  return _metalLayer ? _metalLayer.colorspace : NULL;
}

- (void)setColorspace:(CGColorSpaceRef)cs {
  if (_metalLayer) _metalLayer.colorspace = cs;
}

- (CGSize)preferredDrawableSize {
  return self.drawableSize;
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

/* the internal display loop: a run-loop timer at preferredFramesPerSecond while the view is in a window,
   not paused and not in setNeedsDisplay mode */
- (void)_xefTick:(NSTimer *)t {
  if (!_paused && !_enableSetNeedsDisplay && [self window]) [self draw];
}
- (void)_xefUpdateTimer {
  BOOL want = !_paused && !_enableSetNeedsDisplay && [self window] != nil;
  NSTimeInterval iv = 1.0 / (double)(_preferredFramesPerSecond > 0 ? _preferredFramesPerSecond : 60);
  if (_timer && (!want || fabs([_timer timeInterval] - iv) > 1e-6)) { [_timer invalidate]; [_timer release]; _timer = nil; }
  if (want && !_timer) {
    _timer = [[NSTimer timerWithTimeInterval:iv target:self selector:@selector(_xefTick:) userInfo:nil repeats:YES] retain];
    [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
  }
}
- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  [self _xefUpdateTimer];
}
- (void)setPreferredFramesPerSecond:(NSInteger)fps {
  _preferredFramesPerSecond = fps;
  [self _xefUpdateTimer];
}

- (BOOL)isPaused {
  return _paused;
}

- (void)setPaused:(BOOL)p {
  _paused = p;
  [self _xefUpdateTimer];
}

- (BOOL)enableSetNeedsDisplay {
  return _enableSetNeedsDisplay;
}

- (void)setEnableSetNeedsDisplay:(BOOL)e {
  _enableSetNeedsDisplay = e;
  [self _xefUpdateTimer];
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
    td.usage = _depthStencilAttachmentTextureUsage;
    td.storageMode = _depthStencilStorageMode;
    if (_sampleCount > 1) {
      td.textureType = MTLTextureType2DMultisample;
      td.sampleCount = _sampleCount;
    }
    _depthStencilTexture = [[_device newTextureWithDescriptor:td] retain];
  }
  return _depthStencilTexture;
}

- (id<MTLTexture>)multisampleColorTexture {
  if (_sampleCount <= 1 || !_device) return nil;
  CGSize sz = self.drawableSize;
  NSUInteger w = sz.width > 0 ? (NSUInteger)sz.width : 1;
  NSUInteger h = sz.height > 0 ? (NSUInteger)sz.height : 1;
  if (!_multisampleColorTexture || [_multisampleColorTexture width] != w || [_multisampleColorTexture height] != h || [_multisampleColorTexture sampleCount] != _sampleCount || [_multisampleColorTexture pixelFormat] != _colorPixelFormat) {
    [_multisampleColorTexture release];
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:_colorPixelFormat width:w height:h mipmapped:NO];
    td.textureType = MTLTextureType2DMultisample;
    td.sampleCount = _sampleCount;
    td.usage = _multisampleColorAttachmentTextureUsage;
    td.storageMode = MTLStorageModePrivate;
    _multisampleColorTexture = [[_device newTextureWithDescriptor:td] retain];
  }
  return _multisampleColorTexture;
}

- (id<CAMetalDrawable>)currentDrawable {
  if (!_currentDrawable && _metalLayer) {
    _currentDrawable = [[_metalLayer nextDrawable] retain];
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
  if (_sampleCount > 1) {
    id<MTLTexture> msaaTex = [self multisampleColorTexture];
    colorAtt.texture = msaaTex;
    colorAtt.resolveTexture = drawable.texture;
    colorAtt.loadAction = MTLLoadActionClear;
    colorAtt.storeAction = MTLStoreActionMultisampleResolve;
  } else {
    colorAtt.texture = drawable.texture;
    colorAtt.resolveTexture = nil;
    colorAtt.loadAction = MTLLoadActionClear;
    colorAtt.storeAction = MTLStoreActionStore;
  }
  colorAtt.clearColor = _clearColor;

  if (_depthStencilPixelFormat != MTLPixelFormatInvalid) {
    id<MTLTexture> dt = [self depthStencilTexture];
    if (dt) {
      _currentRenderPassDescriptor.depthAttachment.texture = dt;
      _currentRenderPassDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
      _currentRenderPassDescriptor.depthAttachment.storeAction = MTLStoreActionDontCare;
      _currentRenderPassDescriptor.depthAttachment.clearDepth = _clearDepth;

      if (_depthStencilPixelFormat == MTLPixelFormatDepth32Float_Stencil8 ||
          _depthStencilPixelFormat == MTLPixelFormatDepth24Unorm_Stencil8 ||
          _depthStencilPixelFormat == MTLPixelFormatStencil8 ||
          _depthStencilPixelFormat == 260 /* X8_Stencil8 */) {
        _currentRenderPassDescriptor.stencilAttachment.texture = dt;
        _currentRenderPassDescriptor.stencilAttachment.loadAction = MTLLoadActionClear;
        _currentRenderPassDescriptor.stencilAttachment.storeAction = MTLStoreActionDontCare;
        _currentRenderPassDescriptor.stencilAttachment.clearStencil = _clearStencil;
      }
    }
  }

  return _currentRenderPassDescriptor;
}

- (void)releaseDrawables {
  [_currentDrawable release];
  _currentDrawable = nil;
  [_depthStencilTexture release];
  _depthStencilTexture = nil;
  [_multisampleColorTexture release];
  _multisampleColorTexture = nil;
}

- (void)draw {
  [_currentDrawable release];
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
  [_currentDrawable release];
  [_depthStencilTexture release];
  [_multisampleColorTexture release];
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
    if (options && [options[MTKTextureLoaderOptionGenerateMipmaps] boolValue]) {
      id<MTLCommandQueue> q = [_device newCommandQueue];
      if (q) {
        id<MTLCommandBuffer> cb = [q commandBuffer];
        if (cb) {
          id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
          if (blit) {
            [blit generateMipmapsForTexture:tex];
            [blit endEncoding];
          }
          [cb commit];
          [cb waitUntilCompleted];
        }
        [q release];
      }
    }
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
  /* compiled asset catalog first (MetalKitAssets.m) */
  Class cat = NSClassFromString(@"XEFAssetCatalog");
  id c = [cat performSelector:@selector(catalogForBundle:) withObject:bundle];
  if (c) {
    id<MTLTexture> t = ((id (*)(id, SEL, id, id, id, NSError **))objc_msgSend)(c, NSSelectorFromString(@"newTextureNamed:device:options:error:"), name, _device, options, error);
    if (t) return t;
  }
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

/* ------------------------------------------------------------------- MTKModel */

#import <MetalKit/MTKModel.h>

MTKModelError const MTKModelErrorDomain = @"MTKModelErrorDomain";
MTKModelError const MTKModelErrorKey = @"MTKModelErrorKey";

@interface MTKMeshBufferZone : NSObject <MDLMeshBufferZone> {
  id<MDLMeshBufferAllocator> _allocator;
  NSUInteger _capacity;
  id<MTLBuffer> _buffer;
}
@end

@implementation MTKMeshBufferZone
- (instancetype)initWithCapacity:(NSUInteger)capacity allocator:(id<MDLMeshBufferAllocator>)allocator device:(id<MTLDevice>)device {
  if ((self = [super init])) {
    _capacity = capacity;
    _allocator = allocator;
    _buffer = [[device newBufferWithLength:capacity options:MTLResourceStorageModeShared] retain];
  }
  return self;
}
- (NSUInteger)capacity { return _capacity; }
- (id<MDLMeshBufferAllocator>)allocator { return _allocator; }
- (id<MTLBuffer>)buffer { return _buffer; }
- (void)dealloc {
  [_buffer release];
  [super dealloc];
}
@end

@interface MTKMeshBuffer (Internal)
- (instancetype)initWithLength:(NSUInteger)length allocator:(MTKMeshBufferAllocator *)allocator zone:(id<MDLMeshBufferZone>)zone type:(MDLMeshBufferType)type;
- (instancetype)initWithBytes:(const void *)bytes length:(NSUInteger)length allocator:(MTKMeshBufferAllocator *)allocator zone:(id<MDLMeshBufferZone>)zone type:(MDLMeshBufferType)type;
@end

@implementation MTKMeshBuffer {
  NSUInteger _length;
  MTKMeshBufferAllocator *_allocator;
  id<MDLMeshBufferZone> _zone;
  id<MTLBuffer> _buffer;
  NSUInteger _offset;
  MDLMeshBufferType _type;
  NSString *_name;
}
- (instancetype)initWithLength:(NSUInteger)length allocator:(MTKMeshBufferAllocator *)allocator zone:(id<MDLMeshBufferZone>)zone type:(MDLMeshBufferType)type {
  if ((self = [super init])) {
    _length = length;
    _allocator = [allocator retain];
    _zone = [zone retain];
    _type = type;
    _offset = 0;
    _buffer = [[allocator.device newBufferWithLength:length > 0 ? length : 16 options:MTLResourceStorageModeShared] retain];
  }
  return self;
}
- (instancetype)initWithBytes:(const void *)bytes length:(NSUInteger)length allocator:(MTKMeshBufferAllocator *)allocator zone:(id<MDLMeshBufferZone>)zone type:(MDLMeshBufferType)type {
  if ((self = [super init])) {
    _length = length;
    _allocator = [allocator retain];
    _zone = [zone retain];
    _type = type;
    _offset = 0;
    if (bytes && length > 0) {
      _buffer = [[allocator.device newBufferWithBytes:bytes length:length options:MTLResourceStorageModeShared] retain];
    } else {
      _buffer = [[allocator.device newBufferWithLength:length > 0 ? length : 16 options:MTLResourceStorageModeShared] retain];
    }
  }
  return self;
}
- (NSUInteger)length { return _length; }
- (MTKMeshBufferAllocator *)allocator { return _allocator; }
- (id<MDLMeshBufferZone>)zone { return _zone; }
- (id<MTLBuffer>)buffer { return _buffer; }
- (NSUInteger)offset { return _offset; }
- (MDLMeshBufferType)type { return _type; }
- (NSString *)name { return _name; }
- (void)setName:(NSString *)name { [name retain]; [_name release]; _name = name; }
- (void)fillData:(NSData *)data offset:(NSUInteger)offset {
  if (data && _buffer) {
    NSUInteger copyLen = [data length];
    if (offset + copyLen > _length) copyLen = _length > offset ? (_length - offset) : 0;
    if (copyLen > 0) {
      memcpy((uint8_t *)[_buffer contents] + _offset + offset, [data bytes], copyLen);
    }
  }
}
- (MDLMeshBufferMap *)map {
  void *ptr = (uint8_t *)[_buffer contents] + _offset;
  return [[[MDLMeshBufferMap alloc] initWithBytes:ptr deallocator:nil] autorelease];
}
- (id)copyWithZone:(NSZone *)zone {
  return [self retain];
}
- (void)dealloc {
  [_allocator release];
  [_zone release];
  [_buffer release];
  [_name release];
  [super dealloc];
}
@end

@implementation MTKMeshBufferAllocator {
  id<MTLDevice> _device;
}
- (instancetype)initWithDevice:(id<MTLDevice>)device {
  if ((self = [super init])) {
    _device = [device retain];
  }
  return self;
}
- (id<MTLDevice>)device { return _device; }
/* "new" methods return +1 objects (ARC callers release them) */
- (id<MDLMeshBufferZone>)newZone:(NSUInteger)capacity {
  return [[MTKMeshBufferZone alloc] initWithCapacity:capacity allocator:self device:_device];
}
- (id<MDLMeshBufferZone>)newZoneForBuffersWithSize:(NSArray<NSNumber *> *)sizes andType:(NSArray<NSNumber *> *)types {
  NSUInteger total = 0;
  for (NSNumber *s in sizes) total += [s unsignedIntegerValue];
  return [self newZone:total];
}
- (id<MDLMeshBuffer>)newBuffer:(NSUInteger)length type:(MDLMeshBufferType)type {
  return [[MTKMeshBuffer alloc] initWithLength:length allocator:self zone:nil type:type];
}
- (id<MDLMeshBuffer>)newBufferWithData:(NSData *)data type:(MDLMeshBufferType)type {
  return [[MTKMeshBuffer alloc] initWithBytes:[data bytes] length:[data length] allocator:self zone:nil type:type];
}
- (id<MDLMeshBuffer>)newBufferFromZone:(id<MDLMeshBufferZone>)zone length:(NSUInteger)length type:(MDLMeshBufferType)type {
  return [[MTKMeshBuffer alloc] initWithLength:length allocator:self zone:zone type:type];
}
- (id<MDLMeshBuffer>)newBufferFromZone:(id<MDLMeshBufferZone>)zone data:(NSData *)data type:(MDLMeshBufferType)type {
  return [[MTKMeshBuffer alloc] initWithBytes:[data bytes] length:[data length] allocator:self zone:zone type:type];
}
- (void)dealloc {
  [_device release];
  [super dealloc];
}
@end

@interface MTKSubmesh (Internal)
- (instancetype)initWithPrimitiveType:(MTLPrimitiveType)primitiveType indexType:(MTLIndexType)indexType indexBuffer:(MTKMeshBuffer *)indexBuffer indexCount:(NSUInteger)indexCount mesh:(MTKMesh *)mesh name:(NSString *)name;
@end

@implementation MTKSubmesh {
  MTLPrimitiveType _primitiveType;
  MTLIndexType _indexType;
  MTKMeshBuffer *_indexBuffer;
  NSUInteger _indexCount;
  MTKMesh *_mesh;
  NSString *_name;
}
- (instancetype)initWithPrimitiveType:(MTLPrimitiveType)primitiveType indexType:(MTLIndexType)indexType indexBuffer:(MTKMeshBuffer *)indexBuffer indexCount:(NSUInteger)indexCount mesh:(MTKMesh *)mesh name:(NSString *)name {
  if ((self = [super init])) {
    _primitiveType = primitiveType;
    _indexType = indexType;
    _indexBuffer = [indexBuffer retain];
    _indexCount = indexCount;
    _mesh = mesh;
    _name = [name copy];
  }
  return self;
}
- (MTLPrimitiveType)primitiveType { return _primitiveType; }
- (MTLIndexType)indexType { return _indexType; }
- (MTKMeshBuffer *)indexBuffer { return _indexBuffer; }
- (NSUInteger)indexCount { return _indexCount; }
- (MTKMesh *)mesh { return _mesh; }
- (NSString *)name { return _name; }
- (void)setName:(NSString *)name { [name retain]; [_name release]; _name = name; }
- (void)dealloc {
  [_indexBuffer release];
  [_name release];
  [super dealloc];
}
@end

@implementation MTKMesh {
  NSMutableArray<MTKMeshBuffer *> *_vertexBuffers;
  MDLVertexDescriptor *_vertexDescriptor;
  NSMutableArray<MTKSubmesh *> *_submeshes;
  NSUInteger _vertexCount;
  NSString *_name;
}
- (instancetype)initWithMesh:(MDLMesh *)mesh device:(id<MTLDevice>)device error:(NSError **)error {
  if ((self = [super init])) {
    if (error) *error = nil;
    _vertexBuffers = [[NSMutableArray alloc] init];
    _submeshes = [[NSMutableArray alloc] init];
    if (mesh) {
      _vertexCount = mesh.vertexCount;
      _vertexDescriptor = [mesh.vertexDescriptor retain];
      _name = [mesh.name copy];
      /* buffers keep their index (the vertex descriptor's buffer index); others are copied into Metal buffers */
      MTKMeshBufferAllocator *alloc = [[[MTKMeshBufferAllocator alloc] initWithDevice:device] autorelease];
      MTKMeshBuffer *(^metal)(id) = ^MTKMeshBuffer *(id buf) {
        if ([buf isKindOfClass:[MTKMeshBuffer class]]) return buf;
        if (!buf || buf == [NSNull null]) return nil;
        id<MDLMeshBuffer> b = buf;
        MDLMeshBufferMap *m = [b map];
        NSData *d = [NSData dataWithBytes:[m bytes] length:[b length]];
        return [(MTKMeshBuffer *)[alloc newBufferWithData:d type:[b type]] autorelease];
      };
      for (id buf in mesh.vertexBuffers) {
        MTKMeshBuffer *mb = metal(buf);
        [_vertexBuffers addObject:mb ? (id)mb : (id)[NSNull null]];
      }
      if (mesh.submeshes) {
        for (MDLSubmesh *sub in mesh.submeshes) {
          MTKMeshBuffer *ibuf = metal(sub.indexBuffer);
          MTLIndexType itype = (sub.indexType == MDLIndexBitDepthUInt16) ? MTLIndexTypeUInt16 : MTLIndexTypeUInt32;
          MTLPrimitiveType ptype = (sub.geometryType == MDLGeometryTypeTriangles) ? MTLPrimitiveTypeTriangle : MTLPrimitiveTypeTriangleStrip;
          MTKSubmesh *s = [[MTKSubmesh alloc] initWithPrimitiveType:ptype indexType:itype indexBuffer:ibuf indexCount:sub.indexCount mesh:self name:sub.name];
          [_submeshes addObject:s];
          [s release];
        }
      }
    }
  }
  return self;
}
+ (NSArray<MTKMesh *> *)newMeshesFromAsset:(MDLAsset *)asset device:(id<MTLDevice>)device sourceMeshes:(NSArray<MDLMesh *> **)sourceMeshes error:(NSError **)error {
  if (error) *error = nil;
  NSMutableArray *outMeshes = [NSMutableArray array];
  NSMutableArray *srcMeshes = [NSMutableArray array];
  if (asset && [asset count] > 0) {
    for (NSUInteger i = 0; i < [asset count]; i++) {
      id obj = [asset objectAtIndex:i];
      if ([obj isKindOfClass:[MDLMesh class]]) {
        MDLMesh *m = (MDLMesh *)obj;
        MTKMesh *km = [[[MTKMesh alloc] initWithMesh:m device:device error:error] autorelease];
        if (km) {
          [outMeshes addObject:km];
          [srcMeshes addObject:m];
        }
      }
    }
  }
  if (sourceMeshes) *sourceMeshes = srcMeshes;
  return outMeshes;
}
- (NSArray<MTKMeshBuffer *> *)vertexBuffers { return _vertexBuffers; }
- (MDLVertexDescriptor *)vertexDescriptor { return _vertexDescriptor; }
- (NSArray<MTKSubmesh *> *)submeshes { return _submeshes; }
- (NSUInteger)vertexCount { return _vertexCount; }
- (NSString *)name { return _name; }
- (void)setName:(NSString *)name { [name retain]; [_name release]; _name = name; }
- (void)dealloc {
  [_vertexBuffers release];
  [_vertexDescriptor release];
  [_submeshes release];
  [_name release];
  [super dealloc];
}
@end

MTLVertexFormat MTKMetalVertexFormatFromModelIO(MDLVertexFormat vertexFormat) {
  switch (vertexFormat) {
    case MDLVertexFormatFloat:  return MTLVertexFormatFloat;
    case MDLVertexFormatFloat2: return MTLVertexFormatFloat2;
    case MDLVertexFormatFloat3: return MTLVertexFormatFloat3;
    case MDLVertexFormatFloat4: return MTLVertexFormatFloat4;
    case MDLVertexFormatHalf2:  return MTLVertexFormatHalf2;
    case MDLVertexFormatHalf4:  return MTLVertexFormatHalf4;
    case MDLVertexFormatInt:    return MTLVertexFormatInt;
    case MDLVertexFormatInt2:   return MTLVertexFormatInt2;
    case MDLVertexFormatInt3:   return MTLVertexFormatInt3;
    case MDLVertexFormatInt4:   return MTLVertexFormatInt4;
    case MDLVertexFormatUInt:   return MTLVertexFormatUInt;
    case MDLVertexFormatUInt2:  return MTLVertexFormatUInt2;
    case MDLVertexFormatUInt3:  return MTLVertexFormatUInt3;
    case MDLVertexFormatUInt4:  return MTLVertexFormatUInt4;
    case MDLVertexFormatShort2: return MTLVertexFormatShort2;
    case MDLVertexFormatShort4: return MTLVertexFormatShort4;
    case MDLVertexFormatUChar4: return MTLVertexFormatUChar4;
    case MDLVertexFormatUChar4Normalized: return MTLVertexFormatUChar4Normalized;
    default: return MTLVertexFormatInvalid;
  }
}

MDLVertexFormat MTKModelIOVertexFormatFromMetal(MTLVertexFormat vertexFormat) {
  switch (vertexFormat) {
    case MTLVertexFormatFloat:  return MDLVertexFormatFloat;
    case MTLVertexFormatFloat2: return MDLVertexFormatFloat2;
    case MTLVertexFormatFloat3: return MDLVertexFormatFloat3;
    case MTLVertexFormatFloat4: return MDLVertexFormatFloat4;
    case MTLVertexFormatHalf2:  return MDLVertexFormatHalf2;
    case MTLVertexFormatHalf4:  return MDLVertexFormatHalf4;
    case MTLVertexFormatInt:    return MDLVertexFormatInt;
    case MTLVertexFormatInt2:   return MDLVertexFormatInt2;
    case MTLVertexFormatInt3:   return MDLVertexFormatInt3;
    case MTLVertexFormatInt4:   return MDLVertexFormatInt4;
    case MTLVertexFormatUInt:   return MDLVertexFormatUInt;
    case MTLVertexFormatUInt2:  return MDLVertexFormatUInt2;
    case MTLVertexFormatUInt3:  return MDLVertexFormatUInt3;
    case MTLVertexFormatUInt4:  return MDLVertexFormatUInt4;
    case MTLVertexFormatShort2: return MDLVertexFormatShort2;
    case MTLVertexFormatShort4: return MDLVertexFormatShort4;
    case MTLVertexFormatUChar4: return MDLVertexFormatUChar4;
    case MTLVertexFormatUChar4Normalized: return MDLVertexFormatUChar4Normalized;
    default: return MDLVertexFormatInvalid;
  }
}

MTLVertexDescriptor *MTKMetalVertexDescriptorFromModelIO(MDLVertexDescriptor *modelIODescriptor) {
  return MTKMetalVertexDescriptorFromModelIOWithError(modelIODescriptor, nil);
}

MTLVertexDescriptor *MTKMetalVertexDescriptorFromModelIOWithError(MDLVertexDescriptor *modelIODescriptor, NSError **error) {
  if (error) *error = nil;
  if (!modelIODescriptor) return nil;
  MTLVertexDescriptor *desc = [MTLVertexDescriptor vertexDescriptor];
  for (NSUInteger i = 0; i < 31; i++) {
    MDLVertexAttribute *attr = [modelIODescriptor.attributes objectAtIndexedSubscript:i];
    if (attr && attr.format != MDLVertexFormatInvalid) {
      desc.attributes[i].format = MTKMetalVertexFormatFromModelIO(attr.format);
      desc.attributes[i].offset = attr.offset;
      desc.attributes[i].bufferIndex = attr.bufferIndex;
    }
    MDLVertexBufferLayout *layout = [modelIODescriptor.layouts objectAtIndexedSubscript:i];
    if (layout && layout.stride > 0) {
      desc.layouts[i].stride = layout.stride;
    }
  }
  return desc;
}

MDLVertexDescriptor *MTKModelIOVertexDescriptorFromMetal(MTLVertexDescriptor *metalDescriptor) {
  return MTKModelIOVertexDescriptorFromMetalWithError(metalDescriptor, nil);
}

MDLVertexDescriptor *MTKModelIOVertexDescriptorFromMetalWithError(MTLVertexDescriptor *metalDescriptor, NSError **error) {
  if (error) *error = nil;
  if (!metalDescriptor) return nil;
  MDLVertexDescriptor *desc = [[[MDLVertexDescriptor alloc] init] autorelease];
  for (NSUInteger i = 0; i < 31; i++) {
    MTLVertexAttributeDescriptor *attr = metalDescriptor.attributes[i];
    if (attr && attr.format != MTLVertexFormatInvalid) {
      MDLVertexAttribute *mattr = [desc.attributes objectAtIndexedSubscript:i];
      mattr.format = MTKModelIOVertexFormatFromMetal(attr.format);
      mattr.offset = attr.offset;
      mattr.bufferIndex = attr.bufferIndex;
    }
    MTLVertexBufferLayoutDescriptor *layout = metalDescriptor.layouts[i];
    if (layout && layout.stride > 0) {
      MDLVertexBufferLayout *mlayout = [desc.layouts objectAtIndexedSubscript:i];
      mlayout.stride = layout.stride;
    }
  }
  return desc;
}

