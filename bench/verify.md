# Verification Report

**Date:** 2026-11-11
**Machine:** Intel(R) Xeon(R) CPU E5-2697 v4 @ 2.30GHz; Python 3.13.14; Mistune 3.3.4
**Commands:** `pixi run build && pixi run test && pixi run bench`

## Test Suite

All 69 parity tests pass. No assertions were removed or loosened since the initial commit (`git log -p -- tests/` shows only the initial commit adding the test file).

## Benchmark Reproduction

### Large Documents (best of 5 runs, output equality asserted)

| workload | README mojo | Measured mojo | README mistune | Measured mistune | README speedup | Measured speedup | Mojo Δ | Mistune Δ | Speedup Δ |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| plain paragraphs | 42.45 ms | 35.71 ms | 354.84 ms | 364.21 ms | 8.36x | 10.20x | +15.9% | +2.6% | **+22.0%** |
| inline-heavy | 25.22 ms | 24.14 ms | 2567.20 ms | 2629.00 ms | 101.79x | 108.92x | -4.3% | +2.4% | +7.0% |
| fenced code | 6.53 ms | 3.81 ms | 83.61 ms | 86.22 ms | 12.81x | 22.63x | **+41.7%** | +3.1% | **+76.7%** |
| table plugin | 49.57 ms | 41.64 ms | 1440.98 ms | 1477.23 ms | 29.07x | 35.48x | -16.0% | +2.5% | **+22.1%** |

### Short Documents (best of 5 runs, per-call via repeated calls)

| workload | README mojo | Measured mojo | README mistune | Measured mistune | README speedup | Measured speedup | Mojo Δ | Mistune Δ | Speedup Δ |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| empty | 0.38 us | 0.42 us | 5.75 us | 6.00 us | 15.14x | 14.29x | +10.5% | +4.3% | -5.6% |
| one paragraph | 5.39 us | 5.17 us | 60.14 us | 62.90 us | 11.15x | 12.16x | -4.1% | +4.6% | +9.1% |
| README-sized | 26.32 us | 21.29 us | 1673.40 us | 1716.55 us | 63.57x | 80.64x | **-19.1%** | +2.6% | **+26.9%** |

**Legend:** Positive Δ means measured is higher (slower for times, faster for speedup). **Bold** = exceeds 20% threshold requiring README correction.

## Findings

### Reproduced within 20% (no README change needed)
- inline-heavy (both times and speedup)
- table plugin mojo time and mistune time
- empty, one paragraph (all metrics)

### Exceed 20% threshold (README updated to measured values)
1. **plain paragraphs speedup**: README 8.36x → measured 10.20x (+22%)
2. **fenced code mojo time**: README 6.53 ms → measured 3.81 ms (-42%)
3. **fenced code speedup**: README 12.81x → measured 22.63x (+77%)
4. **table plugin speedup**: README 29.07x → measured 35.48x (+22%)
5. **README-sized speedup**: README 63.57x → measured 80.64x (+27%)

### No evidence of benchmark cheating
- Each row runs both implementations on identical input
- Output equality is asserted before timing (`if actual != expected: raise AssertionError`)
- Both implementations warm up before measurement
- Large docs: single call per repeat. Short docs: repeated calls per batch to amortize boundary
- Machine-wide lock (`flock /tmp/mojo-bench.lock`) prevents concurrent bench jobs

### Parity Tests
- `git log -p -- tests/` shows only the initial commit adding the full test suite
- No assertions were removed, no tolerances loosened
- All 69 tests pass, covering blocks, inlines, tables, HTML, renderer options, utilities, signatures, error paths, and native boundary validation

## Changes Made

Updated README.md benchmark tables with measured values for the 5 rows exceeding 20% variance. All other values kept as originally reported (within 20%).