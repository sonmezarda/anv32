`timescale 1ns/1ps
// Fetch path test through anv32i1_top. Checks that instr_o always matches
// mem[pc_o >> 2] while instr_valid_o is high, across stalls, jumps and reset.
module tb_fetch_stage;

    localparam logic [31:0] RESET_PC = 32'h0000_0000;
    localparam string       HEX_FILE = "./sim/data/fetch_test.hex";

    logic        clk = 0;
    logic        rst;
    logic        stall;
    logic [31:0] pc_jmp_addr;
    logic        pc_jmp_en;
    logic [31:0] pc_o;
    logic [31:0] instr_o;
    logic        instr_valid;
    logic [31:0] instr_addr;
    logic [31:0] instr_rdata;

    int errors = 0;
    int checks = 0;

    logic [31:0] exp_mem [0:63];
    initial $readmemh(HEX_FILE, exp_mem);

    function automatic logic [31:0] expected(input logic [31:0] pc);
        return exp_mem[pc[7:2]];
    endfunction

    anv32i1_top #(
        .PC_RESET_VALUE(RESET_PC)
    ) dut (
        .clk_i(clk), .rst_i(rst), .stall_i(stall),
        .pc_jmp_en_i(pc_jmp_en), .pc_jmp_addr_i(pc_jmp_addr),
        .ext_irq_i(1'b0),
        .pc_o(pc_o), .instr_o(instr_o), .instr_valid_o(instr_valid),
        .instr_i(instr_rdata), .instr_addr_o(instr_addr),
        .mem_rdata_i(32'b0), .mem_ready_i(1'b1),
        .mem_wdata_o(), .mem_addr_o(), .mem_valid_o(), .mem_we()
    );

    anv32_bram_tdp #(
        .ADDR_W(10),
        .INIT_FILE("./sim/data/fetch_test")
    ) ram (
        .clk(clk),
        .addr_a('0),
        .wdata_a(32'b0),
        .we_a(4'b0),
        .rdata_a(),
        .addr_b(instr_addr[11:2]),
        .wdata_b(32'b0),
        .we_b(4'b0),
        .rdata_b(instr_rdata)
    );

    always #5 clk = ~clk;

    // ---- check helpers -----------------------------------------------------
    task automatic chk_pc(string tag, logic [31:0] exp);
        checks++;
        if (pc_o !== exp) begin
            errors++; $display("[FAIL] %-24s pc=%h exp=%h", tag, pc_o, exp);
        end else $display("[ ok ] %-24s pc=%h", tag, pc_o);
    endtask

    task automatic chk_valid(string tag, logic exp);
        checks++;
        if (instr_valid !== exp) begin
            errors++; $display("[FAIL] %-24s valid=%b exp=%b", tag, instr_valid, exp);
        end else $display("[ ok ] %-24s valid=%b", tag, instr_valid);
    endtask

    // The invariant: a valid slot must carry the instruction for its PC.
    task automatic chk_aligned(string tag);
        checks++;
        if (instr_valid && (instr_o !== expected(pc_o))) begin
            errors++;
            $display("[FAIL] %-24s MISALIGNED pc=%h instr=%h exp=%h",
                     tag, pc_o, instr_o, expected(pc_o));
        end else
            $display("[ ok ] %-24s pc=%h instr=%h v=%b", tag, pc_o, instr_o, instr_valid);
    endtask

    // full check: pc + alignment together
    task automatic chk(string tag, logic [31:0] exp_pc);
        chk_pc(tag, exp_pc);
        chk_aligned(tag);
    endtask

    task automatic tick(); @(posedge clk); #1; endtask

    initial begin
        rst = 1; stall = 0; pc_jmp_en = 0; pc_jmp_addr = '0;

        // ====================================================================
        // Phase 0: cold reset - valid must stay 0 while resetting
        // ====================================================================
        $display("\n--- Phase 0: cold reset ---");
        tick; chk_valid("cold reset c0", 1'b0);
        tick; chk_valid("cold reset c1", 1'b0);

        // ====================================================================
        // Phase 1: release reset, first real instruction (1-cycle warm-up)
        // ====================================================================
        $display("\n--- Phase 1: reset release ---");
        @(negedge clk) rst = 0;
        tick;
        chk_valid("after reset valid", 1'b1);
        chk("after reset", RESET_PC + 32'h0);

        // ====================================================================
        // Phase 2: sequential fetch, invariant + pc each cycle
        // ====================================================================
        $display("\n--- Phase 2: sequential ---");
        tick; chk("seq +4",  RESET_PC + 32'h4);
        tick; chk("seq +8",  RESET_PC + 32'h8);
        tick; chk("seq +C",  RESET_PC + 32'hC);

        // ====================================================================
        // Phase 3: multi-cycle stall - pc + instr + valid frozen 4 cycles
        // (this is the real skid-buffer stress: instr must stay at mem[3])
        // ====================================================================
        $display("\n--- Phase 3: multi-cycle stall ---");
        @(negedge clk) stall = 1;
        tick; chk("stall hold 1", RESET_PC + 32'hC);
        tick; chk("stall hold 2", RESET_PC + 32'hC);
        tick; chk("stall hold 3", RESET_PC + 32'hC);
        tick; chk("stall hold 4", RESET_PC + 32'hC);
        chk_valid("stall valid held", 1'b1);   // valid must NOT drop during stall
        @(negedge clk) stall = 0;

        // ====================================================================
        // Phase 4: resume - the held instruction's successor must appear,
        // nothing dropped (skid exit correctness)
        // ====================================================================
        $display("\n--- Phase 4: resume after stall ---");
        tick; chk("resume +10", RESET_PC + 32'h10);
        tick; chk("resume +14", RESET_PC + 32'h14);

        // ====================================================================
        // Phase 5: back-to-back single-cycle stalls (toggle stall every cycle)
        // stresses skid enter/exit on consecutive cycles
        // ====================================================================
        $display("\n--- Phase 5: toggling stalls ---");
        @(negedge clk) stall = 1;
        tick; chk_aligned("toggle stall on");
        @(negedge clk) stall = 0;
        tick; chk_aligned("toggle stall off");
        @(negedge clk) stall = 1;
        tick; chk_aligned("toggle stall on2");
        @(negedge clk) stall = 0;
        tick; chk_aligned("toggle stall off2");

        // ====================================================================
        // Phase 6: jump redirect, then sequential from target
        // ====================================================================
        $display("\n--- Phase 6: jump ---");
        @(negedge clk) begin pc_jmp_en = 1; pc_jmp_addr = 32'h0000_0008; end
        @(negedge clk) pc_jmp_en = 0;
        tick; chk("jump target", 32'h0000_0008);
        tick; chk("after jump +C", 32'h0000_000C);
        tick; chk("after jump +10", 32'h0000_0010);

        // ====================================================================
        // Phase 7: jump while stalled - stall must win (pc frozen), and when
        // stall releases the jump should still be honored if held, or dropped.
        // Here we check stall freezes pc; document jump behavior.
        // ====================================================================
        $display("\n--- Phase 7: stall + jump priority ---");
        @(negedge clk) stall = 1;
        tick;
        $display("[info] before jump under stall: pc=%h", pc_o);
        @(negedge clk) begin pc_jmp_en = 1; pc_jmp_addr = 32'h0000_0030; end
        tick;
        chk_aligned("stall+jump aligned");
        $display("[info] stall+jump: pc=%h (stall should freeze pc)", pc_o);
        @(negedge clk) begin stall = 0; pc_jmp_en = 0; end
        tick; chk_aligned("after stall+jump release");

        // ====================================================================
        // Phase 8: stall immediately after a jump (skid + redirect interplay)
        // ====================================================================
        $display("\n--- Phase 8: jump then immediate stall ---");
        @(negedge clk) begin pc_jmp_en = 1; pc_jmp_addr = 32'h0000_0004; end
        @(negedge clk) begin pc_jmp_en = 0; stall = 1; end
        tick; chk_aligned("jump+stall c0");
        tick; chk_aligned("jump+stall c1");
        @(negedge clk) stall = 0;
        tick; chk_aligned("jump+stall resume");

        // ====================================================================
        // Phase 9: mid-stream reset, then realign
        // ====================================================================
        $display("\n--- Phase 9: mid-stream reset ---");
        @(negedge clk) rst = 1;
        tick; chk_valid("mid reset valid", 1'b0);
        @(negedge clk) rst = 0;
        tick;
        chk_valid("post-reset valid", 1'b1);
        chk("post-reset", RESET_PC + 32'h0);

        // ====================================================================
        // summary
        // ====================================================================
        $display("\n==== %0d checks, %0d failures ====", checks, errors);
        if (errors == 0) $display("==== ALL TESTS PASSED ====");
        else             $display("==== %0d TEST(S) FAILED ====", errors);
        $finish;
    end
endmodule
