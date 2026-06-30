`timescale 1ns/1ps

module tb_cpu_trace
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
#(
    parameter INIT_FILE = "",
    parameter int unsigned MAX_CYCLES = 80,
    parameter logic [XLEN-1:0] PC_RESET_VALUE = RESET_PC,
    parameter logic [XLEN-1:0] COMMIT_PC_BASE = '0
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
    int unsigned cycle = 0;
    bit halt_seen = 1'b0;
    int log_fd = 0;
    int commit_fd = 0;
    bit log_enabled = 1'b0;
    bit commit_enabled = 1'b0;
    bit detail_stdout = 1'b0;
    string log_path;
    string commit_log_path;

    always #5 clk = ~clk;

    anv32im1_top #(
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
            CSRRW:   return "CSRRW";
            CSRRS:   return "CSRRS";
            CSRRC:   return "CSRRC";
            CSRRWI:  return "CSRRWI";
            CSRRSI:  return "CSRRSI";
            CSRRCI:  return "CSRRCI";
            ECALL:   return "ECALL";
            EBREAK:  return "EBREAK";
            MRET:    return "MRET";
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

    function automatic string fwd_name(input fwd_sel_e sel);
        unique case (sel)
            FWD_REG: return "REG";
            FWD_M:   return "M";
            FWD_W:   return "W";
            default: return "?";
        endcase
    endfunction

    function automatic string yn(input logic v);
        return v ? "Y" : "N";
    endfunction

    function automatic string hex32(input logic [31:0] v);
        return $sformatf("%02h%02h%02h%02h", v[31:24], v[23:16], v[15:8], v[7:0]);
    endfunction

    function automatic string commit_pc(input logic [31:0] pc);
        if (pc >= COMMIT_PC_BASE) begin
            return hex32(pc - COMMIT_PC_BASE);
        end
        return hex32(pc);
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

    task automatic emit_commit(input string line);
        if (commit_enabled) begin
            $fdisplay(commit_fd, "%s", line);
        end
    endtask

    task automatic print_commit();
        if (dut.minstr.valid) begin
            emit_commit($sformatf("core0 pc=%s instr=%s %-7s",
                                  commit_pc(dut.minstr.pc),
                                  hex32(dut.minstr.instr),
                                  op_name(dut.minstr.op)));
            if (dut.regfile_we && (dut.rd_idx != 5'd0)) begin
                emit_commit($sformatf("core0 pc=%s instr=%s write x%0d=%s",
                                      commit_pc(dut.minstr.pc),
                                      hex32(dut.minstr.instr),
                                      dut.rd_idx,
                                      hex32(dut.rd_wdata)));
            end
        end

        if (dut.einstr.valid && dut.einstr.is_halt) begin
            emit_commit($sformatf("core0 pc=%s instr=%s %-7s",
                                  commit_pc(dut.einstr.pc),
                                  hex32(dut.einstr.instr),
                                  op_name(dut.einstr.op)));
        end
    endtask

    task automatic print_header();
        emit("cycle | IF(fetch)              | DE.in(decode)          | EX(reg)                       | MEM(reg)                    | WB(to RF)");
        emit("------+------------------------+------------------------+-------------------------------+-----------------------------+----------------");
    endtask

    task automatic print_cycle();
        string if_s;
        string de_s;
        string ex_s;
        string mem_s;
        string mem_val_s;
        string wb_s;
        string ctrl_s;

        if (dut.finstr.valid) begin
            if_s = $sformatf("%s %s", hex32(dut.finstr.pc), hex32(dut.finstr.instr));
        end else begin
            if_s = "bubble";
        end

        if (dut.dinstr_decode.valid) begin
            de_s = $sformatf("%s %-7s", hex32(dut.dinstr_decode.pc), op_name(dut.dinstr_decode.op));
        end else begin
            de_s = "bubble";
        end

        if (dut.einstr.valid) begin
            ex_s = $sformatf("%s %-7s rd=x%-2d alu=%s",
                             hex32(dut.einstr.pc),
                             op_name(dut.einstr.op),
                             dut.einstr.rd_idx,
                             hex32(dut.einstr.alu_result));
        end else begin
            ex_s = "bubble";
        end

        if (dut.minstr.valid) begin
            unique case (dut.minstr.wb_sel)
                WB_ALU:  mem_val_s = hex32(dut.minstr.alu_result);
                WB_MEM:  mem_val_s = hex32(dut.m_stage_mem_out);
                WB_PC4:  mem_val_s = hex32(dut.minstr.link_pc);
                default: mem_val_s = "????????";
            endcase
            mem_s = $sformatf("rd=x%-2d wb=%s val=%s",
                              dut.minstr.rd_idx,
                              wb_name(dut.minstr.wb_sel),
                              mem_val_s);
        end else begin
            mem_s = "bubble";
        end

        if (dut.regfile_we) begin
            wb_s = $sformatf("x%-2d <= %s", dut.rd_idx, hex32(dut.rd_wdata));
        end else begin
            wb_s = "-";
        end

        ctrl_s = "";
        if (rst) begin
            ctrl_s = {ctrl_s, " rst"};
        end
        if (dut.pc_jmp_en) begin
            ctrl_s = {ctrl_s, $sformatf(" redirect->%s", hex32(dut.pc_jmp_addr))};
        end
        if (dut.flush_D) begin
            ctrl_s = {ctrl_s, " flush_de"};
        end
        if (dut.stall_f || dut.stall_d || dut.stall_e || dut.stall_m || dut.stall_w) begin
            ctrl_s = {ctrl_s, $sformatf(" stall=f%0b/d%0b/e%0b/m%0b/w%0b",
                                        dut.stall_f,
                                        dut.stall_d,
                                        dut.stall_e,
                                        dut.stall_m,
                                        dut.stall_w)};
        end

        emit($sformatf("%5d | %-22s | %-22s | %-29s | %-27s | %-14s%s",
                       cycle, if_s, de_s, ex_s, mem_s, wb_s, ctrl_s));
    endtask

    task automatic print_detail();
        emit_detail($sformatf(""));
        emit_detail($sformatf("CYCLE %0d  rst=%0b redirect=%s target=%s flush_de=%s stall={f:%0b d:%0b e:%0b m:%0b w:%0b}",
                              cycle,
                              rst,
                              yn(dut.pc_jmp_en),
                              hex32(dut.pc_jmp_addr),
                              yn(dut.flush_D),
                              dut.stall_f,
                              dut.stall_d,
                              dut.stall_e,
                              dut.stall_m,
                              dut.stall_w));

        if (dut.finstr.valid) begin
            emit_detail($sformatf("  IF(fetch): pc=%s instr=%s next_fetch=%s pmem_addr=%s",
                                  hex32(dut.finstr.pc),
                                  hex32(dut.finstr.instr),
                                  hex32(dut.fetch_addr),
                                  hex10(instr_addr[11:2])));
        end else begin
            emit_detail("  IF(fetch): bubble");
        end

        if (dut.dinstr_decode.valid) begin
            emit_detail($sformatf("  DE.in:     pc=%s op=%-7s rd=x%-2d rdv=%0b wb=%s imm=%s",
                                  hex32(dut.dinstr_decode.pc),
                                  op_name(dut.dinstr_decode.op),
                                  dut.dinstr_decode.rd_idx,
                                  dut.dinstr_decode.rd_valid,
                                  wb_name(dut.dinstr_decode.wb_sel),
                                  hex32(dut.dinstr_decode.imm)));
            emit_detail($sformatf("             rs1=x%-2d need=%0b rf=%s fwd=%s val=%s | rs2=x%-2d need=%0b rf=%s fwd=%s val=%s",
                                  dut.dinstr_decode.rs1_idx,
                                  dut.dinstr_decode.rs1_valid,
                                  hex32(dut.rs1_rdata),
                                  fwd_name(dut.rs1_fwd_sel),
                                  hex32(dut.rs1_D_din),
                                  dut.dinstr_decode.rs2_idx,
                                  dut.dinstr_decode.rs2_valid,
                                  hex32(dut.rs2_rdata),
                                  fwd_name(dut.rs2_fwd_sel),
                                  hex32(dut.rs2_D_din)));
        end else begin
            emit_detail("  DE.in:     bubble");
        end

        if (dut.einstr.valid) begin
            emit_detail($sformatf("  EX(reg):   pc=%s op=%-7s rd=x%-2d wb=%s alu=%s store=%s link=%s",
                                  hex32(dut.einstr.pc),
                                  op_name(dut.einstr.op),
                                  dut.einstr.rd_idx,
                                  wb_name(dut.einstr.wb_sel),
                                  hex32(dut.einstr.alu_result),
                                  hex32(dut.einstr.write_data),
                                  hex32(dut.einstr.link_pc)));
            emit_detail($sformatf("             branch=%0b target=%s mem=%0b pcchg=%0b halt=%0b",
                                  dut.einstr.branch_taken,
                                  hex32(dut.einstr.pc_target),
                                  dut.einstr.is_mem,
                                  dut.einstr.is_pc_changer,
                                  dut.einstr.is_halt));
        end else begin
            emit_detail("  EX(reg):   bubble");
        end

        if (dut.minstr.valid) begin
            emit_detail($sformatf("  MEM(reg):  rd=x%-2d rdv=%0b wb=%s alu=%s mem_out=%s dmem_addr=%s we=%1h wdata=%s",
                                  dut.minstr.rd_idx,
                                  dut.minstr.rd_valid,
                                  wb_name(dut.minstr.wb_sel),
                                  hex32(dut.minstr.alu_result),
                                  hex32(dut.m_stage_mem_out),
                                  hex32(dut.m_stage_dmem_addr_out),
                                  dut.dmem_we,
                                  hex32(dut.dmem_wdata)));
        end else begin
            emit_detail("  MEM(reg):  bubble");
        end

        if (dut.regfile_we) begin
            emit_detail($sformatf("  WB(to RF):  x%-2d <= %s",
                                  dut.rd_idx,
                                  hex32(dut.rd_wdata)));
        end else begin
            emit_detail("  WB(to RF):  -");
        end
        emit_detail($sformatf("  REG:       x1=%s x2=%s x5=%s x6=%s x10=%s",
                              hex32(dut.regfile.regfile[1]),
                              hex32(dut.regfile.regfile[2]),
                              hex32(dut.regfile.regfile[5]),
                              hex32(dut.regfile.regfile[6]),
                              hex32(dut.regfile.regfile[10])));
    endtask

    task automatic print_register_state();
        string line;
        emit("FINAL ARCHITECTURAL STATE:");
        emit($sformatf("  PC = %s", hex32(pc_o)));
        line = "  ";
        for (int unsigned i = 0; i < 32; i++) begin
            line = {line, $sformatf("x%02d=%s", i, hex32(dut.regfile.regfile[i]))};
            if (i != 31) begin
                line = {line, " "};
            end
            if ((i % 8) == 7) begin
                emit(line);
                line = "  ";
            end
        end
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
        if ($value$plusargs("commit_log=%s", commit_log_path)) begin
            commit_fd = $fopen(commit_log_path, "w");
            if (commit_fd == 0) begin
                $fatal(1, "could not open commit log file: %s", commit_log_path);
            end
            commit_enabled = 1'b1;
        end
        detail_stdout = $test$plusargs("detail");

        emit($sformatf("INIT_FILE=%s", INIT_FILE));
        if (log_enabled) begin
            emit($sformatf("PIPELINE_LOG=%s", log_path));
        end
        if (commit_enabled) begin
            emit($sformatf("COMMIT_LOG=%s", commit_log_path));
        end
        print_header();

        repeat (2) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        while (cycle < MAX_CYCLES && !halt_seen) begin
            @(posedge clk);
            #1;
            print_cycle();
            print_detail();
            print_commit();
            halt_seen = dut.einstr.valid && dut.einstr.is_halt;
            cycle++;
        end

        if (halt_seen) begin
            emit($sformatf("HALT: EBREAK reached at cycle %0d", cycle - 1));
        end else begin
            emit($sformatf("STOP: MAX_CYCLES=%0d reached", MAX_CYCLES));
        end

        print_register_state();

        if (log_enabled) begin
            $fclose(log_fd);
        end
        if (commit_enabled) begin
            $fclose(commit_fd);
        end

        $finish;
    end
endmodule
