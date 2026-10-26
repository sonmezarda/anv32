module i2c_periph
    import anv32_bus_pkg::*;
    import anv32_i2c_regs_pkg::*;
#(
    parameter int CLK_FREQ               = 27_000_000,
    parameter int CMD_FIFO_DEPTH         = 16,
    parameter int RX_FIFO_DEPTH          = 8,
    parameter int SCL_LOW_CYCLES         = CLK_FREQ / 200_000,
    parameter int SCL_HIGH_CYCLES        = CLK_FREQ / 200_000,
    parameter int STRETCH_TIMEOUT_CYCLES = CLK_FREQ / 100
)(
    input  logic        clk_i,
    input  logic        rst_i,

    input  bus_req_t    req_i,
    output bus_rsp_t    rsp_o,

    inout  logic        sda_io,
    inout  logic        scl_io,

    output logic        irq_o
);

    localparam logic [4:0] CMD_ADDR    = I2C_CMD_OFFSET[4:0];
    localparam logic [4:0] STATUS_ADDR = I2C_STATUS_OFFSET[4:0];
    localparam logic [4:0] RXDATA_ADDR = I2C_RXDATA_OFFSET[4:0];
    localparam logic [4:0] CTRL_ADDR   = I2C_CTRL_OFFSET[4:0];

    // Bus side: the registers sit at the start of the 4 KiB slot; the rest of
    // the slot, including the alias ranges, reads as zero and ignores writes.
    logic        in_regs;
    logic        sel;
    logic        write;
    logic        read;
    logic [4:0]  addr;
    logic [31:0] wdata;
    logic [31:0] rdata;
    logic [31:0] rdata_q;

    assign in_regs = req_i.addr[11:5] == '0;
    assign sel     = req_i.valid && in_regs;
    assign write   = sel && (req_i.we != 4'b0000);
    assign read    = sel && (req_i.we == 4'b0000);
    assign addr    = req_i.addr[4:0];
    assign wdata   = req_i.wdata;

    // Read data is registered: it appears the cycle after the access
    always_ff @(posedge clk_i) begin
        if (rst_i)            rdata_q <= '0;
        else if (req_i.valid) rdata_q <= in_regs ? rdata : '0;
    end

    assign rsp_o.ready = 1'b1;
    assign rsp_o.rdata = rdata_q;

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

    assign cmd_valid    = sel && write && (addr == CMD_ADDR);
    assign cmd_op       = wdata[2:0];
    assign cmd_start    = wdata[I2C_CMD_START_BIT];
    assign cmd_stop     = wdata[I2C_CMD_STOP_BIT];
    assign cmd_ack      = wdata[I2C_CMD_ACK_BIT];
    assign cmd_data     = wdata[I2C_CMD_DATA_LSB +: 8];
    assign rx_pop       = sel && read && (addr == RXDATA_ADDR);
    assign clear_errors = sel && write && (addr == CTRL_ADDR) && wdata[I2C_CTRL_CLEAR_BIT];
    assign irq_o        = irq_en_q && done_pending_q;

    always_comb begin
        unique case(addr)
            CMD_ADDR: begin
                rdata = 32'b0;
            end
            STATUS_ADDR: begin
                rdata = 32'b0;
                rdata[I2C_STATUS_BUSY_BIT]      = busy;
                rdata[I2C_STATUS_CMD_READY_BIT] = cmd_ready;
                rdata[I2C_STATUS_RX_VALID_BIT]  = rx_valid;
                rdata[I2C_STATUS_DONE_BIT]      = done_pending_q;
                rdata[I2C_STATUS_BUS_OWNED_BIT] = bus_owned;
                rdata[I2C_STATUS_BUS_FREE_BIT]  = bus_free;
                rdata[I2C_STATUS_SDA_BIT]       = sda_io;
                rdata[I2C_STATUS_SCL_BIT]       = scl_io;
                rdata[I2C_STATUS_NACK_BIT]      = nack_error;
                rdata[I2C_STATUS_ARB_LOST_BIT]  = arbitration_lost;
                rdata[I2C_STATUS_TIMEOUT_BIT]   = timeout_error;
                rdata[I2C_STATUS_BUS_BUSY_BIT]  = bus_busy_error;
                rdata[I2C_STATUS_RX_OVF_BIT]    = rx_overflow;
                rdata[I2C_STATUS_CMD_OVF_BIT]   = cmd_overflow;
                rdata[I2C_STATUS_ILLEGAL_BIT]   = illegal_cmd;
                rdata[I2C_STATUS_REC_FAIL_BIT]  = recovery_failed;
            end
            RXDATA_ADDR: begin
                rdata = {24'b0, rx_data};
            end
            CTRL_ADDR: begin
                rdata = 32'b0;
                rdata[I2C_CTRL_IRQ_EN_BIT] = irq_en_q;
            end
            default: begin
                rdata = 32'b0;
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

            if(sel && write && (addr == CTRL_ADDR)) begin
                irq_en_q <= wdata[I2C_CTRL_IRQ_EN_BIT];
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
