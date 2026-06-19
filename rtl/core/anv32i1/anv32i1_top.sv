module anv32i1_top (
    input  logic        clk_i, rst_i, stall_i, pc_jmp_en_i,
    input  logic [31:0] pc_jmp_addr_i,
    output logic [31:0] instr_o, pc_o,
    output logic        instr_valid_o
);
    logic [31:0] fetch_addr, bram_instr;

    anv32i1_fetch_stage #(.PC_RESET_VALUE('h0)) fetch (
        .clk_i, .rst_i, .stall_i,
        .pc_jmp_en_i, .pc_jmp_addr_i,
        .instr_i(bram_instr),
        .fetch_addr_o(fetch_addr),
        .finstr_o({pc_o, instr_o, instr_valid_o})
    );

    anv32_bram_tdp #(.ADDR_W(10), .INIT_FILE("./sim/data/fetch_test.hex")) prog_mem (
        .clk(clk_i),
        .addr_a(fetch_addr[11:2]), .wdata_a(32'b0), .we_a(1'b0), .rdata_a(bram_instr),
        .addr_b(10'b0), .wdata_b(32'b0), .we_b(1'b0), .rdata_b()
    );
endmodule