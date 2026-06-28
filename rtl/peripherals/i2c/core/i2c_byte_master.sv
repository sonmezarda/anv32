module i2c_byte_master(
    input  logic clk_i,
    input  logic rst_i,
    input  logic start_i,
    input  logic scl_tick_i,
    input  logic start_en_i,
    input  logic stop_en_i,
    input  logic [7:0] tx_byte_i,
    inout  logic sda_io,
    inout  logic scl_io,

    output logic busy_o,
    output logic done_o,
    output logic nack_error_o
);

    typedef enum logic [2:0]{
        ST_IDLE, ST_START, ST_SEND, ST_ACK, ST_STOP
    } state_t;

    typedef enum logic {
        PH_LOW,
        PH_HIGH
    } phase_t;

    typedef enum logic [1:0]{
        ST_STOP_SETUP,
        ST_STOP_SCL_HIGH,
        ST_STOP_SDA_RELEASE
    } stop_state_t;

    logic        sda_drive_low_q, scl_drive_low_q;
    state_t      state_q;
    phase_t      phase_q;
    stop_state_t stop_state_q;
    logic [3:0]  bit_idx_q;
    logic [7:0]  data_q;
    logic [2:0]  next_bit_idx;
    logic        nack_error;

    assign sda_io = sda_drive_low_q ? 1'b0 : 1'bz;
    assign scl_io = scl_drive_low_q ? 1'b0 : 1'bz;
    assign next_bit_idx = (bit_idx_q == 4'd8) ? 3'd7 : (bit_idx_q[2:0] - 3'd1);
    assign nack_error_o = nack_error;
    assign busy_o = state_q != ST_IDLE;

    always_ff @(posedge clk_i) begin
        if(rst_i) begin
            state_q         <= ST_IDLE;
            phase_q         <= PH_LOW;
            scl_drive_low_q <= 1'b0;
            sda_drive_low_q <= 1'b0;
            bit_idx_q       <= 4'd0;
            data_q          <= 8'd0;
            nack_error      <= 1'b0;
            stop_state_q    <= ST_STOP_SETUP;
            done_o          <= 1'b0;
        end else begin
            done_o <= 1'b0;
            if(scl_tick_i) begin
                case(state_q)
                    ST_IDLE: begin
                        scl_drive_low_q <= 1'b0;
                        sda_drive_low_q <= 1'b0;
                        phase_q         <= PH_LOW;
                        if(start_i) begin
                            nack_error <= 1'b0;
                            state_q    <= start_en_i ? ST_START : ST_SEND;
                            bit_idx_q  <= 4'd8;
                            data_q     <= tx_byte_i;
                        end
                    end
                    ST_START: begin
                        scl_drive_low_q <= 1'b0;
                        sda_drive_low_q <= 1'b1;
                        phase_q         <= PH_HIGH;
                        bit_idx_q       <= 4'd8;
                        data_q          <= tx_byte_i;
                        state_q         <= ST_SEND;
                    end
                    ST_SEND: begin
                        if(phase_q == PH_LOW) begin
                            scl_drive_low_q <= 1'b0;
                            phase_q         <= PH_HIGH;
                        end else begin
                            scl_drive_low_q <= 1'b1;
                            phase_q         <= PH_LOW;
                            if(bit_idx_q == 4'd0) begin
                                sda_drive_low_q <= 1'b0;
                                state_q         <= ST_ACK;
                            end else begin
                                bit_idx_q       <= {1'b0, next_bit_idx};
                                sda_drive_low_q <= ~data_q[next_bit_idx];
                            end
                        end
                    end

                    ST_ACK: begin
                        if(phase_q == PH_LOW) begin
                            scl_drive_low_q <= 1'b0;
                            phase_q         <= PH_HIGH;
                        end else begin
                            phase_q    <= PH_LOW;
                            nack_error <= sda_io;
                            if(stop_en_i) begin
                                stop_state_q <= ST_STOP_SETUP;
                                state_q      <= ST_STOP;
                            end else begin
                                state_q <= ST_IDLE;
                                done_o  <= 1'b1;
                            end
                        end
                    end
                    ST_STOP: begin
                        case(stop_state_q)
                            ST_STOP_SETUP: begin
                                scl_drive_low_q <= 1'b1;
                                sda_drive_low_q <= 1'b1;
                                stop_state_q    <= ST_STOP_SCL_HIGH;
                            end

                            ST_STOP_SCL_HIGH: begin
                                scl_drive_low_q <= 1'b0;
                                sda_drive_low_q <= 1'b1;
                                stop_state_q    <= ST_STOP_SDA_RELEASE;
                            end

                            ST_STOP_SDA_RELEASE: begin
                                scl_drive_low_q <= 1'b0;
                                sda_drive_low_q <= 1'b0;
                                stop_state_q    <= ST_STOP_SETUP;
                                state_q         <= ST_IDLE;
                                done_o          <= 1'b1;
                            end
                            default: stop_state_q <= ST_STOP_SETUP;
                        endcase
                    end
                    default: begin
                        state_q         <= ST_IDLE;
                        phase_q         <= PH_LOW;
                        scl_drive_low_q <= 1'b0;
                        sda_drive_low_q <= 1'b0;
                    end
                endcase
            end
        end
    end

endmodule
