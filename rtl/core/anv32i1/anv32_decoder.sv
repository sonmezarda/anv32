// ============================================================================
// anv32_decoder.sv
// RV32I decode stage. RAW 32-bit instruction -> dinstr_t.
// ============================================================================
module anv32_decoder
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
(
    input  logic [31:0]     instr_i,   // raw instruction (from memory)
    input  logic [XLEN-1:0] pc_i,      // address of instruction (mem addr)
    input  logic [31:0]     id_i,      // commit-log/diff order no
    output dinstr_t         dinstr_o
);

    logic [6:0] opcode;
    logic [4:0] rd, rs1, rs2;
    logic [2:0] funct3;
    logic [6:0] funct7;

    always_comb begin
        opcode = instr_i[6:0];
        rd     = instr_i[11:7];
        funct3 = instr_i[14:12];
        rs1    = instr_i[19:15];
        rs2    = instr_i[24:20];
        funct7 = instr_i[31:25];

        // --- Default: full 0 ----------
        dinstr_o         = '0;
        dinstr_o.pc      = pc_i;
        dinstr_o.id      = id_i;
        dinstr_o.instr   = instr_i;
        dinstr_o.op      = UNKNOWN;
        dinstr_o.rd_idx  = rd;
        dinstr_o.rs1_idx = rs1;
        dinstr_o.rs2_idx = rs2;

        unique case (opcode)

            // ---- U-type ----------------------------------------------------
            OPC_LUI: begin
                dinstr_o.valid = 1'b1; dinstr_o.op = LUI;
                dinstr_o.rd_valid  = 1'b1;
                dinstr_o.imm_valid = 1'b1; dinstr_o.imm = imm_u_type(instr_i);
            end
            OPC_AUIPC: begin
                dinstr_o.valid = 1'b1; dinstr_o.op = AUIPC;
                dinstr_o.rd_valid  = 1'b1;
                dinstr_o.imm_valid = 1'b1; dinstr_o.imm = imm_u_type(instr_i);
            end

            // ---- Jumps -----------------------------------------------------
            OPC_JAL: begin
                dinstr_o.valid = 1'b1; dinstr_o.op = JAL;
                dinstr_o.rd_valid  = 1'b1;
                dinstr_o.imm_valid = 1'b1; dinstr_o.imm = imm_j_type(instr_i);
            end
            OPC_JALR: begin
                if (funct3 == F3_JALR) begin
                    dinstr_o.valid = 1'b1; dinstr_o.op = JALR;
                    dinstr_o.rd_valid  = 1'b1;
                    dinstr_o.rs1_valid = 1'b1;
                    dinstr_o.imm_valid = 1'b1; dinstr_o.imm = imm_i_type(instr_i);
                end
            end

            // ---- Branches --------------------------------------------------
            OPC_BRANCH: begin
                unique case (funct3)
                    F3_BEQ:  begin dinstr_o.valid = 1'b1; dinstr_o.op = BEQ;  end
                    F3_BNE:  begin dinstr_o.valid = 1'b1; dinstr_o.op = BNE;  end
                    F3_BLT:  begin dinstr_o.valid = 1'b1; dinstr_o.op = BLT;  end
                    F3_BGE:  begin dinstr_o.valid = 1'b1; dinstr_o.op = BGE;  end
                    F3_BLTU: begin dinstr_o.valid = 1'b1; dinstr_o.op = BLTU; end
                    F3_BGEU: begin dinstr_o.valid = 1'b1; dinstr_o.op = BGEU; end
                    default: ; // valid is 0 if illegal
                endcase
                if (dinstr_o.valid) begin
                    dinstr_o.rs1_valid = 1'b1;
                    dinstr_o.rs2_valid = 1'b1;
                    dinstr_o.imm_valid = 1'b1; dinstr_o.imm = imm_b_type(instr_i);
                end
            end

            // ---- Loads -----------------------------------------------------
            OPC_LOAD: begin
                unique case (funct3)
                    F3_LB:  begin dinstr_o.valid = 1'b1; dinstr_o.op = LB;  end
                    F3_LH:  begin dinstr_o.valid = 1'b1; dinstr_o.op = LH;  end
                    F3_LW:  begin dinstr_o.valid = 1'b1; dinstr_o.op = LW;  end
                    F3_LBU: begin dinstr_o.valid = 1'b1; dinstr_o.op = LBU; end
                    F3_LHU: begin dinstr_o.valid = 1'b1; dinstr_o.op = LHU; end
                    default: ;
                endcase
                if (dinstr_o.valid) begin
                    dinstr_o.rd_valid  = 1'b1;
                    dinstr_o.rs1_valid = 1'b1;
                    dinstr_o.imm_valid = 1'b1; dinstr_o.imm = imm_i_type(instr_i);
                end
            end

            // ---- Stores ----------------------------------------------------
            OPC_STORE: begin
                unique case (funct3)
                    F3_SB: begin dinstr_o.valid = 1'b1; dinstr_o.op = SB; end
                    F3_SH: begin dinstr_o.valid = 1'b1; dinstr_o.op = SH; end
                    F3_SW: begin dinstr_o.valid = 1'b1; dinstr_o.op = SW; end
                    default: ;
                endcase
                if (dinstr_o.valid) begin
                    dinstr_o.rs1_valid = 1'b1;
                    dinstr_o.rs2_valid = 1'b1;
                    dinstr_o.imm_valid = 1'b1; dinstr_o.imm = imm_s_type(instr_i);
                end
            end

            // ---- OP-IMM (register-immediate) -------------------------------
            OPC_OPIMM: begin
                unique case (funct3)
                    F3_ADDSUB: begin dinstr_o.valid = 1'b1; dinstr_o.op = ADDI;   end
                    F3_SLT:    begin dinstr_o.valid = 1'b1; dinstr_o.op = SLTI;   end
                    F3_SLTU:   begin dinstr_o.valid = 1'b1; dinstr_o.op = SLTIU;  end
                    F3_XOR:    begin dinstr_o.valid = 1'b1; dinstr_o.op = XORI;   end
                    F3_OR:     begin dinstr_o.valid = 1'b1; dinstr_o.op = ORI;    end
                    F3_AND:    begin dinstr_o.valid = 1'b1; dinstr_o.op = ANDI;   end
                    F3_SLL: begin  // SLLI, sadece funct7 = 0
                        if (funct7 == F7_DEFAULT) begin
                            dinstr_o.valid = 1'b1; dinstr_o.op = SLLI;
                        end
                    end
                    F3_SR: begin   // SRLI / SRAI, funct7'ye göre
                        if      (funct7 == F7_DEFAULT) begin dinstr_o.valid = 1'b1; dinstr_o.op = SRLI; end
                        else if (funct7 == F7_ALT)     begin dinstr_o.valid = 1'b1; dinstr_o.op = SRAI; end
                    end
                    default: ;
                endcase
                if (dinstr_o.valid) begin
                    dinstr_o.rd_valid  = 1'b1;
                    dinstr_o.rs1_valid = 1'b1;
                    dinstr_o.imm_valid = 1'b1;
                    // shift'lerde immediate = shamt, diğerlerinde I-type
                    dinstr_o.imm = (funct3 == F3_SLL || funct3 == F3_SR)
                                 ? imm_shamt(instr_i)
                                 : imm_i_type(instr_i);
                end
            end

            // ---- OP (register-register) ------------------------------------
            OPC_OP: begin
                unique case (funct3)
                    F3_ADDSUB: begin
                        if      (funct7 == F7_DEFAULT) begin dinstr_o.valid = 1'b1; dinstr_o.op = ADD; end
                        else if (funct7 == F7_ALT)     begin dinstr_o.valid = 1'b1; dinstr_o.op = SUB; end
                    end
                    F3_SLL:  if (funct7 == F7_DEFAULT) begin dinstr_o.valid = 1'b1; dinstr_o.op = SLL;  end
                    F3_SLT:  if (funct7 == F7_DEFAULT) begin dinstr_o.valid = 1'b1; dinstr_o.op = SLT;  end
                    F3_SLTU: if (funct7 == F7_DEFAULT) begin dinstr_o.valid = 1'b1; dinstr_o.op = SLTU; end
                    F3_XOR:  if (funct7 == F7_DEFAULT) begin dinstr_o.valid = 1'b1; dinstr_o.op = XOR;  end
                    F3_SR: begin
                        if      (funct7 == F7_DEFAULT) begin dinstr_o.valid = 1'b1; dinstr_o.op = SRL; end
                        else if (funct7 == F7_ALT)     begin dinstr_o.valid = 1'b1; dinstr_o.op = SRA; end
                    end
                    F3_OR:   if (funct7 == F7_DEFAULT) begin dinstr_o.valid = 1'b1; dinstr_o.op = OR;   end
                    F3_AND:  if (funct7 == F7_DEFAULT) begin dinstr_o.valid = 1'b1; dinstr_o.op = AND;  end
                    default: ;
                endcase
                if (dinstr_o.valid) begin
                    dinstr_o.rd_valid  = 1'b1;
                    dinstr_o.rs1_valid = 1'b1;
                    dinstr_o.rs2_valid = 1'b1;
                    // R-type'ta immediate yok
                end
            end

            // ---- SYSTEM (ECALL/EBREAK;) -----------------------
            OPC_SYSTEM: begin
                if (funct3 == F3_SYSTEM) begin
                    unique case (instr_i[31:20])
                        SYS_ECALL:  begin dinstr_o.valid = 1'b1; dinstr_o.op = ECALL;  end
                        SYS_EBREAK: begin
                            dinstr_o.valid  = 1'b1; dinstr_o.op = EBREAK;
                            dinstr_o.is_halt = 1'b1;   // sim-stop; M4'te normal trap olacak
                        end
                        default: ; // MRET/WFI/CSR etc. -> illegal for now
                    endcase
                end
                // funct3 != 0 -> CSR instructions, illegal for now
            end

            default: ; // unknown opcode -> illegal (valid 0)
        endcase

        // --- Decode-time classify -----------
        dinstr_o.is_mem = dinstr_o.valid &&
            (dinstr_o.op inside {LB, LH, LW, LBU, LHU, SB, SH, SW});
        dinstr_o.is_pc_changer = dinstr_o.valid &&
            (dinstr_o.op inside {JAL, JALR, BEQ, BNE, BLT, BGE, BLTU, BGEU});
    end

endmodule