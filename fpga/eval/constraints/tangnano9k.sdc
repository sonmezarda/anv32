// The board oscillator is 27 MHz; the eval flow constrains 50 MHz so
// place-and-route keeps pushing past it, and reports the achieved Fmax.
create_clock -name clk_i -period 20.000 -waveform {0 10.000} [get_ports {clk_i}]
