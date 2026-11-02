from pathlib import Path

PHASE7_EXPANDED_TEST_CORRECTIVE = True


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"missing text in {path}: {old[:100]!r}")
    p.write_text(text.replace(old, new, 1))


def replace_all(path: str, old: str, new: str, minimum: int = 1) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count < minimum:
        raise SystemExit(f"expected {minimum}+ occurrences in {path}: {old!r}; found {count}")
    p.write_text(text.replace(old, new))


def replace_function(path: str, name: str, replacement: str) -> None:
    p = Path(path)
    text = p.read_text()
    start = text.find(f"    func {name}(")
    if start < 0:
        raise SystemExit(f"missing function in {path}: {name}")
    brace = text.find("{", start)
    if brace < 0:
        raise SystemExit(f"missing opening brace in {path}: {name}")
    depth = 0
    end = None
    for i in range(brace, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end is None:
        raise SystemExit(f"missing closing brace in {path}: {name}")
    if end < len(text) and text[end] == "\n":
        end += 1
    new = replacement.rstrip()
    if new:
        new += "\n"
    p.write_text(text[:start] + new + text[end:])


# Current shortcut catalog: legacy residency actions remain only on bounded external IPC.
replace_function(
    "FloatTabsTests/AppCommandControllerTests.swift",
    "testEveryPreviouslyFixedShortcutHasAnIndividualBinding",
    '''    func testEveryCurrentShortcutHasAnIndividualBinding() {
        XCTAssertEqual(AppShortcutCatalog.slotBindings.count, 9)
        XCTAssertEqual(AppShortcutCatalog.navigationBindings.count, 7)
        XCTAssertEqual(AppShortcutCatalog.viewBindings.count, 4)
        XCTAssertEqual(AppShortcutCatalog.applicationBindings.count, 1)
        XCTAssertEqual(AppShortcutCatalog.allBindings.count, 21)
        XCTAssertEqual(Set(AppShortcutCatalog.allNames.map(\\.rawValue)).count, 21)
    }''',
)
replace_function(
    "FloatTabsTests/AppCommandControllerTests.swift",
    "testResidencyShortcutsSelectHotWarmAndCold",
    '''    func testLegacyResidencyKeysAreNotCurrentUserShortcuts() {
        XCTAssertNil(defaultCommand(keyCode: UInt16(KeyboardShortcuts.Key.h.rawValue), modifiers: [.control, .option]))
        XCTAssertNil(defaultCommand(keyCode: UInt16(KeyboardShortcuts.Key.w.rawValue), modifiers: [.control, .option]))
        XCTAssertNil(defaultCommand(keyCode: UInt16(KeyboardShortcuts.Key.c.rawValue), modifiers: [.control, .option]))
    }''',
)
replace_function(
    "FloatTabsTests/AppCommandControllerTests.swift",
    "testStatusHUDDisplaysSelectedResidencyMode",
    "",
)

# Legacy Warm/Cold values stay stored for compatibility but no longer project as settings rows.
replace_function(
    "FloatTabsTests/WebsiteCacheCleanupTests.swift",
    "testPerformanceSettingsShowsResidencyDefaultsAndStoredChoices",
    '''    func testPerformanceSettingsDoesNotProjectLegacyResidencyTimingControls() {
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.warmWebViewRetentionDelay = 600
        preferences.coldWebViewReleaseDelay = 120
        let controller = PerformanceSettingsViewController(preferencesStore: preferences)
        controller.loadView()

        XCTAssertEqual(preferences.warmWebViewRetentionDelay, 600)
        XCTAssertEqual(preferences.coldWebViewReleaseDelay, 120)
        XCTAssertEqual(controller.displayedWebsiteCacheUsage, "Unavailable")
    }''',
)

# Current context-menu copy.
replace_once(
    "FloatTabsTests/BrowserProfileDuplicateTests.swift",
    '"Profile", "Open in New Tab with Profile", "Residency",',
    '"Profile", "Open in New Tab with Profile", "Runtime Retention",',
)
replace_once(
    "FloatTabsTests/ExternalShellTests.swift",
    '"Profile", "Open in New Tab with Profile", "Residency", "Background Media",',
    '"Profile", "Open in New Tab with Profile", "Runtime Retention", "Background Media",',
)
replace_once(
    "FloatTabsTests/ExternalShellTests.swift",
    'XCTAssertEqual(menu.item(withTitle: "Residency")?.submenu?.items.map(\\.title), ["Hot", "Warm", "Cold"])',
    'XCTAssertEqual(menu.item(withTitle: "Runtime Retention")?.submenu?.items.map(\\.title), ["Automatic", "Keep Loaded"])',
)

# Phase 7 presentation detaches inactive runtime instead of keeping a hidden Hot host.
replace_function(
    "FloatTabsTests/WebViewFactoryTests.swift",
    "testHotHostsPreserveInactiveViewportAcrossDifferentSlotSizes",
    '''    func testInactiveRuntimeDetachesFromPresentationAndRestoresAtCurrentSize() {
        _ = NSApplication.shared
        let container = WebPanelContainerView(frame: NSRect(x: 0, y: 0, width: 600, height: 820))
        let window = NSWindow(contentRect: container.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = container
        container.layoutSubtreeIfNeeded()

        let firstID = UUID()
        let secondID = UUID()
        let first = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let second = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)

        container.show(webView: first, slotID: firstID, residencyPolicy: .warm)
        container.layoutSubtreeIfNeeded()
        let firstSize = first.frame.size
        XCTAssertEqual(first.frame.width, 1024, accuracy: 0.001)
        XCTAssertTrue(first.window === window)

        container.deactivate(slotID: firstID, residencyPolicy: .warm)
        XCTAssertNil(first.superview)
        XCTAssertNil(first.window)
        container.setFrameSize(NSSize(width: 1080, height: 850))
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(first.frame.size, firstSize)

        container.show(webView: second, slotID: secondID, residencyPolicy: .warm)
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(second.frame.width, 1440, accuracy: 0.001)
        XCTAssertNil(first.superview)
        XCTAssertTrue(second.window === window)

        container.show(webView: first, slotID: firstID, residencyPolicy: .warm)
        container.layoutSubtreeIfNeeded()
        XCTAssertTrue(container.currentWebView === first)
        XCTAssertEqual(first.frame.width, 1440, accuracy: 0.001)
        XCTAssertTrue(first.window === window)
        XCTAssertNil(second.superview)
    }''',
)

# Automatic lifecycle uses one debug plan class; Cold no longer exists as current policy.
replace_all("FloatTabsTests/WebViewPoolTests.swift", "pendingColdReleaseCount", "pendingWarmReleaseCount", minimum=6)
replace_function(
    "FloatTabsTests/WebViewPoolTests.swift",
    "testResourceLifecycleDefaultTimingsMatchAcceptedContract",
    '''    func testResourceLifecycleDefaultsMatchAutomaticContract() throws {
        XCTAssertEqual(SlotLifecycleCoordinator.defaultAutomaticReleaseDelay, 30)
        XCTAssertEqual(SlotLifecycleCoordinator.defaultHiddenActiveGraceDelay, 0)
        XCTAssertEqual(SlotLifecycleCoordinator.defaultManagedResidentTarget, 2)
        XCTAssertEqual(SlotLifecycleCoordinator.warningManagedResidentTarget, 1)
    }''',
)
replace_function(
    "FloatTabsTests/WebViewPoolTests.swift",
    "testWarmLifecycleDoesNotScheduleColdRelease",
    '''    func testAutomaticLifecycleSchedulesSingleGraceAndReleases() async throws {
        let pool = makePool()
        var profile = makeProfile(name: "Automatic")
        profile.runtimeRetentionPreference = .automatic
        _ = try pool.webView(for: profile)
        let container = WebPanelContainerView(frame: NSRect(x: 0, y: 0, width: 430, height: 820))
        let lifecycle = SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            coldReleaseDelay: 0.01,
            warmReleaseDelay: 0.01,
            installsMemoryPressureSource: false
        )
        lifecycle.activate(profile: profile)
        lifecycle.deactivate(profile: profile)
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(pool.contains(slotID: profile.id))
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 0)
    }''',
)
replace_once(
    "FloatTabsTests/WebViewPoolTests.swift",
    '''        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 3)
        XCTAssertEqual(pool.count, 3)
        for profile in profiles {
            XCTAssertTrue(pool.contains(slotID: profile.id))
        }''',
    '''        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 2)
        XCTAssertEqual(pool.count, 2)
        XCTAssertEqual(profiles.filter { pool.contains(slotID: $0.id) }.count, 2)''',
)
replace_once(
    "FloatTabsTests/WebViewPoolTests.swift",
    "func testThreeInactiveWarmRuntimesRemainUntilTTLWithoutMemoryPressure()",
    "func testThreeInactiveAutomaticRuntimesRespectNormalBudgetBeforeGrace()",
)

# Attention lifecycle expectations now follow normal target 2 / warning target 1.
replace_all("FloatTabsTests/WebAttentionLifecycleTests.swift", "pendingColdReleaseCount", "pendingWarmReleaseCount", minimum=3)
replace_once("FloatTabsTests/WebAttentionLifecycleTests.swift", '.string("release_timer")', '.string("automatic_grace")')
replace_once(
    "FloatTabsTests/WebAttentionLifecycleTests.swift",
    '$0.fields["residency"] == .string(profile.residencyPolicy.rawValue)',
    '$0.fields["runtime_retention"] == .string(profile.runtimeRetentionPreference.rawValue)',
)
replace_once(
    "FloatTabsTests/WebAttentionLifecycleTests.swift",
    '''        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 3)
        for profile in profiles {
            XCTAssertTrue(
                pool.contains(slotID: profile.id),
                "Warm runtime \\(profile.name) should remain resident until its TTL expires."
            )
        }''',
    '''        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 2)
        XCTAssertEqual(pool.count, 2)
        XCTAssertEqual(profiles.filter { pool.contains(slotID: $0.id) }.count, 2)''',
)
replace_once(
    "FloatTabsTests/WebAttentionLifecycleTests.swift",
    "func testThreeInactiveWarmRuntimesRemainResidentBeforeConfiguredTTL()",
    "func testThreeInactiveAutomaticRuntimesRespectNormalBudgetBeforeGrace()",
)
replace_function(
    "FloatTabsTests/WebAttentionLifecycleTests.swift",
    "testMemoryWarningKeepsEligibleWarmRuntimesAndTheirPlans",
    '''    func testMemoryWarningReducesAutomaticRuntimesToOne() throws {
        let pool = makePool()
        let profiles = [
            makeProfile(name: "WarningOne", policy: .warm),
            makeProfile(name: "WarningTwo", policy: .warm),
            makeProfile(name: "WarningThree", policy: .warm)
        ]
        for profile in profiles { _ = try pool.webView(for: profile) }
        let lifecycle = makeLifecycle(pool: pool, warmReleaseDelay: 600)
        for profile in profiles { makeInactive(lifecycle, profile: profile) }

        XCTAssertEqual(pool.count, 2)
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 2)
        lifecycle.handleMemoryPressure(.warning)
        XCTAssertEqual(pool.count, 1)
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 1)
    }''',
)
replace_once(
    "FloatTabsTests/WebAttentionLifecycleTests.swift",
    '''        XCTAssertTrue(pool.contains(slotID: protected.id))
        XCTAssertTrue(pool.contains(slotID: eligibleB.id))
        XCTAssertTrue(pool.contains(slotID: eligibleC.id))
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 3)''',
    '''        XCTAssertTrue(pool.contains(slotID: protected.id))
        XCTAssertFalse(pool.contains(slotID: eligibleB.id))
        XCTAssertFalse(pool.contains(slotID: eligibleC.id))
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 1)''',
)
replace_once(
    "FloatTabsTests/WebAttentionLifecycleTests.swift",
    '''        XCTAssertTrue(pool.contains(slotID: protected.id))
        XCTAssertTrue(lifecycle.mediaProtectedIDs.contains(protected.id))
        XCTAssertTrue(pool.contains(slotID: eligibleB.id))
        XCTAssertTrue(pool.contains(slotID: eligibleC.id))
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 3)''',
    '''        XCTAssertTrue(pool.contains(slotID: protected.id))
        XCTAssertTrue(lifecycle.mediaProtectedIDs.contains(protected.id))
        XCTAssertFalse(pool.contains(slotID: eligibleB.id))
        XCTAssertFalse(pool.contains(slotID: eligibleC.id))
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 1)''',
)
replace_once(
    "FloatTabsTests/WebAttentionLifecycleTests.swift",
    '''        XCTAssertEqual(coordinator.state(for: generating.id), .generating)
        XCTAssertEqual(coordinator.state(for: ready.id), .ready)
        XCTAssertTrue(pool.contains(slotID: generating.id))
        XCTAssertTrue(pool.contains(slotID: ready.id))
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 2)''',
    '''        XCTAssertEqual(coordinator.state(for: generating.id), .generating)
        XCTAssertEqual(coordinator.state(for: ready.id), .ready)
        XCTAssertTrue(pool.contains(slotID: generating.id))
        XCTAssertFalse(pool.contains(slotID: ready.id))
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 1)''',
)

# Cross-feature expectations use the same Automatic projection and budget targets.
replace_all("FloatTabsTests/WebAttentionCrossFeatureTests.swift", "debugPendingColdReleaseCount", "debugPendingWarmReleaseCount", minimum=4)
replace_once(
    "FloatTabsTests/WebAttentionCrossFeatureTests.swift",
    '''        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 3)

        // Warning pressure is diagnostics-only: it must not shorten the
        // configured Warm deadline for any runtime.
        lifecycle.handleMemoryPressure(.warning)
        XCTAssertTrue(pool.contains(slotID: ordinaryA.id))
        XCTAssertTrue(pool.contains(slotID: ordinaryB.id))
        XCTAssertTrue(pool.contains(slotID: chat.id))
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 3)''',
    '''        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 2)
        XCTAssertEqual([ordinaryA, ordinaryB].filter { pool.contains(slotID: $0.id) }.count, 1)
        XCTAssertTrue(pool.contains(slotID: chat.id))

        // Warning target is one Automatic runtime; generating protection wins.
        lifecycle.handleMemoryPressure(.warning)
        XCTAssertFalse(pool.contains(slotID: ordinaryA.id))
        XCTAssertFalse(pool.contains(slotID: ordinaryB.id))
        XCTAssertTrue(pool.contains(slotID: chat.id))
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 1)''',
)
replace_once(
    "FloatTabsTests/WebAttentionCrossFeatureTests.swift",
    "func testWarmGeneratingSurvivesMemoryPressureAndBecomesReadyOffScreen()",
    "func testAutomaticGeneratingSurvivesMemoryPressureAndBecomesReadyOffScreen()",
)
replace_once(
    "FloatTabsTests/WebAttentionCrossFeatureTests.swift",
    '''        makeInactive(lifecycle, profile: ordinaryA)
        makeInactive(lifecycle, profile: ordinaryB)

        lifecycle.handleMemoryPressure(.warning)
        XCTAssertTrue(pool.contains(slotID: ordinaryA.id))
        XCTAssertTrue(pool.contains(slotID: ordinaryB.id))
        XCTAssertTrue(pool.contains(slotID: chat.id))''',
    '''        makeInactive(lifecycle, profile: ordinaryA)
        makeInactive(lifecycle, profile: ordinaryB)
        XCTAssertEqual(pool.count, 2)
        XCTAssertTrue(controller.debugIsProjectingUnreadResponse(slotID: chat.id))

        lifecycle.handleMemoryPressure(.warning)
        XCTAssertEqual(pool.count, 1)
        XCTAssertTrue(controller.debugIsProjectingUnreadResponse(slotID: chat.id))''',
)
replace_once(
    "FloatTabsTests/WebAttentionCrossFeatureTests.swift",
    "func testReadyWarmCanBeReclaimedWhileUnreadSurvivesMemoryPressure()",
    "func testReadyAutomaticCanBeReclaimedWhileUnreadSurvivesMemoryPressure()",
)
