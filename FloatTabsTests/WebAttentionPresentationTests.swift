import AppKit
import XCTest
@testable import FloatTabs

@MainActor
final class WebAttentionPresentationTests: XCTestCase {
    private var coordinator: WebAttentionCoordinator!
    private var slotA: UUID!
    private var slotB: UUID!

    override func setUp() {
        super.setUp()
        coordinator = WebAttentionCoordinator()
        slotA = UUID()
        slotB = UUID()
    }

    override func tearDown() {
        coordinator = nil
        slotA = nil
        slotB = nil
        super.tearDown()
    }

    // MARK: - Observation routing (production router + coordinator)

    func testGenerationStartedRoutesIdleToGenerating() {
        let router = makeRouter()

        router.handle(.generationStarted, for: slotA)

        XCTAssertEqual(coordinator.state(for: slotA), .generating)
    }

    func testGenerationFinishedWhileNotUserVisibleRoutesToReady() {
        let router = makeRouter(visible: false)
        router.handle(.generationStarted, for: slotA)

        router.handle(.generationFinished, for: slotA)

        XCTAssertEqual(coordinator.state(for: slotA), .ready)
    }

    func testHiddenCompletionProjectsReadySlotThroughMenuPresentation() {
        let router = makeRouter(visible: false)
        router.handle(.generationStarted, for: slotA)
        router.handle(.generationFinished, for: slotA)

        let menu = StatusItemController.attentionPresentation(
            readyCount: coordinator.readySlotIDs.count,
            floatTabsVisible: false
        )

        XCTAssertEqual(coordinator.readySlotIDs, [slotA])
        XCTAssertEqual(menu.badge, .dot)
    }

    func testVisibilityProjectionChangesWithoutChangingReadyStates() {
        let router = makeRouter(visible: false)
        router.handle(.generationStarted, for: slotA)
        router.handle(.generationFinished, for: slotA)
        router.handle(.generationStarted, for: slotB)
        router.handle(.generationFinished, for: slotB)

        let visible = StatusItemController.attentionPresentation(
            readyCount: coordinator.readySlotIDs.count,
            floatTabsVisible: true
        )
        let hidden = StatusItemController.attentionPresentation(
            readyCount: coordinator.readySlotIDs.count,
            floatTabsVisible: false
        )

        XCTAssertEqual(visible.badge, .none)
        XCTAssertEqual(hidden.badge, .count("2"))
        XCTAssertEqual(coordinator.readySlotIDs, [slotA, slotB])
    }

    func testGenerationFinishedWhileUserVisibleRoutesToIdle() {
        let router = makeRouter(visible: true)
        router.handle(.generationStarted, for: slotA)

        router.handle(.generationFinished, for: slotA)

        XCTAssertEqual(coordinator.state(for: slotA), .idle)
    }

    func testRuntimeResetRoutesGeneratingAndReadyToIdle() {
        let router = makeRouter()
        router.handle(.generationStarted, for: slotA)
        coordinator.apply(.generationStarted, for: slotB)
        coordinator.apply(.generationFinished(userVisible: false), for: slotB)

        router.handle(.runtimeReset, for: slotA)
        router.handle(.runtimeReset, for: slotB)

        XCTAssertEqual(coordinator.state(for: slotA), .idle)
        XCTAssertEqual(coordinator.state(for: slotB), .idle)
    }

    // MARK: - Visibility decision (production facts + decision)

    func testSelectedButHiddenPresentationIsNotVisible() {
        // Logically current and identity-matched, but the source window is
        // not physically visible.
        let facts = AttentionPresentation.Facts(
            slotID: slotA,
            pooledWebViewExists: true,
            normalCurrentWebViewIsSlotWebView: true,
            sourceWindowIsVisible: false
        )

        XCTAssertFalse(AttentionPresentation.isUserVisible(facts))
    }

    func testNormalVisibleSourceWithMatchingIdentityIsVisible() {
        let facts = AttentionPresentation.Facts(
            slotID: slotA,
            pooledWebViewExists: true,
            normalCurrentWebViewIsSlotWebView: true,
            sourceWindowIsVisible: true
        )

        XCTAssertTrue(AttentionPresentation.isUserVisible(facts))
    }

    func testAttachedInactiveHotWebViewIsNotVisible() {
        // A live pooled runtime that is not the current presentation — an
        // inactive attached Hot host — is never user-visible.
        let facts = AttentionPresentation.Facts(
            slotID: slotA,
            pooledWebViewExists: true,
            normalCurrentWebViewIsSlotWebView: false,
            sourceWindowIsVisible: true
        )

        XCTAssertFalse(AttentionPresentation.isUserVisible(facts))
    }

    func testWrongWebViewIdentityIsNotVisibleWhileCorrectIdentityIs() {
        let wrongIdentity = AttentionPresentation.Facts(
            slotID: slotA,
            pooledWebViewExists: true,
            normalCurrentWebViewIsSlotWebView: false,
            sourceWindowIsVisible: true
        )
        let correctIdentity = AttentionPresentation.Facts(
            slotID: slotB,
            pooledWebViewExists: true,
            normalCurrentWebViewIsSlotWebView: true,
            sourceWindowIsVisible: true
        )

        XCTAssertFalse(AttentionPresentation.isUserVisible(wrongIdentity))
        XCTAssertTrue(AttentionPresentation.isUserVisible(correctIdentity))
    }

    func testFullscreenSourceIsVisibleWhileSessionLockedAndShellHidden() {
        let facts = AttentionPresentation.Facts(
            slotID: slotA,
            sessionIsLocked: true,
            pooledWebViewExists: true,
            normalCurrentWebViewIsSlotWebView: false,
            sourceWindowIsVisible: false,
            fullscreenSourceSlotID: slotA,
            panelIsVisible: false
        )
        let otherSlotFacts = AttentionPresentation.Facts(
            slotID: slotB,
            sessionIsLocked: true,
            fullscreenSourceSlotID: slotA
        )

        XCTAssertTrue(AttentionPresentation.isUserVisible(facts))
        XCTAssertFalse(AttentionPresentation.isUserVisible(otherSlotFacts))
    }

    func testFullscreenCompanionIsVisibleWhenPanelVisibleAndIdentityMatches() {
        let facts = AttentionPresentation.Facts(
            slotID: slotA,
            sessionIsLocked: true,
            pooledWebViewExists: true,
            fullscreenSourceSlotID: slotB,
            panelIsVisible: true,
            companionSlotID: slotA,
            companionCurrentWebViewIsSlotWebView: true
        )

        XCTAssertTrue(AttentionPresentation.isUserVisible(facts))
    }

    func testFullscreenCompanionIsNotVisibleWhilePanelPhysicallyHidden() {
        let facts = AttentionPresentation.Facts(
            slotID: slotA,
            sessionIsLocked: true,
            pooledWebViewExists: true,
            fullscreenSourceSlotID: slotB,
            panelIsVisible: false,
            companionSlotID: slotA,
            companionCurrentWebViewIsSlotWebView: true
        )

        XCTAssertFalse(AttentionPresentation.isUserVisible(facts))
    }

    // MARK: - Acknowledgement through the production decision path

    func testReadySlotStaysReadyWhenSelectedWhileHidden() {
        driveToReady()
        let hidden = AttentionPresentation.Facts(
            slotID: slotA,
            pooledWebViewExists: true,
            normalCurrentWebViewIsSlotWebView: true,
            sourceWindowIsVisible: false
        )

        coordinator.acknowledge(
            slotID: slotA,
            userVisible: AttentionPresentation.isUserVisible(hidden)
        )

        XCTAssertEqual(coordinator.state(for: slotA), .ready)
        XCTAssertEqual(coordinator.readySlotIDs, [slotA])
    }

    func testPresentedNormalReadySlotAcknowledgesToIdle() {
        driveToReady()
        let presented = AttentionPresentation.Facts(
            slotID: slotA,
            pooledWebViewExists: true,
            normalCurrentWebViewIsSlotWebView: true,
            sourceWindowIsVisible: true
        )

        coordinator.acknowledge(
            slotID: slotA,
            userVisible: AttentionPresentation.isUserVisible(presented)
        )

        XCTAssertEqual(coordinator.state(for: slotA), .idle)
    }

    func testHiddenReadySlotAcknowledgesOnlyAfterPhysicalPresentation() {
        driveToReady()
        let hidden = AttentionPresentation.Facts(
            slotID: slotA,
            pooledWebViewExists: true,
            normalCurrentWebViewIsSlotWebView: true,
            sourceWindowIsVisible: false
        )
        let presented = AttentionPresentation.Facts(
            slotID: slotA,
            pooledWebViewExists: true,
            normalCurrentWebViewIsSlotWebView: true,
            sourceWindowIsVisible: true
        )

        coordinator.acknowledge(
            slotID: slotA,
            userVisible: AttentionPresentation.isUserVisible(hidden)
        )
        XCTAssertEqual(coordinator.state(for: slotA), .ready)

        coordinator.acknowledge(
            slotID: slotA,
            userVisible: AttentionPresentation.isUserVisible(presented)
        )
        XCTAssertEqual(coordinator.state(for: slotA), .idle)
    }

    func testPresentedCompanionReadySlotAcknowledgesToIdle() {
        driveToReady()
        let companionPresented = AttentionPresentation.Facts(
            slotID: slotA,
            sessionIsLocked: true,
            pooledWebViewExists: true,
            fullscreenSourceSlotID: slotB,
            panelIsVisible: true,
            companionSlotID: slotA,
            companionCurrentWebViewIsSlotWebView: true
        )

        coordinator.acknowledge(
            slotID: slotA,
            userVisible: AttentionPresentation.isUserVisible(companionPresented)
        )

        XCTAssertEqual(coordinator.state(for: slotA), .idle)
    }

    func testAcknowledgementDerivesHiddenMenuCountFromRemainingReadySlots() {
        let router = makeRouter(visible: false)
        router.handle(.generationStarted, for: slotA)
        router.handle(.generationFinished, for: slotA)
        router.handle(.generationStarted, for: slotB)
        router.handle(.generationFinished, for: slotB)

        let presentedA = AttentionPresentation.Facts(
            slotID: slotA,
            pooledWebViewExists: true,
            normalCurrentWebViewIsSlotWebView: true,
            sourceWindowIsVisible: true
        )
        coordinator.acknowledge(
            slotID: slotA,
            userVisible: AttentionPresentation.isUserVisible(presentedA)
        )

        let hiddenMenu = StatusItemController.attentionPresentation(
            readyCount: coordinator.readySlotIDs.count,
            floatTabsVisible: false
        )

        XCTAssertEqual(coordinator.state(for: slotA), .idle)
        XCTAssertEqual(coordinator.state(for: slotB), .ready)
        XCTAssertEqual(hiddenMenu.badge, .dot)
    }

    func testStatusMenuPresentationDoesNotAcknowledgeReady() {
        driveToReady()
        let controller = StatusItemController(
            onToggle: {},
            isVisible: { false },
            onSettings: {},
            onQuit: {}
        )

        controller.menuWillOpen(NSMenu())
        controller.menuDidClose(NSMenu())

        XCTAssertEqual(coordinator.state(for: slotA), .ready)
        XCTAssertEqual(coordinator.readySlotIDs, [slotA])
    }

    // MARK: - Isolation, cleanup, persistence boundary

    func testRouterKeepsSlotsIsolated() {
        let router = makeRouter(visible: false)
        router.handle(.generationStarted, for: slotA)
        router.handle(.generationStarted, for: slotB)
        router.handle(.generationFinished, for: slotA)
        router.handle(.runtimeReset, for: slotB)

        XCTAssertEqual(coordinator.state(for: slotA), .ready)
        XCTAssertEqual(coordinator.state(for: slotB), .idle)
        XCTAssertEqual(coordinator.readySlotIDs, [slotA])
    }

    func testPermanentRemovalClearsAttentionBookkeeping() {
        let router = makeRouter(visible: false)
        router.handle(.generationStarted, for: slotA)
        router.handle(.generationFinished, for: slotA)
        XCTAssertEqual(coordinator.state(for: slotA), .ready)

        coordinator.removeSlot(slotA)

        XCTAssertEqual(coordinator.state(for: slotA), .idle)
        XCTAssertFalse(coordinator.isAttentionProtected(slotA))
        XCTAssertTrue(coordinator.readySlotIDs.isEmpty)
    }

    func testStateReplacementClearsOldSlotAttentionBookkeeping() {
        let router = makeRouter(visible: false)
        router.handle(.generationStarted, for: slotA)
        router.handle(.generationFinished, for: slotA)
        router.handle(.generationStarted, for: slotB)
        XCTAssertEqual(coordinator.state(for: slotA), .ready)
        XCTAssertEqual(coordinator.state(for: slotB), .generating)

        // Backup restore releases each runtime (routing its reset) and then
        // drops the old identities entirely.
        router.handle(.runtimeReset, for: slotB)
        coordinator.removeSlot(slotA)
        coordinator.removeSlot(slotB)

        XCTAssertTrue(coordinator.readySlotIDs.isEmpty)
        XCTAssertEqual(coordinator.state(for: slotA), .idle)
        XCTAssertEqual(coordinator.state(for: slotB), .idle)

        // A replacement identity starts at implicit Idle.
        let replacement = UUID()
        XCTAssertEqual(coordinator.state(for: replacement), .idle)
        XCTAssertTrue(coordinator.readySlotIDs.isEmpty)
    }

    func testWebAppProfileAndBackupEncodingCarryNoAttentionData() throws {
        var profile = WebAppProfile(
            order: 0,
            name: "ChatGPT",
            homeURL: URL(string: "https://chatgpt.com/")!
        )
        profile.currentURL = URL(string: "https://chatgpt.com/c/abc")!
        let data = try JSONEncoder().encode(profile)

        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let allKeys = try Self.recursiveKeys(in: json)
        let attentionTainted = allKeys.filter {
            let lowered = $0.lowercased()
            return lowered.contains("attention")
                || lowered == "generating"
                || lowered == "ready"
                || lowered.contains("protected")
        }
        XCTAssertTrue(
            attentionTainted.isEmpty,
            "persisted profile schema leaked attention keys: \(attentionTainted)"
        )
    }

    // MARK: - Helpers

    private func makeRouter(
        visible: Bool = false
    ) -> WebAttentionObservationRouter {
        WebAttentionObservationRouter(
            attentionCoordinator: coordinator,
            isUserVisible: { _ in visible }
        )
    }

    private func driveToReady() {
        let router = makeRouter(visible: false)
        router.handle(.generationStarted, for: slotA)
        router.handle(.generationFinished, for: slotA)
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
