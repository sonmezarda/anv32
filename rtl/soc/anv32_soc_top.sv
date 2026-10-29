// The single SoC top. Every build option is a parameter here: the core, the
// memory size, the clock and which peripherals exist. A disabled peripheral
// keeps its bus slot and address range, which then read as zero and ignore
// writes like an unmapped address, so the memory map and software layout do
// not change between configurations.
module anv32_soc_top
    import anv32_bus_pkg::*;
    import anv32_soc_addr_pkg::*;
#(
    parameter int unsigned CORE_TYPE   = 2,           // 0 = i1, 1 = im1, 2 = im2
    parameter int unsigned BRAM_ADDR_W = 10,
    parameter int unsigned POR_CYCLES  = 8,
    parameter              INIT_FILE   = "src/prog",
    parameter int unsigned CLK_FREQ    = 27_000_000,  // Hz, for UART/I2C timing
    parameter int unsigned MTIME_FREQ  = 1_000_000,   // Hz, CLINT mtime rate; must divide CLK_FREQ

    // Peripherals
    parameter bit HAS_CLINT   = 1'b1,
    parameter bit HAS_GPIO    = 1'b1,
    parameter bit HAS_NN      = 1'b1,
    parameter bit HAS_SYSCTRL = 1'b1,
    parameter bit HAS_UART    = 1'b1,
    parameter bit HAS_I2C     = 1'b1
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

    // Fast bus: zero wait states. GPIO0 sits inside the MMIO region but comes
    // first, so it is decoded here instead of behind the peripheral bridge.
    localparam int unsigned FAST_GPIO   = 0;
    localparam int unsigned FAST_BRAM   = 1;
    localparam int unsigned FAST_NN     = 2;
    localparam int unsigned FAST_PERIPH = 3;
    localparam int unsigned FAST_CLINT  = 4;
    localparam int unsigned FAST_N      = 5;
    localparam logic [FAST_N-1:0][31:0] FAST_BASE =     // index 4 .. 0
        {CLINT_BASE, MMIO_BASE, NN_BASE, BRAM_BASE, GPIO0_BASE};
    localparam logic [FAST_N-1:0][31:0] FAST_MASK =
        {~(CLINT_SIZE - 1), ~(MMIO_SIZE - 1), ~(NN_SIZE - 1), ~(BRAM_SIZE - 1),
         ~(MMIO_SLOT_SIZE - 1)};

    // Peripheral bus: behind a register slice, one extra cycle per access
    localparam int unsigned PERIPH_SYSCTRL = 0;
    localparam int unsigned PERIPH_UART    = 1;
    localparam int unsigned PERIPH_I2C     = 2;
    localparam int unsigned PERIPH_N       = 3;
    localparam logic [PERIPH_N-1:0][31:0] PERIPH_BASE = // index 2 .. 0
        {I2C0_BASE, UART0_BASE, SYSCTRL_BASE};
    localparam logic [PERIPH_N-1:0][31:0] PERIPH_MASK = {PERIPH_N{~(MMIO_SLOT_SIZE - 1)}};

    logic rst_i;
    logic [POR_CYCLES-1:0] por_shift = '0;

    logic [31:0] instr_addr;
    logic [31:0] instr_rdata;

    // Core data port
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [31:0] mem_rdata;
    logic        mem_valid;
    logic        mem_ready;
    logic [3:0]  mem_we;

    bus_req_t                   core_req;
    bus_rsp_t                   core_rsp;
    bus_req_t [FAST_N-1:0]      fast_req;
    bus_rsp_t [FAST_N-1:0]      fast_rsp;
    bus_req_t                   periph_req;
    bus_rsp_t                   periph_rsp;
    bus_req_t [PERIPH_N-1:0]    p_req;
    bus_rsp_t [PERIPH_N-1:0]    p_rsp;

    logic [BRAM_ADDR_W-1:0] imem_addr;
    logic [BRAM_ADDR_W-1:0] dmem_addr;
    logic [31:0]            dmem_rdata;
    logic [3:0]             dmem_we;

    logic [31:0] led_reg;
    logic        gpio_irq_pending;
    logic        i2c_irq;
    logic        nn_accel_irq;
    logic        external_irq;
    logic        clint_timer_irq;   // MTIP
    logic        clint_sw_irq;      // MSIP

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) por_shift <= '0;
        else          por_shift <= {por_shift[POR_CYCLES-2:0], 1'b1};
    end

    assign rst_i        = ~por_shift[POR_CYCLES-1];
    assign debug_leds   = ~led_reg[3:0];
    assign external_irq = gpio_irq_pending || nn_accel_irq;

    // ---- Bus fabric ---------------------------------------------------------
    // The core's request first passes through a read-data register stage that
    // registers slow (fast==0) peripheral reads at the boundary, keeping their
    // read data out of the core's combinational load/forwarding path. Fast
    // slaves (BRAM, GPIO) and writes pass through with no added latency.
    bus_req_t cpu_req;
    bus_rsp_t cpu_rsp;

    assign cpu_req.valid = mem_valid;
    assign cpu_req.addr  = mem_addr;
    assign cpu_req.wdata = mem_wdata;
    assign cpu_req.we    = mem_we;
    assign mem_ready     = cpu_rsp.ready;
    assign mem_rdata     = cpu_rsp.rdata;

    // Split the decoded read data into fast and slow buses by slave class. Each
    // slave's bus_rsp_t.fast is a constant, so the per-slave routing resolves at
    // elaboration: a slow slave's read register (e.g. NN scratch) only reaches
    // rdata_slow, never rdata_fast, so the read pipe can register it away from
    // the core's combinational load path. rd_sel/rd_hit name the slave that
    // owns the read data this cycle.
    logic                            rd_hit;
    logic [$clog2(FAST_N)-1:0]       rd_sel;
    logic [31:0]                     rdata_fast;
    logic [31:0]                     rdata_slow;

    always_comb begin
        rdata_fast = 32'b0;
        rdata_slow = 32'b0;
        if (rd_hit) begin
            for (int unsigned i = 0; i < FAST_N; i++) begin
                if (rd_sel == i[$clog2(FAST_N)-1:0]) begin
                    if (fast_rsp[i].fast) rdata_fast = fast_rsp[i].rdata;
                    else                  rdata_slow = fast_rsp[i].rdata;
                end
            end
        end
    end

    anv32_bus_read_pipe read_pipe (
        .clk_i       (clk_i),
        .rst_i       (rst_i),
        .m_req_i     (cpu_req),
        .m_rsp_o     (cpu_rsp),
        .s_req_o     (core_req),
        .s_rsp_i     (core_rsp),
        .rdata_fast_i(rdata_fast),
        .rdata_slow_i(rdata_slow)
    );

    anv32_bus_decoder #(
        .N   (FAST_N),
        .BASE(FAST_BASE),
        .MASK(FAST_MASK)
    ) fast_bus (
        .clk_i  (clk_i),
        .rst_i  (rst_i),
        .m_req_i(core_req),
        .m_rsp_o(core_rsp),
        .s_req_o(fast_req),
        .s_rsp_i(fast_rsp),
        .rd_hit_o(rd_hit),
        .rd_sel_o(rd_sel)
    );

    anv32_bus_bridge periph_bridge (
        .clk_i  (clk_i),
        .rst_i  (rst_i),
        .m_req_i(fast_req[FAST_PERIPH]),
        .m_rsp_o(fast_rsp[FAST_PERIPH]),
        .s_req_o(periph_req),
        .s_rsp_i(periph_rsp)
    );

    anv32_bus_decoder #(
        .N   (PERIPH_N),
        .BASE(PERIPH_BASE),
        .MASK(PERIPH_MASK)
    ) periph_bus (
        .clk_i  (clk_i),
        .rst_i  (rst_i),
        .m_req_i (periph_req),
        .m_rsp_o (periph_rsp),
        .s_req_o (p_req),
        .s_rsp_i (p_rsp),
        .rd_hit_o(),            // only the fast bus splits read data by slave
        .rd_sel_o()
    );

    // ---- Fast slaves ----------------------------------------------------------
    // BRAM: synchronous read, so read data already arrives one cycle later.
    // Only the low BRAM_ADDR_W bits decode; the rest of the region wraps.
    assign dmem_addr           = fast_req[FAST_BRAM].addr[BRAM_ADDR_W+1:2];
    assign dmem_we             = fast_req[FAST_BRAM].valid ? fast_req[FAST_BRAM].we : 4'b0;
    assign fast_rsp[FAST_BRAM] = '{ready: 1'b1, fast: 1'b1, rdata: dmem_rdata};
    assign imem_addr           = instr_addr[BRAM_ADDR_W+1:2];

    // CLINT: machine timer and software interrupt, wired straight to the core
    // (not through the external interrupt line).
    generate
        if (HAS_CLINT) begin : g_clint
            anv32_clint #(
                .CLK_FREQ  (CLK_FREQ),
                .MTIME_FREQ(MTIME_FREQ)
            ) clint (
                .clk_i      (clk_i),
                .rst_i      (rst_i),
                .req_i      (fast_req[FAST_CLINT]),
                .rsp_o      (fast_rsp[FAST_CLINT]),
                .timer_irq_o(clint_timer_irq),
                .sw_irq_o   (clint_sw_irq)
            );
        end else begin : g_no_clint
            assign fast_rsp[FAST_CLINT] = '{ready: 1'b1, fast: 1'b1, rdata: 32'b0};   // absent: reads as zero
            assign clint_timer_irq      = 1'b0;
            assign clint_sw_irq         = 1'b0;
        end
    endgenerate

    generate
        if (HAS_GPIO) begin : g_gpio
            gpio_periph gpio (
                .clk_i(clk_i),
                .rst_i(rst_i),
                .req_i(fast_req[FAST_GPIO]),
                .rsp_o(fast_rsp[FAST_GPIO]),
                .irq_i(gpio_irq_i),
                .irq_o(gpio_irq_pending)
            );
        end else begin : g_no_gpio
            assign fast_rsp[FAST_GPIO] = '{ready: 1'b1, fast: 1'b1, rdata: 32'b0};   // absent: reads as zero
            assign gpio_irq_pending    = 1'b0;
        end
    endgenerate

    // NN accelerator. Register reads are registered here so they arrive one
    // cycle later like every other slave; scratch reads come straight from
    // the scratch BRAM, which is already registered. Parts of the aperture
    // the accelerator does not decode are accepted and read as zero.
    generate
        if (HAS_NN) begin : g_nn
            logic        nn_accel_hit;
            logic        nn_accel_ready;
            logic [31:0] nn_accel_rdata;
            logic [31:0] nn_rdata_q;
            logic        nn_scratch_sel;
            logic        nn_scratch_sel_q;
            logic [31:0] nn_scratch_rdata;

            nn_accel_periph #(
                .BASE_ADDR(NN_BASE),
                .SCRATCH_OFFSET(NN_SCRATCH_BASE - NN_BASE),
                .SCRATCH_WORDS(4096)
            ) nn_accel (
                .clk_i(clk_i),
                .rst_i(rst_i),
                .mem_valid_i(fast_req[FAST_NN].valid),
                .mem_addr_i(fast_req[FAST_NN].addr),
                .mem_wdata_i(fast_req[FAST_NN].wdata),
                .mem_we_i(fast_req[FAST_NN].we),
                .mem_ready_o(nn_accel_ready),
                .mem_rdata_o(nn_accel_rdata),
                .mem_hit_o(nn_accel_hit),
                .scratch_rdata_o(nn_scratch_rdata),
                .scratch_sel_o(nn_scratch_sel),
                .irq_o(nn_accel_irq)
            );

            always_ff @(posedge clk_i) begin
                if (rst_i) begin
                    nn_scratch_sel_q <= 1'b0;
                    nn_rdata_q       <= '0;
                end else begin
                    nn_scratch_sel_q <= nn_scratch_sel;
                    if (fast_req[FAST_NN].valid) nn_rdata_q <= nn_accel_hit ? nn_accel_rdata : '0;
                end
            end

            assign fast_rsp[FAST_NN].ready = nn_accel_hit ? nn_accel_ready : 1'b1;
            assign fast_rsp[FAST_NN].fast  = 1'b0;   // slow: registered at the core boundary
            assign fast_rsp[FAST_NN].rdata = nn_scratch_sel_q ? nn_scratch_rdata : nn_rdata_q;
        end else begin : g_no_nn
            assign fast_rsp[FAST_NN] = '{ready: 1'b1, fast: 1'b1, rdata: 32'b0};   // absent: reads as zero
            assign nn_accel_irq      = 1'b0;
        end
    endgenerate

    // ---- Peripheral slaves --------------------------------------------------
    generate
        if (HAS_SYSCTRL) begin : g_sysctrl
            sysctrl_periph sysctrl (
                .clk_i(clk_i),
                .rst_i(rst_i),
                .req_i(p_req[PERIPH_SYSCTRL]),
                .rsp_o(p_rsp[PERIPH_SYSCTRL]),
                .led_o(led_reg)
            );
        end else begin : g_no_sysctrl
            assign p_rsp[PERIPH_SYSCTRL] = '{ready: 1'b1, fast: 1'b1, rdata: 32'b0};   // absent: reads as zero
            assign led_reg               = '0;   // LEDs stay off
        end

        if (HAS_UART) begin : g_uart
            uart_periph #(
                .CLK_FREQ(CLK_FREQ)
            ) uart (
                .clk_i    (clk_i),
                .rst_i    (rst_i),
                .req_i    (p_req[PERIPH_UART]),
                .rsp_o    (p_rsp[PERIPH_UART]),
                .uart_rx_i(uart_rx_i),
                .uart_tx_o(uart_tx_o)
            );
        end else begin : g_no_uart
            assign p_rsp[PERIPH_UART] = '{ready: 1'b1, fast: 1'b1, rdata: 32'b0};   // absent: reads as zero
            assign uart_tx_o          = 1'b1;   // line idles high
        end

        if (HAS_I2C) begin : g_i2c
            // SCL period = 2 * 135 cycles = 100 kHz at 27 MHz; scale with CLK_FREQ.
            localparam int unsigned SCL_HALF = CLK_FREQ / 200_000;

            i2c_periph #(
                .CLK_FREQ(CLK_FREQ),
                .CMD_FIFO_DEPTH(16),
                .RX_FIFO_DEPTH(8),
                .SCL_LOW_CYCLES(SCL_HALF),
                .SCL_HIGH_CYCLES(SCL_HALF),
                .STRETCH_TIMEOUT_CYCLES(CLK_FREQ / 100)   // 10 ms
            ) i2c (
                .clk_i(clk_i),
                .rst_i(rst_i),
                .req_i(p_req[PERIPH_I2C]),
                .rsp_o(p_rsp[PERIPH_I2C]),
                .sda_io(i2c_sda_io),
                .scl_io(i2c_scl_io),
                .irq_o(i2c_irq)
            );
        end else begin : g_no_i2c
            assign p_rsp[PERIPH_I2C] = '{ready: 1'b1, fast: 1'b1, rdata: 32'b0};   // absent: reads as zero
            assign i2c_irq           = 1'b0;
            assign i2c_sda_io        = 1'bz;    // released; external pull-ups hold the bus idle
            assign i2c_scl_io        = 1'bz;
        end
    endgenerate

    // ---- Core -----------------------------------------------------------------
    generate
        if (CORE_TYPE == CORE_ANV32I1) begin : g_core_i1
            anv32i1_top core (
                .clk_i(clk_i),
                .rst_i(rst_i),
                .stall_i(1'b0),
                .pc_jmp_en_i(1'b0),
                .pc_jmp_addr_i(32'b0),
                .ext_irq_i(external_irq),
                .timer_irq_i(clint_timer_irq),
                .sw_irq_i(clint_sw_irq),
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
                .ext_irq_i(external_irq),
                .timer_irq_i(clint_timer_irq),
                .sw_irq_i(clint_sw_irq),
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
                .ext_irq_i(external_irq),
                .timer_irq_i(clint_timer_irq),
                .sw_irq_i(clint_sw_irq),
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
        .wdata_a(fast_req[FAST_BRAM].wdata),
        .we_a(dmem_we),
        .rdata_a(dmem_rdata),

        .addr_b(imem_addr),
        .wdata_b(32'b0),
        .we_b(4'b0),
        .rdata_b(instr_rdata)
    );

endmodule
