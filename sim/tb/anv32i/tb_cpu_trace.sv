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
    int log_fd = 0;
    bit log_enabled = 1'b0;
    bit detail_stdout = 1'b0;
    string log_path;

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

    function automatic string yn(input logic v);
        return v ? "Y" : "N";
    endfunction

    function automatic string hex32(input logic [31:0] v);
        return $sformatf("%02h%02h%02h%02h", v[31:24], v[23:16], v[15:8], v[7:0]);
    endfunction

    function automatic string hex10(input logic [9:0] v);
        return $sformatf("%01h%02h", v[9:8], v[7:0]);
    endfunction

    task automatic emit(input string line);
        $display("%s", line);
        if (log_enabled) begin
            $fdisplay(log_fd, "%s", line);
        end
    endtask

    task automatic emit_detail(input string line);
        if (detail_stdout) begin
            $display("%s", line);
        end
        if (log_enabled) begin
            $fdisplay(log_fd, "%s", line);
        end
    endtask

    task automatic print_header();
        emit("cycle rst | F.valid F.pc       F.instr    | E.valid E.pc       E.op     rd br tgt      alu      | M.valid rd wb  alu/mem  we wdata    | W.we rd wdata");
        emit("----------+--------------------------------+-----------------------------------------------+--------------------------------------+----------------");
    endtask

    task automatic print_cycle();
        emit($sformatf("%5d  %0b  |    %0b    %08h  %08h |    %0b    %08h %-7s x%-2d %0b %08h %08h |    %0b    x%-2d %-3s %08h %1h %08h |  %0b  x%-2d %08h",
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
                       dut.rd_wdata));
    endtask

    task automatic print_detail();
        emit_detail($sformatf(""));
        emit_detail($sformatf("CYCLE %0d  rst=%0b redirect=%s target=%s flush_de=%s stall={f:%0b de:%0b m:%0b w:%0b}",
                              cycle,
                              rst,
                              yn(dut.pc_jmp_en),
                              hex32(dut.pc_jmp_addr),
                              yn(dut.flush_DE),
                              dut.stall_f,
                              dut.stall_de,
                              dut.stall_m,
                              dut.stall_w));
        emit_detail($sformatf("  F: valid=%0b pc=%s instr=%s fetch_addr=%s pmem_addr=%s bram_instr=%s",
                              dut.finstr.valid,
                              hex32(dut.finstr.pc),
                              hex32(dut.finstr.instr),
                              hex32(dut.fetch_addr),
                              hex10(dut.pmem_addr),
                              hex32(dut.bram_instr)));
        emit_detail($sformatf("  D: valid=%0b op=%-7s rd=x%-2d rdv=%0b rs1=x%-2d(%s) rs1v=%0b rs2=x%-2d(%s) rs2v=%0b imm=%s immv=%0b a_sel=%0d b_sel=%0d wb=%s mem=%0b pcchg=%0b halt=%0b",
                              dut.DE.dinstr.valid,
                              op_name(dut.DE.dinstr.op),
                              dut.DE.dinstr.rd_idx,
                              dut.DE.dinstr.rd_valid,
                              dut.DE.dinstr.rs1_idx,
                              hex32(dut.rs1_rdata),
                              dut.DE.dinstr.rs1_valid,
                              dut.DE.dinstr.rs2_idx,
                              hex32(dut.rs2_rdata),
                              dut.DE.dinstr.rs2_valid,
                              hex32(dut.DE.dinstr.imm),
                              dut.DE.dinstr.imm_valid,
                              dut.DE.dinstr.a_sel,
                              dut.DE.dinstr.b_sel,
                              wb_name(dut.DE.dinstr.wb_sel),
                              dut.DE.dinstr.is_mem,
                              dut.DE.dinstr.is_pc_changer,
                              dut.DE.dinstr.is_halt));
        emit_detail($sformatf("  E: valid=%0b pc=%s op=%-7s rd=x%-2d rdv=%0b wb=%s alu=%s store_data=%s link=%s branch=%0b target=%s mem=%0b pcchg=%0b halt=%0b",
                              dut.einstr.valid,
                              hex32(dut.einstr.pc),
                              op_name(dut.einstr.op),
                              dut.einstr.rd_idx,
                              dut.einstr.rd_valid,
                              wb_name(dut.einstr.wb_sel),
                              hex32(dut.einstr.alu_result),
                              hex32(dut.einstr.write_data),
                              hex32(dut.einstr.link_pc),
                              dut.einstr.branch_taken,
                              hex32(dut.einstr.pc_target),
                              dut.einstr.is_mem,
                              dut.einstr.is_pc_changer,
                              dut.einstr.is_halt));
        emit_detail($sformatf("  M: valid=%0b rd=x%-2d rdv=%0b wb=%s alu=%s dmem_addr=%s dmem_rdata=%s mem_out=%s we=%1h wdata=%s",
                              dut.minstr.valid,
                              dut.minstr.rd_idx,
                              dut.minstr.rd_valid,
                              wb_name(dut.minstr.wb_sel),
                              hex32(dut.minstr.alu_result),
                              hex32(dut.m_stage_dmem_addr_out),
                              hex32(dut.dmem_rdata),
                              hex32(dut.m_stage_mem_out),
                              dut.dmem_we,
                              hex32(dut.dmem_wdata)));
        emit_detail($sformatf("  W: we=%0b rd=x%-2d wdata=%s regfile[x1]=%s regfile[x2]=%s regfile[x5]=%s regfile[x10]=%s",
                              dut.regfile_we,
                              dut.rd_idx,
                              hex32(dut.rd_wdata),
                              hex32(dut.regfile.regfile[1]),
                              hex32(dut.regfile.regfile[2]),
                              hex32(dut.regfile.regfile[5]),
                              hex32(dut.regfile.regfile[10])));
    endtask

    initial begin
        if (INIT_FILE == "") begin
            $fatal(1, "INIT_FILE parameter is empty");
        end

        if ($test$plusargs("trace")) begin
            $dumpfile("obj_dir/cpu_trace.vcd");
            $dumpvars(0, tb_cpu_trace);
        end

        if ($value$plusargs("log=%s", log_path)) begin
            log_fd = $fopen(log_path, "w");
            if (log_fd == 0) begin
                $fatal(1, "could not open log file: %s", log_path);
            end
            log_enabled = 1'b1;
        end
        detail_stdout = $test$plusargs("detail");

        emit($sformatf("INIT_FILE=%s", INIT_FILE));
        if (log_enabled) begin
            emit($sformatf("PIPELINE_LOG=%s", log_path));
        end
        print_header();

        repeat (2) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        while (cycle < MAX_CYCLES && !halt_seen) begin
            @(posedge clk);
            #1;
            print_cycle();
            print_detail();
            halt_seen = dut.einstr.valid && dut.einstr.is_halt;
            cycle++;
        end

        if (halt_seen) begin
            emit($sformatf("HALT: EBREAK reached at cycle %0d", cycle - 1));
        end else begin
            emit($sformatf("STOP: MAX_CYCLES=%0d reached", MAX_CYCLES));
        end

        if (log_enabled) begin
            $fclose(log_fd);
        end

        $finish;
    end
endmodule
