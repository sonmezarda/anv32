module dot_product_stream (
    input  logic               clk_i,
    input  logic               rst_i,

    input  logic               start_i,
    input  logic [15:0]        length_words_i,

    input  logic               data_valid_i,
    output logic               data_ready_o,
    input  logic signed [31:0] activations_i,
    input  logic signed [31:0] weights_i,

    output logic               busy_o,
    output logic               done_o,
    output logic signed [31:0] result_o
);

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_CLEAR,
        ST_COMPUTE,
        ST_CAPTURE,
        ST_DONE
    } state_t;

    state_t state_q;

    logic [15:0] length_words_q;
    logic [15:0] words_seen_q;

    logic               data_fire;
    logic               mac_clear;
    logic               mac_valid;
    logic signed [31:0] mac_accumulator;

    logic signed [31:0] result_q;

    assign result_o = result_q;

    assign busy_o = (state_q != ST_IDLE) && (state_q != ST_DONE);
    assign done_o = state_q == ST_DONE;

    assign data_ready_o =
        (state_q == ST_COMPUTE) && (length_words_q != 16'd0);

    assign data_fire =
        data_valid_i && data_ready_o;

    assign mac_clear =
        state_q == ST_CLEAR;

    assign mac_valid =
        data_fire;

    int8_dot4 mac_unit (
        .clk_i          (clk_i),
        .rst_i          (rst_i),
        .clear_i        (mac_clear),
        .valid_i        (mac_valid),
        .activations_i  (activations_i),
        .weights_i      (weights_i),
        .accumulator_o  (mac_accumulator)
    );

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q        <= ST_IDLE;
            length_words_q <= 16'd0;
            words_seen_q   <= 16'd0;
            result_q       <= 32'sd0;
        end else begin
            case (state_q)
                ST_IDLE: begin
                    if (start_i) begin
                        length_words_q <= length_words_i;
                        words_seen_q   <= 16'd0;
                        result_q       <= 32'sd0;
                        state_q        <= ST_CLEAR;
                    end
                end

                ST_CLEAR: begin
                    if (length_words_q == 16'd0) begin
                        state_q <= ST_CAPTURE;
                    end else begin
                        state_q <= ST_COMPUTE;
                    end
                end

                ST_COMPUTE: begin
                    if (data_fire) begin
                        if (words_seen_q == (length_words_q - 16'd1)) begin
                            state_q <= ST_CAPTURE;
                        end else begin
                            words_seen_q <= words_seen_q + 16'd1;
                        end
                    end
                end

                ST_CAPTURE: begin
                    result_q <= mac_accumulator;
                    state_q  <= ST_DONE;
                end

                ST_DONE: begin
                    state_q <= ST_IDLE;
                end

                default: begin
                    state_q        <= ST_IDLE;
                    length_words_q <= 16'd0;
                    words_seen_q   <= 16'd0;
                    result_q       <= 32'sd0;
                end
            endcase
        end
    end

endmodule
