/* Metal.framework for xef-osx: descriptor classes. The device, resources and command objects live in MetalCore.m
 * (thin layer over the host Metal->Vulkan engine), the remaining auxiliary classes in MetalExtras.m. */
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

/* ------------------------------------------------------------------- MTLStageInputOutputDescriptor */

@implementation MTLBufferLayoutDescriptor {
  NSUInteger _stride;
  MTLStepFunction _stepFunction;
  NSUInteger _stepRate;
}
- (id)init {
  if ((self = [super init])) {
    _stride = 0;
    _stepFunction = MTLStepFunctionConstant;
    _stepRate = 1;
  }
  return self;
}
- (NSUInteger)stride { return _stride; } - (void)setStride:(NSUInteger)s { _stride = s; }
- (MTLStepFunction)stepFunction { return _stepFunction; } - (void)setStepFunction:(MTLStepFunction)f { _stepFunction = f; }
- (NSUInteger)stepRate { return _stepRate; } - (void)setStepRate:(NSUInteger)r { _stepRate = r; }
- (id)copyWithZone:(NSZone *)zone {
  MTLBufferLayoutDescriptor *c = [[MTLBufferLayoutDescriptor allocWithZone:zone] init];
  c->_stride = _stride; c->_stepFunction = _stepFunction; c->_stepRate = _stepRate;
  return c;
}
@end

@implementation MTLBufferLayoutDescriptorArray {
@public
  MTLBufferLayoutDescriptor *_layouts[31];
}
- (MTLBufferLayoutDescriptor *)objectAtIndexedSubscript:(NSUInteger)idx {
  if (idx >= 31) return nil;
  if (!_layouts[idx]) _layouts[idx] = [[MTLBufferLayoutDescriptor alloc] init];
  return _layouts[idx];
}
- (void)setObject:(MTLBufferLayoutDescriptor *)layout atIndexedSubscript:(NSUInteger)idx {
  if (idx >= 31) return;
  MTLBufferLayoutDescriptor *c = [layout copy];
  [_layouts[idx] release];
  _layouts[idx] = c;
}
- (void)dealloc {
  for (int i = 0; i < 31; i++) [_layouts[i] release];
  [super dealloc];
}
@end

@implementation MTLAttributeDescriptor {
  MTLAttributeFormat _format;
  NSUInteger _offset;
  NSUInteger _bufferIndex;
}
- (MTLAttributeFormat)format { return _format; } - (void)setFormat:(MTLAttributeFormat)f { _format = f; }
- (NSUInteger)offset { return _offset; } - (void)setOffset:(NSUInteger)o { _offset = o; }
- (NSUInteger)bufferIndex { return _bufferIndex; } - (void)setBufferIndex:(NSUInteger)i { _bufferIndex = i; }
- (id)copyWithZone:(NSZone *)zone {
  MTLAttributeDescriptor *c = [[MTLAttributeDescriptor allocWithZone:zone] init];
  c->_format = _format; c->_offset = _offset; c->_bufferIndex = _bufferIndex;
  return c;
}
@end

@implementation MTLAttributeDescriptorArray {
@public
  MTLAttributeDescriptor *_attributes[31];
}
- (MTLAttributeDescriptor *)objectAtIndexedSubscript:(NSUInteger)idx {
  if (idx >= 31) return nil;
  if (!_attributes[idx]) _attributes[idx] = [[MTLAttributeDescriptor alloc] init];
  return _attributes[idx];
}
- (void)setObject:(MTLAttributeDescriptor *)attr atIndexedSubscript:(NSUInteger)idx {
  if (idx >= 31) return;
  MTLAttributeDescriptor *c = [attr copy];
  [_attributes[idx] release];
  _attributes[idx] = c;
}
- (void)dealloc {
  for (int i = 0; i < 31; i++) [_attributes[i] release];
  [super dealloc];
}
@end

@implementation MTLStageInputOutputDescriptor {
  MTLBufferLayoutDescriptorArray *_layouts;
  MTLAttributeDescriptorArray *_attributes;
  MTLIndexType _indexType;
  NSUInteger _indexBufferIndex;
}
+ (MTLStageInputOutputDescriptor *)stageInputOutputDescriptor { return [[[self alloc] init] autorelease]; }
- (id)init {
  if ((self = [super init])) {
    _layouts = [[MTLBufferLayoutDescriptorArray alloc] init];
    _attributes = [[MTLAttributeDescriptorArray alloc] init];
    _indexType = MTLIndexTypeUInt16;
  }
  return self;
}
- (MTLBufferLayoutDescriptorArray *)layouts { return _layouts; }
- (MTLAttributeDescriptorArray *)attributes { return _attributes; }
- (MTLIndexType)indexType { return _indexType; } - (void)setIndexType:(MTLIndexType)t { _indexType = t; }
- (NSUInteger)indexBufferIndex { return _indexBufferIndex; } - (void)setIndexBufferIndex:(NSUInteger)i { _indexBufferIndex = i; }
- (void)reset {
  [_layouts release]; _layouts = [[MTLBufferLayoutDescriptorArray alloc] init];
  [_attributes release]; _attributes = [[MTLAttributeDescriptorArray alloc] init];
  _indexType = MTLIndexTypeUInt16;
  _indexBufferIndex = 0;
}
- (id)copyWithZone:(NSZone *)zone {
  MTLStageInputOutputDescriptor *c = [[MTLStageInputOutputDescriptor allocWithZone:zone] init];
  for (int i = 0; i < 31; i++) {
    if (_layouts->_layouts[i]) c->_layouts->_layouts[i] = [_layouts->_layouts[i] copy];
    if (_attributes->_attributes[i]) c->_attributes->_attributes[i] = [_attributes->_attributes[i] copy];
  }
  c->_indexType = _indexType;
  c->_indexBufferIndex = _indexBufferIndex;
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
  NSUInteger _maxVertexAmplificationCount;
  BOOL _supportAddingVertexBinaryFunctions;
  BOOL _supportAddingFragmentBinaryFunctions;
  NSUInteger _maxTessellationFactor;
  BOOL _tessellationFactorScaleEnabled;
  MTLTessellationFactorFormat _tessellationFactorFormat;
  MTLTessellationControlPointIndexType _tessellationControlPointIndexType;
  MTLTessellationFactorStepFunction _tessellationFactorStepFunction;
  MTLWinding _tessellationOutputWindingOrder;
  MTLTessellationPartitionMode _tessellationPartitionMode;
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
    _maxVertexAmplificationCount = 1;
    _maxTessellationFactor = 16;
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
- (NSUInteger)maxVertexAmplificationCount { return _maxVertexAmplificationCount; } - (void)setMaxVertexAmplificationCount:(NSUInteger)c { _maxVertexAmplificationCount = c; }
- (BOOL)supportAddingVertexBinaryFunctions { return _supportAddingVertexBinaryFunctions; } - (void)setSupportAddingVertexBinaryFunctions:(BOOL)s { _supportAddingVertexBinaryFunctions = s; }
- (BOOL)supportAddingFragmentBinaryFunctions { return _supportAddingFragmentBinaryFunctions; } - (void)setSupportAddingFragmentBinaryFunctions:(BOOL)s { _supportAddingFragmentBinaryFunctions = s; }
- (NSUInteger)maxTessellationFactor { return _maxTessellationFactor; } - (void)setMaxTessellationFactor:(NSUInteger)f { _maxTessellationFactor = f; }
- (BOOL)isTessellationFactorScaleEnabled { return _tessellationFactorScaleEnabled; } - (void)setTessellationFactorScaleEnabled:(BOOL)e { _tessellationFactorScaleEnabled = e; }
- (MTLTessellationFactorFormat)tessellationFactorFormat { return _tessellationFactorFormat; } - (void)setTessellationFactorFormat:(MTLTessellationFactorFormat)f { _tessellationFactorFormat = f; }
- (MTLTessellationControlPointIndexType)tessellationControlPointIndexType { return _tessellationControlPointIndexType; } - (void)setTessellationControlPointIndexType:(MTLTessellationControlPointIndexType)t { _tessellationControlPointIndexType = t; }
- (MTLTessellationFactorStepFunction)tessellationFactorStepFunction { return _tessellationFactorStepFunction; } - (void)setTessellationFactorStepFunction:(MTLTessellationFactorStepFunction)f { _tessellationFactorStepFunction = f; }
- (MTLWinding)tessellationOutputWindingOrder { return _tessellationOutputWindingOrder; } - (void)setTessellationOutputWindingOrder:(MTLWinding)w { _tessellationOutputWindingOrder = w; }
- (MTLTessellationPartitionMode)tessellationPartitionMode { return _tessellationPartitionMode; } - (void)setTessellationPartitionMode:(MTLTessellationPartitionMode)m { _tessellationPartitionMode = m; }
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
  _maxVertexAmplificationCount = 1;
  _supportAddingVertexBinaryFunctions = NO;
  _supportAddingFragmentBinaryFunctions = NO;
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
  c.maxVertexAmplificationCount = _maxVertexAmplificationCount;
  c.supportAddingVertexBinaryFunctions = _supportAddingVertexBinaryFunctions;
  c.supportAddingFragmentBinaryFunctions = _supportAddingFragmentBinaryFunctions;
  c.maxTessellationFactor = _maxTessellationFactor;
  c.tessellationFactorScaleEnabled = _tessellationFactorScaleEnabled;
  c.tessellationFactorFormat = _tessellationFactorFormat;
  c.tessellationControlPointIndexType = _tessellationControlPointIndexType;
  c.tessellationFactorStepFunction = _tessellationFactorStepFunction;
  c.tessellationOutputWindingOrder = _tessellationOutputWindingOrder;
  c.tessellationPartitionMode = _tessellationPartitionMode;
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
  NSUInteger _maxCallStackDepth;
  MTLStageInputOutputDescriptor *_stageInputDescriptor;
  MTLPipelineBufferDescriptorArray *_buffers;
  BOOL _supportIndirectCommandBuffers;
  BOOL _supportAddingBinaryFunctions;
  NSArray *_binaryArchives;
  NSArray *_preloadedLibraries;
  MTLLinkedFunctions *_linkedFunctions;
}
- (id)init {
  if ((self = [super init])) {
    _buffers = [[MTLPipelineBufferDescriptorArray alloc] init];
    _maxCallStackDepth = 1;
  }
  return self;
}
- (NSString *)label { return _label; } - (void)setLabel:(NSString *)l { [l retain]; [_label release]; _label = l; }
- (id<MTLFunction>)computeFunction { return _computeFunction; } - (void)setComputeFunction:(id<MTLFunction>)f { [f retain]; [(id)_computeFunction release]; _computeFunction = f; }
- (BOOL)threadGroupSizeIsMultipleOfThreadExecutionWidth { return _threadGroupSizeIsMultipleOfThreadExecutionWidth; }
- (void)setThreadGroupSizeIsMultipleOfThreadExecutionWidth:(BOOL)f { _threadGroupSizeIsMultipleOfThreadExecutionWidth = f; }
- (NSUInteger)maxTotalThreadsPerThreadgroup { return _maxTotalThreadsPerThreadgroup; }
- (void)setMaxTotalThreadsPerThreadgroup:(NSUInteger)m { _maxTotalThreadsPerThreadgroup = m; }
- (NSUInteger)maxCallStackDepth { return _maxCallStackDepth; }
- (void)setMaxCallStackDepth:(NSUInteger)d { _maxCallStackDepth = d; }
- (MTLStageInputOutputDescriptor *)stageInputDescriptor { return _stageInputDescriptor; }
- (void)setStageInputDescriptor:(MTLStageInputOutputDescriptor *)d { MTLStageInputOutputDescriptor *c = [d copy]; [_stageInputDescriptor release]; _stageInputDescriptor = c; }
- (BOOL)supportAddingBinaryFunctions { return _supportAddingBinaryFunctions; }
- (void)setSupportAddingBinaryFunctions:(BOOL)s { _supportAddingBinaryFunctions = s; }
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
  [_stageInputDescriptor release]; _stageInputDescriptor = nil;
  [_binaryArchives release]; _binaryArchives = nil;
  [_preloadedLibraries release]; _preloadedLibraries = nil;
  [_linkedFunctions release]; _linkedFunctions = nil;
  _supportIndirectCommandBuffers = NO;
  _supportAddingBinaryFunctions = NO;
  _maxCallStackDepth = 1;
}
- (id)copyWithZone:(NSZone *)zone {
  MTLComputePipelineDescriptor *c = [[MTLComputePipelineDescriptor allocWithZone:zone] init];
  c.label = _label;
  c.computeFunction = _computeFunction;
  c.threadGroupSizeIsMultipleOfThreadExecutionWidth = _threadGroupSizeIsMultipleOfThreadExecutionWidth;
  c.maxTotalThreadsPerThreadgroup = _maxTotalThreadsPerThreadgroup;
  c.maxCallStackDepth = _maxCallStackDepth;
  c.stageInputDescriptor = _stageInputDescriptor;
  c.supportAddingBinaryFunctions = _supportAddingBinaryFunctions;
  c.supportIndirectCommandBuffers = _supportIndirectCommandBuffers;
  c.binaryArchives = _binaryArchives;
  c.preloadedLibraries = _preloadedLibraries;
  c.linkedFunctions = _linkedFunctions;
  return c;
}
- (void)dealloc {
  [_label release]; [(id)_computeFunction release];
  [_buffers release]; [_stageInputDescriptor release];
  [_binaryArchives release]; [_preloadedLibraries release];
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
  BOOL _supportArgumentBuffers;
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
- (BOOL)supportArgumentBuffers { return _supportArgumentBuffers; } - (void)setSupportArgumentBuffers:(BOOL)s { _supportArgumentBuffers = s; }
- (id)copyWithZone:(NSZone *)zone {
  MTLSamplerDescriptor *c = [[MTLSamplerDescriptor allocWithZone:zone] init];
  c.label = _label; c.minFilter = _minFilter; c.magFilter = _magFilter; c.mipFilter = _mipFilter;
  c.sAddressMode = _sAddressMode; c.tAddressMode = _tAddressMode; c.rAddressMode = _rAddressMode;
  c.maxAnisotropy = _maxAnisotropy; c.compareFunction = _compareFunction;
  c.normalizedCoordinates = _normalizedCoordinates;
  c.lodMinClamp = _lodMinClamp; c.lodMaxClamp = _lodMaxClamp;
  c.borderColor = _borderColor;
  c.supportArgumentBuffers = _supportArgumentBuffers;
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
  MTLTextureCompressionType _compressionType;
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
    _compressionType = MTLTextureCompressionTypeLossless;
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
- (MTLTextureCompressionType)compressionType { return _compressionType; } - (void)setCompressionType:(MTLTextureCompressionType)t { _compressionType = t; }
- (MTLTextureSwizzleChannels)swizzle { return _swizzle; } - (void)setSwizzle:(MTLTextureSwizzleChannels)s { _swizzle = s; }
- (id)copyWithZone:(NSZone *)zone {
  MTLTextureDescriptor *c = [[MTLTextureDescriptor allocWithZone:zone] init];
  c->_textureType = _textureType; c->_pixelFormat = _pixelFormat;
  c->_width = _width; c->_height = _height; c->_depth = _depth;
  c->_mipmapLevelCount = _mipmapLevelCount; c->_sampleCount = _sampleCount;
  c->_arrayLength = _arrayLength; c->_usage = _usage;
  c->_resourceOptions = _resourceOptions; c->_storageMode = _storageMode;
  c->_compressionType = _compressionType;
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
  NSUInteger _resolveLevel;
  NSUInteger _resolveSlice;
  NSUInteger _resolveDepthPlane;
  MTLLoadAction _loadAction;
  MTLStoreAction _storeAction;
  MTLStoreActionOptions _storeActionOptions;
}
- (id<MTLTexture>)texture { return _texture; } - (void)setTexture:(id<MTLTexture>)t { [t retain]; [(id)_texture release]; _texture = t; }
- (id<MTLTexture>)resolveTexture { return _resolveTexture; } - (void)setResolveTexture:(id<MTLTexture>)t { [t retain]; [(id)_resolveTexture release]; _resolveTexture = t; }
- (NSUInteger)level { return _level; } - (void)setLevel:(NSUInteger)l { _level = l; }
- (NSUInteger)slice { return _slice; } - (void)setSlice:(NSUInteger)s { _slice = s; }
- (NSUInteger)depthPlane { return _depthPlane; } - (void)setDepthPlane:(NSUInteger)d { _depthPlane = d; }
- (NSUInteger)resolveLevel { return _resolveLevel; } - (void)setResolveLevel:(NSUInteger)l { _resolveLevel = l; }
- (NSUInteger)resolveSlice { return _resolveSlice; } - (void)setResolveSlice:(NSUInteger)s { _resolveSlice = s; }
- (NSUInteger)resolveDepthPlane { return _resolveDepthPlane; } - (void)setResolveDepthPlane:(NSUInteger)d { _resolveDepthPlane = d; }
- (MTLLoadAction)loadAction { return _loadAction; } - (void)setLoadAction:(MTLLoadAction)a { _loadAction = a; }
- (MTLStoreAction)storeAction { return _storeAction; } - (void)setStoreAction:(MTLStoreAction)a { _storeAction = a; }
- (MTLStoreActionOptions)storeActionOptions { return _storeActionOptions; } - (void)setStoreActionOptions:(MTLStoreActionOptions)o { _storeActionOptions = o; }
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
  c.resolveLevel = self.resolveLevel; c.resolveSlice = self.resolveSlice; c.resolveDepthPlane = self.resolveDepthPlane;
  c.loadAction = self.loadAction; c.storeAction = self.storeAction;
  c.storeActionOptions = self.storeActionOptions;
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
  MTLMultisampleDepthResolveFilter _depthResolveFilter;
}
- (id)init {
  if ((self = [super init])) {
    _clearDepth = 1.0;
  }
  return self;
}
- (double)clearDepth { return _clearDepth; } - (void)setClearDepth:(double)d { _clearDepth = d; }
- (MTLMultisampleDepthResolveFilter)depthResolveFilter { return _depthResolveFilter; }
- (void)setDepthResolveFilter:(MTLMultisampleDepthResolveFilter)f { _depthResolveFilter = f; }
- (id)copyWithZone:(NSZone *)zone {
  MTLRenderPassDepthAttachmentDescriptor *c = [[MTLRenderPassDepthAttachmentDescriptor allocWithZone:zone] init];
  c.texture = self.texture; c.resolveTexture = self.resolveTexture;
  c.level = self.level; c.slice = self.slice; c.depthPlane = self.depthPlane;
  c.resolveLevel = self.resolveLevel; c.resolveSlice = self.resolveSlice; c.resolveDepthPlane = self.resolveDepthPlane;
  c.loadAction = self.loadAction; c.storeAction = self.storeAction;
  c.storeActionOptions = self.storeActionOptions;
  c.clearDepth = _clearDepth;
  c.depthResolveFilter = _depthResolveFilter;
  return c;
}
@end

@implementation MTLRenderPassStencilAttachmentDescriptor {
  uint32_t _clearStencil;
  MTLMultisampleStencilResolveFilter _stencilResolveFilter;
}
- (uint32_t)clearStencil { return _clearStencil; } - (void)setClearStencil:(uint32_t)s { _clearStencil = s; }
- (MTLMultisampleStencilResolveFilter)stencilResolveFilter { return _stencilResolveFilter; }
- (void)setStencilResolveFilter:(MTLMultisampleStencilResolveFilter)f { _stencilResolveFilter = f; }
- (id)copyWithZone:(NSZone *)zone {
  MTLRenderPassStencilAttachmentDescriptor *c = [[MTLRenderPassStencilAttachmentDescriptor allocWithZone:zone] init];
  c.texture = self.texture; c.resolveTexture = self.resolveTexture;
  c.level = self.level; c.slice = self.slice; c.depthPlane = self.depthPlane;
  c.resolveLevel = self.resolveLevel; c.resolveSlice = self.resolveSlice; c.resolveDepthPlane = self.resolveDepthPlane;
  c.loadAction = self.loadAction; c.storeAction = self.storeAction;
  c.storeActionOptions = self.storeActionOptions;
  c.clearStencil = _clearStencil;
  c.stencilResolveFilter = _stencilResolveFilter;
  return c;
}
@end

@implementation MTLRenderPassSampleBufferAttachmentDescriptor {
  id<MTLCounterSampleBuffer> _sampleBuffer;
  NSUInteger _startOfVertexSampleIndex;
  NSUInteger _endOfVertexSampleIndex;
  NSUInteger _startOfFragmentSampleIndex;
  NSUInteger _endOfFragmentSampleIndex;
}
- (instancetype)init {
  if ((self = [super init])) {
    _startOfVertexSampleIndex = MTLCounterDontSample;
    _endOfVertexSampleIndex = MTLCounterDontSample;
    _startOfFragmentSampleIndex = MTLCounterDontSample;
    _endOfFragmentSampleIndex = MTLCounterDontSample;
  }
  return self;
}
- (id<MTLCounterSampleBuffer>)sampleBuffer { return _sampleBuffer; }
- (void)setSampleBuffer:(id<MTLCounterSampleBuffer>)b { [b retain]; [(id)_sampleBuffer release]; _sampleBuffer = b; }
- (NSUInteger)startOfVertexSampleIndex { return _startOfVertexSampleIndex; }
- (void)setStartOfVertexSampleIndex:(NSUInteger)i { _startOfVertexSampleIndex = i; }
- (NSUInteger)endOfVertexSampleIndex { return _endOfVertexSampleIndex; }
- (void)setEndOfVertexSampleIndex:(NSUInteger)i { _endOfVertexSampleIndex = i; }
- (NSUInteger)startOfFragmentSampleIndex { return _startOfFragmentSampleIndex; }
- (void)setStartOfFragmentSampleIndex:(NSUInteger)i { _startOfFragmentSampleIndex = i; }
- (NSUInteger)endOfFragmentSampleIndex { return _endOfFragmentSampleIndex; }
- (void)setEndOfFragmentSampleIndex:(NSUInteger)i { _endOfFragmentSampleIndex = i; }
- (id)copyWithZone:(NSZone *)zone {
  MTLRenderPassSampleBufferAttachmentDescriptor *c = [[MTLRenderPassSampleBufferAttachmentDescriptor allocWithZone:zone] init];
  c.sampleBuffer = _sampleBuffer;
  c.startOfVertexSampleIndex = _startOfVertexSampleIndex;
  c.endOfVertexSampleIndex = _endOfVertexSampleIndex;
  c.startOfFragmentSampleIndex = _startOfFragmentSampleIndex;
  c.endOfFragmentSampleIndex = _endOfFragmentSampleIndex;
  return c;
}
- (void)dealloc {
  [(id)_sampleBuffer release];
  [super dealloc];
}
@end

@implementation MTLRenderPassSampleBufferAttachmentDescriptorArray {
@public
  MTLRenderPassSampleBufferAttachmentDescriptor *_attachments[4];
}
- (MTLRenderPassSampleBufferAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)idx {
  if (idx >= 4) return nil;
  if (!_attachments[idx]) _attachments[idx] = [[MTLRenderPassSampleBufferAttachmentDescriptor alloc] init];
  return _attachments[idx];
}
- (void)setObject:(MTLRenderPassSampleBufferAttachmentDescriptor *)attachment atIndexedSubscript:(NSUInteger)idx {
  if (idx >= 4) return;
  MTLRenderPassSampleBufferAttachmentDescriptor *c = [attachment copy];
  [_attachments[idx] release];
  _attachments[idx] = c;
}
- (void)dealloc {
  for (int i = 0; i < 4; i++) [_attachments[i] release];
  [super dealloc];
}
@end

@implementation MTLRenderPassDescriptor {
  MTLRenderPassColorAttachmentDescriptorArray *_colorAttachments;
  MTLRenderPassDepthAttachmentDescriptor *_depthAttachment;
  MTLRenderPassStencilAttachmentDescriptor *_stencilAttachment;
  MTLRenderPassSampleBufferAttachmentDescriptorArray *_sampleBufferAttachments;
  id<MTLBuffer> _visibilityResultBuffer;
  NSUInteger _renderTargetArrayLength;
  NSUInteger _renderTargetWidth;
  NSUInteger _renderTargetHeight;
  NSUInteger _imageblockSampleLength;
  NSUInteger _threadgroupMemoryLength;
  NSUInteger _tileWidth;
  NSUInteger _tileHeight;
  NSUInteger _defaultRasterSampleCount;
  id<MTLRasterizationRateMap> _rasterizationRateMap;
  MTLSamplePosition _samplePositions[4];
  NSUInteger _samplePositionCount;
}
+ (MTLRenderPassDescriptor *)renderPassDescriptor { return [[[self alloc] init] autorelease]; }
- (id)init {
  if ((self = [super init])) {
    _colorAttachments = [[MTLRenderPassColorAttachmentDescriptorArray alloc] init];
    _depthAttachment = [[MTLRenderPassDepthAttachmentDescriptor alloc] init];
    _stencilAttachment = [[MTLRenderPassStencilAttachmentDescriptor alloc] init];
    _sampleBufferAttachments = [[MTLRenderPassSampleBufferAttachmentDescriptorArray alloc] init];
  }
  return self;
}
- (MTLRenderPassColorAttachmentDescriptorArray *)colorAttachments { return _colorAttachments; }
- (MTLRenderPassDepthAttachmentDescriptor *)depthAttachment { return _depthAttachment; } - (void)setDepthAttachment:(MTLRenderPassDepthAttachmentDescriptor *)d { MTLRenderPassDepthAttachmentDescriptor *c = [d copy]; [_depthAttachment release]; _depthAttachment = c; }
- (MTLRenderPassStencilAttachmentDescriptor *)stencilAttachment { return _stencilAttachment; } - (void)setStencilAttachment:(MTLRenderPassStencilAttachmentDescriptor *)s { MTLRenderPassStencilAttachmentDescriptor *c = [s copy]; [_stencilAttachment release]; _stencilAttachment = c; }
- (MTLRenderPassSampleBufferAttachmentDescriptorArray *)sampleBufferAttachments { return _sampleBufferAttachments; }
- (id<MTLBuffer>)visibilityResultBuffer { return _visibilityResultBuffer; } - (void)setVisibilityResultBuffer:(id<MTLBuffer>)b { [b retain]; [(id)_visibilityResultBuffer release]; _visibilityResultBuffer = b; }
- (NSUInteger)renderTargetArrayLength { return _renderTargetArrayLength; } - (void)setRenderTargetArrayLength:(NSUInteger)l { _renderTargetArrayLength = l; }
- (NSUInteger)renderTargetWidth { return _renderTargetWidth; } - (void)setRenderTargetWidth:(NSUInteger)w { _renderTargetWidth = w; }
- (NSUInteger)renderTargetHeight { return _renderTargetHeight; } - (void)setRenderTargetHeight:(NSUInteger)h { _renderTargetHeight = h; }
- (NSUInteger)imageblockSampleLength { return _imageblockSampleLength; } - (void)setImageblockSampleLength:(NSUInteger)l { _imageblockSampleLength = l; }
- (NSUInteger)threadgroupMemoryLength { return _threadgroupMemoryLength; } - (void)setThreadgroupMemoryLength:(NSUInteger)l { _threadgroupMemoryLength = l; }
- (NSUInteger)tileWidth { return _tileWidth; } - (void)setTileWidth:(NSUInteger)w { _tileWidth = w; }
- (NSUInteger)tileHeight { return _tileHeight; } - (void)setTileHeight:(NSUInteger)h { _tileHeight = h; }
- (NSUInteger)defaultRasterSampleCount { return _defaultRasterSampleCount; } - (void)setDefaultRasterSampleCount:(NSUInteger)c { _defaultRasterSampleCount = c; }
- (NSUInteger)getSamplePositions:(MTLSamplePosition *)positions count:(NSUInteger)count {
  NSUInteger n = (_samplePositionCount < count) ? _samplePositionCount : count;
  if (positions && n > 0) memcpy(positions, _samplePositions, n * sizeof(MTLSamplePosition));
  return _samplePositionCount;
}
- (void)setSamplePositions:(const MTLSamplePosition *)positions count:(NSUInteger)count {
  _samplePositionCount = count > 4 ? 4 : count;
  if (positions && _samplePositionCount > 0) {
    memcpy(_samplePositions, positions, _samplePositionCount * sizeof(MTLSamplePosition));
  }
}
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
  for (int i = 0; i < 4; i++) {
    if (_sampleBufferAttachments->_attachments[i]) {
      c->_sampleBufferAttachments->_attachments[i] = [_sampleBufferAttachments->_attachments[i] copy];
    }
  }
  c.visibilityResultBuffer = _visibilityResultBuffer;
  c.renderTargetArrayLength = _renderTargetArrayLength;
  c.renderTargetWidth = _renderTargetWidth;
  c.renderTargetHeight = _renderTargetHeight;
  c.imageblockSampleLength = _imageblockSampleLength;
  c.threadgroupMemoryLength = _threadgroupMemoryLength;
  c.tileWidth = _tileWidth;
  c.tileHeight = _tileHeight;
  c.defaultRasterSampleCount = _defaultRasterSampleCount;
  c.rasterizationRateMap = _rasterizationRateMap;
  [c setSamplePositions:_samplePositions count:_samplePositionCount];
  return c;
}
- (void)dealloc {
  [_colorAttachments release]; [_depthAttachment release]; [_stencilAttachment release];
  [_sampleBufferAttachments release];
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

