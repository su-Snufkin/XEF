.global _main
.text
_main:
    mov $0x2000001, %rax
    mov $0, %rdi
    syscall
