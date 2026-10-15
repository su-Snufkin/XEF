.global _main
.align 4

.text
_main:
    // write(1, msg, 27)
    mov x0, #1
    adrp x1, msg@PAGE
    add x1, x1, msg@PAGEOFF
    mov x2, #27
    mov x16, #4          // Darwin SYS_write
    svc #0x80

    // exit(0)
    mov x0, #0
    mov x16, #1          // Darwin SYS_exit
    svc #0x80

.data
msg:
    .ascii "Hello from macOS ARM64!\n\0"
