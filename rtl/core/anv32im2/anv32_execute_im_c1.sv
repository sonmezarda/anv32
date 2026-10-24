module anv32_execute_im_c1
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
(
    input  logic               clk_i,
    input  logic               rst_i,
    input  logic               stall_i,
    input  logic               kill_i,

    input  dinstr_t            dinstr_e1_i,
    input  logic    [XLEN-1:0] rs1_e1_rdata_i,
    input  logic    [XLEN-1:0] rs2_e1_rdata_i,
    input  logic    [XLEN-1:0] csr_e1_rdata_i,

    output dinstr_t            dinstr_e2_o,
    output logic    [XLEN-1:0] rs1_e2_rdata_o,
    output logic    [XLEN-1:0] rs2_e2_rdata_o,
    output logic    [XLEN-1:0] csr_e2_rdata_o
);
    logic [XLEN-1:0] rs1_e2_rdata_q, rs2_e2_rdata_q, csr_e2_rdata_q;
    dinstr_t         dinstr_e2_q;

    always_ff @(posedge clk_i) begin
        // A kill only drops the instruction moving into E2. While E2 is
        // stalled it still holds an older instruction that must not be lost.
        if(rst_i || (kill_i && !stall_i)) begin
            dinstr_e2_q     <= '0;
            rs1_e2_rdata_q  <= '0;
            rs2_e2_rdata_q  <= '0;
            csr_e2_rdata_q  <= '0;
        end else if(!stall_i) begin
            dinstr_e2_q     <= dinstr_e1_i;
            rs1_e2_rdata_q  <= rs1_e1_rdata_i;
            rs2_e2_rdata_q  <= rs2_e1_rdata_i;
            csr_e2_rdata_q  <= csr_e1_rdata_i;
        end else begin
            dinstr_e2_q     <= dinstr_e2_q;
            rs1_e2_rdata_q  <= rs1_e2_rdata_q;
            rs2_e2_rdata_q  <= rs2_e2_rdata_q;
            csr_e2_rdata_q  <= csr_e2_rdata_q;
        end
    end

    assign dinstr_e2_o     = dinstr_e2_q;
    assign rs1_e2_rdata_o  = rs1_e2_rdata_q;
    assign rs2_e2_rdata_o  = rs2_e2_rdata_q;
    assign csr_e2_rdata_o  = csr_e2_rdata_q;

endmodule
