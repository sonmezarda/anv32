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
    // Port B (fetch: tie we_b to '0 for read-only use)
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

            initial begin
                if (INIT_FILE != "") begin
                    $readmemh($sformatf("%s_lane%0d.hex", INIT_FILE, i), mem);
                end
            end

            // Port A: no-change write mode (WRITE_MODE = 2'b00), supported by Gowin DPB
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
