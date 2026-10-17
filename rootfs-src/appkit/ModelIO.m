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
