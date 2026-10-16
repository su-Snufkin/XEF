// mach_vm_map with an alignment mask (JavaScriptCore's structure heap: 4 GB aligned), fixed placement, vm_inherit
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <stdint.h>
#include <stdio.h>

int main(void) {
    mach_vm_address_t a = 0;
    kern_return_t kr = mach_vm_map(mach_task_self(), &a, 1ull << 30, (1ull << 32) - 1, VM_FLAGS_ANYWHERE, MACH_PORT_NULL, 0,
                                   FALSE, VM_PROT_NONE, VM_PROT_ALL, VM_INHERIT_DEFAULT);
    printf("reserve 1G aligned 4G: kr=%d aligned=%d\n", kr, (a & ((1ull << 32) - 1)) == 0);
    kr = mach_vm_protect(mach_task_self(), a, 16384, FALSE, VM_PROT_READ | VM_PROT_WRITE);
    *(volatile int*)a = 5;
    printf("protect+write kr=%d value=%d\n", kr, *(volatile int*)a);
    mach_vm_address_t b = a;
    kr = mach_vm_map(mach_task_self(), &b, 16384, 0, VM_FLAGS_FIXED, MACH_PORT_NULL, 0, FALSE, VM_PROT_DEFAULT, VM_PROT_ALL,
                     VM_INHERIT_DEFAULT);
    printf("fixed over used: kr=%d\n", kr);
    kr = mach_vm_map(mach_task_self(), &b, 16384, 0, VM_FLAGS_FIXED | VM_FLAGS_OVERWRITE, MACH_PORT_NULL, 0, FALSE,
                     VM_PROT_DEFAULT, VM_PROT_ALL, VM_INHERIT_DEFAULT);
    printf("fixed overwrite: kr=%d same=%d zero=%d\n", kr, b == a, *(volatile int*)a);
    printf("inherit none: %d, copy: %d\n", mach_vm_inherit(mach_task_self(), a, 16384, VM_INHERIT_NONE),
           mach_vm_inherit(mach_task_self(), a, 16384, VM_INHERIT_COPY));
    mach_vm_address_t c = 0;
    kr = mach_vm_map(mach_task_self(), &c, 100000, 0xFFFFF, VM_FLAGS_ANYWHERE, MACH_PORT_NULL, 0, FALSE, VM_PROT_DEFAULT,
                     VM_PROT_ALL, VM_INHERIT_DEFAULT);
    printf("1M aligned: kr=%d aligned=%d zero=%d\n", kr, (c & 0xFFFFF) == 0, ((volatile char*)c)[99999]);
    printf("dealloc: %d %d\n", mach_vm_deallocate(mach_task_self(), a, 1ull << 30), mach_vm_deallocate(mach_task_self(), c, 100000));
    return 0;
}
