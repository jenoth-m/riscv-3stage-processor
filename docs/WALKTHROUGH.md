# Code walkthrough

The processor implements an RV32I subset using three stages: fetch, decode/execute, and memory/writeback.

## RTL modules

| File | Purpose |
| --- | --- |
| `rtl/rv32_regfile.sv` | 32 registers, two read ports, and one write port. Reads of `x0` return zero; writes to it are ignored. |
| `rtl/rv32_alu.sv` | ADD, SUB, AND, OR, and XOR operations. Operation codes are defined in `rv32_defs.svh`. |
| `rtl/rv32_decode.sv` | Extracts instruction fields, reconstructs immediates, and generates control signals. |
| `rtl/rv32_core.sv` | Connects the modules and handles pipeline state, forwarding, stalls, and redirects. |

## Pipeline

Fetch reads the instruction at `pc`. X decodes and executes an instruction, while W completes an older instruction’s memory operation or register write.

During normal operation, X advances into W, the fetched instruction enters X, and PC increases by four. Valid bits mark whether X and W contain active instructions.

The memories provide combinational reads without wait states.

## Dependencies and control flow

ALU and JAL results in W can be forwarded directly to X. The forwarded operands also feed branch comparisons and store address/data calculations.

Load data is not forwarded. When X depends on a load in W, PC and X hold for one cycle. The load writes its register and W becomes an empty slot, allowing X to read the updated value next cycle.

A taken branch or JAL sets PC to `x_pc + x_immediate` and invalidates the fetched sequential instruction. JAL also writes its return address, `x_pc + 4`.

When EBREAK reaches W, the processor halts and discards younger work. EBREAK is a simulation stop marker here, rather than a standard breakpoint exception.

## Running the simulations

Run all four programs:

```powershell
py tools/run.py
```

Run the hazard checks and save a waveform:

```powershell
py tools/run.py hazards --wave
```

Open `build/hazards.vcd` in GTKWave. On Linux/macOS, replace `py` with `python3`.

The testbench supplies the memories and checks final registers, memory contents, and store counts. For example, `programs/sum.s` adds 1 through 10, stores 55 at byte address zero, and stops with EBREAK.

## Assembler

`tools/assembler.py` uses two passes: one collects label addresses; the other encodes instructions.

It accepts `x0`–`x31`, labels, decimal and hexadecimal values, and `#` comments. Each instruction occupies four bytes. ADDI, LW, and SW use signed 12-bit immediates; supported memory accesses and instruction targets must be word-aligned.

Programs contain up to 256 instructions. Unused instruction-memory locations are filled with NOPs.

To assemble a file separately:

```powershell
py tools/assembler.py programs/sum.s build/sum.hex
```

The runner checks the four included programs. To add another checked program, update `PROGRAMS` in `tools/run.py` and `set_expected_values` in `tb/tb_core.sv`.