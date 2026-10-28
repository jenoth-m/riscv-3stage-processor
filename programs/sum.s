# Sum 1 through 10. The answer (55) is stored at data address 0.

    addi x1, x0, 1          # Current number
    addi x2, x0, 11         # Stop before adding 11
    addi x3, x0, 0          # Running total

loop:
    add  x3, x3, x1
    addi x1, x1, 1
    bne  x1, x2, loop       # Repeat until the current number reaches 11

    sw   x3, 0(x0)
    ebreak                 # Stop simulation and expose the result
