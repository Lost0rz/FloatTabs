import Foundation
import WebKit

/// The only WebKit website-data types that FloatTabs may remove as part of
/// cache management. Keep this set deliberately small: login and durable
/// application state must never be part of a cache release operation.
enum WebsiteCacheDataTypes {
    static let removable: Set<String> = [
        WKWebsiteDataTypeDiskCache,
        WKWebsiteDataTypeMemoryCache,
        WKWebsiteDataTypeFetchCache,
    ]
}

enum WebsiteCacheRetentionOption: String, CaseIterable, Codable, Equatable {
    case sevenDays = "7"
    case thirtyDays = "30"
    case ninetyDays = "90"
    case never

    var days: Int? {
        switch self {
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .ninetyDays: return 90
        case .never: return nil
        }
    }

    var displayName: String {
        switch self {
        case .sevenDays: return "7 days"
        case .thirtyDays: return "30 days"
        case .ninetyDays: return "90 days"
        case .never: return "Never"
        }
    }

    init(days: Int?) {
        switch days {
        case 7: self = .sevenDays
        case 90: self = .ninetyDays
        case nil: self = .never
        default: self = .thirtyDays
        }
    }
}

enum WebsiteCacheLimitOption: String, CaseIterable, Codable, Equatable {
    case megabytes500 = "500MB"
    case gigabyte1 = "1GB"
    case gigabytes1_5 = "1.5GB"
    case gigabytes2 = "2GB"
    case gigabytes5 = "5GB"
    case unlimited

    static let bytesPerGigabyte: Int64 = 1024 * 1024 * 1024

    var bytes: Int64? {
        switch self {
        case .megabytes500: return 500 * 1024 * 1024
        case .gigabyte1: return Self.bytesPerGigabyte
        case .gigabytes1_5: return 3 * Self.bytesPerGigabyte / 2
        case .gigabytes2: return 2 * Self.bytesPerGigabyte
        case .gigabytes5: return 5 * Self.bytesPerGigabyte
        case .unlimited: return nil
        }
    }

    var displayName: String {
        switch self {
        case .megabytes500: return "500 MB"
        case .gigabyte1: return "1 GB"
        case .gigabytes1_5: return "1.5 GB"
        case .gigabytes2: return "2 GB"
        case .gigabytes5: return "5 GB"
        case .unlimited: return "Unlimited"
        }
    }

    init(bytes: Int64?) {
        guard let bytes else {
            self = .unlimited
            return
        }
        self = Self.allCases
            .filter { $0.bytes != nil }
            .min { abs(($0.bytes ?? bytes) - bytes) < abs(($1.bytes ?? bytes) - bytes) }
            ?? .gigabytes1_5
    }
}

/// Pure policy values and decisions. WebKit, AppKit and UserDefaults are kept
/// out of this type so threshold and candidate tests can run without a store.
struct WebsiteCachePolicy: Codable, Equatable {
    static let defaultMaximumEstimatedBytes: Int64 =
        3 * WebsiteCacheLimitOption.bytesPerGigabyte / 2
    static let defaultTargetEstimatedBytes: Int64 = WebsiteCacheLimitOption.bytesPerGigabyte
    static let defaultMinimumCleanupInterval: TimeInterval = 24 * 60 * 60
    static let defaultRecentUseProtection: TimeInterval = 24 * 60 * 60

    static func targetEstimatedBytes(forMaximum maximumEstimatedBytes: Int64?) -> Int64 {
        guard let maximumEstimatedBytes, maximumEstimatedBytes > 0 else {
            return defaultTargetEstimatedBytes
        }
        // floor(2n/3), written without an overflowing multiplication.
        return (maximumEstimatedBytes / 3) * 2
            + ((maximumEstimatedBytes % 3) * 2) / 3
    }

    var automaticCleanupEnabled: Bool
    var retentionDays: Int?
    var maximumEstimatedBytes: Int64?
    var targetEstimatedBytes: Int64
    var minimumCleanupInterval: TimeInterval
    var recentUseProtection: TimeInterval

    static let `default` = WebsiteCachePolicy(
        automaticCleanupEnabled: true,
        retentionDays: 30,
        maximumEstimatedBytes: defaultMaximumEstimatedBytes,
        targetEstimatedBytes: defaultTargetEstimatedBytes,
        minimumCleanupInterval: defaultMinimumCleanupInterval,
        recentUseProtection: defaultRecentUseProtection
    )

    init(
        automaticCleanupEnabled: Bool = WebsiteCachePolicy.default.automaticCleanupEnabled,
        retentionDays: Int? = WebsiteCachePolicy.default.retentionDays,
        maximumEstimatedBytes: Int64? = WebsiteCachePolicy.default.maximumEstimatedBytes,
        targetEstimatedBytes: Int64 = WebsiteCachePolicy.defaultTargetEstimatedBytes,
        minimumCleanupInterval: TimeInterval = WebsiteCachePolicy.defaultMinimumCleanupInterval,
        recentUseProtection: TimeInterval = WebsiteCachePolicy.defaultRecentUseProtection
    ) {
        self.automaticCleanupEnabled = automaticCleanupEnabled
        self.retentionDays = retentionDays
        self.maximumEstimatedBytes = maximumEstimatedBytes
        self.targetEstimatedBytes = targetEstimatedBytes
        self.minimumCleanupInterval = minimumCleanupInterval
        self.recentUseProtection = recentUseProtection
    }

    func normalized() -> WebsiteCachePolicy {
        let normalizedMaximum = maximumEstimatedBytes.flatMap { $0 > 0 ? $0 : nil }
        let normalizedRetention: Int?
        switch retentionDays {
        case 7, 30, 90: normalizedRetention = retentionDays
        case nil: normalizedRetention = nil
        default: normalizedRetention = 30
        }

        let normalizedTarget: Int64
        if let normalizedMaximum {
            let upperBound = Self.targetEstimatedBytes(
                forMaximum: normalizedMaximum
            )
            normalizedTarget = min(
                max(0, targetEstimatedBytes),
                upperBound
            )
        } else {
            normalizedTarget = max(0, targetEstimatedBytes)
        }

        let interval = minimumCleanupInterval.isFinite
            ? max(0, minimumCleanupInterval)
            : Self.defaultMinimumCleanupInterval
        let recentProtection = recentUseProtection.isFinite
            ? max(0, recentUseProtection)
            : Self.defaultRecentUseProtection

        return WebsiteCachePolicy(
            automaticCleanupEnabled: automaticCleanupEnabled,
            retentionDays: normalizedRetention,
            maximumEstimatedBytes: normalizedMaximum,
            targetEstimatedBytes: normalizedTarget,
            minimumCleanupInterval: interval,
            recentUseProtection: recentProtection
        )
    }

    func shouldTriggerCapacity(estimatedBytes: Int64?) -> Bool {
        guard let maximumEstimatedBytes, let estimatedBytes else { return false }
        return estimatedBytes > maximumEstimatedBytes
    }

    func hasReachedTarget(estimatedBytes: Int64?) -> Bool {
        guard let estimatedBytes else { return false }
        return estimatedBytes <= targetEstimatedBytes
    }

    func isPastRetention(lastUsedAt: Date, now: Date) -> Bool {
        guard let retentionDays else { return false }
        let age = now.timeIntervalSince(lastUsedAt)
        return age >= TimeInterval(retentionDays) * 24 * 60 * 60
    }

    func isProtectedByRecentUse(lastUsedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(lastUsedAt) < recentUseProtection
    }

    /// Higher scores are safer eviction candidates. Frequency receives a
    /// bounded grace period, so a profile that was used heavily in the past
    /// cannot become permanently immune to TTL or capacity cleanup.
    static func evictionScore(
        lastUsedAt: Date,
        useCount30Days: Int,
        now: Date
    ) -> Double {
        let ageDays = max(0, now.timeIntervalSince(lastUsedAt) / (24 * 60 * 60))
        let frequencyGrace = min(
            log2(1 + Double(max(0, useCount30Days))) * 2,
            7
        )
        return ageDays - frequencyGrace
    }
}
