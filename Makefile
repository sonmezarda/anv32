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
C_SRC      ?= $(if $(C),$(C),sw/examples/smoke.c)
SW_NAME    ?= $(basename $(notdir $(C_SRC)))
SW_KEEP_DIR ?= build/sw/$(SW_NAME)
KEEP       ?=

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

.PHONY: all help list test hex sw-fetch c-fetch c-run $(TESTS) build-% run-% clean
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
	@echo "  make WARN=1 de       Show Verilator lint warnings"
	@echo "  make clean           Remove build output and generated hex"
	@echo
	@echo "Variables:"
	@echo "  PROG=name            Program base name in $(HEX_DIR) (default prog)"
	@echo "  C_SRC=file.c         C source for sw-fetch (default $(C_SRC))"
	@echo "  SW_NAME=name         Artifact base name (default from C_SRC)"
	@echo "  KEEP=asm,hex,lanes   Keep C assembly, word hex, and lane hex"
	@echo
	@echo "Registered tests:"
	@printf '  %s\n' $(TESTS)

clean:
	rm -rf $(OBJ_DIR)
	rm -f $(HEX_DIR)/*_lane[0-3].hex
	rm -f sim/data/*_lane[0-3].hex
	rm -rf build/sw
