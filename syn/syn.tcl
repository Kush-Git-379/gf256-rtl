# Per-module synthesis + timing for the two GF(2^8) multipliers.
#
# Each multiplier is synthesised ALONE as the top-level entity so the
# reported LUT count is that module's cost and nothing else. Run as:
#     quartus_sh -t syn.tcl <module_name>
#
# Device: Cyclone IV E, the family installed with this Quartus Web Edition.
# Both designs see the identical device and constraints, which is what
# makes the comparison meaningful -- the absolute numbers matter far less
# than the ratio between the two.

package require ::quartus::project
package require ::quartus::flow

set top [lindex $quartus(args) 0]

project_new -overwrite $top

set_global_assignment -name FAMILY "Cyclone IV E"
set_global_assignment -name DEVICE EP4CE22F17C6
set_global_assignment -name TOP_LEVEL_ENTITY $top

set_global_assignment -name VERILOG_FILE ../rtl/$top.v

# gf_mac instantiates a multiplier, so its submodule must be in the
# project too. Default MUL_IMPL=0 selects gf_mul_shift; gf_mul_lut is
# added as well so the parameter can be flipped without editing this.
if {$top eq "gf_mac"} {
    set_global_assignment -name VERILOG_FILE ../rtl/gf_mul_shift.v
    set_global_assignment -name VERILOG_FILE ../rtl/gf_mul_lut.v
}

# gf_mul_lut initialises its ROMs with $readmemh. Quartus resolves those
# paths relative to the PROJECT directory (here syn/), not relative to the
# .v file, so the module's defaults -- which are written for the simulator's
# cwd of tb/ -- do not resolve during synthesis.
#
# The paths are module parameters precisely so they can be retargeted per
# tool. Override them here rather than hard-coding a path in the RTL that
# is wrong for one of the two tools.
if {$top eq "gf_mul_lut" || $top eq "gf_inv"} {
    set_parameter -name LOG_FILE "../tb/golden/gf_log.hex"
    set_parameter -name EXP_FILE "../tb/golden/gf_exp.hex"
}

# The multipliers are purely combinational, so there are no registers for
# Fmax to be measured between. Wrap timing around the combinational path
# by asking for the worst-case input-to-output delay instead: create a
# virtual clock and constrain every input and output against it, then read
# the achieved delay out of the timing report.
set_global_assignment -name SDC_FILE mul.sdc

execute_module -tool map
execute_module -tool fit
execute_module -tool sta

project_close
