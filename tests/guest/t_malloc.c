#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct Node { struct Node* next; int key; char data[20]; } Node;
int main(void) {
    Node* buckets[1024] = {0};
    unsigned seed = 1;
    long total = 0;
    for (int i = 0; i < 200000; i++) {
        seed = seed * 1103515245 + 12345;
        int k = (seed >> 8) % 50000;
        Node** pp = &buckets[k & 1023];
        while (*pp && (*pp)->key != k) pp = &(*pp)->next;
        if (*pp) { Node* n = *pp; *pp = n->next; total -= n->key; free(n); }
        else { Node* n = malloc(sizeof(Node)); n->key = k; n->next = 0; snprintf(n->data, 20, "%d", k); *pp = n; total += k; }
        if ((i & 4095) == 0) {
            char* big = malloc(100000 + i);
            memset(big, i & 255, 100000 + i);
            big = realloc(big, 300000 + i);
            total += big[99999];
            free(big);
        }
    }
    long count = 0;
    for (int b = 0; b < 1024; b++)
        for (Node* n = buckets[b]; n; n = n->next) { count++; if (atoi(n->data) != n->key) return 1; }
    void* ptrs[1000];
    for (int i = 0; i < 1000; i++) ptrs[i] = calloc(i + 1, 16);
    for (int i = 0; i < 1000; i += 2) free(ptrs[i]);
    for (int i = 1; i < 1000; i += 2) total += ((char*)ptrs[i])[i] == 0;
    printf("total=%ld count=%ld\n", total, count);
    return 0;
}
