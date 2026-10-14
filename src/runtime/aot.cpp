// XEF — persistent translation cache (XEF_AOT=1).
//
// A tier-1 chain (runtime/dispatch.cpp: translate) is saved as its host code, exits, pc maps,
// the guest ranges it depends on (bodies and NZCV lookahead) with a hash of their bytes, and the
// relocations its assembler recorded: host addresses (helpers, tables) relative to the xef
// image, rel32 jumps to the runtime stubs, RIP-relative vector constants (re-interned), the
// ExitInfo* of link stubs. Exits are saved unlinked. A later run of the same program (same xef
// build, register mapping, host features and options) instantiates a chain instead of
// translating it when the hash of the guest bytes matches; guest addresses are absolute, so
// file mappings are placed deterministically (mmap_hint) while the cache is on.
//
// File: $XEF_AOT_DIR (default ~/.cache/xef)/<hash of the guest executable path>.xc: a header with
// the configuration key, then records appended at process exit (flock). Unknown key: rewritten.
#include "runtime/aot.h"

#include <fcntl.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "common/cpu_features.h"
#include "frontend/a64/translate.h"
#include "profile/stats.h"
#include "runtime/cpu_state.h"
#include "runtime/dispatch.h"

extern "C" char __executable_start, _end;

namespace xef {
bool vconst_pool_entry(const u8* p, u64* lo, u64* hi);
u8* vconst_pool_get(u64 lo, u64 hi);
}

namespace xef::aot {

using x64::RelocRec;
using namespace x64;

namespace {

constexpr u64 kMagic = 0x3130544f41464558ull;   // "XEFAOT01"
constexpr size_t kHeader = 64;
constexpr u64 kMaxFile = 256ull << 20;   // larger: started again
enum StubId : u8 { ST_ENTER = 1, ST_EXIT = 2, ST_LINK = 3, ST_IBTC_MISS = 4, ST_SYSCALL = 5 };

bool g_on;
u64 g_key;
std::string g_path;
const u8* g_map;             // the cache file at startup (read only)
size_t g_map_size;
struct Unit { u32 off; u8 state; };   // state: 0 untried, 1 used, 2 stale / failed
std::vector<Unit> g_units;
// member start -> unit number + 1: open addressing, at most half full (0: empty)
struct Index {
    struct E { GuestAddr pc; u32 unit; };
    std::vector<E> t;
    u64 mask = 0;
    static u64 h(GuestAddr pc) { return (pc >> 2) * 0x9E3779B97F4A7C15ull; }
    void init(size_t n) {
        size_t sz = 16;
        while (sz < 2 * n) sz *= 2;
        t.assign(sz, E{0, 0});
        mask = sz - 1;
    }
    void add(GuestAddr pc, u32 unit) {   // first one wins
        for (u64 i = h(pc) >> 20 & mask;; i = (i + 1) & mask) {
            if (!t[i].unit) { t[i] = {pc, unit + 1}; return; }
            if (t[i].pc == pc) return;
        }
    }
    int find(GuestAddr pc) const {
        if (t.empty()) return -1;
        for (u64 i = h(pc) >> 20 & mask;; i = (i + 1) & mask) {
            if (!t[i].unit) return -1;
            if (t[i].pc == pc) return (int)t[i].unit - 1;
        }
    }
} g_index;
std::mutex g_mu;                              // g_pending, g_units[].state
std::vector<u8> g_pending;                    // records captured by this process
u64 g_next_map = 0x7d0000000000ull;           // mmap_hint

u64 mix(u64 h, u64 w) {
    h ^= w * 0x9E3779B97F4A7C15ull;
    h = (h << 31) | (h >> 33);
    return h * 0xC2B2AE3D27D4EB4Full;
}
u64 hash_bytes(u64 h, const u8* p, size_t n) {
    size_t i = 0;
    for (; i + 8 <= n; i += 8) {
        u64 w;
        memcpy(&w, p + i, 8);
        h = mix(h, w);
    }
    u64 t = 0;
    memcpy(&t, p + i, n - i);
    return mix(mix(h, t), n);
}

struct Reader {
    const u8* p;
    const u8* end;
    bool ok = true;
    template <typename T> T get() {
        T x{};
        if (p + sizeof(T) > end) { ok = false; return x; }
        memcpy(&x, p, sizeof(T));
        p += sizeof(T);
        return x;
    }
    const u8* skip(size_t n) {
        if (p + n > end) { ok = false; return nullptr; }
        const u8* r = p;
        p += n;
        return r;
    }
};

struct ExitRec { GuestAddr target; u32 site_off, stub_off; u8 kind; u8 pad[3]; };
struct MemberHdr { GuestAddr start, end; u32 code_off, code_size, nexits, npc, npeek, pad; };
struct UnitHdr { u32 nmem, code_size, nreloc, pad; u64 hash; };

// records in the mapped file are not aligned
template <typename T> T ld(const void* base, size_t i) {
    T x;
    memcpy(&x, (const u8*)base + i * sizeof(T), sizeof(T));
    return x;
}

u8 stub_id(const u8* t) {
    const RuntimeStubs& s = g_cache.stubs;
    if (t == s.enter) return ST_ENTER;
    if (t == s.exit_to_runtime) return ST_EXIT;
    if (t == s.link_stub) return ST_LINK;
    if (t == s.ibtc_miss) return ST_IBTC_MISS;
    if (t == s.syscall_exit) return ST_SYSCALL;
    return 0;
}
u8* stub_addr(u8 id) {
    const RuntimeStubs& s = g_cache.stubs;
    switch (id) {
    case ST_ENTER: return s.enter;
    case ST_EXIT: return s.exit_to_runtime;
    case ST_LINK: return s.link_stub;
    case ST_IBTC_MISS: return s.ibtc_miss;
    case ST_SYSCALL: return s.syscall_exit;
    default: return nullptr;
    }
}

bool readable(GuestAddr lo, GuestAddr hi) {
    for (GuestAddr p = lo & ~0xfffull; p < hi; p += 4096)
        if (!a64::guest_readable(p)) return false;
    return true;
}

// configuration key: xef build, register mapping, host features, translation options
u64 config_key() {
    u64 h = 0x5851;
    int fd = open("/proc/self/exe", O_RDONLY | O_CLOEXEC);
    if (fd >= 0) {
        static u8 buf[1 << 16];
        for (ssize_t r; (r = read(fd, buf, sizeof buf)) > 0;) h = hash_bytes(h, buf, (size_t)r);
        close(fd);
    }
    h = hash_bytes(h, (const u8*)regmap::name(), strlen(regmap::name()));
    h = hash_bytes(h, (const u8*)&g_host, sizeof g_host);
    h = mix(h, (u64)g_opt.max_block_insts);
    h = mix(h, (u64)a64::g_abi_flags);
    return h;
}

void index_file() {
    // a first pass sizes the index (members per unit: at most 8; records are ~200+ bytes)
    g_index.init(g_map_size / 64 + 16);
    Reader rd{g_map + kHeader, g_map + g_map_size};
    while (rd.ok && rd.p < rd.end) {
        u32 len = rd.get<u32>();
        const u8* rec = rd.skip(len);
        if (!rd.ok || len < sizeof(UnitHdr)) break;
        Reader u{rec, rec + len};
        UnitHdr uh = u.get<UnitHdr>();
        u32 num = (u32)g_units.size();
        g_units.push_back({(u32)(rec - g_map), 0});
        for (u32 m = 0; m < uh.nmem && u.ok; m++) {
            MemberHdr mh = u.get<MemberHdr>();
            u.skip(sizeof(ExitRec) * mh.nexits + sizeof(PcMapEntry) * mh.npc + 16ull * mh.npeek);
            if (u.ok) g_index.add(mh.start, num);
        }
    }
}

}  // namespace

bool enabled() { return g_on; }

u64 mmap_hint(u64 len) {
    if (!g_on) return 0;
    u64 sz = (len + 0xffff) & ~0xffffull;
    return __atomic_fetch_add(&g_next_map, sz + 0x10000, __ATOMIC_RELAXED);
}

void init(const char* guest_exe) {
    const char* e = getenv("XEF_AOT");
    if (!e || !*e || *e == '0') return;
    if (g_opt.trace || g_opt.dump_ir || g_opt.dump_code || getenv("XEF_SPLIT") || getenv("XEF_VERIFY")) return;
    std::string dir;
    if (const char* d = getenv("XEF_AOT_DIR")) dir = d;
    else if (const char* home = getenv("HOME")) dir = std::string(home) + "/.cache/xef";
    else return;
    for (size_t i = 1; i <= dir.size(); i++)
        if (i == dir.size() || dir[i] == '/') mkdir(dir.substr(0, i).c_str(), 0755);
    char rp[4096];
    const char* exe = realpath(guest_exe, rp) ? rp : guest_exe;
    char name[32];
    snprintf(name, sizeof name, "/%016llx.xc", (unsigned long long)hash_bytes(0x41, (const u8*)exe, strlen(exe)));
    g_path = dir + name;
    g_key = config_key();
    g_on = true;
    int fd = open(g_path.c_str(), O_RDONLY | O_CLOEXEC);
    if (fd < 0) return;
    struct stat sb;
    u64 hdr[2] = {};
    if (fstat(fd, &sb) == 0 && (size_t)sb.st_size > kHeader && pread(fd, hdr, sizeof hdr, 0) == (ssize_t)sizeof hdr &&
        hdr[0] == kMagic && hdr[1] == g_key) {
        void* p = mmap(nullptr, (size_t)sb.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
        if (p != MAP_FAILED) {
            g_map = (const u8*)p;
            g_map_size = (size_t)sb.st_size;
            index_file();
        }
    }
    close(fd);
    XEF_LOG(1, "aot: %s: %zu cached chains", g_path.c_str(), g_units.size());
}

x64::RelocSink* sink() {
    if (!g_on) return nullptr;
    static thread_local x64::RelocSink* s;
    if (!s) s = new x64::RelocSink();
    s->n = 0;
    s->overflow = false;
    return s;
}

void capture(int nc, const GuestAddr* pcs, const GuestAddr* ends, BlockMeta* const* metas, const PeekLog* peeks,
             const PcMapEntry* const* pcmaps, const int* npcmaps, const u8* code, size_t size,
             const x64::RelocSink& rs) {
    if (!g_on || rs.overflow) return;
    // only code at deterministic addresses: executables, interpreter, libraries (mmap_hint);
    // what the kernel placed (JIT buffers) would not be found again
    if (pcs[0] >= __atomic_load_n(&g_next_map, __ATOMIC_RELAXED)) return;
    if (int u = g_index.find(pcs[0]); u >= 0 && g_units[u].state != 2) return;   // in the file
    for (int k = 0; k < nc; k++) if (peeks[k].overflow) return;
    // relocations: classify, or give up on this chain
    static thread_local RelocRec* rel;
    if (!rel) rel = new RelocRec[x64::RelocSink::kMax * 3];
    int nrel = 0;
    const u8* xlo = (const u8*)&__executable_start;
    const u8* xhi = (const u8*)&_end;
    for (int i = 0; i < rs.n; i++) {
        RelocRec r = rs.r[i];
        const u8* t = (const u8*)r.val;
        switch (r.kind) {
        case RK_HOST64:
            if (t < xlo || t >= xhi) return;
            r.val = (u64)(t - xlo);
            break;
        case RK_REL32:
            if (t >= code && t < code + size) continue;   // inside the chain
            if (!(r.val = stub_id(t))) return;
            break;
        case RK_RIP32: {
            u64 lo, hi;
            if (!vconst_pool_entry(t, &lo, &hi)) return;
            rel[nrel++] = r;            // the constant follows in two more records
            rel[nrel++] = {0, 0, 0, lo};
            r = {0, 0, 0, hi};
            break;
        }
        case RK_EXITINFO: {
            int m = 0, x = -1;
            for (; m < nc; m++) {
                const ExitInfo* e = (const ExitInfo*)r.val;
                if (e >= metas[m]->exits && e < metas[m]->exits + metas[m]->nexits) { x = (int)(e - metas[m]->exits); break; }
            }
            if (x < 0) return;
            r.val = (u64)m << 16 | (u64)x;
            break;
        }
        default: return;
        }
        rel[nrel++] = r;
    }
    // the guest bytes the chain was made from
    u64 h = 0x1234;
    size_t len = sizeof(UnitHdr) + sizeof(RelocRec) * nrel + size;
    for (int k = 0; k < nc; k++) {
        h = hash_bytes(h, (const u8*)pcs[k], ends[k] - pcs[k]);
        for (int i = 0; i < peeks[k].n; i++)
            h = hash_bytes(h, (const u8*)peeks[k].r[i].lo, peeks[k].r[i].hi - peeks[k].r[i].lo);
        len += sizeof(MemberHdr) + sizeof(ExitRec) * metas[k]->nexits + sizeof(PcMapEntry) * npcmaps[k] + 16 * peeks[k].n;
    }
    std::lock_guard<std::mutex> g(g_mu);
    if (g_pending.capacity() < g_pending.size() + 4 + len)
        g_pending.reserve(std::max(g_pending.capacity() * 2, g_pending.size() + 4 + len + (4u << 20)));
    size_t o = g_pending.size();
    g_pending.resize(o + 4 + len);
    u8* p = &g_pending[o];
    auto put = [&](const void* x, size_t n) { memcpy(p, x, n); p += n; };
    u32 len32 = (u32)len;
    put(&len32, 4);
    UnitHdr uh{(u32)nc, (u32)size, (u32)nrel, 0, h};
    put(&uh, sizeof uh);
    for (int k = 0; k < nc; k++) {
        const BlockMeta* m = metas[k];
        MemberHdr mh{pcs[k], ends[k], (u32)(m->code - code), m->code_size, m->nexits, (u32)npcmaps[k], (u32)peeks[k].n, 0};
        put(&mh, sizeof mh);
        for (int i = 0; i < m->nexits; i++) {
            const ExitInfo& e = m->exits[i];
            ExitRec x{e.target, (u32)(e.site - code), (u32)(e.stub - code), e.kind, {}};
            put(&x, sizeof x);
        }
        put(pcmaps[k], sizeof(PcMapEntry) * npcmaps[k]);
        for (int i = 0; i < peeks[k].n; i++) { put(&peeks[k].r[i].lo, 8); put(&peeks[k].r[i].hi, 8); }
    }
    put(rel, sizeof(RelocRec) * nrel);
    put(code, size);
}

u64 g_misses, g_stale;
BlockMeta* try_load(GuestAddr pc) {
    if (!g_on || g_units.empty()) return nullptr;
    int ui = g_index.find(pc);
    if (ui < 0) { g_misses++; return nullptr; }
    Unit& un = g_units[ui];
    if (un.state) return nullptr;
    const u8* base = g_map + un.off;
    Reader rd{base, g_map + g_map_size};
    UnitHdr uh = rd.get<UnitHdr>();
    constexpr int kMaxMem = 8;
    if (!rd.ok || uh.nmem == 0 || uh.nmem > kMaxMem) { un.state = 2; return nullptr; }
    MemberHdr mh[kMaxMem];
    const u8* ex[kMaxMem];
    const PcMapEntry* pm[kMaxMem];
    const u8* pk[kMaxMem];
    for (u32 m = 0; m < uh.nmem; m++) {
        mh[m] = rd.get<MemberHdr>();
        ex[m] = rd.skip(sizeof(ExitRec) * mh[m].nexits);
        pm[m] = (const PcMapEntry*)rd.skip(sizeof(PcMapEntry) * mh[m].npc);
        pk[m] = rd.skip(16ull * mh[m].npeek);
    }
    const u8* rel = rd.skip(sizeof(RelocRec) * uh.nreloc);
    const u8* code = rd.skip(uh.code_size);
    if (!rd.ok) { un.state = 2; return nullptr; }
    for (u32 m = 0; m < uh.nmem; m++) if (g_cache.lookup(mh[m].start)) { un.state = 2; return nullptr; }
    // the guest code must be the one the chain was made from; marked before the epoch is read,
    // as translate() does
    u64 ep = g_cache.epoch.load(std::memory_order_seq_cst);
    u64 h = 0x1234;
    for (u32 m = 0; m < uh.nmem; m++) {
        if (!readable(mh[m].start, mh[m].end)) return nullptr;
        g_cache.mark_code(mh[m].start, mh[m].end);
        h = hash_bytes(h, (const u8*)mh[m].start, mh[m].end - mh[m].start);
        for (u32 i = 0; i < mh[m].npeek; i++) {
            GuestAddr lo = ld<GuestAddr>(pk[m], 2 * i), hi = ld<GuestAddr>(pk[m], 2 * i + 1);
            if (!readable(lo, hi)) return nullptr;
            g_cache.mark_code(lo, hi);
            h = hash_bytes(h, (const u8*)lo, hi - lo);
        }
    }
    if (h != uh.hash) { un.state = 2; g_stale++; return nullptr; }
    std::lock_guard<std::mutex> lk(g_cache.lock);
    if (g_cache.epoch.load(std::memory_order_seq_cst) != ep) return nullptr;
    for (u32 m = 0; m < uh.nmem; m++) if (g_cache.lookup(mh[m].start)) return nullptr;
    un.state = 1;
    u8* dst = g_cache.alloc_code(uh.code_size + 64);
    memcpy(dst, code, uh.code_size);
    BlockMeta* metas[kMaxMem];
    for (u32 m = 0; m < uh.nmem; m++) {
        BlockMeta* b = g_cache.alloc_meta((int)mh[m].nexits);
        b->start = mh[m].start;
        b->end = mh[m].end;
        b->code = dst + mh[m].code_off;
        b->code_size = mh[m].code_size;
        b->tier = 1;
        b->chain_prev = m ? metas[m - 1] : nullptr;
        for (u32 i = 0; i < mh[m].nexits; i++) {
            ExitInfo& e = b->exits[i];
            ExitRec x = ld<ExitRec>(ex[m], i);
            e.kind = x.kind;
            e.target = x.target;
            e.site = dst + x.site_off;
            e.stub = dst + x.stub_off;
            e.owner = b;
            e.linked = 0;
            e.next_in = nullptr;
        }
        metas[m] = b;
    }
    const u8* xlo = (const u8*)&__executable_start;
    for (u32 i = 0; i < uh.nreloc; i++) {
        RelocRec r = ld<RelocRec>(rel, i);
        u8* f = dst + r.off;
        switch (r.kind) {
        case RK_HOST64: { u64 v = (u64)(xlo + r.val); memcpy(f, &v, 8); break; }
        case RK_REL32: x64::Assembler::patch_rel32(f, stub_addr((u8)r.val)); break;
        case RK_RIP32: {
            u64 lo = ld<RelocRec>(rel, i + 1).val, hi = ld<RelocRec>(rel, i + 2).val;
            i += 2;
            i32 d = (i32)(vconst_pool_get(lo, hi) - (f + 4 + r.trailing));
            memcpy(f, &d, 4);
            break;
        }
        case RK_EXITINFO: { u64 v = (u64)&metas[r.val >> 16]->exits[r.val & 0xffff]; memcpy(f, &v, 8); break; }
        }
    }
    g_cache.commit_code(dst, uh.code_size);
    int n = (int)uh.nmem;
    for (int m = 0; m < n; m++) {
        BlockMeta* b = metas[m];
        g_cache.set_pcmap(b, pm[m], (int)mh[m].npc);
        for (int i = 0; i < b->nexits; i++) {
            ExitInfo* e = &b->exits[i];
            if (BlockMeta* tb = g_cache.lookup(e->target)) {
                link_exit(e, tb->code);
                e->next_in = tb->incoming;
                tb->incoming = e;
            }
        }
        g_cache.register_block(b);
    }
    // a member depends on its own code and peeks and on those of every member after it
    PeekLog acc;
    for (int k = n - 1; k >= 0; k--) {
        acc.add(mh[k].start, mh[k].end);
        for (u32 i = 0; i < mh[k].npeek; i++) acc.add(ld<GuestAddr>(pk[k], 2 * i), ld<GuestAddr>(pk[k], 2 * i + 1));
        if (!acc.overflow) { g_cache.add_deps(metas[k], acc); continue; }
        for (int j = k; j < n; j++) {
            PeekLog one;
            for (u32 i = 0; i < mh[j].npeek; i++) one.add(ld<GuestAddr>(pk[j], 2 * i), ld<GuestAddr>(pk[j], 2 * i + 1));
            g_cache.add_deps(metas[k], mh[j].start, mh[j].end, &one);
        }
    }
    for (int k = n - 1; k >= 0; k--) g_cache.publish(metas[k]);
    if (g_opt.stats) g_stats.aot_loaded += n;
    for (int k = 0; k < n; k++) if (metas[k]->start == pc) return metas[k];
    return metas[0];
}

void save() {
    if (!g_on) return;
    XEF_LOG(1, "aot: %lu translations not cached, %lu cached ones stale; saving %zu bytes", (unsigned long)g_misses,
            (unsigned long)g_stale, g_pending.size());
    std::lock_guard<std::mutex> g(g_mu);
    if (g_pending.empty()) return;
    int fd = open(g_path.c_str(), O_RDWR | O_CREAT | O_CLOEXEC, 0644);
    if (fd < 0) return;
    if (flock(fd, LOCK_EX) == 0) {
        struct stat sb;
        u64 hdr[8] = {};
        bool fresh = fstat(fd, &sb) != 0 || (size_t)sb.st_size < kHeader || (u64)sb.st_size > kMaxFile ||
                     pread(fd, hdr, 16, 0) != 16 || hdr[0] != kMagic || hdr[1] != g_key;
        if (fresh) {
            hdr[0] = kMagic;
            hdr[1] = g_key;
            if (ftruncate(fd, 0) != 0 || pwrite(fd, hdr, kHeader, 0) != (ssize_t)kHeader) { close(fd); return; }
        }
        off_t end = lseek(fd, 0, SEEK_END);
        ssize_t w = pwrite(fd, g_pending.data(), g_pending.size(), end);
        (void)w;
        flock(fd, LOCK_UN);
    }
    close(fd);
    g_pending.clear();
}

void after_fork() {
    if (!g_on) return;
    new (&g_mu) std::mutex();
    g_pending.clear();
}

}  // namespace xef::aot
