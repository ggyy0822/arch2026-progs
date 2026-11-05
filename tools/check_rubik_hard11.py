#!/usr/bin/env python3
"""Check every distance-11 state on rv32emu without editing the test harness.

Run `make elfs` first, then:
  python3 tools/check_rubik_hard11.py --prefix riscv32-unknown-elf-
The generated temporary target test verifies optimal length, solution text,
replay, and the per-call assembly instruction budget.
"""
import argparse
import csv
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(command, **kwargs):
    subprocess.run([str(x) for x in command], check=True, cwd=ROOT, **kwargs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prefix', default='riscv32-unknown-elf-')
    parser.add_argument('--emu', default='third_party/rv32emu/build/rv32emu')
    parser.add_argument('--build', default='build')
    args = parser.parse_args()
    build = ROOT / args.build
    with (ROOT / 'tools/rubik_distance11.csv').open(newline='') as stream:
        rows = list(csv.DictReader(stream))
    assert len(rows) == 2644
    with tempfile.TemporaryDirectory(prefix='rubik-hard11-') as name:
        tmp = Path(name)
        vectors = (ROOT / 'tests/rubikvec.h').read_text()
        extra = ''.join(f'    {{"{row["state"]}", 11}},\n' for row in rows
                        if f'"{row["state"]}"' not in vectors)
        marker = '};\n#define RUBIK_NCASES'
        assert marker in vectors
        (tmp / 'rubikvec.h').write_text(vectors.replace(marker, extra + marker, 1))
        test = (ROOT / 'tests/trubik.c').read_text()
        assert '    REG_DEPTH(11);' in test
        test = test.replace('#include "rubikvec.h"', '#include "print.h"\n#include "rubikvec.h"', 1)
        test = test.replace('typedef int (*solve_fn)',
                            'static uint64_t hard_max;\nstatic const char *hard_state;\n\n'
                            'typedef int (*solve_fn)', 1)
        marker = '    if (used > budget)\n'
        assert marker in test
        test = test.replace(marker,
                            '    if (solve == rubik_solve_asm && used > hard_max) {\n'
                            '        hard_max = used;\n        hard_state = state;\n    }\n'
                            + marker, 1)
        marker = '    ASSERT_TRUE(seen > 0);\n'
        assert marker in test
        test = test.replace(marker,
                            '    if (depth == 11 && solve == rubik_solve_asm)\n'
                            '        bm_printf("@@hard11 count=%d max=%llu state=%s\\n",'
                            ' seen, hard_max, hard_state);\n' + marker, 1)
        test = test.replace('    REG_DEPTH(11);',
                            '    register_test(depth11_asm, NULL, NULL, "rubik_asm_depth11_full");', 1)
        test = test.replace('    register_test(asm_matches_c, NULL, NULL, "rubik_asm_matches_c");', '', 1)
        (tmp / 'trubik.c').write_text(test)
        arch = ['-march=rv32i_zicsr', '-mabi=ilp32']
        run([args.prefix + 'gcc', *arch, '-ffreestanding', '-fno-pic',
             '-fno-stack-protector', '-Wno-unused-function', '-iquote', '.',
             '-Icommon', '-Itests', '-O2', '-c', tmp / 'trubik.c',
             '-o', tmp / 'test.o'])
        objects = [build / 'rubik/O2/impl.o', build / 'rubik/impl_asm.o',
                   build / 'rubik/O2/main.o', tmp / 'test.o']
        objects += [build / 'common' / f'{x}.o' for x in
                    ('start', 'perf', 'rt', 'print', 'utest', 'trt', 'tutest')]
        run([args.prefix + 'ld', '-m', 'elf32lriscv', '-T', 'common/linker.ld',
             '--no-warn-rwx-segments', '-o', tmp / 'rubik.elf', *objects])
        completed = subprocess.run([str(ROOT / args.emu), str(tmp / 'rubik.elf')],
                                   cwd=ROOT, capture_output=True, text=True)
        for line in completed.stdout.splitlines():
            if ('hard11' in line or line.startswith('Summary:') or
                    line.startswith('@@prog')):
                print(line)
        if completed.returncode:
            print(completed.stdout)
            print(completed.stderr)
            raise SystemExit(completed.returncode)


if __name__ == '__main__':
    main()
