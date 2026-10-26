// Register-file front end for a 4 KiB peripheral slot. It answers every
// request in one cycle and turns accesses into per-register strobes, so a
// peripheral only provides its register values and reacts to the strobes.
//
// Slot layout (RP2040-style atomic aliases):
//   0x000-0x3FF  normal access, register n at offset 4*n
//   0x400-0x7FF  XOR alias: new = old ^ wdata
//   0x800-0xBFF  SET alias: new = old | wdata
//   0xC00-0xFFF  CLR alias: new = old & ~wdata
// Reads return the register value at every alias. Byte enables apply after
// the alias operation. Registers past NREGS read as zero and ignore writes.
// Aliases only make sense for plain storage registers; registers with side
// effects (FIFO push/pop, write-1-to-clear) just see the computed value.
module anv32_bus_regs
    import anv32_bus_pkg::*;
#(
    parameter int unsigned NREGS = 4
)(
    input  logic                   clk_i,
    input  logic                   rst_i,

    input  bus_req_t               req_i,
    output bus_rsp_t               rsp_o,

    input  logic [NREGS-1:0][31:0] rdata_i,   // current register values
    output logic [NREGS-1:0]       wr_o,      // write strobe, one cycle
    output logic [NREGS-1:0]       rd_o,      // read strobe, for read side effects
    output logic [31:0]            wdata_o    // value to store in the written register
);
    localparam logic [1:0] ALIAS_NONE = 2'd0;
    localparam logic [1:0] ALIAS_XOR  = 2'd1;
    localparam logic [1:0] ALIAS_SET  = 2'd2;
    localparam logic [1:0] ALIAS_CLR  = 2'd3;
    localparam int unsigned IDX_W     = (NREGS > 1) ? $clog2(NREGS) : 1;

    logic [7:0]       index;      // register number from the address
    logic [IDX_W-1:0] idx;        // the same, sized for the register arrays
    logic [1:0]       alias_op;
    logic             hit;
    logic [31:0]      cur;
    logic [31:0]      next;
    logic [31:0]      rdata_q;

    assign index    = req_i.addr[9:2];
    assign alias_op = req_i.addr[11:10];
    assign idx      = index[IDX_W-1:0];
    assign hit      = 32'(index) < NREGS;
    assign cur      = hit ? rdata_i[idx] : '0;

    always_comb begin
        unique case (alias_op)
            ALIAS_NONE: next = req_i.wdata;
            ALIAS_XOR:  next = cur ^ req_i.wdata;
            ALIAS_SET:  next = cur | req_i.wdata;
            ALIAS_CLR:  next = cur & ~req_i.wdata;
        endcase

        for (int unsigned b = 0; b < 4; b++) begin
            wdata_o[b*8 +: 8] = req_i.we[b] ? next[b*8 +: 8] : cur[b*8 +: 8];
        end
    end

    always_comb begin
        wr_o = '0;
        rd_o = '0;
        if (req_i.valid && hit) begin
            if (req_i.we != 4'b0000) wr_o[idx] = 1'b1;
            else                     rd_o[idx] = 1'b1;
        end
    end

    // Read data is registered: it appears the cycle after the access
    always_ff @(posedge clk_i) begin
        if (rst_i)            rdata_q <= '0;
        else if (req_i.valid) rdata_q <= cur;
    end

    assign rsp_o.ready = 1'b1;
    assign rsp_o.rdata = rdata_q;

endmodule
