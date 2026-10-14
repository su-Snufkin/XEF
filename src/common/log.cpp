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
// Read line by line through a small stack buffer: reentrant, and any size of maps works.
const char* describe_addr(u64 addr, char* out, size_t outsz) {
    snprintf(out, outsz, "%#lx", (unsigned long)addr);
    int fd = open("/proc/self/maps", O_RDONLY | O_CLOEXEC);
    if (fd < 0) return out;
    char buf[8192];
    size_t n = 0;
    bool eof = false, found = false;
    while (!found) {
        if (!eof && n < sizeof buf - 1) {
            ssize_t r = read(fd, buf + n, sizeof buf - 1 - n);
            if (r <= 0) eof = true;
            else n += (size_t)r;
        }
        buf[n] = 0;
        char* nl = strchr(buf, '\n');
        if (!nl) {
            if (eof || n == sizeof buf - 1) { if (!n) break; nl = buf + n; }   // last or overlong line
            else continue;
        }
        *nl = 0;
        unsigned long lo, hi, off;
        char perms[8];
        int pos = 0;
        if (sscanf(buf, "%lx-%lx %7s %lx %*s %*s%n", &lo, &hi, perms, &off, &pos) >= 4 && addr >= lo && addr < hi) {
            const char* path = buf + pos;
            while (*path == ' ') path++;
            snprintf(out, outsz, "%#lx (%s+%#lx)", (unsigned long)addr, *path ? path : "anon",
                     (unsigned long)(addr - lo + off));
            found = true;
        }
        size_t used = (size_t)(nl - buf) + (nl < buf + n ? 1 : 0);
        memmove(buf, buf + used, n - used);
        n -= used;
    }
    close(fd);
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
