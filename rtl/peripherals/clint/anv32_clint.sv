// Core-local interruptor (CLINT): the RISC-V machine timer and machine
// software interrupt for one hart. The register layout is the SiFive CLINT /
// RISC-V ACLINT one, so FreeRTOS, OpenSBI and Linux drivers work unchanged:
//
//   0x0000  msip           bit 0 drives the machine software interrupt
//   0x4000  mtimecmp[31:0]
//   0x4004  mtimecmp[63:32]
//   0xBFF8  mtime[31:0]
//   0xBFFC  mtime[63:32]
//
// Other offsets in the 64 KiB aperture read as zero and ignore writes.
//
// mtime counts at MTIME_FREQ (one tick every CLK_FREQ / MTIME_FREQ clocks) and
// is writable. The timer interrupt is a level: it stays high while
// mtime >= mtimecmp, and software clears it by moving mtimecmp forward.
// mtimecmp resets to all ones, so nothing fires before software programs it.
// Reads are registered like every slow slave (fast = 0).
module anv32_clint
    import anv32_bus_pkg::*;
#(
    parameter int unsigned CLK_FREQ   = 27_000_000,
    parameter int unsigned MTIME_FREQ = 1_000_000   // must divide CLK_FREQ
)(
    input  logic     clk_i,
    input  logic     rst_i,

    input  bus_req_t req_i,
    output bus_rsp_t rsp_o,

    output logic     timer_irq_o,   // MTIP
    output logic     sw_irq_o       // MSIP
);
    localparam int unsigned PRESCALE = CLK_FREQ / MTIME_FREQ;

    localparam logic [13:0] W_MSIP        = 14'h0000;   // word index = offset[15:2]
    localparam logic [13:0] W_MTIMECMP_LO = 14'h1000;   // 0x4000
    localparam logic [13:0] W_MTIMECMP_HI = 14'h1001;   // 0x4004
    localparam logic [13:0] W_MTIME_LO    = 14'h2FFE;   // 0xBFF8
    localparam logic [13:0] W_MTIME_HI    = 14'h2FFF;   // 0xBFFC

    // synthesis translate_off
    initial begin
        if (MTIME_FREQ == 0 || MTIME_FREQ > CLK_FREQ || CLK_FREQ % MTIME_FREQ != 0)
            $fatal(1, "anv32_clint: CLK_FREQ (%0d) must be a multiple of MTIME_FREQ (%0d)",
                   CLK_FREQ, MTIME_FREQ);
    end
    // synthesis translate_on

    logic [63:0] mtime_q, mtime_d;
    logic [63:0] mtimecmp_q, mtimecmp_d;
    logic        msip_q, msip_d;
    logic        timer_irq_q;
    logic [31:0] rdata_q;
    logic [31:0] cur;
    logic        tick;
    logic        wr;
    logic [13:0] word;

    assign word = req_i.addr[15:2];
    assign wr   = req_i.valid && (req_i.we != 4'b0000);

    // ---- mtime prescaler ------------------------------------------------------
    generate
        if (PRESCALE > 1) begin : g_prescale
            localparam int unsigned PRE_W = $clog2(PRESCALE);
            logic [PRE_W-1:0] pre_q;

            assign tick = (pre_q == PRE_W'(PRESCALE - 1));

            always_ff @(posedge clk_i) begin
                if (rst_i || tick) pre_q <= '0;
                else               pre_q <= pre_q + 1'b1;
            end
        end else begin : g_every_clock
            assign tick = 1'b1;
        end
    endgenerate

    // ---- register file --------------------------------------------------------
    function automatic logic [31:0] merge(input logic [31:0] old,
                                          input logic [31:0] value,
                                          input logic [3:0]  we);
        for (int b = 0; b < 4; b++) begin
            merge[b*8 +: 8] = we[b] ? value[b*8 +: 8] : old[b*8 +: 8];
        end
    endfunction

    always_comb begin
        unique case (word)
            W_MSIP:        cur = {31'b0, msip_q};
            W_MTIMECMP_LO: cur = mtimecmp_q[31:0];
            W_MTIMECMP_HI: cur = mtimecmp_q[63:32];
            W_MTIME_LO:    cur = mtime_q[31:0];
            W_MTIME_HI:    cur = mtime_q[63:32];
            default:       cur = '0;
        endcase
    end

    // A write to mtime replaces that cycle's increment, like the mcycle CSR.
    always_comb begin
        msip_d     = msip_q;
        mtimecmp_d = mtimecmp_q;
        mtime_d    = mtime_q + {63'b0, tick};

        if (wr) begin
            unique case (word)
                W_MSIP:        msip_d            = req_i.we[0] ? req_i.wdata[0] : msip_q;
                W_MTIMECMP_LO: mtimecmp_d[31:0]  = merge(mtimecmp_q[31:0],  req_i.wdata, req_i.we);
                W_MTIMECMP_HI: mtimecmp_d[63:32] = merge(mtimecmp_q[63:32], req_i.wdata, req_i.we);
                W_MTIME_LO:    mtime_d[31:0]     = merge(mtime_q[31:0],     req_i.wdata, req_i.we);
                W_MTIME_HI:    mtime_d[63:32]    = merge(mtime_q[63:32],    req_i.wdata, req_i.we);
                default: ;
            endcase
        end
    end

    // The interrupt is registered from the values the counters take this
    // cycle, so it changes together with them: right after the store that
    // moves mtimecmp lands, MTIP is already low and an mret straight after it
    // cannot take a stale timer interrupt.
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            mtime_q     <= '0;
            mtimecmp_q  <= '1;
            msip_q      <= 1'b0;
            timer_irq_q <= 1'b0;
            rdata_q     <= '0;
        end else begin
            mtime_q     <= mtime_d;
            mtimecmp_q  <= mtimecmp_d;
            msip_q      <= msip_d;
            timer_irq_q <= (mtime_d >= mtimecmp_d);
            if (req_i.valid) rdata_q <= cur;
        end
    end

    assign timer_irq_o = timer_irq_q;
    assign sw_irq_o    = msip_q;

    assign rsp_o.ready = 1'b1;
    assign rsp_o.fast  = 1'b0;      // slow: registered at the core boundary
    assign rsp_o.rdata = rdata_q;

endmodule
