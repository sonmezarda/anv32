// GPIO0. For now only the interrupt input exists: a rising edge on irq_i sets
// IRQ_PENDING, which drives the external interrupt until software writes 1 to
// clear it. The data/direction/enable registers read as zero.
module gpio_periph
    import anv32_bus_pkg::*;
    import anv32_gpio_regs_pkg::*;
(
    input  logic     clk_i,
    input  logic     rst_i,

    input  bus_req_t req_i,
    output bus_rsp_t rsp_o,

    input  logic     irq_i,     // asynchronous interrupt input
    output logic     irq_o      // IRQ_PENDING
);
    localparam int unsigned NREGS       = 6;
    localparam int unsigned PENDING_IDX = int'(GPIO_IRQ_PENDING_OFFSET[9:2]);

    logic [NREGS-1:0][31:0] regs;
    logic [NREGS-1:0]       wr;
    logic                   irq_sync1_q, irq_sync2_q, irq_prev_q;
    logic                   pending_q;

    // GPIO is a fast (combinational, zero-wait) read peripheral.
    anv32_bus_regs #(.NREGS(NREGS), .FAST(1'b1)) bus_regs (
        .clk_i  (clk_i),
        .rst_i  (rst_i),
        .req_i  (req_i),
        .rsp_o  (rsp_o),
        .rdata_i(regs),
        .wr_o   (wr),
        .rd_o   (),
        .wdata_o()
    );

    always_comb begin
        regs                 = '0;
        regs[PENDING_IDX][0] = pending_q;
    end

    // Two-flop synchronizer, then a rising-edge detector. A new edge wins over
    // a clear in the same cycle, so no interrupt is lost. IRQ_PENDING is
    // write-1-to-clear, so it looks at the raw byte 0 of the write rather than
    // the merged value (a write to another byte must not clear it).
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            irq_sync1_q <= 1'b0;
            irq_sync2_q <= 1'b0;
            irq_prev_q  <= 1'b0;
            pending_q   <= 1'b0;
        end else begin
            irq_sync1_q <= irq_i;
            irq_sync2_q <= irq_sync1_q;
            irq_prev_q  <= irq_sync2_q;
            if (irq_sync2_q && !irq_prev_q)                          pending_q <= 1'b1;
            else if (wr[PENDING_IDX] && req_i.we[0] && req_i.wdata[0]) pending_q <= 1'b0;
        end
    end

    assign irq_o = pending_q;

endmodule
