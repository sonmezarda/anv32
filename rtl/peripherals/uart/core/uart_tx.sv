module uart_tx 
#(
    parameter logic IDLE_STATE_BIT = 1'b1,
    parameter logic STOP_BIT       = 1'b1,
    parameter logic START_BIT      = 1'b0
)(
    input  logic       clk_i,
    input  logic       baud_tick_i,
    input  logic       rst_i,

    input  logic [7:0] data_i,
    input  logic       start_i,

    output logic       done_o,
    output logic       tx_o,
    output logic       busy_o,
    output logic       ready_o
);

    typedef enum logic [1:0]{
        ST_IDLE, ST_DATA, ST_STOP
    } state_t;

    state_t state_q;
    logic [2:0] bit_idx;
    logic [7:0] data_reg;
    logic       start_pending;
    logic       stop_active;

    assign ready_o = !rst_i && (state_q == ST_IDLE) && !start_pending && !busy_o;

    always_ff @(posedge clk_i) begin
        if(rst_i) begin
            state_q          <= ST_IDLE;
            data_reg         <= 8'b0;
            busy_o           <= 1'b0;
            tx_o             <= IDLE_STATE_BIT;
            done_o           <= 1'b0;
            bit_idx          <= 3'd0;
            start_pending    <= 1'b0;
            stop_active      <= 1'b0;
        end else begin
            done_o <= 1'b0;
            if (start_i && ready_o) begin
                data_reg      <= data_i;
                start_pending <= 1'b1;
                busy_o        <= 1'b1;
            end
            
            if(baud_tick_i) begin
                case(state_q) 
                    
                    ST_IDLE: begin
                        if(start_pending) begin
                            state_q          <= ST_DATA;
                            bit_idx          <= 3'd0;
                            tx_o             <= START_BIT;
                            done_o           <= 1'b0;
                            start_pending    <= 1'b0;
                            stop_active      <= 1'b0;
                        end else begin
                            state_q <= ST_IDLE;
                        end
                    end
                    
                    ST_DATA: begin
                        tx_o <= data_reg[bit_idx];   
                        if(bit_idx == 3'd7) begin // still in progress
                            state_q <= ST_STOP;       
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end

                    ST_STOP: begin
                        tx_o <= STOP_BIT;
                        if (!stop_active) begin
                            stop_active <= 1'b1;
                        end else begin
                            stop_active <= 1'b0;
                            busy_o      <= 1'b0;
                            done_o      <= 1'b1;
                            state_q     <= ST_IDLE;
                        end
                    end

                    default: begin
                        state_q     <= ST_IDLE;
                        tx_o        <= IDLE_STATE_BIT;
                        busy_o      <= 1'b0;
                        stop_active <= 1'b0;
                    end
                endcase
            end
        end
    end
endmodule
