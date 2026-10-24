package anv32_soc_addr_pkg;

    localparam logic [31:0] BRAM_BASE        = 32'h0000_0000;
    localparam logic [31:0] BRAM_SIZE        = 32'h0001_0000;  // region size; 4 KiB populated today

    // Reserved, no hardware yet
    localparam logic [31:0] BOOTROM_BASE     = 32'h0001_0000;
    localparam logic [31:0] BOOTROM_SIZE     = 32'h0001_0000;

    localparam logic [31:0] MMIO_BASE        = 32'h1000_0000;
    localparam logic [31:0] MMIO_SIZE        = 32'h0001_0000;
    localparam logic [31:0] MMIO_SLOT_SIZE   = 32'h0000_1000;

    localparam logic [31:0] SYSCTRL_BASE     = 32'h1000_0000;
    localparam logic [31:0] GPIO0_BASE       = 32'h1000_1000;
    localparam logic [31:0] UART0_BASE       = 32'h1000_2000;
    localparam logic [31:0] I2C0_BASE        = 32'h1000_3000;
    // Reserved slots, no hardware yet
    localparam logic [31:0] SPI0_BASE        = 32'h1000_4000;
    localparam logic [31:0] TIMER0_BASE      = 32'h1000_5000;
    localparam logic [31:0] PWM0_BASE        = 32'h1000_6000;
    localparam logic [31:0] IRQCTRL_BASE     = 32'h1000_7000;
    localparam logic [31:0] WATCHDOG_BASE    = 32'h1000_8000;
    localparam logic [31:0] UART1_BASE       = 32'h1000_9000;

    localparam logic [31:0] NN_BASE          = 32'h1001_0000;
    localparam logic [31:0] NN_SIZE          = 32'h0001_0000;
    localparam logic [31:0] NN_SCRATCH_BASE  = 32'h1001_1000;

    // Reserved, no hardware yet
    localparam logic [31:0] DMA_BASE         = 32'h1002_0000;
    localparam logic [31:0] DMA_SIZE         = 32'h0001_0000;

    // External devices and memory, no hardware yet
    localparam logic [31:0] EXT_DEVICE_BASE  = 32'h2000_0000;
    localparam logic [31:0] EXT_DEVICE_SIZE  = 32'h1000_0000;

    localparam logic [31:0] EXT_RAM_BASE     = 32'h8000_0000;
    localparam logic [31:0] EXT_RAM_SIZE     = 32'h1000_0000;

endpackage
