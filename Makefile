# Verilator test runner for anv32.
#
# Common usage:
#   make                 # run the decode/execute stage test
#   make de              # same as above
#   make fetch_top       # run the top-level fetch test
#   make all             # run every registered test
#   make test TEST=de    # run a selected registered test
#   make hex             # (re)generate byte-lane hex from PROG
#   make WARN=1 de       # show Verilator lint warnings

SHELL := /bin/bash

VERILATOR ?= verilator
PYTHON    ?= python3
OBJ_DIR   ?= obj_dir
TEST      ?= de

SW_CC      ?= riscv64-unknown-elf-gcc
SW_OBJCOPY ?= riscv64-unknown-elf-objcopy
SW_OBJDUMP ?= riscv64-unknown-elf-objdump
SPIKE      ?= spike
C_SRC      ?= $(if $(C),$(C),sw/examples/smoke.c)
SW_NAME    ?= $(basename $(notdir $(C_SRC)))
SW_KEEP_DIR ?= build/sw/$(SW_NAME)
ASM_SRC    ?= $(if $(ASM),$(ASM),sw/examples/hazard_jalr_raw.S)
ASM_NAME   ?= $(basename $(notdir $(ASM_SRC)))
ASM_KEEP_DIR ?= build/asm/$(ASM_NAME)
FPGA_DIR   ?= fpga/gowin/anv32/src
FPGA_PROG  ?= prog
FPGA_FILE  ?= $(FILE)
FPGA_C_SRC ?= $(if $(C),$(C),sw/fpga/led.c)
FPGA_C_NAME ?= $(basename $(notdir $(FPGA_C_SRC)))
FPGA_C_BUILD_DIR ?= build/fpga/c/$(FPGA_C_NAME)
FPGA_ASM_SRC ?= $(if $(ASM),$(ASM),sw/fpga/led.S)
FPGA_ASM_NAME ?= $(basename $(notdir $(FPGA_ASM_SRC)))
FPGA_ASM_BUILD_DIR ?= build/fpga/asm/$(FPGA_ASM_NAME)
GOLDEN_ASM_SRC ?= $(if $(ASM),$(ASM),sw/examples/hazard_auipc_jalr.S)
GOLDEN_ASM_NAME ?= $(basename $(notdir $(GOLDEN_ASM_SRC)))
GOLDEN_KEEP_DIR ?= build/golden/asm/$(GOLDEN_ASM_NAME)
LINKER     ?= sw/common/link.ld
GOLDEN_LINKER ?= sw/common/link_80000000.ld
PC_RESET_VALUE ?= 0
GOLDEN_PC_RESET_VALUE ?= 2147483648
SPIKE_ISA  ?= rv32i_zicsr
SPIKE_PRIV ?= m
SPIKE_INSNS ?= 200
KEEP       ?=
CYCLES     ?= 80
ASM_LINES  ?= 120
TRACE      ?= 0
DETAIL     ?= 0
PIPELINE_LOG ?=
SPIKE_RAW_LOG ?=
SPIKE_NORM_LOG ?=
CORE_NORM_LOG ?=
DIFF_LOG ?=
ASM_HARD_CYCLES ?= 180
ASM_HARD_SPIKE_INSNS ?= 180
ASM_HARD_TESTS ?= \
	sw/examples/rv32i_alu_stress.S \
	sw/examples/rv32i_branch_jump_stress.S \
	sw/examples/rv32i_load_store_stress.S \
	sw/examples/rv32i_hazard_stress.S \
	sw/examples/load_timing.S \
	sw/examples/hazard_raw.S \
	sw/examples/hazard_auipc_jalr.S

COMMON_PKGS := \
	rtl/include/anv32_config_pkg.sv \
	rtl/include/anv32_isa_pkg.sv

# ---------------------------------------------------------------------------
# Byte-lane hex generation
#
# A program is held as one 32-bit word per line in $(HEX_DIR)/$(PROG).hex.
# tools/split_hex.py splits it into prog_lane0.hex .. prog_lane3.hex, one byte
# per line, matching the byte-lane-split BRAM:
#     $readmemh($sformatf("%s_lane%0d.hex", INIT_FILE, i), lane[i].mem)
# The same four files feed both Verilator sim and Gowin synthesis.
# ---------------------------------------------------------------------------
HEX_DIR   ?= sim/hex
PROG      ?= prog
HEX_SPLIT := tools/split_hex.py
BIN_TO_HEX := tools/bin_to_hex.py
BUILD_RV32 := tools/build_rv32_program.py
BUILD_RV32_ASM := tools/build_rv32_asm_program.py
RUN_SPIKE_LOG := tools/run_spike_log.py
DIFF_COMMIT_LOGS := tools/diff_commit_logs.py

HEX_SRC   := $(HEX_DIR)/$(PROG).hex
LANE_IDX  := 0 1 2 3
LANE_HEX  := $(foreach n,$(LANE_IDX),$(HEX_DIR)/$(PROG)_lane$(n).hex)

FETCH_TEST_HEX_SRC  := sim/data/fetch_test.hex
FETCH_TEST_LANE_HEX := $(foreach n,$(LANE_IDX),sim/data/fetch_test_lane$(n).hex)

# One recipe produces all four lane files (grouped target, GNU Make >= 4.3).
$(LANE_HEX) &: $(HEX_SRC) $(HEX_SPLIT)
	$(PYTHON) $(HEX_SPLIT) $(HEX_SRC) $(HEX_DIR)/$(PROG)

$(FETCH_TEST_LANE_HEX) &: $(FETCH_TEST_HEX_SRC) $(HEX_SPLIT)
	$(PYTHON) $(HEX_SPLIT) $(FETCH_TEST_HEX_SRC) sim/data/fetch_test

# ---------------------------------------------------------------------------
# Registered tests
#
# Per test:  TOP_<t>  top module
#            SRC_<t>  source list
#            HEX_<t>  hex prerequisites (lane files) needed at run time, if any
# ---------------------------------------------------------------------------
TESTS := de m fetch_top

TOP_de := anv32i1_DE_stage_tb
SRC_de := \
	$(COMMON_PKGS) \
	rtl/core/common/anv32_alu.sv \
	rtl/core/common/anv32_decoder.sv \
	rtl/core/anv32i1/stages/anv32i1_DE_stage.sv \
	sim/tb/anv32i/tb_DE_stage.sv
HEX_de :=

TOP_m := anv32i1_M_stage_tb
SRC_m := \
	$(COMMON_PKGS) \
	rtl/core/anv32i1/stages/anv32i1_M_stage.sv \
	sim/tb/anv32i/tb_M_stage.sv
HEX_m :=

TOP_fetch_top := tb_fetch_stage
SRC_fetch_top := \
	$(COMMON_PKGS) \
	rtl/common/mem/anv32_bram_tdp.sv \
	rtl/core/anv32i1/stages/anv32i1_fetch_stage.sv \
	rtl/core/anv32i1/anv32i1_top.sv \
	sim/tb/anv32i/tb_top_fetchtest.sv
HEX_fetch_top := $(FETCH_TEST_LANE_HEX)

SRC_program_fetch := \
	$(COMMON_PKGS) \
	rtl/common/mem/anv32_bram_tdp.sv \
	rtl/core/anv32i1/stages/anv32i1_fetch_stage.sv \
	rtl/core/anv32i1/anv32i1_top.sv \
	sim/tb/anv32i/tb_program_fetch.sv

ANV32I1_TOP_SRC := \
	$(COMMON_PKGS) \
	rtl/common/mem/anv32_bram_tdp.sv \
	rtl/core/common/anv32_regfile.sv \
	rtl/core/common/anv32_alu.sv \
	rtl/core/common/anv32_decoder.sv \
	rtl/core/anv32i1/stages/anv32i1_fetch_stage.sv \
	rtl/core/anv32i1/stages/anv32i1_DE_stage.sv \
	rtl/core/anv32i1/stages/anv32i1_M_stage.sv \
	rtl/core/anv32i1/stages/anv32i1_W_stage.sv \
	rtl/core/anv32i1/anv32i1_top.sv \
	rtl/core/anv32i1/anv32i1_hazard_unit.sv

SRC_cpu_trace := \
	$(ANV32I1_TOP_SRC) \
	sim/tb/anv32i/tb_cpu_trace.sv

VERILATOR_WARNINGS_QUIET := \
	-Wno-DECLFILENAME \
	-Wno-EOFNEWLINE \
	-Wno-TIMESCALEMOD \
	-Wno-UNUSEDSIGNAL \
	-Wno-UNUSEDPARAM \
	-Wno-WIDTHEXPAND \
	-Wno-BLKSEQ \
	-Wno-PINCONNECTEMPTY

ifeq ($(WARN),1)
VERILATOR_WARNINGS :=
else
VERILATOR_WARNINGS := $(VERILATOR_WARNINGS_QUIET)
endif

VERILATOR_FLAGS ?= -sv --binary --timing -Wall -Wno-fatal
VERILATOR_FLAGS += $(VERILATOR_WARNINGS) -Mdir $(OBJ_DIR) $(EXTRA_VFLAGS)

top_for = $(TOP_$(1))
src_for = $(SRC_$(1))
bin_for = $(OBJ_DIR)/V$(call top_for,$(1))
check_test = $(if $(filter $(1),$(TESTS)),,$(error Unknown test '$(1)'. Known tests: $(TESTS)))

.DEFAULT_GOAL := de

.PHONY: all help list test hex sw-fetch cpu-run asm-run fpga fpga-c fpga-asm asm-golden-run asm-diff-test asm-hard-test c-fetch c-run $(TESTS) build-% run-% clean
.SECONDEXPANSION:

all: $(addprefix run-,$(TESTS))

test: run-$(TEST)

$(TESTS): %: run-%

# Generate lane hex on demand: `make hex` or `make hex PROG=other`
hex: $(LANE_HEX)

sw-fetch:
	@set -euo pipefail; \
	src="$(C_SRC)"; \
	name="$(SW_NAME)"; \
	keep="$(KEEP)"; \
	if [ -n "$$keep" ]; then \
		work_dir="$(SW_KEEP_DIR)"; \
		mkdir -p "$$work_dir"; \
	else \
		work_dir="$$(mktemp -d)"; \
		trap 'rm -rf "$$work_dir"' EXIT; \
	fi; \
	echo "SW build: $$src -> $$work_dir"; \
	$(PYTHON) $(BUILD_RV32) \
		--src "$$src" \
		--out-dir "$$work_dir" \
		--name "$$name" \
		--cc "$(SW_CC)" \
		--objcopy "$(SW_OBJCOPY)" \
		--objdump "$(SW_OBJDUMP)" \
		--linker "$(LINKER)" \
		--bin-to-hex "$(BIN_TO_HEX)" \
		--split-hex "$(HEX_SPLIT)" \
		--python "$(PYTHON)"; \
	words="$$(wc -l < "$$work_dir/$$name.hex")"; \
	echo "Program image: $$words words"; \
	$(VERILATOR) $(VERILATOR_FLAGS) \
		--top-module tb_program_fetch \
		-GINIT_FILE=\"$$work_dir/$$name\" \
		-GWORD_HEX_FILE=\"$$work_dir/$$name.hex\" \
		-GPROGRAM_WORDS=$$words \
		-GPC_RESET_VALUE=$(PC_RESET_VALUE) \
		$(SRC_program_fetch); \
	$(OBJ_DIR)/Vtb_program_fetch; \
	if [ -n "$$keep" ]; then \
		keep_lc=",$$(printf '%s' "$$keep" | tr ' ' ','),"; \
		case "$$keep_lc" in \
			*,all,*) ;; \
			*) \
				case "$$keep_lc" in *,asm,*) ;; *) rm -f "$$work_dir/$$name.s" ;; esac; \
				case "$$keep_lc" in *,hex,*) ;; *) rm -f "$$work_dir/$$name.hex" ;; esac; \
				case "$$keep_lc" in *,lanes,*) ;; *) rm -f "$$work_dir/$$name"_lane[0-3].hex ;; esac; \
				case "$$keep_lc" in *,elf,*) ;; *) rm -f "$$work_dir/$$name.elf" ;; esac; \
				case "$$keep_lc" in *,bin,*) ;; *) rm -f "$$work_dir/$$name.bin" ;; esac; \
				case "$$keep_lc" in *,dump,*) ;; *) rm -f "$$work_dir/$$name.dump" ;; esac; \
				case "$$keep_lc" in *,map,*) ;; *) rm -f "$$work_dir/$$name.map" ;; esac; \
				case "$$keep_lc" in *,obj,*) ;; *) rm -f "$$work_dir/$$name.o" "$$work_dir/crt0.o" ;; esac; \
				;; \
		esac; \
		echo "Kept artifacts in $$work_dir (KEEP=$$keep)"; \
	fi

c-fetch c-run: sw-fetch

fpga:
	@set -euo pipefail; \
	file="$(FPGA_FILE)"; \
	if [ -z "$$file" ]; then \
		$(MAKE) --no-print-directory fpga-c; \
	else \
		case "$$file" in \
			*.c) \
				$(MAKE) --no-print-directory fpga-c C="$$file"; \
				;; \
			*.S|*.s) \
				$(MAKE) --no-print-directory fpga-asm ASM="$$file"; \
				;; \
			*) \
				echo "Unsupported FPGA source '$$file'"; \
				echo "Use .c, .S, or .s"; \
				exit 2; \
				;; \
		esac; \
	fi

fpga-c:
	@set -euo pipefail; \
	src="$(FPGA_C_SRC)"; \
	name="$(FPGA_C_NAME)"; \
	work_dir="$(FPGA_C_BUILD_DIR)"; \
	mkdir -p "$$work_dir" "$(FPGA_DIR)"; \
	echo "FPGA C build: $$src -> $(FPGA_DIR)/$(FPGA_PROG)_lane[0-3].hex"; \
	$(PYTHON) $(BUILD_RV32) \
		--src "$$src" \
		--out-dir "$$work_dir" \
		--name "$$name" \
		--cc "$(SW_CC)" \
		--objcopy "$(SW_OBJCOPY)" \
		--objdump "$(SW_OBJDUMP)" \
		--linker "$(LINKER)" \
		--bin-to-hex "$(BIN_TO_HEX)" \
		--split-hex "$(HEX_SPLIT)" \
		--python "$(PYTHON)"; \
	cp "$$work_dir/$$name.hex" "$(FPGA_DIR)/$(FPGA_PROG).hex"; \
	for n in 0 1 2 3; do \
		cp "$$work_dir/$${name}_lane$${n}.hex" "$(FPGA_DIR)/$(FPGA_PROG)_lane$${n}.hex"; \
	done; \
	echo "Wrote $(FPGA_DIR)/$(FPGA_PROG).hex and $(FPGA_DIR)/$(FPGA_PROG)_lane[0-3].hex"; \
	echo "Disassembly: $$work_dir/$$name.dump"

fpga-asm:
	@set -euo pipefail; \
	src="$(FPGA_ASM_SRC)"; \
	name="$(FPGA_ASM_NAME)"; \
	work_dir="$(FPGA_ASM_BUILD_DIR)"; \
	mkdir -p "$$work_dir" "$(FPGA_DIR)"; \
	echo "FPGA ASM build: $$src -> $(FPGA_DIR)/$(FPGA_PROG)_lane[0-3].hex"; \
	$(PYTHON) $(BUILD_RV32_ASM) \
		--src "$$src" \
		--out-dir "$$work_dir" \
		--name "$$name" \
		--cc "$(SW_CC)" \
		--objcopy "$(SW_OBJCOPY)" \
		--objdump "$(SW_OBJDUMP)" \
		--linker "$(LINKER)" \
		--bin-to-hex "$(BIN_TO_HEX)" \
		--split-hex "$(HEX_SPLIT)" \
		--python "$(PYTHON)"; \
	cp "$$work_dir/$$name.hex" "$(FPGA_DIR)/$(FPGA_PROG).hex"; \
	for n in 0 1 2 3; do \
		cp "$$work_dir/$${name}_lane$${n}.hex" "$(FPGA_DIR)/$(FPGA_PROG)_lane$${n}.hex"; \
	done; \
	echo "Wrote $(FPGA_DIR)/$(FPGA_PROG).hex and $(FPGA_DIR)/$(FPGA_PROG)_lane[0-3].hex"; \
	echo "Disassembly: $$work_dir/$$name.dump"

cpu-run:
	@set -euo pipefail; \
	src="$(C_SRC)"; \
	name="$(SW_NAME)"; \
	work_dir="$(SW_KEEP_DIR)"; \
	mkdir -p "$$work_dir"; \
	echo "SW build: $$src -> $$work_dir"; \
	$(PYTHON) $(BUILD_RV32) \
		--src "$$src" \
		--out-dir "$$work_dir" \
		--name "$$name" \
		--cc "$(SW_CC)" \
		--objcopy "$(SW_OBJCOPY)" \
		--objdump "$(SW_OBJDUMP)" \
		--linker "$(LINKER)" \
		--bin-to-hex "$(BIN_TO_HEX)" \
		--split-hex "$(HEX_SPLIT)" \
		--python "$(PYTHON)"; \
	echo; \
	echo "Compiler assembly: $$work_dir/$$name.s"; \
	echo "Linked disassembly: $$work_dir/$$name.dump"; \
	echo "Memory image: $$work_dir/$$name.hex and $$work_dir/$${name}_lane[0-3].hex"; \
	echo; \
	echo "---- linked disassembly (first $(ASM_LINES) lines) ----"; \
	sed -n '1,$(ASM_LINES)p' "$$work_dir/$$name.dump"; \
	echo "---- cpu trace ($(CYCLES) cycles max) ----"; \
	trace_flags=""; \
	trace_arg=""; \
	if [ "$(TRACE)" = "1" ]; then \
		trace_flags="--trace"; \
		trace_arg="+trace"; \
	fi; \
	if [ "$(DETAIL)" = "1" ]; then \
		trace_arg="$$trace_arg +detail"; \
	fi; \
	if [ -n "$(PIPELINE_LOG)" ]; then \
		mkdir -p "$$(dirname "$(PIPELINE_LOG)")"; \
		trace_arg="$$trace_arg +log=$(PIPELINE_LOG)"; \
	fi; \
	$(VERILATOR) $(VERILATOR_FLAGS) $$trace_flags \
		--top-module tb_cpu_trace \
		-GINIT_FILE=\"$$work_dir/$$name\" \
		-GMAX_CYCLES=$(CYCLES) \
		-GPC_RESET_VALUE=$(PC_RESET_VALUE) \
		$(SRC_cpu_trace); \
	$(OBJ_DIR)/Vtb_cpu_trace $$trace_arg; \
	if [ -n "$(PIPELINE_LOG)" ]; then \
		echo "Pipeline log: $(PIPELINE_LOG)"; \
	fi; \
	if [ "$(TRACE)" = "1" ]; then \
		echo "Waveform: $(OBJ_DIR)/cpu_trace.vcd"; \
	fi

asm-run:
	@set -euo pipefail; \
	src="$(ASM_SRC)"; \
	name="$(ASM_NAME)"; \
	work_dir="$(ASM_KEEP_DIR)"; \
	mkdir -p "$$work_dir"; \
	echo "ASM build: $$src -> $$work_dir"; \
	$(PYTHON) $(BUILD_RV32_ASM) \
		--src "$$src" \
		--out-dir "$$work_dir" \
		--name "$$name" \
		--cc "$(SW_CC)" \
		--objcopy "$(SW_OBJCOPY)" \
		--objdump "$(SW_OBJDUMP)" \
		--linker "$(LINKER)" \
		--bin-to-hex "$(BIN_TO_HEX)" \
		--split-hex "$(HEX_SPLIT)" \
		--python "$(PYTHON)"; \
	echo; \
	echo "Assembly source: $$src"; \
	echo "Linked disassembly: $$work_dir/$$name.dump"; \
	echo "Memory image: $$work_dir/$$name.hex and $$work_dir/$${name}_lane[0-3].hex"; \
	echo; \
	echo "---- linked disassembly (first $(ASM_LINES) lines) ----"; \
	sed -n '1,$(ASM_LINES)p' "$$work_dir/$$name.dump"; \
	echo "---- cpu trace ($(CYCLES) cycles max) ----"; \
	trace_flags=""; \
	trace_arg=""; \
	if [ "$(TRACE)" = "1" ]; then \
		trace_flags="--trace"; \
		trace_arg="+trace"; \
	fi; \
	if [ "$(DETAIL)" = "1" ]; then \
		trace_arg="$$trace_arg +detail"; \
	fi; \
	if [ -n "$(PIPELINE_LOG)" ]; then \
		mkdir -p "$$(dirname "$(PIPELINE_LOG)")"; \
		trace_arg="$$trace_arg +log=$(PIPELINE_LOG)"; \
	fi; \
	$(VERILATOR) $(VERILATOR_FLAGS) $$trace_flags \
		--top-module tb_cpu_trace \
		-GINIT_FILE=\"$$work_dir/$$name\" \
		-GMAX_CYCLES=$(CYCLES) \
		-GPC_RESET_VALUE=$(PC_RESET_VALUE) \
		$(SRC_cpu_trace); \
	$(OBJ_DIR)/Vtb_cpu_trace $$trace_arg; \
	if [ -n "$(PIPELINE_LOG)" ]; then \
		echo "Pipeline log: $(PIPELINE_LOG)"; \
	fi; \
	if [ "$(TRACE)" = "1" ]; then \
		echo "Waveform: $(OBJ_DIR)/cpu_trace.vcd"; \
	fi

asm-golden-run:
	@set -euo pipefail; \
	src="$(GOLDEN_ASM_SRC)"; \
	name="$(GOLDEN_ASM_NAME)"; \
	work_dir="$(GOLDEN_KEEP_DIR)"; \
	raw_log="$(if $(SPIKE_RAW_LOG),$(SPIKE_RAW_LOG),$(GOLDEN_KEEP_DIR)/spike.raw.log)"; \
	norm_log="$(if $(SPIKE_NORM_LOG),$(SPIKE_NORM_LOG),$(GOLDEN_KEEP_DIR)/spike.norm.log)"; \
	pipe_log="$(if $(PIPELINE_LOG),$(PIPELINE_LOG),$(GOLDEN_KEEP_DIR)/pipeline.log)"; \
	core_log="$(CORE_NORM_LOG)"; \
	mkdir -p "$$work_dir"; \
	echo "ASM golden build: $$src -> $$work_dir"; \
	$(PYTHON) $(BUILD_RV32_ASM) \
		--src "$$src" \
		--out-dir "$$work_dir" \
		--name "$$name" \
		--cc "$(SW_CC)" \
		--objcopy "$(SW_OBJCOPY)" \
		--objdump "$(SW_OBJDUMP)" \
		--linker "$(GOLDEN_LINKER)" \
		--bin-to-hex "$(BIN_TO_HEX)" \
		--split-hex "$(HEX_SPLIT)" \
		--python "$(PYTHON)"; \
	echo; \
	echo "---- linked disassembly (first $(ASM_LINES) lines) ----"; \
	sed -n '1,$(ASM_LINES)p' "$$work_dir/$$name.dump"; \
	echo "---- spike golden ($(SPIKE_INSNS) instructions max) ----"; \
	$(PYTHON) $(RUN_SPIKE_LOG) \
		--elf "$$work_dir/$$name.elf" \
		--raw-log "$$raw_log" \
		--norm-log "$$norm_log" \
		--spike "$(SPIKE)" \
		--isa "$(SPIKE_ISA)" \
		--priv "$(SPIKE_PRIV)" \
		--instructions "$(SPIKE_INSNS)" \
		--pc-base 0x80000000; \
	echo "---- cpu trace ($(CYCLES) cycles max) ----"; \
	trace_flags=""; \
	trace_arg="+log=$$pipe_log"; \
	if [ -n "$$core_log" ]; then \
		mkdir -p "$$(dirname "$$core_log")"; \
		trace_arg="$$trace_arg +commit_log=$$core_log"; \
	fi; \
	if [ "$(TRACE)" = "1" ]; then \
		trace_flags="--trace"; \
		trace_arg="$$trace_arg +trace"; \
	fi; \
	if [ "$(DETAIL)" = "1" ]; then \
		trace_arg="$$trace_arg +detail"; \
	fi; \
	mkdir -p "$$(dirname "$$pipe_log")"; \
	$(VERILATOR) $(VERILATOR_FLAGS) $$trace_flags \
		--top-module tb_cpu_trace \
		-GINIT_FILE=\"$$work_dir/$$name\" \
		-GMAX_CYCLES=$(CYCLES) \
		-GPC_RESET_VALUE=$(GOLDEN_PC_RESET_VALUE) \
		-GCOMMIT_PC_BASE=$(GOLDEN_PC_RESET_VALUE) \
		$(SRC_cpu_trace); \
	$(OBJ_DIR)/Vtb_cpu_trace $$trace_arg; \
	echo "Pipeline log: $$pipe_log"; \
	echo "Spike raw log: $$raw_log"; \
	echo "Spike normalized log: $$norm_log"; \
	if [ -n "$$core_log" ]; then \
		echo "Core normalized log: $$core_log"; \
	fi; \
	if [ "$(TRACE)" = "1" ]; then \
		echo "Waveform: $(OBJ_DIR)/cpu_trace.vcd"; \
	fi

asm-diff-test:
	@set -euo pipefail; \
	raw_log="$(if $(SPIKE_RAW_LOG),$(SPIKE_RAW_LOG),$(GOLDEN_KEEP_DIR)/spike.raw.log)"; \
	norm_log="$(if $(SPIKE_NORM_LOG),$(SPIKE_NORM_LOG),$(GOLDEN_KEEP_DIR)/spike.norm.log)"; \
	pipe_log="$(if $(PIPELINE_LOG),$(PIPELINE_LOG),$(GOLDEN_KEEP_DIR)/pipeline.log)"; \
	core_log="$(if $(CORE_NORM_LOG),$(CORE_NORM_LOG),$(GOLDEN_KEEP_DIR)/core.norm.log)"; \
	diff_log="$(if $(DIFF_LOG),$(DIFF_LOG),$(GOLDEN_KEEP_DIR)/commit.diff)"; \
	$(MAKE) --no-print-directory asm-golden-run \
		SPIKE_RAW_LOG="$$raw_log" \
		SPIKE_NORM_LOG="$$norm_log" \
		PIPELINE_LOG="$$pipe_log" \
		CORE_NORM_LOG="$$core_log"; \
	echo "---- spike/core diff ----"; \
	$(PYTHON) $(DIFF_COMMIT_LOGS) \
		--spike-log "$$norm_log" \
		--core-log "$$core_log" \
		--diff-out "$$diff_log"; \
	echo "Diff log: $$diff_log"

asm-hard-test:
	@set -euo pipefail; \
	for asm in $(ASM_HARD_TESTS); do \
		echo "---- $$asm ----"; \
		$(MAKE) --no-print-directory asm-diff-test \
			ASM="$$asm" \
			CYCLES=$(ASM_HARD_CYCLES) \
			SPIKE_INSNS=$(ASM_HARD_SPIKE_INSNS); \
	done

build-%:
	$(call check_test,$*)
	$(VERILATOR) $(VERILATOR_FLAGS) --top-module $(call top_for,$*) $(call src_for,$*)

# Hex prerequisites are pulled in per-test via second expansion ($$).
run-%: build-% $$(HEX_$$*)
	$(call bin_for,$*)

list:
	@printf '%s\n' $(TESTS)

help:
	@echo "Usage:"
	@echo "  make                 Run default test: de"
	@echo "  make de              Run tb_DE_stage.sv"
	@echo "  make m               Run tb_M_stage.sv"
	@echo "  make fetch_top       Run tb_top_fetchtest.sv (needs lane hex)"
	@echo "  make all             Run all registered tests"
	@echo "  make test TEST=name  Run a registered test"
	@echo "  make hex             Generate byte-lane hex from PROG ($(PROG))"
	@echo "  make sw-fetch        Build C_SRC and verify program image through fetch"
	@echo "  make sw-fetch KEEP=asm,hex,lanes"
	@echo "                       Keep selected intermediates under $(SW_KEEP_DIR)"
	@echo "  make cpu-run C=file.c"
	@echo "                       Build C, print disassembly, run top-level CPU trace"
	@echo "  make asm-run ASM=file.S"
	@echo "                       Build assembly, print disassembly, run CPU trace"
	@echo "  make fpga FILE=file.c"
	@echo "                       Build C for Gowin BRAM image under $(FPGA_DIR)"
	@echo "  make fpga FILE=file.S"
	@echo "                       Build assembly for Gowin BRAM image"
	@echo "  make fpga-c C=file.c / make fpga-asm ASM=file.S"
	@echo "                       Explicit FPGA C/assembly build targets"
	@echo "  make asm-golden-run ASM=file.S"
	@echo "                       Build at 0x80000000, run Spike golden and CPU trace"
	@echo "  make asm-diff-test ASM=file.S"
	@echo "                       Diff Spike golden commit log against the core"
	@echo "  make asm-hard-test  Run the RV32I hard assembly diff suite"
	@echo "  make cpu-run CYCLES=40 TRACE=1"
	@echo "                       Limit cycles and emit $(OBJ_DIR)/cpu_trace.vcd"
	@echo "  make cpu-run PIPELINE_LOG=build/sw/trace.log"
	@echo "                       Write detailed pipeline trace to a file"
	@echo "  make WARN=1 de       Show Verilator lint warnings"
	@echo "  make clean           Remove build output and generated hex"
	@echo
	@echo "Variables:"
	@echo "  PROG=name            Program base name in $(HEX_DIR) (default prog)"
	@echo "  C_SRC=file.c         C source for sw-fetch (default $(C_SRC))"
	@echo "  ASM_SRC=file.S       Assembly source for asm-run (default $(ASM_SRC))"
	@echo "  FILE=file.c|file.S   Source for make fpga"
	@echo "  FPGA_PROG=name       Gowin BRAM image base in $(FPGA_DIR) (default prog)"
	@echo "  GOLDEN_ASM_SRC=file.S"
	@echo "                       Assembly source for asm-golden-run"
	@echo "  SW_NAME=name         Artifact base name (default from C_SRC)"
	@echo "  ASM_NAME=name        Artifact base name for asm-run"
	@echo "  LINKER=file.ld       Linker for normal C/ASM runs (default $(LINKER))"
	@echo "  GOLDEN_LINKER=file.ld"
	@echo "                       Linker for Spike-compatible golden runs"
	@echo "  SPIKE_INSNS=n        Max Spike instructions for golden log"
	@echo "  KEEP=asm,hex,lanes   Keep C assembly, word hex, and lane hex"
	@echo "  CYCLES=n             Max CPU trace cycles (default $(CYCLES))"
	@echo "  TRACE=1              Enable Verilator VCD trace for cpu-run"
	@echo "  DETAIL=1             Also print detailed per-cycle blocks to stdout"
	@echo "  PIPELINE_LOG=file    Write detailed pipeline trace to file"
	@echo "  CORE_NORM_LOG=file   Write normalized core commit log"
	@echo "  DIFF_LOG=file        Write Spike/core diff output"
	@echo
	@echo "Registered tests:"
	@printf '  %s\n' $(TESTS)

clean:
	rm -rf $(OBJ_DIR)
	rm -f $(HEX_DIR)/*_lane[0-3].hex
	rm -f sim/data/*_lane[0-3].hex
	rm -rf build/sw
