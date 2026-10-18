/* Metal.framework core for xef-osx: thin Objective-C objects over the host Metal->Vulkan engine (xef_mtl_*).
 * Command buffers record a byte stream (xef_mtl.h) that the host translates at commit time. */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#import <Block.h>
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "xef_mtl.h"

#define XEF_UNUSED __attribute__((unused))

/* ------------------------------------------------------------------- base */

static id xef_metal_stub(id self, SEL _cmd, ...) {
  static NSMutableSet *seen;
  @synchronized ([NSObject class]) {
    if (!seen) seen = [[NSMutableSet alloc] init];
    NSString *k = [NSString stringWithFormat:@"%s %s", class_getName(object_getClass(self)), sel_getName(_cmd)];
    if (![seen containsObject:k]) {
      [seen addObject:k];
      if (getenv("XEF_METAL_STUBS")) fprintf(stderr, "METAL STUB -[%s %s]\n", class_getName(object_getClass(self)), sel_getName(_cmd));
    }
  }
  return nil;
}

@interface XEFMetalObject : NSObject {
@public
  NSString *_label;
}
@end

@implementation XEFMetalObject
+ (BOOL)resolveInstanceMethod:(SEL)sel {
  const char *n = sel_getName(sel);
  if (n[0] == '_' || !strncmp(n, "respondsTo", 10) || !strncmp(n, "init", 4) || !strncmp(n, "copy", 4) ||
      !strncmp(n, "mutableCopy", 11) || !strncmp(n, "dealloc", 7) || !strncmp(n, "encodeWith", 10)) return NO;
  class_addMethod(self, sel, (IMP)xef_metal_stub, "@@:");
  return YES;
}
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)l { NSString *c = [l copy]; [_label release]; _label = c; }
- (void)dealloc { [_label release]; [super dealloc]; }
@end

static id<MTLDevice> xef_shared_device(void);

/* ------------------------------------------------------------------- buffers */

@interface XEFMetalBuffer : XEFMetalObject <MTLBuffer> {
@public
  uint32_t _id;
  void *_contents;
  NSUInteger _length;
  uint64_t _gpuAddress;
  MTLResourceOptions _options;
  void (^_deallocator)(void *pointer, NSUInteger length);
  void *_noCopyPointer;
  id<MTLHeap> _heap;
}
@end

@implementation XEFMetalBuffer
- (id<MTLDevice>)device { return xef_shared_device(); }
- (NSUInteger)length { return _length; }
- (void *)contents { return _contents; }
- (uint64_t)gpuAddress { return _gpuAddress; }
- (void)didModifyRange:(NSRange)range {}
- (MTLResourceOptions)resourceOptions { return _options; }
- (MTLStorageMode)storageMode { return (MTLStorageMode)((_options >> MTLResourceStorageModeShift) & 0xf); }
- (MTLCPUCacheMode)cpuCacheMode { return (MTLCPUCacheMode)(_options & 0xf); }
- (MTLHazardTrackingMode)hazardTrackingMode { return (MTLHazardTrackingMode)((_options >> MTLResourceHazardTrackingModeShift) & 0x3); }
- (NSUInteger)allocatedSize { return (_length + 4095) & ~(NSUInteger)4095; }
- (MTLPurgeableState)setPurgeableState:(MTLPurgeableState)state { return MTLPurgeableStateNonVolatile; }
- (id<MTLHeap>)heap { return _heap; }
- (NSUInteger)heapOffset { return 0; }
- (void)makeAliasable {}
- (BOOL)isAliasable { return NO; }
- (void)addDebugMarker:(NSString *)marker range:(NSRange)range {}
- (void)removeAllDebugMarkers {}
- (id<MTLBuffer>)remoteStorageBuffer { return nil; }
- (id<MTLBuffer>)newRemoteBufferViewForDevice:(id<MTLDevice>)device { return nil; }
- (void)dealloc {
  if (_id) xef_mtl_buffer_destroy(_id);
  if (_deallocator) { _deallocator(_noCopyPointer, _length); Block_release(_deallocator); }
  [super dealloc];
}
@end

/* ------------------------------------------------------------------- textures */

@interface XEFMetalTexture : XEFMetalObject <MTLTexture> {
@public
  uint32_t _id;
  uint64_t _rid;
  MTLTextureType _type;
  MTLPixelFormat _pixelFormat;
  NSUInteger _width, _height, _depth, _mips, _arrayLength, _samples;
  MTLTextureUsage _usage;
  MTLStorageMode _storageMode;
  MTLTextureSwizzleChannels _swizzle;
  BOOL _owned;               /* destroys the host texture on dealloc */
  BOOL _framebufferOnly;
  id<MTLTexture> _parent;
  NSUInteger _parentLevel, _parentSlice;
  id<MTLBuffer> _buffer;
  NSUInteger _bufferOffset, _bufferBytesPerRow;
  id<MTLHeap> _heap;         /* not retained: the heap outlives its resources */
}
+ (id)wrapHostTexture:(uint32_t)tex resourceID:(uint64_t)rid width:(NSUInteger)w height:(NSUInteger)h pixelFormat:(MTLPixelFormat)pf;
@end

static void xef_region6(MTLRegion r, uint32_t *out) {
  out[0] = (uint32_t)r.origin.x; out[1] = (uint32_t)r.origin.y; out[2] = (uint32_t)r.origin.z;
  out[3] = (uint32_t)r.size.width; out[4] = (uint32_t)r.size.height; out[5] = (uint32_t)r.size.depth;
}

@implementation XEFMetalTexture
+ (id)wrapHostTexture:(uint32_t)tex resourceID:(uint64_t)rid width:(NSUInteger)w height:(NSUInteger)h pixelFormat:(MTLPixelFormat)pf {
  XEFMetalTexture *t = [[self alloc] init];
  t->_id = tex; t->_rid = rid; t->_type = MTLTextureType2D; t->_pixelFormat = pf;
  t->_width = w; t->_height = h; t->_depth = 1; t->_mips = 1; t->_arrayLength = 1; t->_samples = 1;
  t->_usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
  t->_storageMode = MTLStorageModePrivate;
  t->_swizzle = MTLTextureSwizzleChannelsMake(MTLTextureSwizzleRed, MTLTextureSwizzleGreen, MTLTextureSwizzleBlue, MTLTextureSwizzleAlpha);
  t->_owned = NO;
  t->_framebufferOnly = YES;
  return [t autorelease];
}
- (uint32_t)_xefTexture { return _id; }
- (id<MTLDevice>)device { return xef_shared_device(); }
- (MTLTextureType)textureType { return _type; }
- (MTLPixelFormat)pixelFormat { return _pixelFormat; }
- (NSUInteger)width { return _width; }
- (NSUInteger)height { return _height; }
- (NSUInteger)depth { return _depth; }
- (NSUInteger)mipmapLevelCount { return _mips; }
- (NSUInteger)arrayLength { return _arrayLength; }
- (NSUInteger)sampleCount { return _samples; }
- (MTLTextureUsage)usage { return _usage; }
- (MTLStorageMode)storageMode { return _storageMode; }
- (MTLCPUCacheMode)cpuCacheMode { return MTLCPUCacheModeDefaultCache; }
- (MTLHazardTrackingMode)hazardTrackingMode { return MTLHazardTrackingModeTracked; }
- (MTLResourceOptions)resourceOptions { return (MTLResourceOptions)_storageMode << MTLResourceStorageModeShift; }
- (BOOL)isFramebufferOnly { return _framebufferOnly; }
- (BOOL)framebufferOnly { return _framebufferOnly; }
- (BOOL)isShareable { return NO; }
- (BOOL)allowGPUOptimizedContents { return YES; }
- (MTLTextureCompressionType)compressionType { return MTLTextureCompressionTypeLossless; }
- (MTLTextureSwizzleChannels)swizzle { return _swizzle; }
- (MTLResourceID)gpuResourceID { MTLResourceID r; r._impl = _rid; return r; }
- (id<MTLResource>)rootResource { return _parent ? [(id)_parent rootResource] : self; }
- (id<MTLTexture>)parentTexture { return _parent; }
- (NSUInteger)parentRelativeLevel { return _parentLevel; }
- (NSUInteger)parentRelativeSlice { return _parentSlice; }
- (id<MTLBuffer>)buffer { return _buffer; }
- (NSUInteger)bufferOffset { return _bufferOffset; }
- (NSUInteger)bufferBytesPerRow { return _bufferBytesPerRow; }
- (IOSurfaceRef)iosurface { return NULL; }
- (NSUInteger)iosurfacePlane { return 0; }
- (NSUInteger)allocatedSize { return _width * _height * _depth * _arrayLength * 4; }
- (id<MTLHeap>)heap { return _heap; }
- (NSUInteger)heapOffset { return 0; }
- (void)makeAliasable {}
- (BOOL)isAliasable { return NO; }
- (MTLPurgeableState)setPurgeableState:(MTLPurgeableState)state { return MTLPurgeableStateNonVolatile; }
- (BOOL)isSparse { return NO; }
- (NSUInteger)firstMipmapInTail { return 0; }
- (NSUInteger)tailSizeInBytes { return 0; }
- (void)replaceRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level slice:(NSUInteger)slice withBytes:(const void *)bytes
          bytesPerRow:(NSUInteger)bytesPerRow bytesPerImage:(NSUInteger)bytesPerImage {
  uint32_t r[6];
  xef_region6(region, r);
  xef_mtl_texture_replace(_id, (uint32_t)level, (uint32_t)slice, r, bytes, bytesPerRow, bytesPerImage);
}
- (void)replaceRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level withBytes:(const void *)bytes bytesPerRow:(NSUInteger)bytesPerRow {
  [self replaceRegion:region mipmapLevel:level slice:0 withBytes:bytes bytesPerRow:bytesPerRow bytesPerImage:0];
}
- (void)getBytes:(void *)bytes bytesPerRow:(NSUInteger)bytesPerRow bytesPerImage:(NSUInteger)bytesPerImage fromRegion:(MTLRegion)region
     mipmapLevel:(NSUInteger)level slice:(NSUInteger)slice {
  uint32_t r[6];
  xef_region6(region, r);
  xef_mtl_texture_get_bytes(_id, (uint32_t)level, (uint32_t)slice, r, bytes, bytesPerRow, bytesPerImage);
}
- (void)getBytes:(void *)bytes bytesPerRow:(NSUInteger)bytesPerRow fromRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level {
  [self getBytes:bytes bytesPerRow:bytesPerRow bytesPerImage:0 fromRegion:region mipmapLevel:level slice:0];
}
- (id<MTLTexture>)newTextureViewWithPixelFormat:(MTLPixelFormat)pixelFormat textureType:(MTLTextureType)textureType
                                         levels:(NSRange)levelRange slices:(NSRange)sliceRange swizzle:(MTLTextureSwizzleChannels)swizzle {
  xef_mtl_view_desc d;
  memset(&d, 0, sizeof d);
  d.pixel_format = (uint32_t)pixelFormat;
  d.type = (uint32_t)textureType;
  d.level = (uint32_t)levelRange.location; d.levels = (uint32_t)levelRange.length;
  d.slice = (uint32_t)sliceRange.location; d.slices = (uint32_t)sliceRange.length;
  d.swizzle[0] = swizzle.red; d.swizzle[1] = swizzle.green; d.swizzle[2] = swizzle.blue; d.swizzle[3] = swizzle.alpha;
  uint64_t rid = 0;
  uint32_t id = xef_mtl_texture_view(_id, &d, &rid);
  if (!id) return nil;
  XEFMetalTexture *t = [[XEFMetalTexture alloc] init];
  t->_id = id; t->_rid = rid; t->_owned = YES;
  t->_type = textureType; t->_pixelFormat = pixelFormat;
  t->_width = MAX(1, _width >> levelRange.location); t->_height = MAX(1, _height >> levelRange.location);
  t->_depth = MAX(1, _depth >> levelRange.location);
  t->_mips = levelRange.length;
  bool cube = textureType == MTLTextureTypeCube || textureType == MTLTextureTypeCubeArray;
  t->_arrayLength = cube ? MAX(1, sliceRange.length / 6) : sliceRange.length;
  t->_samples = _samples; t->_usage = _usage; t->_storageMode = _storageMode;
  t->_swizzle = swizzle;
  t->_parent = [self retain];
  t->_parentLevel = levelRange.location; t->_parentSlice = sliceRange.location;
  return t;
}
- (id<MTLTexture>)newTextureViewWithPixelFormat:(MTLPixelFormat)pixelFormat textureType:(MTLTextureType)textureType
                                         levels:(NSRange)levelRange slices:(NSRange)sliceRange {
  return [self newTextureViewWithPixelFormat:pixelFormat textureType:textureType levels:levelRange slices:sliceRange
                                     swizzle:MTLTextureSwizzleChannelsMake(MTLTextureSwizzleRed, MTLTextureSwizzleGreen, MTLTextureSwizzleBlue, MTLTextureSwizzleAlpha)];
}
- (id<MTLTexture>)newTextureViewWithPixelFormat:(MTLPixelFormat)pixelFormat {
  bool cube = _type == MTLTextureTypeCube || _type == MTLTextureTypeCubeArray;
  return [self newTextureViewWithPixelFormat:pixelFormat textureType:_type levels:NSMakeRange(0, _mips)
                                      slices:NSMakeRange(0, cube ? _arrayLength * 6 : _arrayLength)];
}
- (MTLSharedTextureHandle *)newSharedTextureHandle {
  MTLSharedTextureHandle *h = [[MTLSharedTextureHandle alloc] init];
  objc_setAssociatedObject(h, "xef_texture", self, OBJC_ASSOCIATION_RETAIN);
  return h;
}
- (void)dealloc {
  if (_owned && _id) xef_mtl_texture_destroy(_id);
  [(id)_parent release];
  [(id)_buffer release];
  [super dealloc];
}
@end

@implementation XEFMetalBuffer (Textures)
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor offset:(NSUInteger)offset bytesPerRow:(NSUInteger)bytesPerRow {
  /* linear textures over a buffer: modelled as a texture buffer for 1D/buffer types, otherwise a copy */
  xef_mtl_texture_desc d;
  memset(&d, 0, sizeof d);
  d.type = MTLTextureTypeTextureBuffer;
  d.pixel_format = (uint32_t)descriptor.pixelFormat;
  d.width = (uint32_t)descriptor.width; d.height = 1; d.depth = 1;
  d.mip_levels = 1; d.array_length = 1; d.sample_count = 1;
  d.usage = (uint32_t)descriptor.usage;
  d.buffer = _id;
  d.buffer_offset = offset;
  d.bytes_per_row = (uint32_t)bytesPerRow;
  if (descriptor.textureType != MTLTextureTypeTextureBuffer && descriptor.textureType != MTLTextureType1D) {
    d.type = (uint32_t)descriptor.textureType;
    d.height = (uint32_t)descriptor.height;
    d.buffer = 0;
  }
  uint64_t rid = 0;
  uint32_t id = xef_mtl_texture_create(&d, &rid);
  if (!id) return nil;
  XEFMetalTexture *t = [[XEFMetalTexture alloc] init];
  t->_id = id; t->_rid = rid; t->_owned = YES;
  t->_type = descriptor.textureType; t->_pixelFormat = descriptor.pixelFormat;
  t->_width = descriptor.width; t->_height = descriptor.height; t->_depth = 1; t->_mips = 1; t->_arrayLength = 1; t->_samples = 1;
  t->_usage = descriptor.usage; t->_storageMode = descriptor.storageMode;
  t->_swizzle = descriptor.swizzle;
  t->_buffer = [self retain]; t->_bufferOffset = offset; t->_bufferBytesPerRow = bytesPerRow;
  if (d.type != MTLTextureTypeTextureBuffer && _contents) {
    MTLRegion r = MTLRegionMake2D(0, 0, descriptor.width, descriptor.height);
    [t replaceRegion:r mipmapLevel:0 withBytes:(uint8_t *)_contents + offset bytesPerRow:bytesPerRow];
  }
  return t;
}
@end

/* ------------------------------------------------------------------- samplers / depth stencil */

@interface XEFMetalSamplerState : XEFMetalObject <MTLSamplerState> {
@public
  uint32_t _id;
  uint64_t _rid;
}
@end
@implementation XEFMetalSamplerState
- (id<MTLDevice>)device { return xef_shared_device(); }
- (MTLResourceID)gpuResourceID { MTLResourceID r; r._impl = _rid; return r; }
- (void)dealloc { if (_id) xef_mtl_sampler_destroy(_id); [super dealloc]; }
@end

@interface XEFMetalDepthStencilState : XEFMetalObject <MTLDepthStencilState> {
@public
  xef_mtl_depth_stencil _ds;
}
@end
@implementation XEFMetalDepthStencilState
- (id<MTLDevice>)device { return xef_shared_device(); }
- (MTLResourceID)gpuResourceID { MTLResourceID r; r._impl = 0; return r; }
@end

/* ------------------------------------------------------------------- function constants */

@interface MTLFunctionConstantValues () {
@public
  NSMutableData *_blob;
}
@end

static NSUInteger xef_data_type_size(MTLDataType t) {
  switch (t) {
  case MTLDataTypeFloat: case MTLDataTypeInt: case MTLDataTypeUInt: return 4;
  case MTLDataTypeFloat2: case MTLDataTypeInt2: case MTLDataTypeUInt2: return 8;
  case MTLDataTypeFloat3: case MTLDataTypeInt3: case MTLDataTypeUInt3: return 12;
  case MTLDataTypeFloat4: case MTLDataTypeInt4: case MTLDataTypeUInt4: return 16;
  case MTLDataTypeHalf: case MTLDataTypeShort: case MTLDataTypeUShort: return 2;
  case MTLDataTypeHalf2: case MTLDataTypeShort2: case MTLDataTypeUShort2: return 4;
  case MTLDataTypeHalf3: case MTLDataTypeShort3: case MTLDataTypeUShort3: return 6;
  case MTLDataTypeHalf4: case MTLDataTypeShort4: case MTLDataTypeUShort4: return 8;
  case MTLDataTypeChar: case MTLDataTypeUChar: case MTLDataTypeBool: return 1;
  case MTLDataTypeChar2: case MTLDataTypeUChar2: case MTLDataTypeBool2: return 2;
  case MTLDataTypeChar3: case MTLDataTypeUChar3: case MTLDataTypeBool3: return 3;
  case MTLDataTypeChar4: case MTLDataTypeUChar4: case MTLDataTypeBool4: return 4;
  case MTLDataTypeLong: case MTLDataTypeULong: return 8;
  default: return 4;
  }
}

@implementation MTLFunctionConstantValues
- (void)_append:(const void *)value type:(MTLDataType)type index:(uint32_t)index name:(NSString *)name {
  if (!_blob) _blob = [[NSMutableData alloc] init];
  const char *n = name ? [name UTF8String] : "";
  uint32_t nl = (uint32_t)strlen(n);
  uint32_t vs = (uint32_t)xef_data_type_size(type);
  uint32_t h[4] = {index, (uint32_t)type, vs, nl};
  [_blob appendBytes:h length:16];
  static const uint8_t zero[4] = {0, 0, 0, 0};
  [_blob appendBytes:n length:nl];
  [_blob appendBytes:zero length:((nl + 3) & ~3u) - nl];
  [_blob appendBytes:value length:vs];
  [_blob appendBytes:zero length:((vs + 3) & ~3u) - vs];
}
- (void)setConstantValue:(const void *)value type:(MTLDataType)type atIndex:(NSUInteger)index {
  if (value) [self _append:value type:type index:(uint32_t)index name:nil];
}
- (void)setConstantValues:(const void *)values type:(MTLDataType)type withRange:(NSRange)range {
  NSUInteger sz = xef_data_type_size(type);
  for (NSUInteger i = 0; i < range.length; i++)
    [self _append:(const uint8_t *)values + i * sz type:type index:(uint32_t)(range.location + i) name:nil];
}
- (void)setConstantValue:(const void *)value type:(MTLDataType)type withName:(NSString *)name {
  if (value) [self _append:value type:type index:0xffffffffu name:name];
}
- (void)reset { [_blob setLength:0]; }
- (id)copyWithZone:(NSZone *)zone {
  MTLFunctionConstantValues *c = [[MTLFunctionConstantValues allocWithZone:zone] init];
  if (_blob) c->_blob = [_blob mutableCopy];
  return c;
}
- (void)dealloc { [_blob release]; [super dealloc]; }
@end

/* ------------------------------------------------------------------- libraries / functions */

@interface XEFMetalLibrary : XEFMetalObject <MTLLibrary> {
@public
  uint32_t _id;
  NSArray *_names;
  NSArray *_types;
}
@end

@interface XEFMetalFunction : XEFMetalObject <MTLFunction> {
@public
  XEFMetalLibrary *_library;
  NSString *_name;
  MTLFunctionType _type;
  NSData *_constants;
}
@end

@implementation XEFMetalFunction
- (id<MTLDevice>)device { return xef_shared_device(); }
- (NSString *)name { return _name; }
- (MTLFunctionType)functionType { return _type; }
- (MTLPatchType)patchType { return MTLPatchTypeNone; }
- (NSInteger)patchControlPointCount { return -1; }
- (NSArray *)vertexAttributes { return @[]; }
- (NSArray *)stageInputAttributes { return @[]; }
- (NSDictionary *)functionConstantsDictionary { return @{}; }
- (MTLFunctionOptions)options { return MTLFunctionOptionNone; }
- (NSString *)installName { return nil; }
- (void)dealloc { [_library release]; [_name release]; [_constants release]; [super dealloc]; }
- (void)_fill:(xef_mtl_function_ref *)r {
  r->library = _library ? _library->_id : 0;
  r->name = [_name UTF8String];
  r->constants = _constants ? [_constants bytes] : NULL;
  r->constants_size = _constants ? (uint32_t)[_constants length] : 0;
}
@end

@implementation XEFMetalLibrary
- (id<MTLDevice>)device { return xef_shared_device(); }
- (MTLLibraryType)type { return MTLLibraryTypeExecutable; }
- (NSString *)installName { return nil; }
- (NSArray<NSString *> *)functionNames { return _names; }
- (void)_loadNames {
  uint32_t n = xef_mtl_library_function_count(_id);
  NSMutableArray *names = [NSMutableArray arrayWithCapacity:n];
  NSMutableArray *types = [NSMutableArray arrayWithCapacity:n];
  for (uint32_t i = 0; i < n; i++) {
    char buf[1024];
    uint32_t t = xef_mtl_library_function_info(_id, i, buf, sizeof buf);
    [names addObject:[NSString stringWithUTF8String:buf]];
    [types addObject:@(t ? t - 1 : MTLFunctionTypeVisible)];
  }
  _names = [names retain];
  _types = [types retain];
}
- (id<MTLFunction>)newFunctionWithName:(NSString *)name constantValues:(MTLFunctionConstantValues *)values error:(NSError **)error {
  NSUInteger idx = [_names indexOfObject:name];
  if (idx == NSNotFound) {
    if (error) *error = [NSError errorWithDomain:@"MTLLibraryErrorDomain" code:5 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"function %@ not found", name]}];
    return nil;
  }
  XEFMetalFunction *f = [[XEFMetalFunction alloc] init];
  f->_library = [self retain];
  f->_name = [name copy];
  f->_type = (MTLFunctionType)[[_types objectAtIndex:idx] integerValue];
  if (values && values->_blob) f->_constants = [values->_blob copy];
  return f;
}
- (id<MTLFunction>)newFunctionWithName:(NSString *)name {
  return [self newFunctionWithName:name constantValues:nil error:NULL];
}
- (void)newFunctionWithName:(NSString *)name constantValues:(MTLFunctionConstantValues *)values
          completionHandler:(void (^)(id<MTLFunction> function, NSError *error))completionHandler {
  NSError *err = nil;
  id<MTLFunction> f = [self newFunctionWithName:name constantValues:values error:&err];
  completionHandler(f, err);
  [(id)f release];
}
- (id<MTLFunction>)newFunctionWithDescriptor:(MTLFunctionDescriptor *)descriptor error:(NSError **)error {
  return [self newFunctionWithName:descriptor.name constantValues:descriptor.constantValues error:error];
}
- (void)newFunctionWithDescriptor:(MTLFunctionDescriptor *)descriptor completionHandler:(void (^)(id<MTLFunction>, NSError *))completionHandler {
  NSError *err = nil;
  id<MTLFunction> f = [self newFunctionWithDescriptor:descriptor error:&err];
  completionHandler(f, err);
  [(id)f release];
}
- (id<MTLFunction>)newIntersectionFunctionWithDescriptor:(MTLIntersectionFunctionDescriptor *)descriptor error:(NSError **)error {
  return [self newFunctionWithDescriptor:descriptor error:error];
}
- (void)dealloc {
  if (_id) xef_mtl_library_destroy(_id);
  [_names release]; [_types release];
  [super dealloc];
}
@end

/* ------------------------------------------------------------------- pipeline states */

@interface XEFMetalRenderPipelineState : XEFMetalObject <MTLRenderPipelineState> {
@public
  uint32_t _id;
}
@end
@interface XEFMetalFunctionHandle : NSObject
- (instancetype)initWithName:(NSString *)name functionType:(MTLFunctionType)type device:(id<MTLDevice>)device;
@end
@interface XEFMetalVisibleFunctionTable : NSObject
- (instancetype)initWithDevice:(id<MTLDevice>)device descriptor:(MTLVisibleFunctionTableDescriptor *)descriptor;
- (id<MTLBuffer>)_xefBuffer;
@end
static id xef_fn_handle(id<MTLFunction> f) {
  return f ? [[[XEFMetalFunctionHandle alloc] initWithName:[f name] functionType:MTLFunctionTypeVisible device:[f device]] autorelease] : nil;
}

@implementation XEFMetalRenderPipelineState
- (id<MTLDevice>)device { return xef_shared_device(); }
- (NSUInteger)maxTotalThreadsPerThreadgroup { return 1024; }
- (BOOL)threadgroupSizeMatchesTileSize { return NO; }
- (NSUInteger)imageblockSampleLength { return 0; }
- (BOOL)supportIndirectCommandBuffers { return YES; }   /* CPU-encoded ICBs replay through the encoder */
- (MTLResourceID)gpuResourceID { MTLResourceID r; r._impl = _id; return r; }
- (NSUInteger)maxTotalThreadsPerObjectThreadgroup { return 0; }
- (NSUInteger)maxTotalThreadsPerMeshThreadgroup { return 0; }
- (NSUInteger)objectThreadExecutionWidth { return 32; }
- (NSUInteger)meshThreadExecutionWidth { return 32; }
- (NSUInteger)maxTotalThreadgroupsPerMeshGrid { return 0; }
- (NSUInteger)imageblockMemoryLengthForDimensions:(MTLSize)d { return 0; }
- (void)dealloc { if (_id) xef_mtl_pipeline_destroy(_id); [super dealloc]; }
- (id<MTLFunctionHandle>)functionHandleWithFunction:(id<MTLFunction>)f stage:(MTLRenderStages)st { return xef_fn_handle(f); }
- (id<MTLVisibleFunctionTable>)newVisibleFunctionTableWithDescriptor:(MTLVisibleFunctionTableDescriptor *)d stage:(MTLRenderStages)st {
  return (id<MTLVisibleFunctionTable>)[[XEFMetalVisibleFunctionTable alloc] initWithDevice:xef_shared_device() descriptor:d];
}
@end

@interface XEFMetalComputePipelineState : XEFMetalObject <MTLComputePipelineState> {
@public
  uint32_t _id;
  xef_mtl_pipeline_info _info;
}
@end
@implementation XEFMetalComputePipelineState
- (id<MTLDevice>)device { return xef_shared_device(); }
- (NSUInteger)maxTotalThreadsPerThreadgroup { return _info.max_total_threads; }
- (NSUInteger)threadExecutionWidth { return _info.execution_width; }
- (NSUInteger)staticThreadgroupMemoryLength { return _info.static_threadgroup_memory; }
- (NSUInteger)imageblockMemoryLengthForDimensions:(MTLSize)d { return 0; }
- (BOOL)supportIndirectCommandBuffers { return YES; }   /* CPU-encoded ICBs replay through the encoder */
- (MTLResourceID)gpuResourceID { MTLResourceID r; r._impl = _id; return r; }
- (void)dealloc { if (_id) xef_mtl_pipeline_destroy(_id); [super dealloc]; }
- (id<MTLFunctionHandle>)functionHandleWithFunction:(id<MTLFunction>)f { return xef_fn_handle(f); }
- (id<MTLVisibleFunctionTable>)newVisibleFunctionTableWithDescriptor:(MTLVisibleFunctionTableDescriptor *)d {
  return (id<MTLVisibleFunctionTable>)[[XEFMetalVisibleFunctionTable alloc] initWithDevice:xef_shared_device() descriptor:d];
}
- (id<MTLComputePipelineState>)newComputePipelineStateWithAdditionalBinaryFunctions:(NSArray *)fns error:(NSError **)error { return [self retain]; }
@end

/* ------------------------------------------------------------------- events / fences */

@interface XEFMetalFence : XEFMetalObject <MTLFence>
@end
@implementation XEFMetalFence
- (id<MTLDevice>)device { return xef_shared_device(); }
@end

/* implemented in MetalExtras.m */
@interface MTLSharedEventHandle (XEFInternal)
- (uint64_t)_signaledValue;
- (void)_setSignaledValue:(uint64_t)v;
- (void)_setLabel:(NSString *)l;
- (id)_event;
- (void)_setEvent:(id)e;
@end

/* objects implemented in MetalExtras.m */
@interface XEFMetalBinaryArchive : NSObject
- (instancetype)initWithDescriptor:(MTLBinaryArchiveDescriptor *)descriptor device:(id<MTLDevice>)device;
@end
@interface XEFMetalDynamicLibrary : NSObject
- (instancetype)initWithLibrary:(id<MTLLibrary>)library device:(id<MTLDevice>)device;
@end
@interface XEFMetalIndirectCommandBuffer : NSObject {
@public
  id<MTLDevice> _device;
  MTLIndirectCommandBufferDescriptor *_descriptor;
  NSUInteger _maxCommandCount;
  MTLResourceOptions _options;
  NSMutableArray *_renderCommands;
  NSMutableArray *_computeCommands;
}
- (instancetype)initWithDescriptor:(MTLIndirectCommandBufferDescriptor *)descriptor maxCommandCount:(NSUInteger)count options:(MTLResourceOptions)options device:(id<MTLDevice>)device;
@end
@interface XEFMetalLogState : NSObject
- (instancetype)initWithDescriptor:(MTLLogStateDescriptor *)desc;
@end
@protocol XEFIndirectReplay
- (void)executeOnEncoder:(id)encoder;
@end

@interface XEFMetalEvent : XEFMetalObject <MTLSharedEvent> {
@public
  uint32_t _id;
}
@end
@implementation XEFMetalEvent
- (id<MTLDevice>)device { return xef_shared_device(); }
- (uint64_t)signaledValue { return xef_mtl_event_value(_id); }
- (void)setSignaledValue:(uint64_t)v { xef_mtl_event_signal(_id, v); }
- (BOOL)waitUntilSignaledValue:(uint64_t)value timeoutMS:(uint64_t)ms { return xef_mtl_event_wait(_id, value, (int64_t)ms * 1000000) != 0; }
- (void)notifyListener:(MTLSharedEventListener *)listener atValue:(uint64_t)value block:(MTLSharedEventNotificationBlock)block {
  MTLSharedEventNotificationBlock b = Block_copy(block);
  dispatch_queue_t q = listener && [listener respondsToSelector:@selector(dispatchQueue)] ? [listener dispatchQueue] : dispatch_get_global_queue(0, 0);
  if (!q) q = dispatch_get_global_queue(0, 0);
  [self retain];
  dispatch_async(dispatch_get_global_queue(0, 0), ^{
    xef_mtl_event_wait(self->_id, value, -1);
    dispatch_async(q, ^{ b(self, value); Block_release(b); [self release]; });
  });
}
- (MTLSharedEventHandle *)newSharedEventHandle {
  MTLSharedEventHandle *h = [[MTLSharedEventHandle alloc] init];
  [h _setEvent:self];
  [h _setSignaledValue:[self signaledValue]];
  if ([self label]) [h _setLabel:[self label]];
  return h;
}
- (void)dealloc { if (_id) xef_mtl_event_destroy(_id); [super dealloc]; }
@end

/* ------------------------------------------------------------------- command stream */

typedef struct XEFStream {
  uint8_t *data;
  size_t len, cap;
} XEFStream;

static void *xef_stream_emit(XEFStream *s, uint32_t op, size_t payload) {
  size_t sz = (payload + 7) & ~(size_t)7;
  size_t need = s->len + sizeof(xef_mtl_cmd) + sz;
  if (need > s->cap) {
    size_t nc = s->cap ? s->cap * 2 : 4096;
    while (nc < need) nc *= 2;
    s->data = (uint8_t *)realloc(s->data, nc);
    s->cap = nc;
  }
  xef_mtl_cmd *h = (xef_mtl_cmd *)(s->data + s->len);
  h->op = op;
  h->size = (uint32_t)sz;
  void *p = h + 1;
  memset(p, 0, sz);
  s->len = need;
  return p;
}

@class XEFMetalCommandQueue;

@interface XEFMetalCommandBuffer : XEFMetalObject <MTLCommandBuffer> {
@public
  XEFMetalCommandQueue *_queue;
  XEFStream _stream;
  NSMutableArray *_retained;
  NSMutableArray *_scheduledHandlers, *_completedHandlers;
  MTLCommandBufferStatus _status;
  uint64_t _seq;
  BOOL _retainedReferences;
  id _activeEncoder;
  pthread_mutex_t _lock;
  pthread_cond_t _cond;
  CFTimeInterval _startTime, _endTime;
  NSMutableArray *_drawables;
}
- (void)_retain:(id)o;
@end

/* drawables (CAMetalDrawable lives in QuartzCore and exposes these) */
@interface NSObject (XEFDrawable)
- (uint32_t)_xefLayer;
- (uint32_t)_xefIndex;
- (void)_xefMarkPresented;
- (void)_xefRunPresentedHandlers;
@end

/* ------------------------------------------------------------------- encoders */

@interface XEFMetalEncoderBase : XEFMetalObject {
@public
  XEFMetalCommandBuffer *_cb;
  BOOL _ended;
  BOOL _sub;                 /* sub-encoder of a parallel render encoder: does not close the pass */
}
@end

@implementation XEFMetalEncoderBase
- (id<MTLDevice>)device { return xef_shared_device(); }
- (void)pushDebugGroup:(NSString *)string {}
- (void)popDebugGroup {}
- (void)insertDebugSignpost:(NSString *)string {}
- (void)endEncoding {
  if (_ended) return;
  _ended = YES;
  if (_sub) return;
  xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_END_ENCODER, 0);
  if (_cb->_activeEncoder == self) _cb->_activeEncoder = nil;
}
- (void)updateFence:(id<MTLFence>)fence {}
- (void)waitForFence:(id<MTLFence>)fence {}
- (void)updateFence:(id<MTLFence>)fence afterStages:(MTLRenderStages)stages {}
- (void)waitForFence:(id<MTLFence>)fence beforeStages:(MTLRenderStages)stages {}
- (void)useResource:(id<MTLResource>)resource usage:(MTLResourceUsage)usage {}
- (void)useResource:(id<MTLResource>)resource usage:(MTLResourceUsage)usage stages:(MTLRenderStages)stages {}
- (void)useResources:(const id<MTLResource> *)resources count:(NSUInteger)count usage:(MTLResourceUsage)usage {}
- (void)useResources:(const id<MTLResource> *)resources count:(NSUInteger)count usage:(MTLResourceUsage)usage stages:(MTLRenderStages)stages {}
- (void)useHeap:(id<MTLHeap>)heap {}
- (void)useHeap:(id<MTLHeap>)heap stages:(MTLRenderStages)stages {}
- (void)useHeaps:(const id<MTLHeap> *)heaps count:(NSUInteger)count {}
- (void)useHeaps:(const id<MTLHeap> *)heaps count:(NSUInteger)count stages:(MTLRenderStages)stages {}
- (void)barrierAfterQueueStages:(MTLStages)a beforeStages:(MTLStages)b {}
- (void)dealloc { [_cb release]; [super dealloc]; }
@end

static void xef_set_buffer(XEFMetalCommandBuffer *cb, uint32_t stage, id<MTLBuffer> buffer, NSUInteger offset, NSUInteger index) {
  xef_mtl_set_buffer *s = (xef_mtl_set_buffer *)xef_stream_emit(&cb->_stream, XEF_MTL_CMD_SET_BUFFER, sizeof *s);
  s->stage = stage; s->index = (uint32_t)index;
  s->buffer = buffer ? ((XEFMetalBuffer *)buffer)->_id : 0;
  s->offset = offset;
  if (buffer) [cb _retain:buffer];
}
static void xef_set_buffer_offset(XEFMetalCommandBuffer *cb, uint32_t stage, NSUInteger offset, NSUInteger index) {
  xef_mtl_set_buffer *s = (xef_mtl_set_buffer *)xef_stream_emit(&cb->_stream, XEF_MTL_CMD_SET_BUFFER_OFFSET, sizeof *s);
  s->stage = stage; s->index = (uint32_t)index; s->offset = offset;
}
static void xef_set_bytes(XEFMetalCommandBuffer *cb, uint32_t stage, const void *bytes, NSUInteger length, NSUInteger index) {
  xef_mtl_set_bytes *s = (xef_mtl_set_bytes *)xef_stream_emit(&cb->_stream, XEF_MTL_CMD_SET_BYTES, sizeof *s + length);
  s->stage = stage; s->index = (uint32_t)index; s->length = (uint32_t)length;
  if (bytes && length) memcpy(s + 1, bytes, length);
}
static void xef_set_texture(XEFMetalCommandBuffer *cb, uint32_t stage, id<MTLTexture> t, NSUInteger index) {
  xef_mtl_set_texture *s = (xef_mtl_set_texture *)xef_stream_emit(&cb->_stream, XEF_MTL_CMD_SET_TEXTURE, sizeof *s);
  s->stage = stage; s->index = (uint32_t)index;
  s->texture = t ? ((XEFMetalTexture *)t)->_id : 0;
  if (t) [cb _retain:t];
}
static void xef_set_sampler(XEFMetalCommandBuffer *cb, uint32_t stage, id<MTLSamplerState> smp, NSUInteger index) {
  xef_mtl_set_sampler *s = (xef_mtl_set_sampler *)xef_stream_emit(&cb->_stream, XEF_MTL_CMD_SET_SAMPLER, sizeof *s);
  s->stage = stage; s->index = (uint32_t)index;
  s->sampler = smp ? ((XEFMetalSamplerState *)smp)->_id : 0;
  if (smp) [cb _retain:smp];
}

#define XEF_STAGE_BINDINGS(prefix, STAGE) \
- (void)set##prefix##Buffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index { xef_set_buffer(_cb, STAGE, buffer, offset, index); } \
- (void)set##prefix##Buffers:(const id<MTLBuffer> *)buffers offsets:(const NSUInteger *)offsets withRange:(NSRange)range { \
  for (NSUInteger i = 0; i < range.length; i++) xef_set_buffer(_cb, STAGE, buffers[i], offsets ? offsets[i] : 0, range.location + i); } \
- (void)set##prefix##BufferOffset:(NSUInteger)offset atIndex:(NSUInteger)index { xef_set_buffer_offset(_cb, STAGE, offset, index); } \
- (void)set##prefix##Bytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index { xef_set_bytes(_cb, STAGE, bytes, length, index); } \
- (void)set##prefix##Texture:(id<MTLTexture>)texture atIndex:(NSUInteger)index { xef_set_texture(_cb, STAGE, texture, index); } \
- (void)set##prefix##Textures:(const id<MTLTexture> *)textures withRange:(NSRange)range { \
  for (NSUInteger i = 0; i < range.length; i++) xef_set_texture(_cb, STAGE, textures[i], range.location + i); } \
- (void)set##prefix##SamplerState:(id<MTLSamplerState>)sampler atIndex:(NSUInteger)index { xef_set_sampler(_cb, STAGE, sampler, index); } \
- (void)set##prefix##SamplerState:(id<MTLSamplerState>)sampler lodMinClamp:(float)lodMinClamp lodMaxClamp:(float)lodMaxClamp atIndex:(NSUInteger)index { \
  xef_set_sampler(_cb, STAGE, sampler, index); } \
- (void)set##prefix##SamplerStates:(const id<MTLSamplerState> *)samplers withRange:(NSRange)range { \
  for (NSUInteger i = 0; i < range.length; i++) xef_set_sampler(_cb, STAGE, samplers[i], range.location + i); } \
- (void)set##prefix##SamplerStates:(const id<MTLSamplerState> *)samplers lodMinClamps:(const float *)lodMinClamps lodMaxClamps:(const float *)lodMaxClamps withRange:(NSRange)range { \
  for (NSUInteger i = 0; i < range.length; i++) xef_set_sampler(_cb, STAGE, samplers[i], range.location + i); } \
- (void)set##prefix##Buffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset attributeStride:(NSUInteger)stride atIndex:(NSUInteger)index { \
  xef_set_buffer(_cb, STAGE, buffer, offset, index); } \
- (void)set##prefix##BufferOffset:(NSUInteger)offset attributeStride:(NSUInteger)stride atIndex:(NSUInteger)index { xef_set_buffer_offset(_cb, STAGE, offset, index); } \
- (void)set##prefix##Bytes:(const void *)bytes length:(NSUInteger)length attributeStride:(NSUInteger)stride atIndex:(NSUInteger)index { \
  xef_set_bytes(_cb, STAGE, bytes, length, index); }


/* ---- render ---- */

@interface XEFMetalRenderCommandEncoder : XEFMetalEncoderBase <MTLRenderCommandEncoder> {
@public
  xef_mtl_raster_state _rs;
  xef_mtl_stencil_ref _sref;
}
@end

@implementation XEFMetalRenderCommandEncoder
XEF_STAGE_BINDINGS(Vertex, XEF_MTL_STAGE_VERTEX)
XEF_STAGE_BINDINGS(Fragment, XEF_MTL_STAGE_FRAGMENT)
- (void)setRenderPipelineState:(id<MTLRenderPipelineState>)state {
  xef_mtl_set_pipeline *s = (xef_mtl_set_pipeline *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_SET_RENDER_PIPELINE, sizeof *s);
  s->pipeline = state ? ((XEFMetalRenderPipelineState *)state)->_id : 0;
  if (state) [_cb _retain:state];
}
- (void)setViewport:(MTLViewport)vp {
  xef_mtl_viewport *v = (xef_mtl_viewport *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_SET_VIEWPORT, sizeof *v);
  v->x = (float)vp.originX; v->y = (float)vp.originY; v->w = (float)vp.width; v->h = (float)vp.height;
  v->znear = (float)vp.znear; v->zfar = (float)vp.zfar;
}
- (void)setViewports:(const MTLViewport *)viewports count:(NSUInteger)count { if (count) [self setViewport:viewports[0]]; }
- (void)setScissorRect:(MTLScissorRect)r {
  xef_mtl_scissor *s = (xef_mtl_scissor *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_SET_SCISSOR, sizeof *s);
  s->x = (uint32_t)r.x; s->y = (uint32_t)r.y; s->w = (uint32_t)r.width; s->h = (uint32_t)r.height;
}
- (void)setScissorRects:(const MTLScissorRect *)rects count:(NSUInteger)count { if (count) [self setScissorRect:rects[0]]; }
- (void)_emitRaster {
  xef_mtl_raster_state *r = (xef_mtl_raster_state *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_SET_RASTER_STATE, sizeof *r);
  *r = _rs;
}
- (void)setCullMode:(MTLCullMode)m { _rs.cull_mode = (uint32_t)m; [self _emitRaster]; }
- (void)setFrontFacingWinding:(MTLWinding)w { _rs.winding = (uint32_t)w; [self _emitRaster]; }
- (void)setTriangleFillMode:(MTLTriangleFillMode)m { _rs.fill_mode = (uint32_t)m; [self _emitRaster]; }
- (void)setDepthClipMode:(MTLDepthClipMode)m { _rs.depth_clip = (uint32_t)m; [self _emitRaster]; }
- (void)setDepthBias:(float)bias slopeScale:(float)slope clamp:(float)clamp {
  _rs.depth_bias = bias; _rs.slope_scale = slope; _rs.clamp = clamp; [self _emitRaster];
}
- (void)setDepthTestMinBound:(float)a maxBound:(float)b {}
- (void)setDepthStencilState:(id<MTLDepthStencilState>)state {
  xef_mtl_depth_stencil *d = (xef_mtl_depth_stencil *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_SET_DEPTH_STENCIL, sizeof *d);
  if (state) *d = ((XEFMetalDepthStencilState *)state)->_ds;
  else {
    d->depth_compare = MTLCompareFunctionAlways;
    d->front.compare = d->back.compare = MTLCompareFunctionAlways;
    d->front.read_mask = d->back.read_mask = d->front.write_mask = d->back.write_mask = 0xff;
  }
}
- (void)setStencilReferenceValue:(uint32_t)v { [self setStencilFrontReferenceValue:v backReferenceValue:v]; }
- (void)setStencilFrontReferenceValue:(uint32_t)f backReferenceValue:(uint32_t)b {
  xef_mtl_stencil_ref *r = (xef_mtl_stencil_ref *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_SET_STENCIL_REF, sizeof *r);
  r->front = f; r->back = b;
}
- (void)setBlendColorRed:(float)r green:(float)g blue:(float)b alpha:(float)a {
  xef_mtl_blend_color *c = (xef_mtl_blend_color *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_SET_BLEND_COLOR, sizeof *c);
  c->r = r; c->g = g; c->b = b; c->a = a;
}
- (void)setVisibilityResultMode:(MTLVisibilityResultMode)mode offset:(NSUInteger)offset {}
- (void)setColorStoreAction:(MTLStoreAction)a atIndex:(NSUInteger)i {}
- (void)setDepthStoreAction:(MTLStoreAction)a {}
- (void)setStencilStoreAction:(MTLStoreAction)a {}
- (void)setColorStoreActionOptions:(MTLStoreActionOptions)o atIndex:(NSUInteger)i {}
- (void)setDepthStoreActionOptions:(MTLStoreActionOptions)o {}
- (void)setStencilStoreActionOptions:(MTLStoreActionOptions)o {}
- (void)setVertexAmplificationCount:(NSUInteger)count viewMappings:(const MTLVertexAmplificationViewMapping *)m {}
- (void)textureBarrier {
  xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_MEMORY_BARRIER, 0);
}
- (void)memoryBarrierWithScope:(MTLBarrierScope)scope afterStages:(MTLRenderStages)after beforeStages:(MTLRenderStages)before {}
- (void)memoryBarrierWithResources:(const id<MTLResource> *)resources count:(NSUInteger)count afterStages:(MTLRenderStages)after beforeStages:(MTLRenderStages)before {}
- (void)drawPrimitives:(MTLPrimitiveType)type vertexStart:(NSUInteger)start vertexCount:(NSUInteger)count
         instanceCount:(NSUInteger)instances baseInstance:(NSUInteger)baseInstance {
  xef_mtl_draw *d = (xef_mtl_draw *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_DRAW, sizeof *d);
  d->primitive = (uint32_t)type; d->vertex_start = (uint32_t)start; d->vertex_count = (uint32_t)count;
  d->instance_count = (uint32_t)instances; d->base_instance = (uint32_t)baseInstance;
}
- (void)drawPrimitives:(MTLPrimitiveType)type vertexStart:(NSUInteger)start vertexCount:(NSUInteger)count instanceCount:(NSUInteger)instances {
  [self drawPrimitives:type vertexStart:start vertexCount:count instanceCount:instances baseInstance:0];
}
- (void)drawPrimitives:(MTLPrimitiveType)type vertexStart:(NSUInteger)start vertexCount:(NSUInteger)count {
  [self drawPrimitives:type vertexStart:start vertexCount:count instanceCount:1 baseInstance:0];
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)type indexCount:(NSUInteger)indexCount indexType:(MTLIndexType)indexType
                  indexBuffer:(id<MTLBuffer>)indexBuffer indexBufferOffset:(NSUInteger)offset instanceCount:(NSUInteger)instances
                   baseVertex:(NSInteger)baseVertex baseInstance:(NSUInteger)baseInstance {
  xef_mtl_draw_indexed *d = (xef_mtl_draw_indexed *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_DRAW_INDEXED, sizeof *d);
  d->primitive = (uint32_t)type; d->index_count = (uint32_t)indexCount; d->index_type = (uint32_t)indexType;
  d->index_buffer = indexBuffer ? ((XEFMetalBuffer *)indexBuffer)->_id : 0;
  d->index_offset = offset; d->instance_count = (uint32_t)instances; d->base_vertex = (int32_t)baseVertex;
  d->base_instance = (uint32_t)baseInstance;
  if (indexBuffer) [_cb _retain:indexBuffer];
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)type indexCount:(NSUInteger)indexCount indexType:(MTLIndexType)indexType
                  indexBuffer:(id<MTLBuffer>)indexBuffer indexBufferOffset:(NSUInteger)offset instanceCount:(NSUInteger)instances {
  [self drawIndexedPrimitives:type indexCount:indexCount indexType:indexType indexBuffer:indexBuffer indexBufferOffset:offset
                instanceCount:instances baseVertex:0 baseInstance:0];
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)type indexCount:(NSUInteger)indexCount indexType:(MTLIndexType)indexType
                  indexBuffer:(id<MTLBuffer>)indexBuffer indexBufferOffset:(NSUInteger)offset {
  [self drawIndexedPrimitives:type indexCount:indexCount indexType:indexType indexBuffer:indexBuffer indexBufferOffset:offset
                instanceCount:1 baseVertex:0 baseInstance:0];
}
- (void)drawPrimitives:(MTLPrimitiveType)type indirectBuffer:(id<MTLBuffer>)buffer indirectBufferOffset:(NSUInteger)offset {
  xef_mtl_draw_indirect *d = (xef_mtl_draw_indirect *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_DRAW_INDIRECT, sizeof *d);
  d->primitive = (uint32_t)type; d->buffer = ((XEFMetalBuffer *)buffer)->_id; d->offset = offset;
  [_cb _retain:buffer];
}
- (void)drawIndexedPrimitives:(MTLPrimitiveType)type indexType:(MTLIndexType)indexType indexBuffer:(id<MTLBuffer>)indexBuffer
            indexBufferOffset:(NSUInteger)ioff indirectBuffer:(id<MTLBuffer>)buffer indirectBufferOffset:(NSUInteger)offset {
  xef_mtl_draw_indirect *d = (xef_mtl_draw_indirect *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_DRAW_INDEXED_INDIRECT, sizeof *d);
  d->primitive = (uint32_t)type; d->buffer = ((XEFMetalBuffer *)buffer)->_id; d->offset = offset;
  d->index_type = (uint32_t)indexType; d->index_buffer = ((XEFMetalBuffer *)indexBuffer)->_id; d->index_offset = ioff;
  [_cb _retain:buffer];
  [_cb _retain:indexBuffer];
}
/* tile shading / mesh shading (Apple GPUs only) */
- (NSUInteger)tileWidth { return 32; }
- (NSUInteger)tileHeight { return 32; }
- (void)setTileBytes:(const void *)b length:(NSUInteger)l atIndex:(NSUInteger)i {}
- (void)setTileBuffer:(id<MTLBuffer>)b offset:(NSUInteger)o atIndex:(NSUInteger)i {}
- (void)setTileTexture:(id<MTLTexture>)t atIndex:(NSUInteger)i {}
- (void)setTileSamplerState:(id<MTLSamplerState>)s atIndex:(NSUInteger)i {}
- (void)setThreadgroupMemoryLength:(NSUInteger)l offset:(NSUInteger)o atIndex:(NSUInteger)i {}
- (void)dispatchThreadsPerTile:(MTLSize)s {}
- (void)executeCommandsInBuffer:(id<MTLIndirectCommandBuffer>)icb withRange:(NSRange)range {
  XEFMetalIndirectCommandBuffer *b = (XEFMetalIndirectCommandBuffer *)icb;
  NSArray *cmds = b ? b->_renderCommands : nil;
  for (NSUInteger i = range.location; i < NSMaxRange(range) && i < cmds.count; i++) {
    id c = cmds[i];
    if (c != [NSNull null]) [(id<XEFIndirectReplay>)c executeOnEncoder:self];
  }
}
- (void)executeCommandsInBuffer:(id<MTLIndirectCommandBuffer>)icb indirectBuffer:(id<MTLBuffer>)rb indirectBufferOffset:(NSUInteger)off {
  const uint32_t *r = (const uint32_t *)((const uint8_t *)[rb contents] + off);   /* MTLIndirectCommandBufferExecutionRange */
  [self executeCommandsInBuffer:icb withRange:NSMakeRange(r[0], r[1])];
}
- (void)setVertexVisibleFunctionTable:(id<MTLVisibleFunctionTable>)t atBufferIndex:(NSUInteger)i {
  [self setVertexBuffer:[(XEFMetalVisibleFunctionTable *)t _xefBuffer] offset:0 atIndex:i];
}
- (void)setFragmentVisibleFunctionTable:(id<MTLVisibleFunctionTable>)t atBufferIndex:(NSUInteger)i {
  [self setFragmentBuffer:[(XEFMetalVisibleFunctionTable *)t _xefBuffer] offset:0 atIndex:i];
}
@end

/* ---- compute ---- */

@interface XEFMetalComputeCommandEncoder : XEFMetalEncoderBase <MTLComputeCommandEncoder> {
@public
  MTLDispatchType _dispatchType;
}
@end

@implementation XEFMetalComputeCommandEncoder
XEF_STAGE_BINDINGS(, XEF_MTL_STAGE_KERNEL)
- (MTLDispatchType)dispatchType { return _dispatchType; }
- (void)setComputePipelineState:(id<MTLComputePipelineState>)state {
  xef_mtl_set_pipeline *s = (xef_mtl_set_pipeline *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_SET_COMPUTE_PIPELINE, sizeof *s);
  s->pipeline = state ? ((XEFMetalComputePipelineState *)state)->_id : 0;
  if (state) [_cb _retain:state];
}
- (void)setThreadgroupMemoryLength:(NSUInteger)length atIndex:(NSUInteger)index {
  xef_mtl_tg_memory *m = (xef_mtl_tg_memory *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_SET_THREADGROUP_MEMORY, sizeof *m);
  m->index = (uint32_t)index; m->length = (uint32_t)length;
}
- (void)setImageblockWidth:(NSUInteger)w height:(NSUInteger)h {}
- (void)setStageInRegion:(MTLRegion)region {}
- (void)setStageInRegionWithIndirectBuffer:(id<MTLBuffer>)b indirectBufferOffset:(NSUInteger)o {}
- (void)_dispatch:(MTLSize)grid threads:(MTLSize)tg byThreads:(BOOL)byThreads {
  xef_mtl_dispatch *d = (xef_mtl_dispatch *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_DISPATCH, sizeof *d);
  d->groups[0] = (uint32_t)grid.width; d->groups[1] = (uint32_t)grid.height; d->groups[2] = (uint32_t)grid.depth;
  d->threads[0] = (uint32_t)tg.width; d->threads[1] = (uint32_t)tg.height; d->threads[2] = (uint32_t)tg.depth;
  d->by_threads = byThreads ? 1 : 0;
}
- (void)dispatchThreadgroups:(MTLSize)groups threadsPerThreadgroup:(MTLSize)tg { [self _dispatch:groups threads:tg byThreads:NO]; }
- (void)dispatchThreads:(MTLSize)threads threadsPerThreadgroup:(MTLSize)tg { [self _dispatch:threads threads:tg byThreads:YES]; }
- (void)dispatchThreadgroupsWithIndirectBuffer:(id<MTLBuffer>)buffer indirectBufferOffset:(NSUInteger)offset threadsPerThreadgroup:(MTLSize)tg {
  xef_mtl_dispatch_indirect *d = (xef_mtl_dispatch_indirect *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_DISPATCH_INDIRECT, sizeof *d);
  d->buffer = ((XEFMetalBuffer *)buffer)->_id; d->offset = offset;
  d->threads[0] = (uint32_t)tg.width; d->threads[1] = (uint32_t)tg.height; d->threads[2] = (uint32_t)tg.depth;
  [_cb _retain:buffer];
}
- (void)memoryBarrierWithScope:(MTLBarrierScope)scope { xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_MEMORY_BARRIER, 0); }
- (void)memoryBarrierWithResources:(const id<MTLResource> *)resources count:(NSUInteger)count {
  xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_MEMORY_BARRIER, 0);
}
- (void)useResource:(id<MTLResource>)resource usage:(MTLResourceUsage)usage {}
- (void)executeCommandsInBuffer:(id<MTLIndirectCommandBuffer>)icb withRange:(NSRange)range {
  XEFMetalIndirectCommandBuffer *b = (XEFMetalIndirectCommandBuffer *)icb;
  NSArray *cmds = b ? b->_computeCommands : nil;
  for (NSUInteger i = range.location; i < NSMaxRange(range) && i < cmds.count; i++) {
    id c = cmds[i];
    if (c != [NSNull null]) [(id<XEFIndirectReplay>)c executeOnEncoder:self];
  }
}
- (void)executeCommandsInBuffer:(id<MTLIndirectCommandBuffer>)icb indirectBuffer:(id<MTLBuffer>)rb indirectBufferOffset:(NSUInteger)off {
  const uint32_t *r = (const uint32_t *)((const uint8_t *)[rb contents] + off);
  [self executeCommandsInBuffer:icb withRange:NSMakeRange(r[0], r[1])];
}
- (void)setVisibleFunctionTable:(id<MTLVisibleFunctionTable>)t atBufferIndex:(NSUInteger)i {
  [self setBuffer:[(XEFMetalVisibleFunctionTable *)t _xefBuffer] offset:0 atIndex:i];
}
- (void)setVisibleFunctionTables:(const id<MTLVisibleFunctionTable> *)t withBufferRange:(NSRange)r {
  for (NSUInteger k = 0; k < r.length; k++) [self setVisibleFunctionTable:t[k] atBufferIndex:r.location + k];
}
@end

/* ---- blit ---- */

@interface XEFMetalBlitCommandEncoder : XEFMetalEncoderBase <MTLBlitCommandEncoder>
@end

@implementation XEFMetalBlitCommandEncoder
- (void)copyFromBuffer:(id<MTLBuffer>)src sourceOffset:(NSUInteger)so toBuffer:(id<MTLBuffer>)dst destinationOffset:(NSUInteger)doff size:(NSUInteger)size {
  xef_mtl_copy_buffer *c = (xef_mtl_copy_buffer *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_COPY_BUFFER, sizeof *c);
  c->src = ((XEFMetalBuffer *)src)->_id; c->dst = ((XEFMetalBuffer *)dst)->_id;
  c->src_offset = so; c->dst_offset = doff; c->size = size;
  [_cb _retain:src]; [_cb _retain:dst];
}
- (void)copyFromBuffer:(id<MTLBuffer>)src sourceOffset:(NSUInteger)so sourceBytesPerRow:(NSUInteger)bpr sourceBytesPerImage:(NSUInteger)bpi
            sourceSize:(MTLSize)size toTexture:(id<MTLTexture>)dst destinationSlice:(NSUInteger)slice destinationLevel:(NSUInteger)level
     destinationOrigin:(MTLOrigin)origin options:(MTLBlitOption)options {
  xef_mtl_copy_buf_tex *c = (xef_mtl_copy_buf_tex *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_COPY_BUFFER_TO_TEXTURE, sizeof *c);
  c->buffer = ((XEFMetalBuffer *)src)->_id; c->texture = ((XEFMetalTexture *)dst)->_id;
  c->buffer_offset = so; c->bytes_per_row = (uint32_t)bpr; c->bytes_per_image = (uint32_t)bpi;
  c->level = (uint32_t)level; c->slice = (uint32_t)slice;
  c->x = (uint32_t)origin.x; c->y = (uint32_t)origin.y; c->z = (uint32_t)origin.z;
  c->w = (uint32_t)size.width; c->h = (uint32_t)size.height; c->d = (uint32_t)size.depth; c->options = (uint32_t)options;
  [_cb _retain:src]; [_cb _retain:dst];
}
- (void)copyFromBuffer:(id<MTLBuffer>)src sourceOffset:(NSUInteger)so sourceBytesPerRow:(NSUInteger)bpr sourceBytesPerImage:(NSUInteger)bpi
            sourceSize:(MTLSize)size toTexture:(id<MTLTexture>)dst destinationSlice:(NSUInteger)slice destinationLevel:(NSUInteger)level
     destinationOrigin:(MTLOrigin)origin {
  [self copyFromBuffer:src sourceOffset:so sourceBytesPerRow:bpr sourceBytesPerImage:bpi sourceSize:size toTexture:dst
      destinationSlice:slice destinationLevel:level destinationOrigin:origin options:MTLBlitOptionNone];
}
- (void)copyFromTexture:(id<MTLTexture>)src sourceSlice:(NSUInteger)slice sourceLevel:(NSUInteger)level sourceOrigin:(MTLOrigin)origin
             sourceSize:(MTLSize)size toBuffer:(id<MTLBuffer>)dst destinationOffset:(NSUInteger)doff destinationBytesPerRow:(NSUInteger)bpr
destinationBytesPerImage:(NSUInteger)bpi options:(MTLBlitOption)options {
  xef_mtl_copy_buf_tex *c = (xef_mtl_copy_buf_tex *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_COPY_TEXTURE_TO_BUFFER, sizeof *c);
  c->buffer = ((XEFMetalBuffer *)dst)->_id; c->texture = ((XEFMetalTexture *)src)->_id;
  c->buffer_offset = doff; c->bytes_per_row = (uint32_t)bpr; c->bytes_per_image = (uint32_t)bpi;
  c->level = (uint32_t)level; c->slice = (uint32_t)slice;
  c->x = (uint32_t)origin.x; c->y = (uint32_t)origin.y; c->z = (uint32_t)origin.z;
  c->w = (uint32_t)size.width; c->h = (uint32_t)size.height; c->d = (uint32_t)size.depth; c->options = (uint32_t)options;
  [_cb _retain:src]; [_cb _retain:dst];
}
- (void)copyFromTexture:(id<MTLTexture>)src sourceSlice:(NSUInteger)slice sourceLevel:(NSUInteger)level sourceOrigin:(MTLOrigin)origin
             sourceSize:(MTLSize)size toBuffer:(id<MTLBuffer>)dst destinationOffset:(NSUInteger)doff destinationBytesPerRow:(NSUInteger)bpr
destinationBytesPerImage:(NSUInteger)bpi {
  [self copyFromTexture:src sourceSlice:slice sourceLevel:level sourceOrigin:origin sourceSize:size toBuffer:dst destinationOffset:doff
 destinationBytesPerRow:bpr destinationBytesPerImage:bpi options:MTLBlitOptionNone];
}
- (void)copyFromTexture:(id<MTLTexture>)src sourceSlice:(NSUInteger)ss sourceLevel:(NSUInteger)sl sourceOrigin:(MTLOrigin)so sourceSize:(MTLSize)size
              toTexture:(id<MTLTexture>)dst destinationSlice:(NSUInteger)ds destinationLevel:(NSUInteger)dl destinationOrigin:(MTLOrigin)dorg {
  xef_mtl_copy_texture *c = (xef_mtl_copy_texture *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_COPY_TEXTURE, sizeof *c);
  c->src = ((XEFMetalTexture *)src)->_id; c->dst = ((XEFMetalTexture *)dst)->_id;
  c->src_level = (uint32_t)sl; c->src_slice = (uint32_t)ss; c->dst_level = (uint32_t)dl; c->dst_slice = (uint32_t)ds;
  c->sx = (uint32_t)so.x; c->sy = (uint32_t)so.y; c->sz = (uint32_t)so.z;
  c->dx = (uint32_t)dorg.x; c->dy = (uint32_t)dorg.y; c->dz = (uint32_t)dorg.z;
  c->w = (uint32_t)size.width; c->h = (uint32_t)size.height; c->d = (uint32_t)size.depth;
  c->slice_count = 1; c->level_count = 1;
  [_cb _retain:src]; [_cb _retain:dst];
}
- (void)copyFromTexture:(id<MTLTexture>)src sourceSlice:(NSUInteger)ss sourceLevel:(NSUInteger)sl toTexture:(id<MTLTexture>)dst
       destinationSlice:(NSUInteger)ds destinationLevel:(NSUInteger)dl sliceCount:(NSUInteger)sc levelCount:(NSUInteger)lc {
  xef_mtl_copy_texture *c = (xef_mtl_copy_texture *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_COPY_TEXTURE, sizeof *c);
  c->src = ((XEFMetalTexture *)src)->_id; c->dst = ((XEFMetalTexture *)dst)->_id;
  c->src_level = (uint32_t)sl; c->src_slice = (uint32_t)ss; c->dst_level = (uint32_t)dl; c->dst_slice = (uint32_t)ds;
  c->slice_count = (uint32_t)sc; c->level_count = (uint32_t)lc;
  [_cb _retain:src]; [_cb _retain:dst];
}
- (void)copyFromTexture:(id<MTLTexture>)src toTexture:(id<MTLTexture>)dst {
  xef_mtl_copy_texture *c = (xef_mtl_copy_texture *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_COPY_TEXTURE, sizeof *c);
  c->src = ((XEFMetalTexture *)src)->_id; c->dst = ((XEFMetalTexture *)dst)->_id;
  c->whole = 1;
  [_cb _retain:src]; [_cb _retain:dst];
}
- (void)fillBuffer:(id<MTLBuffer>)buffer range:(NSRange)range value:(uint8_t)value {
  xef_mtl_fill_buffer *f = (xef_mtl_fill_buffer *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_FILL_BUFFER, sizeof *f);
  f->buffer = ((XEFMetalBuffer *)buffer)->_id; f->value = value; f->offset = range.location; f->length = range.length;
  [_cb _retain:buffer];
}
- (void)generateMipmapsForTexture:(id<MTLTexture>)texture {
  xef_mtl_texture_ref *t = (xef_mtl_texture_ref *)xef_stream_emit(&_cb->_stream, XEF_MTL_CMD_GENERATE_MIPMAPS, sizeof *t);
  t->texture = ((XEFMetalTexture *)texture)->_id;
  [_cb _retain:texture];
}
- (void)synchronizeResource:(id<MTLResource>)resource {}
- (void)synchronizeTexture:(id<MTLTexture>)texture slice:(NSUInteger)slice level:(NSUInteger)level {}
- (void)optimizeContentsForGPUAccess:(id<MTLTexture>)texture {}
- (void)optimizeContentsForGPUAccess:(id<MTLTexture>)texture slice:(NSUInteger)slice level:(NSUInteger)level {}
- (void)optimizeContentsForCPUAccess:(id<MTLTexture>)texture {}
- (void)optimizeContentsForCPUAccess:(id<MTLTexture>)texture slice:(NSUInteger)slice level:(NSUInteger)level {}
- (void)resetCommandsInBuffer:(id<MTLIndirectCommandBuffer>)b withRange:(NSRange)r {}
- (void)optimizeIndirectCommandBuffer:(id<MTLIndirectCommandBuffer>)b withRange:(NSRange)r {}
- (void)sampleCountersInBuffer:(id<MTLCounterSampleBuffer>)b atSampleIndex:(NSUInteger)i withBarrier:(BOOL)barrier {}
- (void)resolveCounters:(id<MTLCounterSampleBuffer>)b inRange:(NSRange)r destinationBuffer:(id<MTLBuffer>)d destinationOffset:(NSUInteger)o {}
@end

/* ---- parallel render encoder: sub-encoders share the pass ---- */

@interface XEFMetalParallelRenderCommandEncoder : XEFMetalEncoderBase <MTLParallelRenderCommandEncoder> {
@public
  NSMutableArray *_subs;
}
@end

@implementation XEFMetalParallelRenderCommandEncoder
- (id<MTLRenderCommandEncoder>)renderCommandEncoder {
  XEFMetalRenderCommandEncoder *e = [[[XEFMetalRenderCommandEncoder alloc] init] autorelease];
  e->_cb = [_cb retain];
  e->_sub = YES;
  if (!_subs) _subs = [[NSMutableArray alloc] init];
  [_subs addObject:e];
  return e;
}
- (void)endEncoding {
  /* the sub-encoders' records are already in the stream between BEGIN_RENDER and this END; their own endEncoding
     calls must not close the pass */
  [super endEncoding];
}
- (void)setColorStoreAction:(MTLStoreAction)a atIndex:(NSUInteger)i {}
- (void)setDepthStoreAction:(MTLStoreAction)a {}
- (void)setStencilStoreAction:(MTLStoreAction)a {}
- (void)dealloc { [_subs release]; [super dealloc]; }
@end

/* ------------------------------------------------------------------- command buffers / queues */

@interface XEFMetalCommandQueue : XEFMetalObject <MTLCommandQueue> {
@public
  uint32_t _id;
  pthread_mutex_t _lock;
  pthread_cond_t _cond;
  NSMutableArray *_pending;     /* committed command buffers awaiting completion */
  BOOL _threadStarted;
}
- (void)_enqueueCompletion:(XEFMetalCommandBuffer *)cb;
@end

static void xef_pass_attachment_color(MTLRenderPassColorAttachmentDescriptor *a, xef_mtl_rp_color *c, XEFMetalCommandBuffer *cb) {
  id<MTLTexture> t = a.texture;
  if (!t) return;
  c->texture = ((XEFMetalTexture *)t)->_id;
  c->level = (uint32_t)a.level; c->slice = (uint32_t)a.slice; c->depth_plane = (uint32_t)a.depthPlane;
  c->load_action = (uint32_t)a.loadAction; c->store_action = (uint32_t)a.storeAction;
  MTLClearColor cc = a.clearColor;
  c->clear[0] = (float)cc.red; c->clear[1] = (float)cc.green; c->clear[2] = (float)cc.blue; c->clear[3] = (float)cc.alpha;
  id<MTLTexture> r = a.resolveTexture;
  if (r) {
    c->resolve_texture = ((XEFMetalTexture *)r)->_id;
    c->resolve_level = (uint32_t)a.resolveLevel; c->resolve_slice = (uint32_t)a.resolveSlice; c->resolve_depth_plane = (uint32_t)a.resolveDepthPlane;
    [cb _retain:r];
  }
  [cb _retain:t];
}

static void xef_pass_attachment_ds(MTLRenderPassAttachmentDescriptor *a, xef_mtl_rp_depth *d, XEFMetalCommandBuffer *cb, BOOL depth) {
  id<MTLTexture> t = a.texture;
  if (!t) return;
  d->texture = ((XEFMetalTexture *)t)->_id;
  d->level = (uint32_t)a.level; d->slice = (uint32_t)a.slice; d->depth_plane = (uint32_t)a.depthPlane;
  d->load_action = (uint32_t)a.loadAction; d->store_action = (uint32_t)a.storeAction;
  id<MTLTexture> r = a.resolveTexture;
  if (r) {
    d->resolve_texture = ((XEFMetalTexture *)r)->_id;
    d->resolve_level = (uint32_t)a.resolveLevel; d->resolve_slice = (uint32_t)a.resolveSlice;
    [cb _retain:r];
  }
  if (depth) d->clear_depth = (float)((MTLRenderPassDepthAttachmentDescriptor *)a).clearDepth;
  else d->clear_stencil = ((MTLRenderPassStencilAttachmentDescriptor *)a).clearStencil;
  [cb _retain:t];
}

@implementation XEFMetalCommandBuffer
- (id)init {
  if ((self = [super init])) {
    _retained = [[NSMutableArray alloc] init];
    _scheduledHandlers = [[NSMutableArray alloc] init];
    _completedHandlers = [[NSMutableArray alloc] init];
    _drawables = [[NSMutableArray alloc] init];
    _retainedReferences = YES;
    _status = MTLCommandBufferStatusNotEnqueued;
    pthread_mutex_init(&_lock, NULL);
    pthread_cond_init(&_cond, NULL);
  }
  return self;
}
- (void)_retain:(id)o { if (o) [_retained addObject:o]; }
- (id<MTLDevice>)device { return xef_shared_device(); }
- (id<MTLCommandQueue>)commandQueue { return (id<MTLCommandQueue>)_queue; }
- (BOOL)retainedReferences { return _retainedReferences; }
- (MTLCommandBufferErrorOption)errorOptions { return MTLCommandBufferErrorOptionNone; }
- (MTLCommandBufferStatus)status { return _status; }
- (NSError *)error { return nil; }
- (id<MTLLogContainer>)logs { return nil; }
- (CFTimeInterval)kernelStartTime { return _startTime; }
- (CFTimeInterval)kernelEndTime { return _endTime; }
- (CFTimeInterval)GPUStartTime { return _startTime; }
- (CFTimeInterval)GPUEndTime { return _endTime; }
- (void)_endActive {
  if (_activeEncoder) { [(XEFMetalEncoderBase *)_activeEncoder endEncoding]; _activeEncoder = nil; }
}
- (id<MTLRenderCommandEncoder>)renderCommandEncoderWithDescriptor:(MTLRenderPassDescriptor *)desc {
  [self _endActive];
  xef_mtl_begin_render *b = (xef_mtl_begin_render *)xef_stream_emit(&_stream, XEF_MTL_CMD_BEGIN_RENDER, sizeof *b);
  for (int i = 0; i < XEF_MTL_MAX_COLOR; i++) xef_pass_attachment_color(desc.colorAttachments[i], &b->colors[i], self);
  xef_pass_attachment_ds(desc.depthAttachment, &b->depth, self, YES);
  xef_pass_attachment_ds(desc.stencilAttachment, &b->stencil, self, NO);
  b->width = (uint32_t)desc.renderTargetWidth; b->height = (uint32_t)desc.renderTargetHeight;
  b->layers = (uint32_t)desc.renderTargetArrayLength;
  b->default_samples = (uint32_t)desc.defaultRasterSampleCount;
  XEFMetalRenderCommandEncoder *e = [[[XEFMetalRenderCommandEncoder alloc] init] autorelease];
  e->_cb = [self retain];
  _activeEncoder = e;
  return e;
}
- (id<MTLParallelRenderCommandEncoder>)parallelRenderCommandEncoderWithDescriptor:(MTLRenderPassDescriptor *)desc {
  id<MTLRenderCommandEncoder> inner = [self renderCommandEncoderWithDescriptor:desc];
  ((XEFMetalEncoderBase *)inner)->_ended = YES;   /* the parallel encoder ends the pass */
  XEFMetalParallelRenderCommandEncoder *p = [[[XEFMetalParallelRenderCommandEncoder alloc] init] autorelease];
  p->_cb = [self retain];
  _activeEncoder = p;
  return p;
}
- (id<MTLComputeCommandEncoder>)computeCommandEncoderWithDispatchType:(MTLDispatchType)type {
  [self _endActive];
  xef_stream_emit(&_stream, XEF_MTL_CMD_BEGIN_COMPUTE, 0);
  XEFMetalComputeCommandEncoder *e = [[[XEFMetalComputeCommandEncoder alloc] init] autorelease];
  e->_cb = [self retain];
  e->_dispatchType = type;
  _activeEncoder = e;
  return e;
}
- (id<MTLComputeCommandEncoder>)computeCommandEncoder { return [self computeCommandEncoderWithDispatchType:MTLDispatchTypeSerial]; }
- (id<MTLComputeCommandEncoder>)computeCommandEncoderWithDescriptor:(MTLComputePassDescriptor *)d {
  return [self computeCommandEncoderWithDispatchType:d.dispatchType];
}
- (id<MTLBlitCommandEncoder>)blitCommandEncoder {
  [self _endActive];
  xef_stream_emit(&_stream, XEF_MTL_CMD_BEGIN_BLIT, 0);
  XEFMetalBlitCommandEncoder *e = [[[XEFMetalBlitCommandEncoder alloc] init] autorelease];
  e->_cb = [self retain];
  _activeEncoder = e;
  return e;
}
- (id<MTLBlitCommandEncoder>)blitCommandEncoderWithDescriptor:(MTLBlitPassDescriptor *)d { return [self blitCommandEncoder]; }
- (id<MTLResourceStateCommandEncoder>)resourceStateCommandEncoder { return nil; }
- (id<MTLAccelerationStructureCommandEncoder>)accelerationStructureCommandEncoder { return nil; }
- (void)presentDrawable:(id<MTLDrawable>)drawable {
  if (!drawable) return;
  id d = (id)drawable;
  if (![d respondsToSelector:@selector(_xefLayer)]) return;
  [self _endActive];
  xef_mtl_present *p = (xef_mtl_present *)xef_stream_emit(&_stream, XEF_MTL_CMD_PRESENT, sizeof *p);
  p->layer = [d _xefLayer];
  p->drawable = [d _xefIndex];
  [d _xefMarkPresented];
  [_drawables addObject:d];
}
- (void)presentDrawable:(id<MTLDrawable>)drawable atTime:(CFTimeInterval)t { [self presentDrawable:drawable]; }
- (void)presentDrawable:(id<MTLDrawable>)drawable afterMinimumDuration:(CFTimeInterval)d { [self presentDrawable:drawable]; }
- (void)encodeSignalEvent:(id<MTLEvent>)event value:(uint64_t)value {
  [self _endActive];
  xef_mtl_event_op *e = (xef_mtl_event_op *)xef_stream_emit(&_stream, XEF_MTL_CMD_SIGNAL_EVENT, sizeof *e);
  e->event = ((XEFMetalEvent *)event)->_id; e->value = value;
  [self _retain:event];
}
- (void)encodeWaitForEvent:(id<MTLEvent>)event value:(uint64_t)value {
  [self _endActive];
  xef_mtl_event_op *e = (xef_mtl_event_op *)xef_stream_emit(&_stream, XEF_MTL_CMD_WAIT_EVENT, sizeof *e);
  e->event = ((XEFMetalEvent *)event)->_id; e->value = value;
  [self _retain:event];
}
- (void)addScheduledHandler:(MTLCommandBufferHandler)block {
  pthread_mutex_lock(&_lock);
  if (_status >= MTLCommandBufferStatusScheduled) { pthread_mutex_unlock(&_lock); block(self); return; }
  [_scheduledHandlers addObject:[[block copy] autorelease]];
  pthread_mutex_unlock(&_lock);
}
- (void)addCompletedHandler:(MTLCommandBufferHandler)block {
  pthread_mutex_lock(&_lock);
  if (_status >= MTLCommandBufferStatusCompleted) { pthread_mutex_unlock(&_lock); block(self); return; }
  [_completedHandlers addObject:[[block copy] autorelease]];
  pthread_mutex_unlock(&_lock);
}
- (void)enqueue { if (_status < MTLCommandBufferStatusEnqueued) _status = MTLCommandBufferStatusEnqueued; }
- (void)commit {
  [self _endActive];
  if (_status >= MTLCommandBufferStatusCommitted) return;
  _status = MTLCommandBufferStatusCommitted;
  _startTime = CFAbsoluteTimeGetCurrent();
  _seq = xef_mtl_commit(_queue->_id, _stream.data, _stream.len);
  free(_stream.data);
  _stream.data = NULL; _stream.len = _stream.cap = 0;
  /* scheduled handlers run right away (the host has submitted the work) */
  NSArray *sh;
  pthread_mutex_lock(&_lock);
  _status = MTLCommandBufferStatusScheduled;
  sh = [_scheduledHandlers copy];
  [_scheduledHandlers removeAllObjects];
  pthread_mutex_unlock(&_lock);
  for (MTLCommandBufferHandler h in sh) h(self);
  [sh release];
  [_queue _enqueueCompletion:self];
}
- (void)_complete {
  NSArray *ch;
  pthread_mutex_lock(&_lock);
  _endTime = CFAbsoluteTimeGetCurrent();
  _status = MTLCommandBufferStatusCompleted;
  ch = [_completedHandlers copy];
  [_completedHandlers removeAllObjects];
  pthread_cond_broadcast(&_cond);
  pthread_mutex_unlock(&_lock);
  for (id d in _drawables) if ([d respondsToSelector:@selector(_xefRunPresentedHandlers)]) [d _xefRunPresentedHandlers];
  for (MTLCommandBufferHandler h in ch) h(self);
  [ch release];
  [_retained removeAllObjects];
  [_drawables removeAllObjects];
}
- (void)waitUntilScheduled {}
- (void)waitUntilCompleted {
  if (_status < MTLCommandBufferStatusCommitted) return;
  pthread_mutex_lock(&_lock);
  while (_status < MTLCommandBufferStatusCompleted) pthread_cond_wait(&_cond, &_lock);
  pthread_mutex_unlock(&_lock);
}
- (void)pushDebugGroup:(NSString *)s {}
- (void)popDebugGroup {}
- (void)useResidencySet:(id)set {}
- (void)useResidencySets:(const id *)sets count:(NSUInteger)count {}
- (void)dealloc {
  free(_stream.data);
  [_retained release]; [_scheduledHandlers release]; [_completedHandlers release]; [_drawables release];
  [_queue release];
  pthread_mutex_destroy(&_lock);
  pthread_cond_destroy(&_cond);
  [super dealloc];
}
@end

static void *xef_completion_thread(void *arg) {
  XEFMetalCommandQueue *q = (XEFMetalCommandQueue *)arg;
  for (;;) {
    pthread_mutex_lock(&q->_lock);
    while ([q->_pending count] == 0) pthread_cond_wait(&q->_cond, &q->_lock);
    XEFMetalCommandBuffer *cb = [[q->_pending objectAtIndex:0] retain];
    pthread_mutex_unlock(&q->_lock);
    xef_mtl_wait(q->_id, cb->_seq, -1);
    @autoreleasepool {
      [cb _complete];
    }
    pthread_mutex_lock(&q->_lock);
    [q->_pending removeObjectAtIndex:0];
    pthread_mutex_unlock(&q->_lock);
    [cb release];
  }
  return NULL;
}

@implementation XEFMetalCommandQueue
- (id)init {
  if ((self = [super init])) {
    _id = xef_mtl_queue_create();
    pthread_mutex_init(&_lock, NULL);
    pthread_cond_init(&_cond, NULL);
    _pending = [[NSMutableArray alloc] init];
  }
  return self;
}
- (id<MTLDevice>)device { return xef_shared_device(); }
- (id<MTLCommandBuffer>)commandBuffer {
  XEFMetalCommandBuffer *cb = [[[XEFMetalCommandBuffer alloc] init] autorelease];
  cb->_queue = [self retain];
  return cb;
}
- (id<MTLCommandBuffer>)commandBufferWithUnretainedReferences {
  XEFMetalCommandBuffer *cb = (XEFMetalCommandBuffer *)[self commandBuffer];
  cb->_retainedReferences = NO;   /* still retained internally: host objects must outlive the GPU work */
  return cb;
}
- (id<MTLCommandBuffer>)commandBufferWithDescriptor:(MTLCommandBufferDescriptor *)d { return [self commandBuffer]; }
- (void)insertDebugCaptureBoundary {}
- (void)addResidencySet:(id)s {}
- (void)addResidencySets:(const id *)s count:(NSUInteger)n {}
- (void)removeResidencySet:(id)s {}
- (void)removeResidencySets:(const id *)s count:(NSUInteger)n {}
- (void)_enqueueCompletion:(XEFMetalCommandBuffer *)cb {
  pthread_mutex_lock(&_lock);
  [_pending addObject:cb];
  if (!_threadStarted) {
    _threadStarted = YES;
    pthread_t t;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    [self retain];
    pthread_create(&t, &attr, xef_completion_thread, self);
    pthread_attr_destroy(&attr);
  }
  pthread_cond_signal(&_cond);
  pthread_mutex_unlock(&_lock);
}
@end

/* internal queue for -[CAMetalDrawable present] */
id xef_metal_present_queue(void) {
  static XEFMetalCommandQueue *q;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ q = [[XEFMetalCommandQueue alloc] init]; });
  return q;
}

/* ------------------------------------------------------------------- heaps / argument encoders */

@interface XEFMetalHeap : XEFMetalObject <MTLHeap> {
@public
  NSUInteger _size, _used;
  MTLStorageMode _storageMode;
  MTLCPUCacheMode _cacheMode;
  MTLHeapType _type;
}
@end

/* ------------------------------------------------------------------- device */

@interface XEFMetalDevice : XEFMetalObject <MTLDevice> {
@public
  xef_mtl_device_info _info;
  NSString *_name;
}
+ (id)sharedDevice;
@end

static NSError *xef_error(NSString *domain, NSInteger code, const char *msg) {
  return [NSError errorWithDomain:domain code:code userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:msg ? msg : "error"]}];
}

static void xef_function_ref(id<MTLFunction> f, xef_mtl_function_ref *r) {
  memset(r, 0, sizeof *r);
  if (f && [(id)f isKindOfClass:[XEFMetalFunction class]]) [(XEFMetalFunction *)f _fill:r];
}

/* [[visible]] functions for a pipeline: linkedFunctions (functions, binary and private functions) and preloaded
   dynamic libraries; the arrays live until the pipeline call returns */
static void xef_linked(NSArray *lfs, NSArray *libs, NSMutableData *refs, NSMutableData *ids) {
  for (MTLLinkedFunctions *lf in lfs) {
    if (![lf isKindOfClass:[MTLLinkedFunctions class]]) continue;
    for (NSArray *a in @[lf.functions ?: @[], lf.binaryFunctions ?: @[], lf.privateFunctions ?: @[]])
      for (id f in a) {
        xef_mtl_function_ref r;
        xef_function_ref(f, &r);
        if (r.name) [refs appendBytes:&r length:sizeof r];
      }
  }
  for (id dl in libs) {
    id lib = [dl respondsToSelector:@selector(_xefLibrary)] ? [dl performSelector:@selector(_xefLibrary)] : nil;
    if ([lib isKindOfClass:[XEFMetalLibrary class]]) { uint32_t v = ((XEFMetalLibrary *)lib)->_id; [ids appendBytes:&v length:4]; }
  }
}

@implementation XEFMetalDevice
+ (id)sharedDevice {
  static XEFMetalDevice *d;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    XEFMetalDevice *x = [[XEFMetalDevice alloc] init];
    if (!xef_mtl_init(&x->_info)) { [x release]; x = nil; return; }
    x->_name = [[NSString alloc] initWithUTF8String:x->_info.name];
    d = x;
  });
  return d;
}
- (NSString *)name { return _name; }
- (uint64_t)registryID { return 0x100000001ull; }
- (MTLDeviceLocation)location { return MTLDeviceLocationBuiltIn; }
- (NSUInteger)locationNumber { return 0; }
- (MTLSize)maxThreadsPerThreadgroup { return MTLSizeMake(_info.max_threads_per_threadgroup, _info.max_threads_per_threadgroup, 64); }
- (BOOL)isLowPower { return NO; }
- (BOOL)isHeadless { return NO; }
- (BOOL)isRemovable { return NO; }
- (BOOL)hasUnifiedMemory { return YES; }
- (uint64_t)recommendedMaxWorkingSetSize { return _info.recommended_max_working_set; }
- (uint64_t)maxTransferRate { return 0; }
- (BOOL)isDepth24Stencil8PixelFormatSupported { return YES; }
- (MTLReadWriteTextureTier)readWriteTextureSupport { return MTLReadWriteTextureTier2; }
- (MTLArgumentBuffersTier)argumentBuffersSupport { return MTLArgumentBuffersTier2; }
- (BOOL)areRasterOrderGroupsSupported { return NO; }
- (BOOL)supports32BitFloatFiltering { return YES; }
- (BOOL)supports32BitMSAA { return YES; }
- (BOOL)supportsQueryTextureLOD { return YES; }
- (BOOL)supportsBCTextureCompression { return YES; }
- (BOOL)supportsPullModelInterpolation { return NO; }
- (BOOL)areBarycentricCoordsSupported { return NO; }
- (BOOL)supportsShaderBarycentricCoordinates { return NO; }
- (NSUInteger)currentAllocatedSize { return 0; }
- (NSUInteger)maxThreadgroupMemoryLength { return 32768; }
- (NSUInteger)maxArgumentBufferSamplerCount { return 2048; }
- (BOOL)areProgrammableSamplePositionsSupported { return NO; }
- (NSUInteger)maxBufferLength { return (NSUInteger)_info.max_buffer_length; }
- (BOOL)supportsRaytracing { return NO; }
- (BOOL)supportsFunctionPointers { return YES; }   /* switch over the pipeline's linked functions */
- (BOOL)supportsFunctionPointersFromRender { return YES; }
- (BOOL)supportsRaytracingFromRender { return NO; }
- (BOOL)supportsPrimitiveMotionBlur { return NO; }
- (BOOL)shouldMaximizeConcurrentCompilation { return NO; }
- (void)setShouldMaximizeConcurrentCompilation:(BOOL)b {}
- (NSUInteger)maximumConcurrentCompilationTaskCount { return 1; }
- (BOOL)supportsDynamicLibraries { return YES; }   /* linked into each pipeline at compile time */
- (BOOL)supportsRenderDynamicLibraries { return NO; }
- (uint32_t)peerGroupID { return 0; }
- (uint32_t)peerIndex { return 0; }
- (uint32_t)peerCount { return 1; }
- (NSUInteger)sparseTileSizeInBytes { return 65536; }
- (NSArray *)counterSets { return @[]; }
- (BOOL)supportsFamily:(MTLGPUFamily)f {
  switch (f) {
  case MTLGPUFamilyMac2: case MTLGPUFamilyCommon1: case MTLGPUFamilyCommon2: case MTLGPUFamilyCommon3: case MTLGPUFamilyMetal3:
    return YES;
  default:
    return NO;
  }
}
- (BOOL)supportsFeatureSet:(MTLFeatureSet)fs { return fs == MTLFeatureSet_macOS_GPUFamily1_v1 || fs == MTLFeatureSet_macOS_GPUFamily1_v2 ||
                                                       fs == MTLFeatureSet_macOS_GPUFamily1_v3 || fs == MTLFeatureSet_macOS_GPUFamily1_v4 ||
                                                       fs == MTLFeatureSet_macOS_GPUFamily2_v1; }
- (BOOL)supportsTextureSampleCount:(NSUInteger)c { return c == 1 || c == 2 || c == 4 || c == 8; }
- (BOOL)supportsVertexAmplificationCount:(NSUInteger)c { return c == 1; }
- (BOOL)supportsRasterizationRateMapWithLayerCount:(NSUInteger)c { return NO; }
- (BOOL)supportsCounterSampling:(MTLCounterSamplingPoint)p { return NO; }
- (NSUInteger)minimumLinearTextureAlignmentForPixelFormat:(MTLPixelFormat)f { return 256; }
- (NSUInteger)minimumTextureBufferAlignmentForPixelFormat:(MTLPixelFormat)f { return 16; }
- (void)getDefaultSamplePositions:(MTLSamplePosition *)positions count:(NSUInteger)count {
  for (NSUInteger i = 0; i < count; i++) positions[i] = MTLSamplePositionMake(0.5f, 0.5f);
}
- (void)sampleTimestamps:(MTLTimestamp *)cpu gpuTimestamp:(MTLTimestamp *)gpu {
  uint64_t t = (uint64_t)(CFAbsoluteTimeGetCurrent() * 1e9);
  if (cpu) *cpu = t;
  if (gpu) *gpu = t;
}
- (MTLSizeAndAlign)heapBufferSizeAndAlignWithLength:(NSUInteger)length options:(MTLResourceOptions)options {
  MTLSizeAndAlign s = {(length + 255) & ~(NSUInteger)255, 256};
  return s;
}
- (MTLSizeAndAlign)heapTextureSizeAndAlignWithDescriptor:(MTLTextureDescriptor *)d {
  NSUInteger sz = d.width * MAX(1, d.height) * MAX(1, d.depth) * MAX(1, d.arrayLength) * 16;
  MTLSizeAndAlign s = {(sz + 65535) & ~(NSUInteger)65535, 65536};
  return s;
}
/* ---- queues ---- */
- (id<MTLCommandQueue>)newCommandQueue { return [[XEFMetalCommandQueue alloc] init]; }
- (id<MTLCommandQueue>)newCommandQueueWithMaxCommandBufferCount:(NSUInteger)n { return [self newCommandQueue]; }
- (id<MTLCommandQueue>)newCommandQueueWithDescriptor:(MTLCommandQueueDescriptor *)d { return [self newCommandQueue]; }
/* ---- buffers ---- */
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options {
  void *contents = NULL;
  uint64_t gpu = 0;
  uint32_t id = xef_mtl_buffer_create(length, (uint32_t)options, &contents, &gpu);
  if (!id) return nil;
  XEFMetalBuffer *b = [[XEFMetalBuffer alloc] init];
  b->_id = id; b->_contents = contents; b->_length = length; b->_gpuAddress = gpu; b->_options = options;
  return b;
}
- (id<MTLBuffer>)newBufferWithBytes:(const void *)pointer length:(NSUInteger)length options:(MTLResourceOptions)options {
  MTLResourceOptions opts = options;
  if (((options >> MTLResourceStorageModeShift) & 0xf) == MTLStorageModePrivate) opts &= ~(MTLResourceOptions)(0xf << MTLResourceStorageModeShift);
  XEFMetalBuffer *b = (XEFMetalBuffer *)[self newBufferWithLength:length options:opts];
  if (b && b->_contents && pointer) memcpy(b->_contents, pointer, length);
  return b;
}
- (id<MTLBuffer>)newBufferWithBytesNoCopy:(void *)pointer length:(NSUInteger)length options:(MTLResourceOptions)options
                              deallocator:(void (^)(void *pointer, NSUInteger length))deallocator {
  uint64_t gpu = 0;
  uint32_t id = xef_mtl_buffer_create_nocopy(pointer, length, (uint32_t)options, &gpu);
  XEFMetalBuffer *b;
  if (id) {
    b = [[XEFMetalBuffer alloc] init];
    b->_id = id; b->_contents = pointer; b->_length = length; b->_gpuAddress = gpu; b->_options = options;
  } else {
    /* HLE: no host-pointer import available: the buffer gets its own memory (later CPU writes through `pointer` are lost) */
    b = (XEFMetalBuffer *)[self newBufferWithBytes:pointer length:length options:options];
  }
  if (b && deallocator) { b->_deallocator = Block_copy(deallocator); b->_noCopyPointer = pointer; }
  return b;
}
/* ---- textures ---- */
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)desc {
  xef_mtl_texture_desc d;
  memset(&d, 0, sizeof d);
  d.type = (uint32_t)desc.textureType;
  d.pixel_format = (uint32_t)desc.pixelFormat;
  d.width = (uint32_t)desc.width; d.height = (uint32_t)desc.height; d.depth = (uint32_t)desc.depth;
  d.mip_levels = (uint32_t)desc.mipmapLevelCount; d.array_length = (uint32_t)desc.arrayLength;
  d.sample_count = (uint32_t)desc.sampleCount;
  MTLTextureUsage usage = desc.usage;
  if (usage == MTLTextureUsageUnknown) usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageRenderTarget | MTLTextureUsagePixelFormatView;
  d.usage = (uint32_t)usage;
  d.storage_mode = (uint32_t)desc.storageMode;
  MTLTextureSwizzleChannels sw = desc.swizzle;
  d.swizzle[0] = sw.red; d.swizzle[1] = sw.green; d.swizzle[2] = sw.blue; d.swizzle[3] = sw.alpha;
  uint64_t rid = 0;
  uint32_t id = xef_mtl_texture_create(&d, &rid);
  if (!id) return nil;
  XEFMetalTexture *t = [[XEFMetalTexture alloc] init];
  t->_id = id; t->_rid = rid; t->_owned = YES;
  t->_type = desc.textureType; t->_pixelFormat = desc.pixelFormat;
  t->_width = MAX(1, desc.width); t->_height = MAX(1, desc.height); t->_depth = MAX(1, desc.depth);
  t->_mips = MAX(1, desc.mipmapLevelCount); t->_arrayLength = MAX(1, desc.arrayLength); t->_samples = MAX(1, desc.sampleCount);
  t->_usage = usage; t->_storageMode = desc.storageMode; t->_swizzle = sw;
  return t;
}
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)desc iosurface:(IOSurfaceRef)iosurface plane:(NSUInteger)plane {
  return [self newTextureWithDescriptor:desc];
}
- (id<MTLTexture>)newSharedTextureWithDescriptor:(MTLTextureDescriptor *)desc { return [self newTextureWithDescriptor:desc]; }
- (id<MTLTexture>)newSharedTextureWithHandle:(MTLSharedTextureHandle *)h {
  /* handles only travel inside this process: they wrap the texture itself */
  id t = h ? objc_getAssociatedObject(h, "xef_texture") : nil;
  return t ? [t retain] : nil;
}
/* ---- archives, dynamic libraries, indirect command buffers, logging ---- */
- (id<MTLBinaryArchive>)newBinaryArchiveWithDescriptor:(MTLBinaryArchiveDescriptor *)d error:(NSError **)error {
  if (error) *error = nil;
  return (id<MTLBinaryArchive>)[[XEFMetalBinaryArchive alloc] initWithDescriptor:d device:self];
}
- (id<MTLDynamicLibrary>)newDynamicLibrary:(id<MTLLibrary>)library error:(NSError **)error {
  if (error) *error = nil;
  return (id<MTLDynamicLibrary>)[[XEFMetalDynamicLibrary alloc] initWithLibrary:library device:self];
}
- (id<MTLDynamicLibrary>)newDynamicLibraryWithURL:(NSURL *)url error:(NSError **)error {
  id<MTLLibrary> l = [self newLibraryWithURL:url error:error];
  if (!l) return nil;
  id<MTLDynamicLibrary> d = [self newDynamicLibrary:l error:error];
  [(id)l release];
  return d;
}
- (id<MTLIndirectCommandBuffer>)newIndirectCommandBufferWithDescriptor:(MTLIndirectCommandBufferDescriptor *)d
                                                       maxCommandCount:(NSUInteger)n options:(MTLResourceOptions)o {
  return (id<MTLIndirectCommandBuffer>)[[XEFMetalIndirectCommandBuffer alloc] initWithDescriptor:d maxCommandCount:n options:o device:self];
}
- (id<MTLLogState>)newLogStateWithDescriptor:(MTLLogStateDescriptor *)d error:(NSError **)error {
  if (error) *error = nil;
  return (id<MTLLogState>)[[XEFMetalLogState alloc] initWithDescriptor:d];
}
/* ---- samplers / depth stencil ---- */
- (id<MTLSamplerState>)newSamplerStateWithDescriptor:(MTLSamplerDescriptor *)desc {
  xef_mtl_sampler_desc d;
  memset(&d, 0, sizeof d);
  d.min_filter = (uint32_t)desc.minFilter; d.mag_filter = (uint32_t)desc.magFilter; d.mip_filter = (uint32_t)desc.mipFilter;
  d.s_address = (uint32_t)desc.sAddressMode; d.t_address = (uint32_t)desc.tAddressMode; d.r_address = (uint32_t)desc.rAddressMode;
  d.max_anisotropy = (uint32_t)desc.maxAnisotropy;
  d.compare = (uint32_t)desc.compareFunction;
  d.compare_enable = desc.compareFunction != MTLCompareFunctionNever;
  d.border_color = (uint32_t)desc.borderColor;
  d.normalized = desc.normalizedCoordinates ? 1 : 0;
  d.lod_min = desc.lodMinClamp; d.lod_max = desc.lodMaxClamp;
  uint64_t rid = 0;
  uint32_t id = xef_mtl_sampler_create(&d, &rid);
  if (!id) return nil;
  XEFMetalSamplerState *s = [[XEFMetalSamplerState alloc] init];
  s->_id = id; s->_rid = rid;
  s.label = desc.label;
  return s;
}
- (id<MTLDepthStencilState>)newDepthStencilStateWithDescriptor:(MTLDepthStencilDescriptor *)desc {
  XEFMetalDepthStencilState *s = [[XEFMetalDepthStencilState alloc] init];
  s.label = desc.label;
  s->_ds.depth_compare = (uint32_t)desc.depthCompareFunction;
  s->_ds.depth_write = desc.depthWriteEnabled ? 1 : 0;
  MTLStencilDescriptor *f = desc.frontFaceStencil, *b = desc.backFaceStencil;
  s->_ds.stencil_enabled = (f || b) ? 1 : 0;
  xef_mtl_stencil_face *faces[2] = {&s->_ds.front, &s->_ds.back};
  MTLStencilDescriptor *src[2] = {f ? f : b, b ? b : f};
  for (int i = 0; i < 2; i++) {
    xef_mtl_stencil_face *o = faces[i];
    if (src[i]) {
      o->compare = (uint32_t)src[i].stencilCompareFunction;
      o->fail_op = (uint32_t)src[i].stencilFailureOperation;
      o->depth_fail_op = (uint32_t)src[i].depthFailureOperation;
      o->pass_op = (uint32_t)src[i].depthStencilPassOperation;
      o->read_mask = src[i].readMask;
      o->write_mask = src[i].writeMask;
    } else {
      o->compare = MTLCompareFunctionAlways;
      o->read_mask = o->write_mask = 0xff;
    }
  }
  return s;
}
/* ---- libraries ---- */
- (id<MTLLibrary>)newLibraryWithData:(dispatch_data_t)data error:(NSError **)error {
  const void *bytes = NULL;
  size_t size = 0;
  dispatch_data_t map = dispatch_data_create_map(data, &bytes, &size);
  char err[512] = {0};
  uint32_t id = xef_mtl_library_create(bytes, size, err, sizeof err);
  if (map) dispatch_release(map);
  if (!id) {
    if (error) *error = xef_error(@"MTLLibraryErrorDomain", 1, err);
    return nil;
  }
  XEFMetalLibrary *l = [[XEFMetalLibrary alloc] init];
  l->_id = id;
  [l _loadNames];
  return l;
}
- (id<MTLLibrary>)_libraryWithBytes:(const void *)bytes length:(size_t)len error:(NSError **)error {
  char err[512] = {0};
  uint32_t id = xef_mtl_library_create(bytes, len, err, sizeof err);
  if (!id) {
    if (error) *error = xef_error(@"MTLLibraryErrorDomain", 1, err);
    return nil;
  }
  XEFMetalLibrary *l = [[XEFMetalLibrary alloc] init];
  l->_id = id;
  [l _loadNames];
  return l;
}
- (id<MTLLibrary>)newLibraryWithFile:(NSString *)path error:(NSError **)error {
  NSData *d = [NSData dataWithContentsOfFile:path];
  if (!d) {
    if (error) *error = xef_error(@"MTLLibraryErrorDomain", 6, "file not found");
    return nil;
  }
  return [self _libraryWithBytes:[d bytes] length:[d length] error:error];
}
- (id<MTLLibrary>)newLibraryWithURL:(NSURL *)url error:(NSError **)error { return [self newLibraryWithFile:[url path] error:error]; }
- (id<MTLLibrary>)newDefaultLibraryWithBundle:(NSBundle *)bundle error:(NSError **)error {
  NSString *p = [bundle pathForResource:@"default" ofType:@"metallib"];
  if (!p) {
    if (error) *error = xef_error(@"MTLLibraryErrorDomain", 6, "default.metallib not found");
    return nil;
  }
  return [self newLibraryWithFile:p error:error];
}
- (id<MTLLibrary>)newDefaultLibrary {
  id<MTLLibrary> l = [self newDefaultLibraryWithBundle:[NSBundle mainBundle] error:NULL];
  if (!l) {
    /* command line tools: default.metallib next to the executable */
    NSString *exe = [[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent];
    NSString *p = [exe stringByAppendingPathComponent:@"default.metallib"];
    l = [self newLibraryWithFile:p error:NULL];
  }
  return l;
}
- (id<MTLLibrary>)newLibraryWithSource:(NSString *)source options:(MTLCompileOptions *)options error:(NSError **)error {
  char err[4096] = {0};
  /* preprocessor macros travel as "NAME=VALUE" lines */
  NSMutableString *defs = nil;
  NSDictionary *macros = options ? [options preprocessorMacros] : nil;
  for (id k in macros) {
    if (!defs) defs = [NSMutableString string];
    id v = [macros objectForKey:k];
    [defs appendFormat:@"%@=%@\n", k, [v isKindOfClass:[NSNumber class]] ? [v stringValue] : [v description]];
  }
  uint32_t id = xef_mtl_library_create_source([source UTF8String], defs ? [defs UTF8String] : NULL, err, sizeof err);
  if (!id) {
    if (error) *error = xef_error(@"MTLLibraryErrorDomain", 3, err);
    return nil;
  }
  XEFMetalLibrary *l = [[XEFMetalLibrary alloc] init];
  l->_id = id;
  [l _loadNames];
  return l;
}
- (void)newLibraryWithSource:(NSString *)source options:(MTLCompileOptions *)options
           completionHandler:(MTLNewLibraryCompletionHandler)completionHandler {
  NSError *err = nil;
  id<MTLLibrary> l = [self newLibraryWithSource:source options:options error:&err];
  completionHandler(l, err);
  [(id)l release];
}
- (id<MTLLibrary>)newLibraryWithStitchedDescriptor:(id)d error:(NSError **)error {
  if (error) *error = xef_error(@"MTLLibraryErrorDomain", 1, "stitched libraries are not supported");
  return nil;
}
/* ---- render pipelines ---- */
- (id<MTLRenderPipelineState>)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)desc
                                                            options:(MTLPipelineOption)options
                                                         reflection:(MTLAutoreleasedRenderPipelineReflection *)reflection
                                                              error:(NSError **)error {
  xef_mtl_render_pipeline_desc d;
  memset(&d, 0, sizeof d);
  xef_function_ref(desc.vertexFunction, &d.vertex);
  xef_function_ref(desc.fragmentFunction, &d.fragment);
  MTLVertexDescriptor *vd = desc.vertexDescriptor;
  if (vd) {
    d.has_vertex_descriptor = 1;
    for (int i = 0; i < XEF_MTL_MAX_VERTEX_ATTRIBS; i++) {
      MTLVertexAttributeDescriptor *a = vd.attributes[i];
      d.attribs[i].format = (uint32_t)a.format;
      d.attribs[i].offset = (uint32_t)a.offset;
      d.attribs[i].buffer_index = (uint32_t)a.bufferIndex;
    }
    for (int i = 0; i < XEF_MTL_MAX_BUFFERS; i++) {
      MTLVertexBufferLayoutDescriptor *l = vd.layouts[i];
      d.layouts[i].stride = (uint32_t)l.stride;
      d.layouts[i].step_function = (uint32_t)l.stepFunction;
      d.layouts[i].step_rate = (uint32_t)l.stepRate;
    }
  }
  for (int i = 0; i < XEF_MTL_MAX_COLOR; i++) {
    MTLRenderPipelineColorAttachmentDescriptor *c = desc.colorAttachments[i];
    d.colors[i].pixel_format = (uint32_t)c.pixelFormat;
    d.colors[i].blending = c.blendingEnabled ? 1 : 0;
    d.colors[i].src_rgb = (uint32_t)c.sourceRGBBlendFactor; d.colors[i].dst_rgb = (uint32_t)c.destinationRGBBlendFactor;
    d.colors[i].rgb_op = (uint32_t)c.rgbBlendOperation;
    d.colors[i].src_alpha = (uint32_t)c.sourceAlphaBlendFactor; d.colors[i].dst_alpha = (uint32_t)c.destinationAlphaBlendFactor;
    d.colors[i].alpha_op = (uint32_t)c.alphaBlendOperation;
    d.colors[i].write_mask = (uint32_t)c.writeMask;
  }
  d.depth_format = (uint32_t)desc.depthAttachmentPixelFormat;
  d.stencil_format = (uint32_t)desc.stencilAttachmentPixelFormat;
  NSUInteger sc = desc.rasterSampleCount ? desc.rasterSampleCount : desc.sampleCount;
  d.sample_count = (uint32_t)(sc ? sc : 1);
  d.alpha_to_coverage = desc.alphaToCoverageEnabled ? 1 : 0;
  d.alpha_to_one = desc.alphaToOneEnabled ? 1 : 0;
  d.rasterization_enabled = desc.rasterizationEnabled ? 1 : 0;
  d.input_topology = (uint32_t)desc.inputPrimitiveTopology;
  NSMutableData *lrefs = [NSMutableData data], *lids = [NSMutableData data];
  NSMutableArray *lfs = [NSMutableArray array], *libs = [NSMutableArray array];
  if ([desc respondsToSelector:@selector(vertexLinkedFunctions)]) {
    if (desc.vertexLinkedFunctions) [lfs addObject:desc.vertexLinkedFunctions];
    if (desc.fragmentLinkedFunctions) [lfs addObject:desc.fragmentLinkedFunctions];
    if (desc.vertexPreloadedLibraries) [libs addObjectsFromArray:desc.vertexPreloadedLibraries];
    if (desc.fragmentPreloadedLibraries) [libs addObjectsFromArray:desc.fragmentPreloadedLibraries];
  }
  xef_linked(lfs, libs, lrefs, lids);
  d.linked = [lrefs bytes]; d.linked_count = (uint32_t)([lrefs length] / sizeof(xef_mtl_function_ref));
  d.link_libraries = [lids bytes]; d.link_library_count = (uint32_t)([lids length] / 4);
  char err[4096] = {0};
  uint32_t id = xef_mtl_render_pipeline_create(&d, err, sizeof err);
  if (reflection) *reflection = nil;
  if (!id) {
    fprintf(stderr, "xef-metal: render pipeline creation failed: %s\n", err);
    if (error) *error = xef_error(@"CompilerError", 3, err);
    return nil;
  }
  XEFMetalRenderPipelineState *p = [[XEFMetalRenderPipelineState alloc] init];
  p->_id = id;
  p->_label = [desc.label copy];
  return p;
}
- (id<MTLRenderPipelineState>)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)desc error:(NSError **)error {
  return [self newRenderPipelineStateWithDescriptor:desc options:MTLPipelineOptionNone reflection:NULL error:error];
}
- (void)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)desc completionHandler:(MTLNewRenderPipelineStateCompletionHandler)h {
  NSError *err = nil;
  id<MTLRenderPipelineState> p = [self newRenderPipelineStateWithDescriptor:desc error:&err];
  h(p, err);
  [(id)p release];
}
- (void)newRenderPipelineStateWithDescriptor:(MTLRenderPipelineDescriptor *)desc options:(MTLPipelineOption)options
                           completionHandler:(MTLNewRenderPipelineStateWithReflectionCompletionHandler)h {
  NSError *err = nil;
  id<MTLRenderPipelineState> p = [self newRenderPipelineStateWithDescriptor:desc error:&err];
  h(p, nil, err);
  [(id)p release];
}
/* ---- compute pipelines ---- */
- (id<MTLComputePipelineState>)_computeWithFunction:(id<MTLFunction>)fn maxThreads:(NSUInteger)maxThreads label:(NSString *)label error:(NSError **)error {
  return [self _computeWithFunction:fn linked:nil libraries:nil maxThreads:maxThreads label:label error:error];
}
- (id<MTLComputePipelineState>)_computeWithFunction:(id<MTLFunction>)fn linked:(MTLLinkedFunctions *)lf libraries:(NSArray *)libs
                                         maxThreads:(NSUInteger)maxThreads label:(NSString *)label error:(NSError **)error {
  xef_mtl_compute_pipeline_desc d;
  memset(&d, 0, sizeof d);
  xef_function_ref(fn, &d.function);
  NSMutableData *lrefs = [NSMutableData data], *lids = [NSMutableData data];
  xef_linked(lf ? @[lf] : @[], libs ?: @[], lrefs, lids);
  d.linked = [lrefs bytes]; d.linked_count = (uint32_t)([lrefs length] / sizeof(xef_mtl_function_ref));
  d.link_libraries = [lids bytes]; d.link_library_count = (uint32_t)([lids length] / 4);
  d.max_total_threads = (uint32_t)maxThreads;
  XEFMetalComputePipelineState *p = [[XEFMetalComputePipelineState alloc] init];
  char err[4096] = {0};
  uint32_t id = xef_mtl_compute_pipeline_create(&d, &p->_info, err, sizeof err);
  if (!id) {
    fprintf(stderr, "xef-metal: compute pipeline creation failed: %s\n", err);
    if (error) *error = xef_error(@"CompilerError", 3, err);
    [p release];
    return nil;
  }
  p->_id = id;
  p->_label = [label copy];
  return p;
}
- (id<MTLComputePipelineState>)newComputePipelineStateWithFunction:(id<MTLFunction>)fn error:(NSError **)error {
  return [self _computeWithFunction:fn maxThreads:0 label:nil error:error];
}
- (id<MTLComputePipelineState>)newComputePipelineStateWithFunction:(id<MTLFunction>)fn options:(MTLPipelineOption)options
                                                        reflection:(MTLAutoreleasedComputePipelineReflection *)reflection error:(NSError **)error {
  if (reflection) *reflection = nil;
  return [self _computeWithFunction:fn maxThreads:0 label:nil error:error];
}
- (id<MTLComputePipelineState>)newComputePipelineStateWithDescriptor:(MTLComputePipelineDescriptor *)desc options:(MTLPipelineOption)options
                                                          reflection:(MTLAutoreleasedComputePipelineReflection *)reflection error:(NSError **)error {
  if (reflection) *reflection = nil;
  return [self _computeWithFunction:desc.computeFunction linked:desc.linkedFunctions libraries:desc.preloadedLibraries
                         maxThreads:desc.maxTotalThreadsPerThreadgroup label:desc.label error:error];
}
- (void)newComputePipelineStateWithFunction:(id<MTLFunction>)fn completionHandler:(MTLNewComputePipelineStateCompletionHandler)h {
  NSError *err = nil;
  id<MTLComputePipelineState> p = [self newComputePipelineStateWithFunction:fn error:&err];
  h(p, err);
  [(id)p release];
}
- (void)newComputePipelineStateWithFunction:(id<MTLFunction>)fn options:(MTLPipelineOption)o completionHandler:(MTLNewComputePipelineStateWithReflectionCompletionHandler)h {
  NSError *err = nil;
  id<MTLComputePipelineState> p = [self newComputePipelineStateWithFunction:fn error:&err];
  h(p, nil, err);
  [(id)p release];
}
- (void)newComputePipelineStateWithDescriptor:(MTLComputePipelineDescriptor *)desc options:(MTLPipelineOption)o completionHandler:(MTLNewComputePipelineStateWithReflectionCompletionHandler)h {
  NSError *err = nil;
  id<MTLComputePipelineState> p = [self newComputePipelineStateWithDescriptor:desc options:o reflection:NULL error:&err];
  h(p, nil, err);
  [(id)p release];
}
/* ---- sync objects ---- */
- (id<MTLFence>)newFence { return [[XEFMetalFence alloc] init]; }
- (id<MTLEvent>)newEvent { return (id<MTLEvent>)[self newSharedEvent]; }
- (id<MTLSharedEvent>)newSharedEvent {
  XEFMetalEvent *e = [[XEFMetalEvent alloc] init];
  e->_id = xef_mtl_event_create();
  return e;
}
- (id<MTLSharedEvent>)newSharedEventWithHandle:(MTLSharedEventHandle *)h {
  id e = [h _event];
  if (e) return [e retain];
  id<MTLSharedEvent> n = [self newSharedEvent];
  if (h) n.signaledValue = [h _signaledValue];
  return n;
}
- (id<MTLHeap>)newHeapWithDescriptor:(MTLHeapDescriptor *)desc {
  XEFMetalHeap *h = [[XEFMetalHeap alloc] init];
  h->_size = desc.size; h->_storageMode = desc.storageMode; h->_cacheMode = desc.cpuCacheMode; h->_type = desc.type;
  return h;
}
@end

@implementation XEFMetalHeap
- (id<MTLDevice>)device { return xef_shared_device(); }
- (MTLStorageMode)storageMode { return _storageMode; }
- (MTLCPUCacheMode)cpuCacheMode { return _cacheMode; }
- (MTLHazardTrackingMode)hazardTrackingMode { return MTLHazardTrackingModeTracked; }
- (MTLResourceOptions)resourceOptions { return ((MTLResourceOptions)_storageMode << MTLResourceStorageModeShift) | _cacheMode; }
- (NSUInteger)size { return _size; }
- (NSUInteger)usedSize { return _used; }
- (NSUInteger)currentAllocatedSize { return _size; }
- (MTLHeapType)type { return _type; }
- (NSUInteger)maxAvailableSizeWithAlignment:(NSUInteger)alignment { return _size > _used ? _size - _used : 0; }
- (MTLPurgeableState)setPurgeableState:(MTLPurgeableState)state { return MTLPurgeableStateNonVolatile; }
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options {
  _used += (length + 255) & ~(NSUInteger)255;
  XEFMetalBuffer *b = (XEFMetalBuffer *)[xef_shared_device() newBufferWithLength:length options:options];
  if (b) b->_heap = self;
  return b;
}
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options offset:(NSUInteger)offset {
  return [self newBufferWithLength:length options:options];
}
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)desc {
  _used += desc.width * MAX(1, desc.height) * 4;
  XEFMetalTexture *t = (XEFMetalTexture *)[xef_shared_device() newTextureWithDescriptor:desc];
  if (t) t->_heap = self;
  return t;
}
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)desc offset:(NSUInteger)offset {
  return [self newTextureWithDescriptor:desc];
}
@end

static id<MTLDevice> xef_shared_device(void) { return [XEFMetalDevice sharedDevice]; }

id<MTLDevice> MTLCreateSystemDefaultDevice(void) {
  id<MTLDevice> d = xef_shared_device();
  return d ? [(id)d retain] : nil;
}

NSArray<id<MTLDevice>> *MTLCopyAllDevices(void) {
  id<MTLDevice> d = xef_shared_device();
  return d ? [[NSArray alloc] initWithObjects:d, nil] : [[NSArray alloc] init];
}

NSArray<id<MTLDevice>> *MTLCopyAllDevicesWithObserver(id<NSObject> *observer, MTLDeviceNotificationHandler handler) {
  if (observer) *observer = nil;
  return MTLCopyAllDevices();
}

void MTLRemoveDeviceObserver(id<NSObject> observer) {}
