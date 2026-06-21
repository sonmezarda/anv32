// ============================================================================
// anv32_isa_pkg.sv
// ============================================================================
package anv32_isa_pkg;

    import anv32_config_pkg::*;   // XLEN

    // Opcodes (instr[6:0])
    localparam logic [6:0] OPC_LUI    = 7'b0110111;
    localparam logic [6:0] OPC_AUIPC  = 7'b0010111;
    localparam logic [6:0] OPC_JAL    = 7'b1101111;
    localparam logic [6:0] OPC_JALR   = 7'b1100111;
    localparam logic [6:0] OPC_BRANCH = 7'b1100011;
    localparam logic [6:0] OPC_LOAD   = 7'b0000011;
    localparam logic [6:0] OPC_STORE  = 7'b0100011;
    localparam logic [6:0] OPC_OPIMM  = 7'b0010011;  // ADDI, SLTI, ... (eski OPC_ARI)
    localparam logic [6:0] OPC_OP     = 7'b0110011;  // ADD, SUB, ...   (eski OPC_AR)
    localparam logic [6:0] OPC_SYSTEM = 7'b1110011;  // ECALL/EBREAK (+ CSR, M3'te)

    // funct3 (instr[14:12])
    localparam logic [2:0] F3_JALR    = 3'b000;
    // BRANCH
    localparam logic [2:0] F3_BEQ     = 3'b000;
    localparam logic [2:0] F3_BNE     = 3'b001;
    localparam logic [2:0] F3_BLT     = 3'b100;
    localparam logic [2:0] F3_BGE     = 3'b101;
    localparam logic [2:0] F3_BLTU    = 3'b110;
    localparam logic [2:0] F3_BGEU    = 3'b111;
    // LOAD
    localparam logic [2:0] F3_LB      = 3'b000;
    localparam logic [2:0] F3_LH      = 3'b001;
    localparam logic [2:0] F3_LW      = 3'b010;
    localparam logic [2:0] F3_LBU     = 3'b100;
    localparam logic [2:0] F3_LHU     = 3'b101;
    // STORE
    localparam logic [2:0] F3_SB      = 3'b000;
    localparam logic [2:0] F3_SH      = 3'b001;
    localparam logic [2:0] F3_SW      = 3'b010;
    // OP / OP-IMM
    localparam logic [2:0] F3_ADDSUB  = 3'b000;  // OP_IMM ADDI
    localparam logic [2:0] F3_SLL     = 3'b001;  // OP_IMM SLLI
    localparam logic [2:0] F3_SLT     = 3'b010;  // OP_IMM SLTI
    localparam logic [2:0] F3_SLTU    = 3'b011;  // OP_IMM SLTIU
    localparam logic [2:0] F3_XOR     = 3'b100;  // OP_IMM XORI
    localparam logic [2:0] F3_SR      = 3'b101;  // OP_IMM SRL/SRA, OP-IMM SRLI/SRAI
    localparam logic [2:0] F3_OR      = 3'b110;  // OP_IMM ORI
    localparam logic [2:0] F3_AND     = 3'b111;  // OP_IMM ANDI
    localparam logic [2:0] F3_SYSTEM  = 3'b000;  // ECALL/EBREAK
    localparam logic [2:0] F3_CSRRW   = 3'b001;
    localparam logic [2:0] F3_CSRRS   = 3'b010;
    localparam logic [2:0] F3_CSRRC   = 3'b011;
    localparam logic [2:0] F3_CSRRWI  = 3'b101;
    localparam logic [2:0] F3_CSRRSI  = 3'b110;
    localparam logic [2:0] F3_CSRRCI  = 3'b111;

    // funct7 (instr[31:25]) -
    localparam logic [6:0] F7_DEFAULT = 7'b0000000;
    localparam logic [6:0] F7_ALT     = 7'b0100000;  // SUB, SRA, SRAI

    // M extension (RV32M): OP opcode + funct7 = 0000001
    localparam logic [6:0] F7_MULDIV = 7'b0000001;
    localparam logic [2:0] F3_MUL    = 3'b000;
    localparam logic [2:0] F3_MULH   = 3'b001;
    localparam logic [2:0] F3_MULHSU = 3'b010;
    localparam logic [2:0] F3_MULHU  = 3'b011;
    localparam logic [2:0] F3_DIV    = 3'b100;
    localparam logic [2:0] F3_DIVU   = 3'b101;
    localparam logic [2:0] F3_REM    = 3'b110;
    localparam logic [2:0] F3_REMU   = 3'b111;

    // SYSTEM instr[31:20]
    localparam logic [11:0] SYS_ECALL  = 12'h000;
    localparam logic [11:0] SYS_EBREAK = 12'h001;

    localparam logic [11:0] SYS_MRET   = 12'h302;
    // Machine CSR addresses
    localparam logic [11:0] CSR_MSTATUS = 12'h300;
    localparam logic [11:0] CSR_MIE     = 12'h304;
    localparam logic [11:0] CSR_MTVEC   = 12'h305;
    localparam logic [11:0] CSR_MEPC    = 12'h341;
    localparam logic [11:0] CSR_MCAUSE  = 12'h342;
    localparam logic [11:0] CSR_MTVAL   = 12'h343;
    localparam logic [11:0] CSR_MIP     = 12'h344;
    

    // internal micro-op
    typedef enum logic [5:0] {
        // U-type
        LUI, AUIPC,
        // jump
        JAL, JALR,
        // branch
        BEQ, BNE, BLT, BGE, BLTU, BGEU,
        // load
        LB, LH, LW, LBU, LHU,
        // store
        SB, SH, SW,
        // op-imm
        ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI,
        // op (register-register)
        ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND,
        // M extension (RV32M)
        MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU,
        // system
        CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI, MRET,
        ECALL, EBREAK,
        // catch-all
        UNKNOWN
    } op_e;

    typedef enum logic [3:0] {
        ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
        ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR,  ALU_AND
    } alu_op_e;

    typedef enum logic [1:0] {
        FWD_REG = 2'b00,
        FWD_M   = 2'b01,
        FWD_W   = 2'b10
    } fwd_sel_e; // forwarding selection

    // --- ALU A operandı ---
    typedef enum logic [1:0] { A_RS1, A_PC, A_ZERO } a_sel_e;

    // --- ALU B operandı ---
    typedef enum logic [0:0] { B_RS2, B_IMM } b_sel_e;

    // --- rd'ye ne yazılacak ---
    typedef enum logic [1:0] { WB_ALU, WB_MEM, WB_PC4 } wb_sel_e;

    typedef enum logic [2:0] {
        CSR_OP_RW, CSR_OP_RS, CSR_OP_RC
    } csr_op_e;

    typedef enum logic [XLEN-2:0] { // msb is for exception/interrupt
        MCAUSE_INSTR_ADDR_MISALIGNED = 31'd0,
        MCAUSE_INSTR_ACCESS_FAULT    = 31'd1,
        MCAUSE_ILLEGAL_INSTR         = 31'd2,
        MCAUSE_BREAKPOINT            = 31'd3,
        MCAUSE_LOAD_ADDR_MISALIGNED  = 31'd4,
        MCAUSE_LOAD_ACCESS_FAULT     = 31'd5,
        MCAUSE_STORE_ADDR_MISALIGNED = 31'd6,
        MCAUSE_STORE_ACCESS_FAULT    = 31'd7,
        MCAUSE_ECALL_U               = 31'd8,
        MCAUSE_ECALL_M               = 31'd11
    } mcause_code_e;
    // Fetched Instruction
    typedef struct packed {
        logic [XLEN-1:0] pc;
        logic [XLEN-1:0] instr;
        logic            valid;
    } finstr_t;   // fetch -> decode packet

    // Decoded instruction
    typedef struct packed {
        logic [XLEN-1:0] pc;            // addr of instruction
        logic [31:0]     id;            // for commit-log/diff
        logic [31:0]     instr;         // raw instruction (debug/commit-log)

        op_e             op;            // internal micro-op
        logic            valid;         // 1 = legal & decoded; 0 = illegal

        logic [4:0]      rd_idx;        // destination reg
        logic [4:0]      rs1_idx;       // source reg 1
        logic [4:0]      rs2_idx;       // source reg 2
        logic            rd_valid;      // is rd valid (rd will be written)
        logic            rs1_valid;     // is rs1 valid
        logic            rs2_valid;     // is rs2 valid
        logic [XLEN-1:0] rs1_rdata;     // D/E latched operand
        logic [XLEN-1:0] rs2_rdata;     // D/E latched operand

        logic [XLEN-1:0] imm;           // extracted immediate
        logic            imm_valid;     // is imm valid

        alu_op_e         alu_op;        // ALU hangi işlemi yapacak
        a_sel_e          a_sel;         // A = rs1 / pc / 0
        b_sel_e          b_sel;         // B = rs2 / imm
        wb_sel_e         wb_sel;        // rd <- alu / mem / pc+4

        logic            is_mem;        // load/store
        logic            is_pc_changer; // jump/branch
        logic            is_muldiv;     // RV32M op (needs multi-cycle unit)
        logic            is_csr;        // Zicsr instruction
        logic            csr_imm;       // use instr[19:15] as zimm instead of rs1
        csr_op_e         csr_op;        // RW/RS/RC semantic
        logic [11:0]     csr_addr;      // instr[31:20]
        logic [XLEN-1:0] csr_rdata;     // D/E latched CSR read data
        logic            is_halt;       // EBREAK -> sim-stop

        logic        exc_valid;         // is this instruction an exception?
        logic [XLEN-1:0] exc_cause;         // exception cause code     
        logic [XLEN-1:0] exc_tval;          
    } dinstr_t;

    // Executed Instruction
    typedef struct packed {
        // commit-log / diff
        logic [XLEN-1:0] pc;
        logic [31:0]     id;
        logic [31:0]     instr;         // raw instruction (commit-log)
        op_e             op;            // mem-stage load/store genişliği + log
        logic            valid;

        // execute results
        logic [XLEN-1:0] alu_result;   // rd değeri ya da bellek adresi
        logic [XLEN-1:0] write_data;   // store verisi (rs2)
        logic [XLEN-1:0] link_pc;      // pc+4 (JAL/JALR link)
        logic            branch_taken;
        logic [XLEN-1:0] pc_target;    // JALR'da LSB temizlenmiş

        // mem + writeback control passthrough
        logic [4:0]      rd_idx;
        logic            rd_valid;
        wb_sel_e         wb_sel;
        logic            is_mem;
        logic            is_pc_changer;
        logic            is_csr;
        logic [11:0]     csr_addr;
        logic            csr_we;
        logic [XLEN-1:0] csr_wdata;
        logic            is_halt;
    } einstr_t;

    // Instruction after memory stage
    typedef struct packed {
        op_e             op;
        logic            valid;
        logic [XLEN-1:0] pc;
        logic [31:0]     instr;         // raw instruction (commit-log)
        logic [XLEN-1:0] link_pc;      // pc+4 (JAL/JALR link)
        logic [XLEN-1:0] alu_result;   // rd değeri ya da bellek adresi
        logic [4:0]      rd_idx;
        logic            rd_valid;
        wb_sel_e         wb_sel;        // rd <- alu / mem / pc+4
        logic            is_csr;
        logic [11:0]     csr_addr;
        logic            csr_we;
        logic [XLEN-1:0] csr_wdata;
    } minstr_t;



    // ------------------------------------------------------------------------
    // immediate extraction functions
    // ------------------------------------------------------------------------
    function automatic logic [XLEN-1:0] imm_i_type(input logic [31:0] w);
        return {{20{w[31]}}, w[31:20]};
    endfunction

    function automatic logic [XLEN-1:0] imm_s_type(input logic [31:0] w);
        return {{20{w[31]}}, w[31:25], w[11:7]};
    endfunction

    function automatic logic [XLEN-1:0] imm_b_type(input logic [31:0] w);
        return {{19{w[31]}}, w[31], w[7], w[30:25], w[11:8], 1'b0};
    endfunction

    function automatic logic [XLEN-1:0] imm_u_type(input logic [31:0] w);
        return {w[31:12], 12'b0};
    endfunction

    function automatic logic [XLEN-1:0] imm_j_type(input logic [31:0] w);
        return {{11{w[31]}}, w[31], w[19:12], w[20], w[30:21], 1'b0};
    endfunction

    function automatic logic [XLEN-1:0] imm_shamt(input logic [31:0] w);
        return {27'b0, w[24:20]};   // shift amount: 5 bit, zero-extend
    endfunction

    function automatic logic [XLEN-1:0] mcause_exception(input mcause_code_e code);
        return {1'b0, code};
    endfunction

    function automatic logic [XLEN-1:0] mcause_interrupt(input mcause_code_e code);
        return {1'b1, code};
    endfunction

endpackage
