verilator --lint-only --timing \
    rtl/include/anv32_config_pkg.sv \
    rtl/include/anv32_isa_pkg.sv \
    rtl/core/common/anv32_decoder.sv \
    rtl/core/common/anv32_csr.sv \
    rtl/core/common/anv32_csr_exec.sv \
    rtl/common/mem/anv32_bram_tdp.sv \
    rtl/core/common/anv32_alu.sv \
    rtl/core/common/anv32_regfile.sv\
    rtl/core/anv32i1/stages/anv32i1_fetch_stage.sv \
    rtl/core/anv32i1/stages/anv32i1_DE_stage.sv \
    rtl/core/anv32i1/stages/anv32i1_M_stage.sv \
    rtl/core/anv32i1/stages/anv32i1_W_stage.sv \
    rtl/core/anv32i1/anv32i1_top.sv \
    --top-module anv32i1_top -Wno-TIMESCALEMOD -Wno-WIDTHEXPAND
