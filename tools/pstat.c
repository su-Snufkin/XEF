// pstat: user-space cycles / instructions / branch misses of a command and its threads
// (like `perf stat -e cycles:u,instructions:u,branch-misses:u`, without perf; works with
// kernel.perf_event_paranoid <= 2). Cycles are less sensitive to frequency changes than time.
//   cc -O2 -o build/pstat tools/pstat.c && build/pstat [-r N] cmd args...
//   -r N: run N times, report the minimum of each counter
#include <fcntl.h>
#include <linux/perf_event.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static int open_counter(uint32_t type, uint64_t config, pid_t pid) {
    struct perf_event_attr a;
    memset(&a, 0, sizeof a);
    a.size = sizeof a;
    a.type = type;
    a.config = config;
    a.disabled = 1;
    a.enable_on_exec = 1;
    a.inherit = 1;
    a.exclude_kernel = 1;
    a.exclude_hv = 1;
    return (int)syscall(SYS_perf_event_open, &a, pid, -1, -1, 0);
}

int main(int argc, char** argv) {
    int reps = 1, i = 1;
    if (argc > 2 && !strcmp(argv[1], "-r")) { reps = atoi(argv[2]); i = 3; }
    if (i >= argc) { fprintf(stderr, "usage: pstat [-r N] cmd args...\n"); return 2; }
    uint64_t best[3] = {~0ull, ~0ull, ~0ull};
    double best_t = 1e30;
    static const uint64_t cfg[3] = {PERF_COUNT_HW_CPU_CYCLES, PERF_COUNT_HW_INSTRUCTIONS, PERF_COUNT_HW_BRANCH_MISSES};
    for (int r = 0; r < reps; r++) {
        int go[2];
        if (pipe(go)) return 1;
        pid_t pid = fork();
        if (pid == 0) {
            char c;
            close(go[1]);
            if (read(go[0], &c, 1) != 1) _exit(127);
            int devnull = getenv("PSTAT_SHOW") ? -1 : open("/dev/null", 1);
            if (devnull >= 0) dup2(devnull, 1);
            execvp(argv[i], argv + i);
            _exit(127);
        }
        close(go[0]);
        int fd[3];
        for (int k = 0; k < 3; k++) {
            fd[k] = open_counter(PERF_TYPE_HARDWARE, cfg[k], pid);
            if (fd[k] < 0) { perror("perf_event_open"); kill(pid, 9); return 1; }
        }
        struct timespec t0, t1;
        clock_gettime(CLOCK_MONOTONIC, &t0);
        if (write(go[1], "x", 1) != 1) return 1;
        close(go[1]);
        int st;
        waitpid(pid, &st, 0);
        clock_gettime(CLOCK_MONOTONIC, &t1);
        for (int k = 0; k < 3; k++) {
            uint64_t v = 0;
            if (read(fd[k], &v, sizeof v) != sizeof v) v = 0;
            close(fd[k]);
            if (v < best[k]) best[k] = v;
        }
        double t = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
        if (t < best_t) best_t = t;
    }
    fprintf(stderr, "cycles %.4fG  insns %.4fG  ipc %.2f  br-miss %.2fM  wall %.3fs\n", best[0] / 1e9, best[1] / 1e9,
            best[0] ? (double)best[1] / best[0] : 0.0, best[2] / 1e6, best_t);
    return 0;
}
