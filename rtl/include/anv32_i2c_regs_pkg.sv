package anv32_i2c_regs_pkg;

    localparam logic [31:0] I2C_CMD_OFFSET      = 32'h0000_0000;
    localparam logic [31:0] I2C_STATUS_OFFSET   = 32'h0000_0004;
    localparam logic [31:0] I2C_RXDATA_OFFSET   = 32'h0000_0008;
    localparam logic [31:0] I2C_CTRL_OFFSET     = 32'h0000_000C;
    localparam logic [31:0] I2C_SCL_LOW_OFFSET  = 32'h0000_0010;
    localparam logic [31:0] I2C_SCL_HIGH_OFFSET = 32'h0000_0014;
    localparam logic [31:0] I2C_TIMEOUT_OFFSET  = 32'h0000_0018;

endpackage
