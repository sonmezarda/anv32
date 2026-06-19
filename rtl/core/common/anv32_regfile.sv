module anv32_regfile
    import anv32_config_pkg::*;
(
    input  logic            clk_i,
    input  logic            we_i,
    input  logic [4:0]      rs1_idx_i,
    input  logic [4:0]      rs2_idx_i,
    input  logic [4:0]      rd_idx_i,
    input  logic [XLEN-1:0] rd_wdata_i,

    output logic [XLEN-1:0] rs1_rdata_o,
    output logic [XLEN-1:0] rs2_rdata_o
);
    logic [XLEN-1:0] regfile [31:0];

    assign rs1_rdata_o = (rs1_idx_i != 5'd0) ? regfile[rs1_idx_i] : '0;
    assign rs2_rdata_o = (rs2_idx_i != 5'd0) ? regfile[rs2_idx_i] : '0;

    always_ff @(posedge clk_i) begin
        if (we_i && rd_idx_i != 5'd0) begin
            regfile[rd_idx_i] <= rd_wdata_i;
        end
    end
endmodule
