module anv32_execute_i_c1
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
(
    input  logic               clk_i,
    input  logic               rst_i,
    input  logic               stall_i,
    input  logic               kill_i,

    input  dinstr_t            dinstr_i,
    input  logic    [XLEN-1:0] rs1_rdata_i,
    input  logic    [XLEN-1:0] rs2_rdata_i,
    input  logic    [XLEN-1:0] csr_rdata_i,

    output logic               branch_taken_o,
    output logic    [XLEN-1:0] pc_target_o,
    output logic               pc_changer_o,
    output logic               valid_o,
    output einstr_t            einstr_o,

    output logic               trap_req_o,
    output logic    [XLEN-1:0] trap_pc_o,
    output logic    [XLEN-1:0] trap_cause_o,
    output logic    [XLEN-1:0] trap_tval_o,
    output logic               mret_req_o

);
    logic [XLEN-1:0] alu_a, alu_b, alu_result;
    logic [XLEN-1:0] csr_wdata, csr_rd_wdata;
    logic [XLEN-1:0] pc_plus4, pc_target;
    logic            branch_taken;
    logic            csr_we;

    assign trap_req_o   = dinstr_i.valid && dinstr_i.exc_valid;
    assign trap_pc_o    = dinstr_i.pc;
    assign trap_cause_o = dinstr_i.exc_cause;
    assign trap_tval_o  = dinstr_i.exc_tval;
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

    always_comb begin : branch_taken_comb
        unique case (dinstr_i.op)
            JAL, JALR: branch_taken = 1'b1;
            BEQ:  branch_taken = (rs1_rdata_i == rs2_rdata_i);
            BNE:  branch_taken = (rs1_rdata_i != rs2_rdata_i);
            BLT:  branch_taken = ($signed(rs1_rdata_i) <  $signed(rs2_rdata_i));
            BGE:  branch_taken = ($signed(rs1_rdata_i) >= $signed(rs2_rdata_i));
            BLTU: branch_taken = (rs1_rdata_i <  rs2_rdata_i);
            BGEU: branch_taken = (rs1_rdata_i >= rs2_rdata_i);
            default: branch_taken = 1'b0;
        endcase
    end

    anv32_alu alu (
        .op_i    (dinstr_i.alu_op),
        .a_i     (alu_a),
        .b_i     (alu_b),
        .result_o(alu_result)
    );

    anv32_csr_exec csr_exec (
        .valid_i    (dinstr_i.valid && dinstr_i.is_csr),
        .csr_op_i   (dinstr_i.csr_op),
        .csr_imm_i  (dinstr_i.csr_imm),
        .rs1_idx_i  (dinstr_i.rs1_idx),
        .rs1_rdata_i(rs1_rdata_i),
        .csr_rdata_i(csr_rdata_i),
        .csr_we_o   (csr_we),
        .csr_wdata_o(csr_wdata),
        .rd_wdata_o (csr_rd_wdata)
    );

    assign branch_taken_o = branch_taken;
    assign pc_target_o    = pc_target;
    assign pc_changer_o   = dinstr_i.is_pc_changer;
    assign valid_o        = dinstr_i.valid;

    always_ff @(posedge clk_i) begin
        if (rst_i || trap_req_o || mret_req_o || kill_i) begin
            einstr_o <= '0;
        end else if (!stall_i) begin
            einstr_o.valid         <= dinstr_i.valid;
            einstr_o.alu_result    <= dinstr_i.is_csr ? csr_rd_wdata : alu_result;
            einstr_o.write_data    <= rs2_rdata_i;
            einstr_o.link_pc       <= pc_plus4;
            einstr_o.branch_taken  <= branch_taken;
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
            einstr_o.is_halt       <= dinstr_i.is_halt;
            einstr_o.pc            <= dinstr_i.pc;
            einstr_o.id            <= dinstr_i.id;
            einstr_o.instr         <= dinstr_i.instr;
        end
    end

endmodule
