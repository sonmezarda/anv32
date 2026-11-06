`timescale 1ns/1ps

// Core-agnostic benchmark testbench. It drives one corebench_core adapter
// (sim/corebench/adapters) with a flat RAM that has BRAM timing on both
// ports, plus a sim-control MMIO block for console output, exit, traps and
// region-of-interest (ROI) markers. Everything is configured at run time,
// so one Verilator build per core runs every program:
//
//   +image=<file>      word hex image loaded at address 0 (required)
//   +max_cycles=<n>    timeout (default 100000000)
//   +console=<file>    program output file (default: stdout)
//
// The run ends with one line:
//   COREBENCH_RESULT status=<exit|trap|timeout> exit_code=... cycles=...
//                    instret=... roi_cycles=... roi_instret=... roi_count=...
//                    trap_cause=... trap_epc=...
//
// Data accesses outside RAM and the control block stop the run with an
// error. Fetches outside RAM read 0 instead, since prefetching cores may
// fetch past the end of a program without executing it.
//
// With COREBENCH_PROBE defined, a core-specific corebench_probe module
// (sim/corebench/probes) is instantiated and adds a COREBENCH_PROBE line.
//
// The register map is mirrored in sw/corebench/common/corebench.h.
module tb_corebench #(
    parameter int unsigned RAM_BYTES = 64 * 1024
);
    localparam int unsigned RAM_WORDS = RAM_BYTES / 4;
    localparam int unsigned RAM_AW    = $clog2(RAM_WORDS);

    localparam logic [31:0] CTRL_BASE = 32'h2000_0000;
    localparam logic [31:0] CTRL_MASK = 32'hFFFF_FF00;

    localparam logic [7:0] CTRL_EXIT       = 8'h00;  // W: end run, exit code
    localparam logic [7:0] CTRL_PUTC       = 8'h04;  // W: console byte
    localparam logic [7:0] CTRL_ROI        = 8'h08;  // W: !=0 opens, 0 closes the ROI
    localparam logic [7:0] CTRL_TRAP_CAUSE = 8'h0C;  // W: mcause, ends run as a trap
    localparam logic [7:0] CTRL_CYCLE      = 8'h10;  // R: cycle counter [31:0]
    localparam logic [7:0] CTRL_CYCLEH     = 8'h14;  // R: cycle counter [63:32]
    localparam logic [7:0] CTRL_INSTRET    = 8'h18;  // R: retired instructions [31:0]
    localparam logic [7:0] CTRL_INSTRETH   = 8'h1C;  // R: retired instructions [63:32]
    localparam logic [7:0] CTRL_TRAP_EPC   = 8'h20;  // W: mepc, written before TRAP_CAUSE

    logic clk   = 1'b0;
    logic rst_n = 1'b0;

    always #5 clk = ~clk;

    logic        instr_req;
    logic [31:0] instr_addr;
    logic [31:0] instr_rdata;
    logic        data_req;
    logic        data_we;
    logic [ 3:0] data_be;
    logic [31:0] data_addr;
    logic [31:0] data_wdata;
    logic [31:0] data_rdata;
    logic        retire;

    corebench_core dut (
        .clk_i        (clk),
        .rst_ni       (rst_n),
        .irq_i        (1'b0),
        .instr_req_o  (instr_req),
        .instr_addr_o (instr_addr),
        .instr_rdata_i(instr_rdata),
        .data_req_o   (data_req),
        .data_we_o    (data_we),
        .data_be_o    (data_be),
        .data_addr_o  (data_addr),
        .data_wdata_o (data_wdata),
        .data_rdata_i (data_rdata),
        .retire_o     (retire)
    );

`ifdef COREBENCH_PROBE
    corebench_probe probe ();
`endif

    // ---- Memory: both ports read every cycle like the FPGA BRAM ----------
    logic [31:0] ram [RAM_WORDS];

    function automatic bit in_ram(input logic [31:0] addr);
        return addr < RAM_BYTES;
    endfunction

    function automatic bit in_ctrl(input logic [31:0] addr);
        return (addr & CTRL_MASK) == CTRL_BASE;
    endfunction

    // ---- Counters and run state -------------------------------------------
    longint unsigned cycles      = 0;
    longint unsigned instret     = 0;
    longint unsigned roi_cycles  = 0;
    longint unsigned roi_instret = 0;
    int unsigned     roi_count   = 0;
    // The whole run is the ROI until the program first writes the ROI
    // register; that write restarts the ROI counts (and the probe's).
    bit              roi_open    = 1'b1;
    bit              roi_marked  = 1'b0;
    event            roi_restart;
    longint unsigned max_cycles  = 100_000_000;
    logic [31:0]     exit_code   = '0;
    logic [31:0]     trap_cause  = '0;
    logic [31:0]     trap_epc    = '0;
    string           status      = "";
    int              console_fd  = 32'h8000_0001;  // stdout

    function automatic logic [31:0] ctrl_read(input logic [7:0] offset);
        case (offset)
            CTRL_CYCLE:    return cycles[31:0];
            CTRL_CYCLEH:   return cycles[63:32];
            CTRL_INSTRET:  return instret[31:0];
            CTRL_INSTRETH: return instret[63:32];
            default:       return 32'h0;
        endcase
    endfunction

    always @(posedge clk) begin
        if (in_ram(instr_addr)) instr_rdata <= ram[instr_addr[RAM_AW+1:2]];
        else                    instr_rdata <= 32'h0;
    end

    // Data port, counters and the control block share one process so a ROI
    // marker and the counters it gates update in a fixed order.
    always @(posedge clk) begin
        if (rst_n) begin
            cycles  <= cycles + 1;
            instret <= instret + {63'd0, retire};
            if (roi_open) begin
                roi_cycles  <= roi_cycles + 1;
                roi_instret <= roi_instret + {63'd0, retire};
            end
        end

        if (data_req && data_we) begin
            if (in_ram(data_addr)) begin
                for (int i = 0; i < 4; i++)
                    if (data_be[i]) ram[data_addr[RAM_AW+1:2]][i*8 +: 8] <= data_wdata[i*8 +: 8];
            end else if (in_ctrl(data_addr)) begin
                ctrl_write(data_addr[7:0], data_wdata);
            end else begin
                $fatal(1, "corebench: store to unmapped address 0x%08h", data_addr);
            end
        end else begin
            if (in_ram(data_addr))
                data_rdata <= ram[data_addr[RAM_AW+1:2]];
            else if (in_ctrl(data_addr))
                data_rdata <= ctrl_read(data_addr[7:0]);
            else if (data_req)
                $fatal(1, "corebench: load from unmapped address 0x%08h", data_addr);
        end
    end

    task automatic ctrl_write(input logic [7:0] offset, input logic [31:0] wdata);
        case (offset)
            CTRL_EXIT: begin
                exit_code = wdata;
                status    = "exit";
            end
            CTRL_PUTC:
                $fwrite(console_fd, "%c", wdata[7:0]);
            CTRL_ROI: begin
                if (!roi_marked) begin
                    roi_marked   = 1'b1;
                    roi_open     = 1'b0;
                    roi_cycles  <= 0;
                    roi_instret <= 0;
                    -> roi_restart;
                end
                if (wdata != 0 && !roi_open) roi_count++;
                roi_open = (wdata != 0);
            end
            CTRL_TRAP_EPC:
                trap_epc = wdata;
            CTRL_TRAP_CAUSE: begin
                trap_cause = wdata;
                status     = "trap";
            end
            default:
                $fatal(1, "corebench: store to unknown control register 0x%02h", offset);
        endcase
    endtask

    // ---- Run control --------------------------------------------------------
    initial begin
        string image;
        string console_path;

        if (!$value$plusargs("image=%s", image))
            $fatal(1, "corebench: +image=<word hex> is required");
        void'($value$plusargs("max_cycles=%d", max_cycles));
        if ($value$plusargs("console=%s", console_path)) begin
            console_fd = $fopen(console_path, "w");
            if (console_fd == 0) $fatal(1, "corebench: cannot open %s", console_path);
        end

        foreach (ram[i]) ram[i] = 32'h0;
        $readmemh(image, ram);

        repeat (4) @(posedge clk);
        @(negedge clk) rst_n = 1'b1;

        while (status == "" && cycles < max_cycles) @(posedge clk);
        if (status == "") status = "timeout";
        #1;

        if (console_fd != 32'h8000_0001) $fclose(console_fd);
        $display("COREBENCH_RESULT status=%s exit_code=0x%08h cycles=%0d instret=%0d roi_cycles=%0d roi_instret=%0d roi_count=%0d trap_cause=0x%08h trap_epc=0x%08h",
                 status, exit_code, cycles, instret, roi_cycles, roi_instret,
                 roi_count, trap_cause, trap_epc);
        $finish;
    end
endmodule
