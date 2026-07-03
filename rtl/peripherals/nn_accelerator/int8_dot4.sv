module int8_dot4(
  input  logic               clk_i,
  input  logic               rst_i,
  input  logic               clear_i,
  input  logic               valid_i,
  
  input  logic signed [31:0] activations_i,
  input  logic signed [31:0] weights_i,
  
  output logic signed [31:0] accumulator_o
);
  
  logic signed [7:0]  x [0:3];
  logic signed [7:0]  w [0:3];
  logic signed [15:0] p [0:3];
  logic signed [16:0] s [0:1];
  logic signed [17:0] dot_sum;
  
  genvar i;
  generate
    for(i=0; i<4; i++) begin : gen_products
      assign x[i] = activations_i[i*8 +: 8];
      assign w[i] = weights_i[i*8 +: 8];
      assign p[i] = x[i]*w[i];
    end
  endgenerate
  
  generate
    for(i=0; i<2; i++) begin : gen_pair_sums
      assign s[i] = {{1{p[i*2][15]}}, p[i*2]} + {{1{p[i*2+1][15]}},p[i*2+1]};
    end
  endgenerate
  
  assign dot_sum ={{1{s[0][16]}}, s[0]} + {{1{s[1][16]}}, s[1]};

  always_ff @(posedge clk_i) begin
    if(rst_i || clear_i) begin
    	accumulator_o <= '0;
    end else if (valid_i) begin
    	accumulator_o <= accumulator_o + {{14{dot_sum[17]}}, dot_sum};
    end
  end
  
endmodule
