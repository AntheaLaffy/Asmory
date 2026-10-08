.section .rodata
mode_object: .asciz "object"
mode_leaf: .asciz "leaf"
mode_entry: .asciz "entry"
usage: .ascii "usage: asmory-object-check <object> <object|leaf|entry> [symbol section ... | entry]\n"
usage_end:
invalid: .ascii "object-check: invalid x86-64 ELF relocatable object\n"
invalid_end:
exports_error: .ascii "object-check: export symbol/section contract mismatch\n"
exports_error_end:
undefined_error: .ascii "object-check: leaf has undefined external symbols\n"
undefined_error_end:
entry_error: .ascii "object-check: entry must be a defined global executable symbol\n"
entry_error_end:
.section .bss
.align 8
view: .skip 16
metadata: .skip 64
seen: .skip 128
argc: .quad 0
argv: .quad 0
mode: .quad 0
export_count: .quad 0
.section .text
.global _start
.type _start,@function
_start:
    mov (%rsp), %rax
    mov %rax, argc(%rip)
    lea 8(%rsp), %rax
    mov %rax, argv(%rip)
    cmpq $3, argc(%rip)
    jb .usage
    mov 24(%rsp), %rdi
    lea mode_object(%rip), %rsi
    call asmory_text_equal
    test %eax, %eax
    jnz .object_args
    mov 24(%rsp), %rdi
    lea mode_entry(%rip), %rsi
    call asmory_text_equal
    test %eax, %eax
    jnz .entry_args
    mov 24(%rsp), %rdi
    lea mode_leaf(%rip), %rsi
    call asmory_text_equal
    test %eax, %eax
    jz .usage
    mov argc(%rip), %rax
    sub $3, %rax
    test $1, %al
    jnz .usage
    shr $1, %rax
    test %rax, %rax
    jz .usage
    cmp $128, %rax
    ja .usage
    mov %rax, export_count(%rip)
    movq $1, mode(%rip)
    jmp .map
.entry_args:
    cmpq $4, argc(%rip)
    jne .usage
    movq $2, mode(%rip)
    jmp .map
.object_args:
    cmpq $3, argc(%rip)
    jne .usage
.map:
    mov 16(%rsp), %rdi
    lea view(%rip), %rsi
    call asmory_file_map
    test %rax, %rax
    js .invalid
    lea view(%rip), %rdi
    lea metadata(%rip), %rsi
    call asmory_elf64_object
    test %rax, %rax
    js .invalid
    cmpq $0, mode(%rip)
    je .success
    lea metadata(%rip), %r12
    mov 32(%r12), %r13
    xor %r14d, %r14d
    xor %r15d, %r15d
.symbol:
    movzbl 4(%r13), %eax
    shr $4, %eax
    cmp $1, %eax
    je .global
    cmp $2, %eax
    jne .next
.global:
    mov (%r13), %eax
    add 48(%r12), %rax
    mov %rax, %rbp
    cmpq $2, mode(%rip)
    je .entry
    cmpb $0, (%rbp)
    je .exports_error
    cmpw $0, 6(%r13)
    je .undefined
    movzbl 5(%r13), %eax
    and $3, %eax
    cmp $1, %eax                  # STV_INTERNAL/HIDDEN are package-private
    je .next
    cmp $2, %eax
    je .next
    xor %ebx, %ebx
.find_export:
    mov argv(%rip), %rdx
    lea 3(%rbx,%rbx), %rax
    mov (%rdx,%rax,8), %rsi
    mov %rbp, %rdi
    call asmory_text_equal
    test %eax, %eax
    jnz .found_export
    inc %rbx
    cmp export_count(%rip), %rbx
    jb .find_export
    jmp .exports_error
.found_export:
    lea seen(%rip), %rax
    cmpb $0, (%rax,%rbx)
    jne .exports_error
    movb $1, (%rax,%rbx)
    movzbl 5(%r13), %eax
    and $3, %eax
    cmp $0, %eax
    je .export_section
    cmp $3, %eax
    jne .exports_error
.export_section:
    movzwl 6(%r13), %eax
    cmp 8(%r12), %rax
    jae .exports_error
    shl $6, %rax
    add (%r12), %rax
    testq $2, 8(%rax)             # SHF_ALLOC
    jz .exports_error
    mov (%rax), %edi
    add 16(%r12), %rdi
    mov argv(%rip), %rdx
    lea 4(%rbx,%rbx), %rax
    mov (%rdx,%rax,8), %rsi
    call asmory_text_equal
    test %eax, %eax
    jz .exports_error
    inc %r15
    jmp .next
.entry:
    mov argv(%rip), %rax
    mov 24(%rax), %rsi
    mov %rbp, %rdi
    call asmory_text_equal
    test %eax, %eax
    jz .next
    cmpw $0, 6(%r13)
    je .entry_error
    movzwl 6(%r13), %eax
    cmp 8(%r12), %rax
    jae .entry_error
    shl $6, %rax
    add (%r12), %rax
    mov 8(%r13), %rdx
    cmp 32(%rax), %rdx
    jae .entry_error
    mov 8(%rax), %rax
    and $6, %eax
    cmp $6, %eax                  # SHF_ALLOC | SHF_EXECINSTR
    jne .entry_error
    inc %r15
.next:
    inc %r14
    add $24, %r13
    cmp 40(%r12), %r14
    jb .symbol
    cmpq $2, mode(%rip)
    je .entry_count
    cmp export_count(%rip), %r15
    jne .exports_error
    jmp .success
.entry_count:
    cmp $1, %r15
    jne .entry_error
.success:
    lea view(%rip), %rdi
    call asmory_file_unmap
    xor %edi, %edi
    jmp .exit
.usage:
    lea usage(%rip), %rsi
    mov $usage_end-usage, %edx
    jmp .error
.invalid:
    lea invalid(%rip), %rsi
    mov $invalid_end-invalid, %edx
    jmp .error
.exports_error:
    lea exports_error(%rip), %rsi
    mov $exports_error_end-exports_error, %edx
    jmp .error
.undefined:
    lea undefined_error(%rip), %rsi
    mov $undefined_error_end-undefined_error, %edx
    jmp .error
.entry_error:
    lea entry_error(%rip), %rsi
    mov $entry_error_end-entry_error, %edx
.error:
    mov $2, %edi
    call asmory_write_all
    mov $25, %edi
.exit:
    mov $60, %eax
    syscall
.size _start,.-_start
.section .note.GNU-stack,"",@progbits
