package anv32_gpio_regs_pkg;

    // Only IRQ_PENDING is implemented (one interrupt input, write 1 to clear).
    // The rest of the GPIO block is not implemented yet.
    // Implementation date of the GPIO block can be found in the ANV32 roadmap document.
    localparam logic [31:0] GPIO_DATA_OFFSET        = 32'h0000_0000;
    localparam logic [31:0] GPIO_DIR_OFFSET         = 32'h0000_0004;
    localparam logic [31:0] GPIO_OUT_SET_OFFSET     = 32'h0000_0008;
    localparam logic [31:0] GPIO_OUT_CLR_OFFSET     = 32'h0000_000C;
    localparam logic [31:0] GPIO_IRQ_PENDING_OFFSET = 32'h0000_0010;
    localparam logic [31:0] GPIO_IRQ_ENABLE_OFFSET  = 32'h0000_0014;

endpackage
