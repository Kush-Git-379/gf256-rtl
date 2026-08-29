# The GF multipliers are pure combinational logic -- no clock, no
# registers. "Fmax" is therefore not directly meaningful for them; what
# matters is the worst-case propagation delay through the combinational
# cone, which is what sets the clock ceiling for any design that wraps
# one in a register.
#
# A virtual clock plus zero input/output delays turns that combinational
# path into a constrained path STA will report on, so the two
# microarchitectures can be compared on the same footing.

create_clock -name virt_clk -period 10.000

set_input_delay  -clock virt_clk 0.000 [all_inputs]
set_output_delay -clock virt_clk 0.000 [all_outputs]
