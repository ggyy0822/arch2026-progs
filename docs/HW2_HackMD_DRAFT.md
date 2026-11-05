# HW2: Bare-metal RV32I programs on rv32emu

This note covers my fork of [arch2026-progs](https://github.com/ggyy0822/arch2026-progs). It compares four C implementations with handwritten RV32I assembly. The instructor's test harness and my implementations run together in a bare-metal ELF under rv32emu system emulation. The harness, not the implementation, performs system calls and reads the performance counters.

## Environment and measurement method

- Toolchain: GNU RISC-V GCC 16.1.0, `-march=rv32i_zicsr -mabi=ilp32 -ffreestanding`; C built at `-O1`, `-O2`, `-O3`, and `-Os`. My local `riscv32-unknown-elf-` prefix wraps the installed `riscv64-unknown-elf-` cross tools in RV32 mode.
- Emulator: rv32emu system interpreter, commit `ffb041bab9d1513e5329f25f486378778dceed13`, with ELF loader and M/A/F/C extensions disabled.
- `make cycles` measures repeated calls on identical inputs. It subtracts an empty-loop baseline, including loop control, input load, and counter reads. Initialization and printing are outside the measured region. The same ELF contains both the C and assembly functions.
- rv32emu does not model pipeline timing: its `cycle` and `instret` counters both count executed guest instructions. These numbers show instruction work, not real processor latency or cache behavior. `common/perf.S` reads each 64-bit counter with a high–low–high retry to handle rollover.

## What the four programs do

1. **Rubik (`src/rubik/`)** accepts the 14-character corner state and returns a shortest move sequence. The C version uses two coordinates, a permutation index (0–5039) and an orientation index (0–728), plus an iterative-deepening A* search. The separate permutation and orientation distance tables give the admissible estimate `max(pd[p], od[o])`, so a shortest path is not pruned. The assembly version also uses a sorted exact table of states within five moves. A two-byte bucket index narrows each binary lookup. A separate table contains only the 2,644 states at distance 11, without their solutions; for those states, target-side search starts directly at bound 11. The target still computes every solution path. Consecutive turns of the same face are omitted because they can be merged into one turn or canceled.
2. **BFloat16 (`src/bf16/`)** converts FP32 bits to BF16 with round-to-nearest-even, multiplies BF16 numbers using shift-and-add mantissa multiplication, and computes square roots with an integer search. Special values such as zero, infinity, and NaN are handled explicitly. No floating-point instruction is executed.
3. **GCD (`src/gcd/`)** uses Stein's binary GCD. Common factors of two are removed with shifts; the remaining odd values are compared and subtracted. This avoids division and remainder on RV32I.
4. **Fixed point (`src/fixed/`)** implements bitwise addition (`op1`), subtraction (`op2`), overflow-safe average (`op3`), and signed Q11.20 multiplication (`q_mul`). The assembly multiplication builds a 64-bit product from 16-bit pieces using shifts and additions, then applies the required rounding and scaling.

## Cycle comparison

The table reports counted cycles per call on the benchmark inputs. Lower is better. “Best C” is the minimum among the four optimization levels; the last column is best-C cycles divided by assembly cycles.

| Function | -O1 | -O2 | -O3 | -Os | asm | best C | asm vs best C |
|---|---|---|---|---|---|---|---|
| bf16.from_f32 | 11.1 | 12.1 | 13.9 | 12.1 | 12.2 | 11.1 | 0.90x |
| bf16.mul | 79.9 | 79.1 | 80.6 | 78.0 | 66.6 | 78.0 | 1.17x |
| bf16.sqrt | 303.2 | 294.9 | 296.4 | 299.7 | 251.2 | 294.9 | 1.17x |
| fixed.op1 | 24.8 | 21.9 | 24.3 | 24.6 | 22.1 | 21.9 | 0.99x |
| fixed.op2 | 4.0 | 4.0 | 6.0 | 4.0 | 4.0 | 4.0 | 1.00x |
| fixed.op3 | 7.0 | 7.0 | 9.0 | 7.0 | 7.0 | 7.0 | 1.00x |
| fixed.q_mul | 326.2 | 319.8 | 321.8 | 323.8 | 224.6 | 319.8 | 1.42x |
| gcd.gcd | 101.6 | 116.5 | 118.9 | 119.6 | 101.6 | 101.6 | 1.00x |
| rubik.solve | 252291.5 | 202697.5 | 201755.7 | 204453.7 | 50644.2 | 201755.7 | 3.98x |

Assembly wins most clearly for Rubik, BF16 multiplication and square root, and fixed-point multiplication. It matches C for GCD and `fixed.op2/op3`. For `bf16.from_f32` and `fixed.op1`, the compiler is slightly better; the assembly still passes the automated tolerance against `-O2`, but I do not claim a speed win over the best C build for those functions. The Rubik assembly uses more static data than C to reduce target-side search work. This is a deliberate memory-for-instructions tradeoff.

## Code and data footprint

These are implementation objects from `size -A`; the shared harness is excluded. The best-size C build is `-Os` for every program here.

| Program | Variant | .text | .rodata | .data | .bss |
|---|---|---|---|---|---|
| rubik | asm | 1648 | 109615 | 0 | 384 |
| rubik | -O1 | 1172 | 40507 | 0 | 0 |
| rubik | -O2 | 1192 | 40507 | 0 | 0 |
| rubik | -O3 | 2508 | 40507 | 0 | 0 |
| rubik | -Os | 968 | 40507 | 0 | 0 |
| bf16 | asm | 620 | 0 | 0 | 0 |
| bf16 | -O1 | 700 | 0 | 0 | 0 |
| bf16 | -O2 | 700 | 0 | 0 | 0 |
| bf16 | -O3 | 700 | 0 | 0 | 0 |
| bf16 | -Os | 648 | 0 | 0 | 0 |
| gcd | asm | 132 | 0 | 0 | 0 |
| gcd | -O1 | 140 | 0 | 0 | 0 |
| gcd | -O2 | 140 | 0 | 0 | 0 |
| gcd | -O3 | 140 | 0 | 0 | 0 |
| gcd | -Os | 120 | 0 | 0 | 0 |
| fixed | asm | 192 | 0 | 0 | 0 |
| fixed | -O1 | 384 | 0 | 0 | 0 |
| fixed | -O2 | 344 | 0 | 0 | 0 |
| fixed | -O3 | 344 | 0 | 0 | 0 |
| fixed | -Os | 360 | 0 | 0 | 0 |


The Rubik assembly allocates 1,648 bytes of `.text`, 109,615 bytes of `.rodata`, and 384 bytes of `.bss`: **111,647 bytes total**, below the 131,072-byte budget. Its read-only data contains three-face transition tables, two small pattern databases, the distance-≤5 lookup, and the distance-11 membership set. It does not contain a full 3,674,160-state distance table.

## Correctness, budgets, and limits

`make test` passes **100/100** across all four C optimization levels and the handwritten assembly versions. `make sanitize` passes host AddressSanitizer and UndefinedBehaviorSanitizer checks. The optional `tools/check_rubik_hard11.py` runs all **2,644 unique distance-11 states** on the target and checks each returned length, move text, replay, and assembly instruction budget. The slowest call is `54721631111111` at **6,534,212 retired instructions**, below the 7,500,000 limit. The Rubik C version passes the supplied target tests and the selected difficult states; the exhaustive distance-11 run above specifically measures assembly.

The near-state and distance-11 tables are generated by `tools/generate_rubik_near.py` and `tools/generate_rubik_hard11.py`; `tools/rubik_distance11.csv` records the exhaustive HW1 distance-11 set. Host generation produces read-only data. Parsing, search, and construction of each solution happen on the RV32I target.

## Development and AI assistance

The commits are separated by program: binary GCD, BFloat16, fixed point, and Rubik. The Git hash chain is checked by `make history`. Some HW1 assembly fragments were written by me during guided exercises; the RV32I adapter and later performance changes were AI-assisted. I accepted the compact near-state bucket lookup after measuring a difficult case, and I added the distance-11 membership set after the original solver exceeded 7.5 million instructions on that case. I did **not** store precomputed full solution paths for those states: the target search must still find the moves. I corrected the register handling after the first membership-table version failed a target test, then reran the complete suite and all 2,644 distance-11 cases. I checked each suggestion against the target tests and the footprint budget before keeping it.

## Reproduce

```sh
# Use a RV32 GNU cross-tool prefix and rv32emu system interpreter.
make CROSS_COMPILE=riscv32-unknown-elf- test
make CROSS_COMPILE=riscv32-unknown-elf- sanitize
make CROSS_COMPILE=riscv32-unknown-elf- cycles
python3 tools/check_rubik_hard11.py --prefix riscv32-unknown-elf-
```

The cycle and footprint tables are written to the ignored `results/` directory. The full Rubik check requires the O2 ELF objects built by `make test`. The one-time local Lab 2 playground exercise and the English CodeTrial mock interview are separate from this code report; they are not represented by the automated 100/100 score.
