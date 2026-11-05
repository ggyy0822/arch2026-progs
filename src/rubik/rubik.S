# HW2 callable adapter for the register/coordinate search from HW1.
# The path and parse scratch live on the caller's 4 KiB stack.
    .text
    .globl rubik_solve_asm
    .type rubik_solve_asm, @function
    .align 2
rubik_solve_asm:
    addi    sp, sp, -80
    sw      ra, 76(sp)
    sw      s0, 72(sp)
    sw      s1, 68(sp)
    sw      s2, 64(sp)
    sw      s3, 60(sp)
    mv      s1, a1              # output
    mv      s2, a2              # capacity
    addi    a1, sp, 0          # seven permutation bytes
    addi    a2, sp, 8          # seven orientation bytes
    addi    a3, sp, 16         # permutation rank
    addi    a4, sp, 20         # orientation rank
    call    target_parse
    beq     a0, zero, .Linvalid
    lw      a0, 16(sp)
    lw      a1, 20(sp)
    addi    a2, sp, 24         # eleven move indices
    call    target_search
    blt     a0, zero, .Linvalid
    mv      s0, a0              # solution length
    li      t0, 0               # index
    li      t1, 1               # required bytes including NUL
    la      t2, .Lmove_names
.Lsize_loop:
    bge     t0, s0, .Lsize_done
    add     t3, sp, t0
    lbu     t3, 24(t3)
    slli    t3, t3, 1
    add     t3, t3, t2
    lbu     t4, 1(t3)
    addi    t1, t1, 1
    beq     t4, zero, .Lno_suffix
    addi    t1, t1, 1
.Lno_suffix:
    beq     t0, zero, .Lno_space
    addi    t1, t1, 1
.Lno_space:
    addi    t0, t0, 1
    j       .Lsize_loop
.Lsize_done:
    bgeu    s2, t1, .Lwrite
    beq     s2, zero, .Ltoo_small
    sb      zero, 0(s1)
.Ltoo_small:
    li      a0, -2
    j       .Lreturn
.Lwrite:
    li      t0, 0
    mv      t1, s1
    la      t2, .Lmove_names
.Lwrite_loop:
    bge     t0, s0, .Lwrite_done
    beq     t0, zero, .Lwrite_move
    li      t3, 32
    sb      t3, 0(t1)
    addi    t1, t1, 1
.Lwrite_move:
    add     t3, sp, t0
    lbu     t3, 24(t3)
    slli    t3, t3, 1
    add     t3, t3, t2
    lbu     t4, 0(t3)
    sb      t4, 0(t1)
    addi    t1, t1, 1
    lbu     t4, 1(t3)
    beq     t4, zero, .Lwrite_next
    sb      t4, 0(t1)
    addi    t1, t1, 1
.Lwrite_next:
    addi    t0, t0, 1
    j       .Lwrite_loop
.Lwrite_done:
    sb      zero, 0(t1)
    mv      a0, s0
    j       .Lreturn
.Linvalid:
    li      a0, -1
.Lreturn:
    lw      s3, 60(sp)
    lw      s2, 64(sp)
    lw      s1, 68(sp)
    lw      s0, 72(sp)
    lw      ra, 76(sp)
    addi    sp, sp, 80
    ret
    .size rubik_solve_asm, .-rubik_solve_asm
    .section .rodata
.Lmove_names:
    .byte 'R',0, 'R','2', 'R',39
    .byte 'B',0, 'B','2', 'B',39
    .byte 'D',0, 'D','2', 'D',39
