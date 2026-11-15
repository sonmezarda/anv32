`timescale 1ns/1ps

// Runs one SoC test program (sw/tests/soc) on anv32_soc. The program is
// loaded at run time, so one build per core covers every test. Results are
// reported through the SYSCTRL LED register; see sw/tests/soc/soc_test.h.
//
// Without HAS_EXT_RAM the program goes into the BRAM at 0. With it, the
// program (linked at 0x80000000, sw/common/link_ext.ld) goes into external
// RAM behind the caches and the core starts there. External RAM is two AXI3
// memory models (axi3_mem) holding the same image, one per cache port, at
// EXT_RAM_BASE + EXT_OFFSET; a protocol error in either fails the test
// (code 900), and so does an MMIO access while a store is still buffered in
// the data cache (code 901).
//
// Plusargs:
//   +prog=<base>        image base name: loads <base>_lane[0-3].hex into the
//                       BRAM, or <base>.hex into external RAM
//   +max_cycles=<n>     timeout (default 200000)
module tb_soc_test #(
    parameter int unsigned CORE_TYPE   = 2,
    parameter int unsigned BRAM_ADDR_W = 10,
    parameter bit          HAS_NN      = 1'b1,
    parameter bit          MUL_PIPE    = 1'b0,     // anv32im2 only
    parameter bit          HAS_EXT_RAM = 1'b0
);
    localparam logic [31:0] EXT_OFFSET = 32'h9000_0000;     // 0x80000000 -> 0x10000000
    localparam logic [31:0] EXT_AXI    = 32'h8000_0000 + EXT_OFFSET;
    localparam int unsigned EXT_WORDS  = 16384;             // 64 KiB, as link_ext.ld
    localparam logic [31:0] LED_PASS       = 32'h2;
    localparam logic [31:0] LED_GPIO_PULSE = 32'h5;

    logic clk_i = 1'b0;
    logic rst_n_i = 1'b0;
    logic gpio_irq_i = 1'b0;
    logic uart_line;
    logic [3:0] debug_leds;

    tri1 i2c_sda_io;
    tri1 i2c_scl_io;

    always #5 clk_i = ~clk_i;

    // ---- External RAM: one AXI3 port per cache -------------------------------
    logic [5:0]  i_arid, i_rid, d_arid, d_rid, d_awid, d_wid, d_bid;
    logic [31:0] i_araddr, d_araddr, d_awaddr;
    logic [3:0]  i_arlen, d_arlen, d_awlen;
    logic [2:0]  i_arsize, d_arsize, d_awsize;
    logic [1:0]  i_arburst, d_arburst, d_awburst, i_rresp, d_rresp, d_bresp;
    logic        i_arvalid, i_arready, i_rlast, i_rvalid, i_rready;
    logic        d_arvalid, d_arready, d_rlast, d_rvalid, d_rready;
    logic        d_awvalid, d_awready, d_wlast, d_wvalid, d_wready, d_bvalid, d_bready;
    logic [63:0] i_rdata, d_rdata, d_wdata;
    logic [7:0]  d_wstrb;
    int unsigned i_errors, d_errors;

    axi3_mem #(.DW(64), .NAME("instruction port"), .INIT_BASE(EXT_AXI), .INIT_WORDS(EXT_WORDS)) imem (
        .clk(clk_i), .rst(!rst_n_i),
        .s_axi_arid(i_arid), .s_axi_araddr(i_araddr), .s_axi_arlen(i_arlen), .s_axi_arsize(i_arsize),
        .s_axi_arburst(i_arburst), .s_axi_arvalid(i_arvalid), .s_axi_arready(i_arready),
        .s_axi_rid(i_rid), .s_axi_rdata(i_rdata), .s_axi_rresp(i_rresp), .s_axi_rlast(i_rlast),
        .s_axi_rvalid(i_rvalid), .s_axi_rready(i_rready),
        .s_axi_awid(6'd0), .s_axi_awaddr(32'd0), .s_axi_awlen(4'd0), .s_axi_awsize(3'd3),
        .s_axi_awburst(2'b01), .s_axi_awvalid(1'b0), .s_axi_awready(),
        .s_axi_wid(6'd0), .s_axi_wdata(64'd0), .s_axi_wstrb(8'd0), .s_axi_wlast(1'b1),
        .s_axi_wvalid(1'b0), .s_axi_wready(),
        .s_axi_bid(), .s_axi_bresp(), .s_axi_bvalid(), .s_axi_bready(1'b1),
        .poke_valid(1'b0), .poke_addr(32'd0), .poke_data(32'd0),
        .pending_writes(), .errors(i_errors)
    );

    axi3_mem #(.DW(64), .NAME("data port"), .INIT_BASE(EXT_AXI), .INIT_WORDS(EXT_WORDS)) dmem (
        .clk(clk_i), .rst(!rst_n_i),
        .s_axi_arid(d_arid), .s_axi_araddr(d_araddr), .s_axi_arlen(d_arlen), .s_axi_arsize(d_arsize),
        .s_axi_arburst(d_arburst), .s_axi_arvalid(d_arvalid), .s_axi_arready(d_arready),
        .s_axi_rid(d_rid), .s_axi_rdata(d_rdata), .s_axi_rresp(d_rresp), .s_axi_rlast(d_rlast),
        .s_axi_rvalid(d_rvalid), .s_axi_rready(d_rready),
        .s_axi_awid(d_awid), .s_axi_awaddr(d_awaddr), .s_axi_awlen(d_awlen), .s_axi_awsize(d_awsize),
        .s_axi_awburst(d_awburst), .s_axi_awvalid(d_awvalid), .s_axi_awready(d_awready),
        .s_axi_wid(d_wid), .s_axi_wdata(d_wdata), .s_axi_wstrb(d_wstrb), .s_axi_wlast(d_wlast),
        .s_axi_wvalid(d_wvalid), .s_axi_wready(d_wready),
        .s_axi_bid(d_bid), .s_axi_bresp(d_bresp), .s_axi_bvalid(d_bvalid), .s_axi_bready(d_bready),
        .poke_valid(1'b0), .poke_addr(32'd0), .poke_data(32'd0),
        .pending_writes(), .errors(d_errors)
    );

    // Every build option is pinned here, so the tests do not follow whatever
    // defaults anv32_soc currently carries for an FPGA build.
    anv32_soc #(
        .CORE_TYPE(CORE_TYPE),
        .MUL_PIPE(MUL_PIPE),
        .BRAM_ADDR_W(BRAM_ADDR_W),
        .POR_CYCLES(4),
        .INIT_FILE(""),
        .CLK_FREQ(27_000_000),
        .MTIME_FREQ(1_000_000),     // one mtime tick every 27 clocks
        .HAS_CLINT(1'b1),
        .HAS_GPIO(1'b1),
        .HAS_NN(HAS_NN),
        .HAS_SYSCTRL(1'b1),
        .HAS_UART(1'b1),
        .HAS_I2C(1'b1),
        .HAS_BOOTLOADER(1'b0),      // programs are loaded and run from reset
        .HAS_EXT_RAM(HAS_EXT_RAM),
        .RESET_TO_EXT(HAS_EXT_RAM)
    ) dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .gpio_irq_i(gpio_irq_i),
        .uart_rx_i(uart_line),
        .i2c_sda_io(i2c_sda_io),
        .i2c_scl_io(i2c_scl_io),
        .uart_tx_o(uart_line),
        .debug_leds(debug_leds),
        .ext_addr_offset_i(EXT_OFFSET),
        .m_axi_i_arid(i_arid), .m_axi_i_araddr(i_araddr), .m_axi_i_arlen(i_arlen),
        .m_axi_i_arsize(i_arsize), .m_axi_i_arburst(i_arburst), .m_axi_i_arlock(),
        .m_axi_i_arcache(), .m_axi_i_arprot(), .m_axi_i_arqos(),
        .m_axi_i_arvalid(i_arvalid), .m_axi_i_arready(i_arready),
        .m_axi_i_rid(i_rid), .m_axi_i_rdata(i_rdata), .m_axi_i_rresp(i_rresp),
        .m_axi_i_rlast(i_rlast), .m_axi_i_rvalid(i_rvalid), .m_axi_i_rready(i_rready),
        .m_axi_d_arid(d_arid), .m_axi_d_araddr(d_araddr), .m_axi_d_arlen(d_arlen),
        .m_axi_d_arsize(d_arsize), .m_axi_d_arburst(d_arburst), .m_axi_d_arlock(),
        .m_axi_d_arcache(), .m_axi_d_arprot(), .m_axi_d_arqos(),
        .m_axi_d_arvalid(d_arvalid), .m_axi_d_arready(d_arready),
        .m_axi_d_rid(d_rid), .m_axi_d_rdata(d_rdata), .m_axi_d_rresp(d_rresp),
        .m_axi_d_rlast(d_rlast), .m_axi_d_rvalid(d_rvalid), .m_axi_d_rready(d_rready),
        .m_axi_d_awid(d_awid), .m_axi_d_awaddr(d_awaddr), .m_axi_d_awlen(d_awlen),
        .m_axi_d_awsize(d_awsize), .m_axi_d_awburst(d_awburst), .m_axi_d_awlock(),
        .m_axi_d_awcache(), .m_axi_d_awprot(), .m_axi_d_awqos(),
        .m_axi_d_awvalid(d_awvalid), .m_axi_d_awready(d_awready),
        .m_axi_d_wid(d_wid), .m_axi_d_wdata(d_wdata), .m_axi_d_wstrb(d_wstrb),
        .m_axi_d_wlast(d_wlast), .m_axi_d_wvalid(d_wvalid), .m_axi_d_wready(d_wready),
        .m_axi_d_bid(d_bid), .m_axi_d_bresp(d_bresp), .m_axi_d_bvalid(d_bvalid),
        .m_axi_d_bready(d_bready)
    );

    // With external RAM, an access outside the BRAM and external RAM must only
    // go out once every buffered store is in memory
    logic drain_error = 1'b0;

    always @(posedge clk_i) begin
        if (HAS_EXT_RAM && rst_n_i && dut.cpu_req.valid && dut.cpu_rsp.ready &&
            dut.cpu_req.addr[31:16] != 16'h0000 && dut.cpu_req.addr[31:28] != 4'h8 &&
            !dut.dcache_drained) begin
            drain_error <= 1'b1;
        end
    end

    // Pulse the GPIO interrupt input when the program asks for it
    logic [31:0] led_q = '0;

    always @(posedge clk_i) begin
        led_q <= dut.led_reg;
        if (dut.led_reg == LED_GPIO_PULSE && led_q != LED_GPIO_PULSE) begin
            gpio_irq_i <= 1'b1;
        end else if (gpio_irq_i) begin
            gpio_irq_i <= 1'b0;
        end
    end

    initial begin
        string prog;
        int unsigned max_cycles;
        int unsigned cycle;

        if (!$value$plusargs("prog=%s", prog)) begin
            $fatal(1, "missing +prog=<image base>");
        end
        if (!$value$plusargs("max_cycles=%d", max_cycles)) max_cycles = 200000;
        if (HAS_EXT_RAM) begin
            $readmemh({prog, ".hex"}, imem.init_ram);
            $readmemh({prog, ".hex"}, dmem.init_ram);
        end else begin
            $readmemh({prog, "_lane0.hex"}, dut.ram.lane[0].mem);
            $readmemh({prog, "_lane1.hex"}, dut.ram.lane[1].mem);
            $readmemh({prog, "_lane2.hex"}, dut.ram.lane[2].mem);
            $readmemh({prog, "_lane3.hex"}, dut.ram.lane[3].mem);
        end

        repeat (5) @(posedge clk_i);
        rst_n_i = 1'b1;

        for (cycle = 0; cycle < max_cycles; cycle++) begin
            @(posedge clk_i);
            if (i_errors != 0 || d_errors != 0) begin
                $display("TEST_RESULT status=FAIL code=900 cycles=%0d", cycle);   // AXI protocol
                $finish;
            end
            if (drain_error) begin
                $display("TEST_RESULT status=FAIL code=901 cycles=%0d", cycle);   // MMIO before drain
                $finish;
            end
            if (dut.led_reg == LED_PASS) begin
                $display("TEST_RESULT status=PASS code=1 cycles=%0d", cycle);
                $finish;
            end
            if (dut.led_reg[3:0] == 4'hF || dut.led_reg[3:0] == 4'hE) begin
                $display("TEST_RESULT status=FAIL code=%0d cycles=%0d", dut.led_reg >> 8, cycle);
                $finish;
            end
        end

        $display("TEST_RESULT status=TIMEOUT code=0 cycles=%0d", cycle);
        $finish;
    end
endmodule
