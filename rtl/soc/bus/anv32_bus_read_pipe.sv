// Read-data register stage at the core / data-bus boundary.
//
// The caller splits the decoded read data into two combinational buses by
// slave class (see anv32_soc_top): rdata_fast_i carries only fast slaves'
// data (BRAM, GPIO), rdata_slow_i carries only slow slaves' data (NN scratch,
// peripheral bus). Because the split is static (each slave ties bus_rsp_t.fast
// to a constant), rdata_fast_i has no combinational path from a slow slave's
// read register. This stage registers rdata_slow_i and delivers it one cycle
// later, so a slow slave's read data never reaches the core's load/forwarding
// logic combinationally. Fast reads and writes pass through with no added
// latency, so BRAM and GPIO stay zero-wait.
//
// Correctness relies on the bus rule that a master holds its request stable
// while ready == 0. A slow read is presented to the slave for exactly one
// cycle (read side effects happen once); the captured data is delivered one
// cycle after ready, as the protocol requires.
//
// Timeline of a slow read (slave accepts at cycle T):
//   T    PASS: slave sees valid and does its read; master held off (ready=0).
//   T+1  CAP : request masked from the slave; rdata_slow_i registered; ready=1.
//   T+2  PASS: registered data driven to the master (sampled one cycle after ready).
module anv32_bus_read_pipe
    import anv32_bus_pkg::*;
(
    input  logic        clk_i,
    input  logic        rst_i,

    input  bus_req_t    m_req_i,       // from the core
    output bus_rsp_t    m_rsp_o,

    output bus_req_t    s_req_o,       // to the fast-bus decoder
    input  bus_rsp_t    s_rsp_i,       // decoder response (ready/fast used here)

    input  logic [31:0] rdata_fast_i,  // fast slaves only (combinational)
    input  logic [31:0] rdata_slow_i   // slow slaves only (registered here)
);
    typedef enum logic {PASS, CAP} state_t;
    state_t      state_q;
    logic [31:0] rdata_slow_q;  // captured slow-read data
    logic        present_q;     // drive the registered slow data this cycle

    wire is_read = (m_req_i.we == 4'b0000);

    // A slow read accepted by the slave this cycle (first cycle it reports
    // ready with fast == 0). Writes and fast reads never trigger it.
    wire slow_accept = (state_q == PASS) && m_req_i.valid && is_read
                       && s_rsp_i.ready && !s_rsp_i.fast;

    always_comb begin
        // Default: transparent pass-through (fast reads, writes, idle). The
        // core read data comes from the fast bus, which carries no slow slave.
        s_req_o       = m_req_i;
        m_rsp_o.ready = s_rsp_i.ready;
        m_rsp_o.fast  = s_rsp_i.fast;
        m_rsp_o.rdata = present_q ? rdata_slow_q : rdata_fast_i;

        if (state_q == PASS) begin
            // Hold the master off for one cycle; the slave reads now.
            if (slow_accept) m_rsp_o.ready = 1'b0;
        end else begin // CAP: complete the slow read to the master
            s_req_o.valid = 1'b0;   // do not re-issue the held request
            m_rsp_o.ready = 1'b1;
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q   <= PASS;
            rdata_slow_q <= '0;
            present_q <= 1'b0;
        end else begin
            present_q <= 1'b0;
            unique case (state_q)
                PASS: if (slow_accept) state_q <= CAP;
                CAP: begin
                    rdata_slow_q <= rdata_slow_i; // slow data valid this cycle
                    present_q    <= 1'b1;         // deliver it next cycle
                    state_q      <= PASS;
                end
            endcase
        end
    end

endmodule
