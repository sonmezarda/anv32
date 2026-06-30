module anv32_soc_top #(
    parameter int unsigned CORE_TYPE   = 0,
    parameter int unsigned BRAM_ADDR_W = 10,
    parameter int unsigned POR_CYCLES  = 8,
    parameter              INIT_FILE   = "src/prog"
)(
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic gpio_irq_i,
    input  logic uart_rx_i,
    inout  logic i2c_sda_io,
    inout  logic i2c_scl_io,
    output logic uart_tx_o,
    output logic [3:0] debug_leds
);
    localparam int unsigned CORE_ANV32I1  = 0;
    localparam int unsigned CORE_ANV32IM1 = 1;
    localparam int unsigned CORE_ANV32IM2 = 2;

    localparam logic [31:0] LED_ADDR              = 32'h1000_0000;
    localparam logic [31:0] GPIO_IRQ_PENDING_ADDR = 32'h1000_0010;
    localparam logic [31:0] UART_TXDATA_ADDR      = 32'h1000_1000;
    localparam logic [31:0] UART_STATUS_ADDR      = 32'h1000_1004;
    localparam logic [31:0] UART_BAUD_ADDR        = 32'h1000_1008;
    localparam logic [31:0] UART_ERROR_ADDR       = 32'h1000_100C;
    localparam logic [31:0] I2C_BASE_ADDR         = 32'h1000_2000;

    logic rst_i;
    logic [POR_CYCLES-1:0] por_shift = '0;
    logic [31:0] led_reg;
    logic        gpio_irq_pending;

    logic [31:0] instr_addr;
    logic [31:0] instr_rdata;

    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [31:0] mem_rdata;
    logic        mem_valid;
    logic        mem_ready;
    logic [3:0]  mem_we;

    logic [BRAM_ADDR_W-1:0] imem_addr;
    logic [BRAM_ADDR_W-1:0] dmem_addr;
    logic [31:0]            dmem_rdata;
    logic [3:0]             dmem_we;

    logic                   led_sel;
    logic                   led_write;
    logic                   gpio_irq_pending_sel;
    logic                   gpio_irq_pending_clear;
    logic                   uart_txdata_sel;
    logic                   uart_status_sel;
    logic                   uart_baud_sel;
    logic                   uart_error_sel;
    logic                   i2c_sel;
    logic                   uart_tx_write;
    logic                   uart_baud_write;
    logic                   uart_error_clear;
    logic                   i2c_write;
    logic                   i2c_read;
    logic                   mmio_sel;
    logic                   mmio_sel_q;
    logic [31:0]            mmio_rdata;
    logic [31:0]            mmio_rdata_q;

    logic gpio_irq_reg, gpio_irq_reg2, gpio_irq_reg2_q, gpio_irq_rise;
    logic [31:0] uart_baud_rate;
    logic        uart_tx_ready;
    logic        uart_tx_full;
    logic        uart_tx_empty;
    logic        uart_tx_busy;
    logic        uart_tx_done;
    logic [7:0]  uart_rx_data;
    logic        uart_rx_valid;
    logic        uart_rx_empty;
    logic        uart_rx_full;
    logic        uart_rx_busy;
    logic        uart_framing_error;
    logic        uart_rx_overflow;
    logic        uart_framing_error_pulse;
    logic        uart_rx_overflow_pulse;
    logic [31:0] i2c_rdata;
    logic        i2c_irq;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) por_shift <= '0;
        else          por_shift <= {por_shift[POR_CYCLES-2:0], 1'b1};
    end

    assign rst_i = ~por_shift[POR_CYCLES-1];
    assign debug_leds = ~led_reg[3:0];
    assign imem_addr = instr_addr[BRAM_ADDR_W+1:2];
    assign dmem_addr = mem_addr[BRAM_ADDR_W+1:2];

    assign led_sel = mem_valid && (mem_addr == LED_ADDR);
    assign gpio_irq_pending_sel = mem_valid && (mem_addr == GPIO_IRQ_PENDING_ADDR);
    assign uart_txdata_sel = mem_valid && (mem_addr == UART_TXDATA_ADDR);
    assign uart_status_sel = mem_valid && (mem_addr == UART_STATUS_ADDR);
    assign uart_baud_sel   = mem_valid && (mem_addr == UART_BAUD_ADDR);
    assign uart_error_sel  = mem_valid && (mem_addr == UART_ERROR_ADDR);
    assign i2c_sel = mem_valid && (mem_addr[31:5] == I2C_BASE_ADDR[31:5]);
    assign mmio_sel = led_sel || gpio_irq_pending_sel || uart_txdata_sel ||
                      uart_status_sel || uart_baud_sel || uart_error_sel ||
                      i2c_sel;

    assign led_write = led_sel && mem_ready && (mem_we != 4'b0);
    assign gpio_irq_pending_clear = gpio_irq_pending_sel && mem_ready && (mem_we != 4'b0) && mem_wdata[0];
    assign uart_tx_write    = uart_txdata_sel && mem_ready && (mem_we != 4'b0);
    assign uart_baud_write  = uart_baud_sel && mem_ready && (mem_we != 4'b0);
    assign uart_error_clear = uart_error_sel && mem_ready && (mem_we != 4'b0) && mem_wdata[0];
    assign i2c_write = i2c_sel && mem_ready && (mem_we != 4'b0);
    assign i2c_read  = i2c_sel && mem_ready && (mem_we == 4'b0);

    assign mem_ready = 1'b1;
    assign dmem_we = (mem_valid && !mmio_sel && mem_ready) ? mem_we : 4'b0;
    assign mmio_rdata = led_sel ? led_reg :
                        gpio_irq_pending_sel ? {31'b0, gpio_irq_pending} :
                        uart_status_sel ? {24'b0,
                                           uart_rx_busy,
                                           uart_rx_full,
                                           uart_rx_empty,
                                           uart_rx_valid,
                                           uart_tx_done,
                                           uart_tx_busy,
                                           uart_tx_empty,
                                           uart_tx_ready} :
                        uart_baud_sel ? uart_baud_rate :
                        uart_error_sel ? {30'b0, uart_rx_overflow, uart_framing_error} :
                        i2c_sel ? i2c_rdata :
                        32'b0;
    assign mem_rdata = mmio_sel_q ? mmio_rdata_q : dmem_rdata;
    assign gpio_irq_rise = gpio_irq_reg2 && !gpio_irq_reg2_q;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            led_reg          <= 32'b0;
            gpio_irq_reg     <= 1'b0;
            gpio_irq_reg2    <= 1'b0;
            gpio_irq_reg2_q  <= 1'b0;
            gpio_irq_pending <= 1'b0;
            uart_baud_rate   <= 32'd115200;
            mmio_sel_q       <= 1'b0;
            mmio_rdata_q     <= 32'b0;
        end else if (led_write) begin
            led_reg <= mem_wdata;
        end else if (uart_baud_write) begin
            uart_baud_rate <= mem_wdata;
        end

        if (!rst_i) begin
            mmio_sel_q   <= mmio_sel;
            mmio_rdata_q <= mmio_rdata;

            gpio_irq_reg    <= gpio_irq_i;
            gpio_irq_reg2   <= gpio_irq_reg;
            gpio_irq_reg2_q <= gpio_irq_reg2;

            if (gpio_irq_pending_clear) begin
                gpio_irq_pending <= 1'b0;
            end
            if (gpio_irq_rise) begin
                gpio_irq_pending <= 1'b1;
            end
        end
    end

    uart_top #(
        .CLK_FREQ      (27_000_000),
        .TX_FIFO_DEPTH (16),
        .RX_FIFO_DEPTH (16),
        .USE_TX_FIFO   (1'b1),
        .USE_RX_FIFO   (1'b1)
    ) uart (
        .clk_i                  (clk_i),
        .rst_i                  (rst_i),
        .baud_rate_i            (uart_baud_rate),
        .uart_rx_i              (uart_rx_i),
        .uart_tx_o              (uart_tx_o),
        .tx_data_i              (mem_wdata[7:0]),
        .tx_valid_i             (uart_tx_write),
        .tx_ready_o             (uart_tx_ready),
        .tx_full_o              (uart_tx_full),
        .tx_empty_o             (uart_tx_empty),
        .tx_busy_o              (uart_tx_busy),
        .tx_done_o              (uart_tx_done),
        .rx_read_i              (1'b0),
        .rx_data_o              (uart_rx_data),
        .rx_valid_o             (uart_rx_valid),
        .rx_empty_o             (uart_rx_empty),
        .rx_full_o              (uart_rx_full),
        .rx_busy_o              (uart_rx_busy),
        .error_clear_i          (uart_error_clear),
        .framing_error_o        (uart_framing_error),
        .rx_overflow_o          (uart_rx_overflow),
        .framing_error_pulse_o  (uart_framing_error_pulse),
        .rx_overflow_pulse_o    (uart_rx_overflow_pulse)
    );

    i2c_periph #(
        .CLK_FREQ(27_000_000),
        .CMD_FIFO_DEPTH(16),
        .RX_FIFO_DEPTH(8),
        .SCL_LOW_CYCLES(135),
        .SCL_HIGH_CYCLES(135),
        .STRETCH_TIMEOUT_CYCLES(270_000)
    ) i2c (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .sel_i(i2c_sel),
        .write_i(i2c_write),
        .read_i(i2c_read),
        .addr_i(mem_addr[4:0]),
        .wdata_i(mem_wdata),
        .rdata_o(i2c_rdata),
        .sda_io(i2c_sda_io),
        .scl_io(i2c_scl_io),
        .irq_o(i2c_irq)
    );

    generate
        if (CORE_TYPE == CORE_ANV32I1) begin : g_core_i1
            anv32i1_top core (
                .clk_i(clk_i),
                .rst_i(rst_i),
                .stall_i(1'b0),
                .pc_jmp_en_i(1'b0),
                .pc_jmp_addr_i(32'b0),
                .ext_irq_i(gpio_irq_pending),
                .instr_o(),
                .pc_o(),
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
        end else if (CORE_TYPE == CORE_ANV32IM1) begin : g_core_im1
            anv32im1_top #(.HAS_M(1'b1)) core (
                .clk_i(clk_i),
                .rst_i(rst_i),
                .stall_i(1'b0),
                .pc_jmp_en_i(1'b0),
                .pc_jmp_addr_i(32'b0),
                .ext_irq_i(gpio_irq_pending),
                .instr_o(),
                .pc_o(),
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
        end else begin : g_core_im2
            anv32im2_top #(.HAS_M(1'b1)) core (
                .clk_i(clk_i),
                .rst_i(rst_i),
                .stall_i(1'b0),
                .pc_jmp_en_i(1'b0),
                .pc_jmp_addr_i(32'b0),
                .ext_irq_i(gpio_irq_pending),
                .instr_o(),
                .pc_o(),
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
        end
    endgenerate

    anv32_bram_tdp #(
        .ADDR_W(BRAM_ADDR_W),
        .INIT_FILE(INIT_FILE)
    ) ram (
        .clk(clk_i),

        .addr_a(dmem_addr),
        .wdata_a(mem_wdata),
        .we_a(dmem_we),
        .rdata_a(dmem_rdata),

        .addr_b(imem_addr),
        .wdata_b(32'b0),
        .we_b(4'b0),
        .rdata_b(instr_rdata)
    );

endmodule
