#!/usr/bin/env python3
"""Stage 3: Monterey runtime safe mode.

Fullscreen polling never starts on macOS 12, and element fullscreen is only
enabled on macOS 13+ while FloatTabs' fullscreen ownership observation is
disabled for this package.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from monterey_transform_lib import (
    read_source,
    replace_once_regex,
    require_absent,
    require_present,
    write_source,
)

ROOT = Path(__file__).resolve().parents[2]

fullscreen = ROOT / "FloatTabs/Panel/FullscreenSourceHost.swift"
text = read_source(fullscreen)
text = replace_once_regex(
    text,
    r"        if #available\(macOS 13\.0, \*\) \{\s*"
    r"observeModernFullscreenState\(of: webView\)\s*"
    r"\} else \{\s*"
    r"startLegacyFullscreenPolling\(of: webView\)\s*"
    r"\}",
    """        if #available(macOS 13.0, *) {
            observeModernFullscreenState(of: webView)
        } else {
            // Monterey runtime safe mode: do not start the compatibility polling
            // loop during ordinary WebView creation. The polling implementation
            // is compile-valid but cannot be runtime-validated on GitHub's newer
            // macOS runner. Element fullscreen is disabled for the Monterey
            // compatibility package below, so there is no state to infer here.
            legacyFullscreenPollGeneration &+= 1
        }""",
    label="FullscreenSourceHost safe-mode polling guard",
)
write_source(fullscreen, text)

web_factory = ROOT / "FloatTabs/Web/WebViewFactory.swift"
text = read_source(web_factory)
require_absent(
    text,
    'value(forKey: "userAgent")',
    label="Monterey WebViewFactory private KVC survived preparation",
)

# The compatibility source preparation initially guards this API at macOS 12.3.
# Do not leave element fullscreen enabled on Monterey while FloatTabs' fullscreen
# ownership observation is intentionally disabled. Keep the normal feature on
# macOS 13+ only.
text = replace_once_regex(
    text,
    r"        if #available\(macOS 12\.3, \*\) \{\s*"
    r"configuration\.preferences\.isElementFullscreenEnabled = true\s*"
    r"\}",
    """        if #available(macOS 13.0, *) {
            configuration.preferences.isElementFullscreenEnabled = true
        }
""",
    label="WebViewFactory element-fullscreen macOS 13 raise",
)
write_source(web_factory, text)

prepared_fullscreen = read_source(fullscreen)
require_absent(
    prepared_fullscreen,
    "        } else {\n            startLegacyFullscreenPolling(of: webView)\n        }\n",
    label="Monterey runtime still starts legacy fullscreen polling",
)

prepared_web = read_source(web_factory)
require_absent(
    prepared_web,
    "if #available(macOS 12.3, *) {\n            configuration.preferences.isElementFullscreenEnabled = true",
    label="element fullscreen is still enabled on macOS 12",
)
require_present(
    prepared_web,
    "if #available(macOS 13.0, *) {\n            configuration.preferences.isElementFullscreenEnabled = true",
    label="macOS 13+ element-fullscreen behavior was not preserved",
)

print("Applied Monterey runtime safe mode: fullscreen disabled on macOS 12.")
