.section .rodata
error: .ascii "text-splice: invalid edit, input or exclusive output write failed\n"
error_end:
.section .bss
.align 8
source: .skip 16
replacement: .skip 16
offset: .quad 0
removed: .quad 0
output_path: .quad 0
output_fd: .quad 0
created: .quad 0
.section .text
.global _start
.type _start,@function
# Maps source/replacement, validates byte ranges before O_EXCL creation, writes
# prefix + replacement + suffix and fsyncs. It never overwrites a destination.
_start:
    movq $-1, output_fd(%rip)
    cmpq $6, (%rsp)
    jne .failed
    mov 48(%rsp), %rax
    mov %rax, output_path(%rip)
    mov 24(%rsp), %rdi
    call asmory_decimal_parse
    test %rax, %rax
    js .failed
    mov %rax, offset(%rip)
    mov 32(%rsp), %rdi
    call asmory_decimal_parse
    test %rax, %rax
    js .failed
    mov %rax, removed(%rip)
    mov 16(%rsp), %rdi
    lea source(%rip), %rsi
    call asmory_file_map
    test %rax, %rax
    js .failed
    mov 40(%rsp), %rdi
    lea replacement(%rip), %rsi
    call asmory_file_map
    test %rax, %rax
    js .failed
    mov offset(%rip), %rax
    cmp source+8(%rip), %rax
    ja .failed
    mov source+8(%rip), %rdx
    sub %rax, %rdx
    cmp %rdx, removed(%rip)
    ja .failed
    mov $-100, %rdi
    mov output_path(%rip), %rsi
    mov $0xa00c1, %edx           # WRONLY | CREAT | EXCL | CLOEXEC | NOFOLLOW
    mov $0644, %r10d
    mov $257, %eax
    syscall
    test %rax, %rax
    js .failed
    mov %rax, output_fd(%rip)
    movq $1, created(%rip)
    mov %rax, %rdi
    mov source(%rip), %rsi
    mov offset(%rip), %rdx
    call asmory_write_all
    test %rax, %rax
    js .failed
    mov output_fd(%rip), %rdi
    mov replacement(%rip), %rsi
    mov replacement+8(%rip), %rdx
    call asmory_write_all
    test %rax, %rax
    js .failed
    mov offset(%rip), %rax
    add removed(%rip), %rax
    mov source(%rip), %rsi
    add %rax, %rsi
    mov source+8(%rip), %rdx
    sub %rax, %rdx
    mov output_fd(%rip), %rdi
    call asmory_write_all
    test %rax, %rax
    js .failed
    mov output_fd(%rip), %rdi
    mov $74, %eax
    syscall
    test %rax, %rax
    js .failed
    mov output_fd(%rip), %rdi
    mov $3, %eax
    syscall
    movq $-1, output_fd(%rip)
    test %rax, %rax
    js .failed
    lea source(%rip), %rdi
    call asmory_file_unmap
    lea replacement(%rip), %rdi
    call asmory_file_unmap
    xor %edi, %edi
    jmp .exit
.failed:
    mov output_fd(%rip), %rdi
    test %rdi, %rdi
    js .failed_unlink
    mov $3, %eax
    syscall
.failed_unlink:
    cmpq $0, created(%rip)
    je .failed_message
    mov $-100, %rdi
    mov output_path(%rip), %rsi
    xor %edx, %edx
    mov $263, %eax
    syscall
.failed_message:
    mov $2, %edi
    lea error(%rip), %rsi
    mov $error_end-error, %edx
    call asmory_write_all
    mov $27, %edi
.exit:
    mov $60, %eax
    syscall
.size _start,.-_start
.section .note.GNU-stack,"",@progbits
