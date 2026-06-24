module anv32_mul_comb
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
(
    input  logic            clk_i,
    input  logic            rst_i,
    input  op_e             op_i,
    input  logic [XLEN-1:0] a_i,
    input  logic [XLEN-1:0] b_i,
    output logic [XLEN-1:0] result_o
);
    logic a_signed, b_signed, want_high;
    assign a_signed  = op_i inside {MULH, MULHSU};
    assign b_signed  = op_i inside {MULH};
    assign want_high = op_i inside {MULH, MULHSU, MULHU};

    logic signed [32:0] a_ext, b_ext;
    assign a_ext = {a_signed & a_i[XLEN-1], a_i};
    assign b_ext = {b_signed & b_i[XLEN-1], b_i};

    logic signed [65:0] prod;
    assign prod = a_ext * b_ext;

    assign result_o = want_high ? prod[63:32] : prod[31:0];
endmodule