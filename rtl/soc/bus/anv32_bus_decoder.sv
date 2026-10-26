// Routes one bus master to N slaves by address. Slave i owns every address
// with (addr & MASK[i]) == BASE[i]; on an overlap the lowest index wins.
// An address no slave owns is accepted at once and reads as zero.
module anv32_bus_decoder
    import anv32_bus_pkg::*;
#(
    parameter int unsigned N = 4,            // slave count
    parameter logic [N-1:0][31:0] BASE = '0,
    parameter logic [N-1:0][31:0] MASK = '0
)(
    input  logic             clk_i,
    input  logic             rst_i,

    input  bus_req_t         m_req_i, // request from master
    output bus_rsp_t         m_rsp_o, // response to master

    output bus_req_t [N-1:0] s_req_o, // request to slaves
    input  bus_rsp_t [N-1:0] s_rsp_i, // response from slaves

    // Registered acceptance of the in-flight read: who owns the read data this
    // cycle. Exposed so a boundary stage can split fast/slow read data by slave.
    output logic                                 rd_hit_o,
    output logic [((N > 1) ? $clog2(N) : 1)-1:0] rd_sel_o
);
    localparam int unsigned SEL_W = (N > 1) ? $clog2(N) : 1;

    logic [N-1:0]     hit;
    logic             any_hit;
    logic [SEL_W-1:0] sel;

    // Read data arrives one cycle after the transfer, when the address may
    // already belong to the next request, so remember who accepted it.
    logic             rd_hit_q;
    logic [SEL_W-1:0] rd_sel_q;

    always_comb begin
        for (int unsigned i = 0; i < N; i++) begin
            hit[i] = (m_req_i.addr & MASK[i]) == BASE[i];
        end
    end

    // Pick one slave even if the map overlaps: the lowest index wins
    always_comb begin
        any_hit = 1'b0;
        sel     = '0;
        for (int unsigned i = 0; i < N; i++) begin
            if (hit[i] && !any_hit) begin
                any_hit = 1'b1;
                sel     = SEL_W'(i);
            end
        end
    end

    // Every slave sees the request; only the selected one sees valid
    always_comb begin
        for (int unsigned i = 0; i < N; i++) begin
            s_req_o[i]       = m_req_i;
            s_req_o[i].valid = m_req_i.valid && any_hit && (sel == SEL_W'(i));
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            rd_hit_q <= 1'b0;
            rd_sel_q <= '0;
        end else if (m_req_i.valid && m_rsp_o.ready) begin
            rd_hit_q <= any_hit;
            rd_sel_q <= sel;
        end
    end

    always_comb begin
        m_rsp_o.ready = any_hit ? s_rsp_i[sel].ready : 1'b1;
        // fast is valid with ready (request cycle); an unmapped access reads as
        // zero with no wait, so it reports fast.
        m_rsp_o.fast  = any_hit ? s_rsp_i[sel].fast : 1'b1;
        m_rsp_o.rdata = rd_hit_q ? s_rsp_i[rd_sel_q].rdata : '0;
    end

    assign rd_hit_o = rd_hit_q;
    assign rd_sel_o = rd_sel_q;

endmodule
