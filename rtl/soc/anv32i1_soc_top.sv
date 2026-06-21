module anv32i1_soc_top(
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic gpio_irq_i,
    output logic [3:0] debug_leds
);
    localparam int BRAM_ADDR_W = 10;
    localparam logic [31:0] LED_ADDR             = 32'h1000_0000;
    localparam logic [31:0] GPIO_IRQ_PENDING_ADDR = 32'h1000_0010;

    logic rst_i;
    logic [31:0] led_reg;
    logic        gpio_irq_pending;

    logic [31:0] instr_addr;
    logic [31:0] instr_rdata;

    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [31:0] mem_rdata;
    logic [3:0]  mem_we;

    logic [BRAM_ADDR_W-1:0] imem_addr;
    logic [BRAM_ADDR_W-1:0] dmem_addr;
    logic [31:0]            dmem_rdata;
    logic [3:0]             dmem_we;

    logic                   led_sel;
    logic                   led_write;
    logic                   gpio_irq_pending_sel;
    logic                   gpio_irq_pending_clear;
    logic                   mmio_sel;
    logic                   mmio_sel_q;
    logic [31:0]            mmio_rdata;
    logic [31:0]            mmio_rdata_q;

    logic gpio_irq_reg, gpio_irq_reg2, gpio_irq_reg2_q, gpio_irq_rise;

    assign rst_i = ~rst_n_i;
    assign debug_leds = ~led_reg[3:0];
    assign imem_addr = instr_addr[BRAM_ADDR_W+1:2];
    assign dmem_addr = mem_addr[BRAM_ADDR_W+1:2];
    assign led_sel = (mem_addr == LED_ADDR);
    assign gpio_irq_pending_sel = (mem_addr == GPIO_IRQ_PENDING_ADDR);
    assign mmio_sel = led_sel || gpio_irq_pending_sel;
    assign led_write = led_sel && (mem_we != 4'b0);
    assign gpio_irq_pending_clear = gpio_irq_pending_sel && (mem_we != 4'b0) && mem_wdata[0];
    assign dmem_we = mmio_sel ? 4'b0 : mem_we;
    assign mmio_rdata = led_sel ? led_reg :
                        gpio_irq_pending_sel ? {31'b0, gpio_irq_pending} :
                        32'b0;
    assign mem_rdata = mmio_sel_q ? mmio_rdata_q : dmem_rdata;
    assign gpio_irq_rise = gpio_irq_reg2 && !gpio_irq_reg2_q;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            led_reg         <= 32'b0;
            gpio_irq_reg    <= 1'b0;
            gpio_irq_reg2   <= 1'b0;
            gpio_irq_reg2_q <= 1'b0;
            gpio_irq_pending <= 1'b0;
            mmio_sel_q      <= 1'b0;
            mmio_rdata_q    <= 32'b0;
        end else if (led_write) begin
            led_reg <= mem_wdata;
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


    anv32i1_top core (
        .clk_i(clk_i), 
        .rst_i(rst_i), 
        .stall_i(1'b0), 
        .pc_jmp_en_i(1'b0),
        .pc_jmp_addr_i(32'b0),
        .instr_o(), 
        .pc_o(),
        .instr_valid_o(),
        .instr_i(instr_rdata),
        .instr_addr_o(instr_addr),
        .mem_rdata_i(mem_rdata),
        .mem_wdata_o(mem_wdata),
        .mem_addr_o(mem_addr),
        .mem_we(mem_we),
        .ext_irq_i(gpio_irq_pending)
    );

    anv32_bram_tdp #(
        .ADDR_W(BRAM_ADDR_W),
        .INIT_FILE("src/prog")
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
