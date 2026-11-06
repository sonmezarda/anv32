// Core-only FPGA evaluation top, for Fmax and utilization comparisons
// between cores (tools/fpga_eval.py). It wraps any corebench_core adapter
// (sim/corebench/adapters) the way the corebench testbench does: one 8 KiB
// true dual-port BRAM (port B fetch, port A data), a 4-bit LED register on
// stores with addr[31] set, and one synchronized external interrupt. There
// is no bus fabric and no peripherals, so the timing is the core's own.
module core_eval_top #(
    parameter ADDR_W    = 11,   // words: 2^11 * 4 = 8 KiB
    parameter INIT_FILE = ""
)(
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic       irq_i,
    output logic [3:0] led_o
);
    logic [1:0] rst_sync;
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) rst_sync <= '0;
        else          rst_sync <= {rst_sync[0], 1'b1};
    end
    wire rst_n = rst_sync[1];

    logic [1:0] irq_sync;
    always_ff @(posedge clk_i) irq_sync <= {irq_sync[0], irq_i};

    logic [31:0] instr_addr, instr_rdata;
    logic        data_req, data_we;
    logic [ 3:0] data_be;
    logic [31:0] data_addr, data_wdata, data_rdata, bram_rdata;

    corebench_core u_core (
        .clk_i        (clk_i),
        .rst_ni       (rst_n),
        .irq_i        (irq_sync[1]),
        .instr_req_o  (),
        .instr_addr_o (instr_addr),
        .instr_rdata_i(instr_rdata),
        .data_req_o   (data_req),
        .data_we_o    (data_we),
        .data_be_o    (data_be),
        .data_addr_o  (data_addr),
        .data_wdata_o (data_wdata),
        .data_rdata_i (data_rdata),
        .retire_o     ()
    );

    wire data_io = data_addr[31];

    anv32_bram_tdp #(
        .ADDR_W   (ADDR_W),
        .INIT_FILE(INIT_FILE)
    ) u_mem (
        .clk    (clk_i),
        .addr_a (data_addr[ADDR_W+1:2]),
        .wdata_a(data_wdata),
        .we_a   ((data_req && data_we && !data_io) ? data_be : 4'b0),
        .rdata_a(bram_rdata),
        .addr_b (instr_addr[ADDR_W+1:2]),
        .wdata_b(32'h0),
        .we_b   (4'b0),
        .rdata_b(instr_rdata)
    );

    logic data_io_q;
    always_ff @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            data_io_q <= 1'b0;
            led_o     <= '0;
        end else begin
            data_io_q <= data_io;
            if (data_req && data_we && data_io && data_be[0])
                led_o <= data_wdata[3:0];
        end
    end

    assign data_rdata = data_io_q ? {28'h0, led_o} : bram_rdata;
endmodule
