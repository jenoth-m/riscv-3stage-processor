#!/usr/bin/env python3
"""Two-pass assembler for the processor's supported instructions."""

import argparse
from pathlib import Path
import re


# These function fields distinguish the five register-to-register operations.
R_OPS = {
    "add": (0, 0),
    "sub": (0, 0x20),
    "and": (7, 0),
    "or": (6, 0),
    "xor": (4, 0),
}
BRANCHES = {"beq": 0, "bne": 1}


def register(text):
    if not re.fullmatch(r"x([0-9]|[12][0-9]|3[01])", text):
        raise ValueError(f"Use register names x0 through x31, not {text!r}")

    return int(text[1:])


def signed_field(value, width):
    if not -(1 << (width - 1)) <= value < (1 << (width - 1)):
        raise ValueError(f"{value} does not fit a signed {width}-bit immediate")

    # Keep the low bits, including the two's-complement pattern for negatives.
    return value & ((1 << width) - 1)


def i_word(opcode, rd, funct3, rs1, immediate):
    return (
        (signed_field(immediate, 12) << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | (rd << 7)
        | opcode
    )


def encode(text, pc, labels):
    # Split registers and offsets, accepting commas and memory parentheses.
    op, *args = re.split(r"[\s,()]+", text.strip().rstrip(")"))
    op = op.lower()

    def count(expected):
        if len(args) != expected:
            raise ValueError(f"{op} expects {expected} operands")

    def target(value):
        return labels[value] - pc if value in labels else int(value, 0)

    if op in ("nop", "ebreak"):
        count(0)
        return 0x00000013 if op == "nop" else 0x00100073

    if op in R_OPS:
        count(3)
        rd, rs1, rs2 = map(register, args)
        funct3, funct7 = R_OPS[op]

        return (
            (funct7 << 25)
            | (rs2 << 20)
            | (rs1 << 15)
            | (funct3 << 12)
            | (rd << 7)
            | 0x33
        )

    if op == "addi":
        count(3)
        return i_word(
            0x13, register(args[0]), 0, register(args[1]), int(args[2], 0)
        )

    if op in ("lw", "sw"):
        count(3)
        reg, offset, base = register(args[0]), int(args[1], 0), register(args[2])

        if op == "lw":
            return i_word(0x03, reg, 2, base, offset)

        # The store immediate is split across two fields in an S-type word.
        immediate = signed_field(offset, 12)
        return (
            ((immediate >> 5) << 25)
            | (reg << 20)
            | (base << 15)
            | (2 << 12)
            | ((immediate & 31) << 7)
            | 0x23
        )

    if op in BRANCHES:
        count(3)
        immediate = signed_field(target(args[2]), 13)

        if immediate % 4:
            raise ValueError("This project needs word-aligned branch targets")

        # Branch offsets are split into four fields by the instruction format.
        return (
            ((immediate >> 12) << 31)
            | (((immediate >> 5) & 63) << 25)
            | (register(args[1]) << 20)
            | (register(args[0]) << 15)
            | (BRANCHES[op] << 12)
            | (((immediate >> 1) & 15) << 8)
            | (((immediate >> 11) & 1) << 7)
            | 0x63
        )

    if op == "jal":
        count(2)
        immediate = signed_field(target(args[1]), 21)

        if immediate % 4:
            raise ValueError("This project needs word-aligned jump targets")

        return (
            ((immediate >> 20) << 31)
            | (((immediate >> 1) & 1023) << 21)
            | (((immediate >> 11) & 1) << 20)
            | (((immediate >> 12) & 255) << 12)
            | (register(args[0]) << 7)
            | 0x6f
        )

    raise ValueError(f"Unsupported instruction: {op}")


def assemble(source):
    labels = {}
    statements = []

    # Pass 1: record labels. Every instruction (including NOP) takes four bytes.
    for line_number, raw in enumerate(source.splitlines(), 1):
        text = raw.split("#", 1)[0].strip()

        if ":" in text:
            name, text = (piece.strip() for piece in text.split(":", 1))
            if not re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", name) or name in labels:
                raise ValueError(f"Line {line_number}: invalid or duplicate label")

            labels[name] = 4 * len(statements)

        if text and text != ".text":
            statements.append((line_number, text))

    if not 1 <= len(statements) <= 256:
        raise ValueError("A program must contain 1 through 256 instructions")

    # Pass 2: turn each instruction into a 32-bit word, now knowing all labels.
    words = []
    for index, (line_number, text) in enumerate(statements):
        try:
            words.append(encode(text, index * 4, labels))
        except (ValueError, KeyError) as error:
            raise ValueError(f"Line {line_number}: {text}: {error}") from error

    return words


def write_hex(words, path):
    # Fill unused ROM locations with NOPs so readmemh reads exactly 256 words.
    padded = words + [0x00000013] * (256 - len(words))
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(f"{word:08x}\n" for word in padded), encoding="ascii")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()

    try:
        words = assemble(arguments.source.read_text(encoding="utf-8"))
        write_hex(words, arguments.output)
    except (ValueError, OSError) as error:
        parser.error(str(error))

    print(f"Assembled {len(words)} instructions into {arguments.output}")
