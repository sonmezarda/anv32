module nn_accel_periph
    import anv32_nn_regs_pkg::*;
#(
    parameter logic [31:0] BASE_ADDR       = 32'h1001_0000,
    parameter logic [31:0] SCRATCH_OFFSET  = 32'h0000_1000,
    parameter int unsigned SCRATCH_WORDS   = 4096,
    parameter int unsigned SCRATCH_ADDR_W  = $clog2(SCRATCH_WORDS)
)(
    input  logic        clk_i,
    input  logic        rst_i,

    input  logic        mem_valid_i,
    input  logic [31:0] mem_addr_i,
    input  logic [31:0] mem_wdata_i,
    input  logic [3:0]  mem_we_i,
    output logic        mem_ready_o,
    output logic [31:0] mem_rdata_o,
    output logic        mem_hit_o,

    // Scratch read bypass: data valid the cycle after the request.
    output logic [31:0] scratch_rdata_o,
    output logic        scratch_sel_o,

    output logic        irq_o
);

    localparam logic [31:0] SCRATCH_BYTES =
        32'(SCRATCH_WORDS) << 2;

    logic [31:0] offset;

    logic periph_hit;
    logic reg_hit;
    logic scratch_hit;
    logic write_access;

    logic [SCRATCH_ADDR_W-1:0] cpu_scratch_word_addr;

    logic [31:0] input_base_q;
    logic [31:0] weight_base_q;
    logic [31:0] bias_base_q;
    logic [31:0] output_base_q;
    logic [15:0] input_length_words_q;
    logic [15:0] output_count_q;
    logic        relu_enable_q;
    logic        irq_enable_q;

    logic        start_pulse_q;
    logic        done_pending_q;
    logic        error_latched_q;
    logic signed [31:0] best_score_q;
    logic [15:0] best_index_q;
    logic        best_valid_q;
    logic [31:0] cycle_count_q;

    logic dense_busy;
    logic dense_done;
    logic dense_error;

    logic        dense_mem_req_valid;
    logic        dense_mem_req_ready;
    logic [31:0] dense_mem_req_addr;

    logic        dense_mem_rsp_valid;
    logic        dense_mem_rsp_ready;
    logic [31:0] dense_mem_rsp_rdata;
    logic        dense_mem_rsp_error;

    logic        dense_mem_wr_valid;
    logic        dense_mem_wr_ready;
    logic [31:0] dense_mem_wr_addr;
    logic [31:0] dense_mem_wr_wdata;
    logic [3:0]  dense_mem_wr_strb;

    logic        dense_rsp_valid_q;
    logic        dense_rsp_error_q;
    logic        dense_rd_pending_q;
    logic        dense_rd_error_q;
    logic [SCRATCH_ADDR_W-1:0] dense_rd_addr_q;

    logic dense_rd_fire;
    logic dense_wr_fire;
    logic cpu_scratch_write;
    logic cpu_scratch_access_ok;

    logic [SCRATCH_ADDR_W-1:0] dense_rd_word_addr;
    logic [SCRATCH_ADDR_W-1:0] dense_wr_word_addr;
    logic [SCRATCH_ADDR_W-1:0] scratch_cpu_addr;
    logic [SCRATCH_ADDR_W-1:0] scratch_dense_addr;
    logic [31:0]               scratch_cpu_wdata;
    logic [31:0]               scratch_dense_wdata;
    logic [3:0]                scratch_cpu_we;
    logic [3:0]                scratch_dense_we;
    logic [31:0]               scratch_cpu_rdata;
    logic [31:0]               scratch_dense_rdata;
    logic [SCRATCH_ADDR_W-1:0] output_base_word;
    logic [SCRATCH_ADDR_W-1:0] output_limit_word;
    logic [15:0]               output_write_index;
    logic                      dense_output_write;

    assign offset =
        mem_addr_i - BASE_ADDR;

    assign periph_hit =
        (mem_addr_i >= BASE_ADDR) &&
        (offset < (SCRATCH_OFFSET + SCRATCH_BYTES));

    assign reg_hit =
        periph_hit && (offset < SCRATCH_OFFSET);

    assign scratch_hit =
        periph_hit &&
        (offset >= SCRATCH_OFFSET) &&
        (offset < (SCRATCH_OFFSET + SCRATCH_BYTES));

    assign write_access =
        mem_valid_i && periph_hit && (mem_we_i != 4'b0000);

    assign cpu_scratch_word_addr =
        offset[SCRATCH_ADDR_W+1:2] - SCRATCH_OFFSET[SCRATCH_ADDR_W+1:2];

    assign cpu_scratch_access_ok =
        scratch_hit && !dense_busy && !start_pulse_q;

    assign cpu_scratch_write =
        write_access && cpu_scratch_access_ok;

    assign mem_hit_o =
        periph_hit;

    assign mem_ready_o =
        periph_hit;

    // Scratch read data comes from the registered BRAM output, so it is valid
    // one cycle after the address is presented, the same timing as the SoC data
    // BRAM. The SoC must consume it directly instead of through its extra
    // MMIO read register, which would add a second cycle of latency.
    assign scratch_rdata_o =
        scratch_cpu_rdata;

    assign scratch_sel_o =
        mem_valid_i && scratch_hit && (mem_we_i == 4'b0000);

    assign irq_o =
        irq_enable_q && done_pending_q;

    assign dense_mem_req_ready =
        !dense_rsp_valid_q && !dense_rd_pending_q && !dense_mem_wr_valid;

    assign dense_mem_wr_ready =
        !dense_rsp_valid_q && !dense_rd_pending_q;

    assign dense_rd_fire =
        dense_mem_req_valid && dense_mem_req_ready;

    assign dense_wr_fire =
        dense_mem_wr_valid && dense_mem_wr_ready;

    assign dense_mem_rsp_valid =
        dense_rsp_valid_q;

    assign dense_mem_rsp_rdata =
        dense_rsp_error_q ? 32'hDEAD_BEEF : scratch_dense_rdata;

    assign dense_mem_rsp_error =
        dense_rsp_error_q;

    assign dense_rd_word_addr =
        dense_mem_req_addr[SCRATCH_ADDR_W+1:2];

    assign dense_wr_word_addr =
        dense_mem_wr_addr[SCRATCH_ADDR_W+1:2];

    assign scratch_cpu_addr =
        cpu_scratch_word_addr;

    assign scratch_cpu_wdata =
        mem_wdata_i;

    assign scratch_cpu_we =
        cpu_scratch_write ? mem_we_i : 4'b0000;

    assign scratch_dense_addr =
        (dense_rd_pending_q || dense_rsp_valid_q) ? dense_rd_addr_q :
        dense_wr_fire ? dense_wr_word_addr :
        dense_rd_word_addr;

    assign scratch_dense_wdata =
        dense_mem_wr_wdata;

    assign scratch_dense_we =
        (dense_wr_fire && !scratch_addr_error(dense_mem_wr_addr)) ?
        dense_mem_wr_strb :
        4'b0000;

    assign output_base_word =
        output_base_q[SCRATCH_ADDR_W+1:2];

    assign output_limit_word =
        output_base_word + SCRATCH_ADDR_W'(output_count_q);

    assign output_write_index =
        16'(SCRATCH_ADDR_W'(dense_wr_word_addr - output_base_word));

    assign dense_output_write =
        dense_wr_fire &&
        (dense_mem_wr_strb == 4'b1111) &&
        (dense_wr_word_addr >= output_base_word) &&
        (dense_wr_word_addr < output_limit_word);

    dense_layer_engine dense (
        .clk_i                  (clk_i),
        .rst_i                  (rst_i),

        .start_i                (start_pulse_q),
        .input_base_i           (input_base_q),
        .weight_base_i          (weight_base_q),
        .bias_base_i            (bias_base_q),
        .output_base_i          (output_base_q),
        .input_length_words_i   (input_length_words_q),
        .output_count_i         (output_count_q),
        .relu_enable_i          (relu_enable_q),

        .busy_o                 (dense_busy),
        .done_o                 (dense_done),
        .error_o                (dense_error),

        .mem_req_valid_o        (dense_mem_req_valid),
        .mem_req_ready_i        (dense_mem_req_ready),
        .mem_req_addr_o         (dense_mem_req_addr),

        .mem_rsp_valid_i        (dense_mem_rsp_valid),
        .mem_rsp_ready_o        (dense_mem_rsp_ready),
        .mem_rsp_rdata_i        (dense_mem_rsp_rdata),
        .mem_rsp_error_i        (dense_mem_rsp_error),

        .mem_wr_valid_o         (dense_mem_wr_valid),
        .mem_wr_ready_i         (dense_mem_wr_ready),
        .mem_wr_addr_o          (dense_mem_wr_addr),
        .mem_wr_wdata_o         (dense_mem_wr_wdata),
        .mem_wr_strb_o          (dense_mem_wr_strb)
    );

    genvar lane_i;
    generate
        for (lane_i = 0; lane_i < 4; lane_i++) begin : gen_scratch_lane
            (* syn_ramstyle = "block_ram", ram_style = "block" *)
            logic [7:0] scratch_lane [0:SCRATCH_WORDS-1];

            always_ff @(posedge clk_i) begin
                if (scratch_cpu_we[lane_i]) begin
                    scratch_lane[scratch_cpu_addr] <=
                        scratch_cpu_wdata[lane_i*8 +: 8];
                end else begin
                    scratch_cpu_rdata[lane_i*8 +: 8] <=
                        scratch_lane[scratch_cpu_addr];
                end
            end

            always_ff @(posedge clk_i) begin
                if (scratch_dense_we[lane_i]) begin
                    scratch_lane[scratch_dense_addr] <=
                        scratch_dense_wdata[lane_i*8 +: 8];
                end else begin
                    scratch_dense_rdata[lane_i*8 +: 8] <=
                        scratch_lane[scratch_dense_addr];
                end
            end
        end
    endgenerate

    always_comb begin
        mem_rdata_o = 32'b0;

        if (reg_hit) begin
            unique case (offset)
                NN_CONTROL_OFFSET: begin
                    mem_rdata_o = 32'b0;
                end

                NN_STATUS_OFFSET: begin
                    mem_rdata_o[NN_STATUS_BUSY_BIT]       = dense_busy;
                    mem_rdata_o[NN_STATUS_DONE_BIT]       = done_pending_q;
                    mem_rdata_o[NN_STATUS_ERROR_BIT]      = error_latched_q;
                    mem_rdata_o[NN_STATUS_IRQ_ENABLE_BIT] = irq_enable_q;
                    mem_rdata_o[NN_STATUS_BEST_VALID_BIT] = best_valid_q;
                end

                NN_INPUT_BASE_OFFSET: begin
                    mem_rdata_o = input_base_q;
                end

                NN_WEIGHT_BASE_OFFSET: begin
                    mem_rdata_o = weight_base_q;
                end

                NN_BIAS_BASE_OFFSET: begin
                    mem_rdata_o = bias_base_q;
                end

                NN_OUTPUT_BASE_OFFSET: begin
                    mem_rdata_o = output_base_q;
                end

                NN_INPUT_LEN_WORDS_OFFSET: begin
                    mem_rdata_o = {16'b0, input_length_words_q};
                end

                NN_OUTPUT_COUNT_OFFSET: begin
                    mem_rdata_o = {16'b0, output_count_q};
                end

                NN_CONFIG_OFFSET: begin
                    mem_rdata_o[NN_CONFIG_RELU_BIT]       = relu_enable_q;
                    mem_rdata_o[NN_CONFIG_IRQ_ENABLE_BIT] = irq_enable_q;
                end

                NN_RESULT_ARGMAX_OFFSET: begin
                    mem_rdata_o = {16'b0, best_index_q};
                end

                NN_BEST_SCORE_OFFSET: begin
                    mem_rdata_o = best_score_q;
                end

                NN_CYCLE_COUNT_OFFSET: begin
                    mem_rdata_o = cycle_count_q;
                end

                default: begin
                    mem_rdata_o = 32'b0;
                end
            endcase
        end else if (scratch_hit) begin
            mem_rdata_o = scratch_cpu_rdata;
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            input_base_q          <= 32'b0;
            weight_base_q         <= 32'b0;
            bias_base_q           <= 32'b0;
            output_base_q         <= 32'b0;
            input_length_words_q  <= 16'd0;
            output_count_q        <= 16'd0;
            relu_enable_q         <= 1'b0;
            irq_enable_q          <= 1'b0;
            start_pulse_q         <= 1'b0;
            done_pending_q        <= 1'b0;
            error_latched_q       <= 1'b0;
            best_score_q          <= 32'sd0;
            best_index_q          <= 16'd0;
            best_valid_q          <= 1'b0;
            cycle_count_q         <= 32'd0;
            dense_rsp_valid_q     <= 1'b0;
            dense_rsp_error_q     <= 1'b0;
            dense_rd_pending_q    <= 1'b0;
            dense_rd_error_q      <= 1'b0;
            dense_rd_addr_q       <= '0;
        end else begin
            start_pulse_q <= 1'b0;

            // Inference latency counter: cleared on start, counts while the
            // dense engine is busy, then holds until the next start.
            if (start_pulse_q || dense_busy) begin
                cycle_count_q <= cycle_count_q + 32'd1;
            end

            if (dense_rsp_valid_q && dense_mem_rsp_ready) begin
                dense_rsp_valid_q <= 1'b0;
            end

            if (dense_rd_pending_q) begin
                dense_rsp_valid_q  <= 1'b1;
                dense_rsp_error_q  <= dense_rd_error_q;
                dense_rd_pending_q <= 1'b0;
            end

            if (dense_done) begin
                done_pending_q <= 1'b1;
            end

            if (dense_error) begin
                error_latched_q <= 1'b1;
            end

            if (reg_hit && write_access) begin
                unique case (offset)
                    NN_CONTROL_OFFSET: begin
                        if (mem_wdata_i[NN_CONTROL_START_BIT] && !dense_busy) begin
                            start_pulse_q   <= 1'b1;
                            done_pending_q  <= 1'b0;
                            error_latched_q <= 1'b0;
                            best_score_q    <= 32'sd0;
                            best_index_q    <= 16'd0;
                            best_valid_q    <= 1'b0;
                            cycle_count_q   <= 32'd0;
                        end

                        if (mem_wdata_i[NN_CONTROL_CLEAR_BIT]) begin
                            done_pending_q  <= 1'b0;
                            error_latched_q <= 1'b0;
                        end
                    end

                    NN_INPUT_BASE_OFFSET: begin
                        input_base_q <= mem_wdata_i;
                    end

                    NN_WEIGHT_BASE_OFFSET: begin
                        weight_base_q <= mem_wdata_i;
                    end

                    NN_BIAS_BASE_OFFSET: begin
                        bias_base_q <= mem_wdata_i;
                    end

                    NN_OUTPUT_BASE_OFFSET: begin
                        output_base_q <= mem_wdata_i;
                    end

                    NN_INPUT_LEN_WORDS_OFFSET: begin
                        input_length_words_q <= mem_wdata_i[15:0];
                    end

                    NN_OUTPUT_COUNT_OFFSET: begin
                        output_count_q <= mem_wdata_i[15:0];
                    end

                    NN_CONFIG_OFFSET: begin
                        relu_enable_q <= mem_wdata_i[NN_CONFIG_RELU_BIT];
                        irq_enable_q  <= mem_wdata_i[NN_CONFIG_IRQ_ENABLE_BIT];
                    end

                    default: begin
                    end
                endcase
            end

            if (dense_rd_fire) begin
                dense_rd_pending_q <= 1'b1;
                dense_rd_error_q   <= scratch_addr_error(dense_mem_req_addr);
                dense_rd_addr_q    <= dense_rd_word_addr;
            end

            if (dense_output_write) begin
                if (!best_valid_q || ($signed(dense_mem_wr_wdata) > best_score_q)) begin
                    best_score_q <= $signed(dense_mem_wr_wdata);
                    best_index_q <= output_write_index;
                    best_valid_q <= 1'b1;
                end
            end
        end
    end

    function automatic logic scratch_addr_error(input logic [31:0] addr);
        logic [29:0] word_addr;
        begin
            word_addr = addr[31:2];
            scratch_addr_error =
                (addr[1:0] != 2'b00) ||
                (word_addr >= 30'(SCRATCH_WORDS));
        end
    endfunction

endmodule
