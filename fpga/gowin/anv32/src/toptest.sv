module toptest(
    input  logic clk_i,
    output logic led_o
);

    localparam int ADDR_W = 10;

    logic [31:0] counter = 32'd0;

    logic [ADDR_W-1:0] addr_a;
    logic [ADDR_W-1:0] addr_b;

    logic [31:0] wdata_a;
    logic [31:0] wdata_b;

    logic we_a;
    logic we_b;

    logic [31:0] rdata_a;
    logic [31:0] rdata_b;

    always_ff @(posedge clk_i) begin
        counter <= counter + 32'd1;
    end

    assign addr_a  = counter[ADDR_W-1:0];
    assign addr_b  = counter[ADDR_W+7:8];

    assign wdata_a = counter;
    assign wdata_b = ~counter;

    // İki port da arada bir yazsın.
    // Aynı anda aynı adrese yazma durumundan kaçınmak için adresleri farklı seçtik.
    assign we_a = counter[8];
    assign we_b = counter[9];

    bram_tdp #(
        .ADDR_W(ADDR_W),
        .INIT_FILE("")
    ) u_bram (
        .clk     (clk_i),

        .addr_a  (addr_a),
        .wdata_a (wdata_a),
        .we_a    (we_a),
        .rdata_a (rdata_a),

        .addr_b  (addr_b),
        .wdata_b (wdata_b),
        .we_b    (we_b),
        .rdata_b (rdata_b)
    );

    always_ff @(posedge clk_i) begin
        led_o <= ^(rdata_a ^ rdata_b);
    end

endmodule