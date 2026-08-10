from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one match, found {count}: {old[:120]!r}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


# 1. The Gear uses cached CALayer colors, so make it refresh immediately when
# the application appearance changes just like Tab / Add / Pin controls.
replace_once(
    "FloatTabs/UI/ExternalTabRail.swift",
    """    override func mouseUp(with event: NSEvent) {\n        onActivate?()\n    }\n\n    private func updateAppearance() {\n        let fraction: CGFloat = isHovered ? 0.10 : 0.02\n""",
    """    override func mouseUp(with event: NSEvent) {\n        onActivate?()\n    }\n\n    override func viewDidChangeEffectiveAppearance() {\n        super.viewDidChangeEffectiveAppearance()\n        updateAppearance()\n    }\n\n    private func updateAppearance() {\n        let fraction: CGFloat = isHovered ? 0.10 : 0.02\n""",
)

# 2. Do not promise WebKit content is completely isolated from NSApp appearance.
# FloatTabs never injects page CSS, but sites may legitimately react to the
# effective appearance through prefers-color-scheme/WebKit behavior.
replace_once(
    "FloatTabs/UI/GlobalSettingsController.swift",
    """        let root = NSView()\n        root.translatesAutoresizingMaskIntoConstraints = false\n\n        let titleLabel = Self.titleLabel(\"Interface Appearance\")\n        let detail = Self.detailLabel(\n            \"Controls FloatTabs chrome only. Website content is not restyled or injected.\"\n        )\n""",
    """        let root = NSView()\n\n        let titleLabel = Self.titleLabel(\"Interface Appearance\")\n        let detail = Self.detailLabel(\n            \"Changes FloatTabs' native appearance. FloatTabs injects no page CSS; websites may still respond to WebKit's effective light/dark appearance.\"\n        )\n""",
)

# 3. Stage 6D contract must describe the implementation truthfully.
replace_once(
    "docs/product/FloatTabs_Stage_6D_Global_Settings.md",
    "Status: implementation plan for stacked Draft PR.\n",
    "Status: implemented and automated-validated; awaiting Real-Mac acceptance.\n",
)
replace_once(
    "docs/product/FloatTabs_Stage_6D_Global_Settings.md",
    """- applied immediately to FloatTabs-owned AppKit windows;\n- restored on next launch;\n- does not inject CSS or change website/WKWebView content appearance;\n- does not change frozen shell geometry.\n""",
    """- applied immediately as FloatTabs' application appearance and restored on next launch;\n- FloatTabs does not inject page CSS for this preference;\n- a website may still react to WebKit/macOS effective appearance such as `prefers-color-scheme`;\n- does not change frozen shell geometry.\n""",
)
replace_once(
    "docs/product/FloatTabs_Stage_6D_Global_Settings.md",
    "5. Appearance System/Light/Dark changes FloatTabs chrome immediately and persists after relaunch;\n",
    "5. Appearance System/Light/Dark updates FloatTabs native chrome immediately, persists after relaunch, and does not inject page CSS; sites may follow WebKit effective appearance;\n",
)

# 4. Product source of truth still contained pre-6D statements after the first
# implementation pass. Align the Gear entry, file layout, and Warm wording.
replace_once(
    "docs/product/FloatTabs_Product_Development_Spec_v0.5.md",
    "Global Settings 是软件级设置，不属于 `⚙`。\n\nEntry：\n\n```text\nMenu Bar → Settings…\n⌘,\n```\n",
    "Global Settings 是软件级设置，`⚙` 是其固定入口之一。\n\nEntry：\n\n```text\n⚙\nMenu Bar → Settings…\n⌘,\n```\n",
)
replace_once(
    "docs/product/FloatTabs_Product_Development_Spec_v0.5.md",
    "- Appearance: System / Light / Dark，UserDefaults 持久化并即时应用于 FloatTabs chrome；\n",
    "- Appearance: System / Light / Dark，UserDefaults 持久化并即时应用于 FloatTabs native chrome；FloatTabs 不注入页面 CSS，但网页可按 WebKit/macOS effective appearance 响应 `prefers-color-scheme`；\n",
)
replace_once(
    "docs/product/FloatTabs_Product_Development_Spec_v0.5.md",
    "│   └── PreferencesStore.swift\n",
    "│   ├── ProfileRepository.swift\n│   └── AppPreferencesStore.swift\n",
)
# The previous layout already has ProfileRepository immediately before the line
# above. Remove the accidental duplicate produced by replacing the legacy line.
replace_once(
    "docs/product/FloatTabs_Product_Development_Spec_v0.5.md",
    "│   ├── ProfileRepository.swift\n│   ├── ProfileRepository.swift\n│   └── AppPreferencesStore.swift\n",
    "│   ├── ProfileRepository.swift\n│   └── AppPreferencesStore.swift\n",
)
replace_once(
    "docs/product/FloatTabs_Product_Development_Spec_v0.5.md",
    "│   ├── CurrentWebAppControls.swift\n",
    "│   ├── GlobalSettingsController.swift\n",
)
replace_once(
    "docs/product/FloatTabs_Product_Development_Spec_v0.5.md",
    "│   └── SettingsView.swift\n",
    "│   └── EmptyWebAppView.swift\n",
)
# Avoid duplicating EmptyWebAppView if the recommended layout already lists it
# in a future branch; current source-of-truth does not, but keep this defensive.
p = Path("docs/product/FloatTabs_Product_Development_Spec_v0.5.md")
text = p.read_text(encoding="utf-8")
text = text.replace("│   ├── EmptyWebAppView.swift\n│   └── EmptyWebAppView.swift\n", "│   └── EmptyWebAppView.swift\n")
p.write_text(text, encoding="utf-8")
replace_once(
    "docs/product/FloatTabs_Product_Development_Spec_v0.5.md",
    "- warm Slot switch 不 network reload；\n",
    "- resident Warm Slot switch 不 network reload；已 eviction 的 Warm 按 Current URL / persistent website data 重建；\n",
)

# 5. Architecture audit: remove duplicated Global Settings node and update the
# stale permanent-Warm description to the accepted Stage 5E residency model.
replace_once(
    "docs/architecture/FloatTabs_Technical_Architecture_v1.2.md",
    """└── UI\n    ├── Frozen External Shell\n    ├── Global Settings\n    ├── Add/Edit Web App\n    ├── Quick URL\n    └── Global Settings\n""",
    """└── UI\n    ├── Frozen External Shell\n    ├── Global Settings\n    ├── Add/Edit Web App\n    └── Quick URL\n""",
)
replace_once(
    "docs/architecture/FloatTabs_Technical_Architecture_v1.2.md",
    "│   ├── one WKWebView per warm/hot slot\n",
    "│   ├── live WKWebView residency for Active / Hot / cached Warm / grace-protected Cold\n",
)
