verilator --lint-only --timing \
    rtl/include/anv32_config_pkg.sv \
    rtl/include/anv32_isa_pkg.sv \
    rtl/core/common/anv32_decoder.sv \
    rtl/core/common/anv32_csr.sv \
    rtl/core/common/anv32_csr_exec.sv \
    rtl/common/mem/anv32_bram_tdp.sv \
    rtl/core/common/anv32_alu.sv \
    rtl/core/common/anv32_regfile.sv\
    rtl/core/pipe5/anv32_fetch_c1.sv \
    rtl/core/pipe5/anv32_decode_c1.sv \
    rtl/core/anv32i1/anv32_execute_i_c1.sv \
    rtl/core/pipe5/anv32_memory_c1.sv \
    rtl/core/pipe5/anv32_writeback_c1.sv \
    rtl/core/pipe5/anv32_hazard_basic.sv \
    rtl/core/anv32i1/anv32i1_top.sv \
    --top-module anv32i1_top -Wno-TIMESCALEMOD -Wno-WIDTHEXPAND
