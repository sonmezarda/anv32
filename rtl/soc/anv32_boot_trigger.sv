// Lets a host reset the SoC into the bootloader over UART, without the reset
// button: the USB-UART's DTR line does not reach the FPGA on the Tang Nano 9K.
//
// A receiver of its own, at a fixed BAUD and independent of UART0's
// programmable rate, watches the RX pin for MAGIC (8 bytes). When the last
// byte arrives it pulses reset_req_o, which resets the whole SoC, and sets
// boot_req_o, which the bootloader reads (SYSCTRL STATUS.BOOT_REQ) to tell
// this reset from a power-on or button reset. Software clears it with clear_i.
//
// The SoC reset does not reach this block, so boot_req_o survives it; only
// the reset button (rst_n_i) clears everything here.
module anv32_boot_trigger #(
    parameter int unsigned CLK_FREQ = 27_000_000,
    parameter int unsigned BAUD     = 115_200
)(
    input  logic clk_i,
    input  logic rst_n_i,      // reset button, asynchronous
    input  logic rx_i,

    input  logic clear_i,
    output logic reset_req_o,
    output logic boot_req_o
);
    // ESC "ANV32BL". The first byte appears only once, so a mismatch can
    // restart the match without backtracking.
    localparam logic [7:0][7:0] MAGIC = {8'h4C, 8'h42, 8'h32, 8'h33,  // index 7 .. 0
                                         8'h56, 8'h4E, 8'h41, 8'h1B};

    logic       rst_q = 1'b1, rst_sync_q = 1'b1;
    logic       x16_tick;
    logic [7:0] rx_data;
    logic       rx_valid;
    logic [2:0] match_q;
    logic       boot_req_q  = 1'b0;
    logic       reset_req_q = 1'b0;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) {rst_q, rst_sync_q} <= 2'b11;
        else          {rst_q, rst_sync_q} <= {rst_sync_q, 1'b0};
    end

    uart_baud_rate #(.CLK_FREQ(CLK_FREQ)) baud (
        .clk_i          (clk_i),
        .rst_i          (rst_q),
        .baud_rate_i    (32'(BAUD)),
        .baud_tick_o    (),
        .baud_x16_tick_o(x16_tick)
    );

    uart_rx rx (
        .clk_i          (clk_i),
        .rst_i          (rst_q),
        .baud_x16_tick_i(x16_tick),
        .rx_i           (rx_i),
        .data_o         (rx_data),
        .valid_o        (rx_valid),
        .busy_o         (),
        .framing_error_o()
    );

    always_ff @(posedge clk_i) begin
        reset_req_q <= 1'b0;
        if (rst_q) begin
            match_q    <= '0;
            boot_req_q <= 1'b0;
        end else begin
            if (clear_i) boot_req_q <= 1'b0;
            if (rx_valid) begin
                if (rx_data == MAGIC[match_q]) begin
                    match_q <= match_q + 3'd1;     // wraps to 0 after the last byte
                    if (match_q == 3'd7) begin
                        reset_req_q <= 1'b1;
                        boot_req_q  <= 1'b1;
                    end
                end else begin
                    match_q <= (rx_data == MAGIC[0]) ? 3'd1 : 3'd0;
                end
            end
        end
    end

    assign reset_req_o = reset_req_q;
    assign boot_req_o  = boot_req_q;

endmodule
