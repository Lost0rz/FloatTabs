import Foundation
import WebKit

enum BrowserProfileDataStoreProviderError: Error, Equatable, LocalizedError {
    case customProfilesUnsupported

    var errorDescription: String? {
        switch self {
        case .customProfilesUnsupported:
            return "Additional Browser Profiles require macOS 14 or later."
        }
    }
}

/// Resolves the WebKit website-data store for a persisted Browser Profile.
///
/// Default is a virtual identity and therefore always maps to WebKit's real
/// default store. Custom UUID-backed stores are only available on macOS 14+;
/// callers must handle the explicit unsupported error instead of falling back
/// to Default. Slot bindings, Profile metadata and WebView lifecycle remain
/// outside this provider.
@MainActor
struct BrowserProfileDataStoreProvider {
    typealias AvailabilityResolver = @MainActor () -> Bool
    typealias DefaultStoreResolver = @MainActor () -> WKWebsiteDataStore
    typealias CustomStoreResolver = @MainActor (UUID) -> WKWebsiteDataStore
    typealias CustomStoreRemover = @MainActor (UUID) async throws -> Void

    private let isCustomProfileSupported: AvailabilityResolver
    private let defaultStoreResolver: DefaultStoreResolver
    private let customStoreResolver: CustomStoreResolver
    private let customStoreRemover: CustomStoreRemover

    init(
        isCustomProfileSupported: @escaping AvailabilityResolver = {
            BrowserProfileDataStoreProvider.customProfilesSupportedOnCurrentOS()
        },
        defaultStoreResolver: @escaping DefaultStoreResolver = {
            WKWebsiteDataStore.default()
        },
        customStoreResolver: @escaping CustomStoreResolver = { id in
            guard #available(macOS 14.0, *) else {
                preconditionFailure("Custom Browser Profiles require macOS 14 or later")
            }
            return WKWebsiteDataStore(forIdentifier: id)
        },
        customStoreRemover: @escaping CustomStoreRemover = { id in
            guard #available(macOS 14.0, *) else {
                throw BrowserProfileDataStoreProviderError.customProfilesUnsupported
            }
            try await WKWebsiteDataStore.remove(forIdentifier: id)
        }
    ) {
        self.isCustomProfileSupported = isCustomProfileSupported
        self.defaultStoreResolver = defaultStoreResolver
        self.customStoreResolver = customStoreResolver
        self.customStoreRemover = customStoreRemover
    }

    /// The capability seam is deliberately backed only by the injected OS
    /// availability resolver. It never probes WebKit by creating a store.
    var customProfilesSupported: Bool {
        isCustomProfileSupported()
    }

    func dataStore(for browserProfileID: UUID?) throws -> WKWebsiteDataStore {
        guard let browserProfileID else {
            return defaultStoreResolver()
        }

        guard isCustomProfileSupported() else {
            throw BrowserProfileDataStoreProviderError.customProfilesUnsupported
        }

        return customStoreResolver(browserProfileID)
    }

    func removeCustomDataStore(id: UUID) async throws {
        guard isCustomProfileSupported() else {
            throw BrowserProfileDataStoreProviderError.customProfilesUnsupported
        }

        try await customStoreRemover(id)
    }

    private static func customProfilesSupportedOnCurrentOS() -> Bool {
        if #available(macOS 14.0, *) {
            return true
        }
        return false
    }
}
