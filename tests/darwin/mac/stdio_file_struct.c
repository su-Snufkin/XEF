// Darwin FILE layout: getc_unlocked/putc_unlocked/feof_unlocked/ferror_unlocked/clearerr_unlocked/fileno_unlocked are
// macros on struct __sFILE fields; plus fgetln, funopen, fgetpos/fsetpos, freopen, ungetc, memstreams, popen.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int rd(void *c, char *buf, int n) { int *left = c; int k = n < *left ? n : *left; memset(buf, 'z', k); *left -= k; return k; }
static int wr(void *c, const char *buf, int n) { size_t *tot = c; *tot += n; return n; }
static int cl(void *c) { printf("funopen close cookie=%d\n", *(int *)c); return 0; }

int main(void) {
  char path[] = "/tmp/xef_stdio_XXXXXX";
  int fd = mkstemp(path);
  FILE *f = fdopen(fd, "w+");
  printf("fileno ok=%d unlocked=%d\n", fileno(f) == fd, fileno_unlocked(f) == fd);
  for (const char *s = "line one\nline two\nlast"; *s; s++) putc_unlocked(*s, f);
  fflush(f);
  rewind(f);
  int c, n = 0, nl = 0;
  while ((c = getc_unlocked(f)) != EOF) { n++; if (c == '\n') nl++; }
  printf("read %d chars %d newlines feof=%d ferror=%d\n", n, nl, feof_unlocked(f) != 0, ferror_unlocked(f) != 0);
  clearerr_unlocked(f);
  printf("after clearerr feof=%d feof()=%d\n", feof_unlocked(f) != 0, feof(f) != 0);
  fpos_t pos; fseek(f, 5, SEEK_SET); fgetpos(f, &pos);
  printf("fgetpos=%lld getc=%c\n", (long long)pos, getc(f));
  fseek(f, 0, SEEK_END); fsetpos(f, &pos); printf("fsetpos getc=%c\n", getc_unlocked(f));
  ungetc('X', f); printf("ungetc -> %c%c\n", getc_unlocked(f), getc_unlocked(f));
  rewind(f);
  size_t len; char *l;
  while ((l = fgetln(f, &len))) printf("fgetln [%.*s] len=%zu\n", (int)(len && l[len - 1] == '\n' ? len - 1 : len), l, len);
  fclose(f);
  f = fopen(path, "r");
  FILE *g = freopen(path, "a", f);
  printf("freopen same=%d\n", g == f);
  fputs("+more", g); fclose(g);
  f = fopen(path, "r"); char buf[64]; size_t k = fread(buf, 1, sizeof buf, f); buf[k] = 0; fclose(f);
  printf("appended tail=[%s]\n", buf + k - 9);
  unlink(path);
  printf("missing fopen=%p [%8p] [%-6p] [%08p] [%p]\n", (void *)fopen("/nonexistent/xx", "r"), (void *)0x1f, (void *)0xab, (void *)0xc, (void *)0xdeadbeef00);

  int left = 10; size_t tot = 0;
  FILE *fr = funopen(&left, rd, NULL, NULL, cl);
  k = fread(buf, 1, 64, fr); printf("funopen read %zu eof=%d\n", k, feof(fr) != 0); fclose(fr);
  FILE *fw = funopen(&tot, NULL, wr, NULL, NULL);
  fprintf(fw, "%d-%s", 42, "abc"); fclose(fw); printf("funopen wrote %zu\n", tot);

  char *ms; size_t msz; FILE *m = open_memstream(&ms, &msz);
  fprintf(m, "x=%d", 7); putc_unlocked('!', m); fclose(m); printf("memstream [%s] %zu\n", ms, msz); free(ms);
  char mb[] = "abc def"; FILE *fm = fmemopen(mb, strlen(mb), "r"); char w1[8]; fscanf(fm, "%s", w1); printf("fmemopen word=%s\n", w1); fclose(fm);
  FILE *p = popen("echo piped", "r"); fgets(buf, sizeof buf, p); printf("popen=%s", buf); printf("pclose=%d\n", pclose(p));
  printf("stdin fileno=%d stdout=%d stderr=%d\n", fileno(stdin), fileno_unlocked(stdout), fileno(stderr));
  setvbuf(stdout, NULL, _IONBF, 0);
  putc_unlocked('o', stdout); putc_unlocked('k', stdout); putc_unlocked('\n', stdout);
  return 0;
}
