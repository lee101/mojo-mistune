# mojo-mistune

`mojo-mistune` is a standalone Mojo implementation of Mistune's core Markdown
to HTML path. It exposes the familiar `html`, `markdown`, `create_markdown`,
`Markdown`, and `HTMLRenderer` names from Python while the parsing and rendering
work runs in one compiled Mojo kernel.

Use it as a covered-subset replacement:

```python
import mojo_mistune as mistune

markdown = mistune.create_markdown(
    escape=True,
    hard_wrap=False,
    plugins=["strikethrough", "table"],
)

print(markdown("# Mojo\n\nFast **Markdown** with [links](https://example.com).\n"))
```

This prints:

```html
<h1>Mojo</h1>
<p>Fast <strong>Markdown</strong> with <a href="https://example.com">links</a>.</p>
```

## Coverage

The covered block syntax is paragraphs, soft and hard line breaks, ATX and
setext headings, thematic breaks, flat ordered and unordered lists, indented
list continuations, paragraph block quotes, fenced and indented code, raw HTML
blocks, and pipe tables. Inline coverage includes backslash escapes, code
spans, emphasis, strong emphasis, strikethrough, inline links and images,
automatic URL and email links, inline HTML, entities, Unicode text, and harmful
URL filtering.

The Python API supports:

| upstream name | covered behavior |
| --- | --- |
| `html(text)` | unescaped HTML plus Mistune's `strikethrough` and `table` defaults |
| `markdown(text, escape=True, renderer="html", plugins=None)` | HTML renderer |
| `create_markdown(escape=True, hard_wrap=False, renderer="html", plugins=None)` | reusable HTML parser |
| `Markdown(HTMLRenderer(...), plugins=...)` | reusable HTML parser |
| `HTMLRenderer(escape=True)` | renderer configuration |
| `escape`, `escape_url`, `safe_entity`, `unikey` | utility helpers |

The AST renderer, reference-style links, nested or loose multi-block lists,
arbitrary block nesting inside quotes, custom parser/renderer hooks, and
Mistune plugins other than `strikethrough` and `table` are not implemented.
Unsupported renderer and plugin requests raise `NotImplementedError` instead
of silently producing different output. This is not yet the full CommonMark
edge-case surface; use upstream Mistune when documents depend on the omitted
constructs.

The test suite checks exact output against the real `mistune` package,
including renderer options, HTML safety, tables, Unicode, and unsafe inline
input. It also exercises invalid native-boundary calls.

## Install

The repository pins its own Mojo nightly and installs Mistune for parity tests:

```bash
pixi install
pixi run build
pixi run test
```

`pixi run build` invokes `mojo build --emit shared-lib` and writes
`dist/libmojo-mistune.so`. The Python wrapper also rebuilds a missing or stale
library on first use. Set `MOJO_MISTUNE_LIB` to load a prebuilt library from a
different location.

Run the example directly with:

```bash
pixi run python -c 'import mojo_mistune as m; print(m.html("# hello"))'
```

## Performance

Measured with `pixi run bench` on an Intel Xeon E5-2697 v4 at 2.30 GHz, Python
3.13.14, and Mistune 3.3.4. Each row is complete UTF-8 parse plus HTML render
and Python return-string construction. The best of five runs is reported;
output equality is asserted before timing.

| workload | input | mojo-mistune | mistune | speedup |
| --- | ---: | ---: | ---: | ---: |
| plain paragraphs | 1.46 MB | 42.45 ms | 354.84 ms | 8.36x |
| inline-heavy | 1.74 MB | 25.22 ms | 2567.20 ms | 101.79x |
| fenced code | 0.45 MB | 6.53 ms | 83.61 ms | 12.81x |
| table plugin | 0.72 MB | 49.57 ms | 1440.98 ms | 29.07x |

Short-call measurements from the same locked run identify boundary overhead
that the large-document table hides:

| short workload | input | mojo-mistune | mistune | speedup |
| --- | ---: | ---: | ---: | ---: |
| empty | 0 B | 0.38 us | 5.75 us | 15.14x |
| one paragraph | 22 B | 5.39 us | 60.14 us | 11.15x |
| README-sized | 914 B | 26.32 us | 1673.40 us | 63.57x |

No GPU path is provided. Markdown parsing is a branch-heavy, sequential byte
stream transformation with substantially less than two arithmetic operations
per byte moved, so its arithmetic intensity does not justify transfer and
launch overhead.

### Thread parallelism: tested, measured, reverted

A parallel path was implemented and then removed. It split the document at
blank-line boundaries (the block parser keeps no state across blocks, and
every construct that swallows following lines — fenced code, indented code,
raw HTML blocks — is closed by a blank line), rendered each chunk into its own
window of the output buffer, and stitched the windows back together. Before it
was measured it was proven byte-identical to serial output: at 1, 2, 3, 4 and
8 workers on the four benchmark documents, plus fence-at-EOF, a 1.5 MB
document with no blank line at all, CRLF separators and a 1.7 MB table
document.

It was reverted because it never beat serial. Kernel time for the same input
and buffers, interleaved in one process, best of nine, under
`/tmp/mojo-bench.lock`:

| workload | input | 1 worker | 2 workers | 4 workers | 8 workers |
| --- | ---: | ---: | ---: | ---: | ---: |
| plain paragraphs | 1.46 MB | 22.84 ms | 25.15 ms | 25.64 ms | 25.80 ms |
| inline-heavy | 1.74 MB | 21.97 ms | 23.84 ms | 24.26 ms | 24.64 ms |
| fenced code | 0.45 MB | 1.80 ms | 2.50 ms | 2.51 ms | 2.47 ms |
| table plugin | 0.72 MB | 18.31 ms | 19.27 ms | 19.58 ms | 19.06 ms |

The gain flattens at zero and then reverses as workers are added; the 4-worker
cap is already worse than serial. A size sweep of the same code found no
crossover below that either (4 workers relative to serial, best of fifteen):

| input | 1 worker (serial) | 2 workers | 4 workers |
| ---: | ---: | ---: | ---: |
| 1 KB | 24.6 us | 22.6 us | 23.2 us |
| 4 KB | 82.6 us | 88.4 us | 90.0 us |
| 18 KB | 332.0 us | 330.8 us | 332.0 us |
| 72 KB | 1336.5 us | 1324.5 us | 1131.8 us |
| 293 KB | 4566.6 us | 5018.7 us | 5002.0 us |
| 1.19 MB | 18800.3 us | 21131.0 us | 21140.5 us |

The apparent 72 KB win (0.85x) did not reproduce at 293 KB (1.10x) and is
inside the ±15 % machine drift, so no threshold can be defended from it.

The cause is the worker count, not the chunking. `max.algorithm.parallelize`
on this toolchain has the signature
`parallelize(func, num_work_items, num_workers[, ctx])`, where `ctx` is an
`Optional[DeviceContext]` — there is no separate CPU thread-count parameter,
so `num_workers` is the only knob and it does not produce parallel execution
here. A native-build probe (not JIT) holds this with no parser involved:

| probe | 1 worker | 2 workers | 4 workers | 8 workers |
| --- | ---: | ---: | ---: | ---: |
| pure integer loop, `def(Int)` callback | 5 ms | 5 ms | 6 ms | 7 ms |

Adding workers only adds dispatch cost. Under that behaviour a parallel path
that loses to serial at every size a real caller passes is worse than no
parallelism, so the kernel stays serial. The build, test and benchmark results
below are from the reverted tree, unchanged from before this phase:

| run | plain | inline | fenced | table |
| --- | ---: | ---: | ---: | ---: |
| before (start of this phase) | 34.93 ms | 23.69 ms | 7.39 ms | 40.92 ms |
| parallel path present | 37.06 ms | 25.68 ms | 4.10 ms | 40.23 ms |
| after revert | 35.15 ms | 23.07 ms | 3.72 ms | 39.02 ms |

The first and third rows are the same serial code, so their spread is the
machine, not the change. No threshold or worker-count constant is shipped,
because none is earned by these measurements.

These measurements favor large documents, where one FFI call amortizes the
roughly microsecond-scale `ctypes` boundary. They do not imply the same
speedups for short README-sized strings. Reproduce them only through
`pixi run bench`; that task holds a machine-wide lock to avoid concurrent
benchmark jobs.

## How it works

`src/mistune.mojo` is one compilation unit containing the block parser, inline
parser, escaping logic, URL policy, and HTML writer. Python encodes the source
string once as contiguous UTF-8 and passes its address and length through
`ctypes`. Buffers cross the ABI as 64-bit `Int` addresses and are reconstructed
as untracked mutable byte pointers inside the exported non-parametric C
function.

Python owns both contiguous byte buffers and keeps them alive for the complete
synchronous call. Mojo validates lengths and non-null addresses before
constructing pointers, never allocates, and writes only within the supplied
output capacity while separately counting the required length. If a document
expands beyond the initial estimate, the wrapper allocates the exact reported
size and retries. Native error statuses raise in Python. The result is decoded
once to a Python `str`; there are no NumPy dtype or stride assumptions, token
objects, callbacks, SIMD tails, or per-node FFI crossings on the HTML path.

## License

MIT
