// AXI3 master for one cache: turns the memory side of anv32_icache or
// anv32_dcache into an AXI3 port, such as a Zynq-7000 S_AXI_HP port.
//
// Reads: a line fill becomes one INCR burst of BEATS beats (ARLEN = BEATS - 1,
// ARSIZE = the beat width). RREADY is always high, as the caches take every
// beat.
//
// Writes (HAS_WRITE): a buffered store becomes one single-beat write with
// byte strobes. AXI takes the address (AW) and the data (W) separately and
// in either order, so each stays up until it is taken, and the store leaves
// the cache once both are. BREADY is always high; every response is passed
// on as wr_done_o. Without HAS_WRITE the write channels stay idle.
//
// addr_offset_i is added to every address: the caches see external RAM where
// the core does (0x8000_0000 in the SoC memory map), while the buffer the
// core runs from can sit anywhere in DDR.
//
// Every transfer uses ID. Error responses (RRESP, BRESP) are not handled yet.
module anv32_cache_axi #(
    parameter int unsigned    MEM_DW    = 64,    // beat width: 32 or 64
    parameter int unsigned    BEATS     = 8,     // beats per line fill, 2 to 16
    parameter int unsigned    ID_W      = 6,
    parameter logic [ID_W-1:0] ID       = '0,
    parameter bit             HAS_WRITE = 1'b1
)(
    input  logic                clk_i,
    input  logic                rst_i,
    input  logic [31:0]         addr_offset_i,

    // Cache side (mem_* ports of anv32_icache / anv32_dcache)
    input  logic                rd_valid_i,
    output logic                rd_ready_o,
    input  logic [31:0]         rd_addr_i,
    output logic                rvalid_o,
    output logic [MEM_DW-1:0]   rdata_o,
    input  logic                wr_valid_i,
    output logic                wr_ready_o,
    input  logic [31:0]         wr_addr_i,
    input  logic [MEM_DW-1:0]   wr_data_i,
    input  logic [MEM_DW/8-1:0] wr_strb_i,
    output logic                wr_done_o,

    // AXI3 master
    output logic [ID_W-1:0]     m_axi_arid,
    output logic [31:0]         m_axi_araddr,
    output logic [3:0]          m_axi_arlen,
    output logic [2:0]          m_axi_arsize,
    output logic [1:0]          m_axi_arburst,
    output logic [1:0]          m_axi_arlock,
    output logic [3:0]          m_axi_arcache,
    output logic [2:0]          m_axi_arprot,
    output logic [3:0]          m_axi_arqos,
    output logic                m_axi_arvalid,
    input  logic                m_axi_arready,
    input  logic [ID_W-1:0]     m_axi_rid,
    input  logic [MEM_DW-1:0]   m_axi_rdata,
    input  logic [1:0]          m_axi_rresp,
    input  logic                m_axi_rlast,
    input  logic                m_axi_rvalid,
    output logic                m_axi_rready,

    output logic [ID_W-1:0]     m_axi_awid,
    output logic [31:0]         m_axi_awaddr,
    output logic [3:0]          m_axi_awlen,
    output logic [2:0]          m_axi_awsize,
    output logic [1:0]          m_axi_awburst,
    output logic [1:0]          m_axi_awlock,
    output logic [3:0]          m_axi_awcache,
    output logic [2:0]          m_axi_awprot,
    output logic [3:0]          m_axi_awqos,
    output logic                m_axi_awvalid,
    input  logic                m_axi_awready,
    output logic [ID_W-1:0]     m_axi_wid,
    output logic [MEM_DW-1:0]   m_axi_wdata,
    output logic [MEM_DW/8-1:0] m_axi_wstrb,
    output logic                m_axi_wlast,
    output logic                m_axi_wvalid,
    input  logic                m_axi_wready,
    input  logic [ID_W-1:0]     m_axi_bid,
    input  logic [1:0]          m_axi_bresp,
    input  logic                m_axi_bvalid,
    output logic                m_axi_bready
);
    localparam logic [2:0] SIZE  = 3'($clog2(MEM_DW / 8));
    localparam logic [1:0] INCR  = 2'b01;
    // Normal non-cacheable bufferable memory, unprivileged secure data access
    localparam logic [3:0] CACHE = 4'b0011;

    // synthesis translate_off
    initial begin
        if (MEM_DW != 32 && MEM_DW != 64)
            $fatal(1, "anv32_cache_axi: MEM_DW must be 32 or 64 (got %0d)", MEM_DW);
        if (BEATS < 2 || BEATS > 16)
            $fatal(1, "anv32_cache_axi: BEATS (%0d) must be 2 to 16 for AXI3", BEATS);
    end
    // synthesis translate_on

    // ---- Reads -------------------------------------------------------------
    assign m_axi_arid    = ID;
    assign m_axi_araddr  = rd_addr_i + addr_offset_i;
    assign m_axi_arlen   = 4'(BEATS - 1);
    assign m_axi_arsize  = SIZE;
    assign m_axi_arburst = INCR;
    assign m_axi_arlock  = 2'b00;
    assign m_axi_arcache = CACHE;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arqos   = 4'b0000;
    assign m_axi_arvalid = rd_valid_i;
    assign rd_ready_o    = m_axi_arready;

    assign rvalid_o      = m_axi_rvalid;
    assign rdata_o       = m_axi_rdata;
    assign m_axi_rready  = 1'b1;

    // ---- Writes ------------------------------------------------------------
    assign m_axi_awid    = ID;
    assign m_axi_awaddr  = wr_addr_i + addr_offset_i;
    assign m_axi_awlen   = 4'd0;
    assign m_axi_awsize  = SIZE;
    assign m_axi_awburst = INCR;
    assign m_axi_awlock  = 2'b00;
    assign m_axi_awcache = CACHE;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awqos   = 4'b0000;
    assign m_axi_wid     = ID;
    assign m_axi_wdata   = wr_data_i;
    assign m_axi_wstrb   = wr_strb_i;
    assign m_axi_wlast   = 1'b1;
    assign m_axi_bready  = 1'b1;

    generate
        if (HAS_WRITE) begin : g_write
            // Set once AW or W of the store at the head of the buffer is taken
            logic aw_done_q, w_done_q;
            logic aw_fire, w_fire;

            assign m_axi_awvalid = wr_valid_i && !aw_done_q;
            assign m_axi_wvalid  = wr_valid_i && !w_done_q;
            assign aw_fire       = m_axi_awvalid && m_axi_awready;
            assign w_fire        = m_axi_wvalid && m_axi_wready;
            assign wr_ready_o    = wr_valid_i && (aw_done_q || aw_fire) && (w_done_q || w_fire);
            assign wr_done_o     = m_axi_bvalid;

            always_ff @(posedge clk_i) begin
                if (rst_i || wr_ready_o) begin
                    aw_done_q <= 1'b0;
                    w_done_q  <= 1'b0;
                end else begin
                    if (aw_fire) aw_done_q <= 1'b1;
                    if (w_fire)  w_done_q  <= 1'b1;
                end
            end
        end else begin : g_no_write
            assign m_axi_awvalid = 1'b0;
            assign m_axi_wvalid  = 1'b0;
            assign wr_ready_o    = 1'b0;
            assign wr_done_o     = 1'b0;
        end
    endgenerate

endmodule
