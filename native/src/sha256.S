# SHA-256, FIPS 180-4. Context: h[8] u32, byte count u64, buffered u64,
# then 64 bytes. Caller owns 112 bytes; no alignment or ISA extension required.
.section .rodata
.align 4
.sha_initial:
    .long 0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a
    .long 0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
.sha_k:
    .long 0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5
    .long 0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5
    .long 0xd807aa98,0x12835b01,0x243185be,0x550c7dc3
    .long 0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174
    .long 0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc
    .long 0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da
    .long 0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7
    .long 0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967
    .long 0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13
    .long 0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85
    .long 0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3
    .long 0xd192e819,0xd6990624,0xf40e3585,0x106aa070
    .long 0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5
    .long 0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3
    .long 0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208
    .long 0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
.section .text
.global asmory_sha256_init
.type asmory_sha256_init,@function
asmory_sha256_init:
    lea .sha_initial(%rip), %rsi
    mov $8, %ecx
    rep movsl
    xor %eax, %eax
    mov $10, %ecx
    rep stosq
    ret
.size asmory_sha256_init,.-asmory_sha256_init

# Internal compression: context, one complete block. Stack schedule is private.
.type .sha_compress,@function
.sha_compress:
    push %rbx
    push %rbp
    push %r12
    push %r13
    push %r14
    push %r15
    sub $264, %rsp
    mov %rdi, 256(%rsp)
    xor %ecx, %ecx
.sha_words:
    mov (%rsi,%rcx,4), %eax
    bswap %eax
    mov %eax, (%rsp,%rcx,4)
    inc %ecx
    cmp $16, %ecx
    jb .sha_words
.sha_expand:
    mov -60(%rsp,%rcx,4), %eax
    mov %eax, %edx
    mov %eax, %r8d
    ror $7, %eax
    ror $18, %edx
    shr $3, %r8d
    xor %edx, %eax
    xor %r8d, %eax
    add -64(%rsp,%rcx,4), %eax
    add -28(%rsp,%rcx,4), %eax
    mov -8(%rsp,%rcx,4), %edx
    mov %edx, %r8d
    mov %edx, %r9d
    ror $17, %edx
    ror $19, %r8d
    shr $10, %r9d
    xor %r8d, %edx
    xor %r9d, %edx
    add %edx, %eax
    mov %eax, (%rsp,%rcx,4)
    inc %ecx
    cmp $64, %ecx
    jb .sha_expand
    mov (%rdi), %r8d           # a through h
    mov 4(%rdi), %r9d
    mov 8(%rdi), %r10d
    mov 12(%rdi), %r11d
    mov 16(%rdi), %r12d
    mov 20(%rdi), %r13d
    mov 24(%rdi), %r14d
    mov 28(%rdi), %r15d
    lea .sha_k(%rip), %rbp
    xor %ecx, %ecx
.sha_round:
    mov %r12d, %eax
    mov %r12d, %edx
    mov %r12d, %ebx
    ror $6, %eax
    ror $11, %edx
    ror $25, %ebx
    xor %edx, %eax
    xor %ebx, %eax
    add %r15d, %eax
    mov %r13d, %edx
    xor %r14d, %edx
    and %r12d, %edx
    xor %r14d, %edx
    add %edx, %eax
    add (%rbp,%rcx,4), %eax
    add (%rsp,%rcx,4), %eax   # T1
    mov %r8d, %edx
    mov %r8d, %ebx
    mov %r8d, %esi
    ror $2, %edx
    ror $13, %ebx
    ror $22, %esi
    xor %ebx, %edx
    xor %esi, %edx
    mov %r8d, %ebx
    or %r9d, %ebx
    and %r10d, %ebx
    mov %r8d, %esi
    and %r9d, %esi
    or %esi, %ebx
    add %ebx, %edx           # T2
    mov %r14d, %r15d
    mov %r13d, %r14d
    mov %r12d, %r13d
    lea (%r11d,%eax), %r12d
    mov %r10d, %r11d
    mov %r9d, %r10d
    mov %r8d, %r9d
    lea (%eax,%edx), %r8d
    inc %ecx
    cmp $64, %ecx
    jb .sha_round
    mov 256(%rsp), %rdi
    add %r8d, (%rdi)
    add %r9d, 4(%rdi)
    add %r10d, 8(%rdi)
    add %r11d, 12(%rdi)
    add %r12d, 16(%rdi)
    add %r13d, 20(%rdi)
    add %r14d, 24(%rdi)
    add %r15d, 28(%rdi)
    add $264, %rsp
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbp
    pop %rbx
    ret
.size .sha_compress,.-.sha_compress

.global asmory_sha256_update
.type asmory_sha256_update,@function
# context, bytes, length -> 0 or -EOVERFLOW, without changing state on overflow.
asmory_sha256_update:
    mov 32(%rdi), %rax
    add %rdx, %rax
    jc .sha_overflow
    mov %rax, %rcx
    shr $61, %rcx
    jnz .sha_overflow
    mov %rax, 32(%rdi)
    push %rbx
    push %r12
    push %r13
    mov %rdi, %rbx
    mov %rsi, %r12
    mov %rdx, %r13
.sha_update_loop:
    test %r13, %r13
    jz .sha_updated
    mov 40(%rbx), %rax
    test %rax, %rax
    jnz .sha_buffer
    cmp $64, %r13
    jb .sha_buffer
    mov %rbx, %rdi
    mov %r12, %rsi
    call .sha_compress
    add $64, %r12
    sub $64, %r13
    jmp .sha_update_loop
.sha_buffer:
    mov $64, %ecx
    sub %rax, %rcx
    cmp %r13, %rcx
    cmova %r13, %rcx
    sub %rcx, %r13
    lea 48(%rbx,%rax), %rdi
    add %rcx, %rax
    mov %rax, 40(%rbx)
    mov %r12, %rsi
    rep movsb
    mov %rsi, %r12
    cmpq $64, 40(%rbx)
    jne .sha_update_loop
    mov %rbx, %rdi
    lea 48(%rbx), %rsi
    call .sha_compress
    movq $0, 40(%rbx)
    jmp .sha_update_loop
.sha_updated:
    pop %r13
    pop %r12
    pop %rbx
    xor %eax, %eax
    ret
.sha_overflow:
    mov $-75, %rax
    ret
.size asmory_sha256_update,.-asmory_sha256_update

.global asmory_sha256_final
.type asmory_sha256_final,@function
# context, 32-byte output. Finalization consumes the context; initialize to reuse.
asmory_sha256_final:
    push %rbx
    push %r12
    sub $8, %rsp
    mov %rdi, %rbx
    mov %rsi, %r12
    mov 40(%rbx), %rax
    movb $0x80, 48(%rbx,%rax)
    inc %rax
    lea 48(%rbx,%rax), %rdi
    mov $64, %ecx
    sub %eax, %ecx
    xor %eax, %eax
    rep stosb
    cmpq $56, 40(%rbx)
    jb .sha_length
    mov %rbx, %rdi
    lea 48(%rbx), %rsi
    call .sha_compress
    lea 48(%rbx), %rdi
    mov $8, %ecx
    xor %eax, %eax
    rep stosq
.sha_length:
    mov 32(%rbx), %rax
    shl $3, %rax
    bswap %rax
    mov %rax, 104(%rbx)
    mov %rbx, %rdi
    lea 48(%rbx), %rsi
    call .sha_compress
    xor %ecx, %ecx
.sha_output:
    mov (%rbx,%rcx,4), %eax
    bswap %eax
    mov %eax, (%r12,%rcx,4)
    inc %ecx
    cmp $8, %ecx
    jb .sha_output
    add $8, %rsp
    pop %r12
    pop %rbx
    xor %eax, %eax
    ret
.size asmory_sha256_final,.-asmory_sha256_final

.global asmory_sha256_file
.type asmory_sha256_file,@function
# path, 32-byte output -> 0 or negative errno. Streaming regular files permits
# empty/large inputs without mmap races; failures leave caller output untouched.
asmory_sha256_file:
    push %rbx
    push %r12
    sub $65832, %rsp           # context 112, stat 144, digest 32, buffer 65536 + 8
    mov %rsi, %r12
    mov %rdi, %rsi
    mov $-100, %rdi
    mov $0xa0800, %edx        # CLOEXEC | NOFOLLOW | NONBLOCK (refuse FIFOs promptly)
    xor %r10d, %r10d
    mov $257, %eax
    syscall
    test %rax, %rax
    js .sha_file_return
    mov %rax, %rbx
    mov %rax, %rdi
    lea 112(%rsp), %rsi
    mov $5, %eax
    syscall
    test %rax, %rax
    js .sha_file_close
    mov 136(%rsp), %eax
    and $0xf000, %eax
    cmp $0x8000, %eax
    jne .sha_file_invalid
    mov %rsp, %rdi
    call asmory_sha256_init
.sha_file_read:
    mov %rbx, %rdi
    lea 288(%rsp), %rsi
    mov $65536, %edx
    xor %eax, %eax
    syscall
    cmp $-4, %rax
    je .sha_file_read
    test %rax, %rax
    js .sha_file_close
    jz .sha_file_finish
    mov %rax, %rdx
    mov %rsp, %rdi
    lea 288(%rsp), %rsi
    call asmory_sha256_update
    test %rax, %rax
    js .sha_file_close
    jmp .sha_file_read
.sha_file_finish:
    mov %rsp, %rdi
    lea 256(%rsp), %rsi
    call asmory_sha256_final
    mov %rbx, %rdi
    mov $3, %eax
    syscall
    test %rax, %rax
    js .sha_file_return
    lea 256(%rsp), %rsi
    mov %r12, %rdi
    mov $4, %ecx
    rep movsq
    xor %eax, %eax
    jmp .sha_file_return
.sha_file_invalid:
    mov $-22, %rax
.sha_file_close:
    mov %rax, 65824(%rsp)
    mov %rbx, %rdi
    mov $3, %eax
    syscall
    mov 65824(%rsp), %rax
.sha_file_return:
    add $65832, %rsp
    pop %r12
    pop %rbx
    ret
.size asmory_sha256_file,.-asmory_sha256_file
.section .note.GNU-stack,"",@progbits
