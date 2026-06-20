`timescale 1ns/1ps

module tb_cpu_trace
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
#(
    parameter INIT_FILE = "",
    parameter int unsigned MAX_CYCLES = 80,
    parameter logic [XLEN-1:0] PC_RESET_VALUE = RESET_PC
);
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [31:0] pc_o;
    logic [31:0] instr_o;
    logic instr_valid_o;
    int unsigned cycle = 0;
    bit halt_seen = 1'b0;

    always #5 clk = ~clk;

    anv32i1_top #(
        .PC_RESET_VALUE(PC_RESET_VALUE),
        .INIT_FILE(INIT_FILE)
    ) dut (
        .clk_i(clk),
        .rst_i(rst),
        .stall_i(1'b0),
        .pc_jmp_en_i(1'b0),
        .pc_jmp_addr_i('0),
        .pc_o(pc_o),
        .instr_o(instr_o),
        .instr_valid_o(instr_valid_o)
    );

    function automatic string op_name(input op_e op);
        unique case (op)
            LUI:     return "LUI";
            AUIPC:   return "AUIPC";
            JAL:     return "JAL";
            JALR:    return "JALR";
            BEQ:     return "BEQ";
            BNE:     return "BNE";
            BLT:     return "BLT";
            BGE:     return "BGE";
            BLTU:    return "BLTU";
            BGEU:    return "BGEU";
            LB:      return "LB";
            LH:      return "LH";
            LW:      return "LW";
            LBU:     return "LBU";
            LHU:     return "LHU";
            SB:      return "SB";
            SH:      return "SH";
            SW:      return "SW";
            ADDI:    return "ADDI";
            SLTI:    return "SLTI";
            SLTIU:   return "SLTIU";
            XORI:    return "XORI";
            ORI:     return "ORI";
            ANDI:    return "ANDI";
            SLLI:    return "SLLI";
            SRLI:    return "SRLI";
            SRAI:    return "SRAI";
            ADD:     return "ADD";
            SUB:     return "SUB";
            SLL:     return "SLL";
            SLT:     return "SLT";
            SLTU:    return "SLTU";
            XOR:     return "XOR";
            SRL:     return "SRL";
            SRA:     return "SRA";
            OR:      return "OR";
            AND:     return "AND";
            MUL:     return "MUL";
            MULH:    return "MULH";
            MULHSU:  return "MULHSU";
            MULHU:   return "MULHU";
            DIV:     return "DIV";
            DIVU:    return "DIVU";
            REM:     return "REM";
            REMU:    return "REMU";
            ECALL:   return "ECALL";
            EBREAK:  return "EBREAK";
            default: return "UNKNOWN";
        endcase
    endfunction

    function automatic string wb_name(input wb_sel_e wb);
        unique case (wb)
            WB_ALU: return "ALU";
            WB_MEM: return "MEM";
            WB_PC4: return "PC4";
            default: return "?";
        endcase
    endfunction

    task automatic print_header();
        $display("cycle rst | F.valid F.pc       F.instr    | E.valid E.pc       E.op     rd br tgt      alu      | M.valid rd wb  alu/mem  we wdata    | W.we rd wdata");
        $display("----------+--------------------------------+-----------------------------------------------+--------------------------------------+----------------");
    endtask

    task automatic print_cycle();
        $display("%5d  %0b  |    %0b    %08h  %08h |    %0b    %08h %-7s x%-2d %0b %08h %08h |    %0b    x%-2d %-3s %08h %1h %08h |  %0b  x%-2d %08h",
                 cycle,
                 rst,
                 dut.finstr.valid,
                 dut.finstr.pc,
                 dut.finstr.instr,
                 dut.einstr.valid,
                 dut.einstr.pc,
                 op_name(dut.einstr.op),
                 dut.einstr.rd_idx,
                 dut.einstr.branch_taken,
                 dut.einstr.pc_target,
                 dut.einstr.alu_result,
                 dut.minstr.valid,
                 dut.minstr.rd_idx,
                 wb_name(dut.minstr.wb_sel),
                 dut.m_stage_mem_out,
                 dut.dmem_we,
                 dut.dmem_wdata,
                 dut.regfile_we,
                 dut.rd_idx,
                 dut.rd_wdata);
    endtask

    initial begin
        if (INIT_FILE == "") begin
            $fatal(1, "INIT_FILE parameter is empty");
        end

        if ($test$plusargs("trace")) begin
            $dumpfile("obj_dir/cpu_trace.vcd");
            $dumpvars(0, tb_cpu_trace);
        end

        $display("INIT_FILE=%s", INIT_FILE);
        print_header();

        repeat (2) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        while (cycle < MAX_CYCLES && !halt_seen) begin
            @(posedge clk);
            #1;
            print_cycle();
            halt_seen = dut.einstr.valid && dut.einstr.is_halt;
            cycle++;
        end

        if (halt_seen) begin
            $display("HALT: EBREAK reached at cycle %0d", cycle - 1);
        end else begin
            $display("STOP: MAX_CYCLES=%0d reached", MAX_CYCLES);
        end

        $finish;
    end
endmodule
