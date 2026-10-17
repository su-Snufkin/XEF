// Contract between the Metal shader compiler (mtlc/, process xef-mtlc) and the Metal->Vulkan engine (src/metal/).
//
// Resource model of the generated SPIR-V:
//  - device/constant memory is reached through 64-bit buffer device addresses (PhysicalStorageBuffer64);
//    MTLBuffer.gpuAddress is the Vulkan buffer device address, so argument buffers work unchanged.
//  - textures and samplers live in bindless arrays in descriptor set 0; a texture/sampler "handle"
//    (MTLResourceID) is its index in those arrays.
//  - each stage reads its Metal argument table (buffer addresses / resource ids, 8 bytes per entry) from
//    device memory; the push constants hold the table address of every stage.
#pragma once
#include <cstdint>

namespace xef::mtlabi {

constexpr uint32_t kProtoMagic = 0x43544D58;   // "XMTC"
constexpr uint32_t kProtoVersion = 4;

enum Stage : uint32_t { STAGE_VERTEX = 0, STAGE_FRAGMENT = 1, STAGE_KERNEL = 2 };

// ---- descriptor set 0 ----
enum ImgDim : uint32_t {
    DIM_1D, DIM_1D_ARRAY, DIM_2D, DIM_2D_ARRAY, DIM_2D_MS, DIM_2D_MS_ARRAY, DIM_3D, DIM_CUBE, DIM_CUBE_ARRAY, DIM_BUFFER,
    DIM_COUNT
};
enum ImgComp : uint32_t { COMP_FLOAT, COMP_SINT, COMP_UINT, COMP_COUNT };
constexpr uint32_t sampled_image_binding(uint32_t dim, uint32_t comp) { return dim * COMP_COUNT + comp; }
constexpr uint32_t kNumImageBindings = (uint32_t)DIM_COUNT * (uint32_t)COMP_COUNT;
constexpr uint32_t storage_image_binding(uint32_t dim, uint32_t comp) { return kNumImageBindings + dim * COMP_COUNT + comp; }
constexpr uint32_t kSamplerBinding = 2 * kNumImageBindings;   // 60
constexpr uint32_t kNumBindings = kSamplerBinding + 1;

// array sizes of the bindless bindings (the engine allocates resource ids below these limits)
constexpr uint32_t kMaxTextures = 16384;
constexpr uint32_t kMaxSamplers = 2048;

// ---- push constants (shared by all stages) ----
struct PushConstants {
    uint64_t table[2];      // argument table address: [0] vertex or kernel, [1] fragment
    uint32_t grid[3];       // kernel: threads per grid (dispatchThreads) - partial threadgroups are masked
    uint32_t flags;         // PC_FLAG_*
    uint32_t base_instance; // vertex: value of [[base_instance]] / [[base_vertex]] when not natively available
    uint32_t base_vertex;
    uint32_t pad[2];
};
static_assert(sizeof(PushConstants) == 48, "push constant layout");
constexpr uint32_t kPushConstantSize = sizeof(PushConstants);
enum : uint32_t { PC_FLAG_GRID_BOUNDS = 1 };

// ---- argument table entries ----
enum BindKind : uint8_t {
    BIND_BUFFER = 1,        // value: gpu address of [[buffer(index)]] (+ bind offset)
    BIND_TEXTURE = 2,       // value: resource id of [[texture(index)]]
    BIND_SAMPLER = 3,       // value: resource id of [[sampler(index)]]
    BIND_CONST_SAMPLER = 4, // value: resource id of the engine-created constexpr sampler #index
    BIND_CONST_DATA = 5,    // value: gpu address of the pipeline's constant data blob
    BIND_BUFFER_SIZE = 6,   // value: byte length of [[buffer(index)]] (for bounds / array length queries)
};
struct TableEntry {
    uint8_t kind;           // BindKind
    uint8_t stage_flags;    // reserved
    uint16_t index;         // Metal binding index / const sampler number
    uint32_t offset;        // byte offset in the table (8-byte entries)
};

// constexpr sampler state decoded from AIR (Metal enum values)
struct ConstSampler {
    uint8_t s_address, t_address, r_address;   // MTLSamplerAddressMode
    uint8_t min_filter, mag_filter, mip_filter; // MTLSamplerMinMagFilter / MTLSamplerMipFilter
    uint8_t normalized;                         // 1 = normalized coordinates
    uint8_t compare;                            // MTLCompareFunction (0 = never/none)
    uint8_t max_aniso;
    uint8_t border;                             // MTLSamplerBorderColor
    uint16_t pad;
    float lod_min, lod_max;
};

enum BaseType : uint8_t { BT_FLOAT = 0, BT_HALF, BT_INT, BT_UINT, BT_SHORT, BT_USHORT, BT_CHAR, BT_UCHAR, BT_BOOL, BT_OTHER };

struct VertexAttrib { uint32_t location; uint8_t base; uint8_t comps; uint16_t pad; };
struct ColorOutput { uint32_t location; uint8_t index; uint8_t base; uint8_t comps; uint8_t pad; };

enum StageFlags : uint32_t {
    SF_DISCARD = 1, SF_WRITES_DEPTH = 2, SF_EARLY_FRAGMENT_TESTS = 4, SF_WRITES_STENCIL = 8, SF_WRITES_SAMPLE_MASK = 16,
    SF_USES_BARRIER = 32, SF_GRID_BOUNDS = 64, SF_POINT_SIZE = 128, SF_HAS_POSITION = 256,
};

// ---- wire protocol (xef <-> xef-mtlc over pipes) ----
// message: u32 magic, u32 type, u32 length, payload[length]
enum MsgType : uint32_t {
    MSG_COMPILE = 1,        // request: see CompileRequest serialization in mtlc/protocol.h
    MSG_RESULT = 2,
    MSG_PING = 3,
    MSG_QUIT = 4,
};

} // namespace xef::mtlabi
