# Exact solution code for states at distance <=5, sorted by combined rank.
# a0=permutation rank, a1=orientation rank; a0=packed path or -1.
    .text
    .globl near_lookup
    .type near_lookup, @function
    .align 2
near_lookup:
    slli    t0, a0, 9
    slli    t1, a0, 8
    add     t0, t0, t1
    slli    t1, a0, 5
    sub     t0, t0, t1
    slli    t1, a0, 3
    sub     t0, t0, t1
    add     t0, t0, a0
    add     t0, t0, a1     # p*729+o
    srli    t1, t0, 16    # high-byte bucket
    slli    t1, t1, 1
    la      t3, near_bucket
    add     t3, t3, t1
    lhu     t1, 0(t3)     # lower index inclusive
    lhu     t2, 2(t3)     # upper index exclusive
    slli    t0, t0, 16
    srli    t0, t0, 16    # low 16 bits of key
    la      t3, near_table
.Lnear_loop:
    bgeu    t1, t2, .Lnear_miss
    add     t4, t1, t2
    srli    t4, t4, 1
    slli    t5, t4, 2
    add     t5, t5, t4     # five bytes per entry
    add     t5, t5, t3
    lbu     t6, 0(t5)
    lbu     a2, 1(t5)
    slli    a2, a2, 8
    or      t6, t6, a2
    bltu    t6, t0, .Lnear_right
    bltu    t0, t6, .Lnear_left
    lbu     a0, 2(t5)
    lbu     a2, 3(t5)
    slli    a2, a2, 8
    or      a0, a0, a2
    lbu     a2, 4(t5)
    slli    a2, a2, 16
    or      a0, a0, a2
    ret
.Lnear_right:
    addi    t1, t4, 1
    j       .Lnear_loop
.Lnear_left:
    mv      t2, t4
    j       .Lnear_loop
.Lnear_miss:
    li      a0, -1
    ret
    .size near_lookup, .-near_lookup
