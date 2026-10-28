#!/usr/bin/env python3
"""Assemble, simulate, and check the four directed programs."""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys

from assembler import assemble, write_hex


ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
PROGRAMS = ("sum", "fibonacci", "array_sum", "hazards")


def execute(command):
    result = subprocess.run(
        command,
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=60,
    )

    output = result.stdout + result.stderr

    if result.returncode != 0:
        raise RuntimeError(output.strip() or "Simulator command failed")

    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "program", nargs="?", default="all", choices=("all", *PROGRAMS)
    )
    parser.add_argument("--wave", action="store_true", help="Also save a VCD waveform")
    args = parser.parse_args()

    try:
        compiler, simulator = shutil.which("iverilog"), shutil.which("vvp")

        if not compiler or not simulator:
            raise RuntimeError(
                "Install Icarus Verilog and put iverilog/vvp on PATH. See README.md."
            )

        # Compile once, then use the same simulated CPU for each program.
        BUILD.mkdir(exist_ok=True)
        compiled = BUILD / "tb_core.vvp"
        rtl = sorted((ROOT / "rtl").glob("*.sv"))

        output = execute([
            compiler, "-g2012", "-Wall",
            "-I", str(ROOT / "rtl"),
            "-s", "tb_core",
            "-o", str(compiled),
            *map(str, rtl),
            str(ROOT / "tb" / "tb_core.sv"),
        ])

        if output.strip():
            print(output.strip())

        names = PROGRAMS if args.program == "all" else (args.program,)
        passed = 0

        for name in names:
            words = assemble(
                (ROOT / "programs" / f"{name}.s").read_text(encoding="utf-8")
            )
            hex_file = BUILD / f"{name}.hex"
            write_hex(words, hex_file)

            command = [
                simulator, str(compiled),
                f"+test={name}", f"+program={hex_file}",
            ]

            if args.wave:
                command.append(f"+vcd={BUILD / f'{name}.vcd'}")

            output = execute(command)
            print(output.strip())

            if f"PASS {name}:" not in output:
                raise RuntimeError("Simulation ended without a PASS result")

            passed += 1

        print(f"\n{passed} simulations passed.")
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
