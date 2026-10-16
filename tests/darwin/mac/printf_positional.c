// printf positional arguments (%n$, *m$), mixed types, through printf/snprintf/vsnprintf.
#include <stdarg.h>
#include <stdio.h>
static int vs(char *b, size_t n, const char *f, ...) { va_list ap; va_start(ap, f); int r = vsnprintf(b, n, f, ap); va_end(ap); return r; }
int main(void) {
  printf("%2$s %1$s!\n", "world", "hello");
  printf("OMP: Warning #%1$d: %2$s (%1$x)\n", 255, "msg");
  printf("[%1$*2$d] [%1$-*2$d] [%3$.*4$f]\n", 42, 6, 3.14159, 2);
  printf("%3$c%2$c%1$c %4$lld %5$e\n", 'a', 'b', 'c', -1234567890123LL, 6.02e23);
  char b[64]; int n = snprintf(b, sizeof b, "%2$05.1f|%1$p", (void *)0x10, 2.25); printf("%s %d\n", b, n);
  n = vs(b, sizeof b, "%3$s-%2$s-%1$s", "x", "y", "z"); printf("%s %d\n", b, n);
  return 0;
}
