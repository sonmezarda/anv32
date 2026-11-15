// Data cache: two-way set-associative, write-through with no write-allocate,
// between the core's data port and external memory.
//
// Core side: the anv32 bus protocol (anv32_bus_pkg). A load is accepted when
// it hits, and its word is on rdata_o the next cycle; a miss holds
// req_ready_o low until the line is in. A store is accepted as soon as the
// write buffer has room, hit or miss. On a hit it also updates the cached
// line; on a miss the line is not fetched (no write-allocate).
//
// Memory side, shaped after AXI so that a thin adapter can drive a Zynq HP
// port:
//   mem_rd_valid_o / mem_rd_ready_i / mem_rd_addr_o    line address (AR)
//   mem_rvalid_i / mem_rdata_i                         the line's beats (R)
//   mem_wr_valid_o / mem_wr_ready_i / mem_wr_addr_o    one beat with byte
//   mem_wr_data_o / mem_wr_strb_o                      strobes (AW + W)
//   mem_wr_done_i                                      write response (B)
// A line fill is a burst of BEATS = LINE_BYTES * 8 / MEM_DW beats in address
// order, which the cache always takes (RREADY tied high); AXI3 allows at most
// 16. Stores leave through a FIFO of WBUF_DEPTH entries, one single-beat write
// each. AXI does not order reads against writes, so a line fill waits until
// every buffered store has been written and answered.
//
// drained_o is high when no store is buffered or waiting for its response.
// Wait for it before telling anything outside the core that data is in
// memory, for example through MMIO.
//
// invalidate_i drops every line from the next cycle on. Buffered stores still
// go out, and a line fill already in flight still completes.
module anv32_dcache #(
    parameter int unsigned SIZE_BYTES = 8192,
    parameter int unsigned LINE_BYTES = 32,
    parameter int unsigned MEM_DW     = 64,     // memory-side beat width: 32 or 64
    parameter int unsigned WBUF_DEPTH = 4       // write buffer entries, a power of two
)(
    input  logic                clk_i,
    input  logic                rst_i,
    input  logic                invalidate_i,
    output logic                drained_o,

    input  logic                req_valid_i,
    input  logic [31:0]         req_addr_i,
    input  logic [31:0]         req_wdata_i,
    input  logic [3:0]          req_we_i,       // 0 = load
    output logic                req_ready_o,
    output logic [31:0]         rdata_o,

    output logic                mem_rd_valid_o,
    input  logic                mem_rd_ready_i,
    output logic [31:0]         mem_rd_addr_o,
    input  logic                mem_rvalid_i,
    input  logic [MEM_DW-1:0]   mem_rdata_i,

    output logic                mem_wr_valid_o,
    input  logic                mem_wr_ready_i,
    output logic [31:0]         mem_wr_addr_o,
    output logic [MEM_DW-1:0]   mem_wr_data_o,
    output logic [MEM_DW/8-1:0] mem_wr_strb_o,
    input  logic                mem_wr_done_i
);
    localparam int unsigned WAYS     = 2;
    localparam int unsigned SETS     = SIZE_BYTES / (LINE_BYTES * WAYS);
    localparam int unsigned BEATS    = LINE_BYTES * 8 / MEM_DW;
    localparam int unsigned STRB_W   = MEM_DW / 8;
    localparam int unsigned OFFSET_W = $clog2(LINE_BYTES);
    localparam int unsigned INDEX_W  = $clog2(SETS);
    localparam int unsigned TAG_W    = 32 - INDEX_W - OFFSET_W;
    localparam int unsigned BEAT_W   = $clog2(BEATS);
    localparam int unsigned BYTE_W   = $clog2(STRB_W);     // byte offset within a beat
    localparam int unsigned WBUF_W   = $clog2(WBUF_DEPTH);
    localparam int unsigned OUTST_W  = 4;                   // writes awaiting a response

    // synthesis translate_off
    initial begin
        if (MEM_DW != 32 && MEM_DW != 64)
            $fatal(1, "anv32_dcache: MEM_DW must be 32 or 64 (got %0d)", MEM_DW);
        if (LINE_BYTES != (1 << OFFSET_W) || BEATS < 2 || BEATS > 16)
            $fatal(1, "anv32_dcache: LINE_BYTES (%0d) must be a power of two of 2 to 16 beats",
                   LINE_BYTES);
        if (SIZE_BYTES != (1 << $clog2(SIZE_BYTES)) || SETS < 2)
            $fatal(1, "anv32_dcache: SIZE_BYTES (%0d) must be a power of two of 2+ sets",
                   SIZE_BYTES);
        if (WBUF_DEPTH != (1 << WBUF_W) || WBUF_DEPTH < 2)
            $fatal(1, "anv32_dcache: WBUF_DEPTH (%0d) must be a power of two, 2 or more",
                   WBUF_DEPTH);
    end
    // synthesis translate_on

    typedef enum logic [1:0] {IDLE, DRAIN, REQ, FILL} state_t;

    state_t               state_q;
    logic [31-OFFSET_W:0] miss_line_q;    // line address of the miss being filled
    logic                 fill_way_q;     // way the line goes into
    logic [BEAT_W-1:0]    beat_q;
    logic [SETS-1:0]      valid_q [WAYS];
    logic [SETS-1:0]      lru_q;          // per set: the way to replace next

    logic [INDEX_W-1:0]   req_index, miss_index;
    logic [TAG_W-1:0]     req_tag, miss_tag;
    logic [BEAT_W-1:0]    req_beat;
    logic                 is_store;
    logic [WAYS-1:0]      way_hit;
    logic                 hit, hit_way, victim;
    logic                 fire, load_hit, load_miss, store_hit;
    logic                 fill_beat, fill_done;
    logic                 wbuf_full, drained;

    assign req_index  = req_addr_i[OFFSET_W +: INDEX_W];
    assign req_tag    = req_addr_i[31 -: TAG_W];
    assign req_beat   = req_addr_i[BYTE_W +: BEAT_W];
    assign miss_index = miss_line_q[INDEX_W-1:0];
    assign miss_tag   = miss_line_q[31-OFFSET_W -: TAG_W];
    assign is_store   = req_we_i != 4'b0;

    assign hit       = |way_hit;
    assign hit_way   = way_hit[1];
    // An empty way first, otherwise the least recently used one
    assign victim    = !valid_q[0][req_index] ? 1'b0 :
                       !valid_q[1][req_index] ? 1'b1 : lru_q[req_index];

    assign req_ready_o = state_q == IDLE && req_valid_i && (is_store ? !wbuf_full : hit);
    assign fire        = req_valid_i && req_ready_o;
    assign load_hit    = fire && !is_store;
    assign load_miss   = state_q == IDLE && req_valid_i && !is_store && !hit;
    assign store_hit   = fire && is_store && hit;
    assign fill_beat   = state_q == FILL && mem_rvalid_i;
    assign fill_done   = fill_beat && beat_q == BEAT_W'(BEATS - 1);

    assign mem_rd_valid_o = state_q == REQ;
    assign mem_rd_addr_o  = {miss_line_q, {OFFSET_W{1'b0}}};
    assign drained_o      = drained;

    // ---- Store data on the beat --------------------------------------------
    logic [MEM_DW-1:0] store_data;
    logic [STRB_W-1:0] store_strb;

    generate
        if (MEM_DW == 64) begin : g_store64
            assign store_data = {req_wdata_i, req_wdata_i};
            assign store_strb = req_addr_i[2] ? {req_we_i, 4'b0} : {4'b0, req_we_i};
        end else begin : g_store32
            assign store_data = req_wdata_i;
            assign store_strb = req_we_i;
        end
    endgenerate

    // ---- Ways --------------------------------------------------------------
    // Tags in asynchronous-read RAM, so a hit is known in the request cycle.
    // The data RAM has one write port, shared by line fills and store hits
    // (never in the same cycle), with byte enables; both ways are read every
    // cycle at the requested address and the hit way is picked afterwards.
    logic [MEM_DW-1:0] way_data [WAYS];    // each way's word, a cycle after the request

    generate
        for (genvar w = 0; w < WAYS; w++) begin : g_way
            logic [TAG_W-1:0]  tag_ram  [0:SETS-1];
            logic [MEM_DW-1:0] data_ram [0:SETS*BEATS-1];
            logic              data_we;
            logic [INDEX_W+BEAT_W-1:0] data_waddr;
            logic [MEM_DW-1:0] data_wdata;
            logic [STRB_W-1:0] data_wstrb;
            logic [MEM_DW-1:0] data_q;

            assign way_hit[w] = valid_q[w][req_index] && tag_ram[req_index] == req_tag;

            always_comb begin
                if (fill_beat) begin
                    data_we    = fill_way_q == 1'(w);
                    data_waddr = {miss_index, beat_q};
                    data_wdata = mem_rdata_i;
                    data_wstrb = '1;
                end else begin
                    data_we    = store_hit && hit_way == 1'(w);
                    data_waddr = {req_index, req_beat};
                    data_wdata = store_data;
                    data_wstrb = store_strb;
                end
            end

            always_ff @(posedge clk_i) begin
                if (fill_done && fill_way_q == 1'(w)) tag_ram[miss_index] <= miss_tag;
            end

            always_ff @(posedge clk_i) begin
                if (data_we) begin
                    for (int b = 0; b < STRB_W; b++)
                        if (data_wstrb[b]) data_ram[data_waddr][b*8 +: 8] <= data_wdata[b*8 +: 8];
                end
                data_q <= data_ram[{req_index, req_beat}];
            end

            assign way_data[w] = data_q;
        end
    endgenerate

    logic way_q;
    always_ff @(posedge clk_i) way_q <= hit_way;

    generate
        if (MEM_DW == 64) begin : g_word_sel
            logic word_q;
            always_ff @(posedge clk_i) word_q <= req_addr_i[2];
            assign rdata_o = word_q ? way_data[way_q][63:32] : way_data[way_q][31:0];
        end else begin : g_word
            assign rdata_o = way_data[way_q];
        end
    endgenerate

    // ---- Write buffer ------------------------------------------------------
    logic [31-BYTE_W:0] wbuf_addr [WBUF_DEPTH];
    logic [MEM_DW-1:0]  wbuf_data [WBUF_DEPTH];
    logic [STRB_W-1:0]  wbuf_strb [WBUF_DEPTH];
    logic [WBUF_W-1:0]  wbuf_head_q, wbuf_tail_q;
    logic [WBUF_W:0]    wbuf_count_q;
    logic [OUTST_W-1:0] outstanding_q;
    logic               wbuf_push, wbuf_pop;

    assign wbuf_full      = wbuf_count_q == (WBUF_W+1)'(WBUF_DEPTH);
    assign wbuf_push      = fire && is_store;
    assign wbuf_pop       = mem_wr_valid_o && mem_wr_ready_i;
    assign drained        = wbuf_count_q == 0 && outstanding_q == 0;

    assign mem_wr_valid_o = wbuf_count_q != 0 && outstanding_q != '1;
    assign mem_wr_addr_o  = {wbuf_addr[wbuf_head_q], {BYTE_W{1'b0}}};
    assign mem_wr_data_o  = wbuf_data[wbuf_head_q];
    assign mem_wr_strb_o  = wbuf_strb[wbuf_head_q];

    always_ff @(posedge clk_i) begin
        if (wbuf_push) begin
            wbuf_addr[wbuf_tail_q] <= req_addr_i[31:BYTE_W];
            wbuf_data[wbuf_tail_q] <= store_data;
            wbuf_strb[wbuf_tail_q] <= store_strb;
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            wbuf_head_q   <= '0;
            wbuf_tail_q   <= '0;
            wbuf_count_q  <= '0;
            outstanding_q <= '0;
        end else begin
            if (wbuf_push) wbuf_tail_q <= wbuf_tail_q + 1'b1;
            if (wbuf_pop)  wbuf_head_q <= wbuf_head_q + 1'b1;
            wbuf_count_q  <= wbuf_count_q + (WBUF_W+1)'(wbuf_push) - (WBUF_W+1)'(wbuf_pop);
            outstanding_q <= outstanding_q + OUTST_W'(wbuf_pop) - OUTST_W'(mem_wr_done_i);
        end
    end

    // ---- Misses ------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q     <= IDLE;
            miss_line_q <= '0;
            fill_way_q  <= 1'b0;
            beat_q      <= '0;
        end else begin
            unique case (state_q)
                IDLE: if (load_miss) begin
                    state_q     <= DRAIN;
                    miss_line_q <= req_addr_i[31:OFFSET_W];
                    fill_way_q  <= victim;
                end
                DRAIN: if (drained) state_q <= REQ;
                REQ: if (mem_rd_ready_i) begin
                    state_q <= FILL;
                    beat_q  <= '0;
                end
                FILL: if (fill_beat) begin
                    beat_q <= beat_q + 1'b1;
                    if (fill_done) state_q <= IDLE;
                end
                default: state_q <= IDLE;
            endcase
        end
    end

    // ---- Valid bits and replacement ----------------------------------------
    always_ff @(posedge clk_i) begin
        if (rst_i || invalidate_i) begin
            for (int w = 0; w < WAYS; w++) valid_q[w] <= '0;
        end else if (fill_done) begin
            valid_q[fill_way_q][miss_index] <= 1'b1;
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i)                       lru_q <= '0;
        else if (fill_done)              lru_q[miss_index] <= !fill_way_q;
        else if (load_hit || store_hit)  lru_q[req_index]  <= !hit_way;
    end

endmodule
