"""Mistune's core HTML API backed by a Mojo Markdown renderer."""

from __future__ import annotations

from collections.abc import Iterable
from typing import Any

from .markdown import Markdown
from .renderers.html import HTMLRenderer
from .util import escape, escape_url, safe_entity, unikey


def create_markdown(
    escape: bool = True,
    hard_wrap: bool = False,
    renderer: str | HTMLRenderer | None = "html",
    plugins: Iterable[Any] | None = None,
) -> Markdown:
    if renderer == "ast" or renderer is None:
        raise NotImplementedError("the AST renderer is outside the covered subset")
    if renderer == "html":
        renderer = HTMLRenderer(escape=escape)
    return Markdown(
        renderer=renderer,
        plugins=plugins,
        hard_wrap=hard_wrap,
    )


_parser_cache: dict[tuple[bool, object, object], Markdown] = {}


def markdown(
    text: str,
    escape: bool = True,
    renderer: str | HTMLRenderer | None = "html",
    plugins: Iterable[Any] | None = None,
) -> str:
    plugin_names = tuple(plugins) if plugins is not None else ()
    cache_renderer: object = renderer if isinstance(renderer, str) else id(renderer)
    key = (escape, cache_renderer, plugin_names)
    parser = _parser_cache.get(key)
    if parser is None:
        parser = create_markdown(
            escape=escape,
            renderer=renderer,
            plugins=plugin_names,
        )
        _parser_cache[key] = parser
    return parser(text)


html = create_markdown(escape=False, plugins=["strikethrough", "table"])

__all__ = [
    "Markdown",
    "HTMLRenderer",
    "escape",
    "escape_url",
    "safe_entity",
    "unikey",
    "html",
    "create_markdown",
    "markdown",
]
__version__ = "0.1.0"
