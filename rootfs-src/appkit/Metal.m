/* Metal-lite for xef-osx: MTLDevice, MTLCommandQueue, MTLCommandBuffer, MTLRenderCommandEncoder,
 * MTLRenderPipelineDescriptor, MTLTextureDescriptor, MTLBuffer, MTLTexture, MTLLibrary, etc. */
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

NSString *const MTLDeviceWasAddedNotification = @"MTLDeviceWasAddedNotification";
NSString *const MTLDeviceRemovalRequestedNotification = @"MTLDeviceRemovalRequestedNotification";
NSString *const MTLDeviceWasRemovedNotification = @"MTLDeviceWasRemovedNotification";

/* ------------------------------------------------------------------- Descriptors */

@implementation MTLRenderPipelineColorAttachmentDescriptor {
  MTLPixelFormat _pixelFormat;
  MTLColorWriteMask _writeMask;
  BOOL _blendingEnabled;
  MTLBlendFactor _sourceRGBBlendFactor;
  MTLBlendFactor _destinationRGBBlendFactor;
  MTLBlendOperation _rgbBlendOperation;
  MTLBlendFactor _sourceAlphaBlendFactor;
  MTLBlendFactor _destinationAlphaBlendFactor;
  MTLBlendOperation _alphaBlendOperation;
}
- (id)init {
  if ((self = [super init])) {
    _pixelFormat = MTLPixelFormatInvalid;
    _writeMask = MTLColorWriteMaskAll;
    _blendingEnabled = NO;
    _sourceRGBBlendFactor = MTLBlendFactorOne;
    _destinationRGBBlendFactor = MTLBlendFactorZero;
    _rgbBlendOperation = MTLBlendOperationAdd;
    _sourceAlphaBlendFactor = MTLBlendFactorOne;
    _destinationAlphaBlendFactor = MTLBlendFactorZero;
    _alphaBlendOperation = MTLBlendOperationAdd;
  }
  return self;
}
- (MTLPixelFormat)pixelFormat { return _pixelFormat; } - (void)setPixelFormat:(MTLPixelFormat)f { _pixelFormat = f; }
- (MTLColorWriteMask)writeMask { return _writeMask; } - (void)setWriteMask:(MTLColorWriteMask)m { _writeMask = m; }
- (BOOL)isBlendingEnabled { return _blendingEnabled; } - (void)setBlendingEnabled:(BOOL)b { _blendingEnabled = b; }
- (MTLBlendFactor)sourceRGBBlendFactor { return _sourceRGBBlendFactor; } - (void)setSourceRGBBlendFactor:(MTLBlendFactor)f { _sourceRGBBlendFactor = f; }
- (MTLBlendFactor)destinationRGBBlendFactor { return _destinationRGBBlendFactor; } - (void)setDestinationRGBBlendFactor:(MTLBlendFactor)f { _destinationRGBBlendFactor = f; }
- (MTLBlendOperation)rgbBlendOperation { return _rgbBlendOperation; } - (void)setRgbBlendOperation:(MTLBlendOperation)o { _rgbBlendOperation = o; }
- (MTLBlendFactor)sourceAlphaBlendFactor { return _sourceAlphaBlendFactor; } - (void)setSourceAlphaBlendFactor:(MTLBlendFactor)f { _sourceAlphaBlendFactor = f; }
- (MTLBlendFactor)destinationAlphaBlendFactor { return _destinationAlphaBlendFactor; } - (void)setDestinationAlphaBlendFactor:(MTLBlendFactor)f { _destinationAlphaBlendFactor = f; }
- (MTLBlendOperation)alphaBlendOperation { return _alphaBlendOperation; } - (void)setAlphaBlendOperation:(MTLBlendOperation)o { _alphaBlendOperation = o; }
- (id)copyWithZone:(NSZone *)zone {
  MTLRenderPipelineColorAttachmentDescriptor *copy = [[MTLRenderPipelineColorAttachmentDescriptor allocWithZone:zone] init];
  copy->_pixelFormat = _pixelFormat;
  copy->_writeMask = _writeMask;
  copy->_blendingEnabled = _blendingEnabled;
  copy->_sourceRGBBlendFactor = _sourceRGBBlendFactor;
  copy->_destinationRGBBlendFactor = _destinationRGBBlendFactor;
  copy->_rgbBlendOperation = _rgbBlendOperation;
  copy->_sourceAlphaBlendFactor = _sourceAlphaBlendFactor;
  copy->_destinationAlphaBlendFactor = _destinationAlphaBlendFactor;
  copy->_alphaBlendOperation = _alphaBlendOperation;
  return copy;
}
@end

@implementation MTLRenderPipelineColorAttachmentDescriptorArray {
  MTLRenderPipelineColorAttachmentDescriptor *_descriptors[8];
}
- (id)init {
  if ((self = [super init])) {
    for (int i = 0; i < 8; i++) _descriptors[i] = nil;
  }
  return self;
}
- (MTLRenderPipelineColorAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)idx {
  if (idx >= 8) return nil;
  if (!_descriptors[idx]) _descriptors[idx] = [[MTLRenderPipelineColorAttachmentDescriptor alloc] init];
  return _descriptors[idx];
}
- (void)setObject:(MTLRenderPipelineColorAttachmentDescriptor *)attachment atIndexedSubscript:(NSUInteger)idx {
  if (idx >= 8) return;
  [attachment retain];
  [_descriptors[idx] release];
  _descriptors[idx] = attachment;
}
- (void)dealloc {
  for (int i = 0; i < 8; i++) [_descriptors[i] release];
  [super dealloc];
}
@end

@implementation MTLVertexBufferLayoutDescriptor {
  NSUInteger _stride;
  MTLVertexStepFunction _stepFunction;
  NSUInteger _stepRate;
}
- (NSUInteger)stride { return _stride; } - (void)setStride:(NSUInteger)s { _stride = s; }
- (MTLVertexStepFunction)stepFunction { return _stepFunction; } - (void)setStepFunction:(MTLVertexStepFunction)f { _stepFunction = f; }
- (NSUInteger)stepRate { return _stepRate; } - (void)setStepRate:(NSUInteger)r { _stepRate = r; }
- (id)copyWithZone:(NSZone *)zone {
  MTLVertexBufferLayoutDescriptor *c = [[MTLVertexBufferLayoutDescriptor allocWithZone:zone] init];
  c->_stride = _stride; c->_stepFunction = _stepFunction; c->_stepRate = _stepRate;
  return c;
}
@end

@implementation MTLVertexBufferLayoutDescriptorArray {
  MTLVertexBufferLayoutDescriptor *_layouts[31];
}
- (MTLVertexBufferLayoutDescriptor *)objectAtIndexedSubscript:(NSUInteger)idx {
  if (idx >= 31) return nil;
  if (!_layouts[idx]) _layouts[idx] = [[MTLVertexBufferLayoutDescriptor alloc] init];
  return _layouts[idx];
}
- (void)setObject:(MTLVertexBufferLayoutDescriptor *)layout atIndexedSubscript:(NSUInteger)idx {
  if (idx >= 31) return;
  [layout retain]; [_layouts[idx] release]; _layouts[idx] = layout;
}
- (void)dealloc {
  for (int i = 0; i < 31; i++) [_layouts[i] release];
  [super dealloc];
}
@end

@implementation MTLVertexAttributeDescriptor {
  MTLVertexFormat _format;
  NSUInteger _offset;
  NSUInteger _bufferIndex;
}
- (MTLVertexFormat)format { return _format; } - (void)setFormat:(MTLVertexFormat)f { _format = f; }
- (NSUInteger)offset { return _offset; } - (void)setOffset:(NSUInteger)o { _offset = o; }
- (NSUInteger)bufferIndex { return _bufferIndex; } - (void)setBufferIndex:(NSUInteger)i { _bufferIndex = i; }
- (id)copyWithZone:(NSZone *)zone {
  MTLVertexAttributeDescriptor *c = [[MTLVertexAttributeDescriptor allocWithZone:zone] init];
  c->_format = _format; c->_offset = _offset; c->_bufferIndex = _bufferIndex;
  return c;
}
@end

@implementation MTLVertexAttributeDescriptorArray {
  MTLVertexAttributeDescriptor *_attributes[31];
}
- (MTLVertexAttributeDescriptor *)objectAtIndexedSubscript:(NSUInteger)idx {
  if (idx >= 31) return nil;
  if (!_attributes[idx]) _attributes[idx] = [[MTLVertexAttributeDescriptor alloc] init];
  return _attributes[idx];
}
- (void)setObject:(MTLVertexAttributeDescriptor *)attr atIndexedSubscript:(NSUInteger)idx {
  if (idx >= 31) return;
  [attr retain]; [_attributes[idx] release]; _attributes[idx] = attr;
}
- (void)dealloc {
  for (int i = 0; i < 31; i++) [_attributes[i] release];
  [super dealloc];
}
@end

@implementation MTLVertexDescriptor {
  MTLVertexBufferLayoutDescriptorArray *_layouts;
  MTLVertexAttributeDescriptorArray *_attributes;
}
+ (MTLVertexDescriptor *)vertexDescriptor { return [[[self alloc] init] autorelease]; }
- (id)init {
  if ((self = [super init])) {
    _layouts = [[MTLVertexBufferLayoutDescriptorArray alloc] init];
    _attributes = [[MTLVertexAttributeDescriptorArray alloc] init];
  }
  return self;
}
- (MTLVertexBufferLayoutDescriptorArray *)layouts { return _layouts; }
- (MTLVertexAttributeDescriptorArray *)attributes { return _attributes; }
- (void)reset {
  [_layouts release]; _layouts = [[MTLVertexBufferLayoutDescriptorArray alloc] init];
  [_attributes release]; _attributes = [[MTLVertexAttributeDescriptorArray alloc] init];
}
- (id)copyWithZone:(NSZone *)zone {
  MTLVertexDescriptor *c = [[MTLVertexDescriptor allocWithZone:zone] init];
  return c;
}
- (void)dealloc {
  [_layouts release]; [_attributes release];
  [super dealloc];
}
@end

@implementation MTLRenderPipelineDescriptor {
  NSString *_label;
  id<MTLFunction> _vertexFunction;
  id<MTLFunction> _fragmentFunction;
  MTLVertexDescriptor *_vertexDescriptor;
  MTLRenderPipelineColorAttachmentDescriptorArray *_colorAttachments;
  MTLPixelFormat _depthAttachmentPixelFormat;
  MTLPixelFormat _stencilAttachmentPixelFormat;
  NSUInteger _sampleCount;
  BOOL _rasterizationEnabled;
}
- (id)init {
  if ((self = [super init])) {
    _colorAttachments = [[MTLRenderPipelineColorAttachmentDescriptorArray alloc] init];
    _sampleCount = 1;
    _rasterizationEnabled = YES;
  }
  return self;
}
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (id<MTLFunction>)vertexFunction { return _vertexFunction; } - (void)setVertexFunction:(id<MTLFunction>)f { [f retain]; [(id)_vertexFunction release]; _vertexFunction = f; }
- (id<MTLFunction>)fragmentFunction { return _fragmentFunction; } - (void)setFragmentFunction:(id<MTLFunction>)f { [f retain]; [(id)_fragmentFunction release]; _fragmentFunction = f; }
- (MTLVertexDescriptor *)vertexDescriptor { return _vertexDescriptor; } - (void)setVertexDescriptor:(MTLVertexDescriptor *)d { [d retain]; [_vertexDescriptor release]; _vertexDescriptor = d; }
- (MTLRenderPipelineColorAttachmentDescriptorArray *)colorAttachments { return _colorAttachments; }
- (MTLPixelFormat)depthAttachmentPixelFormat { return _depthAttachmentPixelFormat; } - (void)setDepthAttachmentPixelFormat:(MTLPixelFormat)f { _depthAttachmentPixelFormat = f; }
- (MTLPixelFormat)stencilAttachmentPixelFormat { return _stencilAttachmentPixelFormat; } - (void)setStencilAttachmentPixelFormat:(MTLPixelFormat)f { _stencilAttachmentPixelFormat = f; }
- (NSUInteger)sampleCount { return _sampleCount; } - (void)setSampleCount:(NSUInteger)c { _sampleCount = c; }
- (BOOL)isRasterizationEnabled { return _rasterizationEnabled; } - (void)setRasterizationEnabled:(BOOL)e { _rasterizationEnabled = e; }
- (void)reset {
  [_label release]; _label = nil;
  [(id)_vertexFunction release]; _vertexFunction = nil;
  [(id)_fragmentFunction release]; _fragmentFunction = nil;
  [_vertexDescriptor release]; _vertexDescriptor = nil;
  [_colorAttachments release]; _colorAttachments = [[MTLRenderPipelineColorAttachmentDescriptorArray alloc] init];
  _depthAttachmentPixelFormat = MTLPixelFormatInvalid;
  _stencilAttachmentPixelFormat = MTLPixelFormatInvalid;
  _sampleCount = 1;
  _rasterizationEnabled = YES;
}
- (id)copyWithZone:(NSZone *)zone {
  MTLRenderPipelineDescriptor *c = [[MTLRenderPipelineDescriptor allocWithZone:zone] init];
  c.label = _label;
  c.vertexFunction = _vertexFunction;
  c.fragmentFunction = _fragmentFunction;
  c.vertexDescriptor = _vertexDescriptor;
  c.depthAttachmentPixelFormat = _depthAttachmentPixelFormat;
  c.stencilAttachmentPixelFormat = _stencilAttachmentPixelFormat;
  c.sampleCount = _sampleCount;
  c.rasterizationEnabled = _rasterizationEnabled;
  return c;
}
- (void)dealloc {
  [_label release]; [(id)_vertexFunction release]; [(id)_fragmentFunction release];
  [_vertexDescriptor release]; [_colorAttachments release];
  [super dealloc];
}
@end

@implementation MTLComputePipelineDescriptor {
  NSString *_label;
  id<MTLFunction> _computeFunction;
}
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (id<MTLFunction>)computeFunction { return _computeFunction; } - (void)setComputeFunction:(id<MTLFunction>)f { [f retain]; [(id)_computeFunction release]; _computeFunction = f; }
- (id)copyWithZone:(NSZone *)zone {
  MTLComputePipelineDescriptor *c = [[MTLComputePipelineDescriptor allocWithZone:zone] init];
  c.label = _label; c.computeFunction = _computeFunction;
  return c;
}
- (void)dealloc {
  [_label release]; [(id)_computeFunction release];
  [super dealloc];
}
@end

@implementation MTLStencilDescriptor {
  MTLCompareFunction _stencilCompareFunction;
  MTLStencilOperation _stencilFailureOperation;
  MTLStencilOperation _depthFailureOperation;
  MTLStencilOperation _depthNormalFailureOperation;
  uint32_t _readMask;
  uint32_t _writeMask;
}
- (MTLCompareFunction)stencilCompareFunction { return _stencilCompareFunction; } - (void)setStencilCompareFunction:(MTLCompareFunction)f { _stencilCompareFunction = f; }
- (MTLStencilOperation)stencilFailureOperation { return _stencilFailureOperation; } - (void)setStencilFailureOperation:(MTLStencilOperation)o { _stencilFailureOperation = o; }
- (MTLStencilOperation)depthFailureOperation { return _depthFailureOperation; } - (void)setDepthFailureOperation:(MTLStencilOperation)o { _depthFailureOperation = o; }
- (MTLStencilOperation)depthNormalFailureOperation { return _depthNormalFailureOperation; } - (void)setDepthNormalFailureOperation:(MTLStencilOperation)o { _depthNormalFailureOperation = o; }
- (uint32_t)readMask { return _readMask; } - (void)setReadMask:(uint32_t)m { _readMask = m; }
- (uint32_t)writeMask { return _writeMask; } - (void)setWriteMask:(uint32_t)m { _writeMask = m; }
- (id)copyWithZone:(NSZone *)zone {
  MTLStencilDescriptor *c = [[MTLStencilDescriptor allocWithZone:zone] init];
  c->_stencilCompareFunction = _stencilCompareFunction;
  c->_stencilFailureOperation = _stencilFailureOperation;
  c->_depthFailureOperation = _depthFailureOperation;
  c->_depthNormalFailureOperation = _depthNormalFailureOperation;
  c->_readMask = _readMask; c->_writeMask = _writeMask;
  return c;
}
@end

@implementation MTLDepthStencilDescriptor {
  NSString *_label;
  MTLCompareFunction _depthCompareFunction;
  BOOL _depthWriteEnabled;
  MTLStencilDescriptor *_frontFaceStencil;
  MTLStencilDescriptor *_backFaceStencil;
}
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (MTLCompareFunction)depthCompareFunction { return _depthCompareFunction; } - (void)setDepthCompareFunction:(MTLCompareFunction)f { _depthCompareFunction = f; }
- (BOOL)isDepthWriteEnabled { return _depthWriteEnabled; } - (void)setDepthWriteEnabled:(BOOL)e { _depthWriteEnabled = e; }
- (MTLStencilDescriptor *)frontFaceStencil { return _frontFaceStencil; } - (void)setFrontFaceStencil:(MTLStencilDescriptor *)s { [s retain]; [_frontFaceStencil release]; _frontFaceStencil = s; }
- (MTLStencilDescriptor *)backFaceStencil { return _backFaceStencil; } - (void)setBackFaceStencil:(MTLStencilDescriptor *)s { [s retain]; [_backFaceStencil release]; _backFaceStencil = s; }
- (id)copyWithZone:(NSZone *)zone {
  MTLDepthStencilDescriptor *c = [[MTLDepthStencilDescriptor allocWithZone:zone] init];
  c.label = _label; c.depthCompareFunction = _depthCompareFunction; c.depthWriteEnabled = _depthWriteEnabled;
  c.frontFaceStencil = _frontFaceStencil; c.backFaceStencil = _backFaceStencil;
  return c;
}
- (void)dealloc {
  [_label release]; [_frontFaceStencil release]; [_backFaceStencil release];
  [super dealloc];
}
@end

@implementation MTLSamplerDescriptor {
  NSString *_label;
  MTLSamplerMinMagFilter _minFilter;
  MTLSamplerMinMagFilter _magFilter;
  MTLSamplerMipFilter _mipFilter;
  MTLSamplerAddressMode _sAddressMode;
  MTLSamplerAddressMode _tAddressMode;
  MTLSamplerAddressMode _rAddressMode;
  NSUInteger _maxAnisotropy;
  MTLCompareFunction _compareFunction;
  float _lodMinClamp;
  float _lodMaxClamp;
}
- (id)init {
  if ((self = [super init])) {
    _maxAnisotropy = 1;
    _lodMaxClamp = 1000.0f;
  }
  return self;
}
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (MTLSamplerMinMagFilter)minFilter { return _minFilter; } - (void)setMinFilter:(MTLSamplerMinMagFilter)f { _minFilter = f; }
- (MTLSamplerMinMagFilter)magFilter { return _magFilter; } - (void)setMagFilter:(MTLSamplerMinMagFilter)f { _magFilter = f; }
- (MTLSamplerMipFilter)mipFilter { return _mipFilter; } - (void)setMipFilter:(MTLSamplerMipFilter)f { _mipFilter = f; }
- (MTLSamplerAddressMode)sAddressMode { return _sAddressMode; } - (void)setSAddressMode:(MTLSamplerAddressMode)m { _sAddressMode = m; }
- (MTLSamplerAddressMode)tAddressMode { return _tAddressMode; } - (void)setTAddressMode:(MTLSamplerAddressMode)m { _tAddressMode = m; }
- (MTLSamplerAddressMode)rAddressMode { return _rAddressMode; } - (void)setRAddressMode:(MTLSamplerAddressMode)m { _rAddressMode = m; }
- (NSUInteger)maxAnisotropy { return _maxAnisotropy; } - (void)setMaxAnisotropy:(NSUInteger)a { _maxAnisotropy = a; }
- (MTLCompareFunction)compareFunction { return _compareFunction; } - (void)setCompareFunction:(MTLCompareFunction)f { _compareFunction = f; }
- (float)lodMinClamp { return _lodMinClamp; } - (void)setLodMinClamp:(float)c { _lodMinClamp = c; }
- (float)lodMaxClamp { return _lodMaxClamp; } - (void)setLodMaxClamp:(float)c { _lodMaxClamp = c; }
- (id)copyWithZone:(NSZone *)zone {
  MTLSamplerDescriptor *c = [[MTLSamplerDescriptor allocWithZone:zone] init];
  c.label = _label; c.minFilter = _minFilter; c.magFilter = _magFilter; c.mipFilter = _mipFilter;
  c.sAddressMode = _sAddressMode; c.tAddressMode = _tAddressMode; c.rAddressMode = _rAddressMode;
  c.maxAnisotropy = _maxAnisotropy; c.compareFunction = _compareFunction;
  c.lodMinClamp = _lodMinClamp; c.lodMaxClamp = _lodMaxClamp;
  return c;
}
- (void)dealloc {
  [_label release];
  [super dealloc];
}
@end

@implementation MTLTextureDescriptor {
  MTLTextureType _textureType;
  MTLPixelFormat _pixelFormat;
  NSUInteger _width;
  NSUInteger _height;
  NSUInteger _depth;
  NSUInteger _mipmapLevelCount;
  NSUInteger _sampleCount;
  NSUInteger _arrayLength;
  MTLResourceOptions _resourceOptions;
  MTLCPUCacheMode _cpuCacheMode;
  MTLStorageMode _storageMode;
  MTLTextureUsage _usage;
}
+ (MTLTextureDescriptor *)texture2DDescriptorWithPixelFormat:(MTLPixelFormat)pixelFormat width:(NSUInteger)width height:(NSUInteger)height mipmapped:(BOOL)mipmapped {
  MTLTextureDescriptor *d = [[[self alloc] init] autorelease];
  d->_textureType = MTLTextureType2D;
  d->_pixelFormat = pixelFormat;
  d->_width = width;
  d->_height = height;
  d->_depth = 1;
  d->_mipmapLevelCount = mipmapped ? (NSUInteger)(log2(width > height ? width : height) + 1) : 1;
  d->_sampleCount = 1;
  d->_arrayLength = 1;
  return d;
}
- (id)init {
  if ((self = [super init])) {
    _textureType = MTLTextureType2D;
    _pixelFormat = MTLPixelFormatRGBA8Unorm;
    _width = 1; _height = 1; _depth = 1;
    _mipmapLevelCount = 1; _sampleCount = 1; _arrayLength = 1;
    _usage = MTLTextureUsageShaderRead;
  }
  return self;
}
- (MTLTextureType)textureType { return _textureType; } - (void)setTextureType:(MTLTextureType)t { _textureType = t; }
- (MTLPixelFormat)pixelFormat { return _pixelFormat; } - (void)setPixelFormat:(MTLPixelFormat)p { _pixelFormat = p; }
- (NSUInteger)width { return _width; } - (void)setWidth:(NSUInteger)w { _width = w; }
- (NSUInteger)height { return _height; } - (void)setHeight:(NSUInteger)h { _height = h; }
- (NSUInteger)depth { return _depth; } - (void)setDepth:(NSUInteger)d { _depth = d; }
- (NSUInteger)mipmapLevelCount { return _mipmapLevelCount; } - (void)setMipmapLevelCount:(NSUInteger)c { _mipmapLevelCount = c; }
- (NSUInteger)sampleCount { return _sampleCount; } - (void)setSampleCount:(NSUInteger)s { _sampleCount = s; }
- (NSUInteger)arrayLength { return _arrayLength; } - (void)setArrayLength:(NSUInteger)l { _arrayLength = l; }
- (MTLResourceOptions)resourceOptions { return _resourceOptions; } - (void)setResourceOptions:(MTLResourceOptions)o { _resourceOptions = o; }
- (MTLCPUCacheMode)cpuCacheMode { return _cpuCacheMode; } - (void)setCpuCacheMode:(MTLCPUCacheMode)m { _cpuCacheMode = m; }
- (MTLStorageMode)storageMode { return _storageMode; } - (void)setStorageMode:(MTLStorageMode)m { _storageMode = m; }
- (MTLTextureUsage)usage { return _usage; } - (void)setUsage:(MTLTextureUsage)u { _usage = u; }
- (id)copyWithZone:(NSZone *)zone {
  MTLTextureDescriptor *c = [[MTLTextureDescriptor allocWithZone:zone] init];
  c->_textureType = _textureType; c->_pixelFormat = _pixelFormat;
  c->_width = _width; c->_height = _height; c->_depth = _depth;
  c->_mipmapLevelCount = _mipmapLevelCount; c->_sampleCount = _sampleCount;
  c->_arrayLength = _arrayLength; c->_usage = _usage;
  return c;
}
@end

@implementation MTLRenderPassColorAttachmentDescriptor {
  id<MTLTexture> _texture;
  NSUInteger _level;
  NSUInteger _slice;
  MTLLoadAction _loadAction;
  MTLStoreAction _storeAction;
  MTLClearColor _clearColor;
}
- (id<MTLTexture>)texture { return _texture; } - (void)setTexture:(id<MTLTexture>)t { [t retain]; [(id)_texture release]; _texture = t; }
- (NSUInteger)level { return _level; } - (void)setLevel:(NSUInteger)l { _level = l; }
- (NSUInteger)slice { return _slice; } - (void)setSlice:(NSUInteger)s { _slice = s; }
- (MTLLoadAction)loadAction { return _loadAction; } - (void)setLoadAction:(MTLLoadAction)a { _loadAction = a; }
- (MTLStoreAction)storeAction { return _storeAction; } - (void)setStoreAction:(MTLStoreAction)a { _storeAction = a; }
- (MTLClearColor)clearColor { return _clearColor; } - (void)setClearColor:(MTLClearColor)c { _clearColor = c; }
- (id)copyWithZone:(NSZone *)zone {
  MTLRenderPassColorAttachmentDescriptor *c = [[MTLRenderPassColorAttachmentDescriptor allocWithZone:zone] init];
  c.texture = _texture; c.level = _level; c.slice = _slice;
  c.loadAction = _loadAction; c.storeAction = _storeAction; c.clearColor = _clearColor;
  return c;
}
- (void)dealloc {
  [(id)_texture release];
  [super dealloc];
}
@end

@implementation MTLRenderPassColorAttachmentDescriptorArray {
  MTLRenderPassColorAttachmentDescriptor *_attachments[8];
}
- (MTLRenderPassColorAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)idx {
  if (idx >= 8) return nil;
  if (!_attachments[idx]) _attachments[idx] = [[MTLRenderPassColorAttachmentDescriptor alloc] init];
  return _attachments[idx];
}
- (void)setObject:(MTLRenderPassColorAttachmentDescriptor *)attachment atIndexedSubscript:(NSUInteger)idx {
  if (idx >= 8) return;
  [attachment retain]; [_attachments[idx] release]; _attachments[idx] = attachment;
}
- (void)dealloc {
  for (int i = 0; i < 8; i++) [_attachments[i] release];
  [super dealloc];
}
@end

@implementation MTLRenderPassDepthAttachmentDescriptor {
  id<MTLTexture> _texture;
  MTLLoadAction _loadAction;
  MTLStoreAction _storeAction;
  double _clearDepth;
}
- (id<MTLTexture>)texture { return _texture; } - (void)setTexture:(id<MTLTexture>)t { [t retain]; [(id)_texture release]; _texture = t; }
- (MTLLoadAction)loadAction { return _loadAction; } - (void)setLoadAction:(MTLLoadAction)a { _loadAction = a; }
- (MTLStoreAction)storeAction { return _storeAction; } - (void)setStoreAction:(MTLStoreAction)a { _storeAction = a; }
- (double)clearDepth { return _clearDepth; } - (void)setClearDepth:(double)d { _clearDepth = d; }
- (void)dealloc { [(id)_texture release]; [super dealloc]; }
@end

@implementation MTLRenderPassStencilAttachmentDescriptor {
  id<MTLTexture> _texture;
  MTLLoadAction _loadAction;
  MTLStoreAction _storeAction;
  uint32_t _clearStencil;
}
- (id<MTLTexture>)texture { return _texture; } - (void)setTexture:(id<MTLTexture>)t { [t retain]; [(id)_texture release]; _texture = t; }
- (MTLLoadAction)loadAction { return _loadAction; } - (void)setLoadAction:(MTLLoadAction)a { _loadAction = a; }
- (MTLStoreAction)storeAction { return _storeAction; } - (void)setStoreAction:(MTLStoreAction)a { _storeAction = a; }
- (uint32_t)clearStencil { return _clearStencil; } - (void)setClearStencil:(uint32_t)s { _clearStencil = s; }
- (void)dealloc { [(id)_texture release]; [super dealloc]; }
@end

@implementation MTLRenderPassDescriptor {
  MTLRenderPassColorAttachmentDescriptorArray *_colorAttachments;
  MTLRenderPassDepthAttachmentDescriptor *_depthAttachment;
  MTLRenderPassStencilAttachmentDescriptor *_stencilAttachment;
}
+ (MTLRenderPassDescriptor *)renderPassDescriptor { return [[[self alloc] init] autorelease]; }
- (id)init {
  if ((self = [super init])) {
    _colorAttachments = [[MTLRenderPassColorAttachmentDescriptorArray alloc] init];
    _depthAttachment = [[MTLRenderPassDepthAttachmentDescriptor alloc] init];
    _stencilAttachment = [[MTLRenderPassStencilAttachmentDescriptor alloc] init];
  }
  return self;
}
- (MTLRenderPassColorAttachmentDescriptorArray *)colorAttachments { return _colorAttachments; }
- (MTLRenderPassDepthAttachmentDescriptor *)depthAttachment { return _depthAttachment; } - (void)setDepthAttachment:(MTLRenderPassDepthAttachmentDescriptor *)d { [d retain]; [_depthAttachment release]; _depthAttachment = d; }
- (MTLRenderPassStencilAttachmentDescriptor *)stencilAttachment { return _stencilAttachment; } - (void)setStencilAttachment:(MTLRenderPassStencilAttachmentDescriptor *)s { [s retain]; [_stencilAttachment release]; _stencilAttachment = s; }
- (id)copyWithZone:(NSZone *)zone {
  MTLRenderPassDescriptor *c = [[MTLRenderPassDescriptor allocWithZone:zone] init];
  return c;
}
- (void)dealloc {
  [_colorAttachments release]; [_depthAttachment release]; [_stencilAttachment release];
  [super dealloc];
}
@end

@implementation MTLCompileOptions {
  BOOL _fastMathEnabled;
  MTLLanguageVersion _languageVersion;
  NSDictionary *_preprocessorMacros;
}
- (BOOL)fastMathEnabled { return _fastMathEnabled; } - (void)setFastMathEnabled:(BOOL)e { _fastMathEnabled = e; }
- (MTLLanguageVersion)languageVersion { return _languageVersion; } - (void)setLanguageVersion:(MTLLanguageVersion)v { _languageVersion = v; }
- (NSDictionary *)preprocessorMacros { return _preprocessorMacros; } - (void)setPreprocessorMacros:(NSDictionary *)m { [m retain]; [_preprocessorMacros release]; _preprocessorMacros = m; }
- (id)copyWithZone:(NSZone *)zone {
  MTLCompileOptions *c = [[MTLCompileOptions allocWithZone:zone] init];
  c.fastMathEnabled = _fastMathEnabled; c.languageVersion = _languageVersion; c.preprocessorMacros = _preprocessorMacros;
  return c;
}
- (void)dealloc { [_preprocessorMacros release]; [super dealloc]; }
@end

/* ------------------------------------------------------------------- Resources */

static id metal_stub(id self, SEL _cmd, ...) {
  static NSMutableSet *seen;
  @synchronized ([NSObject class]) {
    if (!seen) seen = [[NSMutableSet alloc] init];
    NSString *k = [NSString stringWithFormat:@"%s %s", class_getName(object_getClass(self)), sel_getName(_cmd)];
    if (![seen containsObject:k]) {
      [seen addObject:k];
      fprintf(stderr, "METAL STUB -[%s %s]\n", class_getName(object_getClass(self)), sel_getName(_cmd));
    }
  }
  return nil;
}

@interface XEFMetalObject : NSObject
@end

@implementation XEFMetalObject
+ (BOOL)resolveInstanceMethod:(SEL)sel {
  const char *n = sel_getName(sel);
  if (n[0] == '_' || !strncmp(n, "respondsTo", 10) || !strncmp(n, "init", 4) || !strncmp(n, "copy", 4) || !strncmp(n, "mutableCopy", 11) || !strncmp(n, "dealloc", 7)) return NO;
  class_addMethod(self, sel, (IMP)metal_stub, "@@:");
  return YES;
}
@end

@interface XEFMetalBuffer : XEFMetalObject <MTLBuffer> {
  void *_data;
  NSUInteger _length;
  MTLResourceOptions _options;
  id<MTLDevice> _device;
  NSString *_label;
}
- (instancetype)initWithLength:(NSUInteger)length options:(MTLResourceOptions)options device:(id<MTLDevice>)device;
- (instancetype)initWithBytes:(const void *)pointer length:(NSUInteger)length options:(MTLResourceOptions)options device:(id<MTLDevice>)device;
@end


@implementation XEFMetalBuffer
- (instancetype)initWithLength:(NSUInteger)length options:(MTLResourceOptions)options device:(id<MTLDevice>)device {
  if ((self = [super init])) {
    _length = length;
    _options = options;
    _device = device;
    _data = calloc(1, length > 0 ? length : 1);
  }
  return self;
}
- (instancetype)initWithBytes:(const void *)pointer length:(NSUInteger)length options:(MTLResourceOptions)options device:(id<MTLDevice>)device {
  if ((self = [super init])) {
    _length = length;
    _options = options;
    _device = device;
    _data = malloc(length > 0 ? length : 1);
    if (pointer && length > 0) memcpy(_data, pointer, length);
  }
  return self;
}
- (void *)contents { return _data; }
- (NSUInteger)length { return _length; }
- (void)didModifyRange:(NSRange)range {}
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (MTLStorageMode)storageMode {
  return (MTLStorageMode)((_options >> MTLResourceStorageModeShift) & 0xf);
}
- (MTLCPUCacheMode)cpuCacheMode {
  return (MTLCPUCacheMode)((_options >> MTLResourceCPUCacheModeShift) & 0xf);
}
- (MTLHazardTrackingMode)hazardTrackingMode {
  return (MTLHazardTrackingMode)((_options >> MTLResourceHazardTrackingModeShift) & 0x3);
}
- (MTLResourceOptions)resourceOptions { return _options; }
- (MTLPurgeableState)setPurgeableState:(MTLPurgeableState)state { return MTLPurgeableStateNonVolatile; }
- (void)makeAliasable {}
- (BOOL)isAliasable { return NO; }
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor offset:(NSUInteger)offset bytesPerRow:(NSUInteger)bytesPerRow {
  return [_device newTextureWithDescriptor:descriptor];
}
- (void)addDebugMarker:(NSString *)marker range:(NSRange)range {}
- (void)removeAllDebugMarkers {}
- (void)dealloc {
  if (_data) free(_data);
  [_label release];
  [super dealloc];
}
@end

@interface XEFMetalTexture : XEFMetalObject <MTLTexture> {
  NSUInteger _width, _height, _depth;
  MTLPixelFormat _pixelFormat;
  MTLTextureType _textureType;
  MTLTextureUsage _usage;
  id<MTLDevice> _device;
  void *_data;
  size_t _dataSize;
}
- (instancetype)initWithDescriptor:(MTLTextureDescriptor *)desc device:(id<MTLDevice>)device;
@end

@implementation XEFMetalTexture
- (instancetype)initWithDescriptor:(MTLTextureDescriptor *)desc device:(id<MTLDevice>)device {
  if ((self = [super init])) {
    _width = desc.width; _height = desc.height; _depth = desc.depth;
    _pixelFormat = desc.pixelFormat; _textureType = desc.textureType;
    _usage = desc.usage; _device = device;
    _dataSize = _width * _height * 4;
    _data = calloc(1, _dataSize > 0 ? _dataSize : 1);
  }
  return self;
}
- (NSUInteger)width { return _width; }
- (NSUInteger)height { return _height; }
- (NSUInteger)depth { return _depth; }
- (MTLPixelFormat)pixelFormat { return _pixelFormat; }
- (MTLTextureType)textureType { return _textureType; }
- (MTLTextureUsage)usage { return _usage; }
- (id<MTLDevice>)device { return _device; }
- (void)replaceRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level withBytes:(const void *)pixelBytes bytesPerRow:(NSUInteger)bytesPerRow {
  if (_data && pixelBytes) {
    size_t copySize = region.size.height * bytesPerRow;
    if (copySize > _dataSize) copySize = _dataSize;
    memcpy(_data, pixelBytes, copySize);
  }
}
- (void)getBytes:(void *)pixelBytes bytesPerRow:(NSUInteger)bytesPerRow fromRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level {
  if (_data && pixelBytes) {
    size_t copySize = region.size.height * bytesPerRow;
    if (copySize > _dataSize) copySize = _dataSize;
    memcpy(pixelBytes, _data, copySize);
  }
}
- (void)dealloc {
  if (_data) free(_data);
  [super dealloc];
}
@end

@interface XEFMetalSamplerState : XEFMetalObject <MTLSamplerState>
@property(readonly) id<MTLDevice> device;
@property(readonly) NSString *label;
@end
@implementation XEFMetalSamplerState
@synthesize device = _device, label = _label;
@end

@interface XEFMetalDepthStencilState : XEFMetalObject <MTLDepthStencilState>
@property(readonly) id<MTLDevice> device;
@property(readonly) NSString *label;
@end
@implementation XEFMetalDepthStencilState
@synthesize device = _device, label = _label;
@end

@interface XEFMetalFunction : XEFMetalObject <MTLFunction> {
  NSString *_name;
  MTLFunctionType _functionType;
  id<MTLDevice> _device;
}
@property(readonly) NSString *name;
@property(readonly) MTLFunctionType functionType;
@property(readonly) id<MTLDevice> device;
@end
@implementation XEFMetalFunction
- (instancetype)initWithName:(NSString *)name type:(MTLFunctionType)type device:(id<MTLDevice>)device {
  if ((self = [super init])) {
    _name = [name copy]; _functionType = type; _device = device;
  }
  return self;
}
- (NSString *)name { return _name; }
- (MTLFunctionType)functionType { return _functionType; }
- (id<MTLDevice>)device { return _device; }
- (void)dealloc { [_name release]; [super dealloc]; }
@end

@interface XEFMetalLibrary : XEFMetalObject <MTLLibrary> {
  id<MTLDevice> _device;
  NSMutableDictionary *_functions;
}
@end
@implementation XEFMetalLibrary
- (instancetype)initWithDevice:(id<MTLDevice>)device {
  if ((self = [super init])) {
    _device = device;
    _functions = [[NSMutableDictionary alloc] init];
  }
  return self;
}
- (id<MTLDevice>)device { return _device; }
- (id<MTLFunction>)newFunctionWithName:(NSString *)functionName {
  if (!functionName) return nil;
  XEFMetalFunction *f = [_functions objectForKey:functionName];
  if (!f) {
    f = [[[XEFMetalFunction alloc] initWithName:functionName type:MTLFunctionTypeVertex device:_device] autorelease];
    [_functions setObject:f forKey:functionName];
  }
  return [f retain];
}
- (NSArray<NSString *> *)functionNames { return [_functions allKeys]; }
- (void)dealloc { [_functions release]; [super dealloc]; }
@end

@interface XEFMetalRenderPipelineState : XEFMetalObject <MTLRenderPipelineState> {
  id<MTLDevice> _device;
  NSString *_label;
}
@end
@implementation XEFMetalRenderPipelineState
- (instancetype)initWithDevice:(id<MTLDevice>)device label:(NSString *)label {
  if ((self = [super init])) { _device = device; _label = [label copy]; }
  return self;
}
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; }
- (void)dealloc { [_label release]; [super dealloc]; }
@end

@interface XEFMetalComputePipelineState : XEFMetalObject <MTLComputePipelineState> {
  id<MTLDevice> _device;
  NSString *_label;
}
@end
@implementation XEFMetalComputePipelineState
- (instancetype)initWithDevice:(id<MTLDevice>)device label:(NSString *)label {
  if ((self = [super init])) { _device = device; _label = [label copy]; }
  return self;
}
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; }
- (NSUInteger)maxTotalThreadsPerThreadgroup { return 1024; }
- (NSUInteger)threadExecutionWidth { return 32; }
- (void)dealloc { [_label release]; [super dealloc]; }
@end

/* ------------------------------------------------------------------- Command Encoders */

@interface XEFMetalRenderCommandEncoder : XEFMetalObject <MTLRenderCommandEncoder>
@end
@implementation XEFMetalRenderCommandEncoder
- (id<MTLDevice>)device { return nil; }
- (NSString *)label { return nil; } - (void)setLabel:(NSString *)l {}
- (void)setRenderPipelineState:(id<MTLRenderPipelineState>)pipelineState {}
- (void)setVertexBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index {}
- (void)setVertexBuffers:(const id<MTLBuffer> *)buffers offsets:(const NSUInteger *)offsets withRange:(NSRange)range {}
- (void)setVertexBufferOffset:(NSUInteger)offset atIndex:(NSUInteger)index {}
- (void)setVertexBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index {}
- (void)setVertexSamplerState:(id<MTLSamplerState>)sampler atIndex:(NSUInteger)index {}
- (void)setVertexTexture:(id<MTLTexture>)texture atIndex:(NSUInteger)index {}
- (void)setFragmentBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index {}
- (void)setFragmentBuffers:(const id<MTLBuffer> *)buffers offsets:(const NSUInteger *)offsets withRange:(NSRange)range {}
- (void)setFragmentBufferOffset:(NSUInteger)offset atIndex:(NSUInteger)index {}
- (void)setFragmentBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index {}
- (void)setFragmentSamplerState:(id<MTLSamplerState>)sampler atIndex:(NSUInteger)index {}
- (void)setFragmentTexture:(id<MTLTexture>)texture atIndex:(NSUInteger)index {}
- (void)setViewport:(MTLViewport)viewport {}
- (void)setViewports:(const MTLViewport *)viewports count:(NSUInteger)count {}
- (void)setScissorRect:(MTLScissorRect)rect {}
- (void)setScissorRects:(const MTLScissorRect *)scissorRects count:(NSUInteger)count {}
- (void)setCullMode:(MTLCullMode)cullMode {}
- (void)setFrontFacingWinding:(MTLWinding)frontFacingWinding {}
- (void)setDepthStencilState:(id<MTLDepthStencilState>)depthStencilState {}
- (void)setBlendColorRed:(float)red green:(float)green blue:(float)blue alpha:(float)alpha {}
- (void)setStencilReferenceValue:(uint32_t)val {}

- (void)setTriangleFillMode:(MTLTriangleFillMode)fillMode {}
- (void)setDepthClipMode:(MTLDepthClipMode)clipMode {}
- (void)setDepthBias:(float)bias slopeScale:(float)slope clamp:(float)clamp {}
- (void)setFragmentSamplerStates:(const id<MTLSamplerState> *)samplers withRange:(NSRange)range {}
- (void)setFragmentTextures:(const id<MTLTexture> *)textures withRange:(NSRange)range {}
- (void)drawPrimitives:(MTLPrimitiveType)primitiveType vertexStart:(NSUInteger)vertexStart vertexCount:(NSUInteger)vertexCount {}
- (void)drawPrimitives:(MTLPrimitiveType)primitiveType vertexStart:(NSUInteger)vertexStart vertexCount:(NSUInteger)vertexCount instanceCount:(NSUInteger)instanceCount {}
- (void)drawPrimitives:(MTLPrimitiveType)primitiveType vertexStart:(NSUInteger)vertexStart vertexCount:(NSUInteger)vertexCount instanceCount:(NSUInteger)instanceCount baseInstance:(NSUInteger)baseInstance {}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount indexType:(MTLIndexType)indexType indexBuffer:(id<MTLBuffer>)indexBuffer indexBufferOffset:(NSUInteger)indexBufferOffset {}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount indexType:(MTLIndexType)indexType indexBuffer:(id<MTLBuffer>)indexBuffer indexBufferOffset:(NSUInteger)indexBufferOffset instanceCount:(NSUInteger)instanceCount {}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount indexType:(MTLIndexType)indexType indexBuffer:(id<MTLBuffer>)indexBuffer indexBufferOffset:(NSUInteger)indexBufferOffset instanceCount:(NSUInteger)instanceCount baseVertex:(NSInteger)baseVertex baseInstance:(NSUInteger)baseInstance {}
- (void)endEncoding {}
@end


@interface XEFMetalComputeCommandEncoder : XEFMetalObject <MTLComputeCommandEncoder>
@end
@implementation XEFMetalComputeCommandEncoder
- (void)setComputePipelineState:(id<MTLComputePipelineState>)state {}
- (void)setBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index {}
- (void)setBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index {}
- (void)setTexture:(id<MTLTexture>)texture atIndex:(NSUInteger)index {}
- (void)setSamplerState:(id<MTLSamplerState>)sampler atIndex:(NSUInteger)index {}
- (void)dispatchThreads:(MTLSize)threadsPerGrid threadsPerThreadgroup:(MTLSize)threadsPerThreadgroup {}
- (void)dispatchThreadgroups:(MTLSize)threadgroupsPerGrid threadsPerThreadgroup:(MTLSize)threadsPerThreadgroup {}
- (void)endEncoding {}
@end

@interface XEFMetalBlitCommandEncoder : XEFMetalObject <MTLBlitCommandEncoder>
@end
@implementation XEFMetalBlitCommandEncoder
- (void)copyFromBuffer:(id<MTLBuffer>)sourceBuffer sourceOffset:(NSUInteger)sourceOffset toBuffer:(id<MTLBuffer>)destinationBuffer destinationOffset:(NSUInteger)destinationOffset size:(NSUInteger)size {
  if (sourceBuffer && destinationBuffer) {
    memcpy((uint8_t *)[destinationBuffer contents] + destinationOffset,
           (const uint8_t *)[sourceBuffer contents] + sourceOffset,
           size);
  }
}
- (void)copyFromBuffer:(id<MTLBuffer>)sourceBuffer sourceOffset:(NSUInteger)sourceOffset sourceBytesPerRow:(NSUInteger)sourceBytesPerRow sourceBytesPerImage:(NSUInteger)sourceBytesPerImage sourceSize:(MTLSize)sourceSize toTexture:(id<MTLTexture>)destinationTexture destinationSlice:(NSUInteger)destinationSlice destinationLevel:(NSUInteger)destinationLevel destinationOrigin:(MTLOrigin)destinationOrigin {
  if (sourceBuffer && destinationTexture) {
    const uint8_t *src = (const uint8_t *)[sourceBuffer contents] + sourceOffset;
    MTLRegion region = MTLRegionMake2D(destinationOrigin.x, destinationOrigin.y, sourceSize.width, sourceSize.height);
    [destinationTexture replaceRegion:region mipmapLevel:destinationLevel withBytes:src bytesPerRow:sourceBytesPerRow];
  }
}
- (void)copyFromTexture:(id<MTLTexture>)sourceTexture sourceSlice:(NSUInteger)sourceSlice sourceLevel:(NSUInteger)sourceLevel sourceOrigin:(MTLOrigin)sourceOrigin sourceSize:(MTLSize)sourceSize toBuffer:(id<MTLBuffer>)destinationBuffer destinationOffset:(NSUInteger)destinationOffset destinationBytesPerRow:(NSUInteger)destinationBytesPerRow destinationBytesPerImage:(NSUInteger)destinationBytesPerImage {
  if (sourceTexture && destinationBuffer) {
    uint8_t *dst = (uint8_t *)[destinationBuffer contents] + destinationOffset;
    MTLRegion region = MTLRegionMake2D(sourceOrigin.x, sourceOrigin.y, sourceSize.width, sourceSize.height);
    [sourceTexture getBytes:dst bytesPerRow:destinationBytesPerRow fromRegion:region mipmapLevel:sourceLevel];
  }
}
- (void)copyFromTexture:(id<MTLTexture>)sourceTexture sourceSlice:(NSUInteger)sourceSlice sourceLevel:(NSUInteger)sourceLevel sourceOrigin:(MTLOrigin)sourceOrigin sourceSize:(MTLSize)sourceSize toTexture:(id<MTLTexture>)destinationTexture destinationSlice:(NSUInteger)destinationSlice destinationLevel:(NSUInteger)destinationLevel destinationOrigin:(MTLOrigin)destinationOrigin {}
- (void)generateMipmapsForTexture:(id<MTLTexture>)texture {}
- (void)fillBuffer:(id<MTLBuffer>)buffer range:(NSRange)range value:(uint8_t)value {
  if (buffer) {
    memset((uint8_t *)[buffer contents] + range.location, value, range.length);
  }
}
- (void)endEncoding {}
@end

@interface XEFMetalCommandBuffer : XEFMetalObject <MTLCommandBuffer> {
  id<MTLCommandQueue> _commandQueue;
  MTLCommandBufferStatus _status;
}
@end
@implementation XEFMetalCommandBuffer
- (instancetype)initWithQueue:(id<MTLCommandQueue>)queue {
  if ((self = [super init])) { _commandQueue = queue; _status = MTLCommandBufferStatusNotEnqueued; }
  return self;
}
- (id<MTLCommandQueue>)commandQueue { return _commandQueue; }
- (id<MTLDevice>)device { return _commandQueue.device; }
- (MTLCommandBufferStatus)status { return _status; }
- (id<MTLRenderCommandEncoder>)renderCommandEncoderWithDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor {
  return [[[XEFMetalRenderCommandEncoder alloc] init] autorelease];
}
- (id<MTLComputeCommandEncoder>)computeCommandEncoder {
  return [[[XEFMetalComputeCommandEncoder alloc] init] autorelease];
}
- (id<MTLBlitCommandEncoder>)blitCommandEncoder {
  return [[[XEFMetalBlitCommandEncoder alloc] init] autorelease];
}
- (void)presentDrawable:(id<MTLDrawable>)drawable {
  if (drawable) [drawable present];
}
- (void)commit { _status = MTLCommandBufferStatusCompleted; }
- (void)waitUntilCompleted { _status = MTLCommandBufferStatusCompleted; }
- (void)waitUntilScheduled {}
- (void)addCompletedHandler:(MTLCommandBufferHandler)block {
  if (block) block(self);
}
- (void)addScheduledHandler:(MTLCommandBufferHandler)block {
  if (block) block(self);
}
@end

@interface XEFMetalCommandQueue : XEFMetalObject <MTLCommandQueue> {
  id<MTLDevice> _device;
  NSString *_label;
}
- (instancetype)initWithDevice:(id<MTLDevice>)device;
@end
@implementation XEFMetalCommandQueue
- (instancetype)initWithDevice:(id<MTLDevice>)device {
  if ((self = [super init])) { _device = device; }
  return self;
}
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (id<MTLCommandBuffer>)commandBuffer {
  return [[[XEFMetalCommandBuffer alloc] initWithQueue:self] autorelease];
}
- (id<MTLCommandBuffer>)commandBufferWithUnretainedReferences {
  return [[[XEFMetalCommandBuffer alloc] initWithQueue:self] autorelease];
}
- (void)dealloc { [_label release]; [super dealloc]; }
@end

/* ------------------------------------------------------------------- Device */

@interface XEFMetalDevice : XEFMetalObject <MTLDevice>

+ (XEFMetalDevice *)sharedDevice;
@end

@implementation XEFMetalDevice

+ (XEFMetalDevice *)sharedDevice {
  static XEFMetalDevice *s_dev = nil;
  if (!s_dev) s_dev = [[XEFMetalDevice alloc] init];
  return s_dev;
}

- (NSString *)name { return @"Apple M1 (XEF Metal/Vulkan Bridge)"; }

- (BOOL)supportsFamily:(MTLGPUFamily)gpuFamily {
  /* Return YES for Apple1-8, Mac1-2, Common1-3 to satisfy SDL_GPU, MoltenVK, and games */
  return YES;
}

- (BOOL)supportsFeatureSet:(MTLFeatureSet)featureSet {
  return YES;
}

- (BOOL)hasUnifiedMemory { return YES; }

- (MTLSize)maxThreadsPerThreadgroup {
  return MTLSizeMake(1024, 1024, 64);
}

- (id<MTLCommandQueue>)newCommandQueue {
  return [[XEFMetalCommandQueue alloc] initWithDevice:self];
}

- (id<MTLCommandQueue>)newCommandQueueWithMaxCommandBufferCount:(NSUInteger)maxCommandBufferCount {
  return [[XEFMetalCommandQueue alloc] initWithDevice:self];
}

- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options {
  return [[XEFMetalBuffer alloc] initWithLength:length options:options device:self];
}

- (id<MTLBuffer>)newBufferWithBytes:(const void *)pointer length:(NSUInteger)length options:(MTLResourceOptions)options {
  return [[XEFMetalBuffer alloc] initWithBytes:pointer length:length options:options device:self];
}

- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor {
  return [[XEFMetalTexture alloc] initWithDescriptor:descriptor device:self];
}

- (id<MTLSamplerState>)newSamplerStateWithDescriptor:(MTLSamplerDescriptor *)descriptor {
  XEFMetalSamplerState *s = [[XEFMetalSamplerState alloc] init];
  return s;
}

- (id<MTLDepthStencilState>)newDepthStencilStateWithDescriptor:(MTLDepthStencilDescriptor *)descriptor {
  XEFMetalDepthStencilState *d = [[XEFMetalDepthStencilState alloc] init];
  return d;
}

- (id<MTLRenderPipelineState>)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)descriptor error:(NSError **)error {
  return [[XEFMetalRenderPipelineState alloc] initWithDevice:self label:descriptor.label];
}

- (id<MTLComputePipelineState>)newComputePipelineStateWithDescriptor:(MTLComputePipelineDescriptor *)descriptor options:(MTLPipelineOption)options reflection:(MTLAutoreleasedComputePipelineReflection *)reflection error:(NSError **)error {
  return [[XEFMetalComputePipelineState alloc] initWithDevice:self label:descriptor.label];
}

- (id<MTLComputePipelineState>)newComputePipelineStateWithFunction:(id<MTLFunction>)computeFunction error:(NSError **)error {
  return [[XEFMetalComputePipelineState alloc] initWithDevice:self label:computeFunction.name];
}

- (id<MTLLibrary>)newDefaultLibrary {
  return [[XEFMetalLibrary alloc] initWithDevice:self];
}

- (id<MTLLibrary>)newLibraryWithSource:(NSString *)source options:(MTLCompileOptions *)options error:(NSError **)error {
  return [[XEFMetalLibrary alloc] initWithDevice:self];
}

- (id<MTLLibrary>)newLibraryWithData:(dispatch_data_t)data error:(NSError **)error {
  return [[XEFMetalLibrary alloc] initWithDevice:self];
}

- (id<MTLLibrary>)newLibraryWithURL:(NSURL *)url error:(NSError **)error {
  return [[XEFMetalLibrary alloc] initWithDevice:self];
}

@end

/* ------------------------------------------------------------------- Public C API */

id<MTLDevice> MTLCreateSystemDefaultDevice(void) {
  return [[XEFMetalDevice sharedDevice] retain];
}

NSArray<id<MTLDevice>> *MTLCopyAllDevices(void) {
  return [[NSArray alloc] initWithObjects:[XEFMetalDevice sharedDevice], nil];
}

NSArray<id<MTLDevice>> *MTLCopyAllDevicesWithObserver(id<NSObject> *observer, MTLDeviceNotificationHandler handler) {
  if (observer) *observer = [NSObject new];
  return MTLCopyAllDevices();
}

void MTLRemoveDeviceObserver(id<NSObject> observer) {
  [observer release];
}
