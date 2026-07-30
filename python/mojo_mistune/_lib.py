"""ctypes bridge for the compiled Mojo renderer."""

from __future__ import annotations

import ctypes
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LIB_PATH = Path(os.environ.get("MOJO_MISTUNE_LIB", ROOT / "dist/libmojo-mistune.so"))

I = ctypes.c_int64
_library: ctypes.CDLL | None = None


class BuildError(RuntimeError):
    pass


def build(force: bool = False) -> Path:
    source = ROOT / "src/mistune.mojo"
    if not force and LIB_PATH.exists() and (
        not source.exists() or LIB_PATH.stat().st_mtime >= source.stat().st_mtime
    ):
        return LIB_PATH
    script = ROOT / "build/build.sh"
    if not script.exists():
        raise BuildError(f"shared library not found at {LIB_PATH}")
    process = subprocess.run(
        ["bash", str(script)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        timeout=1800,
    )
    if process.returncode or not LIB_PATH.exists():
        raise BuildError((process.stderr or process.stdout).strip())
    return LIB_PATH


def lib() -> ctypes.CDLL:
    global _library
    if _library is None:
        _library = ctypes.CDLL(str(build()))
        fn = _library.mmt_render_html
        fn.argtypes = [I, I, I, I, I, I, I]
        fn.restype = I
    return _library


def render_html(
    text: str,
    *,
    escape: bool,
    hard_wrap: bool,
    strikethrough: bool,
    table: bool,
) -> str:
    if not isinstance(text, str):
        raise TypeError("markdown input must be str")
    if not text:
        return ""
    encoded = text.encode("utf-8")
    source = ctypes.create_string_buffer(encoded, max(1, len(encoded) + 1))
    capacity = max(256, len(encoded) * 3 + 128)
    while True:
        destination = ctypes.create_string_buffer(capacity)
        needed = lib().mmt_render_html(
            ctypes.addressof(source),
            len(encoded),
            ctypes.addressof(destination),
            capacity,
            int(escape),
            int(hard_wrap),
            int(strikethrough) | (int(table) << 1),
        )
        # Negative values are reserved for native argument/runtime failures.
        # Never interpret them as a slice bound: that would hide the failure
        # and return truncated output.
        if needed < 0:
            raise RuntimeError(f"native renderer failed with status {needed}")
        if needed <= capacity:
            return destination.raw[:needed].decode("utf-8")
        capacity = needed
