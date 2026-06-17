module alu
    import anv32_config_pkg::*;
(
    input  operation_e      op_i,
    input  logic [XLEN-1:0] rs1_i,
    input  logic [XLEN-1:0] rs2_i,
    input  logic [XLEN-1:0] imm_i,
    input  logic [XLEN-1:0] pc_i,
    output logic [XLEN-1:0] result_o
);
    logic [XLEN-1:0] a, b;
    logic [4:0]      shamt;

    always_comb begin
        a = rs1_i;
        unique case (op_i)
            ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI: b = imm_i;
            default:                                              b = rs2_i;
        endcase
        shamt = b[4:0];

        unique case (op_i)
            LUI:          result_o = imm_i;
            AUIPC:        result_o = pc_i + imm_i;
            ADDI, ADD:    result_o = a + b;
            SUB:          result_o = a - b;
            SLTI,  SLT:   result_o = ($signed(a) <  $signed(b)) ? 32'd1 : 32'd0;
            SLTIU, SLTU:  result_o = (a < b) ? 32'd1 : 32'd0;
            XORI,  XOR:   result_o = a ^ b;
            ORI,   OR:    result_o = a | b;
            ANDI,  AND:   result_o = a & b;
            SLLI,  SLL:   result_o = a << shamt;
            SRLI,  SRL:   result_o = a >> shamt;
            SRAI,  SRA:   result_o = $signed(a) >>> shamt;
            default:      result_o = '0;
        endcase
    end
endmodule

