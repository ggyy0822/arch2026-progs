search_loop:
    lw t0, 0(s0)
    lw t1, 4(s0)
    or t0, t0, t1
    beq t0, zero, found
    addi t0, s2, -5
    blt t0, zero, search_check_bound
    bne s1, t0, search_check_bound
    lw a0, 0(s0)
    lw a1, 4(s0)
    call near_lookup
    # The hot child check keeps these table bases in temporary registers.
    la t3, rt_pd
    la t4, rt_od
    blt a0, zero, backtrack
    j near_found
search_check_bound:
    beq s1, s2, backtrack
    j try_move
