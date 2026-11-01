#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

def read(path):
    return (ROOT / path).read_text()

def write(path, text):
    (ROOT / path).write_text(text)

def replace_once(path, old, new):
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, got {count}: {old[:100]!r}")
    write(path, text.replace(old, new, 1))

def regex_once(path, pattern, replacement):
    text = read(path)
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S | re.M)
    if count != 1:
        raise SystemExit(f"{path}: expected one regex match, got {count}: {pattern[:120]!r}")
    write(path, updated)

# Panel: legacy external residency adapter must no longer invoke retired Cold
# cache coupling or project Hot/Warm/Cold HUD copy.
p = "FloatTabs/Panel/PanelController.swift"
replace_once(
    p,
    '''    @discardableResult
    func setResidency(_ policy: SlotResidencyPolicy, for id: UUID) -> Bool {
        guard tabStore.updateResourcePolicy(id: id, residencyPolicy: policy),
              let updatedProfile = tabStore.profiles.first(where: { $0.id == id }) else {
            return false
        }

        handleRuntimeReleased(updatedProfile)

        if tabStore.activeTabID == id {
            synchronizeTransientUIHost()
            statusHUDView.show(residency: policy)
        }
        return true
    }
''',
    '''    @discardableResult
    func setResidency(_ policy: SlotResidencyPolicy, for id: UUID) -> Bool {
        // Legacy IPC/test adapter only. The canonical product state is
        // Automatic / Keep Loaded and no current UI projects legacy labels.
        guard tabStore.updateResourcePolicy(id: id, residencyPolicy: policy) else {
            return false
        }
        if tabStore.activeTabID == id {
            synchronizeTransientUIHost()
        }
        return true
    }
'''
)

# Lifecycle: no second 120s production retention boundary; once hidden, the
# canonical Automatic 30s grace is authoritative. Remove Hot-host cleanup call
# because the container no longer owns residency.
p = "FloatTabs/Web/SlotLifecycleCoordinator.swift"
replace_once(
    p,
    "    nonisolated static let defaultHiddenActiveGraceDelay: TimeInterval = 120\n",
    "    nonisolated static let defaultHiddenActiveGraceDelay: TimeInterval = 0\n"
)
replace_once(
    p,
    '''        // Phase 7 has no hidden Hot host. Remove any compatibility host that
        // could have survived an in-process preference transition.
        container.retainHotSlots([])

''',
    ""
)

# Container: remove the Hot-specific host architecture entirely. Inactive live
# Runtime may remain in WebViewPool, but presentation owns only the selected
# transient attachment.
p = "FloatTabs/Web/WebViewContainer.swift"
regex_once(
    p,
    r'''\nfinal class WebSlotHostView: NSView \{.*?\n\}\n\n/// Phase 6 lightweight native restoring surface\.''',
    '''\n/// Phase 6 lightweight native restoring surface.'''
)
replace_once(
    p,
    '''/// Owns the visible FloatTabs web surface. Warm/Cold use the accepted Stage 4
/// transient host. Hot Slots instead receive one independent host each, so an
/// inactive Hot WebView can stay attached to the FloatTabs window without being
/// resized when another Slot has a different Window Size preset.
''',
    '''/// Owns the visible FloatTabs web surface. Runtime residency is owned by
/// `SlotLifecycleCoordinator` / `WebViewPool`; this view only presents the
/// selected Runtime and detaches it when presentation changes.
'''
)
replace_once(p, "    private var hotHostViews: [UUID: WebSlotHostView] = [:]\n", "")
regex_once(
    p,
    r'''\n    func retainHotSlots\(_ validHotSlotIDs: Set<UUID>\) \{.*?\n    \}\n''',
    "\n"
)
replace_once(
    p,
    '''        if let host = hotHostViews.removeValue(forKey: slotID) {
            host.detachOwnedWebView()
            host.removeFromSuperview()
        }
''',
    ""
)
replace_once(
    p,
    '''    private func prepareForNonWebPresentation() {
        // Presentation bookkeeping must be cleared even when the current
        // placeholder is already the last transient content view. Hot
        // presentation is independent from currentContentView, so cleanup must
        // explicitly release the active WebView and hide every Hot host.
        detachHostedTransientIfOwned()
        activeWebView = nil
        activeSlotID = nil
        websiteLayoutScale = 1
        logicalHostView.bounds = NSRect(origin: .zero, size: logicalHostView.frame.size)
        for host in hotHostViews.values {
            host.autoresizingMask = []
            host.isHidden = true
        }
    }
''',
    '''    private func prepareForNonWebPresentation() {
        detachHostedTransientIfOwned()
        activeWebView = nil
        activeSlotID = nil
        websiteLayoutScale = 1
        logicalHostView.bounds = NSRect(origin: .zero, size: logicalHostView.frame.size)
    }
'''
)
regex_once(
    p,
    r'''    override func layout\(\) \{\n        super\.layout\(\)\n        if let activeSlotID,.*?\n        layer\?\.shadowPath = CGPath\(''',
    '''    override func layout() {
        super.layout()
        updateWebsiteLayoutIfNeeded()
        layer?.shadowPath = CGPath('''
)
replace_once(
    p,
    '''    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSemanticColors()
        for host in hotHostViews.values {
            host.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }
''',
    '''    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSemanticColors()
    }
'''
)
regex_once(
    p,
    r'''\n    private func showHot\(webView: WKWebView, slotID: UUID\) \{.*?\n    \}\n\n(?=    private func showTransient)''',
    "\n"
)

# Current shortcut catalog/settings must not expose legacy Hot/Warm/Cold modes.
p = "FloatTabs/Hotkeys/AppCommandController.swift"
regex_once(
    p,
    r'''    static let setHotResidency = Self\(.*?    static let setColdResidency = Self\(\n        "setColdResidency",\n        initial: \.init\(\.c, modifiers: \[\.control, \.option\]\)\n    \)\n''',
    ""
)
regex_once(
    p,
    r'''\n    static let residencyBindings: \[AppShortcutBinding\] = \[.*?\n    \]\n''',
    "\n"
)
replace_once(
    p,
    '''        slotBindings
            + navigationBindings
            + viewBindings
            + residencyBindings
            + applicationBindings
''',
    '''        slotBindings
            + navigationBindings
            + viewBindings
            + applicationBindings
'''
)

p = "FloatTabs/UI/GlobalSettingsController.swift"
replace_once(
    p,
    '''        views.append(contentsOf: [spacer(10), sectionTitle("Mode")])
        views.append(contentsOf: AppShortcutCatalog.residencyBindings.map(shortcutRecorderRow(for:)))
''',
    ""
)

# Final static guard: current product paths must contain no Hot host or current
# user shortcut catalog surface for legacy modes.
checks = {
    "FloatTabs/Web/WebViewContainer.swift": ["hotHostViews", "showHot(", "retainHotSlots("],
    "FloatTabs/Hotkeys/AppCommandController.swift": ["residencyBindings", "setHotResidency", "setWarmResidency", "setColdResidency", "Set Hot Mode", "Set Warm Mode", "Set Cold Mode"],
    "FloatTabs/UI/GlobalSettingsController.swift": ["sectionTitle(\"Mode\")", "AppShortcutCatalog.residencyBindings"],
}
for path, tokens in checks.items():
    text = read(path)
    for token in tokens:
        if token in text:
            raise SystemExit(f"{path}: forbidden current legacy token remains: {token}")

print("Phase 7 bounded corrective applied")
