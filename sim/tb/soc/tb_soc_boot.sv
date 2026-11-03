`timescale 1ns/1ps

// UART bootloader on anv32_soc_top (default 32 KiB BRAM, HAS_BOOTLOADER), run
// by tools/run_boot_test.py. The BRAM starts with boot_app_a merged with the
// bootloader, as `make fpga` builds it. The testbench plays the host
// (tools/uart_load.py) on the UART pins and checks:
//   1. power-on runs the program at 0 at once (LED = 3), and its writes to
//      the bootloader were dropped
//   2. the boot trigger resets into the bootloader, which says hello
//   3. a bad CRC gets 'E', a bad length gets 'S'
//   4. a good image (boot_app_b) gets 'K' and runs (LED = 2)
//
// Plusargs:
//   +boot_image=<base>  merged image, <base>_lane[0-3].hex
//   +app=<file>         word hex of the image to send
module tb_soc_boot #(
    parameter int unsigned CORE_TYPE = 2
);
    localparam int unsigned CLK_FREQ  = 27_000_000;
    localparam int unsigned BAUD      = 115_200;
    localparam int unsigned BOOT_WORD = 32'h7C00 / 4;

    logic clk_i = 1'b0;
    logic rst_n_i = 1'b0;
    logic rx = 1'b1;            // host -> board
    logic tx;                   // board -> host
    logic [3:0] debug_leds;

    tri1 i2c_sda_io;
    tri1 i2c_scl_io;

    always #5 clk_i = ~clk_i;

    anv32_soc_top #(
        .CORE_TYPE(CORE_TYPE),
        .BRAM_ADDR_W(13),
        .POR_CYCLES(4),
        .INIT_FILE(""),
        .CLK_FREQ(CLK_FREQ),
        .HAS_NN(1'b0),
        .HAS_BOOTLOADER(1'b1)
    ) dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .gpio_irq_i(1'b0),
        .uart_rx_i(rx),
        .i2c_sda_io(i2c_sda_io),
        .i2c_scl_io(i2c_scl_io),
        .uart_tx_o(tx),
        .debug_leds(debug_leds)
    );

    int unsigned cycles = 0;
    always @(posedge clk_i) cycles++;

    // ---- Host side of the UART ---------------------------------------------
    // Clock cycles per bit, rounded; the SoC's fractional baud generators are
    // within 0.2 % of this.
    localparam int unsigned BIT_CYCLES = (CLK_FREQ + BAUD / 2) / BAUD;

    task automatic send_byte(input logic [7:0] b);
        rx = 1'b0;
        repeat (BIT_CYCLES) @(posedge clk_i);
        for (int i = 0; i < 8; i++) begin
            rx = b[i];
            repeat (BIT_CYCLES) @(posedge clk_i);
        end
        rx = 1'b1;
        repeat (BIT_CYCLES) @(posedge clk_i);
    endtask

    task automatic send_word(input logic [31:0] w);
        for (int i = 0; i < 4; i++) send_byte(w[8*i +: 8]);
    endtask

    // Board -> host bytes, collected by a free-running receiver
    logic [7:0] rx_fifo[$];

    initial begin
        logic [7:0] b;
        forever begin
            @(negedge tx);
            repeat (BIT_CYCLES + BIT_CYCLES / 2) @(posedge clk_i);
            for (int i = 0; i < 8; i++) begin
                b[i] = tx;
                repeat (BIT_CYCLES) @(posedge clk_i);
            end
            rx_fifo.push_back(b);
        end
    end

    task automatic expect_byte(input logic [7:0] want, input int unsigned code);
        int unsigned waited = 0;
        while (rx_fifo.size() == 0) begin
            @(posedge clk_i);
            waited++;
            if (waited > 20 * 10 * BIT_CYCLES) fail(code, "no reply");
        end
        if (rx_fifo[0] != want) begin
            $display("got 0x%02h, want 0x%02h", rx_fifo[0], want);
            fail(code, "wrong reply");
        end
        void'(rx_fifo.pop_front());
    endtask

    task automatic fail(input int unsigned code, input string why);
        $display("boot test: %s", why);
        $display("TEST_RESULT status=FAIL code=%0d cycles=%0d", code, cycles);
        $finish;
    endtask

    function automatic logic [31:0] crc32(input logic [31:0] words[$]);
        logic [31:0] crc = '1;
        foreach (words[i]) begin
            for (int k = 0; k < 4; k++) begin
                crc ^= 32'(words[i][8*k +: 8]);
                for (int j = 0; j < 8; j++)
                    crc = crc[0] ? (crc >> 1) ^ 32'hEDB88320 : crc >> 1;
            end
        end
        return ~crc;
    endfunction

    task automatic wait_led(input logic [3:0] value, input int unsigned limit,
                            input int unsigned code);
        int unsigned waited = 0;
        while (dut.led_reg[3:0] != value) begin
            @(posedge clk_i);
            waited++;
            if (waited > limit) fail(code, "LED timeout");
        end
    endtask

    initial begin
        string boot_image, app_file;
        logic [31:0] app[$];
        logic [31:0] word;
        int fd;
        logic [31:0] boot_word0, boot_word64;
        logic [31:0] crc;
        string hello = "anv32 boot\r\n";

        if (!$value$plusargs("boot_image=%s", boot_image)) $fatal(1, "missing +boot_image");
        if (!$value$plusargs("app=%s", app_file)) $fatal(1, "missing +app");
        $readmemh({boot_image, "_lane0.hex"}, dut.ram.lane[0].mem);
        $readmemh({boot_image, "_lane1.hex"}, dut.ram.lane[1].mem);
        $readmemh({boot_image, "_lane2.hex"}, dut.ram.lane[2].mem);
        $readmemh({boot_image, "_lane3.hex"}, dut.ram.lane[3].mem);
        fd = $fopen(app_file, "r");
        if (fd == 0) $fatal(1, "cannot open %s", app_file);
        while ($fscanf(fd, "%h", word) == 1) app.push_back(word);
        $fclose(fd);
        crc = crc32(app);

        boot_word0  = {dut.ram.lane[3].mem[BOOT_WORD], dut.ram.lane[2].mem[BOOT_WORD],
                       dut.ram.lane[1].mem[BOOT_WORD], dut.ram.lane[0].mem[BOOT_WORD]};
        boot_word64 = {dut.ram.lane[3].mem[BOOT_WORD + 64], dut.ram.lane[2].mem[BOOT_WORD + 64],
                       dut.ram.lane[1].mem[BOOT_WORD + 64], dut.ram.lane[0].mem[BOOT_WORD + 64]};

        repeat (5) @(posedge clk_i);
        rst_n_i = 1'b1;

        // 1. Power-on: straight to the program, no wait for the host
        wait_led(4'h3, 200, 1);
        if ({dut.ram.lane[3].mem[BOOT_WORD], dut.ram.lane[2].mem[BOOT_WORD],
             dut.ram.lane[1].mem[BOOT_WORD], dut.ram.lane[0].mem[BOOT_WORD]} != boot_word0 ||
            {dut.ram.lane[3].mem[BOOT_WORD + 64], dut.ram.lane[2].mem[BOOT_WORD + 64],
             dut.ram.lane[1].mem[BOOT_WORD + 64], dut.ram.lane[0].mem[BOOT_WORD + 64]} != boot_word64)
            fail(2, "a program store reached the bootloader");
        if (rx_fifo.size() != 0) fail(3, "bootloader talked on a power-on reset");

        // 2. Boot trigger, after two near misses: a wrong byte, and a restart
        //    of the sequence in the middle of it
        send_byte(8'h1B); send_byte("A"); send_byte("N"); send_byte(8'h00);
        send_byte(8'h1B); send_byte("A");
        send_byte(8'h1B); send_byte("A"); send_byte("N"); send_byte("V");
        send_byte("3");   send_byte("2"); send_byte("B"); send_byte("L");
        for (int i = 0; i < hello.len(); i++) expect_byte(hello[i], 10 + i);
        if (dut.led_reg[3:0] != 4'h0) fail(4, "trigger did not reset the SoC");

        // 3. Bad CRC, then a length past the bootloader
        send_byte("L"); send_word(32'(app.size() * 4)); send_word(crc ^ 32'h1);
        foreach (app[i]) send_word(app[i]);
        expect_byte("E", 30);
        send_byte("L"); send_word(32'h7C04); send_word(crc);
        expect_byte("S", 31);

        // 4. The real image
        send_byte("L"); send_word(32'(app.size() * 4)); send_word(crc);
        foreach (app[i]) send_word(app[i]);
        expect_byte("K", 32);
        wait_led(4'h2, 2000, 33);

        $display("TEST_RESULT status=PASS code=1 cycles=%0d", cycles);
        $finish;
    end
endmodule
