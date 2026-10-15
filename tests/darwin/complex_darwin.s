.global _main
.align 4

.text
_main:
    // 1. Print header
    mov x0, #1
    adrp x1, msg_start@PAGE
    add x1, x1, msg_start@PAGEOFF
    mov x2, #34
    mov x16, #4          // Darwin SYS_write
    svc #0x80

    // 2. Call Darwin getpid (SYS_getpid = 20)
    mov x16, #20
    svc #0x80
    // Result: x0 = pid, x1 = ppid
    cmp x0, #0
    b.le err_exit

    // 3. Call Mach timebase trap (DARWIN_MACH_timebase_info = -89)
    sub sp, sp, #16
    mov x0, sp           // pointer to struct { uint32_t numer, denom }
    mov x16, #-89        // Mach trap -89
    svc #0x80

    // Check numer != 0
    ldr w2, [sp]
    cmp w2, #0
    b.eq err_exit
    add sp, sp, #16

    // 4. Test Darwin mmap (SYS_mmap = 197)
    // mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)
    mov x0, #0           // addr = NULL
    mov x1, #4096        // len = 4096
    mov x2, #3           // prot = PROT_READ | PROT_WRITE
    mov x3, #0x1002      // flags = DARWIN_MAP_PRIVATE | DARWIN_MAP_ANONYMOUS
    mov x4, #-1          // fd = -1
    mov x5, #0           // offset = 0
    mov x16, #197        // Darwin SYS_mmap
    svc #0x80
    b.cs err_exit        // In Darwin, Carry set means error!

    // Write to allocated memory
    mov x1, #0x1234
    movk x1, #0x5678, lsl #16
    str x1, [x0]
    ldr x2, [x0]
    cmp x1, x2
    b.ne err_exit

    // munmap (SYS_munmap = 73)
    mov x1, #4096
    mov x16, #73
    svc #0x80
    b.cs err_exit

    // 5. Test NEON / SIMD math
    fmov d0, #1.5
    fmov d1, #2.5
    fadd d2, d0, d1     // d2 = 4.0
    fmov d3, #4.0
    fcmp d2, d3
    b.ne err_exit

    // 6. Print success message
    mov x0, #1
    adrp x1, msg_ok@PAGE
    add x1, x1, msg_ok@PAGEOFF
    mov x2, #38
    mov x16, #4
    svc #0x80

    // exit(0)
    mov x0, #0
    mov x16, #1
    svc #0x80

err_exit:
    mov x0, #1
    mov x16, #1
    svc #0x80

.data
msg_start:
    .ascii "[Darwin ARM64] Running test suite\n\0"
msg_ok:
    .ascii "[Darwin ARM64] All tests PASSED OK!\n\0"
