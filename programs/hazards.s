# Each section checks one pipeline behavior. Expected answers are in tb_core.sv.

    addi x1, x0, 7
    add  x2, x1, x1         # Forward into both ALU inputs: 14
    add  x3, x1, x2         # Forward into the second input: 21
    sw   x3, 0(x0)          # Forward into store data

    lw   x4, 0(x0)
    add  x5, x4, x1         # Load-use stall for rs1: 28
    lw   x6, 0(x0)
    sub  x7, x1, x6         # Load-use stall for rs2: -14

    addi x8, x0, 16
    sw   x5, 0(x8)          # Forward into a store's base address
    lw   x9, 0(x0)
    sw   x9, 8(x0)          # Load-to-store data dependency
    lw   x10, 8(x0)
    beq  x10, x3, load_branch_ok
    sw   x1, 4(x0)          # Wrong path: address 4 must stay zero
    addi x11, x0, 99        # Also skipped

load_branch_ok:
    addi x12, x0, 12
    sw   x12, 24(x0)
    lw   x13, 24(x0)
    sw   x5, 0(x13)         # Load-to-store address dependency

    addi x14, x0, 6
    and  x15, x14, x1       # 6 AND 7 = 6
    or   x16, x15, x1       # 6 OR 7 = 7
    xor  x17, x16, x1       # 7 XOR 7 = 0
    beq  x17, x0, logic_ok  # Forward directly into a branch comparison
    sw   x1, 20(x0)         # Wrong path

logic_ok:
    bne  x1, x1, bad        # Not taken: the values are equal
    beq  x1, x2, bad        # Not taken: 7 is not 14
    bne  x1, x2, jump_test  # Taken
    sw   x1, 28(x0)         # Wrong path

jump_test:
    jal  x18, jump_target   # Save PC + 4 (124) in x18
    sw   x1, 32(x0)         # Wrong path
    addi x19, x0, 99        # Also skipped

jump_target:
    add  x20, x18, x0       # Check the saved link value
    addi x0, x0, 99         # Writes to x0 must be ignored
    add  x21, x0, x0        # Must still be zero
    lw   x0, 0(x0)          # Loads to x0 also discard their result
    addi x22, x0, 4
    sw   x20, -4(x22)       # Negative offset: store 124 at address zero

    ebreak
    sw   x1, 36(x0)         # Younger than EBREAK: must never execute

bad:
    sw   x1, 40(x0)         # Reaching here is a failed branch test
    ebreak
