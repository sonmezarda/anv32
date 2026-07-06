package anv32_uart_regs_pkg;

    localparam logic [31:0] UART_TXDATA_OFFSET = 32'h0000_0000;
    localparam logic [31:0] UART_STATUS_OFFSET = 32'h0000_0004;
    localparam logic [31:0] UART_BAUD_OFFSET   = 32'h0000_0008;
    localparam logic [31:0] UART_ERROR_OFFSET  = 32'h0000_000C;
    localparam logic [31:0] UART_RXDATA_OFFSET = 32'h0000_0010;

    localparam int unsigned UART_STATUS_TX_READY = 0;
    localparam int unsigned UART_STATUS_TX_EMPTY = 1;
    localparam int unsigned UART_STATUS_TX_BUSY  = 2;
    localparam int unsigned UART_STATUS_TX_DONE  = 3;
    localparam int unsigned UART_STATUS_RX_VALID = 4;
    localparam int unsigned UART_STATUS_RX_EMPTY = 5;
    localparam int unsigned UART_STATUS_RX_FULL  = 6;
    localparam int unsigned UART_STATUS_RX_BUSY  = 7;

endpackage
