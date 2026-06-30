module anv32_forward_unit_im2
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
(
    input  logic [4:0]      rs1_idx_i,
    input  logic [4:0]      rs2_idx_i,
    input  logic [XLEN-1:0] rs1_rdata_i,
    input  logic [XLEN-1:0] rs2_rdata_i,

    input  dinstr_t         dinstr_decode_i,
    input  dinstr_t         dinstr_e1_i,
    input  dinstr_t         dinstr_e2_i,
    input  einstr_t         einstr_i,
    input  minstr_t         minstr_i,

    input  logic            e2_fwd_valid_i,
    input  logic            e2_fwd_ready_i,
    input  logic [4:0]      e2_fwd_rd_idx_i,
    input  logic [XLEN-1:0] e2_fwd_data_i,
    input  logic [XLEN-1:0] rd_wdata_i,

    output logic [XLEN-1:0] rs1_D_din_o,
    output logic [XLEN-1:0] rs2_D_din_o,
    output logic [XLEN-1:0] rs1_E1_din_o,
    output logic [XLEN-1:0] rs2_E1_din_o,
    output logic            stall_raw_o
);
    logic [XLEN-1:0] m_fwd_data;

    function automatic logic src_match_dinstr(
        input logic       src_valid_i,
        input logic [4:0] src_idx_i,
        input dinstr_t    producer_i
    );
        return src_valid_i &&
               src_idx_i != 5'd0 &&
               producer_i.valid &&
               producer_i.rd_valid &&
               src_idx_i == producer_i.rd_idx;
    endfunction

    function automatic logic src_match_einstr(
        input logic       src_valid_i,
        input logic [4:0] src_idx_i,
        input einstr_t    producer_i
    );
        return src_valid_i &&
               src_idx_i != 5'd0 &&
               producer_i.valid &&
               producer_i.rd_valid &&
               src_idx_i == producer_i.rd_idx;
    endfunction

    function automatic logic src_match_minstr(
        input logic       src_valid_i,
        input logic [4:0] src_idx_i,
        input minstr_t    producer_i
    );
        return src_valid_i &&
               src_idx_i != 5'd0 &&
               producer_i.valid &&
               producer_i.rd_valid &&
               src_idx_i == producer_i.rd_idx;
    endfunction

    function automatic logic e2_match(
        input logic       src_valid_i,
        input logic [4:0] src_idx_i
    );
        return src_valid_i &&
               src_idx_i != 5'd0 &&
               e2_fwd_valid_i &&
               src_idx_i == e2_fwd_rd_idx_i;
    endfunction

    function automatic logic is_div_result(input op_e op_i);
        unique case (op_i)
            DIV, DIVU, REM, REMU: return 1'b1;
            default:             return 1'b0;
        endcase
    endfunction

    function automatic logic src_waits_for_not_ready_result(
        input logic       src_valid_i,
        input logic [4:0] src_idx_i
    );
        return (src_match_dinstr(src_valid_i, src_idx_i, dinstr_e1_i) &&
                (dinstr_e1_i.wb_sel == WB_MEM || is_div_result(dinstr_e1_i.op))) ||
               (e2_match(src_valid_i, src_idx_i) &&
                !e2_fwd_ready_i) ||
               (src_match_einstr(src_valid_i, src_idx_i, einstr_i) &&
                einstr_i.wb_sel == WB_MEM);
    endfunction

    function automatic logic [XLEN-1:0] select_e1_operand(
        input logic            src_valid_i,
        input logic [4:0]      src_idx_i,
        input logic [XLEN-1:0] reg_value_i
    );
        if (e2_match(src_valid_i, src_idx_i) && e2_fwd_ready_i) begin
            return e2_fwd_data_i;
        end else if (src_match_einstr(src_valid_i, src_idx_i, einstr_i) &&
                     einstr_i.wb_sel != WB_MEM) begin
            return m_fwd_data;
        end else if (src_match_minstr(src_valid_i, src_idx_i, minstr_i)) begin
            return rd_wdata_i;
        end else begin
            return reg_value_i;
        end
    endfunction

    always_comb begin
        unique case (einstr_i.wb_sel)
            WB_ALU:  m_fwd_data = einstr_i.alu_result;
            WB_PC4:  m_fwd_data = einstr_i.link_pc;
            default: m_fwd_data = '0;
        endcase
    end

    always_comb begin : decode_bypass_comb
        if (minstr_i.valid && minstr_i.rd_valid && minstr_i.rd_idx != 5'd0 &&
            minstr_i.rd_idx == rs1_idx_i) begin
            rs1_D_din_o = rd_wdata_i;
        end else begin
            rs1_D_din_o = rs1_rdata_i;
        end

        if (minstr_i.valid && minstr_i.rd_valid && minstr_i.rd_idx != 5'd0 &&
            minstr_i.rd_idx == rs2_idx_i) begin
            rs2_D_din_o = rd_wdata_i;
        end else begin
            rs2_D_din_o = rs2_rdata_i;
        end
    end

    always_comb begin : e1_forward_comb
        rs1_E1_din_o = select_e1_operand(
            dinstr_e1_i.rs1_valid,
            dinstr_e1_i.rs1_idx,
            dinstr_e1_i.rs1_rdata
        );
        rs2_E1_din_o = select_e1_operand(
            dinstr_e1_i.rs2_valid,
            dinstr_e1_i.rs2_idx,
            dinstr_e1_i.rs2_rdata
        );
    end

    always_comb begin : raw_stall_comb
        stall_raw_o = dinstr_decode_i.valid &&
            (src_waits_for_not_ready_result(dinstr_decode_i.rs1_valid, dinstr_decode_i.rs1_idx) ||
             src_waits_for_not_ready_result(dinstr_decode_i.rs2_valid, dinstr_decode_i.rs2_idx));
    end
endmodule
