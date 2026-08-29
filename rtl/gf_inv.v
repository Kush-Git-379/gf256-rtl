//======================================================================
// gf_inv.v
//
// GF(2^8) multiplicative inverse, table-based.
// Primitive polynomial 0x11D, generator a=2.
//
// Mirrors ref/isro_has_main.cpp gf_inv():
//
//     if (a == 0) { cerr << "Inverse of zero!"; exit(1); }
//     return gf_exp[255 - gf_log[a]];
//
// The C++ treats inverse-of-zero as fatal. Hardware cannot exit, so the
// zero case is surfaced on a dedicated 'err' output. When err is high the
// value on 'inv' is meaningless and must not be consumed -- it is driven
// to 0 rather than left floating so the module infers no latch and
// simulation shows no X propagating into downstream logic.
//
// Purely combinational.
//======================================================================

`timescale 1ns / 1ps

module gf_inv #(
    parameter LOG_FILE = "golden/gf_log.hex",
    parameter EXP_FILE = "golden/gf_exp.hex"
) (
    input  wire [7:0] a,
    output wire [7:0] inv,
    output wire       err     // high iff a == 0 (inverse undefined)
);

    reg [7:0] gf_log [0:255];
    reg [7:0] gf_exp [0:511];

    initial begin
        $readmemh(LOG_FILE, gf_log);
        $readmemh(EXP_FILE, gf_exp);
    end

    wire [7:0] log_a = gf_log[a];

    // 255 - log_a. log_a <= 254 for any nonzero a, so this stays in 0..255
    // and indexes the first half of the exp table. No modulo needed.
    wire [7:0] exp_idx = 8'd255 - log_a;

    assign err = (a == 8'h00);
    assign inv = err ? 8'h00 : gf_exp[exp_idx];

endmodule
