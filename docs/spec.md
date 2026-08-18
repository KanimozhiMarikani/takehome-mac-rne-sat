# `mac_rne_sat` — Functional Specification

## 1. Overview

`mac_rne_sat` is a signed 8×8 multiply-accumulate unit with a rounded,
saturated readout port and a sticky overflow flag. All behavior is
synchronous to the rising edge of `clk`. Reset is synchronous and
active-high.

Keep the internal accumulator at full 28-bit precision. Rounding and
saturation happen **only at readout**, never on each accumulate.

## 2. Interface

| Port        | Dir | Type              | Description                                      |
|-------------|-----|-------------------|--------------------------------------------------|
| `clk`       | in  | `logic`           | Clock. All sequential behavior on the rising edge. |
| `rst`       | in  | `logic`           | Synchronous, active-high reset.                  |
| `en`        | in  | `logic`           | Accumulate `a*b` this cycle.                     |
| `clr`       | in  | `logic`           | Clear the accumulator this cycle.                |
| `rd`        | in  | `logic`           | Request a readout snapshot this cycle.           |
| `a`         | in  | `logic signed [7:0]`  | Multiplicand.                                |
| `b`         | in  | `logic signed [7:0]`  | Multiplier.                                  |
| `res`       | out | `logic signed [15:0]` | Rounded + saturated readout result (registered). |
| `res_valid` | out | `logic`           | Registered pulse: `rd` delayed by **exactly one flip-flop**. |
| `ovf`       | out | `logic`           | Sticky saturation flag (registered).             |

All control inputs (`en`, `clr`, `rd`) are sampled on every rising edge and
may be asserted in any combination. `a` and `b` are consumed only on cycles
where the accumulator takes a product (see §3).

## 3. Accumulator

The internal accumulator `acc` is a 28-bit signed two's-complement register.
The product `p = a * b` is a signed 16-bit value, sign-extended to 28 bits
before use.

Accumulator update at each rising edge (with `rst = 0`):

| `clr` | `en` | `acc` next value |
|-------|------|------------------|
| 0     | 0    | `acc` (hold)     |
| 0     | 1    | `acc + p`        |
| 1     | 0    | `0`              |
| 1     | 1    | `p` — clear-then-accumulate: load `p` alone (not `0`, not `acc+p`) |

The grading testbench guarantees the accumulator value never exceeds the
signed 28-bit range, so accumulator wrap behavior is unspecified and need
not be handled.

## 4. Readout path

Asserting `rd` in cycle *t* requests a snapshot readout.

**Latency (one flop, not two).** Sample `rd` on the rising edge of cycle *t*.
On the **next** cycle (*t+1*) `res_valid` is 1 and `res` holds the rounded,
saturated snapshot. That *t+1* result **is** the registered sample of cycle
*t* — do **not** add a second pipeline (for example `rd` → `rd_d` →
`res_valid`). `res_valid` is exactly one cycle wide per `rd`.

The key rule is: `rd` itself is the trigger for the readout; `res_valid` is
only the one-cycle-delayed acknowledgment. Do not create a second delayed
version of `rd` and then use that as the actual readout event.

```
          t              t+1             t+2
clk       /‾\___/‾\      /‾\___/‾\       /‾\___/‾\
rd        ____/‾‾‾‾‾‾‾‾‾‾\______________
res_valid _______________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾\________
res       ...............|  snapshot    | hold...
```

**Snapshot value.** The snapshot is `acc` as it stood at the end of cycle
*t−1* — **before** any `en`/`clr` update in cycle *t*. Compute rounding
from that current `acc`; then, on the same rising edge, apply the
accumulator update. Do not round from a separately delayed snapshot
register while also delaying `res_valid`.

Important: the readout logic and the accumulator update are both evaluated on
that same rising edge. The snapshot is always the old `acc`, regardless of
whether `en` and/or `clr` are also high in that same cycle. `rd` does not
change the snapshot value; it only asks for a snapshot, and the update still
happens afterward for the same cycle.

Same-cycle combinations (snapshot is always the old `acc`):

| same-cycle inputs | snapshot (for this readout) | `acc` next |
|-------------------|-----------------------------|------------|
| `rd` + `en`       | old `acc`                   | `acc + p`  |
| `rd` + `clr`      | old `acc`                   | `0`        |
| `rd` + `clr` + `en` | old `acc`                 | `p`        |

**Rounding — round-half-to-even at the 8 LSBs, only at readout.**
This is **not** round-half-up: a tie (`r == 128`) does **not** always
round away from zero. Use floor division, including for negatives.
Verilog `acc / 256` truncates toward zero and is **wrong** here.
Equivalent: `q = snapshot >>> 8` (arithmetic shift) and
`r = snapshot − (q <<< 8)`, so `0 ≤ r ≤ 255` even when `snapshot` is
negative.

- `q` if `r < 128`;
- `q + 1` if `r > 128`;
- on a tie (`r == 128`): `q` if `q` is even, else `q + 1`.

**Saturation — applied after rounding.** Clamp the **rounded** value to
signed 16-bit `[−32768, +32767]`. Rounding may itself step past the
16-bit range; saturate only after that. Exact `−32768` is **in range**
and must **not** set `ovf`.

**Hold.** Between readouts, `res` **holds** its last value. Do not
recompute `res` every cycle from `acc`, and do not clear `res` when
`res_valid` goes low. Back-to-back `rd` cycles are allowed; each takes
its own snapshot.

Worked examples (`snapshot → res`):

| snapshot | q      | r   | res     | ovf | note                                      |
|----------|--------|-----|---------|-----|-------------------------------------------|
| 640      | 2      | 128 | 2       | 0   | tie, q even → stays (not round-half-up)   |
| 896      | 3      | 128 | 4       | 0   | tie, q odd → rounds up                    |
| −384     | −2     | 128 | −2      | 0   | tie, q even → stays                       |
| −704     | −3     | 64  | −3      | 0   | negative, r < 128, no tie                 |
| −8388608 | −32768 | 0   | −32768  | 0   | exact 16-bit min, **not** saturation      |
| 8388608  | 32768  | 0   | 32767   | 1   | rounded value already out of 16-bit range |

(The last two rows illustrate saturation vs. in-range min; they are not
the only saturating cases. A tie at `q = 32767`, `r = 128` rounds to
32768 and then saturates to 32767 with `ovf = 1`.)

## 5. Overflow flag

`ovf` is a registered, sticky flag. It updates on the **same rising edge**
as the corresponding `res_valid` (the edge that registered that readout).
There is no extra cycle of delay beyond that.

- **Set** when that readout’s rounded snapshot is strictly outside
  `[−32768, +32767]`.
- **Cleared** only by `clr` (or `rst`).
- **Same-cycle priority:** if a saturating `rd` and `clr` are both sampled
  on that edge, the set wins — `ovf` becomes 1. `clr` clears `ovf` only
  when that same edge is **not** a saturating readout.
- A non-saturating readout leaves `ovf` unchanged. `res` always carries
  the clamped value; saturation is signaled only via `ovf`.
- The `ovf` update happens on the same rising edge as the corresponding
  `res_valid` update, not one cycle later.

## 6. Reset

`rst` is synchronous and active-high, and overrides `en`/`clr`/`rd`. On a
rising edge with `rst = 1`: `acc`, `res`, `res_valid`, and `ovf` all clear
to 0.

## 7. Implementation constraints

- Synthesizable SystemVerilog, compatible with Icarus Verilog (`-g2012`).
- Prefer `always @(posedge clk)` and `always @*` over `always_ff` /
  `always_comb`. Icarus does not fully support part-selects inside
  `always_*` processes.
- No SystemVerilog Assertions (SVA).
- Do not change the module name, port names, directions, or widths.
- Single clock domain. No latches.
