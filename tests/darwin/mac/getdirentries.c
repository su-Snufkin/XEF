// __getdirentries64 (what Zig/Bun and libc's readdir use): Darwin dirent records, small buffers, continuation
#include <dirent.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

extern ssize_t __getdirentries64(int, char*, size_t, int64_t*);
struct dent { uint64_t ino, seekoff; uint16_t reclen, namlen; uint8_t type; char name[1024]; };

static int cmp(const void* a, const void* b) { return strcmp(*(char* const*)a, *(char* const*)b); }

static void list(const char* dir, size_t bufsize) {
    int fd = open(dir, O_RDONLY | O_DIRECTORY);
    char* buf = malloc(bufsize);
    char* names[256]; int n = 0, calls = 0, bad = 0;
    int64_t base;
    for (;;) {
        ssize_t r = __getdirentries64(fd, buf, bufsize, &base);
        if (r <= 0) break;
        calls++;
        for (ssize_t p = 0; p < r;) {
            struct dent* d = (struct dent*)(buf + p);
            if (d->reclen != ((d->namlen + 32) & ~7) || strlen(d->name) != d->namlen) bad++;
            if (n < 256) {
                names[n] = malloc(d->namlen + 3);
                snprintf(names[n], d->namlen + 3, "%s%c", d->name, d->type == DT_DIR ? '/' : d->type == DT_REG ? ' ' : '?');
                n++;
            }
            p += d->reclen;
        }
    }
    qsort(names, n, sizeof *names, cmp);
    printf("bufsize %zu: %d entries, multiple calls %d, bad records %d:", bufsize, n, calls > 1, bad);
    for (int i = 0; i < n; i++) { printf(" %s", names[i]); free(names[i]); }
    printf("\n");
    free(buf); close(fd);
}

int main(void) {
    char dir[] = "/tmp/xef_gde_XXXXXX";
    if (!mkdtemp(dir)) return 1;
    char p[1200];
    for (int i = 0; i < 40; i++) {
        snprintf(p, sizeof p, "%s/file_with_a_longish_name_%02d.txt", dir, i);
        close(open(p, O_CREAT | O_WRONLY, 0644));
    }
    snprintf(p, sizeof p, "%s/subdir", dir); mkdir(p, 0755);
    list(dir, 8192);
    list(dir, 256);
    for (int i = 0; i < 40; i++) { snprintf(p, sizeof p, "%s/file_with_a_longish_name_%02d.txt", dir, i); unlink(p); }
    snprintf(p, sizeof p, "%s/subdir", dir); rmdir(p); rmdir(dir);
    return 0;
}
