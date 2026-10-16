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
  NSTimer *_timer;
}

@property (nonatomic, retain) id<MTLDevice> device;
@property (nonatomic, assign) id<MTKViewDelegate> delegate;
@property (nonatomic, readonly) id<CAMetalDrawable> currentDrawable;
@property (nonatomic, readonly) MTLRenderPassDescriptor *currentRenderPassDescriptor;
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
  [_currentRenderPassDescriptor release];
  [super dealloc];
}
@end
