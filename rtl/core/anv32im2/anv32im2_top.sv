module anv32im2_top
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
#(
    parameter bit              HAS_M          = 1'b1,
    parameter logic [XLEN-1:0] PC_RESET_VALUE = RESET_PC
)(
    input  logic            clk_i, rst_i, stall_i, pc_jmp_en_i,
    input  logic            ext_irq_i,
    input  logic            timer_irq_i,    // CLINT machine timer interrupt
    input  logic            sw_irq_i,       // CLINT machine software interrupt
    input  logic [31:0]     pc_jmp_addr_i,
    output logic [31:0]     instr_o, pc_o,
    output logic            instr_valid_o,

    input  logic [XLEN-1:0] instr_i,
    output logic [XLEN-1:0] instr_addr_o,

    input  logic [XLEN-1:0] mem_rdata_i,
    input  logic            mem_ready_i,
    output logic [XLEN-1:0] mem_wdata_o,
    output logic [XLEN-1:0] mem_addr_o,
    output logic            mem_valid_o,
    output logic [3:0]      mem_we
);

    logic [XLEN-1:0] fetch_addr;

    logic [XLEN-1:0]        dmem_wdata;
    logic [3:0]             dmem_we;
    logic                   dmem_valid;
    logic                   mem_wait_stall;

    logic                   stall_f, stall_d, stall_e;

    finstr_t                finstr;
    einstr_t                einstr;
    minstr_t                minstr;
    dinstr_t                dinstr;
    dinstr_t                dinstr_e2;
    dinstr_t                dinstr_decode;

    logic                   pc_jmp_en;
    logic [XLEN-1:0]        pc_jmp_addr;

    logic [XLEN-1:0]        rs1_rdata, rs2_rdata, rd_wdata;
    logic [4:0]             rd_idx, rs1_idx, rs2_idx;
    logic                   regfile_we;

    logic [XLEN-1:0]        m_stage_mem_out;
    logic [XLEN-1:0]        m_stage_dmem_addr_out;

    logic                   flush_D;
    fwd_sel_e               rs1_fwd_sel, rs2_fwd_sel;
    logic                   stall_f_eff, stall_d_eff, stall_e_eff, stall_m_eff, stall_w_eff;
    logic [XLEN-1:0]        rs1_D_din, rs2_D_din, rs1_e1_rdata, rs2_e1_rdata;
    logic [XLEN-1:0]        rs1_e2_rdata, rs2_e2_rdata, csr_e2_rdata, csr_e2_rdata_fwd;
    logic                   stall_im2_raw;
    logic [11:0]            csr_addr;
    logic [XLEN-1:0]        csr_rdata, csr_rdata_D, csr_e1_rdata;
    logic                   csr_we;
    logic [11:0]            csr_waddr;
    logic [XLEN-1:0]        csr_wdata, mtvec, mepc;
    logic                   e_branch_taken;
    logic [XLEN-1:0]        e_pc_target;
    logic                   e_pc_changer, e_valid;

    // mul/div stall from E (tied to 0 when HAS_M=0)
    logic                   e_mul_div_stall, md_stall, e_div_busy;
    logic                   csr_cnt_stall;

    // E stage trap out
    logic                   trap_req, e2_trap_req;
    logic [XLEN-1:0]        trap_pc, trap_cause, trap_tval;
    logic                   mret_req, e2_mret_req;
    logic [XLEN-1:0]        trap_target, mret_target;
    logic                   irq_pending, irq_req, irq_csr_hazard;
    logic [XLEN-1:0]        irq_cause;
    logic                   csr_serialize;
    logic [XLEN-1:0]        irq_pc;
    logic                   csr_trap;
    logic [XLEN-1:0]        csr_trap_pc, csr_trap_cause, csr_trap_tval;
    logic                   e2_fwd_valid, e2_fwd_ready;
    logic [4:0]             e2_fwd_rd_idx;
    logic [XLEN-1:0]        e2_fwd_data;

    assign mem_wdata_o  = dmem_wdata;
    assign mem_addr_o   = m_stage_dmem_addr_out;
    assign mem_valid_o  = dmem_valid;
    assign mem_we       = dmem_we;
    assign instr_addr_o = fetch_addr;

    assign instr_o       = finstr.instr;
    assign pc_o          = finstr.pc;
    assign instr_valid_o = finstr.valid;

    function automatic logic [XLEN-1:0] csr_bypass_value(
        input logic [11:0]     csr_addr_i,
        input logic [XLEN-1:0] csr_value_i
    );
        if (einstr.valid && einstr.is_csr && einstr.csr_we &&
            einstr.csr_addr == csr_addr_i) begin
            return einstr.csr_wdata;
        end else if (csr_we && csr_waddr == csr_addr_i) begin
            return csr_wdata;
        end else begin
            return csr_value_i;
        end
    endfunction

    always_comb begin : csr_redirect_bypass_comb
        trap_target = csr_bypass_value(CSR_MTVEC, mtvec);
        mret_target = csr_bypass_value(CSR_MEPC,  mepc);
    end

    // The IRQ kills E2 and everything younger, so mepc is the oldest of those.
    always_comb begin : irq_pc_comb
        if (dinstr_e2.valid) begin
            irq_pc = dinstr_e2.pc;
        end else if (dinstr.valid) begin
            irq_pc = dinstr.pc;
        end else if (dinstr_decode.valid) begin
            irq_pc = dinstr_decode.pc;
        end else if (finstr.valid) begin
            irq_pc = finstr.pc;
        end else begin
            irq_pc = fetch_addr;
        end
    end

    // Hold off interrupts while a write to mstatus/mie is still in M or W.
    // Otherwise an IRQ could be taken after the instruction that disabled it.
    assign irq_csr_hazard =
        (einstr.valid && einstr.is_csr && einstr.csr_we &&
         (einstr.csr_addr == CSR_MSTATUS || einstr.csr_addr == CSR_MIE)) ||
        (csr_we && (csr_waddr == CSR_MSTATUS || csr_waddr == CSR_MIE));

    // A trap or MRET in E2 waits until a pending memory access in M completes,
    // so the CSR update and the redirect happen exactly once.
    assign trap_req = e2_trap_req && !stall_i && !mem_wait_stall;
    assign mret_req = e2_mret_req && !stall_i && !mem_wait_stall;

    assign irq_req = irq_pending && !irq_csr_hazard && !trap_req && !mret_req && !pc_jmp_en_i && !stall_i && !mem_wait_stall;

    always_comb begin : csr_trap_mux_comb
        csr_trap       = trap_req || irq_req;
        csr_trap_pc    = trap_req ? trap_pc    : irq_pc;
        csr_trap_cause = trap_req ? trap_cause : irq_cause;
        csr_trap_tval  = trap_req ? trap_tval  : '0;
    end

    // A write to mstatus/mie changes which interrupts are enabled. Refetch
    // everything after it so younger instructions only reach E once the write
    // has landed and the interrupt condition has been re-evaluated.
    assign csr_serialize =
        dinstr_e2.valid && dinstr_e2.is_csr &&
        (dinstr_e2.csr_addr == CSR_MSTATUS || dinstr_e2.csr_addr == CSR_MIE) &&
        (dinstr_e2.csr_op == CSR_OP_RW || dinstr_e2.rs1_idx != 5'd0);

    always_comb begin : pc_jump_comb
        if (pc_jmp_en_i) begin
            pc_jmp_en   = 1'b1;
            pc_jmp_addr = pc_jmp_addr_i;
        end else if (trap_req) begin
            pc_jmp_en   = 1'b1;
            pc_jmp_addr = trap_target;
        end else if (mret_req) begin
            pc_jmp_en   = 1'b1;
            pc_jmp_addr = mret_target;
        end else if (irq_req) begin
            pc_jmp_en   = 1'b1;
            pc_jmp_addr = trap_target;
        end else if (csr_serialize) begin
            pc_jmp_en   = 1'b1;
            pc_jmp_addr = dinstr_e2.pc + 32'd4;
        end else begin
            pc_jmp_en   = e_branch_taken && e_valid && e_pc_changer;
            pc_jmp_addr = e_pc_target;
        end
    end

    // Stall routing: a multi-cycle E op stalls upstream while M/W drain
    assign md_stall    = e_mul_div_stall;            // HAS_M=0 -> execute tie-off 0
    assign mem_wait_stall = dmem_valid && !mem_ready_i;

    assign stall_e     = md_stall;
    // A counter read (mcycle/minstret and their aliases) waits in D until
    // every older instruction has retired, so minstret counts all of them.
    assign csr_cnt_stall =
        dinstr_decode.valid && dinstr_decode.is_csr && csr_is_counter(dinstr_decode.csr_addr) &&
        (dinstr.valid || dinstr_e2.valid || einstr.valid || minstr.valid || e_div_busy);

    assign stall_f_eff = stall_i || stall_f || stall_im2_raw || md_stall || mem_wait_stall || csr_cnt_stall;
    assign stall_d_eff = stall_i || stall_d || stall_im2_raw || md_stall || mem_wait_stall || csr_cnt_stall;
    assign stall_e_eff = stall_i || stall_e || mem_wait_stall;
    assign stall_m_eff = stall_i || mem_wait_stall;
    assign stall_w_eff = stall_i || mem_wait_stall;

    anv32_hazard_basic hazard_unit(
        .branch_taken_i(pc_jmp_en),
        .dinstr_d_i(dinstr_decode),
        .dinstr_e_i(dinstr),
        .einstr_i(einstr),
        .minstr_i(minstr),
        .stall_DE_o(stall_d),
        .stall_F_o(stall_f),
        .rs1_fwd_sel(rs1_fwd_sel),
        .rs2_fwd_sel(rs2_fwd_sel),
        .flush_D_o(flush_D)
    );

    anv32_forward_unit_im2 fwd_unit (
        .rs1_idx_i     (rs1_idx),
        .rs2_idx_i     (rs2_idx),
        .rs1_rdata_i   (rs1_rdata),
        .rs2_rdata_i   (rs2_rdata),
        .dinstr_decode_i(dinstr_decode),
        .dinstr_e1_i   (dinstr),
        .dinstr_e2_i   (dinstr_e2),
        .einstr_i      (einstr),
        .minstr_i      (minstr),
        .e2_fwd_valid_i(e2_fwd_valid),
        .e2_fwd_ready_i(e2_fwd_ready),
        .e2_fwd_rd_idx_i(e2_fwd_rd_idx),
        .e2_fwd_data_i (e2_fwd_data),
        .rd_wdata_i    (rd_wdata),
        .rs1_D_din_o   (rs1_D_din),
        .rs2_D_din_o   (rs2_D_din),
        .rs1_E1_din_o  (rs1_e1_rdata),
        .rs2_E1_din_o  (rs2_e1_rdata),
        .stall_raw_o   (stall_im2_raw)
    );

    anv32_fetch_c1 #(.PC_RESET_VALUE(PC_RESET_VALUE)) fetch (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .stall_i(stall_f_eff),
        .pc_jmp_en_i(pc_jmp_en),
        .pc_jmp_addr_i(pc_jmp_addr),
        .instr_i(instr_i),
        .fetch_addr_o(fetch_addr),
        .finstr_o(finstr)
    );

    always_comb begin : csr_d_bypass_comb
        csr_rdata_D = csr_bypass_value(csr_addr, csr_rdata);
    end

    // A CSR write directly ahead of a CSR read is in M when the read reaches
    // E2, one stage after E1 latched its operand.
    always_comb begin : csr_e2_fwd_comb
        if (einstr.valid && einstr.is_csr && einstr.csr_we &&
            einstr.csr_addr == dinstr_e2.csr_addr) begin
            csr_e2_rdata_fwd = einstr.csr_wdata;
        end else begin
            csr_e2_rdata_fwd = csr_e2_rdata;
        end
    end

    always_comb begin : csr_e_fwd_comb
        if (einstr.valid && einstr.is_csr && einstr.csr_we &&
            einstr.csr_addr == dinstr.csr_addr) begin
            csr_e1_rdata = einstr.csr_wdata;
        end else if (minstr.valid && minstr.is_csr && minstr.csr_we &&
            minstr.csr_addr == dinstr.csr_addr) begin
            csr_e1_rdata = minstr.csr_wdata;
        end else begin
            csr_e1_rdata = dinstr.csr_rdata;
        end
    end

    anv32_decode_c1 #(.HAS_M(HAS_M)) D(
        .clk_i(clk_i),
        .hold_i(stall_e_eff),
        .rs1_hold_i(rs1_e1_rdata),
        .rs2_hold_i(rs2_e1_rdata),
        .csr_hold_i(csr_e1_rdata),
        .rst_i(rst_i),
        .flush_i(flush_D),
        .stall_i(stall_d_eff),
        .finstr_i(finstr),
        .rs1_rdata_i(rs1_D_din),
        .rs2_rdata_i(rs2_D_din),
        .csr_rdata_i(csr_rdata_D),
        .rs1_idx_o(rs1_idx),
        .rs2_idx_o(rs2_idx),
        .csr_addr_o(csr_addr),
        .dinstr_decode_o(dinstr_decode),
        .dinstr_o(dinstr)
    );

    anv32_execute_im_c1 E1(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .stall_i(stall_e_eff),
        .kill_i(pc_jmp_en),
        .dinstr_e1_i    (dinstr),
        .rs1_e1_rdata_i (rs1_e1_rdata),
        .rs2_e1_rdata_i (rs2_e1_rdata),
        .csr_e1_rdata_i (csr_e1_rdata),
        .dinstr_e2_o    (dinstr_e2),
        .rs1_e2_rdata_o (rs1_e2_rdata),
        .rs2_e2_rdata_o (rs2_e2_rdata),
        .csr_e2_rdata_o (csr_e2_rdata)
    );

    anv32_execute_im_c2 #(.HAS_M(HAS_M)) E2(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .stall_i(stall_e_eff),
        .kill_i(irq_req),
        .dinstr_e2_i    (dinstr_e2),
        .rs1_e2_rdata_i (rs1_e2_rdata),
        .rs2_e2_rdata_i (rs2_e2_rdata),
        .csr_e2_rdata_i (csr_e2_rdata_fwd),
        .pc_target_o(e_pc_target),
        .pc_changer_o(e_pc_changer),
        .branch_taken_o(e_branch_taken),
        .valid_o(e_valid),
        .einstr_o(einstr),
        .mul_div_stall_o(e_mul_div_stall),
        .div_busy_o(e_div_busy),
        .fwd_valid_o(e2_fwd_valid),
        .fwd_ready_o(e2_fwd_ready),
        .fwd_rd_idx_o(e2_fwd_rd_idx),
        .fwd_data_o(e2_fwd_data),
        .trap_req_o(e2_trap_req),
        .trap_pc_o(trap_pc),
        .trap_cause_o(trap_cause),
        .trap_tval_o(trap_tval),
        .mret_req_o(e2_mret_req)
    );

    anv32_memory_c1 M(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .stall_i(stall_m_eff),
        .einstr_i(einstr),
        .mem_rdata_i(mem_rdata_i),
        .mem_valid_o(dmem_valid),
        .mem_addr_o(m_stage_dmem_addr_out),
        .mem_wdata_o(dmem_wdata),
        .mem_we_o(dmem_we),
        .mem_rdata_o(m_stage_mem_out),
        .minstr_o(minstr)
    );

    anv32_writeback_c1 W(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .stall_i(stall_w_eff),
        .minstr_i(minstr),
        .mem_rdata_i(m_stage_mem_out),
        .rd_wen_o(regfile_we),
        .rd_wdata_o(rd_wdata),
        .rd_idx_o(rd_idx),
        .csr_we_o(csr_we),
        .csr_addr_o(csr_waddr),
        .csr_wdata_o(csr_wdata)
    );

    anv32_regfile regfile (
        .clk_i(clk_i),
        .we_i(regfile_we),
        .rs1_idx_i(rs1_idx),
        .rs2_idx_i(rs2_idx),
        .rd_idx_i(rd_idx),
        .rd_wdata_i(rd_wdata),
        .rs1_rdata_o(rs1_rdata),
        .rs2_rdata_o(rs2_rdata)
    );

    anv32_csr #(.MISA_VALUE(MISA_MXL32 | MISA_I | (HAS_M ? MISA_M : '0))) csr (
        .clk_i        (clk_i),
        .rst_i        (rst_i),
        .csr_raddr_i  (csr_addr),
        .csr_rdata_o  (csr_rdata),
        .csr_we_i     (csr_we),
        .csr_waddr_i  (csr_waddr),
        .csr_wdata_i  (csr_wdata),
        .retire_i     (minstr.valid && !stall_w_eff),
        .ext_irq_i    (ext_irq_i),
        .timer_irq_i  (timer_irq_i),
        .sw_irq_i     (sw_irq_i),
        .mtvec_o      (mtvec),
        .mepc_o       (mepc),
        .trap_i       (csr_trap),
        .trap_pc_i    (csr_trap_pc),
        .trap_cause_i (csr_trap_cause),
        .trap_tval_i  (csr_trap_tval),
        .mret_i       (mret_req),
        .irq_pending_o(irq_pending),
        .irq_cause_o  (irq_cause)
    );
endmodule
