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
launch overhead. The same grammar dependencies make CPU thread launch and
output stitching more expensive than serial parsing for the covered kernels.

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
