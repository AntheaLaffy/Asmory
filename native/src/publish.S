.section .rodata
fd_prefix: .asciz "/proc/self/fd/"
.section .text
.global asmory_file_publish
.type asmory_file_publish,@function
# SysV64: exclusively owned staging path, destination -> 0 or negative errno.
# Keep the staging link for caller cleanup. Only link the checked inode, even if
# its pathname changes; the caller must keep its contents stable until return.
asmory_file_publish:
    push %rbx
    push %r12
    sub $184, %rsp                 # stat[144], descriptor path[32], saved result
    mov %rsi, %r12
    mov %rdi, %rsi
    mov $-100, %edi
    mov $0xa0800, %edx             # O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
    xor %r10d, %r10d
    mov $257, %eax
    syscall
    test %rax, %rax
    js .publish_return
    mov %rax, %rbx
    mov %rax, %rdi
    mov %rsp, %rsi
    mov $5, %eax
    syscall
    test %rax, %rax
    js .publish_close
    mov 24(%rsp), %eax
    and $0xf000, %eax
    cmp $0x8000, %eax
    jne .publish_invalid
    cmpq $1, 16(%rsp)              # no shared writable aliases to staging
    jne .publish_invalid
    # Refuse an existing destination before changing stage permissions, even
    # when two differently spelled paths identify the same staging file.
    mov $-100, %edi
    mov %r12, %rsi
    mov %rsp, %rdx
    mov $0x100, %r10d              # AT_SYMLINK_NOFOLLOW includes dangling links
    mov $262, %eax                 # newfstatat; linkat still arbitrates races
    syscall
    test %rax, %rax
    jz .publish_exists
    cmp $-2, %rax
    jne .publish_close
    mov %rbx, %rdi
    mov $0444, %esi
    mov $91, %eax                  # fchmod before visibility
    syscall
    test %rax, %rax
    js .publish_close
.publish_sync:
    mov %rbx, %rdi
    mov $74, %eax                  # fsync file data/mode before publication
    syscall
    cmp $-4, %rax
    je .publish_sync
    test %rax, %rax
    js .publish_close
    lea fd_prefix(%rip), %rsi
    lea 144(%rsp), %rdi
    mov $14, %ecx
    rep movsb
    # fd is a nonnegative int: at most ten digits. Write backwards, then
    # append the digits to the prefix without its terminating null.
    lea 175(%rsp), %rsi
    movb $0, (%rsi)
    mov %rbx, %rax
    mov $10, %r9d
.publish_digits:
    xor %edx, %edx
    div %r9
    add $48, %dl
    dec %rsi
    mov %dl, (%rsi)
    test %rax, %rax
    jnz .publish_digits
    lea 158(%rsp), %rdi
.publish_copy:
    lodsb
    stosb
    test %al, %al
    jnz .publish_copy
    mov $-100, %edi
    lea 144(%rsp), %rsi
    mov $-100, %edx
    mov %r12, %r10
    mov $0x400, %r8d               # AT_SYMLINK_FOLLOW for proc fd only
    mov $265, %eax                 # linkat: existing targets always fail
    syscall
.publish_close:
    mov %rax, 176(%rsp)
    mov %rbx, %rdi
    mov $3, %eax
    syscall
    mov 176(%rsp), %rax
.publish_return:
    add $184, %rsp
    pop %r12
    pop %rbx
    ret
.publish_invalid:
    mov $-22, %rax
    jmp .publish_close
.publish_exists:
    mov $-17, %rax
    jmp .publish_close
.size asmory_file_publish,.-asmory_file_publish
.section .note.GNU-stack,"",@progbits
