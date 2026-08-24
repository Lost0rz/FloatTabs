import Foundation

struct WebsiteCacheUsageEntry: Codable, Equatable {
    var lastUsedAt: Date?
    var dailyUseCounts: [String: Int]
    var lastSuccessfulCleanupAt: Date?

    static let empty = WebsiteCacheUsageEntry(
        lastUsedAt: nil,
        dailyUseCounts: [:],
        lastSuccessfulCleanupAt: nil
    )

    private enum CodingKeys: String, CodingKey {
        case lastUsedAt
        case dailyUseCounts
        case lastSuccessfulCleanupAt
        // Kept only to migrate the first implementation of this feature.
        case legacyUseCount = "useCount"
    }

    init(
        lastUsedAt: Date?,
        dailyUseCounts: [String: Int],
        lastSuccessfulCleanupAt: Date?
    ) {
        self.lastUsedAt = lastUsedAt
        self.dailyUseCounts = dailyUseCounts
        self.lastSuccessfulCleanupAt = lastSuccessfulCleanupAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        lastSuccessfulCleanupAt = try container.decodeIfPresent(
            Date.self,
            forKey: .lastSuccessfulCleanupAt
        )
        if let dailyUseCounts = try container.decodeIfPresent(
            [String: Int].self,
            forKey: .dailyUseCounts
        ) {
            self.dailyUseCounts = dailyUseCounts
        } else {
            // Older versions only had a lifetime counter. Preserve that
            // information as a single current-day bucket; it cannot be
            // allowed to remain an unbounded eviction signal.
            let legacyCount = max(
                0,
                try container.decodeIfPresent(Int.self, forKey: .legacyUseCount) ?? 0
            )
            if legacyCount > 0, let lastUsedAt {
                dailyUseCounts = [Self.dayKey(for: lastUsedAt): legacyCount]
            } else {
                dailyUseCounts = [:]
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
        try container.encode(dailyUseCounts, forKey: .dailyUseCounts)
        try container.encodeIfPresent(lastSuccessfulCleanupAt, forKey: .lastSuccessfulCleanupAt)
    }

    var useCount30Days: Int {
        dailyUseCounts.values.reduce(into: 0) { result, value in
            result = result > Int.max - max(0, value)
                ? Int.max
                : result + max(0, value)
        }
    }

    mutating func recordUse(at date: Date) {
        prune(now: date)
        let key = Self.dayKey(for: date)
        let current = max(0, dailyUseCounts[key] ?? 0)
        dailyUseCounts[key] = current == Int.max ? Int.max : current + 1
        lastUsedAt = date
    }

    mutating func prune(now: Date) {
        let retainedKeys = Self.retainedDayKeys(endingAt: now)
        dailyUseCounts = dailyUseCounts.filter { retainedKeys.contains($0.key) }
    }

    static func dayKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func retainedDayKeys(endingAt date: Date) -> Set<String> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startOfToday = calendar.startOfDay(for: date)
        return Set((0..<30).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: startOfToday)
            else { return nil }
            return dayKey(for: day)
        })
    }
}

/// Operational cache metadata is stored separately from the user-facing
/// backup document. It contains no cookies, URLs or website data.
@MainActor
final class WebsiteCacheUsageStore {
    static let entriesKey = "FloatTabs.websiteCache.usageEntries"
    static let lastAutomaticCheckKey = "FloatTabs.websiteCache.lastAutomaticCheckAt"
    static let lastAutomaticFailureKey = "FloatTabs.websiteCache.lastAutomaticFailureAt"
    static let lastSuccessfulCleanupKey = "FloatTabs.websiteCache.lastSuccessfulCleanupAt"

    private let defaults: UserDefaults
    private var entries: [String: WebsiteCacheUsageEntry]
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        if let data = defaults.data(forKey: Self.entriesKey),
           let decoded = try? JSONDecoder().decode(
               [String: WebsiteCacheUsageEntry].self,
               from: data
           ) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    func entry(for identity: BrowserProfileIdentity) -> WebsiteCacheUsageEntry {
        var entry = entries[identity.storageKey] ?? .empty
        entry.prune(now: now())
        return entry
    }

    var allEntries: [String: WebsiteCacheUsageEntry] {
        pruneExpiredBuckets()
        return entries
    }

    func recordUse(
        of identity: BrowserProfileIdentity,
        at date: Date = Date()
    ) {
        var entry = entries[identity.storageKey] ?? .empty
        entry.recordUse(at: date)
        entries[identity.storageKey] = entry
        persistEntries()
    }

    func markCleanupSucceeded(
        for identity: BrowserProfileIdentity,
        at date: Date = Date()
    ) {
        var entry = self.entry(for: identity)
        entry.lastSuccessfulCleanupAt = date
        entries[identity.storageKey] = entry
        persistEntries()
    }

    func markRunSucceeded(at date: Date = Date()) {
        defaults.set(date, forKey: Self.lastSuccessfulCleanupKey)
    }

    func removeEntry(for identity: BrowserProfileIdentity) {
        guard entries.removeValue(forKey: identity.storageKey) != nil else { return }
        persistEntries()
    }

    func prune(keeping identities: Set<BrowserProfileIdentity>) {
        pruneExpiredBuckets()
        let allowedKeys = Set(identities.map(\.storageKey))
        let before = entries.count
        entries = entries.filter { allowedKeys.contains($0.key) }
        if entries.count != before { persistEntries() }
    }

    var lastAutomaticCheckAt: Date? {
        get { defaults.object(forKey: Self.lastAutomaticCheckKey) as? Date }
        set { defaults.set(newValue, forKey: Self.lastAutomaticCheckKey) }
    }

    var lastAutomaticFailureAt: Date? {
        get { defaults.object(forKey: Self.lastAutomaticFailureKey) as? Date }
        set { defaults.set(newValue, forKey: Self.lastAutomaticFailureKey) }
    }

    var lastSuccessfulCleanupAt: Date? {
        defaults.object(forKey: Self.lastSuccessfulCleanupKey) as? Date
    }

    func resetForTesting() {
        entries.removeAll()
        defaults.removeObject(forKey: Self.entriesKey)
        defaults.removeObject(forKey: Self.lastAutomaticCheckKey)
        defaults.removeObject(forKey: Self.lastAutomaticFailureKey)
        defaults.removeObject(forKey: Self.lastSuccessfulCleanupKey)
    }

    private func persistEntries() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.entriesKey)
    }

    private func pruneExpiredBuckets() {
        let currentDate = now()
        var changed = false
        for key in entries.keys {
            guard var entry = entries[key] else { continue }
            let before = entry.dailyUseCounts
            entry.prune(now: currentDate)
            if entry.dailyUseCounts != before {
                entries[key] = entry
                changed = true
            }
        }
        if changed { persistEntries() }
    }
}

extension BrowserProfileIdentity {
    var browserProfileID: UUID? {
        switch self {
        case .default: return nil
        case let .custom(id): return id
        }
    }

    var storageKey: String {
        switch self {
        case .default: return "default"
        case let .custom(id): return "custom:\(id.uuidString.lowercased())"
        }
    }

    init?(storageKey: String) {
        if storageKey == "default" {
            self = .default
        } else if storageKey.hasPrefix("custom:"),
                  let id = UUID(uuidString: String(storageKey.dropFirst("custom:".count))) {
            self = .custom(id)
        } else {
            return nil
        }
    }
}
