module uart_top #(
    parameter int   CLK_FREQ        = 27_000_000,
    parameter int   TX_FIFO_DEPTH   = 16,
    parameter int   RX_FIFO_DEPTH   = 16,
    parameter bit   USE_TX_FIFO     = 1'b1,
    parameter bit   USE_RX_FIFO     = 1'b1,
    parameter logic IDLE_STATE_BIT  = 1'b1,
    parameter logic STOP_BIT_VALUE  = 1'b1,
    parameter logic START_BIT_VALUE = 1'b0
)(
    input  logic        clk_i,
    input  logic        rst_i,
    input  logic [31:0] baud_rate_i,

    input  logic        uart_rx_i,
    output logic        uart_tx_o,

    input  logic [7:0]  tx_data_i,
    input  logic        tx_valid_i,
    output logic        tx_ready_o,
    output logic        tx_full_o,
    output logic        tx_empty_o,
    output logic        tx_busy_o,
    output logic        tx_done_o,

    input  logic        rx_read_i,
    output logic [7:0]  rx_data_o,
    output logic        rx_valid_o,
    output logic        rx_empty_o,
    output logic        rx_full_o,
    output logic        rx_busy_o,

    input  logic        error_clear_i,
    output logic        framing_error_o,
    output logic        rx_overflow_o,
    output logic        framing_error_pulse_o,
    output logic        rx_overflow_pulse_o
);
    logic       baud_tick;
    logic       baud_x16_tick;

    logic [7:0] rx_core_data;
    logic       rx_core_valid;
    logic       rx_core_framing_error;
    logic       rx_overflow_pulse;

    logic [7:0] tx_core_data;
    logic       tx_core_start;
    logic       tx_core_ready;

    uart_baud_rate #(
        .CLK_FREQ(CLK_FREQ)
    ) u_baud_rate (
        .clk_i           (clk_i),
        .rst_i           (rst_i),
        .baud_rate_i     (baud_rate_i),
        .baud_tick_o     (baud_tick),
        .baud_x16_tick_o (baud_x16_tick)
    );

    uart_rx #(
        .IDLE_STATE_BIT  (IDLE_STATE_BIT),
        .STOP_BIT_VALUE  (STOP_BIT_VALUE),
        .START_BIT_VALUE (START_BIT_VALUE)
    ) u_uart_rx (
        .clk_i             (clk_i),
        .rst_i             (rst_i),
        .baud_x16_tick_i   (baud_x16_tick),
        .rx_i              (uart_rx_i),
        .data_o            (rx_core_data),
        .valid_o           (rx_core_valid),
        .busy_o            (rx_busy_o),
        .framing_error_o   (rx_core_framing_error)
    );

    uart_tx #(
        .IDLE_STATE_BIT (IDLE_STATE_BIT),
        .STOP_BIT       (STOP_BIT_VALUE),
        .START_BIT      (START_BIT_VALUE)
    ) u_uart_tx (
        .clk_i       (clk_i),
        .baud_tick_i (baud_tick),
        .rst_i       (rst_i),
        .data_i      (tx_core_data),
        .start_i     (tx_core_start),
        .done_o      (tx_done_o),
        .tx_o        (uart_tx_o),
        .busy_o      (tx_busy_o),
        .ready_o     (tx_core_ready)
    );

    generate
        if (USE_TX_FIFO) begin : gen_tx_fifo
            logic [7:0] tx_fifo_rdata;
            logic       tx_fifo_full;
            logic       tx_fifo_empty;
            logic       tx_fifo_wr_en;
            logic       tx_fifo_rd_en;

            assign tx_fifo_wr_en = tx_valid_i && !tx_fifo_full;
            assign tx_fifo_rd_en = tx_core_ready && !tx_fifo_empty;

            uart_fifo #(
                .DATA_WIDTH (8),
                .DEPTH      (TX_FIFO_DEPTH)
            ) u_tx_fifo (
                .clk_i    (clk_i),
                .rst_i    (rst_i),
                .wr_en_i  (tx_fifo_wr_en),
                .rd_en_i  (tx_fifo_rd_en),
                .wdata_i  (tx_data_i),
                .rdata_o  (tx_fifo_rdata),
                .full_o   (tx_fifo_full),
                .empty_o  (tx_fifo_empty),
                .level_o  ()
            );

            assign tx_core_data  = tx_fifo_rdata;
            assign tx_core_start = tx_fifo_rd_en;
            assign tx_ready_o    = !tx_fifo_full;
            assign tx_full_o     = tx_fifo_full;
            assign tx_empty_o    = tx_fifo_empty && tx_core_ready;
        end else begin : gen_tx_direct
            assign tx_core_data  = tx_data_i;
            assign tx_core_start = tx_valid_i && tx_core_ready;
            assign tx_ready_o    = tx_core_ready;
            assign tx_full_o     = !tx_core_ready;
            assign tx_empty_o    = tx_core_ready;
        end
    endgenerate

    generate
        if (USE_RX_FIFO) begin : gen_rx_fifo
            logic [7:0] rx_fifo_rdata;
            logic       rx_fifo_full;
            logic       rx_fifo_empty;
            logic       rx_fifo_can_accept;
            logic       rx_fifo_wr_en;

            assign rx_fifo_can_accept = !rx_fifo_full || (rx_read_i && !rx_fifo_empty);
            assign rx_fifo_wr_en      = rx_core_valid && rx_fifo_can_accept;
            assign rx_overflow_pulse  = rx_core_valid && !rx_fifo_can_accept;

            uart_fifo #(
                .DATA_WIDTH (8),
                .DEPTH      (RX_FIFO_DEPTH)
            ) u_rx_fifo (
                .clk_i    (clk_i),
                .rst_i    (rst_i),
                .wr_en_i  (rx_fifo_wr_en),
                .rd_en_i  (rx_read_i),
                .wdata_i  (rx_core_data),
                .rdata_o  (rx_fifo_rdata),
                .full_o   (rx_fifo_full),
                .empty_o  (rx_fifo_empty),
                .level_o  ()
            );

            assign rx_data_o  = rx_fifo_rdata;
            assign rx_valid_o = !rx_fifo_empty;
            assign rx_empty_o = rx_fifo_empty;
            assign rx_full_o  = rx_fifo_full;
        end else begin : gen_rx_hold
            logic [7:0] rx_hold_data_q;
            logic       rx_hold_full_q;
            logic       rx_hold_can_accept;

            assign rx_hold_can_accept = !rx_hold_full_q || (rx_read_i && rx_hold_full_q);
            assign rx_overflow_pulse  = rx_core_valid && !rx_hold_can_accept;

            always_ff @(posedge clk_i) begin
                if (rst_i) begin
                    rx_hold_data_q <= 8'h00;
                    rx_hold_full_q <= 1'b0;
                end else begin
                    if (rx_read_i && rx_hold_full_q) begin
                        rx_hold_full_q <= 1'b0;
                    end

                    if (rx_core_valid && rx_hold_can_accept) begin
                        rx_hold_data_q <= rx_core_data;
                        rx_hold_full_q <= 1'b1;
                    end
                end
            end

            assign rx_data_o  = rx_hold_data_q;
            assign rx_valid_o = rx_hold_full_q;
            assign rx_empty_o = !rx_hold_full_q;
            assign rx_full_o  = rx_hold_full_q;
        end
    endgenerate

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            framing_error_o       <= 1'b0;
            rx_overflow_o         <= 1'b0;
            framing_error_pulse_o <= 1'b0;
            rx_overflow_pulse_o   <= 1'b0;
        end else begin
            framing_error_pulse_o <= 1'b0;
            rx_overflow_pulse_o   <= 1'b0;

            if (error_clear_i) begin
                framing_error_o <= 1'b0;
                rx_overflow_o   <= 1'b0;
            end

            if (rx_core_framing_error) begin
                framing_error_o       <= 1'b1;
                framing_error_pulse_o <= 1'b1;
            end

            if (rx_overflow_pulse) begin
                rx_overflow_o       <= 1'b1;
                rx_overflow_pulse_o <= 1'b1;
            end
        end
    end

endmodule
