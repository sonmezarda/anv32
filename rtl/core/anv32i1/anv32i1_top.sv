module anv32i1_top
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
#(
    parameter logic [XLEN-1:0] PC_RESET_VALUE = RESET_PC
)(
    input  logic            clk_i, rst_i, stall_i, pc_jmp_en_i,
    input  logic            ext_irq_i,
    input  logic [31:0]     pc_jmp_addr_i,
    output logic [31:0]     instr_o, pc_o,
    output logic            instr_valid_o,

    input  logic [XLEN-1:0] instr_i,
    output logic [XLEN-1:0] instr_addr_o,

    input  logic [XLEN-1:0] mem_rdata_i,
    output logic [XLEN-1:0] mem_wdata_o,
    output logic [XLEN-1:0] mem_addr_o,
    output logic [3:0]      mem_we
);
    logic [XLEN-1:0] fetch_addr;

    logic [XLEN-1:0]        dmem_wdata;
    logic [3:0]             dmem_we;

    logic                   stall_f, stall_de, stall_e, stall_m, stall_w;

    finstr_t                finstr;
    einstr_t                einstr;
    minstr_t                minstr;
    dinstr_t                dinstr;
    dinstr_t                dinstr_decode;

    logic                   pc_jmp_en;
    logic [XLEN-1:0]        pc_jmp_addr;

    logic [XLEN-1:0]        rs1_rdata;
    logic [XLEN-1:0]        rs2_rdata;
    logic [XLEN-1:0]        rd_wdata;
    logic [4:0]             rd_idx;
    logic [4:0]             rs1_idx;
    logic [4:0]             rs2_idx;
    logic                   regfile_we;
    
    logic [XLEN-1:0]        m_stage_mem_out;
    logic [XLEN-1:0]        m_stage_dmem_addr_out;

    logic                   flush_D;
    fwd_sel_e               rs1_fwd_sel;
    fwd_sel_e               rs2_fwd_sel;
    logic                   stall_f_eff;
    logic                   stall_de_eff;
    logic                   stall_e_eff;
    logic                   stall_m_eff;
    logic                   stall_w_eff;
    logic [XLEN-1:0]        m_fwd_data;
    logic [XLEN-1:0]        w_fwd_data;
    logic [XLEN-1:0]        rs1_D_din;
    logic [XLEN-1:0]        rs2_D_din;
    logic [XLEN-1:0]        rs1_E_din;
    logic [XLEN-1:0]        rs2_E_din;
    logic [11:0]            csr_addr;
    logic [XLEN-1:0]        csr_rdata;
    logic [XLEN-1:0]        csr_rdata_D;
    logic [XLEN-1:0]        csr_rdata_E;
    logic                   csr_we;
    logic [11:0]            csr_waddr;
    logic [XLEN-1:0]        csr_wdata;
    logic [XLEN-1:0]        mtvec;
    logic [XLEN-1:0]        mepc;
    logic                   e_branch_taken;
    logic [XLEN-1:0]        e_pc_target;
    logic                   e_pc_changer;
    logic                   e_valid;

    // E stage trap out
    logic                   trap_req;
    logic [XLEN-1:0]        trap_pc;
    logic [XLEN-1:0]        trap_cause;
    logic [XLEN-1:0]        trap_tval;
    logic                   mret_req;
    logic [XLEN-1:0]        trap_target;
    logic [XLEN-1:0]        mret_target;
    logic                   irq_pending;
    logic                   irq_req;
    logic [XLEN-1:0]        irq_pc;
    logic                   csr_trap;
    logic [XLEN-1:0]        csr_trap_pc;
    logic [XLEN-1:0]        csr_trap_cause;
    logic [XLEN-1:0]        csr_trap_tval;

    assign mem_wdata_o = dmem_wdata;
    assign mem_addr_o  = m_stage_dmem_addr_out;
    assign mem_we      = dmem_we;
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

    always_comb begin : irq_pc_comb
        if (dinstr.valid) begin
            irq_pc = dinstr.pc;
        end else if (dinstr_decode.valid) begin
            irq_pc = dinstr_decode.pc;
        end else if (finstr.valid) begin
            irq_pc = finstr.pc;
        end else begin
            irq_pc = fetch_addr;
        end
    end

    assign irq_req = irq_pending && !trap_req && !mret_req && !pc_jmp_en_i && !stall_i;

    always_comb begin : csr_trap_mux_comb
        csr_trap       = trap_req || irq_req;
        csr_trap_pc    = trap_req ? trap_pc    : irq_pc;
        csr_trap_cause = trap_req ? trap_cause : MCAUSE_MACHINE_EXTERNAL_IRQ;
        csr_trap_tval  = trap_req ? trap_tval  : '0;
    end

    // PC JUMP
    always_comb begin : pc_jump_comb
        if (pc_jmp_en_i) begin
            pc_jmp_en   = 1'b1;
            pc_jmp_addr = pc_jmp_addr_i;
        end else if(trap_req) begin
            pc_jmp_en   = 1'b1;
            pc_jmp_addr = trap_target;
        end else if(mret_req) begin
            pc_jmp_en   = 1'b1;
            pc_jmp_addr = mret_target;
        end else if(irq_req) begin
            pc_jmp_en   = 1'b1;
            pc_jmp_addr = trap_target;
        end else begin
            pc_jmp_en   = e_branch_taken && e_valid && e_pc_changer;
            pc_jmp_addr = e_pc_target;
        end
    end

    assign stall_f_eff  = stall_i || stall_f;
    assign stall_de_eff = stall_i || stall_de;
    assign stall_e      = 1'b0;
    assign stall_e_eff  = stall_i || stall_e;
    assign stall_m_eff  = stall_i;
    assign stall_w_eff  = stall_i;

    anv32_hazard_basic hazard_unit(
        .clk_i(clk_i), 
        .rst_i(rst_i), 
        .stall_i(1'b0),
        .branch_taken_i(pc_jmp_en),
        .dinstr_d_i(dinstr_decode), // instr currently in decode
        .dinstr_e_i(dinstr),        // instr currently in execute
        .einstr_i(einstr),          // instr after execute
        .minstr_i(minstr),          // instr after mem stage
        .stall_DE_o(stall_de),
        .stall_F_o(stall_f),
        .rs1_fwd_sel(rs1_fwd_sel),
        .rs2_fwd_sel(rs2_fwd_sel),
        .flush_D_o(flush_D)
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

    always_comb begin : m_fwd_data_comb
        unique case (einstr.wb_sel)
            WB_ALU:  m_fwd_data = einstr.alu_result;
            WB_PC4:  m_fwd_data = einstr.link_pc;
            default: m_fwd_data = '0;
        endcase
    end

    assign w_fwd_data = rd_wdata;

    always_comb begin : d_bypass_mux_comb
        if (minstr.valid && minstr.rd_valid && minstr.rd_idx != 5'd0 &&
            minstr.rd_idx == rs1_idx) begin
            rs1_D_din = w_fwd_data;
        end else begin
            rs1_D_din = rs1_rdata;
        end

        if (minstr.valid && minstr.rd_valid && minstr.rd_idx != 5'd0 &&
            minstr.rd_idx == rs2_idx) begin
            rs2_D_din = w_fwd_data;
        end else begin
            rs2_D_din = rs2_rdata;
        end
    end

    always_comb begin : e_fwd_mux_comb
        unique case (rs1_fwd_sel)
            FWD_M:   rs1_E_din = m_fwd_data;
            FWD_W:   rs1_E_din = w_fwd_data;
            default: rs1_E_din = dinstr.rs1_rdata;
        endcase

        unique case (rs2_fwd_sel)
            FWD_M:   rs2_E_din = m_fwd_data;
            FWD_W:   rs2_E_din = w_fwd_data;
            default: rs2_E_din = dinstr.rs2_rdata;
        endcase
    end

    always_comb begin : csr_d_bypass_comb
        csr_rdata_D = csr_bypass_value(csr_addr, csr_rdata);
    end

    always_comb begin : csr_e_fwd_comb
        if (einstr.valid && einstr.is_csr && einstr.csr_we &&
            einstr.csr_addr == dinstr.csr_addr) begin
            csr_rdata_E = einstr.csr_wdata;
        end else if (minstr.valid && minstr.is_csr && minstr.csr_we &&
            minstr.csr_addr == dinstr.csr_addr) begin
            csr_rdata_E = minstr.csr_wdata;
        end else begin
            csr_rdata_E = dinstr.csr_rdata;
        end
    end

    anv32_decode_c1 D(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .flush_i(flush_D),
        .stall_i(stall_de_eff),
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

    anv32_execute_i_c1 E(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .stall_i(stall_e_eff),
        .kill_i(irq_req),
        .dinstr_i(dinstr),
        .rs1_rdata_i(rs1_E_din),
        .rs2_rdata_i(rs2_E_din),
        .csr_rdata_i(csr_rdata_E),
        .branch_taken_o(e_branch_taken),
        .pc_target_o(e_pc_target),
        .pc_changer_o(e_pc_changer),
        .valid_o(e_valid),
        .einstr_o(einstr),

        .trap_req_o(trap_req),
        .trap_pc_o(trap_pc),
        .trap_cause_o(trap_cause),
        .trap_tval_o(trap_tval),
        .mret_req_o(mret_req)

    );

    anv32_memory_c1 M(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .stall_i(stall_m_eff),
        .einstr_i(einstr),
        .mem_rdata_i(mem_rdata_i),
        .mem_addr_o(m_stage_dmem_addr_out),   //
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

    assign stall_m = stall_m_eff;
    assign stall_w = stall_w_eff;

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

    anv32_csr csr (
        .clk_i       (clk_i),
        .rst_i       (rst_i),
        .csr_raddr_i (csr_addr),
        .csr_rdata_o (csr_rdata),
        .csr_we_i    (csr_we),
        .csr_waddr_i (csr_waddr),
        .csr_wdata_i (csr_wdata),
        .ext_irq_i   (ext_irq_i),
        .mtvec_o     (mtvec),
        .mepc_o      (mepc),

        .trap_i      (csr_trap),
        .trap_pc_i   (csr_trap_pc),
        .trap_cause_i(csr_trap_cause),
        .trap_tval_i (csr_trap_tval),
        .mret_i      (mret_req),
        .irq_pending_o(irq_pending)
    );
endmodule
