from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"anchor not found: {path}: {old[:100]!r}")
    p.write_text(text.replace(old, new, 1))


# NSView.hitTest receives the point in the receiver's superview coordinate
# system. Keep frame-based geometry; the resize usability fix is the larger
# 32pt target plus activeAlways tracking, not a coordinate-space rewrite.
replace_once(
    "FloatTabs/Web/WebViewContainer.swift",
    """    override func hitTest(_ point: NSPoint) -> NSView? {\n        bounds.contains(point) ? self : nil\n    }\n\n    override func updateTrackingAreas() {\n""",
    """    override func hitTest(_ point: NSPoint) -> NSView? {\n        frame.contains(point) ? self : nil\n    }\n\n    override func updateTrackingAreas() {\n""",
)

rail = Path("FloatTabs/UI/ExternalTabRail.swift")
text = rail.read_text()
marker = "final class ExternalWebAppTabView: NSView {"
start = text.index(marker)
end = text.index("@MainActor\nfinal class AddWebAppControl", start)
section = text[start:end]
old = "bounds.contains(point) ? self : nil"
if old not in section:
    raise SystemExit("tab hit-test anchor missing")
section = section.replace(old, "frame.contains(point) ? self : nil", 1)
rail.write_text(text[:start] + section + text[end:])

replace_once(
    "FloatTabsTests/ExternalShellTests.swift",
    """        let handle = PanelResizeHandleView(frame: NSRect(x: 100, y: 100, width: 32, height: 32))\n        XCTAssertTrue(handle.acceptsFirstMouse(for: nil))\n        XCTAssertTrue(handle.hitTest(NSPoint(x: 2, y: 2)) === handle)\n        XCTAssertNil(handle.hitTest(NSPoint(x: 40, y: 40)))\n""",
    """        let handle = PanelResizeHandleView(frame: NSRect(x: 100, y: 100, width: 32, height: 32))\n        XCTAssertTrue(handle.acceptsFirstMouse(for: nil))\n        XCTAssertTrue(handle.hitTest(NSPoint(x: 102, y: 102)) === handle)\n        XCTAssertNil(handle.hitTest(NSPoint(x: 140, y: 140)))\n""",
)

print("Stage 5D AppKit hit-test semantics corrected")
