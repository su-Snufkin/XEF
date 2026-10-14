// XEF — code cache, block metadata, guest-PC → host-code map, IBTC.
#pragma once
#include <atomic>
#include <mutex>
#include <vector>

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
    u8 vmap[32];          // region vector mapping: guest V reg -> host Xmm (0xff: CpuState)
    BlockMeta** blocks;   // member blocks (tier 2 code)
    int nblocks;
    struct Branch { u8* field; int target; };   // aligned rel32 of jumps to member blocks
    Branch* branches;
    int nbranches;
    bool killed;          // invalidated: member blocks are patched to leave the region
    u64* call_counter;    // calls made from inside the region (each pays two register transfers)
    u32 call_moves;       // cost of one such call in moves: transfers + 16 (cost model for evict_region)
};

// Guest code range a translation depends on (its own instructions or decode-ahead).
struct GuestRange {
    GuestAddr lo, hi;
};

// Collects the guest ranges read by decode-ahead (NZCV liveness) while translating.
struct PeekLog {
    static constexpr int kMax = 32;
    GuestRange r[kMax];
    int n = 0;
    int last = 0;   // range merged into most recently (the lookahead peeks consecutive instructions)
    bool overflow = false;
    void reset() { n = 0; last = 0; overflow = false; }
    void add(GuestAddr lo, GuestAddr hi) {
        if (last < n && lo <= r[last].hi && hi >= r[last].lo) {
            if (lo < r[last].lo) r[last].lo = lo;
            if (hi > r[last].hi) r[last].hi = hi;
            return;
        }
        for (int i = 0; i < n; i++)
            if (lo <= r[i].hi && hi >= r[i].lo) {   // merge touching ranges
                if (lo < r[i].lo) r[i].lo = lo;
                if (hi > r[i].hi) r[i].hi = hi;
                last = i;
                return;
            }
        if (n == kMax) {
            // full: widen the range that grows least (a superset only costs extra invalidations)
            int best = 0;
            u64 best_cost = ~0ull;
            for (int i = 0; i < n; i++) {
                GuestAddr nlo = lo < r[i].lo ? lo : r[i].lo, nhi = hi > r[i].hi ? hi : r[i].hi;
                u64 cost = (nhi - nlo) - (r[i].hi - r[i].lo);
                if (cost < best_cost) { best_cost = cost; best = i; }
            }
            if (best_cost > (1u << 20)) { overflow = true; return; }   // far apart: give up instead
            if (lo < r[best].lo) r[best].lo = lo;
            if (hi > r[best].hi) r[best].hi = hi;
            last = best;
            return;
        }
        last = n;
        r[n++] = {lo, hi};
    }
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

enum : u8 { BF_DEAD = 1, BF_DEMOTED_ONCE = 2, BF_NOCALLS = 4 };   // BlockMeta::flags (NOCALLS: region head, form regions without calls)

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
    BlockMeta* chain_prev;   // tier-1 chain member whose code falls through into this one (no exit)
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
    IbtcEntry* init_ibtc(void* mem);   // kIbtcBytes at mem (after the thread's CpuState)

    bool contains(const void* p) const { return (const u8*)p >= base_ && (const u8*)p < base_ + size_; }
    u8* base() const { return base_; }
    size_t used() const { return code_ptr_ - base_; }

    // host code address -> block (blocks are allocated with increasing code addresses)
    BlockMeta* find_by_host(const u8* p) const;
    void register_block(BlockMeta* b);

    // per-block host->guest pc maps
    void set_pcmap(BlockMeta* b, const PcMapEntry* e, int n);
    const PcMapEntry* find_pc(const BlockMeta* b, const u8* host) const;

    // ---- code page filter (lock-free) ----
    // One bit per 64 KiB of guest address space: set before a translation of code there can be
    // published (bits are never cleared). Cache maintenance on ranges without any bit set has
    // nothing to invalidate; JITs flush every cache line they write (SpiderMonkey, V8).
    // Protocol: a translator marks its ranges, THEN re-checks `epoch`; an invalidator bumps
    // `epoch`, THEN tests the bits. Either the translator sees the new epoch (and decodes
    // again) or the invalidator sees the bit (and takes `lock`).
    void mark_code(GuestAddr lo, GuestAddr hi);
    void mark_code(GuestAddr lo, GuestAddr hi, const PeekLog* peeks) {
        mark_code(lo, hi);
        for (int i = 0; peeks && i < peeks->n; i++) mark_code(peeks->r[i].lo, peeks->r[i].hi);
    }
    bool may_have_code(GuestAddr lo, GuestAddr hi) const;

    // ---- invalidation (all with `lock` held) ----
    // Records that `b` depends on guest code in [lo, hi) (its body) and on the peeked ranges.
    void add_deps(BlockMeta* b, GuestAddr lo, GuestAddr hi, const PeekLog* peeks);
    // ... on every range in `ranges` (which must not have overflowed)
    void add_deps(BlockMeta* b, const PeekLog& ranges);
    // Kills every translation depending on [lo, hi). Returns true if any was found.
    bool invalidate_range(GuestAddr lo, GuestAddr hi);
    void invalidate_block(BlockMeta* b);
    // Makes threads leave a live region (as when it is killed) and re-publishes its tier-1 head.
    void evict_region(RegionInfo* ri);
    // Drops IBTC entries of the blocks killed since the last scrub (after invalidation).
    void scrub_ibtcs();
    // Drops IBTC entries for pc at the next scrub_ibtcs (its block was replaced: region entry).
    void forget_ibtc(GuestAddr pc) { killed_.push_back(pc); }
    // Bumped by every invalidation: translations that started earlier must not be published.
    std::atomic<u64> epoch{0};

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
    u64* code_pages_ = nullptr;   // mark_code bitmap
    BlockMeta** by_host_ = nullptr;
    size_t nby_host_ = 0, cap_by_host_ = 0;
    // guest page -> translations depending on it: an open-addressing table of list heads into a
    // node pool (a hash map of vectors cost a hash division and a vector reallocation per block)
    struct DepNode { BlockMeta* b; GuestAddr lo, hi; u32 next; };   // next: 0 = end of list
    struct DepPage { u64 page; u32 head; };                          // page ~0: empty (never removed)
    std::vector<DepNode> dep_nodes_;   // [0] unused
    u32 dep_free_ = 0;                 // free nodes, linked through next
    size_t dep_live_ = 0;              // nodes in page lists
    std::vector<DepPage> dep_pages_;   // power-of-two size, at most half full
    size_t dep_npages_ = 0;
    u32* dep_head(u64 page, bool create);
    void add_dep_range(BlockMeta* b, GuestAddr lo, GuestAddr hi);
    void kill_region(RegionInfo* ri);
    std::vector<IbtcEntry*> ibtcs_;
    std::vector<GuestAddr> killed_;   // start pcs of blocks killed since the last scrub_ibtcs
    std::mutex ibtc_lock_;
    PcMapEntry* pcmap_ = nullptr;
    u32 npcmap_ = 0, cap_pcmap_ = 0;
    std::mutex pcmap_lock_;
};

extern CodeCache g_cache;

// Patches a direct exit to jump to `host` (atomic 4-byte store).
void link_exit(ExitInfo* e, u8* host);

}  // namespace xef
