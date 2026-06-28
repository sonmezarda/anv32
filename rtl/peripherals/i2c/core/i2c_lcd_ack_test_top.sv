module i2c_lcd_ack_test_top #(
    parameter int CLK_FREQ          = 27_000_000,
    parameter int SCL_HALF_PERIOD   = CLK_FREQ / 200_000,
    parameter int START_DELAY_CYCLES = CLK_FREQ / 10,
    parameter int RETRY_CYCLES       = CLK_FREQ,
    parameter logic [6:0] LCD_ADDR   = 7'h27
)(
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic gpio_irq_i,
    input  logic uart_rx_i,
    inout  logic i2c_sda_io,
    inout  logic i2c_scl_io,
    output logic uart_tx_o,
    output logic [3:0] debug_leds
);

    logic                 rst_i;
    logic [31:0]          scl_div_cnt_q;
    logic                 scl_tick;
    logic [31:0]          retry_cnt_q;
    logic                 start_req_q;
    logic                 i2c_busy;
    logic                 i2c_done;
    logic                 i2c_nack;
    logic                 i2c_arbitration_lost;
    logic                 ack_seen_q;
    logic                 nack_seen_q;
    logic                 heartbeat_q;
    logic [23:0]          heartbeat_cnt_q;

    assign rst_i = ~rst_n_i;

    assign uart_tx_o = 1'b1;

    always_ff @(posedge clk_i) begin
        if(rst_i) begin
            scl_div_cnt_q <= '0;
            scl_tick      <= 1'b0;
        end else begin
            if(scl_div_cnt_q == (SCL_HALF_PERIOD - 1)) begin
                scl_div_cnt_q <= '0;
                scl_tick      <= 1'b1;
            end else begin
                scl_div_cnt_q <= scl_div_cnt_q + 32'd1;
                scl_tick      <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if(rst_i) begin
            retry_cnt_q    <= START_DELAY_CYCLES;
            start_req_q    <= 1'b0;
            ack_seen_q     <= 1'b0;
            nack_seen_q    <= 1'b0;
            heartbeat_q    <= 1'b0;
            heartbeat_cnt_q <= '0;
        end else begin
            heartbeat_cnt_q <= heartbeat_cnt_q + 24'd1;
            if(heartbeat_cnt_q == 24'd0) begin
                heartbeat_q <= ~heartbeat_q;
            end

            if(i2c_busy) begin
                start_req_q <= 1'b0;
            end else if(i2c_done) begin
                ack_seen_q  <= ~i2c_nack;
                nack_seen_q <= i2c_nack;
                retry_cnt_q <= RETRY_CYCLES;
            end else begin
                if(retry_cnt_q == 32'd0) begin
                    start_req_q <= 1'b1;
                end else begin
                    retry_cnt_q <= retry_cnt_q - 32'd1;
                end
            end
        end
    end

    i2c_byte_master u_i2c_byte_master(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .start_i(start_req_q),
        .scl_tick_i(scl_tick),
        .start_en_i(1'b1),
        .stop_en_i(1'b1),
        .tx_byte_i({LCD_ADDR, 1'b0}),
        .sda_io(i2c_sda_io),
        .scl_io(i2c_scl_io),
        .busy_o(i2c_busy),
        .done_o(i2c_done),
        .nack_error_o(i2c_nack),
        .arbitration_lost_o(i2c_arbitration_lost)
    );

    assign debug_leds[0] = ~i2c_busy;
    assign debug_leds[1] = ~ack_seen_q;
    assign debug_leds[2] = ~(nack_seen_q || i2c_arbitration_lost);
    assign debug_leds[3] = ~heartbeat_q;

endmodule
