// Instruction cache: direct-mapped and read-only, between the core's
// instruction port and external memory.
//
// Core side: reads on the anv32 bus protocol (anv32_bus_pkg). A request is
// accepted on a cycle where req_valid_i and req_ready_o are both high, and the
// word is on rdata_o the next cycle. A miss holds req_ready_o low until the
// line is in; the core keeps the address on the port meanwhile.
//
// Memory side: one burst read per line, shaped after AXI so that a thin
// adapter can drive a Zynq HP port:
//   mem_req_valid_o / mem_req_ready_i / mem_req_addr_o   line address (AR)
//   mem_rvalid_i / mem_rdata_i                           the line's beats (R)
// The beats come in address order, BEATS = LINE_BYTES * 8 / MEM_DW of them.
// The cache always takes read data (RREADY tied high on AXI). AXI3, which the
// Zynq-7000 HP ports use, allows at most 16 beats per burst.
//
// SYNC_TAGS selects how a hit is found:
//   0  tags in asynchronous-read RAM (LUTRAM on 7-series): the hit is known in
//      the request cycle, so a hit has no wait state.
//   1  tags in synchronous RAM (block RAM): the tag arrives a cycle later, so
//      every hit waits one cycle. The tag compare then starts from registers,
//      for when the path to req_ready_o limits the clock.
// The data array is block RAM in both cases.
//
// invalidate_i drops every line from the next cycle on (the valid bits are
// flops). Use it after new code has been written to memory; a refill already
// in flight still completes.
module anv32_icache #(
    parameter int unsigned SIZE_BYTES = 8192,
    parameter int unsigned LINE_BYTES = 32,
    parameter int unsigned MEM_DW     = 64,     // memory-side beat width: 32 or 64
    parameter bit          SYNC_TAGS  = 1'b0
)(
    input  logic              clk_i,
    input  logic              rst_i,
    input  logic              invalidate_i,

    input  logic              req_valid_i,
    input  logic [31:0]       req_addr_i,
    output logic              req_ready_o,
    output logic [31:0]       rdata_o,

    output logic              mem_req_valid_o,
    input  logic              mem_req_ready_i,
    output logic [31:0]       mem_req_addr_o,
    input  logic              mem_rvalid_i,
    input  logic [MEM_DW-1:0] mem_rdata_i
);
    localparam int unsigned LINES    = SIZE_BYTES / LINE_BYTES;
    localparam int unsigned BEATS    = LINE_BYTES * 8 / MEM_DW;
    localparam int unsigned OFFSET_W = $clog2(LINE_BYTES);
    localparam int unsigned INDEX_W  = $clog2(LINES);
    localparam int unsigned TAG_W    = 32 - INDEX_W - OFFSET_W;
    localparam int unsigned BEAT_W   = $clog2(BEATS);
    localparam int unsigned BYTE_W   = $clog2(MEM_DW / 8);   // byte offset within a beat

    // synthesis translate_off
    initial begin
        if (MEM_DW != 32 && MEM_DW != 64)
            $fatal(1, "anv32_icache: MEM_DW must be 32 or 64 (got %0d)", MEM_DW);
        if (LINE_BYTES != (1 << OFFSET_W) || BEATS < 2 || BEATS > 16)
            $fatal(1, "anv32_icache: LINE_BYTES (%0d) must be a power of two of 2 to 16 beats",
                   LINE_BYTES);
        if (SIZE_BYTES != (1 << $clog2(SIZE_BYTES)) || LINES < 2)
            $fatal(1, "anv32_icache: SIZE_BYTES (%0d) must be a power of two of 2+ lines",
                   SIZE_BYTES);
    end
    // synthesis translate_on

    typedef enum logic [1:0] {IDLE, REQ, FILL} state_t;

    state_t                    state_q;
    logic [31-OFFSET_W:0]      miss_line_q;    // line address of the miss being filled
    logic [BEAT_W-1:0]         beat_q;
    logic [LINES-1:0]          valid_q;

    logic [INDEX_W-1:0]        req_index, miss_index;
    logic [TAG_W-1:0]          req_tag, miss_tag;
    logic                      lookup_hit;     // the lookup for req_addr_i is done and hit
    logic                      lookup_miss;    // the lookup for req_addr_i is done and missed
    logic                      fill_beat, fill_done;

    assign req_index  = req_addr_i[OFFSET_W +: INDEX_W];
    assign req_tag    = req_addr_i[31 -: TAG_W];
    assign miss_index = miss_line_q[INDEX_W-1:0];
    assign miss_tag   = miss_line_q[31-OFFSET_W -: TAG_W];
    assign fill_beat  = state_q == FILL && mem_rvalid_i;
    assign fill_done  = fill_beat && beat_q == BEAT_W'(BEATS - 1);

    assign req_ready_o     = lookup_hit;
    assign mem_req_valid_o = state_q == REQ;
    assign mem_req_addr_o  = {miss_line_q, {OFFSET_W{1'b0}}};

    // ---- Tags --------------------------------------------------------------
    logic [TAG_W-1:0] tag_ram [0:LINES-1];

    generate
        if (!SYNC_TAGS) begin : g_async_tags
            always_ff @(posedge clk_i) begin
                if (fill_done) tag_ram[miss_index] <= miss_tag;
            end

            assign lookup_hit  = state_q == IDLE && req_valid_i &&
                                 valid_q[req_index] && tag_ram[req_index] == req_tag;
            assign lookup_miss = state_q == IDLE && req_valid_i && !lookup_hit;
        end else begin : g_sync_tags
            // The tag and valid bit are read in the cycle a request shows up and
            // compared in the next one. lookup_q says that the request on the
            // port now is the one read last cycle: it was there and not taken,
            // and the protocol keeps a waiting request unchanged.
            logic [TAG_W-1:0] tag_q, lookup_tag_q;
            logic             valid_bit_q;
            logic             lookup_q;
            logic             tag_match;

            always_ff @(posedge clk_i) begin
                if (fill_done) tag_ram[miss_index] <= miss_tag;
                tag_q        <= tag_ram[req_index];
                valid_bit_q  <= valid_q[req_index];
                lookup_tag_q <= req_tag;
                lookup_q     <= !rst_i && !invalidate_i && state_q == IDLE &&
                                req_valid_i && !req_ready_o;
            end

            assign tag_match   = valid_bit_q && tag_q == lookup_tag_q;
            assign lookup_hit  = state_q == IDLE && lookup_q && tag_match;
            assign lookup_miss = state_q == IDLE && lookup_q && !tag_match;
        end
    endgenerate

    // ---- Data --------------------------------------------------------------
    // Read every cycle at the requested address; the word for a request
    // accepted in this cycle is on rdata_o in the next one.
    logic [MEM_DW-1:0] data_ram [0:LINES*BEATS-1];
    logic [MEM_DW-1:0] data_q;

    always_ff @(posedge clk_i) begin
        if (fill_beat) data_ram[{miss_index, beat_q}] <= mem_rdata_i;
        data_q <= data_ram[{req_index, req_addr_i[BYTE_W +: BEAT_W]}];
    end

    generate
        if (MEM_DW == 64) begin : g_word_sel
            logic word_q;
            always_ff @(posedge clk_i) word_q <= req_addr_i[2];
            assign rdata_o = word_q ? data_q[63:32] : data_q[31:0];
        end else begin : g_word
            assign rdata_o = data_q;
        end
    endgenerate

    // ---- Refill ------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q     <= IDLE;
            miss_line_q <= '0;
            beat_q      <= '0;
        end else begin
            unique case (state_q)
                IDLE: if (lookup_miss) begin
                    state_q     <= REQ;
                    miss_line_q <= req_addr_i[31:OFFSET_W];
                end
                REQ: if (mem_req_ready_i) begin
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

    always_ff @(posedge clk_i) begin
        if (rst_i || invalidate_i) valid_q <= '0;
        else if (fill_done)        valid_q[miss_index] <= 1'b1;
    end

endmodule
