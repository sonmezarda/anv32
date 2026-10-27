// Fetch stage.
//   fetch_addr_o / fetch_req_o / fetch_ready_i -> instruction memory request
//   instr_i      <- read data, valid the cycle after the request is accepted
//   finstr_o     -> aligned packet for the decode stage
//
// The instruction port follows the data bus protocol (anv32_bus_pkg): a
// request is accepted on a cycle where fetch_req_o and fetch_ready_i are both
// high, the read data arrives on the next cycle, and an address that is not
// accepted yet stays on the port. While memory is not ready, decode gets
// bubbles and the rest of the pipeline keeps running.
module anv32_fetch_c1
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
    input  logic [XLEN-1:0] instr_i,        // read data for last cycle's request

    output logic [XLEN-1:0] fetch_addr_o,   // request address
    output logic            fetch_req_o,    // request valid
    input  logic            fetch_ready_i,  // request accepted this cycle

    output logic [XLEN-1:0] next_pc_o,      // oldest PC not yet fetched (for interrupts)

    output finstr_t         finstr_o        // fetched instruction packet
);

    logic [XLEN-1:0] pc_fetch;
    logic            fire;

    // A redirect that arrived while a request was waiting. The waiting request
    // has to stay on the port, so the target is kept here, applied once that
    // request is accepted, and its (wrong-path) data is dropped.
    logic            redirect_q;
    logic [XLEN-1:0] redirect_pc_q;

    assign fetch_addr_o = pc_fetch;
    assign fetch_req_o  = !rst_i;
    assign fire         = fetch_req_o && fetch_ready_i;
    assign next_pc_o    = redirect_q ? redirect_pc_q : pc_fetch;

    // pc_align/instr_valid describe the instruction offered to decode. A new
    // one is taken from memory only when a request is accepted in a cycle
    // where fetch is not stalled; requests accepted during a stall are
    // repeated afterwards and their data is ignored. rsp_q marks that the
    // offered instruction is on instr_i this cycle.
    logic [XLEN-1:0] pc_align;
    logic            instr_valid;
    logic            rsp_q;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            pc_fetch      <= PC_RESET_VALUE;
            redirect_q    <= 1'b0;
            redirect_pc_q <= '0;
            pc_align      <= PC_RESET_VALUE;
            instr_valid   <= 1'b0;
            rsp_q         <= 1'b0;
        end else begin
            rsp_q <= 1'b0;
            if (pc_jmp_en_i) begin
                // Everything fetched after the jump is on the wrong path
                instr_valid <= 1'b0;
                if (fire) begin
                    pc_fetch   <= pc_jmp_addr_i;
                    redirect_q <= 1'b0;
                end else begin
                    redirect_q    <= 1'b1;
                    redirect_pc_q <= pc_jmp_addr_i;
                end
            end else if (redirect_q) begin
                if (fire) begin
                    pc_fetch   <= redirect_pc_q;
                    redirect_q <= 1'b0;
                end
            end else if (!stall_i) begin
                if (fire) begin
                    pc_fetch    <= pc_fetch + 32'h4;
                    pc_align    <= pc_fetch;
                    instr_valid <= 1'b1;
                    rsp_q       <= 1'b1;
                end else begin
                    instr_valid <= 1'b0;   // decode took the last one, memory is busy
                end
            end
            // stall: hold the offered instruction
        end
    end

    // instr_i is only valid in the cycle after the request, so the offered
    // instruction is copied while it is there and held from then on (a stall
    // can keep it waiting). rsp_q is a register, so finstr_o does not depend
    // combinationally on stall_i (hazard -> stall -> fetch -> decode -> hazard).
    logic [XLEN-1:0] skid_buffer;

    always_ff @(posedge clk_i) begin
        if (rst_i)      skid_buffer <= '0;
        else if (rsp_q) skid_buffer <= instr_i;
    end

    assign finstr_o.pc    = pc_align;
    assign finstr_o.valid = instr_valid;
    assign finstr_o.instr = rsp_q ? instr_i : skid_buffer;

endmodule
