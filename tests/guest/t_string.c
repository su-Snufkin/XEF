#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
static int cmp(const void* a, const void* b) { return strcmp(*(char**)a, *(char**)b); }
static int icmp(const void* a, const void* b) { int x = *(int*)a, y = *(int*)b; return (x > y) - (x < y); }
int main(void) {
    static char buf[8192], buf2[8192];
    unsigned h = 0;
    for (int al = 0; al < 16; al++)
        for (int len = 0; len < 300; len += 7) {
            for (int i = 0; i < len; i++) buf[al + i] = (char)('a' + (i * 7 + al) % 26);
            buf[al + len] = 0;
            h = h * 31 + strlen(buf + al);
            memcpy(buf2 + (al ^ 5), buf + al, len + 1);
            h = h * 31 + (unsigned)(strcmp(buf2 + (al ^ 5), buf + al) > 0);
            memmove(buf + al + 3, buf + al, len);
            h = h * 31 + (unsigned char)buf[al + len / 2 + 3];
            memset(buf + al, 'x', len / 2);
            h = h * 31 + (unsigned)(strchr(buf + al, 'y') ? 1 : 0) + (unsigned)(memchr(buf + al, 'q', len + 3) != 0);
            h = h * 31 + (unsigned)(strncmp(buf + al, buf2 + (al ^ 5), len / 3) > 0);
            char* p = strstr(buf2 + (al ^ 5), "nu");
            h = h * 31 + (p ? (unsigned)(p - buf2) : 7);
            h = h * 31 + (unsigned)strspn(buf2 + (al ^ 5), "abcdefg") + (unsigned)(strrchr(buf2 + 5, 'a') ? strrchr(buf2 + 5, 'a') - buf2 : 1);
        }
    printf("h=%u\n", h);
    char* words[] = {"pear", "apple", "fig", "banana", "kiwi", "cherry", "date", "grape", "lemon", "mango"};
    qsort(words, 10, sizeof(char*), cmp);
    for (int i = 0; i < 10; i++) printf("%s%c", words[i], i == 9 ? '\n' : ' ');
    int arr[1000];
    for (int i = 0; i < 1000; i++) arr[i] = (i * 7919) % 1000 - 500;
    qsort(arr, 1000, sizeof(int), icmp);
    printf("%d %d %d\n", arr[0], arr[500], arr[999]);
    char out[256];
    snprintf(out, sizeof out, "%5d|%-8s|%08.3f|%x|%c|%%|%lu", 42, "hi", 3.14159, 255, 'Z', 123456789012UL);
    puts(out);
    int a, b; char w[32]; double d;
    sscanf("12 34 word 5.5", "%d %d %31s %lf", &a, &b, w, &d);
    printf("%d %d %s %g %d\n", a, b, w, d, toupper('q'));
    char* dup = strdup("Hello, World");
    for (char* c = dup; *c; c++) *c = (char)tolower(*c);
    printf("%s %zu\n", dup, strlen(dup));
    free(dup);
    return 0;
}
