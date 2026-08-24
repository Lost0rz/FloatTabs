import Foundation
import WebKit

struct WebsiteCacheProfileCleanupResult: Equatable {
    let identity: BrowserProfileIdentity
    let recordCount: Int
}

enum WebsiteCacheCleanupServiceError: LocalizedError, Equatable {
    case dataStoreUnavailable
    case removalFailed(String)

    var errorDescription: String? {
        switch self {
        case .dataStoreUnavailable:
            return "FloatTabs could not open the selected Browser Profile's website data store."
        case let .removalFailed(message):
            return "FloatTabs could not release website cache: \(message)"
        }
    }
}

/// WebKit is isolated behind two injected closures. Production uses only the
/// public fetch/removeData API; tests can use a non-persistent store or fakes.
@MainActor
final class WebsiteCacheCleanupService {
    typealias DataStoreResolver = @MainActor (BrowserProfileIdentity) throws -> WKWebsiteDataStore
    typealias FetchRecords = @MainActor (
        WKWebsiteDataStore,
        Set<String>,
        @Sendable @escaping ([WKWebsiteDataRecord]) -> Void
    ) -> Void
    typealias RemoveData = @MainActor (
        WKWebsiteDataStore,
        Set<String>,
        [WKWebsiteDataRecord]
    ) async throws -> Void

    private let dataStoreResolver: DataStoreResolver
    private let fetchRecords: FetchRecords
    private let removeData: RemoveData

    init(
        dataStoreResolver: @escaping DataStoreResolver,
        fetchRecords: @escaping FetchRecords = { store, types, completion in
            store.fetchDataRecords(ofTypes: types, completionHandler: completion)
        },
        removeData: @escaping RemoveData = { store, types, records in
            try await withCheckedThrowingContinuation { continuation in
                store.removeData(ofTypes: types, for: records) {
                    continuation.resume()
                }
            }
        }
    ) {
        self.dataStoreResolver = dataStoreResolver
        self.fetchRecords = fetchRecords
        self.removeData = removeData
    }

    convenience init(
        provider: BrowserProfileDataStoreProvider = BrowserProfileDataStoreProvider(),
        fetchRecords: @escaping FetchRecords = { store, types, completion in
            store.fetchDataRecords(ofTypes: types, completionHandler: completion)
        },
        removeData: @escaping RemoveData = { store, types, records in
            try await withCheckedThrowingContinuation { continuation in
                store.removeData(ofTypes: types, for: records) {
                    continuation.resume()
                }
            }
        }
    ) {
        self.init(
            dataStoreResolver: { identity in
                try provider.dataStore(for: identity.browserProfileID)
            },
            fetchRecords: fetchRecords,
            removeData: removeData
        )
    }

    func clean(identity: BrowserProfileIdentity) async throws -> WebsiteCacheProfileCleanupResult {
        let store: WKWebsiteDataStore
        do {
            store = try dataStoreResolver(identity)
        } catch {
            throw error
        }

        let records = await fetchRecords(in: store)
        do {
            // Calling the public removeData API even when WebKit reports no
            // records keeps the operation observable and makes the fake/non-
            // persistent test path exercise the same removal branch as the
            // production path. An empty record list is a harmless no-op.
            try await removeData(store, WebsiteCacheDataTypes.removable, records)
        } catch {
            throw WebsiteCacheCleanupServiceError.removalFailed(error.localizedDescription)
        }
        return WebsiteCacheProfileCleanupResult(
            identity: identity,
            recordCount: records.count
        )
    }

    private func fetchRecords(in store: WKWebsiteDataStore) async -> [WKWebsiteDataRecord] {
        await withCheckedContinuation { continuation in
            fetchRecords(store, WebsiteCacheDataTypes.removable) { records in
                continuation.resume(returning: records)
            }
        }
    }

}
