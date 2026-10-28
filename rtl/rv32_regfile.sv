`timescale 1ns / 1ps
`default_nettype none

module rv32_regfile (
    input  wire        clk,
    input  wire        reset,

    input  wire [4:0]  rs1,
    input  wire [4:0]  rs2,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data,

    input  wire        write_enable,
    input  wire [4:0]  rd,
    input  wire [31:0] write_data
);

    reg [31:0] registers [0:31];
    integer index;

    // Two read ports let an instruction read both source registers at once.
    assign rs1_data = (rs1 == 0) ? 32'b0 : registers[rs1];
    assign rs2_data = (rs2 == 0) ? 32'b0 : registers[rs2];

    always @(posedge clk) begin
        if (reset) begin
            // Clearing every register makes the examples easy to follow.
            // The RISC-V ISA only requires x0 to behave as a constant zero.
            for (index = 0; index < 32; index = index + 1)
                registers[index] <= 32'b0;
        end
        else if (write_enable && rd != 0) begin
            registers[rd] <= write_data;
        end
    end

endmodule

`default_nettype wire
