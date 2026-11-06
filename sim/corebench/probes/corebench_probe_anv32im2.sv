// corebench probe for anv32im2: counts where the pipeline loses cycles
// inside the ROI and prints one COREBENCH_PROBE line at the end of the run.
// Simulation only; see docs/corebench.md.
//
// A load result can only be forwarded once the load reaches W, so a
// consumer waits in D while the load is in E1, E2 or M. load_use_d1..d3
// count stall episodes by how far behind the load the consumer is (1 =
// the next instruction); each episode costs 4 - distance cycles.
module corebench_probe
    import anv32_isa_pkg::*;
;
    longint unsigned redirects = 0, jumps = 0, jumps_indirect = 0;
    longint unsigned branches = 0, branches_taken = 0;
    longint unsigned branches_backward = 0, branches_backward_taken = 0;
    longint unsigned loads = 0, load_use_stall_cycles = 0, muldiv_stall_cycles = 0;
    longint unsigned load_use_d1 = 0, load_use_d2 = 0, load_use_d3 = 0;
    bit              stalled = 1'b0;

    function automatic bit reads(input dinstr_t c, input logic [4:0] rd);
        return (c.rs1_valid && c.rs1_idx == rd) || (c.rs2_valid && c.rs2_idx == rd);
    endfunction

    // The program's first ROI marker restarts the counts, like the testbench's
    always @(tb_corebench.roi_restart) begin
        redirects = 0; jumps = 0; jumps_indirect = 0; branches = 0; branches_taken = 0;
        branches_backward = 0; branches_backward_taken = 0; loads = 0;
        load_use_stall_cycles = 0; muldiv_stall_cycles = 0; load_use_d1 = 0;
        load_use_d2 = 0; load_use_d3 = 0;
        stalled = 1'b0;
    end

    // Sampled on the falling edge, where every signal has settled for the
    // cycle the testbench counts at the next rising edge: no race with the
    // core or the ROI marker logic.
    always @(negedge tb_corebench.clk) begin
        if (tb_corebench.rst_n && tb_corebench.roi_open) begin
            automatic dinstr_t d  = tb_corebench.dut.u_core.dinstr_decode;
            automatic dinstr_t e1 = tb_corebench.dut.u_core.dinstr;
            automatic dinstr_t e2 = tb_corebench.dut.u_core.dinstr_e2;
            automatic bit raw = tb_corebench.dut.u_core.stall_im2_raw && !tb_corebench.dut.u_core.md_stall;

            if (tb_corebench.dut.u_core.pc_jmp_en) redirects++;
            if (tb_corebench.dut.u_core.e_valid && tb_corebench.dut.u_core.e_pc_changer) begin
                if (e2.op == JAL || e2.op == JALR) begin
                    jumps++;
                    if (e2.op == JALR) jumps_indirect++;
                end else begin
                    branches++;
                    branches_taken += tb_corebench.dut.u_core.e_branch_taken;
                    if (e2.imm[31]) begin
                        branches_backward++;
                        branches_backward_taken += tb_corebench.dut.u_core.e_branch_taken;
                    end
                end
            end

            // Every RAW stall on anv32im2 waits for a load (dividers stall via md_stall)
            if (raw) begin
                load_use_stall_cycles++;
                if (!stalled) begin
                    if (e1.valid && e1.wb_sel == WB_MEM && e1.rd_valid && reads(d, e1.rd_idx)) load_use_d1++;
                    else if (e2.valid && e2.wb_sel == WB_MEM && e2.rd_valid && reads(d, e2.rd_idx)) load_use_d2++;
                    else load_use_d3++;
                end
            end
            stalled = raw;

            if (tb_corebench.dut.u_core.md_stall) muldiv_stall_cycles++;
            if (tb_corebench.dut.u_core.minstr.valid && tb_corebench.dut.u_core.minstr.wb_sel == WB_MEM &&
                !tb_corebench.dut.u_core.stall_w_eff)
                loads++;
        end
    end

    final $display("COREBENCH_PROBE redirects=%0d jumps=%0d jumps_indirect=%0d branches=%0d branches_taken=%0d branches_backward=%0d branches_backward_taken=%0d loads=%0d load_use_stall_cycles=%0d load_use_d1=%0d load_use_d2=%0d load_use_d3=%0d muldiv_stall_cycles=%0d",
                   redirects, jumps, jumps_indirect, branches, branches_taken, branches_backward,
                   branches_backward_taken, loads, load_use_stall_cycles, load_use_d1, load_use_d2,
                   load_use_d3, muldiv_stall_cycles);
endmodule
