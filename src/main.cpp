// XEF — AArch64 → x86-64 user-mode binary translator.
#include <chrono>
#include <thread>
#include <limits.h>
#include <stdlib.h>
#include <unistd.h>

#include <string>
#include <vector>
#include <cstring>

#include "common/cpu_features.h"
#include "loader/elf_loader.h"
#include "loader/macho_loader.h"
#include "os/signals.h"
#include "os/syscalls.h"
#include "os/darwin/darwin_syscalls.h"
#include "os/thread.h"
#include "profile/stats.h"
#include "runtime/aot.h"
#include "runtime/dispatch.h"
#include "runtime/verify.h"
#include "runtime/tier2.h"
#include "thunks/thunks.h"

using namespace xef;

static void usage() {
    fprintf(stderr,
            "usage: xef [options] <aarch64-program> [args...]\n"
            "  -L, --rootfs DIR   guest root filesystem (default: $XEF_ROOTFS)\n"
            "  -v                 verbose (repeat for more)\n"
            "  --stats            print translation/runtime statistics at exit\n"
            "  --no-tier2         disable the tier-2 region compiler\n"
            "  --profile          sample host PC (1 kHz) and print the hottest translated blocks\n"
            "  --dump-ir          dump IR of every translated block\n"
            "  --dump-code        write host code of every block to /tmp/xef-<pc>.bin\n"
            "  --max-block N      max guest instructions per block (default 128)\n"
           "  --trace            debug: no block linking, print the last blocks on a bad jump\n"
           "  --host-gl          run the guest's OpenGL/GLX calls on the host's native libGL\n");
    exit(1);
}

int main(int argc, char** argv, char** envp) {
    int i = 1;
    const char* argv0 = nullptr;   // execve under XEF: the guest's argv[0] when it is not the path
    if (const char* r = getenv("XEF_ROOTFS")) g_rootfs = r;
    for (; i < argc && argv[i][0] == '-'; i++) {
        std::string a = argv[i];
        if ((a == "-L" || a == "--rootfs") && i + 1 < argc) g_rootfs = argv[++i];
        else if (a == "-v") g_verbose++;
        else if (a == "-vv") g_verbose += 2;
        else if (a == "--stats") g_opt.stats = true;
        else if (a == "--profile") g_opt.profile = true;
        else if (a == "--darwin" || a == "--osx") g_is_darwin = true;
        else if (a == "--no-tier2") g_opt.tier2 = false;
        else if (a == "--host-gl") g_host_gl = true;
        else if (a == "--trace") { g_opt.trace = true; g_opt.tier2 = false; }
        else if (a == "--tier2-threshold" && i + 1 < argc) g_tier2_threshold = atoi(argv[++i]);
        else if (a == "--dump-ir") g_opt.dump_ir = true;
        else if (a == "--dump-code") g_opt.dump_code = true;
        else if (a == "--max-block" && i + 1 < argc) g_opt.max_block_insts = atoi(argv[++i]);
        else if (a == "--argv0" && i + 1 < argc) argv0 = argv[++i];
        else if (a == "--") { i++; break; }
        else usage();
    }
    if (const char* e = getenv("XEF_DUMP")) {   // --dump-ir / --dump-code only for blocks in [lo, hi)
        unsigned long lo, hi;
        if (sscanf(e, "%lx-%lx", &lo, &hi) == 2) { g_opt.dump_lo = lo; g_opt.dump_hi = hi; }
    }
    if (i >= argc) usage();
    // per-block tables (exit stubs, pc offsets) are sized for this
    g_opt.max_block_insts = std::max(1, std::min(g_opt.max_block_insts, ir::kMaxGuestInsts));
    if (getenv("XEF_STATS")) g_opt.stats = true;
    if (getenv("XEF_HOST_GL")) g_host_gl = true;
    while (!g_rootfs.empty() && g_rootfs.back() == '/') g_rootfs.pop_back();
    if (g_rootfs.empty() && i < argc) {
        std::string prog_path = argv[i];
        size_t pos = prog_path.find("darwin-rootfs");
        if (pos != std::string::npos) {
            std::string cand = prog_path.substr(0, pos + 13);
            char abs[PATH_MAX];
            if (realpath(cand.c_str(), abs)) g_rootfs = abs;
        }
    }
    if (!g_rootfs.empty()) {   // absolute: guest chdir() into the rootfs must not break later lookups
        char abs[PATH_MAX];
        if (realpath(g_rootfs.c_str(), abs)) g_rootfs = abs;
    }
    g_main_argc_xef = i;
    g_xef_argv = argv;

    // A Mach-O program named by its host path inside the rootfs (darwin-rootfs/opt/homebrew/bin/go) runs under its guest
    // path (/opt/homebrew/bin/go), as on macOS: argv[0], executable_path and _NSGetExecutablePath must make sense to the
    // guest (Go finds GOROOT from it, realpath() of it must work).
    std::string guest_prog;
    if (!g_rootfs.empty() && i < argc) {
        bool fat0, arm0;
        std::string a = argv[i];
        if (a.find('/') != std::string::npos) {
            if (a[0] != '/') { char cwd[PATH_MAX]; if (getcwd(cwd, sizeof cwd)) a = std::string(cwd) + "/" + a; }
            std::vector<std::string> parts;   // lexical normalization (symlinks stay: they are the guest's to follow)
            for (size_t b = 0, e; b <= a.size(); b = e + 1) {
                e = a.find('/', b); if (e == std::string::npos) e = a.size();
                std::string c = a.substr(b, e - b);
                if (c.empty() || c == ".") continue;
                if (c == "..") { if (!parts.empty()) parts.pop_back(); continue; }
                parts.push_back(c);
            }
            std::string n;
            for (auto& c : parts) n += "/" + c;
            if (n.rfind(g_rootfs + "/", 0) == 0) {
                std::string g = n.substr(g_rootfs.size());
                if (is_macho_binary(resolve_guest_path(g.c_str()).c_str(), fat0, arm0)) { guest_prog = g; argv[i] = (char*)guest_prog.c_str(); }
            }
        }
    }

    detect_host_features();

    // scripts: "#!interp [arg]" -> run the (guest) interpreter, like execve does
    std::vector<std::string> sargs;
    std::vector<char*> sargv;
    for (int depth = 0; depth < 4; depth++) {
        char hdr[256] = {0};
        std::string hp = resolve_guest_path(argv[i]);
        FILE* f = fopen(hp.c_str(), "rb");
        if (!f) break;
        size_t n = fread(hdr, 1, sizeof hdr - 1, f);
        fclose(f);
        if (n < 2 || hdr[0] != '#' || hdr[1] != '!') break;
        std::string line(hdr + 2, strcspn(hdr + 2, "\n"));
        size_t b = line.find_first_not_of(" \t");
        if (b == std::string::npos) break;
        line = line.substr(b);
        size_t sp = line.find_first_of(" \t");
        std::vector<std::string> na{line.substr(0, sp)};
        if (sp != std::string::npos) {
            std::string arg = line.substr(line.find_first_not_of(" \t", sp));
            while (!arg.empty() && (arg.back() == ' ' || arg.back() == '\t' || arg.back() == '\r')) arg.pop_back();
            if (!arg.empty()) na.push_back(arg);
        }
        for (int k = i; k < argc; k++) na.push_back(argv[k]);
        sargs = na;
        sargv.clear();
        for (auto& s2 : sargs) sargv.push_back((char*)s2.c_str());
        sargv.push_back(nullptr);
        argv = sargv.data();
        argc = (int)sargs.size();
        i = 0;
    }

    // Check if the binary is Mach-O / FAT containing ARM64
    std::string exe_resolved = resolve_guest_path(argv[i], true);
    bool is_fat = false, is_arm64 = false;
    if (is_macho_binary(exe_resolved.c_str(), is_fat, is_arm64)) {
        if (!is_arm64) fatal("%s: Mach-O/FAT binary does not contain an ARM64 slice", argv[i]);
        g_is_darwin = true;
    }

    // the register mapping follows the executable's compiler; code generation starts after this
    regmap::select(exe_resolved.c_str());
    runtime_init();
    aot::init(exe_resolved.c_str());   // before the loader: library placement
    signals_init();

    LoadedImage img;
    if (g_is_darwin) {
        if (!load_macho(argv[i], img)) fatal("cannot load Mach-O binary %s", argv[i]);
    } else {
        if (!load_elf(argv[i], img)) fatal("cannot load %s", argv[i]);
    }
    syscalls_init(img);
    if (argv0) argv[i] = (char*)argv0;

    guest_tid_init();
    ThreadCtx* t = thread_create(nullptr);
    CpuState* st = t->st;

    GuestAddr sp = 0;
    if (g_is_darwin) {
        sp = setup_darwin_stack(img, argc - i, argv + i, envp, st);
    } else {
        sp = setup_stack(img, argc - i, argv + i, envp);
        st->x[kGuestSP] = sp;
        st->pc = img.entry;
        st->eflags = 0x203;   // canonical NZCV=0000 -> CF=1
    }
    signals_thread_init(t);
    if (g_opt.profile) profile_start();
    // XEF_PROFILE_AT=N: print the statistics / profile after N seconds (for programs that do not
    // exit cleanly, e.g. GUI applications handling SIGINT themselves)
    if (const char* e = getenv("XEF_PROFILE_AT"); e && (g_opt.profile || g_opt.stats)) {
        static int secs = atoi(e);
        std::thread([] {
            std::this_thread::sleep_for(std::chrono::seconds(secs));
            if (g_opt.stats) stats_print();
            if (g_opt.profile) profile_report();
        }).detach();
    }
    if (g_opt.profile || g_opt.stats) signals_report_on_interrupt();
    if (getenv("XEF_NO_TIER2")) g_opt.tier2 = false;
    if (verify_enabled()) { g_opt.trace = true; g_opt.tier2 = false; }   // one block per JIT entry
    tier2_init(g_opt.tier2);
    cpu_loop(t);
}
