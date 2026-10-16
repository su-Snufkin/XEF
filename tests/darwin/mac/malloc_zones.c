// malloc zone registry: register / promote to zones[0] (as jemalloc does) / unregister
#include <malloc/malloc.h>
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static malloc_zone_t* zone_at(unsigned i, unsigned* n) {
    vm_address_t* zones = NULL;
    if (malloc_get_all_zones(mach_task_self(), NULL, &zones, n) != KERN_SUCCESS) return NULL;
    return i < *n ? (malloc_zone_t*)zones[i] : NULL;
}
static int index_of(malloc_zone_t* z) {
    unsigned n;
    for (unsigned i = 0; zone_at(0, &n), i < n; i++) if (zone_at(i, &n) == z) return (int)i;
    return -1;
}

int main(void) {
    unsigned n0;
    malloc_zone_t* first = zone_at(0, &n0);
    malloc_zone_t* def = malloc_default_zone();
    printf("zones >= 1: %d, default zone usable: %d\n", n0 >= 1, def != NULL && def->malloc != NULL);
    static malloc_zone_t mine;
    memcpy(&mine, first, sizeof mine);
    mine.zone_name = "mine";
    malloc_zone_register(&mine);
    unsigned n1;
    zone_at(0, &n1);
    printf("registered: count +%u, index last %d\n", n1 - n0, index_of(&mine) == (int)n1 - 1);
    malloc_zone_t* purgeable = malloc_default_purgeable_zone();
    for (int i = 0; i < 4 && zone_at(0, &n1) != &mine; i++) {   // jemalloc's zone_promote
        malloc_zone_unregister(first); malloc_zone_register(first);
        malloc_zone_unregister(purgeable); malloc_zone_register(purgeable);
    }
    printf("promoted: zones[0] is mine %d, first still registered %d\n", zone_at(0, &n1) == &mine, index_of(first) >= 0);
    malloc_zone_unregister(&mine);
    printf("unregistered: found %d\n", index_of(&mine));
    void* p = malloc(100);
    printf("malloc still works %d\n", p != NULL);
    free(p);
    return 0;
}
