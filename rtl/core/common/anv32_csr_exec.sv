module anv32_csr_exec
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
(
    input  logic            valid_i,
    input  csr_op_e         csr_op_i,
    input  logic            csr_imm_i,
    input  logic [4:0]      rs1_idx_i,
    input  logic [XLEN-1:0] rs1_rdata_i,
    input  logic [XLEN-1:0] csr_rdata_i,

    output logic            csr_we_o,
    output logic [XLEN-1:0] csr_wdata_o,
    output logic [XLEN-1:0] rd_wdata_o
);
    logic [XLEN-1:0] operand;
    logic            operand_is_zero;

    // rs1 is zimm for CSR Operations
    assign operand         = csr_imm_i ? {{(XLEN-5){1'b0}}, rs1_idx_i} : rs1_rdata_i;
    assign operand_is_zero = (rs1_idx_i == 5'd0);
    assign rd_wdata_o      = valid_i ? csr_rdata_i : '0;

    always_comb begin
        csr_we_o    = 1'b0;
        csr_wdata_o = csr_rdata_i;

        if (valid_i) begin
            unique case (csr_op_i)
                CSR_OP_RW: begin
                    csr_we_o    = 1'b1;
                    csr_wdata_o = operand;
                end
                CSR_OP_RS: begin
                    csr_we_o    = !operand_is_zero;
                    csr_wdata_o = csr_rdata_i | operand;
                end
                CSR_OP_RC: begin
                    csr_we_o    = !operand_is_zero;
                    csr_wdata_o = csr_rdata_i & ~operand;
                end
                default: begin
                    csr_we_o    = 1'b0;
                    csr_wdata_o = csr_rdata_i;
                end
            endcase
        end
    end

endmodule
