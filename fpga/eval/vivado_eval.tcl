# Vivado core-only evaluation flow: the default synthesis and implementation
# steps in non-project mode. Sourced by the build.tcl that tools/fpga_eval.py
# generates, which sets the eval_* variables; eval_variant is the target
# variant's Tcl from targets.json (a place_design directive). Fmax is
# derived from the routed worst setup slack against the constrained clock
# period.
set eval_place_directive Default
eval $eval_variant

read_verilog -sv $eval_files
foreach f $eval_constraints { read_xdc $f }

synth_design -top $eval_top -part $eval_device -include_dirs $eval_incdirs
report_utilization -hierarchical -hierarchical_depth 4 -file $eval_out/synth_util_hier.rpt

opt_design
place_design -directive $eval_place_directive
phys_opt_design
route_design

report_utilization -file $eval_out/route_util.rpt
report_utilization -hierarchical -hierarchical_depth 4 -file $eval_out/route_util_hier.rpt
report_timing_summary -file $eval_out/timing_summary.rpt
report_timing -max_paths 20 -nworst 1 -unique_pins -file $eval_out/timing_paths.rpt

set path   [get_timing_paths -max_paths 1 -setup]
set period [get_property PERIOD [get_clocks clk_i]]
set wns    [get_property SLACK $path]
set fh [open $eval_out/fmax.txt w]
puts $fh "period_ns $period"
puts $fh "wns_ns $wns"
puts $fh "fmax_mhz [expr {1000.0 / ($period - $wns)}]"
close $fh
