package anv32_bus_pkg;

    // Anv32 Core - Data Bus Types and Protocols
    // Custom protocol rules:
    // if valid == 1 then request is valid
    // if (valid && ready) == 1 then transfer occurs in the same cycle
    // if valid == 1 and ready == 0 then master must hold the request (does not change addr, wdata, we) until ready == 1
    // read value comes back in the next cycle after confirmation of the transfer (ready == 1)
    // valid must not depend combinationally on ready

    typedef struct packed {
        logic        valid;
        logic [31:0] addr;
        logic [31:0] wdata;
        logic [3:0]  we; // we == 4'b0000 means read
    } bus_req_t;

    typedef struct packed {
        logic        ready;
        logic [31:0] rdata;
    } bus_rsp_t;

endpackage
