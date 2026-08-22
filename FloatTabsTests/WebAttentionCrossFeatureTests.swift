import AppKit
import WebKit
import XCTest
@testable import FloatTabs

/// Stage F — cross-feature closure.
///
/// These tests prove the COMPOSITION of the attention feature across the
/// real production wiring, not the individual pieces Stages A–E already
/// cover: the pool-created `ChatGPTAttentionBridge` on a real WKWebView →
/// `WebViewPool.onAttentionObservation` → `PanelController` routing →
/// `WebAttentionCoordinator` → rail Ready projection → lifecycle protection
/// and fresh-boundary restarts.
///
/// Where a boundary needs time compression (Warm TTL, Warm release timers),
/// a directly-built `SlotLifecycleCoordinator` with short delays reads the
/// SAME real attention authority the production chain drives, because
/// `PanelController`'s own coordinator uses production delays. Every other
/// link is the real production object.
@MainActor
final class WebAttentionCrossFeatureTests: XCTestCase {
    private var retainedControllers: [PanelController] = []
    private var retainedContainers: [WebPanelContainerView] = []
    private var repositoryURLs: [URL] = []

    override func tearDown() {
        retainedControllers.removeAll()
        retainedContainers.removeAll()
        repositoryURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        repositoryURLs.removeAll()
        super.tearDown()
    }

    // MARK: 4.1 Live observation → Ready → UI projection

    func testLiveBridgeChainProjectsReadyDotAndNewGenerationClearsItImmediately() throws {
        let (controller, coordinator, store, pool) = makeController(
            profiles: [spec(name: "ChatA", url: "https://chatgpt.com/chat-a")]
        )
        let slot = try profile(named: "ChatA", in: store)
        let webView = try makeResidentWebView(pool: pool, store: store, slotName: "ChatA")
        let bridge = try attentionBridge(pool: pool, slot: slot)

        acceptBaseline(generating: true, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: slot.id), .generating)
        XCTAssertFalse(controller.debugIsProjectingReadyAttention(slotID: slot.id))

        // The shell was never presented, so the real router resolves actual
        // visibility from the real (unordered) windows and finishes to Ready.
        acceptState(generating: false, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: slot.id), .ready)
        XCTAssertEqual(coordinator.readySlotIDs, [slot.id])
        XCTAssertTrue(controller.debugIsProjectingReadyAttention(slotID: slot.id))

        // A new generation supersedes Ready and the dot must clear at once.
        acceptState(generating: true, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: slot.id), .generating)
        XCTAssertFalse(controller.debugIsProjectingReadyAttention(slotID: slot.id))
        XCTAssertEqual(controller.attentionReadyCount, 0)

        // A later completion while still unseen must create a fresh Ready
        // cycle rather than any historical notification count.
        acceptState(generating: false, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: slot.id), .ready)
        XCTAssertEqual(controller.attentionReadyCount, 1)
        XCTAssertTrue(controller.debugIsProjectingReadyAttention(slotID: slot.id))
    }

    // MARK: 4.5 Selected-hidden completion

    func testSelectedHiddenCompletionDuringGraceBecomesReadyProtectedAndProjected() throws {
        let (controller, coordinator, store, pool) = makeController(
            profiles: [spec(name: "ChatA", url: "https://chatgpt.com/chat-a")]
        )
        let slot = try profile(named: "ChatA", in: store)
        setResidency(.cold, for: "ChatA", in: store)
        let webView = try makeResidentWebView(pool: pool, store: store, slotName: "ChatA")
        let bridge = try attentionBridge(pool: pool, slot: slot)

        acceptBaseline(generating: true, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: slot.id), .generating)

        // The real hide path starts the hidden-active grace through the
        // controller's own lifecycle coordinator.
        controller.hideFloatTabs()
        XCTAssertTrue(controller.debugIsHiddenActiveGracePending)

        // Completion while the shell is hidden is not user-visible: the real
        // router must latch Ready, not Idle.
        acceptState(generating: false, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: slot.id), .ready)
        XCTAssertTrue(controller.debugIsProjectingReadyAttention(slotID: slot.id))
        XCTAssertTrue(pool.contains(slotID: slot.id))
        XCTAssertTrue(controller.debugIsHiddenActiveGracePending)
    }

    // MARK: 4.5 / matrix 2 — Cold generating, switched away

    func testColdGeneratingSwitchedAwayGetsProtectedColdPlanAndCompletesToReady() throws {
        let (controller, coordinator, store, pool) = makeController(
            profiles: [
                spec(name: "ChatA", url: "https://chatgpt.com/chat-a"),
                spec(name: "Plain", url: "https://example.com/plain")
            ]
        )
        let slot = try profile(named: "ChatA", in: store)
        setResidency(.cold, for: "ChatA", in: store)
        let webView = try makeResidentWebView(pool: pool, store: store, slotName: "ChatA")
        let bridge = try attentionBridge(pool: pool, slot: slot)

        acceptBaseline(generating: true, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: slot.id), .generating)

        // Switching tabs drives the controller's own lifecycle coordinator:
        // deactivation creates the Cold plan immediately (no grace involved).
        try select(named: "Plain", in: store)
        XCTAssertEqual(controller.debugPendingColdReleaseCount, 1)
        let planToken = try XCTUnwrap(controller.debugInactivePlanToken(slotID: slot.id))
        XCTAssertTrue(pool.contains(slotID: slot.id))

        // Off-screen completion latches Ready and must not churn the plan.
        acceptState(generating: false, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: slot.id), .ready)
        XCTAssertTrue(controller.debugIsProjectingReadyAttention(slotID: slot.id))
        XCTAssertTrue(pool.contains(slotID: slot.id))
        XCTAssertEqual(controller.debugPendingColdReleaseCount, 1)
        XCTAssertEqual(controller.debugInactivePlanToken(slotID: slot.id), planToken)
    }

    // MARK: matrix 5 — Hot remains Hot

    func testHotChatGPTStaysHotWithoutReleasePlanAcrossCompletion() throws {
        let (controller, coordinator, store, pool) = makeController(
            profiles: [
                spec(name: "ChatA", url: "https://chatgpt.com/chat-a"),
                spec(name: "Plain", url: "https://example.com/plain")
            ]
        )
        let slot = try profile(named: "ChatA", in: store)
        setResidency(.hot, for: "ChatA", in: store)
        setResidency(.hot, for: "Plain", in: store)
        let webView = try makeResidentWebView(pool: pool, store: store, slotName: "ChatA")
        let bridge = try attentionBridge(pool: pool, slot: slot)

        acceptBaseline(generating: true, bridge: bridge, webView: webView)
        try select(named: "Plain", in: store)

        XCTAssertEqual(controller.debugPendingColdReleaseCount, 0)
        XCTAssertEqual(controller.debugPendingWarmReleaseCount, 0)
        XCTAssertTrue(pool.contains(slotID: slot.id))

        acceptState(generating: false, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: slot.id), .ready)
        XCTAssertTrue(controller.debugIsProjectingReadyAttention(slotID: slot.id))
        XCTAssertTrue(pool.contains(slotID: slot.id))
        XCTAssertEqual(controller.debugPendingColdReleaseCount, 0)
        XCTAssertEqual(controller.debugPendingWarmReleaseCount, 0)
    }

    // MARK: 4.3 Warm generating → TTL/LRU → Ready (compressed-delay lifecycle
    // reading the SAME real authority the production chain drives)

    func testWarmGeneratingSurvivesTTLLRUAndBecomesReadyOffScreen() async throws {
        let (controller, coordinator, store, pool) = makeController(
            profiles: [
                spec(name: "ChatWarm", url: "https://chatgpt.com/chat-warm"),
                spec(name: "OrdinaryA", url: "https://example.com/ordinary-a"),
                spec(name: "OrdinaryB", url: "https://example.com/ordinary-b"),
                spec(name: "OrdinaryC", url: "https://example.com/ordinary-c"),
                spec(name: "OrdinaryD", url: "https://example.com/ordinary-d")
            ]
        )
        let chat = try profile(named: "ChatWarm", in: store)
        let webView = try makeResidentWebView(pool: pool, store: store, slotName: "ChatWarm")
        let bridge = try attentionBridge(pool: pool, slot: chat)

        // The ordinary pressure controls are materialized AFTER the last
        // store selection: the controller's own lifecycle coordinator (with
        // its production resident limit) must not reconcile them into its
        // own plans and LRU-evict them before the compressed coordinator
        // under test ever observes them.
        let ordinaryA = try materializeRuntime(
            pool: pool, store: store, slotName: "OrdinaryA"
        ).profile
        let ordinaryB = try materializeRuntime(
            pool: pool, store: store, slotName: "OrdinaryB"
        ).profile

        // The compressed-delay lifecycle reads the real attention authority.
        let lifecycle = makeCompressedLifecycle(
            pool: pool,
            warmReleaseDelay: 0.05,
            warmResidentLimit: 3,
            attentionCoordinator: coordinator
        )

        acceptBaseline(generating: true, bridge: bridge, webView: webView)

        makeInactive(lifecycle, profile: chat)
        makeInactive(lifecycle, profile: ordinaryA)
        makeInactive(lifecycle, profile: ordinaryB)
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 3)

        // Proactive LRU pressure must respect the real authority: warning
        // pressure evicts the oldest ELIGIBLE warm slot, never the
        // Generating-protected runtime.
        lifecycle.handleMemoryPressure(.warning)
        XCTAssertFalse(pool.contains(slotID: ordinaryA.id))
        XCTAssertTrue(pool.contains(slotID: ordinaryB.id))
        XCTAssertTrue(pool.contains(slotID: chat.id))
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 2)

        lifecycle.handleMemoryPressure(.critical)
        XCTAssertFalse(pool.contains(slotID: ordinaryB.id))
        XCTAssertTrue(pool.contains(slotID: chat.id))
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 1)

        // Same-deadline differential: OrdinaryC goes inactive NOW, so its
        // 50ms release is the semantic event proving the boundary time has
        // passed for the earlier-scheduled protected plan too. The
        // Generating runtime must still hold its plan and stay resident.
        let ordinaryC = try materializeRuntime(
            pool: pool, store: store, slotName: "OrdinaryC"
        ).profile
        makeInactive(lifecycle, profile: ordinaryC)
        let boundaryCrossed = try await waitUntil {
            !pool.contains(slotID: ordinaryC.id)
        }
        XCTAssertTrue(boundaryCrossed)
        try await wait(milliseconds: 80)
        XCTAssertTrue(pool.contains(slotID: chat.id))
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 1)

        // Off-screen completion through the real chain latches Ready, and a
        // fresh differential control proves Ready protection holds at a new
        // boundary as well.
        acceptState(generating: false, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: chat.id), .ready)
        XCTAssertTrue(controller.debugIsProjectingReadyAttention(slotID: chat.id))

        let ordinaryD = try materializeRuntime(
            pool: pool, store: store, slotName: "OrdinaryD"
        ).profile
        makeInactive(lifecycle, profile: ordinaryD)
        let readyBoundaryCrossed = try await waitUntil {
            !pool.contains(slotID: ordinaryD.id)
        }
        XCTAssertTrue(readyBoundaryCrossed)
        XCTAssertTrue(pool.contains(slotID: chat.id))
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 1)
        XCTAssertEqual(coordinator.state(for: chat.id), .ready)
    }

    // MARK: 4.4 Ready + memory pressure

    func testReadyWarmSurvivesMemoryPressureWhileEligibleWarmIsEvicted() throws {
        let (controller, coordinator, store, pool) = makeController(
            profiles: [
                spec(name: "ChatReady", url: "https://chatgpt.com/chat-ready"),
                spec(name: "OrdinaryA", url: "https://example.com/ordinary-a"),
                spec(name: "OrdinaryB", url: "https://example.com/ordinary-b")
            ]
        )
        let chat = try profile(named: "ChatReady", in: store)
        let webView = try makeResidentWebView(pool: pool, store: store, slotName: "ChatReady")
        let bridge = try attentionBridge(pool: pool, slot: chat)

        // Materialized after the last store selection so the controller's
        // own lifecycle never plans or evicts these pressure controls.
        let ordinaryA = try materializeRuntime(
            pool: pool, store: store, slotName: "OrdinaryA"
        ).profile
        let ordinaryB = try materializeRuntime(
            pool: pool, store: store, slotName: "OrdinaryB"
        ).profile

        let lifecycle = makeCompressedLifecycle(
            pool: pool,
            warmReleaseDelay: 60,
            warmResidentLimit: 3,
            attentionCoordinator: coordinator
        )

        // Reach Ready through the real bridge → pool → controller chain.
        acceptBaseline(generating: true, bridge: bridge, webView: webView)
        makeInactive(lifecycle, profile: chat)
        acceptState(generating: false, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: chat.id), .ready)
        XCTAssertTrue(controller.debugIsProjectingReadyAttention(slotID: chat.id))

        makeInactive(lifecycle, profile: ordinaryA)
        makeInactive(lifecycle, profile: ordinaryB)

        lifecycle.handleMemoryPressure(.warning)
        XCTAssertFalse(pool.contains(slotID: ordinaryA.id))
        XCTAssertTrue(pool.contains(slotID: ordinaryB.id))
        XCTAssertTrue(pool.contains(slotID: chat.id))

        // Critical pressure still cannot take the Ready runtime.
        lifecycle.handleMemoryPressure(.critical)
        XCTAssertFalse(pool.contains(slotID: ordinaryB.id))
        XCTAssertTrue(pool.contains(slotID: chat.id))
        XCTAssertEqual(coordinator.state(for: chat.id), .ready)
    }

    // MARK: 4.2 Runtime reset → fresh lifecycle boundary

    func testWebContentTerminationResetsAttentionAndRestartsColdLifecycleFromFreshBoundary() throws {
        let (controller, coordinator, store, pool) = makeController(
            profiles: [
                spec(name: "ChatA", url: "https://chatgpt.com/chat-a"),
                spec(name: "Plain", url: "https://example.com/plain")
            ]
        )
        let slot = try profile(named: "ChatA", in: store)
        setResidency(.cold, for: "ChatA", in: store)
        let webView = try makeResidentWebView(pool: pool, store: store, slotName: "ChatA")
        let bridge = try attentionBridge(pool: pool, slot: slot)
        let observer = try navigationObserver(of: webView)

        acceptBaseline(generating: true, bridge: bridge, webView: webView)
        try select(named: "Plain", in: store)
        let oldToken = try XCTUnwrap(controller.debugInactivePlanToken(slotID: slot.id))
        XCTAssertEqual(controller.debugPendingColdReleaseCount, 1)

        // WebContent termination routes through the real delegate → pool →
        // bridge → controller chain: protection ends, the runtime stays
        // resident, and the controller must request a fresh Cold plan —
        // never a synthetic completion.
        observer.webViewWebContentProcessDidTerminate(webView)

        XCTAssertEqual(coordinator.state(for: slot.id), .idle)
        XCTAssertFalse(controller.debugIsProjectingReadyAttention(slotID: slot.id))
        XCTAssertTrue(pool.contains(slotID: slot.id))
        XCTAssertEqual(controller.debugPendingColdReleaseCount, 1)
        let newToken = try XCTUnwrap(controller.debugInactivePlanToken(slotID: slot.id))
        XCTAssertNotEqual(newToken, oldToken)

        // The recovered document establishes a fresh baseline and may
        // legitimately generate again.
        acceptBaseline(
            generating: true,
            bridge: bridge,
            webView: webView,
            token: "recovered-document-token-0001"
        )
        XCTAssertEqual(coordinator.state(for: slot.id), .generating)
    }

    // MARK: 4.6 Interaction-aware acknowledgement → later normal policy

    func testNonInteractivePresentationDoesNotAcknowledgeReadyAndLaterDeactivationStartsFreshColdLifecycle() throws {
        let (controller, coordinator, store, pool) = makeController(
            profiles: [
                spec(name: "ChatA", url: "https://chatgpt.com/chat-a"),
                spec(name: "Plain", url: "https://example.com/plain")
            ]
        )
        let slot = try profile(named: "ChatA", in: store)
        setResidency(.cold, for: "ChatA", in: store)
        let webView = try makeResidentWebView(pool: pool, store: store, slotName: "ChatA")
        let bridge = try attentionBridge(pool: pool, slot: slot)

        // Hidden selected completion → Ready (never presented so far).
        acceptBaseline(generating: true, bridge: bridge, webView: webView)
        controller.hideFloatTabs()
        acceptState(generating: false, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: slot.id), .ready)
        XCTAssertTrue(controller.debugIsProjectingReadyAttention(slotID: slot.id))

        // A non-visible acknowledgement must not clear Ready.
        controller.acknowledgeAttentionIfActuallyVisible(slotID: slot.id)
        XCTAssertEqual(coordinator.state(for: slot.id), .ready)
        XCTAssertTrue(controller.debugIsProjectingReadyAttention(slotID: slot.id))

        // The test host's AppKit activation state is environment-dependent.
        // Whatever the actual WebView window topology is, the controller's
        // acknowledgement must agree with the same authoritative visibility
        // decision used by the reducer.
        controller.showFloatTabs()
        let webInteractionRegained = controller.isAttentionUserVisible(slotID: slot.id)
        XCTAssertEqual(
            coordinator.state(for: slot.id),
            webInteractionRegained ? .idle : .ready
        )
        XCTAssertEqual(
            controller.debugIsProjectingReadyAttention(slotID: slot.id),
            !webInteractionRegained
        )
        // Acknowledgement itself never evicts: the runtime is still resident
        // and no inactive plan exists while the Slot stays selected.
        XCTAssertTrue(pool.contains(slotID: slot.id))
        XCTAssertEqual(controller.debugPendingColdReleaseCount, 0)

        // Only the later deactivation starts a fresh Cold lifecycle.
        try select(named: "Plain", in: store)
        XCTAssertEqual(controller.debugPendingColdReleaseCount, 1)
        XCTAssertNotNil(controller.debugInactivePlanToken(slotID: slot.id))
        XCTAssertTrue(pool.contains(slotID: slot.id))
    }

    func testPinnedInactiveCompletionStaysReadyUntilInteractionReturns() {
        let coordinator = WebAttentionCoordinator()
        let slot = UUID()
        let pinnedInactive = AttentionPresentation.Facts(
            slotID: slot,
            pooledWebViewExists: true,
            normalCurrentWebViewIsSlotWebView: true,
            sourceWindowIsVisible: true,
            webPresentationOwnsActiveInteraction: false
        )
        let activePresentation = AttentionPresentation.Facts(
            slotID: slot,
            pooledWebViewExists: true,
            normalCurrentWebViewIsSlotWebView: true,
            sourceWindowIsVisible: true,
            webPresentationOwnsActiveInteraction: true
        )
        let router = WebAttentionObservationRouter(
            attentionCoordinator: coordinator,
            isUserVisible: { _ in
                AttentionPresentation.isUserVisible(pinnedInactive)
            }
        )

        // Physical visibility from pinning is not enough to resolve the
        // completion to Idle; the completion-time interaction fact is false.
        router.handle(.generationStarted, for: slot)
        router.handle(.generationFinished, for: slot)
        XCTAssertEqual(coordinator.state(for: slot), .ready)
        XCTAssertTrue(coordinator.isAttentionProtected(slot))
        XCTAssertEqual(
            StatusItemController.attentionPresentation(
                readyCount: coordinator.readySlotIDs.count,
                floatTabsVisible: true
            ).badge,
            .none
        )

        // Returning to the same selected Web presentation acknowledges the
        // existing Ready state without a tab switch.
        coordinator.acknowledge(
            slotID: slot,
            userVisible: AttentionPresentation.isUserVisible(activePresentation)
        )
        XCTAssertEqual(coordinator.state(for: slot), .idle)
        XCTAssertFalse(coordinator.isAttentionProtected(slot))
        XCTAssertTrue(coordinator.readySlotIDs.isEmpty)
    }

    func testMultipleReadySlotsKeepDerivedAggregateThroughIndependentAcknowledgements() {
        let coordinator = WebAttentionCoordinator()
        let slotIDs = [UUID(), UUID(), UUID()]
        let hiddenRouter = WebAttentionObservationRouter(
            attentionCoordinator: coordinator,
            isUserVisible: { _ in false }
        )

        for slotID in slotIDs {
            hiddenRouter.handle(.generationStarted, for: slotID)
            hiddenRouter.handle(.generationFinished, for: slotID)
        }

        XCTAssertEqual(coordinator.readySlotIDs, Set(slotIDs))
        XCTAssertEqual(
            StatusItemController.attentionPresentation(
                readyCount: coordinator.readySlotIDs.count,
                floatTabsVisible: false
            ).badge,
            .count("3")
        )

        coordinator.acknowledge(slotID: slotIDs[0], userVisible: true)
        XCTAssertEqual(coordinator.readySlotIDs, Set(slotIDs.dropFirst()))
        XCTAssertEqual(
            StatusItemController.attentionPresentation(
                readyCount: coordinator.readySlotIDs.count,
                floatTabsVisible: false
            ).badge,
            .count("2")
        )

        coordinator.acknowledge(slotID: slotIDs[1], userVisible: true)
        XCTAssertEqual(coordinator.readySlotIDs, [slotIDs[2]])
        XCTAssertEqual(
            StatusItemController.attentionPresentation(
                readyCount: coordinator.readySlotIDs.count,
                floatTabsVisible: false
            ).badge,
            .dot
        )

        coordinator.acknowledge(slotID: slotIDs[2], userVisible: true)
        XCTAssertTrue(coordinator.readySlotIDs.isEmpty)
        XCTAssertEqual(
            StatusItemController.attentionPresentation(
                readyCount: coordinator.readySlotIDs.count,
                floatTabsVisible: false
            ).badge,
            .none
        )
    }

    func testUnrelatedFloatTabsKeyWindowDoesNotAcknowledgeReady() throws {
        let (controller, coordinator, store, pool) = makeController(
            profiles: [spec(name: "ChatA", url: "https://chatgpt.com/chat-a")]
        )
        let slot = try profile(named: "ChatA", in: store)
        let webView = try makeResidentWebView(pool: pool, store: store, slotName: "ChatA")
        let bridge = try attentionBridge(pool: pool, slot: slot)

        acceptBaseline(generating: true, bridge: bridge, webView: webView)
        controller.hideFloatTabs()
        acceptState(generating: false, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: slot.id), .ready)

        // Exercise the registered NSWindow notification path with a
        // non-Web FloatTabs surface, such as Settings. Current WebView facts
        // must reject the event and leave the already-selected Slot Ready.
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        NotificationCenter.default.post(
            name: NSWindow.didBecomeKeyNotification,
            object: settingsWindow
        )

        XCTAssertEqual(coordinator.state(for: slot.id), .ready)
        XCTAssertTrue(controller.debugIsProjectingReadyAttention(slotID: slot.id))
    }

    func testWebPresentationKeyNotificationAcknowledgesAlreadySelectedReadySlot() throws {
        let (controller, coordinator, store, pool) = makeController(
            profiles: [spec(name: "ChatA", url: "https://chatgpt.com/chat-a")]
        )
        let slot = try profile(named: "ChatA", in: store)
        _ = try makeResidentWebView(pool: pool, store: store, slotName: "ChatA")

        // Establish the actual Web presentation first. The test host can
        // expose the key-window fact even though it cannot reliably be the
        // system frontmost application.
        controller.showFloatTabs()
        XCTAssertTrue(controller.isAttentionUserVisible(slotID: slot.id))

        // Seed an already-selected Ready state after presentation so the
        // notification below is the acknowledgement boundary under test.
        coordinator.apply(.generationStarted, for: slot.id)
        coordinator.apply(.generationFinished(userVisible: false), for: slot.id)
        XCTAssertEqual(coordinator.state(for: slot.id), .ready)

        NotificationCenter.default.post(
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

        XCTAssertEqual(coordinator.state(for: slot.id), .idle)
        XCTAssertTrue(coordinator.readySlotIDs.isEmpty)
    }

    // MARK: 4.7 Visible / fullscreen completion decisions through the router

    func testCompletionVisibilityDecisionsUseRealPresentationFactsThroughRouter() {
        let coordinator = WebAttentionCoordinator()
        let slot = UUID()

        func makeRouter(visible: AttentionPresentation.Facts) -> WebAttentionObservationRouter {
            WebAttentionObservationRouter(
                attentionCoordinator: coordinator,
                isUserVisible: { _ in
                    AttentionPresentation.isUserVisible(visible)
                }
            )
        }

        let normalVisible = AttentionPresentation.Facts(
            slotID: slot,
            pooledWebViewExists: true,
            normalCurrentWebViewIsSlotWebView: true,
            sourceWindowIsVisible: true,
            webPresentationOwnsActiveInteraction: true
        )
        var router = makeRouter(visible: normalVisible)
        router.handle(.generationStarted, for: slot)
        router.handle(.generationFinished, for: slot)
        XCTAssertEqual(coordinator.state(for: slot), .idle)
        XCTAssertTrue(coordinator.readySlotIDs.isEmpty)

        // WebKit-owned element-fullscreen source: visible for the whole
        // locked session even with the normal shell hidden.
        let fullscreenSource = AttentionPresentation.Facts(
            slotID: slot,
            sessionIsLocked: true,
            pooledWebViewExists: true,
            normalCurrentWebViewIsSlotWebView: false,
            sourceWindowIsVisible: false,
            webPresentationOwnsActiveInteraction: true,
            fullscreenSourceSlotID: slot,
            panelIsVisible: false
        )
        coordinator.apply(.generationStarted, for: slot)
        XCTAssertEqual(coordinator.state(for: slot), .generating)
        router = makeRouter(visible: fullscreenSource)
        router.handle(.generationFinished, for: slot)
        XCTAssertEqual(coordinator.state(for: slot), .idle)

        // A visible fullscreen companion acknowledges; a hidden companion
        // does not.
        let companionVisible = AttentionPresentation.Facts(
            slotID: slot,
            sessionIsLocked: true,
            pooledWebViewExists: true,
            webPresentationOwnsActiveInteraction: true,
            fullscreenSourceSlotID: UUID(),
            panelIsVisible: true,
            companionSlotID: slot,
            companionCurrentWebViewIsSlotWebView: true
        )
        let companionHidden = AttentionPresentation.Facts(
            slotID: slot,
            sessionIsLocked: true,
            pooledWebViewExists: true,
            fullscreenSourceSlotID: UUID(),
            panelIsVisible: false,
            companionSlotID: slot,
            companionCurrentWebViewIsSlotWebView: true
        )
        coordinator.apply(.generationStarted, for: slot)
        router = makeRouter(visible: companionVisible)
        router.handle(.generationFinished, for: slot)
        XCTAssertEqual(coordinator.state(for: slot), .idle)

        coordinator.apply(.generationStarted, for: slot)
        router = makeRouter(visible: companionHidden)
        router.handle(.generationFinished, for: slot)
        XCTAssertEqual(coordinator.state(for: slot), .ready)
    }

    // MARK: 4.8 Committed replacement

    func testCommittedTopLevelReplacementClearsReadyWithoutStaleProjection() throws {
        let (controller, coordinator, store, pool) = makeController(
            profiles: [spec(name: "ChatA", url: "https://chatgpt.com/chat-a")]
        )
        let slot = try profile(named: "ChatA", in: store)
        let webView = try makeResidentWebView(pool: pool, store: store, slotName: "ChatA")
        let bridge = try attentionBridge(pool: pool, slot: slot)
        let observer = try navigationObserver(of: webView)

        acceptBaseline(generating: true, bridge: bridge, webView: webView)
        acceptState(generating: false, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: slot.id), .ready)
        XCTAssertTrue(controller.debugIsProjectingReadyAttention(slotID: slot.id))

        // A committed top-level document replacement resets the runtime.
        observer.webView(webView, didCommit: nil)

        XCTAssertEqual(coordinator.state(for: slot.id), .idle)
        XCTAssertFalse(controller.debugIsProjectingReadyAttention(slotID: slot.id))
        XCTAssertTrue(pool.contains(slotID: slot.id))

        // A late state message from the superseded document is rejected.
        acceptState(generating: true, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: slot.id), .idle)
    }

    // MARK: 4.8 Current-site menu favicon projection

    func testCommittedSiteFlowsThroughPanelToMenuAndSelectionUsesResidentCommit() throws {
        let homeA = URL(string: "https://chatgpt.com/home")!
        let committedA = URL(string: "https://chatgpt.com/chat-a")!
        let homeB = URL(string: "https://docs.example.test/home")!
        let committedB = URL(string: "https://docs.example.test/page-b")!
        var committedURLs: [ObjectIdentifier: URL] = [:]
        let (controller, _, store, pool) = makeController(
            profiles: [
                (name: "ChatA", url: homeA),
                (name: "Docs", url: homeB)
            ],
            committedURLProvider: { webView in
                committedURLs[ObjectIdentifier(webView)]
            }
        )
        let statusItem = StatusItemController(
            onToggle: {},
            isVisible: { false },
            onSettings: {},
            onQuit: {},
            faviconLoader: { _, _ in }
        )
        controller.onSelectedSlotPresentationChange = { name, faviconURL in
            statusItem.setActiveWebApp(name: name, faviconURL: faviconURL)
        }
        statusItem.setActiveWebApp(
            name: controller.selectedSlotName,
            faviconURL: controller.selectedSlotFaviconURL
        )

        let slotA = try profile(named: "ChatA", in: store)
        XCTAssertTrue(store.select(id: slotA.id))
        let webViewA = try XCTUnwrap(pool.existingWebView(for: slotA.id))
        let homeAOrigin = try XCTUnwrap(StatusItemController.faviconOriginKey(for: homeA))
        let committedAOrigin = try XCTUnwrap(StatusItemController.faviconOriginKey(for: committedA))
        XCTAssertEqual(statusItem.debugSelectedFaviconOriginKey, homeAOrigin)

        // Provisional-style runtime changes do not enter the presentation route.
        let observerA = try navigationObserver(of: webViewA)
        observerA.webView(webViewA, didStartProvisionalNavigation: nil)
        observerA.webView(
            webViewA,
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        )
        XCTAssertEqual(statusItem.debugSelectedFaviconOriginKey, homeAOrigin)

        // A commit at the real WebKit delegate boundary drives the pool
        // observer, PanelController's selected-only projection, and finally
        // the real status item API. The provider supplies the committed
        // history fact because headless loadHTMLString does not populate a
        // WKBackForwardList item.
        committedURLs[ObjectIdentifier(webViewA)] = committedA
        observerA.webView(webViewA, didCommit: nil)
        XCTAssertEqual(pool.committedURL(for: slotA.id), committedA)
        XCTAssertEqual(statusItem.debugSelectedFaviconOriginKey, committedAOrigin)
        XCTAssertEqual(controller.selectedSlotFaviconURL, committedA)

        store.updateCurrentURL(
            id: slotA.id,
            url: URL(string: "https://persisted.example.test/restore-only")!
        )
        XCTAssertEqual(controller.selectedSlotFaviconURL, committedA)

        let slotB = try profile(named: "Docs", in: store)
        let webViewB = try XCTUnwrap(pool.existingWebView(for: slotB.id))
        let observerB = try navigationObserver(of: webViewB)
        committedURLs[ObjectIdentifier(webViewB)] = committedB
        observerB.webView(webViewB, didCommit: nil)
        XCTAssertEqual(pool.committedURL(for: slotB.id), committedB)

        // An inactive Slot's commit cannot hijack the selected menu item.
        XCTAssertEqual(statusItem.debugSelectedFaviconOriginKey, committedAOrigin)

        XCTAssertTrue(store.select(id: slotB.id))
        let committedBOrigin = try XCTUnwrap(StatusItemController.faviconOriginKey(for: committedB))
        XCTAssertEqual(statusItem.debugSelectedFaviconOriginKey, committedBOrigin)
        XCTAssertEqual(controller.selectedSlotFaviconURL, committedB)
    }

    func testCommittedHistoryBackForwardRedirectAndReturnHomeStayCommitBound() throws {
        let home = URL(string: "https://home.example.test/home")!
        let pageA = URL(string: "https://a.example.test/page-a")!
        let pageB = URL(string: "https://b.example.test/page-b")!
        let redirectC = URL(string: "https://c.example.test/redirect-c")!
        let redirectD = URL(string: "https://d.example.test/final")!
        var committedURLs: [ObjectIdentifier: URL] = [:]
        let (controller, _, store, pool) = makeController(
            profiles: [(name: "Site", url: home)],
            committedURLProvider: { webView in
                committedURLs[ObjectIdentifier(webView)]
            }
        )
        let statusItem = StatusItemController(
            onToggle: {},
            isVisible: { false },
            onSettings: {},
            onQuit: {},
            faviconLoader: { _, _ in }
        )
        controller.onSelectedSlotPresentationChange = { name, faviconURL in
            statusItem.setActiveWebApp(name: name, faviconURL: faviconURL)
        }
        statusItem.setActiveWebApp(
            name: controller.selectedSlotName,
            faviconURL: controller.selectedSlotFaviconURL
        )

        let slot = try profile(named: "Site", in: store)
        let webView = try XCTUnwrap(pool.existingWebView(for: slot.id))
        let observer = try navigationObserver(of: webView)
        let homeOrigin = try XCTUnwrap(StatusItemController.faviconOriginKey(for: home))
        let originA = try XCTUnwrap(StatusItemController.faviconOriginKey(for: pageA))
        let originB = try XCTUnwrap(StatusItemController.faviconOriginKey(for: pageB))
        let originD = try XCTUnwrap(StatusItemController.faviconOriginKey(for: redirectD))

        XCTAssertEqual(statusItem.debugSelectedFaviconOriginKey, homeOrigin)

        // A normal committed navigation establishes the first current page.
        committedURLs[ObjectIdentifier(webView)] = pageA
        observer.webView(webView, didCommit: nil)
        XCTAssertEqual(statusItem.debugSelectedFaviconOriginKey, originA)

        // Ordinary Forward and Back remain didCommit-owned.
        committedURLs[ObjectIdentifier(webView)] = pageB
        observer.webView(webView, didCommit: nil)
        XCTAssertEqual(statusItem.debugSelectedFaviconOriginKey, originB)
        committedURLs[ObjectIdentifier(webView)] = pageA
        observer.webView(webView, didCommit: nil)
        XCTAssertEqual(statusItem.debugSelectedFaviconOriginKey, originA)

        // Redirect intermediates never enter the menu route.
        observer.webView(webView, didStartProvisionalNavigation: nil)
        committedURLs[ObjectIdentifier(webView)] = redirectC
        observer.webView(webView, didStartProvisionalNavigation: nil)
        committedURLs[ObjectIdentifier(webView)] = redirectD
        XCTAssertEqual(statusItem.debugSelectedFaviconOriginKey, originA)

        observer.webView(webView, didCommit: nil)
        XCTAssertEqual(statusItem.debugSelectedFaviconOriginKey, originD)

        // Return Home mutates restore/navigation state before WebKit commits;
        // the menu remains on the last committed page until that boundary.
        controller.handle(.returnHome)
        XCTAssertEqual(
            store.activeProfile?.currentURL,
            home,
            "Return Home may update restore state before the live page commits"
        )
        XCTAssertEqual(statusItem.debugSelectedFaviconOriginKey, originD)

        committedURLs[ObjectIdentifier(webView)] = home
        observer.webView(webView, didCommit: nil)
        XCTAssertEqual(statusItem.debugSelectedFaviconOriginKey, homeOrigin)
    }

    func testColdRecreationUsesHomeUntilTheFirstLiveCommit() throws {
        let home = URL(string: "https://home.example.test/home")!
        let persistedCurrent = URL(string: "https://restored.example.test/page")!
        var committedURLs: [ObjectIdentifier: URL] = [:]
        let (controller, _, store, pool) = makeController(
            profiles: [
                (name: "Site", url: home),
                (name: "Other", url: URL(string: "https://other.example.test/")!)
            ],
            committedURLProvider: { webView in
                committedURLs[ObjectIdentifier(webView)]
            }
        )
        let statusItem = StatusItemController(
            onToggle: {},
            isVisible: { false },
            onSettings: {},
            onQuit: {},
            faviconLoader: { _, _ in }
        )
        controller.onSelectedSlotPresentationChange = { name, faviconURL in
            statusItem.setActiveWebApp(name: name, faviconURL: faviconURL)
        }
        statusItem.setActiveWebApp(
            name: controller.selectedSlotName,
            faviconURL: controller.selectedSlotFaviconURL
        )

        let site = try profile(named: "Site", in: store)
        store.updateCurrentURL(id: site.id, url: persistedCurrent)
        XCTAssertTrue(store.select(id: try profile(named: "Other", in: store).id))
        pool.release(slotID: site.id)

        // Selecting a cold/recreated Slot starts from persisted currentURL for
        // navigation, but no committed history item exists yet.
        XCTAssertTrue(store.select(id: site.id))
        let recreatedWebView = try XCTUnwrap(pool.existingWebView(for: site.id))
        let observer = try navigationObserver(of: recreatedWebView)
        let homeOrigin = try XCTUnwrap(StatusItemController.faviconOriginKey(for: home))
        let currentOrigin = try XCTUnwrap(
            StatusItemController.faviconOriginKey(for: persistedCurrent)
        )
        XCTAssertNil(pool.committedURL(for: site.id))
        XCTAssertEqual(statusItem.debugSelectedFaviconOriginKey, homeOrigin)

        committedURLs[ObjectIdentifier(recreatedWebView)] = persistedCurrent
        observer.webView(recreatedWebView, didCommit: nil)
        XCTAssertEqual(statusItem.debugSelectedFaviconOriginKey, currentOrigin)
        XCTAssertEqual(store.activeProfile?.currentURL, persistedCurrent)
    }

    func testInstantBackRequiresConfirmedCurrentHistoryItemAndRejectsStaleTarget() throws {
        let targetA = NSObject()
        let targetB = NSObject()
        let urlA = URL(string: "https://a.example.test/")!
        let urlB = URL(string: "https://b.example.test/")!

        // A request is insufficient: the current history item must be the
        // exact target, and the observed URL must agree with that item.
        XCTAssertNil(
            SlotNavigationObserver.confirmedInstantBackURL(
                expectedItemID: ObjectIdentifier(targetA),
                currentItemID: ObjectIdentifier(targetB),
                expectedURL: urlA,
                currentItemURL: urlB,
                observedURL: urlB
            )
        )
        XCTAssertNil(
            SlotNavigationObserver.confirmedInstantBackURL(
                expectedItemID: ObjectIdentifier(targetA),
                currentItemID: ObjectIdentifier(targetA),
                expectedURL: urlA,
                currentItemURL: urlA,
                observedURL: urlB
            )
        )
        XCTAssertEqual(
            SlotNavigationObserver.confirmedInstantBackURL(
                expectedItemID: ObjectIdentifier(targetA),
                currentItemID: ObjectIdentifier(targetA),
                expectedURL: urlA,
                currentItemURL: urlA,
                observedURL: urlA
            ),
            urlA
        )

        // The false branch is deliberately covered by the SDK-shaped policy
        // contract: ordinary didCommit remains the only projection boundary.
        let observer = SlotNavigationObserver(
            slotID: UUID(),
            webView: WKWebView(frame: .zero),
            websiteMode: .desktop,
            onURLChange: { _, _ in }
        )
        XCTAssertFalse(observer.isInstantBackActivationPending)
    }

    func testInstantBackDelegateRecordsOnlyInstantRequestsAndAlwaysAllowsNavigation() async throws {
        guard #available(macOS 26.0, *) else { return }

        let firstURL = URL(string: "x-ft-instant://history.example.test/first")!
        let secondURL = URL(string: "x-ft-instant://history.example.test/second")!
        let schemeHandler = InstantBackTestSchemeHandler()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: "x-ft-instant")
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 430, height: 820),
            configuration: configuration
        )
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 430, height: 820)
        )
        container.show(webView: webView)
        retainedContainers.append(container)

        var instantActivations = 0
        let observer = SlotNavigationObserver(
            slotID: UUID(),
            webView: webView,
            websiteMode: .desktop,
            onURLChange: { _, _ in },
            onInstantBackActivation: { _ in instantActivations += 1 }
        )

        webView.load(URLRequest(url: firstURL))
        let firstReady = try await waitUntil {
            webView.backForwardList.currentItem?.url == firstURL
        }
        XCTAssertTrue(firstReady)
        guard firstReady else { return }
        webView.load(URLRequest(url: secondURL))
        let secondReady = try await waitUntil {
            webView.backForwardList.currentItem?.url == secondURL
        }
        XCTAssertTrue(secondReady)
        guard secondReady else { return }

        let firstItem = try XCTUnwrap(webView.backForwardList.backItem)
        let secondItem = try XCTUnwrap(webView.backForwardList.currentItem)
        var instantDecision: Bool?
        observer.webView(
            webView,
            shouldGoTo: firstItem,
            willUseInstantBack: true,
            completionHandler: { instantDecision = $0 }
        )
        XCTAssertEqual(instantDecision, true)
        XCTAssertTrue(observer.isInstantBackActivationPending)
        XCTAssertEqual(instantActivations, 0)

        // A non-Instant request clears the older correlation and leaves the
        // ordinary didCommit path authoritative.
        var ordinaryDecision: Bool?
        observer.webView(
            webView,
            shouldGoTo: secondItem,
            willUseInstantBack: false,
            completionHandler: { ordinaryDecision = $0 }
        )
        XCTAssertEqual(ordinaryDecision, true)
        XCTAssertFalse(observer.isInstantBackActivationPending)
        XCTAssertEqual(instantActivations, 0)
    }

    // MARK: 4.8 Provisional navigation completion visibility

    func testVisibleCompletionDuringProvisionalNavigationResolvesIdleBeforeFailure() throws {
        let (controller, coordinator, store, pool) = makeController(
            profiles: [spec(name: "ChatA", url: "https://chatgpt.com/chat-a")]
        )
        let slot = try profile(named: "ChatA", in: store)
        let webView = try makeResidentWebView(pool: pool, store: store, slotName: "ChatA")
        let bridge = try attentionBridge(pool: pool, slot: slot)
        let observer = try navigationObserver(of: webView)

        controller.showFloatTabs()
        XCTAssertTrue(controller.isVisible)

        acceptBaseline(generating: true, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: slot.id), .generating)

        // The old accepted document remains authoritative until commit, so a
        // completion observed while its WebView is visible must resolve Idle
        // before any later provisional-failure callback can run.
        observer.webView(webView, didStartProvisionalNavigation: nil)
        acceptState(generating: false, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: slot.id), .idle)
        XCTAssertTrue(coordinator.readySlotIDs.isEmpty)
        XCTAssertFalse(controller.debugIsProjectingReadyAttention(slotID: slot.id))

        // Hiding before the provisional failure must not retroactively change
        // the visibility decision already made at completion time.
        controller.hideFloatTabs()
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut,
            userInfo: [
                NSURLErrorFailingURLErrorKey: URL(string: "https://chatgpt.com/c/abc")!
            ]
        )
        observer.webView(
            webView,
            didFailProvisionalNavigation: nil,
            withError: error
        )

        XCTAssertEqual(coordinator.state(for: slot.id), .idle)
        XCTAssertTrue(coordinator.readySlotIDs.isEmpty)
        XCTAssertFalse(controller.debugIsProjectingReadyAttention(slotID: slot.id))
    }

    func testHiddenCompletionDuringProvisionalNavigationRemainsReadyBeforeAndAfterFailure() throws {
        let (controller, coordinator, store, pool) = makeController(
            profiles: [spec(name: "ChatA", url: "https://chatgpt.com/chat-a")]
        )
        let slot = try profile(named: "ChatA", in: store)
        let webView = try makeResidentWebView(pool: pool, store: store, slotName: "ChatA")
        let bridge = try attentionBridge(pool: pool, slot: slot)
        let observer = try navigationObserver(of: webView)

        XCTAssertFalse(controller.isVisible)
        acceptBaseline(generating: true, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: slot.id), .generating)

        // The same accepted document is hidden, so its completion becomes
        // Ready immediately even though a provisional navigation is pending.
        observer.webView(webView, didStartProvisionalNavigation: nil)
        acceptState(generating: false, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: slot.id), .ready)
        XCTAssertEqual(coordinator.readySlotIDs, [slot.id])
        XCTAssertTrue(controller.debugIsProjectingReadyAttention(slotID: slot.id))

        // Physical presentation in this inactive test host does not own Web
        // interaction, so it must not acknowledge Ready. The failed
        // provisional navigation must not replay or clear that result.
        controller.showFloatTabs()
        XCTAssertEqual(coordinator.state(for: slot.id), .ready)
        XCTAssertEqual(coordinator.readySlotIDs, [slot.id])
        XCTAssertTrue(controller.debugIsProjectingReadyAttention(slotID: slot.id))

        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut,
            userInfo: [
                NSURLErrorFailingURLErrorKey: URL(string: "https://chatgpt.com/c/abc")!
            ]
        )
        observer.webView(
            webView,
            didFailProvisionalNavigation: nil,
            withError: error
        )

        XCTAssertEqual(coordinator.state(for: slot.id), .ready)
        XCTAssertEqual(coordinator.readySlotIDs, [slot.id])
        XCTAssertTrue(controller.debugIsProjectingReadyAttention(slotID: slot.id))
    }

    // MARK: 4.8 Release / rebuild stale callbacks

    func testReleaseInvalidatesBridgeRejectsStaleCallbacksAndRebuildStartsFresh() throws {
        let (controller, coordinator, store, pool) = makeController(
            profiles: [
                spec(name: "ChatA", url: "https://chatgpt.com/chat-a"),
                spec(name: "Plain", url: "https://example.com/plain")
            ]
        )
        let slot = try profile(named: "ChatA", in: store)
        let webView = try makeResidentWebView(pool: pool, store: store, slotName: "ChatA")
        let bridge = try attentionBridge(pool: pool, slot: slot)

        acceptBaseline(generating: true, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: slot.id), .generating)

        // Releasing the runtime invalidates its bridge and forwards exactly
        // one reset boundary through the real chain.
        pool.release(slotID: slot.id)
        XCTAssertFalse(pool.contains(slotID: slot.id))
        XCTAssertEqual(coordinator.state(for: slot.id), .idle)
        XCTAssertFalse(controller.debugIsProjectingReadyAttention(slotID: slot.id))

        // Stale callbacks from the invalidated bridge are rejected.
        acceptState(generating: false, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: slot.id), .idle)

        // A rebuilt runtime gets a fresh bridge: pre-baseline state messages
        // are rejected and a fresh idle baseline stays Idle.
        let rebuilt = pool.webView(for: slot)
        let freshBridge = try attentionBridge(pool: pool, slot: slot)
        XCTAssertFalse(freshBridge === bridge)
        acceptState(
            generating: true,
            bridge: freshBridge,
            webView: rebuilt,
            token: "fresh-bridge-document-token-01"
        )
        XCTAssertEqual(coordinator.state(for: slot.id), .idle)

        acceptBaseline(
            generating: false,
            bridge: freshBridge,
            webView: rebuilt,
            token: "fresh-bridge-document-token-01"
        )
        XCTAssertEqual(coordinator.state(for: slot.id), .idle)
        XCTAssertTrue(coordinator.readySlotIDs.isEmpty)
    }

    // MARK: 4.9 Media + attention independence (real authority state)

    func testMediaProtectionPersistsAfterAttentionResetAndReleasesWhenMediaStops() async throws {
        let (_, coordinator, store, pool) = makeController(
            profiles: [spec(name: "ChatMedia", url: "https://chatgpt.com/chat-media")]
        )
        let preUpdate = try profile(named: "ChatMedia", in: store)
        XCTAssertTrue(
            store.updateResourcePolicy(
                id: preUpdate.id,
                residencyPolicy: .warm,
                backgroundMediaPolicy: .allowBackgroundAudio
            )
        )
        let slot = try profile(named: "ChatMedia", in: store)
        XCTAssertEqual(slot.residencyPolicy, .warm)
        XCTAssertEqual(slot.backgroundMediaPolicy, .allowBackgroundAudio)
        let webView = try makeResidentWebView(pool: pool, store: store, slotName: "ChatMedia")
        let bridge = try attentionBridge(pool: pool, slot: slot)
        let observer = try navigationObserver(of: webView)

        var mediaPlaying = true
        let lifecycle = makeCompressedLifecycle(
            pool: pool,
            warmReleaseDelay: 0.03,
            warmResidentLimit: 2,
            attentionCoordinator: coordinator,
            mediaPlayingQuery: { _, completion in completion(mediaPlaying) },
            mediaProtectionPollDelay: 0.005
        )

        acceptBaseline(generating: true, bridge: bridge, webView: webView)
        makeInactive(lifecycle, profile: slot)
        XCTAssertTrue(lifecycle.mediaProtectedIDs.contains(slot.id))

        // Completion off-screen latches Ready through the real chain.
        acceptState(generating: false, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: slot.id), .ready)

        // A committed replacement ends attention protection, but media
        // protection alone must keep the runtime resident past the Warm TTL.
        observer.webView(webView, didCommit: nil)
        XCTAssertEqual(coordinator.state(for: slot.id), .idle)
        try await wait(milliseconds: 100)
        XCTAssertTrue(pool.contains(slotID: slot.id))
        XCTAssertTrue(lifecycle.mediaProtectedIDs.contains(slot.id))

        // Removing the remaining media protection allows the normal release.
        mediaPlaying = false
        let released = try await waitUntil {
            !pool.contains(slotID: slot.id)
        }
        XCTAssertTrue(released)
    }

    // MARK: 4.10 Relaunch / persistence

    func testRelaunchPersistsNoAttentionStateAndFreshCoordinatorStartsIdle() throws {
        let (controller, coordinator, store, pool) = makeController(
            profiles: [spec(name: "ChatA", url: "https://chatgpt.com/chat-a")]
        )
        let slot = try profile(named: "ChatA", in: store)
        let webView = try makeResidentWebView(pool: pool, store: store, slotName: "ChatA")
        let bridge = try attentionBridge(pool: pool, slot: slot)

        acceptBaseline(generating: true, bridge: bridge, webView: webView)
        acceptState(generating: false, bridge: bridge, webView: webView)
        XCTAssertEqual(coordinator.state(for: slot.id), .ready)
        XCTAssertTrue(controller.debugIsProjectingReadyAttention(slotID: slot.id))

        // The persisted document contains no attention state of any kind.
        let repositoryURL = try XCTUnwrap(repositoryURLs.first)
        let data = try Data(contentsOf: repositoryURL)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let tainted = try Self.recursiveKeys(in: json).filter {
            let lowered = $0.lowercased()
            return lowered.contains("attention")
                || lowered == "generating"
                || lowered == "ready"
                || lowered.contains("protected")
        }
        XCTAssertTrue(
            tainted.isEmpty,
            "persisted store leaked attention keys: \(tainted)"
        )
        XCTAssertEqual(json.keys.sorted(), ["lastActiveTabID", "profiles", "version"])

        // A relaunch rebuilds every runtime object from the persisted store:
        // the fresh coordinator starts the same Slot at Idle with no Ready
        // projection.
        let relaunchedStore = TabStore(
            repository: ProfileRepository(fileURL: repositoryURL)
        )
        XCTAssertEqual(relaunchedStore.activeTabID, slot.id)
        let freshCoordinator = WebAttentionCoordinator()
        let (freshController, _, _, _) = makeController(
            store: relaunchedStore,
            attentionCoordinator: freshCoordinator
        )
        XCTAssertEqual(freshCoordinator.state(for: slot.id), .idle)
        XCTAssertTrue(freshCoordinator.readySlotIDs.isEmpty)
        XCTAssertFalse(freshController.debugIsProjectingReadyAttention(slotID: slot.id))
    }

    // MARK: 4.11 Non-ChatGPT isolation

    func testUnsupportedOriginAndFrameLeaveAttentionAndResidencyUnchanged() throws {
        let (controller, coordinator, store, pool) = makeController(
            profiles: [spec(name: "Plain", url: "https://example.com/plain")]
        )
        let slot = try profile(named: "Plain", in: store)
        let webView = try makeResidentWebView(pool: pool, store: store, slotName: "Plain")
        let bridge = try attentionBridge(pool: pool, slot: slot)

        // An unsupported host, an unsupported scheme, and a subframe message
        // are all rejected by the real bridge on the real pool chain.
        bridge.accept(
            payload: baselinePayload(generating: true),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "example.com",
            originProtocol: "https"
        )
        bridge.accept(
            payload: baselinePayload(generating: true),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "about"
        )
        bridge.accept(
            payload: baselinePayload(generating: true),
            messageWebView: webView,
            isMainFrame: false,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )

        XCTAssertEqual(coordinator.state(for: slot.id), .idle)
        XCTAssertTrue(coordinator.readySlotIDs.isEmpty)
        XCTAssertFalse(controller.debugIsProjectingReadyAttention(slotID: slot.id))
        XCTAssertTrue(pool.contains(slotID: slot.id))
        XCTAssertEqual(controller.debugPendingColdReleaseCount, 0)
    }

    // MARK: 4.12 Factory user-content seam

    func testFactorySeamUsesConfiguredUserContentController() {
        var receivedControllers: [WKUserContentController] = []
        let webView = WebViewFactory.makeWebView { controller in
            receivedControllers.append(controller)
        }

        // The pre-creation seam runs exactly once and the Factory builds the
        // WKWebView on that same configured user content controller.
        XCTAssertEqual(receivedControllers.count, 1)
        XCTAssertTrue(
            webView.configuration.userContentController === receivedControllers.first
        )
    }

    // MARK: - Harness

    private func spec(name: String, url: String) -> (name: String, url: URL) {
        (name, URL(string: url)!)
    }

    /// Builds the real production composition: a real persisted `TabStore`,
    /// a real `WebViewPool` (loads stubbed at the URLRequest boundary), and
    /// a real `PanelController` whose router, lifecycle coordinator, and rail
    /// projection are the production objects. The attention coordinator is
    /// injected so the test can read the same authority the wiring drives.
    private func makeController(
        profiles: [(name: String, url: URL)]? = nil,
        store: TabStore? = nil,
        attentionCoordinator: WebAttentionCoordinator = WebAttentionCoordinator(),
        committedURLProvider: WebViewPool.CommittedURLProvider? = nil
    ) -> (PanelController, WebAttentionCoordinator, TabStore, WebViewPool) {
        let tabStore = store ?? makeTabStore(profiles: profiles ?? [])
        let pool = makePool(committedURLProvider: committedURLProvider)
        let controller = PanelController(
            tabStore: tabStore,
            webViewPool: pool,
            attentionCoordinator: attentionCoordinator,
            frameStore: PanelFrameStore(),
            preferencesStore: AppPreferencesStore()
        )
        retainedControllers.append(controller)
        return (controller, attentionCoordinator, tabStore, pool)
    }

    private func makeTabStore(
        profiles: [(name: String, url: URL)]
    ) -> TabStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsStageF-\(UUID().uuidString).json")
        repositoryURLs.append(url)
        let store = TabStore(repository: ProfileRepository(fileURL: url))
        for spec in profiles {
            _ = store.add(name: spec.name, homeURL: spec.url)
        }
        return store
    }

    private func makePool(
        committedURLProvider: WebViewPool.CommittedURLProvider? = nil
    ) -> WebViewPool {
        WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, _ in },
            isSlotActive: { _ in false },
            committedURLProvider: committedURLProvider
        )
    }

    private func makeCompressedLifecycle(
        pool: WebViewPool,
        warmReleaseDelay: TimeInterval,
        warmResidentLimit: Int,
        attentionCoordinator: WebAttentionCoordinator,
        mediaPlayingQuery: SlotLifecycleCoordinator.MediaPlayingQuery? = nil,
        mediaProtectionPollDelay: TimeInterval = 0.01
    ) -> SlotLifecycleCoordinator {
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 430, height: 820)
        )
        retainedContainers.append(container)
        return SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            coldReleaseDelay: 30,
            warmReleaseDelay: warmReleaseDelay,
            hiddenActiveGraceDelay: 120,
            mediaProtectionPollDelay: mediaProtectionPollDelay,
            warmResidentLimit: warmResidentLimit,
            mediaPlayingQuery: mediaPlayingQuery,
            attentionProtectionQuery: { slotID in
                attentionCoordinator.isAttentionProtected(slotID)
            },
            installsMemoryPressureSource: false
        )
    }

    private func makeInactive(
        _ lifecycle: SlotLifecycleCoordinator,
        profile: WebAppProfile
    ) {
        lifecycle.setPanelVisible(true, activeProfile: nil)
        lifecycle.activate(profile: profile)
        lifecycle.deactivate(profile: profile)
    }

    private func profile(
        named name: String,
        in store: TabStore
    ) throws -> WebAppProfile {
        try XCTUnwrap(store.profiles.first { $0.name == name })
    }

    private func setResidency(
        _ policy: SlotResidencyPolicy,
        for name: String,
        in store: TabStore
    ) {
        guard let slot = store.profiles.first(where: { $0.name == name }) else {
            return
        }
        XCTAssertTrue(store.updateResourcePolicy(id: slot.id, residencyPolicy: policy))
    }

    /// Materializes the Slot's real pooled runtime and bridge the way the
    /// production controller does (by making the slot the active tab), then
    /// returns the live WKWebView.
    private func makeResidentWebView(
        pool: WebViewPool,
        store: TabStore,
        slotName: String
    ) throws -> WKWebView {
        try select(named: slotName, in: store)
        let slot = try profile(named: slotName, in: store)
        return try XCTUnwrap(pool.existingWebView(for: slot.id))
    }

    /// Materializes a background Slot's real pooled runtime and bridge via
    /// the pool's public API without presenting it, for lifecycle-pressure
    /// controls that must be resident but inactive.
    private func materializeRuntime(
        pool: WebViewPool,
        store: TabStore,
        slotName: String
    ) throws -> (profile: WebAppProfile, webView: WKWebView) {
        let slot = try profile(named: slotName, in: store)
        let webView = pool.webView(for: slot)
        XCTAssertTrue(pool.contains(slotID: slot.id))
        return (slot, webView)
    }

    private func select(
        named name: String,
        in store: TabStore
    ) throws {
        let slot = try profile(named: name, in: store)
        XCTAssertTrue(store.select(id: slot.id))
    }

    private func attentionBridge(
        pool: WebViewPool,
        slot: WebAppProfile
    ) throws -> ChatGPTAttentionBridge {
        try XCTUnwrap(pool.attentionBridge(for: slot.id))
    }

    /// The real pool-installed navigation observer for a pooled WKWebView —
    /// the object WebKit would call for navigation and termination events.
    private func navigationObserver(
        of webView: WKWebView
    ) throws -> SlotNavigationObserver {
        try XCTUnwrap(
            webView.navigationDelegate as? SlotNavigationObserver
        )
    }

    private func baselinePayload(generating: Bool) -> ChatGPTBridgePayload {
        ChatGPTBridgePayload(
            version: ChatGPTBridgePayload.currentVersion,
            kind: ChatGPTBridgePayload.baselineKind,
            token: "cross-feature-document-token",
            generating: generating
        )
    }

    /// Drives the REAL bridge acceptance pipeline (origin, frame, identity,
    /// epoch validation) on the pool-owned bridge.
    private func acceptBaseline(
        generating: Bool,
        bridge: ChatGPTAttentionBridge,
        webView: WKWebView,
        token: String = "cross-feature-document-token"
    ) {
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: ChatGPTBridgePayload.currentVersion,
                kind: ChatGPTBridgePayload.baselineKind,
                token: token,
                generating: generating
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
    }

    private func acceptState(
        generating: Bool,
        bridge: ChatGPTAttentionBridge,
        webView: WKWebView,
        token: String = "cross-feature-document-token"
    ) {
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: ChatGPTBridgePayload.currentVersion,
                kind: ChatGPTBridgePayload.stateKind,
                token: token,
                generating: generating
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
    }

    private func wait(milliseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    @discardableResult
    private func waitUntil(
        timeoutMilliseconds: UInt64 = 1000,
        pollMilliseconds: UInt64 = 5,
        condition: () -> Bool
    ) async throws -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds
            + timeoutMilliseconds * 1_000_000

        while true {
            if condition() {
                return true
            }
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                return false
            }
            try await wait(milliseconds: pollMilliseconds)
        }
    }

    private static func recursiveKeys(in object: [String: Any]) throws -> [String] {
        var keys = Array(object.keys)
        for value in object.values {
            if let nested = value as? [String: Any] {
                keys.append(contentsOf: try recursiveKeys(in: nested))
            } else if let array = value as? [Any] {
                for element in array {
                    if let nested = element as? [String: Any] {
                        keys.append(contentsOf: try recursiveKeys(in: nested))
                    }
                }
            }
        }
        return keys
    }
}

@MainActor
private final class InstantBackTestSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let url = urlSchemeTask.request.url ?? URL(string: "x-ft-instant://history.example.test/")!
        let body = "<!doctype html><html><body>\(url.path)</body></html>"
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        ) else {
            urlSchemeTask.didFailWithError(
                NSError(domain: "InstantBackTestSchemeHandler", code: 1)
            )
            return
        }
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(Data(body.utf8))
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
