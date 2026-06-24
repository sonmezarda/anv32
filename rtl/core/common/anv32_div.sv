module anv32_div
    import anv32_config_pkg::*;
    import anv32_isa_pkg::*;
(
    input  logic            clk_i,
    input  logic            rst_i,
    input  logic            flush_i,
    input  logic            start_i,
    input  op_e             op_i,
    input  logic [XLEN-1:0] a_i,
    input  logic [XLEN-1:0] b_i,
    output logic            busy_o,
    output logic            done_o,
    output logic [XLEN-1:0] result_o
);
    typedef enum logic [1:0] { IDLE, RUN, FIN } div_state_e;
    div_state_e state_q;

    logic [5:0]  cnt_q;
    logic [32:0] rem_q;
    logic [31:0] quo_q, dvr_q, res_q;
    logic        quo_neg_q, rem_neg_q, want_rem_q;

    logic        is_signed, want_rem, div_zero, ovf;
    logic [31:0] a_abs, b_abs;
    always_comb begin
        is_signed = op_i inside {DIV, REM};
        want_rem  = op_i inside {REM, REMU};
        div_zero  = (b_i == '0);
        ovf       = is_signed && (a_i == 32'h8000_0000) && (b_i == 32'hFFFF_FFFF);
        a_abs     = (is_signed && a_i[31]) ? (~a_i + 1'b1) : a_i;
        b_abs     = (is_signed && b_i[31]) ? (~b_i + 1'b1) : b_i;
    end

    logic [32:0] rem_shift, rem_sub, nxt_rem;
    logic [31:0] nxt_quo;
    logic        ge;
    always_comb begin
        rem_shift = {rem_q[31:0], quo_q[31]};
        rem_sub   = rem_shift - {1'b0, dvr_q};
        ge        = (rem_shift >= {1'b0, dvr_q});
        nxt_rem   = ge ? rem_sub : rem_shift;
        nxt_quo   = {quo_q[30:0], ge};
    end

    assign busy_o   = (state_q != IDLE);
    assign done_o   = (state_q == FIN);
    assign result_o = res_q;

    always_ff @(posedge clk_i) begin
        if (rst_i || flush_i) begin
            state_q <= IDLE;
        end else begin
            unique case (state_q)
                IDLE: if (start_i) begin
                    want_rem_q <= want_rem;
                    if (div_zero) begin
                        res_q   <= want_rem ? a_i : 32'hFFFF_FFFF;
                        state_q <= FIN;
                    end else if (ovf) begin
                        res_q   <= want_rem ? 32'h0 : 32'h8000_0000;
                        state_q <= FIN;
                    end else begin
                        rem_q     <= '0;
                        quo_q     <= a_abs;
                        dvr_q     <= b_abs;
                        quo_neg_q <= is_signed && (a_i[31] ^ b_i[31]);
                        rem_neg_q <= is_signed && a_i[31];
                        cnt_q     <= 6'd32;
                        state_q   <= RUN;
                    end
                end
                RUN: begin
                    rem_q <= nxt_rem;
                    quo_q <= nxt_quo;
                    cnt_q <= cnt_q - 1'b1;
                    if (cnt_q == 6'd1) begin
                        res_q <= want_rem_q
                               ? (rem_neg_q ? (~nxt_rem[31:0] + 1'b1) : nxt_rem[31:0])
                               : (quo_neg_q ? (~nxt_quo        + 1'b1) : nxt_quo);
                        state_q <= FIN;
                    end
                end
                FIN: state_q <= IDLE;
                default: state_q <= IDLE;
            endcase
        end
    end
endmodule
