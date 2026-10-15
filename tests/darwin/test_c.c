// Test C program for macOS ARM64
// Freestanding/direct Darwin syscall implementation in C

typedef unsigned long u64;
typedef unsigned int u32;

static inline long darwin_syscall1(long nr, long a0) {
    register long x16 __asm__("x16") = nr;
    register long x0 __asm__("x0") = a0;
    __asm__ volatile("svc #0x80" : "+r"(x0) : "r"(x16) : "memory", "cc");
    return x0;
}

static inline long darwin_syscall3(long nr, long a0, long a1, long a2) {
    register long x16 __asm__("x16") = nr;
    register long x0 __asm__("x0") = a0;
    register long x1 __asm__("x1") = a1;
    register long x2 __asm__("x2") = a2;
    __asm__ volatile("svc #0x80" : "+r"(x0) : "r"(x16), "r"(x1), "r"(x2) : "memory", "cc");
    return x0;
}

static inline long darwin_mach_trap0(long nr) {
    register long x16 __asm__("x16") = nr;
    register long x0 __asm__("x0");
    __asm__ volatile("svc #0x80" : "=r"(x0) : "r"(x16) : "memory", "cc");
    return x0;
}

static void print(const char* s) {
    long len = 0;
    while (s[len]) len++;
    darwin_syscall3(4, 1, (long)s, len); // SYS_write
}

void _start(int argc, char** argv, char** envp, char** apple) {
    print("[macOS C ARM64] Running C runtime test!\n");
    if (argc >= 1 && argv && argv[0]) {
        print("[macOS C ARM64] Argv[0] is present: ");
        print(argv[0]);
        print("\n");
    }

    // Mach thread self trap (-27)
    long thread_port = darwin_mach_trap0(-27);
    if (thread_port != 0) {
        print("[macOS C ARM64] Mach thread_self port obtained successfully\n");
    }

    print("[macOS C ARM64] All C runtime checks completed!\n");
    darwin_syscall1(1, 0); // SYS_exit(0)
}
