"""Covered helpers from ``mistune.util``."""

from __future__ import annotations

import html as _html
from urllib.parse import quote


def escape(s: str, quote: bool = True) -> str:
    return _html.escape(s, quote=quote).replace("&#x27;", "'")


def safe_entity(s: str) -> str:
    return _html.escape(_html.unescape(s), quote=True).replace("&#x27;", "'")


def escape_url(link: str) -> str:
    return quote(_html.unescape(link), safe=":/?#@!$&()*+,;=%")


def unikey(s: str) -> str:
    return " ".join(s.split()).strip().lower().upper()
