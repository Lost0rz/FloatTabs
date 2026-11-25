import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class BrowserProfileDataStoreProviderTests: XCTestCase {
    func testDefaultIdentityUsesDefaultResolver() {
        let expectedStore = WKWebsiteDataStore.nonPersistent()
        let defaultResolverCalls = CallCounter()
        let customResolverCalls = CallCounter()

        let provider = makeProvider(
            defaultStore: expectedStore,
            defaultResolverCalls: defaultResolverCalls,
            customResolverCalls: customResolverCalls
        )

        let resolvedStore = provider.dataStore(for: nil)

        XCTAssertTrue(resolvedStore === expectedStore)
        XCTAssertEqual(defaultResolverCalls.value, 1)
        XCTAssertEqual(customResolverCalls.value, 0)
    }

    func testCustomIdentityUsesExactUUIDAndNeverCallsDefaultResolver() {
        let expectedStore = WKWebsiteDataStore.nonPersistent()
        let expectedID = UUID()
        var receivedID: UUID?
        let defaultResolverCalls = CallCounter()

        let provider = BrowserProfileDataStoreProvider(
            defaultStoreResolver: {
                defaultResolverCalls.value += 1
                return WKWebsiteDataStore.nonPersistent()
            },
            customStoreResolver: { id in
                receivedID = id
                return expectedStore
            }
        )

        let resolvedStore = provider.dataStore(for: expectedID)

        XCTAssertTrue(resolvedStore === expectedStore)
        XCTAssertEqual(receivedID, expectedID)
        XCTAssertEqual(defaultResolverCalls.value, 0)
    }

    func testRemovalReceivesExactUUID() async throws {
        let expectedID = UUID()
        var receivedID: UUID?
        var removerCallCount = 0
        let provider = BrowserProfileDataStoreProvider(
            customStoreRemover: { id in
                MainActor.assertIsolated()
                receivedID = id
                removerCallCount += 1
            }
        )

        try await provider.removeCustomDataStore(id: expectedID)

        XCTAssertEqual(receivedID, expectedID)
        XCTAssertEqual(removerCallCount, 1)
    }

    private func makeProvider(
        defaultStore: WKWebsiteDataStore,
        defaultResolverCalls: CallCounter,
        customResolverCalls: CallCounter
    ) -> BrowserProfileDataStoreProvider {
        BrowserProfileDataStoreProvider(
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
