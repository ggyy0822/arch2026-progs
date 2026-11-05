# Stein's binary GCD. a0 = a, a1 = b; result in a0.
# Only RV32I integer instructions, no stack or helper calls.
    .text
    .globl gcd_u32_asm
    .type gcd_u32_asm, @function
    .align 2
gcd_u32_asm:
    beq     a0, zero, .Lreturn_b
    beq     a1, zero, .Ldone
    li      t0, 0                 # common power-of-two count
    or      t1, a0, a1
    andi    t1, t1, 1
    bne     t1, zero, .Lodd_a
.Lcommon:
    srli    a0, a0, 1
    srli    a1, a1, 1
    addi    t0, t0, 1
    or      t1, a0, a1
    andi    t1, t1, 1
    beq     t1, zero, .Lcommon
.Lodd_a:
    andi    t1, a0, 1
    bne     t1, zero, .Lloop
.Lshift_a:
    srli    a0, a0, 1
    andi    t1, a0, 1
    beq     t1, zero, .Lshift_a
.Lloop:
    andi    t1, a1, 1
    bne     t1, zero, .Lcompare
.Lshift_b:
    srli    a1, a1, 1
    andi    t1, a1, 1
    beq     t1, zero, .Lshift_b
.Lcompare:
    bgeu    a1, a0, .Lsubtract_b
    sub     t1, a0, a1
    mv      a0, a1
    mv      a1, t1
    j       .Lrepeat
.Lsubtract_b:
    sub     a1, a1, a0
.Lrepeat:
    bne     a1, zero, .Lloop
    sll     a0, a0, t0
.Ldone:
    ret
.Lreturn_b:
    mv      a0, a1
    ret
    .size gcd_u32_asm, .-gcd_u32_asm
