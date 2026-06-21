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

    input  logic            ext_irq_i,
    input  logic            trap_i,
    input  logic [XLEN-1:0] trap_pc_i,
    input  logic [XLEN-1:0] trap_cause_i,
    input  logic [XLEN-1:0] trap_tval_i,
    input  logic            mret_i,

    output logic [XLEN-1:0] mtvec_o,
    output logic [XLEN-1:0] mepc_o,
    output logic            irq_pending_o
);
    logic [XLEN-1:0] mstatus_q, mtvec_q, mepc_q, mcause_q, mtval_q, mie_q, mip_q;
    logic [XLEN-1:0] mstatus_d, mtvec_d, mepc_d, mcause_d, mtval_d, mie_d, mip_d;
    logic [XLEN-1:0] mip_effective;

    assign mtvec_o = mtvec_q;
    assign mepc_o  = mepc_q;
    assign irq_pending_o =
        mstatus_q[MSTATUS_MIE_BIT] &&
        mie_q[MIE_MEIE_BIT] &&
        mip_effective[MIP_MEIP_BIT];

    always_comb begin
        mip_effective = mip_q;
        mip_effective[MIP_MEIP_BIT] = ext_irq_i;
    end

    always_comb begin
        unique case (csr_raddr_i)
            CSR_MSTATUS: csr_rdata_o = mstatus_q;
            CSR_MIE:     csr_rdata_o = mie_q;
            CSR_MTVEC:   csr_rdata_o = mtvec_q;
            CSR_MEPC:    csr_rdata_o = mepc_q;
            CSR_MCAUSE:  csr_rdata_o = mcause_q;
            CSR_MTVAL:   csr_rdata_o = mtval_q;
            CSR_MIP:     csr_rdata_o = mip_effective;
            default:     csr_rdata_o = '0;
        endcase
    end

    always_comb begin
        mstatus_d = mstatus_q;
        mie_d     = mie_q;
        mtvec_d   = mtvec_q;
        mepc_d    = mepc_q;
        mcause_d  = mcause_q;
        mtval_d   = mtval_q;
        mip_d     = mip_q;

        if (csr_we_i) begin
            unique case (csr_waddr_i)
                CSR_MSTATUS: mstatus_d = csr_wdata_i;
                CSR_MIE:     mie_d     = csr_wdata_i;
                CSR_MTVEC:   mtvec_d   = csr_wdata_i;
                CSR_MEPC:    mepc_d    = csr_wdata_i;
                CSR_MCAUSE:  mcause_d  = csr_wdata_i;
                CSR_MTVAL:   mtval_d   = csr_wdata_i;
                CSR_MIP:     mip_d     = csr_wdata_i;
                default: ;
            endcase
        end

        if (trap_i) begin
            mepc_d   = trap_pc_i;
            mcause_d = trap_cause_i;
            mtval_d  = trap_tval_i;

            mstatus_d[MSTATUS_MPIE_BIT] = mstatus_d[MSTATUS_MIE_BIT];
            mstatus_d[MSTATUS_MIE_BIT]  = 1'b0;
            mstatus_d[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] = PRIV_M;
        end else if (mret_i) begin
            mstatus_d[MSTATUS_MIE_BIT]  = mstatus_d[MSTATUS_MPIE_BIT];
            mstatus_d[MSTATUS_MPIE_BIT] = 1'b1;
            mstatus_d[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] = PRIV_U;
        end
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
            mstatus_q <= mstatus_d;
            mie_q     <= mie_d;
            mtvec_q   <= mtvec_d;
            mepc_q    <= mepc_d;
            mcause_q  <= mcause_d;
            mtval_q   <= mtval_d;
            mip_q     <= mip_d;
        end
    end

endmodule
