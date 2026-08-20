"""Shared, drift-resistant helpers for the Monterey compatibility transforms.

Every structural transform in this pipeline must validate that its anchor
matches exactly once before replacing anything. Source drift must fail loudly
with a labeled error; silent success is not allowed.

The scripts run exactly once per fresh checkout (both the Monterey CI job and
build_monterey_dmg.sh reset the tree first), so re-running a script on an
already-transformed tree is expected to fail with "got 0" instead of
silently skipping.
"""

import re
from pathlib import Path

DEFAULT_FLAGS = re.MULTILINE


def read_source(path: Path) -> str:
    if not path.is_file():
        raise SystemExit(f"error: expected source file not found: {path}")
    return path.read_text(encoding="utf-8")


def write_source(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def _fail(label: str, detail: str) -> None:
    raise SystemExit(f"error: {label}: {detail}")


def replace_once_regex(
    text: str,
    pattern: str,
    replacement: str,
    *,
    label: str,
    flags: int = DEFAULT_FLAGS,
) -> str:
    """Replaces the single occurrence of ``pattern`` with ``replacement``.

    ``replacement`` is inserted literally (no backslash-reference processing),
    so Swift source with ``\\(...)`` interpolation and raw strings survives
    verbatim. Fails unless the pattern matches exactly once.
    """
    matches = list(re.finditer(pattern, text, flags))
    if len(matches) != 1:
        _fail(label, f"expected exactly 1 match, got {len(matches)}")
    updated, count = re.subn(
        pattern,
        lambda _match: replacement,
        text,
        count=1,
        flags=flags,
    )
    if count != 1:
        _fail(label, f"replacement applied {count} times, expected 1")
    return updated


def replace_exact_once(
    text: str,
    old: str,
    new: str,
    *,
    label: str,
    expected: int = 1,
) -> str:
    """Replaces every occurrence of an exact string after counting them.

    Used for small, provably-stable statement blocks where a regex would add
    noise; ``expected`` pins the occurrence count (e.g. the two identical
    WebViewContainer fallbacks).
    """
    count = text.count(old)
    if count != expected:
        _fail(label, f"expected exactly {expected} occurrences, got {count}")
    return text.replace(old, new)


def replace_span_once(
    text: str,
    start_pattern: str,
    end_pattern: str,
    replacement: str,
    *,
    label: str,
    flags: int = DEFAULT_FLAGS,
) -> str:
    """Replaces the region from a unique start anchor to the next end anchor.

    The start anchor must occur exactly once in the whole file (function and
    type signatures are unique by construction). The end anchor must also be
    unique after the start (the next sibling declaration). The span
    ``[start.begin, end.begin)`` is replaced by ``replacement`` verbatim.
    """
    starts = list(re.finditer(start_pattern, text, flags))
    if len(starts) != 1:
        _fail(label, f"start anchor matched {len(starts)} times, expected exactly 1")
    start = starts[0]
    end_matches = list(re.finditer(end_pattern, text[start.end():], flags))
    if not end_matches:
        _fail(label, "end anchor not found after start anchor")
    if len(end_matches) != 1:
        _fail(
            label,
            f"end anchor matched {len(end_matches)} times after start, expected exactly 1",
        )
    end = end_matches[0]
    end_absolute = start.end() + end.start()
    if end_absolute <= start.start():
        _fail(label, "end anchor resolved before start anchor")
    return text[:start.start()] + replacement + text[end_absolute:]


def require_present(text: str, needle: str, *, label: str) -> None:
    if needle not in text:
        _fail(label, f"required content missing: {needle!r}")


def require_absent(text: str, needle: str, *, label: str) -> None:
    if needle in text:
        _fail(label, f"forbidden content present: {needle!r}")


def span_of(
    text: str,
    start_pattern: str,
    end_pattern: str,
    *,
    label: str,
    flags: int = DEFAULT_FLAGS,
) -> str:
    """Returns the text between two anchors without modifying anything."""
    starts = list(re.finditer(start_pattern, text, flags))
    if len(starts) != 1:
        _fail(label, f"start anchor matched {len(starts)} times, expected exactly 1")
    start = starts[0]
    end_matches = list(re.finditer(end_pattern, text[start.end():], flags))
    if not end_matches:
        _fail(label, "end anchor not found after start anchor")
    if len(end_matches) != 1:
        _fail(
            label,
            f"end anchor matched {len(end_matches)} times after start, expected exactly 1",
        )
    end = end_matches[0]
    return text[start.start():start.end() + end.start()]
