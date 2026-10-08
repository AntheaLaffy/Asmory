.section .rodata
gas: .asciz "gas"
att: .asciz "att"
intel: .asciz "intel"
as_name: .asciz "as"
as_version: .asciz "--version"
locale_c: .asciz "LC_ALL=C"
gnu_prefix: .asciz "GNU assembler "
target_prefix: .asciz "target of `x86_64-"
target_linux: .asciz "linux"
target_elf: .asciz "elf"
requires: .asciz "toolchain: GAS below minimum; requires "
found: .asciz ", found "
newline: .asciz "\n"
usage: .asciz "usage: asmory-toolchain-check gas <numeric-min-version> <att|intel>\n"
unsupported: .asciz "toolchain: supported source build adapter is gas with att/intel syntax\n"
invalid_version: .asciz "toolchain: invalid numeric minimum version (2..4 components, <=9 digits each)\n"
missing: .asciz "toolchain: GNU as unavailable or version probe failed\n"
wrong_target: .asciz "toolchain: GNU as must target x86-64 ELF (Linux or bare ELF)\n"
.align 8
as_argv: .quad as_name, as_version, 0
.section .bss
.align 8
minimum: .skip 16
actual: .skip 16
minimum_text: .quad 0
actual_text: .quad 0
actual_end: .quad 0
output: .skip 8192
tool_env: .skip 32776
.section .text
.global _start
.type _start,@function
_start:
    cmpq $4, (%rsp)
    jne .usage
    mov 24(%rsp), %rax
    mov %rax, minimum_text(%rip)
    mov 16(%rsp), %rdi
    lea gas(%rip), %rsi
    call asmory_text_equal
    test %eax, %eax
    jz .unsupported
    mov 32(%rsp), %rdi
    lea att(%rip), %rsi
    call asmory_text_equal
    test %eax, %eax
    jnz .parse_minimum
    mov 32(%rsp), %rdi
    lea intel(%rip), %rsi
    call asmory_text_equal
    test %eax, %eax
    jz .unsupported
.parse_minimum:
    mov minimum_text(%rip), %rdi
    lea minimum(%rip), %rsi
    call asmory_version_parse
    test %rax, %rax
    js .invalid_version
    cmpb $0, (%rax)
    jne .invalid_version
    # Force a stable probe language while retaining the caller's literal PATH.
    lea 48(%rsp), %r12
    lea tool_env(%rip), %r13
    xor %ebx, %ebx
.copy_env:
    mov (%r12), %rax
    test %rax, %rax
    jz .env_end
    cmpb $'L', (%rax)
    jne .keep_env
    cmpb $'C', 1(%rax)
    jne .keep_env
    cmpb $'_', 2(%rax)
    jne .keep_env
    cmpb $'A', 3(%rax)
    jne .keep_env
    cmpb $'L', 4(%rax)
    jne .keep_env
    cmpb $'L', 5(%rax)
    jne .keep_env
    cmpb $'=', 6(%rax)
    je .env_next
.keep_env:
    cmp $4095, %rbx
    jae .probe_failed
    mov %rax, (%r13,%rbx,8)
    inc %rbx
.env_next:
    add $8, %r12
    jmp .copy_env
.env_end:
    lea locale_c(%rip), %rax
    mov %rax, (%r13,%rbx,8)
    inc %rbx
    movq $0, (%r13,%rbx,8)
    lea as_argv(%rip), %rdi
    mov %r13, %rsi
    lea output(%rip), %rdx
    mov $8191, %ecx
    call asmory_process_capture
    test %rax, %rax
    jle .probe_failed
    lea output(%rip), %r12
    movb $0, (%r12,%rax)
    mov %r12, %rdi
    lea gnu_prefix(%rip), %rsi
    call asmory_text_find
    cmp %r12, %rax
    jne .probe_failed
    lea 14(%r12), %rdi
    xor %r13d, %r13d
.find_vendor_end:
    movzbl (%rdi), %eax
    test %eax, %eax
    jz .vendor_end_found
    cmp $10, %eax
    je .vendor_end_found
    cmp $')', %eax
    jne .vendor_end_next
    lea 1(%rdi), %r13
.vendor_end_next:
    inc %rdi
    jmp .find_vendor_end
.vendor_end_found:
    test %r13, %r13
    jz .probe_failed
    mov %r13, %rdi
.find_version:
    movzbl (%rdi), %eax
    test %eax, %eax
    jz .probe_failed
    cmp $10, %eax
    je .probe_failed
    sub $'0', %eax
    cmp $9, %eax
    jbe .parse_actual
    inc %rdi
    jmp .find_version
.parse_actual:
    mov %rdi, actual_text(%rip)
    lea actual(%rip), %rsi
    call asmory_version_parse
    test %rax, %rax
    js .probe_failed
    mov %rax, actual_end(%rip)
    mov %r12, %rdi
    lea target_prefix(%rip), %rsi
    call asmory_text_find
    test %rax, %rax
    jz .wrong_target
    lea 11(%rax), %r13            # target token, through its closing quote
    mov %r13, %rax
.target_end:
    movzbl (%rax), %edx
    test %edx, %edx
    jz .wrong_target
    cmp $10, %edx
    je .wrong_target
    cmp $39, %edx
    je .target_terminated
    inc %rax
    jmp .target_end
.target_terminated:
    movb $0, (%rax)
    mov %r13, %rdi
    lea target_linux(%rip), %rsi
    call asmory_text_find
    test %rax, %rax
    jnz .compare_version
    mov %r13, %rdi
    lea target_elf(%rip), %rsi
    call asmory_text_find
    test %rax, %rax
    jz .wrong_target
.compare_version:
    lea actual(%rip), %rdi
    lea minimum(%rip), %rsi
    call asmory_version_compare
    test %eax, %eax
    js .too_old
    xor %edi, %edi
    jmp .exit
.too_old:
    mov actual_end(%rip), %rax
    movb $0, (%rax)
    lea requires(%rip), %rdi
    call print_error
    mov minimum_text(%rip), %rdi
    call print_error
    lea found(%rip), %rdi
    call print_error
    mov actual_text(%rip), %rdi
    call print_error
    lea newline(%rip), %rdi
    call print_error
    jmp .failed
.usage:
    lea usage(%rip), %rdi
    jmp .error
.unsupported:
    lea unsupported(%rip), %rdi
    jmp .error
.invalid_version:
    lea invalid_version(%rip), %rdi
    jmp .error
.probe_failed:
    lea missing(%rip), %rdi
    jmp .error
.wrong_target:
    lea wrong_target(%rip), %rdi
.error:
    call print_error
.failed:
    mov $26, %edi
.exit:
    mov $60, %eax
    syscall
print_error:
    mov %rdi, %rsi
    xor %edx, %edx
.error_length:
    cmpb $0, (%rsi,%rdx)
    je .error_write
    inc %rdx
    jmp .error_length
.error_write:
    mov $2, %edi
    jmp asmory_write_all
.size _start,.-_start
.section .note.GNU-stack,"",@progbits
