module anv32_csr
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
(
    input  logic        clk_i,
    input  logic        rst_i,

    input  logic [11:0] csr_raddr_i,
    output logic [XLEN-1:0] csr_rdata_o,

    input  logic        csr_we_i,
    input  logic [11:0] csr_waddr_i,
    input  logic [XLEN-1:0] csr_wdata_i,

    input  logic            trap_i,
    input  logic [XLEN-1:0] trap_pc_i,
    input  logic [XLEN-1:0] trap_cause_i,
    input  logic [XLEN-1:0] trap_tval_i,

    output logic [XLEN-1:0] mtvec_o,
    output logic [XLEN-1:0] mepc_o
);
    logic [XLEN-1:0] mstatus_q, mtvec_q, mepc_q, mcause_q, mtval_q, mie_q, mip_q;

    assign mtvec_o = mtvec_q;
    assign mepc_o  = mepc_q;

    always_comb begin
        unique case (csr_raddr_i)
            CSR_MSTATUS: csr_rdata_o = mstatus_q;
            CSR_MIE:     csr_rdata_o = mie_q;
            CSR_MTVEC:   csr_rdata_o = mtvec_q;
            CSR_MEPC:    csr_rdata_o = mepc_q;
            CSR_MCAUSE:  csr_rdata_o = mcause_q;
            CSR_MTVAL:   csr_rdata_o = mtval_q;
            CSR_MIP:     csr_rdata_o = mip_q;
            default:     csr_rdata_o = '0;
        endcase
    end
    
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            mstatus_q <= 32'h0;
            mie_q     <= 32'h0;
            mtvec_q   <= 32'h0;
            mepc_q    <= 32'h0;
            mcause_q  <= 32'h0;
            mtval_q   <= 32'h0;
            mip_q     <= 32'h0;
        end else begin
            if (csr_we_i) begin
                unique case (csr_waddr_i)
                    CSR_MSTATUS: mstatus_q <= csr_wdata_i;
                    CSR_MIE:     mie_q     <= csr_wdata_i;
                    CSR_MTVEC:   mtvec_q   <= csr_wdata_i;
                    CSR_MEPC:    mepc_q    <= csr_wdata_i;
                    CSR_MCAUSE:  mcause_q  <= csr_wdata_i;
                    CSR_MTVAL:   mtval_q   <= csr_wdata_i;
                    CSR_MIP:     mip_q     <= csr_wdata_i;
                    default: ;
                endcase
            end

            if (trap_i) begin
                mepc_q   <= trap_pc_i;
                mcause_q <= trap_cause_i;
                mtval_q  <= trap_tval_i;
            end
        end
    end

endmodule
