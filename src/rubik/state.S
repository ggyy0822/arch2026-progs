# AI-authored RV32I parser and independent physical replay. No C runtime.
.text
.globl target_parse
# a0=input; a1=p[7]; a2=o[7]; a3=&rank_p; a4=&rank_o.
target_parse:
    li a5, 7
    li a6, 0
1:  lbu t0, 0(a0)
    beqz t0, 9f
    addi t0, t0, -49
    li t1, 7
    bgeu t0, t1, 9f
    li t1, 1
    sll t1, t1, t0
    and t2, a6, t1
    bnez t2, 9f
    or a6, a6, t1
    sb t0, 0(a1)
    addi a0, a0, 1
    addi a1, a1, 1
    addi a5, a5, -1
    bnez a5, 1b
    li a5, 7
    li a6, 0
2:  lbu t0, 0(a0)
    beqz t0, 9f
    addi t0, t0, -49
    li t1, 3
    bgeu t0, t1, 9f
    add a6, a6, t0
    sb t0, 0(a2)
    addi a0, a0, 1
    addi a2, a2, 1
    addi a5, a5, -1
    bnez a5, 2b
    lbu t0, 0(a0)
    bnez t0, 9f
3:  bltu a6, t1, 4f
    addi a6, a6, -3
    j 3b
4:  bnez a6, 9f
    addi t0, a1, -7
    li t2, 0
    li t3, 7
    li a5, 1
5:  lbu t5, 0(t0)
    addi t6, t0, 1
    li t4, 0
6:  beq t6, a1, 7f
    lbu a6, 0(t6)
    sltu a6, a6, t5
    add t4, t4, a6
    addi t6, t6, 1
    j 6b
7:  li a6, 0
    beqz t2, 11f
    mv a7, t3
8:  add a6, a6, t2
    addi a7, a7, -1
    bnez a7, 8b
11: add t2, a6, t4
    addi t0, t0, 1
    addi t3, t3, -1
    bne t3, a5, 5b
    sw t2, 0(a3)
    addi t0, a2, -7
    addi a2, a2, -1
    li t2, 0
10: lbu t1, 0(t0)
    slli t3, t2, 1
    add t2, t2, t3
    add t2, t2, t1
    addi t0, t0, 1
    bne t0, a2, 10b
    sw t2, 0(a4)
    li a0, 1
    ret
9:  li a0, 0
    ret

