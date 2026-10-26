module anv32_execute_im
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
#(
    parameter bit HAS_M = 1'b1
)(
    input  logic               clk_i,
    input  logic               rst_i,
    input  logic               stall_i,
    input  logic               kill_i,

    input  dinstr_t            dinstr_i,
    input  logic    [XLEN-1:0] rs1_rdata_i,
    input  logic    [XLEN-1:0] rs2_rdata_i,
    input  logic    [XLEN-1:0] csr_rdata_i,
    input  logic               branch_taken_i,

    output logic    [XLEN-1:0] pc_target_o,
    output logic               pc_changer_o,
    output logic               valid_o,
    output einstr_t            einstr_o,

    output logic               mul_div_stall_o,
    output logic               div_busy_o,      // a divide is in flight

    output logic               trap_req_o,
    output logic    [XLEN-1:0] trap_pc_o,
    output logic    [XLEN-1:0] trap_cause_o,
    output logic    [XLEN-1:0] trap_tval_o,
    output logic               mret_req_o
);
    logic [XLEN-1:0] alu_a, alu_b, alu_result;
    logic [XLEN-1:0] csr_wdata, csr_rd_wdata;
    logic [XLEN-1:0] pc_plus4, pc_target;
    logic            csr_we;

    logic [XLEN-1:0] muldiv_result;
    logic            md_stall;
    logic            is_mul_op, is_div_op;
    logic            div_start, div_busy, div_done;
    logic            div_active_q, div_ready_q;
    logic            div_emit_accept;
    logic [XLEN-1:0] div_result_q, div_emit_result;
    logic [XLEN-1:0] div_write_data_q;
    dinstr_t         div_dinstr_q;

    generate
        if (HAS_M) begin : g_muldiv
            logic [XLEN-1:0] mul_result, div_result;

            assign is_mul_op = dinstr_i.valid && (dinstr_i.op inside {MUL, MULH, MULHSU, MULHU});
            assign is_div_op = dinstr_i.valid && (dinstr_i.op inside {DIV, DIVU, REM, REMU});

            assign div_start     = is_div_op && !div_active_q;
            assign muldiv_result = is_mul_op ? mul_result : div_emit_result;
            assign md_stall      = (div_start || (div_active_q && !div_ready_q && !div_done)) && !kill_i;
            assign div_emit_result = div_done ? div_result : div_result_q;

            anv32_mul_comb u_mul (
                .op_i    (dinstr_i.op),
                .a_i     (rs1_rdata_i),
                .b_i     (rs2_rdata_i),
                .result_o(mul_result)
            );

            anv32_div u_div (
                .clk_i   (clk_i),
                .rst_i   (rst_i),
                .flush_i (kill_i),
                .start_i (div_start),
                .op_i    (dinstr_i.op),
                .a_i     (rs1_rdata_i),
                .b_i     (rs2_rdata_i),
                .busy_o  (div_busy),
                .done_o  (div_done),
                .result_o(div_result)
            );
        end else begin : g_no_muldiv
            assign is_mul_op      = 1'b0;
            assign is_div_op      = 1'b0;
            assign div_start      = 1'b0;
            assign div_busy       = 1'b0;
            assign div_done       = 1'b0;
            assign div_emit_result = '0;
            assign muldiv_result = '0;
            assign md_stall      = 1'b0;
        end
    endgenerate

    assign mul_div_stall_o = md_stall;
    assign div_busy_o      = div_active_q;
    assign div_emit_accept = !stall_i && div_active_q && (div_ready_q || div_done);

    assign mret_req_o   = dinstr_i.valid && dinstr_i.op == MRET;

    always_comb begin
        unique case (dinstr_i.a_sel)
            A_PC:    alu_a = dinstr_i.pc;
            A_ZERO:  alu_a = '0;
            default: alu_a = rs1_rdata_i;
        endcase
        unique case (dinstr_i.b_sel)
            B_IMM:   alu_b = dinstr_i.imm;
            default: alu_b = rs2_rdata_i;
        endcase
    end

    assign pc_plus4  = dinstr_i.pc + 32'd4;
    assign pc_target = (dinstr_i.op == JALR) ? (alu_result & ~32'd1) : alu_result;

    anv32_alu alu (
        .op_i    (dinstr_i.alu_op),
        .a_i     (alu_a),
        .b_i     (alu_b),
        .result_o(alu_result)
    );

    // Exceptions detected here: a misaligned load/store address, or a taken
    // jump/branch to an address that is not 4-byte aligned (no C extension).
    logic mem_misaligned_exc, fetch_misaligned_exc;

    assign mem_misaligned_exc   = dinstr_i.is_mem && mem_misaligned(dinstr_i.op, alu_result[1:0]);
    assign fetch_misaligned_exc = dinstr_i.is_pc_changer && branch_taken_i && pc_target[1];

    assign trap_req_o = dinstr_i.valid &&
                        (dinstr_i.exc_valid || mem_misaligned_exc || fetch_misaligned_exc);
    assign trap_pc_o  = dinstr_i.pc;

    always_comb begin : trap_info_comb
        if (dinstr_i.exc_valid) begin
            trap_cause_o = dinstr_i.exc_cause;
            trap_tval_o  = dinstr_i.exc_tval;
        end else if (mem_misaligned_exc) begin
            trap_cause_o = mcause_exception(is_load(dinstr_i.op) ? MCAUSE_LOAD_ADDR_MISALIGNED
                                                              : MCAUSE_STORE_ADDR_MISALIGNED);
            trap_tval_o  = alu_result;
        end else begin
            trap_cause_o = mcause_exception(MCAUSE_INSTR_ADDR_MISALIGNED);
            trap_tval_o  = pc_target;
        end
    end

    anv32_csr_exec csr_exec (
        .valid_i    (dinstr_i.valid && dinstr_i.is_csr),
        .csr_op_i   (dinstr_i.csr_op),
        .csr_imm_i  (dinstr_i.csr_imm),
        .csr_addr_i (dinstr_i.csr_addr),
        .rs1_idx_i  (dinstr_i.rs1_idx),
        .rs1_rdata_i(rs1_rdata_i),
        .csr_rdata_i(csr_rdata_i),
        .csr_we_o   (csr_we),
        .csr_wdata_o(csr_wdata),
        .rd_wdata_o (csr_rd_wdata)
    );

    assign pc_target_o    = pc_target;
    assign pc_changer_o   = dinstr_i.is_pc_changer;
    assign valid_o        = dinstr_i.valid;

    always_ff @(posedge clk_i) begin
        // While stalled, einstr_o is the M-stage instruction waiting on memory,
        // so a trap/MRET in E must not clear it. kill_i (an interrupt) is
        // never raised during a memory wait.
        if (rst_i || kill_i || ((trap_req_o || mret_req_o) && !stall_i)) begin
            einstr_o <= '0;
            div_active_q <= 1'b0;
            div_ready_q <= 1'b0;
            div_result_q <= '0;
            div_write_data_q <= '0;
            div_dinstr_q <= '0;
        end else if (!stall_i) begin
            if (div_emit_accept) begin
                einstr_o.valid         <= div_dinstr_q.valid;
                einstr_o.alu_result    <= div_emit_result;
                einstr_o.write_data    <= div_write_data_q;
                einstr_o.link_pc       <= div_dinstr_q.pc + 32'd4;
                einstr_o.branch_taken  <= 1'b0;
                einstr_o.pc_target     <= '0;
                einstr_o.rd_idx        <= div_dinstr_q.rd_idx;
                einstr_o.rd_valid      <= div_dinstr_q.rd_valid;
                einstr_o.wb_sel        <= div_dinstr_q.wb_sel;
                einstr_o.op            <= div_dinstr_q.op;
                einstr_o.is_mem        <= div_dinstr_q.is_mem;
                einstr_o.is_pc_changer <= div_dinstr_q.is_pc_changer;
                einstr_o.is_csr        <= div_dinstr_q.is_csr;
                einstr_o.csr_addr      <= div_dinstr_q.csr_addr;
                einstr_o.csr_we        <= 1'b0;
                einstr_o.csr_wdata     <= '0;
                einstr_o.pc            <= div_dinstr_q.pc;
                einstr_o.instr         <= div_dinstr_q.instr;
                div_active_q           <= 1'b0;
                div_ready_q            <= 1'b0;
            end else begin
                einstr_o.valid         <= dinstr_i.valid;
                einstr_o.alu_result    <= dinstr_i.is_csr             ? csr_rd_wdata  :
                                          (HAS_M && dinstr_i.is_muldiv)? muldiv_result :
                                                                         alu_result;
                einstr_o.write_data    <= rs2_rdata_i;
                einstr_o.link_pc       <= pc_plus4;
                einstr_o.branch_taken  <= 1'b0;
                einstr_o.pc_target     <= pc_target;
                einstr_o.rd_idx        <= dinstr_i.rd_idx;
                einstr_o.rd_valid      <= dinstr_i.rd_valid;
                einstr_o.wb_sel        <= dinstr_i.wb_sel;
                einstr_o.op            <= dinstr_i.op;
                einstr_o.is_mem        <= dinstr_i.is_mem;
                einstr_o.is_pc_changer <= dinstr_i.is_pc_changer;
                einstr_o.is_csr        <= dinstr_i.is_csr;
                einstr_o.csr_addr      <= dinstr_i.csr_addr;
                einstr_o.csr_we        <= csr_we;
                einstr_o.csr_wdata     <= csr_wdata;
                einstr_o.pc            <= dinstr_i.pc;
                einstr_o.instr         <= dinstr_i.instr;
            end
        end else if (md_stall) begin
            einstr_o <= '0;
        end

        if (!(rst_i || trap_req_o || mret_req_o || kill_i)) begin
            if (div_start) begin
                div_active_q     <= 1'b1;
                div_ready_q      <= 1'b0;
                div_dinstr_q     <= dinstr_i;
                div_write_data_q <= rs2_rdata_i;
            end else if (div_active_q && div_done && !div_ready_q && !div_emit_accept) begin
                div_ready_q  <= 1'b1;
                div_result_q <= div_emit_result;
            end
        end
    end
endmodule
