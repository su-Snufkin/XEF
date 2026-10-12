// XEF — code cache, block metadata, guest-PC → host-code map, IBTC.
#pragma once
#include <atomic>
#include <mutex>

#include "common/common.h"

namespace xef {

struct BlockMeta;

// Host code offset -> guest instruction, recorded at every guest memory access (fault mapping).
struct PcMapEntry {
    u32 host_off;      // offset of the host instruction from BlockMeta::code
    u16 guest_off;     // guest pc - BlockMeta::start
    u16 borrowed;      // host regs borrowed as temporaries: their guest value is in CpuState
    u8 flags_loc;      // where the guest NZCV is: PCF_EFLAGS / PCF_SPILL / PCF_UNKNOWN
    u8 pad[3];
};
enum : u8 { PCF_EFLAGS = 0, PCF_SPILL = 1, PCF_UNKNOWN = 2 };

// Runtime feedback for a tier-2 region.
struct RegionInfo {
    BlockMeta* head_t1;   // tier-1 version of the head (for demotion)
    BlockMeta* entry;     // published region entry
    u64* exit_counter;    // incremented (flag-free) by every region exit stub; lives in the code cache
    u64 samples;
    bool demoted;
    u8* sig_exit;         // region -> canonical transfer + exit_to_runtime (signal delivery)
    u8 map[32];           // region register mapping: guest reg -> host reg (0xff: CpuState)
};

enum ExitKind : u8 {
    EK_JMP = 0,     // jmp rel32 site
    EK_JCC = 1,     // jcc rel32 site
    EK_CALL = 2,    // call rel32 site (BL)
};

// One patchable direct exit of a translated block.
struct ExitInfo {
    u8* site;              // address of the rel32 field
    u8* stub;              // unlinked target (link stub)
    GuestAddr target;
    BlockMeta* owner;
    ExitInfo* next_in;     // intrusive list of exits linked INTO a block (for unlinking)
    u8 kind;
    u8 linked;
};

struct BlockMeta {
    GuestAddr start;
    GuestAddr end;
    u8* code;
    u32 code_size;
    u16 nexits;
    u8 tier;
    u8 flags;
    ExitInfo* incoming;    // exits from other blocks that jump here
    BlockMeta* next_on_page;  // chained per guest page for invalidation
    u64 exec_count;
    struct RegionInfo* region;   // tier-2 blocks: owning region
    u32 host_pc_map_off;   // offset of host→guest pc map (for faults)
    u32 host_pc_map_len;
    ExitInfo exits[];
};

// Indirect branch target cache: direct-mapped, 16K entries, probed inline by JIT code.
struct IbtcEntry {
    u64 guest;   // odd value (1) = empty
    u64 host;
};
constexpr int kIbtcEntries = 16384;

struct RuntimeStubs {
    u8* enter;               // void enter(CpuState*, void* host) — C ABI
    u8* exit_to_runtime;     // save state, return to C++ (reason already stored)
    u8* link_stub;           // rax = ExitInfo*
    u8* ibtc_miss;           // rax = guest target
    u8* syscall_exit;        // rax = next pc
};

class CodeCache {
public:
    void init(size_t size);
    u8* alloc_code(size_t max_size);          // returns write pointer (caller commits)
    // Mutable data reachable RIP-relatively from code but on separate pages (writes near
    // executing code trigger self-modifying-code machine clears).
    u8* alloc_data(size_t size);
    void commit_code(u8* start, size_t used);
    BlockMeta* alloc_meta(int nexits);

    // guest pc -> block (lock-free read)
    BlockMeta* lookup(GuestAddr pc) const {
        u64 i1 = (pc >> 24) & ((1ull << 24) - 1);
        BlockMeta** l2 = l1_[i1].load(std::memory_order_acquire);
        if (!l2) return nullptr;
        return __atomic_load_n(&l2[(pc >> 2) & ((1u << 22) - 1)], __ATOMIC_ACQUIRE);
    }
    void publish(BlockMeta* b);
    void unpublish(GuestAddr pc);

    void ibtc_insert(IbtcEntry* table, GuestAddr pc, u8* host) {
        IbtcEntry& e = table[(pc >> 2) & (kIbtcEntries - 1)];
        __atomic_store_n(&e.guest, 1ull, __ATOMIC_RELAXED);
        __atomic_store_n(&e.host, (u64)host, __ATOMIC_RELEASE);
        __atomic_store_n(&e.guest, pc, __ATOMIC_RELEASE);
    }
    IbtcEntry* new_ibtc();

    bool contains(const void* p) const { return (const u8*)p >= base_ && (const u8*)p < base_ + size_; }
    u8* base() const { return base_; }
    size_t used() const { return code_ptr_ - base_; }

    // host code address -> block (blocks are allocated with increasing code addresses)
    BlockMeta* find_by_host(const u8* p) const;
    void register_block(BlockMeta* b);

    // per-block host->guest pc maps
    void set_pcmap(BlockMeta* b, const PcMapEntry* e, int n);
    const PcMapEntry* find_pc(const BlockMeta* b, const u8* host) const;

    std::mutex lock;   // serializes translation / linking (off the hot path)
    RuntimeStubs stubs;

private:
    u8* base_ = nullptr;
    size_t size_ = 0;
    u8* code_ptr_ = nullptr;
    u8* data_ptr_ = nullptr;
    u8* data_end_ = nullptr;
    std::mutex data_lock_;
    u8* meta_base_ = nullptr;
    u8* meta_ptr_ = nullptr;
    u8* meta_end_ = nullptr;
    std::atomic<BlockMeta**>* l1_ = nullptr;
    BlockMeta** by_host_ = nullptr;
    size_t nby_host_ = 0, cap_by_host_ = 0;
    PcMapEntry* pcmap_ = nullptr;
    u32 npcmap_ = 0, cap_pcmap_ = 0;
    std::mutex pcmap_lock_;
};

extern CodeCache g_cache;

// Patches a direct exit to jump to `host` (atomic 4-byte store).
void link_exit(ExitInfo* e, u8* host);

}  // namespace xef
