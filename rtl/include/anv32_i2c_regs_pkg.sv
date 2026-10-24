package anv32_i2c_regs_pkg;

    localparam logic [31:0] I2C_CMD_OFFSET      = 32'h0000_0000;
    localparam logic [31:0] I2C_STATUS_OFFSET   = 32'h0000_0004;
    localparam logic [31:0] I2C_RXDATA_OFFSET   = 32'h0000_0008;
    localparam logic [31:0] I2C_CTRL_OFFSET     = 32'h0000_000C;
    // Not implemented yet: timing is still set by i2c_periph parameters.
    localparam logic [31:0] I2C_SCL_LOW_OFFSET  = 32'h0000_0010;
    localparam logic [31:0] I2C_SCL_HIGH_OFFSET = 32'h0000_0014;
    localparam logic [31:0] I2C_TIMEOUT_OFFSET  = 32'h0000_0018;

    // CMD fields
    localparam logic [2:0]  I2C_CMD_OP_WRITE    = 3'd0;
    localparam logic [2:0]  I2C_CMD_OP_READ     = 3'd1;
    localparam logic [2:0]  I2C_CMD_OP_RECOVER  = 3'd2;
    localparam int unsigned I2C_CMD_START_BIT   = 3;
    localparam int unsigned I2C_CMD_STOP_BIT    = 4;
    localparam int unsigned I2C_CMD_ACK_BIT     = 5;
    localparam int unsigned I2C_CMD_DATA_LSB    = 8;

    localparam int unsigned I2C_CTRL_CLEAR_BIT  = 0;
    localparam int unsigned I2C_CTRL_IRQ_EN_BIT = 1;

    localparam int unsigned I2C_STATUS_BUSY_BIT      = 0;
    localparam int unsigned I2C_STATUS_CMD_READY_BIT = 1;
    localparam int unsigned I2C_STATUS_RX_VALID_BIT  = 2;
    localparam int unsigned I2C_STATUS_DONE_BIT      = 3;
    localparam int unsigned I2C_STATUS_BUS_OWNED_BIT = 4;
    localparam int unsigned I2C_STATUS_BUS_FREE_BIT  = 5;
    localparam int unsigned I2C_STATUS_SDA_BIT       = 6;
    localparam int unsigned I2C_STATUS_SCL_BIT       = 7;
    localparam int unsigned I2C_STATUS_NACK_BIT      = 16;
    localparam int unsigned I2C_STATUS_ARB_LOST_BIT  = 17;
    localparam int unsigned I2C_STATUS_TIMEOUT_BIT   = 18;
    localparam int unsigned I2C_STATUS_BUS_BUSY_BIT  = 19;
    localparam int unsigned I2C_STATUS_RX_OVF_BIT    = 20;
    localparam int unsigned I2C_STATUS_CMD_OVF_BIT   = 21;
    localparam int unsigned I2C_STATUS_ILLEGAL_BIT   = 22;
    localparam int unsigned I2C_STATUS_REC_FAIL_BIT  = 23;

endpackage
