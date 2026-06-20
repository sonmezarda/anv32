module anv32i1_DE_stage
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
(
    input  logic               clk_i,
    input  logic               rst_i,
    input  logic               stall_i,
    input  logic               flush_i,

    input  finstr_t            finstr_i,    // from fetch
    input  logic    [XLEN-1:0] rs1_rdata_i, // from regfile
    input  logic    [XLEN-1:0] rs2_rdata_i, // from regfile
    output logic    [4:0]      rs1_idx_o,   // to regfile
    output logic    [4:0]      rs2_idx_o,   // to regfile
    output einstr_t            einstr_o,    // to mem + writeback
    output dinstr_t            dinstr_o     // for debug and hazard unit
);
    dinstr_t dinstr;
    assign dinstr_o = dinstr;
    logic [XLEN-1:0] alu_a, alu_b, alu_result;
    logic [XLEN-1:0] pc_plus4, pc_target;
    logic            branch_taken;

    // regfile okuma adresleri
    assign rs1_idx_o = dinstr.rs1_idx;
    assign rs2_idx_o = dinstr.rs2_idx;

    // --- ALU operand seçimi (kontrol decoder'dan) ---
    always_comb begin
        unique case (dinstr.a_sel)
            A_PC:    alu_a = finstr_i.pc;
            A_ZERO:  alu_a = '0;
            default: alu_a = rs1_rdata_i;   // A_RS1
        endcase
        unique case (dinstr.b_sel)
            B_IMM:   alu_b = dinstr.imm;
            default: alu_b = rs2_rdata_i;   // B_RS2
        endcase
    end

    // --- link and branch/jump target ---
    assign pc_plus4  = finstr_i.pc + 32'd4;
    // JAL/branch target = pc+imm = alu_result
    assign pc_target = (dinstr.op == JALR) ? (alu_result & ~32'd1) : alu_result;

    // --- branch comparator ---
    always_comb begin : branch_taken_comb
        unique case (dinstr.op)
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

    anv32_decoder decoder (
        .instr_i (finstr_i.instr),
        .pc_i    (finstr_i.pc),
        .id_i    ('0),                 // TODO: commit id
        .dinstr_o(dinstr)
    );

    anv32_alu alu (
        .op_i    (dinstr.alu_op),
        .a_i     (alu_a),
        .b_i     (alu_b),
        .result_o(alu_result)
    );

    // --- DE/MEM pipeline register ---
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            einstr_o <= '0;
        end else if (flush_i) begin
            einstr_o <= '0;
        end else if (!stall_i) begin
            einstr_o.valid         <= finstr_i.valid && dinstr.valid;
            einstr_o.alu_result    <= alu_result;
            einstr_o.write_data    <= rs2_rdata_i;
            einstr_o.link_pc       <= pc_plus4;
            einstr_o.branch_taken  <= branch_taken;
            einstr_o.pc_target     <= pc_target;
            // control passthrough
            einstr_o.rd_idx        <= dinstr.rd_idx;
            einstr_o.rd_valid      <= dinstr.rd_valid;
            einstr_o.wb_sel        <= dinstr.wb_sel;
            einstr_o.op            <= dinstr.op;
            einstr_o.is_mem        <= dinstr.is_mem;
            einstr_o.is_pc_changer <= dinstr.is_pc_changer;
            einstr_o.is_halt       <= dinstr.is_halt;
            einstr_o.pc            <= dinstr.pc;
            einstr_o.id            <= dinstr.id;
            einstr_o.instr         <= dinstr.instr;
        end
    end
endmodule
