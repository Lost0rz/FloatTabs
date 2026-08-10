from pathlib import Path

path = Path("FloatTabsTests/WebViewFactoryTests.swift")
text = path.read_text()
old = "        let location = NSPoint(x: webView.frame.midX, y: webView.frame.midY)"
new = "        let location = webView.convert(\n            NSPoint(x: webView.bounds.midX, y: webView.bounds.midY),\n            to: nil\n        )"
count = text.count(old)
if count != 1:
    raise SystemExit(f"click helper: expected exactly one match, found {count}")
path.write_text(text.replace(old, new, 1))
