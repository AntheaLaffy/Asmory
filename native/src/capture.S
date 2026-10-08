.section .rodata
default_path: .asciz "/usr/local/bin:/usr/bin:/bin"
.section .text
.global asmory_exec_path
.type asmory_exec_path,@function
# basename/path, argv[], envp[] -> exec replacement or negative errno.
# PATH entries are literal argv boundaries; executable text never gets a shell
# fallback. Relative/empty entries retain their ordinary cwd interpretation.
asmory_exec_path:
    push %rbx
    push %rbp
    push %r12
    push %r13
    push %r14
    push %r15
    sub $4104, %rsp
    mov %rdi, %r12
    mov %rsi, %r13
    mov %rdx, %r14
    mov %rdi, %rax
.path_slash:
    movzbl (%rax), %ecx
    test %ecx, %ecx
    jz .path_environment
    cmp $'/', %cl
    je .path_direct
    inc %rax
    jmp .path_slash
.path_direct:
    mov %r12, %rdi
    mov %r13, %rsi
    mov %r14, %rdx
    mov $59, %eax
    syscall
    jmp .path_return
.path_environment:
    lea default_path(%rip), %rbx
    mov %r14, %rax
.path_env_next:
    mov (%rax), %rcx
    test %rcx, %rcx
    jz .path_start
    cmpb $'P', (%rcx)
    jne .path_env_advance
    cmpb $'A', 1(%rcx)
    jne .path_env_advance
    cmpb $'T', 2(%rcx)
    jne .path_env_advance
    cmpb $'H', 3(%rcx)
    jne .path_env_advance
    cmpb $'=', 4(%rcx)
    jne .path_env_advance
    lea 5(%rcx), %rbx
    jmp .path_start
.path_env_advance:
    add $8, %rax
    jmp .path_env_next
.path_start:
    mov $-2, %rbp
.path_component:
    xor %r15d, %r15d
.path_copy_dir:
    movzbl (%rbx), %eax
    cmp $':', %al
    je .path_dir_end
    test %al, %al
    jz .path_dir_end
    cmp $4093, %r15
    jae .path_long
    mov %al, (%rsp,%r15)
    inc %r15
    inc %rbx
    jmp .path_copy_dir
.path_dir_end:
    test %r15, %r15
    jz .path_name_start
    movb $'/', (%rsp,%r15)
    inc %r15
.path_name_start:
    mov %r12, %rcx
.path_copy_name:
    cmp $4095, %r15
    jae .path_long
    movzbl (%rcx), %eax
    mov %al, (%rsp,%r15)
    inc %rcx
    inc %r15
    test %al, %al
    jnz .path_copy_name
    mov %rsp, %rdi
    mov %r13, %rsi
    mov %r14, %rdx
    mov $59, %eax
    syscall
    cmp $-13, %rax
    jne .path_error_test
    mov %rax, %rbp
    jmp .path_advance
.path_error_test:
    cmp $-2, %rax
    je .path_advance
    cmp $-20, %rax
    jne .path_return
.path_advance:
    cmpb $0, (%rbx)
    je .path_exhausted
    inc %rbx
    jmp .path_component
.path_exhausted:
    mov %rbp, %rax
    jmp .path_return
.path_long:
    mov $-36, %rax
.path_return:
    add $4104, %rsp
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbp
    pop %rbx
    ret
.size asmory_exec_path,.-asmory_exec_path

.global asmory_process_capture
.type asmory_process_capture,@function
# argv[], envp[], output bytes, capacity -> byte count or negative errno.
# Captures stdout, keeps stderr, bounds output and a 5-second monotonic deadline,
# and reaps only its own child even on overflow/read/probe/timeout failures.
asmory_process_capture:
    push %rbx
    push %rbp
    push %r12
    push %r13
    push %r14
    push %r15
    sub $72, %rsp
    mov %rdi, %r12
    mov %rsi, %r13
    mov %rdx, %r14
    mov %rcx, %r15
    xor %ebx, %ebx
    xor %ebp, %ebp
    movq $-1, (%rsp)
    test %r15, %r15
    jz .capture_invalid
    cmp $1048576, %r15
    ja .capture_invalid
    call .capture_clock
    test %rax, %rax
    js .capture_error
    add $5000, %rax
    mov %rax, 32(%rsp)
    mov %rsp, %rdi
    mov $0x80000, %esi            # pipe2 O_CLOEXEC
    mov $293, %eax
    syscall
    test %rax, %rax
    js .capture_error
    mov $57, %eax
    syscall
    test %rax, %rax
    js .capture_error
    jz .capture_child
    mov %rax, %rbp
    mov 4(%rsp), %edi
    mov $3, %eax
    syscall
    movl $-1, 4(%rsp)
    mov (%rsp), %edi
    mov $4, %esi                 # fcntl F_SETFL: parent read end only
    mov $0x800, %edx             # O_NONBLOCK
    mov $72, %eax
    syscall
    test %rax, %rax
    js .capture_error
.capture_read:
    mov (%rsp), %edi
    lea (%r14,%rbx), %rsi
    mov %r15, %rdx
    sub %rbx, %rdx
    jnz .capture_read_bytes
    lea 56(%rsp), %rsi           # one-byte lookahead allows an exact-fit output
    mov $1, %edx
.capture_read_bytes:
    mov $0, %eax
    syscall
    test %rax, %rax
    jz .capture_eof
    cmp $-4, %rax
    je .capture_poll
    cmp $-11, %rax
    je .capture_poll
    test %rax, %rax
    js .capture_error
    cmp %r15, %rbx
    jae .capture_overflow
    add %rax, %rbx
.capture_poll:
    call .capture_remaining
    test %rax, %rax
    js .capture_error
    mov %eax, %edx
    mov (%rsp), %eax
    mov %eax, 8(%rsp)
    movl $1, 12(%rsp)            # POLLIN, revents cleared
    lea 8(%rsp), %rdi
    mov $1, %esi
    mov $7, %eax
    syscall
    cmp $-4, %rax
    je .capture_poll
    test %rax, %rax
    js .capture_error
    jmp .capture_read
.capture_eof:
    mov (%rsp), %edi
    mov $3, %eax
    syscall
    movl $-1, (%rsp)
.capture_wait:
    mov %rbp, %rdi
    lea 16(%rsp), %rsi
    mov $1, %edx                 # WNOHANG; closed stdout is not child exit
    xor %r10d, %r10d
    mov $61, %eax
    syscall
    cmp $-4, %rax
    je .capture_wait
    test %rax, %rax
    js .capture_error
    jnz .capture_finished
    call .capture_remaining
    test %rax, %rax
    js .capture_error
    cmp $10, %eax
    jbe .capture_wait_delay
    mov $10, %eax
.capture_wait_delay:
    mov %eax, %edx
    xor %edi, %edi
    xor %esi, %esi
    mov $7, %eax
    syscall
    jmp .capture_wait
.capture_finished:
    xor %ebp, %ebp              # no kill after reaping: PID may be reused
    cmpl $0, 16(%rsp)
    jne .capture_failed
    mov %rbx, %rax
    jmp .capture_return
.capture_invalid:
    mov $-22, %rax
    jmp .capture_error
.capture_overflow:
    mov $-75, %rax
    jmp .capture_error
.capture_failed:
    mov $-5, %rax
.capture_error:
    mov %rax, 24(%rsp)
    test %rbp, %rbp
    jz .capture_close
    mov %rbp, %rdi
    mov $9, %esi
    mov $62, %eax
    syscall
.capture_reap:
    mov %rbp, %rdi
    lea 16(%rsp), %rsi
    xor %edx, %edx
    xor %r10d, %r10d
    mov $61, %eax
    syscall
    cmp $-4, %rax
    je .capture_reap
.capture_close:
    mov (%rsp), %edi
    test %edi, %edi
    js .capture_close_write
    mov $3, %eax
    syscall
.capture_close_write:
    mov 4(%rsp), %edi
    test %edi, %edi
    js .capture_error_return
    mov $3, %eax
    syscall
.capture_error_return:
    mov 24(%rsp), %rax
.capture_return:
    add $72, %rsp
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbp
    pop %rbx
    ret
.capture_child:
    mov (%rsp), %edi
    mov $3, %eax
    syscall
    mov 4(%rsp), %edi
    mov $1, %esi
    mov $33, %eax
    syscall
    test %rax, %rax
    js .capture_child_failed
    mov $1, %edi
    mov $2, %esi                 # clear CLOEXEC even if dup2(1,1)
    xor %edx, %edx
    mov $72, %eax
    syscall
    test %rax, %rax
    js .capture_child_failed
    mov 4(%rsp), %edi
    cmp $1, %edi
    je .capture_child_exec
    mov $3, %eax
    syscall
.capture_child_exec:
    mov (%r12), %rdi
    mov %r12, %rsi
    mov %r13, %rdx
    call asmory_exec_path
.capture_child_failed:
    mov $127, %edi
    mov $60, %eax
    syscall

# Private monotonic helpers; entry alignment is irrelevant to the syscall.
.capture_clock:
    sub $24, %rsp
    mov $1, %edi
    mov %rsp, %rsi
    mov $228, %eax
    syscall
    test %rax, %rax
    js .capture_clock_return
    mov 8(%rsp), %rax
    xor %edx, %edx
    mov $1000000, %ecx
    div %rcx
    imul $1000, (%rsp), %rdx
    add %rdx, %rax
.capture_clock_return:
    add $24, %rsp
    ret
.capture_remaining:
    sub $8, %rsp
    call .capture_clock
    add $8, %rsp
    test %rax, %rax
    js .capture_remaining_return
    mov 40(%rsp), %rdx           # caller frame deadline; return address adds 8
    sub %rax, %rdx
    test %rdx, %rdx
    jle .capture_timed_out
    mov %rdx, %rax
.capture_remaining_return:
    ret
.capture_timed_out:
    mov $-110, %rax
    ret
.size asmory_process_capture,.-asmory_process_capture
.section .note.GNU-stack,"",@progbits
