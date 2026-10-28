`ifndef RV32_DEFS_SVH
`define RV32_DEFS_SVH

// These are internal ALU choices, not complete RISC-V instructions.
// Three bits are enough to select our five operations.
`define ALU_ADD  3'd0
`define ALU_SUB  3'd1
`define ALU_AND  3'd2
`define ALU_OR   3'd3
`define ALU_XOR  3'd4

`endif
