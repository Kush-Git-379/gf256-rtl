//======================================================================
// gf_mul_lut.v
//
// GF(2^8) multiplier, log/antilog (table) microarchitecture.
// Primitive polynomial 0x11D  (x^8 + x^4 + x^3 + x^2 + 1), generator a=2.
//
// Mirrors ref/isro_has_main.cpp gf_mul() directly:
//
//     if (a == 0 || b == 0) return 0;
//     return gf_exp[gf_log[a] + gf_log[b]];
//
// The C++ leans on gf_exp being 512 entries deep (exp[i] = exp[i-255] for
// i >= 255) so the sum of two logs, max 254+254 = 508, needs no modulo.
// This module reproduces that exactly rather than folding mod 255, so the
// hardware matches the reference one-for-one.
//
// Purely combinational. Tables are initialised from the golden .hex files
// emitted by tb/gen_golden.cpp, so simulation uses the SAME tables the C++
// built -- not tables regenerated from an independent source.
//======================================================================

`timescale 1ns / 1ps

module gf_mul_lut #(
    // Paths are parameters so the testbench can point at the golden dir
    // regardless of the simulator's working directory.
    parameter LOG_FILE = "golden/gf_log.hex",
    parameter EXP_FILE = "golden/gf_exp.hex"
) (
    input  wire [7:0] a,
    input  wire [7:0] b,
    output wire [7:0] p
);

    // log table: 256 x 8.  Entry 0 is a don't-care sentinel (the C++ stores
    // -1 there) and is never used on a live path because of the zero
    // short-circuit below.
    reg [7:0] gf_log [0:255];

    // antilog table: 512 x 8, double-length so log_a + log_b never wraps.
    reg [7:0] gf_exp [0:511];

    initial begin
        $readmemh(LOG_FILE, gf_log);
        $readmemh(EXP_FILE, gf_exp);
    end

    wire [7:0] log_a = gf_log[a];
    wire [7:0] log_b = gf_log[b];

    // 9 bits: max 254 + 254 = 508 does not fit in 8.
    wire [8:0] log_sum = {1'b0, log_a} + {1'b0, log_b};

    wire       is_zero = (a == 8'h00) || (b == 8'h00);

    assign p = is_zero ? 8'h00 : gf_exp[log_sum];

endmodule
