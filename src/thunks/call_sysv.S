// XEF — generic SysV x86-64 call: the host side of guest->host library thunks.
//
// u64 xef_call_sysv(void* fn, const u64* iregs /*6*/, const u64* fregs /*8*/,
//                   const u64* stack, u64 nstack, u64* xmm0_out)
// Loads rdi..r9 and xmm0..7, pushes `nstack` stack arguments, calls fn and returns rax;
// the low 64 bits of xmm0 are stored to *xmm0_out (float/double results).
    .text
    .globl xef_call_sysv
    .type xef_call_sysv, @function
    .p2align 4
xef_call_sysv:
    push %rbp
    mov %rsp, %rbp
    push %rbx
    push %r12
    push %r13
    push %r14
    mov %rdi, %r11           // fn
    mov %rsi, %r12           // iregs
    mov %rdx, %r13           // fregs
    mov %r9, %r14            // xmm0_out
    // stack arguments: keep rsp 16-byte aligned at the call
    mov %r8, %rax
    shl $3, %rax
    sub %rax, %rsp
    and $-16, %rsp
    xor %rbx, %rbx
1:  cmp %r8, %rbx
    jae 2f
    mov (%rcx,%rbx,8), %rax
    mov %rax, (%rsp,%rbx,8)
    inc %rbx
    jmp 1b
2:  movq 0(%r13), %xmm0
    movq 8(%r13), %xmm1
    movq 16(%r13), %xmm2
    movq 24(%r13), %xmm3
    movq 32(%r13), %xmm4
    movq 40(%r13), %xmm5
    movq 48(%r13), %xmm6
    movq 56(%r13), %xmm7
    mov 0(%r12), %rdi
    mov 8(%r12), %rsi
    mov 16(%r12), %rdx
    mov 24(%r12), %rcx
    mov 32(%r12), %r8
    mov 40(%r12), %r9
    mov $8, %eax             // upper bound of vector registers used (variadic callees)
    call *%r11
    movq %xmm0, (%r14)
    lea -32(%rbp), %rsp
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    pop %rbp
    ret
    .size xef_call_sysv, .-xef_call_sysv
    .section .note.GNU-stack,"",@progbits
