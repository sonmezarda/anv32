module anv32_bram_tdp #(
    parameter ADDR_W    = 10,
    parameter INIT_FILE = ""
)(
    input  logic              clk,
    // Port A (data: R/W + byte enable)
    input  logic [ADDR_W-1:0] addr_a,
    input  logic [31:0]       wdata_a,
    input  logic [3:0]        we_a,
    output logic [31:0]       rdata_a,
    // Port B (fetch: read-only kullanırsan we_b='0)
    input  logic [ADDR_W-1:0] addr_b,
    input  logic [31:0]       wdata_b,
    input  logic [3:0]        we_b,
    output logic [31:0]       rdata_b
);
    localparam int DEPTH = (1 << ADDR_W);

    genvar i;
    generate
        for (i = 0; i < 4; i++) begin : lane
            logic [7:0] mem [0:DEPTH-1];

            // Port A — no-change (WRITE_MODE = 2'b00): Gowin DPB destekler
            always_ff @(posedge clk) begin
                if (we_a[i]) mem[addr_a]       <= wdata_a[i*8 +: 8];
                else         rdata_a[i*8 +: 8] <= mem[addr_a];
            end
            // Port B
            always_ff @(posedge clk) begin
                if (we_b[i]) mem[addr_b]       <= wdata_b[i*8 +: 8];
                else         rdata_b[i*8 +: 8] <= mem[addr_b];
            end
        end
    endgenerate
endmodule