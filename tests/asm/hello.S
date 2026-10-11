    .text
    .globl _start
_start:
    mov x0, #1
    adr x1, msg
    mov x2, #len
    mov x8, #64      // write
    svc #0
    mov x0, #42
    mov x8, #93      // exit
    svc #0
    .data
msg: .ascii "Hello from AArch64 under XEF!\n"
    .set len, . - msg
