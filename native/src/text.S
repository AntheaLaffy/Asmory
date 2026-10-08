.section .text
.global asmory_text_equal
.type asmory_text_equal,@function
asmory_text_equal:
    movzbl (%rdi), %eax
    cmpb (%rsi), %al
    jne .text_not_equal
    test %eax, %eax
    jz .text_equal
    inc %rdi
    inc %rsi
    jmp asmory_text_equal
.text_equal:
    mov $1, %eax
    ret
.text_not_equal:
    xor %eax, %eax
    ret
.size asmory_text_equal,.-asmory_text_equal

.global asmory_text_find
.type asmory_text_find,@function
# NUL-terminated haystack, needle -> matching address or 0.
asmory_text_find:
    cmpb $0, (%rsi)
    je .text_found
.text_find_next:
    cmpb $0, (%rdi)
    je .text_not_equal
    xor %ecx, %ecx
.text_find_compare:
    movzbl (%rsi,%rcx), %eax
    test %eax, %eax
    jz .text_found
    cmpb (%rdi,%rcx), %al
    jne .text_find_advance
    inc %rcx
    jmp .text_find_compare
.text_find_advance:
    inc %rdi
    jmp .text_find_next
.text_found:
    mov %rdi, %rax
    ret
.size asmory_text_find,.-asmory_text_find

.global asmory_version_parse
.type asmory_version_parse,@function
# NUL-terminated text, uint32_t[4]* -> end pointer or -EINVAL.
# 2..4 numeric components; omitted trailing components become zero. Each
# component is bounded to 9 digits so probes cannot overflow integer arithmetic.
asmory_version_parse:
    movq $0, (%rsi)
    movq $0, 8(%rsi)
    xor %r8d, %r8d
.version_component:
    xor %r9d, %r9d
    xor %r10d, %r10d
.version_digit:
    movzbl (%rdi), %eax
    sub $'0', %eax
    cmp $9, %eax
    ja .version_component_end
    inc %r10d
    cmp $9, %r10d
    ja .version_invalid
    imul $10, %r9, %r9
    add %rax, %r9
    inc %rdi
    jmp .version_digit
.version_component_end:
    test %r10d, %r10d
    jz .version_invalid
    mov %r9d, (%rsi,%r8,4)
    inc %r8d
    cmpb $'.', (%rdi)
    jne .version_end
    cmp $4, %r8d
    jae .version_invalid
    inc %rdi
    jmp .version_component
.version_end:
    cmp $2, %r8d
    jb .version_invalid
    mov %rdi, %rax
    ret
.version_invalid:
    mov $-22, %rax
    ret
.size asmory_version_parse,.-asmory_version_parse

.global asmory_version_compare
.type asmory_version_compare,@function
# Two parsed uint32_t[4] versions -> -1, 0, +1 (numeric ordering).
asmory_version_compare:
    xor %ecx, %ecx
.version_compare_next:
    mov (%rdi,%rcx,4), %eax
    cmp (%rsi,%rcx,4), %eax
    jb .version_less
    ja .version_greater
    inc %ecx
    cmp $4, %ecx
    jb .version_compare_next
    xor %eax, %eax
    ret
.version_less:
    mov $-1, %eax
    ret
.version_greater:
    mov $1, %eax
    ret
.size asmory_version_compare,.-asmory_version_compare

.global asmory_decimal_parse
.type asmory_decimal_parse,@function
# Decimal C string -> nonnegative signed-64-bit value or -EINVAL.
asmory_decimal_parse:
    xor %eax, %eax
    xor %r8d, %r8d
    movabs $922337203685477580, %r9
.decimal_next:
    movzbl (%rdi), %edx
    test %edx, %edx
    jz .decimal_end
    sub $'0', %edx
    cmp $9, %edx
    ja .decimal_invalid
    cmp %r9, %rax
    ja .decimal_invalid
    jne .decimal_accumulate
    cmp $7, %edx
    ja .decimal_invalid
.decimal_accumulate:
    imul $10, %rax, %rax
    add %rdx, %rax
    inc %rdi
    inc %r8
    jmp .decimal_next
.decimal_end:
    test %r8, %r8
    jz .decimal_invalid
    ret
.decimal_invalid:
    mov $-22, %rax
    ret
.size asmory_decimal_parse,.-asmory_decimal_parse
.section .note.GNU-stack,"",@progbits
