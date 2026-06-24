module tb_mul_unit;

    logic clk, rst;
    logic [31:0] a, b;
    logic [63:0] result;

    anv32_multiply_unit dut(
        .clk_i(clk),
        .rst_i(rst),
        .a_i(a),
        .b_i(b),
        .result_o(result)
    );

    always begin
        #5 clk = ~clk; 
    end

    initial begin
        rst = 0;
        a = '0;
        b = '0;
        #1;
        $display("RES=%h", result);

        @(posedge clk) #1;

        a = 32'h4;
        b = 32'h2;
        @(posedge clk) #1;
        $display("RES=%h", result);
        
        $finish;
    end
endmodule
