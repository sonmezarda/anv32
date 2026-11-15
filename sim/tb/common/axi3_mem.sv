// AXI3 slave memory model for testbenches, standing in for a Zynq-7000 HP
// port in front of DDR.
//
// - AR, AW and W are taken after random delays and independently of each
//   other; W may come before its AW. Up to four reads and eight writes wait
//   at a time.
// - Reads are answered in order, the first beat 2 to 21 cycles after the
//   burst starts and then with random gaps; RLAST marks the last beat.
// - Writes are answered in order 1 to 24 cycles after both halves are in,
//   and only then land in memory. Only single-beat writes (AWLEN = 0) are
//   modelled.
// - Memory covers the whole address space: a word never written reads as a
//   hash of its address and SEED. poke_* writes a word directly, as another
//   bus master (the PS) would. INIT_WORDS words from INIT_BASE live in a
//   plain array instead (init_ram, zero at start), which a testbench can
//   fill with $readmemh to load a program.
//
// Checked: a request that waits keeps its payload, ARBURST is INCR, the
// transfer size is the bus width, bursts are aligned and stay inside 4 KiB,
// WID and WLAST match, and no read overlaps a write that has not been
// answered yet (AXI does not order the two). errors counts the violations;
// the first few are printed with NAME.
`timescale 1ns/1ps

module axi3_mem #(
    parameter int unsigned DW   = 64,
    parameter int unsigned ID_W = 6,
    parameter logic [31:0] SEED = 32'h1D0F_2B4A,
    parameter string       NAME = "axi3_mem",
    parameter logic [31:0] INIT_BASE  = 32'h0,
    parameter int unsigned INIT_WORDS = 0
)(
    input  logic              clk,
    input  logic              rst,

    input  logic [ID_W-1:0]   s_axi_arid,
    input  logic [31:0]       s_axi_araddr,
    input  logic [3:0]        s_axi_arlen,
    input  logic [2:0]        s_axi_arsize,
    input  logic [1:0]        s_axi_arburst,
    input  logic              s_axi_arvalid,
    output logic              s_axi_arready,
    output logic [ID_W-1:0]   s_axi_rid,
    output logic [DW-1:0]     s_axi_rdata,
    output logic [1:0]        s_axi_rresp,
    output logic              s_axi_rlast,
    output logic              s_axi_rvalid,
    input  logic              s_axi_rready,

    input  logic [ID_W-1:0]   s_axi_awid,
    input  logic [31:0]       s_axi_awaddr,
    input  logic [3:0]        s_axi_awlen,
    input  logic [2:0]        s_axi_awsize,
    input  logic [1:0]        s_axi_awburst,
    input  logic              s_axi_awvalid,
    output logic              s_axi_awready,
    input  logic [ID_W-1:0]   s_axi_wid,
    input  logic [DW-1:0]     s_axi_wdata,
    input  logic [DW/8-1:0]   s_axi_wstrb,
    input  logic              s_axi_wlast,
    input  logic              s_axi_wvalid,
    output logic              s_axi_wready,
    output logic [ID_W-1:0]   s_axi_bid,
    output logic [1:0]        s_axi_bresp,
    output logic              s_axi_bvalid,
    input  logic              s_axi_bready,

    input  logic              poke_valid,
    input  logic [31:0]       poke_addr,
    input  logic [31:0]       poke_data,

    output int unsigned       pending_writes,   // address taken, not answered yet
    output int unsigned       errors
);
    localparam int unsigned BYTES = DW / 8;
    localparam logic [2:0]  SIZE  = 3'($clog2(BYTES));

    // ---- Memory ------------------------------------------------------------
    logic [31:0] mem [int unsigned];
    logic [31:0] init_ram [INIT_WORDS > 0 ? INIT_WORDS : 1];

    function automatic logic [31:0] init_word(int unsigned waddr);
        logic [31:0] x = waddr ^ SEED;
        x = x * 32'h9E37_79B1;
        return x ^ (x >> 15);
    endfunction

    function automatic logic in_init(logic [31:0] addr);
        return INIT_WORDS != 0 && addr - INIT_BASE < 32'(INIT_WORDS * 4);
    endfunction

    function automatic logic [31:0] read_word(logic [31:0] addr);
        int unsigned w = addr >> 2;
        if (in_init(addr)) return init_ram[(addr - INIT_BASE) >> 2];
        return mem.exists(w) ? mem[w] : init_word(w);
    endfunction

    function automatic void write_word(logic [31:0] addr, logic [31:0] value);
        if (in_init(addr)) init_ram[(addr - INIT_BASE) >> 2] = value;
        else               mem[addr >> 2] = value;
    endfunction

    function automatic logic [DW-1:0] read_beat(logic [31:0] addr);
        logic [DW-1:0] b;
        for (int i = 0; i < DW / 32; i++) b[i*32 +: 32] = read_word(addr + 32'(4 * i));
        return b;
    endfunction

    // ---- Random source -----------------------------------------------------
    logic [31:0] rng = SEED | 32'h1;

    function automatic logic [31:0] next_rng(logic [31:0] s);
        s ^= s << 13;
        s ^= s >> 17;
        s ^= s << 5;
        return s;
    endfunction

    function automatic void report(string what);
        $display("  [FAIL] %s: %s", NAME, what);
    endfunction

    // ---- Queues ------------------------------------------------------------
    typedef struct {
        logic [ID_W-1:0] id;
        logic [31:0]     addr;
        logic [3:0]      len;
    } addr_t;

    typedef struct {
        logic [ID_W-1:0] id;
        logic [DW-1:0]   data;
        logic [DW/8-1:0] strb;
        logic            last;
    } wbeat_t;

    typedef struct {
        logic [ID_W-1:0] id;
        logic [31:0]     addr;
        logic [DW-1:0]   data;
        logic [DW/8-1:0] strb;
        longint unsigned due;
    } write_t;

    addr_t           arq[$];            // reads taken, not started
    addr_t           awq[$];            // write addresses waiting for their data
    wbeat_t          wq[$];             // write data waiting for its address
    write_t          bq[$];             // complete writes, answered in order
    longint unsigned cycle = 0;

    // Current read burst
    logic            r_active = 1'b0;
    logic [ID_W-1:0] r_id;
    logic [31:0]     r_addr;
    int unsigned     r_left;
    int unsigned     r_delay;
    logic            r_valid = 1'b0;
    logic [DW-1:0]   r_data;
    logic            r_last;
    logic            b_valid = 1'b0;

    assign s_axi_arready  = arq.size() < 4 && rng[2:0] < 3'd5;
    assign s_axi_awready  = awq.size() < 8 && rng[5:3] < 3'd5;
    assign s_axi_wready   = wq.size() < 8 && rng[8:6] < 3'd5;
    assign s_axi_rid      = r_id;
    assign s_axi_rdata    = r_data;
    assign s_axi_rresp    = 2'b00;
    assign s_axi_rlast    = r_last;
    assign s_axi_rvalid   = r_valid;
    assign s_axi_bid      = bq.size() != 0 ? bq[0].id : '0;
    assign s_axi_bresp    = 2'b00;
    assign s_axi_bvalid   = b_valid;
    assign pending_writes = awq.size() + bq.size();

    // A request is a burst inside one 4 KiB page, aligned to the bus width
    function automatic logic bad_burst(logic [31:0] addr, logic [3:0] len, logic [2:0] size,
                                       logic [1:0] burst);
        return burst != 2'b01 || size != SIZE || addr[$clog2(BYTES)-1:0] != 0 ||
               32'(addr[11:0]) + (32'(len) + 1) * BYTES > 4096;
    endfunction

    function automatic logic overlaps(logic [31:0] a0, int unsigned n0, logic [31:0] a1, int unsigned n1);
        return a0 < a1 + n1 && a1 < a0 + n0;
    endfunction

    // ---- Protocol state for the stability checks ---------------------------
    logic            ar_wait_q = 1'b0, aw_wait_q = 1'b0, w_wait_q = 1'b0;
    addr_t           ar_q, aw_q;
    wbeat_t          w_q;
    logic [1:0]      arburst_q, awburst_q;
    logic [2:0]      arsize_q, awsize_q;

    always_ff @(posedge clk) begin
        automatic int bad = 0;

        rng   <= next_rng(rng);
        cycle <= cycle + 1;

        if (rst) begin
            r_active <= 1'b0;
            r_valid  <= 1'b0;
            b_valid  <= 1'b0;
        end else begin
            // Payload must hold while a request waits
            if (ar_wait_q && (!s_axi_arvalid || s_axi_araddr != ar_q.addr || s_axi_arid != ar_q.id ||
                              s_axi_arlen != ar_q.len || s_axi_arsize != arsize_q ||
                              s_axi_arburst != arburst_q)) begin
                if (errors + bad < 10) report("AR changed while waiting");
                bad++;
            end
            if (aw_wait_q && (!s_axi_awvalid || s_axi_awaddr != aw_q.addr || s_axi_awid != aw_q.id ||
                              s_axi_awlen != aw_q.len || s_axi_awsize != awsize_q ||
                              s_axi_awburst != awburst_q)) begin
                if (errors + bad < 10) report("AW changed while waiting");
                bad++;
            end
            if (w_wait_q && (!s_axi_wvalid || s_axi_wdata != w_q.data || s_axi_wstrb != w_q.strb ||
                             s_axi_wlast != w_q.last || s_axi_wid != w_q.id)) begin
                if (errors + bad < 10) report("W changed while waiting");
                bad++;
            end

            // Read addresses
            if (s_axi_arvalid && s_axi_arready) begin
                automatic addr_t a;
                a.id = s_axi_arid; a.addr = s_axi_araddr; a.len = s_axi_arlen;
                if (bad_burst(s_axi_araddr, s_axi_arlen, s_axi_arsize, s_axi_arburst)) begin
                    if (errors + bad < 10) report($sformatf("bad read burst at %08x", s_axi_araddr));
                    bad++;
                end
                foreach (awq[i])
                    if (overlaps(s_axi_araddr, (32'(s_axi_arlen) + 1) * BYTES, awq[i].addr, BYTES)) begin
                        if (errors + bad < 10) report($sformatf("read %08x overlaps an unanswered write", s_axi_araddr));
                        bad++;
                    end
                foreach (bq[i])
                    if (overlaps(s_axi_araddr, (32'(s_axi_arlen) + 1) * BYTES, bq[i].addr, BYTES)) begin
                        if (errors + bad < 10) report($sformatf("read %08x overlaps an unanswered write", s_axi_araddr));
                        bad++;
                    end
                arq.push_back(a);
            end

            // Read data: one burst at a time, in order
            if (r_valid && s_axi_rready) begin
                r_valid <= 1'b0;
                if (r_last) r_active <= 1'b0;
            end
            if (!r_active && !(r_valid && s_axi_rready) && arq.size() != 0) begin
                r_active <= 1'b1;
                r_id     <= arq[0].id;
                r_addr   <= arq[0].addr;
                r_left   <= 32'(arq[0].len) + 1;
                r_delay  <= 2 + rng[16:12] % 20;
                void'(arq.pop_front());
            end else if (r_active && r_delay != 0) begin
                r_delay <= r_delay - 1;
            end else if (r_active && r_left != 0 && (!r_valid || s_axi_rready) && !rng[9]) begin
                r_valid <= 1'b1;
                r_data  <= read_beat(r_addr);
                r_last  <= r_left == 1;
                r_addr  <= r_addr + BYTES;
                r_left  <= r_left - 1;
            end

            // Write addresses and data, paired in order
            if (s_axi_awvalid && s_axi_awready) begin
                automatic addr_t a;
                a.id = s_axi_awid; a.addr = s_axi_awaddr; a.len = s_axi_awlen;
                if (bad_burst(s_axi_awaddr, s_axi_awlen, s_axi_awsize, s_axi_awburst) || s_axi_awlen != 0) begin
                    if (errors + bad < 10) report($sformatf("bad or multi-beat write at %08x", s_axi_awaddr));
                    bad++;
                end
                awq.push_back(a);
            end
            if (s_axi_wvalid && s_axi_wready) begin
                automatic wbeat_t b;
                b.id = s_axi_wid; b.data = s_axi_wdata; b.strb = s_axi_wstrb; b.last = s_axi_wlast;
                wq.push_back(b);
            end
            if (awq.size() != 0 && wq.size() != 0) begin
                automatic write_t w;
                if (wq[0].id != awq[0].id || !wq[0].last) begin
                    if (errors + bad < 10) report("WID or WLAST does not match the write address");
                    bad++;
                end
                w.id   = awq[0].id;
                w.addr = awq[0].addr;
                w.data = wq[0].data;
                w.strb = wq[0].strb;
                w.due  = cycle + 1 + longint'(rng[21:17] % 24);
                if (bq.size() != 0 && w.due <= bq[bq.size()-1].due) w.due = bq[bq.size()-1].due + 1;
                bq.push_back(w);
                void'(awq.pop_front());
                void'(wq.pop_front());
            end

            // Write responses: the write lands in memory when it is answered
            if (b_valid && s_axi_bready) begin
                for (int i = 0; i < DW / 32; i++) begin
                    automatic logic [31:0] a = bq[0].addr + 32'(4 * i);
                    automatic logic [31:0] v = read_word(a);
                    for (int k = 0; k < 4; k++)
                        if (bq[0].strb[i*4 + k]) v[k*8 +: 8] = bq[0].data[i*32 + k*8 +: 8];
                    write_word(a, v);
                end
                void'(bq.pop_front());
                b_valid <= 1'b0;
            end else if (!b_valid && bq.size() != 0 && bq[0].due <= cycle) begin
                b_valid <= 1'b1;
            end

            if (poke_valid) write_word(poke_addr, poke_data);
        end

        errors    <= errors + bad;
        ar_wait_q <= !rst && s_axi_arvalid && !s_axi_arready;
        aw_wait_q <= !rst && s_axi_awvalid && !s_axi_awready;
        w_wait_q  <= !rst && s_axi_wvalid && !s_axi_wready;
        ar_q      <= '{id: s_axi_arid, addr: s_axi_araddr, len: s_axi_arlen};
        aw_q      <= '{id: s_axi_awid, addr: s_axi_awaddr, len: s_axi_awlen};
        w_q       <= '{id: s_axi_wid, data: s_axi_wdata, strb: s_axi_wstrb, last: s_axi_wlast};
        arsize_q  <= s_axi_arsize;
        arburst_q <= s_axi_arburst;
        awsize_q  <= s_axi_awsize;
        awburst_q <= s_axi_awburst;
    end
endmodule
