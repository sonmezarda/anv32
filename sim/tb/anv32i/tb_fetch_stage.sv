`timescale 1ns/1ps
module tb_fetch_stage;
    logic clk;
    logic rst;
    logic stall;
    logic [31:0] pc_jmp_addr;
    logic pc_jmp_en;
    logic [31:0] pc_o;
    logic [31:0] instr_o;

    fetch_stage dut (
        .clk_i(clk),
        .rst_i(rst),
        .stall_i(stall),
        .pc_jmp_addr_i(pc_jmp_addr),
        .pc_jmp_en_i(pc_jmp_en),
        .pc_o(pc_o),
        .instr_i(instr_mem[pc_o[5:2]]), // Fetch instruction based on the current word address
        .instr_o(instr_o)
    );


    logic [31:0] instr_mem [0:15];

    task automatic check_state(
        input logic [31:0] exp_pc,
        input logic [31:0] exp_instr,
        input string label
    );
        if ((pc_o !== exp_pc) || (instr_o !== exp_instr)) begin
            $error(
                "%s: expected PC=%h INSTR=%h, got PC=%h INSTR=%h",
                label, exp_pc, exp_instr, pc_o, instr_o
            );
        end

        $display("%s: PC = %h, Instruction = %h", label, pc_o, instr_o);
    endtask

    always #5 clk = ~clk;   // free-running: 10ns period
    initial begin
        instr_mem[0] = 32'h0000_0010;
        instr_mem[1] = 32'h0000_0011;
        instr_mem[2] = 32'h0000_0012;
        instr_mem[3] = 32'h0000_0013;
        instr_mem[4] = 32'h0000_0014;
        instr_mem[5] = 32'h0000_0015;
        instr_mem[6] = 32'h0000_0016;
        instr_mem[7] = 32'h0000_0017;   
        clk = 0;
        rst = 1;
        stall = 0;
        pc_jmp_en = 0;
        pc_jmp_addr = '0;

        @(posedge clk); #1;
        check_state(32'h8000_0000, 32'h0000_0010, "After reset");

        @(negedge clk);
        rst = 0;

        // Test jump functionality
        pc_jmp_en = 1; // Enable jump
        pc_jmp_addr = 32'h8000_000c; // Jump to instruction index 3
        @(posedge clk); // Wait for the next clock edge to capture the jump
        #1; // Allow time for the output to settle
        check_state(32'h8000_000c, 32'h0000_0013, "After jump");

        pc_jmp_en = 0; // Disable jump
        @(posedge clk); // Wait for the next clock edge to capture next instruction
        #1;
        check_state(32'h8000_0010, 32'h0000_0014, "After jump disabled");
        
        @(posedge clk); #1;
        check_state(32'h8000_0014, 32'h0000_0015, "After 1 cycle");
        

        @(posedge clk); #1;
        check_state(32'h8000_0018, 32'h0000_0016, "After 2 cycles");

        stall = 1; // Enable stall
        @(posedge clk); #1;
        check_state(32'h8000_0018, 32'h0000_0016, "After stall enabled");

        stall = 0; // Disable stall
        @(posedge clk); #1;
        check_state(32'h8000_001c, 32'h0000_0017, "After stall disabled");

        rst = 1; // Assert reset
        @(posedge clk); #1;
        check_state(32'h8000_0000, 32'h0000_0010, "After reset asserted");

        $finish; // End simulation
    end



endmodule
