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

    // funct7 (instr[31:25]) -
    localparam logic [6:0] F7_DEFAULT = 7'b0000000;
    localparam logic [6:0] F7_ALT     = 7'b0100000;  // SUB, SRA, SRAI

    // SYSTEM instr[31:20]
    localparam logic [11:0] SYS_ECALL  = 12'h000;
    localparam logic [11:0] SYS_EBREAK = 12'h001;

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
        // system
        ECALL, EBREAK,
        // catch-all
        UNKNOWN
    } op_e;

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

        logic [XLEN-1:0] imm;           // extracted immediate
        logic            imm_valid;     // is imm valid

        logic            is_mem;        // load/store
        logic            is_pc_changer; // jump/branch
        logic            is_halt;       // EBREAK -> sim-stop
    } dinstr_t;

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

endpackage