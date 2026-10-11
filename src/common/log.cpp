#include <cstdarg>
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

void fatal(const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vemit("xef: fatal: ", fmt, ap);
    va_end(ap);
    _exit(132);
}

}  // namespace xef
