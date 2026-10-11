// run_test(state* x0, code* x1): load full register state, call code, store state.
// state layout: x[0..27] @0, nzcv @224, fpcr @232, v[0..31] @240 (16 bytes each)
    .text
    .globl run_test
    .type run_test, %function
run_test:
    stp x29, x30, [sp, -160]!
    stp x19, x20, [sp, 16]
    stp x21, x22, [sp, 32]
    stp x23, x24, [sp, 48]
    stp x25, x26, [sp, 64]
    stp x27, x28, [sp, 80]
    stp d8, d9, [sp, 96]
    stp d10, d11, [sp, 112]
    stp d12, d13, [sp, 128]
    stp d14, d15, [sp, 144]
    mov x29, x0
    mov x28, x1
    add x2, x29, 240
    ld1 {v0.16b-v3.16b}, [x2], 64
    ld1 {v4.16b-v7.16b}, [x2], 64
    ld1 {v8.16b-v11.16b}, [x2], 64
    ld1 {v12.16b-v15.16b}, [x2], 64
    ld1 {v16.16b-v19.16b}, [x2], 64
    ld1 {v20.16b-v23.16b}, [x2], 64
    ld1 {v24.16b-v27.16b}, [x2], 64
    ld1 {v28.16b-v31.16b}, [x2], 64
    ldr x2, [x29, 224]
    msr nzcv, x2
    ldp x0, x1, [x29, 0]
    ldp x2, x3, [x29, 16]
    ldp x4, x5, [x29, 32]
    ldp x6, x7, [x29, 48]
    ldp x8, x9, [x29, 64]
    ldp x10, x11, [x29, 80]
    ldp x12, x13, [x29, 96]
    ldp x14, x15, [x29, 112]
    ldp x16, x17, [x29, 128]
    ldp x18, x19, [x29, 144]
    ldp x20, x21, [x29, 160]
    ldp x22, x23, [x29, 176]
    ldp x24, x25, [x29, 192]
    ldp x26, x27, [x29, 208]
    blr x28
    stp x0, x1, [x29, 0]
    stp x2, x3, [x29, 16]
    stp x4, x5, [x29, 32]
    stp x6, x7, [x29, 48]
    stp x8, x9, [x29, 64]
    stp x10, x11, [x29, 80]
    stp x12, x13, [x29, 96]
    stp x14, x15, [x29, 112]
    stp x16, x17, [x29, 128]
    stp x18, x19, [x29, 144]
    stp x20, x21, [x29, 160]
    stp x22, x23, [x29, 176]
    stp x24, x25, [x29, 192]
    stp x26, x27, [x29, 208]
    mrs x0, nzcv
    str x0, [x29, 224]
    add x0, x29, 240
    st1 {v0.16b-v3.16b}, [x0], 64
    st1 {v4.16b-v7.16b}, [x0], 64
    st1 {v8.16b-v11.16b}, [x0], 64
    st1 {v12.16b-v15.16b}, [x0], 64
    st1 {v16.16b-v19.16b}, [x0], 64
    st1 {v20.16b-v23.16b}, [x0], 64
    st1 {v24.16b-v27.16b}, [x0], 64
    st1 {v28.16b-v31.16b}, [x0], 64
    ldp x19, x20, [sp, 16]
    ldp x21, x22, [sp, 32]
    ldp x23, x24, [sp, 48]
    ldp x25, x26, [sp, 64]
    ldp x27, x28, [sp, 80]
    ldp d8, d9, [sp, 96]
    ldp d10, d11, [sp, 112]
    ldp d12, d13, [sp, 128]
    ldp d14, d15, [sp, 144]
    ldp x29, x30, [sp], 160
    ret
