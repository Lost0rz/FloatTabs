import AppKit
import XCTest
@testable import FloatTabs

@MainActor
final class WebAttentionIndicatorTests: XCTestCase {
    func testIdleAndGeneratingSlotsHaveNoReadyDot() {
        let coordinator = WebAttentionCoordinator()
        let profile = makeProfile(name: "GPT")
        let (_, zone) = makeZoneHarness()
        zone.apply(profiles: [profile], activeTabID: profile.id)
        synchronize(zone, from: coordinator)

        let tab = try! XCTUnwrap(zone.tabView(for: profile.id))
        XCTAssertFalse(tab.isShowingReadyAttention)

        coordinator.apply(.generationStarted, for: profile.id)
        synchronize(zone, from: coordinator)
        XCTAssertFalse(tab.isShowingReadyAttention)
    }

    func testGenerationCompletionProjectsReadyDotAndNewGenerationClearsIt() {
        let coordinator = WebAttentionCoordinator()
        let profile = makeProfile(name: "GPT")
        let (_, zone) = makeZoneHarness()
        zone.apply(profiles: [profile], activeTabID: profile.id)

        coordinator.apply(.generationStarted, for: profile.id)
        coordinator.apply(.generationFinished(userVisible: false), for: profile.id)
        synchronize(zone, from: coordinator)

        let tab = try! XCTUnwrap(zone.tabView(for: profile.id))
        XCTAssertTrue(tab.isShowingReadyAttention)

        coordinator.apply(.generationStarted, for: profile.id)
        synchronize(zone, from: coordinator)
        XCTAssertFalse(tab.isShowingReadyAttention)
    }

    func testReadyAcknowledgementAndRuntimeResetClearTheDot() {
        let coordinator = WebAttentionCoordinator()
        let profile = makeProfile(name: "GPT")
        let (_, zone) = makeZoneHarness()
        zone.apply(profiles: [profile], activeTabID: profile.id)
        let tab = try! XCTUnwrap(zone.tabView(for: profile.id))

        coordinator.apply(.generationStarted, for: profile.id)
        coordinator.apply(.generationFinished(userVisible: false), for: profile.id)
        synchronize(zone, from: coordinator)
        XCTAssertTrue(tab.isShowingReadyAttention)

        coordinator.acknowledge(slotID: profile.id, userVisible: true)
        synchronize(zone, from: coordinator)
        XCTAssertFalse(tab.isShowingReadyAttention)

        coordinator.apply(.generationStarted, for: profile.id)
        coordinator.apply(.generationFinished(userVisible: false), for: profile.id)
        coordinator.apply(.runtimeReset, for: profile.id)
        synchronize(zone, from: coordinator)
        XCTAssertFalse(tab.isShowingReadyAttention)
    }

    func testMultipleSlotsOnlyReadyIDsDisplayDots() {
        let coordinator = WebAttentionCoordinator()
        let ready = makeProfile(name: "Ready")
        let idle = makeProfile(name: "Idle")
        let generating = makeProfile(name: "Generating")
        let (_, zone) = makeZoneHarness()
        zone.apply(profiles: [ready, idle, generating], activeTabID: ready.id)

        coordinator.apply(.generationStarted, for: ready.id)
        coordinator.apply(.generationFinished(userVisible: false), for: ready.id)
        coordinator.apply(.generationStarted, for: generating.id)
        synchronize(zone, from: coordinator)

        XCTAssertTrue(try! XCTUnwrap(zone.tabView(for: ready.id)).isShowingReadyAttention)
        XCTAssertFalse(try! XCTUnwrap(zone.tabView(for: idle.id)).isShowingReadyAttention)
        XCTAssertFalse(try! XCTUnwrap(zone.tabView(for: generating.id)).isShowingReadyAttention)
    }

    func testReadyProjectionReplacesInsteadOfAccumulating() {
        let first = makeProfile(name: "First")
        let second = makeProfile(name: "Second")
        let (_, zone) = makeZoneHarness()
        zone.apply(profiles: [first, second], activeTabID: first.id)

        zone.setReadySlotIDs([first.id])
        XCTAssertTrue(try! XCTUnwrap(zone.tabView(for: first.id)).isShowingReadyAttention)
        XCTAssertFalse(try! XCTUnwrap(zone.tabView(for: second.id)).isShowingReadyAttention)

        zone.setReadySlotIDs([second.id])
        XCTAssertFalse(try! XCTUnwrap(zone.tabView(for: first.id)).isShowingReadyAttention)
        XCTAssertTrue(try! XCTUnwrap(zone.tabView(for: second.id)).isShowingReadyAttention)

        zone.setReadySlotIDs([])
        XCTAssertFalse(try! XCTUnwrap(zone.tabView(for: first.id)).isShowingReadyAttention)
        XCTAssertFalse(try! XCTUnwrap(zone.tabView(for: second.id)).isShowingReadyAttention)
    }

    func testRemovedSlotHasNoVisibleTabOrReadyDot() {
        let removed = makeProfile(name: "Removed")
        let remaining = makeProfile(name: "Remaining")
        let (_, zone) = makeZoneHarness()
        zone.apply(profiles: [removed, remaining], activeTabID: remaining.id)
        zone.setReadySlotIDs([removed.id])

        zone.apply(profiles: [remaining], activeTabID: remaining.id)

        XCTAssertNil(zone.tabView(for: removed.id))
        XCTAssertNotNil(zone.tabView(for: remaining.id))
    }

    func testRailReapplyKeepsReadyProjectionOnRecreatedAndUpdatedTabs() {
        let coordinator = WebAttentionCoordinator()
        let profile = makeProfile(name: "GPT")
        let (_, zone) = makeZoneHarness()
        coordinator.apply(.generationStarted, for: profile.id)
        coordinator.apply(.generationFinished(userVisible: false), for: profile.id)

        zone.apply(profiles: [profile], activeTabID: profile.id)
        synchronize(zone, from: coordinator)
        XCTAssertTrue(try! XCTUnwrap(zone.tabView(for: profile.id)).isShowingReadyAttention)

        zone.apply(profiles: [profile], activeTabID: nil)
        XCTAssertTrue(try! XCTUnwrap(zone.tabView(for: profile.id)).isShowingReadyAttention)
    }

    func testReadyDotUsesFaviconGeometryAtRestAndMagnifiedWidths() {
        let profile = makeProfile(name: "GPT")
        let (_, zone) = makeZoneHarness()
        zone.apply(profiles: [profile], activeTabID: profile.id)
        zone.setReadySlotIDs([profile.id])
        zone.layoutSubtreeIfNeeded()

        let tab = try! XCTUnwrap(zone.tabView(for: profile.id))
        let restingWidth = tab.frame.width
        let restingIconFrame = tab.iconFrame
        let restingDotFrame = tab.readyAttentionFrame
        XCTAssertEqual(restingWidth, ExternalTabMetrics.collapsedWidth, accuracy: 0.001)
        assertReadyDot(
            restingDotFrame,
            isAttachedTo: restingIconFrame,
            file: #filePath,
            line: #line
        )

        tab.setHovered(true)
        zone.needsLayout = true
        zone.layoutSubtreeIfNeeded()

        let magnifiedIconFrame = tab.iconFrame
        let magnifiedDotFrame = tab.readyAttentionFrame
        XCTAssertEqual(tab.frame.width, ExternalTabMetrics.hoverWidth, accuracy: 0.001)
        XCTAssertEqual(magnifiedIconFrame, restingIconFrame)
        XCTAssertEqual(
            magnifiedDotFrame.offsetBy(
                dx: -magnifiedIconFrame.minX,
                dy: -magnifiedIconFrame.minY
            ),
            restingDotFrame.offsetBy(
                dx: -restingIconFrame.minX,
                dy: -restingIconFrame.minY
            )
        )
        XCTAssertLessThan(magnifiedDotFrame.maxX, tab.bounds.maxX)
    }

    func testReadyDotDoesNotChangeTabWidthOrDockMagnification() {
        let tab = ExternalWebAppTabView(slotID: UUID())
        tab.frame = NSRect(
            x: 0,
            y: 0,
            width: ExternalTabMetrics.collapsedWidth,
            height: ExternalTabMetrics.tabHeight
        )

        tab.setDockInfluence(1)
        let normalWidth = tab.preferredWidth
        tab.setReadyAttention(true)
        XCTAssertEqual(tab.preferredWidth, normalWidth, accuracy: 0.001)

        tab.setHovered(true)
        let hoveredWidth = tab.preferredWidth
        tab.setReadyAttention(false)
        XCTAssertEqual(tab.preferredWidth, hoveredWidth, accuracy: 0.001)
    }

    func testReadyDotIsNonInteractiveAndSemanticRed() {
        let tab = ExternalWebAppTabView(slotID: UUID())
        tab.frame = NSRect(x: 0, y: 0, width: 40, height: 32)
        tab.setReadyAttention(true)
        tab.layoutSubtreeIfNeeded()

        XCTAssertTrue(tab.hitTest(tab.readyAttentionFrame.midPoint) === tab)
        let red = try! XCTUnwrap(
            tab.readyAttentionColor?.usingColorSpace(.deviceRGB)
        )
        XCTAssertGreaterThan(red.redComponent, red.greenComponent)
        XCTAssertGreaterThan(red.redComponent, red.blueComponent)
    }

    func testReadyDotDoesNotChangeResidentOrReleasedFaviconPresentation() {
        let tab = ExternalWebAppTabView(slotID: UUID())

        tab.setResident(true)
        let residentIcon = try! XCTUnwrap(tab.displayedIcon)
        tab.setReadyAttention(true)
        XCTAssertTrue(tab.isResidentRuntime)
        XCTAssertTrue(tab.displayedIcon === residentIcon)

        tab.setResident(false)
        let releasedIcon = try! XCTUnwrap(tab.displayedIcon)
        tab.setReadyAttention(false)
        tab.setReadyAttention(true)
        XCTAssertFalse(tab.isResidentRuntime)
        XCTAssertTrue(tab.displayedIcon === releasedIcon)
        XCTAssertTrue(tab.isShowingReadyAttention)
    }

    func testReadyAttentionIsNotPersistedInWebAppProfile() throws {
        let profile = makeProfile(name: "GPT")
        let data = try JSONEncoder().encode(profile)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertFalse(
            object.keys.contains { key in
                let normalized = key.lowercased()
                return normalized.contains("ready") || normalized.contains("attention")
            }
        )
    }

    private func makeZoneHarness() -> (host: NSView, zone: ExternalControlZoneView) {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 76, height: 820))
        let zone = ExternalControlZoneView(frame: host.bounds)
        host.addSubview(zone)
        zone.layoutSubtreeIfNeeded()
        return (host, zone)
    }

    private func synchronize(
        _ zone: ExternalControlZoneView,
        from coordinator: WebAttentionCoordinator
    ) {
        zone.setReadySlotIDs(coordinator.readySlotIDs)
        zone.layoutSubtreeIfNeeded()
    }

    private func assertReadyDot(
        _ dot: NSRect,
        isAttachedTo icon: NSRect,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(dot.width, 6, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(dot.height, 6, accuracy: 0.001, file: file, line: line)
        XCTAssertGreaterThan(dot.minX, icon.minX, file: file, line: line)
        XCTAssertGreaterThan(dot.minY, icon.minY, file: file, line: line)
        XCTAssertGreaterThanOrEqual(dot.maxX, icon.maxX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(dot.maxY, icon.maxY, file: file, line: line)
    }

    private func makeProfile(name: String) -> WebAppProfile {
        WebAppProfile(
            order: 0,
            name: name,
            homeURL: URL(string: "https://example.com/\(name)")!
        )
    }
}

private extension NSRect {
    var midPoint: NSPoint {
        NSPoint(x: midX, y: midY)
    }
}
