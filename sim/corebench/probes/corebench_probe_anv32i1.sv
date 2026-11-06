// corebench probe for anv32i1: counts where the pipeline loses cycles
// inside the ROI and prints one COREBENCH_PROBE line at the end of the run.
// Simulation only; see docs/corebench.md.
//
// Loads forward from W into E, so only an instruction right after a load
// stalls, for one cycle: load_use_d1 equals load_use_stall_cycles.
module corebench_probe
    import anv32_isa_pkg::*;
;
    longint unsigned redirects = 0, jumps = 0, jumps_indirect = 0;
    longint unsigned branches = 0, branches_taken = 0;
    longint unsigned branches_backward = 0, branches_backward_taken = 0;
    longint unsigned loads = 0, load_use_stall_cycles = 0;

    // The program's first ROI marker restarts the counts, like the testbench's
    always @(tb_corebench.roi_restart) begin
        redirects = 0; jumps = 0; jumps_indirect = 0; branches = 0; branches_taken = 0;
        branches_backward = 0; branches_backward_taken = 0; loads = 0;
        load_use_stall_cycles = 0;
    end

    // Sampled on the falling edge, where every signal has settled for the
    // cycle the testbench counts at the next rising edge: no race with the
    // core or the ROI marker logic.
    always @(negedge tb_corebench.clk) begin
        if (tb_corebench.rst_n && tb_corebench.roi_open) begin
            automatic dinstr_t e = tb_corebench.dut.u_core.dinstr;

            if (tb_corebench.dut.u_core.pc_jmp_en) redirects++;
            if (tb_corebench.dut.u_core.e_valid && tb_corebench.dut.u_core.e_pc_changer) begin
                if (e.op == JAL || e.op == JALR) begin
                    jumps++;
                    if (e.op == JALR) jumps_indirect++;
                end else begin
                    branches++;
                    branches_taken += tb_corebench.dut.u_core.e_branch_taken;
                    if (e.imm[31]) begin
                        branches_backward++;
                        branches_backward_taken += tb_corebench.dut.u_core.e_branch_taken;
                    end
                end
            end

            if (tb_corebench.dut.u_core.stall_de) load_use_stall_cycles++;
            if (tb_corebench.dut.u_core.minstr.valid && tb_corebench.dut.u_core.minstr.wb_sel == WB_MEM &&
                !tb_corebench.dut.u_core.stall_w_eff)
                loads++;
        end
    end

    final $display("COREBENCH_PROBE redirects=%0d jumps=%0d jumps_indirect=%0d branches=%0d branches_taken=%0d branches_backward=%0d branches_backward_taken=%0d loads=%0d load_use_stall_cycles=%0d load_use_d1=%0d",
                   redirects, jumps, jumps_indirect, branches, branches_taken, branches_backward,
                   branches_backward_taken, loads, load_use_stall_cycles, load_use_stall_cycles);
endmodule
