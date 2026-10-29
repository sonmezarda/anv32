`timescale 1ns/1ps

// Runs one SoC test program (sw/tests/soc) on anv32_soc_top. The program is
// loaded into the BRAM at run time, so one build per core covers every test.
// Results are reported through the SYSCTRL LED register; see
// sw/tests/soc/soc_test.h.
//
// Plusargs:
//   +prog=<base>        image base name, loads <base>_lane[0-3].hex
//   +max_cycles=<n>     timeout (default 200000)
module tb_soc_test #(
    parameter int unsigned CORE_TYPE = 2
);
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

    // Every build option is pinned here, so the tests do not follow whatever
    // defaults anv32_soc_top currently carries for an FPGA build.
    anv32_soc_top #(
        .CORE_TYPE(CORE_TYPE),
        .BRAM_ADDR_W(10),
        .POR_CYCLES(4),
        .INIT_FILE(""),
        .CLK_FREQ(27_000_000),
        .MTIME_FREQ(1_000_000),     // one mtime tick every 27 clocks
        .HAS_CLINT(1'b1),
        .HAS_GPIO(1'b1),
        .HAS_NN(1'b1),
        .HAS_SYSCTRL(1'b1),
        .HAS_UART(1'b1),
        .HAS_I2C(1'b1)
    ) dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .gpio_irq_i(gpio_irq_i),
        .uart_rx_i(uart_line),
        .i2c_sda_io(i2c_sda_io),
        .i2c_scl_io(i2c_scl_io),
        .uart_tx_o(uart_line),
        .debug_leds(debug_leds)
    );

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
        $readmemh({prog, "_lane0.hex"}, dut.ram.lane[0].mem);
        $readmemh({prog, "_lane1.hex"}, dut.ram.lane[1].mem);
        $readmemh({prog, "_lane2.hex"}, dut.ram.lane[2].mem);
        $readmemh({prog, "_lane3.hex"}, dut.ram.lane[3].mem);

        repeat (5) @(posedge clk_i);
        rst_n_i = 1'b1;

        for (cycle = 0; cycle < max_cycles; cycle++) begin
            @(posedge clk_i);
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
