"""Exact behavioral parity checks against Mistune 3.x."""

from __future__ import annotations

import inspect
from types import SimpleNamespace

import mistune
import pytest

import mojo_mistune


BLOCK_CASES = [
    "",
    "# heading\n",
    "### heading ###\n",
    "###### six\n",
    "heading\n=======\n",
    "heading\n-------\n",
    "first paragraph\n\nsecond paragraph\n",
    "a\nsoft line\n",
    "a  \nhard line\n",
    "a\\\nhard line\n",
    "---\n",
    "* * *\n",
    "> quoted\n> paragraph\n",
    "- alpha\n- beta\n",
    "+ alpha\n+ beta\n",
    "1. alpha\n2. beta\n",
    "3. alpha\n4. beta\n",
    "- alpha\n  continuation\n- beta\n",
    "```python\nx < 2 && y > 1\n```\n",
    "~~~ js extra\na & b\n~~~\n",
    "    indented\n    code\n",
]


@pytest.mark.parametrize("source", BLOCK_CASES)
def test_core_block_rendering_matches_upstream(source):
    assert mojo_mistune.html(source) == mistune.html(source)


INLINE_CASES = [
    "plain < text > & \"quoted\"\n",
    "*emphasis* and **strong**\n",
    "_emphasis_ and __strong__\n",
    "***both*** and ___both___\n",
    "**outer *inner* outer**\n",
    "a_b_c and a__b__c\n",
    "\\*literal asterisks\\* and \\[brackets\\]\n",
    "`code <tag> & value`\n",
    "`` code ` with tick ``\n",
    "[text](https://example.test/path)\n",
    "[text](https://example.test \"A & B\")\n",
    "[space](<a b>)\n",
    "![alt](image.png)\n",
    "![alt *markup*](image.png \"title\")\n",
    "<https://example.test/a?q=1&b=2>\n",
    "<person@example.test>\n",
    "[blocked](javascript:alert(1))\n",
    "~~deleted~~\n",
    "Unicode: café, 東京, λ\n",
    "&amp; &copy; &#35; &#x20; &bad;\n",
    "Invalid numeric entities: &#0; &#xD800; &#x110000;\n",
]


@pytest.mark.parametrize("source", INLINE_CASES)
def test_core_inline_rendering_matches_upstream(source):
    assert mojo_mistune.html(source) == mistune.html(source)


TABLE_CASES = [
    "| A | B |\n|---|---|\n| x | y |\n",
    "| A | B |\n|:---|:---:|\n| *x* | **y** |\n",
    "A | B\n---|---:\nx|y\n",
    "| A | B |\n|---|---|\n",
]


@pytest.mark.parametrize("source", TABLE_CASES)
def test_default_table_plugin_matches_upstream(source):
    assert mojo_mistune.html(source) == mistune.html(source)


@pytest.mark.parametrize(
    "source",
    [
        "<b>inline HTML</b>\n",
        "<div>\nraw & unescaped\n</div>\n",
        "<script>alert('x')</script> &\n",
    ],
)
def test_html_singleton_raw_html_matches_upstream(source):
    assert mojo_mistune.html(source) == mistune.html(source)


@pytest.mark.parametrize(
    ("options", "source"),
    [
        ({}, "<b>x</b> & y\n"),
        ({"escape": False}, "<b>x</b> & y\n"),
        ({"hard_wrap": True}, "a\nb\n"),
        ({"plugins": ["strikethrough"]}, "~~x~~\n"),
        ({"plugins": ["table"]}, "a|b\n---|---\nx|y\n"),
    ],
)
def test_create_markdown_options_match_upstream(options, source):
    ours = mojo_mistune.create_markdown(**options)
    theirs = mistune.create_markdown(**options)
    assert ours(source) == theirs(source)


def test_markdown_convenience_function_matches_upstream():
    source = "# title\n\nA **small** [document](https://example.test).\n"
    assert mojo_mistune.markdown(source) == mistune.markdown(source)


def test_reusable_renderer_object_matches_upstream():
    ours = mojo_mistune.Markdown(mojo_mistune.HTMLRenderer(escape=False))
    theirs = mistune.Markdown(mistune.HTMLRenderer(escape=False))
    for source in ("one\n", "two *em*\n", "<b>three</b>\n"):
        assert ours(source) == theirs(source)


@pytest.mark.parametrize("name", ["escape", "escape_url", "safe_entity", "unikey"])
def test_utilities_match_upstream(name):
    value = '  A & <tag> "café"  '
    assert getattr(mojo_mistune, name)(value) == getattr(mistune, name)(value)


def test_public_function_signatures_match_upstream():
    def contract(callable_object):
        return [
            (parameter.name, parameter.kind, parameter.default)
            for parameter in inspect.signature(callable_object).parameters.values()
        ]

    assert contract(mojo_mistune.create_markdown) == contract(mistune.create_markdown)
    assert contract(mojo_mistune.markdown) == contract(mistune.markdown)
    assert contract(mojo_mistune.HTMLRenderer) == contract(mistune.HTMLRenderer)


def test_unsupported_ast_and_plugins_fail_explicitly():
    with pytest.raises(NotImplementedError, match="AST"):
        mojo_mistune.create_markdown(renderer="ast")
    with pytest.raises(NotImplementedError, match="footnotes"):
        mojo_mistune.create_markdown(plugins=["footnotes"])


def test_non_string_input_is_rejected():
    with pytest.raises(TypeError, match="must be str"):
        mojo_mistune.html(b"bytes")


def test_empty_input_bypasses_native_boundary(monkeypatch):
    from mojo_mistune import _lib

    def fail():
        raise AssertionError("empty input crossed the native boundary")

    monkeypatch.setattr(_lib, "lib", fail)
    assert mojo_mistune.html("") == ""


def test_native_failure_is_not_returned_as_truncated_output(monkeypatch):
    from mojo_mistune import _lib

    fake = SimpleNamespace(mmt_render_html=lambda *_args: -1)
    monkeypatch.setattr(_lib, "lib", lambda: fake)
    with pytest.raises(RuntimeError, match="status -1"):
        mojo_mistune.html("nonempty")


@pytest.mark.parametrize(
    "arguments",
    [
        (0, -1, 1, 1, 0, 0, 0),
        (0, 1, 1, 1, 0, 0, 0),
        (1, 1, 0, 1, 0, 0, 0),
        (1, 1, 1, 0, 0, 0, 0),
    ],
)
def test_native_boundary_rejects_invalid_lengths_and_pointers(arguments):
    from mojo_mistune import _lib

    assert _lib.lib().mmt_render_html(*arguments) == -1
