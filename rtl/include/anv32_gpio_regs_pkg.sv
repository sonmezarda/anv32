package anv32_gpio_regs_pkg;

    localparam logic [31:0] GPIO_DATA_OFFSET        = 32'h0000_0000;
    localparam logic [31:0] GPIO_DIR_OFFSET         = 32'h0000_0004;
    localparam logic [31:0] GPIO_OUT_SET_OFFSET     = 32'h0000_0008;
    localparam logic [31:0] GPIO_OUT_CLR_OFFSET     = 32'h0000_000C;
    localparam logic [31:0] GPIO_IRQ_PENDING_OFFSET = 32'h0000_0010;
    localparam logic [31:0] GPIO_IRQ_ENABLE_OFFSET  = 32'h0000_0014;

endpackage
