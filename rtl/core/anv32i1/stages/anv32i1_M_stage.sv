module anv32i1_M_stage
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
(
    input  logic            clk_i,
    input  logic            rst_i,
    input  logic            stall_i,
    input  einstr_t         einstr_i,
    input  logic [XLEN-1:0] mem_rdata_i, 

    output logic [XLEN-1:0] mem_addr_o,
    output logic [XLEN-1:0] mem_wdata_o,
    output logic [3:0]      mem_we_o,
    output logic [XLEN-1:0] mem_rdata_o,
    output minstr_t         minstr_o
);
    logic [XLEN-1:0] load_data;
    logic [XLEN-1:0] load_data_hold;
    logic [7:0]      load_byte;
    logic [15:0]     load_half;
    minstr_t         minstr;

    assign mem_addr_o = einstr_i.alu_result;
    assign minstr_o = minstr;
    assign mem_rdata_o = stall_i ? load_data_hold : load_data;

    always_comb begin
        mem_we_o    = 4'b0000;
        mem_wdata_o = 32'b0;

        if (einstr_i.valid && einstr_i.is_mem) begin
            unique case (einstr_i.op)
                SB: begin
                    mem_we_o    = 4'b0001 << einstr_i.alu_result[1:0];
                    mem_wdata_o = {24'b0, einstr_i.write_data[7:0]}
                                << (8 * einstr_i.alu_result[1:0]);
                end
                SH: begin
                    mem_we_o    = 4'b0011 << {einstr_i.alu_result[1], 1'b0};
                    mem_wdata_o = {16'b0, einstr_i.write_data[15:0]}
                                << (8 * {einstr_i.alu_result[1], 1'b0});
                end
                SW: begin
                    mem_we_o    = 4'b1111;
                    mem_wdata_o = einstr_i.write_data;
                end
                default: begin
                    mem_we_o    = 4'b0000;
                    mem_wdata_o = 32'b0;
                end
            endcase
        end
    end

    always_comb begin
        load_byte = mem_rdata_i[8 * minstr.alu_result[1:0] +: 8];
        load_half = mem_rdata_i[16 * minstr.alu_result[1] +: 16];

        unique case (minstr.op)
            LB:      load_data = {{24{load_byte[7]}}, load_byte};
            LBU:     load_data = {24'b0, load_byte};
            LH:      load_data = {{16{load_half[15]}}, load_half};
            LHU:     load_data = {16'b0, load_half};
            default: load_data = mem_rdata_i; // LW and non-load passthrough
        endcase
    end

    always_ff @(posedge clk_i) begin
        if(rst_i) begin
            minstr <= '0;
            load_data_hold <= '0;
        end else if(!stall_i) begin
            load_data_hold     <= load_data;
            minstr.valid       <= einstr_i.valid;
            minstr.pc          <= einstr_i.pc;
            minstr.instr       <= einstr_i.instr;
            minstr.link_pc     <= einstr_i.link_pc;
            minstr.alu_result  <= einstr_i.alu_result;
            minstr.rd_idx      <= einstr_i.rd_idx;
            minstr.rd_valid    <= einstr_i.rd_valid;
            minstr.wb_sel      <= einstr_i.wb_sel;
            minstr.op          <= einstr_i.op;
        end
    end

endmodule
