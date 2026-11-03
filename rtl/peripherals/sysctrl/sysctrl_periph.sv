// SYSCTRL: system registers.
//   LED       read/write, drives the board LEDs
//   STATUS    bit 0 BOOT_REQ: this reset came from the UART boot trigger
//             (anv32_boot_trigger); write 1 to clear it. Other bits read zero.
// BOARD_ID and BUILD_ID read as zero for now.
module sysctrl_periph
    import anv32_bus_pkg::*;
    import anv32_sysctrl_regs_pkg::*;
(
    input  logic        clk_i,
    input  logic        rst_i,

    input  bus_req_t    req_i,
    output bus_rsp_t    rsp_o,

    output logic [31:0] led_o,
    input  logic        boot_req_i,
    output logic        boot_req_clr_o
);
    localparam int unsigned NREGS      = 4;
    localparam int unsigned LED_IDX    = int'(SYSCTRL_LED_OFFSET[9:2]);
    localparam int unsigned STATUS_IDX = int'(SYSCTRL_STATUS_OFFSET[9:2]);

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
        regs[STATUS_IDX][0] = boot_req_i;
    end

    always_ff @(posedge clk_i) begin
        if (rst_i)            led_q <= '0;
        else if (wr[LED_IDX]) led_q <= wdata;
    end

    assign led_o          = led_q;
    assign boot_req_clr_o = wr[STATUS_IDX] && wdata[0];

endmodule
