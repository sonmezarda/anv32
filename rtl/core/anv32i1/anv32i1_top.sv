module anv32i1_top
    import anv32_config_pkg::*;
#(
    parameter logic [XLEN-1:0] PC_RESET_VALUE = RESET_PC,
    parameter INIT_FILE = "./sim/data/fetch_test",
    parameter BRAM_ADDR_W = 10;
)(
    input  logic        clk_i, rst_i, stall_i, pc_jmp_en_i,
    input  logic [31:0] pc_jmp_addr_i,
    output logic [31:0] instr_o, pc_o,
    output logic        instr_valid_o
);
    logic [XLEN-1:0] fetch_addr, bram_instr;

    logic [BRAM_ADDR_W-1:0] dmem_addr;
    logic [XLEN-1:0]        dmem_wdata;
    logic [XLEN-1:0]        dmem_rdata;
    logic [3:0]             dmem_we;

    logic [BRAM_ADDR_W-1:0] pmem_addr;
    logic [XLEN-1:0]        pmem_wdata;
    logic [XLEN-1:0]        pmem_rdata;
    logic [3:0]             pmem_we;

    logic                   stall_f, stall_de, stall_m, stall_w;

    finstr_t                finstr;
    einstr_t                einstr;
    minstr_t                minstr;

    logic                   pc_jmp_en;
    logic [XLEN-1:0]        pc_jmp_addr;
    anv32i1_fetch_stage #(.PC_RESET_VALUE(PC_RESET_VALUE)) fetch (
        .clk_i(clk_i), 
        .rst_i(rst_i), 
        .stall_i(stall_f),
        .pc_jmp_en_i(), 
        .pc_jmp_addr_i(),
        .instr_i(bram_instr),
        .fetch_addr_o(fetch_addr),
        .finstr_o(finstr)
    );

    anv32i1_DE_stage DE(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .stall_i(stall_de),
        .finstr_i(finstr),
        .rs1_rdata_i(),
        .rs2_rdata_i(),
        .rs1_idx_o(),
        .rs2_idx_o(),
        .einstr_o(einstr)
    );

    always_comb begin : pc_jump_comb
        pc_jmp_en   = einstr.branch_taken && einstr.valid && einstr.is_pc_changer;
        pc_jmp_addr = einstr.pc_target;
    end

    anv32i1_M_stage M(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .stall_i(stall_m),
        .einstr_i(einstr),
        .mem_rdata_i(),

        .mem_addr_o(),
        .mem_wdata_o(),
        .mem_we_o(),
        .mem_rdata_o(),
        .minstr_o(minstr)
    );

    anv32i1_W_stage W(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .stall_i(stall_w),
        .minstr_i(minstr),
        .mem_rdata_i(),

        .rd_wen_o(),
        .rd_wdata_o(),
        .rd_idx_o()
    );

    assign pmem_addr = fetch_addr[11:2];
    anv32_bram_tdp #(
        .ADDR_W(BRAM_ADDR_W), 
        .INIT_FILE(INIT_FILE)) prog_mem (
        .clk(clk_i),

        .addr_a(pmem_addr), 
        .wdata_a(pmem_wdata), 
        .we_a(pmem_we), 
        .rdata_a(pmem_rdata),

        .addr_b(dmam_addr), 
        .wdata_b(dmem_wdata), 
        .we_b(dmem_we), 
        .rdata_b(dmem_rdata)
    );

    anv32_regfile regfile (
        .clk_i(clk_i),
        .we_i(),
        .rs1_idx_i(),
        .rs2_idx_i(),
        .rd_idx_i(),
        .rd_wdata_i(),
        .rs1_rdata_o(),
        .rs2_rdata_o()
    );
endmodule
