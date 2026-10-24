module anv32_hazard_basic
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
(
    input  logic branch_taken_i,
    input  dinstr_t dinstr_d_i, // instr currently in decode
    input  dinstr_t dinstr_e_i, // instr currently in execute
    input  einstr_t einstr_i,   // instr after execute
    input  minstr_t minstr_i,   // instr after mem stage
    output logic flush_D_o,
    output logic stall_DE_o,
    output logic stall_F_o,
    output fwd_sel_e rs1_fwd_sel,
    output fwd_sel_e rs2_fwd_sel
);
    assign flush_D_o = branch_taken_i;
    logic drs1_need_e, drs2_need_e;
    logic ers1_need_m, ers2_need_m;
    logic ers1_need_wb, ers2_need_wb;

    assign drs1_need_e =
        dinstr_d_i.valid &&
        dinstr_e_i.valid &&
        dinstr_d_i.rs1_valid &&
        dinstr_e_i.rd_valid &&
        (dinstr_d_i.rs1_idx != 5'd0) &&
        (dinstr_d_i.rs1_idx == dinstr_e_i.rd_idx);

    assign drs2_need_e =
        dinstr_d_i.valid &&
        dinstr_e_i.valid &&
        dinstr_d_i.rs2_valid &&
        dinstr_e_i.rd_valid &&
        (dinstr_d_i.rs2_idx != 5'd0) &&
        (dinstr_d_i.rs2_idx == dinstr_e_i.rd_idx);

    assign ers1_need_m =
        dinstr_e_i.valid &&
        einstr_i.valid &&
        dinstr_e_i.rs1_valid &&
        einstr_i.rd_valid &&
        (dinstr_e_i.rs1_idx != 5'd0) &&
        (dinstr_e_i.rs1_idx == einstr_i.rd_idx);

    assign ers2_need_m =
        dinstr_e_i.valid &&
        einstr_i.valid &&
        dinstr_e_i.rs2_valid &&
        einstr_i.rd_valid &&
        (dinstr_e_i.rs2_idx != 5'd0) &&
        (dinstr_e_i.rs2_idx == einstr_i.rd_idx);

    assign ers1_need_wb =
        dinstr_e_i.valid &&
        dinstr_e_i.rs1_valid &&
        minstr_i.valid &&
        minstr_i.rd_valid &&
        (dinstr_e_i.rs1_idx != 5'd0) &&
        (dinstr_e_i.rs1_idx == minstr_i.rd_idx);

    assign ers2_need_wb =
        dinstr_e_i.valid &&
        dinstr_e_i.rs2_valid &&
        minstr_i.valid &&
        minstr_i.rd_valid &&
        (dinstr_e_i.rs2_idx != 5'd0) &&
        (dinstr_e_i.rs2_idx == minstr_i.rd_idx);

    always_comb begin : ld_RAW_hazard_comb
        stall_DE_o  = 1'b0;
        stall_F_o   = 1'b0;
        rs1_fwd_sel = FWD_REG;
        rs2_fwd_sel = FWD_REG;

        if ((drs1_need_e || drs2_need_e) && dinstr_e_i.wb_sel == WB_MEM) begin
            stall_DE_o = 1'b1;
            stall_F_o  = 1'b1;
        end

        if (ers1_need_m && einstr_i.wb_sel != WB_MEM) begin
            rs1_fwd_sel = FWD_M;
        end else if (ers1_need_wb) begin
            rs1_fwd_sel = FWD_W;
        end

        if (ers2_need_m && einstr_i.wb_sel != WB_MEM) begin
            rs2_fwd_sel = FWD_M;
        end else if (ers2_need_wb) begin
            rs2_fwd_sel = FWD_W;
        end
    end

endmodule
