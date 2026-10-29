package anv32_isa_pkg;

    import anv32_config_pkg::*;   // XLEN

    // Opcodes (instr[6:0])
    localparam logic [6:0] OPC_LUI      = 7'b0110111;
    localparam logic [6:0] OPC_AUIPC    = 7'b0010111;
    localparam logic [6:0] OPC_JAL      = 7'b1101111;
    localparam logic [6:0] OPC_JALR     = 7'b1100111;
    localparam logic [6:0] OPC_BRANCH   = 7'b1100011;
    localparam logic [6:0] OPC_LOAD     = 7'b0000011;
    localparam logic [6:0] OPC_STORE    = 7'b0100011;
    localparam logic [6:0] OPC_OPIMM    = 7'b0010011;  // ADDI, SLTI, ...
    localparam logic [6:0] OPC_OP       = 7'b0110011;  // ADD, SUB, ...
    localparam logic [6:0] OPC_MISC_MEM = 7'b0001111;  // FENCE
    localparam logic [6:0] OPC_SYSTEM   = 7'b1110011;  // ECALL/EBREAK/MRET, Zicsr

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
    localparam logic [2:0] F3_FENCE   = 3'b000;
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
    localparam logic [11:0] CSR_MSTATUS    = 12'h300;
    localparam logic [11:0] CSR_MISA       = 12'h301;
    localparam logic [11:0] CSR_MIE        = 12'h304;
    localparam logic [11:0] CSR_MTVEC      = 12'h305;
    localparam logic [11:0] CSR_MSTATUSH   = 12'h310;
    localparam logic [11:0] CSR_MSCRATCH   = 12'h340;
    localparam logic [11:0] CSR_MEPC       = 12'h341;
    localparam logic [11:0] CSR_MCAUSE     = 12'h342;
    localparam logic [11:0] CSR_MTVAL      = 12'h343;
    localparam logic [11:0] CSR_MIP        = 12'h344;
    localparam logic [11:0] CSR_MCYCLE     = 12'hB00;
    localparam logic [11:0] CSR_MINSTRET   = 12'hB02;
    localparam logic [11:0] CSR_MCYCLEH    = 12'hB80;
    localparam logic [11:0] CSR_MINSTRETH  = 12'hB82;
    localparam logic [11:0] CSR_CYCLE      = 12'hC00;
    localparam logic [11:0] CSR_INSTRET    = 12'hC02;
    localparam logic [11:0] CSR_CYCLEH     = 12'hC80;
    localparam logic [11:0] CSR_INSTRETH   = 12'hC82;
    localparam logic [11:0] CSR_MVENDORID  = 12'hF11;
    localparam logic [11:0] CSR_MARCHID    = 12'hF12;
    localparam logic [11:0] CSR_MIMPID     = 12'hF13;
    localparam logic [11:0] CSR_MHARTID    = 12'hF14;
    localparam logic [11:0] CSR_MCONFIGPTR = 12'hF15;
    localparam logic [11:0] CSR_PMPCFG0    = 12'h3A0;   // pmpcfg0-15
    localparam logic [11:0] CSR_PMPADDR0   = 12'h3B0;   // pmpaddr0-63

    // misa: MXL = 1 (32-bit) and the extension letters
    localparam logic [XLEN-1:0] MISA_MXL32 = 32'h4000_0000;
    localparam logic [XLEN-1:0] MISA_I     = 32'h0000_0100;
    localparam logic [XLEN-1:0] MISA_M     = 32'h0000_1000;

    // Machine-mode interrupt/CSR bit definitions
    localparam logic [XLEN-1:0] MCAUSE_MACHINE_SOFTWARE_IRQ = {1'b1, 31'd3};
    localparam logic [XLEN-1:0] MCAUSE_MACHINE_TIMER_IRQ    = {1'b1, 31'd7};
    localparam logic [XLEN-1:0] MCAUSE_MACHINE_EXTERNAL_IRQ = {1'b1, 31'd11};

    localparam int unsigned MSTATUS_MIE_BIT  = 3;      // Machine Interrupt Enable
    localparam int unsigned MSTATUS_MPIE_BIT = 7;      // Machine Previous Interrupt Enable
    localparam int unsigned MSTATUS_MPP_LSB  = 11;     // Machine Previous Privilege
    localparam int unsigned MSTATUS_MPP_MSB  = 12;

    localparam int unsigned MIE_MSIE_BIT = 3;          // Machine Software Interrupt Enable
    localparam int unsigned MIE_MTIE_BIT = 7;          // Machine Timer Interrupt Enable
    localparam int unsigned MIE_MEIE_BIT = 11;         // Machine External Interrupt Enable
    localparam int unsigned MIP_MSIP_BIT = 3;          // Machine Software Interrupt Pending
    localparam int unsigned MIP_MTIP_BIT = 7;          // Machine Timer Interrupt Pending
    localparam int unsigned MIP_MEIP_BIT = 11;         // Machine External Interrupt Pending

    localparam logic [1:0] PRIV_U = 2'b00;
    localparam logic [1:0] PRIV_M = 2'b11;

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
        // memory ordering
        FENCE,
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

    // ALU operand A source
    typedef enum logic [1:0] { A_RS1, A_PC, A_ZERO } a_sel_e;

    // ALU operand B source
    typedef enum logic [0:0] { B_RS2, B_IMM } b_sel_e;

    // rd writeback source
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
        logic [XLEN-1:0] pc;
        logic [31:0]     instr;         // raw instruction (debug/commit-log)

        op_e             op;            // internal micro-op
        logic            valid;         // slot holds an instruction (illegal ones trap via exc_valid)

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

        alu_op_e         alu_op;
        a_sel_e          a_sel;         // A = rs1 / pc / 0
        b_sel_e          b_sel;         // B = rs2 / imm
        wb_sel_e         wb_sel;        // rd <- alu / mem / pc+4

        logic            is_mem;        // load/store
        logic            is_pc_changer; // jump/branch
        logic            is_muldiv;     // RV32M op
        logic            is_csr;        // Zicsr instruction
        logic            csr_imm;       // use instr[19:15] as zimm instead of rs1
        csr_op_e         csr_op;        // RW/RS/RC semantic
        logic [11:0]     csr_addr;      // instr[31:20]
        logic [XLEN-1:0] csr_rdata;     // D/E latched CSR read data

        logic            exc_valid;     // instruction raises an exception in E
        logic [XLEN-1:0] exc_cause;
        logic [XLEN-1:0] exc_tval;
    } dinstr_t;

    // Executed Instruction
    typedef struct packed {
        // commit-log / diff
        logic [XLEN-1:0] pc;
        logic [31:0]     instr;         // raw instruction (commit-log)
        op_e             op;            // load/store width in M, commit log
        logic            valid;

        // execute results
        logic [XLEN-1:0] alu_result;   // rd value or memory address
        logic [XLEN-1:0] write_data;   // store data (rs2)
        logic [XLEN-1:0] link_pc;      // pc+4 (JAL/JALR link)
        logic            branch_taken;
        logic [XLEN-1:0] pc_target;    // LSB cleared for JALR

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
    } einstr_t;

    // Instruction after memory stage
    typedef struct packed {
        op_e             op;
        logic            valid;
        logic [XLEN-1:0] pc;
        logic [31:0]     instr;         // raw instruction (commit-log)
        logic [XLEN-1:0] link_pc;      // pc+4 (JAL/JALR link)
        logic [XLEN-1:0] alu_result;   // rd value or memory address
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

    // Loads and stores must be naturally aligned; misaligned ones trap.
    function automatic logic mem_misaligned(input op_e op, input logic [1:0] addr);
        unique case (op)
            LH, LHU, SH: return addr[0];
            LW, SW:      return addr != 2'b00;
            default:     return 1'b0;
        endcase
    endfunction

    function automatic logic is_load(input op_e op);
        return op inside {LB, LH, LW, LBU, LHU};
    endfunction

    function automatic logic csr_is_pmp(input logic [11:0] addr);
        return (addr >= CSR_PMPCFG0 && addr < CSR_PMPCFG0 + 12'd16) ||
               (addr >= CSR_PMPADDR0 && addr < CSR_PMPADDR0 + 12'd64);
    endfunction

    // CSRs that exist on these cores. Anything else raises an illegal
    // instruction exception.
    function automatic logic csr_exists(input logic [11:0] addr);
        unique case (addr)
            CSR_MSTATUS, CSR_MISA, CSR_MIE, CSR_MTVEC, CSR_MSTATUSH,
            CSR_MSCRATCH, CSR_MEPC, CSR_MCAUSE, CSR_MTVAL, CSR_MIP,
            CSR_MCYCLE, CSR_MINSTRET, CSR_MCYCLEH, CSR_MINSTRETH,
            CSR_CYCLE, CSR_INSTRET, CSR_CYCLEH, CSR_INSTRETH,
            CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID, CSR_MHARTID,
            CSR_MCONFIGPTR:
                return 1'b1;
            default:
                // No PMP entries: the PMP CSRs exist but are read-only zero
                return csr_is_pmp(addr);
        endcase
    endfunction

    // CSR address bits [11:10] = 2'b11 mark read-only CSRs.
    function automatic logic csr_read_only(input logic [11:0] addr);
        return addr[11:10] == 2'b11;
    endfunction

    // CSRs whose contents software can change. Writes to misa, mstatush, mip
    // and the PMP CSRs are legal but have no effect, so they are skipped.
    function automatic logic csr_writable(input logic [11:0] addr);
        return csr_exists(addr) && !csr_read_only(addr) && !csr_is_pmp(addr) &&
               !(addr inside {CSR_MISA, CSR_MSTATUSH, CSR_MIP});
    endfunction

    // WARL: the value a CSR actually holds after writing `value` to it.
    function automatic logic [XLEN-1:0] csr_legalize(input logic [11:0] addr,
                                                     input logic [XLEN-1:0] value);
        logic [XLEN-1:0] legal;
        unique case (addr)
            CSR_MSTATUS: begin
                legal = '0;
                legal[MSTATUS_MIE_BIT]  = value[MSTATUS_MIE_BIT];
                legal[MSTATUS_MPIE_BIT] = value[MSTATUS_MPIE_BIT];
                legal[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] = PRIV_M;  // M-mode only
            end
            CSR_MIE: begin
                legal = '0;
                legal[MIE_MSIE_BIT] = value[MIE_MSIE_BIT];
                legal[MIE_MTIE_BIT] = value[MIE_MTIE_BIT];
                legal[MIE_MEIE_BIT] = value[MIE_MEIE_BIT];
            end
            CSR_MTVEC,                                 // direct mode only
            CSR_MEPC:  legal = {value[XLEN-1:2], 2'b00};
            default:   legal = value;
        endcase
        return legal;
    endfunction

    function automatic logic csr_is_counter(input logic [11:0] addr);
        return addr inside {CSR_MCYCLE, CSR_MINSTRET, CSR_MCYCLEH, CSR_MINSTRETH,
                            CSR_CYCLE, CSR_INSTRET, CSR_CYCLEH, CSR_INSTRETH};
    endfunction

endpackage
