module anv32_alu
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
(
    input  alu_op_e         op_i,
    input  logic [XLEN-1:0] a_i,
    input  logic [XLEN-1:0] b_i,
    output logic [XLEN-1:0] result_o
);
    logic [4:0] shamt;
    assign shamt = b_i[4:0];   // SLLI'de b=imm[4:0], SLL'de b=rs2[4:0] — ikisi de doğru

    always_comb begin
        unique case (op_i)
            ALU_ADD:  result_o = a_i + b_i;
            ALU_SUB:  result_o = a_i - b_i;
            ALU_SLL:  result_o = a_i << shamt;
            ALU_SLT:  result_o = ($signed(a_i) <  $signed(b_i)) ? 32'd1 : 32'd0;
            ALU_SLTU: result_o = (a_i < b_i) ? 32'd1 : 32'd0;
            ALU_XOR:  result_o = a_i ^ b_i;
            ALU_SRL:  result_o = a_i >> shamt;
            ALU_SRA:  result_o = $signed(a_i) >>> shamt;
            ALU_OR:   result_o = a_i | b_i;
            ALU_AND:  result_o = a_i & b_i;
            default:  result_o = '0;
        endcase
    end
endmodule