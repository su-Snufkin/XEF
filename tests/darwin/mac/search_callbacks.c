// libc functions taking guest callbacks: tsearch/tfind/tdelete/twalk, lfind/lsearch, qsort_b/bsearch_b/mergesort_b/heapsort.
#include <search.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int cmpi(const void *a, const void *b) { return *(const int *)a - *(const int *)b; }
static int cmps(const void *a, const void *b) { return strcmp(a, b); }
static int depth_max;
static void walk(const void *node, VISIT v, int depth) {
  if (v == postorder || v == leaf) printf("%s(%d) ", *(char *const *)node, depth);
  if (depth > depth_max) depth_max = depth;
}
int main(void) {
  void *root = NULL;
  const char *words[] = {"m", "c", "x", "a", "e", "z", "m"};
  for (int i = 0; i < 7; i++) { void *r = tsearch(words[i], &root, cmps); printf("ins %s -> %s\n", words[i], *(char **)r); }
  printf("tfind e=%s q=%p\n", *(char **)tfind("e", &root, cmps), tfind("q", &root, cmps));
  twalk(root, walk); printf("\n");
  printf("tdelete c parent!=NULL: %d, find c after: %p\n", tdelete("c", &root, cmps) != NULL, tfind("c", &root, cmps));
  int arr[8] = {5, 3, 9}; size_t n = 3; int k = 7;
  int *f = lfind(&k, arr, &n, sizeof(int), cmpi); printf("lfind 7 = %p\n", (void *)f);
  int *l = lsearch(&k, arr, &n, sizeof(int), cmpi); printf("lsearch added %d n=%zu\n", *l, n);
  int v[10] = {4, 8, 1, 9, 3, 7, 2, 6, 5, 0};
  qsort_b(v, 10, sizeof(int), ^(const void *a, const void *b) { return *(const int *)b - *(const int *)a; });
  for (int i = 0; i < 10; i++) printf("%d", v[i]); printf("\n");
  int key = 3;
  int *hit = bsearch_b(&key, v, 10, sizeof(int), ^(const void *a, const void *b) { return *(const int *)b - *(const int *)a; });
  printf("bsearch_b idx=%ld\n", hit ? (long)(hit - v) : -1L);
  struct { int k; char c; } recs[6] = {{2, 'a'}, {1, 'b'}, {2, 'c'}, {1, 'd'}, {3, 'e'}, {2, 'f'}};
  mergesort_b(recs, 6, sizeof recs[0], ^(const void *a, const void *b) { return *(const int *)a - *(const int *)b; });
  for (int i = 0; i < 6; i++) printf("%d%c ", recs[i].k, recs[i].c); printf("\n");
  int h[5] = {3, 1, 2, 5, 4}; heapsort(h, 5, sizeof(int), cmpi); for (int i = 0; i < 5; i++) printf("%d", h[i]); printf("\n");
  return 0;
}
