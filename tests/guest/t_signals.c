#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>
#include <pthread.h>
#include <setjmp.h>
#include <ucontext.h>
static sigjmp_buf probe_jb;
static volatile int ill_code, trap_code;
static void h_ill(int s, siginfo_t* si, void* uc) { ill_code = si->si_code; siglongjmp(probe_jb, 1); }
static void h_trap(int s, siginfo_t* si, void* uc) {   // skip the brk, like a debugger would
    trap_code = si->si_code;
    ((ucontext_t*)uc)->uc_mcontext.pc += 4;
}
static volatile sig_atomic_t got_usr1, got_alarm, info_ok;
static volatile long spin;
static void h_usr1(int s) { got_usr1++; }
static void h_info(int s, siginfo_t* si, void* uc) { if (si->si_signo == SIGUSR2 && si->si_pid == getpid()) info_ok = 1; }
static void h_alarm(int s) { got_alarm = 1; }
static void* th(void* a) { usleep(20000); kill(getpid(), SIGUSR1); return 0; }
int main(void) {
    signal(SIGUSR1, h_usr1);
    raise(SIGUSR1);
    kill(getpid(), SIGUSR1);
    printf("usr1 %d\n", got_usr1);
    struct sigaction sa; memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = h_info; sa.sa_flags = SA_SIGINFO;
    sigaction(SIGUSR2, &sa, 0);
    raise(SIGUSR2);
    printf("siginfo ok %d\n", info_ok);
    // async delivery into a busy loop (translated code, no syscalls)
    signal(SIGALRM, h_alarm);
    struct itimerval it = {{0, 0}, {0, 50000}};
    setitimer(ITIMER_REAL, &it, 0);
    double x = 1.0;
    while (!got_alarm) { spin++; x = x * 1.0000001 + 1e-9; }
    printf("alarm interrupted busy loop: %d\n", got_alarm);
    // blocked signal delivered on unblock
    sigset_t m, old; sigemptyset(&m); sigaddset(&m, SIGUSR1);
    sigprocmask(SIG_BLOCK, &m, &old);
    int before = got_usr1;
    raise(SIGUSR1);
    printf("while blocked: %d\n", got_usr1 - before);
    sigprocmask(SIG_SETMASK, &old, 0);
    printf("after unblock: %d\n", got_usr1 - before);
    // sigsuspend woken by another thread
    sigprocmask(SIG_BLOCK, &m, &old);
    pthread_t t; pthread_create(&t, 0, th, 0);
    sigset_t w; sigemptyset(&w);
    before = got_usr1;
    sigsuspend(&w);
    printf("sigsuspend got %d\n", got_usr1 - before);
    pthread_join(t, 0);
    // SIGILL / SIGTRAP from the instruction stream reach the guest's handlers (feature probing)
    sa.sa_sigaction = h_ill; sa.sa_flags = SA_SIGINFO;
    sigaction(SIGILL, &sa, 0);
    int probed = 0;
    if (!sigsetjmp(probe_jb, 1)) { __asm__ volatile(".inst 0x00000000"); probed = 1; }   // udf #0
    // the kernel reports ILL_ILLOPC, qemu ILL_ILLOPN
    printf("udf: handler %s, si_code ok %d\n", probed ? "skipped" : "ran", ill_code == ILL_ILLOPC || ill_code == ILL_ILLOPN);
    sa.sa_sigaction = h_trap;
    sigaction(SIGTRAP, &sa, 0);
    long v = 1;
    __asm__ volatile("brk #0x7\n\tadd %0, %0, #2" : "+r"(v));
    printf("brk: si_code %d, resumed v=%ld\n", trap_code, v);
    return 0;
}
