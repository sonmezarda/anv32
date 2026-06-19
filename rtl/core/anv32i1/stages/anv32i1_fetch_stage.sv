// ============================================================================
// anv32i1_fetch_stage.sv

// Interface:
//   fetch_addr_o -> RAM address (live fetch pointer)
//   instr_i      <- RAM registered read data
//   pc_o/instr_o/instr_valid_o -> aligned packet for the decode stage
// ============================================================================
module anv32i1_fetch_stage
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
#(
    parameter logic [XLEN-1:0] PC_RESET_VALUE = 'h0000_0000
)(
    input  logic            clk_i,
    input  logic            rst_i,
    input  logic            stall_i,
    input  logic            pc_jmp_en_i,
    input  logic [XLEN-1:0] pc_jmp_addr_i,
    input  logic [XLEN-1:0] instr_i,        // registered read data from RAM

    output logic [XLEN-1:0] fetch_addr_o,   // -> RAM address (live fetch PC)

    output finstr_t         finstr_o        // fetched instruction packet
);

    logic [XLEN-1:0] pc_fetch;
    logic [XLEN-1:0] pc_next;
    logic instr_valid;

    always_comb begin
        if (pc_jmp_en_i) pc_next = pc_jmp_addr_i;
        else             pc_next = pc_fetch + 32'h4;
    end

    always_ff @(posedge clk_i) begin
        if (rst_i)         pc_fetch <= PC_RESET_VALUE;
        else if (!stall_i) pc_fetch <= pc_next;
    end

    assign fetch_addr_o = pc_fetch;

    // PC alignment + valid. pc_align lags pc_fetch by one cycle to match the
    // valid is 0 during reset warm-up and on a jump (wrong-path flush).
    logic [XLEN-1:0] pc_align;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            pc_align      <= PC_RESET_VALUE;
            instr_valid <= 1'b0;
        end else if (!stall_i) begin
            pc_align      <= pc_fetch;
            instr_valid <= ~pc_jmp_en_i;   // jump -> wrong-path slot invalid
        end
        // stall: hold pc_align and valid
    end

    
    // Skid buffer. The sync RAM's in-flight read completes during a stall and
    // would change instr_i, so we cannot pass it through while stalled.
    // Rule: keep the buffer fresh every normal cycle; capture once on the
    // FIRST stall cycle; freeze on subsequent stall cycles.
    logic [XLEN-1:0] skid_buffer;
    logic            stall_prev;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            skid_buffer <= '0;
            stall_prev  <= 1'b0;
        end else begin
            stall_prev <= stall_i;
            if (stall_i) begin
                if (!stall_prev) skid_buffer <= instr_i;  // first stall cycle: capture
                // later stall cycles: hold
            end else begin
                skid_buffer <= instr_i;                   // normal: keep fresh
            end
        end
    end

    // instr to DE: buffered while stalled, straight from RAM otherwise
    assign finstr_o.pc = pc_align;
    assign finstr_o.valid = instr_valid;
    assign finstr_o.instr = stall_i ? skid_buffer : instr_i;

endmodule