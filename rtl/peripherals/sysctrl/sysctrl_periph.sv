// SYSCTRL: system registers. Only the LED register is implemented; STATUS,
// BOARD_ID and BUILD_ID read as zero for now.
module sysctrl_periph
    import anv32_bus_pkg::*;
    import anv32_sysctrl_regs_pkg::*;
(
    input  logic        clk_i,
    input  logic        rst_i,

    input  bus_req_t    req_i,
    output bus_rsp_t    rsp_o,

    output logic [31:0] led_o
);
    localparam int unsigned NREGS   = 4;
    localparam int unsigned LED_IDX = int'(SYSCTRL_LED_OFFSET[9:2]);

    logic [NREGS-1:0][31:0] regs;
    logic [NREGS-1:0]       wr;
    logic [31:0]            wdata;
    logic [31:0]            led_q;

    anv32_bus_regs #(.NREGS(NREGS)) bus_regs (
        .clk_i  (clk_i),
        .rst_i  (rst_i),
        .req_i  (req_i),
        .rsp_o  (rsp_o),
        .rdata_i(regs),
        .wr_o   (wr),
        .rd_o   (),
        .wdata_o(wdata)
    );

    always_comb begin
        regs          = '0;
        regs[LED_IDX] = led_q;
    end

    always_ff @(posedge clk_i) begin
        if (rst_i)            led_q <= '0;
        else if (wr[LED_IDX]) led_q <= wdata;
    end

    assign led_o = led_q;

endmodule
