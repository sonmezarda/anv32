// ============================================================================
// anv32_config_pkg.sv
// ============================================================================
package anv32_config_pkg;
    localparam int unsigned     XLEN     = 32;
    localparam logic [XLEN-1:0] RESET_PC = 32'h0000_0000;
endpackage