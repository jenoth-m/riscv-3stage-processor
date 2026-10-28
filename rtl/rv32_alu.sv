`timescale 1ns / 1ps
`default_nettype none
`include "rv32_defs.svh"

// This is a calculator, with no clock or stored state of its own.
module rv32_alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [2:0]  operation,
    output reg  [31:0] result
);

    always @* begin
        case (operation)
            `ALU_ADD: result = a + b;
            `ALU_SUB: result = a - b;
            `ALU_AND: result = a & b;
            `ALU_OR:  result = a | b;
            `ALU_XOR: result = a ^ b;

            // Assign a result even if the selector is not a supported value.
            default: result = 32'b0;
        endcase
    end

endmodule

`default_nettype wire
