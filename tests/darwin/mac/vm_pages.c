// mmap / vm_allocate in whole 16K pages: alignment, the tail of the last page, hints, fixed vm_allocate on a used range
#include <mach/mach.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

int main(void) {
    long ps = getpagesize();
    printf("pagesize %ld vm_page_size %lu\n", ps, (unsigned long)vm_page_size);
    for (int i = 0; i < 4; i++) {
        size_t len = i == 0 ? 100 : i == 1 ? 5000 : i == 2 ? 16384 : 40000;
        char* p = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        size_t whole = (len + ps - 1) & ~(size_t)(ps - 1);
        p[whole - 1] = 7;                                       // the rest of the last page belongs to the mapping
        printf("mmap %zu: aligned %d tail %d\n", len, ((uintptr_t)p % ps) == 0, p[whole - 1]);
        munmap(p, len);
    }
    char* a = mmap(NULL, 3 * ps, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    munmap(a + ps, ps);                                         // a hole in the middle, then a hint for it
    char* h = mmap(a + ps, 100, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    printf("hint honored %d aligned %d\n", h == a + ps, ((uintptr_t)h % ps) == 0);
    h[ps - 1] = 1;

    vm_address_t va = 0;
    kern_return_t kr = vm_allocate(mach_task_self(), &va, 1000, VM_FLAGS_ANYWHERE);
    printf("vm_allocate anywhere kr=%d aligned %d zero %d\n", kr, (va % vm_page_size) == 0, ((char*)va)[vm_page_size - 1]);
    vm_address_t fixed = (vm_address_t)a;                     // in use: must not be replaced
    a[0] = 42;
    kr = vm_allocate(mach_task_self(), &fixed, ps, VM_FLAGS_FIXED);
    printf("vm_allocate fixed on used range kr=%d data kept %d\n", kr, a[0]);
    kr = vm_deallocate(mach_task_self(), va, 1000);
    printf("vm_deallocate kr=%d\n", kr);
    vm_address_t again = va;
    kr = vm_allocate(mach_task_self(), &again, ps, VM_FLAGS_FIXED);   // the whole page went away
    printf("vm_allocate fixed on freed page kr=%d same %d\n", kr, again == va);
    vm_deallocate(mach_task_self(), again, ps);
    munmap(a, 3 * ps);
    return 0;
}
