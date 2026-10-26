// UART0 bus slave around uart_top.
//   TXDATA  write pushes byte 0 into the TX FIFO
//   STATUS  read-only flags
//   BAUD    baud rate in bit/s, read/write
//   ERROR   sticky error flags, write 1 to bit 0 to clear them
//   RXDATA  read pops the RX FIFO
module uart_periph
    import anv32_bus_pkg::*;
    import anv32_uart_regs_pkg::*;
#(
    parameter int unsigned CLK_FREQ     = 27_000_000,
    parameter int unsigned DEFAULT_BAUD = 115_200
)(
    input  logic     clk_i,
    input  logic     rst_i,

    input  bus_req_t req_i,
    output bus_rsp_t rsp_o,

    input  logic     uart_rx_i,
    output logic     uart_tx_o
);
    localparam int unsigned NREGS      = 5;
    localparam int unsigned TXDATA_IDX = int'(UART_TXDATA_OFFSET[9:2]);
    localparam int unsigned STATUS_IDX = int'(UART_STATUS_OFFSET[9:2]);
    localparam int unsigned BAUD_IDX   = int'(UART_BAUD_OFFSET[9:2]);
    localparam int unsigned ERROR_IDX  = int'(UART_ERROR_OFFSET[9:2]);
    localparam int unsigned RXDATA_IDX = int'(UART_RXDATA_OFFSET[9:2]);

    logic [NREGS-1:0][31:0] regs;
    logic [NREGS-1:0]       wr;
    logic [NREGS-1:0]       rd;
    logic [31:0]            wdata;
    logic [31:0]            baud_q;

    logic       tx_ready, tx_full, tx_empty, tx_busy, tx_done;
    logic [7:0] rx_data;
    logic       rx_valid, rx_empty, rx_full, rx_busy;
    logic       framing_error, rx_overflow;

    anv32_bus_regs #(.NREGS(NREGS)) bus_regs (
        .clk_i  (clk_i),
        .rst_i  (rst_i),
        .req_i  (req_i),
        .rsp_o  (rsp_o),
        .rdata_i(regs),
        .wr_o   (wr),
        .rd_o   (rd),
        .wdata_o(wdata)
    );

    always_comb begin
        regs = '0;
        regs[STATUS_IDX][UART_STATUS_TX_READY] = tx_ready;
        regs[STATUS_IDX][UART_STATUS_TX_EMPTY] = tx_empty;
        regs[STATUS_IDX][UART_STATUS_TX_BUSY]  = tx_busy;
        regs[STATUS_IDX][UART_STATUS_TX_DONE]  = tx_done;
        regs[STATUS_IDX][UART_STATUS_RX_VALID] = rx_valid;
        regs[STATUS_IDX][UART_STATUS_RX_EMPTY] = rx_empty;
        regs[STATUS_IDX][UART_STATUS_RX_FULL]  = rx_full;
        regs[STATUS_IDX][UART_STATUS_RX_BUSY]  = rx_busy;
        regs[BAUD_IDX]                         = baud_q;
        regs[ERROR_IDX][UART_ERROR_FRAMING]    = framing_error;
        regs[ERROR_IDX][UART_ERROR_OVERFLOW]   = rx_overflow;
        regs[RXDATA_IDX][7:0]                  = rx_data;
    end

    always_ff @(posedge clk_i) begin
        if (rst_i)             baud_q <= 32'(DEFAULT_BAUD);
        else if (wr[BAUD_IDX]) baud_q <= wdata;
    end

    uart_top #(
        .CLK_FREQ      (CLK_FREQ),
        .TX_FIFO_DEPTH (16),
        .RX_FIFO_DEPTH (16),
        .USE_TX_FIFO   (1'b1),
        .USE_RX_FIFO   (1'b1)
    ) uart (
        .clk_i                  (clk_i),
        .rst_i                  (rst_i),
        .baud_rate_i            (baud_q),
        .uart_rx_i              (uart_rx_i),
        .uart_tx_o              (uart_tx_o),
        .tx_data_i              (wdata[7:0]),
        .tx_valid_i             (wr[TXDATA_IDX]),
        .tx_ready_o             (tx_ready),
        .tx_full_o              (tx_full),
        .tx_empty_o             (tx_empty),
        .tx_busy_o              (tx_busy),
        .tx_done_o              (tx_done),
        .rx_read_i              (rd[RXDATA_IDX]),
        .rx_data_o              (rx_data),
        .rx_valid_o             (rx_valid),
        .rx_empty_o             (rx_empty),
        .rx_full_o              (rx_full),
        .rx_busy_o              (rx_busy),
        // ERROR is write-1-to-clear: use the raw byte 0 of the write
        .error_clear_i          (wr[ERROR_IDX] && req_i.we[0] && req_i.wdata[0]),
        .framing_error_o        (framing_error),
        .rx_overflow_o          (rx_overflow),
        .framing_error_pulse_o  (),
        .rx_overflow_pulse_o    ()
    );

endmodule
