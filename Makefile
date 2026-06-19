# Verilator test runner for anv32.
#
# Common usage:
#   make                 # run the decode/execute stage test
#   make de              # same as above
#   make fetch_top       # run the top-level fetch test
#   make all             # run every registered test
#   make test TEST=de    # run a selected registered test

SHELL := /bin/bash

VERILATOR ?= verilator
OBJ_DIR   ?= obj_dir
TEST      ?= de

COMMON_PKGS := \
	rtl/include/anv32_config_pkg.sv \
	rtl/include/anv32_isa_pkg.sv

TESTS := de fetch_top

TOP_de := anv32i1_DE_stage_tb
SRC_de := \
	$(COMMON_PKGS) \
	rtl/core/common/anv32_alu.sv \
	rtl/core/common/anv32_decoder.sv \
	rtl/core/anv32i1/stages/anv32i1_DE_stage.sv \
	sim/tb/anv32i/tb_DE_stage.sv

TOP_fetch_top := tb_fetch_stage
SRC_fetch_top := \
	$(COMMON_PKGS) \
	rtl/common/mem/anv32_bram_tdp.sv \
	rtl/core/anv32i1/stages/anv32i1_fetch_stage.sv \
	rtl/core/anv32i1/anv32i1_top.sv \
	sim/tb/anv32i/tb_top_fetchtest.sv

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

.PHONY: all help list test $(TESTS) build-% run-% clean

all: $(addprefix run-,$(TESTS))

test: run-$(TEST)

$(TESTS): %: run-%

build-%:
	$(call check_test,$*)
	$(VERILATOR) $(VERILATOR_FLAGS) --top-module $(call top_for,$*) $(call src_for,$*)

run-%: build-%
	$(call bin_for,$*)

list:
	@printf '%s\n' $(TESTS)

help:
	@echo "Usage:"
	@echo "  make                 Run default test: de"
	@echo "  make de              Run tb_DE_stage.sv"
	@echo "  make fetch_top       Run tb_top_fetchtest.sv"
	@echo "  make all             Run all registered tests"
	@echo "  make test TEST=name  Run a registered test"
	@echo "  make WARN=1 de       Show Verilator lint warnings"
	@echo "  make clean           Remove Verilator build output"
	@echo
	@echo "Registered tests:"
	@printf '  %s\n' $(TESTS)

clean:
	rm -rf $(OBJ_DIR)
