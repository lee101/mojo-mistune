"""Locked end-to-end Markdown rendering benchmarks against Mistune."""

from __future__ import annotations

import gc
import math
import platform
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))

import mistune  # noqa: E402
import mojo_mistune  # noqa: E402


def best_time(function, repeats: int = 5) -> float:
    best = math.inf
    for _ in range(repeats):
        gc.collect()
        started = time.perf_counter()
        function()
        best = min(best, time.perf_counter() - started)
    return best


def cpu_name() -> str:
    try:
        for line in Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith("model name"):
                return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return platform.processor() or platform.machine()


def documents() -> list[tuple[str, str]]:
    plain = "\n\n".join(
        f"Paragraph {i} contains ordinary prose, punctuation, and number {i * 17}."
        for i in range(20_000)
    )
    inline = "\n".join(
        f"Line {i}: **strong text**, *emphasis*, `code < {i}`, "
        f"[link](https://example.test/{i}?a=1&b=2), and ~~deleted~~."
        for i in range(15_000)
    )
    code = "\n\n".join(
        f"```python\nvalue_{i} = left < right and left & mask\n```"
        for i in range(8_000)
    )
    table_rows = "\n".join(
        f"| row {i} | {i * 3} | **value {i % 97}** |" for i in range(20_000)
    )
    table = (
        "| name | count | value |\n"
        "|:---|---:|:---:|\n"
        f"{table_rows}\n"
    )
    return [
        ("plain paragraphs", plain),
        ("inline-heavy", inline),
        ("fenced code", code),
        ("table plugin", table),
    ]


def short_documents() -> list[tuple[str, str, int]]:
    return [
        ("empty", "", 20_000),
        ("one paragraph", "A **small** document.\n", 2_000),
        (
            "README-sized",
            "\n\n".join(
                f"Section {i} has **bold text**, `code`, and [a link](https://example.test/{i})."
                for i in range(12)
            ),
            200,
        ),
    ]


def best_per_call(function, calls: int, repeats: int = 5) -> float:
    def batch() -> None:
        for _ in range(calls):
            function()

    return best_time(batch, repeats) / calls


def main() -> None:
    print(f"Machine: {cpu_name()}; Python {platform.python_version()}; Mistune {mistune.__version__}")
    print()
    print("| workload | input | mojo-mistune | mistune | speedup |")
    print("| --- | ---: | ---: | ---: | ---: |")
    for name, source in documents():
        expected = mistune.html(source)
        actual = mojo_mistune.html(source)
        if actual != expected:
            raise AssertionError(f"benchmark parity failed for {name}")
        mojo_mistune.html(source)
        mistune.html(source)
        mojo_seconds = best_time(lambda: mojo_mistune.html(source))
        python_seconds = best_time(lambda: mistune.html(source))
        speedup = python_seconds / mojo_seconds
        print(
            f"| {name} | {len(source.encode('utf-8')) / 1e6:.2f} MB "
            f"| {mojo_seconds * 1e3:.2f} ms | {python_seconds * 1e3:.2f} ms "
            f"| {speedup:.2f}x |"
        )
    print()
    print("| short workload | input | mojo-mistune | mistune | speedup |")
    print("| --- | ---: | ---: | ---: | ---: |")
    for name, source, calls in short_documents():
        expected = mistune.html(source)
        actual = mojo_mistune.html(source)
        if actual != expected:
            raise AssertionError(f"benchmark parity failed for {name}")
        mojo_seconds = best_per_call(lambda: mojo_mistune.html(source), calls)
        python_seconds = best_per_call(lambda: mistune.html(source), calls)
        speedup = python_seconds / mojo_seconds
        print(
            f"| {name} | {len(source.encode('utf-8'))} B "
            f"| {mojo_seconds * 1e6:.2f} us | {python_seconds * 1e6:.2f} us "
            f"| {speedup:.2f}x |"
        )


if __name__ == "__main__":
    main()
