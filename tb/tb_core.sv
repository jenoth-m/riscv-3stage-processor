`timescale 1ns / 1ps
`default_nettype none

// Simulation only: supply memories, run a program, and check its final answers.
module tb_core;

    localparam integer MEMORY_WORDS = 256;

    reg clk = 1'b0;
    reg reset = 1'b1;
    always #5 clk = !clk;

    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;
    wire        dmem_read;
    wire        dmem_write;
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [31:0] dmem_rdata;
    wire        halted;

    rv32_core dut (
        .clk(clk),
        .reset(reset),

        .imem_addr(imem_addr),
        .imem_rdata(imem_rdata),

        .dmem_read(dmem_read),
        .dmem_write(dmem_write),
        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_rdata(dmem_rdata),

        .halted(halted)
    );

    reg [31:0] instruction_memory [0:MEMORY_WORDS - 1];
    reg [31:0] data_memory [0:MEMORY_WORDS - 1];
    reg [31:0] expected_registers [0:31];
    reg [31:0] expected_memory [0:MEMORY_WORDS - 1];

    string test_name;
    string program_path;
    string wave_path;

    integer index;
    integer store_count = 0;
    integer expected_stores;

    // Addresses count bytes, but each array entry contains four bytes.
    // Removing the lowest two address bits divides the address by four.
    assign imem_rdata = (imem_addr < 1024)
                      ? instruction_memory[imem_addr[9:2]] : 32'h00000013;

    assign dmem_rdata = (dmem_addr < 1024)
                      ? data_memory[dmem_addr[9:2]] : 32'b0;

    always @(posedge clk) begin
        if (reset)
            store_count <= 0;
        else if (dmem_write) begin
            data_memory[dmem_addr[9:2]] <= dmem_wdata;
            store_count <= store_count + 1;
        end
    end

    task set_expected_values;
        begin
            for (index = 0; index < 32; index = index + 1)
                expected_registers[index] = 0;

            for (index = 0; index < MEMORY_WORDS; index = index + 1)
                expected_memory[index] = 0;

            if (test_name == "sum") begin
                expected_registers[1] = 11;
                expected_registers[2] = 11;
                expected_registers[3] = 55;

                expected_memory[0] = 55;
                expected_stores = 1;
            end
            else if (test_name == "fibonacci") begin
                expected_registers[1] = 55;
                expected_registers[2] = 89;
                expected_registers[3] = 40;
                expected_registers[5] = 89;

                expected_memory[1] = 1;
                expected_memory[2] = 1;
                expected_memory[3] = 2;
                expected_memory[4] = 3;
                expected_memory[5] = 5;
                expected_memory[6] = 8;
                expected_memory[7] = 13;
                expected_memory[8] = 21;
                expected_memory[9] = 34;
                expected_stores = 10;
            end
            else if (test_name == "array_sum") begin
                expected_registers[1] = 32'hffffffff;  // -1
                expected_registers[2] = 20;
                expected_registers[4] = 11;
                expected_registers[5] = 32'hffffffff;

                expected_memory[0] = 3;
                expected_memory[1] = 32'hfffffffe;     // -2
                expected_memory[2] = 7;
                expected_memory[3] = 4;
                expected_memory[4] = 32'hffffffff;
                expected_memory[5] = 11;
                expected_stores = 6;
            end
            else if (test_name == "hazards") begin
                expected_registers[1] = 7;
                expected_registers[2] = 14;
                expected_registers[3] = 21;
                expected_registers[4] = 21;
                expected_registers[5] = 28;
                expected_registers[6] = 21;
                expected_registers[7] = 32'hfffffff2;  // -14
                expected_registers[8] = 16;
                expected_registers[9] = 21;
                expected_registers[10] = 21;
                expected_registers[12] = 12;
                expected_registers[13] = 12;
                expected_registers[14] = 6;
                expected_registers[15] = 6;
                expected_registers[16] = 7;
                expected_registers[18] = 124;         // JAL's PC + 4
                expected_registers[20] = 124;
                expected_registers[22] = 4;

                expected_memory[0] = 124;
                expected_memory[2] = 21;
                expected_memory[3] = 28;
                expected_memory[4] = 28;
                expected_memory[6] = 12;
                expected_stores = 6;

                // All unlisted registers and memory words must stay zero.
            end
            else begin
                $fatal(1, "Unknown test: %s", test_name);
            end
        end
    endtask

    task check_results;
        begin
            for (index = 0; index < 32; index = index + 1) begin
                if (dut.regfile.registers[index] !== expected_registers[index])
                    $fatal(1, "x%0d = %08x, expected %08x", index,
                           dut.regfile.registers[index], expected_registers[index]);
            end

            for (index = 0; index < MEMORY_WORDS; index = index + 1) begin
                if (data_memory[index] !== expected_memory[index])
                    $fatal(1, "Memory address %0d = %08x, expected %08x", index * 4,
                           data_memory[index], expected_memory[index]);
            end

            if (store_count != expected_stores)
                $fatal(1, "Store count = %0d, expected %0d", store_count, expected_stores);
        end
    endtask

    // Catch mistakes in example programs. These checks are not CPU fault logic.
    always @(posedge clk) begin
        if (!reset && !halted) begin
            if ((dmem_read || dmem_write) &&
                (dmem_addr >= 1024 || dmem_addr[1:0] != 0 || ^dmem_addr === 1'bx))
                $fatal(1, "Invalid or unaligned data address");

            // Check issued instructions, not a fetch that may be flushed.
            if (dut.x_valid && dut.advance_x) begin
                if (dut.x_pc >= 1024 || dut.x_pc[1:0] != 0 || ^dut.x_pc === 1'bx)
                    $fatal(1, "Invalid or unaligned instruction address");
                if (dut.decoder.unsupported)
                    $fatal(1, "Unsupported instruction at PC %08x", dut.x_pc);
            end
        end
    end

    initial begin
        if (!$value$plusargs("test=%s", test_name))
            $fatal(1, "Missing +test=name");
        if (!$value$plusargs("program=%s", program_path))
            $fatal(1, "Missing +program=path.hex");

        for (index = 0; index < MEMORY_WORDS; index = index + 1) begin
            instruction_memory[index] = 32'h00000013;
            data_memory[index] = 0;
        end
        $readmemh(program_path, instruction_memory);
        set_expected_values();

        if ($value$plusargs("vcd=%s", wave_path)) begin
            $dumpfile(wave_path);
            $dumpvars(0, dut);
        end

        // Change reset away from the rising edge, when the CPU is updating.
        repeat (3) @(negedge clk);
        reset = 1'b0;
        wait (halted);
        @(negedge clk);
        check_results();

        // Ensure the instruction after EBREAK cannot change the result.
        repeat (3) @(negedge clk);
        check_results();
        if (!halted || dmem_read || dmem_write)
            $fatal(1, "Processor did not remain stopped");

        $display("PASS %s: registers, memory, and store count match", test_name);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "Program timed out instead of reaching EBREAK");
    end

endmodule

`default_nettype wire
