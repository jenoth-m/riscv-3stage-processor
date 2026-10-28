`timescale 1ns / 1ps
`default_nettype none

// F = fetch, X = decode/execute, W = memory/writeback.
// Both memories provide read data without wait states. Stores use a clock edge.
module rv32_core #(
    parameter [31:0] RESET_PC = 32'h00000000
) (
    input  wire        clk,
    input  wire        reset,

    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,

    output wire        dmem_read,
    output wire        dmem_write,
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    input  wire [31:0] dmem_rdata,

    output reg         halted
);

    // These registers keep the instruction and its PC together between stages.
    reg [31:0] pc;
    reg        x_valid;
    reg [31:0] x_pc;
    reg [31:0] x_instruction;

    // W keeps the calculated result with its destination and memory controls.
    reg        w_valid;
    reg [4:0]  w_rd;
    reg        w_reg_write;
    reg [31:0] w_result;
    reg        w_mem_read;
    reg        w_mem_write;
    reg [31:0] w_store_data;
    reg        w_halt;

    wire [4:0]  x_rs1;
    wire [4:0]  x_rs2;
    wire [4:0]  x_rd;
    wire        x_uses_rs1;
    wire        x_uses_rs2;
    wire        x_reg_write;
    wire [2:0]  x_alu_operation;
    wire        x_alu_b_immediate;
    wire [31:0] x_immediate;
    wire        x_mem_read;
    wire        x_mem_write;
    wire        x_branch;
    wire        x_branch_not_equal;
    wire        x_jal;
    wire        x_halt;

    // Values flowing between the register file, forwarding logic, and ALU.
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    wire [31:0] operand_a;
    wire [31:0] operand_b;
    wire [31:0] alu_b;
    wire [31:0] alu_result;
    wire [31:0] x_result;
    wire [31:0] writeback_data;

    wire writeback_enable;
    wire forward_available;
    wire branch_condition;
    wire load_stall;
    wire stop_now;
    wire advance_x;
    wire redirect;

    rv32_decode decoder (
        .instruction(x_instruction),
        .rs1(x_rs1),
        .rs2(x_rs2),
        .rd(x_rd),

        .uses_rs1(x_uses_rs1),
        .uses_rs2(x_uses_rs2),
        .reg_write(x_reg_write),
        .alu_operation(x_alu_operation),
        .alu_b_immediate(x_alu_b_immediate),
        .immediate(x_immediate),

        .mem_read(x_mem_read),
        .mem_write(x_mem_write),
        .branch(x_branch),
        .branch_not_equal(x_branch_not_equal),
        .jal(x_jal),
        .halt_request(x_halt)
    );

    rv32_regfile regfile (
        .clk(clk),
        .reset(reset),

        .rs1(x_rs1),
        .rs2(x_rs2),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),

        .write_enable(writeback_enable),
        .rd(w_rd),
        .write_data(writeback_data)
    );

    // Use the newest ALU/jump result if X needs a register that W is writing.
    // The forwarded values also feed store data and branch comparisons.
    assign forward_available = w_valid && w_reg_write && !w_mem_read &&
                               (w_rd != 0);

    assign operand_a = (forward_available && w_rd == x_rs1)
                     ? w_result : rs1_data;

    assign operand_b = (forward_available && w_rd == x_rs2)
                     ? w_result : rs2_data;

    // Loads/stores use the ALU to add a base address and an immediate offset.
    assign alu_b = x_alu_b_immediate ? x_immediate : operand_b;

    rv32_alu alu (
        .a(operand_a),
        .b(alu_b),
        .operation(x_alu_operation),
        .result(alu_result)
    );

    // JAL saves its return address; the target is calculated in the redirect.
    assign x_result = x_jal ? x_pc + 32'd4 : alu_result;

    assign branch_condition = x_branch_not_equal
                            ? (operand_a != operand_b) : (operand_a == operand_b);

    // W finishes in one cycle. There is no valid/ready memory handshake.
    assign imem_addr = pc;

    assign dmem_read = w_valid && w_mem_read && !halted && !reset;
    assign dmem_write = w_valid && w_mem_write && !halted && !reset;
    assign dmem_addr = w_result;
    assign dmem_wdata = w_store_data;

    assign writeback_data = w_mem_read ? dmem_rdata : w_result;
    assign writeback_enable = w_valid && w_reg_write && !halted && !reset;

    // We deliberately do not forward load data. Hold the dependent instruction
    // for one cycle so it can read the register after the load writes it.
    assign load_stall = x_valid && w_valid && w_mem_read && (w_rd != 0) &&
                        ((x_uses_rs1 && x_rs1 == w_rd) ||
                         (x_uses_rs2 && x_rs2 == w_rd));

    assign stop_now = w_valid && w_halt;
    assign advance_x = !load_stall && !stop_now && !halted;
    assign redirect = x_valid && advance_x &&
                      (x_jal || (x_branch && branch_condition));

    always @(posedge clk) begin
        if (reset) begin
            pc <= RESET_PC;
            x_valid <= 1'b0;
            x_pc <= 32'b0;
            x_instruction <= 32'h00000013;  // ADDI x0, x0, 0 (NOP)

            w_valid <= 1'b0;
            w_rd <= 5'b0;
            w_reg_write <= 1'b0;
            w_result <= 32'b0;
            w_mem_read <= 1'b0;
            w_mem_write <= 1'b0;
            w_store_data <= 32'b0;
            w_halt <= 1'b0;
            halted <= 1'b0;
        end
        else if (!halted) begin
            if (stop_now) begin
                // EBREAK stops these examples; this is not a RISC-V trap handler.
                halted <= 1'b1;
                x_valid <= 1'b0;
                w_valid <= 1'b0;
            end
            else if (load_stall) begin
                // The load writes back now. Empty W, but keep PC and X unchanged.
                w_valid <= 1'b0;
            end
            else begin
                // Move X into W. A false valid bit marks an empty pipeline slot.
                w_valid <= x_valid;
                w_rd <= x_rd;
                w_reg_write <= x_reg_write;
                w_result <= x_result;
                w_mem_read <= x_mem_read;
                w_mem_write <= x_mem_write;
                w_store_data <= operand_b;
                w_halt <= x_halt;

                if (redirect) begin
                    pc <= x_pc + x_immediate;
                    x_valid <= 1'b0;  // Discard the fetched wrong-path instruction.
                end
                else begin
                    // Nonblocking assignments read the old PC at this edge.
                    pc <= pc + 32'd4;
                    x_valid <= 1'b1;
                    x_pc <= pc;
                    x_instruction <= imem_rdata;
                end
            end
        end
    end

endmodule

`default_nettype wire
