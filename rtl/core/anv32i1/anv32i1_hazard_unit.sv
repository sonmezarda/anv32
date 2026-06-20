module anv32i1_hazard_unit
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
(
    input  logic clk_i,
    input  logic rst_i,
    input  logic stall_i,

    input  logic branch_taken_i,
    input  dinstr_t dinstr_i, // instr after decode 
    input  einstr_t einstr_i, // instr after execute
    input  minstr_t minstr_i,  // instr after mem stage
    
    output logic flush_DE_o,
    output logic stall_DE_o,
    output logic stall_F_o,
    output fwd_sel_e rs1_fwd_sel,
    output fwd_sel_e rs2_fwd_sel
    // output logic flush_F_o,
    // output logic flush_M_o
);
    assign flush_DE_o = branch_taken_i;
    logic drs1_need_m, drs2_need_m;
    logic drs1_need_wb, drs2_need_wb;
    assign drs1_need_m =
        dinstr_i.valid &&
        einstr_i.valid &&
        dinstr_i.rs1_valid &&
        einstr_i.rd_valid &&
        (dinstr_i.rs1_idx != 5'd0) &&
        (dinstr_i.rs1_idx == einstr_i.rd_idx);

    assign drs2_need_m =
        dinstr_i.valid &&
        einstr_i.valid &&
        dinstr_i.rs2_valid &&
        einstr_i.rd_valid &&
        (dinstr_i.rs2_idx != 5'd0) &&
        (dinstr_i.rs2_idx == einstr_i.rd_idx);

    assign drs1_need_wb =
        dinstr_i.valid &&
        dinstr_i.rs1_valid &&
        minstr_i.valid &&
        minstr_i.rd_valid &&
        (dinstr_i.rs1_idx != 5'd0) &&
        (dinstr_i.rs1_idx == minstr_i.rd_idx);

    assign drs2_need_wb =
        dinstr_i.valid &&
        dinstr_i.rs2_valid &&
        minstr_i.valid &&
        minstr_i.rd_valid &&
        (dinstr_i.rs2_idx != 5'd0) &&
        (dinstr_i.rs2_idx == minstr_i.rd_idx);

    always_comb begin : ld_RAW_hazard_comb
        stall_DE_o  = 1'b0;
        stall_F_o   = 1'b0;
        rs1_fwd_sel = FWD_REG;
        rs2_fwd_sel = FWD_REG;

        if (drs1_need_m) begin
            if (einstr_i.wb_sel == WB_MEM) begin
                stall_DE_o = 1'b1;
                stall_F_o  = 1'b1;
            end else begin
                rs1_fwd_sel = FWD_M;
            end
        end else if (drs1_need_wb) begin
            rs1_fwd_sel = FWD_W;
        end

        if (drs2_need_m) begin
            if (einstr_i.wb_sel == WB_MEM) begin
                stall_DE_o = 1'b1;
                stall_F_o  = 1'b1;
            end else begin
                rs2_fwd_sel = FWD_M;
            end
        end else if (drs2_need_wb) begin
            rs2_fwd_sel = FWD_W;
        end
    end

endmodule