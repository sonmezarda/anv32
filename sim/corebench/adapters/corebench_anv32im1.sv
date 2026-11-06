// corebench adapter for anv32im1 (RV32IM, 5-stage pipeline). See
// docs/corebench.md for the corebench_core port contract.
module corebench_core (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        irq_i,

    output logic        instr_req_o,
    output logic [31:0] instr_addr_o,
    input  logic [31:0] instr_rdata_i,

    output logic        data_req_o,
    output logic        data_we_o,
    output logic [ 3:0] data_be_o,
    output logic [31:0] data_addr_o,
    output logic [31:0] data_wdata_o,
    input  logic [31:0] data_rdata_i,

    output logic        retire_o
);
    logic [3:0] mem_we;

    anv32im1_top #(.HAS_M(1'b1), .PC_RESET_VALUE(32'h0000_0000)) u_core (
        .clk_i        (clk_i),
        .rst_i        (!rst_ni),
        .stall_i      (1'b0),
        .pc_jmp_en_i  (1'b0),
        .pc_jmp_addr_i(32'b0),
        .ext_irq_i    (irq_i),
        .timer_irq_i  (1'b0),
        .sw_irq_i     (1'b0),
        .instr_o      (),
        .pc_o         (),
        .instr_valid_o(),
        .instr_i      (instr_rdata_i),
        .instr_addr_o (instr_addr_o),
        .instr_req_o  (instr_req_o),
        .instr_ready_i(1'b1),
        .mem_rdata_i  (data_rdata_i),
        .mem_ready_i  (1'b1),
        .mem_wdata_o  (data_wdata_o),
        .mem_addr_o   (data_addr_o),
        .mem_valid_o  (data_req_o),
        .mem_we       (mem_we)
    );

    assign data_we_o   = |mem_we;
    assign data_be_o   = data_we_o ? mem_we : 4'b1111;

`ifdef COREBENCH_SIM
    // Same event that increments minstret
    assign retire_o = u_core.minstr.valid && !u_core.stall_w_eff;
`else
    assign retire_o = 1'b0;
`endif
endmodule
