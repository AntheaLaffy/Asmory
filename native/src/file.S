.section .text
.global asmory_write_all
.type asmory_write_all,@function
# SysV64: fd, bytes, length -> 0 or negative Linux errno.
asmory_write_all:
    test %rdx, %rdx
    jz .write_done
.write_loop:
    mov $1, %eax
    syscall
    cmp $-4, %rax
    je .write_loop
    test %rax, %rax
    js .write_return
    jz .write_zero
    add %rax, %rsi
    sub %rax, %rdx
    jnz .write_loop
.write_done:
    xor %eax, %eax
.write_return:
    ret
.write_zero:
    mov $-5, %rax
    ret
.size asmory_write_all,.-asmory_write_all

.global asmory_file_map
.type asmory_file_map,@function
# SysV64: path, {address, length}* -> 0 or negative Linux errno.
# Regular files only, no final symlink, at most 64 MiB. The view owns its mmap.
asmory_file_map:
    push %rbx
    push %r12
    sub $152, %rsp
    mov %rsi, %r12
    mov %rdi, %rsi
    mov $-100, %rdi
    mov $0xa0000, %edx             # O_CLOEXEC | O_NOFOLLOW
    xor %r10d, %r10d
    mov $257, %eax
    syscall
    test %rax, %rax
    js .map_return
    mov %rax, %rbx
    mov %rax, %rdi
    mov %rsp, %rsi
    mov $5, %eax
    syscall
    test %rax, %rax
    js .map_close_error
    mov 24(%rsp), %eax
    and $0xf000, %eax
    cmp $0x8000, %eax
    jne .map_invalid
    mov 48(%rsp), %rsi
    test %rsi, %rsi
    jle .map_invalid
    cmp $67108864, %rsi
    ja .map_invalid
    mov %rsi, 8(%r12)
    xor %edi, %edi
    mov $1, %edx                 # PROT_READ
    mov $2, %r10d                # MAP_PRIVATE
    mov %rbx, %r8
    xor %r9d, %r9d
    mov $9, %eax
    syscall
    test %rax, %rax
    js .map_close_error
    mov %rax, (%r12)
    mov %rbx, %rdi
    mov $3, %eax
    syscall
    xor %eax, %eax
    jmp .map_return
.map_invalid:
    mov $-22, %rax
.map_close_error:
    mov %rax, 144(%rsp)
    mov %rbx, %rdi
    mov $3, %eax
    syscall
    mov 144(%rsp), %rax
.map_return:
    add $152, %rsp
    pop %r12
    pop %rbx
    ret
.size asmory_file_map,.-asmory_file_map

.global asmory_file_unmap
.type asmory_file_unmap,@function
asmory_file_unmap:
    mov 8(%rdi), %rsi
    mov (%rdi), %rdi
    mov $11, %eax
    syscall
    ret
.size asmory_file_unmap,.-asmory_file_unmap
.section .note.GNU-stack,"",@progbits
