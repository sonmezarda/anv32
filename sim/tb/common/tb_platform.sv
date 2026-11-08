`timescale 1ns/1ps

// Simulation platform for large programs: one core, 32 MiB of RAM at
// 0x8000_0000 (where external RAM sits in the SoC memory map) and a small
// simulation device. Used to run Doom before the real hardware exists.
//
// Simulation device at 0x2000_0000:
//   0x00  EXIT     write: end the simulation with this exit code
//   0x10  PUTC     write: print byte 0 to stdout
//   0x20  PALETTE  write: address of 256 colors, 4 bytes each (b, g, r, unused)
//   0x24  FRAME    write: address of a 320x200 8-bit indexed frame; the
//                  palette and the frame are appended to +frames=<file>
//
// Any other address stops the simulation with an error, which catches stray
// pointers early.
//
// Plusargs:
//   +prog=<file>        word hex image, loaded at 0x8000_0000
//   +max_cycles=<n>     timeout (default 2_000_000_000)
//   +frames=<file>      frame dump file
//   +max_frames=<n>     stop after this many frames (default: no limit)
//   +imem_lat=<n>       without the instruction cache: every fetch waits n
//                       cycles before it is accepted (external memory, no
//                       cache); with it: the first beat of a line fill comes n
//                       cycles after the request, then one beat per cycle
//   +dmem_lat=<n>       every data access to RAM waits n cycles
//   +lat_from_frame=<k> the wait states start once k frames are out, so the
//                       start-up can run at full speed (default 0: from reset)
//   +window=<n>         stop after n instructions have retired with the wait
//                       states on; cycles, CPI and wait cycles are printed
//
// ICACHE_SIZE != 0 puts anv32_icache with these parameters in front of the
// instruction port.
module tb_platform #(
    parameter int unsigned ICACHE_SIZE      = 0,     // bytes; 0 = no instruction cache
    parameter int unsigned ICACHE_LINE      = 32,
    parameter int unsigned ICACHE_MEM_DW    = 64,
    parameter bit          ICACHE_SYNC_TAGS = 1'b0
);
    localparam logic [31:0] RAM_BASE   = 32'h8000_0000;
    localparam int unsigned RAM_ADDR_W = 25;            // 32 MiB
    localparam int unsigned RAM_WORDS  = 1 << (RAM_ADDR_W - 2);
    localparam int unsigned FB_W       = 320;
    localparam int unsigned FB_H       = 200;

    localparam logic [3:0] DEV_REGION  = 4'h2;
    localparam logic [7:0] DEV_EXIT    = 8'h00;
    localparam logic [7:0] DEV_PUTC    = 8'h10;
    localparam logic [7:0] DEV_PALETTE = 8'h20;
    localparam logic [7:0] DEV_FRAME   = 8'h24;

    logic clk = 1'b0;
    logic rst = 1'b1;

    logic [31:0] instr_addr;
    logic [31:0] instr_rdata;
    logic        instr_req;
    logic        instr_ready;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [31:0] mem_rdata;
    logic [3:0]  mem_we;
    logic        mem_valid;
    logic        mem_ready;

    always #5 clk = ~clk;

`ifdef ANV32_BENCH_CORE_ANV32IM1
    anv32im1_top #(.HAS_M(1'b1), .PC_RESET_VALUE(RAM_BASE)) dut (
`elsif ANV32_BENCH_CORE_ANV32IM2
    anv32im2_top #(.HAS_M(1'b1), .PC_RESET_VALUE(RAM_BASE)) dut (
`else
    initial $fatal(1, "Define ANV32_BENCH_CORE_ANV32IM1 or ANV32_BENCH_CORE_ANV32IM2");
    anv32im2_top dut (
`endif
        .clk_i(clk),
        .rst_i(rst),
        .stall_i(1'b0),
        .pc_jmp_en_i(1'b0),
        .pc_jmp_addr_i('0),
        .ext_irq_i(1'b0),
        .timer_irq_i(1'b0),
        .sw_irq_i(1'b0),
        .pc_o(),
        .instr_o(),
        .instr_valid_o(),
        .instr_i(instr_rdata),
        .instr_addr_o(instr_addr),
        .instr_req_o(instr_req),
        .instr_ready_i(instr_ready),
        .mem_rdata_i(mem_rdata),
        .mem_ready_i(mem_ready),
        .mem_wdata_o(mem_wdata),
        .mem_addr_o(mem_addr),
        .mem_valid_o(mem_valid),
        .mem_we(mem_we)
    );

    // ---- Memory ------------------------------------------------------------
    logic [31:0] ram [0:RAM_WORDS-1];
    logic        ram_sel;
    logic        dev_sel;
    logic        instr_fire;
    logic        mem_fire;

    assign ram_sel    = mem_addr[31:RAM_ADDR_W] == RAM_BASE[31:RAM_ADDR_W];
    assign dev_sel    = mem_addr[31:28] == DEV_REGION;
    assign instr_fire = instr_req && instr_ready;
    assign mem_fire   = mem_valid && mem_ready;

    always_ff @(posedge clk) begin
        mem_rdata <= ram_sel ? ram[mem_addr[RAM_ADDR_W-1:2]] : 32'b0;

        if (mem_fire && ram_sel) begin
            for (int i = 0; i < 4; i++) begin
                if (mem_we[i]) ram[mem_addr[RAM_ADDR_W-1:2]][i*8 +: 8] <= mem_wdata[i*8 +: 8];
            end
        end
    end

    function automatic logic [7:0] ram_byte(logic [31:0] addr);
        return ram[addr[RAM_ADDR_W-1:2]][addr[1:0]*8 +: 8];
    endfunction

    // ---- Simulation device -------------------------------------------------
    logic        done = 1'b0;
    logic [31:0] exit_code = '0;
    logic [31:0] palette_addr = '0;
    int          frames_fd = 0;
    int unsigned frame_count = 0;
    int unsigned max_frames = 0;
    longint unsigned cycle = 0;

    // ---- Memory wait states ------------------------------------------------
    // Without a cache, a request waits *_lat cycles and is accepted on the
    // next one, like a fixed-latency memory. Only RAM data accesses wait; the
    // simulation device answers at once.
    int unsigned imem_lat = 0;
    int unsigned dmem_lat = 0;
    int unsigned lat_from_frame = 0;
    int unsigned dpend_cycles = 0;    // cycles the current request has waited
    logic        lat_on;

    assign lat_on    = frame_count >= lat_from_frame;
    assign mem_ready = !(lat_on && mem_valid && ram_sel && dpend_cycles < dmem_lat);

    always_ff @(posedge clk) begin
        if (!mem_valid || mem_fire) dpend_cycles <= 0;
        else                        dpend_cycles <= dpend_cycles + 1;
    end

    // ---- Measurement window ------------------------------------------------
    // Counted while the wait states are on.
    longint unsigned window = 0;
    longint unsigned win_cycles = 0;
    longint unsigned win_instret = 0;
    longint unsigned win_iwait = 0;   // cycles a fetch waited for memory
    longint unsigned win_dwait = 0;   // cycles a load/store waited (pipeline stalled)
    longint unsigned win_fills = 0;   // instruction cache line fills

    // ---- Instruction side --------------------------------------------------
    generate
        if (ICACHE_SIZE == 0) begin : g_no_icache
            int unsigned ipend_cycles = 0;

            assign instr_ready = !(lat_on && instr_req && ipend_cycles < imem_lat);

            always_ff @(posedge clk) begin
                instr_rdata <= ram[instr_addr[RAM_ADDR_W-1:2]];
                if (!instr_req || instr_fire) ipend_cycles <= 0;
                else                          ipend_cycles <= ipend_cycles + 1;
            end
        end else begin : g_icache
            localparam int unsigned BEATS = ICACHE_LINE * 8 / ICACHE_MEM_DW;

            logic                     fill_req_valid;
            logic                     fill_req_ready;
            logic [31:0]              fill_req_addr;
            logic                     fill_rvalid;
            logic [ICACHE_MEM_DW-1:0] fill_rdata;

            anv32_icache #(
                .SIZE_BYTES(ICACHE_SIZE),
                .LINE_BYTES(ICACHE_LINE),
                .MEM_DW    (ICACHE_MEM_DW),
                .SYNC_TAGS (ICACHE_SYNC_TAGS)
            ) icache (
                .clk_i          (clk),
                .rst_i          (rst),
                .invalidate_i   (1'b0),
                .req_valid_i    (instr_req),
                .req_addr_i     (instr_addr),
                .req_ready_o    (instr_ready),
                .rdata_o        (instr_rdata),
                .mem_req_valid_o(fill_req_valid),
                .mem_req_ready_i(fill_req_ready),
                .mem_req_addr_o (fill_req_addr),
                .mem_rvalid_i   (fill_rvalid),
                .mem_rdata_i    (fill_rdata)
            );

            // Burst memory: a line request is taken when no burst is running;
            // the first beat comes imem_lat cycles later, then one per cycle.
            logic        burst_active = 1'b0;
            logic [31:0] burst_addr;
            int unsigned beats_left;
            int unsigned delay;

            assign fill_req_ready = !burst_active;
            assign fill_rvalid    = burst_active && delay == 0;

            always_comb begin
                for (int i = 0; i < ICACHE_MEM_DW / 32; i++)
                    fill_rdata[i*32 +: 32] = ram[burst_addr[RAM_ADDR_W-1:2] + (RAM_ADDR_W-2)'(i)];
            end

            always_ff @(posedge clk) begin
                if (rst) begin
                    burst_active <= 1'b0;
                end else if (!burst_active) begin
                    if (fill_req_valid) begin
                        burst_active <= 1'b1;
                        burst_addr   <= fill_req_addr;
                        beats_left   <= BEATS;
                        delay        <= lat_on ? imem_lat : 0;
                        if (lat_on) win_fills <= win_fills + 1;
                    end
                end else if (delay != 0) begin
                    delay <= delay - 1;
                end else begin
                    burst_addr <= burst_addr + 32'(ICACHE_MEM_DW / 8);
                    beats_left <= beats_left - 1;
                    if (beats_left == 1) burst_active <= 1'b0;
                end
            end
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (!rst && lat_on) begin
            win_cycles  <= win_cycles + 1;
            win_instret <= win_instret + 64'(dut.csr.retire_i);
            win_iwait   <= win_iwait + 64'(instr_req && !instr_ready);
            win_dwait   <= win_dwait + 64'(mem_valid && !mem_ready);
        end
    end

    task automatic dump_frame(logic [31:0] fb_addr);
        $display("[platform] frame %0d at cycle %0d", frame_count, cycle);
        if (frames_fd != 0) begin
            for (int i = 0; i < 256 * 4; i++) $fwrite(frames_fd, "%c", ram_byte(palette_addr + i));
            for (int i = 0; i < FB_W * FB_H; i++) $fwrite(frames_fd, "%c", ram_byte(fb_addr + i));
            $fflush(frames_fd);
        end
        frame_count++;
    endtask

    always_ff @(posedge clk) begin
        if (!rst && mem_fire && !ram_sel) begin
            if (dev_sel && mem_we != 4'b0) begin
                unique case (mem_addr[7:0])
                    DEV_EXIT: begin
                        exit_code <= mem_wdata;
                        done      <= 1'b1;
                    end
                    DEV_PUTC:    $write("%c", mem_wdata[7:0]);
                    DEV_PALETTE: palette_addr <= mem_wdata;
                    DEV_FRAME:   dump_frame(mem_wdata);
                    default: ;
                endcase
            end else begin
                $display("[platform] bad %s at %08x, pc near %08x, cycle %0d",
                         (mem_we != 4'b0) ? "store" : "load", mem_addr, instr_addr, cycle);
                exit_code <= 32'hFFFF_FFFF;
                done      <= 1'b1;
            end
        end
    end

    initial begin
        string prog;
        string frames_file;
        longint unsigned max_cycles;

        if (!$value$plusargs("prog=%s", prog)) $fatal(1, "missing +prog=<word hex file>");
        $readmemh(prog, ram);
        if (!$value$plusargs("max_cycles=%d", max_cycles)) max_cycles = 2_000_000_000;
        if ($value$plusargs("frames=%s", frames_file)) frames_fd = $fopen(frames_file, "wb");

        repeat (3) @(posedge clk);
        rst = 1'b0;

        void'($value$plusargs("max_frames=%d", max_frames));
        void'($value$plusargs("imem_lat=%d", imem_lat));
        void'($value$plusargs("dmem_lat=%d", dmem_lat));
        void'($value$plusargs("lat_from_frame=%d", lat_from_frame));
        void'($value$plusargs("window=%d", window));

        while (!done && cycle < max_cycles && (max_frames == 0 || frame_count < max_frames) &&
               (window == 0 || win_instret < window)) begin
            @(posedge clk);
            cycle++;
        end

        if (frames_fd != 0) $fclose(frames_fd);
        if (win_instret != 0)
            $display("[platform] imem_lat=%0d dmem_lat=%0d: %0d instructions, %0d cycles, CPI %0.3f, fetch wait %0d, load/store wait %0d",
                     imem_lat, dmem_lat, win_instret, win_cycles,
                     real'(win_cycles) / real'(win_instret), win_iwait, win_dwait);
        if (win_instret != 0 && ICACHE_SIZE != 0)
            $display("[platform] icache %0d B, %0d B lines, %0d-bit fills, %s tags: %0d line fills, %0.2f per 1000 instructions",
                     ICACHE_SIZE, ICACHE_LINE, ICACHE_MEM_DW, ICACHE_SYNC_TAGS ? "sync" : "async",
                     win_fills, 1000.0 * real'(win_fills) / real'(win_instret));
        if (window != 0 && win_instret >= window)
            $display("[platform] window done after %0d cycles", cycle);
        else if (max_frames != 0 && frame_count >= max_frames)
            $display("[platform] stopped after %0d frames, %0d cycles", frame_count, cycle);
        else if (!done)
            $display("[platform] timeout after %0d cycles", cycle);
        else
            $display("[platform] exit code %0d after %0d cycles, %0d frames",
                     $signed(exit_code), cycle, frame_count);
        $finish;
    end
endmodule
