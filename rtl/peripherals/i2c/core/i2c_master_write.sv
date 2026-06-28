module i2c_master_write(
    input  logic       clk_i,
    input  logic       rst_i,
    input  logic       start_i,
    input  logic       scl_tick_i,
    input  logic [6:0] slave_addr_i,
    input  logic       read_write_sel_i,
    input  logic [7:0] tx_data_i,
    inout  logic       sda_io,
    inout  logic       scl_io,

    output logic       busy_o,
    output logic       done_o,
    output logic       nack_error_o,
    output logic       arbitration_lost_o
);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_ADDR_WAIT,
        ST_DATA_WAIT,
        ST_DONE
    } state_t;

    state_t     state_q;
    logic       byte_start;
    logic       byte_start_en;
    logic       byte_stop_en;
    logic [7:0] byte_tx;
    logic       byte_busy;
    logic       byte_done;
    logic       byte_nack;
    logic       byte_arbitration_lost;

    assign busy_o       = state_q != ST_IDLE;
    assign nack_error_o = byte_nack;
    assign arbitration_lost_o = byte_arbitration_lost;

    i2c_byte_master byte_master (
        .clk_i        (clk_i),
        .rst_i        (rst_i),
        .start_i      (byte_start),
        .scl_tick_i   (scl_tick_i),
        .start_en_i   (byte_start_en),
        .stop_en_i    (byte_stop_en),
        .tx_byte_i    (byte_tx),
        .sda_io       (sda_io),
        .scl_io       (scl_io),
        .busy_o       (byte_busy),
        .done_o       (byte_done),
        .nack_error_o (byte_nack),
        .arbitration_lost_o(byte_arbitration_lost)
    );

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q       <= ST_IDLE;
            byte_start    <= 1'b0;
            byte_start_en <= 1'b0;
            byte_stop_en  <= 1'b0;
            byte_tx       <= 8'd0;
            done_o        <= 1'b0;
        end else begin
            done_o <= 1'b0;

            case (state_q)
                ST_IDLE: begin
                    byte_start <= 1'b0;
                    if (start_i) begin
                        byte_tx       <= {slave_addr_i, read_write_sel_i};
                        byte_start_en <= 1'b1;
                        byte_stop_en  <= 1'b0;
                        byte_start    <= 1'b1;
                        state_q       <= ST_ADDR_WAIT;
                    end
                end

                ST_ADDR_WAIT: begin
                    if (byte_busy) begin
                        byte_start <= 1'b0;
                    end
                    if (byte_done) begin
                        if (byte_nack || byte_arbitration_lost) begin
                            done_o  <= 1'b1;
                            state_q <= ST_DONE;
                        end else begin
                            byte_tx       <= tx_data_i;
                            byte_start_en <= 1'b0;
                            byte_stop_en  <= 1'b1;
                            byte_start    <= 1'b1;
                            state_q       <= ST_DATA_WAIT;
                        end
                    end
                end

                ST_DATA_WAIT: begin
                    if (byte_busy) begin
                        byte_start <= 1'b0;
                    end
                    if (byte_done) begin
                        done_o  <= 1'b1;
                        state_q <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    byte_start <= 1'b0;
                    state_q <= ST_IDLE;
                end

                default: begin
                    byte_start <= 1'b0;
                    state_q <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
