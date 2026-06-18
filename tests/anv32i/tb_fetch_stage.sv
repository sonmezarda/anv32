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
        .instr_i(instr_mem[pc_o[3:0]]), // Fetch instruction based on current PC (word-aligned)
        .instr_o(instr_o)
    );


    logic [31:0] instr_mem [0:15];
   
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
        rst = 0;
        stall = 0;
        pc_jmp_addr = 32'h0000_0004;
        pc_jmp_en = 0;

//        #10 rst = 0; // Release reset after 10 time units


        // Test jump functionality
        pc_jmp_en = 1; // Enable jump
        pc_jmp_addr = 32'h8000_0003; // Set jump address
        @(posedge clk); // Wait for the next clock edge to capture the jump
        #1; // Allow time for the output to settle
        $display("After jump: PC = %h, Instruction = %h", pc_o, instr_o);

        pc_jmp_en = 0; // Disable jump
        @(posedge clk); // Wait for the next clock edge to capture next instruction
        #1;
        $display("After jump disabled: PC = %h, Instruction = %h", pc_o, instr_o);
        

        $finish; // End simulation
    end



endmodule