.section .rodata
plan_magic: .ascii "ASMBLD1\0"
usage: .ascii "usage: asmory-build-runner <plan>\n"
usage_end:
invalid: .ascii "build-runner: invalid build plan\n"
invalid_end:
cwd_error: .ascii "build-runner: cannot enter job directory\n"
cwd_error_end:
.section .bss
.align 8
view: .skip 16
envp: .quad 0
job_argv: .skip 4104
.section .text
.global _start
.type _start,@function
_start:
    cmpq $2, (%rsp)
    jne .usage
    lea 32(%rsp), %rax
    mov %rax, envp(%rip)
    mov 16(%rsp), %rdi
    lea view(%rip), %rsi
    call asmory_file_map
    test %rax, %rax
    js .invalid
    mov view(%rip), %r12
    mov 8+view(%rip), %r13
    cmp $16, %r13
    jb .invalid
    cmp $8388608, %r13
    ja .invalid
    add %r12, %r13
    mov plan_magic(%rip), %rax
    cmp %rax, (%r12)
    jne .invalid
    cmpl $0, 12(%r12)
    jne .invalid
    mov 8(%r12), %r14d
    cmp $4096, %r14d
    ja .invalid
    test %r14d, %r14d
    jz .invalid
    lea 16(%r12), %r15
    xor %ebx, %ebx
    # Validate the entire plan before any child can run.
.validate_job:
    call parse_job
    inc %ebx
    cmp %r14d, %ebx
    jb .validate_job
    cmp %r13, %r15
    jne .invalid
    lea 16(%r12), %r15
    xor %ebx, %ebx
.run_job:
    call parse_job
    mov %rbp, %rdi
    mov $80, %eax
    syscall
    test %rax, %rax
    js .cwd_error
    lea job_argv(%rip), %rdi
    mov envp(%rip), %rsi
    call asmory_process_run
    test %rax, %rax
    js .invalid
    jnz .exit_status
    inc %ebx
    cmp %r14d, %ebx
    jb .run_job
    lea view(%rip), %rdi
    call asmory_file_unmap
    xor %edi, %edi
    jmp .exit

# r15 cursor, r13 end -> rbp=cwd, job_argv, updated cursor.
parse_job:
    sub $8, %rsp
    mov %r13, %rax
    sub %r15, %rax
    cmp $4, %rax
    jb .invalid
    mov (%r15), %r9d
    add $4, %r15
    test %r9d, %r9d
    jz .invalid
    cmp $512, %r9d
    ja .invalid
    mov %r15, %rbp
    call scan_string
    cmpb $'/', (%rbp)
    jne .invalid
    xor %r8d, %r8d
    lea job_argv(%rip), %r10
.parse_arg:
    mov %r15, (%r10,%r8,8)
    call scan_string
    inc %r8d
    cmp %r9d, %r8d
    jb .parse_arg
    movq $0, (%r10,%r8,8)
    mov (%r10), %rax
    cmpb $'/', (%rax)
    jne .invalid
    add $8, %rsp
    ret
scan_string:
    cmp %r13, %r15
    jae .invalid
    cmpb $0, (%r15)
    je .invalid
.scan_next:
    cmp %r13, %r15
    jae .invalid
    movzbl (%r15), %eax
    inc %r15
    test %eax, %eax
    jnz .scan_next
    ret
.usage:
    lea usage(%rip), %rsi
    mov $usage_end-usage, %edx
    jmp .error
.invalid:
    lea invalid(%rip), %rsi
    mov $invalid_end-invalid, %edx
    jmp .error
.cwd_error:
    lea cwd_error(%rip), %rsi
    mov $cwd_error_end-cwd_error, %edx
.error:
    mov $2, %edi
    call asmory_write_all
    mov $25, %edi
    jmp .exit
.exit_status:
    mov %eax, %edi
.exit:
    mov $60, %eax
    syscall
.size _start,.-_start
.section .note.GNU-stack,"",@progbits
