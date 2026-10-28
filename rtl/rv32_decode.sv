`timescale 1ns / 1ps
`default_nettype none
`include "rv32_defs.svh"

// Decode the register numbers, immediate value, and controls for one instruction.
module rv32_decode (
    input  wire [31:0] instruction,

    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [4:0]  rd,

    output reg         uses_rs1,
    output reg         uses_rs2,
    output reg         reg_write,
    output reg  [2:0]  alu_operation,
    output reg         alu_b_immediate,
    output reg  [31:0] immediate,

    output reg         mem_read,
    output reg         mem_write,
    output reg         branch,
    output reg         branch_not_equal,
    output reg         jal,
    output reg         halt_request
);

    reg unsupported;

    wire [6:0] opcode = instruction[6:0];
    wire [2:0] funct3 = instruction[14:12];
    wire [6:0] funct7 = instruction[31:25];

    assign rs1 = instruction[19:15];
    assign rs2 = instruction[24:20];
    assign rd = instruction[11:7];

    always @* begin
        // Defaults mean "do nothing". Every output is assigned on every path,
        // so the decoder does not need to remember the previous instruction.
        uses_rs1 = 1'b0;
        uses_rs2 = 1'b0;
        reg_write = 1'b0;

        alu_operation = `ALU_ADD;
        alu_b_immediate = 1'b0;
        immediate = 32'b0;

        mem_read = 1'b0;
        mem_write = 1'b0;

        branch = 1'b0;
        branch_not_equal = 1'b0;
        jal = 1'b0;
        halt_request = 1'b0;
        unsupported = 1'b0;

        case (opcode)
            7'b0110011: begin                    // ADD, SUB, AND, OR, XOR
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b1;
                reg_write = 1'b1;

                case ({funct7, funct3})
                    10'b0000000_000: alu_operation = `ALU_ADD;
                    10'b0100000_000: alu_operation = `ALU_SUB;
                    10'b0000000_111: alu_operation = `ALU_AND;
                    10'b0000000_110: alu_operation = `ALU_OR;
                    10'b0000000_100: alu_operation = `ALU_XOR;
                    default: unsupported = 1'b1;
                endcase
            end

            7'b0010011: begin                    // ADDI only
                uses_rs1 = 1'b1;
                reg_write = 1'b1;
                alu_b_immediate = 1'b1;

                // Copy the sign bit so a negative 12-bit immediate stays negative.
                immediate = {{20{instruction[31]}}, instruction[31:20]};
                unsupported = (funct3 != 3'b000);
            end

            7'b0000011: begin                    // LW: address = rs1 + offset
                uses_rs1 = 1'b1;
                reg_write = 1'b1;
                mem_read = 1'b1;
                alu_b_immediate = 1'b1;
                immediate = {{20{instruction[31]}}, instruction[31:20]};
                unsupported = (funct3 != 3'b010);
            end

            7'b0100011: begin                    // SW: store rs2 at rs1 + offset
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b1;
                mem_write = 1'b1;
                alu_b_immediate = 1'b1;
                immediate = {{20{instruction[31]}}, instruction[31:25],
                             instruction[11:7]};
                unsupported = (funct3 != 3'b010);
            end

            7'b1100011: begin                    // BEQ and BNE
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b1;
                branch = 1'b1;
                branch_not_equal = (funct3 == 3'b001);
                immediate = {{19{instruction[31]}}, instruction[31],
                             instruction[7], instruction[30:25],
                             instruction[11:8], 1'b0};
                unsupported = (funct3 != 3'b000 && funct3 != 3'b001);
            end

            7'b1101111: begin                    // JAL: jump and save PC + 4
                reg_write = 1'b1;
                jal = 1'b1;
                immediate = {{11{instruction[31]}}, instruction[31],
                             instruction[19:12], instruction[20],
                             instruction[30:21], 1'b0};
            end

            7'b1110011: begin                    // EBREAK: simulation stop marker
                if (instruction == 32'h00100073)
                    halt_request = 1'b1;
                else
                    unsupported = 1'b1;
            end

            default: unsupported = 1'b1;
        endcase

        // Unsupported instructions cannot write registers/memory or redirect PC.
        // The testbench reports the error; the CPU has no exception system.
        if (unsupported) begin
            uses_rs1 = 1'b0;
            uses_rs2 = 1'b0;
            reg_write = 1'b0;
            mem_read = 1'b0;
            mem_write = 1'b0;
            branch = 1'b0;
            jal = 1'b0;
        end
    end

endmodule

`default_nettype wire
