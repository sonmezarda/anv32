module i2c_lcd_text_test_top #(
    parameter int CLK_FREQ           = 27_000_000,
    parameter int SCL_HALF_PERIOD    = CLK_FREQ / 200_000,
    parameter int POWER_WAIT_CYCLES  = CLK_FREQ / 20,
    parameter logic [6:0] LCD_ADDR    = 7'h27
)(
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic gpio_irq_i,
    input  logic uart_rx_i,
    inout  logic i2c_sda_io,
    inout  logic i2c_scl_io,
    output logic uart_tx_o,
    output logic [3:0] debug_leds
);

    typedef enum logic [2:0] {
        ST_POWER_WAIT,
        ST_START_WRITE,
        ST_WAIT_WRITE,
        ST_DELAY,
        ST_DONE,
        ST_ERROR
    } state_t;

    localparam logic [5:0] INIT_OPS = 6'd10;
    localparam logic [5:0] MSG_LEN  = 6'd12;
    localparam logic [5:0] OP_COUNT = INIT_OPS + MSG_LEN;

    logic        rst_i;
    logic [31:0] scl_div_cnt_q;
    logic        scl_tick;
    state_t      state_q;
    logic [31:0] delay_cnt_q;
    logic [5:0]  op_idx_q;
    logic [1:0]  phase_idx_q;
    logic        write_start_q;
    logic [7:0]  write_data_q;
    logic        i2c_busy;
    logic        i2c_done;
    logic        i2c_nack;
    logic        heartbeat_q;
    logic [23:0] heartbeat_cnt_q;

    assign rst_i     = ~rst_n_i;
    assign uart_tx_o = 1'b1;

    function automatic logic [7:0] msg_char(input logic [5:0] idx);
        case(idx)
            6'd0:  msg_char = 8'h41; // A
            6'd1:  msg_char = 8'h4e; // N
            6'd2:  msg_char = 8'h56; // V
            6'd3:  msg_char = 8'h33; // 3
            6'd4:  msg_char = 8'h32; // 2
            6'd5:  msg_char = 8'h20; // space
            6'd6:  msg_char = 8'h49; // I
            6'd7:  msg_char = 8'h32; // 2
            6'd8:  msg_char = 8'h43; // C
            6'd9:  msg_char = 8'h20; // space
            6'd10: msg_char = 8'h4f; // O
            6'd11: msg_char = 8'h4b; // K
            default: msg_char = 8'h20;
        endcase
    endfunction

    function automatic logic [7:0] op_data(input logic [5:0] op_idx);
        if(op_idx >= INIT_OPS) begin
            op_data = msg_char(op_idx - INIT_OPS);
        end else begin
            case(op_idx)
                6'd0: op_data = 8'h03;
                6'd1: op_data = 8'h03;
                6'd2: op_data = 8'h03;
                6'd3: op_data = 8'h02;
                6'd4: op_data = 8'h28;
                6'd5: op_data = 8'h08;
                6'd6: op_data = 8'h01;
                6'd7: op_data = 8'h06;
                6'd8: op_data = 8'h0c;
                6'd9: op_data = 8'h80;
                default: op_data = 8'h00;
            endcase
        end
    endfunction

    function automatic logic op_rs(input logic [5:0] op_idx);
        op_rs = (op_idx >= INIT_OPS);
    endfunction

    function automatic logic op_nibble_only(input logic [5:0] op_idx);
        op_nibble_only = (op_idx < 6'd4);
    endfunction

    function automatic logic [1:0] op_last_phase(input logic [5:0] op_idx);
        op_last_phase = op_nibble_only(op_idx) ? 2'd1 : 2'd3;
    endfunction

    function automatic logic [31:0] op_delay_cycles(input logic [5:0] op_idx);
        case(op_idx)
            6'd0: op_delay_cycles = CLK_FREQ / 200;   // 5 ms
            6'd1: op_delay_cycles = CLK_FREQ / 5000;  // 200 us
            6'd2: op_delay_cycles = CLK_FREQ / 5000;  // 200 us
            6'd3: op_delay_cycles = CLK_FREQ / 5000;  // 200 us
            6'd6: op_delay_cycles = CLK_FREQ / 500;   // 2 ms after clear
            default: op_delay_cycles = CLK_FREQ / 20000; // 50 us
        endcase
    endfunction

    function automatic logic [7:0] pcf_byte(
        input logic [7:0] lcd_data,
        input logic       rs,
        input logic [1:0] phase_idx,
        input logic       nibble_only
    );
        logic [3:0] nibble;
        logic       enable;
        begin
            if(nibble_only || (phase_idx < 2'd2)) begin
                nibble = lcd_data[7:4];
            end else begin
                nibble = lcd_data[3:0];
            end

            if(nibble_only) begin
                nibble = lcd_data[3:0];
            end

            enable   = ~phase_idx[0];
            pcf_byte = {nibble, 1'b1, enable, 1'b0, rs};
        end
    endfunction

    always_ff @(posedge clk_i) begin
        if(rst_i) begin
            scl_div_cnt_q <= 32'd0;
            scl_tick      <= 1'b0;
        end else begin
            if(scl_div_cnt_q == (SCL_HALF_PERIOD - 1)) begin
                scl_div_cnt_q <= 32'd0;
                scl_tick      <= 1'b1;
            end else begin
                scl_div_cnt_q <= scl_div_cnt_q + 32'd1;
                scl_tick      <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if(rst_i) begin
            state_q         <= ST_POWER_WAIT;
            delay_cnt_q     <= POWER_WAIT_CYCLES;
            op_idx_q        <= 6'd0;
            phase_idx_q     <= 2'd0;
            write_start_q   <= 1'b0;
            write_data_q    <= 8'd0;
            heartbeat_q     <= 1'b0;
            heartbeat_cnt_q <= 24'd0;
        end else begin
            heartbeat_cnt_q <= heartbeat_cnt_q + 24'd1;
            if(heartbeat_cnt_q == 24'd0) begin
                heartbeat_q <= ~heartbeat_q;
            end

            case(state_q)
                ST_POWER_WAIT: begin
                    write_start_q <= 1'b0;
                    if(delay_cnt_q == 32'd0) begin
                        state_q <= ST_START_WRITE;
                    end else begin
                        delay_cnt_q <= delay_cnt_q - 32'd1;
                    end
                end

                ST_START_WRITE: begin
                    if(!i2c_busy) begin
                        write_data_q <= pcf_byte(
                            op_data(op_idx_q),
                            op_rs(op_idx_q),
                            phase_idx_q,
                            op_nibble_only(op_idx_q)
                        );
                        write_start_q <= 1'b1;
                    end

                    if(i2c_busy) begin
                        write_start_q <= 1'b0;
                        state_q       <= ST_WAIT_WRITE;
                    end
                end

                ST_WAIT_WRITE: begin
                    write_start_q <= 1'b0;
                    if(i2c_done) begin
                        if(i2c_nack) begin
                            state_q <= ST_ERROR;
                        end else if(phase_idx_q == op_last_phase(op_idx_q)) begin
                            phase_idx_q <= 2'd0;
                            delay_cnt_q <= op_delay_cycles(op_idx_q);
                            state_q     <= ST_DELAY;
                        end else begin
                            phase_idx_q <= phase_idx_q + 2'd1;
                            state_q     <= ST_START_WRITE;
                        end
                    end
                end

                ST_DELAY: begin
                    if(delay_cnt_q == 32'd0) begin
                        if(op_idx_q == (OP_COUNT - 6'd1)) begin
                            state_q <= ST_DONE;
                        end else begin
                            op_idx_q <= op_idx_q + 6'd1;
                            state_q  <= ST_START_WRITE;
                        end
                    end else begin
                        delay_cnt_q <= delay_cnt_q - 32'd1;
                    end
                end

                ST_DONE: begin
                    write_start_q <= 1'b0;
                end

                ST_ERROR: begin
                    write_start_q <= 1'b0;
                end

                default: begin
                    state_q       <= ST_POWER_WAIT;
                    delay_cnt_q   <= POWER_WAIT_CYCLES;
                    write_start_q <= 1'b0;
                end
            endcase
        end
    end

    i2c_master_write u_i2c_master_write(
        .clk_i(clk_i),
        .rst_i(rst_i),
        .start_i(write_start_q),
        .scl_tick_i(scl_tick),
        .slave_addr_i(LCD_ADDR),
        .read_write_sel_i(1'b0),
        .tx_data_i(write_data_q),
        .sda_io(i2c_sda_io),
        .scl_io(i2c_scl_io),
        .busy_o(i2c_busy),
        .done_o(i2c_done),
        .nack_error_o(i2c_nack)
    );

    assign debug_leds[0] = ~i2c_busy;
    assign debug_leds[1] = ~(state_q == ST_DONE);
    assign debug_leds[2] = ~(state_q == ST_ERROR);
    assign debug_leds[3] = ~heartbeat_q;

endmodule
