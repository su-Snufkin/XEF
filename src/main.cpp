// XEF — AArch64 → x86-64 user-mode binary translator.
#include <unistd.h>

#include <string>

#include "common/cpu_features.h"
#include "loader/elf_loader.h"
#include "os/signals.h"
#include "os/syscalls.h"
#include "os/thread.h"
#include "profile/stats.h"
#include "runtime/dispatch.h"
#include "runtime/tier2.h"

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
            "  --max-block N      max guest instructions per block (default 128)\n");
    exit(1);
}

int main(int argc, char** argv, char** envp) {
    int i = 1;
    if (const char* r = getenv("XEF_ROOTFS")) g_rootfs = r;
    for (; i < argc && argv[i][0] == '-'; i++) {
        std::string a = argv[i];
        if ((a == "-L" || a == "--rootfs") && i + 1 < argc) g_rootfs = argv[++i];
        else if (a == "-v") g_verbose++;
        else if (a == "-vv") g_verbose += 2;
        else if (a == "--stats") g_opt.stats = true;
        else if (a == "--profile") g_opt.profile = true;
        else if (a == "--no-tier2") g_opt.tier2 = false;
        else if (a == "--tier2-threshold" && i + 1 < argc) g_tier2_threshold = atoi(argv[++i]);
        else if (a == "--dump-ir") g_opt.dump_ir = true;
        else if (a == "--dump-code") g_opt.dump_code = true;
        else if (a == "--max-block" && i + 1 < argc) g_opt.max_block_insts = atoi(argv[++i]);
        else if (a == "--") { i++; break; }
        else usage();
    }
    if (i >= argc) usage();
    if (getenv("XEF_STATS")) g_opt.stats = true;
    while (!g_rootfs.empty() && g_rootfs.back() == '/') g_rootfs.pop_back();
    g_main_argc_xef = i;
    g_xef_argv = argv;

    detect_host_features();
    runtime_init();
    signals_init();

    LoadedImage img;
    if (!load_elf(argv[i], img)) fatal("cannot load %s", argv[i]);
    syscalls_init(img);
    GuestAddr sp = setup_stack(img, argc - i, argv + i, envp);

    ThreadCtx* t = thread_create(nullptr);
    CpuState* st = t->st;
    st->x[kGuestSP] = sp;
    st->pc = img.entry;
    st->eflags = 0x203;   // canonical NZCV=0000 -> CF=1
    if (g_opt.profile) profile_start();
    if (getenv("XEF_NO_TIER2")) g_opt.tier2 = false;
    tier2_init(g_opt.tier2);
    cpu_loop(t);
}
