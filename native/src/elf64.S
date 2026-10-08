.section .text
.global asmory_elf64_object
.type asmory_elf64_object,@function
# SysV64: file view*, metadata[8]* -> 0 or -EINVAL.
# Metadata: sections/count, section strings/size, symbols/count, strings/size.
# All offsets, names and symbol section indexes are validated before exposure.
asmory_elf64_object:
    push %rbx
    push %rbp
    push %r12
    push %r13
    push %r14
    push %r15
    sub $8, %rsp
    mov (%rdi), %r12
    mov 8(%rdi), %r13
    mov %rsi, %r14
    cmp $64, %r13
    jb .elf_invalid
    cmpl $0x464c457f, (%r12)
    jne .elf_invalid
    cmpb $2, 4(%r12)              # ELFCLASS64
    jne .elf_invalid
    cmpb $1, 5(%r12)              # little endian
    jne .elf_invalid
    cmpb $1, 6(%r12)
    jne .elf_invalid
    cmpw $1, 16(%r12)             # ET_REL
    jne .elf_invalid
    cmpw $62, 18(%r12)            # EM_X86_64
    jne .elf_invalid
    cmpl $1, 20(%r12)
    jne .elf_invalid
    cmpw $64, 52(%r12)
    jne .elf_invalid
    cmpw $0, 56(%r12)             # no program headers in source objects
    jne .elf_invalid
    cmpw $64, 58(%r12)
    jne .elf_invalid
    movzwl 60(%r12), %edx
    test %edx, %edx
    jz .elf_invalid               # extended section counts unsupported
    mov %rdx, 8(%r14)
    shl $6, %rdx
    mov 40(%r12), %rax
    call .elf_range
    test %rax, %rax
    jz .elf_invalid
    mov %rax, (%r14)
    mov %rax, %r15
    movzwl 62(%r12), %eax
    test %eax, %eax
    jz .elf_invalid
    cmp 8(%r14), %rax
    jae .elf_invalid
    shl $6, %rax
    add %r15, %rax
    cmpl $3, 4(%rax)              # SHT_STRTAB
    jne .elf_invalid
    mov 32(%rax), %rdx
    mov %rdx, 24(%r14)
    mov 24(%rax), %rax
    call .elf_range
    test %rax, %rax
    jz .elf_invalid
    cmpq $0, 24(%r14)
    je .elf_invalid
    mov %rax, 16(%r14)
    movq $0, 32(%r14)
    xor %ebx, %ebx
.elf_section:
    mov %rbx, %rbp
    shl $6, %rbp
    add %r15, %rbp
    mov 16(%r14), %rdi
    mov 24(%r14), %rsi
    mov (%rbp), %edx
    call .elf_name
    test %rax, %rax
    jz .elf_invalid
    cmpl $8, 4(%rbp)              # SHT_NOBITS owns no file bytes
    je .elf_section_type
    mov 24(%rbp), %rax
    mov 32(%rbp), %rdx
    call .elf_range
    test %rax, %rax
    jz .elf_invalid
.elf_section_type:
    cmpl $2, 4(%rbp)              # exactly one full symbol table
    jne .elf_section_next
    cmpq $0, 32(%r14)
    jne .elf_invalid
    cmpq $24, 56(%rbp)
    jne .elf_invalid
    mov 32(%rbp), %rax
    xor %edx, %edx
    mov $24, %ecx
    div %rcx
    test %rdx, %rdx
    jnz .elf_invalid
    test %rax, %rax
    jz .elf_invalid
    mov %rax, 40(%r14)
    mov 24(%rbp), %rax
    add %r12, %rax
    mov %rax, 32(%r14)
    mov 40(%rbp), %eax
    cmp 8(%r14), %rax
    jae .elf_invalid
    shl $6, %rax
    add %r15, %rax
    cmpl $3, 4(%rax)
    jne .elf_invalid
    mov 32(%rax), %rdx
    mov %rdx, 56(%r14)
    mov 24(%rax), %rax
    call .elf_range
    test %rax, %rax
    jz .elf_invalid
    cmpq $0, 56(%r14)
    je .elf_invalid
    mov %rax, 48(%r14)
.elf_section_next:
    inc %rbx
    cmp 8(%r14), %rbx
    jb .elf_section
    mov 32(%r14), %rbp
    test %rbp, %rbp
    jz .elf_invalid
    xor %ebx, %ebx
.elf_symbol:
    mov 48(%r14), %rdi
    mov 56(%r14), %rsi
    mov (%rbp), %edx
    call .elf_name
    test %rax, %rax
    jz .elf_invalid
    movzwl 6(%rbp), %eax
    test %eax, %eax
    jz .elf_symbol_next
    cmp 8(%r14), %rax
    jb .elf_symbol_bounds
    cmp $0xfff1, %eax             # SHN_ABS
    je .elf_symbol_next
    cmp $0xfff2, %eax             # SHN_COMMON
    jne .elf_invalid
    jmp .elf_symbol_next
.elf_symbol_bounds:
    shl $6, %rax
    add %r15, %rax
    mov 32(%rax), %rax
    mov 8(%rbp), %rdx
    cmp %rax, %rdx
    ja .elf_invalid
    sub %rdx, %rax
    cmp %rax, 16(%rbp)
    ja .elf_invalid
.elf_symbol_next:
    add $24, %rbp
    inc %rbx
    cmp 40(%r14), %rbx
    jb .elf_symbol
    xor %eax, %eax
    jmp .elf_return
.elf_invalid:
    mov $-22, %rax
.elf_return:
    add $8, %rsp
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbp
    pop %rbx
    ret
.elf_range:
    cmp %r13, %rax
    ja .range_invalid
    mov %r13, %rcx
    sub %rax, %rcx
    cmp %rcx, %rdx
    ja .range_invalid
    add %r12, %rax
    ret
.range_invalid:
    xor %eax, %eax
    ret
.elf_name:
    cmp %rsi, %rdx
    jae .range_invalid
    lea (%rdi,%rdx), %rax
    add %rsi, %rdi
    mov %rax, %rcx
.name_scan:
    cmp %rdi, %rcx
    jae .range_invalid
    cmpb $0, (%rcx)
    je .name_valid
    inc %rcx
    jmp .name_scan
.name_valid:
    ret
.size asmory_elf64_object,.-asmory_elf64_object
.section .note.GNU-stack,"",@progbits
