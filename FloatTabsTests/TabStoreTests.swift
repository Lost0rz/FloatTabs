import Foundation
import XCTest
@testable import FloatTabs

final class MemoryProfileRepository: ProfileRepositoryProtocol {
    var state: StoredWebAppState
    var savedStates: [StoredWebAppState] = []
    var loadError: Error?

    init(state: StoredWebAppState = .empty) {
        self.state = state
    }

    func load() throws -> StoredWebAppState {
        if let loadError { throw loadError }
        return state
    }

    func save(_ state: StoredWebAppState) throws {
        self.state = state
        savedStates.append(state)
    }
}

@MainActor
final class TabStoreTests: XCTestCase {
    private let urlA = URL(string: "https://example.com/a")!
    private let urlB = URL(string: "https://example.com/b")!
    private let urlC = URL(string: "https://example.com/c")!

    func testAddProducesStableContinuousOrderAndSelectsNewSlot() {
        let repository = MemoryProfileRepository()
        let store = TabStore(repository: repository)

        let first = store.add(name: "A", homeURL: urlA)!
        let second = store.add(name: "B", homeURL: urlB)!
        let third = store.add(name: "C", homeURL: urlC)!

        XCTAssertEqual(store.orderedProfiles.map(\.order), [0, 1, 2])
        XCTAssertEqual(store.orderedProfiles.map(\.id), [first.id, second.id, third.id])
        XCTAssertEqual(store.activeTabID, third.id)
    }

    func testAddAndEditPersistRenderingProfileAcrossRelaunch() {
        let repository = MemoryProfileRepository()
        let store = TabStore(repository: repository)
        let initialRendering = WebRenderingProfile(
            websiteMode: .mobile,
            browserIdentity: .androidChrome,
            customUserAgent: nil,
            sizePreset: .small,
            devicePresetID: nil,
            orientation: .portrait,
            viewportWidth: 390,
            viewportHeight: 780,
            zoom: 1.25
        )
        let profile = store.add(
            name: "A",
            homeURL: urlA,
            renderingProfile: initialRendering
        )!

        let editedRendering = initialRendering
            .settingBrowserIdentity(.windowsChrome)
            .settingSimplePreset(.large)
            .settingZoom(1.33)
        XCTAssertTrue(
            store.update(
                id: profile.id,
                name: "A Edited",
                homeURL: urlA,
                renderingProfile: editedRendering
            )
        )

        let relaunched = TabStore(repository: repository)
        let restored = try! XCTUnwrap(relaunched.profiles.first(where: { $0.id == profile.id }))
        XCTAssertEqual(restored.name, "A Edited")
        XCTAssertEqual(restored.renderingProfile, editedRendering.normalized())
    }

    func testPreferredViewportAndZoomUpdatesPersistPerSlot() {
        let repository = MemoryProfileRepository()
        let store = TabStore(repository: repository)
        let profile = store.add(name: "A", homeURL: urlA)!

        XCTAssertTrue(store.updatePreferredViewport(id: profile.id, size: CGSize(width: 612, height: 777)))
        XCTAssertTrue(store.updateZoom(id: profile.id, zoom: 1.49))

        let updated = try! XCTUnwrap(store.profiles.first(where: { $0.id == profile.id }))
        XCTAssertEqual(updated.renderingProfile.viewportWidth, 612)
        XCTAssertEqual(updated.renderingProfile.viewportHeight, 777)
        XCTAssertEqual(updated.renderingProfile.sizePreset, .custom)
        XCTAssertNil(updated.renderingProfile.devicePresetID)
        XCTAssertEqual(updated.renderingProfile.zoom, 1.50, accuracy: 0.001)
        XCTAssertEqual(repository.state.profiles.first?.renderingProfile, updated.renderingProfile)
    }

    func testActiveSelectionUpdatesIdentity() {
        let store = TabStore(repository: MemoryProfileRepository())
        let first = store.add(name: "A", homeURL: urlA)!
        _ = store.add(name: "B", homeURL: urlB)!

        XCTAssertTrue(store.select(id: first.id))
        XCTAssertEqual(store.activeTabID, first.id)
    }

    func testRemovingActiveSlotSelectsNearestNeighborAtOriginalPosition() {
        let store = TabStore(repository: MemoryProfileRepository())
        _ = store.add(name: "A", homeURL: urlA)!
        let middle = store.add(name: "B", homeURL: urlB)!
        let last = store.add(name: "C", homeURL: urlC)!
        _ = store.select(id: middle.id)

        XCTAssertTrue(store.remove(id: middle.id))
        XCTAssertEqual(store.activeTabID, last.id)
        XCTAssertEqual(store.orderedProfiles.map(\.order), [0, 1])
    }

    func testRemovingFinalSlotProducesValidEmptyState() {
        let store = TabStore(repository: MemoryProfileRepository())
        let only = store.add(name: "A", homeURL: urlA)!

        XCTAssertTrue(store.remove(id: only.id))
        XCTAssertTrue(store.profiles.isEmpty)
        XCTAssertNil(store.activeTabID)
        XCTAssertNil(store.activeProfile)
    }

    func testReorderNormalizesOrderWithoutChangingSlotIDs() {
        let store = TabStore(repository: MemoryProfileRepository())
        let first = store.add(name: "A", homeURL: urlA)!
        let second = store.add(name: "B", homeURL: urlB)!
        let third = store.add(name: "C", homeURL: urlC)!
        let idsBefore = Set(store.profiles.map(\.id))

        XCTAssertTrue(store.move(id: third.id, toIndex: 0))

        XCTAssertEqual(store.orderedProfiles.map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(store.orderedProfiles.map(\.order), [0, 1, 2])
        XCTAssertEqual(Set(store.profiles.map(\.id)), idsBefore)
    }

    func testKeyboardIndexMappingFollowsVisibleOrderImmediately() {
        let store = TabStore(repository: MemoryProfileRepository())
        let first = store.add(name: "A", homeURL: urlA)!
        let second = store.add(name: "B", homeURL: urlB)!
        let third = store.add(name: "C", homeURL: urlC)!

        _ = store.move(id: third.id, toIndex: 0)

        XCTAssertEqual(store.slotByKeyboardIndex(1)?.id, third.id)
        XCTAssertEqual(store.slotByKeyboardIndex(2)?.id, first.id)
        XCTAssertEqual(store.slotByKeyboardIndex(3)?.id, second.id)
        XCTAssertNil(store.slotByKeyboardIndex(4))
        XCTAssertNil(store.slotByKeyboardIndex(0))
    }

    func testNextAndPreviousWrapAround() {
        let store = TabStore(repository: MemoryProfileRepository())
        let first = store.add(name: "A", homeURL: urlA)!
        _ = store.add(name: "B", homeURL: urlB)!
        let third = store.add(name: "C", homeURL: urlC)!

        _ = store.select(id: third.id)
        XCTAssertEqual(store.selectNext()?.id, first.id)
        XCTAssertEqual(store.selectPrevious()?.id, third.id)
    }

    func testPersistedDuplicateAndInvalidOrdersAreNormalizedContinuously() {
        let early = WebAppProfile(
            order: -4,
            name: "Early",
            homeURL: urlA,
            createdAt: Date(timeIntervalSince1970: 10),
            lastUsedAt: Date(timeIntervalSince1970: 10)
        )
        let duplicateA = WebAppProfile(
            order: 7,
            name: "Duplicate A",
            homeURL: urlB,
            createdAt: Date(timeIntervalSince1970: 20),
            lastUsedAt: Date(timeIntervalSince1970: 20)
        )
        let duplicateB = WebAppProfile(
            order: 7,
            name: "Duplicate B",
            homeURL: urlC,
            createdAt: Date(timeIntervalSince1970: 30),
            lastUsedAt: Date(timeIntervalSince1970: 30)
        )
        let repository = MemoryProfileRepository(
            state: StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                profiles: [duplicateB, early, duplicateA],
                lastActiveTabID: duplicateB.id
            )
        )

        let store = TabStore(repository: repository)

        XCTAssertEqual(store.orderedProfiles.map(\.id), [early.id, duplicateA.id, duplicateB.id])
        XCTAssertEqual(store.orderedProfiles.map(\.order), [0, 1, 2])
        XCTAssertEqual(store.activeTabID, duplicateB.id)
    }

    func testDuplicatePersistedSlotIDsAreDeduplicatedBeforeUse() {
        let id = UUID()
        let first = WebAppProfile(
            id: id,
            order: 0,
            name: "First",
            homeURL: urlA,
            createdAt: Date(timeIntervalSince1970: 10),
            lastUsedAt: Date(timeIntervalSince1970: 10)
        )
        let duplicateIdentity = WebAppProfile(
            id: id,
            order: 4,
            name: "Duplicate identity",
            homeURL: urlB,
            createdAt: Date(timeIntervalSince1970: 20),
            lastUsedAt: Date(timeIntervalSince1970: 20)
        )
        let other = WebAppProfile(
            order: 9,
            name: "Other",
            homeURL: urlC,
            createdAt: Date(timeIntervalSince1970: 30),
            lastUsedAt: Date(timeIntervalSince1970: 30)
        )
        let repository = MemoryProfileRepository(
            state: StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                profiles: [duplicateIdentity, other, first],
                lastActiveTabID: id
            )
        )

        let store = TabStore(repository: repository)

        XCTAssertEqual(store.orderedProfiles.count, 2)
        XCTAssertEqual(store.orderedProfiles.map(\.id), [id, other.id])
        XCTAssertEqual(store.orderedProfiles.map(\.order), [0, 1])
        XCTAssertEqual(store.orderedProfiles.first?.name, "First")
        XCTAssertEqual(store.activeTabID, id)
        XCTAssertEqual(repository.savedStates.last?.profiles.count, 2)
    }

    func testInvalidPersistedActiveIDIsRepairedAndPersisted() {
        let first = makeProfile(order: 7, name: "A", url: urlA)
        let second = makeProfile(order: 20, name: "B", url: urlB)
        let repository = MemoryProfileRepository(
            state: StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                profiles: [second, first],
                lastActiveTabID: UUID()
            )
        )

        let store = TabStore(repository: repository)

        XCTAssertEqual(store.orderedProfiles.map(\.order), [0, 1])
        XCTAssertEqual(store.activeTabID, first.id)
        XCTAssertEqual(repository.savedStates.last?.lastActiveTabID, first.id)
        XCTAssertEqual(repository.savedStates.last?.profiles.map(\.order), [0, 1])
    }

    private func makeProfile(order: Int, name: String, url: URL) -> WebAppProfile {
        WebAppProfile(
            order: order,
            name: name,
            homeURL: url,
            createdAt: Date(timeIntervalSince1970: TimeInterval(order)),
            lastUsedAt: Date(timeIntervalSince1970: TimeInterval(order))
        )
    }
}

final class WebRenderingProfileTests: XCTestCase {
    func testCanonicalDefaultsAndCodableRoundTrip() throws {
        let profile = WebRenderingProfile.canonicalDefault
        XCTAssertEqual(profile.websiteMode, .desktop)
        XCTAssertEqual(profile.effectiveWebsiteMode, .desktop)
        XCTAssertEqual(profile.browserIdentity, .automatic)
        XCTAssertEqual(profile.effectiveBrowserIdentity, .macosSafari)
        XCTAssertEqual(profile.sizePreset, .medium)
        XCTAssertNil(profile.devicePresetID)
        XCTAssertEqual(profile.viewportSize, CGSize(width: 430, height: 820))
        XCTAssertEqual(profile.zoom, 1.0)

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(WebRenderingProfile.self, from: data)
        XCTAssertEqual(decoded, profile)
    }

    func testSimpleViewportPresetsAndMinimumClamp() {
        XCTAssertEqual(SimpleViewportPreset.small.size, CGSize(width: 390, height: 780))
        XCTAssertEqual(SimpleViewportPreset.medium.size, CGSize(width: 430, height: 820))
        XCTAssertEqual(SimpleViewportPreset.large.size, CGSize(width: 600, height: 800))
        XCTAssertEqual(SimpleViewportPreset.wide.size, CGSize(width: 900, height: 850))
        XCTAssertNil(SimpleViewportPreset.custom.size)

        let clamped = WebRenderingProfile.canonicalDefault.settingViewport(
            CGSize(width: 120, height: 200)
        )
        XCTAssertEqual(clamped.viewportSize, CGSize(width: 320, height: 400))
        XCTAssertEqual(clamped.sizePreset, .custom)
    }

    func testWebsiteModeAndViewportAreIndependent() {
        let base = WebRenderingProfile.canonicalDefault
        let mobile = base.settingWebsiteMode(.mobile)
        XCTAssertEqual(mobile.websiteMode, .mobile)
        XCTAssertEqual(mobile.browserIdentity, .automatic)
        XCTAssertEqual(mobile.effectiveBrowserIdentity, .iphoneSafari)
        XCTAssertEqual(mobile.viewportSize, base.viewportSize)

        let wide = mobile.settingSimplePreset(.wide)
        XCTAssertEqual(wide.websiteMode, .mobile)
        XCTAssertEqual(wide.browserIdentity, .automatic)
        XCTAssertEqual(wide.effectiveBrowserIdentity, .iphoneSafari)
        XCTAssertEqual(wide.viewportSize, CGSize(width: 900, height: 850))
    }

    func testExplicitBrowserIdentityAndWebsiteModeRemainIndependent() {
        let base = WebRenderingProfile.canonicalDefault.settingViewport(
            CGSize(width: 430, height: 820)
        )
        let androidOnDesktop = base.settingBrowserIdentity(.androidChrome)
        XCTAssertEqual(androidOnDesktop.websiteMode, .desktop)
        XCTAssertEqual(androidOnDesktop.effectiveWebsiteMode, .desktop)
        XCTAssertEqual(androidOnDesktop.browserIdentity, .androidChrome)
        XCTAssertEqual(androidOnDesktop.effectiveBrowserIdentity, .androidChrome)
        XCTAssertEqual(androidOnDesktop.viewportSize, CGSize(width: 430, height: 820))

        let androidOnMobile = androidOnDesktop.settingWebsiteMode(.mobile)
        XCTAssertEqual(androidOnMobile.websiteMode, .mobile)
        XCTAssertEqual(androidOnMobile.browserIdentity, .androidChrome)
        XCTAssertEqual(androidOnMobile.effectiveBrowserIdentity, .androidChrome)
        XCTAssertEqual(androidOnMobile.viewportSize, CGSize(width: 430, height: 820))

        let windowsOnMobile = androidOnMobile.settingBrowserIdentity(.windowsChrome)
        XCTAssertEqual(windowsOnMobile.websiteMode, .mobile)
        XCTAssertEqual(windowsOnMobile.effectiveWebsiteMode, .mobile)
        XCTAssertEqual(windowsOnMobile.browserIdentity, .windowsChrome)
        XCTAssertEqual(windowsOnMobile.effectiveBrowserIdentity, .windowsChrome)
        XCTAssertEqual(windowsOnMobile.viewportSize, CGSize(width: 430, height: 820))
    }

    func testDevicePresetIsAdvancedViewportShortcutAndManualResizeClearsIt() {
        let device = try! XCTUnwrap(DevicePresetCatalog.preset(id: "iphone-17-pro-max"))
        var profile = WebRenderingProfile.canonicalDefault.settingDevicePreset(id: device.id)
        XCTAssertEqual(profile.devicePresetID, device.id)
        XCTAssertEqual(profile.sizePreset, .custom)
        XCTAssertEqual(profile.viewportSize, CGSize(width: 440, height: 956))
        XCTAssertEqual(profile.websiteMode, .desktop)

        profile = profile.settingOrientation(.landscape)
        XCTAssertEqual(profile.viewportSize, CGSize(width: 956, height: 440))
        XCTAssertEqual(profile.devicePresetID, device.id)

        profile = profile.settingViewport(CGSize(width: 500, height: 700))
        XCTAssertNil(profile.devicePresetID)
        XCTAssertEqual(profile.sizePreset, .custom)
        XCTAssertEqual(profile.viewportSize, CGSize(width: 500, height: 700))
    }

    func testDeviceCatalogContainsCurrentPhoneAndTabletClasses() {
        XCTAssertEqual(DevicePresetCatalog.preset(id: "iphone-16e")?.portraitSize, CGSize(width: 390, height: 844))
        XCTAssertEqual(DevicePresetCatalog.preset(id: "iphone-17-pro")?.portraitSize, CGSize(width: 402, height: 874))
        XCTAssertEqual(DevicePresetCatalog.preset(id: "iphone-17-pro-max")?.portraitSize, CGSize(width: 440, height: 956))
        XCTAssertEqual(DevicePresetCatalog.preset(id: "android-standard")?.portraitSize, CGSize(width: 412, height: 924))
        XCTAssertEqual(DevicePresetCatalog.preset(id: "android-large")?.portraitSize, CGSize(width: 448, height: 997))
        XCTAssertEqual(DevicePresetCatalog.preset(id: "ipad-mini")?.portraitSize, CGSize(width: 744, height: 1133))
        XCTAssertEqual(DevicePresetCatalog.preset(id: "ipad-air-11")?.portraitSize, CGSize(width: 820, height: 1180))
        XCTAssertEqual(DevicePresetCatalog.preset(id: "ipad-pro-13")?.portraitSize, CGSize(width: 1032, height: 1376))
    }

    func testLegacyStage3RenderingJSONMigratesWithoutLosingSizeOrZoom() throws {
        let data = Data(
            """
            {
              "browserCompatibility": "chrome",
              "contentMode": "mobile",
              "viewportWidth": 390,
              "viewportHeight": 780,
              "zoom": 1.25
            }
            """.utf8
        )

        let migrated = try JSONDecoder().decode(WebRenderingProfile.self, from: data)
        XCTAssertEqual(migrated.websiteMode, .mobile)
        XCTAssertEqual(migrated.browserIdentity, .iphoneChrome)
        XCTAssertEqual(migrated.sizePreset, .small)
        XCTAssertEqual(migrated.viewportSize, CGSize(width: 390, height: 780))
        XCTAssertEqual(migrated.zoom, 1.25, accuracy: 0.001)
    }

    func testZoomStepTraversalAndResetHelpers() {
        XCTAssertEqual(ZoomSteps.nextLarger(after: 1.0), 1.10, accuracy: 0.001)
        XCTAssertEqual(ZoomSteps.nextSmaller(before: 1.0), 0.90, accuracy: 0.001)
        XCTAssertEqual(ZoomSteps.nextLarger(after: 2.0), 2.0, accuracy: 0.001)
        XCTAssertEqual(ZoomSteps.nextSmaller(before: 0.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(ZoomSteps.nearest(to: 1.49), 1.50, accuracy: 0.001)
        XCTAssertEqual(ZoomSteps.percentageText(for: 1.33), "133%")
    }

    func testOnlyBrowserIdentityOrWebsiteModeRequiresWebViewRebuild() {
        let base = WebRenderingProfile.canonicalDefault
        XCTAssertFalse(base.settingZoom(1.25).requiresWebViewRebuild(comparedTo: base))
        XCTAssertFalse(base.settingViewport(CGSize(width: 600, height: 800)).requiresWebViewRebuild(comparedTo: base))
        XCTAssertFalse(base.settingDevicePreset(id: "iphone-17-pro").requiresWebViewRebuild(comparedTo: base))

        let browser = base.settingBrowserIdentity(.windowsChrome)
        XCTAssertTrue(browser.requiresWebViewRebuild(comparedTo: base))

        let mobile = base.settingWebsiteMode(.mobile)
        XCTAssertTrue(mobile.requiresWebViewRebuild(comparedTo: base))
    }
}

final class WebAppURLTests: XCTestCase {
    func testNormalizesBareHostToHTTPSAndRejectsUnsafeSchemes() {
        XCTAssertEqual(
            WebAppURL.normalized(from: "example.com")?.absoluteString,
            "https://example.com"
        )
        XCTAssertEqual(
            WebAppURL.normalized(from: "https://example.com/path")?.absoluteString,
            "https://example.com/path"
        )
        XCTAssertNil(WebAppURL.normalized(from: "javascript:alert(1)"))
        XCTAssertNil(WebAppURL.normalized(from: "file:///tmp/test.html"))
        XCTAssertNil(WebAppURL.normalized(from: "ftp://example.com/file"))
    }
}
