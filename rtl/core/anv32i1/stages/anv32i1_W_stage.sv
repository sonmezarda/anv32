module anv32i1_W_stage
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
(
    input  logic            clk_i,
    input  logic            rst_i,
    input  logic            stall_i,
    input  minstr_t         minstr_i,
    input  logic [XLEN-1:0] mem_rdata_i,

    output logic            rd_wen_o,
    output logic [XLEN-1:0] rd_wdata_o,
    output logic [4:0]      rd_idx_o
);
    logic [XLEN-1:0] result;
    assign rd_wen_o = ~rst_i && ~stall_i && minstr_i.valid && minstr_i.rd_valid;

    assign rd_idx_o = minstr_i.rd_idx;
    assign rd_wdata_o = result;

    always_comb begin : result_select_comb
        case(minstr_i.wb_sel)
            WB_ALU : result = minstr_i.alu_result; 
            WB_MEM : result = mem_rdata_i;
            WB_PC4 : result = minstr_i.link_pc;
            default: result = 0;
        endcase
    end

endmodule