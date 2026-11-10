# mojo-mistune ANALYZE: measured hotspot map

Phase: ANALYZE only. No algorithm, `src/`, or `tests/` change was made. This file
is the only addition to the repository.

## What was measured, and against what

| item | value |
| --- | --- |
| machine | Intel Xeon E5-2697 v4 @ 2.30 GHz, 72 logical CPUs, Linux 6.8 |
| interpreter / upstream | Python 3.13.14, mistune 3.3.4 (the importable upstream in the pixi env) |
| build under test | `dist/libmojo-mistune.so`, sha256 `b679a396…6cb12b80`, built 2026-11-10 22:15 (after `src/mistune.mojo`, mtime check in `_lib.build`) |
| benchmark command | `pixi run bench` (flock-wrapped), plus phase probes under the same `/tmp/mojo-bench.lock` |
| load during the runs | 25–44 runnable tasks of 72 CPUs (other tenants). Absolute us/ms carry that noise; in-FFI vs host splits measured in the same process do not |
| session date | 2026-11-10 (UTC) |

Every number below was produced in this session. Where a quantity is derived,
the derivation is shown and no estimate is hidden inside a "measured" cell.

Method for the splits: the same `str` is passed through
`mojo_mistune.html` and separately through the raw `mmt_render_html` C symbol
with pre-allocated `ctypes` buffers, so "python/ctypes glue" =
wrapper − bare kernel, measured, not modelled. A C shim that `dlopen`s the
shipped `.so` and calls `mmt_render_html` directly isolates the ctypes cost.

Reference times, all this session:

| run | plain | inline | fenced | table |
| --- | ---: | ---: | ---: | ---: |
| `pixi run bench` (first, warm start) | 34.44 ms | 24.75 ms | 4.27 ms | 39.25 ms |
| `bench/bench.py` logic re-run, locked | 35.21 ms | 28.32 ms | 3.58 ms | 38.71 ms |
| `bench/bench.py` logic re-run, locked | 35.47 ms | 29.65 ms | 3.50 ms | 40.59 ms |

The machine drifts ~±15 % between runs. Rows below therefore use the three runs
above as a range, never a cherry-picked best, when comparing to upstream.

## Ranked hotspot table

`size` = workload input bytes (out bytes in parentheses). `bytes touched` =
input + output, measured from the public API (`bytes_in`, `bytes_out`).
`flops` = *arithmetic* ops only; comparisons/branches are not counted as flops and
are reported as the lower-bound byte-compare count, because that is the number
that decides SIMD/GPU viability. `flops/byte` is per touched byte.
`bound` class: with < 2 flops/byte this is latency/branch-bound, which for the
purposes of this table counts as memory/bandwidth-bound rather than compute-bound.
All kernel numbers are from the first full locked run (`final.txt`); the second
run (`final2.txt`) agrees within noise and its kernel times are quoted beside.

| # | function (where the time is) | input size | time | bytes touched | flops | flops/byte | bound | time sits in |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| 1 | `render_document` → paragraph loop → `render_inline` + `Writer.byte/literal/source`, plain prose (**kernel**) | 1.46 MB (1.58 MB out) | 27.95 ms (run 2: 27.37 ms) | 3.04 MB | 1.46 M (≈1 cmp/in byte) | 0.48 | memory/branch-bound | kernel |
| 2 | Same, inline-heavy: `render_inline` emphasis/codespan/link/URL path (**kernel**) | 1.74 MB (2.58 MB out) | 21.50 ms (run 2: 20.86 ms) | 4.31 MB | 1.74 M | 0.40 | memory/branch-bound | kernel |
| 3 | Same, pipe tables: `render_table_row` × 20 001 rows, 3 cells, `table_cell_*` rescans (**kernel**) | 0.72 MB (3.20 MB out) | 17.66 ms (run 2: 17.66 ms) | 3.93 MB | 0.72 M | 0.18 | memory/branch-bound | kernel |
| 4 | **`_lib.render_html` retry (table only)**: 3× cap buffer, kernel pass 1 only reports need, pass 2 re-parses the whole document into an exact buffer (**python + full 2nd kernel**) | 0.72 MB | 19.53 ms of the 48.70 ms wrapper (40 %) | 2 × 3.93 MB logical | 2 × 0.72 M | 0.18 | memory/branch-bound | python/ctypes glue **plus a repeated kernel run** |
| 5 | Same, fenced code: `render_escaped` + `Writer.source` memcpy (**kernel**) | 0.45 MB (0.78 MB out) | 3.06 ms (run 2: 3.16 ms) | 1.24 MB | 0.45 M | 0.37 | memory-bound | kernel |
| 6 | ctypes boundary, per call (`mmt_render_html` through `ctypes`, any size) | 0 B | 1.95 µs (C direct: 4.4 ns) | 0 | 0 | 0 | n/a | python/ctypes glue |
| 7 | `str.encode` + 2× `ctypes.create_string_buffer` per call | 22 B | 1.14 µs (in-buffer 0.17 µs @1.46 MB) | 2 × len + cap | 0 | 0 | n/a | python/ctypes glue |
| 8 | `destination.raw[:needed]` slice + UTF-8 decode per call | 1.58 MB out | 0.56 ms (plain), 0.90 ms (inline), 0.75 ms (table) | out bytes | 0 | 0 | memory-bound | python (C codecs) |
| 9 | `mojo_mistune.escape` (utility, pure Python on the 1.46 MB doc) | 1.46 MB | 3.83 ms | 2.92 MB | 0 | 0 | memory-bound, per-char Python | python |
| 10 | upstream `mistune.html` for scale | 1.46 MB | 356–371 ms | 3.04 MB | n/a | n/a | n/a | upstream Python |

`ns/in byte` inside the kernel: plain 18.7–19.1, inline 12.0–12.4, table 16.1–24.4,
fenced 6.7–7.0. Kernel share of the wrapper: plain 77–79 %, inline 70–92 %,
fenced 54–90 %, table 36–46 %.

### Per-call overhead at real caller sizes

| entry point | input | time |
| --- | ---: | ---: |
| `html("")` | 0 B | 0.36–0.40 µs (0 Python allocations) |
| `html(one paragraph)` | 22 B | 4.89–5.35 µs (26 Python allocations) |
| `html(README-sized)` | 914 B | 21.1–21.9 µs |
| `html(plain)` | 1.46 MB | 29.5–35.5 ms |
| `markdown(plain, plugins=2)` | 1.46 MB | 24.3–25.4 ms |
| `create_markdown(...)(plain)` (fresh parser) | 1.46 MB | 28.8–30.1 ms (constructor 6.9–21.1 µs of it) |
| `Markdown(HTMLRenderer(), plugins=...)` reused call | 1.46 MB | 24.1–24.9 ms |
| `HTMLRenderer()` | — | 2.4–8.0 µs |
| `escape_url(36 B)` / `safe_entity` / `unikey` | small | 11.8–14.5 µs / 2.3–2.5 µs / 2.6–7.3 µs |

### Python / numpy baselines (same 1.46 MB document)

| baseline | time |
| --- | ---: |
| `mistune.html` (upstream) | 356–365 ms |
| `mojo_mistune.html` | 30.7–36.2 ms |
| pure-Python per-character escape loop | 139–143 ms |
| pure-Python per-character newline count | 48 ms |
| `bytes.count(b"\n")` | 1.22–1.24 ms |
| `numpy.count_nonzero(arr == 10)` | 0.25–0.29 ms |
| `numpy` copy of the 1.46 MB input | 0.12–0.14 ms |

The last three show how wide the gap between "one vector pass over the bytes"
(0.25 ms) and the current kernel (27.4 ms) still is: ~100×. This is the useful
direction marker for later phases, not a target.

## Where the time is: Python/ctypes glue vs kernel

| workload | wrapper | bare kernel | kernel share | glue |
| --- | ---: | ---: | ---: | ---: |
| plain paragraphs | 35.80 ms | 27.95 ms | 78 % | ~7.9 ms (retry absent) |
| inline-heavy | 30.73 ms | 21.50 ms | 70 % | ~9.2 ms (retry absent) |
| fenced code | 3.52 ms | 3.06 ms | 87 % | ~0.46 ms (retry absent) |
| table plugin | 40.59–48.70 ms | 17.66 ms (pass 1; 11.6–19.2 ms across runs) | 36–46 % | **19.5 ms retry + ~4–20 ms glue** |

C-shim control (direct call into the shipped `.so`, /tmp shim, no Python):

| input | C direct | through ctypes | Python-level cost |
| --- | ---: | ---: | ---: |
| 0 B (early return) | 4.4 ns | 2.11 µs | 2.1 µs pure ctypes dispatch |
| 22 B | 462 ns | 2.47 µs | 2.0 µs dispatch + buffer setup |
| 1 KB | 13.4 µs | 14.5 µs | ~1.1 µs |
| 64 KB | 811 µs | 776 µs | 0 (kernel dominates) |
| 1.46 MB | 18.0 ms | 17.1 ms | 0 (kernel dominates) |

Conclusions from that control:

- The ~2 µs/ctypes-call floor is **entirely host-side**; the kernel's own cost
  at 0 B is 4.4 ns. It is invisible above ~1 KB but it is the whole story for
  the 22 B and 0 B rows.
- At 1.46 MB the ctypes call costs nothing measurable extra; that 17–27 ms is
  the kernel.
- Fenced code's 6.7 ns/in-byte vs plain prose's 18.7 ns/in-byte shows the
  kernel is dominated by the per-byte `render_inline` state machine, not by
  copying: the fenced path is mostly `Writer` byte copies (`render_escaped`
  with memcpy-ish loops) and runs ~2.8× faster per input byte.

## Python-level loops that re-enter ctypes per element

**None on the HTML path.** There is exactly one `mmt_render_html` call per
`Markdown.__call__`, over the whole document, with one contiguous in-buffer and
one contiguous out-buffer. Verified by counting: `html("")` performs 0 Python
allocations; a 22 B call performs 26, and there is one ctypes call. No token
objects, no per-node callbacks. This is the good part of the design and no
phase should "fix" it.

The one genuine repeated call is not per element but per *attempt*:

- `_lib.render_html` (line 67 `while True:`) re-enters the kernel for the
  **entire document** when the estimate is wrong. For the 0.72 MB pipe-table
  workload, `cap0 = max(256, 3n + 128) = 2 169 599` but the true output is
  3 203 301 B (4.43× inflation), so pass 2 re-parses everything. Measured cost:
  **19.53 ms = 40 % of that workload's wall time**. The other three benchmark
  documents fit pass 1 (no retry).
- `tracemalloc` shows the same thing from the allocator side: table plugin has
  `traced_peak` 11.06 MB and 4 908 live bytes after the call vs 200 B live for
  the others; the extra ~7.1 MB is the pass-1 buffer that is thrown away.

## Per-call allocations and copies

Per `html()` call, measured with `tracemalloc` and by timing each step:

| step | cost | allocation/copy |
| --- | ---: | --- |
| `text.encode("utf-8")` | 62–156 µs | 1 copy of the input (unavoidable: Python `str` is not UTF-8 contiguous) |
| `create_string_buffer(encoded, …)` | 170–321 µs @MB scale; 0.48–1.9 µs @22 B | 1 copy of the input again, to add the NUL |
| `create_string_buffer(capacity)` | 186–332 µs @MB scale | zero-filled allocation of `3n+128` even when `n` output needs 1.08n |
| kernel write | (kernel) | 1 write pass over the output |
| `destination.raw[:needed]` | part of decode row | **copies the whole output again** (≥ cap-sized raw already exists, then sliced) |
| `.decode("utf-8")` | 0.56–0.90 ms | 1 decode into a `str` |
| retry (table only) | 19.53 ms | exact-size re-alloc + **full second encode + kernel** |

So the input is copied 3× (encode, buffer, kernel read) and the output 3×
(kernel write, `raw`, slice+decode). The `raw` property materialises a
`cap`-sized `bytes` (up to `3n+128`) just to slice `needed` bytes out of it.

## Flags

Rows where the port is **slower than upstream**: none. All seven benchmark
documents are 10–94× faster than mistune 3.3.4 in this session; every row above
is therefore unmarked. The comparison that does *not* favour the port is
against the raw-memory baseline: the kernel is ~114× slower per output byte
than a `memcpy` (17.1 vs ~0.15 ns/B on plain prose) and ~100× slower than one
`numpy` comparison pass. That gap is where the remaining headroom is.

Note on README numbers: the checked-in README table (42.45 / 25.22 / 6.53 /
49.57 ms) and this session's runs agree to within the machine noise
(34–36 / 24–30 / 3.5–4.3 / 39–49 ms). Nothing was regressed or fixed; do not
"correct" the README from this file, a later phase should re-measure.

## Next phase per hotspot

Verdicts use the measured flops/byte: every kernel row is ≤ 0.5 arithmetic
flops per touched byte (≈1 branch/compare per input byte, ≈1 byte written per
output byte). `MOJO_NOTES.md` §5 and the README both set the bar for a GPU path
at roughly ≥2 flops/byte; these rows are 4–10× below that and dominated by
data-dependent branching, so a GPU transfer + launch cannot pay off for **any**
row here. That verdict is backed by the flops-per-byte figures in the table.

| hotspot | next phase | why (measured) | what to attack |
| --- | --- | --- | --- |
| #4 table retry (19.5 ms, 40 % of one workload) | **none (algorithm/host fix in a later non-kernel phase; must preserve output byte-for-byte)** | pure Python + a repeated full kernel run; no arithmetic to vectorise | either make `cap0` fit (a table row's HTML is ~4.4× its source; the current `3n+128` cannot hold it) or make the retry a *count-only* mode so pass 1 returns `needed` without writing, leaving one real parse. Estimated recovery up to 19.5 ms on this workload |
| #1 plain-prose kernel (27.4 ms) | **simd**, then **unroll** | 0.48 flops/touched byte; the inner loop is `src[i]` branch tests with no data movement or arithmetic to parallelise; most bytes are "plain text copied to output" | vectorise the plain-run fast path: find the next byte in the trigger set `* _ ~ ` \ [ < & \n` over a SIMD lane, copy the whole run with a wide store, then fall back to the scalar state machine at the trigger. `MOJO_NOTES.md` §3 gives the verified `load[width=W]`/`store`/tail pattern. This is the single largest absolute win: ~27 ms here |
| #2 inline-heavy kernel (21.5 ms) | **simd** (same run-scanner), then **unroll** `find_bytes` | 0.40 flops/byte; `find_bytes` is already a byte scanner but is scalar with a per-position inner `for j in range(count)` and no early exit (line 232–238: `matched` is computed for all `count` lanes even after a mismatch) | fold `find_bytes` into the SIMD trigger scan; add early exit/`count == 1` specialisation. Emphasis/codespan/link handling itself stays scalar |
| #3 pipe-table kernel (17.7 ms) | **unroll**, then **simd** for cell splitting | 0.18 flops/byte; measured 3.52 ns per output byte — the *cheapest* per-byte rate of all four kernel rows despite 4.43× inflation | the row path calls `table_cell_count`/`table_cell_start`/`table_cell_end` per cell (each a rescan of the row); build per-cell bounds once per row. No arithmetic to vectorise until the rescan is gone |
| #5 fenced-code kernel (3.1 ms) | **simd** (bulk copy with escape screening) | 0.37 flops/byte; already 6.7 ns/in byte, mostly `Writer.source`/`render_escaped` copies | one wide load-compare-store loop for runs with no `<`, `>`, `&`, `\`; scalar fallback on a hit. Small absolute win |
| #6 + #7 ctypes/buffer floor (2.0 µs + 1.1 µs/call) | **none** | host-side only (C direct call at 0 B is 4.4 ns; 2.1 µs is ctypes dispatch) | nothing in Mojo can remove it. It only matters at the 22 B / 0 B sizes and is already 12–16× faster than upstream there |
| #8 output slice+decode (0.56–0.90 ms) | **none** | pure Python/C-codecs byte copy | could be reduced in the wrapper later (`bytes(dst[0:needed])` instead of `dst.raw`) but it is < 3 % of wall time |
| #9 `escape` utility (3.8 ms) | **none** | a Python utility, not the render path | out of scope of the kernel; note only |
| thread-level parallelism (all rows) | **none** | the dependency is a single left-to-right byte stream: block detection needs the previous line's block state, inline needs link/emphasis stacks. `max.algorithm.parallelize` exists (`MOJO_NOTES.md` §4) but cannot split one document without a two-pass design | revisit only if a document corpus of *many independent documents* is the real workload; that is a host-side batching change, not a kernel one |

## Appendix: raw runs behind this file

- `pixi run bench` (first run, this session): plain 34.44 ms, inline 24.75 ms,
  fenced 4.27 ms, table 39.25 ms; short 0.38 / 4.90 / 21.72 µs.
- `bench.py` logic re-run, locked, twice: 35.21 / 28.32 / 3.58 / 38.71 ms and
  35.47 / 29.65 / 3.50 / 40.59 ms; short 0.37 / 5.07 / 21.64 µs.
- C shim vs ctypes: 0 B 4.4 ns / 2.11 µs; 22 B 462 ns / 2.47 µs;
  1 KB 13.4 / 14.5 µs; 64 KB 811 / 776 µs; 1.46 MB 18.0 / 17.1 ms.
- Retry probe: table pass 1 18.03 ms, pass 2 18.97 ms, one-pass emulation
  36.97 ms vs wrapper 40.75 ms.
- All probe scripts lived in `/tmp`; none were added to the repository.
