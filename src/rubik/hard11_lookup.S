# Is this exactly one of the distance-11 states? Return 1 or 0 in a0.
# The table stores only state keys; search still runs on the target.
    .text
    .globl hard11_lookup
    .type hard11_lookup, @function
    .align 2
hard11_lookup:
    slli t0, a0, 9
    slli t1, a0, 8
    add t0, t0, t1
    slli t1, a0, 5
    sub t0, t0, t1
    slli t1, a0, 3
    sub t0, t0, t1
    add t0, t0, a0
    add t0, t0, a1
    li t1, 0
    li t2, 2644
    la t3, hard11_table
.Lhard_loop:
    bgeu t1, t2, .Lhard_miss
    add t4, t1, t2
    srli t4, t4, 1
    slli t5, t4, 1
    add t5, t5, t4
    add t5, t5, t3
    lbu t6, 0(t5)
    lbu a2, 1(t5)
    slli a2, a2, 8
    or t6, t6, a2
    lbu a2, 2(t5)
    slli a2, a2, 16
    or t6, t6, a2
    bltu t6, t0, .Lhard_right
    bltu t0, t6, .Lhard_left
    li a0, 1
    ret
.Lhard_right:
    addi t1, t4, 1
    j .Lhard_loop
.Lhard_left:
    mv t2, t4
    j .Lhard_loop
.Lhard_miss:
    li a0, 0
    ret
    .size hard11_lookup, .-hard11_lookup
