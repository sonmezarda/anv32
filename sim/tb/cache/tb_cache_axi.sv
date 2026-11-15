// AXI path testbench: anv32_dcache and anv32_icache, each through
// anv32_cache_axi to an AXI3 memory model (axi3_mem) that takes AR, AW and W
// independently and after random delays, answers in order, and checks the
// protocol and that no read overtakes an unanswered write.
//   - Data runs issue loads and stores of every width; loads are checked
//     against a reference memory in program order. Now and then, with the
//     cache drained, the PS writes words behind the cache's back and the
//     cache is invalidated. At the end the cache is invalidated and every
//     word ever written is read back through AXI, so a store that never
//     reached memory shows up even if the cache had hidden it.
//   - Instruction runs fetch along straight runs, short jumps, same-index
//     jumps and anywhere, with PS writes and invalidates as well.
// The adapters add a non-zero address offset in most runs.
`timescale 1ns/1ps

// The memory model's contents for a word never written (see axi3_mem)
function automatic logic [31:0] axi3_mem_init_word(int unsigned waddr, logic [31:0] seed);
    logic [31:0] x = waddr ^ seed;
    x = x * 32'h9E37_79B1;
    return x ^ (x >> 15);
endfunction

function automatic logic [31:0] tb_next_rng(logic [31:0] s);
    s ^= s << 13;
    s ^= s >> 17;
    s ^= s << 5;
    return s;
endfunction

// ---------------------------------------------------------------------------
module tb_dcache_axi_run #(
    parameter int unsigned SIZE_BYTES = 8192,
    parameter int unsigned LINE_BYTES = 32,
    parameter int unsigned MEM_DW     = 64,
    parameter int unsigned WBUF_DEPTH = 4,
    parameter logic [31:0] OFFSET     = 32'h0,
    parameter logic [31:0] SEED       = 32'h1D0F_2B4A,
    parameter int unsigned REQUESTS   = 20000,
    parameter string       NAME       = "run"
)(
    input  logic        clk,
    input  logic        rst,
    output logic        done,
    output int unsigned checks,
    output int unsigned errors
);
    localparam int unsigned BEATS   = LINE_BYTES * 8 / MEM_DW;
    localparam int unsigned STRB_W  = MEM_DW / 8;
    localparam int unsigned HOT     = SIZE_BYTES * 4;
    localparam int unsigned TAG_LSB = $clog2(SIZE_BYTES / 2);
    localparam logic [31:0] BASE    = 32'h8000_0000;

    logic              invalidate, drained;
    logic              req_valid, req_ready;
    logic [31:0]       req_addr, req_wdata, rdata;
    logic [3:0]        req_we;
    logic              rd_valid, rd_ready, rvalid;
    logic [31:0]       rd_addr;
    logic [MEM_DW-1:0] rbeat;
    logic              wr_valid, wr_ready, wr_done;
    logic [31:0]       wr_addr;
    logic [MEM_DW-1:0] wr_data;
    logic [STRB_W-1:0] wr_strb;

    anv32_dcache #(
        .SIZE_BYTES(SIZE_BYTES), .LINE_BYTES(LINE_BYTES), .MEM_DW(MEM_DW), .WBUF_DEPTH(WBUF_DEPTH)
    ) dcache (
        .clk_i(clk), .rst_i(rst), .invalidate_i(invalidate), .drained_o(drained),
        .req_valid_i(req_valid), .req_addr_i(req_addr), .req_wdata_i(req_wdata), .req_we_i(req_we),
        .req_ready_o(req_ready), .rdata_o(rdata),
        .mem_rd_valid_o(rd_valid), .mem_rd_ready_i(rd_ready), .mem_rd_addr_o(rd_addr),
        .mem_rvalid_i(rvalid), .mem_rdata_i(rbeat),
        .mem_wr_valid_o(wr_valid), .mem_wr_ready_i(wr_ready), .mem_wr_addr_o(wr_addr),
        .mem_wr_data_o(wr_data), .mem_wr_strb_o(wr_strb), .mem_wr_done_i(wr_done)
    );

    // ---- AXI ---------------------------------------------------------------
    logic [5:0]        arid, rid, awid, wid, bid;
    logic [31:0]       araddr, awaddr;
    logic [3:0]        arlen, awlen, arcache, awcache, arqos, awqos;
    logic [2:0]        arsize, awsize, arprot, awprot;
    logic [1:0]        arburst, awburst, arlock, awlock, rresp, bresp;
    logic              arvalid, arready, rlast, rvalid_axi, rready, awvalid, awready;
    logic              wlast, wvalid, wready, bvalid, bready;
    logic [MEM_DW-1:0] rdata_axi, wdata;
    logic [STRB_W-1:0] wstrb;
    logic              poke_valid;
    logic [31:0]       poke_addr, poke_data;
    int unsigned       pending_writes, mem_errors;

    anv32_cache_axi #(.MEM_DW(MEM_DW), .BEATS(BEATS), .ID(6'h11), .HAS_WRITE(1'b1)) axi (
        .clk_i(clk), .rst_i(rst), .addr_offset_i(OFFSET),
        .rd_valid_i(rd_valid), .rd_ready_o(rd_ready), .rd_addr_i(rd_addr),
        .rvalid_o(rvalid), .rdata_o(rbeat),
        .wr_valid_i(wr_valid), .wr_ready_o(wr_ready), .wr_addr_i(wr_addr),
        .wr_data_i(wr_data), .wr_strb_i(wr_strb), .wr_done_o(wr_done),
        .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
        .m_axi_arburst(arburst), .m_axi_arlock(arlock), .m_axi_arcache(arcache), .m_axi_arprot(arprot),
        .m_axi_arqos(arqos), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rid(rid), .m_axi_rdata(rdata_axi), .m_axi_rresp(rresp), .m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid_axi), .m_axi_rready(rready),
        .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
        .m_axi_awburst(awburst), .m_axi_awlock(awlock), .m_axi_awcache(awcache), .m_axi_awprot(awprot),
        .m_axi_awqos(awqos), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wid(wid), .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bid(bid), .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready)
    );

    axi3_mem #(.DW(MEM_DW), .SEED(SEED), .NAME(NAME)) ddr (
        .clk, .rst,
        .s_axi_arid(arid), .s_axi_araddr(araddr), .s_axi_arlen(arlen), .s_axi_arsize(arsize),
        .s_axi_arburst(arburst), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rid(rid), .s_axi_rdata(rdata_axi), .s_axi_rresp(rresp), .s_axi_rlast(rlast),
        .s_axi_rvalid(rvalid_axi), .s_axi_rready(rready),
        .s_axi_awid(awid), .s_axi_awaddr(awaddr), .s_axi_awlen(awlen), .s_axi_awsize(awsize),
        .s_axi_awburst(awburst), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wid(wid), .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wlast(wlast),
        .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bid(bid), .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .poke_valid, .poke_addr, .poke_data, .pending_writes, .errors(mem_errors)
    );

    // ---- Reference ---------------------------------------------------------
    logic [31:0] ref_mem [int unsigned];      // by core word address
    logic [31:0] written[$];                  // core addresses ever written

    function automatic logic [31:0] ref_word(logic [31:0] addr);
        int unsigned w = addr >> 2;
        return ref_mem.exists(w) ? ref_mem[w] : axi3_mem_init_word((addr + OFFSET) >> 2, SEED);
    endfunction

    function automatic logic [31:0] merge(logic [31:0] old, logic [31:0] data, logic [3:0] mask);
        for (int b = 0; b < 4; b++) if (mask[b]) old[b*8 +: 8] = data[b*8 +: 8];
        return old;
    endfunction

    function automatic void report(string what);
        $display("  [FAIL] %s (dcache %0dB/%0dB/%0db): %s", NAME, SIZE_BYTES, LINE_BYTES, MEM_DW, what);
    endfunction

    // ---- Core model --------------------------------------------------------
    typedef enum logic [1:0] {RUN, PS, READBACK, DONE} phase_t;

    phase_t      phase = RUN;
    logic [31:0] rng = SEED ^ 32'h5A5A_0F0F;
    logic [31:0] ptr;
    logic        load_q = 1'b0;
    logic [31:0] load_addr_q, load_expect_q;
    int unsigned accepted = 0, ps_left = 0, readback_idx = 0;
    int unsigned stores = 0, invalidates = 0, tb_errors = 0;

    assign errors = tb_errors + mem_errors;
    assign done   = phase == DONE;

    always_ff @(posedge clk) begin
        automatic int          bad = 0;
        automatic logic [31:0] next, a;
        automatic int unsigned size;
        automatic logic        store;

        rng        <= tb_next_rng(rng);
        invalidate <= 1'b0;
        poke_valid <= 1'b0;

        if (rst) begin
            req_valid <= 1'b0;
            req_we    <= '0;
            ptr       <= BASE;
            load_q    <= 1'b0;
        end else begin
            if (load_q) begin
                checks++;
                if (rdata !== load_expect_q) begin
                    if (tb_errors + bad < 10)
                        report($sformatf("load %08x: got %08x, expected %08x", load_addr_q, rdata, load_expect_q));
                    bad++;
                end
            end
            load_q        <= req_valid && req_ready && req_we == 0;
            load_addr_q   <= req_addr;
            load_expect_q <= ref_word(req_addr);

            if (req_valid && req_ready && req_we != 0) begin
                ref_mem[req_addr >> 2] = merge(ref_word(req_addr), req_wdata, req_we);
                written.push_back(req_addr & ~32'h3);
                stores <= stores + 1;
            end
            if (req_valid && req_ready) accepted <= accepted + 1;

            unique case (phase)
                RUN: if (!req_valid || req_ready) begin
                    size  = rng[25:24] == 2'd3 ? 2 : int'(rng[25:24]);
                    store = rng[27:26] == 2'b01 || rng[27:26] == 2'b10;
                    unique casez (rng[31:28])
                        4'b00??, 4'b010?:          next = ptr + 32'(1 << size);
                        4'b0110, 4'b0111, 4'b100?: next = BASE + (rng & 32'(HOT - 1));
                        4'b1010: next = ptr ^ (32'h1 << (TAG_LSB + rng[4:0] % (32 - TAG_LSB)));
                        4'b1011: next = BASE + (rng & 32'h0FFF_FFFF);
                        default: next = ptr;
                    endcase
                    a = next & ~32'((1 << size) - 1);
                    if (accepted + int'(req_valid) >= REQUESTS) begin
                        req_valid <= 1'b0;
                        phase     <= READBACK;
                    end else if (rng[31:28] == 4'b1101 && drained && !req_valid) begin
                        req_valid <= 1'b0;              // the PS writes 16 words, then invalidate
                        ps_left   <= 16;
                        phase     <= PS;
                    end else if (rng[31:28] >= 4'b1100) begin
                        req_valid <= 1'b0;              // idle
                    end else begin
                        req_valid <= 1'b1;
                        req_addr  <= a;
                        req_we    <= store ? 4'((1 << (1 << size)) - 1) << a[1:0] : 4'b0;
                        req_wdata <= tb_next_rng(rng ^ 32'hC3C3_3C3C);
                        ptr       <= a;
                    end
                end
                PS: begin
                    if (ps_left != 0) begin
                        a = BASE + ((rng & 32'(HOT - 1)) & ~32'h3);
                        poke_valid <= 1'b1;
                        poke_addr  <= a + OFFSET;
                        poke_data  <= tb_next_rng(rng);
                        ref_mem[a >> 2] = tb_next_rng(rng);
                        written.push_back(a);
                        ps_left <= ps_left - 1;
                    end else begin
                        invalidate  <= 1'b1;            // no request goes out with it
                        invalidates <= invalidates + 1;
                        phase       <= RUN;
                    end
                end
                READBACK: if (!req_valid || req_ready) begin
                    if (readback_idx == 0 && !req_valid && !invalidate) begin
                        invalidate <= drained;          // drop every line, then read all back
                        if (drained) readback_idx <= 1;
                    end else if (readback_idx > 0 && readback_idx <= written.size()) begin
                        req_valid    <= 1'b1;
                        req_we       <= 4'b0;
                        req_addr     <= written[readback_idx - 1];
                        readback_idx <= readback_idx + 1;
                    end else if (readback_idx > written.size()) begin
                        req_valid <= 1'b0;
                        if (!load_q && !(req_valid && req_ready)) phase <= DONE;
                    end
                end
                DONE: req_valid <= 1'b0;
                default: ;
            endcase
        end
        tb_errors <= tb_errors + bad;
    end

    final $display("  dcache %0d B, %0d B lines, %0d-bit, offset %08x: %0d requests, %0d stores, %0d invalidates, %0d words read back (with repeats)",
                   SIZE_BYTES, LINE_BYTES, MEM_DW, OFFSET, accepted, stores, invalidates, written.size());
endmodule

// ---------------------------------------------------------------------------
module tb_icache_axi_run #(
    parameter int unsigned SIZE_BYTES = 8192,
    parameter int unsigned LINE_BYTES = 64,
    parameter int unsigned MEM_DW     = 64,
    parameter bit          SYNC_TAGS  = 1'b0,
    parameter logic [31:0] OFFSET     = 32'h0,
    parameter logic [31:0] SEED       = 32'h3C77_4E91,
    parameter int unsigned REQUESTS   = 20000,
    parameter string       NAME       = "run"
)(
    input  logic        clk,
    input  logic        rst,
    output logic        done,
    output int unsigned checks,
    output int unsigned errors
);
    localparam int unsigned BEATS   = LINE_BYTES * 8 / MEM_DW;
    localparam int unsigned TAG_LSB = $clog2(SIZE_BYTES);
    localparam logic [31:0] BASE    = 32'h8000_0000;

    logic              invalidate;
    logic              req_valid, req_ready;
    logic [31:0]       req_addr, rdata;
    logic              rd_valid, rd_ready, rvalid;
    logic [31:0]       rd_addr;
    logic [MEM_DW-1:0] rbeat;

    anv32_icache #(.SIZE_BYTES(SIZE_BYTES), .LINE_BYTES(LINE_BYTES), .MEM_DW(MEM_DW), .SYNC_TAGS(SYNC_TAGS)) icache (
        .clk_i(clk), .rst_i(rst), .invalidate_i(invalidate),
        .req_valid_i(req_valid), .req_addr_i(req_addr), .req_ready_o(req_ready), .rdata_o(rdata),
        .mem_req_valid_o(rd_valid), .mem_req_ready_i(rd_ready), .mem_req_addr_o(rd_addr),
        .mem_rvalid_i(rvalid), .mem_rdata_i(rbeat)
    );

    logic [5:0]        arid, rid, awid, wid, bid;
    logic [31:0]       araddr, awaddr;
    logic [3:0]        arlen, awlen, arcache, awcache, arqos, awqos;
    logic [2:0]        arsize, awsize, arprot, awprot;
    logic [1:0]        arburst, awburst, arlock, awlock, rresp, bresp;
    logic              arvalid, arready, rlast, rvalid_axi, rready, awvalid, awready;
    logic              wlast, wvalid, wready, bvalid, bready;
    logic [MEM_DW-1:0] rdata_axi, wdata;
    logic [MEM_DW/8-1:0] wstrb;
    logic              poke_valid;
    logic [31:0]       poke_addr, poke_data;
    int unsigned       pending_writes, mem_errors;

    anv32_cache_axi #(.MEM_DW(MEM_DW), .BEATS(BEATS), .ID(6'h22), .HAS_WRITE(1'b0)) axi (
        .clk_i(clk), .rst_i(rst), .addr_offset_i(OFFSET),
        .rd_valid_i(rd_valid), .rd_ready_o(rd_ready), .rd_addr_i(rd_addr),
        .rvalid_o(rvalid), .rdata_o(rbeat),
        .wr_valid_i(1'b0), .wr_ready_o(), .wr_addr_i('0), .wr_data_i('0), .wr_strb_i('0), .wr_done_o(),
        .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
        .m_axi_arburst(arburst), .m_axi_arlock(arlock), .m_axi_arcache(arcache), .m_axi_arprot(arprot),
        .m_axi_arqos(arqos), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rid(rid), .m_axi_rdata(rdata_axi), .m_axi_rresp(rresp), .m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid_axi), .m_axi_rready(rready),
        .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
        .m_axi_awburst(awburst), .m_axi_awlock(awlock), .m_axi_awcache(awcache), .m_axi_awprot(awprot),
        .m_axi_awqos(awqos), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wid(wid), .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bid(bid), .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready)
    );

    axi3_mem #(.DW(MEM_DW), .SEED(SEED), .NAME(NAME)) ddr (
        .clk, .rst,
        .s_axi_arid(arid), .s_axi_araddr(araddr), .s_axi_arlen(arlen), .s_axi_arsize(arsize),
        .s_axi_arburst(arburst), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rid(rid), .s_axi_rdata(rdata_axi), .s_axi_rresp(rresp), .s_axi_rlast(rlast),
        .s_axi_rvalid(rvalid_axi), .s_axi_rready(rready),
        .s_axi_awid(awid), .s_axi_awaddr(awaddr), .s_axi_awlen(awlen), .s_axi_awsize(awsize),
        .s_axi_awburst(awburst), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wid(wid), .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wlast(wlast),
        .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bid(bid), .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .poke_valid, .poke_addr, .poke_data, .pending_writes, .errors(mem_errors)
    );

    logic [31:0] ref_mem [int unsigned];

    function automatic logic [31:0] ref_word(logic [31:0] addr);
        int unsigned w = addr >> 2;
        return ref_mem.exists(w) ? ref_mem[w] : axi3_mem_init_word((addr + OFFSET) >> 2, SEED);
    endfunction

    function automatic void report(string what);
        $display("  [FAIL] %s (icache %0dB/%0dB/%0db): %s", NAME, SIZE_BYTES, LINE_BYTES, MEM_DW, what);
    endfunction

    typedef enum logic [1:0] {RUN, PS, DONE} phase_t;

    phase_t      phase = RUN;
    logic [31:0] rng = SEED ^ 32'h0F0F_A5A5;
    logic [31:0] pc;
    logic        fetch_q = 1'b0;
    logic [31:0] fetch_addr_q, fetch_expect_q;
    int unsigned accepted = 0, ps_left = 0, invalidates = 0, tb_errors = 0;

    assign errors = tb_errors + mem_errors;
    assign done   = phase == DONE;

    always_ff @(posedge clk) begin
        automatic int          bad = 0;
        automatic logic [31:0] next, a;

        rng        <= tb_next_rng(rng);
        invalidate <= 1'b0;
        poke_valid <= 1'b0;

        if (rst) begin
            req_valid <= 1'b0;
            pc        <= BASE;
            fetch_q   <= 1'b0;
        end else begin
            if (fetch_q) begin
                checks++;
                if (rdata !== fetch_expect_q) begin
                    if (tb_errors + bad < 10)
                        report($sformatf("fetch %08x: got %08x, expected %08x", fetch_addr_q, rdata, fetch_expect_q));
                    bad++;
                end
            end
            fetch_q        <= req_valid && req_ready;
            fetch_addr_q   <= req_addr;
            fetch_expect_q <= ref_word(req_addr);
            if (req_valid && req_ready) accepted <= accepted + 1;

            unique case (phase)
                RUN: if (!req_valid || req_ready) begin
                    unique casez (rng[31:28])
                        4'b00??, 4'b01??: next = pc + 4;
                        4'b100?:          next = pc - 32'(rng[8:4] * 4) + 32'(rng[9] * 64);
                        4'b1010:          next = pc ^ (32'h1 << (TAG_LSB + rng[4:0] % (32 - TAG_LSB)));
                        4'b1011:          next = BASE + (rng & 32'h0FFF_FFFC);
                        default:          next = pc;
                    endcase
                    a = next & ~32'h3;
                    if (accepted + int'(req_valid) >= REQUESTS) begin
                        req_valid <= 1'b0;
                        if (!fetch_q) phase <= DONE;
                    end else if (rng[31:28] == 4'b1101 && !req_valid) begin
                        ps_left <= 16;                  // the PS loads new code
                        phase   <= PS;
                    end else if (rng[31:28] >= 4'b1100) begin
                        req_valid <= 1'b0;
                    end else begin
                        req_valid <= 1'b1;
                        req_addr  <= a;
                        pc        <= a;
                    end
                end
                PS: begin
                    if (ps_left != 0) begin
                        a = (pc & ~32'h3FF) + ((rng & 32'h3FF) & ~32'h3);   // near the code running now
                        poke_valid <= 1'b1;
                        poke_addr  <= a + OFFSET;
                        poke_data  <= tb_next_rng(rng);
                        ref_mem[a >> 2] = tb_next_rng(rng);
                        ps_left <= ps_left - 1;
                    end else if (!fetch_q && !rd_valid) begin
                        invalidate  <= 1'b1;
                        invalidates <= invalidates + 1;
                        phase       <= RUN;
                    end
                end
                DONE: req_valid <= 1'b0;
                default: ;
            endcase
        end
        tb_errors <= tb_errors + bad;
    end

    final $display("  icache %0d B, %0d B lines, %0d-bit, %s tags, offset %08x: %0d fetches, %0d invalidates",
                   SIZE_BYTES, LINE_BYTES, MEM_DW, SYNC_TAGS ? "sync" : "async", OFFSET, accepted, invalidates);
endmodule

// ---------------------------------------------------------------------------
module tb_cache_axi;
    localparam int unsigned RUNS = 5;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    logic        done   [RUNS];
    int unsigned checks [RUNS];
    int unsigned errors [RUNS];

    tb_dcache_axi_run #(.SIZE_BYTES(8192), .LINE_BYTES(32), .MEM_DW(64), .WBUF_DEPTH(4),
                        .OFFSET(32'h1F00_0000), .SEED(32'h1D0F_2B4A), .NAME("d0"))
        d0 (.clk, .rst, .done(done[0]), .checks(checks[0]), .errors(errors[0]));
    tb_dcache_axi_run #(.SIZE_BYTES(1024), .LINE_BYTES(64), .MEM_DW(32), .WBUF_DEPTH(2),
                        .OFFSET(32'h0), .SEED(32'h3C77_4E91), .NAME("d1"))
        d1 (.clk, .rst, .done(done[1]), .checks(checks[1]), .errors(errors[1]));
    tb_dcache_axi_run #(.SIZE_BYTES(2048), .LINE_BYTES(128), .MEM_DW(64), .WBUF_DEPTH(8),
                        .OFFSET(32'h9000_0000), .SEED(32'h5A03_6B21), .NAME("d2"))
        d2 (.clk, .rst, .done(done[2]), .checks(checks[2]), .errors(errors[2]));
    tb_icache_axi_run #(.SIZE_BYTES(8192), .LINE_BYTES(64), .MEM_DW(64), .SYNC_TAGS(1'b0),
                        .OFFSET(32'h1F00_0000), .SEED(32'h7E15_9A0C), .NAME("i0"))
        i0 (.clk, .rst, .done(done[3]), .checks(checks[3]), .errors(errors[3]));
    tb_icache_axi_run #(.SIZE_BYTES(2048), .LINE_BYTES(32), .MEM_DW(32), .SYNC_TAGS(1'b1),
                        .OFFSET(32'h4000_0000), .SEED(32'h2468_ACE1), .NAME("i1"))
        i1 (.clk, .rst, .done(done[4]), .checks(checks[4]), .errors(errors[4]));

    initial begin
        int unsigned total_checks = 0;
        int unsigned total_errors = 0;
        bit          all_done;

        repeat (3) @(posedge clk);
        rst = 1'b0;

        for (int cycle = 0; cycle < 5_000_000; cycle++) begin
            @(posedge clk);
            all_done = 1'b1;
            foreach (done[i]) all_done &= done[i];
            if (all_done) break;
        end
        repeat (5) @(posedge clk);                  // let the last checks land

        foreach (done[i]) begin
            if (!done[i]) begin
                $display("  [FAIL] run %0d timed out", i);
                total_errors++;
            end
            total_checks += checks[i];
            total_errors += errors[i];
        end

        if (total_errors == 0) $display("  PASS  all %0d checks passed", total_checks);
        else                   $display("  DONE  %0d/%0d checks FAILED", total_errors, total_checks);
        $finish;
    end
endmodule
