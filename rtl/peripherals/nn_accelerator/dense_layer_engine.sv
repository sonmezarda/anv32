module dense_layer_engine (
    input  logic               clk_i,
    input  logic               rst_i,

    // Layer control
    input  logic               start_i,
    input  logic [31:0]        input_base_i,
    input  logic [31:0]        weight_base_i,
    input  logic [31:0]        bias_base_i,
    input  logic [31:0]        output_base_i,
    input  logic [15:0]        input_length_words_i,
    input  logic [15:0]        output_count_i,
    input  logic               relu_enable_i,

    output logic               busy_o,
    output logic               done_o,
    output logic               error_o,

    // Read request channel
    output logic               mem_req_valid_o,
    input  logic               mem_req_ready_i,
    output logic [31:0]        mem_req_addr_o,

    // Read response channel
    input  logic               mem_rsp_valid_i,
    output logic               mem_rsp_ready_o,
    input  logic [31:0]        mem_rsp_rdata_i,
    input  logic               mem_rsp_error_i,

    // Write request channel
    output logic               mem_wr_valid_o,
    input  logic               mem_wr_ready_i,
    output logic [31:0]        mem_wr_addr_o,
    output logic [31:0]        mem_wr_wdata_o,
    output logic [3:0]         mem_wr_strb_o
);

    typedef enum logic [3:0] {
        ST_IDLE,
        ST_START_DOT,
        ST_WAIT_DOT,
        ST_REQ_BIAS,
        ST_WAIT_BIAS,
        ST_WRITE_OUTPUT,
        ST_NEXT_OUTPUT,
        ST_DONE,
        ST_ERROR
    } state_t;

    state_t state_q;

    logic [31:0] input_base_q;
    logic [31:0] current_weight_base_q;
    logic [31:0] current_bias_addr_q;
    logic [31:0] current_output_addr_q;
    logic [31:0] weight_stride_bytes_q;

    logic [15:0] input_length_words_q;
    logic [15:0] output_count_q;
    logic [15:0] output_index_q;
    logic        relu_enable_q;

    logic signed [31:0] dot_result_q;
    logic signed [31:0] bias_q;
    logic signed [31:0] biased_result;
    logic signed [31:0] activated_result;

    logic dot_start;
    logic dot_busy;
    logic dot_done;
    logic dot_error;
    logic signed [31:0] dot_result;

    logic        dot_mem_req_valid;
    logic        dot_mem_req_ready;
    logic [31:0] dot_mem_req_addr;

    logic        dot_mem_rsp_valid;
    logic        dot_mem_rsp_ready;
    logic [31:0] dot_mem_rsp_rdata;
    logic        dot_mem_rsp_error;

    logic dot_read_active;
    logic bias_req_valid;
    logic bias_req_fire;
    logic bias_rsp_fire;
    logic write_fire;
    logic last_output;

    assign dot_read_active =
        (state_q == ST_START_DOT) || (state_q == ST_WAIT_DOT);

    assign bias_req_valid =
        state_q == ST_REQ_BIAS;

    assign bias_req_fire =
        bias_req_valid && mem_req_ready_i;

    assign bias_rsp_fire =
        mem_rsp_valid_i && mem_rsp_ready_o;

    assign write_fire =
        mem_wr_valid_o && mem_wr_ready_i;

    assign last_output =
        output_index_q == (output_count_q - 16'd1);

    assign dot_start =
        state_q == ST_START_DOT;

    assign busy_o =
        ((state_q != ST_IDLE) && (state_q != ST_DONE)) || dot_busy;

    assign done_o =
        state_q == ST_DONE;

    assign error_o =
        state_q == ST_ERROR;

    assign biased_result =
        dot_result_q + bias_q;

    assign activated_result =
        (relu_enable_q && biased_result[31]) ? 32'sd0 : biased_result;

    memory_dot_product_stream dot_engine (
        .clk_i              (clk_i),
        .rst_i              (rst_i),

        .start_i            (dot_start),
        .activation_base_i  (input_base_q),
        .weight_base_i      (current_weight_base_q),
        .length_words_i     (input_length_words_q),

        .busy_o             (dot_busy),
        .done_o             (dot_done),
        .error_o            (dot_error),
        .result_o           (dot_result),

        .mem_req_valid_o    (dot_mem_req_valid),
        .mem_req_ready_i    (dot_mem_req_ready),
        .mem_req_addr_o     (dot_mem_req_addr),

        .mem_rsp_valid_i    (dot_mem_rsp_valid),
        .mem_rsp_ready_o    (dot_mem_rsp_ready),
        .mem_rsp_rdata_i    (dot_mem_rsp_rdata),
        .mem_rsp_error_i    (dot_mem_rsp_error)
    );

    assign dot_mem_req_ready =
        dot_read_active && mem_req_ready_i;

    assign dot_mem_rsp_valid =
        dot_read_active && mem_rsp_valid_i;

    assign dot_mem_rsp_rdata =
        mem_rsp_rdata_i;

    assign dot_mem_rsp_error =
        mem_rsp_error_i;

    always_comb begin
        mem_req_valid_o = 1'b0;
        mem_req_addr_o  = 32'b0;

        if (dot_read_active) begin
            mem_req_valid_o = dot_mem_req_valid;
            mem_req_addr_o  = dot_mem_req_addr;
        end else if (bias_req_valid) begin
            mem_req_valid_o = 1'b1;
            mem_req_addr_o  = current_bias_addr_q;
        end
    end

    always_comb begin
        mem_rsp_ready_o = 1'b0;

        if (dot_read_active) begin
            mem_rsp_ready_o = dot_mem_rsp_ready;
        end else begin
            case (state_q)
                ST_REQ_BIAS: begin
                    mem_rsp_ready_o = bias_req_fire;
                end

                ST_WAIT_BIAS: begin
                    mem_rsp_ready_o = 1'b1;
                end

                default: begin
                    mem_rsp_ready_o = 1'b0;
                end
            endcase
        end
    end

    always_comb begin
        mem_wr_valid_o = 1'b0;
        mem_wr_addr_o  = 32'b0;
        mem_wr_wdata_o = 32'b0;
        mem_wr_strb_o  = 4'b0000;

        if (state_q == ST_WRITE_OUTPUT) begin
            mem_wr_valid_o = 1'b1;
            mem_wr_addr_o  = current_output_addr_q;
            mem_wr_wdata_o = activated_result;
            mem_wr_strb_o  = 4'b1111;
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q               <= ST_IDLE;
            input_base_q          <= 32'b0;
            current_weight_base_q <= 32'b0;
            current_bias_addr_q   <= 32'b0;
            current_output_addr_q <= 32'b0;
            weight_stride_bytes_q <= 32'b0;
            input_length_words_q  <= 16'd0;
            output_count_q        <= 16'd0;
            output_index_q        <= 16'd0;
            relu_enable_q         <= 1'b0;
            dot_result_q          <= 32'sd0;
            bias_q                <= 32'sd0;
        end else begin
            case (state_q)
                ST_IDLE: begin
                    if (start_i) begin
                        input_base_q          <= input_base_i;
                        current_weight_base_q <= weight_base_i;
                        current_bias_addr_q   <= bias_base_i;
                        current_output_addr_q <= output_base_i;
                        weight_stride_bytes_q <= {14'b0, input_length_words_i, 2'b00};
                        input_length_words_q  <= input_length_words_i;
                        output_count_q        <= output_count_i;
                        output_index_q        <= 16'd0;
                        relu_enable_q         <= relu_enable_i;
                        dot_result_q          <= 32'sd0;
                        bias_q                <= 32'sd0;

                        if (output_count_i == 16'd0) begin
                            state_q <= ST_DONE;
                        end else begin
                            state_q <= ST_START_DOT;
                        end
                    end
                end

                ST_START_DOT: begin
                    state_q <= ST_WAIT_DOT;
                end

                ST_WAIT_DOT: begin
                    if (dot_error) begin
                        state_q <= ST_ERROR;
                    end else if (dot_done) begin
                        dot_result_q <= dot_result;
                        state_q      <= ST_REQ_BIAS;
                    end
                end

                ST_REQ_BIAS: begin
                    if (bias_req_fire) begin
                        if (bias_rsp_fire) begin
                            if (mem_rsp_error_i) begin
                                state_q <= ST_ERROR;
                            end else begin
                                bias_q  <= $signed(mem_rsp_rdata_i);
                                state_q <= ST_WRITE_OUTPUT;
                            end
                        end else begin
                            state_q <= ST_WAIT_BIAS;
                        end
                    end
                end

                ST_WAIT_BIAS: begin
                    if (bias_rsp_fire) begin
                        if (mem_rsp_error_i) begin
                            state_q <= ST_ERROR;
                        end else begin
                            bias_q  <= $signed(mem_rsp_rdata_i);
                            state_q <= ST_WRITE_OUTPUT;
                        end
                    end
                end

                ST_WRITE_OUTPUT: begin
                    if (write_fire) begin
                        if (last_output) begin
                            state_q <= ST_DONE;
                        end else begin
                            state_q <= ST_NEXT_OUTPUT;
                        end
                    end
                end

                ST_NEXT_OUTPUT: begin
                    output_index_q        <= output_index_q + 16'd1;
                    current_weight_base_q <= current_weight_base_q + weight_stride_bytes_q;
                    current_bias_addr_q   <= current_bias_addr_q + 32'd4;
                    current_output_addr_q <= current_output_addr_q + 32'd4;
                    dot_result_q          <= 32'sd0;
                    bias_q                <= 32'sd0;
                    state_q               <= ST_START_DOT;
                end

                ST_DONE: begin
                    state_q <= ST_IDLE;
                end

                ST_ERROR: begin
                    state_q <= ST_ERROR;
                end

                default: begin
                    state_q <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
