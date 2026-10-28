`timescale 1ns/1ps

// Runs one self-checking program from sw/tests on a core. The program is
// loaded at run time (+prog=<word hex>), so one build per core covers every
// test. Results come back through a small test device; see sw/tests/test.h.
//
// It also runs riscv-tests (pass/fail written to tohost) and riscv-arch-test
// (signature dumped for comparison with a reference model).
//
// Plusargs:
//   +prog=<file>        word hex image, loaded at RESET_PC (RAM wraps every 4 MiB)
//   +max_cycles=<n>     timeout (default 200000)
//   +mem_wait           random data-port wait states (cores with mem_ready only)
//   +mem_wait_fixed=<n> every data access waits exactly n cycles before ready
//   +tohost=<hex>       riscv-tests: a store here ends the test (1 = pass)
//   +signature=<file> +sig_begin=<hex> +sig_end=<hex>
//                       dump RAM [sig_begin, sig_end) at the end of the test
module tb_core_test #(
    parameter logic [31:0] RESET_PC = 32'h0000_0000
);
    localparam int unsigned RAM_ADDR_W = 22;            // 4 MiB, wraps above
    localparam int unsigned RAM_WORDS  = 1 << (RAM_ADDR_W - 2);

    localparam logic [3:0] TEST_REGION    = 4'h2;
    localparam logic [7:0] TEST_RESULT    = 8'h00;
    localparam logic [7:0] TEST_IRQ_AFTER = 8'h04;
    localparam logic [7:0] TEST_IRQ_CLEAR = 8'h08;
    localparam logic [7:0] TEST_CYCLE     = 8'h0C;
    localparam logic [7:0] TEST_PUTC      = 8'h10;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic ext_irq = 1'b0;

    logic [31:0] instr_addr;
    logic [31:0] instr_rdata;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [31:0] mem_rdata;
    logic [3:0]  mem_we;
    logic        mem_valid;
    logic        mem_ready;

    always #5 clk = ~clk;

`ifdef ANV32_BENCH_CORE_ANV32I1
    anv32i1_top #(.PC_RESET_VALUE(RESET_PC)) dut (
`elsif ANV32_BENCH_CORE_ANV32IM1
    anv32im1_top #(.HAS_M(1'b1), .PC_RESET_VALUE(RESET_PC)) dut (
`elsif ANV32_BENCH_CORE_ANV32IM2
    anv32im2_top #(.HAS_M(1'b1), .PC_RESET_VALUE(RESET_PC)) dut (
`else
    initial $fatal(1, "Define one ANV32_BENCH_CORE_* macro");
    anv32im2_top dut (
`endif
        .clk_i(clk),
        .rst_i(rst),
        .stall_i(1'b0),
        .pc_jmp_en_i(1'b0),
        .pc_jmp_addr_i('0),
        .ext_irq_i(ext_irq),
        .pc_o(),
        .instr_o(),
        .instr_valid_o(),
        .instr_i(instr_rdata),
        .instr_addr_o(instr_addr),
        .mem_rdata_i(mem_rdata),
        .mem_ready_i(mem_ready),
        .mem_wdata_o(mem_wdata),
        .mem_addr_o(mem_addr),
        .mem_valid_o(mem_valid),
        .mem_we(mem_we)
    );

    // ---- Memory: synchronous reads like the FPGA BRAM ----------------------
    logic [31:0] ram [0:RAM_WORDS-1];
    logic        test_sel;
    logic        mem_fire;
    int unsigned cycle = 0;

    assign test_sel = (mem_addr[31:28] == TEST_REGION);
    assign mem_fire = mem_valid && mem_ready;

    always_ff @(posedge clk) begin
        instr_rdata <= ram[instr_addr[RAM_ADDR_W-1:2]];

        if (test_sel) begin
            mem_rdata <= (mem_addr[7:0] == TEST_CYCLE) ? cycle : 32'b0;
        end else begin
            mem_rdata <= ram[mem_addr[RAM_ADDR_W-1:2]];
        end

        if (mem_fire && !test_sel) begin
            for (int i = 0; i < 4; i++) begin
                if (mem_we[i]) ram[mem_addr[RAM_ADDR_W-1:2]][i*8 +: 8] <= mem_wdata[i*8 +: 8];
            end
        end
    end

    // ---- Optional data-port wait states ------------------------------------
    logic        wait_en = 1'b0;
    int unsigned wait_fixed = 0;      // 0 = off; else wait cycles per access
    int unsigned pend_cycles = 0;     // cycles the current request has waited
    logic [15:0] lfsr = 16'hACE1;

    always_ff @(posedge clk) begin
        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
        if (!mem_valid || mem_fire) pend_cycles <= 0;
        else                        pend_cycles <= pend_cycles + 1;
    end

    // Random: about one cycle in four is a wait state while a request is
    // pending. Fixed: every access is held off for exactly wait_fixed cycles,
    // so each load/store is guaranteed to stall the pipeline.
    assign mem_ready = (wait_fixed != 0) ? !(mem_valid && pend_cycles < wait_fixed)
                                         : !(wait_en && mem_valid && lfsr[0] && lfsr[5]);

    // ---- Test device -------------------------------------------------------
    logic        done = 1'b0;
    logic [31:0] result;
    logic        tohost_en = 1'b0;
    logic        tohost_hit = 1'b0;
    logic [31:0] tohost_addr;
    logic        irq_armed = 1'b0;
    logic [31:0] irq_count;

    always_ff @(posedge clk) begin
        if (rst) begin
            ext_irq   <= 1'b0;
            irq_armed <= 1'b0;
        end else begin
            if (irq_armed) begin
                if (irq_count == 0) begin
                    ext_irq   <= 1'b1;
                    irq_armed <= 1'b0;
                end else begin
                    irq_count <= irq_count - 1;
                end
            end

            if (tohost_en && mem_fire && mem_we != 4'b0 && mem_addr == tohost_addr) begin
                result     <= mem_wdata;
                tohost_hit <= 1'b1;
                done       <= 1'b1;
            end

            if (mem_fire && test_sel && mem_we != 4'b0) begin
                unique case (mem_addr[7:0])
                    TEST_RESULT: begin
                        result <= mem_wdata;
                        done   <= 1'b1;
                    end
                    TEST_IRQ_AFTER: begin
                        irq_armed <= 1'b1;
                        irq_count <= mem_wdata;
                    end
                    TEST_IRQ_CLEAR: ext_irq <= 1'b0;
                    TEST_PUTC:      $write("%c", mem_wdata[7:0]);
                    default: ;
                endcase
            end
        end
    end

    initial begin
        string prog;
        string sig_file;
        int unsigned max_cycles;
        logic [31:0] sig_begin;
        logic [31:0] sig_end;
        int fd;

        for (int i = 0; i < RAM_WORDS; i++) ram[i] = 32'b0;
        if (!$value$plusargs("prog=%s", prog)) begin
            $fatal(1, "missing +prog=<word hex file>");
        end
        $readmemh(prog, ram);
        if (!$value$plusargs("max_cycles=%d", max_cycles)) max_cycles = 200000;
        wait_en = $test$plusargs("mem_wait");
        if (!$value$plusargs("mem_wait_fixed=%d", wait_fixed)) wait_fixed = 0;
        tohost_en = $value$plusargs("tohost=%h", tohost_addr);

        repeat (3) @(posedge clk);
        rst = 1'b0;

        while (!done && cycle < max_cycles) begin
            @(posedge clk);
            cycle++;
        end

        if ($value$plusargs("signature=%s", sig_file) &&
            $value$plusargs("sig_begin=%h", sig_begin) &&
            $value$plusargs("sig_end=%h", sig_end)) begin
            fd = $fopen(sig_file, "w");
            for (logic [31:0] a = sig_begin; a < sig_end; a += 4) begin
                $fwrite(fd, "%08x\n", ram[a[RAM_ADDR_W-1:2]]);
            end
            $fclose(fd);
        end

        if (!done) begin
            $display("TEST_RESULT status=TIMEOUT code=0 cycles=%0d", cycle);
        end else if (tohost_hit && result != 32'd1) begin
            // riscv-tests encode the failing test number as (n << 1) | 1
            $display("TEST_RESULT status=FAIL code=%0d cycles=%0d", result >> 1, cycle);
        end else if (result == 32'd1) begin
            $display("TEST_RESULT status=PASS code=1 cycles=%0d", cycle);
        end else begin
            $display("TEST_RESULT status=FAIL code=%0d cycles=%0d", result, cycle);
        end
        $finish;
    end
endmodule
