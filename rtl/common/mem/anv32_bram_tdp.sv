module anv32_bram_tdp #(
    parameter ADDR_W = 10,
    parameter INIT_FILE = "prog.hex"
)(
    input  logic              clk,

    // Port A
    input  logic [ADDR_W-1:0] addr_a,
    input  logic [31:0]       wdata_a,
    input  logic              we_a,
    output logic [31:0]       rdata_a,

    // Port B
    input  logic [ADDR_W-1:0] addr_b,
    input  logic [31:0]       wdata_b,
    input  logic              we_b,
    output logic [31:0]       rdata_b
);

    logic [31:0] mem [0:(1 << ADDR_W)-1];

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    // Port A: no-change read-during-write
    always_ff @(posedge clk) begin
        if (we_a) begin
            mem[addr_a] <= wdata_a;
        end else begin
            rdata_a <= mem[addr_a];
        end
    end

    // Port B: no-change read-during-write
    always_ff @(posedge clk) begin
        if (we_b) begin
            mem[addr_b] <= wdata_b;
        end else begin
            rdata_b <= mem[addr_b];
        end
    end

endmodule