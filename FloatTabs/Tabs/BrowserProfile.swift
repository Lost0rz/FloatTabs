import Foundation

/// Persisted metadata for one custom browser data identity.
///
/// The built-in Default Profile is virtual and is intentionally not represented
/// by this type. A BrowserProfile's UUID is also the future WebKit data-store
/// identifier; the name is presentation metadata only.
struct BrowserProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date
}
