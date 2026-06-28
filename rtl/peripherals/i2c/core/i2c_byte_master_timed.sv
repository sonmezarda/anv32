module i2c_byte_master_timed #(
    parameter int SCL_LOW_CYCLES          = 135,
    parameter int SCL_HIGH_CYCLES         = 135,
    parameter int STRETCH_TIMEOUT_CYCLES  = 27_000
)(
    input  logic       clk_i,
    input  logic       rst_i,
    input  logic       start_i,
    input  logic       start_en_i,
    input  logic       stop_en_i,
    input  logic [7:0] tx_byte_i,
    inout  logic       sda_io,
    inout  logic       scl_io,

    output logic       busy_o,
    output logic       done_o,
    output logic       nack_error_o,
    output logic       arbitration_lost_o,
    output logic       timeout_error_o
);

    typedef enum logic [3:0] {
        ST_IDLE,
        ST_START_HOLD,
        ST_BIT_LOW,
        ST_BIT_WAIT_HIGH,
        ST_BIT_HIGH,
        ST_ACK_LOW,
        ST_ACK_WAIT_HIGH,
        ST_ACK_HIGH,
        ST_STOP_SETUP,
        ST_STOP_WAIT_HIGH,
        ST_STOP_RELEASE,
        ST_DONE
    } state_t;

    localparam logic [31:0] SCL_LOW_LAST      = SCL_LOW_CYCLES - 1;
    localparam logic [31:0] SCL_HIGH_LAST     = SCL_HIGH_CYCLES - 1;
    localparam logic [31:0] STRETCH_LAST      = STRETCH_TIMEOUT_CYCLES - 1;

    state_t      state_q;
    logic        sda_drive_low_q;
    logic        scl_drive_low_q;
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
            sda_drive_low_q    <= 1'b0;
            scl_drive_low_q    <= 1'b0;
            data_q             <= 8'd0;
            bit_idx_q          <= 3'd7;
            phase_cnt_q        <= 32'd0;
            stretch_cnt_q      <= 32'd0;
            done_o             <= 1'b0;
            nack_error_o       <= 1'b0;
            arbitration_lost_o <= 1'b0;
            timeout_error_o    <= 1'b0;
        end else begin
            done_o <= 1'b0;

            case(state_q)
                ST_IDLE: begin
                    sda_drive_low_q <= 1'b0;
                    scl_drive_low_q <= 1'b0;
                    phase_cnt_q     <= 32'd0;
                    stretch_cnt_q   <= 32'd0;

                    if(start_i) begin
                        data_q             <= tx_byte_i;
                        bit_idx_q          <= 3'd7;
                        nack_error_o       <= 1'b0;
                        arbitration_lost_o <= 1'b0;
                        timeout_error_o    <= 1'b0;

                        if(start_en_i) begin
                            sda_drive_low_q <= 1'b1;
                            scl_drive_low_q <= 1'b0;
                            state_q         <= ST_START_HOLD;
                        end else begin
                            sda_drive_low_q <= ~tx_byte_i[7];
                            scl_drive_low_q <= 1'b1;
                            state_q         <= ST_BIT_LOW;
                        end
                    end
                end

                ST_START_HOLD: begin
                    sda_drive_low_q <= 1'b1;
                    scl_drive_low_q <= 1'b0;

                    if(phase_cnt_q >= SCL_HIGH_LAST) begin
                        phase_cnt_q     <= 32'd0;
                        sda_drive_low_q <= ~data_q[7];
                        scl_drive_low_q <= 1'b1;
                        state_q         <= ST_BIT_LOW;
                    end else begin
                        phase_cnt_q <= phase_cnt_q + 32'd1;
                    end
                end

                ST_BIT_LOW: begin
                    scl_drive_low_q <= 1'b1;

                    if(phase_cnt_q >= SCL_LOW_LAST) begin
                        phase_cnt_q    <= 32'd0;
                        stretch_cnt_q  <= 32'd0;
                        scl_drive_low_q <= 1'b0;
                        state_q        <= ST_BIT_WAIT_HIGH;
                    end else begin
                        phase_cnt_q <= phase_cnt_q + 32'd1;
                    end
                end

                ST_BIT_WAIT_HIGH: begin
                    scl_drive_low_q <= 1'b0;

                    if(scl_io == 1'b1) begin
                        phase_cnt_q   <= 32'd0;
                        stretch_cnt_q <= 32'd0;
                        state_q       <= ST_BIT_HIGH;
                    end else if(stretch_cnt_q >= STRETCH_LAST) begin
                        timeout_error_o <= 1'b1;
                        state_q         <= ST_DONE;
                    end else begin
                        stretch_cnt_q <= stretch_cnt_q + 32'd1;
                    end
                end

                ST_BIT_HIGH: begin
                    if(!sda_drive_low_q && (sda_io == 1'b0)) begin
                        arbitration_lost_o <= 1'b1;
                        state_q            <= ST_DONE;
                    end else if(phase_cnt_q >= SCL_HIGH_LAST) begin
                        phase_cnt_q     <= 32'd0;
                        scl_drive_low_q <= 1'b1;

                        if(bit_idx_q == 3'd0) begin
                            sda_drive_low_q <= 1'b0;
                            state_q         <= ST_ACK_LOW;
                        end else begin
                            bit_idx_q       <= bit_idx_q - 3'd1;
                            sda_drive_low_q <= ~data_q[bit_idx_q - 3'd1];
                            state_q         <= ST_BIT_LOW;
                        end
                    end else begin
                        phase_cnt_q <= phase_cnt_q + 32'd1;
                    end
                end

                ST_ACK_LOW: begin
                    sda_drive_low_q <= 1'b0;
                    scl_drive_low_q <= 1'b1;

                    if(phase_cnt_q >= SCL_LOW_LAST) begin
                        phase_cnt_q     <= 32'd0;
                        stretch_cnt_q   <= 32'd0;
                        scl_drive_low_q <= 1'b0;
                        state_q         <= ST_ACK_WAIT_HIGH;
                    end else begin
                        phase_cnt_q <= phase_cnt_q + 32'd1;
                    end
                end

                ST_ACK_WAIT_HIGH: begin
                    scl_drive_low_q <= 1'b0;

                    if(scl_io == 1'b1) begin
                        nack_error_o <= (sda_io != 1'b0);
                        phase_cnt_q  <= 32'd0;
                        stretch_cnt_q <= 32'd0;
                        state_q      <= ST_ACK_HIGH;
                    end else if(stretch_cnt_q >= STRETCH_LAST) begin
                        timeout_error_o <= 1'b1;
                        state_q         <= ST_DONE;
                    end else begin
                        stretch_cnt_q <= stretch_cnt_q + 32'd1;
                    end
                end

                ST_ACK_HIGH: begin
                    if(phase_cnt_q >= SCL_HIGH_LAST) begin
                        phase_cnt_q     <= 32'd0;
                        scl_drive_low_q <= 1'b1;

                        if(stop_en_i) begin
                            sda_drive_low_q <= 1'b1;
                            state_q         <= ST_STOP_SETUP;
                        end else begin
                            sda_drive_low_q <= 1'b0;
                            state_q         <= ST_DONE;
                        end
                    end else begin
                        phase_cnt_q <= phase_cnt_q + 32'd1;
                    end
                end

                ST_STOP_SETUP: begin
                    sda_drive_low_q <= 1'b1;
                    scl_drive_low_q <= 1'b1;

                    if(phase_cnt_q >= SCL_LOW_LAST) begin
                        phase_cnt_q     <= 32'd0;
                        stretch_cnt_q   <= 32'd0;
                        scl_drive_low_q <= 1'b0;
                        state_q         <= ST_STOP_WAIT_HIGH;
                    end else begin
                        phase_cnt_q <= phase_cnt_q + 32'd1;
                    end
                end

                ST_STOP_WAIT_HIGH: begin
                    sda_drive_low_q <= 1'b1;
                    scl_drive_low_q <= 1'b0;

                    if(scl_io == 1'b1) begin
                        phase_cnt_q   <= 32'd0;
                        stretch_cnt_q <= 32'd0;
                        state_q       <= ST_STOP_RELEASE;
                    end else if(stretch_cnt_q >= STRETCH_LAST) begin
                        timeout_error_o <= 1'b1;
                        state_q         <= ST_DONE;
                    end else begin
                        stretch_cnt_q <= stretch_cnt_q + 32'd1;
                    end
                end

                ST_STOP_RELEASE: begin
                    sda_drive_low_q <= 1'b0;
                    scl_drive_low_q <= 1'b0;

                    if(phase_cnt_q >= SCL_HIGH_LAST) begin
                        phase_cnt_q <= 32'd0;
                        state_q     <= ST_DONE;
                    end else begin
                        phase_cnt_q <= phase_cnt_q + 32'd1;
                    end
                end

                ST_DONE: begin
                    sda_drive_low_q <= 1'b0;
                    scl_drive_low_q <= 1'b0;
                    done_o          <= 1'b1;
                    state_q         <= ST_IDLE;
                end

                default: begin
                    state_q         <= ST_IDLE;
                    sda_drive_low_q <= 1'b0;
                    scl_drive_low_q <= 1'b0;
                end
            endcase
        end
    end

endmodule
