package anv32_bus_pkg;

    // Anv32 Core - Data Bus Types and Protocols
    // Custom protocol rules:
    // if valid == 1 then request is valid
    // if (valid && ready) == 1 then transfer occurs in the same cycle
    // if valid == 1 and ready == 0 then master must hold the request (does not change addr, wdata, we) until ready == 1
    // read value comes back in the next cycle after confirmation of the transfer (ready == 1)
    // valid must not depend combinationally on ready
    //
    // fast: a slave read-timing hint, valid in the same cycle as ready (the
    // request cycle). fast == 1 means the slave's rdata is combinationally
    // valid one cycle after the transfer and can be consumed directly (0 extra
    // wait). fast == 0 means the read must be registered at the core boundary
    // (anv32_bus_read_pipe), which costs one extra cycle but keeps the slave's
    // read data out of the master's combinational path. Unmapped/read-as-zero
    // responses report fast == 1 (no wait).

    typedef struct packed {
        logic        valid;
        logic [31:0] addr;
        logic [31:0] wdata;
        logic [3:0]  we; // we == 4'b0000 means read
    } bus_req_t;

    typedef struct packed {
        logic        ready;
        logic        fast;
        logic [31:0] rdata;
    } bus_rsp_t;

endpackage
