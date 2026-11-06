# PYNQ-Z2 (xc7z020clg400-1) pins for fpga/eval/core_eval_top.sv. PL only,
# no PS block needed.

# 125 MHz sysclk from the Ethernet PHY. The eval flow derives Fmax from the
# routed WNS against this period.
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports clk_i]
create_clock -name clk_i -period 8.000 [get_ports clk_i]

# SW0 as active-low reset (switch up = run), BTN0 as the external interrupt
set_property -dict {PACKAGE_PIN M20 IOSTANDARD LVCMOS33} [get_ports rst_n_i]
set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33} [get_ports irq_i]

set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {led_o[0]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {led_o[1]}]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports {led_o[2]}]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {led_o[3]}]

# Switch, button and LEDs are asynchronous to the core and both inputs go
# through 2-flop synchronizers, so only internal paths are timed.
set_false_path -from [get_ports {rst_n_i irq_i}]
set_false_path -to   [get_ports {led_o[*]}]
