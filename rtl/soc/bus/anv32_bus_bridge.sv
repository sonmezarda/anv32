// Register slice between the fast bus and the peripheral bus. A request is
// captured first and shown to the peripheral side one cycle later, which
// splits the long path from the master's address to the peripheral read mux.
// Each peripheral access costs one extra cycle. Read data comes back one
// cycle after the transfer on both sides, so it passes straight through.
module anv32_bus_bridge
    import anv32_bus_pkg::*;
(
    input  logic     clk_i,
    input  logic     rst_i,

    input  bus_req_t m_req_i,   // from the fast bus
    output bus_rsp_t m_rsp_o,

    output bus_req_t s_req_o,   // to the peripheral bus
    input  bus_rsp_t s_rsp_i
);
    logic     busy_q;   // a captured request is waiting on the peripheral side
    bus_req_t req_q;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            busy_q <= 1'b0;
            req_q  <= '0;
        end else if (!busy_q) begin
            if (m_req_i.valid) begin
                busy_q <= 1'b1;
                req_q  <= m_req_i;
            end
        end else if (s_rsp_i.ready) begin
            busy_q <= 1'b0;
        end
    end

    always_comb begin
        s_req_o       = req_q;
        s_req_o.valid = busy_q;
    end

    // The master holds its request until ready, so the captured copy is still
    // the request being accepted here.
    assign m_rsp_o.ready = busy_q && s_rsp_i.ready;
    // Everything behind the bridge is a slow (registered-at-boundary) read, so
    // report a constant fast=0. Keeping it constant lets the boundary stage
    // statically route this subtree's read data onto the slow (registered) bus.
    assign m_rsp_o.fast  = 1'b0;
    assign m_rsp_o.rdata = s_rsp_i.rdata;

endmodule
