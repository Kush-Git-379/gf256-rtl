//======================================================================
// tb_gf_inv.sv
//
// EXHAUSTIVE self-checking testbench for the GF(2^8) inverse.
// All 256 inputs, compared against golden vectors from the ISRO C++.
//
// Also checks the error contract the C++ expresses as exit(1):
//   a == 0  -> err must be high
//   a != 0  -> err must be low AND a * inv(a) must equal 1
//
// The a*inv(a)==1 check is an independent confirmation that does not
// depend on the golden file being right -- it is the field axiom itself.
//======================================================================

`timescale 1ns / 1ps

module tb_gf_inv;

    localparam int N_VEC = 256;

    logic [7:0] a;
    logic [7:0] inv;
    logic       err;

    // Round-trip check: feed a and inv(a) back through the multiplier.
    logic [7:0] prod;

    logic [7:0] vec_a   [0:N_VEC-1];
    logic [7:0] vec_inv [0:N_VEC-1];
    logic [7:0] vec_err [0:N_VEC-1];

    int errors  = 0;
    int checked = 0;

    gf_inv u_inv (
        .a   (a),
        .inv (inv),
        .err (err)
    );

    gf_mul_lut u_chk (
        .a (a),
        .b (inv),
        .p (prod)
    );

    initial begin
        $display("=====================================================");
        $display(" GF(2^8) inverse -- exhaustive verification");
        $display(" polynomial 0x11D, golden reference: ISRO HAS C++");
        $display("=====================================================");

        $readmemh("golden/gf_inv_a.hex",   vec_a);
        $readmemh("golden/gf_inv_i.hex",   vec_inv);
        $readmemh("golden/gf_inv_e.hex",   vec_err);

        if (vec_a[N_VEC-1] === 8'hxx) begin
            $display("FATAL: golden/gf_inv_*.hex missing or short.");
            $fatal(1);
        end

        for (int i = 0; i < N_VEC; i++) begin

            a = vec_a[i];

            #1;

            checked++;

            // 1. error flag matches the C++ fatal condition
            if (err !== vec_err[i][0]) begin
                errors++;
                $display("MISMATCH err: a=%02h err=%0b, expected %0b",
                         a, err, vec_err[i][0]);
            end

            if (!err) begin

                // 2. inverse value matches the golden table
                if (inv !== vec_inv[i]) begin
                    errors++;
                    if (errors <= 20)
                        $display("MISMATCH inv: inv(%02h) = %02h, expected %02h",
                                 a, inv, vec_inv[i]);
                end

                // 3. field axiom: a * inv(a) == 1
                if (prod !== 8'h01) begin
                    errors++;
                    $display("MISMATCH axiom: %02h * inv(%02h)=%02h -> %02h, expected 01",
                             a, a, inv, prod);
                end
            end
        end

        $display("-----------------------------------------------------");
        $display(" inputs checked : %0d / %0d", checked, N_VEC);
        $display(" mismatches     : %0d", errors);

        if (errors == 0 && checked == N_VEC) begin
            $display(" RESULT: PASS  (%0d/%0d exhaustive, incl. inv(0) error flag)",
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
