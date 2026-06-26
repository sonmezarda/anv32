module uart_fifo #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH      = 16
)(
    input  logic                  clk_i,
    input  logic                  rst_i,

    input  logic                  wr_en_i,
    input  logic                  rd_en_i,
    input  logic [DATA_WIDTH-1:0] wdata_i,

    output logic [DATA_WIDTH-1:0] rdata_o,
    output logic                  full_o,
    output logic                  empty_o,
    output logic [$clog2(DEPTH+1)-1:0] level_o
);
    localparam int ADDR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

    logic [DATA_WIDTH-1:0] mem [DEPTH];
    logic [ADDR_W-1:0]    wr_ptr_q;
    logic [ADDR_W-1:0]    rd_ptr_q;
    logic [$clog2(DEPTH+1)-1:0] count_q;
    logic                 wr_fire;
    logic                 rd_fire;

    function automatic logic [ADDR_W-1:0] ptr_next(
        input logic [ADDR_W-1:0] ptr_i
    );
        if (ptr_i == ADDR_W'(DEPTH - 1)) begin
            return '0;
        end
        return ptr_i + {{(ADDR_W-1){1'b0}}, 1'b1};
    endfunction

    assign full_o   = count_q == $clog2(DEPTH+1)'(DEPTH);
    assign empty_o  = count_q == '0;
    assign level_o  = count_q;
    assign rdata_o  = mem[rd_ptr_q];
    assign rd_fire  = rd_en_i && !empty_o;
    assign wr_fire  = wr_en_i && (!full_o || rd_fire);

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            wr_ptr_q <= '0;
            rd_ptr_q <= '0;
            count_q  <= '0;
        end else begin
            if (wr_fire) begin
                mem[wr_ptr_q] <= wdata_i;
                wr_ptr_q      <= ptr_next(wr_ptr_q);
            end

            if (rd_fire) begin
                rd_ptr_q <= ptr_next(rd_ptr_q);
            end

            unique case ({wr_fire, rd_fire})
                2'b10: count_q <= count_q + 1'b1;
                2'b01: count_q <= count_q - 1'b1;
                default: count_q <= count_q;
            endcase
        end
    end

endmodule
