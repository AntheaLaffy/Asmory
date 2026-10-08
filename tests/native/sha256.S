# Direct SysV64 consumer: unaligned context/output, zero-length updates, arbitrary
# stream splits, overflow refusal and callee-saved register/canary checks.
.macro checked_call symbol
    mov $0x12345678, %ebx
    mov $0x23456789, %ebp
    mov $0x3456789a, %r12d
    mov $0x456789ab, %r13d
    mov $0x56789abc, %r14d
    mov $0x6789abcd, %r15d
    call \symbol
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
.endm
.section .bss
before: .skip 1
context: .skip 112
after: .skip 1
before_digest: .skip 1
digest: .skip 32
after_digest: .skip 1
.align 8
chunk: .skip 8
file_path: .skip 8
buffer: .skip 65536
.section .text
.global _start
_start:
    cmpq $2, (%rsp)
    je .arguments
    cmpq $3, (%rsp)
    jne .failed
    mov 24(%rsp), %rax
    mov %rax, file_path(%rip)
.arguments:
    mov 16(%rsp), %rdi
    call asmory_decimal_parse
    test %rax, %rax
    jz .file_mode
    cmp $1, %rax
    jl .failed
    cmp $65536, %rax
    ja .failed
    mov %rax, chunk(%rip)
.file_mode:
    movb $0x5a, before(%rip)
    movb $0xa5, after(%rip)
    movb $0x3c, before_digest(%rip)
    movb $0xc3, after_digest(%rip)
    cmpq $0, file_path(%rip)
    jne .hash_file
    cmpq $0, chunk(%rip)
    je .failed
    lea context(%rip), %rdi
    checked_call asmory_sha256_init
    lea context(%rip), %rdi
    xor %esi, %esi
    xor %edx, %edx
    checked_call asmory_sha256_update
    test %rax, %rax
    jnz .failed
    movabs $0x1fffffffffffffff, %rax
    mov %rax, context+32(%rip)
    lea context(%rip), %rdi
    xor %esi, %esi           # Overflow must be rejected before dereferencing.
    mov $1, %edx
    checked_call asmory_sha256_update
    cmp $-75, %rax
    jne .failed
    movabs $0x1fffffffffffffff, %rax
    cmp %rax, context+32(%rip)
    jne .failed
    movq $-1, context+32(%rip)
    lea context(%rip), %rdi
    xor %esi, %esi
    mov $1, %edx
    checked_call asmory_sha256_update
    cmp $-75, %rax
    jne .failed
    cmpq $-1, context+32(%rip)
    jne .failed
    lea context(%rip), %rdi
    checked_call asmory_sha256_init
.read:
    xor %edi, %edi
    lea buffer(%rip), %rsi
    mov chunk(%rip), %rdx
    xor %eax, %eax
    syscall
    cmp $-4, %rax
    je .read
    test %rax, %rax
    js .failed
    jz .finish
    mov %rax, %rdx
    lea context(%rip), %rdi
    lea buffer(%rip), %rsi
    checked_call asmory_sha256_update
    test %rax, %rax
    jnz .failed
    jmp .read
.finish:
    lea context(%rip), %rdi
    lea digest(%rip), %rsi
    checked_call asmory_sha256_final
    test %rax, %rax
    jnz .failed
.guards:
    cmpb $0x5a, before(%rip)
    jne .failed
    cmpb $0xa5, after(%rip)
    jne .failed
    cmpb $0x3c, before_digest(%rip)
    jne .failed
    cmpb $0xc3, after_digest(%rip)
    jne .failed
    mov $1, %edi
    lea digest(%rip), %rsi
    mov $32, %edx
    call asmory_write_all
    test %rax, %rax
    js .failed
    xor %edi, %edi
    jmp .exit
.hash_file:
    lea digest(%rip), %rdi
    mov $32, %ecx
    mov $0xaa, %al
    rep stosb
    mov file_path(%rip), %rdi
    lea digest(%rip), %rsi
    checked_call asmory_sha256_file
    test %rax, %rax
    jz .guards
    jns .failed
    lea digest(%rip), %rsi
    mov $32, %ecx
.unchanged:
    cmpb $0xaa, (%rsi)
    jne .failed
    inc %rsi
    loop .unchanged
    cmpb $0x3c, before_digest(%rip)
    jne .failed
    cmpb $0xc3, after_digest(%rip)
    jne .failed
    mov $28, %edi
    jmp .exit
.failed:
    mov $1, %edi
.exit:
    mov $60, %eax
    syscall
.section .note.GNU-stack,"",@progbits
