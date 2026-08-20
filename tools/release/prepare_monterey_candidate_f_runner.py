#!/usr/bin/env python3
"""Run Candidate F against the Stage-2 Monterey container shape.

Stage 2 has already removed the runtime preferredContentMode read and leaves a
conservative `FloatTabsWebView?.websiteMode ?? .desktop` fallback. Candidate F
replaces that fallback with explicit AppKit WebsiteMode metadata. This wrapper
narrows the two replacement anchors to their owning classes without modifying
Candidate E's accepted Stage-6 generator.
"""

import re
import runpy
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))

import monterey_transform_lib as lib

_original_replace_once_regex = lib.replace_once_regex

_STAGE2_MODE_PATTERN = (
    r"        let mode = \(webView as\? FloatTabsWebView\)\?\.websiteMode \?\? \.desktop\n"
    r"        // Monterey compatibility: macOS fallback stays desktop without reading\n"
    r"        // WKWebpagePreferences\.preferredContentMode\.\n"
    r"        let logicalSize = WebsiteLayoutViewport\.logicalSize\(\n"
    r"            forVisibleSize: visibleSize,\n"
    r"            websiteMode: mode\n"
    r"        \)"
)


def _replace_inside_class(
    text: str,
    *,
    class_start: str,
    class_end: str | None,
    replacement: str,
    label: str,
) -> str:
    start_match = re.search(class_start, text, re.MULTILINE)
    if start_match is None:
        raise SystemExit(f"error: {label}: class start not found")
    start = start_match.start()
    if class_end is None:
        end = len(text)
    else:
        end_match = re.search(class_end, text[start_match.end():], re.MULTILINE)
        if end_match is None:
            raise SystemExit(f"error: {label}: class end not found")
        end = start_match.end() + end_match.start()
    section = text[start:end]
    section = _original_replace_once_regex(
        section,
        _STAGE2_MODE_PATTERN,
        replacement,
        label=label,
    )
    return text[:start] + section + text[end:]


def candidate_f_replace_once_regex(
    text: str,
    pattern: str,
    replacement: str,
    *,
    label: str,
    flags: int = lib.DEFAULT_FLAGS,
) -> str:
    if label == "Candidate F WebSlotHost no WebKit mode inference":
        return _replace_inside_class(
            text,
            class_start=r"^final class WebSlotHostView: NSView \{",
            class_end=r"^/// Owns the visible FloatTabs web surface",
            replacement=replacement,
            label=label,
        )
    if label == "Candidate F WebPanel no WebKit mode inference":
        return _replace_inside_class(
            text,
            class_start=r"^final class WebPanelContainerView: NSView \{",
            class_end=None,
            replacement=replacement,
            label=label,
        )
    return _original_replace_once_regex(
        text,
        pattern,
        replacement,
        label=label,
        flags=flags,
    )


lib.replace_once_regex = candidate_f_replace_once_regex
runpy.run_path(str(HERE / "prepare_monterey_candidate_f.py"), run_name="__main__")
