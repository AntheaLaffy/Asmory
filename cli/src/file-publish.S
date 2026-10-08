.section .rodata
error: .ascii "publish: expected single-link regular staging file and absent same-filesystem destination\n"
error_end:
.section .text
.global _start
.type _start,@function
_start:
    cmpq $3, (%rsp)
    jne .failed
    mov 16(%rsp), %rdi
    mov 24(%rsp), %rsi
    call asmory_file_publish
    test %rax, %rax
    js .failed
    xor %edi, %edi
    jmp .exit
.failed:
    mov $2, %edi
    lea error(%rip), %rsi
    mov $error_end-error, %edx
    call asmory_write_all
    mov $12, %edi
.exit:
    mov $60, %eax
    syscall
.size _start,.-_start
.section .note.GNU-stack,"",@progbits
