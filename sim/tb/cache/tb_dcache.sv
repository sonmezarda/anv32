// Data cache testbench (anv32_dcache). Several cache geometries run side by
// side, each with its own core model and memory model:
//   - The core model issues loads and stores of every width, one at a time,
//     like the memory stage: a request that is not accepted stays unchanged,
//     and a new one may follow right after an accepted one. Addresses mix
//     straight runs, a hot window four times the cache size, accesses to the
//     same set with another tag, and accesses anywhere.
//   - The memory model answers line fills with random delays and gaps, takes
//     writes with random delays and answers them in order. A write only lands
//     in memory when it is answered, so a fill that overtakes a buffered or
//     unanswered store reads stale data.
//   - Now and then, with the cache drained and idle, words in the hot window
//     change behind the cache's back and invalidate_i drops every line, as
//     when the PS writes DDR.
// Every load is checked against a reference memory in program order, every
// fill and write request against the bus rules, a store against being
// accepted at once while the write buffer has room, a repeated load against
// hitting without a wait state, and drained_o against the writes in flight.
// After the last request the cache drains and memory must equal the
// reference.
`timescale 1ns/1ps

module tb_dcache_run #(
    parameter int unsigned SIZE_BYTES = 8192,
    parameter int unsigned LINE_BYTES = 32,
    parameter int unsigned MEM_DW     = 64,
    parameter int unsigned WBUF_DEPTH = 4,
    parameter int unsigned REQUESTS   = 20000,
    parameter logic [15:0] SEED       = 16'h1D0F
)(
    input  logic        clk,
    input  logic        rst,
    output logic        done,
    output int unsigned checks,
    output int unsigned errors
);
    localparam int unsigned BEATS   = LINE_BYTES * 8 / MEM_DW;
    localparam int unsigned STRB_W  = MEM_DW / 8;
    localparam int unsigned HOT     = SIZE_BYTES * 4;           // hot window size
    localparam int unsigned TAG_LSB = $clog2(SIZE_BYTES / 2);   // lowest tag bit (2 ways)
    localparam logic [31:0] BASE    = 32'h8000_0000;

    logic              invalidate;
    logic              drained;
    logic              req_valid;
    logic [31:0]       req_addr;
    logic [31:0]       req_wdata;
    logic [3:0]        req_we;
    logic              req_ready;
    logic [31:0]       rdata;
    logic              rd_valid, rd_ready;
    logic [31:0]       rd_addr;
    logic              rvalid;
    logic [MEM_DW-1:0] rbeat;
    logic              wr_valid, wr_ready;
    logic [31:0]       wr_addr;
    logic [MEM_DW-1:0] wr_data;
    logic [STRB_W-1:0] wr_strb;
    logic              wr_done;

    anv32_dcache #(
        .SIZE_BYTES(SIZE_BYTES),
        .LINE_BYTES(LINE_BYTES),
        .MEM_DW    (MEM_DW),
        .WBUF_DEPTH(WBUF_DEPTH)
    ) dut (
        .clk_i         (clk),
        .rst_i         (rst),
        .invalidate_i  (invalidate),
        .drained_o     (drained),
        .req_valid_i   (req_valid),
        .req_addr_i    (req_addr),
        .req_wdata_i   (req_wdata),
        .req_we_i      (req_we),
        .req_ready_o   (req_ready),
        .rdata_o       (rdata),
        .mem_rd_valid_o(rd_valid),
        .mem_rd_ready_i(rd_ready),
        .mem_rd_addr_o (rd_addr),
        .mem_rvalid_i  (rvalid),
        .mem_rdata_i   (rbeat),
        .mem_wr_valid_o(wr_valid),
        .mem_wr_ready_i(wr_ready),
        .mem_wr_addr_o (wr_addr),
        .mem_wr_data_o (wr_data),
        .mem_wr_strb_o (wr_strb),
        .mem_wr_done_i (wr_done)
    );

    // ---- Memories ----------------------------------------------------------
    // Sparse word arrays over the whole address space; a word never written
    // reads as a hash of its address. ref_mem follows the program order and
    // belongs to the core model, ddr_mem is what memory holds and belongs to
    // the memory model.
    logic [31:0] ref_mem [int unsigned];
    logic [31:0] ddr_mem [int unsigned];

    function automatic logic [31:0] init_word(int unsigned waddr);
        logic [31:0] x = waddr ^ {SEED, SEED};
        x = x * 32'h9E37_79B1;
        return x ^ (x >> 15);
    endfunction

    function automatic logic [31:0] ref_word(logic [31:0] addr);
        int unsigned w = addr >> 2;
        return ref_mem.exists(w) ? ref_mem[w] : init_word(w);
    endfunction

    function automatic logic [31:0] ddr_word(logic [31:0] addr);
        int unsigned w = addr >> 2;
        return ddr_mem.exists(w) ? ddr_mem[w] : init_word(w);
    endfunction

    function automatic logic [MEM_DW-1:0] ddr_beat(logic [31:0] addr);
        logic [MEM_DW-1:0] b;
        for (int i = 0; i < MEM_DW / 32; i++) b[i*32 +: 32] = ddr_word(addr + 32'(4 * i));
        return b;
    endfunction

    function automatic logic [31:0] merge(logic [31:0] old, logic [31:0] data, logic [3:0] mask);
        for (int b = 0; b < 4; b++) if (mask[b]) old[b*8 +: 8] = data[b*8 +: 8];
        return old;
    endfunction

    // ---- Random source -----------------------------------------------------
    logic [31:0] rng = {SEED, ~SEED};

    function automatic logic [31:0] next_rng(logic [31:0] s);
        s ^= s << 13;
        s ^= s >> 17;
        s ^= s << 5;
        return s;
    endfunction

    always_ff @(posedge clk) rng <= next_rng(rng);

    function automatic void report(string what);
        $display("  [FAIL] %0dB/%0dB/%0db/wb%0d: %s", SIZE_BYTES, LINE_BYTES, MEM_DW, WBUF_DEPTH, what);
    endfunction

    // Each process counts its own failures
    int unsigned err_mem = 0, err_core = 0, err_end = 0;
    assign errors = err_mem + err_core + err_end;

    // The PS writes DDR now and then: with the cache drained and nothing in
    // flight, 16 words of the hot window change in both memories (each model
    // updates its own) and the next cycle invalidates the cache.
    logic        ps_write;
    logic        finished = 1'b0;
    logic        burst_active = 1'b0;

    function automatic logic [31:0] ps_addr(logic [31:0] r, int i);
        return BASE + ((next_rng(r + 32'(i)) & 32'(HOT - 1)) & ~32'h3);
    endfunction

    function automatic logic [31:0] ps_value(logic [31:0] r, int i);
        return next_rng(r ^ 32'(i * 7919));
    endfunction

    assign ps_write = !rst && !req_valid && !finished && drained && !rd_valid && !burst_active &&
                      rng[13:10] == 4'hA;

    // ---- Memory model ------------------------------------------------------
    typedef struct {
        logic [31:0]       addr;
        logic [MEM_DW-1:0] data;
        logic [STRB_W-1:0] strb;
        longint unsigned   due;
    } write_t;

    write_t            wq[$];           // taken, not answered yet; answered in order
    longint unsigned   cycle = 0;
    logic [31:0]       burst_addr;
    int unsigned       beats_left;
    int unsigned       delay;
    int unsigned       line_fills = 0;
    int unsigned       mem_writes = 0;
    logic              wr_done_q = 1'b0;
    logic              rd_wait_q = 1'b0;
    logic [31:0]       rd_addr_q;
    logic              wr_wait_q = 1'b0;
    logic [31:0]       wr_addr_q;
    logic [MEM_DW-1:0] wr_data_q;
    logic [STRB_W-1:0] wr_strb_q;

    assign rd_ready = !burst_active && rd_valid && rng[3:0] < 4'd6;
    assign rvalid   = burst_active && delay == 0 && !rng[4];
    assign wr_ready = wr_valid && rng[7:5] < 3'd5;
    assign wr_done  = wr_done_q;

    function automatic void mem_fail(string what);
        if (err_mem < 10) report(what);
    endfunction

    always_ff @(posedge clk) begin
        automatic int bad = 0;

        cycle <= cycle + 1;
        if (rst) begin
            burst_active <= 1'b0;
            wr_done_q    <= 1'b0;
        end else begin
            // Line fills: first beat 2 to 21 cycles after the request
            if (!burst_active) begin
                if (rd_valid && rd_ready) begin
                    if (rd_addr[$clog2(LINE_BYTES)-1:0] != 0) begin
                        mem_fail($sformatf("line request %08x not aligned", rd_addr));
                        bad++;
                    end
                    if (wq.size() != 0 || (wr_valid && wr_ready)) begin
                        mem_fail($sformatf("line request %08x with writes unanswered", rd_addr));
                        bad++;
                    end
                    burst_active <= 1'b1;
                    burst_addr   <= rd_addr;
                    rbeat        <= ddr_beat(rd_addr);
                    beats_left   <= BEATS;
                    delay        <= 2 + rng[12:8] % 20;
                    line_fills   <= line_fills + 1;
                end
            end else if (delay != 0) begin
                delay <= delay - 1;
            end else if (rvalid) begin
                burst_addr <= burst_addr + 32'(MEM_DW / 8);
                rbeat      <= ddr_beat(burst_addr + 32'(MEM_DW / 8));
                beats_left <= beats_left - 1;
                if (beats_left == 1) burst_active <= 1'b0;
            end

            // Writes: answered in order 1 to 24 cycles after they are taken,
            // and only then visible in memory
            if (wr_done_q) begin
                for (int i = 0; i < MEM_DW / 32; i++) begin
                    automatic logic [31:0] a = wq[0].addr + 32'(4 * i);
                    ddr_mem[a >> 2] = merge(ddr_word(a), wq[0].data[i*32 +: 32], wq[0].strb[i*4 +: 4]);
                end
                void'(wq.pop_front());
            end
            if (wr_valid && wr_ready) begin
                automatic write_t w;
                if (wr_addr[$clog2(STRB_W)-1:0] != 0 || wr_strb == '0) begin
                    mem_fail($sformatf("bad write %08x strobes %b", wr_addr, wr_strb));
                    bad++;
                end
                w.addr = wr_addr;
                w.data = wr_data;
                w.strb = wr_strb;
                w.due  = cycle + 1 + longint'(rng[20:16] % 24);
                if (wq.size() != 0 && w.due <= wq[wq.size()-1].due) w.due = wq[wq.size()-1].due + 1;
                wq.push_back(w);
                mem_writes <= mem_writes + 1;
            end
            wr_done_q <= wq.size() != 0 && wq[0].due <= cycle + 1;

            if (ps_write) begin
                for (int i = 0; i < 16; i++) ddr_mem[ps_addr(rng, i) >> 2] = ps_value(rng, i);
            end

            // Requests that wait must not change, a fill must not start during
            // a burst, and drained_o must mean that no write is in flight
            if ((rd_wait_q && (!rd_valid || rd_addr != rd_addr_q)) || (burst_active && rd_valid) ||
                (wr_wait_q && (!wr_valid || wr_addr != wr_addr_q || wr_data != wr_data_q ||
                               wr_strb != wr_strb_q)) ||
                (drained && (wq.size() != 0 || wr_valid))) begin
                mem_fail("memory-side request changed while waiting, fill during a burst, or drained_o early");
                bad++;
            end
        end
        err_mem   <= err_mem + bad;
        rd_wait_q <= !rst && rd_valid && !rd_ready;
        rd_addr_q <= rd_addr;
        wr_wait_q <= !rst && wr_valid && !wr_ready;
        wr_addr_q <= wr_addr;
        wr_data_q <= wr_data;
        wr_strb_q <= wr_strb;
    end

    // ---- Core model --------------------------------------------------------
    logic [31:0] ptr;
    logic        load_q = 1'b0;         // a load was accepted last cycle
    logic [31:0] load_addr_q;
    logic [31:0] load_expect_q;
    logic        repeat_load = 1'b0;    // this load repeats the last accepted one
    int unsigned wbuf_used = 0;         // stores accepted and not yet taken by memory
    int unsigned accepted = 0;
    int unsigned loads = 0, stores = 0, invalidates = 0;

    function automatic void core_fail(string what);
        if (err_core < 10) report(what);
    endfunction

    function automatic logic [31:0] align(logic [31:0] addr, int unsigned size);
        return addr & ~32'((1 << size) - 1);
    endfunction

    always_ff @(posedge clk) begin
        automatic int          bad = 0;
        automatic logic [31:0] next;
        automatic logic [31:0] a;
        automatic int unsigned size;
        automatic logic        store;
        automatic int unsigned acc_now;

        invalidate <= 1'b0;
        wbuf_used  <= wbuf_used + int'(req_valid && req_ready && req_we != 0) - int'(wr_valid && wr_ready);

        if (rst) begin
            req_valid <= 1'b0;
            req_addr  <= BASE;
            req_we    <= '0;
            ptr       <= BASE;
            load_q    <= 1'b0;
        end else begin
            if (load_q) begin
                checks++;
                if (rdata !== load_expect_q) begin
                    core_fail($sformatf("load %08x: got %08x, expected %08x", load_addr_q, rdata, load_expect_q));
                    bad++;
                end
            end
            load_q        <= req_valid && req_ready && req_we == 0;
            load_addr_q   <= req_addr;
            load_expect_q <= ref_word(req_addr);

            if (req_valid && !req_ready) begin
                if (req_we != 0 && wbuf_used < WBUF_DEPTH) begin
                    core_fail($sformatf("store %08x waited with the write buffer not full", req_addr));
                    bad++;
                end
                if (req_we == 0 && repeat_load) begin
                    core_fail($sformatf("repeated load %08x missed", req_addr));
                    bad++;
                end
            end else begin
                if (req_valid) begin
                    if (req_we != 0) begin
                        ref_mem[req_addr >> 2] = merge(ref_word(req_addr), req_wdata, req_we);
                        stores <= stores + 1;
                    end else begin
                        loads <= loads + 1;
                    end
                end
                acc_now = accepted + int'(req_valid);
                accepted <= acc_now;

                // Next request: 1, 2 or 4 bytes, about half of them stores
                size  = rng[25:24] == 2'd3 ? 2 : int'(rng[25:24]);
                store = rng[27:26] == 2'b01 || rng[27:26] == 2'b10;
                unique casez (rng[31:28])
                    4'b00??, 4'b010?:         next = ptr + 32'(1 << size);          // straight run
                    4'b0110, 4'b0111, 4'b100?: next = BASE + (rng & 32'(HOT - 1));   // hot window
                    4'b1010: next = ptr ^ (32'h1 << (TAG_LSB + rng[4:0] % (32 - TAG_LSB))); // same set
                    4'b1011: next = rng;                                            // anywhere
                    default: next = ptr;
                endcase
                a = align(next, size);
                repeat_load <= 1'b0;
                if (acc_now >= REQUESTS) begin
                    req_valid <= 1'b0;
                    finished  <= 1'b1;
                end else if (rng[31:28] == 4'b1100 && req_valid && req_we == 0) begin
                    req_valid   <= 1'b1;                                            // same load again
                    repeat_load <= 1'b1;
                end else if (rng[31:28] == 4'b1101) begin
                    req_valid <= 1'b0;                                              // idle
                end else begin
                    req_valid <= 1'b1;
                    req_addr  <= a;
                    req_we    <= store ? 4'((1 << (1 << size)) - 1) << a[1:0] : 4'b0;
                    req_wdata <= next_rng(rng ^ 32'h5A5A_5A5A);
                    ptr       <= a;
                end
            end

            // The PS write: no request goes out together with the invalidate,
            // which counts from the cycle after it
            if (ps_write) begin
                for (int i = 0; i < 16; i++) ref_mem[ps_addr(rng, i) >> 2] = ps_value(rng, i);
                invalidate  <= 1'b1;
                req_valid   <= 1'b0;
                invalidates <= invalidates + 1;
            end
        end
        err_core <= err_core + bad;
    end

    // ---- End: drain, then memory must match the reference -----------------
    logic compared = 1'b0;

    always_ff @(posedge clk) begin
        if (finished && !compared && !req_valid && drained && wq.size() == 0 && !load_q) begin
            automatic int unsigned bad = 0;
            foreach (ref_mem[w]) begin
                if (ddr_word(w << 2) != ref_mem[w]) begin
                    if (bad < 5) report($sformatf("memory word %08x: %08x, expected %08x",
                                                  w << 2, ddr_word(w << 2), ref_mem[w]));
                    bad++;
                end
            end
            compared <= 1'b1;
            err_end  <= bad;
        end
    end

    assign done = compared;

    final $display("  %0d B, %0d B lines, %0d-bit memory, %0d-entry buffer: %0d loads, %0d stores, %0d fills, %0d writes, %0d invalidates",
                   SIZE_BYTES, LINE_BYTES, MEM_DW, WBUF_DEPTH, loads, stores, line_fills, mem_writes,
                   invalidates);
endmodule

module tb_dcache;
    localparam int unsigned RUNS = 5;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    logic        done   [RUNS];
    int unsigned checks [RUNS];
    int unsigned errors [RUNS];

    // The default geometry, a tiny cache with 32-bit beats and a 2-entry
    // buffer, the longest AXI3 bursts (16 beats) and a larger cache.
    tb_dcache_run #(.SIZE_BYTES(8192),  .LINE_BYTES(32), .MEM_DW(64), .WBUF_DEPTH(4), .SEED(16'h1D0F))
        r0 (.clk, .rst, .done(done[0]), .checks(checks[0]), .errors(errors[0]));
    tb_dcache_run #(.SIZE_BYTES(512),   .LINE_BYTES(16), .MEM_DW(32), .WBUF_DEPTH(2), .SEED(16'h2B4A))
        r1 (.clk, .rst, .done(done[1]), .checks(checks[1]), .errors(errors[1]));
    tb_dcache_run #(.SIZE_BYTES(2048),  .LINE_BYTES(64), .MEM_DW(64), .WBUF_DEPTH(8), .SEED(16'h3C77))
        r2 (.clk, .rst, .done(done[2]), .checks(checks[2]), .errors(errors[2]));
    tb_dcache_run #(.SIZE_BYTES(1024),  .LINE_BYTES(64), .MEM_DW(32), .WBUF_DEPTH(4), .SEED(16'h4E91))
        r3 (.clk, .rst, .done(done[3]), .checks(checks[3]), .errors(errors[3]));
    tb_dcache_run #(.SIZE_BYTES(16384), .LINE_BYTES(32), .MEM_DW(64), .WBUF_DEPTH(2), .SEED(16'h5A03))
        r4 (.clk, .rst, .done(done[4]), .checks(checks[4]), .errors(errors[4]));

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
