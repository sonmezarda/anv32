module uart_baud_rate #(
    parameter integer CLK_FREQ = 27_000_000
)(
    input  logic        clk_i,
    input  logic        rst_i,
    input  logic [31:0] baud_rate_i,

    output logic        baud_tick_o,
    output logic        baud_x16_tick_o
);
    logic [31:0] baud_rate_x16;
    logic [31:0] baud_accum;
    logic [31:0] baud_x16_accum;

    assign baud_rate_x16 = baud_rate_i << 4;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            baud_accum     <= 32'd0;
            baud_x16_accum <= 32'd0;
            baud_tick_o    <= 1'b0;
            baud_x16_tick_o <= 1'b0;
        end else if (baud_rate_i == 32'd0) begin
            baud_accum     <= 32'd0;
            baud_x16_accum <= 32'd0;
            baud_tick_o    <= 1'b0;
            baud_x16_tick_o <= 1'b0;
        end else begin
            if ((baud_accum + baud_rate_i) >= CLK_FREQ) begin
                baud_accum  <= baud_accum + baud_rate_i - CLK_FREQ;
                baud_tick_o <= 1'b1;
            end else begin
                baud_accum  <= baud_accum + baud_rate_i;
                baud_tick_o <= 1'b0;
            end

            if ((baud_x16_accum + baud_rate_x16) >= CLK_FREQ) begin
                baud_x16_accum  <= baud_x16_accum + baud_rate_x16 - CLK_FREQ;
                baud_x16_tick_o <= 1'b1;
            end else begin
                baud_x16_accum  <= baud_x16_accum + baud_rate_x16;
                baud_x16_tick_o <= 1'b0;
            end
        end
    end

endmodule
