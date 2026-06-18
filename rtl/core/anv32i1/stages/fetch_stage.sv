module fetch_stage
    import anv32_config_pkg::*;
#(
    parameter int PC_RESET_VALUE = 'h8000_0000
)
(   
    input  logic            clk_i,
    input  logic            rst_i,
    input  logic            stall_i,
    input  logic [XLEN-1:0] pc_jmp_addr_i,
    input  logic            pc_jmp_en_i,
    input  logic [XLEN-1:0] instr_i,

    output logic [XLEN-1:0] pc_o,
    output logic [XLEN-1:0] instr_o
);
    logic [XLEN-1:0] pc_current;
    logic [XLEN-1:0] pc_next;
    logic [XLEN-1:0] pc_plus_4;

    assign pc_plus_4 = pc_current + 'h4;
    always_comb begin
        if (stall_i)
            pc_next = pc_current; // Hold the current PC if stalled
        else if (pc_jmp_en_i)
            pc_next = pc_jmp_addr_i; // Jump to the target address if jump enabled
        else
            pc_next = pc_plus_4; // Otherwise, move to the next instruction
    end

    anv32_pc #(
        .PC_RESET_VALUE(PC_RESET_VALUE)
    ) pc_inst(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .pc_next_i(pc_next),
        .pc_current_o(pc_o)
    );

    assign instr_o = instr_i; // Pass the fetched (prog mem will be act as register)

endmodule