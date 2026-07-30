"""Mistune-compatible reusable Markdown callable."""

from __future__ import annotations

from collections.abc import Iterable
from typing import Any

from ._lib import render_html
from .renderers.html import HTMLRenderer

_SUPPORTED_PLUGINS = {"strikethrough", "table", "speedup"}


class Markdown:
    def __init__(
        self,
        renderer: HTMLRenderer | str | None = None,
        block: Any = None,
        inline: Any = None,
        plugins: Iterable[Any] | None = None,
        *,
        hard_wrap: bool = False,
    ) -> None:
        if block is not None or inline is not None:
            raise NotImplementedError("custom parser objects are outside the covered subset")
        if renderer == "html":
            renderer = HTMLRenderer()
        if renderer is None:
            raise NotImplementedError("the AST renderer is outside the covered subset")
        if not isinstance(renderer, HTMLRenderer):
            raise TypeError("renderer must be HTMLRenderer")
        names = tuple(plugins or ())
        unsupported = [name for name in names if name not in _SUPPORTED_PLUGINS]
        if unsupported:
            raise NotImplementedError(
                f"unsupported Mistune plugins: {', '.join(map(str, unsupported))}"
            )
        self.renderer = renderer
        self.hard_wrap = bool(hard_wrap)
        self.plugins = names

    def __call__(self, s: str) -> str:
        return render_html(
            s,
            escape=self.renderer._escape,
            hard_wrap=self.hard_wrap,
            strikethrough="strikethrough" in self.plugins,
            table="table" in self.plugins,
        )

    def parse(self, s: str, state: Any = None) -> tuple[str, Any]:
        return self(s), state
