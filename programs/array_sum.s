# Add five numbers stored in memory: 3 + (-2) + 7 + 4 + (-1) = 11.
# Store the result at byte address 20.

    addi x1, x0, 3
    sw   x1, 0(x0)

    addi x1, x0, -2
    sw   x1, 4(x0)

    addi x1, x0, 7
    sw   x1, 8(x0)

    addi x1, x0, 4
    sw   x1, 12(x0)

    addi x1, x0, -1
    sw   x1, 16(x0)

    addi x2, x0, 0          # Address of the next element
    addi x3, x0, 5          # Elements remaining
    addi x4, x0, 0          # Total

loop:
    lw   x5, 0(x2)
    add  x4, x4, x5         # Wait one cycle for the load above
    addi x2, x2, 4          # A 32-bit word occupies four bytes
    addi x3, x3, -1
    bne  x3, x0, loop

    sw   x4, 20(x0)
    ebreak
