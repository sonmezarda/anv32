module i2c_test(
    input  logic clk_i,
    input  logic rst_i,
    input  logic start_i,
    input  logic scl_tick_i,
    input  logic [6:0] slave_addr_i,
    input  logic read_write_sel_i,
    input  logic [7:0] send_data_i, 
    inout  logic sda_io,
    inout  logic scl_io
);

    typedef enum logic [2:0]{
        ST_IDLE, ST_START, ST_SEND, ST_ACK, ST_STOP
    } state_t;


    logic       sda_drive_low_q, scl_drive_low_q;
    state_t     state_q;
    logic       scl_phase_q;
    logic       byte_sel_q;
    logic [3:0] bit_idx_q;
    logic [7:0] data_q;

    assign sda_io = sda_reg;

    always_ff @(posedge clk_i) begin
        if(rst_i) begin
            state_q <= ST_IDLE;
        end else begin
            if(scl_tick_i) begin
                case(state_q)
                    ST_IDLE: begin
                        
                    end
                    ST_SEND: begin
                        if(scl_drive_low_q == 1'b1 && scl_phase_q == 1'b0) begin // scl == low && 
                            sda_drive_low_q <= data_q[bit_idx_q];  // set sda to current bit
                            bit_idx_q       <= bit_idx_q + 1'b1;   // set next bit
                            scl_drive_low_q <= 1'b0;
                        end 
                    end
                endcase
            end
        end
        
    end

endmodule
