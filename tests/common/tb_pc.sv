`timescale 1ns/1ps
module tb_pc;
    logic        clk = 0;
    logic        rst;
    logic [31:0] pc_next;
    logic [31:0] pc_current;

    anv32_pc #(.PC_RESET_VALUE('h8000_0000)) dut (
        .clk_i(clk),
        .rst_i(rst),
        .pc_next_i(pc_next),
        .pc_current_o(pc_current)
    );

    always #5 clk = ~clk;   // free-running: 10ns period

    initial begin
        rst     = 1;
        pc_next = 'h8000_0004;

        @(posedge clk);                 // 1st edge: rst active -> PC = reset
        @(negedge clk) rst = 0;         // drop reset away from edge (clean)
        $display("after reset:    %h (expect 80000000)", pc_current);

        @(posedge clk);                 // 2nd edge: rst=0 -> PC <= pc_next
        #1;                             // settle after edge
        $display("after next set: %h (expect 80000004)", pc_current);

        @(posedge clk);
        #1;
        $display("one more cycle: %h (expect 80000004)", pc_current);

        @(posedge clk); #1;
        $display("one more cycle: %h (expect 80000004)", pc_current);

        $finish;
    end
endmodule