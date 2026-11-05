/* AI-generated ABI/storage adapter around student-completed fragments.
 * Search fragments completed through guided student exercises.
 * This file's provenance is separate from the student exercise fragments.
 */
.include "src/rubik/search_tables.inc"
.globl target_search
.type target_search, @function
target_search:
    addi sp, sp, -48
    sw ra, 44(sp)
    sw s0, 0(sp)
    sw s1, 4(sp)
    sw s2, 8(sp)
    sw s3, 12(sp)
    sw s4, 16(sp)
    sw s5, 20(sp)
    sw s6, 24(sp)
    sw s7, 28(sp)
    mv s4, a0
    mv s5, a1
    mv s6, a2
    la s7, search_frames
    mv a0, s4
    mv a1, s5
    call hard11_lookup
    la t3, rt_pd
    la t4, rt_od
    beq a0, zero, .Lcompute_initial_bound
    li s2, 11
    j start_bound
.Lcompute_initial_bound:
    # The membership lookup used a0/a1, so restore both coordinates.
    mv a0, s4
    mv a1, s5
    mv a2, t3
    mv a3, t4
    call heuristic
    mv s2, a0
    j start_bound
.include "src/rubik/search_entry.inc"
.include "src/rubik/search_progress.inc"
.include "src/rubik/select_face.inc"
.include "src/rubik/prepare_child.inc"
.include "src/rubik/advance_child.inc"
.include "src/rubik/search_finish.inc"
search_return:
    lw s0, 0(sp)
    lw s1, 4(sp)
    lw s2, 8(sp)
    lw s3, 12(sp)
    lw s4, 16(sp)
    lw s5, 20(sp)
    lw s6, 24(sp)
    lw s7, 28(sp)
    lw ra, 44(sp)
    addi sp, sp, 48
    ret
.size target_search, .-target_search

.section .bss
.balign 16
search_frames:
    .space 384
