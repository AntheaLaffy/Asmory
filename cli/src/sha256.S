.section .rodata
hex: .ascii "0123456789abcdef"
error: .ascii "sha256: expected one readable regular file (no final symlink)\n"
error_end:
.section .bss
digest: .skip 32
line: .skip 65
.section .text
.global _start
.type _start,@function
_start:
    cmpq $2, (%rsp)
    jne .failed
    mov 16(%rsp), %rdi
    lea digest(%rip), %rsi
    call asmory_sha256_file
    test %rax, %rax
    js .failed
    lea digest(%rip), %rsi
    lea line(%rip), %rdi
    lea hex(%rip), %r8
    mov $32, %ecx
.encode:
    movzbl (%rsi), %eax
    mov %eax, %edx
    shr $4, %eax
    and $15, %edx
    mov (%r8,%rax), %al
    mov %al, (%rdi)
    mov (%r8,%rdx), %al
    mov %al, 1(%rdi)
    inc %rsi
    add $2, %rdi
    dec %ecx
    jnz .encode
    movb $10, (%rdi)
    mov $1, %edi
    lea line(%rip), %rsi
    mov $65, %edx
    call asmory_write_all
    test %rax, %rax
    js .failed
    xor %edi, %edi
    jmp .exit
.failed:
    mov $2, %edi
    lea error(%rip), %rsi
    mov $error_end-error, %edx
    call asmory_write_all
    mov $28, %edi
.exit:
    mov $60, %eax
    syscall
.size _start,.-_start
.section .note.GNU-stack,"",@progbits
