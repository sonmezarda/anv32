module tb_nn_accel_soc;
    logic clk_i = 1'b0;
    logic rst_n_i = 1'b0;
    logic gpio_irq_i = 1'b0;
    logic uart_rx_i = 1'b1;
    logic uart_tx_o;
    logic [3:0] debug_leds;

    tri1 i2c_sda_io;
    tri1 i2c_scl_io;

    localparam int unsigned MAX_CYCLES = 20_000;
    localparam logic [3:0] PASS_LEDS = 4'hD;
    localparam logic [3:0] ERROR_LEDS = 4'h1;
    localparam logic [3:0] FAIL_LEDS = 4'h0;

    always #5 clk_i = ~clk_i;

    anv32_soc_top #(
        .CORE_TYPE(2),
        .BRAM_ADDR_W(10),
        .POR_CYCLES(4),
        .INIT_FILE("src/prog")
    ) dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .gpio_irq_i(gpio_irq_i),
        .uart_rx_i(uart_rx_i),
        .i2c_sda_io(i2c_sda_io),
        .i2c_scl_io(i2c_scl_io),
        .uart_tx_o(uart_tx_o),
        .debug_leds(debug_leds)
    );

    initial begin
        repeat (5) @(posedge clk_i);
        rst_n_i = 1'b1;

        for (int cycle = 0; cycle < MAX_CYCLES; cycle++) begin
            @(posedge clk_i);

            if (debug_leds == PASS_LEDS) begin
                $display("NN accelerator SoC smoke test passed at cycle %0d", cycle);
                $finish;
            end

            if (debug_leds == ERROR_LEDS) begin
                $fatal(1, "NN accelerator reported an internal error");
            end

            if (debug_leds == FAIL_LEDS) begin
                $fatal(1, "NN accelerator result mismatch");
            end
        end

        $fatal(1, "Timed out waiting for NN accelerator smoke test");
    end
endmodule
