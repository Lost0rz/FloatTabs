import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class BrowserProfileDataStoreProviderTests: XCTestCase {
    func testDefaultIdentityUsesDefaultResolverEvenWhenCustomProfilesAreUnsupported() throws {
        let expectedStore = WKWebsiteDataStore.nonPersistent()
        let defaultResolverCalls = CallCounter()
        let customResolverCalls = CallCounter()

        let provider = makeProvider(
            supported: false,
            defaultStore: expectedStore,
            defaultResolverCalls: defaultResolverCalls,
            customResolverCalls: customResolverCalls
        )

        let resolvedStore = try provider.dataStore(for: nil)

        XCTAssertTrue(resolvedStore === expectedStore)
        XCTAssertEqual(defaultResolverCalls.value, 1)
        XCTAssertEqual(customResolverCalls.value, 0)
    }

    func testCustomIdentityUsesExactUUIDAndNeverCallsDefaultResolver() throws {
        let expectedStore = WKWebsiteDataStore.nonPersistent()
        let expectedID = UUID()
        var receivedID: UUID?
        let defaultResolverCalls = CallCounter()

        let provider = BrowserProfileDataStoreProvider(
            isCustomProfileSupported: { true },
            defaultStoreResolver: {
                defaultResolverCalls.value += 1
                return WKWebsiteDataStore.nonPersistent()
            },
            customStoreResolver: { id in
                receivedID = id
                return expectedStore
            }
        )

        let resolvedStore = try provider.dataStore(for: expectedID)

        XCTAssertTrue(resolvedStore === expectedStore)
        XCTAssertEqual(receivedID, expectedID)
        XCTAssertEqual(defaultResolverCalls.value, 0)
    }

    func testUnsupportedCustomIdentityFailsClosedBeforeEitherResolver() {
        let expectedID = UUID()
        let defaultResolverCalls = CallCounter()
        let customResolverCalls = CallCounter()
        let provider = makeProvider(
            supported: false,
            defaultStore: WKWebsiteDataStore.nonPersistent(),
            defaultResolverCalls: defaultResolverCalls,
            customResolverCalls: customResolverCalls
        )

        XCTAssertThrowsError(try provider.dataStore(for: expectedID)) { error in
            XCTAssertEqual(
                error as? BrowserProfileDataStoreProviderError,
                .customProfilesUnsupported
            )
        }
        XCTAssertEqual(defaultResolverCalls.value, 0)
        XCTAssertEqual(customResolverCalls.value, 0)
    }

    func testSupportedRemovalReceivesExactUUID() async throws {
        let expectedID = UUID()
        var receivedID: UUID?
        let provider = BrowserProfileDataStoreProvider(
            isCustomProfileSupported: { true },
            customStoreRemover: { id in
                receivedID = id
            }
        )

        try await provider.removeCustomDataStore(id: expectedID)

        XCTAssertEqual(receivedID, expectedID)
    }

    func testUnsupportedRemovalFailsClosedWithoutCallingRemover() async {
        let expectedID = UUID()
        let removerCalls = CallCounter()
        let provider = BrowserProfileDataStoreProvider(
            isCustomProfileSupported: { false },
            customStoreRemover: { _ in
                removerCalls.value += 1
            }
        )

        do {
            try await provider.removeCustomDataStore(id: expectedID)
            XCTFail("Unsupported custom Profile removal must fail")
        } catch {
            XCTAssertEqual(
                error as? BrowserProfileDataStoreProviderError,
                .customProfilesUnsupported
            )
        }

        XCTAssertEqual(removerCalls.value, 0)
    }

    private func makeProvider(
        supported: Bool,
        defaultStore: WKWebsiteDataStore,
        defaultResolverCalls: CallCounter,
        customResolverCalls: CallCounter
    ) -> BrowserProfileDataStoreProvider {
        BrowserProfileDataStoreProvider(
            isCustomProfileSupported: { supported },
            defaultStoreResolver: {
                defaultResolverCalls.value += 1
                return defaultStore
            },
            customStoreResolver: { _ in
                customResolverCalls.value += 1
                return WKWebsiteDataStore.nonPersistent()
            }
        )
    }

    private final class CallCounter {
        var value = 0
    }
}
