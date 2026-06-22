module anv32_execute_im_c1(
    input  logic               clk_i,
    input  logic               rst_i,
    input  logic               stall_i,
    input  logic               kill_i,

    input  dinstr_t            dinstr_i,
    input  logic    [XLEN-1:0] rs1_rdata_i,
    input  logic    [XLEN-1:0] rs2_rdata_i,
    input  logic    [XLEN-1:0] csr_rdata_i,

    output logic               branch_taken_o,
    output logic    [XLEN-1:0] pc_target_o,
    output logic               pc_changer_o,
    output logic               valid_o,
    output einstr_t            einstr_o,

    output logic               trap_req_o,
    output logic    [XLEN-1:0] trap_pc_o,
    output logic    [XLEN-1:0] trap_cause_o,
    output logic    [XLEN-1:0] trap_tval_o,
    output logic               mret_req_o
);

endmodule