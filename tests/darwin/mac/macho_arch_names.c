// <mach-o/utils.h> macho_arch_name_for_cpu_type (CMake asks it for the target architecture)
#include <mach-o/utils.h>
#include <mach/machine.h>
#include <stdio.h>

int main(void) {
    struct { cpu_type_t t; cpu_subtype_t s; } c[] = {
        {CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL}, {CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64E}, {CPU_TYPE_ARM64, (cpu_subtype_t)(CPU_SUBTYPE_ARM64E | CPU_SUBTYPE_PTRAUTH_ABI)},
        {CPU_TYPE_X86_64, CPU_SUBTYPE_X86_64_ALL}, {CPU_TYPE_X86_64, CPU_SUBTYPE_X86_64_H}, {CPU_TYPE_ARM64_32, CPU_SUBTYPE_ARM64_32_V8},
        {CPU_TYPE_I386, CPU_SUBTYPE_I386_ALL}, {CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7}, {CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7S}, {12345, 0}};
    for (unsigned i = 0; i < sizeof c / sizeof *c; i++) {
        const char* n = macho_arch_name_for_cpu_type(c[i].t, c[i].s);
        printf("%#x/%#x -> %s\n", (unsigned)c[i].t, (unsigned)c[i].s, n ? n : "(null)");
    }
    return 0;
}
