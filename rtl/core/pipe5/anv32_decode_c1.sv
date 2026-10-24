module anv32_decode_c1
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
#(
    parameter bit HAS_M = 1'b0
)(
    input  logic               clk_i,
    input  logic               rst_i,
    input  logic               stall_i,    // insert a bubble, D keeps its instruction
    input  logic               hold_i,     // next stage is stalled: keep dinstr_o
    input  logic               flush_i,

    input  finstr_t            finstr_i,
    input  logic    [XLEN-1:0] rs1_rdata_i,
    input  logic    [XLEN-1:0] rs2_rdata_i,
    input  logic    [XLEN-1:0] csr_rdata_i,

    // Next stage's forwarded operands. While holding, the producers they came
    // from can retire, so the held instruction keeps these values instead.
    input  logic    [XLEN-1:0] rs1_hold_i,
    input  logic    [XLEN-1:0] rs2_hold_i,
    input  logic    [XLEN-1:0] csr_hold_i,

    output logic    [4:0]      rs1_idx_o,
    output logic    [4:0]      rs2_idx_o,
    output logic    [11:0]     csr_addr_o,
    output dinstr_t            dinstr_decode_o,
    output dinstr_t            dinstr_o
);
    dinstr_t decoded;
    dinstr_t decoded_gated;

    always_comb begin
        decoded_gated           = decoded;
        decoded_gated.valid     = finstr_i.valid && decoded.valid && !flush_i;
        decoded_gated.exc_valid = finstr_i.valid && decoded.exc_valid && !flush_i;
    end

    assign dinstr_decode_o = decoded_gated;

    assign rs1_idx_o  = decoded.rs1_idx;
    assign rs2_idx_o  = decoded.rs2_idx;
    assign csr_addr_o = decoded.csr_addr;

    anv32_decoder #(.HAS_M(HAS_M)) decoder (
        .instr_i (finstr_i.instr),
        .pc_i    (finstr_i.pc),
        .dinstr_o(decoded)
    );

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            dinstr_o <= '0;
        end else if (hold_i) begin
            dinstr_o.rs1_rdata <= rs1_hold_i;
            dinstr_o.rs2_rdata <= rs2_hold_i;
            dinstr_o.csr_rdata <= csr_hold_i;
        end else if (stall_i) begin
            dinstr_o <= '0;
        end else begin
            dinstr_o           <= decoded_gated;
            dinstr_o.rs1_rdata <= rs1_rdata_i;
            dinstr_o.rs2_rdata <= rs2_rdata_i;
            dinstr_o.csr_rdata <= csr_rdata_i;
        end
    end

endmodule
