// ============================================================================
// anv32_decoder.sv
// RV32I (+ optional RV32M) decode stage. Raw 32-bit instruction -> dinstr_t.
// Shared across core variants; HAS_M selects M-extension decode.
// ============================================================================
module anv32_decoder
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
#(
    parameter bit HAS_M = 1'b0   // 1 -> decode RV32M (MUL/DIV); 0 -> base RV32I
)(
    input  logic [XLEN-1:0] instr_i,   // raw instruction (from memory)
    input  logic [XLEN-1:0] pc_i,      // address of this instruction
    input  logic [XLEN-1:0] id_i,      // commit-log/diff order no (debug)
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

        // --- Default: full 0, then build up ---
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
                    default: ; // illegal -> valid stays 0
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
                    F3_ADDSUB: begin dinstr_o.valid = 1'b1; dinstr_o.op = ADDI;  end
                    F3_SLT:    begin dinstr_o.valid = 1'b1; dinstr_o.op = SLTI;  end
                    F3_SLTU:   begin dinstr_o.valid = 1'b1; dinstr_o.op = SLTIU; end
                    F3_XOR:    begin dinstr_o.valid = 1'b1; dinstr_o.op = XORI;  end
                    F3_OR:     begin dinstr_o.valid = 1'b1; dinstr_o.op = ORI;   end
                    F3_AND:    begin dinstr_o.valid = 1'b1; dinstr_o.op = ANDI;  end
                    F3_SLL: begin // SLLI, funct7 = 0 only
                        if (funct7 == F7_DEFAULT) begin
                            dinstr_o.valid = 1'b1; dinstr_o.op = SLLI;
                        end
                    end
                    F3_SR: begin  // SRLI / SRAI by funct7
                        if      (funct7 == F7_DEFAULT) begin dinstr_o.valid = 1'b1; dinstr_o.op = SRLI; end
                        else if (funct7 == F7_ALT)     begin dinstr_o.valid = 1'b1; dinstr_o.op = SRAI; end
                    end
                    default: ;
                endcase
                if (dinstr_o.valid) begin
                    dinstr_o.rd_valid  = 1'b1;
                    dinstr_o.rs1_valid = 1'b1;
                    dinstr_o.imm_valid = 1'b1;
                    // shifts use shamt, others use I-type immediate
                    dinstr_o.imm = (funct3 == F3_SLL || funct3 == F3_SR)
                                 ? imm_shamt(instr_i)
                                 : imm_i_type(instr_i);
                end
            end

            // ---- OP (register-register): base RV32I + optional RV32M --------
            OPC_OP: begin
                if (HAS_M && funct7 == F7_MULDIV) begin
                    // RV32M multiply/divide (decoded only when HAS_M=1)
                    unique case (funct3)
                        F3_MUL:    begin dinstr_o.valid = 1'b1; dinstr_o.op = MUL;    end
                        F3_MULH:   begin dinstr_o.valid = 1'b1; dinstr_o.op = MULH;   end
                        F3_MULHSU: begin dinstr_o.valid = 1'b1; dinstr_o.op = MULHSU; end
                        F3_MULHU:  begin dinstr_o.valid = 1'b1; dinstr_o.op = MULHU;  end
                        F3_DIV:    begin dinstr_o.valid = 1'b1; dinstr_o.op = DIV;    end
                        F3_DIVU:   begin dinstr_o.valid = 1'b1; dinstr_o.op = DIVU;   end
                        F3_REM:    begin dinstr_o.valid = 1'b1; dinstr_o.op = REM;    end
                        F3_REMU:   begin dinstr_o.valid = 1'b1; dinstr_o.op = REMU;   end
                        default: ;
                    endcase
                end else begin
                    // base RV32I register-register
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
                end
                // both base R-type and M are rd/rs1/rs2, no immediate
                if (dinstr_o.valid) begin
                    dinstr_o.rd_valid  = 1'b1;
                    dinstr_o.rs1_valid = 1'b1;
                    dinstr_o.rs2_valid = 1'b1;
                end
            end

            // ---- SYSTEM (ECALL/EBREAK/CSR) ----------------------------------
            OPC_SYSTEM: begin
                if (funct3 == F3_SYSTEM) begin
                    unique case (instr_i[31:20])
                        SYS_ECALL:  begin dinstr_o.valid = 1'b1; dinstr_o.op = ECALL; end
                        SYS_EBREAK: begin
                            dinstr_o.valid   = 1'b1; dinstr_o.op = EBREAK;
                            dinstr_o.is_halt = 1'b1; // sim-stop; becomes a real trap in M4
                        end
                        default: ; // MRET/WFI/etc -> illegal for now
                    endcase
                end else begin
                    unique case (funct3)
                        F3_CSRRW: begin
                            dinstr_o.valid  = 1'b1;
                            dinstr_o.op     = CSRRW;
                            dinstr_o.csr_op = CSR_OP_RW;
                        end
                        F3_CSRRS: begin
                            dinstr_o.valid  = 1'b1;
                            dinstr_o.op     = CSRRS;
                            dinstr_o.csr_op = CSR_OP_RS;
                        end
                        F3_CSRRC: begin
                            dinstr_o.valid  = 1'b1;
                            dinstr_o.op     = CSRRC;
                            dinstr_o.csr_op = CSR_OP_RC;
                        end
                        F3_CSRRWI: begin
                            dinstr_o.valid   = 1'b1;
                            dinstr_o.op      = CSRRWI;
                            dinstr_o.csr_op  = CSR_OP_RW;
                            dinstr_o.csr_imm = 1'b1;
                        end
                        F3_CSRRSI: begin
                            dinstr_o.valid   = 1'b1;
                            dinstr_o.op      = CSRRSI;
                            dinstr_o.csr_op  = CSR_OP_RS;
                            dinstr_o.csr_imm = 1'b1;
                        end
                        F3_CSRRCI: begin
                            dinstr_o.valid   = 1'b1;
                            dinstr_o.op      = CSRRCI;
                            dinstr_o.csr_op  = CSR_OP_RC;
                            dinstr_o.csr_imm = 1'b1;
                        end
                        default: ;
                    endcase

                    if (dinstr_o.valid) begin
                        dinstr_o.rd_valid  = 1'b1;
                        dinstr_o.is_csr    = 1'b1;
                        dinstr_o.csr_addr  = instr_i[31:20];
                        dinstr_o.rs1_valid = !dinstr_o.csr_imm &&
                            (dinstr_o.csr_op == CSR_OP_RW || rs1 != 5'd0);
                    end
                end
            end

            default: ; // unknown opcode -> illegal (valid 0)
        endcase

        // --- ALU işlemi: adres/hedef üreten her şey ADD ---
        unique case (dinstr_o.op)
            SUB:          dinstr_o.alu_op = ALU_SUB;
            SLLI, SLL:    dinstr_o.alu_op = ALU_SLL;
            SLTI, SLT:    dinstr_o.alu_op = ALU_SLT;
            SLTIU, SLTU:  dinstr_o.alu_op = ALU_SLTU;
            XORI, XOR:    dinstr_o.alu_op = ALU_XOR;
            SRLI, SRL:    dinstr_o.alu_op = ALU_SRL;
            SRAI, SRA:    dinstr_o.alu_op = ALU_SRA;
            ORI, OR:      dinstr_o.alu_op = ALU_OR;
            ANDI, AND:    dinstr_o.alu_op = ALU_AND;
            // ADDI,ADD,LUI,AUIPC,JAL,JALR,load,store,branch -> ADD
            default:      dinstr_o.alu_op = ALU_ADD;
        endcase

        // --- A operandı ---
        unique case (dinstr_o.op)
            AUIPC, JAL, BEQ, BNE, BLT, BGE, BLTU, BGEU: dinstr_o.a_sel = A_PC;
            LUI:                                        dinstr_o.a_sel = A_ZERO;
            default:                                    dinstr_o.a_sel = A_RS1; // JALR, load, store, OP, OP-IMM
        endcase

        // --- B operandı: register-register ops rs2, gerisi imm ---
        dinstr_o.b_sel = (dinstr_o.op inside
            {ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND}) ? B_RS2 : B_IMM;

        // --- writeback kaynağı ---
        unique case (dinstr_o.op)
            LB, LH, LW, LBU, LHU: dinstr_o.wb_sel = WB_MEM;
            JAL, JALR:            dinstr_o.wb_sel = WB_PC4;
            default:              dinstr_o.wb_sel = WB_ALU;
        endcase
        
        // --- Decode-time classification (pipeline helpers) ------------------
        dinstr_o.is_mem = dinstr_o.valid &&
            (dinstr_o.op inside {LB, LH, LW, LBU, LHU, SB, SH, SW});
        dinstr_o.is_pc_changer = dinstr_o.valid &&
            (dinstr_o.op inside {JAL, JALR, BEQ, BNE, BLT, BGE, BLTU, BGEU});
        dinstr_o.is_muldiv = dinstr_o.valid &&
            (dinstr_o.op inside {MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU});
    end

endmodule
