# Lab Guide — working through the GF(2⁸) core yourself

For **Quartus II 13.0.1 Web Edition** and **ModelSim ASE 10.5b**, both installed
on this machine. Written for someone comfortable with logic gates, flip-flops and
Verilog syntax who has not driven these tools seriously before.

Work through it in order. Each lab has a **what you're proving**, the clicks, and
**what to look for** — that last part is where the interview answers come from.

| Lab | What you do | Time |
|---|---|---|
| 0 | Set up, and prove the tools work | 20 min |
| 1 | Simulate in the ModelSim GUI, read a waveform | 45 min |
| 2 | Break it on purpose (fault injection) | 30 min |
| 3 | Synthesize in the Quartus GUI | 45 min |
| 4 | Read the RTL and Technology Map Viewers | 45 min |
| 5 | Read a timing report properly | 60 min |
| 6 | Reproduce the M9K experiment | 45 min |
| 7 | Design your own experiment | open |

---

## Paths on this machine

```
Project     C:\Users\HP\Documents\Code\gf256-rtl
Quartus     D:\Downloads\quartus\bin64\quartus.exe
ModelSim    C:\Users\HP\modelsim_ase\win32aloem\modelsim.exe
```

Quartus is **not** on PATH. Launch it from the exe, or add
`D:\Downloads\quartus\bin64` to PATH if you want `quartus_sh` in a terminal.

---

# Lab 0 — Setup, and prove the tools work

**Proving:** your toolchain reproduces the committed results before you change
anything. Never debug your own edits on top of an unverified baseline.

In Git Bash, from the project root:

```bash
./run_tests.sh
```

Expect, after about 20 seconds:

```
RESULT: PASS  (65536/65536 exhaustive, both impls equivalent)
RESULT: PASS  (256/256 exhaustive, incl. inv(0) error flag)
RESULT: PASS  (1180160 checks)
OVERALL: PASS
```

If that fails, stop and fix it — everything downstream assumes this baseline.

**What the script did**, in three stages:

1. Compiled `tb/gen_golden.cpp` with g++ and ran it. That wrote `tb/golden/*.hex`
   — the expected answers, computed by the C++ from `ref/isro_has_main.cpp`.
2. `vlib work` created a compiled-library directory, then `vlog` compiled the
   Verilog and SystemVerilog into it.
3. `vsim -c` ran each testbench in console mode.

`tb/golden/` and `tb/work/` are gitignored — both are regenerated, never
committed. That is deliberate: the C++ stays the single source of truth, and a
stale committed vector file could hide a real regression.

---

# Lab 1 — Simulate in the ModelSim GUI

**Proving:** you can drive a simulation by hand and read what the hardware did,
not just trust a PASS line.

## 1.1 Launch and point at the right directory

Open `C:\Users\HP\modelsim_ase\win32aloem\modelsim.exe`.

The **working directory matters** — the testbenches open `golden/gf_mul_a.hex`
with a *relative* path, so ModelSim must be sitting in `tb/`. In the transcript
pane:

```tcl
cd C:/Users/HP/Documents/Code/gf256-rtl/tb
pwd
```

Use forward slashes — ModelSim's Tcl treats `\` as an escape character.

## 1.2 Compile

```tcl
vlib work
vlog -sv ../rtl/gf_mul_lut.v ../rtl/gf_mul_shift.v ../rtl/gf_inv.v ../rtl/gf_mac.v
vlog -sv tb_gf_mul.sv tb_gf_inv.sv tb_gf_mac.sv
```

Or via menus: **Compile → Compile...**, select the files, Compile, Done.

You want `Errors: 0, Warnings: 0`. Warnings in RTL are not noise to be ignored —
an inferred latch or a width mismatch shows up here first.

## 1.3 Run with waveforms

This is the part the console run never shows you:

```tcl
vsim tb_gf_inv
add wave -radix hexadecimal /tb_gf_inv/*
run -all
```

`tb_gf_inv` first, deliberately — 256 inputs makes a readable waveform. The
multiplier's 65,536 is unreadable by eye, which is exactly why the testbench
self-checks instead of asking you to look.

## 1.4 What to look for

In the Wave window, press **F** (zoom full), then:

**(a) The error flag.** Find `err`. It is high for exactly one 1 ns slice at the
very start — `a = 00` — and low for all 255 others. That is the C++ `exit(1)`
translated into hardware. Check `inv` at that same instant: it is `00`, driven to
a defined value rather than left floating, so no X propagates downstream.

**(b) Verify one inverse by hand.** At `a = 02`, read `inv`. It should be `8E`.
Check it: 0x02 · 0x8E should be 1. Watch `prod` at that instant — the testbench
feeds `a` and `inv` back through `gf_mul_shift` and asserts the product is `01`.
That is the field axiom, and it holds independently of whether the golden file is
correct.

**(c) Notice there is no clock.** No `clk` signal exists anywhere. All four
modules are combinational — outputs are pure functions of inputs, no state, no
edges. The `#1` delays in the testbench exist only to let values settle before
sampling. This is why "Fmax" needs care for these modules (Lab 5).

## 1.5 The equivalence run

```tcl
vsim tb_gf_mul
run -all
```

Read the output carefully:

```
 lut   vs golden      : 0 mismatches
 shift vs golden      : 0 mismatches
 lut   vs shift       : 0 mismatches
```

The third line is logically redundant given the first two. It is there on purpose:
it states the equivalence claim *directly*, so a future change that breaks it is
reported as an equivalence failure rather than inferred from two separate logs.

**Interview-relevant:** this is a poor man's equivalence check. Formal tools
(Conformal, Formality) prove equivalence over all inputs symbolically. Here the
input space is only 2¹⁶, so exhaustive simulation *is* a proof — no sampling, no
coverage argument needed. Knowing when exhaustive beats formal is worth saying.

---

# Lab 2 — Break it on purpose

**Proving:** the testbench can actually fail. This is the single most important
lab. A green run from a test never seen to fail is worth nothing, and an
interviewer who knows verification will ask how you know your testbench works.

## 2.1 The polynomial substitution

Open `rtl/gf_mul_shift.v`, find the `xtime` line (~line 63):

```verilog
assign x[i+1] = {x[i][6:0], 1'b0} ^ (x[i][7] ? 8'h1D : 8'h00);
```

Change `8'h1D` to `8'h1B` and re-run `tb_gf_mul`. This is the AES polynomial —
the single most common way to get GF(256) silently wrong.

Expect:

```
MISMATCH shift: 02 * 80 = 1b, expected 1d
MISMATCH equiv: 02 * 80 -> lut=1d shift=1b
```

Two things to notice. First, the *first* failing case is `02 * 80` — everything
below it passes, because reduction only happens when a value overflows bit 7. A
random-sampling testbench could plausibly miss this. Second, the LUT version stays
correct, so the equivalence check fires too. **That is the payoff of building it
twice:** the two implementations share no common-mode error.

Restore `8'h1D`.

## 2.2 The accumulate substitution

In `rtl/gf_mac.v`, change:

```verilog
assign acc_out = acc_in ^ prod;
```

to use `|` instead of `^`. Re-run `tb_gf_mac`. Look closely at which check catches
it:

```
MISMATCH acc=ff: 01 * 01 -> ff, expected fe
```

**It passes `acc_in = 0` completely** — `0 | x` equals `0 ^ x` for all x. Only the
walking-bit patterns catch it. This is why `tb_gf_mac` sweeps 18 `acc_in` values
instead of just zero, and it is the concrete justification for that TB not being a
full 3-input sweep.

Restore `^`, then `./run_tests.sh` to confirm you are back to green.

## 2.3 Why this matters more than it looks

`gf_mac` is the only module not verified over its complete input space. The full
space is 256³ = 16.7M vectors (~151 MB of golden files). The argument for the
reduced sweep is:

- `gf_mac` is `gf_mul` + one XOR
- `gf_mul` is already exhaustively proven over all 65,536 pairs
- so the only unverified logic is the 8-bit XOR
- walking-1/walking-0 across 8 bits exercises every bit in both polarities against
  every product bit, which is everything an 8-bit XOR can do

That argument is only credible *because* 2.2 demonstrates the sweep catches a real
bug the zero case misses. Coverage claims need evidence, not reasoning alone.

---

# Lab 3 — Synthesize in the Quartus GUI

**Proving:** you can take RTL to gates and read what the tool produced.

## 3.1 New project

Launch `D:\Downloads\quartus\bin64\quartus.exe`. **File → New Project Wizard**.

| Page | What to enter |
|---|---|
| Directory, Name, Top-Level Entity | Working dir: `C:/Users/HP/Documents/Code/gf256-rtl/syn_gui` — a **new** folder, do not reuse `syn/`, which the Tcl script owns. Name: `gf_mul_shift`. Top-level entity: `gf_mul_shift` — **must match the module name exactly** |
| Project Type | Empty project |
| Add Files | Add `../rtl/gf_mul_shift.v` |
| Family & Device | Family: **Cyclone IV E**. Device: **EP4CE22F17C6** (filter Package FBGA, Pin count 256, Speed grade 6) |
| EDA Tools | Simulation: ModelSim-Altera, Verilog HDL. Optional |
| Summary | Finish |

Device choice matters for comparison, not correctness: **all variants must use the
same device and speed grade or the numbers are meaningless.** The `C6` suffix is
the speed grade — lower is faster. A C6 part is faster than a C8, so quoting a
figure without the part number says nothing.

## 3.2 Constrain the timing

Without a constraint, timing analysis has nothing to measure against.
**Project → Add/Remove Files in Project → Add** `syn/mul.sdc`.

That file is three active lines:

```tcl
create_clock -name virt_clk -period 10.000
set_input_delay  -clock virt_clk 0.000 [all_inputs]
set_output_delay -clock virt_clk 0.000 [all_outputs]
```

Read what it is doing. These modules have **no clock and no registers**, so there
is no register-to-register path for timing analysis to walk. The virtual clock plus
zero I/O delays turns the combinational input-to-output cone into a *constrained
path* that STA will report on. It is a measurement fixture, not a description of
how the module would be clocked in a real design.

## 3.3 Compile

**Processing → Start Compilation** (Ctrl+L). Roughly 30 seconds.

Read the Compilation Report:

- **Flow Summary** — total logic elements, registers, memory bits, pins
- **Analysis & Synthesis → Messages** — where inferred-latch warnings appear
- **Fitter → Resource Section → Resource Usage Summary**
- **TimeQuest Timing Analyzer** — Lab 5

For `gf_mul_shift` expect **62 logic elements, 0 registers, 0 memory bits**.

## 3.4 The latch check

Search the Messages pane for `latch`. You want **nothing**.

An inferred latch means a combinational `always` block did not assign its output on
every path, so the synthesizer built a level-sensitive storage element you did not
ask for. They are a classic source of silicon bugs: they make timing unanalyzable
and are sensitive to glitches. The reason these modules are clean is that every
output uses continuous `assign` — there is no path where an output goes unassigned.

## 3.5 Repeat for the others

Same procedure, new project folder each time:

| Project | Files to add | Notes |
|---|---|---|
| `gf_mul_lut` | `rtl/gf_mul_lut.v` | ROM path issue, below |
| `gf_inv` | `rtl/gf_inv.v` | Same ROM path issue |
| `gf_mac` | `rtl/gf_mac.v` **and** `rtl/gf_mul_shift.v` | Needs its submodule |

**The ROM path trap.** `gf_mul_lut` and `gf_inv` initialize tables with
`$readmemh("golden/gf_log.hex", ...)`. Quartus resolves that relative to the
*project* directory, not the .v file, so it fails with:

```
Error (10054): Verilog HDL File I/O error ... can't open ... "golden/gf_log.hex"
```

The paths are module **parameters** precisely so each tool can retarget them. Use
**Assignments → Parameters** and set:

```
LOG_FILE = ../tb/golden/gf_log.hex
EXP_FILE = ../tb/golden/gf_exp.hex
```

Relative to your `syn_gui` folder — adjust if you nested it differently. This is a
real lesson: path resolution differs between simulator and synthesizer, and
hard-coding a path that suits one breaks the other.

## 3.6 Fill in your own table

| Module | LEs | Registers | Memory bits | Latches |
|---|---|---|---|---|
| `gf_mul_lut` | | | | |
| `gf_mul_shift` | | | | |
| `gf_inv` | | | | |
| `gf_mac` | | | | |

Committed results for comparison: **804 / 62 / 211 / 65** LEs, all with 0
registers, 0 memory bits, 0 latches. **If yours differ, work out why before moving
on** — different device, different optimization setting, or a missing file are the
usual causes.

---

# Lab 4 — Look at the logic

**Proving:** you can connect Verilog you wrote to the gates it became. This is
where "why is the table version bigger" stops being a claim and becomes something
you have seen.

## 4.1 RTL Viewer — what the tool understood

With `gf_mul_shift` compiled: **Tools → Netlist Viewers → RTL Viewer**.

This shows your design *before* technology mapping — still generic logic.

Find the eight `xtime` stages. Each is a shift (just rewiring — **a shift by a
constant costs zero gates**, it is only which wire goes where) plus an 8-bit XOR
gated by `x[i][7]`. Trace one stage and match it against:

```verilog
assign x[i+1] = {x[i][6:0], 1'b0} ^ (x[i][7] ? 8'h1D : 8'h00);
```

Then find the accumulate chain: `acc[i+1] = acc[i] ^ (x[i] & {8{b[i]}})`. Eight of
those in series. **That series chain is the critical path** — 8 XOR levels deep,
which is what sets the 7.71 ns.

## 4.2 Technology Map Viewer — what it actually built

**Tools → Netlist Viewers → Technology Map Viewer (Post-Fitting)**.

Now you see real Cyclone IV atoms. Each logic element is a **4-input LUT plus a
register**; here the registers are unused. A 4-LUT is a 16-entry truth table, so
any function of ≤4 inputs costs exactly one LE. Wider functions decompose into a
tree.

62 LEs for 8 output bits is roughly 8 LEs per output bit.

## 4.3 Now do the same for gf_mul_lut

Open its Technology Map Viewer and compare. 804 LEs for the same function.

**Find the tables.** They are not memory blocks — they are combinational logic.
That is the whole story of this project's headline result: a 256-entry × 8-bit
table becomes a 2048-bit truth table implemented as a LUT tree, and there are two
of those plus a 512-entry one.

**Ask yourself the question an interviewer will ask:** the device has 608,256
memory bits and 66 M9K blocks sitting idle. Why did Quartus not use them?

The answer is Lab 6. Try to work it out first from what you can see — look at
whether anything registers the address before the lookup.

---

# Lab 5 — Read a timing report properly

**Proving:** you can interpret STA output, which is a core skill in this field and
the most likely place a screen goes deep.

## 5.1 Open TimeQuest

With `gf_mul_shift` compiled: **Tools → TimeQuest Timing Analyzer**.

In TimeQuest: **Netlist → Create Timing Netlist**, then **Read SDC File**, then
**Update Timing Netlist**. The compile already did this; doing it by hand once
makes the flow concrete.

## 5.2 The corners

**Tasks → Reports → Slow 1200mV 85C Model → Report Fmax Summary**.

Quartus analyzes multiple **corners** — combinations of process, voltage and
temperature. You will see Slow 85C, Slow 0C, and Fast 0C.

**Always quote the slow corner.** It is the worst case, and a design that meets
timing only at the fast corner does not work. For `gf_mul_shift` at slow 1200mV
85C:

```
; Fmax       ; Restricted Fmax ; Clock Name ; Note                                           ;
; 129.63 MHz ; 100.02 MHz      ; virt_clk   ; limit due to minimum period restriction (tmin) ;
```

## 5.3 Two columns, and why they differ

This catches people out. Understand it before you quote a number.

**Fmax (129.63 MHz)** is what the logic supports. The combinational delay is
7.714 ns, and 1/7.714 ns = 129.63 MHz. Verify it by hand from the slack: the
constraint was 10 ns, reported setup slack is +2.286 ns, so path delay is
10 − 2.286 = 7.714 ns.

**Restricted Fmax (100.02 MHz)** is lower because of `tmin` — a minimum pulse
width / minimum period restriction of the **device**, not of your logic. Some
Cyclone IV resources cannot be clocked faster than a certain rate regardless of how
fast the combinational path is.

Now compare `gf_mul_lut`:

```
; 77.22 MHz ; 77.22 MHz ; virt_clk ;   ;
```

**No restriction, and the two columns are equal.** Its own logic delay (12.95 ns)
is already slower than the device floor, so the device limit never binds.

**This asymmetry is worth understanding**, because it separates reading a number
off a screen from knowing what it means. The honest comparison:

- On **logic delay**: shift beats table 7.71 ns vs 12.95 ns — a real 1.7× win
- On **achievable clock in this device**: 100.02 vs 77.22 MHz — still a win, but
  smaller, because the shift version hits a device floor the table version never
  reaches

## 5.4 The critical path

**Tasks → Reports → Custom Reports → Report Timing**. Set *From clock* and *To
clock* to `virt_clk`, Detail level **Path only**, click Report Timing.

Expand the worst path. You will see each hop: cell delays (inside a LUT) and
interconnect delays (routing between LEs). Add them up.

**Look at the ratio of routing to logic delay.** On small designs like this,
routing is often a large fraction. That is a real and frequently surprising result
— designers new to FPGAs assume gate count dominates, but wires often do.

## 5.5 A caveat to state out loud

These are **combinational** modules. "Fmax" here is a derived figure: it is the
clock ceiling for a design that wraps this logic between registers. It is not the
module's own clock rate, because the module has no clock.

Saying that unprompted in an interview signals you understand what you measured
rather than having copied a number out of a report. The README states it the same
way for the same reason.

---

# Lab 6 — Reproduce the M9K experiment

**Proving:** you can form a hypothesis, build the experiment, and interpret a
result that overturns an expectation.

## 6.1 The question

From Lab 4: `gf_mul_lut` needs 804 LEs for tables the device has ample memory for.
`Auto ROM Replacement` is **On** — check **Assignments → Settings → Analysis &
Synthesis Settings → More Settings** — and 66 M9K blocks are idle.

**Hypothesis:** M9K blocks require a *registered* read address. Cyclone IV memory
is synchronous — the address is captured on a clock edge. `gf_mul_lut` reads its
tables combinationally (`wire [7:0] log_a = gf_log[a];`), so there is no clock edge
to capture an address, and Quartus has no choice but to build logic.

## 6.2 The test

`experiments/gf_mul_lut_reg.v` is already in the repo — same log/antilog algorithm,
reads registered across three pipeline stages. **Read it before synthesizing it.**

New Quartus project, top-level `gf_mul_lut_reg`. It has a real `clk`, so the SDC is
different — a genuine clock, not a virtual one:

```tcl
create_clock -name clk -period 5.000 [get_ports clk]
derive_clock_uncertainty
```

Set `LOG_FILE`/`EXP_FILE` parameters as in Lab 3.5. Compile.

## 6.3 The result

| variant | LEs | mem bits | regs | Fmax |
|---|---|---|---|---|
| `gf_mul_lut` (async) | 804 | 0 | 0 | 77.2 MHz |
| `gf_mul_shift` | 62 | 0 | 0 | 129.6 MHz |
| `gf_mul_lut_reg` | **23** | **6,144** | 10 | **179.6 MHz** |

Hypothesis confirmed, decisively. Logic collapses 804 → 23 LEs, the tables move
into 2 of 66 M9K blocks, and Fmax becomes the highest of the three.

Confirm in the Fitter report: **Resource Section → RAM Summary** should show 2 M9K
blocks. 6,144 bits covers the 256×8 log table and the 512×8 exp table.

## 6.4 The part that matters

**It is not a free win.** Throughput is one result per clock, but **latency is 3
cycles** and the output is registered, not combinational. Every consumer must be
pipeline-aware. The verified core keeps all four modules combinational so they
compose without any latency bookkeeping.

Also: **this experiment is not verified.** `run_tests.sh` drives combinational
DUTs. Checking a 3-stage pipeline needs a clocked testbench that aligns expected
values 3 cycles behind the stimulus. The file is labelled a *synthesis result, not
a verified module*, and the README says so.

**That distinction is itself the interview point.** Being able to say "I measured
this but have not verified it, and here is what verifying it would require" is a
stronger signal than an unqualified claim.

## 6.5 Optional: verify it

Write `tb_gf_mul_lut_reg.sv`. Drive `a`, `b` on `posedge clk`; the expected value
must be delayed 3 cycles to line up with `p`. A shift register of expected values is
the simplest alignment. Reuse the same golden vectors.

Genuinely useful exercise — pipeline alignment in a testbench is a skill you will
use constantly.

---

# Lab 7 — Your own experiments

Ranked by payoff-to-effort. Each is a real question with a measurable answer.

**(a) Speed grade sensitivity.** Recompile `gf_mul_shift` on EP4CE22F17**C8**
instead of C6. How much does Fmax drop? Teaches you that a quoted Fmax is
meaningless without the part number.

**(b) Optimization mode.** **Assignments → Settings → Compiler Settings →
Optimization Technique**: Balanced / Speed / Area. Three compiles, three rows. Does
Speed actually buy Fmax, and what does it cost in LEs?

**(c) Pipeline the shift multiplier.** Register between `xtime` stages. Where is the
sweet spot between latency and Fmax? The single most interview-relevant extension —
pipelining questions are near-universal.

**(d) A parallel GF multiplier.** Compute all eight partial products at once and
XOR-reduce in a tree instead of a chain. Should shorten the critical path at some
area cost. Verify against the same golden vectors and you have a *third*
microarchitecture in the equivalence check.

**(e) Where does `gf_inv`'s 211 LEs go?** One table lookup plus a subtract, yet 3×
the shift multiplier's cost. Find out in the Technology Map Viewer.

For any of these: **add it to the exhaustive testbench.** A new microarchitecture
that is not in the equivalence check is not verified, and the credibility of this
whole project rests on that discipline.

---

# Interview preparation

## The story to lead with

> I built the same GF(2⁸) multiplier two ways and measured both. The table version
> — which mirrors my C++ directly — came out 13× larger and 1.7× slower than the
> shift-and-reduce version, the opposite of what I expected. I dug into the Fitter
> report: 804 logic elements and zero memory bits, on a device with 66 idle M9K
> blocks. The reason was that my ROM reads were asynchronous, and Cyclone IV memory
> needs a registered address. I registered it and the design collapsed to 23 LEs at
> 180 MHz — but now with 3-cycle latency, so I kept the combinational version as
> the deliverable.

Hypothesis → measurement → surprise → root cause → fix → understood tradeoff. That
is the shape of real engineering work, and every step is yours.

## Questions to be ready for

**"Why 0x11D and not 0x11B?"**
Because the C++ I was verifying against uses 0x11D, and that C++ was the reference.
0x11B is AES's polynomial and is more common in textbooks — substituting it produces
plausible but wrong results. My vector generator refuses to emit unless α⁸ == 0x1D,
which is 0x11D's signature. One discriminating case: 0x57 · 0x83 is 0x31 in this
field, 0xC1 under AES.

**"How do you know your testbench works?"**
I injected bugs and confirmed each was caught: an index error in the LUT multiplier,
the 0x1D→0x1B substitution in the shift version, and `^`→`|` in the MAC. The last
is the instructive one — it passes the `acc_in = 0` case entirely and is caught only
by the walking-bit patterns, which is why that sweep exists.

**"Why exhaustive instead of random or formal?"**
The multiplier's input space is 2¹⁶. Exhaustive *is* a proof at that size and runs
in seconds, so a coverage argument is unnecessary. For `gf_mac` the space is 2²⁴
(~151 MB of vectors), so there I argued structurally: a proven multiplier plus one
XOR, with walking-bit patterns fully exercising an 8-bit XOR. I documented that
reasoning rather than quietly sampling.

**"Is this a Reed–Solomon decoder?"**
No, and I am careful about that. It is the arithmetic layer beneath one. No
Berlekamp-Massey, no Chien search, no Forney — the original C++ does erasure
decoding by Gaussian elimination and matrix inversion and has none of those either.
The RTL mirrors the algorithm I actually built.

**"What is the critical path?"**
In the shift version, the eight serial accumulate stages:
`acc[i+1] = acc[i] ^ (x[i] & {8{b[i]}})`. Eight XOR levels, 7.71 ns at the slow 85C
corner. The shifts themselves are free — shifting by a constant is rewiring.

**"What would you do differently?"**
Pipeline it. Everything here is combinational so the modules compose freely, but a
real datapath would register between stages. The M9K experiment is the first step in
that direction, and I would verify it with a clocked testbench that aligns expected
values 3 cycles back.

**"Why write it twice?"**
Partly to show I understand that one algorithm has multiple hardware realizations.
The practical payoff was the equivalence check: when I injected the polynomial bug
the two implementations disagreed, proving they share no common-mode error. A single
implementation checked against its own author's assumptions is much weaker.

## Two things to be honest about

**Restricted Fmax.** The shift version's raw Fmax is 129.63 MHz but its *restricted*
Fmax is 100.02 MHz, limited by a device `tmin` restriction rather than by my logic.
The table version shows no restriction because its own delay is already slower than
the device floor. On logic delay the win is 1.7×; on achievable clock in this part it
is smaller. Knowing the difference is the point.

**These are combinational modules.** "Fmax" is derived — the ceiling for a design
that wraps this logic between registers, not the module's own clock rate. Say it
before someone asks.
