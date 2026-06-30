`timescale 1ns/1ps

module tb_benchmark
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
#(
    parameter INIT_FILE = "",
    parameter int unsigned MAX_CYCLES = 2000,
    parameter logic [XLEN-1:0] PC_RESET_VALUE = RESET_PC,
    parameter logic [31:0] EXPECT_X10 = 32'h00000001,
    parameter bit CHECK_X10 = 1'b1
);
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [31:0] pc_o;
    logic [31:0] instr_o;
    logic instr_valid_o;
    logic [31:0] instr_addr;
    logic [31:0] instr_rdata;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [31:0] mem_rdata;
    logic [3:0]  mem_we;
    logic        mem_valid;

    int unsigned cycle = 0;
    int unsigned commits = 0;
    int unsigned alu_ops = 0;
    int unsigned muldiv_ops = 0;
    int unsigned loads = 0;
    int unsigned stores = 0;
    int unsigned control_ops = 0;
    int unsigned jumps = 0;
    int unsigned branches = 0;
    int unsigned branches_taken = 0;
    int unsigned branches_not_taken = 0;
    int unsigned static_nt_mispredicts = 0;
    int unsigned static_nt_branch_mispredicts = 0;
    int unsigned raw_stall_cycles = 0;
    int unsigned load_use_stall_cycles = 0;
    int unsigned branch_redirect_cycles = 0;
    int unsigned muldiv_stall_cycles = 0;
    int unsigned mem_wait_stall_cycles = 0;
    bit halt_seen = 1'b0;
    bit pass = 1'b0;
    logic [31:0] final_x10;

    always #5 clk = ~clk;

`ifdef ANV32_BENCH_CORE_ANV32I1
    anv32i1_top #(
        .PC_RESET_VALUE(PC_RESET_VALUE)
    ) dut (
        .clk_i(clk),
        .rst_i(rst),
        .stall_i(1'b0),
        .pc_jmp_en_i(1'b0),
        .pc_jmp_addr_i('0),
        .ext_irq_i(1'b0),
        .pc_o(pc_o),
        .instr_o(instr_o),
        .instr_valid_o(instr_valid_o),
        .instr_i(instr_rdata),
        .instr_addr_o(instr_addr),
        .mem_rdata_i(mem_rdata),
        .mem_ready_i(1'b1),
        .mem_wdata_o(mem_wdata),
        .mem_addr_o(mem_addr),
        .mem_valid_o(),
        .mem_we(mem_we)
    );
    assign mem_valid = |mem_we;
`elsif ANV32_BENCH_CORE_ANV32IM1
    anv32im1_top #(
        .HAS_M(1'b1),
        .PC_RESET_VALUE(PC_RESET_VALUE)
    ) dut (
        .clk_i(clk),
        .rst_i(rst),
        .stall_i(1'b0),
        .pc_jmp_en_i(1'b0),
        .pc_jmp_addr_i('0),
        .ext_irq_i(1'b0),
        .pc_o(pc_o),
        .instr_o(instr_o),
        .instr_valid_o(instr_valid_o),
        .instr_i(instr_rdata),
        .instr_addr_o(instr_addr),
        .mem_rdata_i(mem_rdata),
        .mem_ready_i(1'b1),
        .mem_wdata_o(mem_wdata),
        .mem_addr_o(mem_addr),
        .mem_valid_o(),
        .mem_we(mem_we)
    );
    assign mem_valid = |mem_we;
`elsif ANV32_BENCH_CORE_ANV32IM2
    anv32im2_top #(
        .HAS_M(1'b1),
        .PC_RESET_VALUE(PC_RESET_VALUE)
    ) dut (
        .clk_i(clk),
        .rst_i(rst),
        .stall_i(1'b0),
        .pc_jmp_en_i(1'b0),
        .pc_jmp_addr_i('0),
        .ext_irq_i(1'b0),
        .pc_o(pc_o),
        .instr_o(instr_o),
        .instr_valid_o(instr_valid_o),
        .instr_i(instr_rdata),
        .instr_addr_o(instr_addr),
        .mem_rdata_i(mem_rdata),
        .mem_ready_i(1'b1),
        .mem_wdata_o(mem_wdata),
        .mem_addr_o(mem_addr),
        .mem_valid_o(mem_valid),
        .mem_we(mem_we)
    );
`else
    initial $fatal(1, "Define one ANV32_BENCH_CORE_* macro");
`endif

    anv32_bram_tdp #(
        .ADDR_W(10),
        .INIT_FILE(INIT_FILE)
    ) ram (
        .clk(clk),
        .addr_a(mem_addr[11:2]),
        .wdata_a(mem_wdata),
        .we_a(mem_we),
        .rdata_a(mem_rdata),
        .addr_b(instr_addr[11:2]),
        .wdata_b(32'b0),
        .we_b(4'b0),
        .rdata_b(instr_rdata)
    );

    function automatic bit is_cond_branch(input op_e op);
        unique case (op)
            BEQ, BNE, BLT, BGE, BLTU, BGEU: return 1'b1;
            default: return 1'b0;
        endcase
    endfunction

    function automatic bit is_jump(input op_e op);
        unique case (op)
            JAL, JALR: return 1'b1;
            default: return 1'b0;
        endcase
    endfunction

    function automatic bit is_load(input op_e op);
        unique case (op)
            LB, LH, LW, LBU, LHU: return 1'b1;
            default: return 1'b0;
        endcase
    endfunction

    function automatic bit is_store(input op_e op);
        unique case (op)
            SB, SH, SW: return 1'b1;
            default: return 1'b0;
        endcase
    endfunction

    function automatic bit is_alu(input op_e op);
        unique case (op)
            LUI, AUIPC,
            ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI,
            ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND:
                return 1'b1;
            default:
                return 1'b0;
        endcase
    endfunction

    function automatic bit is_muldiv(input op_e op);
        unique case (op)
            MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU: return 1'b1;
            default: return 1'b0;
        endcase
    endfunction

    task automatic sample_counters();
        bit ctrl_valid;
        bit actual_taken;
        bit load_use_hazard;
        op_e ctrl_op;

`ifdef ANV32_BENCH_CORE_ANV32I1
        if (dut.stall_de) begin
            raw_stall_cycles++;
            load_use_stall_cycles++;
        end
        if (dut.pc_jmp_en) begin
            branch_redirect_cycles++;
        end
`elsif ANV32_BENCH_CORE_ANV32IM1
        if (dut.stall_d) begin
            raw_stall_cycles++;
            load_use_stall_cycles++;
        end
        if (dut.md_stall) begin
            muldiv_stall_cycles++;
        end
        if (dut.pc_jmp_en) begin
            branch_redirect_cycles++;
        end
`elsif ANV32_BENCH_CORE_ANV32IM2
        load_use_hazard =
            dut.dinstr_decode.valid &&
            (((dut.dinstr_decode.rs1_valid && dut.dinstr_decode.rs1_idx != 5'd0) &&
              ((dut.dinstr.valid && dut.dinstr.rd_valid && dut.dinstr.wb_sel == WB_MEM &&
                dut.dinstr_decode.rs1_idx == dut.dinstr.rd_idx) ||
               (dut.dinstr_e2.valid && dut.dinstr_e2.rd_valid && dut.dinstr_e2.wb_sel == WB_MEM &&
                dut.dinstr_decode.rs1_idx == dut.dinstr_e2.rd_idx) ||
               (dut.einstr.valid && dut.einstr.rd_valid && dut.einstr.wb_sel == WB_MEM &&
                dut.dinstr_decode.rs1_idx == dut.einstr.rd_idx))) ||
             ((dut.dinstr_decode.rs2_valid && dut.dinstr_decode.rs2_idx != 5'd0) &&
              ((dut.dinstr.valid && dut.dinstr.rd_valid && dut.dinstr.wb_sel == WB_MEM &&
                dut.dinstr_decode.rs2_idx == dut.dinstr.rd_idx) ||
               (dut.dinstr_e2.valid && dut.dinstr_e2.rd_valid && dut.dinstr_e2.wb_sel == WB_MEM &&
                dut.dinstr_decode.rs2_idx == dut.dinstr_e2.rd_idx) ||
               (dut.einstr.valid && dut.einstr.rd_valid && dut.einstr.wb_sel == WB_MEM &&
                dut.dinstr_decode.rs2_idx == dut.einstr.rd_idx))));

        if (dut.stall_im2_raw && !dut.md_stall && !dut.mem_wait_stall) begin
            raw_stall_cycles++;
        end
        if (load_use_hazard && !dut.md_stall && !dut.mem_wait_stall) begin
            load_use_stall_cycles++;
        end
        if (dut.md_stall) begin
            muldiv_stall_cycles++;
        end
        if (dut.mem_wait_stall) begin
            mem_wait_stall_cycles++;
        end
        if (dut.pc_jmp_en) begin
            branch_redirect_cycles++;
        end
`endif

        if (dut.minstr.valid) begin
            commits++;
            if (is_alu(dut.minstr.op)) begin
                alu_ops++;
            end
            if (is_muldiv(dut.minstr.op)) begin
                muldiv_ops++;
            end
            if (is_load(dut.minstr.op)) begin
                loads++;
            end
            if (is_store(dut.minstr.op)) begin
                stores++;
            end
        end

`ifdef ANV32_BENCH_CORE_ANV32IM2
        ctrl_valid = dut.e_valid && dut.e_pc_changer;
        actual_taken = dut.e_branch_taken;
        ctrl_op = dut.dinstr_e2.op;
`else
        ctrl_valid = dut.e_valid && dut.e_pc_changer;
        actual_taken = dut.e_branch_taken;
        ctrl_op = dut.dinstr.op;
`endif

        if (ctrl_valid) begin
            control_ops++;
            if (is_jump(ctrl_op)) begin
                jumps++;
            end

            if (is_cond_branch(ctrl_op)) begin
                branches++;
                if (actual_taken) begin
                    branches_taken++;
                    static_nt_branch_mispredicts++;
                end else begin
                    branches_not_taken++;
                end
            end

            if (actual_taken) begin
                static_nt_mispredicts++;
            end
        end
    endtask

    initial begin
        if (INIT_FILE == "") begin
            $fatal(1, "INIT_FILE parameter is empty");
        end

        repeat (2) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        while (cycle < MAX_CYCLES && !halt_seen) begin
            @(posedge clk);
            #1;
            sample_counters();
            halt_seen = dut.einstr.valid && dut.einstr.is_halt;
            cycle++;
        end

        final_x10 = dut.regfile.regfile[10];
        pass = halt_seen && (!CHECK_X10 || final_x10 == EXPECT_X10);

        $display("BENCH_RESULT status=%s cycles=%0d commits=%0d alu_ops=%0d muldiv_ops=%0d loads=%0d stores=%0d control_ops=%0d jumps=%0d branches=%0d branches_taken=%0d branches_not_taken=%0d static_nt_mispredicts=%0d static_nt_branch_mispredicts=%0d raw_stall_cycles=%0d load_use_stall_cycles=%0d branch_redirect_cycles=%0d muldiv_stall_cycles=%0d mem_wait_stall_cycles=%0d final_x10=0x%08h expected_x10=0x%08h",
                 pass ? "PASS" : "FAIL",
                 cycle,
                 commits,
                 alu_ops,
                 muldiv_ops,
                 loads,
                 stores,
                 control_ops,
                 jumps,
                 branches,
                 branches_taken,
                 branches_not_taken,
                 static_nt_mispredicts,
                 static_nt_branch_mispredicts,
                 raw_stall_cycles,
                 load_use_stall_cycles,
                 branch_redirect_cycles,
                 muldiv_stall_cycles,
                 mem_wait_stall_cycles,
                 final_x10,
                 EXPECT_X10);

        if (!halt_seen) begin
            $fatal(1, "benchmark timed out before EBREAK");
        end
        if (!pass) begin
            $fatal(1, "benchmark result check failed");
        end

        $finish;
    end
endmodule
