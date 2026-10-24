// Memory stage testbench: byte enables, store data alignment, load
// extension, and stall behavior.
`timescale 1ns/1ps

module tb_m_stage
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic stall = 1'b0;

    einstr_t         einstr;
    logic [XLEN-1:0] mem_rdata;
    logic [XLEN-1:0] mem_addr;
    logic [XLEN-1:0] mem_wdata;
    logic            mem_valid;
    logic [3:0]      mem_we;
    logic [XLEN-1:0] mem_rdata_o;
    minstr_t         minstr;

    int unsigned tests = 0;
    int unsigned errors = 0;
    string cur;

    always #5 clk = ~clk;

    anv32_memory_c1 dut (
        .clk_i       (clk),
        .rst_i       (rst),
        .stall_i     (stall),
        .einstr_i    (einstr),
        .mem_rdata_i (mem_rdata),
        .mem_valid_o (mem_valid),
        .mem_addr_o  (mem_addr),
        .mem_wdata_o (mem_wdata),
        .mem_we_o    (mem_we),
        .mem_rdata_o (mem_rdata_o),
        .minstr_o    (minstr)
    );

    function automatic einstr_t mk_einstr(
        logic valid,
        op_e op,
        logic is_mem,
        logic [XLEN-1:0] alu_result,
        logic [XLEN-1:0] write_data,
        logic [XLEN-1:0] link_pc,
        logic [4:0] rd_idx,
        logic rd_valid,
        wb_sel_e wb_sel
    );
        einstr_t e;
        e = '0;
        e.valid      = valid;
        e.op         = op;
        e.is_mem     = is_mem;
        e.alu_result = alu_result;
        e.write_data = write_data;
        e.link_pc    = link_pc;
        e.rd_idx     = rd_idx;
        e.rd_valid   = rd_valid;
        e.wb_sel     = wb_sel;
        return e;
    endfunction

    task automatic chk32(string nm, logic [31:0] got, logic [31:0] exp);
        tests++;
        if (got !== exp) begin
            errors++;
            $display("  [FAIL] %-12s %-14s got=%08h exp=%08h", cur, nm, got, exp);
        end
    endtask

    task automatic chk4(string nm, logic [3:0] got, logic [3:0] exp);
        tests++;
        if (got !== exp) begin
            errors++;
            $display("  [FAIL] %-12s %-14s got=%04b exp=%04b", cur, nm, got, exp);
        end
    endtask

    task automatic chk5(string nm, logic [4:0] got, logic [4:0] exp);
        tests++;
        if (got !== exp) begin
            errors++;
            $display("  [FAIL] %-12s %-14s got=%0d exp=%0d", cur, nm, got, exp);
        end
    endtask

    task automatic chk1(string nm, logic got, logic exp);
        tests++;
        if (got !== exp) begin
            errors++;
            $display("  [FAIL] %-12s %-14s got=%b exp=%b", cur, nm, got, exp);
        end
    endtask

    task automatic chk_wb(string nm, wb_sel_e got, wb_sel_e exp);
        tests++;
        if (got !== exp) begin
            errors++;
            $display("  [FAIL] %-12s %-14s got=%0d exp=%0d", cur, nm, got, exp);
        end
    endtask

    task automatic drive(
        string nm,
        einstr_t e,
        logic [XLEN-1:0] rdata,
        logic stall_value
    );
        cur = nm;
        @(negedge clk);
        einstr    = e;
        mem_rdata = rdata;
        stall     = stall_value;
        #1;
    endtask

    task automatic capture();
        @(posedge clk);
        #1;
    endtask

    task automatic chk_minstr(
        logic valid,
        logic [XLEN-1:0] alu_result,
        logic [XLEN-1:0] link_pc,
        logic [4:0] rd_idx,
        logic rd_valid,
        wb_sel_e wb_sel
    );
        chk1 ("m.valid",     minstr.valid,      valid);
        chk32("m.alu",       minstr.alu_result, alu_result);
        chk32("m.link",      minstr.link_pc,    link_pc);
        chk5 ("m.rd_idx",    minstr.rd_idx,     rd_idx);
        chk1 ("m.rd_valid",  minstr.rd_valid,   rd_valid);
        chk_wb("m.wb_sel",   minstr.wb_sel,     wb_sel);
    endtask

    task automatic check_store(
        string nm,
        op_e op,
        logic [XLEN-1:0] addr,
        logic [XLEN-1:0] wdata,
        logic [3:0] exp_we,
        logic [XLEN-1:0] exp_wdata
    );
        einstr_t e;
        e = mk_einstr(1'b1, op, 1'b1, addr, wdata, 32'h0000_0104,
                      5'd0, 1'b0, WB_ALU);
        drive(nm, e, 32'hCAFE_BABE, 1'b0);
        chk1 ("valid", mem_valid, 1'b1);
        chk32("addr",  mem_addr,   addr);
        chk4 ("we",    mem_we,     exp_we);
        chk32("wdata", mem_wdata,  exp_wdata);
        chk32("rdata", mem_rdata_o, 32'hCAFE_BABE);
        capture();
        chk_minstr(1'b1, addr, 32'h0000_0104, 5'd0, 1'b0, WB_ALU);
    endtask

    task automatic check_load(
        string nm,
        op_e op,
        logic [XLEN-1:0] addr,
        logic [XLEN-1:0] raw_rdata,
        logic [XLEN-1:0] exp_rdata
    );
        einstr_t e;
        e = mk_einstr(1'b1, op, 1'b1, addr, 32'h0, 32'h0000_0204,
                      5'd11, 1'b1, WB_MEM);
        drive(nm, e, raw_rdata, 1'b0);
        chk1 ("valid", mem_valid, 1'b1);
        chk32("addr",  mem_addr,    addr);
        chk4 ("we",    mem_we,      4'b0000);
        capture();
        chk32("rdata", mem_rdata_o, exp_rdata);
        chk_minstr(1'b1, addr, 32'h0000_0204, 5'd11, 1'b1, WB_MEM);
    endtask

    initial begin
        einstr = '0;
        mem_rdata = '0;

        cur = "reset";
        repeat (2) capture();
        chk1 ("m.valid",    minstr.valid,    1'b0);
        chk32("m.alu",      minstr.alu_result, 32'h0);
        chk32("rdata_hold", mem_rdata_o,     32'h0);

        @(negedge clk);
        rst = 1'b0;

        // Non-memory passthrough
        begin
            einstr_t e;
            e = mk_einstr(1'b1, ADD, 1'b0, 32'h1234_5678, 32'h0,
                          32'h8000_0004, 5'd5, 1'b1, WB_ALU);
            drive("ALU", e, 32'h1111_2222, 1'b0);
            chk1 ("valid", mem_valid, 1'b0);
            chk32("addr",  mem_addr,   32'h1234_5678);
            chk4 ("we",    mem_we,     4'b0000);
            chk32("wdata", mem_wdata,  32'h0);
            capture();
            chk_minstr(1'b1, 32'h1234_5678, 32'h8000_0004, 5'd5, 1'b1, WB_ALU);
        end

        begin
            einstr_t e;
            e = mk_einstr(1'b1, JAL, 1'b0, 32'h0000_0200, 32'h0,
                          32'h0000_0104, 5'd1, 1'b1, WB_PC4);
            drive("JAL", e, 32'h3333_4444, 1'b0);
            chk4("we", mem_we, 4'b0000);
            capture();
            chk_minstr(1'b1, 32'h0000_0200, 32'h0000_0104, 5'd1, 1'b1, WB_PC4);
        end

        // Invalid store must not write memory.
        begin
            einstr_t e;
            e = mk_einstr(1'b0, SW, 1'b1, 32'h0000_1000, 32'hDEAD_BEEF,
                          32'h0, 5'd0, 1'b0, WB_ALU);
            drive("INVALID", e, 32'hAAAA_5555, 1'b0);
            chk4 ("we",    mem_we,    4'b0000);
            chk32("wdata", mem_wdata, 32'h0);
            capture();
            chk1("m.valid", minstr.valid, 1'b0);
        end

        // Stores: byte enables and shifted write data.
        check_store("SB0", SB, 32'h0000_1000, 32'h0000_00A5, 4'b0001, 32'h0000_00A5);
        check_store("SB1", SB, 32'h0000_1001, 32'h0000_00A5, 4'b0010, 32'h0000_A500);
        check_store("SB2", SB, 32'h0000_1002, 32'h0000_00A5, 4'b0100, 32'h00A5_0000);
        check_store("SB3", SB, 32'h0000_1003, 32'h0000_00A5, 4'b1000, 32'hA500_0000);
        check_store("SH0", SH, 32'h0000_2000, 32'h0000_BEEF, 4'b0011, 32'h0000_BEEF);
        check_store("SH2", SH, 32'h0000_2002, 32'h0000_BEEF, 4'b1100, 32'hBEEF_0000);
        check_store("SW",  SW, 32'h0000_3000, 32'h89AB_CDEF, 4'b1111, 32'h89AB_CDEF);

        // Loads: extraction and sign/zero extension.
        check_load("LB0",  LB,  32'h0000_4000, 32'h807F_FF01, 32'h0000_0001);
        check_load("LB1",  LB,  32'h0000_4001, 32'h807F_FF01, 32'hFFFF_FFFF);
        check_load("LB2",  LB,  32'h0000_4002, 32'h807F_FF01, 32'h0000_007F);
        check_load("LB3",  LB,  32'h0000_4003, 32'h807F_FF01, 32'hFFFF_FF80);
        check_load("LBU3", LBU, 32'h0000_4003, 32'h807F_FF01, 32'h0000_0080);
        check_load("LH0",  LH,  32'h0000_5000, 32'h8001_7FFF, 32'h0000_7FFF);
        check_load("LH2",  LH,  32'h0000_5002, 32'h8001_7FFF, 32'hFFFF_8001);
        check_load("LHU2", LHU, 32'h0000_5002, 32'h8001_7FFF, 32'h0000_8001);
        check_load("LW",   LW,  32'h0000_6000, 32'hDEAD_BEEF, 32'hDEAD_BEEF);

        // Stall holds registered metadata and the last non-stalled read data.
        begin
            einstr_t held;
            einstr_t blocked;
            held = mk_einstr(1'b1, ADD, 1'b0, 32'h0000_7000, 32'h0,
                             32'h0000_7004, 5'd7, 1'b1, WB_ALU);
            drive("STALL_pre", held, 32'h1234_5678, 1'b0);
            capture();
            chk_minstr(1'b1, 32'h0000_7000, 32'h0000_7004, 5'd7, 1'b1, WB_ALU);

            blocked = mk_einstr(1'b1, ADD, 1'b0, 32'h0000_8000, 32'h0,
                                32'h0000_8004, 5'd8, 1'b1, WB_ALU);
            // The memory answers minstr one cycle after the request: this is
            // the data for the instruction now held in W.
            drive("STALL", blocked, 32'h8765_4321, 1'b1);
            chk32("rdata", mem_rdata_o, 32'h8765_4321);
            capture();
            chk_minstr(1'b1, 32'h0000_7000, 32'h0000_7004, 5'd7, 1'b1, WB_ALU);
            chk32("held_rdata", mem_rdata_o, 32'h8765_4321);

            // The bus moves on to the blocked request; W keeps the held data
            drive("STALL_2", blocked, 32'hAAAA_5555, 1'b1);
            chk32("held_rdata", mem_rdata_o, 32'h8765_4321);
            capture();

            // W retires in the release cycle, still with the held data
            drive("STALL_rel", blocked, 32'hAAAA_5555, 1'b0);
            chk32("held_rdata", mem_rdata_o, 32'h8765_4321);
            capture();
            chk_minstr(1'b1, 32'h0000_8000, 32'h0000_8004, 5'd8, 1'b1, WB_ALU);
            chk32("next_rdata", mem_rdata_o, 32'hAAAA_5555);
        end

        $display("----------------------------------------------------------");
        if (errors == 0)
            $display("  PASS  all %0d checks passed", tests);
        else
            $display("  DONE  %0d/%0d checks FAILED", errors, tests);
        $display("----------------------------------------------------------");
        $finish;
    end

    initial begin
        #100000;
        $display("  [TIMEOUT] testbench hung");
        $finish;
    end
endmodule
