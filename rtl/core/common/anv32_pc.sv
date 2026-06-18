module anv32_pc
    import anv32_config_pkg::*;
#(
    parameter int PC_RESET_VALUE = 'h8000_0000
)
(
    input  logic            clk_i,
    input  logic            rst_i,
    input  logic [XLEN-1:0] pc_next_i,
    output logic [XLEN-1:0] pc_current_o
);
    logic [XLEN-1:0] pc_reg;

    always_ff @(posedge clk_i) begin : update_pc_ff
        if(rst_i) 
            pc_reg <= PC_RESET_VALUE;
        else
            pc_reg <= pc_next_i;
    end

    assign pc_current_o = pc_reg;

endmodule