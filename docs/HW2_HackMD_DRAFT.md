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
4. **Fixed point (`src/fixed/`)** implements bitwise addition (`op1`), subtraction (`op2`), overflow-safe average (`op3`), and signed Q11.20 multiplication (`q_mul`). The assembly multiplication builds a 64-bit product in a pair of 32-bit registers using shifts and additions, then applies the required rounding and scaling.

## 1. Rubik: representation and optimal search

The state has seven corner-permutation digits `1`–`7`, followed by seven orientation digits `1`–`3`. The last orientation is fixed by the invariant that the orientation sum is 0 modulo 3. Thus there are `7! × 3^6 = 3,674,160` legal states. The parser checks the digits, duplicates, length, and orientation sum before it makes a Lehmer-code permutation rank `p` and a base-three orientation rank `o`. [C parser and search](https://github.com/ggyy0822/arch2026-progs/blob/431f35b85d36f92b4aea760e5d34303288259c8f/src/rubik/rubik.c) and [assembly parser](https://github.com/ggyy0822/arch2026-progs/blob/431f35b85d36f92b4aea760e5d34303288259c8f/src/rubik/state.S) implement the same input contract.

For each state, `pd[p]` is the exact distance of its permutation projection and `od[o]` is the exact distance of its orientation projection. Every full solution also solves both projections. Therefore `h=max(pd[p], od[o])` cannot exceed the true remaining distance. IDA* tries increasing bounds on `g+h`, with `g` the number of moves already made. When the bound reaches the shortest solution length `D`, no prefix of a shortest solution is pruned, so the first found path is shortest. The full state graph has maximum distance 11. The target stores only 384 bytes of explicit search frames rather than allocating a recursive stack or a full-state BFS queue. [Search control](https://github.com/ggyy0822/arch2026-progs/blob/431f35b85d36f92b4aea760e5d34303288259c8f/src/rubik/search.S) and [short-path lookup](https://github.com/ggyy0822/arch2026-progs/blob/431f35b85d36f92b4aea760e5d34303288259c8f/src/rubik/near_lookup.S) show the target code.

The short-path lookup stores exact paths for the 12,224 states within five moves. Each entry keeps 2 low key bytes and 3 path bytes; the high key bits select a bucket first. A separate 7,932-byte table stores only the ranks of all distance-11 states. Its lookup says that a search may start at bound 11, but gives no move sequence. This cut repeat searches at lower bounds. These tables cost memory and host preparation time; their benefit is fewer target instructions, while the solution search itself still runs on RV32I.

Key lines from [the pinned search source](https://github.com/ggyy0822/arch2026-progs/blob/431f35b85d36f92b4aea760e5d34303288259c8f/src/rubik/search.S#L22-L34):

```asm
call hard11_lookup
beq a0, zero, .Lcompute_initial_bound
li s2, 11
j start_bound
```

The lookup only decides the starting bound. `start_bound` still runs the search on the target and builds the move sequence. For other states, the code computes the starting bound from the pattern databases.

Here is the measured refinement on the difficult state `54721631111111` (same rv32emu build and the assembly call):

| Assembly change | Retired instructions | Static-data effect |
|---|---:|---|
| Six-byte near entries, no distance-11 set | 13,499,998 | Baseline near table |
| Five-byte bucketed near entries | 9,218,760 | About 12 KiB less near-table data |
| Also start at bound 11 for exact distance-11 members | 6,534,212 | Add 7,932 bytes of membership keys |

The last result is below 7.5 million. This is an instruction budget, not a time estimate. The full 2,644-state target test checks that every returned path has length 11, replays correctly, and fits the instruction budget. A practical use of this approach is a small puzzle solver or route search where a tiny exact endgame table saves repeated traversal; the tradeoff is read-only storage and table generation.

## 2. BFloat16: bit arithmetic without hardware floating point

BF16 is a 16-bit pattern with one sign bit, eight exponent bits (bias 127), and seven fraction bits. A normal value is `(-1)^sign × (1 + fraction/128) × 2^(exponent−127)`. The least positive subnormal is `2^−133`; the maximum finite positive value is `(2−2^−7) × 2^127`. The spacing at 1.0 is `2^−7`. NaN, infinity, zero, and subnormal patterns have their own contract rules, so the code works on integer bit patterns rather than C `float`. [C implementation](https://github.com/ggyy0822/arch2026-progs/blob/431f35b85d36f92b4aea760e5d34303288259c8f/src/bf16/bf16.c) and [assembly routines](https://github.com/ggyy0822/arch2026-progs/blob/431f35b85d36f92b4aea760e5d34303288259c8f/src/bf16/bf16.S) show these cases.

`from_f32` keeps the high 16 bits of an FP32 pattern. For ordinary values, adding `0x7FFF` and the low bit of the kept half before shifting implements nearest-even rounding: exactly halfway values go to the even BF16 encoding. Its error is at most half a BF16 spacing for finite values that do not overflow. Multiplication XORs the signs, normalizes subnormal significands, forms an 8-bit by 8-bit product with shifts and additions, adjusts the exponent, and **truncates** the fraction as this assignment's contract requires. The operand order for NaN and infinity is deliberate: a first-operand infinity can override a second-operand NaN. For normal results without overflow or underflow, truncating the significand loses less than one output spacing. Square root uses the largest integer `k` in `[90, 256]` satisfying `floor(k²/128) ≤ m`; equivalently, `k² < 128(m+1)`. Its result is not correctly rounded. The contract reports a worst relative error of 0.3884% on positive normals, and the tests check the squared result within 1% of the input.

Key lines from [the pinned conversion source](https://github.com/ggyy0822/arch2026-progs/blob/431f35b85d36f92b4aea760e5d34303288259c8f/src/bf16/bf16.S#L11-L19):

```asm
srli t0, a0, 16
andi t0, t0, 1
li t1, 0x7fff
add a0, a0, t1
add a0, a0, t0
```

The low bit of the kept half is the tie breaker. After these additions, shifting right by 16 yields the nearest-even BF16 pattern for ordinary inputs. A separate branch handles exponent-255 special values before these lines.

The C code uses a small bitwise product routine; the assembly keeps the product and search variables in registers and avoids a multiply helper call. On the benchmark, multiplication falls from 79.1 cycles at `-O2` to 66.6 in assembly, and square root from 294.9 to 251.2. `from_f32` takes 12.2 in assembly versus the best C result of 11.1, so it is a measured loss. The tests compare exact output bits on conversion sweeps (all 65,536 discarded halves under 16 representative kept halves, plus five boundary tails under every kept half), multiplication grids and columns, and all 65,536 square-root inputs. Thus the observed mismatch against the contract reference is zero tested encodings. BF16 is used when reduced storage and arithmetic cost matter, such as machine-learning data paths; this software version illustrates the extra work when an ISA has no floating-point unit.

## 3. Binary GCD: use shifts instead of division

For unsigned 32-bit integers, GCD is exact, with `gcd(x,0)=x` and `gcd(0,0)=0`. Stein's algorithm uses three identities: `gcd(2a,2b)=2gcd(a,b)`, `gcd(2a,b)=gcd(a,b)` when `b` is odd, and `gcd(a,b)=gcd(a,b−a)` when `a≤b` are odd. Repeatedly removing even factors and subtracting the smaller odd value eventually reaches zero; the saved common power of two is then restored. This proves both termination and the result. [C algorithm](https://github.com/ggyy0822/arch2026-progs/blob/431f35b85d36f92b4aea760e5d34303288259c8f/src/gcd/gcd.c) and [RV32I loop](https://github.com/ggyy0822/arch2026-progs/blob/431f35b85d36f92b4aea760e5d34303288259c8f/src/gcd/gcd.S) contain only shifts, compares, subtraction, and branches on the main path.

RV32I has no integer divide instruction, so Euclid's remainder step would need a software helper. This code does not call one. On the benchmark, the handwritten version retires 101.6 instructions per call versus 116.5 for C `-O2`; C `-O1` reaches the same 101.6, so the assembly matches the **best** compiler level rather than beating it. The output has zero numerical error because GCD is an integer operation. Tests cover zero and boundary operands, an exhaustive small grid, powers of two, algebraic laws, and directed expensive pairs. Binary GCD is useful in rational-number normalization and cryptographic integer routines on small processors without a divider.

Key lines from [the pinned GCD source](https://github.com/ggyy0822/arch2026-progs/blob/431f35b85d36f92b4aea760e5d34303288259c8f/src/gcd/gcd.S#L14-L20):

```asm
srli a0, a0, 1
srli a1, a1, 1
addi t0, t0, 1
```

Each pass removes one factor of two shared by both inputs. `t0` counts those factors, so the final code restores them with a left shift after the odd-part GCD is known.

## 4. Logic operations and signed Q11.20 fixed point

`op1` reproduces 32-bit addition without using `+` in its loop: `carry=(a&b)<<1`, `sum=a^b`, then repeat with `sum` and `carry` until the carry is zero. The carry moves to higher bit positions, so the loop terminates within 32 passes; the pass count is also returned. `op2` is subtraction modulo `2^32`. For an exact unsigned sum, the identity `floor((a+b)/2)=(a&b)+((a^b)>>1)` gives `op3` without overflowing an intermediate 32-bit addition. [C functions](https://github.com/ggyy0822/arch2026-progs/blob/431f35b85d36f92b4aea760e5d34303288259c8f/src/fixed/fixed.c) and [assembly functions](https://github.com/ggyy0822/arch2026-progs/blob/431f35b85d36f92b4aea760e5d34303288259c8f/src/fixed/fixed.S) show these formulas.

A signed Q11.20 stored integer `A` represents `A/2^20`, so the representable range is `−2048` through `2048−2^−20` in steps of `2^−20`. `q_mul` forms a signed 64-bit product, adds `2^19`, then shifts right by 20. Thus ties round toward positive infinity: `q_mul(3, 524288)=2` and `q_mul(−3, 524288)=−1`. The low 32 bits are kept, so an out-of-range result wraps instead of saturating. Before wrapping, the real-value rounding error is at most `2^−21`. The assembly forms the product using shift-and-add on 32-bit register pairs, avoiding a 64-bit multiply helper that this freestanding runtime does not supply.

Key lines from [the pinned fixed-point source](https://github.com/ggyy0822/arch2026-progs/blob/431f35b85d36f92b4aea760e5d34303288259c8f/src/fixed/fixed.S#L71-L80):

```asm
li t6, 0x80000
add t0, t0, t6
sltu t6, t0, a2
add t1, t1, t6
srli t0, t0, 20
slli t1, t1, 12
or a0, t0, t1
```

Here `t1:t0` is the 64-bit product and `a2` holds the old low half. The addition gives the required rounding; `sltu` carries overflow into the high half. The final shifts extract bits 20 through 51 as the wrapped 32-bit result.

On the benchmark, `q_mul` falls from 319.8 instructions at C `-O2` to 224.6 in assembly. `op2` and `op3` match the best C at 4 and 7; `op1` is 22.1 versus best C 21.9. The fixed-point contract is checked against an independent host reference over a 64×64 grid and 4,096 pseudorandom pairs, plus ties, signs, identity, and wraparound laws. Tested outputs match the contract exactly; the half-unit bound describes quantization relative to the unrounded mathematical product. Fixed-point arithmetic is useful in embedded control and graphics when floating-point hardware is absent, provided range and overflow behavior are explicit.

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
