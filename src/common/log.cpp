#include <cstdarg>
#include <cstring>
#include <fcntl.h>
#include <unistd.h>

#include "common/common.h"

namespace xef {

int g_verbose = 0;

static void vemit(const char* prefix, const char* fmt, va_list ap) {
    char buf[2048];
    int n = snprintf(buf, sizeof buf, "%s", prefix);
    n += vsnprintf(buf + n, sizeof buf - n, fmt, ap);
    if (n > (int)sizeof buf - 2) n = sizeof buf - 2;
    buf[n++] = '\n';
    // Write directly: logging must work from signal handlers and with a broken libc state.
    ssize_t r = write(2, buf, n);
    (void)r;
}

void log_msg(const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vemit("xef: ", fmt, ap);
    va_end(ap);
}

// "file+0xoff" for an address, from /proc/self/maps (raw syscalls only: usable in handlers).
const char* describe_addr(u64 addr, char* out, size_t outsz) {
    snprintf(out, outsz, "%#lx", (unsigned long)addr);
    int fd = open("/proc/self/maps", O_RDONLY | O_CLOEXEC);
    if (fd < 0) return out;
    static char buf[1 << 20];
    size_t n = 0;
    ssize_t r;
    while (n < sizeof buf - 1 && (r = read(fd, buf + n, sizeof buf - 1 - n)) > 0) n += (size_t)r;
    close(fd);
    buf[n] = 0;
    for (char* line = buf; line && *line;) {
        char* next = strchr(line, '\n');
        if (next) *next++ = 0;
        unsigned long lo, hi, off;
        char perms[8];
        int pos = 0;
        if (sscanf(line, "%lx-%lx %7s %lx %*s %*s%n", &lo, &hi, perms, &off, &pos) >= 4 && addr >= lo && addr < hi) {
            const char* path = line + pos;
            while (*path == ' ') path++;
            snprintf(out, outsz, "%#lx (%s+%#lx)", (unsigned long)addr, *path ? path : "anon",
                     (unsigned long)(addr - lo + off));
            break;
        }
        line = next;
    }
    return out;
}

void fatal(const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vemit("xef: fatal: ", fmt, ap);
    va_end(ap);
    _exit(132);
}

}  // namespace xef
