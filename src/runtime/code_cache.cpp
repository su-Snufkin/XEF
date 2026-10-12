#include "runtime/code_cache.h"

#include <sys/mman.h>

#include "backend/x64/assembler.h"
#include "runtime/cpu_state.h"

namespace xef {

CodeCache g_cache;

void CodeCache::init(size_t size) {
    size_ = size;
    void* p = mmap(nullptr, size, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    if (p == MAP_FAILED) fatal("cannot allocate code cache (%zu MB)", size >> 20);
    base_ = (u8*)p;
    // first 16 MB: data area (counters etc.), code starts after it
    data_ptr_ = base_;
    data_end_ = base_ + (16u << 20);
    code_ptr_ = data_end_;
    size_t meta_size = size / 2;
    void* m = mmap(nullptr, meta_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    if (m == MAP_FAILED) fatal("cannot allocate block metadata");
    meta_base_ = meta_ptr_ = (u8*)m;
    meta_end_ = meta_base_ + meta_size;
    size_t l1_size = sizeof(std::atomic<BlockMeta**>) << 24;
    void* l1 = mmap(nullptr, l1_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    if (l1 == MAP_FAILED) fatal("cannot allocate block map");
    l1_ = (std::atomic<BlockMeta**>*)l1;
}

u8* CodeCache::alloc_code(size_t max_size) {
    if (code_ptr_ + max_size > base_ + size_) fatal("code cache full (flush not implemented yet)");
    return code_ptr_;
}

u8* CodeCache::alloc_data(size_t size) {
    std::lock_guard<std::mutex> g(data_lock_);
    u8* p = (u8*)align_up((uintptr_t)data_ptr_, (uintptr_t)64);  // own cache line
    if (p + size > data_end_) fatal("code cache data area full");
    data_ptr_ = p + align_up(size, (size_t)64);
    return p;
}

void CodeCache::commit_code(u8* start, size_t used) {
    code_ptr_ = (u8*)align_up((uintptr_t)(start + used), (uintptr_t)16);
}

BlockMeta* CodeCache::alloc_meta(int nexits) {
    size_t sz = align_up(sizeof(BlockMeta) + sizeof(ExitInfo) * nexits, (size_t)16);
    if (meta_ptr_ + sz > meta_end_) fatal("block metadata full");
    BlockMeta* b = (BlockMeta*)meta_ptr_;
    meta_ptr_ += sz;
    memset(b, 0, sz);
    b->nexits = (u16)nexits;
    return b;
}

void CodeCache::publish(BlockMeta* b) {
    GuestAddr pc = b->start;
    u64 i1 = (pc >> 24) & ((1ull << 24) - 1);
    BlockMeta** l2 = l1_[i1].load(std::memory_order_acquire);
    if (!l2) {
        void* p = mmap(nullptr, sizeof(BlockMeta*) << 22, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
        if (p == MAP_FAILED) fatal("block map l2");
        l2 = (BlockMeta**)p;
        l1_[i1].store(l2, std::memory_order_release);
    }
    __atomic_store_n(&l2[(pc >> 2) & ((1u << 22) - 1)], b, __ATOMIC_RELEASE);
}

void CodeCache::unpublish(GuestAddr pc) {
    u64 i1 = (pc >> 24) & ((1ull << 24) - 1);
    BlockMeta** l2 = l1_[i1].load(std::memory_order_acquire);
    if (l2) __atomic_store_n(&l2[(pc >> 2) & ((1u << 22) - 1)], nullptr, __ATOMIC_RELEASE);
}

IbtcEntry* CodeCache::new_ibtc() {
    void* p = mmap(nullptr, sizeof(IbtcEntry) * kIbtcEntries, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) fatal("ibtc alloc");
    IbtcEntry* t = (IbtcEntry*)p;
    for (int i = 0; i < kIbtcEntries; i++) { t[i].guest = 1; t[i].host = 0; }
    std::lock_guard<std::mutex> g(ibtc_lock_);
    ibtcs_.push_back(t);
    return t;
}

void CodeCache::register_block(BlockMeta* b) {
    // fixed-size index (no reallocation: read lock-free from the SIGPROF sampler)
    if (!by_host_) {
        cap_by_host_ = 1 << 24;
        void* p = mmap(nullptr, cap_by_host_ * sizeof(BlockMeta*), PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
        if (p == MAP_FAILED) fatal("block index alloc");
        by_host_ = (BlockMeta**)p;
    }
    if (nby_host_ >= cap_by_host_) fatal("block index full");
    by_host_[nby_host_] = b;
    __atomic_store_n(&nby_host_, nby_host_ + 1, __ATOMIC_RELEASE);
}

BlockMeta* CodeCache::find_by_host(const u8* p) const {
    size_t lo = 0, hi = __atomic_load_n(&nby_host_, __ATOMIC_ACQUIRE);
    while (lo < hi) {
        size_t mid = (lo + hi) / 2;
        if (by_host_[mid]->code <= p) lo = mid + 1; else hi = mid;
    }
    if (lo == 0) return nullptr;
    BlockMeta* b = by_host_[lo - 1];
    // stubs follow the body; accept anything up to the next block
    return b;
}

void CodeCache::set_pcmap(BlockMeta* b, const PcMapEntry* e, int n) {
    std::lock_guard<std::mutex> g(pcmap_lock_);
    if (!pcmap_) {
        cap_pcmap_ = 1u << 26;
        void* p = mmap(nullptr, (size_t)cap_pcmap_ * sizeof(PcMapEntry), PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
        if (p == MAP_FAILED) fatal("pc map alloc");
        pcmap_ = (PcMapEntry*)p;
    }
    if (npcmap_ + (u32)n > cap_pcmap_) { b->host_pc_map_len = 0; return; }  // degrade: no fault mapping
    memcpy(pcmap_ + npcmap_, e, sizeof(PcMapEntry) * n);
    b->host_pc_map_off = npcmap_;
    b->host_pc_map_len = (u32)n;
    npcmap_ += (u32)n;
}

// Last recorded access at or before `host` (entries are in increasing host order). Called from
// signal handlers: no locks, the entries of a published block never change.
const PcMapEntry* CodeCache::find_pc(const BlockMeta* b, const u8* host) const {
    if (!pcmap_ || !b->host_pc_map_len || host < b->code) return nullptr;
    u32 off = (u32)(host - b->code);
    const PcMapEntry* best = nullptr;
    for (u32 i = 0; i < b->host_pc_map_len; i++) {
        const PcMapEntry& e = pcmap_[b->host_pc_map_off + i];
        if (e.host_off > off) break;
        best = &e;
    }
    return best;
}

// ------------------------------------------------------------------ invalidation

void CodeCache::add_deps(BlockMeta* b, GuestAddr lo, GuestAddr hi, const PeekLog* peeks) {
    auto add = [&](GuestAddr l, GuestAddr h) {
        if (h <= l) return;
        for (u64 pg = l >> 12; pg <= (h - 1) >> 12; pg++) deps_[pg].push_back({b, l, h});
    };
    add(lo, hi);
    if (peeks)
        for (int i = 0; i < peeks->n; i++) add(peeks->r[i].lo, peeks->r[i].hi);
}

bool CodeCache::invalidate_range(GuestAddr lo, GuestAddr hi) {
    epoch.fetch_add(1, std::memory_order_seq_cst);
    if (hi <= lo || deps_.empty()) return false;
    bool found = false;
    auto scan = [&](std::vector<Dep>& v) {
        size_t k = 0;
        for (size_t i = 0; i < v.size(); i++) {
            Dep d = v[i];
            if (d.b->flags & BF_DEAD) continue;          // drop stale entries
            if (d.lo < hi && d.hi > lo) { invalidate_block(d.b); found = true; continue; }
            v[k++] = d;
        }
        v.resize(k);
    };
    u64 first = lo >> 12, last = (hi - 1) >> 12;
    if (last - first + 1 > deps_.size()) {
        for (auto it = deps_.begin(); it != deps_.end();) {
            if (it->first >= first && it->first <= last) scan(it->second);
            if (it->second.empty()) it = deps_.erase(it); else ++it;
        }
    } else {
        for (u64 pg = first; pg <= last; pg++) {
            auto it = deps_.find(pg);
            if (it == deps_.end()) continue;
            scan(it->second);
            if (it->second.empty()) deps_.erase(it);
        }
    }
    return found;
}

void CodeCache::invalidate_block(BlockMeta* b) {
    if (b->flags & BF_DEAD) return;
    b->flags |= BF_DEAD;
    if (lookup(b->start) == b) unpublish(b->start);
    // exits of other blocks that jump here go back to their link stubs
    for (ExitInfo* e = b->incoming; e; e = e->next_in) {
        i32 rel = (i32)(e->stub - (e->site + 4));
        __atomic_store_n((i32*)e->site, rel, __ATOMIC_RELEASE);
        e->linked = 0;
    }
    b->incoming = nullptr;
    if (b->region) kill_region(b->region);
}

// A region jumps between its blocks directly, so a thread may stay inside it indefinitely. Every
// jump to a member block is retargeted (atomic store of its rel32) to a stub that leaves
// through the region's exit path; the runtime then re-dispatches at that block's guest pc.
// Code itself is never rewritten: other threads may be executing it.
void CodeCache::kill_region(RegionInfo* ri) {
    if (ri->killed) return;
    ri->killed = true;
    ri->demoted = true;
    invalidate_block(ri->entry);
    if (ri->head_t1 && lookup(ri->head_t1->start) == ri->head_t1) unpublish(ri->head_t1->start);
    u8* stub[64];
    for (int i = 0; i < ri->nblocks && i < 64; i++) {
        BlockMeta* m = ri->blocks[i];
        m->flags |= BF_DEAD;
        u8* s = alloc_code(64);
        x64::Assembler as(s, 64);
        as.mov_imm(x64::RAX, m->start);   // rax is free at block boundaries
        as.mov(8, x64::mem(x64::R15, XEF_ST(pc)), x64::RAX);
        as.mov_imm(8, x64::mem(x64::R15, XEF_ST(exit_reason)), EXIT_LOOKUP);
        as.jmp_rel32(ri->sig_exit);
        commit_code(s, as.size());
        stub[i] = s;
    }
    for (int k = 0; k < ri->nbranches; k++) {
        const RegionInfo::Branch& br = ri->branches[k];
        i32 rel = (i32)(stub[br.target] - (br.field + 4));
        __atomic_store_n((i32*)br.field, rel, __ATOMIC_SEQ_CST);   // within one cache line: atomic
    }
}

void CodeCache::scrub_ibtcs() {
    std::lock_guard<std::mutex> g(ibtc_lock_);
    for (IbtcEntry* t : ibtcs_)
        for (int i = 0; i < kIbtcEntries; i++) {
            GuestAddr pc = __atomic_load_n(&t[i].guest, __ATOMIC_ACQUIRE);
            if (pc == 1) continue;
            BlockMeta* b = lookup(pc);
            if (!b || b->code != (u8*)__atomic_load_n(&t[i].host, __ATOMIC_ACQUIRE))
                __atomic_store_n(&t[i].guest, 1ull, __ATOMIC_RELEASE);
        }
}

void link_exit(ExitInfo* e, u8* host) {
    // The rel32 field is 4-byte aligned, so this store is atomic w.r.t. concurrent execution.
    i32 rel = (i32)(host - (e->site + 4));
    __atomic_store_n((i32*)e->site, rel, __ATOMIC_RELEASE);
    e->linked = 1;
}

}  // namespace xef
