# Gowin core-only evaluation flow: synthesis, place and route, timing.
# Sourced by the build.tcl that tools/fpga_eval.py generates, which sets the
# eval_* variables; eval_variant is the target variant's Tcl from
# targets.json (a placement algorithm). Reports land under impl/ in the
# working directory.
set_device -name $eval_device_name $eval_device
foreach f $eval_files       { add_file $f }
foreach f $eval_constraints { add_file $f }

set_option -output_base_name $eval_name
set_option -top_module $eval_top
set_option -verilog_std sysv2017
if {[llength $eval_incdirs] > 0} {
    set_option -include_path [join $eval_incdirs ";"]
}
set_option -timing_driven 1
set_option -gen_text_timing_rpt 1
eval $eval_variant

run all
