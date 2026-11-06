// Stand-in for CV32E40P's technology clock gate, used in both corebench
// simulation and FPGA builds. Gating a clock in fabric logic is unsafe on an
// FPGA, so the sleep unit's gate is a pass-through: the core still reports
// sleep on core_sleep_o, its flops just keep receiving the clock.
module cv32e40p_clock_gate (
    input  logic clk_i,
    input  logic en_i,
    input  logic scan_cg_en_i,
    output logic clk_o
);
    assign clk_o = clk_i;
endmodule
