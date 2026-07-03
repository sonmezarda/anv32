module memory_dot_product_stream (
    input  logic               clk_i,
    input  logic               rst_i,

    // Accelerator control
    input  logic               start_i,
    input  logic [31:0]        activation_base_i,
    input  logic [31:0]        weight_base_i,
    input  logic [15:0]        length_words_i,

    output logic               busy_o,
    output logic               done_o,
    output logic               error_o,
    output logic signed [31:0] result_o,

    // Read request channel
    output logic               mem_req_valid_o,
    input  logic               mem_req_ready_i,
    output logic [31:0]        mem_req_addr_o,

    // Read response channel
    input  logic               mem_rsp_valid_i,
    output logic               mem_rsp_ready_o,
    input  logic [31:0]        mem_rsp_rdata_i,
    input  logic               mem_rsp_error_i
);

    typedef enum logic [3:0] {
        ST_IDLE,
        ST_START_CORE,

        ST_REQ_ACT,
        ST_WAIT_ACT,

        ST_REQ_WEIGHT,
        ST_WAIT_WEIGHT,

        ST_SEND_CORE,
        ST_WAIT_CORE,

        ST_DONE,
        ST_ERROR
    } state_t;

    state_t state_q;

    logic [15:0] word_index_q;
    logic [15:0] length_words_q;

    logic [31:0] activation_base_q;
    logic [31:0] weight_base_q;

    logic signed [31:0] activation_word_q;
    logic signed [31:0] weight_word_q;

    logic signed [31:0] result_q;

    logic               core_start;
    logic               core_data_valid;
    logic               core_data_ready;
    logic               core_data_fire;

    logic               core_busy;
    logic               core_done;
    logic signed [31:0] core_result;

    logic mem_req_fire;
    logic mem_rsp_fire;

    assign mem_req_fire =
        mem_req_valid_o && mem_req_ready_i;

    assign mem_rsp_fire =
        mem_rsp_valid_i && mem_rsp_ready_o;

    assign core_data_fire =
        core_data_valid && core_data_ready;

    assign result_o = result_q;

    always_comb begin
        busy_o  = 1'b0;
        done_o  = 1'b0;
        error_o = 1'b0;

        case (state_q)
            ST_IDLE: begin
                busy_o = core_busy;
            end

            ST_DONE: begin
                done_o = 1'b1;
            end

            ST_ERROR: begin
                error_o = 1'b1;
            end

            default: begin
                busy_o = 1'b1;
            end
        endcase
    end

    assign core_start =
        state_q == ST_START_CORE;

    assign core_data_valid =
        state_q == ST_SEND_CORE;

    dot_product_stream core (
        .clk_i          (clk_i),
        .rst_i          (rst_i),

        .start_i        (core_start),
        .length_words_i (length_words_q),

        .data_valid_i   (core_data_valid),
        .data_ready_o   (core_data_ready),
        .activations_i  (activation_word_q),
        .weights_i      (weight_word_q),

        .busy_o         (core_busy),
        .done_o         (core_done),
        .result_o       (core_result)
    );

    always_comb begin
        mem_req_valid_o = 1'b0;
        mem_req_addr_o  = 32'b0;

        case (state_q)
            ST_REQ_ACT: begin
                mem_req_valid_o = 1'b1;
                mem_req_addr_o  =
                    activation_base_q + {14'b0, word_index_q, 2'b00};
            end

            ST_REQ_WEIGHT: begin
                mem_req_valid_o = 1'b1;
                mem_req_addr_o  =
                    weight_base_q + {14'b0, word_index_q, 2'b00};
            end

            default: begin
                mem_req_valid_o = 1'b0;
                mem_req_addr_o  = 32'b0;
            end
        endcase
    end

    always_comb begin
        mem_rsp_ready_o = 1'b0;

        case (state_q)
            ST_REQ_ACT,
            ST_REQ_WEIGHT: begin
                mem_rsp_ready_o = mem_req_fire;
            end

            ST_WAIT_ACT,
            ST_WAIT_WEIGHT: begin
                mem_rsp_ready_o = 1'b1;
            end

            default: begin
                mem_rsp_ready_o = 1'b0;
            end
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q           <= ST_IDLE;
            word_index_q      <= 16'd0;
            length_words_q    <= 16'd0;

            activation_base_q <= 32'b0;
            weight_base_q     <= 32'b0;

            activation_word_q <= 32'sd0;
            weight_word_q     <= 32'sd0;

            result_q          <= 32'sd0;
        end else begin
            case (state_q)
                ST_IDLE: begin
                    if (start_i) begin
                        activation_base_q <= activation_base_i;
                        weight_base_q     <= weight_base_i;
                        length_words_q    <= length_words_i;

                        word_index_q      <= 16'd0;
                        result_q          <= 32'sd0;

                        state_q           <= ST_START_CORE;
                    end
                end

                ST_START_CORE: begin
                    if (length_words_q == 16'd0) begin
                        state_q <= ST_WAIT_CORE;
                    end else begin
                        state_q <= ST_REQ_ACT;
                    end
                end

                ST_REQ_ACT: begin
                    if (mem_req_fire) begin
                        if (mem_rsp_fire) begin
                            if (mem_rsp_error_i) begin
                                state_q <= ST_ERROR;
                            end else begin
                                activation_word_q <= $signed(mem_rsp_rdata_i);
                                state_q           <= ST_REQ_WEIGHT;
                            end
                        end else begin
                            state_q <= ST_WAIT_ACT;
                        end
                    end
                end

                ST_WAIT_ACT: begin
                    if (mem_rsp_fire) begin
                        if (mem_rsp_error_i) begin
                            state_q <= ST_ERROR;
                        end else begin
                            activation_word_q <= $signed(mem_rsp_rdata_i);
                            state_q           <= ST_REQ_WEIGHT;
                        end
                    end
                end

                ST_REQ_WEIGHT: begin
                    if (mem_req_fire) begin
                        if (mem_rsp_fire) begin
                            if (mem_rsp_error_i) begin
                                state_q <= ST_ERROR;
                            end else begin
                                weight_word_q <= $signed(mem_rsp_rdata_i);
                                state_q       <= ST_SEND_CORE;
                            end
                        end else begin
                            state_q <= ST_WAIT_WEIGHT;
                        end
                    end
                end

                ST_WAIT_WEIGHT: begin
                    if (mem_rsp_fire) begin
                        if (mem_rsp_error_i) begin
                            state_q <= ST_ERROR;
                        end else begin
                            weight_word_q <= $signed(mem_rsp_rdata_i);
                            state_q       <= ST_SEND_CORE;
                        end
                    end
                end

                ST_SEND_CORE: begin
                    if (core_data_fire) begin
                        if (word_index_q == (length_words_q - 16'd1)) begin
                            state_q <= ST_WAIT_CORE;
                        end else begin
                            word_index_q <= word_index_q + 16'd1;
                            state_q      <= ST_REQ_ACT;
                        end
                    end
                end

                ST_WAIT_CORE: begin
                    if (core_done) begin
                        result_q <= core_result;
                        state_q  <= ST_DONE;
                    end
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
