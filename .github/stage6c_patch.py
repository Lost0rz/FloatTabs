from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one match, found {count}: {old[:100]!r}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


# App command: add Reload as a first-class local command.
replace_once(
    "FloatTabs/Hotkeys/AppCommandController.swift",
    "    case returnHome\n    case togglePin\n",
    "    case returnHome\n    case reload\n    case togglePin\n",
)
replace_once(
    "FloatTabs/Hotkeys/AppCommandController.swift",
    "            case \"l\":\n                return .quickURL\n            case \"-\":\n",
    "            case \"l\":\n                return .quickURL\n            case \"r\":\n                return .reload\n            case \"-\":\n",
)

# WebViewPool owns page-runtime actions, including reload.
replace_once(
    "FloatTabs/Web/WebViewPool.swift",
    "    func navigate(slotID: UUID, to url: URL) {\n        guard WebAppURL.isSafe(url), let webView = webViews[slotID] else { return }\n        lastKnownURLs[slotID] = url\n        load(webView, URLRequest(url: url))\n    }\n\n    func remove(slotID: UUID) {\n",
    "    func navigate(slotID: UUID, to url: URL) {\n        guard WebAppURL.isSafe(url), let webView = webViews[slotID] else { return }\n        lastKnownURLs[slotID] = url\n        load(webView, URLRequest(url: url))\n    }\n\n    @discardableResult\n    func reload(slotID: UUID) -> Bool {\n        guard let webView = webViews[slotID] else { return false }\n        webView.reload()\n        return true\n    }\n\n    func remove(slotID: UUID) {\n",
)

# Panel routes active keyboard Reload and target context-menu Reload through one method.
replace_once(
    "FloatTabs/Panel/PanelController.swift",
    "        case .returnHome:\n            returnActiveSlotHome()\n\n        case .togglePin:\n",
    "        case .returnHome:\n            returnActiveSlotHome()\n\n        case .reload:\n            reloadActiveSlot()\n\n        case .togglePin:\n",
)
replace_once(
    "FloatTabs/Panel/PanelController.swift",
    "        rail.onReturnHome = { [weak self] id in\n            self?.returnSlotHome(id: id)\n        }\n        rail.onAdd = { [weak self] in\n",
    "        rail.onReturnHome = { [weak self] id in\n            self?.returnSlotHome(id: id)\n        }\n        rail.onReload = { [weak self] id in\n            self?.reloadSlot(id: id)\n        }\n        rail.onAdd = { [weak self] in\n",
)
replace_once(
    "FloatTabs/Panel/PanelController.swift",
    "    private func returnActiveSlotHome() {\n        guard let id = tabStore.activeTabID else { return }\n        returnSlotHome(id: id)\n    }\n\n    private func returnSlotHome(id: UUID) {\n",
    "    private func returnActiveSlotHome() {\n        guard let id = tabStore.activeTabID else { return }\n        returnSlotHome(id: id)\n    }\n\n    private func reloadActiveSlot() {\n        guard let id = tabStore.activeTabID else { return }\n        reloadSlot(id: id)\n    }\n\n    private func reloadSlot(id: UUID) {\n        guard webViewPool.reload(slotID: id) else { return }\n        if tabStore.activeTabID == id {\n            focusActiveWebViewIfAvailable()\n        }\n    }\n\n    private func returnSlotHome(id: UUID) {\n",
)

# Context menu: keep page controls, add reload, native shortcuts, zoom commands.
replace_once(
    "FloatTabs/UI/ExternalTabRail.swift",
    "    var onReturnHome: ((UUID) -> Void)?\n    var onAdd: (() -> Void)?\n",
    "    var onReturnHome: ((UUID) -> Void)?\n    var onReload: ((UUID) -> Void)?\n    var onAdd: (() -> Void)?\n",
)
replace_once(
    "FloatTabs/UI/ExternalTabRail.swift",
    "        view.onReturnHome = { [weak self] slotID in self?.onReturnHome?(slotID) }\n        view.onEdit = { [weak self] slotID in self?.onEdit?(slotID) }\n",
    "        view.onReturnHome = { [weak self] slotID in self?.onReturnHome?(slotID) }\n        view.onReload = { [weak self] slotID in self?.onReload?(slotID) }\n        view.onEdit = { [weak self] slotID in self?.onEdit?(slotID) }\n",
)
replace_once(
    "FloatTabs/UI/ExternalTabRail.swift",
    "    var onReturnHome: ((UUID) -> Void)?\n    var onEdit: ((UUID) -> Void)?\n",
    "    var onReturnHome: ((UUID) -> Void)?\n    var onReload: ((UUID) -> Void)?\n    var onEdit: ((UUID) -> Void)?\n",
)
replace_once(
    "FloatTabs/UI/ExternalTabRail.swift",
    "        home.target = self\n        menu.addItem(home)\n        menu.addItem(.separator())\n\n        let websiteMode = NSMenuItem(title: \"Website Mode\", action: nil, keyEquivalent: \"\")\n",
    "        home.target = self\n        menu.addItem(home)\n\n        let reload = NSMenuItem(\n            title: \"Reload\",\n            action: #selector(reloadFromMenu(_:)),\n            keyEquivalent: \"r\"\n        )\n        reload.keyEquivalentModifierMask = [.command]\n        reload.target = self\n        reload.isEnabled = isResident\n        menu.addItem(reload)\n        menu.addItem(.separator())\n\n        let websiteMode = NSMenuItem(title: \"Website Mode\", action: nil, keyEquivalent: \"\")\n",
)
replace_once(
    "FloatTabs/UI/ExternalTabRail.swift",
    "        let zoom = NSMenuItem(title: \"Zoom\", action: nil, keyEquivalent: \"\")\n        let zoomMenu = NSMenu(title: \"Zoom\")\n        for value in ZoomSteps.values {\n",
    "        let zoom = NSMenuItem(title: \"Zoom\", action: nil, keyEquivalent: \"\")\n        let zoomMenu = NSMenu(title: \"Zoom\")\n\n        let zoomIn = NSMenuItem(\n            title: \"Zoom In\",\n            action: #selector(zoomInFromMenu(_:)),\n            keyEquivalent: \"+\"\n        )\n        zoomIn.keyEquivalentModifierMask = [.command]\n        zoomIn.target = self\n        zoomMenu.addItem(zoomIn)\n\n        let zoomOut = NSMenuItem(\n            title: \"Zoom Out\",\n            action: #selector(zoomOutFromMenu(_:)),\n            keyEquivalent: \"-\"\n        )\n        zoomOut.keyEquivalentModifierMask = [.command]\n        zoomOut.target = self\n        zoomMenu.addItem(zoomOut)\n\n        let resetZoom = NSMenuItem(\n            title: \"Reset Zoom\",\n            action: #selector(resetZoomFromMenu(_:)),\n            keyEquivalent: \"0\"\n        )\n        resetZoom.keyEquivalentModifierMask = [.command]\n        resetZoom.target = self\n        zoomMenu.addItem(resetZoom)\n        zoomMenu.addItem(.separator())\n\n        for value in ZoomSteps.values {\n",
)
replace_once(
    "FloatTabs/UI/ExternalTabRail.swift",
    "    @objc private func returnHomeFromMenu(_ sender: NSMenuItem) { onReturnHome?(slotID) }\n\n    @objc private func setWebsiteModeFromMenu(_ sender: NSMenuItem) {\n",
    "    @objc private func returnHomeFromMenu(_ sender: NSMenuItem) { onReturnHome?(slotID) }\n    @objc private func reloadFromMenu(_ sender: NSMenuItem) { onReload?(slotID) }\n\n    @objc private func setWebsiteModeFromMenu(_ sender: NSMenuItem) {\n",
)
replace_once(
    "FloatTabs/UI/ExternalTabRail.swift",
    "    @objc private func setZoomFromMenu(_ sender: NSMenuItem) {\n        guard let number = sender.representedObject as? NSNumber else { return }\n        onSetZoom?(slotID, CGFloat(number.doubleValue))\n    }\n\n    @objc private func setResidencyFromMenu(_ sender: NSMenuItem) {\n",
    "    @objc private func zoomInFromMenu(_ sender: NSMenuItem) {\n        onSetZoom?(slotID, ZoomSteps.nextLarger(after: renderingProfile.zoom))\n    }\n\n    @objc private func zoomOutFromMenu(_ sender: NSMenuItem) {\n        onSetZoom?(slotID, ZoomSteps.nextSmaller(before: renderingProfile.zoom))\n    }\n\n    @objc private func resetZoomFromMenu(_ sender: NSMenuItem) {\n        onSetZoom?(slotID, 1.0)\n    }\n\n    @objc private func setZoomFromMenu(_ sender: NSMenuItem) {\n        guard let number = sender.representedObject as? NSNumber else { return }\n        onSetZoom?(slotID, CGFloat(number.doubleValue))\n    }\n\n    @objc private func setResidencyFromMenu(_ sender: NSMenuItem) {\n",
)

# Regression tests.
replace_once(
    "FloatTabsTests/AppCommandControllerTests.swift",
    "        XCTAssertEqual(\n            AppCommandController.command(characters: \"l\", keyCode: 37, modifiers: [.command]),\n            .quickURL\n        )\n",
    "        XCTAssertEqual(\n            AppCommandController.command(characters: \"l\", keyCode: 37, modifiers: [.command]),\n            .quickURL\n        )\n        XCTAssertEqual(\n            AppCommandController.command(characters: \"r\", keyCode: 15, modifiers: [.command]),\n            .reload\n        )\n",
)
replace_once(
    "FloatTabsTests/ExternalShellTests.swift",
    "            [\"Return to Home\", \"Website Mode\", \"Window Size\", \"Zoom\", \"Residency\", \"Background Media\", \"Edit Web App…\", \"Remove Web App…\"]\n",
    "            [\"Return to Home\", \"Reload\", \"Website Mode\", \"Window Size\", \"Zoom\", \"Residency\", \"Background Media\", \"Edit Web App…\", \"Remove Web App…\"]\n",
)
replace_once(
    "FloatTabsTests/ExternalShellTests.swift",
    "        XCTAssertEqual(menu.item(withTitle: \"Website Mode\")?.submenu?.items.map(\\.title), [\"Desktop\", \"Mobile\"])\n",
    "        let reload = try! XCTUnwrap(menu.item(withTitle: \"Reload\"))\n        XCTAssertEqual(reload.keyEquivalent, \"r\")\n        XCTAssertEqual(reload.keyEquivalentModifierMask, [.command])\n        XCTAssertTrue(reload.isEnabled)\n\n        XCTAssertEqual(menu.item(withTitle: \"Website Mode\")?.submenu?.items.map(\\.title), [\"Desktop\", \"Mobile\"])\n",
)
replace_once(
    "FloatTabsTests/ExternalShellTests.swift",
    "        XCTAssertEqual(menu.item(withTitle: \"Residency\")?.submenu?.items.map(\\.title), [\"Hot\", \"Warm\", \"Cold\"])\n",
    "        let zoomItems = try! XCTUnwrap(menu.item(withTitle: \"Zoom\")?.submenu?.items)\n        XCTAssertEqual(zoomItems[0].title, \"Zoom In\")\n        XCTAssertEqual(zoomItems[0].keyEquivalent, \"+\")\n        XCTAssertEqual(zoomItems[0].keyEquivalentModifierMask, [.command])\n        XCTAssertEqual(zoomItems[1].title, \"Zoom Out\")\n        XCTAssertEqual(zoomItems[1].keyEquivalent, \"-\")\n        XCTAssertEqual(zoomItems[1].keyEquivalentModifierMask, [.command])\n        XCTAssertEqual(zoomItems[2].title, \"Reset Zoom\")\n        XCTAssertEqual(zoomItems[2].keyEquivalent, \"0\")\n        XCTAssertEqual(zoomItems[2].keyEquivalentModifierMask, [.command])\n        XCTAssertTrue(zoomItems[3].isSeparatorItem)\n\n        XCTAssertEqual(menu.item(withTitle: \"Residency\")?.submenu?.items.map(\\.title), [\"Hot\", \"Warm\", \"Cold\"])\n",
)

# Runtime user-facing resource description.
replace_once(
    "FloatTabs/Tabs/WebAppProfile.swift",
    '            return "Cache recent inactive WebViews; release after 3 minutes, beyond the two-Slot Warm cache, or under memory pressure."\n',
    '            return "Cache recent inactive WebViews; release after 2 minutes, beyond the two-Slot Warm cache, or under memory pressure."\n',
)

# Product source of truth: context menu + accepted Stage 5 Warm semantics.
replace_once(
    "docs/product/FloatTabs_Product_Development_Spec_v0.5.md",
    "Slot 右键菜单管理 Slot 身份与资源策略，不模拟完整浏览器：\n\n```text\nReturn to Home\n────────────\nResidency\n  Hot\n  Warm\n  Cold\nBackground Media\n  Pause When Inactive\n  Allow Background Audio\n────────────\nEdit Web App…\n────────────\nRemove Web App…\n```\n",
    "Slot 右键菜单是页面 / Slot 级高频控制面，不模拟完整浏览器：\n\n```text\nReturn to Home                 ⌘⇧H\nReload                         ⌘R\n────────────\nWebsite Mode\nWindow Size\nZoom\n────────────\nResidency\n  Hot\n  Warm\n  Cold\nBackground Media\n  Pause When Inactive\n  Allow Background Audio\n────────────\nEdit Web App…\n────────────\nRemove Web App…\n```\n\nWebsite Mode / Window Size / Zoom 保留在右键菜单，因为它们是高频 per-Slot 页面显示控制。Browser Identity、Device Preset、Orientation、Custom User Agent 等低频兼容性参数继续进入 `Edit Web App…` 调整。菜单快捷键提示使用原生 macOS `NSMenuItem` key equivalent 呈现，不自行绘制第二套灰字。\n",
)
replace_once(
    "docs/product/FloatTabs_Product_Development_Spec_v0.5.md",
    "### Warm\n\n- 默认值；\n- WKWebView 保留在 pool；\n- inactive 时从 visible presentation detach；\n- 再次选择时复用同一个 WKWebView；\n- 页面内存状态由 WebKit best-effort 保留，不做强保证。\n",
    "### Warm\n\n- 默认值；\n- inactive 时作为 opportunistic resident cache 保留 live WKWebView；\n- 默认 inactive TTL = 120 秒；\n- 最多保留 2 个 inactive、非后台播放保护的 Warm runtime，超过上限按 LRU 释放；\n- macOS memory pressure 可提前释放 inactive Warm；\n- 再次选择时若仍 resident 则复用同一个 WKWebView；若已释放则从持久化 Current URL / website data 重建；\n- 页面内存状态只在 resident 期间由 WebKit best-effort 保留，不做强保证。\n",
)

# Architecture source of truth: accepted Warm lifecycle.
replace_once(
    "docs/architecture/FloatTabs_Technical_Architecture_v1.2.md",
    "## 5.2 Warm\n\nWarm is the default.\n\n- keep the WKWebView object in `WebViewPool`;\n- detach it from visible presentation while inactive;\n- re-selection reuses the same WKWebView;\n- DOM / SPA / scroll / unsent text preservation remains best-effort because WebKit may throttle or suspend detached content;\n- do not proactively evict Warm WebViews merely because they are inactive.\n",
    "## 5.2 Warm\n\nWarm is the default opportunistic resident cache.\n\n- keep an inactive live WKWebView in `WebViewPool` for up to 120 seconds;\n- detach it from visible presentation while inactive;\n- keep at most 2 inactive, non-media-protected Warm runtimes resident; evict older entries LRU-first;\n- memory-pressure warning may reduce the inactive Warm cache and critical pressure may evict all inactive non-protected Warm runtimes;\n- re-selection before eviction reuses the same WKWebView; after eviction it recreates from persisted profile/current URL and the persistent website data store;\n- DOM / SPA / scroll / unsent text preservation remains best-effort only while the runtime remains resident.\n",
)

# Design system: lock context-menu information architecture without changing Gear yet.
replace_once(
    "docs/design/FloatTabs_UI_Design_System_v1.2.md",
    "Drag/Reorder：\n\n- vertical reorder;\n- no bounce/scale gimmick;\n- subtle elevation allowed;\n- neighbors smoothly make room;\n- after drop, `⌘1…⌘9` mapping immediately follows new order.\n\n---\n\n# 10. Bottom-left System Controls\n",
    "Drag/Reorder：\n\n- vertical reorder;\n- no bounce/scale gimmick;\n- subtle elevation allowed;\n- neighbors smoothly make room;\n- after drop, `⌘1…⌘9` mapping immediately follows new order.\n\n## 9.1 Slot Context Menu\n\nRight click remains the fast page / Slot-level control surface:\n\n```text\nReturn to Home                 ⌘⇧H\nReload                         ⌘R\n────────────\nWebsite Mode                  >\nWindow Size                   >\nZoom                          >\n────────────\nResidency                     >\nBackground Media              >\n────────────\nEdit Web App…\n────────────\nRemove Web App…\n```\n\nWebsite Mode, Window Size, and Zoom stay here because they are frequent per-Slot controls. Shortcut hints use native `NSMenuItem` key equivalents so macOS owns alignment, modifier glyphs, and secondary visual hierarchy. Browser Identity / Device Preset / Custom UA remain under Edit rather than expanding this menu.\n\n---\n\n# 10. Bottom-left System Controls\n",
)

print("Stage 6C patch applied")
