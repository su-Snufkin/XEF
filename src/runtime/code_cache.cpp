#include "runtime/code_cache.h"

#include <sys/mman.h>

#include "backend/x64/assembler.h"

namespace xef {

CodeCache g_cache;

void CodeCache::init(size_t size) {
    size_ = size;
    void* p = mmap(nullptr, size, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    if (p == MAP_FAILED) fatal("cannot allocate code cache (%zu MB)", size >> 20);
    base_ = code_ptr_ = (u8*)p;
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
    return t;
}

void CodeCache::register_block(BlockMeta* b) {
    if (nby_host_ == cap_by_host_) {
        size_t nc = cap_by_host_ ? cap_by_host_ * 2 : 65536;
        void* p = mmap(nullptr, nc * sizeof(BlockMeta*), PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (p == MAP_FAILED) fatal("block index alloc");
        if (by_host_) { memcpy(p, by_host_, nby_host_ * sizeof(BlockMeta*)); munmap(by_host_, cap_by_host_ * sizeof(BlockMeta*)); }
        by_host_ = (BlockMeta**)p;
        cap_by_host_ = nc;
    }
    by_host_[nby_host_++] = b;
}

BlockMeta* CodeCache::find_by_host(const u8* p) const {
    size_t lo = 0, hi = nby_host_;
    while (lo < hi) {
        size_t mid = (lo + hi) / 2;
        if (by_host_[mid]->code <= p) lo = mid + 1; else hi = mid;
    }
    if (lo == 0) return nullptr;
    BlockMeta* b = by_host_[lo - 1];
    // stubs follow the body; accept anything up to the next block
    return b;
}

void link_exit(ExitInfo* e, u8* host) {
    // The rel32 field is 4-byte aligned, so this store is atomic w.r.t. concurrent execution.
    i32 rel = (i32)(host - (e->site + 4));
    __atomic_store_n((i32*)e->site, rel, __ATOMIC_RELEASE);
    e->linked = 1;
}

}  // namespace xef
