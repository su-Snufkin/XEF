/* Metal.framework for xef-osx: auxiliary classes (shared events, counters, rasterization rate maps, function
 * tables, acceleration structures, indirect command buffers, logs, dynamic libraries, binary archives, capture).
 * Mostly state holders: their GPU features are not available on the Vulkan backend. */
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#import <Block.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

@interface XEFMetalObject : NSObject
@end
@interface XEFMetalDevice : XEFMetalObject
+ (id)sharedDevice;
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
- (id)_event;
- (void)_setEvent:(id)e;
@end

@implementation MTLSharedEventHandle {
  NSString *_label;
  uint64_t _signaledValue;
  id _event;                 /* the event this handle was made from (same process) */
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
- (id)_event { return _event; }
- (void)_setEvent:(id)e { [e retain]; [_event release]; _event = e; }
- (void)dealloc { [_label release]; [_event release]; [super dealloc]; }
@end


@implementation MTLSharedTextureHandle
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder {}
- (instancetype)initWithCoder:(NSCoder *)coder { return [super init]; }
- (id<MTLDevice>)device { id t = objc_getAssociatedObject(self, "xef_texture"); return t ? [t device] : [XEFMetalDevice sharedDevice]; }
- (NSString *)label { id t = objc_getAssociatedObject(self, "xef_texture"); return t ? [t label] : nil; }
@end

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
/* same value xef-mtlc compiles into function-pointer dispatch: FNV-1a of the name, top bit set */
- (MTLResourceID)gpuResourceID {
  uint64_t h = 0xcbf29ce484222325ull;
  for (const char *c = [_name UTF8String]; c && *c; c++) { h ^= (uint8_t)*c; h *= 0x100000001b3ull; }
  MTLResourceID rid = { h | (1ull << 63) };
  return rid;
}
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
  id<MTLBuffer> _buffer;   /* one 64-bit function id per entry, bound like a buffer */
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
    _buffer = [device newBufferWithLength:MAX(_functionCount, (NSUInteger)1) * 8 options:MTLResourceStorageModeShared];
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
    ((uint64_t *)[_buffer contents])[index] = function ? [function gpuResourceID]._impl : 0;
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
- (id<MTLBuffer>)_xefBuffer { return _buffer; }
- (void)dealloc {
  [_label release];
  [_functions release];
  [_buffer release];
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


@implementation MTLLogStateDescriptor {
  MTLLogLevel _level;
  NSInteger _bufferSize;
}
- (instancetype)init {
  if ((self = [super init])) {
    _level = MTLLogLevelUndefined;
    _bufferSize = 1024;
  }
  return self;
}
- (MTLLogLevel)level { return _level; }
- (void)setLevel:(MTLLogLevel)l { _level = l; }
- (NSInteger)bufferSize { return _bufferSize; }
- (void)setBufferSize:(NSInteger)s { _bufferSize = (s >= 1024) ? s : 1024; }
- (id)copyWithZone:(NSZone *)zone {
  MTLLogStateDescriptor *c = [[MTLLogStateDescriptor allocWithZone:zone] init];
  c.level = _level;
  c.bufferSize = _bufferSize;
  return c;
}
@end

@interface XEFMetalLogState : XEFMetalObject <MTLLogState> {
  NSMutableArray *_handlers;
  MTLLogLevel _level;
  NSInteger _bufferSize;
}
- (instancetype)initWithDescriptor:(MTLLogStateDescriptor *)desc;
@end

@implementation XEFMetalLogState
- (instancetype)initWithDescriptor:(MTLLogStateDescriptor *)desc {
  if ((self = [super init])) {
    _handlers = [[NSMutableArray alloc] init];
    _level = desc ? desc.level : MTLLogLevelUndefined;
    _bufferSize = desc ? desc.bufferSize : 1024;
  }
  return self;
}
- (void)addLogHandler:(void(^)(NSString *subSystem, NSString *category, MTLLogLevel logLevel, NSString *message))block {
  if (block) {
    id copy = [block copy];
    [_handlers addObject:copy];
    [copy release];
  }
}
- (void)dealloc {
  [_handlers release];
  [super dealloc];
}
@end

@implementation MTLCommandQueueDescriptor {
  NSUInteger _maxCommandBufferCount;
  id<MTLLogState> _logState;
}
- (instancetype)init {
  if ((self = [super init])) {
    _maxCommandBufferCount = 64;
  }
  return self;
}
- (NSUInteger)maxCommandBufferCount { return _maxCommandBufferCount; }
- (void)setMaxCommandBufferCount:(NSUInteger)count { _maxCommandBufferCount = count; }
- (id<MTLLogState>)logState { return _logState; }
- (void)setLogState:(id<MTLLogState>)ls { [ls retain]; [_logState release]; _logState = ls; }
- (id)copyWithZone:(NSZone *)zone {
  MTLCommandQueueDescriptor *c = [[MTLCommandQueueDescriptor allocWithZone:zone] init];
  c.maxCommandBufferCount = _maxCommandBufferCount;
  c.logState = _logState;
  return c;
}
- (void)dealloc { [_logState release]; [super dealloc]; }
@end


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
- (id<MTLLibrary>)_xefLibrary { return _library; }
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


