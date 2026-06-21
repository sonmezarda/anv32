// ============================================================================
// anv32i1_DE_stage_tb.sv
// Self-checking testbench for the refactored decode+execute stage.
//
// ASSUMES the post-refactor interfaces:
//   anv32_alu       : ports (op_i: alu_op_e, a_i, b_i, result_o)
//   anv32_decoder   : derives alu_op / a_sel / b_sel / wb_sel into dinstr_t
//   einstr_t        : has link_pc + control passthrough (rd_idx, rd_valid,
//                     wb_sel, is_mem, is_pc_changer, is_halt, pc, id, op)
//
// Compile order: config_pkg, isa_pkg, alu, decoder, DE_stage, this tb.
// Strategy: encode real RV32I instructions independently of the decoder,
// hand-compute golden values, drive, clock once (output is registered),
// then check. A behavioural regfile answers the DUT's index outputs async.
// ============================================================================
`timescale 1ns/1ps

module anv32i1_DE_stage_tb
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
;

    // ---------------- clock / reset / control ------------------------------
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic stall = 1'b0;
    always #5 clk = ~clk;          // 10ns period

    // ---------------- DUT I/O ----------------------------------------------
    finstr_t           finstr;
    dinstr_t           dinstr_decode;
    dinstr_t           dinstr;
    einstr_t           einstr;
    logic [4:0]        rs1_idx, rs2_idx;
    logic [11:0]       csr_addr;
    logic [XLEN-1:0]   rs1_rdata, rs2_rdata;
    logic [XLEN-1:0]   csr_rdata = 32'hCAFE_BABE;
    logic              branch_taken;
    logic [XLEN-1:0]   pc_target;
    logic              pc_changer;
    logic              e_valid;

    // ---------------- behavioural register file (async read) ---------------
    logic [XLEN-1:0] xreg [0:31];
    assign rs1_rdata = (rs1_idx == 5'd0) ? '0 : xreg[rs1_idx];
    assign rs2_rdata = (rs2_idx == 5'd0) ? '0 : xreg[rs2_idx];

    // ---------------- DUT ---------------------------------------------------
    anv32i1_D_stage d_stage (
        .clk_i      (clk),
        .rst_i      (rst),
        .stall_i    (stall),
        .flush_i    (1'b0),
        .finstr_i   (finstr),
        .rs1_rdata_i(rs1_rdata),
        .rs2_rdata_i(rs2_rdata),
        .csr_rdata_i(csr_rdata),
        .rs1_idx_o  (rs1_idx),
        .rs2_idx_o  (rs2_idx),
        .csr_addr_o (csr_addr),
        .dinstr_decode_o(dinstr_decode),
        .dinstr_o   (dinstr)
    );

    anv32i1_E_stage e_stage (
        .clk_i          (clk),
        .rst_i          (rst),
        .stall_i        (1'b0),
        .dinstr_i       (dinstr),
        .rs1_rdata_i    (dinstr.rs1_rdata),
        .rs2_rdata_i    (dinstr.rs2_rdata),
        .csr_rdata_i    (dinstr.csr_rdata),
        .branch_taken_o (branch_taken),
        .pc_target_o    (pc_target),
        .pc_changer_o   (pc_changer),
        .valid_o        (e_valid),
        .einstr_o       (einstr)
    );

    // =======================================================================
    //  Instruction encoders (independent of the decoder's imm functions)
    // =======================================================================
    function automatic logic [31:0] enc_r(
        logic [6:0] f7, logic [4:0] rs2, logic [4:0] rs1,
        logic [2:0] f3, logic [4:0] rd, logic [6:0] op);
        return {f7, rs2, rs1, f3, rd, op};
    endfunction

    function automatic logic [31:0] enc_i(
        logic [11:0] imm, logic [4:0] rs1,
        logic [2:0] f3, logic [4:0] rd, logic [6:0] op);
        return {imm, rs1, f3, rd, op};
    endfunction

    function automatic logic [31:0] enc_s(
        logic [11:0] imm, logic [4:0] rs2, logic [4:0] rs1,
        logic [2:0] f3, logic [6:0] op);
        return {imm[11:5], rs2, rs1, f3, imm[4:0], op};
    endfunction

    function automatic logic [31:0] enc_b(
        logic [12:0] imm, logic [4:0] rs2, logic [4:0] rs1,
        logic [2:0] f3, logic [6:0] op);
        return {imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], op};
    endfunction

    function automatic logic [31:0] enc_u(
        logic [31:0] imm, logic [4:0] rd, logic [6:0] op);
        return {imm[31:12], rd, op};
    endfunction

    function automatic logic [31:0] enc_j(
        logic [20:0] imm, logic [4:0] rd, logic [6:0] op);
        return {imm[20], imm[10:1], imm[11], imm[19:12], rd, op};
    endfunction

    // =======================================================================
    //  Scoreboard helpers
    // =======================================================================
    int unsigned tests = 0;
    int unsigned errors = 0;
    string cur;   // name of the current test case

    task automatic chk(string nm, logic [31:0] got, logic [31:0] exp);
        tests++;
        if (got !== exp) begin
            errors++;
            $display("  [FAIL] %-12s %-14s got=%08h exp=%08h", cur, nm, got, exp);
        end
    endtask

    task automatic chk1(string nm, logic got, logic exp);
        tests++;
        if (got !== exp) begin
            errors++;
            $display("  [FAIL] %-12s %-14s got=%b exp=%b", cur, nm, got, exp);
        end
    endtask

    task automatic chk_wb(string nm, wb_sel_e got, wb_sel_e exp);
        tests++;
        if (got !== exp) begin
            errors++;
            $display("  [FAIL] %-12s %-14s got=%0d exp=%0d", cur, nm, got, exp);
        end
    endtask

    // Drive one instruction and clock it into the output register.
    // After return: einstr holds the result; finstr still holds this instr,
    // so combinational outputs (rs1_idx/rs2_idx) also reflect it.
    task automatic run(string nm, logic [31:0] instr, logic [31:0] pc);
        cur = nm;
        @(negedge clk);
        finstr.valid = 1'b1;
        finstr.instr = instr;
        finstr.pc    = pc;
        stall        = 1'b0;
        @(posedge clk);   // D register capture
        #1;
        finstr.valid = 1'b0;
        @(posedge clk);   // E register capture
        #1;               // let NBA update settle
    endtask

    // =======================================================================
    //  Stimulus
    // =======================================================================
    initial begin
        // --- register contents -------------------------------------------
        for (int i = 0; i < 32; i++) xreg[i] = '0;
        xreg[1] = 32'd10;            // 0x0000000A
        xreg[2] = 32'd3;
        xreg[3] = 32'hFFFFFFFF;      // -1
        xreg[4] = 32'd1;
        xreg[5] = 32'hFFFFFFF0;      // -16
        xreg[6] = 32'h00001001;      // for JALR LSB-clear test
        xreg[7] = 32'h00000F0F;      // for CSR write tests

        finstr = '0;

        // --------------------------------------------------------------
        //  Reset behaviour
        // --------------------------------------------------------------
        cur = "reset";
        rst = 1'b1;
        repeat (2) @(posedge clk);
        #1;
        chk1("valid",  einstr.valid, 1'b0);
        @(negedge clk);
        rst = 1'b0;

        // --------------------------------------------------------------
        //  ALU register-register
        // --------------------------------------------------------------
        run("ADD", enc_r(F7_DEFAULT, 5'd2, 5'd1, F3_ADDSUB, 5'd10, OPC_OP), 32'h0);
        chk ("alu_result", einstr.alu_result, 32'd13);
        chk ("rd_idx",     einstr.rd_idx,     32'd10);
        chk1("rd_valid",   einstr.rd_valid,   1'b1);
        chk1("is_mem",     einstr.is_mem,     1'b0);
        chk1("is_pc_chg",  einstr.is_pc_changer, 1'b0);
        chk_wb("wb_sel",   einstr.wb_sel,     WB_ALU);
        chk ("rs1_idx_o",  rs1_idx,           32'd1);
        chk ("rs2_idx_o",  rs2_idx,           32'd2);

        run("SUB", enc_r(F7_ALT, 5'd2, 5'd1, F3_ADDSUB, 5'd10, OPC_OP), 32'h0);
        chk ("alu_result", einstr.alu_result, 32'd7);

        run("AND", enc_r(F7_DEFAULT, 5'd2, 5'd1, F3_AND, 5'd10, OPC_OP), 32'h0);
        chk ("alu_result", einstr.alu_result, 32'd2);     // 10 & 3

        run("OR",  enc_r(F7_DEFAULT, 5'd2, 5'd1, F3_OR, 5'd10, OPC_OP), 32'h0);
        chk ("alu_result", einstr.alu_result, 32'd11);    // 10 | 3

        run("XOR", enc_r(F7_DEFAULT, 5'd2, 5'd1, F3_XOR, 5'd10, OPC_OP), 32'h0);
        chk ("alu_result", einstr.alu_result, 32'd9);     // 10 ^ 3

        run("SLL", enc_r(F7_DEFAULT, 5'd2, 5'd1, F3_SLL, 5'd10, OPC_OP), 32'h0);
        chk ("alu_result", einstr.alu_result, 32'd80);    // 10 << 3

        run("SRL", enc_r(F7_DEFAULT, 5'd2, 5'd5, F3_SR, 5'd10, OPC_OP), 32'h0);
        chk ("alu_result", einstr.alu_result, 32'h1FFFFFFE); // 0xFFFFFFF0 >> 3

        run("SRA", enc_r(F7_ALT, 5'd2, 5'd5, F3_SR, 5'd10, OPC_OP), 32'h0);
        chk ("alu_result", einstr.alu_result, 32'hFFFFFFFE); // -16 >>> 3 = -2

        run("SLT", enc_r(F7_DEFAULT, 5'd4, 5'd3, F3_SLT, 5'd10, OPC_OP), 32'h0);
        chk ("alu_result", einstr.alu_result, 32'd1);     // signed: -1 < 1

        run("SLTU", enc_r(F7_DEFAULT, 5'd4, 5'd3, F3_SLTU, 5'd10, OPC_OP), 32'h0);
        chk ("alu_result", einstr.alu_result, 32'd0);     // unsigned: huge < 1 -> 0

        // --------------------------------------------------------------
        //  ALU register-immediate
        // --------------------------------------------------------------
        run("ADDI", enc_i(12'd5, 5'd1, F3_ADDSUB, 5'd10, OPC_OPIMM), 32'h0);
        chk ("alu_result", einstr.alu_result, 32'd15);

        run("ADDIx0", enc_i(12'd7, 5'd0, F3_ADDSUB, 5'd5, OPC_OPIMM), 32'h0);
        chk ("alu_result", einstr.alu_result, 32'd7);     // x0 reads 0 -> li

        run("ANDI", enc_i(12'hF, 5'd1, F3_AND, 5'd10, OPC_OPIMM), 32'h0);
        chk ("alu_result", einstr.alu_result, 32'd10);    // 10 & 0xF

        run("SLTI", enc_i(12'd20, 5'd1, F3_SLT, 5'd10, OPC_OPIMM), 32'h0);
        chk ("alu_result", einstr.alu_result, 32'd1);     // 10 < 20

        run("SLLI", enc_r(F7_DEFAULT, 5'd4, 5'd1, F3_SLL, 5'd10, OPC_OPIMM), 32'h0);
        chk ("alu_result", einstr.alu_result, 32'hA0);    // 10 << 4

        run("SRAI", enc_r(F7_ALT, 5'd4, 5'd5, F3_SR, 5'd10, OPC_OPIMM), 32'h0);
        chk ("alu_result", einstr.alu_result, 32'hFFFFFFFF); // -16 >>> 4 = -1

        // --------------------------------------------------------------
        //  U-type: operand A select (ZERO vs PC)
        // --------------------------------------------------------------
        run("LUI", enc_u(32'h12345000, 5'd10, OPC_LUI), 32'hDEAD0000);
        chk ("alu_result", einstr.alu_result, 32'h12345000); // 0 + imm, pc ignored
        chk_wb("wb_sel",   einstr.wb_sel,     WB_ALU);

        run("AUIPC", enc_u(32'h00010000, 5'd10, OPC_AUIPC), 32'h00001000);
        chk ("alu_result", einstr.alu_result, 32'h00011000); // pc + imm

        // --------------------------------------------------------------
        //  Loads / stores: address = rs1 + imm
        // --------------------------------------------------------------
        run("LW", enc_i(12'd8, 5'd1, F3_LW, 5'd10, OPC_LOAD), 32'h0);
        chk ("addr(alu)",  einstr.alu_result, 32'd18);    // 10 + 8
        chk1("is_mem",     einstr.is_mem,     1'b1);
        chk1("rd_valid",   einstr.rd_valid,   1'b1);
        chk_wb("wb_sel",   einstr.wb_sel,     WB_MEM);

        run("SW", enc_s(12'd16, 5'd2, 5'd1, F3_SW, OPC_STORE), 32'h0);
        chk ("addr(alu)",  einstr.alu_result, 32'd26);    // 10 + 16
        chk ("write_data", einstr.write_data, 32'd3);     // rs2 = x2
        chk1("is_mem",     einstr.is_mem,     1'b1);
        chk1("rd_valid",   einstr.rd_valid,   1'b0);

        // --------------------------------------------------------------
        //  Branches: comparator + pc-relative target
        // --------------------------------------------------------------
        run("BEQ_T", enc_b(13'd16, 5'd1, 5'd1, F3_BEQ, OPC_BRANCH), 32'h100);
        chk1("branch_taken", einstr.branch_taken, 1'b1);  // x1 == x1
        chk ("pc_target",    einstr.pc_target,    32'h110); // pc + 16
        chk1("is_pc_chg",    einstr.is_pc_changer, 1'b1);

        run("BEQ_N", enc_b(13'd16, 5'd2, 5'd1, F3_BEQ, OPC_BRANCH), 32'h100);
        chk1("branch_taken", einstr.branch_taken, 1'b0);  // 10 != 3
        chk ("pc_target",    einstr.pc_target,    32'h110); // computed anyway

        run("BNE_T", enc_b(13'd16, 5'd2, 5'd1, F3_BNE, OPC_BRANCH), 32'h100);
        chk1("branch_taken", einstr.branch_taken, 1'b1);

        run("BLT_T", enc_b(13'd16, 5'd4, 5'd3, F3_BLT, OPC_BRANCH), 32'h100);
        chk1("branch_taken", einstr.branch_taken, 1'b1);  // signed -1 < 1

        run("BLTU_N", enc_b(13'd16, 5'd4, 5'd3, F3_BLTU, OPC_BRANCH), 32'h100);
        chk1("branch_taken", einstr.branch_taken, 1'b0);  // unsigned huge < 1 -> 0

        // --------------------------------------------------------------
        //  Jumps: target + link + WB_PC4
        // --------------------------------------------------------------
        run("JAL", enc_j(21'h20, 5'd10, OPC_JAL), 32'h200);
        chk ("pc_target",  einstr.pc_target, 32'h220);    // pc + 0x20
        chk ("link_pc",    einstr.link_pc,   32'h204);    // pc + 4
        chk_wb("wb_sel",   einstr.wb_sel,    WB_PC4);
        chk1("is_pc_chg",  einstr.is_pc_changer, 1'b1);
        chk1("rd_valid",   einstr.rd_valid,  1'b1);

        // JALR target = (rs1 + imm) & ~1 ; here 0x1001 + 2 = 0x1003 -> 0x1002
        run("JALR", enc_i(12'd2, 5'd6, F3_JALR, 5'd10, OPC_JALR), 32'h300);
        chk ("pc_target",  einstr.pc_target, 32'h1002);   // LSB cleared
        chk ("link_pc",    einstr.link_pc,   32'h304);
        chk_wb("wb_sel",   einstr.wb_sel,    WB_PC4);

        // --------------------------------------------------------------
        //  CSR: rd gets old CSR value, CSR write data is op-dependent
        // --------------------------------------------------------------
        run("CSRRW", enc_i(CSR_MSTATUS, 5'd7, F3_CSRRW, 5'd10, OPC_SYSTEM), 32'h400);
        chk ("alu_result", einstr.alu_result, 32'hCAFE_BABE);
        chk ("csr_addr",   einstr.csr_addr,   CSR_MSTATUS);
        chk ("csr_wdata",  einstr.csr_wdata,  32'h00000F0F);
        chk1("is_csr",     einstr.is_csr,     1'b1);
        chk1("csr_we",     einstr.csr_we,     1'b1);
        chk1("rd_valid",   einstr.rd_valid,   1'b1);

        run("CSRRS0", enc_i(CSR_MTVEC, 5'd0, F3_CSRRS, 5'd10, OPC_SYSTEM), 32'h404);
        chk ("alu_result", einstr.alu_result, 32'hCAFE_BABE);
        chk ("csr_addr",   einstr.csr_addr,   CSR_MTVEC);
        chk1("csr_we",     einstr.csr_we,     1'b0);

        run("CSRRCI", enc_i(CSR_MCAUSE, 5'd5, F3_CSRRCI, 5'd10, OPC_SYSTEM), 32'h408);
        chk ("alu_result", einstr.alu_result, 32'hCAFE_BABE);
        chk ("csr_wdata",  einstr.csr_wdata,  32'hCAFE_BABA);
        chk1("csr_we",     einstr.csr_we,     1'b1);

        // --------------------------------------------------------------
        //  Illegal instruction -> valid = 0
        // --------------------------------------------------------------
        run("ILLEGAL", 32'hFFFFFFFF, 32'h0);
        chk1("valid", einstr.valid, 1'b0);

        // --------------------------------------------------------------
        //  Stall injects a bubble so an older load can advance to M/W while
        //  the dependent instruction is held in fetch/decode.
        // --------------------------------------------------------------
        run("STALL_pre", enc_r(F7_DEFAULT, 5'd2, 5'd1, F3_ADDSUB, 5'd10, OPC_OP), 32'h0);
        chk ("alu_result", einstr.alu_result, 32'd13);    // ADD captured
        begin
            cur = "STALL_hold";
            @(negedge clk);
            stall        = 1'b1;
            finstr.instr = enc_r(F7_ALT, 5'd2, 5'd1, F3_ADDSUB, 5'd10, OPC_OP); // SUB
            @(posedge clk);
            #1;
            chk1("bubble", einstr.valid, 1'b0);
            @(negedge clk);
            stall = 1'b0;
        end

        // --------------------------------------------------------------
        //  Summary
        // --------------------------------------------------------------
        $display("----------------------------------------------------------");
        if (errors == 0)
            $display("  PASS  all %0d checks passed", tests);
        else
            $display("  DONE  %0d/%0d checks FAILED", errors, tests);
        $display("----------------------------------------------------------");
        $finish;
    end

    // safety net
    initial begin
        #100000;
        $display("  [TIMEOUT] testbench hung");
        $finish;
    end

endmodule
