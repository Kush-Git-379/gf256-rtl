# GF(2⁸) Arithmetic Core — Verilog

Synthesizable Galois-field arithmetic for GF(2⁸), reimplemented in RTL from the
C++ Reed–Solomon **erasure** decoder I wrote during my ISRO SAC internship, and
verified exhaustively against that C++ as golden reference.

This is the **arithmetic layer** beneath a Reed–Solomon decoder — `gf_mul`,
`gf_inv`, `gf_mac`. It is not an RS decoder: there is no Berlekamp-Massey, no
Chien search, no Forney. The original C++ recovers lost pages by Gaussian
elimination and k×k matrix inversion over GF(256), and contains none of those
either. The hardware mirrors the algorithm actually built.

| | Result |
|---|---|
| Multiply | **65,536 / 65,536** exhaustive vs C++ golden, both microarchitectures, and equivalent to each other |
| Inverse | **256 / 256** exhaustive, including the `inv(0)` error contract |
| MAC | **1,180,160** checks |
| Smallest / fastest multiplier | `gf_mul_shift` — **62 LEs, 7.71 ns** (vs 804 LEs, 12.95 ns for the table version) |
| Latches inferred | **0**, all four modules |

Everything reproduces from a clean checkout with `./run_tests.sh`.

> **On provenance:** the ISRO C++ in `ref/` is my own work from that internship,
> included here as the verification reference. Only the Galois-field layer is
> reimplemented in RTL — the mission-specific decoding around it is not, and is
> not the subject of this project.

---

## Field parameters

| Parameter | Value |
|---|---|
| Field | GF(2⁸), 256 elements |
| Primitive polynomial | **0x11D** — x⁸ + x⁴ + x³ + x² + 1 |
| Generator | α = 2 |
| Addition | XOR |
| `gf_mul(a,0)` / `gf_mul(0,b)` | 0 |
| `gf_inv(0)` | error — flagged on a dedicated output |

> **0x11D, not 0x11B.** The AES polynomial 0x11B is far more common in textbooks
> and produces plausible-looking but wrong results. The vector generator refuses
> to emit unless α⁸ == 0x1D, which is the signature of 0x11D (0x11B gives 0x1B).
> A single discriminating vector: `0x57 · 0x83` is **0x31** here, but 0xC1 under
> the AES field.

---

## Results

Exhaustive verification — every reachable input, nothing randomised:

```
RESULT: PASS  (65536/65536 exhaustive, both impls equivalent)
RESULT: PASS  (256/256 exhaustive, incl. inv(0) error flag)
RESULT: PASS  (1180160 checks)
```

### Microarchitecture comparison

Both multipliers are functionally identical and proven equivalent on all 65,536
input pairs. Quartus II 13.0.1, Cyclone IV E `EP4CE22F17C6`, slow 1200 mV 85 °C
corner, 10 ns virtual clock over the combinational cone:

| | `gf_mul_lut` | `gf_mul_shift` |
|---|---|---|
| Microarchitecture | log/antilog tables | shift-and-reduce (xtime) |
| Logic elements | **804** | **62** |
| Memory bits | 0 | 0 |
| Registers | 0 | 0 |
| Worst-case delay | 12.95 ns | **7.71 ns** |
| Implied Fmax | 77.2 MHz | **129.6 MHz** |

The other two modules, same device and corner:

| | LEs | Delay | Notes |
|---|---|---|---|
| `gf_inv` | 211 | — | table-based, same async-read situation |
| `gf_mac` | **65** | 8.32 ns | `gf_mul_shift` (62) + **3 LEs** for the accumulate |

`gf_mac` is the sharpest illustration of why this field suits hardware: addition
in GF(2^m) *is* XOR, so the accumulate costs 3 logic elements and 0.6 ns on top
of the multiplier — no carry chain, no adder. On a CPU that MAC is two
instructions; here the second one is nearly free.

**The table version is both larger and slower here — the opposite of the usual
expectation, and the most interesting result in the project.**

Two things drive it, and both are worth understanding:

1. **The ROMs became logic, not memory.** `Auto ROM Replacement` is On and the
   device has 608 kbit of M9K available, yet the design uses 0 memory bits. M9K
   blocks require a *registered* read address; these lookups are asynchronous, so
   Quartus had no choice but to build 768 bytes of table out of LUTs. That is
   where 804 LEs went.

2. **A table lookup is not free in hardware.** The C++ intuition — "a lookup is
   one cycle, a loop is eight" — does not carry over. The shift version's eight
   `xtime` stages are each a 1-bit shift plus a conditional 8-bit XOR, which
   flattens into a shallow XOR tree. The table version's path is
   address-decode → 256-entry mux → 9-bit add → 512-entry mux, which is deeper.

**Takeaway:** the log/antilog form is the right choice on a CPU, where the tables
sit in cache and the alternative is a real loop. On FPGA fabric, without a
registered-read memory, shift-and-reduce wins on both axes at once.

### Follow-up: does registering the address recover M9K?

Yes, completely. `experiments/gf_mul_lut_reg.v` is the same log/antilog design
with registered read addresses:

| variant | LEs | mem bits | regs | Fmax |
|---|---|---|---|---|
| `gf_mul_lut` (async ROM) | 804 | 0 | 0 | 77.2 MHz (comb.) |
| `gf_mul_shift` (no tables) | 62 | 0 | 0 | 129.6 MHz (comb.) |
| `gf_mul_lut_reg` (registered) | **23** | **6,144** | 10 | **179.6 MHz** |

Logic collapses 804 → 23 LEs, the tables move into 2 of 66 M9K blocks, and Fmax
becomes the highest of the three. The async read really was the whole story.

The cost is that it is no longer combinational: throughput is one result per
clock but latency is 3 cycles, so every consumer must be pipeline-aware. The
verified core keeps all four modules combinational so they compose freely.

**This experiment is not covered by `run_tests.sh`** — the exhaustive testbenches
drive combinational DUTs, and verifying a pipelined version needs a clocked
testbench with 3-cycle alignment. It is included as a synthesis result, not as a
verified module, and is labelled that way in the source.

---

## Layout

```
gf256-rtl/
├── rtl/
│   ├── gf_mul_lut.v      log/antilog multiplier (combinational)
│   ├── gf_mul_shift.v    shift-and-reduce multiplier (combinational)
│   ├── gf_inv.v          table inverse, err flag on a == 0
│   └── gf_mac.v          multiply-accumulate: acc ^= a*b
├── tb/
│   ├── gen_golden.cpp    golden vector generator (GF code verbatim from ISRO C++)
│   ├── tb_gf_mul.sv      exhaustive: both impls vs golden, and vs each other
│   ├── tb_gf_inv.sv      exhaustive: 256 inputs + inv(0) error contract
│   └── tb_gf_mac.sv      1.18M checks incl. accumulate + algebraic properties
├── experiments/
│   └── gf_mul_lut_reg.v  registered-ROM variant (synthesis result, unverified)
├── syn/
│   ├── syn.tcl           per-module synthesis + STA
│   └── mul.sdc           virtual-clock constraint over the combinational path
├── ref/isro_has_main.cpp golden reference (unmodified)
└── run_tests.sh          regenerate vectors, compile, run everything
```

---

## Verification method

The C++ is the **single source of truth**. `tb/gen_golden.cpp` copies the GF
functions verbatim out of `ref/isro_has_main.cpp` and dumps every
`(a, b, a·b)` triple and every `(a, a⁻¹)` pair. The testbenches read those with
`$readmemh` and compare. Generated vectors are gitignored so they are always
rebuilt from the C++ — a stale committed vector file could mask a regression.

`ref/isro_has_main.cpp` is **unmodified**. Its `main` is interactive and needs a
`GMatrix.txt` not in this repo, so it cannot run standalone; extracting the GF
block verbatim gives the same guarantee while leaving the reference pristine.
The one deliberate difference: the C++ `gf_inv(0)` calls `exit(1)`, which would
abort the generator, so `a == 0` is emitted as the error case the RTL's `err`
flag must reproduce.

Three claims checked rather than assumed:

- **`$readmemh` splits on whitespace.** Probed in ModelSim before relying on it —
  an `aa bb pp` line loads as three *separate* array entries, not one packed
  word. Vectors are written as parallel one-value-per-line files instead.
- **The generator catches a wrong field.** Rebuilt with 0x11B substituted: 409
  self-check failures, refuses to emit.
- **The testbenches can actually fail.** Verified by injecting bugs — a one-bit
  index error into the LUT multiplier, and the 0x1D→0x1B substitution into the
  shift multiplier. Both were caught, and in the second case the golden check and
  the equivalence check fired *independently*, confirming the two implementations
  do not share a common-mode error. A green result from a testbench never seen to
  fail proves nothing.

Independently of the golden tables, `tb_gf_inv` also feeds `a` and `inv(a)` back
through the multiplier and asserts the product is 1 — the field axiom itself.

### Why `gf_mac` is not swept exhaustively

The multipliers and the inverse are verified over their *complete* input spaces.
`gf_mac` is not, and the distinction is deliberate rather than a shortcut.

Its full space is 256³ = 16,777,216 vectors, ~151 MB of golden files. But
`gf_mac` is `gf_mul` followed by one XOR, and `gf_mul` is already proven
exhaustively over all 65,536 pairs. The only unverified logic is the 8-bit XOR.
So the TB sweeps all 65,536 `(a,b)` pairs against 18 `acc_in` patterns —
all-zeros, all-ones, and walking-1/walking-0 across all eight bit positions —
which drives every `acc_in` bit both polarities against every product bit. That
is the whole of what an 8-bit XOR stage can do. 1,180,160 checks, seconds to run.

This was worth stating because the weaker sweep has to actually catch things:
substituting `|` for `^` in the accumulate passes the `acc_in = 0` case
completely, and is caught only by the walking patterns.

---

## Reproducing

```bash
./run_tests.sh                      # vectors + compile + exhaustive sim
cd syn && quartus_sh -t syn.tcl gf_mul_shift
                                    # and gf_mul_lut, gf_inv
```

Requires g++, ModelSim (`vlog`/`vsim`), and Quartus II for the synthesis numbers.

---

## Status

- [x] Exhaustive test passes: 65,536/65,536 multiply, 256/256 inverse
- [x] Both multiplier implementations agree with each other and with C++
- [x] `gf_inv(0)` raises the error flag rather than returning garbage
- [x] Synthesizes clean in Quartus, no inferred latches
- [x] Testbench self-checking — reports pass/fail, exits nonzero, no waveform reading
- [x] LUT/Fmax comparison recorded
- [x] `gf_mac` built and verified (Tier 2)
- [x] Reproduces green from a clean checkout via `./run_tests.sh`
