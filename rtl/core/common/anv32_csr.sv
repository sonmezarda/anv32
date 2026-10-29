// Machine-mode CSR file. Writes arrive from W already legalized by
// csr_legalize(), so stored and forwarded values always match.
module anv32_csr
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
#(
    parameter logic [XLEN-1:0] MISA_VALUE = MISA_MXL32 | MISA_I
)(
    input  logic        clk_i,
    input  logic        rst_i,

    input  logic [11:0] csr_raddr_i,
    output logic [XLEN-1:0] csr_rdata_o,

    input  logic        csr_we_i,
    input  logic [11:0] csr_waddr_i,
    input  logic [XLEN-1:0] csr_wdata_i,

    input  logic            retire_i,       // an instruction retires this cycle

    input  logic            ext_irq_i,      // MEIP
    input  logic            timer_irq_i,    // MTIP (CLINT mtime >= mtimecmp)
    input  logic            sw_irq_i,       // MSIP (CLINT msip)
    input  logic            trap_i,
    input  logic [XLEN-1:0] trap_pc_i,
    input  logic [XLEN-1:0] trap_cause_i,
    input  logic [XLEN-1:0] trap_tval_i,
    input  logic            mret_i,

    output logic [XLEN-1:0] mtvec_o,
    output logic [XLEN-1:0] mepc_o,
    output logic            irq_pending_o,
    output logic [XLEN-1:0] irq_cause_o     // mcause of the interrupt to take
);
    logic [XLEN-1:0] mstatus_q, mtvec_q, mepc_q, mcause_q, mtval_q, mie_q, mscratch_q;
    logic [XLEN-1:0] mstatus_d, mtvec_d, mepc_d, mcause_d, mtval_d, mie_d, mscratch_d;
    logic [63:0]     mcycle_q, minstret_q;
    logic [63:0]     mcycle_d, minstret_d;
    logic [XLEN-1:0] mip;
    logic [XLEN-1:0] irq_enabled;

    assign mtvec_o = mtvec_q;
    assign mepc_o  = mepc_q;

    // Machine external, timer and software interrupts. The pending bits are
    // read-only: they follow their sources (software clears MSIP/MTIP at the
    // CLINT, MEIP at the peripheral that raised it).
    always_comb begin
        mip = '0;
        mip[MIP_MSIP_BIT] = sw_irq_i;
        mip[MIP_MTIP_BIT] = timer_irq_i;
        mip[MIP_MEIP_BIT] = ext_irq_i;
    end

    assign irq_enabled   = mie_q & mip;
    assign irq_pending_o = mstatus_q[MSTATUS_MIE_BIT] && (irq_enabled != '0);

    // Highest-priority enabled source, in the privileged spec order MEI > MSI > MTI
    always_comb begin
        if      (irq_enabled[MIP_MEIP_BIT]) irq_cause_o = MCAUSE_MACHINE_EXTERNAL_IRQ;
        else if (irq_enabled[MIP_MSIP_BIT]) irq_cause_o = MCAUSE_MACHINE_SOFTWARE_IRQ;
        else                                irq_cause_o = MCAUSE_MACHINE_TIMER_IRQ;
    end

    always_comb begin
        unique case (csr_raddr_i)
            CSR_MSTATUS:   csr_rdata_o = mstatus_q;
            CSR_MISA:      csr_rdata_o = MISA_VALUE;
            CSR_MIE:       csr_rdata_o = mie_q;
            CSR_MTVEC:     csr_rdata_o = mtvec_q;
            CSR_MSCRATCH:  csr_rdata_o = mscratch_q;
            CSR_MEPC:      csr_rdata_o = mepc_q;
            CSR_MCAUSE:    csr_rdata_o = mcause_q;
            CSR_MTVAL:     csr_rdata_o = mtval_q;
            CSR_MIP:       csr_rdata_o = mip;
            CSR_MCYCLE,
            CSR_CYCLE:     csr_rdata_o = mcycle_q[31:0];
            CSR_MCYCLEH,
            CSR_CYCLEH:    csr_rdata_o = mcycle_q[63:32];
            CSR_MINSTRET,
            CSR_INSTRET:   csr_rdata_o = minstret_q[31:0];
            CSR_MINSTRETH,
            CSR_INSTRETH:  csr_rdata_o = minstret_q[63:32];
            default:       csr_rdata_o = '0;    // mstatush, IDs, mconfigptr, PMP
        endcase
    end

    always_comb begin
        mstatus_d  = mstatus_q;
        mie_d      = mie_q;
        mtvec_d    = mtvec_q;
        mscratch_d = mscratch_q;
        mepc_d     = mepc_q;
        mcause_d   = mcause_q;
        mtval_d    = mtval_q;
        mcycle_d   = mcycle_q + 64'd1;
        minstret_d = minstret_q + {63'd0, retire_i};

        // A write to a counter replaces the increment for that cycle, so the
        // next instruction reads exactly the written value.
        if (csr_we_i) begin
            unique case (csr_waddr_i)
                CSR_MSTATUS:   mstatus_d  = csr_wdata_i;
                CSR_MIE:       mie_d      = csr_wdata_i;
                CSR_MTVEC:     mtvec_d    = csr_wdata_i;
                CSR_MSCRATCH:  mscratch_d = csr_wdata_i;
                CSR_MEPC:      mepc_d     = csr_wdata_i;
                CSR_MCAUSE:    mcause_d   = csr_wdata_i;
                CSR_MTVAL:     mtval_d    = csr_wdata_i;
                CSR_MCYCLE:    mcycle_d   = {mcycle_q[63:32], csr_wdata_i};
                CSR_MCYCLEH:   mcycle_d   = {csr_wdata_i, mcycle_q[31:0]};
                CSR_MINSTRET:  minstret_d = {minstret_q[63:32], csr_wdata_i};
                CSR_MINSTRETH: minstret_d = {csr_wdata_i, minstret_q[31:0]};
                default: ;
            endcase
        end

        if (trap_i) begin
            mepc_d   = trap_pc_i;
            mcause_d = trap_cause_i;
            mtval_d  = trap_tval_i;

            mstatus_d[MSTATUS_MPIE_BIT] = mstatus_d[MSTATUS_MIE_BIT];
            mstatus_d[MSTATUS_MIE_BIT]  = 1'b0;
        end else if (mret_i) begin
            mstatus_d[MSTATUS_MIE_BIT]  = mstatus_d[MSTATUS_MPIE_BIT];
            mstatus_d[MSTATUS_MPIE_BIT] = 1'b1;
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            mstatus_q  <= csr_legalize(CSR_MSTATUS, '0);
            mie_q      <= '0;
            mtvec_q    <= '0;
            mscratch_q <= '0;
            mepc_q     <= '0;
            mcause_q   <= '0;
            mtval_q    <= '0;
            mcycle_q   <= '0;
            minstret_q <= '0;
        end else begin
            mstatus_q  <= mstatus_d;
            mie_q      <= mie_d;
            mtvec_q    <= mtvec_d;
            mscratch_q <= mscratch_d;
            mepc_q     <= mepc_d;
            mcause_q   <= mcause_d;
            mtval_q    <= mtval_d;
            mcycle_q   <= mcycle_d;
            minstret_q <= minstret_d;
        end
    end

endmodule
