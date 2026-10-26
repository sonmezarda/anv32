// Bus fabric testbench: the read-data register stage (anv32_bus_read_pipe),
// decoder, bridge and the register front end with its SET/CLR/XOR aliases.
// The read pipe sits in front of the decoder; three slaves sit behind it:
//   0  0x0000_0000/64 KiB  memory, fast (zero wait, data straight through)
//   1  0x1000_1000/4 KiB   anv32_bus_regs, slow (fast=0 -> registered, +1 wait)
//   2  0x1000_2000/4 KiB   bridge, then slow memory with random wait states
// Anything else is unmapped. Random reads and writes, with random byte
// enables and aliases, are checked against a model. The read pipe must keep
// read data correct, add exactly one wait to slow reads, and present each slow
// slave with a single valid pulse (checked via the register read strobes).
`timescale 1ns/1ps

module tb_bus
    import anv32_bus_pkg::*;
;
    localparam int unsigned NREGS = 4;
    localparam int unsigned WORDS = 16;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    bus_req_t       m_req;
    bus_rsp_t       m_rsp;
    bus_req_t       dec_req;
    bus_rsp_t       dec_rsp;
    bus_req_t [2:0] s_req;
    bus_rsp_t [2:0] s_rsp;

    logic           rd_hit;
    logic [1:0]     rd_sel;
    logic [31:0]    rdata_fast;
    logic [31:0]    rdata_slow;

    // Static fast/slow read-data split by slave class (slave 0 fast, 1/2 slow).
    always_comb begin
        rdata_fast = 32'b0;
        rdata_slow = 32'b0;
        if (rd_hit) begin
            for (int unsigned i = 0; i < 3; i++) begin
                if (rd_sel == i[1:0]) begin
                    if (s_rsp[i].fast) rdata_fast = s_rsp[i].rdata;
                    else               rdata_slow = s_rsp[i].rdata;
                end
            end
        end
    end

    // Read-data register stage under test, in front of the decoder.
    anv32_bus_read_pipe dut_pipe (
        .clk_i       (clk),
        .rst_i       (rst),
        .m_req_i     (m_req),
        .m_rsp_o     (m_rsp),
        .s_req_o     (dec_req),
        .s_rsp_i     (dec_rsp),
        .rdata_fast_i(rdata_fast),
        .rdata_slow_i(rdata_slow)
    );

    anv32_bus_decoder #(
        .N   (3),
        .BASE({32'h1000_2000, 32'h1000_1000, 32'h0000_0000}),
        .MASK({32'hFFFF_F000, 32'hFFFF_F000, 32'hFFFF_0000})
    ) dut_dec (
        .clk_i   (clk),
        .rst_i   (rst),
        .m_req_i (dec_req),
        .m_rsp_o (dec_rsp),
        .s_req_o (s_req),
        .s_rsp_i (s_rsp),
        .rd_hit_o(rd_hit),
        .rd_sel_o(rd_sel)
    );

    // Slave 0: zero-wait memory
    logic [31:0] mem0 [WORDS];
    logic [31:0] mem0_rdata_q;

    always_ff @(posedge clk) begin
        if (s_req[0].valid) begin
            mem0_rdata_q <= mem0[s_req[0].addr[5:2]];
            for (int b = 0; b < 4; b++)
                if (s_req[0].we[b]) mem0[s_req[0].addr[5:2]][b*8 +: 8] <= s_req[0].wdata[b*8 +: 8];
        end
    end

    assign s_rsp[0] = '{ready: 1'b1, fast: 1'b1, rdata: mem0_rdata_q};

    // Slave 1: register block
    logic [NREGS-1:0][31:0] regs_q;
    logic [NREGS-1:0]       regs_wr;
    logic [NREGS-1:0]       regs_rd;
    logic [31:0]            regs_wdata;
    int unsigned            rd_strobes = 0;

    anv32_bus_regs #(.NREGS(NREGS)) dut_regs (
        .clk_i  (clk),
        .rst_i  (rst),
        .req_i  (s_req[1]),
        .rsp_o  (s_rsp[1]),
        .rdata_i(regs_q),
        .wr_o   (regs_wr),
        .rd_o   (regs_rd),
        .wdata_o(regs_wdata)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            regs_q <= '0;
        end else begin
            for (int i = 0; i < NREGS; i++)
                if (regs_wr[i]) regs_q[i] <= regs_wdata;
        end
        if (regs_rd != '0) rd_strobes <= rd_strobes + 1;
    end

    // Slave 2: bridge, then memory that is ready only when slow_ready is set
    bus_req_t    br_req;
    bus_rsp_t    br_rsp;
    logic        rand_wait = 1'b0;
    logic        slow_ready;
    logic [15:0] lfsr = 16'h1;
    logic [31:0] mem2 [WORDS];
    logic [31:0] mem2_rdata_q;

    anv32_bus_bridge dut_bridge (
        .clk_i  (clk),
        .rst_i  (rst),
        .m_req_i(s_req[2]),
        .m_rsp_o(s_rsp[2]),
        .s_req_o(br_req),
        .s_rsp_i(br_rsp)
    );

    always_ff @(posedge clk) lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    assign slow_ready = !rand_wait || lfsr[0];

    always_ff @(posedge clk) begin
        if (br_req.valid && slow_ready) begin
            mem2_rdata_q <= mem2[br_req.addr[5:2]];
            for (int b = 0; b < 4; b++)
                if (br_req.we[b]) mem2[br_req.addr[5:2]][b*8 +: 8] <= br_req.wdata[b*8 +: 8];
        end
    end

    assign br_rsp = '{ready: slow_ready, fast: 1'b0, rdata: mem2_rdata_q};

    // Model
    logic [31:0] model0 [WORDS];
    logic [31:0] model2 [WORDS];
    logic [31:0] model_regs [NREGS];

    int unsigned tests  = 0;
    int unsigned errors = 0;
    int unsigned reg_reads = 0;

    task automatic chk32(string nm, logic [31:0] got, logic [31:0] exp);
        tests++;
        if (got !== exp) begin
            errors++;
            if (errors <= 10) $display("  [FAIL] %-24s got=%08h exp=%08h", nm, got, exp);
        end
    endtask

    function automatic logic [31:0] merge(logic [31:0] old, logic [31:0] val, logic [3:0] we);
        logic [31:0] r;
        for (int b = 0; b < 4; b++) r[b*8 +: 8] = we[b] ? val[b*8 +: 8] : old[b*8 +: 8];
        return r;
    endfunction

    // One access: drive at the falling edge, wait for ready, transfer on the
    // rising edge, then check the read data the cycle after. Returns the
    // number of cycles the request was held before it was accepted.
    task automatic access(input logic [31:0] addr, input logic [31:0] wdata,
                          input logic [3:0] we, output logic [31:0] rdata,
                          output int unsigned waits);
        @(negedge clk);
        m_req = '{valid: 1'b1, addr: addr, wdata: wdata, we: we};
        waits = 0;
        #1;
        while (!m_rsp.ready) begin
            @(negedge clk);
            waits++;
            #1;
        end
        @(negedge clk);
        m_req = '{valid: 1'b0, addr: 32'hDEAD_BEE0, wdata: 32'h0, we: 4'h0};
        #1;
        rdata = m_rsp.rdata;
    endtask

    // Applies an access to the model and returns the expected read data
    function automatic logic [31:0] model_access(logic [31:0] addr, logic [31:0] wdata, logic [3:0] we);
        logic [31:0] exp;
        int unsigned idx;
        logic [31:0] cur;
        logic [31:0] next;
        int unsigned w;

        w = int'(addr[5:2]);
        exp = 32'h0;
        if (addr[31:16] == 16'h0000) begin
            exp = model0[w];
            model0[w] = merge(model0[w], wdata, we);
        end else if (addr[31:12] == 20'h1000_2) begin
            exp = model2[w];
            model2[w] = merge(model2[w], wdata, we);
        end else if (addr[31:12] == 20'h1000_1) begin
            idx = int'(addr[9:2]);
            if (idx < NREGS) begin
                cur = model_regs[idx];
                exp = cur;
                unique case (addr[11:10])
                    2'd0: next = wdata;
                    2'd1: next = cur ^ wdata;
                    2'd2: next = cur | wdata;
                    2'd3: next = cur & ~wdata;
                endcase
                model_regs[idx] = merge(cur, next, we);
            end
        end
        return exp;
    endfunction

    function automatic logic [31:0] rand_addr();
        unique case ($urandom_range(0, 3))
            0: return 32'h0000_0000 | ($urandom_range(0, WORDS - 1) << 2);
            1: return 32'h1000_1000 | ($urandom_range(0, 3) << 10) | ($urandom_range(0, NREGS + 1) << 2);
            2: return 32'h1000_2000 | ($urandom_range(0, WORDS - 1) << 2);
            default: return 32'h5000_0000 | ($urandom_range(0, WORDS - 1) << 2);
        endcase
    endfunction

    initial begin
        logic [31:0] rdata;
        logic [31:0] exp;
        int unsigned waits;

        for (int w = 0; w < WORDS; w++) begin
            mem0[w] = $urandom; model0[w] = mem0[w];
            mem2[w] = $urandom; model2[w] = mem2[w];
        end
        for (int i = 0; i < NREGS; i++) model_regs[i] = 32'h0;
        m_req = '0;
        repeat (3) @(posedge clk);
        rst = 1'b0;

        $display("tb_bus: decoder, bridge, register aliases");

        // Directed: wait states seen by the master
        access(32'h0000_0000, 32'h0, 4'h0, rdata, waits);
        chk32("fast slave waits", 32'(waits), 32'd0);        // fast: no wait
        access(32'h1000_1000, 32'h0, 4'h0, rdata, waits);
        chk32("regs slave waits", 32'(waits), 32'd1);        // slow: read pipe +1
        access(32'h1000_2000, 32'h0, 4'h0, rdata, waits);
        chk32("bridge waits", 32'(waits), 32'd2);            // bridge +1, read pipe +1
        access(32'h5000_0000, 32'h0, 4'h0, rdata, waits);
        chk32("unmapped waits", 32'(waits), 32'd0);
        chk32("unmapped rdata", rdata, 32'h0);

        // Directed: aliases on register 1
        access(32'h1000_1004, 32'h0000_00F0, 4'hF, rdata, waits);   // = F0
        access(32'h1000_1804, 32'h0000_000F, 4'hF, rdata, waits);   // SET -> FF
        access(32'h1000_1C04, 32'h0000_0081, 4'hF, rdata, waits);   // CLR -> 7E
        access(32'h1000_1404, 32'h0000_0003, 4'hF, rdata, waits);   // XOR -> 7D
        access(32'h1000_1004, 32'h0, 4'h0, rdata, waits);
        chk32("alias SET/CLR/XOR", rdata, 32'h0000_007D);
        access(32'h1000_1C04, 32'h0, 4'h0, rdata, waits);
        chk32("read through CLR alias", rdata, 32'h0000_007D);
        access(32'h1000_1804, 32'hFFFF_FFFF, 4'b0100, rdata, waits); // SET, byte 2 only
        access(32'h1000_1004, 32'h0, 4'h0, rdata, waits);
        chk32("alias with byte enable", rdata, 32'h00FF_007D);
        access(32'h1000_1040, 32'h1234_5678, 4'hF, rdata, waits);    // past NREGS
        access(32'h1000_1040, 32'h0, 4'h0, rdata, waits);
        chk32("register past NREGS", rdata, 32'h0);
        model_regs[1] = 32'h00FF_007D;
        reg_reads = 4;

        // Random traffic with wait states behind the bridge
        rand_wait = 1'b1;
        for (int n = 0; n < 4000; n++) begin
            logic [31:0] addr;
            logic [31:0] wdata;
            logic [3:0]  we;

            addr  = rand_addr();
            wdata = $urandom;
            we    = ($urandom_range(0, 1) == 0) ? 4'h0 : 4'($urandom_range(1, 15));
            exp   = model_access(addr, wdata, we);
            if (we == 4'h0 && addr[31:12] == 20'h1000_1 && 32'(addr[9:2]) < NREGS) reg_reads++;
            access(addr, wdata, we, rdata, waits);
            if (we == 4'h0) chk32($sformatf("read %08h", addr), rdata, exp);
        end

        for (int i = 0; i < NREGS; i++) chk32($sformatf("final reg %0d", i), regs_q[i], model_regs[i]);
        chk32("read strobes", 32'(rd_strobes), 32'(reg_reads));

        $display("----------------------------------------------------------");
        if (errors == 0) begin
            $display("  PASS  all %0d checks passed", tests);
        end else begin
            $display("  DONE  %0d/%0d checks FAILED", errors, tests);
            $fatal(1, "tb_bus failed");
        end
        $display("----------------------------------------------------------");
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "tb_bus: testbench hung");
    end
endmodule
