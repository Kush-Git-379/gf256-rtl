//======================================================================
// tb_gf_mul.sv
//
// EXHAUSTIVE self-checking testbench for BOTH GF(2^8) multipliers.
// Drives all 65,536 ordered input pairs and checks three things:
//
//   1. gf_mul_lut   matches the C++ golden vectors
//   2. gf_mul_shift matches the C++ golden vectors
//   3. the two implementations match EACH OTHER
//
// (3) is redundant given (1) and (2), and deliberately so: it is the
// equivalence claim stated directly, so a future change that breaks it
// is reported as an equivalence failure rather than inferred from two
// separate mismatch logs.
//
// Golden vectors come from ref/isro_has_main.cpp via tb/gen_golden.cpp.
//
// GF(2^8) is small enough to verify completely, so nothing here is
// randomised -- every reachable input is covered.
//
// Exits nonzero on any mismatch so a CI/script run can gate on it.
//======================================================================

`timescale 1ns / 1ps

module tb_gf_mul;

    localparam int N_VEC = 65536;

    logic [7:0] a, b;
    logic [7:0] p_lut;
    logic [7:0] p_shift;

    // Golden vectors, three parallel arrays indexed in step.
    // (Not one packed word per line: $readmemh splits on whitespace, so a
    // "aa bb pp" line would load as three separate entries.)
    logic [7:0] vec_a [0:N_VEC-1];
    logic [7:0] vec_b [0:N_VEC-1];
    logic [7:0] vec_p [0:N_VEC-1];

    int err_lut   = 0;   // lut   vs golden
    int err_shift = 0;   // shift vs golden
    int err_equiv = 0;   // lut   vs shift
    int errors    = 0;
    int checked   = 0;

    gf_mul_lut u_lut (
        .a (a),
        .b (b),
        .p (p_lut)
    );

    gf_mul_shift u_shift (
        .a (a),
        .b (b),
        .p (p_shift)
    );

    initial begin
        $display("=====================================================");
        $display(" GF(2^8) multipliers -- exhaustive verification");
        $display(" lut vs golden, shift vs golden, lut vs shift");
        $display(" polynomial 0x11D, golden reference: ISRO HAS C++");
        $display("=====================================================");

        $readmemh("golden/gf_mul_a.hex", vec_a);
        $readmemh("golden/gf_mul_b.hex", vec_b);
        $readmemh("golden/gf_mul_p.hex", vec_p);

        // Guard against a silently short/missing vector file: if $readmemh
        // found nothing, every entry is X and the comparisons below would
        // vacuously "pass" in a way that is easy to misread as success.
        if (vec_a[N_VEC-1] === 8'hxx || vec_b[N_VEC-1] === 8'hxx ||
            vec_p[N_VEC-1] === 8'hxx) begin
            $display("FATAL: golden/gf_mul_*.hex missing or short.");
            $fatal(1);
        end

        for (int i = 0; i < N_VEC; i++) begin

            a = vec_a[i];
            b = vec_b[i];

            #1;  // settle combinational logic

            checked++;

            if (p_lut !== vec_p[i]) begin
                err_lut++;
                if (err_lut <= 10)
                    $display("MISMATCH lut  : %02h * %02h = %02h, expected %02h",
                             a, b, p_lut, vec_p[i]);
                else if (err_lut == 11)
                    $display("... further lut mismatches suppressed.");
            end

            if (p_shift !== vec_p[i]) begin
                err_shift++;
                if (err_shift <= 10)
                    $display("MISMATCH shift: %02h * %02h = %02h, expected %02h",
                             a, b, p_shift, vec_p[i]);
                else if (err_shift == 11)
                    $display("... further shift mismatches suppressed.");
            end

            if (p_lut !== p_shift) begin
                err_equiv++;
                if (err_equiv <= 10)
                    $display("MISMATCH equiv: %02h * %02h -> lut=%02h shift=%02h",
                             a, b, p_lut, p_shift);
                else if (err_equiv == 11)
                    $display("... further equivalence mismatches suppressed.");
            end
        end

        errors = err_lut + err_shift + err_equiv;

        $display("-----------------------------------------------------");
        $display(" vectors checked      : %0d / %0d", checked, N_VEC);
        $display(" lut   vs golden      : %0d mismatches", err_lut);
        $display(" shift vs golden      : %0d mismatches", err_shift);
        $display(" lut   vs shift       : %0d mismatches", err_equiv);

        if (errors == 0 && checked == N_VEC) begin
            $display(" RESULT: PASS  (%0d/%0d exhaustive, both impls equivalent)",
                     checked, N_VEC);
            $display("=====================================================");
            $finish;
        end
        else begin
            $display(" RESULT: FAIL");
            $display("=====================================================");
            $fatal(1);
        end
    end

endmodule
