// Instruction cache testbench (anv32_icache). Several cache geometries run
// side by side, each with its own core model and memory model:
//   - The core model issues reads like the fetch stage: a request that is not
//     accepted stays unchanged, and a new one may follow right after an
//     accepted one. Addresses mix straight-line runs, short jumps (hits),
//     jumps to the same index with another tag (conflicts) and jumps anywhere.
//   - The memory model takes line requests after a random delay and returns
//     the beats with random gaps. Memory contents are a function of the
//     address and an epoch, so the whole 4 GiB is memory; changing the epoch
//     while the cache is idle, together with invalidate_i, stands in for new
//     code being loaded.
// Every word is checked against memory, every line request against the burst
// rules, and a repeated request against the hit latency (no wait state with
// asynchronous tags, exactly one with synchronous tags).
`timescale 1ns/1ps

module tb_icache_run #(
    parameter int unsigned SIZE_BYTES = 8192,
    parameter int unsigned LINE_BYTES = 32,
    parameter int unsigned MEM_DW     = 64,
    parameter bit          SYNC_TAGS  = 1'b0,
    parameter int unsigned REQUESTS   = 20000,
    parameter logic [15:0] SEED       = 16'h1D0F
)(
    input  logic        clk,
    input  logic        rst,
    output logic        done,
    output int unsigned checks,
    output int unsigned errors
);
    localparam int unsigned BEATS    = LINE_BYTES * 8 / MEM_DW;
    localparam int unsigned TAG_LSB  = $clog2(SIZE_BYTES);
    localparam logic [31:0] RESET_PC = 32'h8000_0000;

    logic              invalidate;
    logic              req_valid;
    logic [31:0]       req_addr;
    logic              req_ready;
    logic [31:0]       rdata;
    logic              mem_req_valid;
    logic              mem_req_ready;
    logic [31:0]       mem_req_addr;
    logic              mem_rvalid;
    logic [MEM_DW-1:0] mem_rdata;

    anv32_icache #(
        .SIZE_BYTES(SIZE_BYTES),
        .LINE_BYTES(LINE_BYTES),
        .MEM_DW    (MEM_DW),
        .SYNC_TAGS (SYNC_TAGS)
    ) dut (
        .clk_i          (clk),
        .rst_i          (rst),
        .invalidate_i   (invalidate),
        .req_valid_i    (req_valid),
        .req_addr_i     (req_addr),
        .req_ready_o    (req_ready),
        .rdata_o        (rdata),
        .mem_req_valid_o(mem_req_valid),
        .mem_req_ready_i(mem_req_ready),
        .mem_req_addr_o (mem_req_addr),
        .mem_rvalid_i   (mem_rvalid),
        .mem_rdata_i    (mem_rdata)
    );

    // ---- Memory contents ---------------------------------------------------
    logic [31:0] epoch = 32'h0;

    function automatic logic [31:0] mem_word(logic [31:0] addr, logic [31:0] ep);
        logic [31:0] x = (addr >> 2) ^ ep;
        x = x * 32'h9E37_79B1;
        return x ^ (x >> 15) ^ ep;
    endfunction

    function automatic logic [MEM_DW-1:0] mem_beat(logic [31:0] addr, logic [31:0] ep);
        logic [MEM_DW-1:0] b;
        for (int i = 0; i < MEM_DW / 32; i++) b[i*32 +: 32] = mem_word(addr + 32'(4 * i), ep);
        return b;
    endfunction

    // ---- Random source -----------------------------------------------------
    logic [31:0] rng = {SEED, ~SEED};

    function automatic logic [31:0] next_rng(logic [31:0] s);
        s ^= s << 13;
        s ^= s >> 17;
        s ^= s << 5;
        return s;
    endfunction

    function automatic void report(string what);
        $display("  [FAIL] %0dB/%0dB/%0db/%s: %s", SIZE_BYTES, LINE_BYTES, MEM_DW,
                 SYNC_TAGS ? "sync" : "async", what);
    endfunction

    // Each process counts its own failures
    int unsigned err_mem = 0, err_proto = 0, err_core = 0;
    assign errors = err_mem + err_proto + err_core;

    // ---- Memory model ------------------------------------------------------
    logic        burst_active = 1'b0;   // a line request was taken, beats pending
    logic [31:0] burst_addr;
    int unsigned beats_left;
    int unsigned delay;
    int unsigned line_reqs = 0;

    always_ff @(posedge clk) begin
        rng <= next_rng(rng);
    end

    always_comb begin
        mem_req_ready = !burst_active && mem_req_valid && rng[3:0] < 4'd6;
        mem_rvalid    = burst_active && delay == 0 && !rng[4];
        mem_rdata     = mem_rvalid ? mem_beat(burst_addr, epoch) : {MEM_DW{1'bx}};
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            burst_active <= 1'b0;
        end else if (!burst_active) begin
            if (mem_req_valid && mem_req_ready) begin
                if (mem_req_addr[$clog2(LINE_BYTES)-1:0] != 0) begin
                    if (err_mem < 10) report($sformatf("bad line request %08x", mem_req_addr));
                    err_mem <= err_mem + 1;
                end
                burst_active <= 1'b1;
                burst_addr   <= mem_req_addr;
                beats_left   <= BEATS;
                delay        <= 2 + rng[9:5] % 20;     // first beat after 2..21 cycles
                line_reqs    <= line_reqs + 1;
            end
        end else if (delay != 0) begin
            delay <= delay - 1;
        end else if (mem_rvalid) begin
            burst_addr <= burst_addr + 32'(MEM_DW / 8);
            beats_left <= beats_left - 1;
            if (beats_left == 1) burst_active <= 1'b0;
        end
    end

    // A line request must stay up until it is taken, and none may come while
    // a burst is still delivering beats.
    logic        mreq_wait_q = 1'b0;
    logic [31:0] mreq_addr_q;

    always_ff @(posedge clk) begin
        if (!rst) begin
            if ((mreq_wait_q && (!mem_req_valid || mem_req_addr != mreq_addr_q)) ||
                (burst_active && mem_req_valid)) begin
                if (err_proto < 10) report($sformatf("line request %08x changed while waiting or came during a burst",
                                                     mem_req_addr));
                err_proto <= err_proto + 1;
            end
        end
        mreq_wait_q <= !rst && mem_req_valid && !mem_req_ready;
        mreq_addr_q <= mem_req_addr;
    end

    // ---- Core model --------------------------------------------------------
    logic [31:0] pc;
    logic        pending_q = 1'b0;      // last cycle's request was accepted
    logic [31:0] pending_addr_q;
    logic [31:0] pending_epoch_q;
    int unsigned wait_cycles = 0;       // cycles the current request has waited
    logic        repeat_req = 1'b0;     // this request repeats the last one
    int unsigned accepted = 0;
    int unsigned invalidates = 0;
    logic        idle_req;              // the cache has nothing in flight

    // With no request on the port the cache cannot be filling a line (a
    // waiting request never goes away), so only the memory side needs a look.
    // A read accepted last cycle is already in the data register, and its
    // expected value was taken with the epoch of that cycle.
    assign idle_req = !req_valid && !mem_req_valid && !burst_active;

    function automatic void core_fail(string what);
        if (err_core < 10) report(what);
    endfunction

    always_ff @(posedge clk) begin
        invalidate <= 1'b0;

        if (rst) begin
            req_valid <= 1'b0;
            req_addr  <= RESET_PC;
            pc        <= RESET_PC;
            pending_q <= 1'b0;
        end else begin
            // Data for the request accepted last cycle
            if (pending_q) begin
                checks++;
                if (rdata !== mem_word(pending_addr_q, pending_epoch_q)) begin
                    core_fail($sformatf("read %08x: got %08x, expected %08x", pending_addr_q, rdata,
                                        mem_word(pending_addr_q, pending_epoch_q)));
                    err_core++;
                end
            end
            pending_q <= req_valid && req_ready;
            pending_addr_q  <= req_addr;
            pending_epoch_q <= epoch;

            if (req_valid && !req_ready) begin
                wait_cycles <= wait_cycles + 1;
                if (repeat_req && wait_cycles == (SYNC_TAGS ? 1 : 0)) begin
                    core_fail($sformatf("repeated read %08x missed", req_addr));
                    err_core++;
                end
            end else begin
                if (req_valid && repeat_req && wait_cycles != (SYNC_TAGS ? 1 : 0)) begin
                    core_fail($sformatf("hit on %08x took %0d wait cycles", req_addr, wait_cycles));
                    err_core++;
                end
                if (req_valid) accepted <= accepted + 1;
                wait_cycles <= 0;

                // Next request: mostly straight-line code, sometimes the same
                // address again, a short jump, a far jump or an idle cycle.
                repeat_req <= 1'b0;
                req_valid  <= 1'b1;
                unique casez (rng[23:20])
                    4'b00??, 4'b010?, 4'b0110: begin
                        req_addr <= pc + 4;
                        pc       <= pc + 4;
                    end
                    4'b0111, 4'b100?: begin
                        req_addr   <= req_valid ? req_addr : pc;
                        repeat_req <= req_valid;
                    end
                    4'b101?, 4'b1100: begin
                        req_addr <= pc - 32'(rng[30:26] * 4) + 32'(rng[31] * 64);
                        pc       <= pc - 32'(rng[30:26] * 4) + 32'(rng[31] * 64);
                    end
                    4'b1101: begin              // same index, one tag bit flipped
                        req_addr <= pc ^ (32'h1 << (TAG_LSB + rng[31:27] % (32 - TAG_LSB)));
                        pc       <= pc ^ (32'h1 << (TAG_LSB + rng[31:27] % (32 - TAG_LSB)));
                    end
                    4'b1110: begin              // anywhere
                        req_addr <= rng & ~32'h3;
                        pc       <= rng & ~32'h3;
                    end
                    default: req_valid <= 1'b0;
                endcase
            end

            // Now and then load "new code": change memory and invalidate. The
            // invalidate counts from the cycle after it, so no request goes
            // out together with it.
            if (idle_req && rng[13:6] == 8'hA5) begin
                epoch       <= rng;
                invalidate  <= 1'b1;
                req_valid   <= 1'b0;
                invalidates <= invalidates + 1;
            end
        end
    end

    assign done = accepted >= REQUESTS;

    final $display("  %0d B, %0d B lines, %0d-bit memory, %s tags: %0d reads, %0d line fills, %0d invalidates",
                   SIZE_BYTES, LINE_BYTES, MEM_DW, SYNC_TAGS ? "sync " : "async",
                   accepted, line_reqs, invalidates);
endmodule

module tb_icache;
    localparam int unsigned RUNS = 5;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    logic        done   [RUNS];
    int unsigned checks [RUNS];
    int unsigned errors [RUNS];

    // The default geometry with both tag modes, a small cache with 32-bit
    // beats, and the longest AXI3 bursts (16 beats) with both beat widths.
    tb_icache_run #(.SIZE_BYTES(8192), .LINE_BYTES(32),  .MEM_DW(64), .SYNC_TAGS(0), .SEED(16'h1D0F))
        r0 (.clk, .rst, .done(done[0]), .checks(checks[0]), .errors(errors[0]));
    tb_icache_run #(.SIZE_BYTES(8192), .LINE_BYTES(32),  .MEM_DW(64), .SYNC_TAGS(1), .SEED(16'h2B4A))
        r1 (.clk, .rst, .done(done[1]), .checks(checks[1]), .errors(errors[1]));
    tb_icache_run #(.SIZE_BYTES(256),  .LINE_BYTES(16),  .MEM_DW(32), .SYNC_TAGS(0), .SEED(16'h3C77))
        r2 (.clk, .rst, .done(done[2]), .checks(checks[2]), .errors(errors[2]));
    tb_icache_run #(.SIZE_BYTES(2048), .LINE_BYTES(64),  .MEM_DW(32), .SYNC_TAGS(1), .SEED(16'h4E91))
        r3 (.clk, .rst, .done(done[3]), .checks(checks[3]), .errors(errors[3]));
    tb_icache_run #(.SIZE_BYTES(4096), .LINE_BYTES(128), .MEM_DW(64), .SYNC_TAGS(0), .SEED(16'h5A03))
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
