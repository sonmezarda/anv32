package anv32_nn_regs_pkg;

    localparam logic [31:0] NN_CONTROL_OFFSET         = 32'h0000_0000;
    localparam logic [31:0] NN_STATUS_OFFSET          = 32'h0000_0004;
    localparam logic [31:0] NN_INPUT_BASE_OFFSET      = 32'h0000_0008;
    localparam logic [31:0] NN_WEIGHT_BASE_OFFSET     = 32'h0000_000C;
    localparam logic [31:0] NN_BIAS_BASE_OFFSET       = 32'h0000_0010;
    localparam logic [31:0] NN_OUTPUT_BASE_OFFSET     = 32'h0000_0014;
    localparam logic [31:0] NN_INPUT_LEN_WORDS_OFFSET = 32'h0000_0018;
    localparam logic [31:0] NN_OUTPUT_COUNT_OFFSET    = 32'h0000_001C;
    localparam logic [31:0] NN_CONFIG_OFFSET          = 32'h0000_0020;
    localparam logic [31:0] NN_RESULT_ARGMAX_OFFSET   = 32'h0000_0024;
    localparam logic [31:0] NN_BEST_SCORE_OFFSET      = 32'h0000_0028;
    localparam logic [31:0] NN_CYCLE_COUNT_OFFSET     = 32'h0000_002C;

    localparam int unsigned NN_STATUS_BUSY_BIT       = 0;
    localparam int unsigned NN_STATUS_DONE_BIT       = 1;
    localparam int unsigned NN_STATUS_ERROR_BIT      = 2;
    localparam int unsigned NN_STATUS_IRQ_ENABLE_BIT = 3;
    localparam int unsigned NN_STATUS_BEST_VALID_BIT = 4;

    localparam int unsigned NN_CONTROL_START_BIT     = 0;
    localparam int unsigned NN_CONTROL_CLEAR_BIT     = 1;

endpackage
