// Shader compilation through the xef-mtlc helper process, with memory and disk caches.
#include "mtl_engine.h"
#include "common/common.h"
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char** environ;

namespace xef::mtl {

using namespace mtlabi;

static std::mutex g_cmtx;
static int g_to = -1, g_from = -1;
static pid_t g_pid = 0;
static std::map<uint64_t, std::shared_ptr<CompileResult>> g_mem_cache;

static std::string self_dir() {
    char buf[4096];
    ssize_t n = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
    if (n <= 0) return ".";
    buf[n] = 0;
    std::string s(buf);
    size_t p = s.rfind('/');
    return p == std::string::npos ? "." : s.substr(0, p);
}

static std::string compiler_path() {
    if (const char* e = getenv("XEF_MTLC")) return e;
    std::string d = self_dir();
    for (const char* c : {"/mtlc/xef-mtlc", "/xef-mtlc"}) {
        std::string p = d + c;
        if (access(p.c_str(), X_OK) == 0) return p;
    }
    return d + "/mtlc/xef-mtlc";
}

static void kill_compiler() {
    if (g_to >= 0) close(g_to);
    if (g_from >= 0) close(g_from);
    g_to = g_from = -1;
    if (g_pid > 0) { kill(g_pid, SIGKILL); waitpid(g_pid, nullptr, 0); }
    g_pid = 0;
}

static bool spawn_compiler() {
    if (g_pid > 0) return true;
    int in[2], out[2];
    if (pipe2(in, O_CLOEXEC) || pipe2(out, O_CLOEXEC)) return false;
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, in[0], 0);
    posix_spawn_file_actions_adddup2(&fa, out[1], 1);
    std::string path = compiler_path();
    char* argv[] = {(char*)path.c_str(), (char*)"--server", nullptr};
    int r = posix_spawn(&g_pid, path.c_str(), &fa, nullptr, argv, environ);
    posix_spawn_file_actions_destroy(&fa);
    close(in[0]);
    close(out[1]);
    if (r != 0) {
        XEF_LOG(1, "metal: cannot start shader compiler %s: %s", path.c_str(), strerror(r));
        close(in[1]); close(out[0]);
        g_pid = 0;
        return false;
    }
    g_to = in[1];
    g_from = out[0];
    return true;
}

static bool write_all(int fd, const void* p, size_t n) {
    const uint8_t* b = (const uint8_t*)p;
    while (n) {
        ssize_t r = write(fd, b, n);
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) return false;
        b += r; n -= (size_t)r;
    }
    return true;
}
static bool read_all(int fd, void* p, size_t n) {
    uint8_t* b = (uint8_t*)p;
    while (n) {
        ssize_t r = read(fd, b, n);
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) return false;
        b += r; n -= (size_t)r;
    }
    return true;
}

static uint64_t hash64(const uint8_t* p, size_t n) {
    uint64_t h = 0xcbf29ce484222325ull;
    for (size_t i = 0; i < n; i++) { h ^= p[i]; h *= 0x100000001b3ull; }
    return h ^ (n * 0x9E3779B97F4A7C15ull);
}

static std::string cache_dir() {
    std::string base;
    if (const char* x = getenv("XDG_CACHE_HOME")) base = x;
    else if (const char* h = getenv("HOME")) base = std::string(h) + "/.cache";
    else return {};
    std::string d = base + "/xef-mtl";
    mkdir(base.c_str(), 0755);
    mkdir(d.c_str(), 0755);
    return d;
}

// compiler build stamp: cached results become stale when xef-mtlc changes
static std::string compiler_stamp() {
    static std::string s;
    if (!s.empty()) return s;
    struct stat st{};
    if (stat(compiler_path().c_str(), &st) == 0) {
        char b[64];
        snprintf(b, sizeof b, "%lx-%lx", (unsigned long)st.st_mtime, (unsigned long)st.st_size);
        s = b;
    } else s = "none";
    return s;
}

// one request/reply exchange with the compiler process; a crash is retried once with a fresh process
static bool transact(uint32_t type, const std::vector<uint8_t>& msg, std::vector<uint8_t>& reply, std::string& err) {
    for (int attempt = 0; attempt < 2; attempt++) {
        if (!spawn_compiler()) { err = "shader compiler unavailable"; return false; }
        uint32_t hdr[3] = {kProtoMagic, type, (uint32_t)msg.size()};
        uint32_t rh[3];
        bool io = write_all(g_to, hdr, sizeof hdr) && write_all(g_to, msg.data(), msg.size()) && read_all(g_from, rh, sizeof rh);
        if (io && rh[0] == kProtoMagic) {
            reply.resize(rh[2]);
            io = read_all(g_from, reply.data(), reply.size());
        } else io = false;
        if (io) return true;
        kill_compiler();
        err = "shader compiler crashed";
    }
    return false;
}

static std::string cache_path(uint64_t key, const char* ext) {
    if (getenv("XEF_MTL_NOCACHE")) return {};
    std::string dir = cache_dir();
    if (dir.empty()) return {};
    char name[64];
    snprintf(name, sizeof name, "/%016llx.%s", (unsigned long long)key, ext);
    return dir + name;
}

// cached payload without the compiler stamp, or empty when missing/stale
static std::vector<uint8_t> cache_load(const std::string& path) {
    std::vector<uint8_t> data;
    if (path.empty()) return data;
    FILE* f = fopen(path.c_str(), "rb");
    if (!f) return data;
    uint8_t buf[65536];
    size_t n;
    while ((n = fread(buf, 1, sizeof buf, f)) > 0) data.insert(data.end(), buf, buf + n);
    fclose(f);
    const std::string& stamp = compiler_stamp();
    if (data.size() <= stamp.size() || memcmp(data.data(), stamp.data(), stamp.size())) return {};
    data.erase(data.begin(), data.begin() + (ptrdiff_t)stamp.size());
    return data;
}

static void cache_store(const std::string& path, const std::vector<uint8_t>& data) {
    if (path.empty()) return;
    std::string tmp = path + ".tmp";
    if (FILE* f = fopen(tmp.c_str(), "wb")) {
        const std::string& stamp = compiler_stamp();
        fwrite(stamp.data(), 1, stamp.size(), f);
        fwrite(data.data(), 1, data.size(), f);
        fclose(f);
        rename(tmp.c_str(), path.c_str());
    }
}

bool compile_shaders(const CompileRequest& req, CompileResult& res) {
    std::vector<uint8_t> msg = serialize(req);
    uint64_t key = hash64(msg.data(), msg.size());
    std::lock_guard<std::mutex> lk(g_cmtx);
    auto it = g_mem_cache.find(key);
    if (it != g_mem_cache.end()) { res = *it->second; return res.ok; }
    std::string path = cache_path(key, "bin");
    std::vector<uint8_t> cached = cache_load(path);
    if (!cached.empty() && deserialize(cached.data(), cached.size(), res) && res.ok) {
        g_mem_cache[key] = std::make_shared<CompileResult>(res);
        return true;
    }
    std::vector<uint8_t> reply;
    res = CompileResult();
    if (!transact(MSG_COMPILE, msg, reply, res.log)) return false;
    if (!deserialize(reply.data(), reply.size(), res)) { res.ok = false; res.log = "bad compiler reply"; return false; }
    if (res.ok) {
        g_mem_cache[key] = std::make_shared<CompileResult>(res);
        cache_store(path, serialize(res));
    } else {
        XEF_LOG(1, "metal: shader compilation failed: %s", res.log.c_str());
    }
    return res.ok;
}

bool compile_source(const SourceRequest& req, SourceResult& res) {
    std::vector<uint8_t> msg = serialize(req);
    uint64_t key = hash64(msg.data(), msg.size());
    std::lock_guard<std::mutex> lk(g_cmtx);
    std::string path = cache_path(key, "lib");
    std::vector<uint8_t> cached = cache_load(path);
    if (!cached.empty() && deserialize(cached.data(), cached.size(), res) && res.ok) return true;
    std::vector<uint8_t> reply;
    res = SourceResult();
    if (!transact(MSG_COMPILE_MSL, msg, reply, res.log)) return false;
    if (!deserialize(reply.data(), reply.size(), res)) { res.ok = false; res.log = "bad compiler reply"; return false; }
    if (res.ok) cache_store(path, serialize(res));
    else XEF_LOG(1, "metal: MSL compilation failed: %s", res.log.c_str());
    return res.ok;
}

bool make_stage(const StageResult& r, StageModule& out, std::string& err) {
    out.refl = r;
    VkShaderModuleCreateInfo ci{VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
    ci.codeSize = r.spirv.size() * 4;
    ci.pCode = r.spirv.data();
    if (vk.CreateShaderModule(g.dev, &ci, nullptr, &out.mod) != VK_SUCCESS) { err = "vkCreateShaderModule failed"; return false; }
    if (!r.const_data.empty()) {
        void* map = nullptr;
        out.const_buffer = create_buffer_internal(r.const_data.size(), true, &map);
        if (map) memcpy(map, r.const_data.data(), r.const_data.size());
    }
    for (const ConstSampler& cs : r.const_samplers) out.const_samplers.push_back(const_sampler_id(cs));
    return true;
}

} // namespace xef::mtl
