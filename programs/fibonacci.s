# Store the first ten Fibonacci numbers in data memory:
# 0, 1, 1, 2, 3, 5, 8, 13, 21, 34.

    addi x1, x0, 0         # Previous number
    addi x2, x0, 1         # Current number
    addi x3, x0, 0         # Output address
    addi x4, x0, 10        # Numbers remaining

loop:
    sw   x1, 0(x3)
    add  x5, x1, x2
    addi x1, x2, 0
    addi x2, x5, 0
    addi x3, x3, 4
    addi x4, x4, -1
    bne  x4, x0, loop

    ebreak
