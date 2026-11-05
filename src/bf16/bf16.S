# BFloat16 bit operations. All functions use only RV32I registers.
    .text
    .globl bf16_from_f32_asm
    .type bf16_from_f32_asm, @function
    .align 2
bf16_from_f32_asm:
    srli    t0, a0, 23
    andi    t0, t0, 255
    li      t1, 255
    beq     t0, t1, .Lfrom_special
    srli    t0, a0, 16
    andi    t0, t0, 1
    li      t1, 0x7fff
    add     a0, a0, t1
    add     a0, a0, t0
.Lfrom_special:
    srli    a0, a0, 16
    ret
    .size bf16_from_f32_asm, .-bf16_from_f32_asm

    .globl bf16_mul_asm
    .type bf16_mul_asm, @function
    .align 2
bf16_mul_asm:
    xor     t0, a0, a1
    li      t6, 0x8000
    and     t0, t0, t6          # result sign
    srli    t1, a0, 7
    srli    t2, a1, 7
    andi    t1, t1, 255        # exponent a
    andi    t2, t2, 255        # exponent b
    li      t6, 255
    beq     t1, t6, .Lmul_special_a
    beq     t2, t6, .Lmul_special_b
    li      t6, 0x7fff
    and     t3, a0, t6
    beq     t3, zero, .Lmul_zero
    and     t4, a1, t6
    beq     t4, zero, .Lmul_zero
    andi    t3, a0, 127        # significand a
    andi    t4, a1, 127        # significand b
    beq     t1, zero, .Lmul_denorm_a
    ori     t3, t3, 128
.Lmul_after_a:
    beq     t2, zero, .Lmul_denorm_b
    ori     t4, t4, 128
.Lmul_after_b:
    li      t5, 0             # product, shift and add
.Lmul_bits:
    andi    t6, t4, 1
    beq     t6, zero, .Lmul_skip_add
    add     t5, t5, t3
.Lmul_skip_add:
    slli    t3, t3, 1
    srli    t4, t4, 1
    bne     t4, zero, .Lmul_bits
    add     t1, t1, t2
    addi    t1, t1, -127
    li      t6, 32768
    bltu    t5, t6, .Lmul_product_ready
    srli    t5, t5, 1
    addi    t1, t1, 1
.Lmul_product_ready:
    srli    t5, t5, 7
    li      t6, 255
    bge     t1, t6, .Lmul_inf
    bge     zero, t1, .Lmul_underflow
    slli    t1, t1, 7
    andi    t5, t5, 127
    or      a0, t0, t1
    or      a0, a0, t5
    ret
.Lmul_underflow:
    li      t6, -6
    blt     t1, t6, .Lmul_zero
    andi    t5, t5, 127        # specified fraction-only denormal
    li      t6, 1
    sub     t6, t6, t1
    srl     t5, t5, t6
    or      a0, t0, t5
    ret
.Lmul_denorm_a:
    li      t1, 1
    li      t6, 128
.Lmul_norm_a:
    slli    t3, t3, 1
    addi    t1, t1, -1
    bltu    t3, t6, .Lmul_norm_a
    j       .Lmul_after_a
.Lmul_denorm_b:
    li      t2, 1
    li      t6, 128
.Lmul_norm_b:
    slli    t4, t4, 1
    addi    t2, t2, -1
    bltu    t4, t6, .Lmul_norm_b
    j       .Lmul_after_b
.Lmul_special_a:
    andi    t3, a0, 127
    bne     t3, zero, .Lmul_return
    li      t6, 0x7fff
    and     t3, a1, t6
    beq     t3, zero, .Lmul_nan
    j       .Lmul_inf
.Lmul_special_b:
    andi    t3, a1, 127
    bne     t3, zero, .Lmul_return_b
    li      t6, 0x7fff
    and     t3, a0, t6
    beq     t3, zero, .Lmul_nan
.Lmul_inf:
    li      t6, 0x7f80
    or      a0, t0, t6
    ret
.Lmul_nan:
    li      a0, 0x7fc0
    ret
.Lmul_zero:
    mv      a0, t0
.Lmul_return:
    ret
.Lmul_return_b:
    mv      a0, a1
    ret
    .size bf16_mul_asm, .-bf16_mul_asm

    .globl bf16_sqrt_asm
    .type bf16_sqrt_asm, @function
    .align 2
bf16_sqrt_asm:
    srli    t0, a0, 7
    andi    t0, t0, 255        # biased exponent
    andi    t1, a0, 127        # fraction
    li      t2, 255
    beq     t0, t2, .Lsqrt_special
    li      t2, 0x7fff
    and     t2, a0, t2
    beq     t2, zero, .Lsqrt_zero
    li      t2, 0x8000
    and     t2, a0, t2
    bne     t2, zero, .Lsqrt_nan
    beq     t0, zero, .Lsqrt_zero
    ori     t1, t1, 128        # input significand
    addi    t0, t0, -127      # unbiased exponent
    andi    t2, t0, 1
    beq     t2, zero, .Lsqrt_even
    slli    t1, t1, 1
    addi    t0, t0, -1
.Lsqrt_even:
    srai    t0, t0, 1
    addi    t0, t0, 127       # output exponent
    li      t2, 90            # binary search lower bound
    li      t3, 256           # exclusive upper bound
.Lsqrt_search:
    addi    t4, t2, 1
    bgeu    t4, t3, .Lsqrt_done
    add     t4, t2, t3
    srli    t4, t4, 1        # mid
    mv      t5, t4            # multiplier
    mv      t6, t4            # multiplicand
    li      a1, 0             # square
.Lsqrt_square:
    andi    a2, t6, 1
    beq     a2, zero, .Lsqrt_skip_add
    add     a1, a1, t5
.Lsqrt_skip_add:
    slli    t5, t5, 1
    srli    t6, t6, 1
    bne     t6, zero, .Lsqrt_square
    srli    a1, a1, 7
    bltu    t1, a1, .Lsqrt_lower_hi
    mv      t2, t4
    j       .Lsqrt_search
.Lsqrt_lower_hi:
    mv      t3, t4
    j       .Lsqrt_search
.Lsqrt_done:
    slli    t0, t0, 7
    andi    t2, t2, 127
    or      a0, t0, t2
    ret
.Lsqrt_special:
    bne     t1, zero, .Lsqrt_return
    li      t2, 0x8000
    and     t2, a0, t2
    beq     t2, zero, .Lsqrt_return
.Lsqrt_nan:
    li      a0, 0x7fc0
.Lsqrt_return:
    ret
.Lsqrt_zero:
    li      a0, 0
    ret
    .size bf16_sqrt_asm, .-bf16_sqrt_asm
