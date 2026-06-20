module anv32i1_top
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
#(
    parameter logic [XLEN-1:0] PC_RESET_VALUE = RESET_PC,
    parameter INIT_FILE = "./sim/data/prog.hex",
    parameter BRAM_ADDR_W = 10
)(
    input  logic            clk_i, rst_i, stall_i, pc_jmp_en_i,
    input  logic [31:0]     pc_jmp_addr_i,
    output logic [31:0]     instr_o, pc_o,
    output logic            instr_valid_o,

    input  logic [XLEN-1:0] mem_rdata_i,
    output logic [XLEN-1:0] mem_wdata_o,
    output logic [XLEN-1:0] mem_addr_o,
    output logic [3:0]      mem_we
);
    logic [XLEN-1:0] fetch_addr, bram_instr;

    assign mem_wdata_o = dmem_wdata;
    assign mem_addr_o  = m_stage_dmem_addr_out;
    assign mem_we      = dmem_we;

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
    dinstr_t                dinstr;

    assign instr_o       = finstr.instr;
    assign pc_o          = finstr.pc;
    assign instr_valid_o = finstr.valid;

    logic                   pc_jmp_en;
    logic [XLEN-1:0]        pc_jmp_addr;

    logic [XLEN-1:0]        rs1_rdata;
    logic [XLEN-1:0]        rs2_rdata;
    logic [XLEN-1:0]        rd_wdata;
    logic [4:0]             rd_idx;
    logic [4:0]             rs1_idx;
    logic [4:0]             rs2_idx;
    logic                   regfile_we;
    
    logic [XLEN-1:0]        m_stage_mem_out;
    logic [XLEN-1:0]        m_stage_dmem_addr_out;

    logic                   flush_DE;
    fwd_sel_e               rs1_fwd_sel;
    fwd_sel_e               rs2_fwd_sel;
    logic [XLEN-1:0]        m_fwd_data;
    logic [XLEN-1:0]        w_fwd_data;
    logic [XLEN-1:0]        rs1_DE_din;
    logic [XLEN-1:0]        rs2_DE_din;

    always_comb begin : pc_jump_comb
        pc_jmp_en   = einstr.branch_taken && einstr.valid && einstr.is_pc_changer;
        pc_jmp_addr = einstr.pc_target;
    end

    anv32i1_hazard_unit hazard_unit(
        .clk_i(clk_i), 
        .rst_i(rst_i), 
        .stall_i(1'b0),
        .branch_taken_i(pc_jmp_en),
        .dinstr_i(dinstr), // instr after decode 
        .einstr_i(einstr), // instr after execute
        .minstr_i(minstr),  // instr after mem stage
        .stall_DE_o(stall_de),
        .stall_F_o(stall_f),
        .rs1_fwd_sel(rs1_fwd_sel),
        .rs2_fwd_sel(rs2_fwd_sel),
        .flush_DE_o(flush_DE)
    );
    anv32i1_fetch_stage #(.PC_RESET_VALUE(PC_RESET_VALUE)) fetch (
        .clk_i(clk_i), 
        .rst_i(rst_i), 
        .stall_i(stall_f),
        .pc_jmp_en_i(pc_jmp_en), 
        .pc_jmp_addr_i(pc_jmp_addr),
        .instr_i(bram_instr),
        .fetch_addr_o(fetch_addr),
        .finstr_o(finstr)
    );

    always_comb begin : m_fwd_data_comb
        unique case (einstr.wb_sel)
            WB_ALU:  m_fwd_data = einstr.alu_result;
            WB_PC4:  m_fwd_data = einstr.link_pc;
            default: m_fwd_data = '0;
        endcase
    end

    assign w_fwd_data = rd_wdata;

    always_comb begin : fwd_mux_comb
        unique case (rs1_fwd_sel)
            FWD_M:   rs1_DE_din = m_fwd_data;
            FWD_W:   rs1_DE_din = w_fwd_data;
            default: rs1_DE_din = rs1_rdata;
        endcase

        unique case (rs2_fwd_sel)
            FWD_M:   rs2_DE_din = m_fwd_data;
            FWD_W:   rs2_DE_din = w_fwd_data;
            default: rs2_DE_din = rs2_rdata;
        endcase
    end

    anv32i1_DE_stage DE(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .flush_i(flush_DE),
        .stall_i(stall_de),
        .finstr_i(finstr),
        .rs1_rdata_i(rs1_DE_din),
        .rs2_rdata_i(rs2_DE_din),
        .rs1_idx_o(rs1_idx),
        .rs2_idx_o(rs2_idx),
        .einstr_o(einstr),
        .dinstr_o(dinstr)
    );

    anv32i1_M_stage M(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .stall_i(stall_m),
        .einstr_i(einstr),
        .mem_rdata_i(dmem_rdata),
        .mem_addr_o(m_stage_dmem_addr_out),   //
        .mem_wdata_o(dmem_wdata),
        .mem_we_o(dmem_we),
        .mem_rdata_o(m_stage_mem_out),
        .minstr_o(minstr)
    );

    anv32i1_W_stage W(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .stall_i(stall_w),
        .minstr_i(minstr),
        .mem_rdata_i(m_stage_mem_out),

        .rd_wen_o(regfile_we),
        .rd_wdata_o(rd_wdata),
        .rd_idx_o(rd_idx)
    );

    assign pmem_addr = fetch_addr[BRAM_ADDR_W+1:2];
    assign dmem_addr = m_stage_dmem_addr_out[BRAM_ADDR_W+1:2];
    assign bram_instr = pmem_rdata;
    assign pmem_we = 4'b0;
    assign pmem_wdata = 32'b0;
    assign stall_m = 1'b0;
    assign stall_w = 1'b0;

    anv32_bram_tdp #(
        .ADDR_W(BRAM_ADDR_W), 
        .INIT_FILE(INIT_FILE)) prog_mem (
        .clk(clk_i),

        .addr_a(pmem_addr), 
        .wdata_a(pmem_wdata), 
        .we_a(pmem_we), 
        .rdata_a(pmem_rdata),

        .addr_b(dmem_addr), 
        .wdata_b(dmem_wdata), 
        .we_b(dmem_we), 
        .rdata_b(dmem_rdata)
    );

    anv32_regfile regfile (
        .clk_i(clk_i),
        .we_i(regfile_we),
        .rs1_idx_i(rs1_idx),
        .rs2_idx_i(rs2_idx),
        .rd_idx_i(rd_idx),
        .rd_wdata_i(rd_wdata),
        .rs1_rdata_o(rs1_rdata),
        .rs2_rdata_o(rs2_rdata)
    );
endmodule
