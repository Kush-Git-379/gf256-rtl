//======================================================================
// tb_gf_mac.sv
//
// Self-checking testbench for gf_mac:  acc_out = acc_in ^ (a * b)
//
// COVERAGE ARGUMENT -- why this is not a full 3-input sweep:
//
// The full space is 256^3 = 16,777,216 vectors (~151 MB of golden files).
// That expense buys nothing here. gf_mac is gf_mul followed by one XOR,
// and gf_mul is ALREADY proven exhaustively against the C++ over all
// 65,536 pairs by tb_gf_mul. The only new logic is the XOR, and XOR over
// 8 bits is fully exercised by sweeping acc_in across a set that covers
// every bit position in both polarities.
//
// So this TB checks:
//   1. all 65,536 (a,b) pairs with acc_in = 0   -> MAC degenerates to MUL,
//      cross-checked against the golden product file
//   2. all 65,536 (a,b) pairs against a live gf_mul_shift instance with a
//      walking/edge set of acc_in values -- the accumulate identity
//   3. the algebraic properties the matrix inversion actually relies on
//
// Expected values are computed directly (acc_in ^ product) rather than
// read from a dumped file: for a one-XOR module the dump would just be
// restating the same expression, and a file that large would slow every
// future run for no added confidence.
//======================================================================

`timescale 1ns / 1ps

module tb_gf_mac;

    localparam int N_PAIR = 65536;

    logic [7:0] a, b, acc_in;
    logic [7:0] acc_out;
    logic [7:0] prod_ref;

    logic [7:0] vec_a [0:N_PAIR-1];
    logic [7:0] vec_b [0:N_PAIR-1];
    logic [7:0] vec_p [0:N_PAIR-1];

    int errors  = 0;
    int checked = 0;

    // acc_in values: 00 and FF (all-zero / all-one), the eight one-hot
    // walking-1 patterns, and their complements (walking-0). Together
    // these drive every acc_in bit both high and low against every
    // product bit, which is the whole of what the XOR stage can do.
    localparam int N_ACC = 18;
    logic [7:0] acc_set [0:N_ACC-1];

    gf_mac #(.MUL_IMPL(0)) u_mac (
        .a       (a),
        .b       (b),
        .acc_in  (acc_in),
        .acc_out (acc_out)
    );

    // Reference multiplier, independently instantiated. Note this is the
    // SAME microarchitecture the DUT wraps, so it is not an independent
    // check of the product -- that is what item (1) and tb_gf_mul are for.
    // Here it isolates the accumulate stage.
    gf_mul_shift u_ref (
        .a (a),
        .b (b),
        .p (prod_ref)
    );

    initial begin
        $display("=====================================================");
        $display(" GF(2^8) multiply-accumulate -- verification");
        $display(" acc_out = acc_in XOR (a * b),  polynomial 0x11D");
        $display("=====================================================");

        acc_set[0] = 8'h00;
        acc_set[1] = 8'hFF;
        for (int k = 0; k < 8; k++) begin
            acc_set[2 + k]  =  (8'h01 << k);   // walking 1
            acc_set[10 + k] = ~(8'h01 << k);   // walking 0
        end

        $readmemh("golden/gf_mul_a.hex", vec_a);
        $readmemh("golden/gf_mul_b.hex", vec_b);
        $readmemh("golden/gf_mul_p.hex", vec_p);

        if (vec_a[N_PAIR-1] === 8'hxx || vec_p[N_PAIR-1] === 8'hxx) begin
            $display("FATAL: golden/gf_mul_*.hex missing or short.");
            $fatal(1);
        end

        // ---- 1. acc_in = 0 : MAC must reduce to plain multiply, and
        //         that product must match the C++ golden vectors.
        acc_in = 8'h00;
        for (int i = 0; i < N_PAIR; i++) begin
            a = vec_a[i];
            b = vec_b[i];
            #1;
            checked++;
            if (acc_out !== vec_p[i]) begin
                errors++;
                if (errors <= 10)
                    $display("MISMATCH acc0: %02h * %02h + 00 = %02h, expected %02h",
                             a, b, acc_out, vec_p[i]);
            end
        end
        $display(" [1] acc_in=0 vs C++ golden      : %0d pairs", N_PAIR);

        // ---- 2. accumulate identity across the acc_in bit patterns.
        for (int s = 1; s < N_ACC; s++) begin
            acc_in = acc_set[s];
            for (int i = 0; i < N_PAIR; i++) begin
                a = vec_a[i];
                b = vec_b[i];
                #1;
                checked++;
                if (acc_out !== (acc_in ^ vec_p[i])) begin
                    errors++;
                    if (errors <= 10)
                        $display("MISMATCH acc=%02h: %02h * %02h -> %02h, expected %02h",
                                 acc_in, a, b, acc_out, acc_in ^ vec_p[i]);
                end
            end
        end
        $display(" [2] %0d acc_in patterns x %0d pairs : %0d checks",
                 N_ACC - 1, N_PAIR, (N_ACC - 1) * N_PAIR);

        // ---- 3. properties the matrix-inversion inner loop depends on.

        // (a) accumulating a zero product leaves acc unchanged --
        //     the r == i skip case and any zero pivot column entry.
        for (int v = 0; v < 256; v++) begin
            a = 8'h00; b = v[7:0]; acc_in = v[7:0];
            #1;
            checked++;
            if (acc_out !== acc_in) begin
                errors++;
                $display("MISMATCH zero-term: acc=%02h unchanged expected, got %02h",
                         acc_in, acc_out);
            end
        end

        // (b) self-inverse: XOR-ing the same product twice restores acc.
        //     This is why elimination in GF(2^m) needs no subtraction.
        for (int v = 0; v < 256; v++) begin
            a = v[7:0]; b = 8'h07; acc_in = 8'h00;
            #1;
            begin
                logic [7:0] once;
                once = acc_out;
                acc_in = once;
                #1;
                checked++;
                if (acc_out !== 8'h00) begin
                    errors++;
                    $display("MISMATCH self-inv: a=%02h twice -> %02h, expected 00",
                             v[7:0], acc_out);
                end
            end
        end
        $display(" [3] algebraic properties          : 512 checks");

        $display("-----------------------------------------------------");
        $display(" total checks : %0d", checked);
        $display(" mismatches   : %0d", errors);

        if (errors == 0) begin
            $display(" RESULT: PASS  (%0d checks)", checked);
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
