`timescale 1ns/1ps

module tb_mem_ready_stall
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
#(
    parameter INIT_FILE = "",
    parameter int unsigned MAX_CYCLES = 80,
    parameter int unsigned WAIT_CYCLES = 3,
    parameter logic [XLEN-1:0] PC_RESET_VALUE = RESET_PC
);
    logic clk = 1'b0;
    logic rst = 1'b1;

    logic [31:0] pc_o;
    logic [31:0] instr_o;
    logic        instr_valid_o;
    logic [31:0] instr_addr;
    logic [31:0] instr_rdata;

    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [31:0] mem_rdata;
    logic        mem_valid;
    logic        mem_ready = 1'b1;
    logic [3:0]  mem_we;
    logic [3:0]  ram_we;

    logic        wait_active;
    int unsigned wait_left;
    logic [31:0] wait_addr;
    logic [31:0] wait_wdata;
    logic [3:0]  wait_we;
    logic        saw_wait;
    int unsigned errors;
    int unsigned cycle;

    always #5 clk = ~clk;

    assign ram_we = mem_ready ? mem_we : 4'b0000;

    anv32im2_top #(
        .PC_RESET_VALUE(PC_RESET_VALUE)
    ) dut (
        .clk_i(clk),
        .rst_i(rst),
        .stall_i(1'b0),
        .pc_jmp_en_i(1'b0),
        .pc_jmp_addr_i('0),
        .ext_irq_i(1'b0),
        .pc_o(pc_o),
        .instr_o(instr_o),
        .instr_valid_o(instr_valid_o),
        .instr_i(instr_rdata),
        .instr_addr_o(instr_addr),
        .mem_rdata_i(mem_rdata),
        .mem_ready_i(mem_ready),
        .mem_wdata_o(mem_wdata),
        .mem_addr_o(mem_addr),
        .mem_valid_o(mem_valid),
        .mem_we(mem_we)
    );

    anv32_bram_tdp #(
        .ADDR_W(10),
        .INIT_FILE(INIT_FILE)
    ) ram (
        .clk(clk),
        .addr_a(mem_addr[11:2]),
        .wdata_a(mem_wdata),
        .we_a(ram_we),
        .rdata_a(mem_rdata),
        .addr_b(instr_addr[11:2]),
        .wdata_b(32'b0),
        .we_b(4'b0),
        .rdata_b(instr_rdata)
    );

    function automatic string hex32(input logic [31:0] v);
        return $sformatf("%08h", v);
    endfunction

    task automatic fail(input string msg);
        errors++;
        $display("  [FAIL] cycle=%0d %s", cycle, msg);
    endtask

    always @(negedge clk) begin
        if(rst) begin
            mem_ready   = 1'b1;
            wait_active = 1'b0;
            wait_left   = 0;
            wait_addr   = 32'b0;
            wait_wdata  = 32'b0;
            wait_we     = 4'b0;
        end else if(!mem_valid) begin
            mem_ready   = 1'b1;
            wait_active = 1'b0;
            wait_left   = 0;
        end else if(!wait_active ||
                    (mem_addr != wait_addr) ||
                    (mem_wdata != wait_wdata) ||
                    (mem_we != wait_we)) begin
            wait_active = 1'b1;
            wait_left   = WAIT_CYCLES;
            wait_addr   = mem_addr;
            wait_wdata  = mem_wdata;
            wait_we     = mem_we;
            mem_ready   = (WAIT_CYCLES == 0);
        end else if(wait_left != 0) begin
            wait_left = wait_left - 1;
            mem_ready = (wait_left == 0);
        end else begin
            mem_ready = 1'b1;
        end
    end

    task automatic print_cycle();
        $display("%3d pc=%s instr=%s valid=%0b ready=%0b addr=%s we=%1h wdata=%s stall={f:%0b d:%0b e:%0b m:%0b w:%0b}",
                 cycle,
                 hex32(pc_o),
                 hex32(instr_o),
                 mem_valid,
                 mem_ready,
                 hex32(mem_addr),
                 mem_we,
                 hex32(mem_wdata),
                 dut.stall_f_eff,
                 dut.stall_d_eff,
                 dut.stall_e_eff,
                 dut.stall_m_eff,
                 dut.stall_w_eff);
        if(!rst && mem_valid && !mem_ready) begin
            saw_wait = 1'b1;

            if(mem_addr !== wait_addr) begin
                fail($sformatf("mem_addr changed while ready=0: got=%s exp=%s",
                               hex32(mem_addr), hex32(wait_addr)));
            end
            if(mem_wdata !== wait_wdata) begin
                fail($sformatf("mem_wdata changed while ready=0: got=%s exp=%s",
                               hex32(mem_wdata), hex32(wait_wdata)));
            end
            if(mem_we !== wait_we) begin
                fail($sformatf("mem_we changed while ready=0: got=%1h exp=%1h",
                               mem_we, wait_we));
            end
            if(!(dut.stall_f_eff && dut.stall_d_eff &&
                 dut.stall_e_eff && dut.stall_m_eff && dut.stall_w_eff)) begin
                fail("not all pipeline stages stalled while mem_ready=0");
            end
        end
    endtask

    initial begin
        if(INIT_FILE == "") begin
            $fatal(1, "INIT_FILE parameter is empty");
        end

        saw_wait = 1'b0;
        errors   = 0;
        cycle    = 0;

        $display("INIT_FILE=%s WAIT_CYCLES=%0d", INIT_FILE, WAIT_CYCLES);
        $display("cyc pc       instr    valid ready addr     we wdata    stall");

        repeat (2) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        while(cycle < MAX_CYCLES) begin
            @(posedge clk);
            #1;
            print_cycle();
            if(dut.einstr.valid && dut.einstr.is_halt) begin
                break;
            end
            cycle++;
        end

        if(!saw_wait) begin
            fail("no mem_ready wait cycle observed");
        end

        if(errors == 0) begin
            $display("PASS mem_ready stall trace");
        end else begin
            $fatal(1, "FAIL mem_ready stall trace: %0d errors", errors);
        end
        $finish;
    end
endmodule
