// corebench adapter for OpenHW CV32E40P (third_party/cv32e40p), configured
// as RV32IMC: no PULP extensions, no FPU. See docs/corebench.md for the
// corebench_core port contract.
//
// OBI is mapped onto the BRAM-like ports by granting every request at once
// and returning rvalid one cycle later, which is when the data arrives.
module corebench_core (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        irq_i,

    output logic        instr_req_o,
    output logic [31:0] instr_addr_o,
    input  logic [31:0] instr_rdata_i,

    output logic        data_req_o,
    output logic        data_we_o,
    output logic [ 3:0] data_be_o,
    output logic [31:0] data_addr_o,
    output logic [31:0] data_wdata_o,
    input  logic [31:0] data_rdata_i,

    output logic        retire_o
);
    logic instr_rvalid, data_rvalid;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            instr_rvalid <= 1'b0;
            data_rvalid  <= 1'b0;
        end else begin
            instr_rvalid <= instr_req_o;
            data_rvalid  <= data_req_o;
        end
    end

    cv32e40p_core #(
        .COREV_PULP      (0),
        .COREV_CLUSTER   (0),
        .FPU             (0),
        .ZFINX           (0),
        .NUM_MHPMCOUNTERS(1)
    ) u_core (
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),
        .pulp_clock_en_i    (1'b1),
        .scan_cg_en_i       (1'b0),
        .boot_addr_i        (32'h0000_0000),
        .mtvec_addr_i       (32'h0000_0000),
        .dm_halt_addr_i     (32'h0000_0000),
        .hart_id_i          (32'h0000_0000),
        .dm_exception_addr_i(32'h0000_0000),
        .instr_req_o        (instr_req_o),
        .instr_gnt_i        (instr_req_o),
        .instr_rvalid_i     (instr_rvalid),
        .instr_addr_o       (instr_addr_o),
        .instr_rdata_i      (instr_rdata_i),
        .data_req_o         (data_req_o),
        .data_gnt_i         (data_req_o),
        .data_rvalid_i      (data_rvalid),
        .data_we_o          (data_we_o),
        .data_be_o          (data_be_o),
        .data_addr_o        (data_addr_o),
        .data_wdata_o       (data_wdata_o),
        .data_rdata_i       (data_rdata_i),
        .apu_busy_o         (),
        .apu_req_o          (),
        .apu_gnt_i          (1'b0),
        .apu_operands_o     (),
        .apu_op_o           (),
        .apu_flags_o        (),
        .apu_rvalid_i       (1'b0),
        .apu_result_i       (32'h0),
        .apu_flags_i        ('0),
        .irq_i              ({20'h0, irq_i, 11'h0}),  // MEIP
        .irq_ack_o          (),
        .irq_id_o           (),
        .debug_req_i        (1'b0),
        .debug_havereset_o  (),
        .debug_running_o    (),
        .debug_halted_o     (),
        .fetch_enable_i     (1'b1),
        .core_sleep_o       ()
    );

`ifdef COREBENCH_SIM
    // Same event that increments minstret (counted when leaving ID)
    assign retire_o = u_core.id_stage_i.mhpmevent_minstret_o;
`else
    assign retire_o = 1'b0;
`endif
endmodule
