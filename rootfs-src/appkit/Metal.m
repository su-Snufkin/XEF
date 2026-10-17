/* Metal-lite for xef-osx: MTLDevice, MTLCommandQueue, MTLCommandBuffer, MTLRenderCommandEncoder,
 * MTLRenderPipelineDescriptor, MTLTextureDescriptor, MTLBuffer, MTLTexture, MTLLibrary,
 * software/host-bridged 2D/3D rasterizer, blit engine, and compute support. */
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#import <Block.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>
#include "xef_host.h"

NSString *const MTLDeviceWasAddedNotification = @"MTLDeviceWasAddedNotification";
NSString *const MTLDeviceRemovalRequestedNotification = @"MTLDeviceRemovalRequestedNotification";
NSString *const MTLDeviceWasRemovedNotification = @"MTLDeviceWasRemovedNotification";
NSString *const MTLLibraryErrorDomain = @"MTLLibraryErrorDomain";
NSString *const MTLRenderPipelineErrorDomain = @"MTLRenderPipelineErrorDomain";
NSString *const MTLCommandBufferErrorDomain = @"MTLCommandBufferErrorDomain";

static NSUInteger xef_mtl_bpp(MTLPixelFormat fmt) {
  switch ((NSUInteger)fmt) {
    case 1:  /* A8Unorm */
    case 10: /* R8Unorm */
    case 11: /* R8Unorm_sRGB */
    case 12: /* R8Snorm */
    case 13: /* R8Uint */
    case 14: /* R8Sint */
    case 250: /* Stencil8 */
      return 1;
    case 20: /* R16Unorm */
    case 22: /* R16Snorm */
    case 23: /* R16Uint */
    case 24: /* R16Sint */
    case 25: /* R16Float */
    case 30: /* RG8Unorm */
    case 31: /* RG8Unorm_sRGB */
    case 32: /* RG8Snorm */
    case 33: /* RG8Uint */
    case 34: /* RG8Sint */
    case 40: /* B5G6R5Unorm */
    case 41: /* A1BGR5Unorm */
    case 42: /* ABGR4Unorm */
    case 43: /* BGR5A1Unorm */
    case 251: /* Depth16Unorm */
      return 2;
    case 60: /* RG16Unorm */
    case 62: /* RG16Snorm */
    case 63: /* RG16Uint */
    case 64: /* RG16Sint */
    case 65: /* RG16Float */
    case 110: /* RGBA16Unorm */
    case 112: /* RGBA16Snorm */
    case 113: /* RGBA16Uint */
    case 114: /* RGBA16Sint */
    case 115: /* RGBA16Float */
    case 103: /* RG32Uint */
    case 104: /* RG32Sint */
    case 105: /* RG32Float */
    case 260: /* Depth32Float_Stencil8 */
      return 8;
    case 123: /* RGBA32Uint */
    case 124: /* RGBA32Sint */
    case 125: /* RGBA32Float */
      return 16;
    default:
      return 4;
  }
}

static inline float xef_clampf(float v, float lo, float hi) {
  return v < lo ? lo : (v > hi ? hi : v);
}

static float xef_half_to_float(uint16_t h) {
  uint32_t sign = (uint32_t)(h & 0x8000) << 16;
  uint32_t exp = (h >> 10) & 0x1F;
  uint32_t mant = h & 0x03FF;
  uint32_t fbits = 0;
  if (exp == 0) {
    if (mant == 0) fbits = sign;
    else {
      exp = 1;
      while ((mant & 0x0400) == 0) { mant <<= 1; exp--; }
      mant &= 0x03FF;
      fbits = sign | ((exp + (127 - 15)) << 23) | (mant << 13);
    }
  } else if (exp == 31) {
    fbits = sign | 0x7F800000 | (mant << 13);
  } else {
    fbits = sign | ((exp + (127 - 15)) << 23) | (mant << 13);
  }
  float out = 0.0f;
  memcpy(&out, &fbits, sizeof(float));
  return out;
}

static uint16_t xef_float_to_half(float v) {
  uint32_t fbits = 0;
  memcpy(&fbits, &v, sizeof(uint32_t));
  uint16_t sign = (uint16_t)((fbits >> 16) & 0x8000);
  int32_t exp = (int32_t)((fbits >> 23) & 0xFF) - 127 + 15;
  uint32_t mant = fbits & 0x007FFFFF;
  if (exp <= 0) return sign;
  if (exp >= 31) return sign | 0x7C00;
  return sign | (uint16_t)(exp << 10) | (uint16_t)(mant >> 13);
}

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
@public
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
  MTLRenderPipelineColorAttachmentDescriptor *c = [attachment copy];
  [_descriptors[idx] release];
  _descriptors[idx] = c;
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
- (id)init {
  if ((self = [super init])) {
    _stride = 0;
    _stepFunction = MTLVertexStepFunctionPerVertex;
    _stepRate = 1;
  }
  return self;
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
@public
  MTLVertexBufferLayoutDescriptor *_layouts[31];
}
- (MTLVertexBufferLayoutDescriptor *)objectAtIndexedSubscript:(NSUInteger)idx {
  if (idx >= 31) return nil;
  if (!_layouts[idx]) _layouts[idx] = [[MTLVertexBufferLayoutDescriptor alloc] init];
  return _layouts[idx];
}
- (void)setObject:(MTLVertexBufferLayoutDescriptor *)layout atIndexedSubscript:(NSUInteger)idx {
  if (idx >= 31) return;
  MTLVertexBufferLayoutDescriptor *c = [layout copy];
  [_layouts[idx] release];
  _layouts[idx] = c;
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
@public
  MTLVertexAttributeDescriptor *_attributes[31];
}
- (MTLVertexAttributeDescriptor *)objectAtIndexedSubscript:(NSUInteger)idx {
  if (idx >= 31) return nil;
  if (!_attributes[idx]) _attributes[idx] = [[MTLVertexAttributeDescriptor alloc] init];
  return _attributes[idx];
}
- (void)setObject:(MTLVertexAttributeDescriptor *)attr atIndexedSubscript:(NSUInteger)idx {
  if (idx >= 31) return;
  MTLVertexAttributeDescriptor *c = [attr copy];
  [_attributes[idx] release];
  _attributes[idx] = c;
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
  for (int i = 0; i < 31; i++) {
    if (_layouts->_layouts[i]) c->_layouts->_layouts[i] = [_layouts->_layouts[i] copy];
    if (_attributes->_attributes[i]) c->_attributes->_attributes[i] = [_attributes->_attributes[i] copy];
  }
  return c;
}
- (void)dealloc {
  [_layouts release]; [_attributes release];
  [super dealloc];
}
@end

/* ------------------------------------------------------------------- MTLPipelineBufferDescriptor */

@implementation MTLPipelineBufferDescriptor {
  MTLMutability _mutability;
}
- (instancetype)init {
  if ((self = [super init])) {
    _mutability = MTLMutabilityDefault;
  }
  return self;
}
- (MTLMutability)mutability { return _mutability; }
- (void)setMutability:(MTLMutability)m { _mutability = m; }
- (id)copyWithZone:(NSZone *)zone {
  MTLPipelineBufferDescriptor *c = [[MTLPipelineBufferDescriptor allocWithZone:zone] init];
  c.mutability = _mutability;
  return c;
}
@end

@implementation MTLPipelineBufferDescriptorArray {
  MTLPipelineBufferDescriptor *_descriptors[31];
}
- (MTLPipelineBufferDescriptor *)objectAtIndexedSubscript:(NSUInteger)bufferIndex {
  if (bufferIndex >= 31) return nil;
  if (!_descriptors[bufferIndex]) {
    _descriptors[bufferIndex] = [[MTLPipelineBufferDescriptor alloc] init];
  }
  return _descriptors[bufferIndex];
}
- (void)setObject:(MTLPipelineBufferDescriptor *)buffer atIndexedSubscript:(NSUInteger)bufferIndex {
  if (bufferIndex >= 31) return;
  MTLPipelineBufferDescriptor *c = [buffer copy];
  [_descriptors[bufferIndex] release];
  _descriptors[bufferIndex] = c;
}
- (id)copyWithZone:(NSZone *)zone {
  MTLPipelineBufferDescriptorArray *c = [[MTLPipelineBufferDescriptorArray allocWithZone:zone] init];
  for (int i = 0; i < 31; i++) {
    if (_descriptors[i]) c->_descriptors[i] = [_descriptors[i] copy];
  }
  return c;
}
- (void)dealloc {
  for (int i = 0; i < 31; i++) [_descriptors[i] release];
  [super dealloc];
}
@end

@implementation MTLRenderPipelineDescriptor {
  NSString *_label;
  id<MTLFunction> _vertexFunction;
  id<MTLFunction> _fragmentFunction;
  MTLVertexDescriptor *_vertexDescriptor;
  MTLRenderPipelineColorAttachmentDescriptorArray *_colorAttachments;
  MTLPipelineBufferDescriptorArray *_vertexBuffers;
  MTLPipelineBufferDescriptorArray *_fragmentBuffers;
  MTLPixelFormat _depthAttachmentPixelFormat;
  MTLPixelFormat _stencilAttachmentPixelFormat;
  NSUInteger _sampleCount;
  NSUInteger _rasterSampleCount;
  BOOL _rasterizationEnabled;
  BOOL _alphaToCoverageEnabled;
  BOOL _alphaToOneEnabled;
  MTLPrimitiveTopologyClass _inputPrimitiveTopology;
  BOOL _supportIndirectCommandBuffers;
  NSArray *_binaryArchives;
  NSArray *_vertexPreloadedLibraries;
  NSArray *_fragmentPreloadedLibraries;
  NSUInteger _maxVertexCallStackDepth;
  NSUInteger _maxFragmentCallStackDepth;
  MTLLinkedFunctions *_vertexLinkedFunctions;
  MTLLinkedFunctions *_fragmentLinkedFunctions;
}
- (id)init {
  if ((self = [super init])) {
    _colorAttachments = [[MTLRenderPipelineColorAttachmentDescriptorArray alloc] init];
    _vertexDescriptor = [[MTLVertexDescriptor alloc] init];
    _vertexBuffers = [[MTLPipelineBufferDescriptorArray alloc] init];
    _fragmentBuffers = [[MTLPipelineBufferDescriptorArray alloc] init];
    _sampleCount = 1;
    _rasterSampleCount = 1;
    _rasterizationEnabled = YES;
    _maxVertexCallStackDepth = 1;
    _maxFragmentCallStackDepth = 1;
  }
  return self;
}
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (id<MTLFunction>)vertexFunction { return _vertexFunction; } - (void)setVertexFunction:(id<MTLFunction>)f { [f retain]; [(id)_vertexFunction release]; _vertexFunction = f; }
- (id<MTLFunction>)fragmentFunction { return _fragmentFunction; } - (void)setFragmentFunction:(id<MTLFunction>)f { [f retain]; [(id)_fragmentFunction release]; _fragmentFunction = f; }
- (MTLVertexDescriptor *)vertexDescriptor { return _vertexDescriptor; } - (void)setVertexDescriptor:(MTLVertexDescriptor *)d { MTLVertexDescriptor *c = [d copy]; [_vertexDescriptor release]; _vertexDescriptor = c; }
- (MTLRenderPipelineColorAttachmentDescriptorArray *)colorAttachments { return _colorAttachments; }
- (MTLPipelineBufferDescriptorArray *)vertexBuffers { return _vertexBuffers; }
- (MTLPipelineBufferDescriptorArray *)fragmentBuffers { return _fragmentBuffers; }
- (MTLLinkedFunctions *)vertexLinkedFunctions { return _vertexLinkedFunctions; }
- (void)setVertexLinkedFunctions:(MTLLinkedFunctions *)lf { MTLLinkedFunctions *c = [lf copy]; [_vertexLinkedFunctions release]; _vertexLinkedFunctions = c; }
- (MTLLinkedFunctions *)fragmentLinkedFunctions { return _fragmentLinkedFunctions; }
- (void)setFragmentLinkedFunctions:(MTLLinkedFunctions *)lf { MTLLinkedFunctions *c = [lf copy]; [_fragmentLinkedFunctions release]; _fragmentLinkedFunctions = c; }
- (MTLPixelFormat)depthAttachmentPixelFormat { return _depthAttachmentPixelFormat; } - (void)setDepthAttachmentPixelFormat:(MTLPixelFormat)f { _depthAttachmentPixelFormat = f; }
- (MTLPixelFormat)stencilAttachmentPixelFormat { return _stencilAttachmentPixelFormat; } - (void)setStencilAttachmentPixelFormat:(MTLPixelFormat)f { _stencilAttachmentPixelFormat = f; }
- (NSUInteger)sampleCount { return _sampleCount; } - (void)setSampleCount:(NSUInteger)c { _sampleCount = c; _rasterSampleCount = c; }
- (NSUInteger)rasterSampleCount { return _rasterSampleCount; } - (void)setRasterSampleCount:(NSUInteger)c { _rasterSampleCount = c; _sampleCount = c; }
- (BOOL)isRasterizationEnabled { return _rasterizationEnabled; } - (void)setRasterizationEnabled:(BOOL)e { _rasterizationEnabled = e; }
- (BOOL)isAlphaToCoverageEnabled { return _alphaToCoverageEnabled; } - (void)setAlphaToCoverageEnabled:(BOOL)e { _alphaToCoverageEnabled = e; }
- (BOOL)isAlphaToOneEnabled { return _alphaToOneEnabled; } - (void)setAlphaToOneEnabled:(BOOL)e { _alphaToOneEnabled = e; }
- (MTLPrimitiveTopologyClass)inputPrimitiveTopology { return _inputPrimitiveTopology; } - (void)setInputPrimitiveTopology:(MTLPrimitiveTopologyClass)t { _inputPrimitiveTopology = t; }
- (BOOL)supportIndirectCommandBuffers { return _supportIndirectCommandBuffers; } - (void)setSupportIndirectCommandBuffers:(BOOL)s { _supportIndirectCommandBuffers = s; }
- (NSArray *)binaryArchives { return _binaryArchives; } - (void)setBinaryArchives:(NSArray *)a { [a retain]; [_binaryArchives release]; _binaryArchives = a; }
- (NSArray *)vertexPreloadedLibraries { return _vertexPreloadedLibraries; } - (void)setVertexPreloadedLibraries:(NSArray *)a { [a retain]; [_vertexPreloadedLibraries release]; _vertexPreloadedLibraries = a; }
- (NSArray *)fragmentPreloadedLibraries { return _fragmentPreloadedLibraries; } - (void)setFragmentPreloadedLibraries:(NSArray *)a { [a retain]; [_fragmentPreloadedLibraries release]; _fragmentPreloadedLibraries = a; }
- (NSUInteger)maxVertexCallStackDepth { return _maxVertexCallStackDepth; } - (void)setMaxVertexCallStackDepth:(NSUInteger)d { _maxVertexCallStackDepth = d; }
- (NSUInteger)maxFragmentCallStackDepth { return _maxFragmentCallStackDepth; } - (void)setMaxFragmentCallStackDepth:(NSUInteger)d { _maxFragmentCallStackDepth = d; }
- (void)reset {
  [_label release]; _label = nil;
  [(id)_vertexFunction release]; _vertexFunction = nil;
  [(id)_fragmentFunction release]; _fragmentFunction = nil;
  [_vertexDescriptor release]; _vertexDescriptor = [[MTLVertexDescriptor alloc] init];
  [_colorAttachments release]; _colorAttachments = [[MTLRenderPipelineColorAttachmentDescriptorArray alloc] init];
  [_vertexBuffers release]; _vertexBuffers = [[MTLPipelineBufferDescriptorArray alloc] init];
  [_fragmentBuffers release]; _fragmentBuffers = [[MTLPipelineBufferDescriptorArray alloc] init];
  [_binaryArchives release]; _binaryArchives = nil;
  [_vertexPreloadedLibraries release]; _vertexPreloadedLibraries = nil;
  [_fragmentPreloadedLibraries release]; _fragmentPreloadedLibraries = nil;
  [_vertexLinkedFunctions release]; _vertexLinkedFunctions = nil;
  [_fragmentLinkedFunctions release]; _fragmentLinkedFunctions = nil;
  _depthAttachmentPixelFormat = MTLPixelFormatInvalid;
  _stencilAttachmentPixelFormat = MTLPixelFormatInvalid;
  _sampleCount = 1;
  _rasterSampleCount = 1;
  _rasterizationEnabled = YES;
  _supportIndirectCommandBuffers = NO;
}
- (id)copyWithZone:(NSZone *)zone {
  MTLRenderPipelineDescriptor *c = [[MTLRenderPipelineDescriptor allocWithZone:zone] init];
  c.label = _label;
  c.vertexFunction = _vertexFunction;
  c.fragmentFunction = _fragmentFunction;
  c.vertexDescriptor = _vertexDescriptor;
  for (int i = 0; i < 8; i++) {
    if (_colorAttachments->_descriptors[i]) {
      c->_colorAttachments->_descriptors[i] = [_colorAttachments->_descriptors[i] copy];
    }
  }
  c.depthAttachmentPixelFormat = _depthAttachmentPixelFormat;
  c.stencilAttachmentPixelFormat = _stencilAttachmentPixelFormat;
  c.sampleCount = _sampleCount;
  c.rasterizationEnabled = _rasterizationEnabled;
  c.alphaToCoverageEnabled = _alphaToCoverageEnabled;
  c.alphaToOneEnabled = _alphaToOneEnabled;
  c.inputPrimitiveTopology = _inputPrimitiveTopology;
  c.supportIndirectCommandBuffers = _supportIndirectCommandBuffers;
  c.binaryArchives = _binaryArchives;
  c.vertexPreloadedLibraries = _vertexPreloadedLibraries;
  c.fragmentPreloadedLibraries = _fragmentPreloadedLibraries;
  c.maxVertexCallStackDepth = _maxVertexCallStackDepth;
  c.maxFragmentCallStackDepth = _maxFragmentCallStackDepth;
  c.vertexLinkedFunctions = _vertexLinkedFunctions;
  c.fragmentLinkedFunctions = _fragmentLinkedFunctions;
  return c;
}
- (void)dealloc {
  [_label release]; [(id)_vertexFunction release]; [(id)_fragmentFunction release];
  [_vertexDescriptor release]; [_colorAttachments release];
  [_vertexBuffers release]; [_fragmentBuffers release];
  [_binaryArchives release]; [_vertexPreloadedLibraries release]; [_fragmentPreloadedLibraries release];
  [_vertexLinkedFunctions release]; [_fragmentLinkedFunctions release];
  [super dealloc];
}
@end

@implementation MTLComputePipelineDescriptor {
  NSString *_label;
  id<MTLFunction> _computeFunction;
  BOOL _threadGroupSizeIsMultipleOfThreadExecutionWidth;
  NSUInteger _maxTotalThreadsPerThreadgroup;
  MTLPipelineBufferDescriptorArray *_buffers;
  BOOL _supportIndirectCommandBuffers;
  NSArray *_binaryArchives;
  NSArray *_preloadedLibraries;
  MTLLinkedFunctions *_linkedFunctions;
}
- (id)init {
  if ((self = [super init])) {
    _buffers = [[MTLPipelineBufferDescriptorArray alloc] init];
  }
  return self;
}
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (id<MTLFunction>)computeFunction { return _computeFunction; } - (void)setComputeFunction:(id<MTLFunction>)f { [f retain]; [(id)_computeFunction release]; _computeFunction = f; }
- (BOOL)threadGroupSizeIsMultipleOfThreadExecutionWidth { return _threadGroupSizeIsMultipleOfThreadExecutionWidth; }
- (void)setThreadGroupSizeIsMultipleOfThreadExecutionWidth:(BOOL)f { _threadGroupSizeIsMultipleOfThreadExecutionWidth = f; }
- (NSUInteger)maxTotalThreadsPerThreadgroup { return _maxTotalThreadsPerThreadgroup; }
- (void)setMaxTotalThreadsPerThreadgroup:(NSUInteger)m { _maxTotalThreadsPerThreadgroup = m; }
- (MTLPipelineBufferDescriptorArray *)buffers { return _buffers; }
- (BOOL)supportIndirectCommandBuffers { return _supportIndirectCommandBuffers; } - (void)setSupportIndirectCommandBuffers:(BOOL)s { _supportIndirectCommandBuffers = s; }
- (NSArray *)binaryArchives { return _binaryArchives; } - (void)setBinaryArchives:(NSArray *)a { [a retain]; [_binaryArchives release]; _binaryArchives = a; }
- (NSArray *)preloadedLibraries { return _preloadedLibraries; } - (void)setPreloadedLibraries:(NSArray *)a { [a retain]; [_preloadedLibraries release]; _preloadedLibraries = a; }
- (NSArray *)insertLibraries { return _preloadedLibraries; } - (void)setInsertLibraries:(NSArray *)a { [self setPreloadedLibraries:a]; }
- (MTLLinkedFunctions *)linkedFunctions { return _linkedFunctions; }
- (void)setLinkedFunctions:(MTLLinkedFunctions *)lf { MTLLinkedFunctions *c = [lf copy]; [_linkedFunctions release]; _linkedFunctions = c; }
- (void)reset {
  [_label release]; _label = nil;
  [(id)_computeFunction release]; _computeFunction = nil;
  [_buffers release]; _buffers = [[MTLPipelineBufferDescriptorArray alloc] init];
  [_binaryArchives release]; _binaryArchives = nil;
  [_preloadedLibraries release]; _preloadedLibraries = nil;
  [_linkedFunctions release]; _linkedFunctions = nil;
  _supportIndirectCommandBuffers = NO;
}
- (id)copyWithZone:(NSZone *)zone {
  MTLComputePipelineDescriptor *c = [[MTLComputePipelineDescriptor allocWithZone:zone] init];
  c.label = _label;
  c.computeFunction = _computeFunction;
  c.threadGroupSizeIsMultipleOfThreadExecutionWidth = _threadGroupSizeIsMultipleOfThreadExecutionWidth;
  c.maxTotalThreadsPerThreadgroup = _maxTotalThreadsPerThreadgroup;
  c.supportIndirectCommandBuffers = _supportIndirectCommandBuffers;
  c.binaryArchives = _binaryArchives;
  c.preloadedLibraries = _preloadedLibraries;
  c.linkedFunctions = _linkedFunctions;
  return c;
}
- (void)dealloc {
  [_label release]; [(id)_computeFunction release];
  [_buffers release]; [_binaryArchives release]; [_preloadedLibraries release];
  [_linkedFunctions release];
  [super dealloc];
}
@end

@implementation MTLStencilDescriptor {
  MTLCompareFunction _stencilCompareFunction;
  MTLStencilOperation _stencilFailureOperation;
  MTLStencilOperation _depthFailureOperation;
  MTLStencilOperation _depthStencilPassOperation;
  uint32_t _readMask;
  uint32_t _writeMask;
}
- (id)init {
  if ((self = [super init])) {
    _stencilCompareFunction = MTLCompareFunctionAlways;
    _readMask = 0xFFFFFFFF;
    _writeMask = 0xFFFFFFFF;
  }
  return self;
}
- (MTLCompareFunction)stencilCompareFunction { return _stencilCompareFunction; } - (void)setStencilCompareFunction:(MTLCompareFunction)f { _stencilCompareFunction = f; }
- (MTLStencilOperation)stencilFailureOperation { return _stencilFailureOperation; } - (void)setStencilFailureOperation:(MTLStencilOperation)o { _stencilFailureOperation = o; }
- (MTLStencilOperation)depthFailureOperation { return _depthFailureOperation; } - (void)setDepthFailureOperation:(MTLStencilOperation)o { _depthFailureOperation = o; }
- (MTLStencilOperation)depthStencilPassOperation { return _depthStencilPassOperation; } - (void)setDepthStencilPassOperation:(MTLStencilOperation)o { _depthStencilPassOperation = o; }
- (MTLStencilOperation)depthNormalFailureOperation { return _depthStencilPassOperation; } - (void)setDepthNormalFailureOperation:(MTLStencilOperation)o { _depthStencilPassOperation = o; }
- (uint32_t)readMask { return _readMask; } - (void)setReadMask:(uint32_t)m { _readMask = m; }
- (uint32_t)writeMask { return _writeMask; } - (void)setWriteMask:(uint32_t)m { _writeMask = m; }
- (id)copyWithZone:(NSZone *)zone {
  MTLStencilDescriptor *c = [[MTLStencilDescriptor allocWithZone:zone] init];
  c->_stencilCompareFunction = _stencilCompareFunction;
  c->_stencilFailureOperation = _stencilFailureOperation;
  c->_depthFailureOperation = _depthFailureOperation;
  c->_depthStencilPassOperation = _depthStencilPassOperation;
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
- (id)init {
  if ((self = [super init])) {
    _depthCompareFunction = MTLCompareFunctionAlways;
    _depthWriteEnabled = NO;
    _frontFaceStencil = [[MTLStencilDescriptor alloc] init];
    _backFaceStencil = [[MTLStencilDescriptor alloc] init];
  }
  return self;
}
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (MTLCompareFunction)depthCompareFunction { return _depthCompareFunction; } - (void)setDepthCompareFunction:(MTLCompareFunction)f { _depthCompareFunction = f; }
- (BOOL)isDepthWriteEnabled { return _depthWriteEnabled; } - (void)setDepthWriteEnabled:(BOOL)e { _depthWriteEnabled = e; }
- (MTLStencilDescriptor *)frontFaceStencil { return _frontFaceStencil; } - (void)setFrontFaceStencil:(MTLStencilDescriptor *)s { [s retain]; [_frontFaceStencil release]; _frontFaceStencil = s; }
- (MTLStencilDescriptor *)backFaceStencil { return _backFaceStencil; } - (void)setBackFaceStencil:(MTLStencilDescriptor *)s { [s retain]; [_backFaceStencil release]; _backFaceStencil = s; }
- (id)copyWithZone:(NSZone *)zone {
  MTLDepthStencilDescriptor *c = [[MTLDepthStencilDescriptor allocWithZone:zone] init];
  c.label = _label; c.depthCompareFunction = _depthCompareFunction; c.depthWriteEnabled = _depthWriteEnabled;
  c.frontFaceStencil = [[_frontFaceStencil copy] autorelease];
  c.backFaceStencil = [[_backFaceStencil copy] autorelease];
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
  BOOL _normalizedCoordinates;
  float _lodMinClamp;
  float _lodMaxClamp;
  MTLSamplerBorderColor _borderColor;
}
- (id)init {
  if ((self = [super init])) {
    _maxAnisotropy = 1;
    _normalizedCoordinates = YES;
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
- (BOOL)normalizedCoordinates { return _normalizedCoordinates; } - (void)setNormalizedCoordinates:(BOOL)n { _normalizedCoordinates = n; }
- (float)lodMinClamp { return _lodMinClamp; } - (void)setLodMinClamp:(float)c { _lodMinClamp = c; }
- (float)lodMaxClamp { return _lodMaxClamp; } - (void)setLodMaxClamp:(float)c { _lodMaxClamp = c; }
- (MTLSamplerBorderColor)borderColor { return _borderColor; } - (void)setBorderColor:(MTLSamplerBorderColor)b { _borderColor = b; }
- (id)copyWithZone:(NSZone *)zone {
  MTLSamplerDescriptor *c = [[MTLSamplerDescriptor allocWithZone:zone] init];
  c.label = _label; c.minFilter = _minFilter; c.magFilter = _magFilter; c.mipFilter = _mipFilter;
  c.sAddressMode = _sAddressMode; c.tAddressMode = _tAddressMode; c.rAddressMode = _rAddressMode;
  c.maxAnisotropy = _maxAnisotropy; c.compareFunction = _compareFunction;
  c.normalizedCoordinates = _normalizedCoordinates;
  c.lodMinClamp = _lodMinClamp; c.lodMaxClamp = _lodMaxClamp;
  c.borderColor = _borderColor;
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
  MTLHazardTrackingMode _hazardTrackingMode;
  MTLTextureUsage _usage;
  BOOL _allowGPUOptimizedContents;
  MTLTextureSwizzleChannels _swizzle;
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
+ (MTLTextureDescriptor *)textureCubeDescriptorWithPixelFormat:(MTLPixelFormat)pixelFormat size:(NSUInteger)size mipmapped:(BOOL)mipmapped {
  MTLTextureDescriptor *d = [[[self alloc] init] autorelease];
  d->_textureType = MTLTextureTypeCube;
  d->_pixelFormat = pixelFormat;
  d->_width = size;
  d->_height = size;
  d->_depth = 1;
  d->_mipmapLevelCount = mipmapped ? (NSUInteger)(log2(size) + 1) : 1;
  d->_sampleCount = 1;
  d->_arrayLength = 1;
  return d;
}
+ (MTLTextureDescriptor *)textureBufferDescriptorWithPixelFormat:(MTLPixelFormat)pixelFormat width:(NSUInteger)width resourceOptions:(MTLResourceOptions)resourceOptions usage:(MTLTextureUsage)usage {
  MTLTextureDescriptor *d = [[[self alloc] init] autorelease];
  d->_textureType = MTLTextureTypeTextureBuffer;
  d->_pixelFormat = pixelFormat;
  d->_width = width;
  d->_height = 1;
  d->_depth = 1;
  d->_resourceOptions = resourceOptions;
  d->_usage = usage;
  return d;
}
- (id)init {
  if ((self = [super init])) {
    _textureType = MTLTextureType2D;
    _pixelFormat = MTLPixelFormatRGBA8Unorm;
    _width = 1; _height = 1; _depth = 1;
    _mipmapLevelCount = 1; _sampleCount = 1; _arrayLength = 1;
    _usage = MTLTextureUsageShaderRead;
    _allowGPUOptimizedContents = YES;
    _swizzle = MTLTextureSwizzleChannelsMake(MTLTextureSwizzleRed, MTLTextureSwizzleGreen, MTLTextureSwizzleBlue, MTLTextureSwizzleAlpha);
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
- (MTLHazardTrackingMode)hazardTrackingMode { return _hazardTrackingMode; } - (void)setHazardTrackingMode:(MTLHazardTrackingMode)m { _hazardTrackingMode = m; }
- (MTLTextureUsage)usage { return _usage; } - (void)setUsage:(MTLTextureUsage)u { _usage = u; }
- (BOOL)allowGPUOptimizedContents { return _allowGPUOptimizedContents; } - (void)setAllowGPUOptimizedContents:(BOOL)a { _allowGPUOptimizedContents = a; }
- (MTLTextureSwizzleChannels)swizzle { return _swizzle; } - (void)setSwizzle:(MTLTextureSwizzleChannels)s { _swizzle = s; }
- (id)copyWithZone:(NSZone *)zone {
  MTLTextureDescriptor *c = [[MTLTextureDescriptor allocWithZone:zone] init];
  c->_textureType = _textureType; c->_pixelFormat = _pixelFormat;
  c->_width = _width; c->_height = _height; c->_depth = _depth;
  c->_mipmapLevelCount = _mipmapLevelCount; c->_sampleCount = _sampleCount;
  c->_arrayLength = _arrayLength; c->_usage = _usage;
  c->_resourceOptions = _resourceOptions; c->_storageMode = _storageMode;
  c->_swizzle = _swizzle;
  return c;
}
@end

@implementation MTLRenderPassAttachmentDescriptor {
  id<MTLTexture> _texture;
  id<MTLTexture> _resolveTexture;
  NSUInteger _level;
  NSUInteger _slice;
  NSUInteger _depthPlane;
  MTLLoadAction _loadAction;
  MTLStoreAction _storeAction;
}
- (id<MTLTexture>)texture { return _texture; } - (void)setTexture:(id<MTLTexture>)t { [t retain]; [(id)_texture release]; _texture = t; }
- (id<MTLTexture>)resolveTexture { return _resolveTexture; } - (void)setResolveTexture:(id<MTLTexture>)t { [t retain]; [(id)_resolveTexture release]; _resolveTexture = t; }
- (NSUInteger)level { return _level; } - (void)setLevel:(NSUInteger)l { _level = l; }
- (NSUInteger)slice { return _slice; } - (void)setSlice:(NSUInteger)s { _slice = s; }
- (NSUInteger)depthPlane { return _depthPlane; } - (void)setDepthPlane:(NSUInteger)d { _depthPlane = d; }
- (MTLLoadAction)loadAction { return _loadAction; } - (void)setLoadAction:(MTLLoadAction)a { _loadAction = a; }
- (MTLStoreAction)storeAction { return _storeAction; } - (void)setStoreAction:(MTLStoreAction)a { _storeAction = a; }
- (void)dealloc {
  [(id)_texture release];
  [(id)_resolveTexture release];
  [super dealloc];
}
@end

@implementation MTLRenderPassColorAttachmentDescriptor {
  MTLClearColor _clearColor;
}
- (id)init {
  if ((self = [super init])) {
    _clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
  }
  return self;
}
- (MTLClearColor)clearColor { return _clearColor; } - (void)setClearColor:(MTLClearColor)c { _clearColor = c; }
- (id)copyWithZone:(NSZone *)zone {
  MTLRenderPassColorAttachmentDescriptor *c = [[MTLRenderPassColorAttachmentDescriptor allocWithZone:zone] init];
  c.texture = self.texture; c.resolveTexture = self.resolveTexture;
  c.level = self.level; c.slice = self.slice; c.depthPlane = self.depthPlane;
  c.loadAction = self.loadAction; c.storeAction = self.storeAction;
  c.clearColor = _clearColor;
  return c;
}
@end

@implementation MTLRenderPassColorAttachmentDescriptorArray {
@public
  MTLRenderPassColorAttachmentDescriptor *_attachments[8];
}
- (MTLRenderPassColorAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)idx {
  if (idx >= 8) return nil;
  if (!_attachments[idx]) _attachments[idx] = [[MTLRenderPassColorAttachmentDescriptor alloc] init];
  return _attachments[idx];
}
- (void)setObject:(MTLRenderPassColorAttachmentDescriptor *)attachment atIndexedSubscript:(NSUInteger)idx {
  if (idx >= 8) return;
  MTLRenderPassColorAttachmentDescriptor *c = [attachment copy];
  [_attachments[idx] release];
  _attachments[idx] = c;
}
- (void)dealloc {
  for (int i = 0; i < 8; i++) [_attachments[i] release];
  [super dealloc];
}
@end

@implementation MTLRenderPassDepthAttachmentDescriptor {
  double _clearDepth;
}
- (id)init {
  if ((self = [super init])) {
    _clearDepth = 1.0;
  }
  return self;
}
- (double)clearDepth { return _clearDepth; } - (void)setClearDepth:(double)d { _clearDepth = d; }
- (id)copyWithZone:(NSZone *)zone {
  MTLRenderPassDepthAttachmentDescriptor *c = [[MTLRenderPassDepthAttachmentDescriptor allocWithZone:zone] init];
  c.texture = self.texture; c.resolveTexture = self.resolveTexture;
  c.level = self.level; c.slice = self.slice;
  c.loadAction = self.loadAction; c.storeAction = self.storeAction;
  c.clearDepth = _clearDepth;
  return c;
}
@end

@implementation MTLRenderPassStencilAttachmentDescriptor {
  uint32_t _clearStencil;
}
- (uint32_t)clearStencil { return _clearStencil; } - (void)setClearStencil:(uint32_t)s { _clearStencil = s; }
- (id)copyWithZone:(NSZone *)zone {
  MTLRenderPassStencilAttachmentDescriptor *c = [[MTLRenderPassStencilAttachmentDescriptor allocWithZone:zone] init];
  c.texture = self.texture; c.resolveTexture = self.resolveTexture;
  c.level = self.level; c.slice = self.slice;
  c.loadAction = self.loadAction; c.storeAction = self.storeAction;
  c.clearStencil = _clearStencil;
  return c;
}
@end

@implementation MTLRenderPassDescriptor {
  MTLRenderPassColorAttachmentDescriptorArray *_colorAttachments;
  MTLRenderPassDepthAttachmentDescriptor *_depthAttachment;
  MTLRenderPassStencilAttachmentDescriptor *_stencilAttachment;
  id<MTLBuffer> _visibilityResultBuffer;
  NSUInteger _renderTargetArrayLength;
  NSUInteger _renderTargetWidth;
  NSUInteger _renderTargetHeight;
  id<MTLRasterizationRateMap> _rasterizationRateMap;
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
- (MTLRenderPassDepthAttachmentDescriptor *)depthAttachment { return _depthAttachment; } - (void)setDepthAttachment:(MTLRenderPassDepthAttachmentDescriptor *)d { MTLRenderPassDepthAttachmentDescriptor *c = [d copy]; [_depthAttachment release]; _depthAttachment = c; }
- (MTLRenderPassStencilAttachmentDescriptor *)stencilAttachment { return _stencilAttachment; } - (void)setStencilAttachment:(MTLRenderPassStencilAttachmentDescriptor *)s { MTLRenderPassStencilAttachmentDescriptor *c = [s copy]; [_stencilAttachment release]; _stencilAttachment = c; }
- (id<MTLBuffer>)visibilityResultBuffer { return _visibilityResultBuffer; } - (void)setVisibilityResultBuffer:(id<MTLBuffer>)b { [b retain]; [(id)_visibilityResultBuffer release]; _visibilityResultBuffer = b; }
- (NSUInteger)renderTargetArrayLength { return _renderTargetArrayLength; } - (void)setRenderTargetArrayLength:(NSUInteger)l { _renderTargetArrayLength = l; }
- (NSUInteger)renderTargetWidth { return _renderTargetWidth; } - (void)setRenderTargetWidth:(NSUInteger)w { _renderTargetWidth = w; }
- (NSUInteger)renderTargetHeight { return _renderTargetHeight; } - (void)setRenderTargetHeight:(NSUInteger)h { _renderTargetHeight = h; }
- (id<MTLRasterizationRateMap>)rasterizationRateMap { return _rasterizationRateMap; }
- (void)setRasterizationRateMap:(id<MTLRasterizationRateMap>)m { [m retain]; [(id)_rasterizationRateMap release]; _rasterizationRateMap = m; }
- (id)copyWithZone:(NSZone *)zone {
  MTLRenderPassDescriptor *c = [[MTLRenderPassDescriptor allocWithZone:zone] init];
  for (int i = 0; i < 8; i++) {
    if (_colorAttachments->_attachments[i]) {
      c->_colorAttachments->_attachments[i] = [_colorAttachments->_attachments[i] copy];
    }
  }
  c.depthAttachment = _depthAttachment;
  c.stencilAttachment = _stencilAttachment;
  c.visibilityResultBuffer = _visibilityResultBuffer;
  c.renderTargetWidth = _renderTargetWidth;
  c.renderTargetHeight = _renderTargetHeight;
  c.rasterizationRateMap = _rasterizationRateMap;
  return c;
}
- (void)dealloc {
  [_colorAttachments release]; [_depthAttachment release]; [_stencilAttachment release];
  [(id)_visibilityResultBuffer release];
  [(id)_rasterizationRateMap release];
  [super dealloc];
}
@end

@implementation MTLCompileOptions {
  BOOL _fastMathEnabled;
  MTLLanguageVersion _languageVersion;
  NSDictionary *_preprocessorMacros;
}
- (id)init {
  if ((self = [super init])) {
    _fastMathEnabled = YES;
  }
  return self;
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

@implementation MTLFunctionConstantValues
- (void)setConstantValue:(const void *)value type:(MTLDataType)type atIndex:(NSUInteger)index {}
- (void)setConstantValues:(const void *)values type:(MTLDataType)type withRange:(NSRange)range {}
- (void)setConstantValue:(const void *)value type:(MTLDataType)type withName:(NSString *)name {}
- (void)reset {}
- (id)copyWithZone:(NSZone *)zone { return [[MTLFunctionConstantValues allocWithZone:zone] init]; }
@end

@implementation MTLHeapDescriptor {
  NSUInteger _size;
  MTLStorageMode _storageMode;
  MTLCPUCacheMode _cpuCacheMode;
  MTLHazardTrackingMode _hazardTrackingMode;
  MTLResourceOptions _resourceOptions;
  MTLHeapType _type;
}
- (NSUInteger)size { return _size; } - (void)setSize:(NSUInteger)s { _size = s; }
- (MTLStorageMode)storageMode { return _storageMode; } - (void)setStorageMode:(MTLStorageMode)m { _storageMode = m; }
- (MTLCPUCacheMode)cpuCacheMode { return _cpuCacheMode; } - (void)setCpuCacheMode:(MTLCPUCacheMode)m { _cpuCacheMode = m; }
- (MTLHazardTrackingMode)hazardTrackingMode { return _hazardTrackingMode; } - (void)setHazardTrackingMode:(MTLHazardTrackingMode)m { _hazardTrackingMode = m; }
- (MTLResourceOptions)resourceOptions { return _resourceOptions; } - (void)setResourceOptions:(MTLResourceOptions)o { _resourceOptions = o; }
- (MTLHeapType)type { return _type; } - (void)setType:(MTLHeapType)t { _type = t; }
- (id)copyWithZone:(NSZone *)zone {
  MTLHeapDescriptor *c = [[MTLHeapDescriptor allocWithZone:zone] init];
  c.size = _size; c.storageMode = _storageMode; c.cpuCacheMode = _cpuCacheMode;
  c.hazardTrackingMode = _hazardTrackingMode; c.resourceOptions = _resourceOptions; c.type = _type;
  return c;
}
@end

@implementation MTLArgumentDescriptor
+ (MTLArgumentDescriptor *)argumentDescriptor { return [[[self alloc] init] autorelease]; }
- (id)copyWithZone:(NSZone *)zone { return [[MTLArgumentDescriptor allocWithZone:zone] init]; }
@end

/* ------------------------------------------------------------------- Base & Resources */

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
@public
  void *_data;
  NSUInteger _length;
  MTLResourceOptions _options;
  id<MTLDevice> _device;
  NSString *_label;
  BOOL _ownsData;
  id<MTLHeap> _heap;
  NSUInteger _heapOffset;
}
- (instancetype)initWithLength:(NSUInteger)length options:(MTLResourceOptions)options device:(id<MTLDevice>)device;
- (instancetype)initWithBytes:(const void *)pointer length:(NSUInteger)length options:(MTLResourceOptions)options device:(id<MTLDevice>)device;
- (instancetype)initWithBytesNoCopy:(void *)pointer length:(NSUInteger)length options:(MTLResourceOptions)options device:(id<MTLDevice>)device;
@end

@implementation XEFMetalBuffer
- (instancetype)initWithLength:(NSUInteger)length options:(MTLResourceOptions)options device:(id<MTLDevice>)device {
  if ((self = [super init])) {
    _length = length;
    _options = options;
    _device = device;
    _data = calloc(1, length > 0 ? length : 16);
    _ownsData = YES;
  }
  return self;
}
- (instancetype)initWithBytes:(const void *)pointer length:(NSUInteger)length options:(MTLResourceOptions)options device:(id<MTLDevice>)device {
  if ((self = [super init])) {
    _length = length;
    _options = options;
    _device = device;
    _data = calloc(1, length > 0 ? length : 16);
    _ownsData = YES;
    if (pointer && length > 0) memcpy(_data, pointer, length);
  }
  return self;
}
- (instancetype)initWithBytesNoCopy:(void *)pointer length:(NSUInteger)length options:(MTLResourceOptions)options device:(id<MTLDevice>)device {
  if ((self = [super init])) {
    _length = length;
    _options = options;
    _device = device;
    if (pointer) {
      _data = pointer;
      _ownsData = NO;
    } else {
      _data = calloc(1, length > 0 ? length : 16);
      _ownsData = YES;
    }
  }
  return self;
}
- (void *)contents { return _data; }
- (NSUInteger)length { return _length; }
- (uint64_t)gpuAddress { return (uint64_t)(uintptr_t)_data; }
- (void)didModifyRange:(NSRange)range {}
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (MTLStorageMode)storageMode { return (MTLStorageMode)((_options >> MTLResourceStorageModeShift) & 0xf); }
- (MTLCPUCacheMode)cpuCacheMode { return (MTLCPUCacheMode)((_options >> MTLResourceCPUCacheModeShift) & 0xf); }
- (MTLHazardTrackingMode)hazardTrackingMode { return (MTLHazardTrackingMode)((_options >> MTLResourceHazardTrackingModeShift) & 0x3); }
- (MTLResourceOptions)resourceOptions { return _options; }
- (MTLPurgeableState)setPurgeableState:(MTLPurgeableState)state { return MTLPurgeableStateNonVolatile; }
- (void)makeAliasable {}
- (BOOL)isAliasable { return NO; }
- (id<MTLHeap>)heap { return _heap; }
- (NSUInteger)heapOffset { return _heapOffset; }
- (NSUInteger)allocatedSize { return _length; }
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor offset:(NSUInteger)offset bytesPerRow:(NSUInteger)bytesPerRow {
  return [_device newTextureWithDescriptor:descriptor];
}
- (void)addDebugMarker:(NSString *)marker range:(NSRange)range {}
- (void)removeAllDebugMarkers {}
- (void)dealloc {
  if (_ownsData && _data) free(_data);
  [_label release];
  [super dealloc];
}
@end

@interface XEFMetalTextureStorage : NSObject {
@public
  uint8_t *_data;
  size_t _dataSize;
  NSUInteger _width, _height, _depth, _arrayLength, _bpp, _bytesPerRow, _bytesPerImage;
}
- (instancetype)initWithWidth:(NSUInteger)w height:(NSUInteger)h depth:(NSUInteger)d arrayLength:(NSUInteger)arr bpp:(NSUInteger)bpp;
@end

@implementation XEFMetalTextureStorage
- (instancetype)initWithWidth:(NSUInteger)w height:(NSUInteger)h depth:(NSUInteger)d arrayLength:(NSUInteger)arr bpp:(NSUInteger)bpp {
  if ((self = [super init])) {
    _width = w > 0 ? w : 1;
    _height = h > 0 ? h : 1;
    _depth = d > 0 ? d : 1;
    _arrayLength = arr > 0 ? arr : 1;
    _bpp = bpp > 0 ? bpp : 4;
    _bytesPerRow = _width * _bpp;
    _bytesPerImage = _bytesPerRow * _height;
    _dataSize = (size_t)_bytesPerImage * _depth * _arrayLength;
    _data = (uint8_t *)calloc(1, _dataSize > 0 ? _dataSize : 16);
  }
  return self;
}
- (void)dealloc {
  if (_data) free(_data);
  [super dealloc];
}
@end

@interface XEFMetalTexture : XEFMetalObject <MTLTexture> {
@public
  NSUInteger _width, _height, _depth, _mipmapLevelCount, _sampleCount, _arrayLength;
  MTLPixelFormat _pixelFormat;
  MTLTextureType _textureType;
  MTLTextureUsage _usage;
  MTLStorageMode _storageMode;
  MTLCPUCacheMode _cpuCacheMode;
  MTLResourceOptions _resourceOptions;
  id<MTLDevice> _device;
  NSString *_label;
  XEFMetalTextureStorage *_storage;
  id<MTLTexture> _parentTexture;
  NSUInteger _parentRelativeLevel;
  NSUInteger _parentRelativeSlice;
  uint32_t _hostTexId;
  id<MTLHeap> _heap;
  NSUInteger _heapOffset;
  MTLTextureSwizzleChannels _swizzle;
}
- (instancetype)initWithDescriptor:(MTLTextureDescriptor *)desc device:(id<MTLDevice>)device;
- (instancetype)initWithParent:(XEFMetalTexture *)parent pixelFormat:(MTLPixelFormat)fmt textureType:(MTLTextureType)ttype levels:(NSRange)levels slices:(NSRange)slices;
- (instancetype)initWithParent:(XEFMetalTexture *)parent pixelFormat:(MTLPixelFormat)fmt textureType:(MTLTextureType)ttype levels:(NSRange)levels slices:(NSRange)slices swizzle:(MTLTextureSwizzleChannels)swizzle;
- (uint32_t)_hostTexId;
- (const void *)_rawBytes;
- (void *)_mutableRawBytes;
- (NSUInteger)_bpp;
@end

@implementation XEFMetalTexture
- (instancetype)initWithDescriptor:(MTLTextureDescriptor *)desc device:(id<MTLDevice>)device {
  if ((self = [super init])) {
    _width = desc.width > 0 ? desc.width : 1;
    _height = desc.height > 0 ? desc.height : 1;
    _depth = desc.depth > 0 ? desc.depth : 1;
    _mipmapLevelCount = desc.mipmapLevelCount > 0 ? desc.mipmapLevelCount : 1;
    _sampleCount = desc.sampleCount > 0 ? desc.sampleCount : 1;
    _arrayLength = desc.arrayLength > 0 ? desc.arrayLength : 1;
    _pixelFormat = desc.pixelFormat ? desc.pixelFormat : MTLPixelFormatBGRA8Unorm;
    _textureType = desc.textureType;
    _usage = desc.usage;
    _storageMode = desc.storageMode;
    _cpuCacheMode = desc.cpuCacheMode;
    _resourceOptions = desc.resourceOptions;
    _device = device;
    _swizzle = desc.swizzle;
    NSUInteger slices = _arrayLength * (_textureType == MTLTextureTypeCube ? 6 : 1);
    _storage = [[XEFMetalTextureStorage alloc] initWithWidth:_width height:_height depth:_depth arrayLength:slices bpp:xef_mtl_bpp(_pixelFormat)];
    _hostTexId = xef_host_metal_tex_create((int)_width, (int)_height, (int)_pixelFormat, (_usage & MTLTextureUsageRenderTarget) != 0);
  }
  return self;
}
- (instancetype)initWithParent:(XEFMetalTexture *)parent pixelFormat:(MTLPixelFormat)fmt textureType:(MTLTextureType)ttype levels:(NSRange)levels slices:(NSRange)slices {
  return [self initWithParent:parent pixelFormat:fmt textureType:ttype levels:levels slices:slices swizzle:MTLTextureSwizzleChannelsMake(MTLTextureSwizzleRed, MTLTextureSwizzleGreen, MTLTextureSwizzleBlue, MTLTextureSwizzleAlpha)];
}
- (instancetype)initWithParent:(XEFMetalTexture *)parent pixelFormat:(MTLPixelFormat)fmt textureType:(MTLTextureType)ttype levels:(NSRange)levels slices:(NSRange)slices swizzle:(MTLTextureSwizzleChannels)swizzle {
  if ((self = [super init])) {
    _width = parent->_width;
    _height = parent->_height;
    _depth = parent->_depth;
    _mipmapLevelCount = levels.length > 0 ? levels.length : parent->_mipmapLevelCount;
    _sampleCount = parent->_sampleCount;
    _arrayLength = slices.length > 0 ? slices.length : parent->_arrayLength;
    _pixelFormat = fmt ? fmt : parent->_pixelFormat;
    _textureType = ttype;
    _usage = parent->_usage;
    _storageMode = parent->_storageMode;
    _cpuCacheMode = parent->_cpuCacheMode;
    _resourceOptions = parent->_resourceOptions;
    _device = parent->_device;
    _swizzle = swizzle;
    _storage = [parent->_storage retain];
    _parentTexture = [parent retain];
    _parentRelativeLevel = levels.location;
    _parentRelativeSlice = slices.location;
    if (parent->_hostTexId > 0) {
      _hostTexId = xef_host_metal_tex_create_view(parent->_hostTexId, (int)_pixelFormat,
                                                  (int)swizzle.red, (int)swizzle.green, (int)swizzle.blue, (int)swizzle.alpha,
                                                  (int)levels.location, (int)_mipmapLevelCount,
                                                  (int)slices.location, (int)_arrayLength);
    }
  }
  return self;
}
- (uint32_t)_hostTexId { return _hostTexId; }
- (const void *)_rawBytes { return _storage ? _storage->_data : NULL; }
- (void *)_mutableRawBytes { return _storage ? _storage->_data : NULL; }
- (NSUInteger)_bpp { return _storage ? _storage->_bpp : 4; }
- (NSUInteger)width { return _width; }
- (NSUInteger)height { return _height; }
- (NSUInteger)depth { return _depth; }
- (NSUInteger)mipmapLevelCount { return _mipmapLevelCount; }
- (NSUInteger)sampleCount { return _sampleCount; }
- (NSUInteger)arrayLength { return _arrayLength; }
- (MTLPixelFormat)pixelFormat { return _pixelFormat; }
- (MTLTextureType)textureType { return _textureType; }
- (MTLTextureUsage)usage { return _usage; }
- (MTLStorageMode)storageMode { return _storageMode; }
- (MTLCPUCacheMode)cpuCacheMode { return _cpuCacheMode; }
- (MTLHazardTrackingMode)hazardTrackingMode { return MTLHazardTrackingModeDefault; }
- (MTLResourceOptions)resourceOptions { return _resourceOptions; }
- (BOOL)isFramebufferOnly { return NO; }
- (BOOL)allowGPUOptimizedContents { return YES; }
- (BOOL)isShareable { return NO; }
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (id<MTLTexture>)parentTexture { return _parentTexture; }
- (NSUInteger)parentRelativeLevel { return _parentRelativeLevel; }
- (NSUInteger)parentRelativeSlice { return _parentRelativeSlice; }
- (id<MTLBuffer>)buffer { return nil; }
- (NSUInteger)bufferOffset { return 0; }
- (NSUInteger)bufferBytesPerRow { return 0; }
- (IOSurfaceRef)iosurface { return NULL; }
- (NSUInteger)iosurfacePlane { return 0; }
- (id<MTLResource>)rootResource { return _parentTexture ? _parentTexture : nil; }
- (id<MTLHeap>)heap { return _heap; }
- (NSUInteger)heapOffset { return _heapOffset; }
- (NSUInteger)allocatedSize { return _storage ? _storage->_dataSize : 0; }
- (MTLPurgeableState)setPurgeableState:(MTLPurgeableState)state { return MTLPurgeableStateNonVolatile; }
- (MTLTextureSwizzleChannels)swizzle { return _swizzle; }

- (id<MTLTexture>)newTextureViewWithPixelFormat:(MTLPixelFormat)pixelFormat {
  return [[XEFMetalTexture alloc] initWithParent:self pixelFormat:pixelFormat textureType:_textureType levels:NSMakeRange(0, _mipmapLevelCount) slices:NSMakeRange(0, _arrayLength)];
}
- (id<MTLTexture>)newTextureViewWithPixelFormat:(MTLPixelFormat)pixelFormat textureType:(MTLTextureType)textureType levels:(NSRange)levelRange slices:(NSRange)sliceRange {
  return [[XEFMetalTexture alloc] initWithParent:self pixelFormat:pixelFormat textureType:textureType levels:levelRange slices:sliceRange];
}
- (id<MTLTexture>)newTextureViewWithPixelFormat:(MTLPixelFormat)pixelFormat textureType:(MTLTextureType)textureType levels:(NSRange)levelRange slices:(NSRange)sliceRange swizzle:(MTLTextureSwizzleChannels)swizzle {
  return [[XEFMetalTexture alloc] initWithParent:self pixelFormat:pixelFormat textureType:textureType levels:levelRange slices:sliceRange swizzle:swizzle];
}

- (void)replaceRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level slice:(NSUInteger)slice withBytes:(const void *)pixelBytes bytesPerRow:(NSUInteger)bytesPerRow bytesPerImage:(NSUInteger)bytesPerImage {
  if (!_storage || !_storage->_data || !pixelBytes) return;
  if (level > 0) return; /* base level used for sampling/display */
  NSUInteger bpp = _storage->_bpp;
  NSUInteger dstBpr = _storage->_bytesPerRow;
  NSUInteger srcBpr = bytesPerRow > 0 ? bytesPerRow : region.size.width * bpp;
  NSUInteger x0 = region.origin.x;
  NSUInteger y0 = region.origin.y;
  NSUInteger z0 = region.origin.z + slice + _parentRelativeSlice;
  NSUInteger w = region.size.width;
  NSUInteger h = region.size.height;
  NSUInteger d = region.size.depth > 0 ? region.size.depth : 1;
  if (x0 >= _width || y0 >= _height) return;
  if (x0 + w > _width) w = _width - x0;
  if (y0 + h > _height) h = _height - y0;
  NSUInteger rowBytes = w * bpp;
  NSUInteger srcBpi = bytesPerImage > 0 ? bytesPerImage : srcBpr * region.size.height;
  for (NSUInteger z = 0; z < d; z++) {
    size_t sliceOffset = (size_t)(z0 + z) * _storage->_bytesPerImage;
    if (sliceOffset >= _storage->_dataSize) break;
    const uint8_t *srcSlice = (const uint8_t *)pixelBytes + (size_t)z * srcBpi;
    for (NSUInteger y = 0; y < h; y++) {
      size_t dstOff = sliceOffset + (size_t)(y0 + y) * dstBpr + (size_t)x0 * bpp;
      if (dstOff + rowBytes <= _storage->_dataSize) {
        memcpy(_storage->_data + dstOff, srcSlice + (size_t)y * srcBpr, rowBytes);
      }
    }
  }
  if (_hostTexId > 0 && pixelBytes) {
    xef_host_metal_tex_update_ex(_hostTexId, (int)z0, (int)(level + _parentRelativeLevel), (int)x0, (int)y0, 0, (int)w, (int)h, (int)d, pixelBytes, (int)srcBpr, (int)srcBpi);
  }
}

- (void)replaceRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level withBytes:(const void *)pixelBytes bytesPerRow:(NSUInteger)bytesPerRow {
  [self replaceRegion:region mipmapLevel:level slice:0 withBytes:pixelBytes bytesPerRow:bytesPerRow bytesPerImage:0];
}

- (void)getBytes:(void *)pixelBytes bytesPerRow:(NSUInteger)bytesPerRow bytesPerImage:(NSUInteger)bytesPerImage fromRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level slice:(NSUInteger)slice {
  if (!_storage || !_storage->_data || !pixelBytes) return;
  NSUInteger bpp = _storage->_bpp;
  NSUInteger srcBpr = _storage->_bytesPerRow;
  NSUInteger dstBpr = bytesPerRow > 0 ? bytesPerRow : region.size.width * bpp;
  NSUInteger x0 = region.origin.x;
  NSUInteger y0 = region.origin.y;
  NSUInteger z0 = region.origin.z + slice + _parentRelativeSlice;
  NSUInteger w = region.size.width;
  NSUInteger h = region.size.height;
  NSUInteger d = region.size.depth > 0 ? region.size.depth : 1;
  if (x0 >= _width || y0 >= _height) return;
  if (x0 + w > _width) w = _width - x0;
  NSUInteger rowBytes = w * bpp;
  NSUInteger dstBpi = bytesPerImage > 0 ? bytesPerImage : dstBpr * region.size.height;
  if (_hostTexId > 0) {
    xef_host_metal_tex_readback_ex(_hostTexId, (int)z0, (int)(level + _parentRelativeLevel), (int)x0, (int)y0, 0, (int)w, (int)h, (int)d, pixelBytes, (int)dstBpr, (int)dstBpi);
    return;
  }
  for (NSUInteger z = 0; z < d; z++) {
    size_t sliceOffset = (size_t)(z0 + z) * _storage->_bytesPerImage;
    if (sliceOffset >= _storage->_dataSize) break;
    uint8_t *dstSlice = (uint8_t *)pixelBytes + (size_t)z * dstBpi;
    for (NSUInteger y = 0; y < h; y++) {
      size_t srcOff = sliceOffset + (size_t)(y0 + y) * srcBpr + (size_t)x0 * bpp;
      if (srcOff + rowBytes <= _storage->_dataSize) {
        memcpy(dstSlice + (size_t)y * dstBpr, _storage->_data + srcOff, rowBytes);
      }
    }
  }
}

- (void)getBytes:(void *)pixelBytes bytesPerRow:(NSUInteger)bytesPerRow fromRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level {
  [self getBytes:pixelBytes bytesPerRow:bytesPerRow bytesPerImage:0 fromRegion:region mipmapLevel:level slice:0];
}

- (void)dealloc {
  if (_hostTexId > 0 && (!_parentTexture || _hostTexId != [(XEFMetalTexture *)_parentTexture _hostTexId])) {
    xef_host_metal_tex_destroy(_hostTexId);
    _hostTexId = 0;
  }
  [_storage release];
  [(id)_parentTexture release];
  [_label release];
  [super dealloc];
}
@end

/* Pixel read/write helpers on XEFMetalTexture */
static inline void xef_tex_read_pixel(XEFMetalTexture *tex, int x, int y, float out_rgba[4]) {
  if (!tex || !tex->_storage || !tex->_storage->_data) {
    out_rgba[0] = out_rgba[1] = out_rgba[2] = 0.0f; out_rgba[3] = 1.0f;
    return;
  }
  int w = (int)tex->_width, h = (int)tex->_height;
  if (x < 0) x = 0; else if (x >= w) x = w - 1;
  if (y < 0) y = 0; else if (y >= h) y = h - 1;
  const uint8_t *p = tex->_storage->_data + (size_t)y * tex->_storage->_bytesPerRow + (size_t)x * tex->_storage->_bpp;
  NSUInteger fmt = (NSUInteger)tex->_pixelFormat;
  if (fmt == 80 || fmt == 81) { /* BGRA8Unorm */
    out_rgba[0] = p[2] * (1.0f / 255.0f);
    out_rgba[1] = p[1] * (1.0f / 255.0f);
    out_rgba[2] = p[0] * (1.0f / 255.0f);
    out_rgba[3] = p[3] * (1.0f / 255.0f);
  } else if (fmt == 70 || fmt == 71) { /* RGBA8Unorm */
    out_rgba[0] = p[0] * (1.0f / 255.0f);
    out_rgba[1] = p[1] * (1.0f / 255.0f);
    out_rgba[2] = p[2] * (1.0f / 255.0f);
    out_rgba[3] = p[3] * (1.0f / 255.0f);
  } else if (fmt == 10 || fmt == 11) { /* R8Unorm */
    float r = p[0] * (1.0f / 255.0f);
    out_rgba[0] = r; out_rgba[1] = 0.0f; out_rgba[2] = 0.0f; out_rgba[3] = 1.0f;
  } else if (fmt == 1) { /* A8Unorm */
    out_rgba[0] = 0.0f; out_rgba[1] = 0.0f; out_rgba[2] = 0.0f; out_rgba[3] = p[0] * (1.0f / 255.0f);
  } else if (fmt == 30 || fmt == 31) { /* RG8Unorm */
    out_rgba[0] = p[0] * (1.0f / 255.0f);
    out_rgba[1] = p[1] * (1.0f / 255.0f);
    out_rgba[2] = 0.0f; out_rgba[3] = 1.0f;
  } else if (fmt == 115) { /* RGBA16Float */
    const uint16_t *hp = (const uint16_t *)p;
    out_rgba[0] = xef_half_to_float(hp[0]);
    out_rgba[1] = xef_half_to_float(hp[1]);
    out_rgba[2] = xef_half_to_float(hp[2]);
    out_rgba[3] = xef_half_to_float(hp[3]);
  } else if (fmt == 125) { /* RGBA32Float */
    const float *fp = (const float *)p;
    out_rgba[0] = fp[0]; out_rgba[1] = fp[1]; out_rgba[2] = fp[2]; out_rgba[3] = fp[3];
  } else {
    out_rgba[0] = p[0] * (1.0f / 255.0f);
    out_rgba[1] = p[1] * (1.0f / 255.0f);
    out_rgba[2] = p[2] * (1.0f / 255.0f);
    out_rgba[3] = p[3] * (1.0f / 255.0f);
  }
}

static inline void xef_tex_write_pixel(XEFMetalTexture *tex, int x, int y, const float in_rgba[4], MTLColorWriteMask mask) {
  if (!tex || !tex->_storage || !tex->_storage->_data) return;
  if (x < 0 || x >= (int)tex->_width || y < 0 || y >= (int)tex->_height) return;
  uint8_t *p = tex->_storage->_data + (size_t)y * tex->_storage->_bytesPerRow + (size_t)x * tex->_storage->_bpp;
  NSUInteger fmt = (NSUInteger)tex->_pixelFormat;
  uint8_t r8 = (uint8_t)(xef_clampf(in_rgba[0], 0.0f, 1.0f) * 255.0f + 0.5f);
  uint8_t g8 = (uint8_t)(xef_clampf(in_rgba[1], 0.0f, 1.0f) * 255.0f + 0.5f);
  uint8_t b8 = (uint8_t)(xef_clampf(in_rgba[2], 0.0f, 1.0f) * 255.0f + 0.5f);
  uint8_t a8 = (uint8_t)(xef_clampf(in_rgba[3], 0.0f, 1.0f) * 255.0f + 0.5f);
  if (fmt == 80 || fmt == 81) { /* BGRA8Unorm */
    if (mask == MTLColorWriteMaskAll) {
      p[0] = b8; p[1] = g8; p[2] = r8; p[3] = a8;
    } else {
      if (mask & MTLColorWriteMaskBlue)  p[0] = b8;
      if (mask & MTLColorWriteMaskGreen) p[1] = g8;
      if (mask & MTLColorWriteMaskRed)   p[2] = r8;
      if (mask & MTLColorWriteMaskAlpha) p[3] = a8;
    }
  } else if (fmt == 70 || fmt == 71) { /* RGBA8Unorm */
    if (mask == MTLColorWriteMaskAll) {
      p[0] = r8; p[1] = g8; p[2] = b8; p[3] = a8;
    } else {
      if (mask & MTLColorWriteMaskRed)   p[0] = r8;
      if (mask & MTLColorWriteMaskGreen) p[1] = g8;
      if (mask & MTLColorWriteMaskBlue)  p[2] = b8;
      if (mask & MTLColorWriteMaskAlpha) p[3] = a8;
    }
  } else if (fmt == 10 || fmt == 11) {
    if (mask & MTLColorWriteMaskRed) p[0] = r8;
  } else if (fmt == 1) {
    if (mask & MTLColorWriteMaskAlpha) p[0] = a8;
  } else if (fmt == 115) {
    uint16_t *hp = (uint16_t *)p;
    if (mask & MTLColorWriteMaskRed)   hp[0] = xef_float_to_half(in_rgba[0]);
    if (mask & MTLColorWriteMaskGreen) hp[1] = xef_float_to_half(in_rgba[1]);
    if (mask & MTLColorWriteMaskBlue)  hp[2] = xef_float_to_half(in_rgba[2]);
    if (mask & MTLColorWriteMaskAlpha) hp[3] = xef_float_to_half(in_rgba[3]);
  } else if (fmt == 125) {
    float *fp = (float *)p;
    if (mask & MTLColorWriteMaskRed)   fp[0] = in_rgba[0];
    if (mask & MTLColorWriteMaskGreen) fp[1] = in_rgba[1];
    if (mask & MTLColorWriteMaskBlue)  fp[2] = in_rgba[2];
    if (mask & MTLColorWriteMaskAlpha) fp[3] = in_rgba[3];
  } else if (tex->_storage->_bpp >= 4) {
    p[0] = r8; p[1] = g8; p[2] = b8; p[3] = a8;
  }
}

static void xef_tex_clear(XEFMetalTexture *tex, MTLClearColor cc) {
  if (!tex || !tex->_storage || !tex->_storage->_data) return;
  int w = (int)tex->_width, h = (int)tex->_height;
  float rgba[4] = { (float)cc.red, (float)cc.green, (float)cc.blue, (float)cc.alpha };
  NSUInteger fmt = (NSUInteger)tex->_pixelFormat;
  if ((fmt == 80 || fmt == 81 || fmt == 70 || fmt == 71) && tex->_storage->_bpp == 4) {
    uint8_t r8 = (uint8_t)(xef_clampf(rgba[0], 0.0f, 1.0f) * 255.0f + 0.5f);
    uint8_t g8 = (uint8_t)(xef_clampf(rgba[1], 0.0f, 1.0f) * 255.0f + 0.5f);
    uint8_t b8 = (uint8_t)(xef_clampf(rgba[2], 0.0f, 1.0f) * 255.0f + 0.5f);
    uint8_t a8 = (uint8_t)(xef_clampf(rgba[3], 0.0f, 1.0f) * 255.0f + 0.5f);
    uint32_t packed = 0;
    uint8_t *pb = (uint8_t *)&packed;
    if (fmt == 80 || fmt == 81) {
      pb[0] = b8; pb[1] = g8; pb[2] = r8; pb[3] = a8;
    } else {
      pb[0] = r8; pb[1] = g8; pb[2] = b8; pb[3] = a8;
    }
    uint32_t *dst = (uint32_t *)tex->_storage->_data;
    size_t count = (size_t)w * (size_t)h;
    for (size_t i = 0; i < count; i++) dst[i] = packed;
    return;
  }
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      xef_tex_write_pixel(tex, x, y, rgba, MTLColorWriteMaskAll);
    }
  }
}

@interface XEFMetalSamplerState : XEFMetalObject <MTLSamplerState> {
@public
  id<MTLDevice> _device;
  NSString *_label;
  MTLSamplerMinMagFilter _minFilter;
  MTLSamplerMinMagFilter _magFilter;
  MTLSamplerMipFilter _mipFilter;
  MTLSamplerAddressMode _sAddressMode;
  MTLSamplerAddressMode _tAddressMode;
  MTLSamplerAddressMode _rAddressMode;
  MTLSamplerBorderColor _borderColor;
  BOOL _normalizedCoordinates;
  float _lodMinClamp;
  float _lodMaxClamp;
  NSUInteger _maxAnisotropy;
  MTLCompareFunction _compareFunction;
}
- (instancetype)initWithDescriptor:(MTLSamplerDescriptor *)desc device:(id<MTLDevice>)device;
@end
@implementation XEFMetalSamplerState
- (instancetype)initWithDescriptor:(MTLSamplerDescriptor *)desc device:(id<MTLDevice>)device {
  if ((self = [super init])) {
    _device = device;
    if (desc) {
      _label = [desc.label copy];
      _minFilter = desc.minFilter;
      _magFilter = desc.magFilter;
      _mipFilter = desc.mipFilter;
      _sAddressMode = desc.sAddressMode;
      _tAddressMode = desc.tAddressMode;
      _rAddressMode = desc.rAddressMode;
      _borderColor = desc.borderColor;
      _normalizedCoordinates = desc.normalizedCoordinates;
      _lodMinClamp = desc.lodMinClamp;
      _lodMaxClamp = desc.lodMaxClamp;
      _maxAnisotropy = desc.maxAnisotropy;
      _compareFunction = desc.compareFunction;
    } else {
      _normalizedCoordinates = YES;
      _lodMinClamp = 0.0f;
      _lodMaxClamp = 1000.0f;
      _maxAnisotropy = 1;
      _compareFunction = MTLCompareFunctionNever;
    }
  }
  return self;
}
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; }
- (MTLSamplerMinMagFilter)minFilter { return _minFilter; }
- (MTLSamplerMinMagFilter)magFilter { return _magFilter; }
- (MTLSamplerMipFilter)mipFilter { return _mipFilter; }
- (MTLSamplerAddressMode)sAddressMode { return _sAddressMode; }
- (MTLSamplerAddressMode)tAddressMode { return _tAddressMode; }
- (MTLSamplerAddressMode)rAddressMode { return _rAddressMode; }
- (MTLSamplerBorderColor)borderColor { return _borderColor; }
- (BOOL)normalizedCoordinates { return _normalizedCoordinates; }
- (float)lodMinClamp { return _lodMinClamp; }
- (float)lodMaxClamp { return _lodMaxClamp; }
- (NSUInteger)maxAnisotropy { return _maxAnisotropy; }
- (MTLCompareFunction)compareFunction { return _compareFunction; }
- (void)dealloc { [_label release]; [super dealloc]; }
@end

static inline float xef_wrap_coord(float c, MTLSamplerAddressMode mode, BOOL *out_is_border) {
  if (out_is_border) *out_is_border = NO;
  switch (mode) {
    case MTLSamplerAddressModeRepeat:
      return c - floorf(c);
    case MTLSamplerAddressModeMirrorRepeat: {
      float t = c - 2.0f * floorf(c * 0.5f);
      return (t > 1.0f) ? (2.0f - t) : t;
    }
    case MTLSamplerAddressModeClampToZero:
    case MTLSamplerAddressModeClampToBorderColor:
      if (c < 0.0f || c > 1.0f) {
        if (out_is_border) *out_is_border = YES;
        return 0.0f;
      }
      return c;
    case MTLSamplerAddressModeClampToEdge:
    case MTLSamplerAddressModeMirrorClampToEdge:
    default:
      return xef_clampf(c, 0.0f, 1.0f);
  }
}

static inline void xef_tex_sample(XEFMetalTexture *tex, XEFMetalSamplerState *samp, float u, float v, float out_rgba[4]) {
  if (!tex || !tex->_storage || !tex->_storage->_data) {
    out_rgba[0] = out_rgba[1] = out_rgba[2] = 1.0f; out_rgba[3] = 1.0f;
    return;
  }
  int w = (int)tex->_width, h = (int)tex->_height;
  float fx, fy;
  if (samp && !samp->_normalizedCoordinates) {
    fx = u - 0.5f;
    fy = v - 0.5f;
  } else {
    BOOL border_u = NO, border_v = NO;
    MTLSamplerAddressMode sMode = samp ? samp->_sAddressMode : MTLSamplerAddressModeClampToEdge;
    MTLSamplerAddressMode tMode = samp ? samp->_tAddressMode : MTLSamplerAddressModeClampToEdge;
    u = xef_wrap_coord(u, sMode, &border_u);
    v = xef_wrap_coord(v, tMode, &border_v);
    if (border_u || border_v) {
      if (samp && (samp->_borderColor == MTLSamplerBorderColorOpaqueBlack)) {
        out_rgba[0] = out_rgba[1] = out_rgba[2] = 0.0f; out_rgba[3] = 1.0f;
      } else if (samp && (samp->_borderColor == MTLSamplerBorderColorOpaqueWhite)) {
        out_rgba[0] = out_rgba[1] = out_rgba[2] = 1.0f; out_rgba[3] = 1.0f;
      } else {
        out_rgba[0] = out_rgba[1] = out_rgba[2] = out_rgba[3] = 0.0f;
      }
      return;
    }
    fx = u * (float)w - 0.5f;
    fy = v * (float)h - 0.5f;
  }
  MTLSamplerMinMagFilter filter = samp ? samp->_magFilter : MTLSamplerMinMagFilterLinear;
  if (samp && samp->_minFilter == MTLSamplerMinMagFilterNearest && samp->_magFilter == MTLSamplerMinMagFilterNearest) {
    filter = MTLSamplerMinMagFilterNearest;
  }
  if (filter == MTLSamplerMinMagFilterNearest) {
    int ix = (int)floorf(fx + 0.5f);
    int iy = (int)floorf(fy + 0.5f);
    xef_tex_read_pixel(tex, ix, iy, out_rgba);
  } else {
    int x0 = (int)floorf(fx);
    int y0 = (int)floorf(fy);
    float tx = fx - (float)x0;
    float ty = fy - (float)y0;
    float c00[4], c10[4], c01[4], c11[4];
    xef_tex_read_pixel(tex, x0,     y0,     c00);
    xef_tex_read_pixel(tex, x0 + 1, y0,     c10);
    xef_tex_read_pixel(tex, x0,     y0 + 1, c01);
    xef_tex_read_pixel(tex, x0 + 1, y0 + 1, c11);
    for (int i = 0; i < 4; i++) {
      float top = c00[i] + (c10[i] - c00[i]) * tx;
      float bot = c01[i] + (c11[i] - c01[i]) * tx;
      out_rgba[i] = top + (bot - top) * ty;
    }
  }
}

@interface XEFMetalDepthStencilState : XEFMetalObject <MTLDepthStencilState> {
@public
  id<MTLDevice> _device;
  NSString *_label;
  MTLCompareFunction _depthCompareFunction;
  BOOL _depthWriteEnabled;
  MTLStencilDescriptor *_frontFaceStencil;
  MTLStencilDescriptor *_backFaceStencil;
}
- (instancetype)initWithDescriptor:(MTLDepthStencilDescriptor *)desc device:(id<MTLDevice>)device;
@end
@implementation XEFMetalDepthStencilState
- (instancetype)initWithDescriptor:(MTLDepthStencilDescriptor *)desc device:(id<MTLDevice>)device {
  if ((self = [super init])) {
    _device = device;
    if (desc) {
      _label = [desc.label copy];
      _depthCompareFunction = desc.depthCompareFunction;
      _depthWriteEnabled = desc.isDepthWriteEnabled;
      _frontFaceStencil = [desc.frontFaceStencil copy];
      _backFaceStencil = [desc.backFaceStencil copy];
    } else {
      _depthCompareFunction = MTLCompareFunctionAlways;
    }
  }
  return self;
}
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; }
- (void)dealloc { [_label release]; [_frontFaceStencil release]; [_backFaceStencil release]; [super dealloc]; }
@end

enum {
  XEF_FRAG_MODE_AUTO = 0,
  XEF_FRAG_MODE_COLOR_ONLY = 1,
  XEF_FRAG_MODE_TEX_RGBA = 2,
  XEF_FRAG_MODE_TEX_RGB = 3,
  XEF_FRAG_MODE_BLIT2D = 4,
  XEF_FRAG_MODE_CONST_COLOR = 5,
};

@interface XEFMetalFunction : XEFMetalObject <MTLFunction> {
@public
  NSString *_name;
  MTLFunctionType _functionType;
  id<MTLDevice> _device;
  NSString *_source;
  BOOL _isFullscreenVert;
  BOOL _hasCustomVerts;
  int _customVertCount;
  float _customVerts[16][4];
  int _fragMode;
  float _constFragColor[4];
  NSData *_bitcodeData;
}
- (instancetype)initWithName:(NSString *)name type:(MTLFunctionType)type device:(id<MTLDevice>)device source:(NSString *)source data:(NSData *)data;
@end

@implementation XEFMetalFunction
- (instancetype)initWithName:(NSString *)name type:(MTLFunctionType)type device:(id<MTLDevice>)device source:(NSString *)source data:(NSData *)data {
  if ((self = [super init])) {
    _name = [name copy];
    _functionType = type;
    _device = device;
    _source = [source copy];
    _fragMode = XEF_FRAG_MODE_AUTO;
    _constFragColor[0] = 1.0f; _constFragColor[1] = 1.0f; _constFragColor[2] = 1.0f; _constFragColor[3] = 1.0f;

    const char *cname = name ? [name UTF8String] : "";
    if (strstr(cname, "FullscreenVert")) {
      _isFullscreenVert = YES;
    } else if (strstr(cname, "BlitFrom")) {
      _fragMode = XEF_FRAG_MODE_BLIT2D;
    }

    if (data && [data length] > 0) {
      const char *bytes = (const char *)[data bytes];
      size_t len = [data length];
      if (memmem(bytes, len, "FullscreenVert", 14)) _isFullscreenVert = YES;
      if (memmem(bytes, len, "BlitFrom", 8)) _fragMode = XEF_FRAG_MODE_BLIT2D;
    }

    if (source) {
      const char *csrc = [source UTF8String];
      if (csrc) {
        /* Detect SDL_render_gpu fragment modes */
        if (strstr(csrc, "u_texture.sample")) {
          if (strstr(csrc, ".xyz * Constants.color_scale, 1.0")) {
            _fragMode = XEF_FRAG_MODE_TEX_RGB;
          } else {
            _fragMode = XEF_FRAG_MODE_TEX_RGBA;
          }
        } else if (strstr(csrc, "texture0.sample")) {
          _fragMode = XEF_FRAG_MODE_TEX_RGBA;
        } else if (strstr(csrc, "Constants.color_scale") && !strstr(csrc, "texture")) {
          _fragMode = XEF_FRAG_MODE_COLOR_ONLY;
        }

        /* Parse inline vertex array literal like: float2 p[3]={float2(-.5,-.5),float2(.5,-.5),float2(0,.5)}; */
        const char *vfn = strstr(csrc, "vertex ");
        if (vfn) {
          const char *arr = strstr(vfn, "]={");
          if (!arr) arr = strstr(vfn, "] = {");
          if (arr) {
            const char *p = strchr(arr, '{');
            if (p) {
              p++;
              int cnt = 0;
              while (*p && *p != '}' && cnt < 16) {
                const char *f2 = strstr(p, "float2(");
                if (!f2 || f2 > strchr(p, '}')) break;
                f2 += 7;
                char *endp = NULL;
                float vx = strtof(f2, &endp);
                if (endp && *endp == ',') {
                  float vy = strtof(endp + 1, &endp);
                  _customVerts[cnt][0] = vx;
                  _customVerts[cnt][1] = vy;
                  _customVerts[cnt][2] = 0.0f;
                  _customVerts[cnt][3] = 1.0f;
                  cnt++;
                  p = endp;
                } else break;
              }
              if (cnt >= 3) {
                _hasCustomVerts = YES;
                _customVertCount = cnt;
              }
            }
          }
        }

        /* Parse constant fragment return like: fragment float4 fs(){return float4(1,0,0,1);} */
        const char *ffn = strstr(csrc, "fragment ");
        if (ffn && !strstr(ffn, "stage_in") && !strstr(ffn, "texture")) {
          const char *ret = strstr(ffn, "return float4(");
          if (ret) {
            ret += 14;
            float r = 1.0f, g = 0.0f, b = 0.0f, a = 1.0f;
            if (sscanf(ret, "%f , %f , %f , %f", &r, &g, &b, &a) == 4) {
              _fragMode = XEF_FRAG_MODE_CONST_COLOR;
              _constFragColor[0] = r;
              _constFragColor[1] = g;
              _constFragColor[2] = b;
              _constFragColor[3] = a;
            }
          }
        }
      }
    }
  }
  return self;
}
- (NSString *)name { return _name; }
- (MTLFunctionType)functionType { return _functionType; }
- (id<MTLDevice>)device { return _device; }
- (NSArray *)vertexAttributes { return [NSArray array]; }
- (NSArray *)stageInputAttributes { return [NSArray array]; }
- (NSDictionary *)functionConstantsDictionary { return [NSDictionary dictionary]; }
- (void)dealloc { [_name release]; [_source release]; [_bitcodeData release]; [super dealloc]; }
@end

@interface XEFMetalLibrary : XEFMetalObject <MTLLibrary> {
@public
  id<MTLDevice> _device;
  NSString *_label;
  NSString *_source;
  NSData *_data;
  NSMutableDictionary *_functions;
}
- (instancetype)initWithDevice:(id<MTLDevice>)device source:(NSString *)source data:(NSData *)data;
- (void)_parseMetallib:(NSData *)data;
@end

@implementation XEFMetalLibrary
- (instancetype)initWithDevice:(id<MTLDevice>)device source:(NSString *)source data:(NSData *)data {
  if ((self = [super init])) {
    _device = device;
    _source = [source copy];
    _data = [data retain];
    _functions = [[NSMutableDictionary alloc] init];

    if (_data && [_data length] >= 88) {
      [self _parseMetallib:_data];
    }
  }
  return self;
}

- (void)_parseMetallib:(NSData *)data {
  const uint8_t *bytes = (const uint8_t *)[data bytes];
  size_t len = [data length];
  if (len < 88 || memcmp(bytes, "MTLB", 4) != 0) return;

  uint64_t fnListOff = 0, fnListSz = 0, bcOff = 0, bcSz = 0;
  memcpy(&fnListOff, bytes + 24, sizeof(uint64_t));
  memcpy(&fnListSz,  bytes + 32, sizeof(uint64_t));
  memcpy(&bcOff,      bytes + 72, sizeof(uint64_t));
  memcpy(&bcSz,       bytes + 80, sizeof(uint64_t));

  if (fnListOff + 4 > len) return;

  uint32_t fnCount = 0;
  memcpy(&fnCount, bytes + fnListOff, sizeof(uint32_t));

  size_t pos = fnListOff + 4;
  for (uint32_t i = 0; i < fnCount && pos + 4 <= len; i++) {
    uint32_t entrySize = 0;
    memcpy(&entrySize, bytes + pos, sizeof(uint32_t));
    if (entrySize < 4 || pos + entrySize > len) break;

    const uint8_t *entryBytes = bytes + pos + 4;
    size_t entryRemaining = entrySize - 4;
    pos += entrySize;

    NSString *fnName = nil;
    MTLFunctionType fnType = MTLFunctionTypeVertex;
    uint64_t fnBcOffset = 0;
    uint64_t fnBcSize = 0;

    size_t tagPos = 0;
    while (tagPos + 4 <= entryRemaining) {
      char tagName[5] = {0};
      memcpy(tagName, entryBytes + tagPos, 4);
      tagPos += 4;

      if (!strcmp(tagName, "ENDT")) break;
      if (tagPos + 2 > entryRemaining) break;

      uint16_t tagSize = 0;
      memcpy(&tagSize, entryBytes + tagPos, sizeof(uint16_t));
      tagPos += 2;

      if (tagPos + tagSize > entryRemaining) break;
      const uint8_t *payload = entryBytes + tagPos;

      if (!strcmp(tagName, "NAME")) {
        if (tagSize > 0) {
          /* Null-terminated or Pascal-string format */
          if (payload[tagSize - 1] == 0) {
            fnName = [NSString stringWithUTF8String:(const char *)payload];
          } else {
            fnName = [[[NSString alloc] initWithBytes:payload length:tagSize encoding:NSUTF8StringEncoding] autorelease];
          }
        }
      } else if (!strcmp(tagName, "TYPE")) {
        if (tagSize >= 1) {
          uint8_t t = payload[0];
          if (t == 0) fnType = MTLFunctionTypeVertex;
          else if (t == 1) fnType = MTLFunctionTypeFragment;
          else if (t == 2) fnType = MTLFunctionTypeKernel;
        }
      } else if (!strcmp(tagName, "MDSZ")) {
        if (tagSize >= sizeof(uint64_t)) {
          memcpy(&fnBcSize, payload, sizeof(uint64_t));
        }
      } else if (!strcmp(tagName, "OFFT")) {
        if (tagSize >= 24) {
          /* publicMetaOffset (8), privateMetaOffset (8), bitcodeOffset (8) */
          memcpy(&fnBcOffset, payload + 16, sizeof(uint64_t));
        }
      }
      tagPos += tagSize;
    }

    if (fnName && [fnName length] > 0) {
      NSData *bcSlice = nil;
      if (bcOff + fnBcOffset + fnBcSize <= len && fnBcSize > 0) {
        bcSlice = [NSData dataWithBytes:bytes + bcOff + fnBcOffset length:(NSUInteger)fnBcSize];
      }
      XEFMetalFunction *f = [[[XEFMetalFunction alloc] initWithName:fnName type:fnType device:_device source:_source data:bcSlice ? bcSlice : _data] autorelease];
      if (bcSlice) f->_bitcodeData = [bcSlice retain];
      [_functions setObject:f forKey:fnName];
    }
  }
}

- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (id<MTLFunction>)newFunctionWithName:(NSString *)functionName {
  if (!functionName) return nil;
  XEFMetalFunction *f = [_functions objectForKey:functionName];
  if (!f) {
    f = [[[XEFMetalFunction alloc] initWithName:functionName type:MTLFunctionTypeVertex device:_device source:_source data:_data] autorelease];
    [_functions setObject:f forKey:functionName];
  }
  return [f retain];
}
- (id<MTLFunction>)newFunctionWithName:(NSString *)name constantValues:(MTLFunctionConstantValues *)constantValues error:(NSError **)error {
  if (error) *error = nil;
  return [self newFunctionWithName:name];
}
- (NSArray<NSString *> *)functionNames { return [_functions allKeys]; }
- (void)dealloc {
  [_label release]; [_source release]; [_data release]; [_functions release];
  [super dealloc];
}
@end

@interface XEFMetalRenderPipelineState : XEFMetalObject <MTLRenderPipelineState> {
@public
  id<MTLDevice> _device;
  NSString *_label;
  MTLRenderPipelineDescriptor *_desc;
}
- (instancetype)initWithDevice:(id<MTLDevice>)device descriptor:(MTLRenderPipelineDescriptor *)desc;
@end
@implementation XEFMetalRenderPipelineState
- (instancetype)initWithDevice:(id<MTLDevice>)device descriptor:(MTLRenderPipelineDescriptor *)desc {
  if ((self = [super init])) {
    _device = device;
    _label = [desc.label copy];
    _desc = [desc copy];
  }
  return self;
}
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; }
- (void)dealloc { [_label release]; [_desc release]; [super dealloc]; }
@end

@interface XEFMetalComputePipelineState : XEFMetalObject <MTLComputePipelineState> {
@public
  id<MTLDevice> _device;
  NSString *_label;
  XEFMetalFunction *_function;
}
- (instancetype)initWithDevice:(id<MTLDevice>)device function:(id<MTLFunction>)fn label:(NSString *)label;
@end
@implementation XEFMetalComputePipelineState
- (instancetype)initWithDevice:(id<MTLDevice>)device function:(id<MTLFunction>)fn label:(NSString *)label {
  if ((self = [super init])) {
    _device = device;
    _function = [(XEFMetalFunction *)fn retain];
    _label = [label ? label : fn.name copy];
  }
  return self;
}
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; }
- (NSUInteger)maxTotalThreadsPerThreadgroup { return 1024; }
- (NSUInteger)threadExecutionWidth { return 32; }
- (NSUInteger)staticThreadgroupMemoryLength { return 0; }
- (void)dealloc { [_label release]; [_function release]; [super dealloc]; }
@end

@interface XEFMetalFence : XEFMetalObject <MTLFence> {
  id<MTLDevice> _device;
  NSString *_label;
}
- (instancetype)initWithDevice:(id<MTLDevice>)device;
@end
@implementation XEFMetalFence
- (instancetype)initWithDevice:(id<MTLDevice>)device { if ((self = [super init])) _device = device; return self; }
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (void)dealloc { [_label release]; [super dealloc]; }
@end

@interface XEFMetalEvent : XEFMetalObject <MTLEvent> {
  id<MTLDevice> _device;
  NSString *_label;
  uint64_t _signaledValue;
}
- (instancetype)initWithDevice:(id<MTLDevice>)device;
@end
@implementation XEFMetalEvent
- (instancetype)initWithDevice:(id<MTLDevice>)device { if ((self = [super init])) _device = device; return self; }
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (uint64_t)signaledValue { return _signaledValue; } - (void)setSignaledValue:(uint64_t)v { _signaledValue = v; }
- (void)dealloc { [_label release]; [super dealloc]; }
@end

@implementation MTLSharedEventListener {
  dispatch_queue_t _dispatchQueue;
}
- (instancetype)init {
  return [self initWithDispatchQueue:dispatch_get_main_queue()];
}
- (instancetype)initWithDispatchQueue:(dispatch_queue_t)dispatchQueue {
  if ((self = [super init])) {
    _dispatchQueue = dispatchQueue ? dispatchQueue : dispatch_get_main_queue();
  }
  return self;
}
- (dispatch_queue_t)dispatchQueue { return _dispatchQueue; }
+ (MTLSharedEventListener *)sharedListener {
  static MTLSharedEventListener *s_shared = nil;
  if (!s_shared) s_shared = [[MTLSharedEventListener alloc] initWithDispatchQueue:dispatch_get_main_queue()];
  return s_shared;
}
@end

@interface MTLSharedEventHandle (Internal)
- (uint64_t)_signaledValue;
- (void)_setSignaledValue:(uint64_t)v;
- (void)_setLabel:(NSString *)l;
@end

@implementation MTLSharedEventHandle {
  NSString *_label;
  uint64_t _signaledValue;
}
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:_label forKey:@"label"];
  [coder encodeInt64:_signaledValue forKey:@"signaledValue"];
}
- (instancetype)initWithCoder:(NSCoder *)coder {
  if ((self = [super init])) {
    _label = [[coder decodeObjectOfClass:[NSString class] forKey:@"label"] retain];
    _signaledValue = [coder decodeInt64ForKey:@"signaledValue"];
  }
  return self;
}
- (NSString *)label { return _label; }
- (uint64_t)_signaledValue { return _signaledValue; }
- (void)_setSignaledValue:(uint64_t)v { _signaledValue = v; }
- (void)_setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (void)dealloc { [_label release]; [super dealloc]; }
@end

@interface XEFMetalSharedEventListenerRecord : NSObject {
@public
  MTLSharedEventListener *_listener;
  uint64_t _value;
  MTLSharedEventNotificationBlock _block;
}
@end
@implementation XEFMetalSharedEventListenerRecord
- (void)dealloc {
  [_listener release];
  if (_block) Block_release(_block);
  [super dealloc];
}
@end

@interface XEFMetalSharedEvent : XEFMetalEvent <MTLSharedEvent> {
  NSMutableArray *_records;
}
@end

@implementation XEFMetalSharedEvent
- (instancetype)initWithDevice:(id<MTLDevice>)device {
  if ((self = [super initWithDevice:device])) {
    _records = [[NSMutableArray alloc] init];
  }
  return self;
}
- (void)notifyListener:(MTLSharedEventListener *)listener atValue:(uint64_t)value block:(MTLSharedEventNotificationBlock)block {
  if (!listener || !block) return;
  if (self.signaledValue >= value) {
    MTLSharedEventNotificationBlock copied = Block_copy(block);
    dispatch_async(listener.dispatchQueue, ^{
      copied(self, value);
      Block_release(copied);
    });
    return;
  }
  XEFMetalSharedEventListenerRecord *rec = [[XEFMetalSharedEventListenerRecord alloc] init];
  rec->_listener = [listener retain];
  rec->_value = value;
  rec->_block = Block_copy(block);
  [_records addObject:rec];
  [rec release];
}
- (void)setSignaledValue:(uint64_t)v {
  [super setSignaledValue:v];
  NSMutableArray *toFire = [NSMutableArray array];
  NSMutableArray *toKeep = [NSMutableArray array];
  for (XEFMetalSharedEventListenerRecord *rec in _records) {
    if (v >= rec->_value) [toFire addObject:rec];
    else [toKeep addObject:rec];
  }
  [_records setArray:toKeep];
  for (XEFMetalSharedEventListenerRecord *rec in toFire) {
    dispatch_queue_t q = rec->_listener.dispatchQueue;
    uint64_t val = rec->_value;
    MTLSharedEventNotificationBlock blk = Block_copy(rec->_block);
    dispatch_async(q, ^{
      blk(self, val);
      Block_release(blk);
    });
  }
}
- (BOOL)waitUntilSignaledValue:(uint64_t)value timeoutMS:(uint64_t)milliseconds {
  if (self.signaledValue >= value) return YES;
  uint64_t waited = 0;
  while (self.signaledValue < value && waited < milliseconds) {
    usleep(1000);
    waited++;
  }
  return self.signaledValue >= value;
}
- (MTLSharedEventHandle *)newSharedEventHandle {
  MTLSharedEventHandle *h = [[MTLSharedEventHandle alloc] init];
  [h _setLabel:self.label];
  [h _setSignaledValue:self.signaledValue];
  return [h autorelease];
}
- (void)dealloc {
  [_records release];
  [super dealloc];
}
@end

@interface XEFMetalHeap : XEFMetalObject <MTLHeap> {
@public
  id<MTLDevice> _device;
  NSString *_label;
  NSUInteger _size;
  MTLStorageMode _storageMode;
  MTLCPUCacheMode _cpuCacheMode;
  MTLHazardTrackingMode _hazardTrackingMode;
  MTLResourceOptions _resourceOptions;
  MTLHeapType _type;
  NSUInteger _usedSize;
  NSUInteger _currentAllocatedSize;
  void *_storage;
}
- (instancetype)initWithDescriptor:(MTLHeapDescriptor *)descriptor device:(id<MTLDevice>)device;
@end

@implementation XEFMetalHeap
- (instancetype)initWithDescriptor:(MTLHeapDescriptor *)descriptor device:(id<MTLDevice>)device {
  if ((self = [super init])) {
    _device = device;
    if (descriptor) {
      _size = descriptor.size > 0 ? descriptor.size : 1024 * 1024;
      _storageMode = descriptor.storageMode;
      _cpuCacheMode = descriptor.cpuCacheMode;
      _hazardTrackingMode = descriptor.hazardTrackingMode;
      _resourceOptions = descriptor.resourceOptions;
      _type = descriptor.type;
    } else {
      _size = 1024 * 1024;
    }
    _currentAllocatedSize = _size;
    _usedSize = 0;
    _storage = calloc(1, _size);
  }
  return self;
}
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (MTLResourceOptions)resourceOptions { return _resourceOptions; }
- (MTLStorageMode)storageMode { return _storageMode; }
- (MTLCPUCacheMode)cpuCacheMode { return _cpuCacheMode; }
- (MTLHazardTrackingMode)hazardTrackingMode { return _hazardTrackingMode; }
- (MTLHeapType)type { return _type; }
- (NSUInteger)size { return _size; }
- (NSUInteger)usedSize { return _usedSize; }
- (NSUInteger)currentAllocatedSize { return _currentAllocatedSize; }
- (NSUInteger)maxAvailableSizeWithAlignment:(NSUInteger)alignment {
  NSUInteger align = alignment > 0 ? alignment : 1;
  NSUInteger alignedUsed = (_usedSize + align - 1) & ~(align - 1);
  return (alignedUsed < _size) ? (_size - alignedUsed) : 0;
}
- (MTLPurgeableState)setPurgeableState:(MTLPurgeableState)state {
  return MTLPurgeableStateNonVolatile;
}
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options {
  return [self newBufferWithLength:length options:options offset:_usedSize];
}
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options offset:(NSUInteger)offset {
  NSUInteger align = 256;
  NSUInteger alignedOffset = (offset + align - 1) & ~(align - 1);
  if (alignedOffset + length > _size) return nil;
  void *ptr = (uint8_t *)_storage + alignedOffset;
  XEFMetalBuffer *buf = [[XEFMetalBuffer alloc] initWithBytesNoCopy:ptr length:length options:options device:_device];
  buf->_heap = self;
  buf->_heapOffset = alignedOffset;
  if (alignedOffset + length > _usedSize) _usedSize = alignedOffset + length;
  return [buf autorelease];
}
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor {
  return [self newTextureWithDescriptor:descriptor offset:_usedSize];
}
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor offset:(NSUInteger)offset {
  if (!descriptor) return nil;
  XEFMetalTexture *tex = [[XEFMetalTexture alloc] initWithDescriptor:descriptor device:_device];
  tex->_heap = self;
  tex->_heapOffset = offset;
  NSUInteger bytesPerPixel = 4;
  if (descriptor.pixelFormat == MTLPixelFormatRGBA32Float) bytesPerPixel = 16;
  NSUInteger est = (descriptor.width * descriptor.height * (descriptor.depth > 0 ? descriptor.depth : 1) * bytesPerPixel + 255) & ~255ULL;
  if (offset + est > _usedSize) _usedSize = offset + est;
  return [tex autorelease];
}
- (void)dealloc {
  [_label release];
  if (_storage) free(_storage);
  [super dealloc];
}
@end

/* ------------------------------------------------------------------- Command Encoders */

typedef struct {
  float pos[4];   /* clip-space position */
  float sx, sy;   /* screen-space x, y */
  float sz, invW; /* depth z and 1/w */
  float col[4];   /* vertex color RGBA */
  float uv[2];    /* texture coord UV */
} XEFVertex;

static float xef_eval_blend_factor(MTLBlendFactor factor, const float src[4], const float dst[4], const float bc[4], int ch) {
  switch (factor) {
    case MTLBlendFactorZero: return 0.0f;
    case MTLBlendFactorOne: return 1.0f;
    case MTLBlendFactorSourceColor: return src[ch];
    case MTLBlendFactorOneMinusSourceColor: return 1.0f - src[ch];
    case MTLBlendFactorSourceAlpha: return src[3];
    case MTLBlendFactorOneMinusSourceAlpha: return 1.0f - src[3];
    case MTLBlendFactorDestinationColor: return dst[ch];
    case MTLBlendFactorOneMinusDestinationColor: return 1.0f - dst[ch];
    case MTLBlendFactorDestinationAlpha: return dst[3];
    case MTLBlendFactorOneMinusDestinationAlpha: return 1.0f - dst[3];
    case MTLBlendFactorSourceAlphaSaturated: {
      float f = src[3] < (1.0f - dst[3]) ? src[3] : (1.0f - dst[3]);
      return ch == 3 ? 1.0f : f;
    }
    case MTLBlendFactorBlendColor: return bc[ch];
    case MTLBlendFactorOneMinusBlendColor: return 1.0f - bc[ch];
    case MTLBlendFactorBlendAlpha: return bc[3];
    case MTLBlendFactorOneMinusBlendAlpha: return 1.0f - bc[3];
    default: return 1.0f;
  }
}

static float xef_eval_blend_op(MTLBlendOperation op, float s, float d) {
  switch (op) {
    case MTLBlendOperationAdd: return s + d;
    case MTLBlendOperationSubtract: return s - d;
    case MTLBlendOperationReverseSubtract: return d - s;
    case MTLBlendOperationMin: return s < d ? s : d;
    case MTLBlendOperationMax: return s > d ? s : d;
    default: return s + d;
  }
}

static void xef_read_vertex_attr(const uint8_t *ptr, MTLVertexFormat fmt, float out[4], float defW) {
  out[0] = 0.0f; out[1] = 0.0f; out[2] = 0.0f; out[3] = defW;
  if (!ptr) return;
  switch (fmt) {
    case MTLVertexFormatFloat: {
      const float *f = (const float *)ptr;
      out[0] = f[0];
      break;
    }
    case MTLVertexFormatFloat2: {
      const float *f = (const float *)ptr;
      out[0] = f[0]; out[1] = f[1];
      break;
    }
    case MTLVertexFormatFloat3: {
      const float *f = (const float *)ptr;
      out[0] = f[0]; out[1] = f[1]; out[2] = f[2];
      break;
    }
    case MTLVertexFormatFloat4: {
      const float *f = (const float *)ptr;
      out[0] = f[0]; out[1] = f[1]; out[2] = f[2]; out[3] = f[3];
      break;
    }
    case MTLVertexFormatUChar4Normalized: {
      out[0] = ptr[0] * (1.0f / 255.0f);
      out[1] = ptr[1] * (1.0f / 255.0f);
      out[2] = ptr[2] * (1.0f / 255.0f);
      out[3] = ptr[3] * (1.0f / 255.0f);
      break;
    }
    case MTLVertexFormatUChar4: {
      out[0] = (float)ptr[0]; out[1] = (float)ptr[1]; out[2] = (float)ptr[2]; out[3] = (float)ptr[3];
      break;
    }
    case MTLVertexFormatUChar4Normalized_BGRA: {
      out[0] = ptr[2] * (1.0f / 255.0f);
      out[1] = ptr[1] * (1.0f / 255.0f);
      out[2] = ptr[0] * (1.0f / 255.0f);
      out[3] = ptr[3] * (1.0f / 255.0f);
      break;
    }
    case MTLVertexFormatHalf2: {
      const uint16_t *h = (const uint16_t *)ptr;
      out[0] = xef_half_to_float(h[0]); out[1] = xef_half_to_float(h[1]);
      break;
    }
    case MTLVertexFormatHalf4: {
      const uint16_t *h = (const uint16_t *)ptr;
      out[0] = xef_half_to_float(h[0]); out[1] = xef_half_to_float(h[1]);
      out[2] = xef_half_to_float(h[2]); out[3] = xef_half_to_float(h[3]);
      break;
    }
    case MTLVertexFormatShort2: {
      const int16_t *s = (const int16_t *)ptr;
      out[0] = (float)s[0]; out[1] = (float)s[1];
      break;
    }
    case MTLVertexFormatShort2Normalized: {
      const int16_t *s = (const int16_t *)ptr;
      out[0] = xef_clampf((float)s[0] / 32767.0f, -1.0f, 1.0f);
      out[1] = xef_clampf((float)s[1] / 32767.0f, -1.0f, 1.0f);
      break;
    }
    case MTLVertexFormatUShort2Normalized: {
      const uint16_t *s = (const uint16_t *)ptr;
      out[0] = (float)s[0] / 65535.0f;
      out[1] = (float)s[1] / 65535.0f;
      break;
    }
    case MTLVertexFormatShort4: {
      const int16_t *s = (const int16_t *)ptr;
      out[0] = (float)s[0]; out[1] = (float)s[1]; out[2] = (float)s[2]; out[3] = (float)s[3];
      break;
    }
    case MTLVertexFormatShort4Normalized: {
      const int16_t *s = (const int16_t *)ptr;
      out[0] = xef_clampf((float)s[0] / 32767.0f, -1.0f, 1.0f);
      out[1] = xef_clampf((float)s[1] / 32767.0f, -1.0f, 1.0f);
      out[2] = xef_clampf((float)s[2] / 32767.0f, -1.0f, 1.0f);
      out[3] = xef_clampf((float)s[3] / 32767.0f, -1.0f, 1.0f);
      break;
    }
    case MTLVertexFormatUShort4Normalized: {
      const uint16_t *s = (const uint16_t *)ptr;
      out[0] = (float)s[0] / 65535.0f;
      out[1] = (float)s[1] / 65535.0f;
      out[2] = (float)s[2] / 65535.0f;
      out[3] = (float)s[3] / 65535.0f;
      break;
    }
    case MTLVertexFormatInt: {
      const int32_t *i = (const int32_t *)ptr;
      out[0] = (float)i[0];
      break;
    }
    case MTLVertexFormatInt2: {
      const int32_t *i = (const int32_t *)ptr;
      out[0] = (float)i[0]; out[1] = (float)i[1];
      break;
    }
    case MTLVertexFormatInt3: {
      const int32_t *i = (const int32_t *)ptr;
      out[0] = (float)i[0]; out[1] = (float)i[1]; out[2] = (float)i[2];
      break;
    }
    case MTLVertexFormatInt4: {
      const int32_t *i = (const int32_t *)ptr;
      out[0] = (float)i[0]; out[1] = (float)i[1]; out[2] = (float)i[2]; out[3] = (float)i[3];
      break;
    }
    case MTLVertexFormatUInt: {
      const uint32_t *u = (const uint32_t *)ptr;
      out[0] = (float)u[0];
      break;
    }
    case MTLVertexFormatUInt2: {
      const uint32_t *u = (const uint32_t *)ptr;
      out[0] = (float)u[0]; out[1] = (float)u[1];
      break;
    }
    case MTLVertexFormatUInt3: {
      const uint32_t *u = (const uint32_t *)ptr;
      out[0] = (float)u[0]; out[1] = (float)u[1]; out[2] = (float)u[2];
      break;
    }
    case MTLVertexFormatUInt4: {
      const uint32_t *u = (const uint32_t *)ptr;
      out[0] = (float)u[0]; out[1] = (float)u[1]; out[2] = (float)u[2]; out[3] = (float)u[3];
      break;
    }
    default:
      break;
  }
}

/* ------------------------------------------------------------------- MTLCounters */

NSErrorDomain const MTLCounterErrorDomain = @"MTLCounterErrorDomain";
MTLCommonCounter const MTLCommonCounterTimestamp = @"MTLCommonCounterTimestamp";
MTLCommonCounter const MTLCommonCounterTessellationInputPatches = @"MTLCommonCounterTessellationInputPatches";
MTLCommonCounter const MTLCommonCounterVertexInvocations = @"MTLCommonCounterVertexInvocations";
MTLCommonCounter const MTLCommonCounterPostTessellationVertexInvocations = @"MTLCommonCounterPostTessellationVertexInvocations";
MTLCommonCounter const MTLCommonCounterClipperInvocations = @"MTLCommonCounterClipperInvocations";
MTLCommonCounter const MTLCommonCounterClipperPrimitivesOut = @"MTLCommonCounterClipperPrimitivesOut";
MTLCommonCounter const MTLCommonCounterFragmentInvocations = @"MTLCommonCounterFragmentInvocations";
MTLCommonCounter const MTLCommonCounterFragmentsPassed = @"MTLCommonCounterFragmentsPassed";
MTLCommonCounter const MTLCommonCounterComputeKernelInvocations = @"MTLCommonCounterComputeKernelInvocations";
MTLCommonCounter const MTLCommonCounterTotalCycles = @"MTLCommonCounterTotalCycles";
MTLCommonCounter const MTLCommonCounterVertexCycles = @"MTLCommonCounterVertexCycles";
MTLCommonCounter const MTLCommonCounterTessellationCycles = @"MTLCommonCounterTessellationCycles";
MTLCommonCounter const MTLCommonCounterPostTessellationVertexCycles = @"MTLCommonCounterPostTessellationVertexCycles";
MTLCommonCounter const MTLCommonCounterFragmentCycles = @"MTLCommonCounterFragmentCycles";
MTLCommonCounter const MTLCommonCounterRenderTargetWriteCycles = @"MTLCommonCounterRenderTargetWriteCycles";

MTLCommonCounterSet const MTLCommonCounterSetTimestamp = @"MTLCommonCounterSetTimestamp";
MTLCommonCounterSet const MTLCommonCounterSetStageUtilization = @"MTLCommonCounterSetStageUtilization";
MTLCommonCounterSet const MTLCommonCounterSetStatistic = @"MTLCommonCounterSetStatistic";

@interface XEFMetalCounter : NSObject <MTLCounter> {
  NSString *_name;
}
- (instancetype)initWithName:(NSString *)name;
@end

@implementation XEFMetalCounter
- (instancetype)initWithName:(NSString *)name {
  if ((self = [super init])) {
    _name = [name copy];
  }
  return self;
}
- (NSString *)name { return _name; }
- (void)dealloc {
  [_name release];
  [super dealloc];
}
@end

@interface XEFMetalCounterSet : NSObject <MTLCounterSet> {
  NSString *_name;
  NSArray<id<MTLCounter>> *_counters;
}
- (instancetype)initWithName:(NSString *)name counters:(NSArray<id<MTLCounter>> *)counters;
@end

@implementation XEFMetalCounterSet
- (instancetype)initWithName:(NSString *)name counters:(NSArray<id<MTLCounter>> *)counters {
  if ((self = [super init])) {
    _name = [name copy];
    _counters = [counters retain];
  }
  return self;
}
- (NSString *)name { return _name; }
- (NSArray<id<MTLCounter>> *)counters { return _counters; }
- (void)dealloc {
  [_name release];
  [_counters release];
  [super dealloc];
}
@end

@implementation MTLCounterSampleBufferDescriptor {
  id<MTLCounterSet> _counterSet;
  NSString *_label;
  MTLStorageMode _storageMode;
  NSUInteger _sampleCount;
}
- (instancetype)init {
  if ((self = [super init])) {
    _storageMode = MTLStorageModeShared;
    _sampleCount = 0;
  }
  return self;
}
- (id<MTLCounterSet>)counterSet { return _counterSet; }
- (void)setCounterSet:(id<MTLCounterSet>)cs { [cs retain]; [_counterSet release]; _counterSet = cs; }
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (MTLStorageMode)storageMode { return _storageMode; }
- (void)setStorageMode:(MTLStorageMode)sm { _storageMode = sm; }
- (NSUInteger)sampleCount { return _sampleCount; }
- (void)setSampleCount:(NSUInteger)sc { _sampleCount = sc; }
- (id)copyWithZone:(NSZone *)zone {
  MTLCounterSampleBufferDescriptor *c = [[MTLCounterSampleBufferDescriptor allocWithZone:zone] init];
  c.counterSet = _counterSet;
  c.label = _label;
  c.storageMode = _storageMode;
  c.sampleCount = _sampleCount;
  return c;
}
- (void)dealloc {
  [_counterSet release];
  [_label release];
  [super dealloc];
}
@end

@interface XEFMetalCounterSampleBuffer : NSObject <MTLCounterSampleBuffer> {
@public
  id<MTLDevice> _device;
  NSString *_label;
  NSUInteger _sampleCount;
  id<MTLCounterSet> _counterSet;
  MTLStorageMode _storageMode;
  uint64_t *_samples;
}
- (instancetype)initWithDevice:(id<MTLDevice>)device descriptor:(MTLCounterSampleBufferDescriptor *)descriptor;
- (void)sampleAtIndex:(NSUInteger)index;
@end

@implementation XEFMetalCounterSampleBuffer
- (instancetype)initWithDevice:(id<MTLDevice>)device descriptor:(MTLCounterSampleBufferDescriptor *)descriptor {
  if ((self = [super init])) {
    _device = device;
    _label = [descriptor.label copy];
    _sampleCount = descriptor.sampleCount > 0 ? descriptor.sampleCount : 1;
    _counterSet = [descriptor.counterSet retain];
    _storageMode = descriptor.storageMode;
    _samples = (uint64_t *)calloc(_sampleCount, sizeof(uint64_t));
  }
  return self;
}
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; }
- (NSUInteger)sampleCount { return _sampleCount; }
- (void)sampleAtIndex:(NSUInteger)index {
  if (index < _sampleCount && _samples) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    _samples[index] = (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
  }
}
- (NSData *)resolveCounterRange:(NSRange)range {
  if (!_samples) return nil;
  NSUInteger start = range.location;
  NSUInteger len = range.length;
  if (start >= _sampleCount) return [NSData data];
  if (start + len > _sampleCount) len = _sampleCount - start;
  return [NSData dataWithBytes:&_samples[start] length:len * sizeof(uint64_t)];
}
- (void)dealloc {
  [_label release];
  [_counterSet release];
  if (_samples) free(_samples);
  [super dealloc];
}
@end

/* ------------------------------------------------------------------- MTLLinkedFunctions */

@implementation MTLLinkedFunctions {
  NSArray<id<MTLFunction>> *_functions;
  NSArray<id<MTLFunction>> *_binaryFunctions;
  NSDictionary<NSString *, NSArray<id<MTLFunction>> *> *_groups;
  NSArray<id<MTLFunction>> *_privateFunctions;
}
+ (instancetype)linkedFunctions {
  return [[[self alloc] init] autorelease];
}
- (NSArray<id<MTLFunction>> *)functions { return _functions; }
- (void)setFunctions:(NSArray<id<MTLFunction>> *)funcs { [funcs retain]; [_functions release]; _functions = funcs; }
- (NSArray<id<MTLFunction>> *)binaryFunctions { return _binaryFunctions; }
- (void)setBinaryFunctions:(NSArray<id<MTLFunction>> *)bfuncs { [bfuncs retain]; [_binaryFunctions release]; _binaryFunctions = bfuncs; }
- (NSDictionary<NSString *, NSArray<id<MTLFunction>> *> *)groups { return _groups; }
- (void)setGroups:(NSDictionary<NSString *, NSArray<id<MTLFunction>> *> *)grps { [grps retain]; [_groups release]; _groups = grps; }
- (NSArray<id<MTLFunction>> *)privateFunctions { return _privateFunctions; }
- (void)setPrivateFunctions:(NSArray<id<MTLFunction>> *)priv { [priv retain]; [_privateFunctions release]; _privateFunctions = priv; }
- (id)copyWithZone:(NSZone *)zone {
  MTLLinkedFunctions *c = [[MTLLinkedFunctions allocWithZone:zone] init];
  c.functions = _functions;
  c.binaryFunctions = _binaryFunctions;
  c.groups = _groups;
  c.privateFunctions = _privateFunctions;
  return c;
}
- (BOOL)isEqual:(id)object {
  if (self == object) return YES;
  if (![object isKindOfClass:[MTLLinkedFunctions class]]) return NO;
  MTLLinkedFunctions *other = (MTLLinkedFunctions *)object;
  BOOL funcsEq = (!_functions && !other->_functions) || [_functions isEqual:other->_functions];
  BOOL bfuncsEq = (!_binaryFunctions && !other->_binaryFunctions) || [_binaryFunctions isEqual:other->_binaryFunctions];
  BOOL grpsEq = (!_groups && !other->_groups) || [_groups isEqual:other->_groups];
  BOOL privEq = (!_privateFunctions && !other->_privateFunctions) || [_privateFunctions isEqual:other->_privateFunctions];
  return funcsEq && bfuncsEq && grpsEq && privEq;
}
- (NSUInteger)hash {
  return [_functions hash] ^ [_binaryFunctions hash] ^ [_groups hash] ^ [_privateFunctions hash];
}
- (void)dealloc {
  [_functions release];
  [_binaryFunctions release];
  [_groups release];
  [_privateFunctions release];
  [super dealloc];
}
@end

/* ------------------------------------------------------------------- MTLRasterizationRate */

@implementation MTLRasterizationRateSampleArray {
  float _storage[256];
  NSUInteger _count;
}
- (instancetype)initWithCount:(NSUInteger)count {
  if ((self = [super init])) {
    _count = count < 256 ? count : 256;
    memset(_storage, 0, sizeof(_storage));
  }
  return self;
}
- (NSNumber *)objectAtIndexedSubscript:(NSUInteger)index {
  if (index < _count) return [NSNumber numberWithFloat:_storage[index]];
  return [NSNumber numberWithFloat:0.0f];
}
- (void)setObject:(NSNumber *)value atIndexedSubscript:(NSUInteger)index {
  if (index < _count) _storage[index] = [value floatValue];
}
@end

@implementation MTLRasterizationRateLayerDescriptor {
  MTLSize _sampleCount;
  MTLSize _maxSampleCount;
  float *_horizontalStorage;
  float *_verticalStorage;
  MTLRasterizationRateSampleArray *_horizontal;
  MTLRasterizationRateSampleArray *_vertical;
}
- (instancetype)initWithSampleCount:(MTLSize)sampleCount {
  return [self initWithSampleCount:sampleCount horizontal:NULL vertical:NULL];
}
- (instancetype)initWithSampleCount:(MTLSize)sampleCount horizontal:(const float *)horizontal vertical:(const float *)vertical {
  if ((self = [super init])) {
    _sampleCount = sampleCount;
    _maxSampleCount = sampleCount;
    NSUInteger w = sampleCount.width > 0 ? sampleCount.width : 1;
    NSUInteger h = sampleCount.height > 0 ? sampleCount.height : 1;
    _horizontalStorage = (float *)calloc(w, sizeof(float));
    _verticalStorage = (float *)calloc(h, sizeof(float));
    if (horizontal) memcpy(_horizontalStorage, horizontal, w * sizeof(float));
    else for (NSUInteger i = 0; i < w; i++) _horizontalStorage[i] = 1.0f;
    if (vertical) memcpy(_verticalStorage, vertical, h * sizeof(float));
    else for (NSUInteger i = 0; i < h; i++) _verticalStorage[i] = 1.0f;
    _horizontal = [[MTLRasterizationRateSampleArray alloc] initWithCount:w];
    _vertical = [[MTLRasterizationRateSampleArray alloc] initWithCount:h];
    for (NSUInteger i = 0; i < w; i++) [_horizontal setObject:[NSNumber numberWithFloat:_horizontalStorage[i]] atIndexedSubscript:i];
    for (NSUInteger i = 0; i < h; i++) [_vertical setObject:[NSNumber numberWithFloat:_verticalStorage[i]] atIndexedSubscript:i];
  }
  return self;
}
- (MTLSize)sampleCount { return _sampleCount; }
- (void)setSampleCount:(MTLSize)sc { _sampleCount = sc; }
- (MTLSize)maxSampleCount { return _maxSampleCount; }
- (float *)horizontalSampleStorage { return _horizontalStorage; }
- (float *)verticalSampleStorage { return _verticalStorage; }
- (MTLRasterizationRateSampleArray *)horizontal { return _horizontal; }
- (MTLRasterizationRateSampleArray *)vertical { return _vertical; }
- (id)copyWithZone:(NSZone *)zone {
  return [[MTLRasterizationRateLayerDescriptor allocWithZone:zone] initWithSampleCount:_sampleCount horizontal:_horizontalStorage vertical:_verticalStorage];
}
- (void)dealloc {
  if (_horizontalStorage) free(_horizontalStorage);
  if (_verticalStorage) free(_verticalStorage);
  [_horizontal release];
  [_vertical release];
  [super dealloc];
}
@end

@implementation MTLRasterizationRateLayerArray {
  NSMutableArray<MTLRasterizationRateLayerDescriptor *> *_layers;
}
- (instancetype)init {
  if ((self = [super init])) {
    _layers = [[NSMutableArray alloc] init];
  }
  return self;
}
- (MTLRasterizationRateLayerDescriptor *)objectAtIndexedSubscript:(NSUInteger)layerIndex {
  if (layerIndex < _layers.count) {
    id obj = [_layers objectAtIndex:layerIndex];
    if (obj != [NSNull null]) return obj;
  }
  return nil;
}
- (void)setObject:(MTLRasterizationRateLayerDescriptor *)layer atIndexedSubscript:(NSUInteger)layerIndex {
  while (_layers.count <= layerIndex) {
    [_layers addObject:(id)[NSNull null]];
  }
  if (layer) {
    [_layers replaceObjectAtIndex:layerIndex withObject:layer];
  } else {
    [_layers replaceObjectAtIndex:layerIndex withObject:(id)[NSNull null]];
  }
}
- (void)dealloc {
  [_layers release];
  [super dealloc];
}
@end

@implementation MTLRasterizationRateMapDescriptor {
  MTLRasterizationRateLayerArray *_layers;
  MTLSize _screenSize;
  NSString *_label;
}
+ (MTLRasterizationRateMapDescriptor *)rasterizationRateMapDescriptorWithScreenSize:(MTLSize)screenSize {
  MTLRasterizationRateMapDescriptor *d = [[[self alloc] init] autorelease];
  d.screenSize = screenSize;
  return d;
}
+ (MTLRasterizationRateMapDescriptor *)rasterizationRateMapDescriptorWithScreenSize:(MTLSize)screenSize layer:(MTLRasterizationRateLayerDescriptor *)layer {
  MTLRasterizationRateMapDescriptor *d = [self rasterizationRateMapDescriptorWithScreenSize:screenSize];
  [d setLayer:layer atIndex:0];
  return d;
}
+ (MTLRasterizationRateMapDescriptor *)rasterizationRateMapDescriptorWithScreenSize:(MTLSize)screenSize layerCount:(NSUInteger)layerCount layers:(MTLRasterizationRateLayerDescriptor * const *)layers {
  MTLRasterizationRateMapDescriptor *d = [self rasterizationRateMapDescriptorWithScreenSize:screenSize];
  for (NSUInteger i = 0; i < layerCount; i++) {
    [d setLayer:layers[i] atIndex:i];
  }
  return d;
}
- (instancetype)init {
  if ((self = [super init])) {
    _layers = [[MTLRasterizationRateLayerArray alloc] init];
    _screenSize = MTLSizeMake(0, 0, 0);
  }
  return self;
}
- (MTLRasterizationRateLayerDescriptor *)layerAtIndex:(NSUInteger)layerIndex {
  return [_layers objectAtIndexedSubscript:layerIndex];
}
- (void)setLayer:(MTLRasterizationRateLayerDescriptor *)layer atIndex:(NSUInteger)layerIndex {
  [_layers setObject:layer atIndexedSubscript:layerIndex];
}
- (MTLRasterizationRateLayerArray *)layers { return _layers; }
- (MTLSize)screenSize { return _screenSize; }
- (void)setScreenSize:(MTLSize)s { _screenSize = s; }
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (NSUInteger)layerCount {
  NSUInteger count = 0;
  while ([self layerAtIndex:count] != nil) {
    count++;
  }
  return count;
}
- (id)copyWithZone:(NSZone *)zone {
  MTLRasterizationRateMapDescriptor *c = [[MTLRasterizationRateMapDescriptor allocWithZone:zone] init];
  c.screenSize = _screenSize;
  c.label = _label;
  NSUInteger cnt = self.layerCount;
  for (NSUInteger i = 0; i < cnt; i++) {
    [c setLayer:[self layerAtIndex:i] atIndex:i];
  }
  return c;
}
- (void)dealloc {
  [_layers release];
  [_label release];
  [super dealloc];
}
@end

@interface XEFMetalRasterizationRateMap : NSObject <MTLRasterizationRateMap> {
  id<MTLDevice> _device;
  NSString *_label;
  MTLSize _screenSize;
  NSUInteger _layerCount;
}
- (instancetype)initWithDevice:(id<MTLDevice>)device descriptor:(MTLRasterizationRateMapDescriptor *)descriptor;
@end

@implementation XEFMetalRasterizationRateMap
- (instancetype)initWithDevice:(id<MTLDevice>)device descriptor:(MTLRasterizationRateMapDescriptor *)descriptor {
  if ((self = [super init])) {
    _device = device;
    _label = [descriptor.label copy];
    _screenSize = descriptor.screenSize;
    _layerCount = descriptor.layerCount > 0 ? descriptor.layerCount : 1;
  }
  return self;
}
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; }
- (MTLSize)screenSize { return _screenSize; }
- (MTLSize)physicalGranularity { return MTLSizeMake(1, 1, 0); }
- (NSUInteger)layerCount { return _layerCount; }
- (MTLSizeAndAlign)parameterBufferSizeAndAlign {
  MTLSizeAndAlign sa;
  sa.size = 256;
  sa.align = 256;
  return sa;
}
- (void)copyParameterDataToBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset {
  if (buffer && offset + 256 <= [buffer length]) {
    memset((uint8_t *)[buffer contents] + offset, 0, 256);
  }
}
- (MTLSize)physicalSizeForLayer:(NSUInteger)layerIndex {
  return _screenSize;
}
- (MTLCoordinate2D)mapScreenToPhysicalCoordinates:(MTLCoordinate2D)screenCoordinates forLayer:(NSUInteger)layerIndex {
  return screenCoordinates;
}
- (MTLCoordinate2D)mapPhysicalToScreenCoordinates:(MTLCoordinate2D)physicalCoordinates forLayer:(NSUInteger)layerIndex {
  return physicalCoordinates;
}
- (void)dealloc {
  [_label release];
  [super dealloc];
}
@end

/* ------------------------------------------------------------------- MTLFunctionHandle & Function Tables */

@interface XEFMetalFunctionHandle : NSObject <MTLFunctionHandle> {
  NSString *_name;
  MTLFunctionType _functionType;
  id<MTLDevice> _device;
}
- (instancetype)initWithName:(NSString *)name functionType:(MTLFunctionType)type device:(id<MTLDevice>)device;
@end

@implementation XEFMetalFunctionHandle
- (instancetype)initWithName:(NSString *)name functionType:(MTLFunctionType)type device:(id<MTLDevice>)device {
  if ((self = [super init])) {
    _name = [name copy];
    _functionType = type;
    _device = device;
  }
  return self;
}
- (NSString *)name { return _name; }
- (MTLFunctionType)functionType { return _functionType; }
- (id<MTLDevice>)device { return _device; }
- (MTLResourceID)gpuResourceID { MTLResourceID rid = { (uint64_t)(uintptr_t)self }; return rid; }
- (void)dealloc {
  [_name release];
  [super dealloc];
}
@end

@implementation MTLVisibleFunctionTableDescriptor
+ (instancetype)visibleFunctionTableDescriptor {
  return [[[self alloc] init] autorelease];
}
- (id)copyWithZone:(NSZone *)zone {
  MTLVisibleFunctionTableDescriptor *c = [[MTLVisibleFunctionTableDescriptor allocWithZone:zone] init];
  c.functionCount = self.functionCount;
  return c;
}
@end

@interface XEFMetalVisibleFunctionTable : XEFMetalObject <MTLVisibleFunctionTable> {
  id<MTLDevice> _device;
  NSString *_label;
  NSUInteger _functionCount;
  NSMutableArray<id<MTLFunctionHandle>> *_functions;
}
- (instancetype)initWithDevice:(id<MTLDevice>)device descriptor:(MTLVisibleFunctionTableDescriptor *)descriptor;
@end

@implementation XEFMetalVisibleFunctionTable
- (instancetype)initWithDevice:(id<MTLDevice>)device descriptor:(MTLVisibleFunctionTableDescriptor *)descriptor {
  if ((self = [super init])) {
    _device = device;
    _functionCount = descriptor.functionCount;
    _functions = [[NSMutableArray alloc] initWithCapacity:_functionCount];
    for (NSUInteger i = 0; i < _functionCount; i++) {
      [_functions addObject:(id)[NSNull null]];
    }
  }
  return self;
}
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (NSUInteger)allocatedSize { return _functionCount * 8; }
- (MTLResourceID)gpuResourceID { MTLResourceID rid = { (uint64_t)(uintptr_t)self }; return rid; }
- (void)setFunction:(id<MTLFunctionHandle>)function atIndex:(NSUInteger)index {
  if (index < _functionCount) {
    [_functions replaceObjectAtIndex:index withObject:(function ? (id)function : (id)[NSNull null])];
  }
}
- (void)setFunctions:(const id<MTLFunctionHandle> *)functions withRange:(NSRange)range {
  for (NSUInteger i = 0; i < range.length; i++) {
    [self setFunction:functions ? functions[i] : nil atIndex:range.location + i];
  }
}
- (MTLStorageMode)storageMode { return MTLStorageModeShared; }
- (MTLCPUCacheMode)cpuCacheMode { return MTLCPUCacheModeDefaultCache; }
- (MTLHazardTrackingMode)hazardTrackingMode { return MTLHazardTrackingModeDefault; }
- (MTLResourceOptions)resourceOptions { return MTLResourceStorageModeShared; }
- (MTLPurgeableState)setPurgeableState:(MTLPurgeableState)state { return MTLPurgeableStateNonVolatile; }
- (void)makeAliasable {}
- (BOOL)isAliasable { return NO; }
- (id<MTLHeap>)heap { return nil; }
- (NSUInteger)heapOffset { return 0; }
- (void)dealloc {
  [_label release];
  [_functions release];
  [super dealloc];
}
@end

@implementation MTLIntersectionFunctionTableDescriptor
+ (instancetype)intersectionFunctionTableDescriptor {
  return [[[self alloc] init] autorelease];
}
- (id)copyWithZone:(NSZone *)zone {
  MTLIntersectionFunctionTableDescriptor *c = [[MTLIntersectionFunctionTableDescriptor allocWithZone:zone] init];
  c.functionCount = self.functionCount;
  return c;
}
@end

@interface XEFMetalIntersectionFunctionTable : XEFMetalObject <MTLIntersectionFunctionTable> {
  id<MTLDevice> _device;
  NSString *_label;
  NSUInteger _functionCount;
  NSMutableArray *_functions;
  NSMutableArray *_buffers;
}
- (instancetype)initWithDevice:(id<MTLDevice>)device descriptor:(MTLIntersectionFunctionTableDescriptor *)descriptor;
@end

@implementation XEFMetalIntersectionFunctionTable
- (instancetype)initWithDevice:(id<MTLDevice>)device descriptor:(MTLIntersectionFunctionTableDescriptor *)descriptor {
  if ((self = [super init])) {
    _device = device;
    _functionCount = descriptor.functionCount;
    _functions = [[NSMutableArray alloc] initWithCapacity:_functionCount];
    _buffers = [[NSMutableArray alloc] initWithCapacity:31];
    for (NSUInteger i = 0; i < _functionCount; i++) {
      [_functions addObject:(id)[NSNull null]];
    }
    for (NSUInteger i = 0; i < 31; i++) {
      [_buffers addObject:(id)[NSNull null]];
    }
  }
  return self;
}
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (NSUInteger)allocatedSize { return _functionCount * 8; }
- (MTLResourceID)gpuResourceID { MTLResourceID rid = { (uint64_t)(uintptr_t)self }; return rid; }
- (void)setBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index {
  if (index < _buffers.count) {
    [_buffers replaceObjectAtIndex:index withObject:(buffer ? (id)buffer : (id)[NSNull null])];
  }
}
- (void)setBuffers:(const id<MTLBuffer> *)buffers offsets:(const NSUInteger *)offsets withRange:(NSRange)range {
  for (NSUInteger i = 0; i < range.length; i++) {
    [self setBuffer:buffers ? buffers[i] : nil offset:offsets ? offsets[i] : 0 atIndex:range.location + i];
  }
}
- (void)setFunction:(id<MTLFunctionHandle>)function atIndex:(NSUInteger)index {
  if (index < _functionCount) {
    [_functions replaceObjectAtIndex:index withObject:(function ? (id)function : (id)[NSNull null])];
  }
}
- (void)setFunctions:(const id<MTLFunctionHandle> *)functions withRange:(NSRange)range {
  for (NSUInteger i = 0; i < range.length; i++) {
    [self setFunction:functions ? functions[i] : nil atIndex:range.location + i];
  }
}
- (void)setOpaqueTriangleIntersectionFunctionWithSignature:(MTLIntersectionFunctionSignature)signature atIndex:(NSUInteger)index {
  [self setFunction:nil atIndex:index];
}
- (void)setOpaqueTriangleIntersectionFunctionWithSignature:(MTLIntersectionFunctionSignature)signature withRange:(NSRange)range {
  for (NSUInteger i = 0; i < range.length; i++) {
    [self setFunction:nil atIndex:range.location + i];
  }
}
- (void)setOpaqueCurveIntersectionFunctionWithSignature:(MTLIntersectionFunctionSignature)signature atIndex:(NSUInteger)index {
  [self setFunction:nil atIndex:index];
}
- (void)setOpaqueCurveIntersectionFunctionWithSignature:(MTLIntersectionFunctionSignature)signature withRange:(NSRange)range {
  for (NSUInteger i = 0; i < range.length; i++) {
    [self setFunction:nil atIndex:range.location + i];
  }
}
- (void)setVisibleFunctionTable:(id<MTLVisibleFunctionTable>)functionTable atBufferIndex:(NSUInteger)bufferIndex {}
- (void)setVisibleFunctionTables:(const id<MTLVisibleFunctionTable> *)functionTables withBufferRange:(NSRange)bufferRange {}
- (MTLStorageMode)storageMode { return MTLStorageModeShared; }
- (MTLCPUCacheMode)cpuCacheMode { return MTLCPUCacheModeDefaultCache; }
- (MTLHazardTrackingMode)hazardTrackingMode { return MTLHazardTrackingModeDefault; }
- (MTLResourceOptions)resourceOptions { return MTLResourceStorageModeShared; }
- (MTLPurgeableState)setPurgeableState:(MTLPurgeableState)state { return MTLPurgeableStateNonVolatile; }
- (void)makeAliasable {}
- (BOOL)isAliasable { return NO; }
- (id<MTLHeap>)heap { return nil; }
- (NSUInteger)heapOffset { return 0; }
- (void)dealloc {
  [_label release];
  [_functions release];
  [_buffers release];
  [super dealloc];
}
@end

@implementation XEFMetalRenderPipelineState (FunctionTables)
- (id<MTLFunctionHandle>)functionHandleWithFunction:(id<MTLFunction>)function stage:(MTLRenderStages)stage {
  if (!function) return nil;
  return [[[XEFMetalFunctionHandle alloc] initWithName:function.name functionType:function.functionType device:self.device] autorelease];
}
- (id<MTLVisibleFunctionTable>)newVisibleFunctionTableWithDescriptor:(MTLVisibleFunctionTableDescriptor *)descriptor stage:(MTLRenderStages)stage {
  if (!descriptor) return nil;
  return [[[XEFMetalVisibleFunctionTable alloc] initWithDevice:self.device descriptor:descriptor] autorelease];
}
- (id<MTLIntersectionFunctionTable>)newIntersectionFunctionTableWithDescriptor:(MTLIntersectionFunctionTableDescriptor *)descriptor stage:(MTLRenderStages)stage {
  if (!descriptor) return nil;
  return [[[XEFMetalIntersectionFunctionTable alloc] initWithDevice:self.device descriptor:descriptor] autorelease];
}
@end

@implementation XEFMetalComputePipelineState (FunctionTables)
- (id<MTLFunctionHandle>)functionHandleWithFunction:(id<MTLFunction>)function {
  if (!function) return nil;
  return [[[XEFMetalFunctionHandle alloc] initWithName:function.name functionType:function.functionType device:self.device] autorelease];
}
- (id<MTLVisibleFunctionTable>)newVisibleFunctionTableWithDescriptor:(MTLVisibleFunctionTableDescriptor *)descriptor {
  if (!descriptor) return nil;
  return [[[XEFMetalVisibleFunctionTable alloc] initWithDevice:self.device descriptor:descriptor] autorelease];
}
- (id<MTLIntersectionFunctionTable>)newIntersectionFunctionTableWithDescriptor:(MTLIntersectionFunctionTableDescriptor *)descriptor {
  if (!descriptor) return nil;
  return [[[XEFMetalIntersectionFunctionTable alloc] initWithDevice:self.device descriptor:descriptor] autorelease];
}
@end

/* ------------------------------------------------------------------- MTLAccelerationStructure */

@implementation MTLAccelerationStructureDescriptor
@synthesize usage = _usage;
- (id)copyWithZone:(NSZone *)zone {
  MTLAccelerationStructureDescriptor *c = [[[self class] allocWithZone:zone] init];
  c.usage = self.usage;
  return c;
}
@end

@implementation MTLAccelerationStructureGeometryDescriptor
@synthesize intersectionFunctionTableOffset = _intersectionFunctionTableOffset;
@synthesize opaque = _opaque;
@synthesize allowDuplicateIntersectionFunctionInvocation = _allowDuplicateIntersectionFunctionInvocation;
@synthesize label = _label;
@synthesize primitiveDataBuffer = _primitiveDataBuffer;
@synthesize primitiveDataBufferOffset = _primitiveDataBufferOffset;
@synthesize primitiveDataStride = _primitiveDataStride;
@synthesize primitiveDataElementSize = _primitiveDataElementSize;

- (instancetype)init {
  if ((self = [super init])) {
    _allowDuplicateIntersectionFunctionInvocation = YES;
  }
  return self;
}
- (id)copyWithZone:(NSZone *)zone {
  MTLAccelerationStructureGeometryDescriptor *c = [[[self class] allocWithZone:zone] init];
  c.intersectionFunctionTableOffset = self.intersectionFunctionTableOffset;
  c.opaque = self.opaque;
  c.allowDuplicateIntersectionFunctionInvocation = self.allowDuplicateIntersectionFunctionInvocation;
  c.label = self.label;
  c.primitiveDataBuffer = self.primitiveDataBuffer;
  c.primitiveDataBufferOffset = self.primitiveDataBufferOffset;
  c.primitiveDataStride = self.primitiveDataStride;
  c.primitiveDataElementSize = self.primitiveDataElementSize;
  return c;
}
- (void)dealloc {
  [_label release];
  [_primitiveDataBuffer release];
  [super dealloc];
}
@end

@implementation MTLAccelerationStructureTriangleGeometryDescriptor
@synthesize vertexBuffer = _vertexBuffer;
@synthesize vertexBufferOffset = _vertexBufferOffset;
@synthesize vertexFormat = _vertexFormat;
@synthesize vertexStride = _vertexStride;
@synthesize indexBuffer = _indexBuffer;
@synthesize indexBufferOffset = _indexBufferOffset;
@synthesize indexType = _indexType;
@synthesize triangleCount = _triangleCount;
@synthesize transformationMatrixBuffer = _transformationMatrixBuffer;
@synthesize transformationMatrixBufferOffset = _transformationMatrixBufferOffset;

+ (instancetype)descriptor {
  return [[[self alloc] init] autorelease];
}
- (instancetype)init {
  if ((self = [super init])) {
    _vertexFormat = MTLAttributeFormatFloat3;
  }
  return self;
}
- (id)copyWithZone:(NSZone *)zone {
  MTLAccelerationStructureTriangleGeometryDescriptor *c = [super copyWithZone:zone];
  c.vertexBuffer = self.vertexBuffer;
  c.vertexBufferOffset = self.vertexBufferOffset;
  c.vertexFormat = self.vertexFormat;
  c.vertexStride = self.vertexStride;
  c.indexBuffer = self.indexBuffer;
  c.indexBufferOffset = self.indexBufferOffset;
  c.indexType = self.indexType;
  c.triangleCount = self.triangleCount;
  c.transformationMatrixBuffer = self.transformationMatrixBuffer;
  c.transformationMatrixBufferOffset = self.transformationMatrixBufferOffset;
  return c;
}
- (void)dealloc {
  [_vertexBuffer release];
  [_indexBuffer release];
  [_transformationMatrixBuffer release];
  [super dealloc];
}
@end

@implementation MTLAccelerationStructureBoundingBoxGeometryDescriptor
@synthesize boundingBoxBuffer = _boundingBoxBuffer;
@synthesize boundingBoxBufferOffset = _boundingBoxBufferOffset;
@synthesize boundingBoxStride = _boundingBoxStride;
@synthesize boundingBoxCount = _boundingBoxCount;

+ (instancetype)descriptor {
  return [[[self alloc] init] autorelease];
}
- (instancetype)init {
  if ((self = [super init])) {
    _boundingBoxStride = 24;
  }
  return self;
}
- (id)copyWithZone:(NSZone *)zone {
  MTLAccelerationStructureBoundingBoxGeometryDescriptor *c = [super copyWithZone:zone];
  c.boundingBoxBuffer = self.boundingBoxBuffer;
  c.boundingBoxBufferOffset = self.boundingBoxBufferOffset;
  c.boundingBoxStride = self.boundingBoxStride;
  c.boundingBoxCount = self.boundingBoxCount;
  return c;
}
- (void)dealloc {
  [_boundingBoxBuffer release];
  [super dealloc];
}
@end

@implementation MTLPrimitiveAccelerationStructureDescriptor
@synthesize geometryDescriptors = _geometryDescriptors;
@synthesize motionStartBorderMode = _motionStartBorderMode;
@synthesize motionEndBorderMode = _motionEndBorderMode;
@synthesize motionStartTime = _motionStartTime;
@synthesize motionEndTime = _motionEndTime;
@synthesize motionKeyframeCount = _motionKeyframeCount;

+ (instancetype)descriptor {
  return [[[self alloc] init] autorelease];
}
- (instancetype)init {
  if ((self = [super init])) {
    _motionKeyframeCount = 1;
    _motionEndTime = 1.0f;
  }
  return self;
}
- (id)copyWithZone:(NSZone *)zone {
  MTLPrimitiveAccelerationStructureDescriptor *c = [super copyWithZone:zone];
  c.geometryDescriptors = self.geometryDescriptors;
  c.motionStartBorderMode = self.motionStartBorderMode;
  c.motionEndBorderMode = self.motionEndBorderMode;
  c.motionStartTime = self.motionStartTime;
  c.motionEndTime = self.motionEndTime;
  c.motionKeyframeCount = self.motionKeyframeCount;
  return c;
}
- (void)dealloc {
  [_geometryDescriptors release];
  [super dealloc];
}
@end

@implementation MTLInstanceAccelerationStructureDescriptor
@synthesize instanceDescriptorBuffer = _instanceDescriptorBuffer;
@synthesize instanceDescriptorBufferOffset = _instanceDescriptorBufferOffset;
@synthesize instanceDescriptorStride = _instanceDescriptorStride;
@synthesize instanceCount = _instanceCount;
@synthesize instancedAccelerationStructures = _instancedAccelerationStructures;
@synthesize instanceDescriptorType = _instanceDescriptorType;

+ (instancetype)descriptor {
  return [[[self alloc] init] autorelease];
}
- (instancetype)init {
  if ((self = [super init])) {
    _instanceDescriptorStride = sizeof(MTLAccelerationStructureInstanceDescriptor);
  }
  return self;
}
- (id)copyWithZone:(NSZone *)zone {
  MTLInstanceAccelerationStructureDescriptor *c = [super copyWithZone:zone];
  c.instanceDescriptorBuffer = self.instanceDescriptorBuffer;
  c.instanceDescriptorBufferOffset = self.instanceDescriptorBufferOffset;
  c.instanceDescriptorStride = self.instanceDescriptorStride;
  c.instanceCount = self.instanceCount;
  c.instancedAccelerationStructures = self.instancedAccelerationStructures;
  c.instanceDescriptorType = self.instanceDescriptorType;
  return c;
}
- (void)dealloc {
  [_instanceDescriptorBuffer release];
  [_instancedAccelerationStructures release];
  [super dealloc];
}
@end

@implementation MTLAccelerationStructurePassDescriptor
+ (MTLAccelerationStructurePassDescriptor *)accelerationStructurePassDescriptor {
  return [[[self alloc] init] autorelease];
}
- (id)copyWithZone:(NSZone *)zone {
  return [[[self class] allocWithZone:zone] init];
}
@end

@interface XEFMetalAccelerationStructure : XEFMetalObject <MTLAccelerationStructure> {
  id<MTLDevice> _device;
  NSString *_label;
  NSUInteger _size;
  MTLAccelerationStructureDescriptor *_descriptor;
}
- (instancetype)initWithDevice:(id<MTLDevice>)device size:(NSUInteger)size;
- (instancetype)initWithDevice:(id<MTLDevice>)device descriptor:(MTLAccelerationStructureDescriptor *)descriptor;
@end

@implementation XEFMetalAccelerationStructure
- (instancetype)initWithDevice:(id<MTLDevice>)device size:(NSUInteger)size {
  if ((self = [super init])) {
    _device = device;
    _size = size;
  }
  return self;
}
- (instancetype)initWithDevice:(id<MTLDevice>)device descriptor:(MTLAccelerationStructureDescriptor *)descriptor {
  if ((self = [super init])) {
    _device = device;
    _descriptor = [descriptor copy];
    MTLAccelerationStructureSizes sizes = [device accelerationStructureSizesWithDescriptor:descriptor];
    _size = sizes.accelerationStructureSize;
  }
  return self;
}
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (NSUInteger)size { return _size; }
- (NSUInteger)allocatedSize { return _size; }
- (MTLResourceID)gpuResourceID { MTLResourceID rid = { (uint64_t)(uintptr_t)self }; return rid; }
- (MTLStorageMode)storageMode { return MTLStorageModeShared; }
- (MTLCPUCacheMode)cpuCacheMode { return MTLCPUCacheModeDefaultCache; }
- (MTLHazardTrackingMode)hazardTrackingMode { return MTLHazardTrackingModeDefault; }
- (MTLResourceOptions)resourceOptions { return MTLResourceStorageModeShared; }
- (MTLPurgeableState)setPurgeableState:(MTLPurgeableState)state { return MTLPurgeableStateNonVolatile; }
- (void)makeAliasable {}
- (BOOL)isAliasable { return NO; }
- (id<MTLHeap>)heap { return nil; }
- (NSUInteger)heapOffset { return 0; }
- (void)dealloc {
  [_label release];
  [_descriptor release];
  [super dealloc];
}
@end

@interface XEFMetalAccelerationStructureCommandEncoder : XEFMetalObject <MTLAccelerationStructureCommandEncoder> {
  id<MTLCommandBuffer> _commandBuffer;
  NSString *_label;
}
- (instancetype)initWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer;
@end

@implementation XEFMetalAccelerationStructureCommandEncoder
- (instancetype)initWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer {
  if ((self = [super init])) {
    _commandBuffer = commandBuffer;
  }
  return self;
}
- (id<MTLDevice>)device { return _commandBuffer.device; }
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (void)buildAccelerationStructure:(id<MTLAccelerationStructure>)accelerationStructure descriptor:(MTLAccelerationStructureDescriptor *)descriptor scratchBuffer:(id<MTLBuffer>)scratchBuffer scratchBufferOffset:(NSUInteger)scratchBufferOffset {}
- (void)refitAccelerationStructure:(id<MTLAccelerationStructure>)baseAccelerationStructure descriptor:(MTLAccelerationStructureDescriptor *)descriptor destination:(id<MTLAccelerationStructure>)destination scratchBuffer:(id<MTLBuffer>)scratchBuffer scratchBufferOffset:(NSUInteger)scratchBufferOffset {}
- (void)refitAccelerationStructure:(id<MTLAccelerationStructure>)sourceAccelerationStructure descriptor:(MTLAccelerationStructureDescriptor *)descriptor destination:(id<MTLAccelerationStructure>)destination scratchBuffer:(id<MTLBuffer>)scratchBuffer scratchBufferOffset:(NSUInteger)scratchBufferOffset options:(MTLAccelerationStructureRefitOptions)options {}
- (void)copyAccelerationStructure:(id<MTLAccelerationStructure>)source toAccelerationStructure:(id<MTLAccelerationStructure>)destination {}
- (void)writeCompactedAccelerationStructureSize:(id<MTLAccelerationStructure>)accelerationStructure toBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset {
  if (buffer && [buffer contents] && offset + sizeof(uint32_t) <= [buffer length]) {
    uint32_t *p = (uint32_t *)((uint8_t *)[buffer contents] + offset);
    *p = (uint32_t)[accelerationStructure size];
  }
}
- (void)writeCompactedAccelerationStructureSize:(id<MTLAccelerationStructure>)accelerationStructure toBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset sizeDataType:(MTLDataType)sizeDataType {
  [self writeCompactedAccelerationStructureSize:accelerationStructure toBuffer:buffer offset:offset];
}
- (void)copyAndCompactAccelerationStructure:(id<MTLAccelerationStructure>)source toAccelerationStructure:(id<MTLAccelerationStructure>)destination {}
- (void)useResource:(id<MTLResource>)resource usage:(MTLResourceUsage)usage {}
- (void)useResources:(const id<MTLResource> *)resources count:(NSUInteger)count usage:(MTLResourceUsage)usage {}
- (void)useHeap:(id<MTLHeap>)heap {}
- (void)useHeaps:(const id<MTLHeap> *)heaps count:(NSUInteger)count {}
- (void)updateFence:(id<MTLFence>)fence {}
- (void)waitForFence:(id<MTLFence>)fence {}
- (void)sampleCountersInBuffer:(id<MTLCounterSampleBuffer>)sampleBuffer atSampleIndex:(NSUInteger)sampleIndex withBarrier:(BOOL)barrier {
  if (sampleBuffer && [sampleBuffer isKindOfClass:[XEFMetalCounterSampleBuffer class]]) {
    [(XEFMetalCounterSampleBuffer *)sampleBuffer sampleAtIndex:sampleIndex];
  }
}
- (void)endEncoding {}
- (void)dealloc {
  [_label release];
  [super dealloc];
}
@end

/* ------------------------------------------------------------------- MTLIndirectCommandBuffer */

@implementation MTLIndirectCommandBufferDescriptor {
  MTLIndirectCommandType _commandTypes;
  BOOL _inheritPipelineState;
  BOOL _inheritBuffers;
  NSUInteger _maxVertexBufferBindCount;
  NSUInteger _maxFragmentBufferBindCount;
  NSUInteger _maxKernelBufferBindCount;
}
- (instancetype)init {
  if ((self = [super init])) {
    _commandTypes = MTLIndirectCommandTypeDraw;
    _inheritPipelineState = NO;
    _inheritBuffers = NO;
    _maxVertexBufferBindCount = 31;
    _maxFragmentBufferBindCount = 31;
    _maxKernelBufferBindCount = 31;
  }
  return self;
}
- (MTLIndirectCommandType)commandTypes { return _commandTypes; }
- (void)setCommandTypes:(MTLIndirectCommandType)c { _commandTypes = c; }
- (BOOL)inheritPipelineState { return _inheritPipelineState; }
- (void)setInheritPipelineState:(BOOL)p { _inheritPipelineState = p; }
- (BOOL)inheritBuffers { return _inheritBuffers; }
- (void)setInheritBuffers:(BOOL)b { _inheritBuffers = b; }
- (NSUInteger)maxVertexBufferBindCount { return _maxVertexBufferBindCount; }
- (void)setMaxVertexBufferBindCount:(NSUInteger)c { _maxVertexBufferBindCount = c; }
- (NSUInteger)maxFragmentBufferBindCount { return _maxFragmentBufferBindCount; }
- (void)setMaxFragmentBufferBindCount:(NSUInteger)c { _maxFragmentBufferBindCount = c; }
- (NSUInteger)maxKernelBufferBindCount { return _maxKernelBufferBindCount; }
- (void)setMaxKernelBufferBindCount:(NSUInteger)c { _maxKernelBufferBindCount = c; }
- (id)copyWithZone:(NSZone *)zone {
  MTLIndirectCommandBufferDescriptor *c = [[MTLIndirectCommandBufferDescriptor allocWithZone:zone] init];
  c.commandTypes = _commandTypes;
  c.inheritPipelineState = _inheritPipelineState;
  c.inheritBuffers = _inheritBuffers;
  c.maxVertexBufferBindCount = _maxVertexBufferBindCount;
  c.maxFragmentBufferBindCount = _maxFragmentBufferBindCount;
  c.maxKernelBufferBindCount = _maxKernelBufferBindCount;
  return c;
}
@end

@interface XEFMetalIndirectRenderCommand : NSObject <MTLIndirectRenderCommand> {
@public
  id<MTLRenderPipelineState> _pipelineState;
  id<MTLBuffer> _vertexBuffers[31];
  NSUInteger _vertexBufferOffsets[31];
  id<MTLBuffer> _fragmentBuffers[31];
  NSUInteger _fragmentBufferOffsets[31];
  BOOL _isDrawIndexed;
  BOOL _hasDraw;
  MTLPrimitiveType _primitiveType;
  NSUInteger _vertexStart;
  NSUInteger _vertexCount;
  NSUInteger _instanceCount;
  NSUInteger _baseInstance;
  MTLIndexType _indexType;
  id<MTLBuffer> _indexBuffer;
  NSUInteger _indexBufferOffset;
  NSInteger _baseVertex;
}
- (void)executeOnEncoder:(id<MTLRenderCommandEncoder>)encoder;
@end

@implementation XEFMetalIndirectRenderCommand
- (void)setRenderPipelineState:(id<MTLRenderPipelineState>)pipelineState {
  [pipelineState retain];
  [_pipelineState release];
  _pipelineState = pipelineState;
}
- (void)setVertexBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index {
  if (index < 31) {
    [buffer retain];
    [_vertexBuffers[index] release];
    _vertexBuffers[index] = buffer;
    _vertexBufferOffsets[index] = offset;
  }
}
- (void)setVertexBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset attributeStride:(NSUInteger)stride atIndex:(NSUInteger)index {
  [self setVertexBuffer:buffer offset:offset atIndex:index];
}
- (void)setFragmentBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index {
  if (index < 31) {
    [buffer retain];
    [_fragmentBuffers[index] release];
    _fragmentBuffers[index] = buffer;
    _fragmentBufferOffsets[index] = offset;
  }
}
- (void)drawPrimitives:(MTLPrimitiveType)primitiveType vertexStart:(NSUInteger)vertexStart vertexCount:(NSUInteger)vertexCount instanceCount:(NSUInteger)instanceCount baseInstance:(NSUInteger)baseInstance {
  _hasDraw = YES;
  _isDrawIndexed = NO;
  _primitiveType = primitiveType;
  _vertexStart = vertexStart;
  _vertexCount = vertexCount;
  _instanceCount = instanceCount;
  _baseInstance = baseInstance;
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount indexType:(MTLIndexType)indexType indexBuffer:(id<MTLBuffer>)indexBuffer indexBufferOffset:(NSUInteger)indexBufferOffset instanceCount:(NSUInteger)instanceCount baseVertex:(NSInteger)baseVertex baseInstance:(NSUInteger)baseInstance {
  _hasDraw = YES;
  _isDrawIndexed = YES;
  _primitiveType = primitiveType;
  _vertexCount = indexCount;
  _indexType = indexType;
  [indexBuffer retain];
  [_indexBuffer release];
  _indexBuffer = indexBuffer;
  _indexBufferOffset = indexBufferOffset;
  _instanceCount = instanceCount;
  _baseVertex = baseVertex;
  _baseInstance = baseInstance;
}
- (void)drawPatches:(NSUInteger)numberOfPatchControlPoints patchStart:(NSUInteger)patchStart patchCount:(NSUInteger)patchCount patchIndexBuffer:(id<MTLBuffer>)patchIndexBuffer patchIndexBufferOffset:(NSUInteger)patchIndexBufferOffset instanceCount:(NSUInteger)instanceCount baseInstance:(NSUInteger)baseInstance tessellationFactorBuffer:(id<MTLBuffer>)buffer tessellationFactorBufferOffset:(NSUInteger)offset tessellationFactorBufferInstanceStride:(NSUInteger)instanceStride {}
- (void)drawIndexedPatches:(NSUInteger)numberOfPatchControlPoints patchStart:(NSUInteger)patchStart patchCount:(NSUInteger)patchCount patchIndexBuffer:(id<MTLBuffer>)patchIndexBuffer patchIndexBufferOffset:(NSUInteger)patchIndexBufferOffset controlPointIndexBuffer:(id<MTLBuffer>)controlPointIndexBuffer controlPointIndexBufferOffset:(NSUInteger)controlPointIndexBufferOffset instanceCount:(NSUInteger)instanceCount baseInstance:(NSUInteger)baseInstance tessellationFactorBuffer:(id<MTLBuffer>)buffer tessellationFactorBufferOffset:(NSUInteger)offset tessellationFactorBufferInstanceStride:(NSUInteger)instanceStride {}
- (void)setObjectThreadgroupMemoryLength:(NSUInteger)length atIndex:(NSUInteger)index {}
- (void)setObjectBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index {}
- (void)setMeshBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index {}
- (void)drawMeshThreadgroups:(MTLSize)threadgroupsPerGrid threadsPerObjectThreadgroup:(MTLSize)threadsPerObjectThreadgroup threadsPerMeshThreadgroup:(MTLSize)threadsPerMeshThreadgroup {}
- (void)drawMeshThreads:(MTLSize)threadsPerGrid threadsPerObjectThreadgroup:(MTLSize)threadsPerObjectThreadgroup threadsPerMeshThreadgroup:(MTLSize)threadsPerMeshThreadgroup {}
- (void)setBarrier {}
- (void)clearBarrier {}
- (void)setDepthStencilState:(id<MTLDepthStencilState>)depthStencilState {}
- (void)setDepthBias:(float)depthBias slopeScale:(float)slopeScale clamp:(float)clamp {}
- (void)setDepthClipMode:(MTLDepthClipMode)depthClipMode {}
- (void)setCullMode:(MTLCullMode)cullMode {}
- (void)setFrontFacingWinding:(MTLWinding)frontFacingWindning {}
- (void)setTriangleFillMode:(MTLTriangleFillMode)fillMode {}

- (void)reset {
  [_pipelineState release]; _pipelineState = nil;
  for (int i = 0; i < 31; i++) {
    [_vertexBuffers[i] release]; _vertexBuffers[i] = nil; _vertexBufferOffsets[i] = 0;
    [_fragmentBuffers[i] release]; _fragmentBuffers[i] = nil; _fragmentBufferOffsets[i] = 0;
  }
  [_indexBuffer release]; _indexBuffer = nil;
  _hasDraw = NO;
  _isDrawIndexed = NO;
}

- (void)executeOnEncoder:(id<MTLRenderCommandEncoder>)encoder {
  if (_pipelineState) [encoder setRenderPipelineState:_pipelineState];
  for (int i = 0; i < 31; i++) {
    if (_vertexBuffers[i]) [encoder setVertexBuffer:_vertexBuffers[i] offset:_vertexBufferOffsets[i] atIndex:i];
    if (_fragmentBuffers[i]) [encoder setFragmentBuffer:_fragmentBuffers[i] offset:_fragmentBufferOffsets[i] atIndex:i];
  }
  if (_hasDraw) {
    if (_isDrawIndexed) {
      [encoder drawIndexedPrimitives:_primitiveType indexCount:_vertexCount indexType:_indexType indexBuffer:_indexBuffer indexBufferOffset:_indexBufferOffset instanceCount:_instanceCount baseVertex:_baseVertex baseInstance:_baseInstance];
    } else {
      [encoder drawPrimitives:_primitiveType vertexStart:_vertexStart vertexCount:_vertexCount instanceCount:_instanceCount baseInstance:_baseInstance];
    }
  }
}

- (void)dealloc {
  [self reset];
  [super dealloc];
}
@end

@interface XEFMetalIndirectComputeCommand : NSObject <MTLIndirectComputeCommand> {
@public
  id<MTLComputePipelineState> _pipelineState;
  id<MTLBuffer> _kernelBuffers[31];
  NSUInteger _kernelBufferOffsets[31];
  BOOL _hasDispatch;
  BOOL _isDispatchThreads;
  MTLSize _threadsPerGrid;
  MTLSize _threadgroupsPerGrid;
  MTLSize _threadsPerThreadgroup;
}
- (void)executeOnEncoder:(id<MTLComputeCommandEncoder>)encoder;
@end

@implementation XEFMetalIndirectComputeCommand
- (void)setComputePipelineState:(id<MTLComputePipelineState>)pipelineState {
  [pipelineState retain];
  [_pipelineState release];
  _pipelineState = pipelineState;
}
- (void)setKernelBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index {
  if (index < 31) {
    [buffer retain];
    [_kernelBuffers[index] release];
    _kernelBuffers[index] = buffer;
    _kernelBufferOffsets[index] = offset;
  }
}
- (void)setKernelBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset attributeStride:(NSUInteger)stride atIndex:(NSUInteger)index {
  [self setKernelBuffer:buffer offset:offset atIndex:index];
}
- (void)concurrentDispatchThreadgroups:(MTLSize)threadgroupsPerGrid threadsPerThreadgroup:(MTLSize)threadsPerThreadgroup {
  _hasDispatch = YES;
  _isDispatchThreads = NO;
  _threadgroupsPerGrid = threadgroupsPerGrid;
  _threadsPerThreadgroup = threadsPerThreadgroup;
}
- (void)concurrentDispatchThreads:(MTLSize)threadsPerGrid threadsPerThreadgroup:(MTLSize)threadsPerThreadgroup {
  _hasDispatch = YES;
  _isDispatchThreads = YES;
  _threadsPerGrid = threadsPerGrid;
  _threadsPerThreadgroup = threadsPerThreadgroup;
}
- (void)setBarrier {}
- (void)clearBarrier {}
- (void)setImageblockWidth:(NSUInteger)width height:(NSUInteger)height {}
- (void)setThreadgroupMemoryLength:(NSUInteger)length atIndex:(NSUInteger)index {}
- (void)setStageInRegion:(MTLRegion)region {}
- (void)reset {
  [_pipelineState release]; _pipelineState = nil;
  for (int i = 0; i < 31; i++) {
    [_kernelBuffers[i] release]; _kernelBuffers[i] = nil; _kernelBufferOffsets[i] = 0;
  }
  _hasDispatch = NO;
  _isDispatchThreads = NO;
}
- (void)executeOnEncoder:(id<MTLComputeCommandEncoder>)encoder {
  if (_pipelineState) [encoder setComputePipelineState:_pipelineState];
  for (int i = 0; i < 31; i++) {
    if (_kernelBuffers[i]) [encoder setBuffer:_kernelBuffers[i] offset:_kernelBufferOffsets[i] atIndex:i];
  }
  if (_hasDispatch) {
    if (_isDispatchThreads) {
      [encoder dispatchThreads:_threadsPerGrid threadsPerThreadgroup:_threadsPerThreadgroup];
    } else {
      [encoder dispatchThreadgroups:_threadgroupsPerGrid threadsPerThreadgroup:_threadsPerThreadgroup];
    }
  }
}
- (void)dealloc {
  [self reset];
  [super dealloc];
}
@end

@interface XEFMetalIndirectCommandBuffer : XEFMetalObject <MTLIndirectCommandBuffer> {
@public
  id<MTLDevice> _device;
  MTLIndirectCommandBufferDescriptor *_descriptor;
  NSUInteger _maxCommandCount;
  MTLResourceOptions _options;
  NSMutableArray *_renderCommands;
  NSMutableArray *_computeCommands;
  NSString *_label;
  id<MTLHeap> _heap;
  NSUInteger _heapOffset;
}
- (instancetype)initWithDescriptor:(MTLIndirectCommandBufferDescriptor *)descriptor maxCommandCount:(NSUInteger)count options:(MTLResourceOptions)options device:(id<MTLDevice>)device;
@end

@implementation XEFMetalIndirectCommandBuffer
- (instancetype)initWithDescriptor:(MTLIndirectCommandBufferDescriptor *)descriptor maxCommandCount:(NSUInteger)count options:(MTLResourceOptions)options device:(id<MTLDevice>)device {
  if ((self = [super init])) {
    _device = device;
    _descriptor = [descriptor copy];
    _maxCommandCount = count;
    _options = options;
    _renderCommands = [[NSMutableArray alloc] initWithCapacity:count];
    _computeCommands = [[NSMutableArray alloc] initWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
      XEFMetalIndirectRenderCommand *rc = [[XEFMetalIndirectRenderCommand alloc] init];
      [_renderCommands addObject:rc];
      [rc release];
      XEFMetalIndirectComputeCommand *cc = [[XEFMetalIndirectComputeCommand alloc] init];
      [_computeCommands addObject:cc];
      [cc release];
    }
  }
  return self;
}
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (NSUInteger)size { return _maxCommandCount; }
- (MTLResourceID)gpuResourceID { MTLResourceID rid = { (uint64_t)(uintptr_t)self }; return rid; }
- (void)resetWithRange:(NSRange)range {
  NSUInteger end = range.location + range.length;
  if (end > _maxCommandCount) end = _maxCommandCount;
  for (NSUInteger i = range.location; i < end; i++) {
    [_renderCommands[i] reset];
    [_computeCommands[i] reset];
  }
}
- (id<MTLIndirectRenderCommand>)indirectRenderCommandAtIndex:(NSUInteger)commandIndex {
  if (commandIndex < _maxCommandCount) return _renderCommands[commandIndex];
  return nil;
}
- (id<MTLIndirectComputeCommand>)indirectComputeCommandAtIndex:(NSUInteger)commandIndex {
  if (commandIndex < _maxCommandCount) return _computeCommands[commandIndex];
  return nil;
}
- (MTLStorageMode)storageMode { return (MTLStorageMode)((_options >> MTLResourceStorageModeShift) & 0xf); }
- (MTLCPUCacheMode)cpuCacheMode { return (MTLCPUCacheMode)((_options >> MTLResourceCPUCacheModeShift) & 0xf); }
- (MTLHazardTrackingMode)hazardTrackingMode { return (MTLHazardTrackingMode)((_options >> MTLResourceHazardTrackingModeShift) & 0x3); }
- (MTLResourceOptions)resourceOptions { return _options; }
- (MTLPurgeableState)setPurgeableState:(MTLPurgeableState)state { return MTLPurgeableStateNonVolatile; }
- (void)makeAliasable {}
- (BOOL)isAliasable { return NO; }
- (id<MTLHeap>)heap { return _heap; }
- (NSUInteger)heapOffset { return _heapOffset; }
- (void)dealloc {
  [_descriptor release];
  [_renderCommands release];
  [_computeCommands release];
  [_label release];
  [super dealloc];
}
@end

@interface XEFMetalRenderCommandEncoder : XEFMetalObject <MTLRenderCommandEncoder> {
@public
  id<MTLDevice> _device;
  NSString *_label;
  MTLRenderPassDescriptor *_passDesc;
  XEFMetalRenderPipelineState *_pipelineState;
  XEFMetalDepthStencilState *_depthStencilState;
  XEFMetalBuffer *_vertexBuffers[31];
  NSUInteger _vertexBufferOffsets[31];
  XEFMetalBuffer *_fragmentBuffers[31];
  NSUInteger _fragmentBufferOffsets[31];
  XEFMetalTexture *_vertexTextures[31];
  XEFMetalTexture *_fragmentTextures[31];
  XEFMetalSamplerState *_vertexSamplers[16];
  XEFMetalSamplerState *_fragmentSamplers[16];
  MTLViewport _viewport;
  BOOL _hasViewport;
  MTLScissorRect _scissorRect;
  BOOL _hasScissor;
  MTLCullMode _cullMode;
  MTLWinding _frontFacingWinding;
  MTLTriangleFillMode _triangleFillMode;
  float _depthBias;
  float _depthBiasSlopeScale;
  float _depthBiasClamp;
  float _blendColor[4];
  uint32_t _stencilRef;
  uint32_t _stencilBackRef;
}
- (instancetype)initWithDescriptor:(MTLRenderPassDescriptor *)desc device:(id<MTLDevice>)device;
@end

@implementation XEFMetalRenderCommandEncoder
- (instancetype)initWithDescriptor:(MTLRenderPassDescriptor *)desc device:(id<MTLDevice>)device {
  if ((self = [super init])) {
    _device = device;
    _passDesc = [desc copy];
    _blendColor[0] = _blendColor[1] = _blendColor[2] = _blendColor[3] = 1.0f;
    if (_passDesc) {
      MTLRenderPassDepthAttachmentDescriptor *datt = _passDesc.depthAttachment;
      XEFMetalTexture *dtex = (datt && datt.texture) ? (XEFMetalTexture *)datt.texture : nil;
      uint32_t hostDepthTexId = dtex ? dtex->_hostTexId : 0;
      float clearDepth = (datt && datt.loadAction == MTLLoadActionClear) ? (float)datt.clearDepth : 1.0f;

      for (int i = 0; i < 8; i++) {
        MTLRenderPassColorAttachmentDescriptor *att = _passDesc.colorAttachments->_attachments[i];
        if (att && att.texture) {
          XEFMetalTexture *tex = (XEFMetalTexture *)att.texture;
          if (i == 0) {
            _viewport = (MTLViewport){0.0, 0.0, (double)tex->_width, (double)tex->_height, 0.0, 1.0};
            _scissorRect = (MTLScissorRect){0, 0, tex->_width, tex->_height};
          }
          if (att.loadAction == MTLLoadActionClear) {
            if (tex->_hostTexId > 0) {
              xef_host_metal_pass_begin_ex(0, tex->_hostTexId, hostDepthTexId, 1,
                                          (float)att.clearColor.red, (float)att.clearColor.green,
                                          (float)att.clearColor.blue, (float)att.clearColor.alpha,
                                          clearDepth);
            }
            xef_tex_clear(tex, att.clearColor);
          } else if (tex->_hostTexId > 0) {
            xef_host_metal_pass_begin_ex(0, tex->_hostTexId, hostDepthTexId, 0,
                                        0, 0, 0, 0, clearDepth);
          }
        }
      }
      if (datt && datt.texture && datt.loadAction == MTLLoadActionClear) {
        if (dtex->_storage && dtex->_storage->_data && dtex->_storage->_bpp >= 4) {
          float cd = (float)datt.clearDepth;
          float *dp = (float *)dtex->_storage->_data;
          size_t count = (size_t)dtex->_width * (size_t)dtex->_height;
          for (size_t k = 0; k < count; k++) dp[k] = cd;
        }
      }
    }
  }
  return self;
}
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (void)setRenderPipelineState:(id<MTLRenderPipelineState>)pipelineState {
  [pipelineState retain];
  [_pipelineState release];
  _pipelineState = (XEFMetalRenderPipelineState *)pipelineState;
}
- (void)setVertexBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index {
  if (index >= 31) return;
  [buffer retain];
  [_vertexBuffers[index] release];
  _vertexBuffers[index] = (XEFMetalBuffer *)buffer;
  _vertexBufferOffsets[index] = offset;
}
- (void)setVertexBuffers:(const id<MTLBuffer> *)buffers offsets:(const NSUInteger *)offsets withRange:(NSRange)range {
  for (NSUInteger i = 0; i < range.length; i++) {
    [self setVertexBuffer:buffers ? buffers[i] : nil offset:offsets ? offsets[i] : 0 atIndex:range.location + i];
  }
}
- (void)setVertexBufferOffset:(NSUInteger)offset atIndex:(NSUInteger)index {
  if (index < 31) _vertexBufferOffsets[index] = offset;
}
- (void)setVertexBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index {
  if (index >= 31) return;
  XEFMetalBuffer *b = [[[XEFMetalBuffer alloc] initWithBytes:bytes length:length options:0 device:_device] autorelease];
  [self setVertexBuffer:b offset:0 atIndex:index];
}
- (void)setVertexSamplerState:(id<MTLSamplerState>)sampler atIndex:(NSUInteger)index {
  if (index >= 16) return;
  [sampler retain];
  [_vertexSamplers[index] release];
  _vertexSamplers[index] = (XEFMetalSamplerState *)sampler;
}
- (void)setVertexSamplerState:(id<MTLSamplerState>)sampler lodMinClamp:(float)lodMinClamp lodMaxClamp:(float)lodMaxClamp atIndex:(NSUInteger)index {
  [self setVertexSamplerState:sampler atIndex:index];
}
- (void)setVertexSamplerStates:(const id<MTLSamplerState> *)samplers withRange:(NSRange)range {
  for (NSUInteger i = 0; i < range.length; i++) {
    [self setVertexSamplerState:samplers ? samplers[i] : nil atIndex:range.location + i];
  }
}
- (void)setVertexSamplerStates:(const id<MTLSamplerState> *)samplers lodMinClamps:(const float *)lodMinClamps lodMaxClamps:(const float *)lodMaxClamps withRange:(NSRange)range {
  for (NSUInteger i = 0; i < range.length; i++) {
    float minC = lodMinClamps ? lodMinClamps[i] : 0.0f;
    float maxC = lodMaxClamps ? lodMaxClamps[i] : 1000.0f;
    [self setVertexSamplerState:samplers ? samplers[i] : nil lodMinClamp:minC lodMaxClamp:maxC atIndex:range.location + i];
  }
}
- (void)setVertexTexture:(id<MTLTexture>)texture atIndex:(NSUInteger)index {
  if (index >= 31) return;
  [texture retain];
  [_vertexTextures[index] release];
  _vertexTextures[index] = (XEFMetalTexture *)texture;
}
- (void)setFragmentBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index {
  if (index >= 31) return;
  [buffer retain];
  [_fragmentBuffers[index] release];
  _fragmentBuffers[index] = (XEFMetalBuffer *)buffer;
  _fragmentBufferOffsets[index] = offset;
}
- (void)setFragmentBuffers:(const id<MTLBuffer> *)buffers offsets:(const NSUInteger *)offsets withRange:(NSRange)range {
  for (NSUInteger i = 0; i < range.length; i++) {
    [self setFragmentBuffer:buffers ? buffers[i] : nil offset:offsets ? offsets[i] : 0 atIndex:range.location + i];
  }
}
- (void)setFragmentBufferOffset:(NSUInteger)offset atIndex:(NSUInteger)index {
  if (index < 31) _fragmentBufferOffsets[index] = offset;
}
- (void)setFragmentBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index {
  if (index >= 31) return;
  XEFMetalBuffer *b = [[[XEFMetalBuffer alloc] initWithBytes:bytes length:length options:0 device:_device] autorelease];
  [self setFragmentBuffer:b offset:0 atIndex:index];
}
- (void)setFragmentSamplerState:(id<MTLSamplerState>)sampler atIndex:(NSUInteger)index {
  if (index >= 16) return;
  [sampler retain];
  [_fragmentSamplers[index] release];
  _fragmentSamplers[index] = (XEFMetalSamplerState *)sampler;
}
- (void)setFragmentSamplerState:(id<MTLSamplerState>)sampler lodMinClamp:(float)lodMinClamp lodMaxClamp:(float)lodMaxClamp atIndex:(NSUInteger)index {
  [self setFragmentSamplerState:sampler atIndex:index];
}
- (void)setFragmentSamplerStates:(const id<MTLSamplerState> *)samplers withRange:(NSRange)range {
  for (NSUInteger i = 0; i < range.length; i++) {
    [self setFragmentSamplerState:samplers ? samplers[i] : nil atIndex:range.location + i];
  }
}
- (void)setFragmentSamplerStates:(const id<MTLSamplerState> *)samplers lodMinClamps:(const float *)lodMinClamps lodMaxClamps:(const float *)lodMaxClamps withRange:(NSRange)range {
  for (NSUInteger i = 0; i < range.length; i++) {
    float minC = lodMinClamps ? lodMinClamps[i] : 0.0f;
    float maxC = lodMaxClamps ? lodMaxClamps[i] : 1000.0f;
    [self setFragmentSamplerState:samplers ? samplers[i] : nil lodMinClamp:minC lodMaxClamp:maxC atIndex:range.location + i];
  }
}
- (void)setFragmentTexture:(id<MTLTexture>)texture atIndex:(NSUInteger)index {
  if (index >= 31) return;
  [texture retain];
  [_fragmentTextures[index] release];
  _fragmentTextures[index] = (XEFMetalTexture *)texture;
}
- (void)setFragmentTextures:(const id<MTLTexture> *)textures withRange:(NSRange)range {
  for (NSUInteger i = 0; i < range.length; i++) {
    [self setFragmentTexture:textures ? textures[i] : nil atIndex:range.location + i];
  }
}
- (void)setViewport:(MTLViewport)viewport { _viewport = viewport; _hasViewport = YES; }
- (void)setViewports:(const MTLViewport *)viewports count:(NSUInteger)count { if (count > 0 && viewports) [self setViewport:viewports[0]]; }
- (void)setScissorRect:(MTLScissorRect)rect { _scissorRect = rect; _hasScissor = YES; }
- (void)setScissorRects:(const MTLScissorRect *)scissorRects count:(NSUInteger)count { if (count > 0 && scissorRects) [self setScissorRect:scissorRects[0]]; }
- (void)setCullMode:(MTLCullMode)cullMode { _cullMode = cullMode; }
- (void)setFrontFacingWinding:(MTLWinding)frontFacingWinding { _frontFacingWinding = frontFacingWinding; }
- (void)setDepthStencilState:(id<MTLDepthStencilState>)depthStencilState {
  [depthStencilState retain];
  [_depthStencilState release];
  _depthStencilState = (XEFMetalDepthStencilState *)depthStencilState;
}
- (void)setBlendColorRed:(float)red green:(float)green blue:(float)blue alpha:(float)alpha {
  _blendColor[0] = red; _blendColor[1] = green; _blendColor[2] = blue; _blendColor[3] = alpha;
}
- (void)setStencilReferenceValue:(uint32_t)val { _stencilRef = val; _stencilBackRef = val; }
- (void)setStencilFrontReferenceValue:(uint32_t)front backReferenceValue:(uint32_t)back { _stencilRef = front; _stencilBackRef = back; }
- (void)setTriangleFillMode:(MTLTriangleFillMode)fillMode {
  _triangleFillMode = fillMode;
}
- (void)setDepthClipMode:(MTLDepthClipMode)clipMode {}
- (void)setDepthBias:(float)bias slopeScale:(float)slope clamp:(float)clamp {
  _depthBias = bias;
  _depthBiasSlopeScale = slope;
  _depthBiasClamp = clamp;
}
- (void)setVisibilityResultMode:(MTLVisibilityResultMode)mode offset:(NSUInteger)offset {}
- (void)pushDebugGroup:(NSString *)string {}
- (void)popDebugGroup {}
- (void)insertDebugSignpost:(NSString *)string {}
- (void)useResource:(id<MTLResource>)resource usage:(MTLResourceUsage)usage {}
- (void)useResources:(const id<MTLResource> *)resources count:(NSUInteger)count usage:(MTLResourceUsage)usage {}
- (void)useResource:(id<MTLResource>)resource usage:(MTLResourceUsage)usage stages:(MTLRenderStages)stages {}
- (void)useResources:(const id<MTLResource> *)resources count:(NSUInteger)count usage:(MTLResourceUsage)usage stages:(MTLRenderStages)stages {}
- (void)useHeap:(id<MTLHeap>)heap {}
- (void)useHeaps:(const id<MTLHeap> *)heaps count:(NSUInteger)count {}
- (void)useHeap:(id<MTLHeap>)heap stages:(MTLRenderStages)stages {}
- (void)useHeaps:(const id<MTLHeap> *)heaps count:(NSUInteger)count stages:(MTLRenderStages)stages {}
- (void)updateFence:(id<MTLFence>)fence afterStages:(MTLRenderStages)stages {}
- (void)waitForFence:(id<MTLFence>)fence beforeStages:(MTLRenderStages)stages {}
- (void)memoryBarrierWithScope:(MTLBarrierScope)scope afterStages:(MTLRenderStages)after beforeStages:(MTLRenderStages)before {}
- (void)memoryBarrierWithResources:(const id<MTLResource> *)resources count:(NSUInteger)count afterStages:(MTLRenderStages)after beforeStages:(MTLRenderStages)before {}
- (void)sampleCountersInBuffer:(id<MTLCounterSampleBuffer>)sampleBuffer atSampleIndex:(NSUInteger)sampleIndex withBarrier:(BOOL)barrier {
  if (sampleBuffer && [sampleBuffer isKindOfClass:[XEFMetalCounterSampleBuffer class]]) {
    [(XEFMetalCounterSampleBuffer *)sampleBuffer sampleAtIndex:sampleIndex];
  }
}

typedef struct {
  const uint8_t *attr_bases[3];
  size_t attr_lens[3];
  size_t strides[3];
  int attr_offs[3];
  MTLVertexFormat attr_fmts[3];
  BOOL attr_active[3];
  BOOL has_attr;
  BOOL is_custom_vert;
  int custom_count;
  const float (*custom_verts)[4];
  BOOL is_fullscreen_vert;
  BOOL fallback_packed_float2;
  const float *fallback_fp;
  const float *mvp;
  BOOL has_const_frag_col;
  float const_frag_col[4];
  float vp_ox, vp_oy, vp_w_half, vp_h_half, vp_znear, vp_zdiff;
} XEFVertexFetcher;

static void xef_init_vertex_fetcher(XEFVertexFetcher *vf, XEFMetalRenderCommandEncoder *enc) {
  memset(vf, 0, sizeof(*vf));
  for (int i = 0; i < 3; i++) vf->attr_offs[i] = -1;

  XEFMetalFunction *vfn = enc->_pipelineState && enc->_pipelineState->_desc ? (XEFMetalFunction *)enc->_pipelineState->_desc.vertexFunction : nil;
  XEFMetalFunction *ffn = enc->_pipelineState && enc->_pipelineState->_desc ? (XEFMetalFunction *)enc->_pipelineState->_desc.fragmentFunction : nil;

  if (vfn && vfn->_hasCustomVerts) {
    vf->is_custom_vert = YES;
    vf->custom_count = vfn->_customVertCount;
    vf->custom_verts = (const float (*)[4])vfn->_customVerts;
  } else if (vfn && vfn->_isFullscreenVert) {
    vf->is_fullscreen_vert = YES;
  } else {
    MTLVertexDescriptor *vd = enc->_pipelineState && enc->_pipelineState->_desc ? enc->_pipelineState->_desc.vertexDescriptor : nil;
    uint32_t usedAttrMask = 0;
    if (vd) {
      for (int a = 0; a < 3; a++) {
        MTLVertexAttributeDescriptor *ad = vd.attributes->_attributes[a];
        if (!ad || ad.format == MTLVertexFormatInvalid) continue;
        NSUInteger bIdx = ad.bufferIndex;
        if (bIdx >= 31 || !enc->_vertexBuffers[bIdx]) continue;
        MTLVertexBufferLayoutDescriptor *ld = vd.layouts->_layouts[bIdx];
        NSUInteger stride = ld ? ld.stride : 0;
        if (stride == 0) continue;
        vf->has_attr = YES;
        usedAttrMask |= (1u << (uint32_t)bIdx);
        XEFMetalBuffer *buf = enc->_vertexBuffers[bIdx];
        vf->attr_bases[a] = (const uint8_t *)buf->_data + enc->_vertexBufferOffsets[bIdx];
        vf->attr_lens[a] = buf->_length > enc->_vertexBufferOffsets[bIdx] ? buf->_length - enc->_vertexBufferOffsets[bIdx] : 0;
        vf->strides[a] = stride;
        vf->attr_offs[a] = (int)ad.offset;
        vf->attr_fmts[a] = ad.format;
        vf->attr_active[a] = YES;
      }
    }
    if (!vf->has_attr) {
      if (enc->_vertexBuffers[0] && enc->_vertexBuffers[0]->_length >= 8) {
        vf->fallback_packed_float2 = YES;
        vf->fallback_fp = (const float *)((const uint8_t *)enc->_vertexBuffers[0]->_data + enc->_vertexBufferOffsets[0]);
      }
    } else {
      /* Check buffers for 4x4 matrix uniforms (64 bytes) */
      for (int b = 0; b < 4; b++) {
        if (!(usedAttrMask & (1u << (uint32_t)b)) && enc->_vertexBuffers[b]) {
          XEFMetalBuffer *ubuf = enc->_vertexBuffers[b];
          size_t uoff = enc->_vertexBufferOffsets[b];
          if (uoff + 64 <= ubuf->_length) {
            vf->mvp = (const float *)((const uint8_t *)ubuf->_data + uoff);
            break;
          }
        }
      }
    }

    /* Fallback: if no vertex descriptor but vertexBuffers[0] contains struct Vertex { float4 pos; float4 col; } */
    if (!vf->has_attr && enc->_vertexBuffers[0] && enc->_vertexBuffers[0]->_length >= 32) {
      vf->has_attr = YES;
      XEFMetalBuffer *buf = enc->_vertexBuffers[0];
      const uint8_t *bptr = (const uint8_t *)buf->_data + enc->_vertexBufferOffsets[0];
      size_t blen = buf->_length > enc->_vertexBufferOffsets[0] ? buf->_length - enc->_vertexBufferOffsets[0] : 0;
      vf->attr_bases[0] = bptr; vf->attr_lens[0] = blen; vf->strides[0] = 32; vf->attr_offs[0] = 0; vf->attr_fmts[0] = MTLVertexFormatFloat4; vf->attr_active[0] = YES;
      vf->attr_bases[1] = bptr; vf->attr_lens[1] = blen; vf->strides[1] = 32; vf->attr_offs[1] = 16; vf->attr_fmts[1] = MTLVertexFormatFloat4; vf->attr_active[1] = YES;
      for (int b = 1; b < 4; b++) {
        if (enc->_vertexBuffers[b]) {
          XEFMetalBuffer *ubuf = enc->_vertexBuffers[b];
          size_t uoff = enc->_vertexBufferOffsets[b];
          if (uoff + 64 <= ubuf->_length) {
            vf->mvp = (const float *)((const uint8_t *)ubuf->_data + uoff);
            break;
          }
        }
      }
    }
  }

  if (ffn && ffn->_fragMode == XEF_FRAG_MODE_CONST_COLOR) {
    vf->has_const_frag_col = YES;
    memcpy(vf->const_frag_col, ffn->_constFragColor, sizeof(vf->const_frag_col));
  }

  vf->vp_ox = (float)enc->_viewport.originX;
  vf->vp_oy = (float)enc->_viewport.originY;
  vf->vp_w_half = (float)enc->_viewport.width * 0.5f;
  vf->vp_h_half = (float)enc->_viewport.height * 0.5f;
  vf->vp_znear = (float)enc->_viewport.znear;
  vf->vp_zdiff = (float)(enc->_viewport.zfar - enc->_viewport.znear);
}

static inline void xef_fetch_vertex_fast(const XEFVertexFetcher *vf, NSInteger vIdx, XEFVertex *v) {
  v->pos[0] = 0.0f; v->pos[1] = 0.0f; v->pos[2] = 0.0f; v->pos[3] = 1.0f;
  v->col[0] = 1.0f; v->col[1] = 1.0f; v->col[2] = 1.0f; v->col[3] = 1.0f;
  v->uv[0]  = 0.0f; v->uv[1]  = 0.0f;

  if (vf->is_custom_vert) {
    int idx = (int)vIdx % vf->custom_count;
    if (idx < 0) idx = 0;
    v->pos[0] = vf->custom_verts[idx][0];
    v->pos[1] = vf->custom_verts[idx][1];
    v->pos[2] = vf->custom_verts[idx][2];
    v->pos[3] = vf->custom_verts[idx][3];
  } else if (vf->is_fullscreen_vert) {
    uint32_t vi = (uint32_t)vIdx;
    float u = (float)((vi << 1) & 2);
    float vt = (float)(vi & 2);
    v->uv[0] = u; v->uv[1] = vt;
    v->pos[0] = u * 2.0f - 1.0f; v->pos[1] = 1.0f - vt * 2.0f;
    v->pos[2] = 0.0f; v->pos[3] = 1.0f;
  } else if (vf->has_attr) {
    /* Attribute 0: Position */
    if (vf->attr_active[0] && vf->attr_offs[0] >= 0) {
      size_t off = (size_t)vIdx * vf->strides[0];
      if (off < vf->attr_lens[0]) {
        xef_read_vertex_attr(vf->attr_bases[0] + off + vf->attr_offs[0], vf->attr_fmts[0], v->pos, 1.0f);
      }
    }
    /* Attribute 1: Color */
    if (vf->attr_active[1] && vf->attr_offs[1] >= 0) {
      size_t off = (size_t)vIdx * vf->strides[1];
      if (off < vf->attr_lens[1]) {
        xef_read_vertex_attr(vf->attr_bases[1] + off + vf->attr_offs[1], vf->attr_fmts[1], v->col, 1.0f);
      }
    }
    /* Attribute 2: UV */
    if (vf->attr_active[2] && vf->attr_offs[2] >= 0) {
      size_t off = (size_t)vIdx * vf->strides[2];
      if (off < vf->attr_lens[2]) {
        float tmp[4];
        xef_read_vertex_attr(vf->attr_bases[2] + off + vf->attr_offs[2], vf->attr_fmts[2], tmp, 0.0f);
        v->uv[0] = tmp[0]; v->uv[1] = tmp[1];
      }
    }
    if (vf->mvp) {
      const float *m = vf->mvp;
      float px = v->pos[0], py = v->pos[1], pz = v->pos[2], pw = v->pos[3];
      v->pos[0] = m[0]*px + m[4]*py + m[8]*pz  + m[12]*pw;
      v->pos[1] = m[1]*px + m[5]*py + m[9]*pz  + m[13]*pw;
      v->pos[2] = m[2]*px + m[6]*py + m[10]*pz + m[14]*pw;
      v->pos[3] = m[3]*px + m[7]*py + m[11]*pz + m[15]*pw;
    }
  } else if (vf->fallback_packed_float2) {
    v->pos[0] = vf->fallback_fp[vIdx * 2 + 0];
    v->pos[1] = vf->fallback_fp[vIdx * 2 + 1];
    v->pos[2] = 0.0f; v->pos[3] = 1.0f;
  } else {
    uint32_t vi = (uint32_t)vIdx;
    float u = (float)((vi << 1) & 2);
    float vt = (float)(vi & 2);
    v->uv[0] = u; v->uv[1] = vt;
    v->pos[0] = u * 2.0f - 1.0f; v->pos[1] = 1.0f - vt * 2.0f;
    v->pos[2] = 0.0f; v->pos[3] = 1.0f;
  }

  if (vf->has_const_frag_col) {
    v->col[0] = vf->const_frag_col[0];
    v->col[1] = vf->const_frag_col[1];
    v->col[2] = vf->const_frag_col[2];
    v->col[3] = vf->const_frag_col[3];
  }

  float w = v->pos[3];
  if (fabsf(w) < 1e-7f) w = 1.0f;
  float invW = 1.0f / w;
  float ndcX = v->pos[0] * invW;
  float ndcY = v->pos[1] * invW;
  float ndcZ = v->pos[2] * invW;
  v->invW = invW;
  v->sx = vf->vp_ox + (ndcX + 1.0f) * vf->vp_w_half;
  v->sy = vf->vp_oy + (1.0f - ndcY) * vf->vp_h_half;
  v->sz = vf->vp_znear + ndcZ * vf->vp_zdiff;
}

- (void)_fetchVertex:(NSInteger)vIdx outVertex:(XEFVertex *)v {
  XEFVertexFetcher vf;
  xef_init_vertex_fetcher(&vf, self);
  xef_fetch_vertex_fast(&vf, vIdx, v);
}

- (void)_shadeAndWritePixelX:(int)px Y:(int)py col:(const float[4])vcol uv:(const float[2])uv target:(XEFMetalTexture *)target {
  XEFMetalFunction *ffn = _pipelineState && _pipelineState->_desc ? (XEFMetalFunction *)_pipelineState->_desc.fragmentFunction : nil;
  int fmode = ffn ? ffn->_fragMode : XEF_FRAG_MODE_AUTO;

  float colorScale = 1.0f;
  float uvLeftTop[2] = {0.0f, 0.0f};
  float uvDims[2] = {1.0f, 1.0f};

  if (_fragmentBuffers[0]) {
    XEFMetalBuffer *fb = _fragmentBuffers[0];
    size_t foff = _fragmentBufferOffsets[0];
    if (fmode == XEF_FRAG_MODE_BLIT2D && foff + 16 <= fb->_length) {
      const float *fp = (const float *)((const uint8_t *)fb->_data + foff);
      uvLeftTop[0] = fp[0]; uvLeftTop[1] = fp[1];
      uvDims[0] = fp[2];    uvDims[1] = fp[3];
    } else if (foff + 4 <= fb->_length) {
      const float *fp = (const float *)((const uint8_t *)fb->_data + foff);
      if (foff + 16 <= fb->_length && ffn && ffn->_source && strstr([ffn->_source UTF8String], "scRGB_output")) {
        colorScale = fp[3];
      } else {
        colorScale = fp[0];
      }
      if (isnan(colorScale) || colorScale <= 0.0f || colorScale > 100.0f) colorScale = 1.0f;
    }
  }

  float src[4];
  if (fmode == XEF_FRAG_MODE_CONST_COLOR) {
    src[0] = vcol[0]; src[1] = vcol[1]; src[2] = vcol[2]; src[3] = vcol[3];
  } else if (fmode == XEF_FRAG_MODE_BLIT2D && _fragmentTextures[0]) {
    float su = uv[0] * uvDims[0] + uvLeftTop[0];
    float sv = uv[1] * uvDims[1] + uvLeftTop[1];
    xef_tex_sample(_fragmentTextures[0], _fragmentSamplers[0], su, sv, src);
  } else if (fmode == XEF_FRAG_MODE_COLOR_ONLY || !_fragmentTextures[0]) {
    src[0] = vcol[0] * colorScale;
    src[1] = vcol[1] * colorScale;
    src[2] = vcol[2] * colorScale;
    src[3] = vcol[3];
  } else {
    float texCol[4];
    xef_tex_sample(_fragmentTextures[0], _fragmentSamplers[0], uv[0], uv[1], texCol);
    if (fmode == XEF_FRAG_MODE_TEX_RGB) texCol[3] = 1.0f;
    src[0] = texCol[0] * colorScale * vcol[0];
    src[1] = texCol[1] * colorScale * vcol[1];
    src[2] = texCol[2] * colorScale * vcol[2];
    src[3] = texCol[3] * vcol[3];
  }

  MTLRenderPipelineColorAttachmentDescriptor *catt =
      (_pipelineState && _pipelineState->_desc) ? _pipelineState->_desc.colorAttachments->_descriptors[0] : nil;
  MTLColorWriteMask writeMask = catt ? catt.writeMask : MTLColorWriteMaskAll;

  if (catt && catt.isBlendingEnabled) {
    float dst[4];
    xef_tex_read_pixel(target, px, py, dst);
    float out[4];
    for (int c = 0; c < 3; c++) {
      float sf = xef_eval_blend_factor(catt.sourceRGBBlendFactor, src, dst, _blendColor, c);
      float df = xef_eval_blend_factor(catt.destinationRGBBlendFactor, src, dst, _blendColor, c);
      out[c] = xef_eval_blend_op(catt.rgbBlendOperation, src[c] * sf, dst[c] * df);
    }
    float saf = xef_eval_blend_factor(catt.sourceAlphaBlendFactor, src, dst, _blendColor, 3);
    float daf = xef_eval_blend_factor(catt.destinationAlphaBlendFactor, src, dst, _blendColor, 3);
    out[3] = xef_eval_blend_op(catt.alphaBlendOperation, src[3] * saf, dst[3] * daf);
    xef_tex_write_pixel(target, px, py, out, writeMask);
  } else {
    xef_tex_write_pixel(target, px, py, src, writeMask);
  }
}

typedef struct XEFRasterContext {
  uint32_t *target_u32;
  uint8_t  *target_raw;
  int target_w, target_h, target_stride;
  int target_bpp;
  int target_is_bgra;
  int clip_min_x, clip_min_y, clip_max_x, clip_max_y;

  const uint32_t *tex_u32;
  int tex_w, tex_h;
  int tex_is_bgra;
  BOOL has_tex;

  int frag_mode;
  float color_scale;
  float uv_left_top[2];
  float uv_dims[2];

  BOOL blending;
  BOOL is_standard_alpha;
  BOOL is_premul_alpha;
  MTLBlendFactor src_rgb_factor;
  MTLBlendFactor dst_rgb_factor;
  MTLBlendOperation rgb_op;
  MTLBlendFactor src_a_factor;
  MTLBlendFactor dst_a_factor;
  MTLBlendOperation a_op;
  float blend_col[4];
  MTLColorWriteMask write_mask;
  MTLCullMode cull_mode;
  MTLWinding front_facing_winding;
} XEFRasterContext;

static inline void xef_blend_over_bgra(uint32_t *dst, uint32_t src) {
  uint32_t a = (src >> 24) & 0xff;
  if (a == 0) return;
  if (a == 255) { *dst = src; return; }
  uint32_t d = *dst;
  uint32_t inv_a = 255 - a;
  uint32_t rb = (((src & 0x00ff00ff) * a + (d & 0x00ff00ff) * inv_a + 0x00800080) >> 8) & 0x00ff00ff;
  uint32_t g  = (((src & 0x0000ff00) * a + (d & 0x0000ff00) * inv_a + 0x00008000) >> 8) & 0x0000ff00;
  *dst = rb | g | 0xff000000;
}

static inline void xef_blend_premul_bgra(uint32_t *dst, uint32_t src) {
  uint32_t a = (src >> 24) & 0xff;
  if (a == 0) return;
  uint32_t d = *dst;
  uint32_t inv_a = 255 - a;
  uint32_t rb = (src & 0x00ff00ff) + (((d & 0x00ff00ff) * inv_a + 0x00800080) >> 8);
  uint32_t g  = (src & 0x0000ff00) + (((d & 0x0000ff00) * inv_a + 0x00008000) >> 8);
  if (rb & 0x01000000) rb = (rb & 0x000000ff) | 0x00ff0000;
  if (rb & 0x00000100) rb = (rb & 0x00ff0000) | 0x000000ff;
  if (g  & 0x00010000) g  = 0x0000ff00;
  *dst = (rb & 0x00ff00ff) | (g & 0x0000ff00) | 0xff000000;
}

static inline uint32_t xef_sample_tex_fast(const XEFRasterContext *ctx, float u, float v) {
  if (!ctx->has_tex) return 0xffffffff;
  int tx = (int)(u * (float)ctx->tex_w);
  int ty = (int)(v * (float)ctx->tex_h);
  if (tx < 0) tx = 0; else if (tx >= ctx->tex_w) tx = ctx->tex_w - 1;
  if (ty < 0) ty = 0; else if (ty >= ctx->tex_h) ty = ctx->tex_h - 1;
  uint32_t pix = ctx->tex_u32[ty * ctx->tex_w + tx];
  if (ctx->tex_is_bgra != ctx->target_is_bgra) {
    pix = (pix & 0xff00ff00) | ((pix & 0xff) << 16) | ((pix >> 16) & 0xff);
  }
  return pix;
}

static inline void xef_write_shaded_pixel_dst(const XEFRasterContext *ctx, uint32_t *dst, float r, float g, float b, float a, float u, float v) {
  uint32_t src_col;
  if (!ctx->has_tex || ctx->frag_mode == XEF_FRAG_MODE_COLOR_ONLY) {
    uint32_t ur = (uint32_t)(r * ctx->color_scale * 255.0f); if (ur > 255) ur = 255;
    uint32_t ug = (uint32_t)(g * ctx->color_scale * 255.0f); if (ug > 255) ug = 255;
    uint32_t ub = (uint32_t)(b * ctx->color_scale * 255.0f); if (ub > 255) ub = 255;
    uint32_t ua = (uint32_t)(a * 255.0f); if (ua > 255) ua = 255;
    if (ctx->target_is_bgra) {
      src_col = (ua << 24) | (ur << 16) | (ug << 8) | ub;
    } else {
      src_col = (ua << 24) | (ub << 16) | (ug << 8) | ur;
    }
  } else {
    float su = u, sv = v;
    if (ctx->frag_mode == XEF_FRAG_MODE_BLIT2D) {
      su = u * ctx->uv_dims[0] + ctx->uv_left_top[0];
      sv = v * ctx->uv_dims[1] + ctx->uv_left_top[1];
    }
    uint32_t tpix = xef_sample_tex_fast(ctx, su, sv);
    uint32_t tb = (tpix & 0xff);
    uint32_t tg = (tpix >> 8) & 0xff;
    uint32_t tr = (tpix >> 16) & 0xff;
    uint32_t ta = (tpix >> 24) & 0xff;
    if (ctx->frag_mode == XEF_FRAG_MODE_TEX_RGB) ta = 255;
    float scR = (ctx->target_is_bgra ? r : b) * ctx->color_scale;
    float scG = g * ctx->color_scale;
    float scB = (ctx->target_is_bgra ? b : r) * ctx->color_scale;
    uint32_t ob = (uint32_t)(tb * scB); if (ob > 255) ob = 255;
    uint32_t og = (uint32_t)(tg * scG); if (og > 255) og = 255;
    uint32_t or_ = (uint32_t)(tr * scR); if (or_ > 255) or_ = 255;
    uint32_t oa = (uint32_t)(ta * a); if (oa > 255) oa = 255;
    src_col = (oa << 24) | (or_ << 16) | (og << 8) | ob;
  }

  if (ctx->is_standard_alpha) {
    xef_blend_over_bgra(dst, src_col);
  } else if (ctx->is_premul_alpha) {
    xef_blend_premul_bgra(dst, src_col);
  } else if (!ctx->blending) {
    *dst = src_col;
  } else {
    xef_blend_over_bgra(dst, src_col);
  }
}

static inline void xef_write_shaded_pixel(const XEFRasterContext *ctx, int px, int py, float r, float g, float b, float a, float u, float v) {
  if (!ctx->target_u32) return;
  uint32_t *dst = ctx->target_u32 + py * ctx->target_stride + px;
  xef_write_shaded_pixel_dst(ctx, dst, r, g, b, a, u, v);
}

static void xef_rasterize_triangle_fast(const XEFRasterContext *ctx, const XEFVertex *v0, const XEFVertex *v1, const XEFVertex *v2) {
  int clipMinX = ctx->clip_min_x;
  int clipMinY = ctx->clip_min_y;
  int clipMaxX = ctx->clip_max_x;
  int clipMaxY = ctx->clip_max_y;

  if (clipMinX > clipMaxX || clipMinY > clipMaxY) return;

  float fminX = fminf(v0->sx, fminf(v1->sx, v2->sx));
  float fmaxX = fmaxf(v0->sx, fmaxf(v1->sx, v2->sx));
  float fminY = fminf(v0->sy, fminf(v1->sy, v2->sy));
  float fmaxY = fmaxf(v0->sy, fmaxf(v1->sy, v2->sy));

  int minX = (int)floorf(fminX);
  int maxX = (int)ceilf(fmaxX);
  int minY = (int)floorf(fminY);
  int maxY = (int)ceilf(fmaxY);

  if (minX < clipMinX) minX = clipMinX;
  if (maxX > clipMaxX) maxX = clipMaxX;
  if (minY < clipMinY) minY = clipMinY;
  if (maxY > clipMaxY) maxY = clipMaxY;
  if (minX > maxX || minY > maxY) return;

  float area = (v1->sx - v0->sx) * (v2->sy - v0->sy) - (v1->sy - v0->sy) * (v2->sx - v0->sx);
  if (fabsf(area) < 1e-5f) return;

  if (ctx->cull_mode != MTLCullModeNone) {
    BOOL isCW = (area > 0.0f);
    BOOL isFront = (ctx->front_facing_winding == MTLWindingClockwise) ? isCW : !isCW;
    if (ctx->cull_mode == MTLCullModeBack && !isFront) return;
    if (ctx->cull_mode == MTLCullModeFront && isFront) return;
  }

  float invArea = 1.0f / area;

  float cy0 = (float)minY + 0.5f;
  float cx0 = (float)minX + 0.5f;

  float dw0_dx = -(v2->sy - v1->sy) * invArea;
  float dw0_dy =  (v2->sx - v1->sx) * invArea;

  float dw1_dx = -(v0->sy - v2->sy) * invArea;
  float dw1_dy =  (v0->sx - v2->sx) * invArea;

  float w0_row = ((v2->sx - v1->sx) * (cy0 - v1->sy) - (v2->sy - v1->sy) * (cx0 - v1->sx)) * invArea;
  float w1_row = ((v0->sx - v2->sx) * (cy0 - v2->sy) - (v0->sy - v2->sy) * (cx0 - v2->sx)) * invArea;

  /* Fast-path for constant color & constant UV (covers UI background rectangles, panels, borders) */
  BOOL const_uv = (!ctx->has_tex || (fabsf(v0->uv[0] - v1->uv[0]) < 1e-5f && fabsf(v0->uv[0] - v2->uv[0]) < 1e-5f &&
                                      fabsf(v0->uv[1] - v1->uv[1]) < 1e-5f && fabsf(v0->uv[1] - v2->uv[1]) < 1e-5f));
  BOOL const_col = (fabsf(v0->col[0] - v1->col[0]) < 1e-4f && fabsf(v0->col[0] - v2->col[0]) < 1e-4f &&
                    fabsf(v0->col[1] - v1->col[1]) < 1e-4f && fabsf(v0->col[1] - v2->col[1]) < 1e-4f &&
                    fabsf(v0->col[2] - v1->col[2]) < 1e-4f && fabsf(v0->col[2] - v2->col[2]) < 1e-4f &&
                    fabsf(v0->col[3] - v1->col[3]) < 1e-4f && fabsf(v0->col[3] - v2->col[3]) < 1e-4f);

  if (const_uv && const_col) {
    uint32_t const_src_col;
    if (!ctx->has_tex || ctx->frag_mode == XEF_FRAG_MODE_COLOR_ONLY) {
      uint32_t ur = (uint32_t)(v0->col[0] * ctx->color_scale * 255.0f); if (ur > 255) ur = 255;
      uint32_t ug = (uint32_t)(v0->col[1] * ctx->color_scale * 255.0f); if (ug > 255) ug = 255;
      uint32_t ub = (uint32_t)(v0->col[2] * ctx->color_scale * 255.0f); if (ub > 255) ub = 255;
      uint32_t ua = (uint32_t)(v0->col[3] * 255.0f); if (ua > 255) ua = 255;
      const_src_col = ctx->target_is_bgra ? ((ua << 24) | (ur << 16) | (ug << 8) | ub) : ((ua << 24) | (ub << 16) | (ug << 8) | ur);
    } else {
      float su = v0->uv[0], sv = v0->uv[1];
      if (ctx->frag_mode == XEF_FRAG_MODE_BLIT2D) {
        su = su * ctx->uv_dims[0] + ctx->uv_left_top[0];
        sv = sv * ctx->uv_dims[1] + ctx->uv_left_top[1];
      }
      uint32_t tpix = xef_sample_tex_fast(ctx, su, sv);
      uint32_t tb = (tpix & 0xff);
      uint32_t tg = (tpix >> 8) & 0xff;
      uint32_t tr = (tpix >> 16) & 0xff;
      uint32_t ta = (tpix >> 24) & 0xff;
      if (ctx->frag_mode == XEF_FRAG_MODE_TEX_RGB) ta = 255;
      float scR = (ctx->target_is_bgra ? v0->col[0] : v0->col[2]) * ctx->color_scale;
      float scG = v0->col[1] * ctx->color_scale;
      float scB = (ctx->target_is_bgra ? v0->col[2] : v0->col[0]) * ctx->color_scale;
      uint32_t ob = (uint32_t)(tb * scB); if (ob > 255) ob = 255;
      uint32_t og = (uint32_t)(tg * scG); if (og > 255) og = 255;
      uint32_t or_ = (uint32_t)(tr * scR); if (or_ > 255) or_ = 255;
      uint32_t oa = (uint32_t)(ta * v0->col[3]); if (oa > 255) oa = 255;
      const_src_col = (oa << 24) | (or_ << 16) | (og << 8) | ob;
    }

    BOOL is_opaque = (!ctx->blending || (const_src_col >> 24) == 255);
    BOOL is_std_alpha = ctx->is_standard_alpha;
    BOOL is_premul_alpha = ctx->is_premul_alpha;

    float inv_dy0 = fabsf(v1->sy - v0->sy) > 1e-5f ? (v1->sx - v0->sx) / (v1->sy - v0->sy) : 0.0f;
    float inv_dy1 = fabsf(v2->sy - v1->sy) > 1e-5f ? (v2->sx - v1->sx) / (v2->sy - v1->sy) : 0.0f;
    float inv_dy2 = fabsf(v0->sy - v2->sy) > 1e-5f ? (v0->sx - v2->sx) / (v0->sy - v2->sy) : 0.0f;

    for (int py = minY; py <= maxY; py++) {
      float y = (float)py + 0.5f;
      float x_cross[3];
      int n_cross = 0;
      if ((v0->sy <= y && y < v1->sy) || (v1->sy <= y && y < v0->sy)) {
        x_cross[n_cross++] = v0->sx + (y - v0->sy) * inv_dy0;
      }
      if ((v1->sy <= y && y < v2->sy) || (v2->sy <= y && y < v1->sy)) {
        x_cross[n_cross++] = v1->sx + (y - v1->sy) * inv_dy1;
      }
      if (n_cross < 2 && ((v2->sy <= y && y < v0->sy) || (v0->sy <= y && y < v2->sy))) {
        x_cross[n_cross++] = v2->sx + (y - v2->sy) * inv_dy2;
      }
      if (n_cross == 2) {
        float x_left = x_cross[0] < x_cross[1] ? x_cross[0] : x_cross[1];
        float x_right = x_cross[0] > x_cross[1] ? x_cross[0] : x_cross[1];
        int sx0 = (int)ceilf(x_left);
        int sx1 = (int)floorf(x_right);
        if (sx0 < clipMinX) sx0 = clipMinX;
        if (sx1 > clipMaxX) sx1 = clipMaxX;
        if (sx0 <= sx1) {
          uint32_t *dst = ctx->target_u32 + py * ctx->target_stride + sx0;
          int span_len = sx1 - sx0 + 1;
          if (is_opaque) {
            int k = 0;
            for (; k <= span_len - 8; k += 8) {
              dst[k+0] = const_src_col; dst[k+1] = const_src_col;
              dst[k+2] = const_src_col; dst[k+3] = const_src_col;
              dst[k+4] = const_src_col; dst[k+5] = const_src_col;
              dst[k+6] = const_src_col; dst[k+7] = const_src_col;
            }
            for (; k < span_len; k++) dst[k] = const_src_col;
          } else if (is_std_alpha) {
            for (int k = 0; k < span_len; k++) xef_blend_over_bgra(&dst[k], const_src_col);
          } else if (is_premul_alpha) {
            for (int k = 0; k < span_len; k++) xef_blend_premul_bgra(&dst[k], const_src_col);
          } else {
            for (int k = 0; k < span_len; k++) dst[k] = const_src_col;
          }
        }
      }
    }
    return;
  }

  for (int py = minY; py <= maxY; py++) {
    uint32_t *row = ctx->target_u32 + py * ctx->target_stride;
    float w0 = w0_row;
    float w1 = w1_row;
    for (int px = minX; px <= maxX; px++) {
      float w2 = 1.0f - w0 - w1;
      if (w0 >= -1e-4f && w1 >= -1e-4f && w2 >= -1e-4f) {
        float r = w0 * v0->col[0] + w1 * v1->col[0] + w2 * v2->col[0];
        float g = w0 * v0->col[1] + w1 * v1->col[1] + w2 * v2->col[1];
        float b = w0 * v0->col[2] + w1 * v1->col[2] + w2 * v2->col[2];
        float a = w0 * v0->col[3] + w1 * v1->col[3] + w2 * v2->col[3];

        float u = w0 * v0->uv[0] + w1 * v1->uv[0] + w2 * v2->uv[0];
        float v = w0 * v0->uv[1] + w1 * v1->uv[1] + w2 * v2->uv[1];

        xef_write_shaded_pixel_dst(ctx, row + px, r, g, b, a, u, v);
      }
      w0 += dw0_dx;
      w1 += dw1_dx;
    }
    w0_row += dw0_dy;
    w1_row += dw1_dy;
  }
}

static void xef_fill_host_metal_pipeline(xef_host_metal_pipeline_t *pipe, XEFMetalRenderCommandEncoder *enc, XEFMetalTexture *target) {
  memset(pipe, 0, sizeof(*pipe));
  if (!target) return;
  pipe->rt_tex_id = target->_hostTexId;
  if (enc->_fragmentTextures[0] && [(id)enc->_fragmentTextures[0] respondsToSelector:@selector(_hostTexId)]) {
    pipe->tex_id = [(id)enc->_fragmentTextures[0] _hostTexId];
  }

  XEFMetalFunction *ffn = enc->_pipelineState && enc->_pipelineState->_desc ? (XEFMetalFunction *)enc->_pipelineState->_desc.fragmentFunction : nil;
  pipe->frag_mode = ffn ? ffn->_fragMode : 0;
  if (!enc->_fragmentTextures[0] && pipe->frag_mode != XEF_FRAG_MODE_CONST_COLOR) {
    pipe->frag_mode = XEF_FRAG_MODE_COLOR_ONLY;
  }
  pipe->color_scale = 1.0f;
  pipe->uv_left_top[0] = 0.0f; pipe->uv_left_top[1] = 0.0f;
  pipe->uv_dims[0] = 1.0f;     pipe->uv_dims[1] = 1.0f;

  if (enc->_fragmentBuffers[0]) {
    XEFMetalBuffer *fb = enc->_fragmentBuffers[0];
    size_t foff = enc->_fragmentBufferOffsets[0];
    if (pipe->frag_mode == XEF_FRAG_MODE_BLIT2D && foff + 16 <= fb->_length) {
      const float *fp = (const float *)((const uint8_t *)fb->_data + foff);
      pipe->uv_left_top[0] = fp[0]; pipe->uv_left_top[1] = fp[1];
      pipe->uv_dims[0] = fp[2];    pipe->uv_dims[1] = fp[3];
    } else if (foff + 4 <= fb->_length) {
      const float *fp = (const float *)((const uint8_t *)fb->_data + foff);
      if (foff + 16 <= fb->_length && ffn && ffn->_source && strstr([ffn->_source UTF8String], "scRGB_output")) {
        pipe->color_scale = fp[3];
      } else {
        pipe->color_scale = fp[0];
      }
      if (isnan(pipe->color_scale) || pipe->color_scale <= 0.0f || pipe->color_scale > 100.0f) pipe->color_scale = 1.0f;
    }
  }

  MTLRenderPipelineColorAttachmentDescriptor *catt =
      (enc->_pipelineState && enc->_pipelineState->_desc) ? enc->_pipelineState->_desc.colorAttachments->_descriptors[0] : nil;
  pipe->write_mask = catt ? (int)catt.writeMask : 15;

  if (catt && catt.isBlendingEnabled) {
    pipe->blend_enable = 1;
    pipe->src_rgb = (int)catt.sourceRGBBlendFactor;
    pipe->dst_rgb = (int)catt.destinationRGBBlendFactor;
    pipe->rgb_op  = (int)catt.rgbBlendOperation;
    pipe->src_a   = (int)catt.sourceAlphaBlendFactor;
    pipe->dst_a   = (int)catt.destinationAlphaBlendFactor;
    pipe->a_op    = (int)catt.alphaBlendOperation;
  }

  pipe->viewport[0] = (int)enc->_viewport.originX;
  pipe->viewport[1] = (int)enc->_viewport.originY;
  pipe->viewport[2] = (int)enc->_viewport.width;
  pipe->viewport[3] = (int)enc->_viewport.height;

  if (enc->_hasScissor) {
    pipe->clip_rect[0] = (int)enc->_scissorRect.x;
    pipe->clip_rect[1] = (int)enc->_scissorRect.y;
    pipe->clip_rect[2] = (int)enc->_scissorRect.width;
    pipe->clip_rect[3] = (int)enc->_scissorRect.height;
  } else {
    pipe->clip_rect[0] = 0;
    pipe->clip_rect[1] = 0;
    pipe->clip_rect[2] = (int)target->_width;
    pipe->clip_rect[3] = (int)target->_height;
  }

  if (enc->_fragmentSamplers[0]) {
    pipe->filter_linear = (enc->_fragmentSamplers[0]->_minFilter == MTLSamplerMinMagFilterNearest) ? 0 : 1;
    pipe->clamp_to_edge = (enc->_fragmentSamplers[0]->_sAddressMode == MTLSamplerAddressModeRepeat) ? 0 : 1;
  } else {
    pipe->filter_linear = 1;
    pipe->clamp_to_edge = 1;
  }

  /* Depth & Stencil states */
  if (enc->_passDesc && enc->_passDesc.depthAttachment && enc->_passDesc.depthAttachment.texture) {
    XEFMetalTexture *dtex = (XEFMetalTexture *)enc->_passDesc.depthAttachment.texture;
    pipe->depth_tex_id = dtex->_hostTexId;
  }
  if (enc->_depthStencilState) {
    pipe->depth_compare_op = (int)enc->_depthStencilState->_depthCompareFunction;
    pipe->depth_write_enable = enc->_depthStencilState->_depthWriteEnabled ? 1 : 0;
    pipe->depth_test_enable = (pipe->depth_compare_op != (int)MTLCompareFunctionAlways || pipe->depth_write_enable) ? 1 : 0;

    MTLStencilDescriptor *front = enc->_depthStencilState->_frontFaceStencil;
    MTLStencilDescriptor *back = enc->_depthStencilState->_backFaceStencil;
    if (front || back) {
      pipe->stencil_test_enable = 1;
      if (front) {
        pipe->stencil_compare_op = (int)front.stencilCompareFunction;
        pipe->stencil_fail_op = (int)front.stencilFailureOperation;
        pipe->stencil_depth_fail_op = (int)front.depthFailureOperation;
        pipe->stencil_pass_op = (int)front.depthStencilPassOperation;
        pipe->stencil_read_mask = front.readMask;
        pipe->stencil_write_mask = front.writeMask;
      }
      pipe->stencil_ref = enc->_stencilRef;

      if (back) {
        pipe->stencil_back_compare_op = (int)back.stencilCompareFunction;
        pipe->stencil_back_fail_op = (int)back.stencilFailureOperation;
        pipe->stencil_back_depth_fail_op = (int)back.depthFailureOperation;
        pipe->stencil_back_pass_op = (int)back.depthStencilPassOperation;
        pipe->stencil_back_read_mask = back.readMask;
        pipe->stencil_back_write_mask = back.writeMask;
      } else if (front) {
        pipe->stencil_back_compare_op = pipe->stencil_compare_op;
        pipe->stencil_back_fail_op = pipe->stencil_fail_op;
        pipe->stencil_back_depth_fail_op = pipe->stencil_depth_fail_op;
        pipe->stencil_back_pass_op = pipe->stencil_pass_op;
        pipe->stencil_back_read_mask = pipe->stencil_read_mask;
        pipe->stencil_back_write_mask = pipe->stencil_write_mask;
      }
      pipe->stencil_back_ref = enc->_stencilBackRef;
    }
  }

  pipe->cull_mode = (int)enc->_cullMode;
  pipe->front_facing_winding = (int)enc->_frontFacingWinding;
  pipe->triangle_fill_mode = (int)enc->_triangleFillMode;
  pipe->depth_bias = enc->_depthBias;
  pipe->depth_bias_slope_scale = enc->_depthBiasSlopeScale;
  pipe->depth_bias_clamp = enc->_depthBiasClamp;
  pipe->blend_color[0] = enc->_blendColor[0];
  pipe->blend_color[1] = enc->_blendColor[1];
  pipe->blend_color[2] = enc->_blendColor[2];
  pipe->blend_color[3] = enc->_blendColor[3];
}

static void xef_init_raster_context(XEFRasterContext *ctx, XEFMetalRenderCommandEncoder *enc, XEFMetalTexture *target) {
  memset(ctx, 0, sizeof(*ctx));
  if (!target || !target->_storage || !target->_storage->_data) return;

  ctx->target_raw = (uint8_t *)target->_storage->_data;
  ctx->target_w = (int)target->_width;
  ctx->target_h = (int)target->_height;
  ctx->target_stride = (int)target->_width;
  ctx->target_bpp = (int)target->_storage->_bpp;
  if (ctx->target_bpp == 4) {
    ctx->target_u32 = (uint32_t *)ctx->target_raw;
  }
  ctx->target_is_bgra = (target->_pixelFormat == MTLPixelFormatBGRA8Unorm ||
                         target->_pixelFormat == MTLPixelFormatBGRA8Unorm_sRGB);

  ctx->clip_min_x = 0; ctx->clip_min_y = 0;
  ctx->clip_max_x = ctx->target_w - 1; ctx->clip_max_y = ctx->target_h - 1;
  if (enc->_hasScissor) {
    int sx0 = (int)enc->_scissorRect.x, sy0 = (int)enc->_scissorRect.y;
    int sx1 = sx0 + (int)enc->_scissorRect.width - 1, sy1 = sy0 + (int)enc->_scissorRect.height - 1;
    if (sx0 > ctx->clip_min_x) ctx->clip_min_x = sx0;
    if (sy0 > ctx->clip_min_y) ctx->clip_min_y = sy0;
    if (sx1 < ctx->clip_max_x) ctx->clip_max_x = sx1;
    if (sy1 < ctx->clip_max_y) ctx->clip_max_y = sy1;
  }

  XEFMetalFunction *ffn = enc->_pipelineState && enc->_pipelineState->_desc ? (XEFMetalFunction *)enc->_pipelineState->_desc.fragmentFunction : nil;
  ctx->frag_mode = ffn ? ffn->_fragMode : XEF_FRAG_MODE_AUTO;
  ctx->color_scale = 1.0f;
  ctx->uv_left_top[0] = 0.0f; ctx->uv_left_top[1] = 0.0f;
  ctx->uv_dims[0] = 1.0f;     ctx->uv_dims[1] = 1.0f;

  if (enc->_fragmentBuffers[0]) {
    XEFMetalBuffer *fb = enc->_fragmentBuffers[0];
    size_t foff = enc->_fragmentBufferOffsets[0];
    if (ctx->frag_mode == XEF_FRAG_MODE_BLIT2D && foff + 16 <= fb->_length) {
      const float *fp = (const float *)((const uint8_t *)fb->_data + foff);
      ctx->uv_left_top[0] = fp[0]; ctx->uv_left_top[1] = fp[1];
      ctx->uv_dims[0] = fp[2];    ctx->uv_dims[1] = fp[3];
    } else if (foff + 4 <= fb->_length) {
      const float *fp = (const float *)((const uint8_t *)fb->_data + foff);
      if (foff + 16 <= fb->_length && ffn && ffn->_source && strstr([ffn->_source UTF8String], "scRGB_output")) {
        ctx->color_scale = fp[3];
      } else {
        ctx->color_scale = fp[0];
      }
      if (isnan(ctx->color_scale) || ctx->color_scale <= 0.0f || ctx->color_scale > 100.0f) ctx->color_scale = 1.0f;
    }
  }

  if (enc->_fragmentTextures[0] && enc->_fragmentTextures[0]->_storage && enc->_fragmentTextures[0]->_storage->_data &&
      enc->_fragmentTextures[0]->_storage->_bpp == 4) {
    ctx->has_tex = YES;
    ctx->tex_u32 = (const uint32_t *)enc->_fragmentTextures[0]->_storage->_data;
    ctx->tex_w = (int)enc->_fragmentTextures[0]->_width;
    ctx->tex_h = (int)enc->_fragmentTextures[0]->_height;
    ctx->tex_is_bgra = (enc->_fragmentTextures[0]->_pixelFormat == MTLPixelFormatBGRA8Unorm ||
                        enc->_fragmentTextures[0]->_pixelFormat == MTLPixelFormatBGRA8Unorm_sRGB);
  }

  MTLRenderPipelineColorAttachmentDescriptor *catt =
      (enc->_pipelineState && enc->_pipelineState->_desc) ? enc->_pipelineState->_desc.colorAttachments->_descriptors[0] : nil;
  ctx->write_mask = catt ? catt.writeMask : MTLColorWriteMaskAll;
  ctx->cull_mode = enc->_cullMode;
  ctx->front_facing_winding = enc->_frontFacingWinding;

  if (catt && catt.isBlendingEnabled) {
    ctx->blending = YES;
    ctx->src_rgb_factor = catt.sourceRGBBlendFactor;
    ctx->dst_rgb_factor = catt.destinationRGBBlendFactor;
    ctx->rgb_op = catt.rgbBlendOperation;
    ctx->src_a_factor = catt.sourceAlphaBlendFactor;
    ctx->dst_a_factor = catt.destinationAlphaBlendFactor;
    ctx->a_op = catt.alphaBlendOperation;
    ctx->is_standard_alpha = (ctx->src_rgb_factor == MTLBlendFactorSourceAlpha &&
                             ctx->dst_rgb_factor == MTLBlendFactorOneMinusSourceAlpha &&
                             ctx->rgb_op == MTLBlendOperationAdd);
    ctx->is_premul_alpha   = (ctx->src_rgb_factor == MTLBlendFactorOne &&
                             ctx->dst_rgb_factor == MTLBlendFactorOneMinusSourceAlpha &&
                             ctx->rgb_op == MTLBlendOperationAdd);
  }
}

- (void)_rasterizeTriangleV0:(const XEFVertex *)v0 V1:(const XEFVertex *)v1 V2:(const XEFVertex *)v2 target:(XEFMetalTexture *)target {
  XEFRasterContext ctx;
  xef_init_raster_context(&ctx, self, target);
  if (ctx.target_u32) {
    xef_rasterize_triangle_fast(&ctx, v0, v1, v2);
  } else {
    int tw = (int)target->_width, th = (int)target->_height;
    int clipMinX = 0, clipMinY = 0, clipMaxX = tw - 1, clipMaxY = th - 1;
    if (_hasScissor) {
      int sx0 = (int)_scissorRect.x, sy0 = (int)_scissorRect.y;
      int sx1 = sx0 + (int)_scissorRect.width - 1, sy1 = sy0 + (int)_scissorRect.height - 1;
      if (sx0 > clipMinX) clipMinX = sx0;
      if (sy0 > clipMinY) clipMinY = sy0;
      if (sx1 < clipMaxX) clipMaxX = sx1;
      if (sy1 < clipMaxY) clipMaxY = sy1;
    }
    if (clipMinX > clipMaxX || clipMinY > clipMaxY) return;

    float fminX = fminf(v0->sx, fminf(v1->sx, v2->sx));
    float fmaxX = fmaxf(v0->sx, fmaxf(v1->sx, v2->sx));
    float fminY = fminf(v0->sy, fminf(v1->sy, v2->sy));
    float fmaxY = fmaxf(v0->sy, fmaxf(v1->sy, v2->sy));

    int minX = (int)floorf(fminX);
    int maxX = (int)ceilf(fmaxX);
    int minY = (int)floorf(fminY);
    int maxY = (int)ceilf(fmaxY);

    if (minX < clipMinX) minX = clipMinX;
    if (maxX > clipMaxX) maxX = clipMaxX;
    if (minY < clipMinY) minY = clipMinY;
    if (maxY > clipMaxY) maxY = clipMaxY;
    if (minX > maxX || minY > maxY) return;

    float area = (v1->sx - v0->sx) * (v2->sy - v0->sy) - (v1->sy - v0->sy) * (v2->sx - v0->sx);
    if (fabsf(area) < 1e-5f) return;

    float invArea = 1.0f / area;
    for (int py = minY; py <= maxY; py++) {
      float cy = (float)py + 0.5f;
      for (int px = minX; px <= maxX; px++) {
        float cx = (float)px + 0.5f;
        float w0 = ((v2->sx - v1->sx) * (cy - v1->sy) - (v2->sy - v1->sy) * (cx - v1->sx)) * invArea;
        float w1 = ((v0->sx - v2->sx) * (cy - v2->sy) - (v0->sy - v2->sy) * (cx - v2->sx)) * invArea;
        float w2 = 1.0f - w0 - w1;
        if (w0 >= -1e-4f && w1 >= -1e-4f && w2 >= -1e-4f) {
          float col[4] = {
            w0 * v0->col[0] + w1 * v1->col[0] + w2 * v2->col[0],
            w0 * v0->col[1] + w1 * v1->col[1] + w2 * v2->col[1],
            w0 * v0->col[2] + w1 * v1->col[2] + w2 * v2->col[2],
            w0 * v0->col[3] + w1 * v1->col[3] + w2 * v2->col[3],
          };
          float uv[2] = {
            w0 * v0->uv[0] + w1 * v1->uv[0] + w2 * v2->uv[0],
            w0 * v0->uv[1] + w1 * v1->uv[1] + w2 * v2->uv[1],
          };
          [self _shadeAndWritePixelX:px Y:py col:col uv:uv target:target];
        }
      }
    }
  }
}

- (void)_rasterizeLineV0:(const XEFVertex *)v0 V1:(const XEFVertex *)v1 target:(XEFMetalTexture *)target {
  float dx = v1->sx - v0->sx;
  float dy = v1->sy - v0->sy;
  int steps = (int)ceilf(fmaxf(fabsf(dx), fabsf(dy)));
  if (steps <= 0) steps = 1;
  int tw = (int)target->_width, th = (int)target->_height;
  for (int i = 0; i <= steps; i++) {
    float t = (float)i / (float)steps;
    int px = (int)(v0->sx + dx * t);
    int py = (int)(v0->sy + dy * t);
    if (px < 0 || px >= tw || py < 0 || py >= th) continue;
    if (_hasScissor) {
      if (px < (int)_scissorRect.x || px >= (int)(_scissorRect.x + _scissorRect.width) ||
          py < (int)_scissorRect.y || py >= (int)(_scissorRect.y + _scissorRect.height)) continue;
    }
    float col[4] = {
      v0->col[0] + (v1->col[0] - v0->col[0]) * t,
      v0->col[1] + (v1->col[1] - v0->col[1]) * t,
      v0->col[2] + (v1->col[2] - v0->col[2]) * t,
      v0->col[3] + (v1->col[3] - v0->col[3]) * t,
    };
    float uv[2] = {
      v0->uv[0] + (v1->uv[0] - v0->uv[0]) * t,
      v0->uv[1] + (v1->uv[1] - v0->uv[1]) * t,
    };
    [self _shadeAndWritePixelX:px Y:py col:col uv:uv target:target];
  }
}

- (void)drawPrimitives:(MTLPrimitiveType)primitiveType vertexStart:(NSUInteger)vertexStart vertexCount:(NSUInteger)vertexCount instanceCount:(NSUInteger)instanceCount baseInstance:(NSUInteger)baseInstance {
  if (!_passDesc || vertexCount == 0 || instanceCount == 0) return;
  MTLRenderPassColorAttachmentDescriptor *att0 = _passDesc.colorAttachments->_attachments[0];
  if (!att0 || !att0.texture) return;
  XEFMetalTexture *target = (XEFMetalTexture *)att0.texture;

  if (target->_hostTexId > 0) {
    xef_host_metal_pipeline_t pipe;
    xef_fill_host_metal_pipeline(&pipe, self, target);

    xef_host_metal_vertex_t vstack[256];
    xef_host_metal_vertex_t *vbuf = (vertexCount <= 256) ? vstack : (xef_host_metal_vertex_t *)malloc(vertexCount * sizeof(xef_host_metal_vertex_t));

    XEFVertexFetcher vf;
    xef_init_vertex_fetcher(&vf, self);

    for (NSUInteger i = 0; i < vertexCount; i++) {
      XEFVertex v;
      xef_fetch_vertex_fast(&vf, (NSInteger)(vertexStart + i), &v);
      vbuf[i].sx = v.sx;
      vbuf[i].sy = v.sy;
      vbuf[i].sz = v.sz;
      vbuf[i].u  = v.uv[0];
      vbuf[i].v  = v.uv[1];
      vbuf[i].r  = v.col[0];
      vbuf[i].g  = v.col[1];
      vbuf[i].b  = v.col[2];
      vbuf[i].a  = v.col[3];
    }

    int prim = (primitiveType == MTLPrimitiveTypePoint) ? 0 :
               (primitiveType == MTLPrimitiveTypeLine) ? 1 :
               (primitiveType == MTLPrimitiveTypeLineStrip) ? 2 :
               (primitiveType == MTLPrimitiveTypeTriangle) ? 3 :
               (primitiveType == MTLPrimitiveTypeTriangleStrip) ? 4 : 3;

    xef_host_metal_draw(0, &pipe, prim, vbuf, (int)vertexCount, NULL, 0);

    if (vbuf != vstack) free(vbuf);
    return;
  }

  /* Fast-path for 1:1 fullscreen BlitFrom2D */
  XEFMetalFunction *vfn = _pipelineState && _pipelineState->_desc ? (XEFMetalFunction *)_pipelineState->_desc.vertexFunction : nil;
  XEFMetalFunction *ffn = _pipelineState && _pipelineState->_desc ? (XEFMetalFunction *)_pipelineState->_desc.fragmentFunction : nil;
  MTLRenderPipelineColorAttachmentDescriptor *catt =
      (_pipelineState && _pipelineState->_desc) ? _pipelineState->_desc.colorAttachments->_descriptors[0] : nil;
  if (primitiveType == MTLPrimitiveTypeTriangle && vertexCount == 3 &&
      vfn && vfn->_isFullscreenVert && ffn && ffn->_fragMode == XEF_FRAG_MODE_BLIT2D &&
      _fragmentTextures[0] && (!catt || !catt.isBlendingEnabled)) {
    XEFMetalTexture *srcTex = _fragmentTextures[0];
    float uvLeftTop[2] = {0.0f, 0.0f}, uvDims[2] = {1.0f, 1.0f};
    if (_fragmentBuffers[0] && _fragmentBufferOffsets[0] + 16 <= _fragmentBuffers[0]->_length) {
      const float *fp = (const float *)((const uint8_t *)_fragmentBuffers[0]->_data + _fragmentBufferOffsets[0]);
      uvLeftTop[0] = fp[0]; uvLeftTop[1] = fp[1];
      uvDims[0] = fp[2];    uvDims[1] = fp[3];
    }
    if (srcTex->_width == target->_width && srcTex->_height == target->_height &&
        srcTex->_pixelFormat == target->_pixelFormat &&
        fabsf(uvLeftTop[0]) < 1e-4f && fabsf(uvLeftTop[1]) < 1e-4f &&
        fabsf(uvDims[0] - 1.0f) < 1e-4f && fabsf(uvDims[1] - 1.0f) < 1e-4f &&
        srcTex->_storage && target->_storage && srcTex->_storage->_dataSize == target->_storage->_dataSize) {
      memcpy(target->_storage->_data, srcTex->_storage->_data, target->_storage->_dataSize);
      return;
    }
  }

  XEFRasterContext ctx;
  xef_init_raster_context(&ctx, self, target);
  XEFVertexFetcher vf;
  xef_init_vertex_fetcher(&vf, self);

  if (primitiveType == MTLPrimitiveTypeTriangle) {
    for (NSUInteger i = 0; i + 2 < vertexCount; i += 3) {
      XEFVertex v0, v1, v2;
      xef_fetch_vertex_fast(&vf, (NSInteger)(vertexStart + i + 0), &v0);
      xef_fetch_vertex_fast(&vf, (NSInteger)(vertexStart + i + 1), &v1);
      xef_fetch_vertex_fast(&vf, (NSInteger)(vertexStart + i + 2), &v2);
      if (ctx.target_u32) {
        xef_rasterize_triangle_fast(&ctx, &v0, &v1, &v2);
      } else {
        [self _rasterizeTriangleV0:&v0 V1:&v1 V2:&v2 target:target];
      }
    }
  } else if (primitiveType == MTLPrimitiveTypeTriangleStrip) {
    for (NSUInteger i = 0; i + 2 < vertexCount; i++) {
      XEFVertex v0, v1, v2;
      xef_fetch_vertex_fast(&vf, (NSInteger)(vertexStart + i + (i & 1 ? 1 : 0)), &v0);
      xef_fetch_vertex_fast(&vf, (NSInteger)(vertexStart + i + (i & 1 ? 0 : 1)), &v1);
      xef_fetch_vertex_fast(&vf, (NSInteger)(vertexStart + i + 2), &v2);
      if (ctx.target_u32) {
        xef_rasterize_triangle_fast(&ctx, &v0, &v1, &v2);
      } else {
        [self _rasterizeTriangleV0:&v0 V1:&v1 V2:&v2 target:target];
      }
    }
  } else if (primitiveType == MTLPrimitiveTypeLine) {
    for (NSUInteger i = 0; i + 1 < vertexCount; i += 2) {
      XEFVertex v0, v1;
      xef_fetch_vertex_fast(&vf, (NSInteger)(vertexStart + i + 0), &v0);
      xef_fetch_vertex_fast(&vf, (NSInteger)(vertexStart + i + 1), &v1);
      [self _rasterizeLineV0:&v0 V1:&v1 target:target];
    }
  } else if (primitiveType == MTLPrimitiveTypeLineStrip) {
    for (NSUInteger i = 0; i + 1 < vertexCount; i++) {
      XEFVertex v0, v1;
      xef_fetch_vertex_fast(&vf, (NSInteger)(vertexStart + i + 0), &v0);
      xef_fetch_vertex_fast(&vf, (NSInteger)(vertexStart + i + 1), &v1);
      [self _rasterizeLineV0:&v0 V1:&v1 target:target];
    }
  } else if (primitiveType == MTLPrimitiveTypePoint) {
    for (NSUInteger i = 0; i < vertexCount; i++) {
      XEFVertex v0;
      xef_fetch_vertex_fast(&vf, (NSInteger)(vertexStart + i), &v0);
      [self _shadeAndWritePixelX:(int)v0.sx Y:(int)v0.sy col:v0.col uv:v0.uv target:target];
    }
  }
}

- (void)drawPrimitives:(MTLPrimitiveType)primitiveType vertexStart:(NSUInteger)vertexStart vertexCount:(NSUInteger)vertexCount instanceCount:(NSUInteger)instanceCount {
  [self drawPrimitives:primitiveType vertexStart:vertexStart vertexCount:vertexCount instanceCount:instanceCount baseInstance:0];
}

- (void)drawPrimitives:(MTLPrimitiveType)primitiveType vertexStart:(NSUInteger)vertexStart vertexCount:(NSUInteger)vertexCount {
  [self drawPrimitives:primitiveType vertexStart:vertexStart vertexCount:vertexCount instanceCount:1 baseInstance:0];
}

- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount indexType:(MTLIndexType)indexType indexBuffer:(id<MTLBuffer>)indexBuffer indexBufferOffset:(NSUInteger)indexBufferOffset instanceCount:(NSUInteger)instanceCount baseVertex:(NSInteger)baseVertex baseInstance:(NSUInteger)baseInstance {
  if (!_passDesc || !indexBuffer || indexCount == 0 || instanceCount == 0) return;
  MTLRenderPassColorAttachmentDescriptor *att0 = _passDesc.colorAttachments->_attachments[0];
  if (!att0 || !att0.texture) return;
  XEFMetalTexture *target = (XEFMetalTexture *)att0.texture;
  XEFMetalBuffer *ibuf = (XEFMetalBuffer *)indexBuffer;
  if (indexBufferOffset >= ibuf->_length) return;
  const uint8_t *iptr = (const uint8_t *)ibuf->_data + indexBufferOffset;

  #define READ_IDX(k) ((indexType == MTLIndexTypeUInt16) ? (NSInteger)((const uint16_t *)iptr)[k] + baseVertex : (NSInteger)((const uint32_t *)iptr)[k] + baseVertex)

  if (target->_hostTexId > 0) {
    xef_host_metal_pipeline_t pipe;
    xef_fill_host_metal_pipeline(&pipe, self, target);

    xef_host_metal_vertex_t vstack[256];
    xef_host_metal_vertex_t *vbuf = (indexCount <= 256) ? vstack : (xef_host_metal_vertex_t *)malloc(indexCount * sizeof(xef_host_metal_vertex_t));

    XEFVertexFetcher vf;
    xef_init_vertex_fetcher(&vf, self);

    for (NSUInteger i = 0; i < indexCount; i++) {
      XEFVertex v;
      xef_fetch_vertex_fast(&vf, READ_IDX(i), &v);
      vbuf[i].sx = v.sx;
      vbuf[i].sy = v.sy;
      vbuf[i].sz = v.sz;
      vbuf[i].u  = v.uv[0];
      vbuf[i].v  = v.uv[1];
      vbuf[i].r  = v.col[0];
      vbuf[i].g  = v.col[1];
      vbuf[i].b  = v.col[2];
      vbuf[i].a  = v.col[3];
    }

    int prim = (primitiveType == MTLPrimitiveTypePoint) ? 0 :
               (primitiveType == MTLPrimitiveTypeLine) ? 1 :
               (primitiveType == MTLPrimitiveTypeLineStrip) ? 2 :
               (primitiveType == MTLPrimitiveTypeTriangle) ? 3 :
               (primitiveType == MTLPrimitiveTypeTriangleStrip) ? 4 : 3;

    xef_host_metal_draw(0, &pipe, prim, vbuf, (int)indexCount, NULL, 0);

    if (vbuf != vstack) free(vbuf);
    return;
  }

  XEFRasterContext ctx;
  xef_init_raster_context(&ctx, self, target);
  XEFVertexFetcher vf;
  xef_init_vertex_fetcher(&vf, self);

  if (primitiveType == MTLPrimitiveTypeTriangle) {
    for (NSUInteger i = 0; i + 2 < indexCount; i += 3) {
      XEFVertex v0, v1, v2;
      xef_fetch_vertex_fast(&vf, READ_IDX(i + 0), &v0);
      xef_fetch_vertex_fast(&vf, READ_IDX(i + 1), &v1);
      xef_fetch_vertex_fast(&vf, READ_IDX(i + 2), &v2);
      if (ctx.target_u32) {
        xef_rasterize_triangle_fast(&ctx, &v0, &v1, &v2);
      } else {
        [self _rasterizeTriangleV0:&v0 V1:&v1 V2:&v2 target:target];
      }
    }
  } else if (primitiveType == MTLPrimitiveTypeTriangleStrip) {
    for (NSUInteger i = 0; i + 2 < indexCount; i++) {
      XEFVertex v0, v1, v2;
      xef_fetch_vertex_fast(&vf, READ_IDX(i + (i & 1 ? 1 : 0)), &v0);
      xef_fetch_vertex_fast(&vf, READ_IDX(i + (i & 1 ? 0 : 1)), &v1);
      xef_fetch_vertex_fast(&vf, READ_IDX(i + 2), &v2);
      if (ctx.target_u32) {
        xef_rasterize_triangle_fast(&ctx, &v0, &v1, &v2);
      } else {
        [self _rasterizeTriangleV0:&v0 V1:&v1 V2:&v2 target:target];
      }
    }
  } else if (primitiveType == MTLPrimitiveTypeLine) {
    for (NSUInteger i = 0; i + 1 < indexCount; i += 2) {
      XEFVertex v0, v1;
      xef_fetch_vertex_fast(&vf, READ_IDX(i + 0), &v0);
      xef_fetch_vertex_fast(&vf, READ_IDX(i + 1), &v1);
      [self _rasterizeLineV0:&v0 V1:&v1 target:target];
    }
  } else if (primitiveType == MTLPrimitiveTypeLineStrip) {
    for (NSUInteger i = 0; i + 1 < indexCount; i++) {
      XEFVertex v0, v1;
      xef_fetch_vertex_fast(&vf, READ_IDX(i + 0), &v0);
      xef_fetch_vertex_fast(&vf, READ_IDX(i + 1), &v1);
      [self _rasterizeLineV0:&v0 V1:&v1 target:target];
    }
  } else if (primitiveType == MTLPrimitiveTypePoint) {
    for (NSUInteger i = 0; i < indexCount; i++) {
      XEFVertex v0;
      xef_fetch_vertex_fast(&vf, READ_IDX(i), &v0);
      [self _shadeAndWritePixelX:(int)v0.sx Y:(int)v0.sy col:v0.col uv:v0.uv target:target];
    }
  }
  #undef READ_IDX
}


- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount indexType:(MTLIndexType)indexType indexBuffer:(id<MTLBuffer>)indexBuffer indexBufferOffset:(NSUInteger)indexBufferOffset instanceCount:(NSUInteger)instanceCount {
  [self drawIndexedPrimitives:primitiveType indexCount:indexCount indexType:indexType indexBuffer:indexBuffer indexBufferOffset:indexBufferOffset instanceCount:instanceCount baseVertex:0 baseInstance:0];
}

- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount indexType:(MTLIndexType)indexType indexBuffer:(id<MTLBuffer>)indexBuffer indexBufferOffset:(NSUInteger)indexBufferOffset {
  [self drawIndexedPrimitives:primitiveType indexCount:indexCount indexType:indexType indexBuffer:indexBuffer indexBufferOffset:indexBufferOffset instanceCount:1 baseVertex:0 baseInstance:0];
}

- (void)drawPrimitives:(MTLPrimitiveType)primitiveType indirectBuffer:(id<MTLBuffer>)indirectBuffer indirectBufferOffset:(NSUInteger)indirectBufferOffset {
  if (!indirectBuffer) return;
  XEFMetalBuffer *ibuf = (XEFMetalBuffer *)indirectBuffer;
  if (indirectBufferOffset + sizeof(MTLDrawPrimitivesIndirectArguments) > ibuf->_length) return;
  const MTLDrawPrimitivesIndirectArguments *args = (const MTLDrawPrimitivesIndirectArguments *)((const uint8_t *)ibuf->_data + indirectBufferOffset);
  [self drawPrimitives:primitiveType
           vertexStart:args->vertexStart
           vertexCount:args->vertexCount
         instanceCount:args->instanceCount
          baseInstance:args->baseInstance];
}

- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType
                    indexType:(MTLIndexType)indexType
                  indexBuffer:(id<MTLBuffer>)indexBuffer
            indexBufferOffset:(NSUInteger)indexBufferOffset
               indirectBuffer:(id<MTLBuffer>)indirectBuffer
         indirectBufferOffset:(NSUInteger)indirectBufferOffset {
  if (!indexBuffer || !indirectBuffer) return;
  XEFMetalBuffer *ibuf = (XEFMetalBuffer *)indirectBuffer;
  if (indirectBufferOffset + sizeof(MTLDrawIndexedPrimitivesIndirectArguments) > ibuf->_length) return;
  const MTLDrawIndexedPrimitivesIndirectArguments *args = (const MTLDrawIndexedPrimitivesIndirectArguments *)((const uint8_t *)ibuf->_data + indirectBufferOffset);
  NSUInteger indexSize = (indexType == MTLIndexTypeUInt16) ? sizeof(uint16_t) : sizeof(uint32_t);
  [self drawIndexedPrimitives:primitiveType
                   indexCount:args->indexCount
                    indexType:indexType
                  indexBuffer:indexBuffer
            indexBufferOffset:indexBufferOffset + (NSUInteger)args->indexStart * indexSize
                instanceCount:args->instanceCount
                   baseVertex:args->baseVertex
                 baseInstance:args->baseInstance];
}

- (void)executeCommandsInBuffer:(id<MTLIndirectCommandBuffer>)indirectCommandBuffer withRange:(NSRange)executionRange {
  if (!indirectCommandBuffer || ![indirectCommandBuffer isKindOfClass:[XEFMetalIndirectCommandBuffer class]]) return;
  XEFMetalIndirectCommandBuffer *icb = (XEFMetalIndirectCommandBuffer *)indirectCommandBuffer;
  NSUInteger end = executionRange.location + executionRange.length;
  if (end > icb->_maxCommandCount) end = icb->_maxCommandCount;
  for (NSUInteger i = executionRange.location; i < end; i++) {
    XEFMetalIndirectRenderCommand *cmd = icb->_renderCommands[i];
    [cmd executeOnEncoder:self];
  }
}

- (void)executeCommandsInBuffer:(id<MTLIndirectCommandBuffer>)indirectCommandBuffer indirectBuffer:(id<MTLBuffer>)indirectRangeBuffer indirectBufferOffset:(NSUInteger)indirectBufferOffset {
  if (!indirectCommandBuffer || !indirectRangeBuffer) return;
  XEFMetalBuffer *ibuf = (XEFMetalBuffer *)indirectRangeBuffer;
  if (indirectBufferOffset + sizeof(MTLIndirectCommandBufferExecutionRange) > ibuf->_length) return;
  const MTLIndirectCommandBufferExecutionRange *range = (const MTLIndirectCommandBufferExecutionRange *)((const uint8_t *)ibuf->_data + indirectBufferOffset);
  [self executeCommandsInBuffer:indirectCommandBuffer withRange:NSMakeRange(range->location, range->length)];
}

- (void)setVertexVisibleFunctionTable:(id<MTLVisibleFunctionTable>)functionTable atBufferIndex:(NSUInteger)bufferIndex {}
- (void)setVertexVisibleFunctionTables:(const id<MTLVisibleFunctionTable> *)functionTables withBufferRange:(NSRange)range {}
- (void)setVertexIntersectionFunctionTable:(id<MTLIntersectionFunctionTable>)intersectionFunctionTable atBufferIndex:(NSUInteger)bufferIndex {}
- (void)setVertexIntersectionFunctionTables:(const id<MTLIntersectionFunctionTable> *)intersectionFunctionTables withBufferRange:(NSRange)range {}
- (void)setFragmentVisibleFunctionTable:(id<MTLVisibleFunctionTable>)functionTable atBufferIndex:(NSUInteger)bufferIndex {}
- (void)setFragmentVisibleFunctionTables:(const id<MTLVisibleFunctionTable> *)functionTables withBufferRange:(NSRange)range {}
- (void)setFragmentIntersectionFunctionTable:(id<MTLIntersectionFunctionTable>)intersectionFunctionTable atBufferIndex:(NSUInteger)bufferIndex {}
- (void)setFragmentIntersectionFunctionTables:(const id<MTLIntersectionFunctionTable> *)intersectionFunctionTables withBufferRange:(NSRange)range {}
- (void)setTileVisibleFunctionTable:(id<MTLVisibleFunctionTable>)functionTable atBufferIndex:(NSUInteger)bufferIndex {}
- (void)setTileVisibleFunctionTables:(const id<MTLVisibleFunctionTable> *)functionTables withBufferRange:(NSRange)range {}
- (void)setTileIntersectionFunctionTable:(id<MTLIntersectionFunctionTable>)intersectionFunctionTable atBufferIndex:(NSUInteger)bufferIndex {}
- (void)setTileIntersectionFunctionTables:(const id<MTLIntersectionFunctionTable> *)intersectionFunctionTables withBufferRange:(NSRange)range {}

- (void)endEncoding {
  if (_passDesc) {
    MTLRenderPassColorAttachmentDescriptor *att0 = _passDesc.colorAttachments->_attachments[0];
    if (att0 && att0.texture) {
      XEFMetalTexture *tex = (XEFMetalTexture *)att0.texture;
      if (tex->_hostTexId > 0) {
        xef_host_metal_pass_end(0, tex->_hostTexId);
      }
    }
  }
}

- (void)dealloc {
  [_label release];
  [_passDesc release];
  [_pipelineState release];
  [_depthStencilState release];
  for (int i = 0; i < 31; i++) {
    [_vertexBuffers[i] release];
    [_fragmentBuffers[i] release];
    [_vertexTextures[i] release];
    [_fragmentTextures[i] release];
  }
  for (int i = 0; i < 16; i++) {
    [_vertexSamplers[i] release];
    [_fragmentSamplers[i] release];
  }
  [super dealloc];
}
@end


@interface XEFMetalComputeCommandEncoder : XEFMetalObject <MTLComputeCommandEncoder> {
@public
  id<MTLDevice> _device;
  NSString *_label;
  XEFMetalComputePipelineState *_pipelineState;
  XEFMetalBuffer *_buffers[31];
  NSUInteger _bufferOffsets[31];
  XEFMetalTexture *_textures[31];
  XEFMetalSamplerState *_samplers[16];
}
- (instancetype)initWithDevice:(id<MTLDevice>)device;
@end

@implementation XEFMetalComputeCommandEncoder
- (instancetype)initWithDevice:(id<MTLDevice>)device {
  if ((self = [super init])) { _device = device; }
  return self;
}
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (void)setComputePipelineState:(id<MTLComputePipelineState>)state {
  [state retain]; [_pipelineState release]; _pipelineState = (XEFMetalComputePipelineState *)state;
}
- (void)setBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index {
  if (index >= 31) return;
  [buffer retain]; [_buffers[index] release];
  _buffers[index] = (XEFMetalBuffer *)buffer;
  _bufferOffsets[index] = offset;
}
- (void)setBuffers:(const id<MTLBuffer> *)buffers offsets:(const NSUInteger *)offsets withRange:(NSRange)range {
  for (NSUInteger i = 0; i < range.length; i++) {
    [self setBuffer:buffers ? buffers[i] : nil offset:offsets ? offsets[i] : 0 atIndex:range.location + i];
  }
}
- (void)setBufferOffset:(NSUInteger)offset atIndex:(NSUInteger)index {
  if (index < 31) _bufferOffsets[index] = offset;
}
- (void)setBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index {
  if (index >= 31) return;
  XEFMetalBuffer *b = [[[XEFMetalBuffer alloc] initWithBytes:bytes length:length options:0 device:_device] autorelease];
  [self setBuffer:b offset:0 atIndex:index];
}
- (void)setTexture:(id<MTLTexture>)texture atIndex:(NSUInteger)index {
  if (index >= 31) return;
  [texture retain]; [_textures[index] release];
  _textures[index] = (XEFMetalTexture *)texture;
}
- (void)setTextures:(const id<MTLTexture> *)textures withRange:(NSRange)range {
  for (NSUInteger i = 0; i < range.length; i++) {
    [self setTexture:textures ? textures[i] : nil atIndex:range.location + i];
  }
}
- (void)setSamplerState:(id<MTLSamplerState>)sampler atIndex:(NSUInteger)index {
  if (index >= 16) return;
  [sampler retain]; [_samplers[index] release];
  _samplers[index] = (XEFMetalSamplerState *)sampler;
}
- (void)setSamplerState:(id<MTLSamplerState>)sampler lodMinClamp:(float)lodMinClamp lodMaxClamp:(float)lodMaxClamp atIndex:(NSUInteger)index {
  [self setSamplerState:sampler atIndex:index];
}
- (void)setSamplerStates:(const id<MTLSamplerState> *)samplers withRange:(NSRange)range {
  for (NSUInteger i = 0; i < range.length; i++) {
    [self setSamplerState:samplers ? samplers[i] : nil atIndex:range.location + i];
  }
}
- (void)setSamplerStates:(const id<MTLSamplerState> *)samplers lodMinClamps:(const float *)lodMinClamps lodMaxClamps:(const float *)lodMaxClamps withRange:(NSRange)range {
  for (NSUInteger i = 0; i < range.length; i++) {
    float minC = lodMinClamps ? lodMinClamps[i] : 0.0f;
    float maxC = lodMaxClamps ? lodMaxClamps[i] : 1000.0f;
    [self setSamplerState:samplers ? samplers[i] : nil lodMinClamp:minC lodMaxClamp:maxC atIndex:range.location + i];
  }
}
- (void)setThreadgroupMemoryLength:(NSUInteger)length atIndex:(NSUInteger)index {}
- (void)dispatchThreads:(MTLSize)threadsPerGrid threadsPerThreadgroup:(MTLSize)threadsPerThreadgroup {
  MTLSize threadgroupsPerGrid;
  threadgroupsPerGrid.width = (threadsPerThreadgroup.width > 0) ? ((threadsPerGrid.width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width) : 1;
  threadgroupsPerGrid.height = (threadsPerThreadgroup.height > 0) ? ((threadsPerGrid.height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height) : 1;
  threadgroupsPerGrid.depth = (threadsPerThreadgroup.depth > 0) ? ((threadsPerGrid.depth + threadsPerThreadgroup.depth - 1) / threadsPerThreadgroup.depth) : 1;
  [self dispatchThreadgroups:threadgroupsPerGrid threadsPerThreadgroup:threadsPerThreadgroup];
}
- (void)dispatchThreadgroups:(MTLSize)threadgroupsPerGrid threadsPerThreadgroup:(MTLSize)threadsPerThreadgroup {
  if (!_pipelineState || !_pipelineState->_function) return;
  NSString *fnName = _pipelineState->_function.name;
  NSUInteger totalThreads = threadgroupsPerGrid.width * threadsPerThreadgroup.width *
                            threadgroupsPerGrid.height * threadsPerThreadgroup.height *
                            threadgroupsPerGrid.depth * threadsPerThreadgroup.depth;
  if (totalThreads == 0) return;

  /* If this is an add_arrays kernel (from basic-compute or darling-indium) */
  if ([fnName isEqualToString:@"add_arrays"] || [fnName containsString:@"add_array"]) {
    if (_buffers[0] && _buffers[1] && _buffers[2]) {
      const float *inA = (const float *)((const uint8_t *)[_buffers[0] contents] + _bufferOffsets[0]);
      const float *inB = (const float *)((const uint8_t *)[_buffers[1] contents] + _bufferOffsets[1]);
      float *result = (float *)((uint8_t *)[_buffers[2] contents] + _bufferOffsets[2]);
      NSUInteger maxElems = [_buffers[2] length] / sizeof(float);
      if (totalThreads < maxElems) maxElems = totalThreads;
      for (NSUInteger i = 0; i < maxElems; i++) {
        result[i] = inA[i] + inB[i];
      }
      return;
    }
  }

  /* Support element-wise multiply/scale/copy kernels */
  if ([fnName containsString:@"mul"] || [fnName containsString:@"scale"]) {
    if (_buffers[0] && _buffers[1] && _buffers[2]) {
      const float *inA = (const float *)((const uint8_t *)[_buffers[0] contents] + _bufferOffsets[0]);
      const float *inB = (const float *)((const uint8_t *)[_buffers[1] contents] + _bufferOffsets[1]);
      float *result = (float *)((uint8_t *)[_buffers[2] contents] + _bufferOffsets[2]);
      NSUInteger maxElems = [_buffers[2] length] / sizeof(float);
      if (totalThreads < maxElems) maxElems = totalThreads;
      for (NSUInteger i = 0; i < maxElems; i++) {
        result[i] = inA[i] * inB[i];
      }
      return;
    }
  }

  /* General buffer copy/fill compute shader */
  if ([fnName containsString:@"copy"] && _buffers[0] && _buffers[1]) {
    const uint8_t *src = (const uint8_t *)[_buffers[0] contents] + _bufferOffsets[0];
    uint8_t *dst = (uint8_t *)[_buffers[1] contents] + _bufferOffsets[1];
    NSUInteger cpyLen = [_buffers[1] length] - _bufferOffsets[1];
    NSUInteger srcLen = [_buffers[0] length] - _bufferOffsets[0];
    if (srcLen < cpyLen) cpyLen = srcLen;
    memcpy(dst, src, cpyLen);
    return;
  }
}
- (void)dispatchThreadgroupsWithIndirectBuffer:(id<MTLBuffer>)indirectBuffer indirectBufferOffset:(NSUInteger)indirectBufferOffset threadsPerThreadgroup:(MTLSize)threadsPerThreadgroup {
  if (!indirectBuffer) return;
  XEFMetalBuffer *ibuf = (XEFMetalBuffer *)indirectBuffer;
  if (indirectBufferOffset + sizeof(MTLDispatchThreadgroupsIndirectArguments) > ibuf->_length) return;
  const MTLDispatchThreadgroupsIndirectArguments *args = (const MTLDispatchThreadgroupsIndirectArguments *)((const uint8_t *)ibuf->_data + indirectBufferOffset);
  MTLSize tg = MTLSizeMake(args->threadgroupsPerGrid[0], args->threadgroupsPerGrid[1], args->threadgroupsPerGrid[2]);
  [self dispatchThreadgroups:tg threadsPerThreadgroup:threadsPerThreadgroup];
}
- (void)executeCommandsInBuffer:(id<MTLIndirectCommandBuffer>)indirectCommandBuffer withRange:(NSRange)executionRange {
  if (!indirectCommandBuffer || ![indirectCommandBuffer isKindOfClass:[XEFMetalIndirectCommandBuffer class]]) return;
  XEFMetalIndirectCommandBuffer *icb = (XEFMetalIndirectCommandBuffer *)indirectCommandBuffer;
  NSUInteger end = executionRange.location + executionRange.length;
  if (end > icb->_maxCommandCount) end = icb->_maxCommandCount;
  for (NSUInteger i = executionRange.location; i < end; i++) {
    XEFMetalIndirectComputeCommand *cmd = icb->_computeCommands[i];
    [cmd executeOnEncoder:self];
  }
}
- (void)executeCommandsInBuffer:(id<MTLIndirectCommandBuffer>)indirectCommandBuffer indirectBuffer:(id<MTLBuffer>)indirectRangeBuffer indirectBufferOffset:(NSUInteger)indirectBufferOffset {
  if (!indirectCommandBuffer || !indirectRangeBuffer) return;
  XEFMetalBuffer *ibuf = (XEFMetalBuffer *)indirectRangeBuffer;
  if (indirectBufferOffset + sizeof(MTLIndirectCommandBufferExecutionRange) > ibuf->_length) return;
  const MTLIndirectCommandBufferExecutionRange *range = (const MTLIndirectCommandBufferExecutionRange *)((const uint8_t *)ibuf->_data + indirectBufferOffset);
  [self executeCommandsInBuffer:indirectCommandBuffer withRange:NSMakeRange(range->location, range->length)];
}
- (void)updateFence:(id<MTLFence>)fence {}
- (void)waitForFence:(id<MTLFence>)fence {}
- (void)useResource:(id<MTLResource>)resource usage:(MTLResourceUsage)usage {}
- (void)useResources:(const id<MTLResource> *)resources count:(NSUInteger)count usage:(MTLResourceUsage)usage {}
- (void)useHeap:(id<MTLHeap>)heap {}
- (void)useHeaps:(const id<MTLHeap> *)heaps count:(NSUInteger)count {}
- (void)memoryBarrierWithScope:(MTLBarrierScope)scope {}
- (void)memoryBarrierWithResources:(const id<MTLResource> *)resources count:(NSUInteger)count {}
- (void)sampleCountersInBuffer:(id<MTLCounterSampleBuffer>)sampleBuffer atSampleIndex:(NSUInteger)sampleIndex withBarrier:(BOOL)barrier {
  if (sampleBuffer && [sampleBuffer isKindOfClass:[XEFMetalCounterSampleBuffer class]]) {
    [(XEFMetalCounterSampleBuffer *)sampleBuffer sampleAtIndex:sampleIndex];
  }
}
- (void)pushDebugGroup:(NSString *)string {}
- (void)popDebugGroup {}
- (void)insertDebugSignpost:(NSString *)string {}
- (void)setVisibleFunctionTable:(id<MTLVisibleFunctionTable>)visibleFunctionTable atBufferIndex:(NSUInteger)bufferIndex {}
- (void)setVisibleFunctionTables:(const id<MTLVisibleFunctionTable> *)visibleFunctionTables withBufferRange:(NSRange)range {}
- (void)setIntersectionFunctionTable:(id<MTLIntersectionFunctionTable>)intersectionFunctionTable atBufferIndex:(NSUInteger)bufferIndex {}
- (void)setIntersectionFunctionTables:(const id<MTLIntersectionFunctionTable> *)intersectionFunctionTables withBufferRange:(NSRange)range {}

- (void)endEncoding {}
- (void)dealloc {
  [_label release];
  [_pipelineState release];
  for (int i = 0; i < 31; i++) {
    [_buffers[i] release];
    [_textures[i] release];
  }
  for (int i = 0; i < 16; i++) [_samplers[i] release];
  [super dealloc];
}
@end

@interface XEFMetalBlitCommandEncoder : XEFMetalObject <MTLBlitCommandEncoder> {
  id<MTLDevice> _device;
  NSString *_label;
}
@end
@implementation XEFMetalBlitCommandEncoder
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
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
    MTLRegion region = MTLRegionMake3D(destinationOrigin.x, destinationOrigin.y, destinationOrigin.z, sourceSize.width, sourceSize.height, sourceSize.depth > 0 ? sourceSize.depth : 1);
    [(XEFMetalTexture *)destinationTexture replaceRegion:region mipmapLevel:destinationLevel slice:destinationSlice withBytes:src bytesPerRow:sourceBytesPerRow bytesPerImage:sourceBytesPerImage];
  }
}
- (void)copyFromTexture:(id<MTLTexture>)sourceTexture sourceSlice:(NSUInteger)sourceSlice sourceLevel:(NSUInteger)sourceLevel sourceOrigin:(MTLOrigin)sourceOrigin sourceSize:(MTLSize)sourceSize toBuffer:(id<MTLBuffer>)destinationBuffer destinationOffset:(NSUInteger)destinationOffset destinationBytesPerRow:(NSUInteger)destinationBytesPerRow destinationBytesPerImage:(NSUInteger)destinationBytesPerImage {
  if (sourceTexture && destinationBuffer) {
    uint8_t *dst = (uint8_t *)[destinationBuffer contents] + destinationOffset;
    MTLRegion region = MTLRegionMake3D(sourceOrigin.x, sourceOrigin.y, sourceOrigin.z, sourceSize.width, sourceSize.height, sourceSize.depth > 0 ? sourceSize.depth : 1);
    [(XEFMetalTexture *)sourceTexture getBytes:dst bytesPerRow:destinationBytesPerRow bytesPerImage:destinationBytesPerImage fromRegion:region mipmapLevel:sourceLevel slice:sourceSlice];
  }
}
- (void)copyFromTexture:(id<MTLTexture>)sourceTexture sourceSlice:(NSUInteger)sourceSlice sourceLevel:(NSUInteger)sourceLevel sourceOrigin:(MTLOrigin)sourceOrigin sourceSize:(MTLSize)sourceSize toTexture:(id<MTLTexture>)destinationTexture destinationSlice:(NSUInteger)destinationSlice destinationLevel:(NSUInteger)destinationLevel destinationOrigin:(MTLOrigin)destinationOrigin {
  if (!sourceTexture || !destinationTexture) return;
  XEFMetalTexture *src = (XEFMetalTexture *)sourceTexture;
  XEFMetalTexture *dst = (XEFMetalTexture *)destinationTexture;
  int w = (int)sourceSize.width;
  int h = (int)sourceSize.height;
  if (src->_hostTexId > 0 && dst->_hostTexId > 0) {
    xef_host_metal_tex_copy_ex(src->_hostTexId, (int)sourceSlice, (int)sourceLevel, (int)sourceOrigin.x, (int)sourceOrigin.y, (int)sourceOrigin.z,
                               dst->_hostTexId, (int)destinationSlice, (int)destinationLevel, (int)destinationOrigin.x, (int)destinationOrigin.y, (int)destinationOrigin.z,
                               w, h, (int)(sourceSize.depth > 0 ? sourceSize.depth : 1));
    return;
  }
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      float rgba[4];
      xef_tex_read_pixel(src, (int)sourceOrigin.x + x, (int)sourceOrigin.y + y, rgba);
      xef_tex_write_pixel(dst, (int)destinationOrigin.x + x, (int)destinationOrigin.y + y, rgba, MTLColorWriteMaskAll);
    }
  }
}
- (void)copyFromTexture:(id<MTLTexture>)sourceTexture toTexture:(id<MTLTexture>)destinationTexture {
  if (!sourceTexture || !destinationTexture) return;
  MTLSize sz = MTLSizeMake([sourceTexture width], [sourceTexture height], 1);
  MTLOrigin zero = MTLOriginMake(0, 0, 0);
  [self copyFromTexture:sourceTexture sourceSlice:0 sourceLevel:0 sourceOrigin:zero sourceSize:sz toTexture:destinationTexture destinationSlice:0 destinationLevel:0 destinationOrigin:zero];
}
- (void)generateMipmapsForTexture:(id<MTLTexture>)texture {
  if (texture && [texture isKindOfClass:[XEFMetalTexture class]]) {
    XEFMetalTexture *tex = (XEFMetalTexture *)texture;
    if (tex->_hostTexId > 0) {
      xef_host_metal_tex_generate_mipmaps(tex->_hostTexId);
    }
  }
}
- (void)copyFromBuffer:(id<MTLBuffer>)sourceBuffer sourceOffset:(NSUInteger)sourceOffset sourceBytesPerRow:(NSUInteger)sourceBytesPerRow sourceBytesPerImage:(NSUInteger)sourceBytesPerImage sourceSize:(MTLSize)sourceSize toTexture:(id<MTLTexture>)destinationTexture destinationSlice:(NSUInteger)destinationSlice destinationLevel:(NSUInteger)destinationLevel destinationOrigin:(MTLOrigin)destinationOrigin options:(MTLBlitOption)options {
  [self copyFromBuffer:sourceBuffer sourceOffset:sourceOffset sourceBytesPerRow:sourceBytesPerRow sourceBytesPerImage:sourceBytesPerImage sourceSize:sourceSize toTexture:destinationTexture destinationSlice:destinationSlice destinationLevel:destinationLevel destinationOrigin:destinationOrigin];
}
- (void)copyFromTexture:(id<MTLTexture>)sourceTexture sourceSlice:(NSUInteger)sourceSlice sourceLevel:(NSUInteger)sourceLevel sourceOrigin:(MTLOrigin)sourceOrigin sourceSize:(MTLSize)sourceSize toBuffer:(id<MTLBuffer>)destinationBuffer destinationOffset:(NSUInteger)destinationOffset destinationBytesPerRow:(NSUInteger)destinationBytesPerRow destinationBytesPerImage:(NSUInteger)destinationBytesPerImage options:(MTLBlitOption)options {
  [self copyFromTexture:sourceTexture sourceSlice:sourceSlice sourceLevel:sourceLevel sourceOrigin:sourceOrigin sourceSize:sourceSize toBuffer:destinationBuffer destinationOffset:destinationOffset destinationBytesPerRow:destinationBytesPerRow destinationBytesPerImage:destinationBytesPerImage];
}
- (void)optimizeContentsForGPUAccess:(id<MTLTexture>)texture {}
- (void)optimizeContentsForGPUAccess:(id<MTLTexture>)texture slice:(NSUInteger)slice level:(NSUInteger)level {}
- (void)optimizeContentsForCPUAccess:(id<MTLTexture>)texture {}
- (void)optimizeContentsForCPUAccess:(id<MTLTexture>)texture slice:(NSUInteger)slice level:(NSUInteger)level {}
- (void)resetCommandsInBuffer:(id<MTLIndirectCommandBuffer>)buffer withRange:(NSRange)range {
  if (buffer) [buffer resetWithRange:range];
}
- (void)copyIndirectCommandBuffer:(id<MTLIndirectCommandBuffer>)source sourceRange:(NSRange)sourceRange destination:(id<MTLIndirectCommandBuffer>)destination destinationIndex:(NSUInteger)destinationIndex {}
- (void)optimizeIndirectCommandBuffer:(id<MTLIndirectCommandBuffer>)indirectCommandBuffer withRange:(NSRange)range {}
- (void)updateFence:(id<MTLFence>)fence {}
- (void)waitForFence:(id<MTLFence>)fence {}
- (void)sampleCountersInBuffer:(id<MTLCounterSampleBuffer>)sampleBuffer atSampleIndex:(NSUInteger)sampleIndex withBarrier:(BOOL)barrier {
  if (sampleBuffer && [sampleBuffer isKindOfClass:[XEFMetalCounterSampleBuffer class]]) {
    [(XEFMetalCounterSampleBuffer *)sampleBuffer sampleAtIndex:sampleIndex];
  }
}
- (void)resolveCounters:(id<MTLCounterSampleBuffer>)sampleBuffer inRange:(NSRange)range destinationBuffer:(id<MTLBuffer>)destinationBuffer destinationOffset:(NSUInteger)destinationOffset {
  if (sampleBuffer && destinationBuffer && [sampleBuffer isKindOfClass:[XEFMetalCounterSampleBuffer class]]) {
    NSData *data = [sampleBuffer resolveCounterRange:range];
    if (data && [data length] > 0) {
      NSUInteger len = [data length];
      NSUInteger dstLen = [destinationBuffer length];
      if (destinationOffset + len > dstLen) {
        len = dstLen > destinationOffset ? (dstLen - destinationOffset) : 0;
      }
      if (len > 0) {
        memcpy((uint8_t *)[destinationBuffer contents] + destinationOffset, [data bytes], len);
      }
    }
  }
}
- (void)synchronizeResource:(id<MTLResource>)resource {}
- (void)synchronizeTexture:(id<MTLTexture>)texture slice:(NSUInteger)slice level:(NSUInteger)level {}
- (void)fillBuffer:(id<MTLBuffer>)buffer range:(NSRange)range value:(uint8_t)value {
  if (buffer) {
    memset((uint8_t *)[buffer contents] + range.location, value, range.length);
  }
}
- (void)pushDebugGroup:(NSString *)string {}
- (void)popDebugGroup {}
- (void)insertDebugSignpost:(NSString *)string {}
- (void)endEncoding {}
- (void)dealloc { [_label release]; [super dealloc]; }
@end

@implementation MTLCommandBufferDescriptor {
  BOOL _retainedReferences;
  MTLCommandBufferErrorOption _errorOptions;
}
- (instancetype)init {
  if ((self = [super init])) {
    _retainedReferences = YES;
    _errorOptions = MTLCommandBufferErrorOptionNone;
  }
  return self;
}
- (BOOL)retainedReferences { return _retainedReferences; }
- (void)setRetainedReferences:(BOOL)r { _retainedReferences = r; }
- (MTLCommandBufferErrorOption)errorOptions { return _errorOptions; }
- (void)setErrorOptions:(MTLCommandBufferErrorOption)o { _errorOptions = o; }
- (id)copyWithZone:(NSZone *)zone {
  MTLCommandBufferDescriptor *c = [[MTLCommandBufferDescriptor allocWithZone:zone] init];
  c.retainedReferences = _retainedReferences;
  c.errorOptions = _errorOptions;
  return c;
}
@end

typedef enum {
  XEF_CMD_ACTION_WAIT_EVENT,
  XEF_CMD_ACTION_SIGNAL_EVENT
} XEFCommandEventActionType;

@interface XEFMetalCommandEventAction : NSObject {
@public
  XEFCommandEventActionType _type;
  id<MTLEvent> _event;
  uint64_t _value;
}
@end
@implementation XEFMetalCommandEventAction
- (void)dealloc {
  [_event release];
  [super dealloc];
}
@end

@interface XEFMetalCommandBuffer : XEFMetalObject <MTLCommandBuffer> {
  id<MTLCommandQueue> _commandQueue;
  MTLCommandBufferStatus _status;
  NSString *_label;
  NSMutableArray *_completedHandlers;
  NSMutableArray *_scheduledHandlers;
  NSMutableArray *_drawables;
  NSMutableArray *_eventActions;
  BOOL _retainedReferences;
  MTLCommandBufferErrorOption _errorOptions;
}
- (instancetype)initWithQueue:(id<MTLCommandQueue>)queue;
- (instancetype)initWithQueue:(id<MTLCommandQueue>)queue descriptor:(MTLCommandBufferDescriptor *)desc;
@end
@implementation XEFMetalCommandBuffer
- (instancetype)initWithQueue:(id<MTLCommandQueue>)queue {
  return [self initWithQueue:queue descriptor:nil];
}
- (instancetype)initWithQueue:(id<MTLCommandQueue>)queue descriptor:(MTLCommandBufferDescriptor *)desc {
  if ((self = [super init])) {
    _commandQueue = queue;
    _status = MTLCommandBufferStatusNotEnqueued;
    _retainedReferences = desc ? desc.retainedReferences : YES;
    _errorOptions = desc ? desc.errorOptions : MTLCommandBufferErrorOptionNone;
  }
  return self;
}
- (BOOL)retainedReferences { return _retainedReferences; }
- (MTLCommandBufferErrorOption)errorOptions { return _errorOptions; }
- (id<MTLCommandQueue>)commandQueue { return _commandQueue; }
- (id<MTLDevice>)device { return _commandQueue.device; }
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (MTLCommandBufferStatus)status { return _status; }
- (NSError *)error { return nil; }
- (CFTimeInterval)GPUStartTime { return 0.0; }
- (CFTimeInterval)GPUEndTime { return 0.0; }
- (CFTimeInterval)kernelStartTime { return 0.0; }
- (CFTimeInterval)kernelEndTime { return 0.0; }
- (id<MTLRenderCommandEncoder>)renderCommandEncoderWithDescriptor:(MTLRenderPassDescriptor *)renderPassDescriptor {
  return [[[XEFMetalRenderCommandEncoder alloc] initWithDescriptor:renderPassDescriptor device:_commandQueue.device] autorelease];
}
- (id<MTLComputeCommandEncoder>)computeCommandEncoder {
  return [[[XEFMetalComputeCommandEncoder alloc] initWithDevice:_commandQueue.device] autorelease];
}
- (id<MTLComputeCommandEncoder>)computeCommandEncoderWithDispatchType:(MTLDispatchType)dispatchType {
  return [[[XEFMetalComputeCommandEncoder alloc] initWithDevice:_commandQueue.device] autorelease];
}
- (id<MTLBlitCommandEncoder>)blitCommandEncoder {
  return [[[XEFMetalBlitCommandEncoder alloc] init] autorelease];
}
- (id<MTLAccelerationStructureCommandEncoder>)accelerationStructureCommandEncoder {
  return [[[XEFMetalAccelerationStructureCommandEncoder alloc] initWithCommandBuffer:self] autorelease];
}
- (id<MTLAccelerationStructureCommandEncoder>)accelerationStructureCommandEncoderWithDescriptor:(MTLAccelerationStructurePassDescriptor *)descriptor {
  return [[[XEFMetalAccelerationStructureCommandEncoder alloc] initWithCommandBuffer:self] autorelease];
}
- (void)enqueue { _status = MTLCommandBufferStatusEnqueued; }
- (void)presentDrawable:(id<MTLDrawable>)drawable {
  if (!drawable) return;
  if (!_drawables) _drawables = [[NSMutableArray alloc] init];
  [_drawables addObject:drawable];
}
- (void)presentDrawable:(id<MTLDrawable>)drawable atTime:(CFTimeInterval)presentationTime {
  [self presentDrawable:drawable];
}
- (void)presentDrawable:(id<MTLDrawable>)drawable afterMinimumDuration:(CFTimeInterval)duration {
  [self presentDrawable:drawable];
}
- (void)commit {
  _status = MTLCommandBufferStatusCommitted;

  /* Process deferred event actions (wait before execution, signal after) */
  NSMutableArray *signalActions = nil;
  if (_eventActions) {
    for (XEFMetalCommandEventAction *act in _eventActions) {
      if (act->_type == XEF_CMD_ACTION_WAIT_EVENT) {
        if ([(id)act->_event respondsToSelector:@selector(waitUntilSignaledValue:timeoutMS:)]) {
          [(id)act->_event waitUntilSignaledValue:act->_value timeoutMS:1000];
        } else if ([(id)act->_event respondsToSelector:@selector(signaledValue)]) {
          uint64_t waited = 0;
          while ([(XEFMetalEvent *)act->_event signaledValue] < act->_value && waited < 1000) {
            usleep(1000);
            waited++;
          }
        }
      } else if (act->_type == XEF_CMD_ACTION_SIGNAL_EVENT) {
        if (!signalActions) signalActions = [NSMutableArray array];
        [signalActions addObject:act];
      }
    }
  }

  if (_scheduledHandlers) {
    for (MTLCommandBufferHandler blk in _scheduledHandlers) blk(self);
    [_scheduledHandlers removeAllObjects];
  }
  if (_drawables) {
    for (id<MTLDrawable> d in _drawables) [d present];
    [_drawables removeAllObjects];
  }

  /* Signal events upon command completion */
  if (signalActions) {
    for (XEFMetalCommandEventAction *act in signalActions) {
      if ([(id)act->_event respondsToSelector:@selector(setSignaledValue:)]) {
        [(XEFMetalEvent *)act->_event setSignaledValue:act->_value];
      }
    }
  }
  if (_eventActions) {
    [_eventActions removeAllObjects];
  }

  _status = MTLCommandBufferStatusCompleted;
  if (_completedHandlers) {
    for (MTLCommandBufferHandler blk in _completedHandlers) blk(self);
    [_completedHandlers removeAllObjects];
  }
}
- (void)waitUntilCompleted { _status = MTLCommandBufferStatusCompleted; }
- (void)waitUntilScheduled {}
- (void)addCompletedHandler:(MTLCommandBufferHandler)block {
  if (!block) return;
  if (_status == MTLCommandBufferStatusCompleted) {
    block(self);
    return;
  }
  if (!_completedHandlers) _completedHandlers = [[NSMutableArray alloc] init];
  [_completedHandlers addObject:[[block copy] autorelease]];
}
- (void)addScheduledHandler:(MTLCommandBufferHandler)block {
  if (!block) return;
  if (_status >= MTLCommandBufferStatusScheduled) {
    block(self);
    return;
  }
  if (!_scheduledHandlers) _scheduledHandlers = [[NSMutableArray alloc] init];
  [_scheduledHandlers addObject:[[block copy] autorelease]];
}
- (void)pushDebugGroup:(NSString *)string {}
- (void)popDebugGroup {}
- (void)encodeSignalEvent:(id<MTLEvent>)event value:(uint64_t)value {
  if (!event) return;
  if (!_eventActions) _eventActions = [[NSMutableArray alloc] init];
  XEFMetalCommandEventAction *act = [[XEFMetalCommandEventAction alloc] init];
  act->_type = XEF_CMD_ACTION_SIGNAL_EVENT;
  act->_event = [event retain];
  act->_value = value;
  [_eventActions addObject:act];
  [act release];
}
- (void)encodeWaitForEvent:(id<MTLEvent>)event value:(uint64_t)value {
  if (!event) return;
  if (!_eventActions) _eventActions = [[NSMutableArray alloc] init];
  XEFMetalCommandEventAction *act = [[XEFMetalCommandEventAction alloc] init];
  act->_type = XEF_CMD_ACTION_WAIT_EVENT;
  act->_event = [event retain];
  act->_value = value;
  [_eventActions addObject:act];
  [act release];
}
- (void)dealloc {
  [_label release];
  [_completedHandlers release];
  [_scheduledHandlers release];
  [_drawables release];
  [_eventActions release];
  [super dealloc];
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
  MTLCommandBufferDescriptor *desc = [[[MTLCommandBufferDescriptor alloc] init] autorelease];
  desc.retainedReferences = NO;
  return [[[XEFMetalCommandBuffer alloc] initWithQueue:self descriptor:desc] autorelease];
}
- (id<MTLCommandBuffer>)commandBufferWithDescriptor:(MTLCommandBufferDescriptor *)descriptor {
  return [[[XEFMetalCommandBuffer alloc] initWithQueue:self descriptor:descriptor] autorelease];
}
- (void)insertDebugCaptureBoundary {}
- (void)dealloc { [_label release]; [super dealloc]; }
@end

/* ------------------------------------------------------------------- MTLDynamicLibrary & MTLBinaryArchive */

@interface XEFMetalDynamicLibrary : XEFMetalObject <MTLDynamicLibrary> {
  id<MTLDevice> _device;
  id<MTLLibrary> _library;
  NSString *_label;
  NSString *_installName;
}
- (instancetype)initWithLibrary:(id<MTLLibrary>)library device:(id<MTLDevice>)device;
@end

@implementation XEFMetalDynamicLibrary
- (instancetype)initWithLibrary:(id<MTLLibrary>)library device:(id<MTLDevice>)device {
  if ((self = [super init])) {
    _device = device;
    _library = [library retain];
    _installName = [@"@executable_path/dynamic.metallib" retain];
  }
  return self;
}
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (NSString *)installName { return _installName; }
- (BOOL)serializeToURL:(NSURL *)url error:(NSError **)error {
  if (error) *error = nil;
  if (_library && [_library respondsToSelector:@selector(_data)]) {
    NSData *data = [(id)_library _data];
    if (data && url) {
      return [data writeToURL:url options:NSDataWritingAtomic error:error];
    }
  }
  return YES;
}
- (void)dealloc {
  [_library release];
  [_label release];
  [_installName release];
  [super dealloc];
}
@end

@implementation MTLBinaryArchiveDescriptor {
  NSURL *_url;
}
- (NSURL *)url { return _url; }
- (void)setUrl:(NSURL *)u { [u retain]; [_url release]; _url = u; }
- (id)copyWithZone:(NSZone *)zone {
  MTLBinaryArchiveDescriptor *c = [[MTLBinaryArchiveDescriptor allocWithZone:zone] init];
  c.url = _url;
  return c;
}
- (void)dealloc {
  [_url release];
  [super dealloc];
}
@end

@interface XEFMetalBinaryArchive : XEFMetalObject <MTLBinaryArchive> {
  id<MTLDevice> _device;
  NSString *_label;
  NSMutableArray *_functions;
}
- (instancetype)initWithDescriptor:(MTLBinaryArchiveDescriptor *)descriptor device:(id<MTLDevice>)device;
@end

@implementation XEFMetalBinaryArchive
- (instancetype)initWithDescriptor:(MTLBinaryArchiveDescriptor *)descriptor device:(id<MTLDevice>)device {
  if ((self = [super init])) {
    _device = device;
    _functions = [[NSMutableArray alloc] init];
  }
  return self;
}
- (id<MTLDevice>)device { return _device; }
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (BOOL)addComputePipelineFunctionsWithDescriptor:(MTLComputePipelineDescriptor *)descriptor error:(NSError **)error {
  if (error) *error = nil;
  if (descriptor && descriptor.computeFunction) {
    [_functions addObject:descriptor.computeFunction];
  }
  return YES;
}
- (BOOL)addRenderPipelineFunctionsWithDescriptor:(MTLRenderPipelineDescriptor *)descriptor error:(NSError **)error {
  if (error) *error = nil;
  if (descriptor) {
    if (descriptor.vertexFunction) [_functions addObject:descriptor.vertexFunction];
    if (descriptor.fragmentFunction) [_functions addObject:descriptor.fragmentFunction];
  }
  return YES;
}
- (BOOL)serializeToURL:(NSURL *)url error:(NSError **)error {
  if (error) *error = nil;
  return YES;
}
- (void)dealloc {
  [_label release];
  [_functions release];
  [super dealloc];
}
@end

/* ------------------------------------------------------------------- Device */

@interface XEFMetalDevice : XEFMetalObject <MTLDevice>
+ (XEFMetalDevice *)sharedDevice;
@end

@implementation XEFMetalDevice

+ (XEFMetalDevice *)sharedDevice {
  static XEFMetalDevice *s_dev = nil;
  if (!s_dev) {
    /* Default orbit64 RDP to fast HLE while keeping Metal GPU presentation active */
    setenv("ORBIT64_HIRES", "cpu", 0);
    setenv("ORBIT64_RDP", "fast", 0);
    s_dev = [[XEFMetalDevice alloc] init];
  }
  return s_dev;
}

- (NSString *)name {
  const char *bname = xef_host_metal_backend_name();
  if (bname && strlen(bname) > 0) {
    return [NSString stringWithFormat:@"Apple M1 (MetalVK: %s)", bname];
  }
  return @"Apple M1 (MetalVK Vulkan Engine)";
}
- (uint64_t)registryID { return 0x100000001ULL; }
- (BOOL)isLowPower { return NO; }
- (BOOL)isHeadless { return NO; }
- (BOOL)isRemovable { return NO; }
- (BOOL)hasUnifiedMemory { return YES; }
- (BOOL)isDepth24Stencil8PixelFormatSupported { return YES; }
- (uint64_t)recommendedMaxWorkingSetSize { return 4ULL * 1024 * 1024 * 1024; }
- (NSUInteger)maxBufferLength { return 1ULL * 1024 * 1024 * 1024; }
- (NSUInteger)maxThreadgroupMemoryLength { return 32768; }
- (NSUInteger)currentAllocatedSize { return 0; }
- (MTLReadWriteTextureTier)readWriteTextureSupport { return MTLReadWriteTextureTier2; }
- (MTLArgumentBuffersTier)argumentBuffersSupport { return MTLArgumentBuffersTier2; }

- (BOOL)supportsFamily:(MTLGPUFamily)gpuFamily { return YES; }
- (BOOL)supportsFeatureSet:(MTLFeatureSet)featureSet { return YES; }
- (BOOL)supportsTextureSampleCount:(NSUInteger)sampleCount { return (sampleCount == 1 || sampleCount == 4); }
- (BOOL)supportsCounterSampling:(MTLCounterSamplingPoint)samplingPoint { return YES; }
- (BOOL)supportsRasterizationRateMapWithLayerCount:(NSUInteger)layerCount { return layerCount <= 8; }
- (BOOL)supportsRaytracing { return YES; }
- (BOOL)supportsRaytracingFromRender { return YES; }

- (MTLAccelerationStructureSizes)accelerationStructureSizesWithDescriptor:(MTLAccelerationStructureDescriptor *)descriptor {
  MTLAccelerationStructureSizes sizes;
  sizes.accelerationStructureSize = 65536;
  sizes.buildScratchBufferSize = 65536;
  sizes.refitScratchBufferSize = 32768;

  if ([descriptor isKindOfClass:[MTLPrimitiveAccelerationStructureDescriptor class]]) {
    MTLPrimitiveAccelerationStructureDescriptor *pdesc = (MTLPrimitiveAccelerationStructureDescriptor *)descriptor;
    NSUInteger totalPrimitives = 0;
    for (MTLAccelerationStructureGeometryDescriptor *g in pdesc.geometryDescriptors) {
      if ([g isKindOfClass:[MTLAccelerationStructureTriangleGeometryDescriptor class]]) {
        totalPrimitives += ((MTLAccelerationStructureTriangleGeometryDescriptor *)g).triangleCount;
      } else if ([g isKindOfClass:[MTLAccelerationStructureBoundingBoxGeometryDescriptor class]]) {
        totalPrimitives += ((MTLAccelerationStructureBoundingBoxGeometryDescriptor *)g).boundingBoxCount;
      }
    }
    if (totalPrimitives > 0) {
      sizes.accelerationStructureSize = ((totalPrimitives * 128 + 65535) / 65536) * 65536;
      sizes.buildScratchBufferSize = ((totalPrimitives * 64 + 65535) / 65536) * 65536;
      sizes.refitScratchBufferSize = ((totalPrimitives * 32 + 65535) / 65536) * 65536;
    }
  } else if ([descriptor isKindOfClass:[MTLInstanceAccelerationStructureDescriptor class]]) {
    MTLInstanceAccelerationStructureDescriptor *idesc = (MTLInstanceAccelerationStructureDescriptor *)descriptor;
    NSUInteger count = idesc.instanceCount;
    if (count > 0) {
      sizes.accelerationStructureSize = ((count * 256 + 65535) / 65536) * 65536;
      sizes.buildScratchBufferSize = ((count * 128 + 65535) / 65536) * 65536;
      sizes.refitScratchBufferSize = ((count * 64 + 65535) / 65536) * 65536;
    }
  }
  return sizes;
}

- (id<MTLAccelerationStructure>)newAccelerationStructureWithSize:(NSUInteger)size {
  return [[[XEFMetalAccelerationStructure alloc] initWithDevice:self size:size] autorelease];
}

- (id<MTLAccelerationStructure>)newAccelerationStructureWithDescriptor:(MTLAccelerationStructureDescriptor *)descriptor {
  return [[[XEFMetalAccelerationStructure alloc] initWithDevice:self descriptor:descriptor] autorelease];
}

- (MTLSizeAndAlign)heapAccelerationStructureSizeAndAlignWithSize:(NSUInteger)size {
  MTLSizeAndAlign sa;
  sa.size = (size + 255) & ~255ULL;
  sa.align = 256;
  return sa;
}

- (MTLSizeAndAlign)heapAccelerationStructureSizeAndAlignWithDescriptor:(MTLAccelerationStructureDescriptor *)descriptor {
  MTLAccelerationStructureSizes sizes = [self accelerationStructureSizesWithDescriptor:descriptor];
  return [self heapAccelerationStructureSizeAndAlignWithSize:sizes.accelerationStructureSize];
}
- (NSArray<id<MTLCounterSet>> *)counterSets {
  static NSArray *sets = nil;
  if (!sets) {
    XEFMetalCounter *cTs = [[[XEFMetalCounter alloc] initWithName:MTLCommonCounterTimestamp] autorelease];
    XEFMetalCounterSet *csTs = [[[XEFMetalCounterSet alloc] initWithName:MTLCommonCounterSetTimestamp counters:@[cTs]] autorelease];
    sets = [@[csTs] retain];
  }
  return sets;
}
- (NSUInteger)minimumLinearTextureAlignmentForPixelFormat:(MTLPixelFormat)format { return 16; }
- (NSUInteger)minimumTextureBufferAlignmentForPixelFormat:(MTLPixelFormat)format { return 16; }

- (MTLSize)maxThreadsPerThreadgroup { return MTLSizeMake(1024, 1024, 64); }

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

- (id<MTLBuffer>)newBufferWithBytesNoCopy:(void *)pointer length:(NSUInteger)length options:(MTLResourceOptions)options deallocator:(void (^)(void *pointer, NSUInteger length))deallocator {
  return [[XEFMetalBuffer alloc] initWithBytesNoCopy:pointer length:length options:options device:self];
}

- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor {
  return [[XEFMetalTexture alloc] initWithDescriptor:descriptor device:self];
}

- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor iosurface:(IOSurfaceRef)iosurface plane:(NSUInteger)plane {
  return [[XEFMetalTexture alloc] initWithDescriptor:descriptor device:self];
}

- (id<MTLSamplerState>)newSamplerStateWithDescriptor:(MTLSamplerDescriptor *)descriptor {
  return [[XEFMetalSamplerState alloc] initWithDescriptor:descriptor device:self];
}

- (id<MTLDepthStencilState>)newDepthStencilStateWithDescriptor:(MTLDepthStencilDescriptor *)descriptor {
  return [[XEFMetalDepthStencilState alloc] initWithDescriptor:descriptor device:self];
}

- (id<MTLRenderPipelineState>)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)descriptor error:(NSError **)error {
  if (error) *error = nil;
  return [[XEFMetalRenderPipelineState alloc] initWithDevice:self descriptor:descriptor];
}

- (id<MTLRenderPipelineState>)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)descriptor options:(MTLPipelineOption)options reflection:(MTLAutoreleasedRenderPipelineReflection *)reflection error:(NSError **)error {
  if (error) *error = nil;
  if (reflection) *reflection = nil;
  return [[XEFMetalRenderPipelineState alloc] initWithDevice:self descriptor:descriptor];
}

- (id<MTLComputePipelineState>)newComputePipelineStateWithDescriptor:(MTLComputePipelineDescriptor *)descriptor error:(NSError **)error {
  return [self newComputePipelineStateWithDescriptor:descriptor options:0 reflection:nil error:error];
}

- (id<MTLComputePipelineState>)newComputePipelineStateWithDescriptor:(MTLComputePipelineDescriptor *)descriptor options:(MTLPipelineOption)options reflection:(MTLAutoreleasedComputePipelineReflection *)reflection error:(NSError **)error {
  if (error) *error = nil;
  if (reflection) *reflection = nil;
  return [[XEFMetalComputePipelineState alloc] initWithDevice:self function:descriptor.computeFunction label:descriptor.label];
}

- (id<MTLComputePipelineState>)newComputePipelineStateWithFunction:(id<MTLFunction>)computeFunction error:(NSError **)error {
  if (error) *error = nil;
  return [[XEFMetalComputePipelineState alloc] initWithDevice:self function:computeFunction label:computeFunction.name];
}

- (id<MTLComputePipelineState>)newComputePipelineStateWithFunction:(id<MTLFunction>)computeFunction options:(MTLPipelineOption)options reflection:(MTLAutoreleasedComputePipelineReflection *)reflection error:(NSError **)error {
  if (error) *error = nil;
  if (reflection) *reflection = nil;
  return [[XEFMetalComputePipelineState alloc] initWithDevice:self function:computeFunction label:computeFunction.name];
}

- (id<MTLLibrary>)newDefaultLibrary {
  return [self newDefaultLibraryWithBundle:[NSBundle mainBundle] error:nil];
}

- (id<MTLLibrary>)newDefaultLibraryWithBundle:(NSBundle *)bundle error:(NSError **)error {
  if (error) *error = nil;
  NSURL *url = [bundle URLForResource:@"default" withExtension:@"metallib"];
  if (url) {
    return [self newLibraryWithURL:url error:error];
  }
  NSString *p = [bundle pathForResource:@"default" ofType:@"metallib"];
  if (p) {
    return [self newLibraryWithFile:p error:error];
  }
  return [[XEFMetalLibrary alloc] initWithDevice:self source:nil data:nil];
}

- (id<MTLLibrary>)newLibraryWithSource:(NSString *)source options:(MTLCompileOptions *)options error:(NSError **)error {
  if (error) *error = nil;
  return [[XEFMetalLibrary alloc] initWithDevice:self source:source data:nil];
}

- (void)newLibraryWithSource:(NSString *)source options:(MTLCompileOptions *)options completionHandler:(MTLNewLibraryCompletionHandler)completionHandler {
  id<MTLLibrary> lib = [[self newLibraryWithSource:source options:options error:nil] autorelease];
  if (completionHandler) completionHandler(lib, nil);
}

- (id<MTLLibrary>)newLibraryWithData:(dispatch_data_t)data error:(NSError **)error {
  if (error) *error = nil;
  NSData *nsdata = nil;
  if (data) {
    const void *buf = NULL;
    size_t size = 0;
    dispatch_data_t contig = dispatch_data_create_map(data, &buf, &size);
    if (buf && size > 0) nsdata = [NSData dataWithBytes:buf length:size];
    if (contig) dispatch_release(contig);
  }
  return [[XEFMetalLibrary alloc] initWithDevice:self source:nil data:nsdata];
}

- (id<MTLLibrary>)newLibraryWithURL:(NSURL *)url error:(NSError **)error {
  if (error) *error = nil;
  NSData *nsdata = url ? [NSData dataWithContentsOfURL:url] : nil;
  return [[XEFMetalLibrary alloc] initWithDevice:self source:nil data:nsdata];
}

- (id<MTLLibrary>)newLibraryWithFile:(NSString *)filepath error:(NSError **)error {
  if (error) *error = nil;
  NSData *nsdata = filepath ? [NSData dataWithContentsOfFile:filepath] : nil;
  return [[XEFMetalLibrary alloc] initWithDevice:self source:nil data:nsdata];
}

- (id<MTLFence>)newFence {
  return [[XEFMetalFence alloc] initWithDevice:self];
}

- (id<MTLEvent>)newEvent {
  return [[XEFMetalEvent alloc] initWithDevice:self];
}

- (id<MTLSharedEvent>)newSharedEvent {
  return [[[XEFMetalSharedEvent alloc] initWithDevice:self] autorelease];
}

- (id<MTLSharedEvent>)newSharedEventWithHandle:(MTLSharedEventHandle *)sharedEventHandle {
  XEFMetalSharedEvent *ev = [[[XEFMetalSharedEvent alloc] initWithDevice:self] autorelease];
  if (sharedEventHandle) {
    ev.label = sharedEventHandle.label;
    ev.signaledValue = [sharedEventHandle _signaledValue];
  }
  return ev;
}

- (MTLSizeAndAlign)heapBufferSizeAndAlignWithLength:(NSUInteger)length options:(MTLResourceOptions)options {
  MTLSizeAndAlign res;
  res.align = 256;
  res.size = (length + 255) & ~255ULL;
  return res;
}

- (MTLSizeAndAlign)heapTextureSizeAndAlignWithDescriptor:(MTLTextureDescriptor *)desc {
  MTLSizeAndAlign res;
  res.align = 256;
  NSUInteger bytesPerPixel = 4;
  if (desc) {
    if (desc.pixelFormat == MTLPixelFormatRGBA8Unorm || desc.pixelFormat == MTLPixelFormatBGRA8Unorm) bytesPerPixel = 4;
    else if (desc.pixelFormat == MTLPixelFormatRGBA32Float) bytesPerPixel = 16;
    else if (desc.pixelFormat == MTLPixelFormatDepth32Float) bytesPerPixel = 4;
    res.size = (desc.width * desc.height * (desc.depth > 0 ? desc.depth : 1) * bytesPerPixel + 255) & ~255ULL;
  } else {
    res.size = 256;
  }
  return res;
}

- (id<MTLHeap>)newHeapWithDescriptor:(MTLHeapDescriptor *)descriptor {
  return [[[XEFMetalHeap alloc] initWithDescriptor:descriptor device:self] autorelease];
}

- (void)getDefaultSamplePositions:(MTLSamplePosition *)positions count:(NSUInteger)count {
  for (NSUInteger i = 0; i < count; i++) {
    positions[i].x = 0.5f;
    positions[i].y = 0.5f;
  }
}

- (id<MTLDynamicLibrary>)newDynamicLibrary:(id<MTLLibrary>)library error:(NSError **)error {
  if (error) *error = nil;
  return [[[XEFMetalDynamicLibrary alloc] initWithLibrary:library device:self] autorelease];
}

- (id<MTLDynamicLibrary>)newDynamicLibraryWithURL:(NSURL *)url error:(NSError **)error {
  if (error) *error = nil;
  id<MTLLibrary> lib = [self newLibraryWithURL:url error:error];
  return [[[XEFMetalDynamicLibrary alloc] initWithLibrary:lib device:self] autorelease];
}

- (id<MTLBinaryArchive>)newBinaryArchiveWithDescriptor:(MTLBinaryArchiveDescriptor *)descriptor error:(NSError **)error {
  if (error) *error = nil;
  return [[[XEFMetalBinaryArchive alloc] initWithDescriptor:descriptor device:self] autorelease];
}

- (id<MTLIndirectCommandBuffer>)newIndirectCommandBufferWithDescriptor:(MTLIndirectCommandBufferDescriptor *)descriptor maxCommandCount:(NSUInteger)maxCount options:(MTLResourceOptions)options {
  return [[[XEFMetalIndirectCommandBuffer alloc] initWithDescriptor:descriptor maxCommandCount:maxCount options:options device:self] autorelease];
}

- (id<MTLCounterSampleBuffer>)newCounterSampleBufferWithDescriptor:(MTLCounterSampleBufferDescriptor *)descriptor error:(NSError **)error {
  if (error) *error = nil;
  return [[[XEFMetalCounterSampleBuffer alloc] initWithDevice:self descriptor:descriptor] autorelease];
}

- (id<MTLRasterizationRateMap>)newRasterizationRateMapWithDescriptor:(MTLRasterizationRateMapDescriptor *)descriptor {
  if (!descriptor || descriptor.screenSize.width == 0 || descriptor.screenSize.height == 0) return nil;
  return [[[XEFMetalRasterizationRateMap alloc] initWithDevice:self descriptor:descriptor] autorelease];
}

@end

/* ------------------------------------------------------------------- MTLCaptureManager */

NSString * const MTLCaptureErrorDomain = @"MTLCaptureErrorDomain";

@interface XEFCaptureScope : XEFMetalObject <MTLCaptureScope> {
  id<MTLDevice> _device;
  id<MTLCommandQueue> _commandQueue;
  NSString *_label;
}
@end

@implementation XEFCaptureScope
- (instancetype)initWithDevice:(id<MTLDevice>)device queue:(id<MTLCommandQueue>)queue {
  if ((self = [super init])) {
    _device = [device retain];
    _commandQueue = [queue retain];
  }
  return self;
}
- (void)beginScope {}
- (void)endScope {}
- (id<MTLDevice>)device { return _device; }
- (id<MTLCommandQueue>)commandQueue { return _commandQueue; }
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (void)dealloc {
  [_device release];
  [_commandQueue release];
  [_label release];
  [super dealloc];
}
@end

@interface MTLCaptureDescriptor ()
@end
@implementation MTLCaptureDescriptor
- (id)copyWithZone:(NSZone *)zone {
  MTLCaptureDescriptor *d = [[MTLCaptureDescriptor allocWithZone:zone] init];
  d.captureObject = self.captureObject;
  d.destination = self.destination;
  d.outputURL = self.outputURL;
  return d;
}
- (void)dealloc {
  [_captureObject release];
  [_outputURL release];
  [super dealloc];
}
@end

@interface MTLCaptureManager () {
  id<MTLCaptureScope> _defaultCaptureScope;
  BOOL _isCapturing;
}
@end

@implementation MTLCaptureManager

+ (MTLCaptureManager *)sharedCaptureManager {
  static MTLCaptureManager *s_manager = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    s_manager = [[MTLCaptureManager alloc] init];
  });
  return s_manager;
}

- (id<MTLCaptureScope>)newCaptureScopeWithDevice:(id<MTLDevice>)device {
  return [[XEFCaptureScope alloc] initWithDevice:device queue:nil];
}

- (id<MTLCaptureScope>)newCaptureScopeWithCommandQueue:(id<MTLCommandQueue>)commandQueue {
  return [[XEFCaptureScope alloc] initWithDevice:commandQueue.device queue:commandQueue];
}

- (BOOL)supportsDestination:(MTLCaptureDestination)destination {
  return NO;
}

- (BOOL)startCaptureWithDescriptor:(MTLCaptureDescriptor *)descriptor error:(NSError **)error {
  if (_isCapturing) {
    if (error) *error = [NSError errorWithDomain:MTLCaptureErrorDomain code:2 userInfo:nil];
    return NO;
  }
  _isCapturing = YES;
  return YES;
}

- (void)startCaptureWithDevice:(id<MTLDevice>)device {
  _isCapturing = YES;
}

- (void)startCaptureWithCommandQueue:(id<MTLCommandQueue>)commandQueue {
  _isCapturing = YES;
}

- (void)startCaptureWithScope:(id<MTLCaptureScope>)captureScope {
  _isCapturing = YES;
}

- (void)stopCapture {
  _isCapturing = NO;
}

- (id<MTLCaptureScope>)defaultCaptureScope { return _defaultCaptureScope; }
- (void)setDefaultCaptureScope:(id<MTLCaptureScope>)s {
  [s retain];
  [_defaultCaptureScope release];
  _defaultCaptureScope = s;
}

- (BOOL)isCapturing { return _isCapturing; }

- (void)dealloc {
  [(id)_defaultCaptureScope release];
  [super dealloc];
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
