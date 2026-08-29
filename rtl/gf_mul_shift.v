//======================================================================
// gf_mul_shift.v
//
// GF(2^8) multiplier, combinational shift-and-reduce microarchitecture.
// Primitive polynomial 0x11D  (x^8 + x^4 + x^3 + x^2 + 1).
//
// Functionally identical to gf_mul_lut.v but built from pure logic --
// NO tables, NO ROM. This is the area/timing counterpart: the LUT version
// spends memory to keep the path short, this one spends a long XOR chain
// to use no memory at all.
//
// Algorithm -- schoolbook multiply with reduction folded in ("xtime"):
//
//   p = 0; x = a;
//   for i in 0..7:
//       if b[i]: p ^= x;
//       x = xtime(x);          // x * alpha, reduced back into the field
//
// where xtime(x) = (x << 1) XOR (0x1D if x[7] else 0).
//
// The 0x1D is the primitive polynomial 0x11D with its x^8 term dropped:
// when the shift pushes a 1 out of bit 7 that bit IS x^8, and x^8 is
// congruent to x^4+x^3+x^2+1 = 0x1D in this field. Substituting 0x1B
// here silently switches to the AES field and produces wrong products
// that still look plausible -- see the exhaustive TB.
//
// The loop is fully unrolled into 8 stages of combinational logic. Zero
// operands need no special case: if b == 0 no term is ever accumulated,
// and if a == 0 every term is 0.
//======================================================================

`timescale 1ns / 1ps

module gf_mul_shift (
    input  wire [7:0] a,
    input  wire [7:0] b,
    output wire [7:0] p
);

    // x[i] holds a * alpha^i, reduced.  x[0] = a.
    wire [7:0] x    [0:7];

    // acc[i] is the running sum after folding in bit i of b.
    wire [7:0] acc  [0:8];

    assign x[0]   = a;
    assign acc[0] = 8'h00;

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : stage

            // Conditionally accumulate a * alpha^i when b[i] is set.
            // Replicating b[i] across 8 bits masks the term without a
            // mux, which is what the synthesiser wants to see here.
            assign acc[i+1] = acc[i] ^ (x[i] & {8{b[i]}});

            // xtime: shift left one, and if the bit shifted out of the
            // top was set, reduce by XOR-ing the polynomial remainder.
            // The last stage's product is unused (no b[8]) but costs
            // nothing -- synthesis prunes it.
            if (i < 7) begin : xt
                assign x[i+1] = {x[i][6:0], 1'b0} ^ (x[i][7] ? 8'h1D : 8'h00);
            end

        end
    endgenerate

    assign p = acc[8];

endmodule
