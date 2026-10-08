.section .bss
result: .skip 8
.section .text
.global _start
_start:
    cmpq $3, (%rsp)
    jne .failed
    mov 16(%rsp), %rdi
    mov 24(%rsp), %rsi
    mov $0x12345678, %ebx
    mov $0x23456789, %ebp
    mov $0x3456789a, %r12d
    mov $0x456789ab, %r13d
    mov $0x56789abc, %r14d
    mov $0x6789abcd, %r15d
    call asmory_file_publish
    cmp $0x12345678, %rbx
    jne .failed
    cmp $0x23456789, %rbp
    jne .failed
    cmp $0x3456789a, %r12
    jne .failed
    cmp $0x456789ab, %r13
    jne .failed
    cmp $0x56789abc, %r14
    jne .failed
    cmp $0x6789abcd, %r15
    jne .failed
    mov %rax, result(%rip)
    mov $1, %edi
    lea result(%rip), %rsi
    mov $8, %edx
    call asmory_write_all
    test %rax, %rax
    js .failed
    xor %edi, %edi
    jmp .exit
.failed:
    mov $1, %edi
.exit:
    mov $60, %eax
    syscall
.section .note.GNU-stack,"",@progbits
