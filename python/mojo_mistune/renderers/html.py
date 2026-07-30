"""HTML renderer configuration compatible with Mistune's core constructor."""

from __future__ import annotations

from collections.abc import Iterable


class HTMLRenderer:
    NAME = "html"
    SAFE_PROTOCOLS = (
        "http:",
        "https:",
        "mailto:",
        "tel:",
        "ftp:",
        "ftps:",
        "irc:",
        "ircs:",
    )

    def __init__(
        self,
        escape: bool = True,
        allow_harmful_protocols: bool | Iterable[str] | None = None,
    ) -> None:
        if allow_harmful_protocols not in (None, False):
            raise NotImplementedError(
                "custom harmful-protocol policies are outside the covered subset"
            )
        self._escape = bool(escape)
        self._allow_harmful_protocols = allow_harmful_protocols
