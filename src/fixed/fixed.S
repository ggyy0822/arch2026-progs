# Bitwise arithmetic and Q11.20 multiplication, RV32I only.
    .text
    .globl op1_asm
    .type op1_asm, @function
    .align 2
op1_asm:
    li      t0, 0
    beq     a1, zero, .Lop1_done
.Lop1_loop:
    and     t1, a0, a1
    xor     a0, a0, a1
    slli    a1, t1, 1
    addi    t0, t0, 1
    bne     a1, zero, .Lop1_loop
.Lop1_done:
    sw      t0, 0(a2)
    ret
    .size op1_asm, .-op1_asm

    .globl op2_asm
    .type op2_asm, @function
    .align 2
op2_asm:
    sub     a0, a0, a1
    ret
    .size op2_asm, .-op2_asm

    .globl op3_asm
    .type op3_asm, @function
    .align 2
op3_asm:
    and     t0, a0, a1
    xor     a0, a0, a1
    srli    a0, a0, 1
    add     a0, a0, t0
    ret
    .size op3_asm, .-op3_asm

    .globl q_mul_asm
    .type q_mul_asm, @function
    .align 2
q_mul_asm:
    li      t0, 0               # low half of product
    li      t1, 0               # high half of product
    mv      t2, a0              # low half of shifted multiplicand
    li      t3, 0               # high half of shifted multiplicand
    mv      t4, a1              # unsigned multiplier
    beq     t4, zero, .Lq_product_done
.Lq_bit:
    andi    t6, t4, 1
    beq     t6, zero, .Lq_shift
    mv      a2, t0
    add     t0, t0, t2
    sltu    a3, t0, a2          # carry from low addition
    add     t1, t1, t3
    add     t1, t1, a3
.Lq_shift:
    srli    t6, t2, 31
    slli    t3, t3, 1
    or      t3, t3, t6
    slli    t2, t2, 1
    srli    t4, t4, 1
    bne     t4, zero, .Lq_bit
.Lq_product_done:
    bge     a0, zero, .Lq_a_positive
    sub     t1, t1, a1          # signed correction for a
.Lq_a_positive:
    bge     a1, zero, .Lq_b_positive
    sub     t1, t1, a0          # signed correction for b
.Lq_b_positive:
    mv      a2, t0
    li      t6, 0x80000         # half unit for ties toward +infinity
    add     t0, t0, t6
    sltu    t6, t0, a2
    add     t1, t1, t6
    srli    t0, t0, 20
    slli    t1, t1, 12
    or      a0, t0, t1
    ret
    .size q_mul_asm, .-q_mul_asm
