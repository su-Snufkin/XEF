#import <Foundation/Foundation.h>
#import <ModelIO/ModelIO.h>

@implementation MDLMeshBufferMap {
    void *_bytes;
    void (^_deallocator)(void);
}

- (instancetype)initWithBytes:(void *)bytes deallocator:(void (^)(void))deallocator {
    if ((self = [super init])) {
        _bytes = bytes;
        _deallocator = [deallocator copy];
    }
    return self;
}

- (void *)bytes {
    return _bytes;
}

- (void)dealloc {
    if (_deallocator) {
        _deallocator();
        [_deallocator release];
    }
    [super dealloc];
}

@end

@implementation MDLVertexAttribute {
    NSString *_name;
    MDLVertexFormat _format;
    NSUInteger _offset;
    NSUInteger _bufferIndex;
    NSTimeInterval _time;
    vector_float4 _initializationValue;
}

- (instancetype)initWithName:(NSString *)name format:(MDLVertexFormat)format offset:(NSUInteger)offset bufferIndex:(NSUInteger)bufferIndex {
    if ((self = [super init])) {
        _name = [name copy];
        _format = format;
        _offset = offset;
        _bufferIndex = bufferIndex;
    }
    return self;
}

- (instancetype)init {
    return [self initWithName:@"" format:MDLVertexFormatInvalid offset:0 bufferIndex:0];
}

- (NSString *)name { return _name; }
- (void)setName:(NSString *)name { [_name release]; _name = [name copy]; }

- (MDLVertexFormat)format { return _format; }
- (void)setFormat:(MDLVertexFormat)format { _format = format; }

- (NSUInteger)offset { return _offset; }
- (void)setOffset:(NSUInteger)offset { _offset = offset; }

- (NSUInteger)bufferIndex { return _bufferIndex; }
- (void)setBufferIndex:(NSUInteger)bufferIndex { _bufferIndex = bufferIndex; }

- (NSTimeInterval)time { return _time; }
- (void)setTime:(NSTimeInterval)time { _time = time; }

- (vector_float4)initializationValue { return _initializationValue; }
- (void)setInitializationValue:(vector_float4)initializationValue { _initializationValue = initializationValue; }

- (id)copyWithZone:(NSZone *)zone {
    MDLVertexAttribute *c = [[MDLVertexAttribute allocWithZone:zone] initWithName:_name format:_format offset:_offset bufferIndex:_bufferIndex];
    c.time = _time;
    c.initializationValue = _initializationValue;
    return c;
}

- (void)dealloc {
    [_name release];
    [super dealloc];
}

@end

@implementation MDLVertexBufferLayout {
    NSUInteger _stride;
}

- (instancetype)initWithStride:(NSUInteger)stride {
    if ((self = [super init])) {
        _stride = stride;
    }
    return self;
}

- (instancetype)init {
    return [self initWithStride:0];
}

- (NSUInteger)stride { return _stride; }
- (void)setStride:(NSUInteger)stride { _stride = stride; }

- (id)copyWithZone:(NSZone *)zone {
    return [[MDLVertexBufferLayout allocWithZone:zone] initWithStride:_stride];
}

@end

@implementation MDLVertexDescriptor {
    NSMutableArray<MDLVertexAttribute *> *_attributes;
    NSMutableArray<MDLVertexBufferLayout *> *_layouts;
}

- (instancetype)init {
    if ((self = [super init])) {
        _attributes = [[NSMutableArray alloc] initWithCapacity:32];
        for (int i = 0; i < 32; i++) {
            [_attributes addObject:[[[MDLVertexAttribute alloc] init] autorelease]];
        }
        _layouts = [[NSMutableArray alloc] initWithCapacity:32];
        for (int i = 0; i < 32; i++) {
            [_layouts addObject:[[[MDLVertexBufferLayout alloc] init] autorelease]];
        }
    }
    return self;
}

- (NSMutableArray<MDLVertexAttribute *> *)attributes {
    return _attributes;
}

- (void)setAttributes:(NSMutableArray<MDLVertexAttribute *> *)attributes {
    if (_attributes != attributes) {
        [_attributes release];
        _attributes = [attributes mutableCopy];
    }
}

- (NSMutableArray<MDLVertexBufferLayout *> *)layouts {
    return _layouts;
}

- (void)setLayouts:(NSMutableArray<MDLVertexBufferLayout *> *)layouts {
    if (_layouts != layouts) {
        [_layouts release];
        _layouts = [layouts mutableCopy];
    }
}

- (void)reset {
    for (int i = 0; i < 32; i++) {
        _attributes[i].format = MDLVertexFormatInvalid;
        _attributes[i].offset = 0;
        _attributes[i].bufferIndex = 0;
        _attributes[i].name = @"";
        _layouts[i].stride = 0;
    }
}

- (MDLVertexAttribute *)attributeNamed:(NSString *)name {
    for (MDLVertexAttribute *attr in _attributes) {
        if ([attr.name isEqualToString:name]) return attr;
    }
    return nil;
}

- (void)addOrReplaceAttribute:(MDLVertexAttribute *)attribute {
    if (!attribute) return;
    for (NSUInteger i = 0; i < _attributes.count; i++) {
        if ([_attributes[i].name isEqualToString:attribute.name] || _attributes[i].format == MDLVertexFormatInvalid) {
            _attributes[i] = [[attribute copy] autorelease];
            return;
        }
    }
}

- (id)copyWithZone:(NSZone *)zone {
    MDLVertexDescriptor *c = [[MDLVertexDescriptor allocWithZone:zone] init];
    for (int i = 0; i < 32; i++) {
        c.attributes[i] = [[_attributes[i] copy] autorelease];
        c.layouts[i] = [[_layouts[i] copy] autorelease];
    }
    return c;
}

- (void)dealloc {
    [_attributes release];
    [_layouts release];
    [super dealloc];
}

@end

/* ======================================================================= meshes */

NSString *const MDLVertexAttributeAnisotropy = @"anisotropy";
NSString *const MDLVertexAttributeBinormal = @"binormal";
NSString *const MDLVertexAttributeBitangent = @"bitangent";
NSString *const MDLVertexAttributeColor = @"color";
NSString *const MDLVertexAttributeEdgeCrease = @"edgeCrease";
NSString *const MDLVertexAttributeJointIndices = @"jointIndices";
NSString *const MDLVertexAttributeJointWeights = @"jointWeights";
NSString *const MDLVertexAttributeNormal = @"normal";
NSString *const MDLVertexAttributeOcclusionValue = @"occlusionValue";
NSString *const MDLVertexAttributePosition = @"position";
NSString *const MDLVertexAttributeShadingBasisU = @"shadingBasisU";
NSString *const MDLVertexAttributeShadingBasisV = @"shadingBasisV";
NSString *const MDLVertexAttributeSubdivisionStencil = @"subdivisionStencil";
NSString *const MDLVertexAttributeTangent = @"tangent";
NSString *const MDLVertexAttributeTextureCoordinate = @"textureCoordinate";

static NSUInteger mdl_format_size(MDLVertexFormat f) {
  NSUInteger n = f & 0xff, bits = f & 0xff0000;
  if (f & MDLVertexFormatPackedBit) return 4;
  switch (bits) {
  case MDLVertexFormatUCharBits: case MDLVertexFormatCharBits: case MDLVertexFormatUCharNormalizedBits: case MDLVertexFormatCharNormalizedBits: return n;
  case MDLVertexFormatUShortBits: case MDLVertexFormatShortBits: case MDLVertexFormatUShortNormalizedBits: case MDLVertexFormatShortNormalizedBits:
  case MDLVertexFormatHalfBits: return 2 * n;
  default: return 4 * n;
  }
}

static vector_float4 mdl_read(const uint8_t *p, MDLVertexFormat f) {
  float v[4] = {0, 0, 0, 1};
  NSUInteger n = f & 0xff, bits = f & 0xff0000;
  for (NSUInteger i = 0; i < n && i < 4; i++) {
    switch (bits) {
    case MDLVertexFormatUCharBits: v[i] = p[i]; break;
    case MDLVertexFormatCharBits: v[i] = (int8_t)p[i]; break;
    case MDLVertexFormatUCharNormalizedBits: v[i] = p[i] / 255.0f; break;
    case MDLVertexFormatCharNormalizedBits: v[i] = fmaxf((int8_t)p[i] / 127.0f, -1.0f); break;
    case MDLVertexFormatUShortBits: v[i] = ((const uint16_t *)p)[i]; break;
    case MDLVertexFormatShortBits: v[i] = ((const int16_t *)p)[i]; break;
    case MDLVertexFormatUShortNormalizedBits: v[i] = ((const uint16_t *)p)[i] / 65535.0f; break;
    case MDLVertexFormatShortNormalizedBits: v[i] = fmaxf(((const int16_t *)p)[i] / 32767.0f, -1.0f); break;
    case MDLVertexFormatUIntBits: v[i] = ((const uint32_t *)p)[i]; break;
    case MDLVertexFormatIntBits: v[i] = ((const int32_t *)p)[i]; break;
    case MDLVertexFormatHalfBits: v[i] = (float)((const _Float16 *)p)[i]; break;
    case MDLVertexFormatFloatBits: v[i] = ((const float *)p)[i]; break;
    default: break;
    }
  }
  return (vector_float4){v[0], v[1], v[2], v[3]};
}

static void mdl_write(uint8_t *p, MDLVertexFormat f, vector_float4 val) {
  float v[4] = {val.x, val.y, val.z, val.w};
  NSUInteger n = f & 0xff, bits = f & 0xff0000;
  for (NSUInteger i = 0; i < n && i < 4; i++) {
    float x = v[i];
    switch (bits) {
    case MDLVertexFormatUCharBits: p[i] = (uint8_t)x; break;
    case MDLVertexFormatCharBits: p[i] = (uint8_t)(int8_t)x; break;
    case MDLVertexFormatUCharNormalizedBits: p[i] = (uint8_t)lrintf(fminf(fmaxf(x, 0), 1) * 255); break;
    case MDLVertexFormatCharNormalizedBits: p[i] = (uint8_t)(int8_t)lrintf(fminf(fmaxf(x, -1), 1) * 127); break;
    case MDLVertexFormatUShortBits: ((uint16_t *)p)[i] = (uint16_t)x; break;
    case MDLVertexFormatShortBits: ((int16_t *)p)[i] = (int16_t)x; break;
    case MDLVertexFormatUShortNormalizedBits: ((uint16_t *)p)[i] = (uint16_t)lrintf(fminf(fmaxf(x, 0), 1) * 65535); break;
    case MDLVertexFormatShortNormalizedBits: ((int16_t *)p)[i] = (int16_t)lrintf(fminf(fmaxf(x, -1), 1) * 32767); break;
    case MDLVertexFormatUIntBits: ((uint32_t *)p)[i] = (uint32_t)x; break;
    case MDLVertexFormatIntBits: ((int32_t *)p)[i] = (int32_t)x; break;
    case MDLVertexFormatHalfBits: ((_Float16 *)p)[i] = (_Float16)x; break;
    case MDLVertexFormatFloatBits: ((float *)p)[i] = x; break;
    default: break;
    }
  }
}

@implementation MDLMeshBufferData {
  NSMutableData *_data;
  MDLMeshBufferType _type;
}
- (instancetype)initWithType:(MDLMeshBufferType)type length:(NSUInteger)length {
  if ((self = [super init])) { _type = type; _data = [[NSMutableData alloc] initWithLength:length]; }
  return self;
}
- (instancetype)initWithType:(MDLMeshBufferType)type data:(NSData *)data {
  if ((self = [super init])) { _type = type; _data = data ? [data mutableCopy] : [[NSMutableData alloc] init]; }
  return self;
}
- (NSData *)data { return _data; }
- (NSUInteger)length { return [_data length]; }
- (MDLMeshBufferType)type { return _type; }
- (id<MDLMeshBufferAllocator>)allocator { return [[[MDLMeshBufferDataAllocator alloc] init] autorelease]; }
- (id<MDLMeshBufferZone>)zone { return nil; }
- (void)fillData:(NSData *)data offset:(NSUInteger)offset {
  NSUInteger n = [data length];
  if (offset + n > [_data length]) n = [_data length] > offset ? [_data length] - offset : 0;
  if (n) memcpy((uint8_t *)[_data mutableBytes] + offset, [data bytes], n);
}
- (MDLMeshBufferMap *)map { return [[[MDLMeshBufferMap alloc] initWithBytes:[_data mutableBytes] deallocator:nil] autorelease]; }
- (id)copyWithZone:(NSZone *)zone { return [[MDLMeshBufferData allocWithZone:zone] initWithType:_type data:_data]; }
- (void)dealloc { [_data release]; [super dealloc]; }
@end

@implementation MDLMeshBufferDataAllocator
- (id<MDLMeshBufferZone>)newZone:(NSUInteger)capacity { return nil; }
- (id<MDLMeshBufferZone>)newZoneForBuffersWithSize:(NSArray<NSNumber *> *)sizes andType:(NSArray<NSNumber *> *)types { return nil; }
- (id<MDLMeshBuffer>)newBuffer:(NSUInteger)length type:(MDLMeshBufferType)type {
  return [[MDLMeshBufferData alloc] initWithType:type length:length];
}
- (id<MDLMeshBuffer>)newBufferWithData:(NSData *)data type:(MDLMeshBufferType)type {
  return [[MDLMeshBufferData alloc] initWithType:type data:data];
}
- (id<MDLMeshBuffer>)newBufferFromZone:(id<MDLMeshBufferZone>)zone length:(NSUInteger)length type:(MDLMeshBufferType)type {
  return [self newBuffer:length type:type];
}
- (id<MDLMeshBuffer>)newBufferFromZone:(id<MDLMeshBufferZone>)zone data:(NSData *)data type:(MDLMeshBufferType)type {
  return [self newBufferWithData:data type:type];
}
@end

@implementation MDLObject {
  NSString *_mdlName;
  MDLObject *_mdlParent;
  NSMutableArray *_mdlChildren;
  BOOL _mdlHidden;
}
- (NSString *)name { return _mdlName; }
- (void)setName:(NSString *)n { [_mdlName release]; _mdlName = [n copy]; }
- (MDLObject *)parent { return _mdlParent; }
- (void)setParent:(MDLObject *)p { _mdlParent = p; }
- (BOOL)hidden { return _mdlHidden; }
- (void)setHidden:(BOOL)h { _mdlHidden = h; }
- (void)addChild:(MDLObject *)c { if (!_mdlChildren) _mdlChildren = [[NSMutableArray alloc] init]; [_mdlChildren addObject:c]; [c setParent:self]; }
- (NSArray *)_xefChildren { return _mdlChildren ? _mdlChildren : @[]; }
- (id)componentConformingToProtocol:(Protocol *)p { return nil; }
- (void)setComponent:(id)c forProtocol:(Protocol *)p {}
- (NSString *)path { return [@"/" stringByAppendingString:_mdlName ? _mdlName : @""]; }
- (void)dealloc { [_mdlName release]; [_mdlChildren release]; [super dealloc]; }
@end

@implementation MDLSubmesh {
  id<MDLMeshBuffer> _ib;
  NSUInteger _icount;
  MDLIndexBitDepth _itype;
  MDLGeometryType _gtype;
  MDLMaterial *_material;
  NSString *_subName;
}
- (instancetype)initWithName:(NSString *)name indexBuffer:(id<MDLMeshBuffer>)ib indexCount:(NSUInteger)n
                   indexType:(MDLIndexBitDepth)t geometryType:(MDLGeometryType)g material:(MDLMaterial *)m {
  if ((self = [super init])) {
    _subName = [name copy]; _ib = [ib retain]; _icount = n; _itype = t; _gtype = g; _material = [m retain];
  }
  return self;
}
- (instancetype)initWithIndexBuffer:(id<MDLMeshBuffer>)ib indexCount:(NSUInteger)n indexType:(MDLIndexBitDepth)t
                       geometryType:(MDLGeometryType)g material:(MDLMaterial *)m {
  return [self initWithName:@"" indexBuffer:ib indexCount:n indexType:t geometryType:g material:m];
}
- (id<MDLMeshBuffer>)indexBuffer { return _ib; }
- (id<MDLMeshBuffer>)indexBufferAsIndexType:(MDLIndexBitDepth)t { return _ib; }
- (NSUInteger)indexCount { return _icount; }
- (MDLIndexBitDepth)indexType { return _itype; }
- (MDLGeometryType)geometryType { return _gtype; }
- (MDLMaterial *)material { return _material; }
- (void)setMaterial:(MDLMaterial *)m { [m retain]; [_material release]; _material = m; }
- (NSString *)name { return _subName; }
- (void)setName:(NSString *)n { [_subName release]; _subName = [n copy]; }
- (void)dealloc { [_ib release]; [_material release]; [_subName release]; [super dealloc]; }
@end

@implementation MDLVertexAttributeData {
  MDLMeshBufferMap *_vmap; void *_vstart; NSUInteger _vstride, _vsize; MDLVertexFormat _vformat;
}
- (instancetype)_xefInitWithMap:(MDLMeshBufferMap *)m start:(void *)s stride:(NSUInteger)st format:(MDLVertexFormat)f size:(NSUInteger)sz {
  if ((self = [super init])) { _vmap = [m retain]; _vstart = s; _vstride = st; _vformat = f; _vsize = sz; }
  return self;
}
- (MDLMeshBufferMap *)map { return _vmap; }
- (void *)dataStart { return _vstart; }
- (NSUInteger)stride { return _vstride; }
- (MDLVertexFormat)format { return _vformat; }
- (NSUInteger)bufferSize { return _vsize; }
- (void)dealloc { [_vmap release]; [super dealloc]; }
@end

@implementation MDLMesh {
  NSArray *_vbufs;
  NSUInteger _vcount;
  MDLVertexDescriptor *_vdesc;
  NSMutableArray *_subs;
  id<MDLMeshBufferAllocator> _alloc;
}
- (instancetype)initWithBufferAllocator:(id<MDLMeshBufferAllocator>)a {
  if ((self = [super init])) {
    _alloc = a ? [(id)a retain] : [[MDLMeshBufferDataAllocator alloc] init];
    _vbufs = [[NSArray alloc] init];
    _subs = [[NSMutableArray alloc] init];
    _vdesc = [[MDLVertexDescriptor alloc] init];
  }
  return self;
}
- (instancetype)init { return [self initWithBufferAllocator:nil]; }
- (instancetype)initWithVertexBuffers:(NSArray<id<MDLMeshBuffer>> *)vbs vertexCount:(NSUInteger)n
                           descriptor:(MDLVertexDescriptor *)d submeshes:(NSArray<MDLSubmesh *> *)s {
  id<MDLMeshBuffer> first = [vbs count] ? [vbs objectAtIndex:0] : nil;
  if ((self = [self initWithBufferAllocator:[(id)first respondsToSelector:@selector(allocator)] ? [first allocator] : nil])) {
    [_vbufs release]; _vbufs = [vbs copy];
    _vcount = n;
    [_vdesc release]; _vdesc = [d copy];
    [_subs addObjectsFromArray:s];
  }
  return self;
}
- (instancetype)initWithVertexBuffer:(id<MDLMeshBuffer>)vb vertexCount:(NSUInteger)n descriptor:(MDLVertexDescriptor *)d submeshes:(NSArray<MDLSubmesh *> *)s {
  return [self initWithVertexBuffers:vb ? @[vb] : @[] vertexCount:n descriptor:d submeshes:s];
}
- (NSArray *)vertexBuffers { return _vbufs; }
- (void)setVertexBuffers:(NSArray *)b { [_vbufs release]; _vbufs = [b copy]; }
- (NSUInteger)vertexCount { return _vcount; }
- (void)setVertexCount:(NSUInteger)n { _vcount = n; }
- (NSMutableArray *)submeshes { return _subs; }
- (void)setSubmeshes:(NSMutableArray *)s { [_subs release]; _subs = [s mutableCopy]; }
- (id<MDLMeshBufferAllocator>)allocator { return _alloc; }
- (MDLVertexDescriptor *)vertexDescriptor { return _vdesc; }

static NSUInteger mdl_layout_stride(MDLVertexDescriptor *d, NSUInteger b) {
  NSUInteger s = b < [d.layouts count] ? d.layouts[b].stride : 0;
  if (s) return s;
  for (MDLVertexAttribute *a in d.attributes)
    if (a.format != MDLVertexFormatInvalid && a.bufferIndex == b) s = MAX(s, a.offset + mdl_format_size(a.format));
  return s;
}

/* converts the vertex data to the new layout, attribute by attribute (matched by name) */
- (void)setVertexDescriptor:(MDLVertexDescriptor *)nd {
  MDLVertexDescriptor *od = _vdesc;
  if (!nd) return;
  if (!od || ![_vbufs count] || !_vcount) { [_vdesc release]; _vdesc = [nd copy]; return; }
  NSUInteger nbuf = 0;
  for (MDLVertexAttribute *a in nd.attributes)
    if (a.format != MDLVertexFormatInvalid && [a.name length]) nbuf = MAX(nbuf, a.bufferIndex + 1);
  NSMutableArray *nb = [NSMutableArray array];
  NSMutableArray *maps = [NSMutableArray array];
  for (NSUInteger b = 0; b < nbuf; b++) {
    NSUInteger st = mdl_layout_stride(nd, b);
    if (!st) { [nb addObject:[NSNull null]]; [maps addObject:[NSNull null]]; continue; }
    id<MDLMeshBuffer> buf = [_alloc newBuffer:st * _vcount type:MDLMeshBufferTypeVertex];
    [nb addObject:buf];
    [(id)buf release];
    MDLMeshBufferMap *m = [buf map];
    memset([m bytes], 0, st * _vcount);
    [maps addObject:m];
  }
  NSMutableArray *srcMaps = [NSMutableArray array];
  for (id b in _vbufs) [srcMaps addObject:b == [NSNull null] ? (id)[NSNull null] : (id)[b map]];
  for (MDLVertexAttribute *a in nd.attributes) {
    if (a.format == MDLVertexFormatInvalid || ![a.name length] || a.bufferIndex >= nbuf || [maps objectAtIndex:a.bufferIndex] == [NSNull null]) continue;
    MDLVertexAttribute *src = [od attributeNamed:a.name];
    if (src && (src.format == MDLVertexFormatInvalid || src.bufferIndex >= [srcMaps count] || [srcMaps objectAtIndex:src.bufferIndex] == [NSNull null])) src = nil;
    uint8_t *dst = (uint8_t *)[[maps objectAtIndex:a.bufferIndex] bytes] + a.offset;
    NSUInteger dstStride = mdl_layout_stride(nd, a.bufferIndex);
    const uint8_t *s = src ? (const uint8_t *)[[srcMaps objectAtIndex:src.bufferIndex] bytes] + src.offset : NULL;
    NSUInteger srcStride = src ? mdl_layout_stride(od, src.bufferIndex) : 0;
    for (NSUInteger v = 0; v < _vcount; v++)
      mdl_write(dst + v * dstStride, a.format, s ? mdl_read(s + v * srcStride, src.format) : a.initializationValue);
  }
  for (NSUInteger b = 0; b < nbuf && b < [nd.layouts count]; b++) nd.layouts[b].stride = mdl_layout_stride(nd, b);
  [_vbufs release]; _vbufs = [nb copy];
  [_vdesc release]; _vdesc = [nd copy];
}

- (MDLVertexAttributeData *)vertexAttributeDataForAttributeNamed:(NSString *)name {
  MDLVertexAttribute *a = [_vdesc attributeNamed:name];
  if (!a || a.format == MDLVertexFormatInvalid || a.bufferIndex >= [_vbufs count]) return nil;
  id<MDLMeshBuffer> b = [_vbufs objectAtIndex:a.bufferIndex];
  if ((id)b == [NSNull null]) return nil;
  MDLMeshBufferMap *m = [b map];
  return [[[MDLVertexAttributeData alloc] _xefInitWithMap:m start:(uint8_t *)[m bytes] + a.offset stride:mdl_layout_stride(_vdesc, a.bufferIndex)
                                                    format:a.format size:[b length]] autorelease];
}
- (MDLVertexAttributeData *)vertexAttributeDataForAttributeNamed:(NSString *)name asFormat:(MDLVertexFormat)f {
  return [self vertexAttributeDataForAttributeNamed:name];
}
- (MDLAxisAlignedBoundingBox)boundingBox {
  MDLAxisAlignedBoundingBox bb = {{0, 0, 0}, {0, 0, 0}};
  MDLVertexAttributeData *p = [self vertexAttributeDataForAttributeNamed:MDLVertexAttributePosition];
  for (NSUInteger v = 0; p && v < _vcount; v++) {
    vector_float4 x = mdl_read((const uint8_t *)p.dataStart + v * p.stride, p.format);
    vector_float3 q = {x.x, x.y, x.z};
    if (!v) { bb.minBounds = q; bb.maxBounds = q; }
    else { bb.minBounds = simd_min(bb.minBounds, q); bb.maxBounds = simd_max(bb.maxBounds, q); }
  }
  return bb;
}
- (void)addNormalsWithAttributeNamed:(NSString *)n creaseThreshold:(float)t {}
- (void)addTangentBasisForTextureCoordinateAttributeNamed:(NSString *)a normalAttributeNamed:(NSString *)n tangentAttributeNamed:(NSString *)t {}
- (void)addTangentBasisForTextureCoordinateAttributeNamed:(NSString *)a tangentAttributeNamed:(NSString *)t bitangentAttributeNamed:(NSString *)b {}
- (void)addOrthTanBasisForTextureCoordinateAttributeNamed:(NSString *)a normalAttributeNamed:(NSString *)n tangentAttributeNamed:(NSString *)t {}
- (void)dealloc { [_vbufs release]; [_vdesc release]; [_subs release]; [(id)_alloc release]; [super dealloc]; }

/* ---- generators: interleaved position/normal/textureCoordinate (32 bytes), 32-bit triangle indices ---- */
typedef struct { float p[3], n[3], t[2]; } MDLGenVertex;

+ (MDLMesh *)_xefMeshWithVertices:(const MDLGenVertex *)v count:(NSUInteger)nv indices:(const uint32_t *)idx count:(NSUInteger)ni
                         allocator:(id<MDLMeshBufferAllocator>)alloc inward:(BOOL)inward {
  if (!alloc) alloc = [[[MDLMeshBufferDataAllocator alloc] init] autorelease];
  NSMutableData *vd = [NSMutableData dataWithBytes:v length:nv * sizeof *v];
  NSMutableData *id_ = [NSMutableData dataWithBytes:idx length:ni * 4];
  if (inward) {
    MDLGenVertex *w = [vd mutableBytes];
    for (NSUInteger i = 0; i < nv; i++) for (int k = 0; k < 3; k++) w[i].n[k] = -w[i].n[k];
    uint32_t *t = [id_ mutableBytes];
    for (NSUInteger i = 0; i + 2 < ni; i += 3) { uint32_t s = t[i + 1]; t[i + 1] = t[i + 2]; t[i + 2] = s; }
  }
  id<MDLMeshBuffer> vb = [alloc newBufferWithData:vd type:MDLMeshBufferTypeVertex];
  id<MDLMeshBuffer> ib = [alloc newBufferWithData:id_ type:MDLMeshBufferTypeIndex];
  MDLVertexDescriptor *d = [[[MDLVertexDescriptor alloc] init] autorelease];
  d.attributes[0].name = MDLVertexAttributePosition; d.attributes[0].format = MDLVertexFormatFloat3; d.attributes[0].offset = 0;
  d.attributes[1].name = MDLVertexAttributeNormal; d.attributes[1].format = MDLVertexFormatFloat3; d.attributes[1].offset = 12;
  d.attributes[2].name = MDLVertexAttributeTextureCoordinate; d.attributes[2].format = MDLVertexFormatFloat2; d.attributes[2].offset = 24;
  d.layouts[0].stride = sizeof(MDLGenVertex);
  MDLSubmesh *s = [[[MDLSubmesh alloc] initWithIndexBuffer:ib indexCount:ni indexType:MDLIndexBitDepthUInt32
                                              geometryType:MDLGeometryTypeTriangles material:nil] autorelease];
  MDLMesh *m = [[MDLMesh alloc] initWithVertexBuffers:@[vb] vertexCount:nv descriptor:d submeshes:@[s]];
  [(id)m->_alloc release]; m->_alloc = [(id)alloc retain];
  [(id)vb release]; [(id)ib release];
  return m;   /* +1, "new" family */
}

/* one face: corner grid along u/v with normal n */
static void mdl_face(NSMutableData *vs, NSMutableData *is, vector_float3 c, vector_float3 u, vector_float3 v, vector_float3 n, unsigned su, unsigned sv) {
  su = MAX(su, 1u); sv = MAX(sv, 1u);
  uint32_t base = (uint32_t)([vs length] / sizeof(MDLGenVertex));
  for (unsigned j = 0; j <= sv; j++)
    for (unsigned i = 0; i <= su; i++) {
      float fu = (float)i / su, fv = (float)j / sv;
      vector_float3 p = c + u * (fu - 0.5f) + v * (fv - 0.5f);
      MDLGenVertex x = {{p.x, p.y, p.z}, {n.x, n.y, n.z}, {fu, 1.0f - fv}};
      [vs appendBytes:&x length:sizeof x];
    }
  for (unsigned j = 0; j < sv; j++)
    for (unsigned i = 0; i < su; i++) {
      uint32_t a = base + j * (su + 1) + i, b = a + 1, d = a + (su + 1), e = d + 1;
      uint32_t t[6] = {a, b, e, a, e, d};
      [is appendBytes:t length:sizeof t];
    }
}

+ (instancetype)newBoxWithDimensions:(vector_float3)dims segments:(vector_uint3)seg geometryType:(MDLGeometryType)g
                       inwardNormals:(BOOL)inward allocator:(id<MDLMeshBufferAllocator>)alloc {
  NSMutableData *vs = [NSMutableData data], *is = [NSMutableData data];
  vector_float3 h = dims * 0.5f;
  mdl_face(vs, is, (vector_float3){h.x, 0, 0}, (vector_float3){0, 0, -dims.z}, (vector_float3){0, dims.y, 0}, (vector_float3){1, 0, 0}, seg.z, seg.y);
  mdl_face(vs, is, (vector_float3){-h.x, 0, 0}, (vector_float3){0, 0, dims.z}, (vector_float3){0, dims.y, 0}, (vector_float3){-1, 0, 0}, seg.z, seg.y);
  mdl_face(vs, is, (vector_float3){0, h.y, 0}, (vector_float3){dims.x, 0, 0}, (vector_float3){0, 0, -dims.z}, (vector_float3){0, 1, 0}, seg.x, seg.z);
  mdl_face(vs, is, (vector_float3){0, -h.y, 0}, (vector_float3){dims.x, 0, 0}, (vector_float3){0, 0, dims.z}, (vector_float3){0, -1, 0}, seg.x, seg.z);
  mdl_face(vs, is, (vector_float3){0, 0, h.z}, (vector_float3){dims.x, 0, 0}, (vector_float3){0, dims.y, 0}, (vector_float3){0, 0, 1}, seg.x, seg.y);
  mdl_face(vs, is, (vector_float3){0, 0, -h.z}, (vector_float3){-dims.x, 0, 0}, (vector_float3){0, dims.y, 0}, (vector_float3){0, 0, -1}, seg.x, seg.y);
  return [self _xefMeshWithVertices:[vs bytes] count:[vs length] / sizeof(MDLGenVertex) indices:[is bytes] count:[is length] / 4 allocator:alloc inward:inward];
}
+ (instancetype)newPlaneWithDimensions:(vector_float2)dims segments:(vector_uint2)seg geometryType:(MDLGeometryType)g
                             allocator:(id<MDLMeshBufferAllocator>)alloc {
  NSMutableData *vs = [NSMutableData data], *is = [NSMutableData data];
  mdl_face(vs, is, (vector_float3){0, 0, 0}, (vector_float3){dims.x, 0, 0}, (vector_float3){0, 0, -dims.y}, (vector_float3){0, 1, 0}, seg.x, seg.y);
  return [self _xefMeshWithVertices:[vs bytes] count:[vs length] / sizeof(MDLGenVertex) indices:[is bytes] count:[is length] / 4 allocator:alloc inward:NO];
}
+ (instancetype)newEllipsoidWithRadii:(vector_float3)r radialSegments:(NSUInteger)rs verticalSegments:(NSUInteger)vs_
                          geometryType:(MDLGeometryType)g inwardNormals:(BOOL)inward hemisphere:(BOOL)hemi
                             allocator:(id<MDLMeshBufferAllocator>)alloc {
  NSMutableData *vs = [NSMutableData data], *is = [NSMutableData data];
  rs = MAX(rs, (NSUInteger)3); vs_ = MAX(vs_, (NSUInteger)2);
  float vmax = hemi ? (float)M_PI_2 : (float)M_PI;
  for (NSUInteger j = 0; j <= vs_; j++)
    for (NSUInteger i = 0; i <= rs; i++) {
      float th = vmax * j / vs_, ph = 2.0f * (float)M_PI * i / rs;
      vector_float3 n = {sinf(th) * cosf(ph), cosf(th), -sinf(th) * sinf(ph)};
      vector_float3 p = n * r;
      vector_float3 nn = simd_normalize(n / (r * r + 1e-12f));
      MDLGenVertex x = {{p.x, p.y, p.z}, {nn.x, nn.y, nn.z}, {(float)i / rs, (float)j / vs_}};
      [vs appendBytes:&x length:sizeof x];
    }
  for (NSUInteger j = 0; j < vs_; j++)
    for (NSUInteger i = 0; i < rs; i++) {
      uint32_t a = (uint32_t)(j * (rs + 1) + i), b = a + 1, c = a + (uint32_t)(rs + 1), d = c + 1;
      uint32_t t[6] = {a, c, b, b, c, d};
      [is appendBytes:t length:sizeof t];
    }
  return [self _xefMeshWithVertices:[vs bytes] count:[vs length] / sizeof(MDLGenVertex) indices:[is bytes] count:[is length] / 4 allocator:alloc inward:inward];
}
+ (instancetype)newIcosahedronWithRadius:(float)r inwardNormals:(BOOL)inward allocator:(id<MDLMeshBufferAllocator>)alloc {
  return [self newEllipsoidWithRadii:(vector_float3){r, r, r} radialSegments:12 verticalSegments:6 geometryType:MDLGeometryTypeTriangles
                       inwardNormals:inward hemisphere:NO allocator:alloc];
}
@end
