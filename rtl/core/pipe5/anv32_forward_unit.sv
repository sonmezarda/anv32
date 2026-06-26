module anv32_forward_unit
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
(
    input  logic [4:0]      rs1_idx_i,  
    input  logic [4:0]      rs2_idx_i,
    input  logic [XLEN-1:0] rs1_rdata_i,
    input  logic [XLEN-1:0] rs2_rdata_i,
 
    input  dinstr_t         dinstr_i,
    input  einstr_t         einstr_i,
    input  minstr_t         minstr_i,
 
    input  fwd_sel_e        rs1_fwd_sel_i,
    input  fwd_sel_e        rs2_fwd_sel_i,
    input  logic [XLEN-1:0] rd_wdata_i,

    output logic [XLEN-1:0] rs1_D_din_o,
    output logic [XLEN-1:0] rs2_D_din_o,
    output logic [XLEN-1:0] rs1_E_din_o,
    output logic [XLEN-1:0] rs2_E_din_o
);

    logic [XLEN-1:0] w_fwd_data;
    logic [XLEN-1:0] m_fwd_data;
    always_comb begin
        unique case (einstr_i.wb_sel)
            WB_ALU:  m_fwd_data = einstr_i.alu_result;
            WB_PC4:  m_fwd_data = einstr_i.link_pc;
            default: m_fwd_data = '0;
        endcase
    end

    assign w_fwd_data = rd_wdata_i;
    always_comb begin // decode bypass
        if (minstr_i.valid && minstr_i.rd_valid && minstr_i.rd_idx != 5'd0 &&
            minstr_i.rd_idx == rs1_idx_i)
            rs1_D_din_o = w_fwd_data;
        else
            rs1_D_din_o = rs1_rdata_i;

        if (minstr_i.valid && minstr_i.rd_valid && minstr_i.rd_idx != 5'd0 &&
            minstr_i.rd_idx == rs2_idx_i)
            rs2_D_din_o = w_fwd_data;
        else
            rs2_D_din_o = rs2_rdata_i;
    end

    always_comb begin // execute forwarding
        unique case (rs1_fwd_sel_i)
            FWD_M:   rs1_E_din_o = m_fwd_data;
            FWD_W:   rs1_E_din_o = w_fwd_data;
            default: rs1_E_din_o = dinstr_i.rs1_rdata;
        endcase

        unique case (rs2_fwd_sel_i)
            FWD_M:   rs2_E_din_o = m_fwd_data;
            FWD_W:   rs2_E_din_o = w_fwd_data;
            default: rs2_E_din_o = dinstr_i.rs2_rdata;
        endcase
    end

endmodule
