.section .rodata
exec_error: .ascii "build-runner: execve failed\n"
exec_error_end:
.section .text
.global asmory_process_run
.type asmory_process_run,@function
# SysV64: absolute-path argv[], envp[] -> exit status, 128+signal, or errno.
# No shell expansion or PATH search. The caller controls cwd and environment.
asmory_process_run:
    push %rbx
    push %r12
    push %r13
    sub $16, %rsp
    mov %rdi, %r12
    mov %rsi, %r13
    mov $57, %eax
    syscall
    test %rax, %rax
    js .process_return
    jz .process_child
    mov %rax, %rbx
.process_wait:
    mov %rbx, %rdi
    mov %rsp, %rsi
    xor %edx, %edx
    xor %r10d, %r10d
    mov $61, %eax
    syscall
    cmp $-4, %rax
    je .process_wait
    test %rax, %rax
    js .process_return
    mov (%rsp), %eax
    mov %eax, %edx
    and $0x7f, %edx
    jnz .process_signal
    shr $8, %eax
    and $255, %eax
    jmp .process_return
.process_signal:
    lea 128(%rdx), %eax
.process_return:
    add $16, %rsp
    pop %r13
    pop %r12
    pop %rbx
    ret
.process_child:
    mov (%r12), %rdi
    mov %r12, %rsi
    mov %r13, %rdx
    mov $59, %eax
    syscall
    mov $2, %edi
    lea exec_error(%rip), %rsi
    mov $exec_error_end-exec_error, %edx
    call asmory_write_all
    mov $127, %edi
    mov $60, %eax
    syscall
.size asmory_process_run,.-asmory_process_run

.section .rodata
self_path: .asciz "/proc/self/exe"
.section .text
.global asmory_exec_sibling
.type asmory_exec_sibling,@function
# SysV64: basename, argv[], envp[] -> negative errno if execve returns.
# Helpers are installed beside the caller; no shell or ambient PATH is needed.
asmory_exec_sibling:
    push %rbx
    push %r12
    push %r13
    push %r14
    sub $4104, %rsp
    mov %rdi, %r12
    mov %rsi, %r13
    mov %rdx, %r14
    lea self_path(%rip), %rdi
    mov %rsp, %rsi
    mov $4095, %edx
    mov $89, %eax
    syscall
    test %rax, %rax
    js .sibling_return
    cmp $4095, %rax
    jae .sibling_long
    xor %ecx, %ecx
    xor %ebx, %ebx
.sibling_scan:
    cmpb $'/', (%rsp,%rcx)
    jne .sibling_next
    lea 1(%rcx), %rbx
.sibling_next:
    inc %rcx
    cmp %rax, %rcx
    jb .sibling_scan
    test %rbx, %rbx
    jz .sibling_invalid
    cmpb $0, (%r12)
    je .sibling_invalid
.sibling_copy:
    cmp $4095, %rbx
    jae .sibling_long
    movzbl (%r12), %eax
    cmp $'/', %al
    je .sibling_invalid
    mov %al, (%rsp,%rbx)
    inc %rbx
    inc %r12
    test %al, %al
    jnz .sibling_copy
    mov %rsp, %rdi
    mov %r13, %rsi
    mov %r14, %rdx
    mov $59, %eax
    syscall
    jmp .sibling_return
.sibling_long:
    mov $-36, %rax
    jmp .sibling_return
.sibling_invalid:
    mov $-22, %rax
.sibling_return:
    add $4104, %rsp
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    ret
.size asmory_exec_sibling,.-asmory_exec_sibling

.global asmory_process_run_sibling
.type asmory_process_run_sibling,@function
# helper basename, argv[], envp[] -> exit code, 128+signal or negative errno.
asmory_process_run_sibling:
    push %rbx
    push %r12
    push %r13
    push %r14
    sub $24, %rsp
    mov %rdi, %r12
    mov %rsi, %r13
    mov %rdx, %r14
    mov $57, %eax
    syscall
    test %rax, %rax
    js .sibling_run_return
    jz .sibling_run_child
    mov %rax, %rbx
.sibling_run_wait:
    mov %rbx, %rdi
    mov %rsp, %rsi
    xor %edx, %edx
    xor %r10d, %r10d
    mov $61, %eax
    syscall
    cmp $-4, %rax
    je .sibling_run_wait
    test %rax, %rax
    js .sibling_run_return
    mov (%rsp), %eax
    mov %eax, %edx
    and $0x7f, %edx
    jnz .sibling_run_signal
    shr $8, %eax
    and $255, %eax
    jmp .sibling_run_return
.sibling_run_signal:
    lea 128(%rdx), %eax
.sibling_run_return:
    add $24, %rsp
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    ret
.sibling_run_child:
    mov %r12, %rdi
    mov %r13, %rsi
    mov %r14, %rdx
    call asmory_exec_sibling
    mov $127, %edi
    mov $60, %eax
    syscall
.size asmory_process_run_sibling,.-asmory_process_run_sibling
.section .note.GNU-stack,"",@progbits
