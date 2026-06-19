`timescale 1ns/1ps

module tb_program_fetch
    import anv32_config_pkg::*;
#(
    parameter INIT_FILE = "",
    parameter WORD_HEX_FILE = "",
    parameter int PROGRAM_WORDS = 1,
    parameter logic [XLEN-1:0] PC_RESET_VALUE = RESET_PC
);
    localparam int WORDS = (PROGRAM_WORDS < 1) ? 1 : PROGRAM_WORDS;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic stall = 1'b0;
    logic pc_jmp_en = 1'b0;
    logic [31:0] pc_jmp_addr = '0;
    logic [31:0] pc_o;
    logic [31:0] instr_o;
    logic instr_valid;

    logic [31:0] expected [0:WORDS-1];
    int unsigned errors = 0;

    always #5 clk = ~clk;

    anv32i1_top #(
        .PC_RESET_VALUE(PC_RESET_VALUE),
        .INIT_FILE(INIT_FILE)
    ) dut (
        .clk_i(clk),
        .rst_i(rst),
        .stall_i(stall),
        .pc_jmp_en_i(pc_jmp_en),
        .pc_jmp_addr_i(pc_jmp_addr),
        .pc_o(pc_o),
        .instr_o(instr_o),
        .instr_valid_o(instr_valid)
    );

    task automatic tick();
        @(posedge clk);
        #1;
    endtask

    initial begin
        if (WORD_HEX_FILE == "") begin
            $fatal(1, "WORD_HEX_FILE parameter is empty");
        end
        $readmemh(WORD_HEX_FILE, expected);

        repeat (2) tick();
        @(negedge clk);
        rst = 1'b0;

        for (int i = 0; i < PROGRAM_WORDS; i++) begin
            logic [XLEN-1:0] exp_pc;
            exp_pc = PC_RESET_VALUE + (i * 32'd4);
            tick();
            if (!instr_valid) begin
                errors++;
                $display("[FAIL] word %0d: instr_valid=0", i);
            end
            if (pc_o !== exp_pc) begin
                errors++;
                $display("[FAIL] word %0d: pc=%08h exp=%08h",
                         i, pc_o, exp_pc);
            end
            if (instr_o !== expected[i]) begin
                errors++;
                $display("[FAIL] word %0d: instr=%08h exp=%08h",
                         i, instr_o, expected[i]);
            end
        end

        if (errors == 0) begin
            $display("PASS fetched %0d program words from %s", PROGRAM_WORDS, INIT_FILE);
        end else begin
            $display("FAIL %0d errors while fetching %0d program words",
                     errors, PROGRAM_WORDS);
        end
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "timeout");
    end
endmodule
