module uart_rx #(
    parameter logic IDLE_STATE_BIT  = 1'b1,
    parameter logic STOP_BIT_VALUE  = 1'b1,
    parameter logic START_BIT_VALUE = 1'b0
)(
    input logic clk_i,
    input logic rst_i,
    input logic baud_x16_tick_i,
    input logic rx_i,
    
    output logic [7:0] data_o,
    output logic valid_o,
    output logic busy_o,
    output logic framing_error_o
);
    typedef enum logic [1:0] {
        ST_IDLE,
        ST_START,
        ST_DATA,
        ST_STOP
    } state_t;

    state_t state;

    logic [3:0] sample_count;
    logic [2:0] bit_index;
    logic [7:0] data_reg;
    logic [1:0] sample_sum;
    logic       sample_vote;

    logic rx_sync_0;
    logic rx_sync_1;
    logic rx_prev_q;

    // Majority of the three mid-bit samples taken at ticks 7/8/9; the vote is
    // consumed after all three have been accumulated.
    assign sample_vote = sample_sum >= 2'd2;

    // 2FF for metastability
    always_ff @(posedge clk_i) begin : blockName
        if(rst_i) begin
            rx_sync_0 <= IDLE_STATE_BIT;
            rx_sync_1 <= IDLE_STATE_BIT;
            rx_prev_q <= IDLE_STATE_BIT;
        end else begin
            rx_sync_0 <= rx_i;
            rx_sync_1 <= rx_sync_0;
            rx_prev_q <= rx_sync_1;
        end
    end

    always_ff @(posedge clk_i) begin
        if(rst_i) begin
            state         <= ST_IDLE;
            sample_count  <= 4'd0;
            bit_index     <= 3'd0;
            data_reg      <= 8'd0;
            data_o        <= 8'd0;
            valid_o       <= 1'b0;
            busy_o        <= 1'b0;
            framing_error_o <= 1'b0;
            sample_sum    <= 2'd0;
        end else begin
            valid_o       <= 1'b0;
            framing_error_o <= 1'b0;
            if (state == ST_IDLE) begin
                busy_o <= 1'b0;
                // Falling-edge start detection at clock rate (not gated by the
                // x16 tick): every frame re-anchors to the true start edge, so
                // a sender slightly faster than the local baud cannot
                // accumulate drift across a gapless byte stream.
                if (rx_prev_q == IDLE_STATE_BIT && rx_sync_1 == START_BIT_VALUE) begin
                    state        <= ST_START;
                    bit_index    <= 3'd0;
                    busy_o       <= 1'b1;
                    data_reg     <= 8'd0;
                    sample_count <= 4'd0;
                    sample_sum   <= 2'd0;
                end
            end else if(baud_x16_tick_i) begin
                case(state)
                    ST_START: begin
                        sample_count <= sample_count + 1'b1;
                        if(sample_count == 4'd7 || sample_count == 4'd8 || sample_count == 4'd9) begin
                            sample_sum <= sample_sum + {1'b0, rx_sync_1};
                        end
                        if(sample_count == 4'd15) begin
                            if(sample_vote == START_BIT_VALUE) begin
                                // valid start bit, start receiving data
                                state        <= ST_DATA;
                                sample_count <= 4'd0;
                                bit_index    <= 3'd0;
                                sample_sum   <= 2'd0;
                            end else begin
                                state        <= ST_IDLE;
                                busy_o       <= 1'b0;
                                sample_count <= 4'd0;
                                sample_sum   <= 2'd0;
                            end
                        end
                    end

                    ST_DATA: begin
                        sample_count <= sample_count + 1'b1;
                        if(sample_count == 4'd7 || sample_count == 4'd8 || sample_count == 4'd9) begin
                            sample_sum <= sample_sum + {1'b0, rx_sync_1};
                        end
                        if(sample_count == 4'd15) begin
                            data_reg[bit_index] <= sample_vote;
                            bit_index           <= bit_index + 1'b1;
                            sample_count        <= 4'd0;
                            sample_sum          <= 2'd0;
                            if(bit_index == 3'b111) begin
                                state <= ST_STOP;
                            end
                        end
                    end

                    ST_STOP: begin
                        sample_count <= sample_count + 1'b1;
                        if(sample_count == 4'd7 || sample_count == 4'd8 || sample_count == 4'd9) begin
                            sample_sum <= sample_sum + {1'b0, rx_sync_1};
                        end
                        // Leave right after the mid-bit vote instead of
                        // consuming the whole stop bit, so ST_IDLE is already
                        // hunting for the next start edge when it arrives.
                        if(sample_count == 4'd10) begin
                            state        <= ST_IDLE;
                            busy_o       <= 1'b0;
                            sample_count <= 4'd0;
                            bit_index    <= 3'd0;
                            sample_sum   <= 2'd0;
                            // check stop bit
                            if(sample_vote == STOP_BIT_VALUE) begin
                                data_o  <= data_reg;
                                valid_o <= 1'b1;
                            end else begin
                                framing_error_o <= 1'b1;
                            end
                        end
                    end
                    
                    default: begin
                        state         <= ST_IDLE;
                        sample_count  <= 4'd0;
                        bit_index     <= 3'd0;
                        data_reg      <= 8'd0;
                        busy_o        <= 1'b0;
                        sample_sum    <= 2'd0;
                    end
                endcase
            end
        end
    end

endmodule
