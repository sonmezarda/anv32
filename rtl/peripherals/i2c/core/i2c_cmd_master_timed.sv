module i2c_cmd_master_timed #(
    parameter int CMD_FIFO_DEPTH         = 16,
    parameter int RX_FIFO_DEPTH          = 8,
    parameter int SCL_LOW_CYCLES         = 135,
    parameter int SCL_HIGH_CYCLES        = 135,
    parameter int STRETCH_TIMEOUT_CYCLES = 27_000
)(
    input  logic       clk_i,
    input  logic       rst_i,

    input  logic       cmd_valid_i,
    output logic       cmd_ready_o,
    input  logic [2:0] cmd_op_i,
    input  logic       cmd_start_i,
    input  logic       cmd_stop_i,
    input  logic       cmd_ack_i,
    input  logic [7:0] cmd_data_i,

    output logic       rx_valid_o,
    input  logic       rx_pop_i,
    output logic [7:0] rx_data_o,

    input  logic       clear_errors_i,

    inout  logic       sda_io,
    inout  logic       scl_io,

    output logic       busy_o,
    output logic       done_o,
    output logic       bus_owned_o,
    output logic       bus_free_o,
    output logic       nack_error_o,
    output logic       arbitration_lost_o,
    output logic       timeout_error_o,
    output logic       bus_busy_error_o,
    output logic       rx_overflow_o,
    output logic       cmd_overflow_o,
    output logic       illegal_cmd_o,
    output logic       recovery_failed_o
);

    localparam logic [2:0] CMD_WRITE   = 3'd0;
    localparam logic [2:0] CMD_READ    = 3'd1;
    localparam logic [2:0] CMD_RECOVER = 3'd2;

    typedef enum logic [3:0] {
        ST_IDLE,
        ST_LAUNCH,
        ST_WAIT_BYTE,
        ST_REC_LOW,
        ST_REC_WAIT_HIGH,
        ST_REC_HIGH,
        ST_REC_STOP_LOW,
        ST_REC_STOP_WAIT_HIGH,
        ST_REC_STOP_RELEASE
    } state_t;

    localparam int CMD_AW = $clog2(CMD_FIFO_DEPTH);
    localparam int RX_AW  = $clog2(RX_FIFO_DEPTH);
    localparam logic [31:0] SCL_LOW_LAST  = SCL_LOW_CYCLES - 1;
    localparam logic [31:0] SCL_HIGH_LAST = SCL_HIGH_CYCLES - 1;
    localparam logic [31:0] STRETCH_LAST  = STRETCH_TIMEOUT_CYCLES - 1;

    state_t state_q;

    (* syn_ramstyle = "registers", ram_style = "registers" *) logic [2:0] cmd_op_fifo      [CMD_FIFO_DEPTH];
    (* syn_ramstyle = "registers", ram_style = "registers" *) logic       cmd_start_fifo   [CMD_FIFO_DEPTH];
    (* syn_ramstyle = "registers", ram_style = "registers" *) logic       cmd_stop_fifo    [CMD_FIFO_DEPTH];
    (* syn_ramstyle = "registers", ram_style = "registers" *) logic       cmd_ack_fifo     [CMD_FIFO_DEPTH];
    (* syn_ramstyle = "registers", ram_style = "registers" *) logic [7:0] cmd_data_fifo    [CMD_FIFO_DEPTH];
    logic [CMD_AW-1:0] cmd_wr_ptr_q;
    logic [CMD_AW-1:0] cmd_rd_ptr_q;
    logic [CMD_AW:0]   cmd_count_q;

    (* syn_ramstyle = "registers", ram_style = "registers" *) logic [7:0] rx_fifo [RX_FIFO_DEPTH];
    logic [RX_AW-1:0] rx_wr_ptr_q;
    logic [RX_AW-1:0] rx_rd_ptr_q;
    logic [RX_AW:0]   rx_count_q;
    logic [7:0]       rx_data_q;

    logic [2:0] cur_op_q;
    logic       cur_start_q;
    logic       cur_stop_q;
    logic       cur_ack_q;
    logic [7:0] cur_data_q;

    logic byte_start_q;
    logic byte_busy;
    logic byte_done;
    logic byte_sda_drive_low;
    logic byte_scl_drive_low;
    logic [7:0] byte_rx_data;
    logic byte_rx_valid;
    logic byte_nack;
    logic byte_arbitration_lost;
    logic byte_timeout;

    logic recovery_sda_drive_low_q;
    logic recovery_scl_drive_low_q;
    logic [3:0] recovery_pulse_q;
    logic [31:0] phase_cnt_q;
    logic [31:0] stretch_cnt_q;
    logic bus_owned_q;

    logic cmd_push;
    logic rx_push;
    logic rx_pop;

    assign cmd_ready_o = cmd_count_q != CMD_FIFO_DEPTH[CMD_AW:0];
    assign cmd_push    = cmd_valid_i && cmd_ready_o;
    assign rx_valid_o  = rx_count_q != '0;
    assign rx_data_o   = rx_data_q;
    assign rx_pop      = rx_pop_i && rx_valid_o;
    assign rx_push     = byte_rx_valid && (rx_count_q != RX_FIFO_DEPTH[RX_AW:0]);

    assign sda_io = (byte_sda_drive_low || recovery_sda_drive_low_q) ? 1'b0 : 1'bz;
    assign scl_io = (byte_scl_drive_low || recovery_scl_drive_low_q) ? 1'b0 : 1'bz;

    assign busy_o      = state_q != ST_IDLE;
    assign bus_owned_o = bus_owned_q;
    assign bus_free_o  = (sda_io == 1'b1) && (scl_io == 1'b1);

    i2c_byte_master_timed #(
        .SCL_LOW_CYCLES(SCL_LOW_CYCLES),
        .SCL_HIGH_CYCLES(SCL_HIGH_CYCLES),
        .STRETCH_TIMEOUT_CYCLES(STRETCH_TIMEOUT_CYCLES)
    ) byte_master (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .start_i(byte_start_q),
        .start_en_i(cur_start_q),
        .stop_en_i(cur_stop_q),
        .read_i(cur_op_q == CMD_READ),
        .rx_ack_i(cur_ack_q),
        .tx_byte_i(cur_data_q),
        .sda_i(sda_io),
        .scl_i(scl_io),
        .busy_o(byte_busy),
        .done_o(byte_done),
        .sda_drive_low_o(byte_sda_drive_low),
        .scl_drive_low_o(byte_scl_drive_low),
        .rx_byte_o(byte_rx_data),
        .rx_valid_o(byte_rx_valid),
        .nack_error_o(byte_nack),
        .arbitration_lost_o(byte_arbitration_lost),
        .timeout_error_o(byte_timeout)
    );

    always_ff @(posedge clk_i) begin
        if(rst_i) begin
            state_q                    <= ST_IDLE;
            cmd_wr_ptr_q               <= '0;
            cmd_rd_ptr_q               <= '0;
            cmd_count_q                <= '0;
            rx_wr_ptr_q                <= '0;
            rx_rd_ptr_q                <= '0;
            rx_count_q                 <= '0;
            rx_data_q                  <= 8'd0;
            cur_op_q                   <= CMD_WRITE;
            cur_start_q                <= 1'b0;
            cur_stop_q                 <= 1'b0;
            cur_ack_q                  <= 1'b0;
            cur_data_q                 <= 8'd0;
            byte_start_q               <= 1'b0;
            recovery_sda_drive_low_q   <= 1'b0;
            recovery_scl_drive_low_q   <= 1'b0;
            recovery_pulse_q           <= 4'd0;
            phase_cnt_q                <= 32'd0;
            stretch_cnt_q              <= 32'd0;
            bus_owned_q                <= 1'b0;
            done_o                     <= 1'b0;
            nack_error_o               <= 1'b0;
            arbitration_lost_o         <= 1'b0;
            timeout_error_o            <= 1'b0;
            bus_busy_error_o           <= 1'b0;
            rx_overflow_o              <= 1'b0;
            cmd_overflow_o             <= 1'b0;
            illegal_cmd_o              <= 1'b0;
            recovery_failed_o          <= 1'b0;
        end else begin
            done_o       <= 1'b0;
            byte_start_q <= 1'b0;

            if(clear_errors_i) begin
                nack_error_o       <= 1'b0;
                arbitration_lost_o <= 1'b0;
                timeout_error_o    <= 1'b0;
                bus_busy_error_o   <= 1'b0;
                rx_overflow_o      <= 1'b0;
                cmd_overflow_o     <= 1'b0;
                illegal_cmd_o      <= 1'b0;
                recovery_failed_o  <= 1'b0;
                done_o             <= 1'b0;
            end

            if(cmd_valid_i && !cmd_ready_o) begin
                cmd_overflow_o <= 1'b1;
            end

            if(cmd_push) begin
                cmd_op_fifo[cmd_wr_ptr_q]    <= cmd_op_i;
                cmd_start_fifo[cmd_wr_ptr_q] <= cmd_start_i;
                cmd_stop_fifo[cmd_wr_ptr_q]  <= cmd_stop_i;
                cmd_ack_fifo[cmd_wr_ptr_q]   <= cmd_ack_i;
                cmd_data_fifo[cmd_wr_ptr_q]  <= cmd_data_i;
                cmd_wr_ptr_q                 <= cmd_wr_ptr_q + 1'b1;
                cmd_count_q                  <= cmd_count_q + 1'b1;
            end

            if(rx_pop) begin
                rx_rd_ptr_q <= rx_rd_ptr_q + 1'b1;
            end

            if(byte_rx_valid && (rx_count_q == RX_FIFO_DEPTH[RX_AW:0])) begin
                rx_overflow_o <= 1'b1;
            end

            unique case({rx_push, rx_pop})
                2'b10: begin
                    rx_fifo[rx_wr_ptr_q] <= byte_rx_data;
                    if(rx_count_q == '0) begin
                        rx_data_q <= byte_rx_data;
                    end
                    rx_wr_ptr_q          <= rx_wr_ptr_q + 1'b1;
                    rx_count_q           <= rx_count_q + 1'b1;
                end
                2'b01: begin
                    if(rx_count_q > {{RX_AW{1'b0}}, 1'b1}) begin
                        rx_data_q <= rx_fifo[rx_rd_ptr_q + 1'b1];
                    end
                    rx_count_q <= rx_count_q - 1'b1;
                end
                2'b11: begin
                    rx_fifo[rx_wr_ptr_q] <= byte_rx_data;
                    rx_wr_ptr_q          <= rx_wr_ptr_q + 1'b1;
                    rx_rd_ptr_q          <= rx_rd_ptr_q + 1'b1;
                    rx_data_q            <= (rx_count_q == {{RX_AW{1'b0}}, 1'b1}) ?
                                            byte_rx_data : rx_fifo[rx_rd_ptr_q + 1'b1];
                end
                default: ;
            endcase

            case(state_q)
                ST_IDLE: begin
                    recovery_sda_drive_low_q <= 1'b0;
                    recovery_scl_drive_low_q <= 1'b0;
                    phase_cnt_q              <= 32'd0;
                    stretch_cnt_q            <= 32'd0;

                    if(cmd_count_q != '0) begin
                        cur_op_q    <= cmd_op_fifo[cmd_rd_ptr_q];
                        cur_start_q <= cmd_start_fifo[cmd_rd_ptr_q];
                        cur_stop_q  <= cmd_stop_fifo[cmd_rd_ptr_q];
                        cur_ack_q   <= cmd_ack_fifo[cmd_rd_ptr_q];
                        cur_data_q  <= cmd_data_fifo[cmd_rd_ptr_q];
                        cmd_rd_ptr_q <= cmd_rd_ptr_q + 1'b1;
                        cmd_count_q  <= cmd_push ? cmd_count_q : (cmd_count_q - 1'b1);

                        if(cmd_op_fifo[cmd_rd_ptr_q] == CMD_RECOVER) begin
                            recovery_pulse_q         <= 4'd0;
                            recovery_sda_drive_low_q <= 1'b0;
                            recovery_scl_drive_low_q <= 1'b1;
                            state_q                  <= ST_REC_LOW;
                        end else if((cmd_op_fifo[cmd_rd_ptr_q] != CMD_WRITE) &&
                                    (cmd_op_fifo[cmd_rd_ptr_q] != CMD_READ)) begin
                            illegal_cmd_o <= 1'b1;
                            done_o        <= 1'b1;
                        end else if(cmd_start_fifo[cmd_rd_ptr_q] && !bus_owned_q && !bus_free_o) begin
                            bus_busy_error_o <= 1'b1;
                            done_o           <= 1'b1;
                        end else begin
                            state_q <= ST_LAUNCH;
                        end
                    end
                end

                ST_LAUNCH: begin
                    byte_start_q <= 1'b1;
                    if(byte_busy) begin
                        state_q <= ST_WAIT_BYTE;
                    end
                end

                ST_WAIT_BYTE: begin
                    if(byte_busy) begin
                        byte_start_q <= 1'b0;
                    end

                    if(byte_done) begin
                        if(byte_nack) begin
                            nack_error_o <= 1'b1;
                        end
                        if(byte_arbitration_lost) begin
                            arbitration_lost_o <= 1'b1;
                            bus_owned_q        <= 1'b0;
                        end else if(byte_timeout) begin
                            timeout_error_o <= 1'b1;
                            bus_owned_q     <= 1'b0;
                        end else if(cur_stop_q) begin
                            bus_owned_q <= 1'b0;
                        end else begin
                            bus_owned_q <= 1'b1;
                        end

                        done_o  <= 1'b1;
                        state_q <= ST_IDLE;
                    end
                end

                ST_REC_LOW: begin
                    recovery_sda_drive_low_q <= 1'b0;
                    recovery_scl_drive_low_q <= 1'b1;
                    if(phase_cnt_q >= SCL_LOW_LAST) begin
                        phase_cnt_q              <= 32'd0;
                        stretch_cnt_q            <= 32'd0;
                        recovery_scl_drive_low_q <= 1'b0;
                        state_q                  <= ST_REC_WAIT_HIGH;
                    end else begin
                        phase_cnt_q <= phase_cnt_q + 32'd1;
                    end
                end

                ST_REC_WAIT_HIGH: begin
                    recovery_sda_drive_low_q <= 1'b0;
                    recovery_scl_drive_low_q <= 1'b0;
                    if(scl_io == 1'b1) begin
                        phase_cnt_q   <= 32'd0;
                        stretch_cnt_q <= 32'd0;
                        state_q       <= ST_REC_HIGH;
                    end else if(stretch_cnt_q >= STRETCH_LAST) begin
                        recovery_failed_o <= 1'b1;
                        bus_owned_q       <= 1'b0;
                        done_o            <= 1'b1;
                        state_q           <= ST_IDLE;
                    end else begin
                        stretch_cnt_q <= stretch_cnt_q + 32'd1;
                    end
                end

                ST_REC_HIGH: begin
                    recovery_sda_drive_low_q <= 1'b0;
                    recovery_scl_drive_low_q <= 1'b0;
                    if(phase_cnt_q >= SCL_HIGH_LAST) begin
                        phase_cnt_q <= 32'd0;
                        if(recovery_pulse_q == 4'd8) begin
                            recovery_sda_drive_low_q <= 1'b1;
                            recovery_scl_drive_low_q <= 1'b1;
                            state_q                  <= ST_REC_STOP_LOW;
                        end else begin
                            recovery_pulse_q         <= recovery_pulse_q + 1'b1;
                            recovery_scl_drive_low_q <= 1'b1;
                            state_q                  <= ST_REC_LOW;
                        end
                    end else begin
                        phase_cnt_q <= phase_cnt_q + 32'd1;
                    end
                end

                ST_REC_STOP_LOW: begin
                    recovery_sda_drive_low_q <= 1'b1;
                    recovery_scl_drive_low_q <= 1'b1;
                    if(phase_cnt_q >= SCL_LOW_LAST) begin
                        phase_cnt_q              <= 32'd0;
                        stretch_cnt_q            <= 32'd0;
                        recovery_scl_drive_low_q <= 1'b0;
                        state_q                  <= ST_REC_STOP_WAIT_HIGH;
                    end else begin
                        phase_cnt_q <= phase_cnt_q + 32'd1;
                    end
                end

                ST_REC_STOP_WAIT_HIGH: begin
                    recovery_sda_drive_low_q <= 1'b1;
                    recovery_scl_drive_low_q <= 1'b0;
                    if(scl_io == 1'b1) begin
                        phase_cnt_q   <= 32'd0;
                        stretch_cnt_q <= 32'd0;
                        state_q       <= ST_REC_STOP_RELEASE;
                    end else if(stretch_cnt_q >= STRETCH_LAST) begin
                        recovery_failed_o <= 1'b1;
                        done_o            <= 1'b1;
                        state_q           <= ST_IDLE;
                    end else begin
                        stretch_cnt_q <= stretch_cnt_q + 32'd1;
                    end
                end

                ST_REC_STOP_RELEASE: begin
                    recovery_sda_drive_low_q <= 1'b0;
                    recovery_scl_drive_low_q <= 1'b0;
                    if(phase_cnt_q >= SCL_HIGH_LAST) begin
                        phase_cnt_q <= 32'd0;
                        bus_owned_q <= 1'b0;
                        done_o      <= 1'b1;
                        state_q     <= ST_IDLE;
                    end else begin
                        phase_cnt_q <= phase_cnt_q + 32'd1;
                    end
                end

                default: begin
                    state_q <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
