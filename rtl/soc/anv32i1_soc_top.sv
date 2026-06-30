module anv32i1_soc_top(
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic gpio_irq_i,
    input  logic uart_rx_i,
    inout  logic i2c_sda_io,
    inout  logic i2c_scl_io,
    output logic uart_tx_o,
    output logic [3:0] debug_leds
);
    anv32_soc_top #(.CORE_TYPE(0)) soc (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .gpio_irq_i(gpio_irq_i),
        .uart_rx_i(uart_rx_i),
        .i2c_sda_io(i2c_sda_io),
        .i2c_scl_io(i2c_scl_io),
        .uart_tx_o(uart_tx_o),
        .debug_leds(debug_leds)
    );
endmodule
