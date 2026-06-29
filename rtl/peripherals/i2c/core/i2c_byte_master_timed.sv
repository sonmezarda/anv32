module i2c_byte_master_timed #(
    parameter int SCL_LOW_CYCLES         = 135,
    parameter int SCL_HIGH_CYCLES        = 135,
    parameter int STRETCH_TIMEOUT_CYCLES = 27_000
)(
    input  logic       clk_i,
    input  logic       rst_i,
    input  logic       start_i,
    input  logic       start_en_i,
    input  logic       stop_en_i,
    input  logic       read_i,
    input  logic       rx_ack_i,
    input  logic [7:0] tx_byte_i,
    inout  logic       sda_io,
    inout  logic       scl_io,

    output logic       busy_o,
    output logic       done_o,
    output logic [7:0] rx_byte_o,
    output logic       rx_valid_o,
    output logic       nack_error_o,
    output logic       arbitration_lost_o,
    output logic       timeout_error_o
);

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_START,
        ST_SEND,
        ST_TX_ACK,
        ST_RECV,
        ST_RX_ACK,
        ST_STOP
    } state_t;

    typedef enum logic [1:0] {
        PH_LOW, 
        PH_WAIT_HIGH, // scl released, wait until be 1
        PH_HIGH
    } phase_t;

    localparam logic [31:0] SCL_LOW_LAST  = SCL_LOW_CYCLES - 1;
    localparam logic [31:0] SCL_HIGH_LAST = SCL_HIGH_CYCLES - 1;
    localparam logic [31:0] SCL_HIGH_SAMPLE = SCL_HIGH_CYCLES / 2;
    localparam logic [31:0] STRETCH_LAST  = STRETCH_TIMEOUT_CYCLES - 1;

    state_t      state_q;
    phase_t      phase_q;
    logic        sda_drive_low_q;
    logic        scl_drive_low_q;
    logic        hold_bus_q;
    logic        read_q;
    logic        rx_ack_q;
    logic        rx_sampled_q;
    logic [7:0]  data_q;
    logic [2:0]  bit_idx_q;
    logic [31:0] phase_cnt_q;
    logic [31:0] stretch_cnt_q;

    assign sda_io = sda_drive_low_q ? 1'b0 : 1'bz;
    assign scl_io = scl_drive_low_q ? 1'b0 : 1'bz;

    assign busy_o = state_q != ST_IDLE;

    always_ff @(posedge clk_i) begin
        if(rst_i) begin
            state_q            <= ST_IDLE;
            phase_q            <= PH_LOW;
            sda_drive_low_q    <= 1'b0;
            scl_drive_low_q    <= 1'b0;
            hold_bus_q         <= 1'b0;
            data_q             <= 8'd0;
            read_q             <= 1'b0;
            rx_ack_q           <= 1'b0;
            rx_sampled_q       <= 1'b0;
            bit_idx_q          <= 3'd7;
            phase_cnt_q        <= 32'd0;
            stretch_cnt_q      <= 32'd0;
            done_o             <= 1'b0;
            rx_byte_o          <= 8'd0;
            rx_valid_o         <= 1'b0;
            nack_error_o       <= 1'b0;
            arbitration_lost_o <= 1'b0;
            timeout_error_o    <= 1'b0;
        end else begin
            done_o     <= 1'b0;
            rx_valid_o <= 1'b0;

            case(state_q)
                ST_IDLE: begin
                    phase_q       <= PH_LOW;
                    phase_cnt_q   <= 32'd0;
                    stretch_cnt_q <= 32'd0;

                    if(hold_bus_q) begin
                        scl_drive_low_q <= 1'b1;
                        sda_drive_low_q <= 1'b0;
                    end else begin
                        scl_drive_low_q <= 1'b0;
                        sda_drive_low_q <= 1'b0;
                    end

                    if(start_i) begin
                        data_q             <= tx_byte_i;
                        read_q             <= read_i;
                        rx_ack_q           <= rx_ack_i;
                        rx_sampled_q       <= 1'b0;
                        bit_idx_q          <= 3'd7;
                        rx_byte_o          <= 8'd0;
                        nack_error_o       <= 1'b0;
                        arbitration_lost_o <= 1'b0;
                        timeout_error_o    <= 1'b0;
                        hold_bus_q         <= 1'b0;

                        if(start_en_i) begin
                            scl_drive_low_q <= 1'b0;
                            sda_drive_low_q <= 1'b0;
                            phase_q         <= PH_WAIT_HIGH;
                            state_q         <= ST_START;
                        end else begin
                            scl_drive_low_q <= 1'b1;
                            sda_drive_low_q <= read_i ? 1'b0 : ~tx_byte_i[7];
                            phase_q         <= PH_LOW;
                            state_q         <= read_i ? ST_RECV : ST_SEND;
                        end
                    end
                end

                ST_START: begin
                    case(phase_q)
                        PH_WAIT_HIGH: begin
                            scl_drive_low_q <= 1'b0;
                            sda_drive_low_q <= 1'b0;

                            if(scl_io == 1'b1) begin
                                sda_drive_low_q <= 1'b1;
                                phase_cnt_q     <= 32'd0;
                                stretch_cnt_q   <= 32'd0;
                                phase_q         <= PH_HIGH;
                            end else if(stretch_cnt_q >= STRETCH_LAST) begin
                                timeout_error_o <= 1'b1;
                                state_q         <= ST_IDLE;
                                done_o          <= 1'b1;
                            end else begin
                                stretch_cnt_q <= stretch_cnt_q + 32'd1;
                            end
                        end

                        PH_HIGH: begin
                            scl_drive_low_q <= 1'b0;
                            sda_drive_low_q <= 1'b1;

                            if(phase_cnt_q >= SCL_HIGH_LAST) begin
                                scl_drive_low_q <= 1'b1;
                                sda_drive_low_q <= read_q ? 1'b0 : ~data_q[7];
                                phase_cnt_q     <= 32'd0;
                                phase_q         <= PH_LOW;
                                state_q         <= read_q ? ST_RECV : ST_SEND;
                            end else begin
                                phase_cnt_q <= phase_cnt_q + 32'd1;
                            end
                        end

                        default: phase_q <= PH_WAIT_HIGH;
                    endcase
                end

                ST_SEND: begin
                    case(phase_q)
                        PH_LOW: begin
                            scl_drive_low_q <= 1'b1;
                            sda_drive_low_q <= ~data_q[bit_idx_q];

                            if(phase_cnt_q >= SCL_LOW_LAST) begin // low state finished, wait until high
                                scl_drive_low_q <= 1'b0;
                                phase_cnt_q     <= 32'd0;
                                stretch_cnt_q   <= 32'd0;
                                phase_q         <= PH_WAIT_HIGH;
                            end else begin // still low phase 
                                phase_cnt_q <= phase_cnt_q + 32'd1;
                            end
                        end

                        PH_WAIT_HIGH: begin
                            scl_drive_low_q <= 1'b0; // release scl

                            if(scl_io == 1'b1) begin // if scl_io realy released
                                phase_cnt_q   <= 32'd0;
                                stretch_cnt_q <= 32'd0;
                                phase_q       <= PH_HIGH; 
                            end else if(stretch_cnt_q >= STRETCH_LAST) begin
                                timeout_error_o <= 1'b1;
                                sda_drive_low_q <= 1'b0;
                                state_q         <= ST_IDLE;
                                done_o          <= 1'b1;
                            end else begin
                                stretch_cnt_q <= stretch_cnt_q + 32'd1;
                            end
                        end

                        PH_HIGH: begin
                            scl_drive_low_q <= 1'b0;

                            if(!sda_drive_low_q && (sda_io == 1'b0)) begin // SDA released but its still low
                                arbitration_lost_o <= 1'b1;
                                sda_drive_low_q    <= 1'b0;
                                state_q            <= ST_IDLE;
                                done_o             <= 1'b1;
                            end else if(phase_cnt_q >= SCL_HIGH_LAST) begin
                                scl_drive_low_q <= 1'b1;
                                phase_cnt_q     <= 32'd0;
                                phase_q         <= PH_LOW;

                                if(bit_idx_q == 3'd0) begin
                                    sda_drive_low_q <= 1'b0;
                                    state_q         <= ST_TX_ACK;
                                end else begin
                                    bit_idx_q       <= bit_idx_q - 3'd1;
                                    sda_drive_low_q <= ~data_q[bit_idx_q - 3'd1];
                                end
                            end else begin
                                phase_cnt_q <= phase_cnt_q + 32'd1;
                            end
                        end

                        default: phase_q <= PH_LOW;
                    endcase
                end

                ST_TX_ACK: begin
                    case(phase_q)
                        PH_LOW: begin
                            scl_drive_low_q <= 1'b1;
                            sda_drive_low_q <= 1'b0;

                            if(phase_cnt_q >= SCL_LOW_LAST) begin
                                scl_drive_low_q <= 1'b0;
                                phase_cnt_q     <= 32'd0;
                                stretch_cnt_q   <= 32'd0;
                                phase_q         <= PH_WAIT_HIGH;
                            end else begin
                                phase_cnt_q <= phase_cnt_q + 32'd1;
                            end
                        end

                        PH_WAIT_HIGH: begin
                            scl_drive_low_q <= 1'b0;
                            sda_drive_low_q <= 1'b0;

                            if(scl_io == 1'b1) begin
                                nack_error_o <= (sda_io != 1'b0);
                                phase_cnt_q  <= 32'd0;
                                stretch_cnt_q <= 32'd0;
                                phase_q      <= PH_HIGH;
                            end else if(stretch_cnt_q >= STRETCH_LAST) begin
                                timeout_error_o <= 1'b1;
                                state_q         <= ST_IDLE;
                                done_o          <= 1'b1;
                            end else begin
                                stretch_cnt_q <= stretch_cnt_q + 32'd1;
                            end
                        end

                        PH_HIGH: begin
                            scl_drive_low_q <= 1'b0;
                            sda_drive_low_q <= 1'b0;

                            if(phase_cnt_q >= SCL_HIGH_LAST) begin
                                scl_drive_low_q <= 1'b1;
                                phase_cnt_q     <= 32'd0;
                                phase_q         <= PH_LOW;

                                if(stop_en_i) begin
                                    sda_drive_low_q <= 1'b1;
                                    state_q         <= ST_STOP;
                                end else begin
                                    hold_bus_q      <= 1'b1;
                                    sda_drive_low_q <= 1'b0;
                                    state_q         <= ST_IDLE;
                                    done_o          <= 1'b1;
                                end
                            end else begin
                                phase_cnt_q <= phase_cnt_q + 32'd1;
                            end
                        end

                        default: phase_q <= PH_LOW;
                    endcase
                end

                ST_RECV: begin
                    case(phase_q)
                        PH_LOW: begin
                            scl_drive_low_q <= 1'b1;
                            sda_drive_low_q <= 1'b0;

                            if(phase_cnt_q >= SCL_LOW_LAST) begin
                                scl_drive_low_q <= 1'b0;
                                phase_cnt_q     <= 32'd0;
                                stretch_cnt_q   <= 32'd0;
                                phase_q         <= PH_WAIT_HIGH;
                            end else begin
                                phase_cnt_q <= phase_cnt_q + 32'd1;
                            end
                        end

                        PH_WAIT_HIGH: begin
                            scl_drive_low_q <= 1'b0;
                            sda_drive_low_q <= 1'b0;

                            if(scl_io == 1'b1) begin
                                phase_cnt_q    <= 32'd0;
                                stretch_cnt_q  <= 32'd0;
                                rx_sampled_q   <= 1'b0;
                                phase_q        <= PH_HIGH;
                            end else if(stretch_cnt_q >= STRETCH_LAST) begin
                                timeout_error_o <= 1'b1;
                                state_q         <= ST_IDLE;
                                done_o          <= 1'b1;
                            end else begin
                                stretch_cnt_q <= stretch_cnt_q + 32'd1;
                            end
                        end

                        PH_HIGH: begin
                            scl_drive_low_q <= 1'b0;
                            sda_drive_low_q <= 1'b0;

                            if(!rx_sampled_q && (phase_cnt_q >= SCL_HIGH_SAMPLE)) begin
                                rx_byte_o[bit_idx_q] <= sda_io;
                                rx_sampled_q         <= 1'b1;
                            end

                            if(phase_cnt_q >= SCL_HIGH_LAST) begin
                                scl_drive_low_q <= 1'b1;
                                phase_cnt_q     <= 32'd0;
                                phase_q         <= PH_LOW;
                                rx_sampled_q    <= 1'b0;

                                if(bit_idx_q == 3'd0) begin
                                    state_q <= ST_RX_ACK;
                                end else begin
                                    bit_idx_q <= bit_idx_q - 3'd1;
                                end
                            end else begin
                                phase_cnt_q <= phase_cnt_q + 32'd1;
                            end
                        end

                        default: phase_q <= PH_LOW;
                    endcase
                end

                ST_RX_ACK: begin
                    case(phase_q)
                        PH_LOW: begin
                            scl_drive_low_q <= 1'b1;
                            sda_drive_low_q <= rx_ack_q;

                            if(phase_cnt_q >= SCL_LOW_LAST) begin
                                scl_drive_low_q <= 1'b0;
                                phase_cnt_q     <= 32'd0;
                                stretch_cnt_q   <= 32'd0;
                                phase_q         <= PH_WAIT_HIGH;
                            end else begin
                                phase_cnt_q <= phase_cnt_q + 32'd1;
                            end
                        end

                        PH_WAIT_HIGH: begin
                            scl_drive_low_q <= 1'b0;
                            sda_drive_low_q <= rx_ack_q;

                            if(scl_io == 1'b1) begin
                                phase_cnt_q   <= 32'd0;
                                stretch_cnt_q <= 32'd0;
                                phase_q       <= PH_HIGH;
                            end else if(stretch_cnt_q >= STRETCH_LAST) begin
                                timeout_error_o <= 1'b1;
                                sda_drive_low_q <= 1'b0;
                                state_q         <= ST_IDLE;
                                done_o          <= 1'b1;
                            end else begin
                                stretch_cnt_q <= stretch_cnt_q + 32'd1;
                            end
                        end

                        PH_HIGH: begin
                            scl_drive_low_q <= 1'b0;
                            sda_drive_low_q <= rx_ack_q;

                            if(phase_cnt_q >= SCL_HIGH_LAST) begin
                                scl_drive_low_q <= 1'b1;
                                sda_drive_low_q <= 1'b0;
                                phase_cnt_q     <= 32'd0;
                                phase_q         <= PH_LOW;
                                rx_valid_o      <= 1'b1;

                                if(stop_en_i) begin
                                    sda_drive_low_q <= 1'b1;
                                    state_q         <= ST_STOP;
                                end else begin
                                    hold_bus_q <= 1'b1;
                                    state_q    <= ST_IDLE;
                                    done_o     <= 1'b1;
                                end
                            end else begin
                                phase_cnt_q <= phase_cnt_q + 32'd1;
                            end
                        end

                        default: phase_q <= PH_LOW;
                    endcase
                end

                ST_STOP: begin
                    case(phase_q)
                        PH_LOW: begin
                            scl_drive_low_q <= 1'b1;
                            sda_drive_low_q <= 1'b1;

                            if(phase_cnt_q >= SCL_LOW_LAST) begin
                                scl_drive_low_q <= 1'b0;
                                phase_cnt_q     <= 32'd0;
                                stretch_cnt_q   <= 32'd0;
                                phase_q         <= PH_WAIT_HIGH;
                            end else begin
                                phase_cnt_q <= phase_cnt_q + 32'd1;
                            end
                        end

                        PH_WAIT_HIGH: begin
                            scl_drive_low_q <= 1'b0;
                            sda_drive_low_q <= 1'b1;

                            if(scl_io == 1'b1) begin
                                phase_cnt_q   <= 32'd0;
                                stretch_cnt_q <= 32'd0;
                                phase_q       <= PH_HIGH;
                            end else if(stretch_cnt_q >= STRETCH_LAST) begin
                                timeout_error_o <= 1'b1;
                                sda_drive_low_q <= 1'b0;
                                state_q         <= ST_IDLE;
                                done_o          <= 1'b1;
                            end else begin
                                stretch_cnt_q <= stretch_cnt_q + 32'd1;
                            end
                        end

                        PH_HIGH: begin
                            scl_drive_low_q <= 1'b0;
                            sda_drive_low_q <= 1'b0;

                            if(phase_cnt_q >= SCL_HIGH_LAST) begin
                                phase_cnt_q <= 32'd0;
                                hold_bus_q  <= 1'b0;
                                state_q     <= ST_IDLE;
                                done_o      <= 1'b1;
                            end else begin
                                phase_cnt_q <= phase_cnt_q + 32'd1;
                            end
                        end

                        default: phase_q <= PH_LOW;
                    endcase
                end

                default: begin
                    state_q         <= ST_IDLE;
                    phase_q         <= PH_LOW;
                    sda_drive_low_q <= 1'b0;
                    scl_drive_low_q <= 1'b0;
                    hold_bus_q      <= 1'b0;
                end
            endcase
        end
    end

endmodule
