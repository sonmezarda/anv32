module i2c_periph #(
    parameter int CLK_FREQ               = 27_000_000,
    parameter int CMD_FIFO_DEPTH         = 16,
    parameter int RX_FIFO_DEPTH          = 8,
    parameter int SCL_LOW_CYCLES         = CLK_FREQ / 200_000,
    parameter int SCL_HIGH_CYCLES        = CLK_FREQ / 200_000,
    parameter int STRETCH_TIMEOUT_CYCLES = CLK_FREQ / 100
)(
    input  logic        clk_i,
    input  logic        rst_i,

    input  logic        sel_i,
    input  logic        write_i,
    input  logic        read_i,
    input  logic [4:0]  addr_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,

    inout  logic        sda_io,
    inout  logic        scl_io,

    output logic        irq_o
);

    localparam logic [4:0] CMD_ADDR    = 5'h00;
    localparam logic [4:0] STATUS_ADDR = 5'h04;
    localparam logic [4:0] RXDATA_ADDR = 5'h08;
    localparam logic [4:0] CTRL_ADDR   = 5'h0c;

    logic       cmd_valid;
    logic       cmd_ready;
    logic [2:0] cmd_op;
    logic       cmd_start;
    logic       cmd_stop;
    logic       cmd_ack;
    logic [7:0] cmd_data;
    logic       rx_valid;
    logic       rx_pop;
    logic [7:0] rx_data;
    logic       clear_errors;
    logic       busy;
    logic       done;
    logic       done_pending_q;
    logic       bus_owned;
    logic       bus_free;
    logic       nack_error;
    logic       arbitration_lost;
    logic       timeout_error;
    logic       bus_busy_error;
    logic       rx_overflow;
    logic       cmd_overflow;
    logic       illegal_cmd;
    logic       recovery_failed;
    logic       irq_en_q;

    assign cmd_valid    = sel_i && write_i && (addr_i == CMD_ADDR);
    assign cmd_op       = wdata_i[2:0];
    assign cmd_start    = wdata_i[3];
    assign cmd_stop     = wdata_i[4];
    assign cmd_ack      = wdata_i[5];
    assign cmd_data     = wdata_i[15:8];
    assign rx_pop       = sel_i && read_i && (addr_i == RXDATA_ADDR);
    assign clear_errors = sel_i && write_i && (addr_i == CTRL_ADDR) && wdata_i[0];
    assign irq_o        = irq_en_q && done_pending_q;

    always_comb begin
        unique case(addr_i)
            CMD_ADDR: begin
                rdata_o = 32'b0;
            end
            STATUS_ADDR: begin
                rdata_o = 32'b0;
                rdata_o[0]  = busy;
                rdata_o[1]  = cmd_ready;
                rdata_o[2]  = rx_valid;
                rdata_o[3]  = done_pending_q;
                rdata_o[4]  = bus_owned;
                rdata_o[5]  = bus_free;
                rdata_o[6]  = sda_io;
                rdata_o[7]  = scl_io;
                rdata_o[16] = nack_error;
                rdata_o[17] = arbitration_lost;
                rdata_o[18] = timeout_error;
                rdata_o[19] = bus_busy_error;
                rdata_o[20] = rx_overflow;
                rdata_o[21] = cmd_overflow;
                rdata_o[22] = illegal_cmd;
                rdata_o[23] = recovery_failed;
            end
            RXDATA_ADDR: begin
                rdata_o = {24'b0, rx_data};
            end
            CTRL_ADDR: begin
                rdata_o = {31'b0, irq_en_q};
            end
            default: begin
                rdata_o = 32'b0;
            end
        endcase
    end

    always_ff @(posedge clk_i) begin
        if(rst_i) begin
            done_pending_q <= 1'b0;
            irq_en_q       <= 1'b0;
        end else begin
            if(done) begin
                done_pending_q <= 1'b1;
            end

            if(clear_errors || cmd_valid) begin
                done_pending_q <= 1'b0;
            end

            if(sel_i && write_i && (addr_i == CTRL_ADDR)) begin
                irq_en_q <= wdata_i[1];
            end
        end
    end

    i2c_cmd_master_timed #(
        .CMD_FIFO_DEPTH(CMD_FIFO_DEPTH),
        .RX_FIFO_DEPTH(RX_FIFO_DEPTH),
        .SCL_LOW_CYCLES(SCL_LOW_CYCLES),
        .SCL_HIGH_CYCLES(SCL_HIGH_CYCLES),
        .STRETCH_TIMEOUT_CYCLES(STRETCH_TIMEOUT_CYCLES)
    ) cmd_master (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .cmd_valid_i(cmd_valid),
        .cmd_ready_o(cmd_ready),
        .cmd_op_i(cmd_op),
        .cmd_start_i(cmd_start),
        .cmd_stop_i(cmd_stop),
        .cmd_ack_i(cmd_ack),
        .cmd_data_i(cmd_data),
        .rx_valid_o(rx_valid),
        .rx_pop_i(rx_pop),
        .rx_data_o(rx_data),
        .clear_errors_i(clear_errors),
        .sda_io(sda_io),
        .scl_io(scl_io),
        .busy_o(busy),
        .done_o(done),
        .bus_owned_o(bus_owned),
        .bus_free_o(bus_free),
        .nack_error_o(nack_error),
        .arbitration_lost_o(arbitration_lost),
        .timeout_error_o(timeout_error),
        .bus_busy_error_o(bus_busy_error),
        .rx_overflow_o(rx_overflow),
        .cmd_overflow_o(cmd_overflow),
        .illegal_cmd_o(illegal_cmd),
        .recovery_failed_o(recovery_failed)
    );

endmodule
