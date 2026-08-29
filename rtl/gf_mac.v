//======================================================================
// gf_mac.v
//
// GF(2^8) multiply-accumulate:  acc_out = acc_in XOR (a * b)
// Primitive polynomial 0x11D.
//
// This is the exact operation in the inner loop of the matrix inversion
// in ref/isro_has_main.cpp (invertMatrix, lines 114-123):
//
//     A[r][c] = gf_add(A[r][c], gf_mul(factor, A[i][c]));
//
// gf_add is XOR in this field, so accumulation is free -- it is one XOR
// gate deep, not an adder with a carry chain. That is why GF arithmetic
// suits hardware: the "accumulate" half of a MAC costs almost nothing.
//
// Combinational, matching the two multipliers. The row loop that would
// drive this is the matrix-inversion controller, which is deliberately
// out of scope for this project.
//
// MUL_IMPL selects the multiplier microarchitecture:
//   0 = gf_mul_shift  (default -- 62 LEs, 7.71 ns; smaller AND faster)
//   1 = gf_mul_lut    (804 LEs, 12.95 ns)
// See README.md for why the table version loses on both axes here.
//======================================================================

`timescale 1ns / 1ps

module gf_mac #(
    parameter MUL_IMPL = 0,
    // Only used when MUL_IMPL = 1; harmless otherwise.
    parameter LOG_FILE = "golden/gf_log.hex",
    parameter EXP_FILE = "golden/gf_exp.hex"
) (
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire [7:0] acc_in,
    output wire [7:0] acc_out
);

    wire [7:0] prod;

    generate
        if (MUL_IMPL == 0) begin : g_shift
            gf_mul_shift u_mul (
                .a (a),
                .b (b),
                .p (prod)
            );
        end
        else begin : g_lut
            gf_mul_lut #(
                .LOG_FILE (LOG_FILE),
                .EXP_FILE (EXP_FILE)
            ) u_mul (
                .a (a),
                .b (b),
                .p (prod)
            );
        end
    endgenerate

    // gf_add(x, y) == x ^ y
    assign acc_out = acc_in ^ prod;

endmodule
