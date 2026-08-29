//======================================================================
// gf_mul_lut_reg.v   -- EXPERIMENT, not part of the verified core.
//
// Question this answers: the async-read ROMs in rtl/gf_mul_lut.v cannot
// map to M9K block RAM, so Quartus builds 768 bytes of table out of
// logic (804 LEs). Does registering the read address recover block RAM,
// and what does that cost?
//
// Answer (Quartus 13.0.1, Cyclone IV E EP4CE22F17C6, slow 1200mV 85C):
//
//   variant                        LEs   mem bits  regs   Fmax
//   ------------------------------------------------------------
//   gf_mul_lut     (async ROM)     804          0     0   77.2 MHz (comb)
//   gf_mul_shift   (no tables)      62          0     0  129.6 MHz (comb)
//   gf_mul_lut_reg (this file)      23      6,144    10  179.6 MHz
//
// Registering the address recovers M9K inference completely: 2 of 66
// blocks, 6,144 memory bits, and logic collapses 804 -> 23 LEs. Fmax
// rises to 179.6 MHz, the highest of the three.
//
// The catch, and why this is NOT the deliverable: throughput is per
// clock but latency is now 3 cycles, and the result is no longer
// combinational. Every consumer must be pipeline-aware. The verified
// core deliberately keeps all four modules combinational so they compose
// freely; this file records what the pipelined form would buy.
//
// Not covered by run_tests.sh -- the exhaustive testbenches drive
// combinational DUTs. Verifying this properly means a clocked testbench
// with 3-cycle pipeline alignment, which is future work.
//======================================================================

`timescale 1ns / 1ps

module gf_mul_lut_reg #(
    parameter LOG_FILE = "../tb/golden/gf_log.hex",
    parameter EXP_FILE = "../tb/golden/gf_exp.hex"
) (
    input  wire       clk,
    input  wire [7:0] a,
    input  wire [7:0] b,
    output reg  [7:0] p
);

    reg [7:0] gf_log [0:255];
    reg [7:0] gf_exp [0:511];

    initial begin
        $readmemh(LOG_FILE, gf_log);
        $readmemh(EXP_FILE, gf_exp);
    end

    // Stage 1 -- registered log lookups. The registered read address is
    // precisely what the async version lacks and what M9K requires.
    reg [7:0] log_a_r, log_b_r;
    reg       zero_r;

    always @(posedge clk) begin
        log_a_r <= gf_log[a];
        log_b_r <= gf_log[b];
        zero_r  <= (a == 8'h00) || (b == 8'h00);
    end

    // Stage 2 -- registered antilog lookup. 9-bit index: the doubled exp
    // table means log_a + log_b (max 508) needs no modulo.
    wire [8:0] log_sum = {1'b0, log_a_r} + {1'b0, log_b_r};

    reg [7:0] exp_r;
    reg       zero_r2;

    always @(posedge clk) begin
        exp_r   <= gf_exp[log_sum];
        zero_r2 <= zero_r;
    end

    // Stage 3 -- apply the zero short-circuit, carried alongside the data.
    always @(posedge clk)
        p <= zero_r2 ? 8'h00 : exp_r;

endmodule
