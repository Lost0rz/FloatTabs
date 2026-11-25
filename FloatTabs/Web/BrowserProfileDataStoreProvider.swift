import Foundation
import WebKit

/// Resolves the WebKit website-data store for a persisted Browser Profile.
///
/// Default is a virtual identity and therefore always maps to WebKit's real
/// default store. Custom UUID-backed stores map directly to WebKit's native
/// persistent `WKWebsiteDataStore(forIdentifier:)` on macOS 14+.
/// Slot bindings, Profile metadata and WebView lifecycle remain outside this
/// provider.
@MainActor
struct BrowserProfileDataStoreProvider {
    typealias DefaultStoreResolver = @MainActor () -> WKWebsiteDataStore
    typealias CustomStoreResolver = @MainActor (UUID) -> WKWebsiteDataStore
    typealias CustomStoreRemover = @MainActor (UUID) async throws -> Void
    typealias DefaultWebsiteDataCleaner = @MainActor () async throws -> Void

    private let defaultStoreResolver: DefaultStoreResolver
    private let customStoreResolver: CustomStoreResolver
    private let customStoreRemover: CustomStoreRemover
    private let defaultWebsiteDataCleaner: DefaultWebsiteDataCleaner?

    init(
        defaultStoreResolver: @escaping DefaultStoreResolver = {
            WKWebsiteDataStore.default()
        },
        customStoreResolver: @escaping CustomStoreResolver = { id in
            WKWebsiteDataStore(forIdentifier: id)
        },
        customStoreRemover: @escaping CustomStoreRemover = { id in
            try await WKWebsiteDataStore.remove(forIdentifier: id)
        },
        defaultWebsiteDataCleaner: DefaultWebsiteDataCleaner? = nil
    ) {
        self.defaultStoreResolver = defaultStoreResolver
        self.customStoreResolver = customStoreResolver
        self.customStoreRemover = customStoreRemover
        self.defaultWebsiteDataCleaner = defaultWebsiteDataCleaner
    }

    func dataStore(for browserProfileID: UUID?) -> WKWebsiteDataStore {
        guard let browserProfileID else {
            return defaultStoreResolver()
        }
        return customStoreResolver(browserProfileID)
    }

    func removeCustomDataStore(id: UUID) async throws {
        try await customStoreRemover(id)
    }

    func removeDefaultWebsiteData() async throws {
        if let defaultWebsiteDataCleaner {
            try await defaultWebsiteDataCleaner()
            return
        }
        let store = defaultStoreResolver()
        await store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
    }
}
