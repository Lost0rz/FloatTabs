import Foundation
import WebKit

struct WebsiteCacheProfileSnapshot: Equatable {
    let identity: BrowserProfileIdentity
    let lastUsedAt: Date
    let useCount: Int
    let isActive: Bool
}

struct WebsiteCacheCleanupResult: Equatable {
    let estimatedBytesBefore: Int64?
    let estimatedBytesAfter: Int64?
    let cleanedProfileCount: Int
    let cleanedRecordCount: Int
    let skippedActiveProfileCount: Int
    let completedAt: Date

    var releasedBytes: Int64? {
        guard let before = estimatedBytesBefore,
              let after = estimatedBytesAfter else { return nil }
        return max(0, before - after)
    }
}

struct WebsiteCacheSettingsSnapshot: Equatable {
    let policy: WebsiteCachePolicy
    let estimatedBytes: Int64?
    let measurementState: WebsiteCacheMeasurementState
    let lastSuccessfulCleanupAt: Date?
    let isOperationInProgress: Bool

    init(
        policy: WebsiteCachePolicy,
        estimatedBytes: Int64?,
        measurementState: WebsiteCacheMeasurementState? = nil,
        lastSuccessfulCleanupAt: Date?,
        isOperationInProgress: Bool
    ) {
        self.policy = policy
        self.estimatedBytes = estimatedBytes
        self.measurementState = measurementState
            ?? (estimatedBytes.map(WebsiteCacheMeasurementState.available) ?? .unavailable)
        self.lastSuccessfulCleanupAt = lastSuccessfulCleanupAt
        self.isOperationInProgress = isOperationInProgress
    }
}

enum WebsiteCacheManagementError: LocalizedError, Equatable {
    case unavailable
    case operationAlreadyRunning
    case applicationTerminating
    case activeProfileProtected
    case runtimeStillInUse

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Website cache management is unavailable."
        case .operationAlreadyRunning:
            return "Another cache operation is already in progress."
        case .applicationTerminating:
            return "FloatTabs is closing and cannot start a cache operation."
        case .activeProfileProtected:
            return "The active page is still in use. Hide FloatTabs and try again."
        case .runtimeStillInUse:
            return "FloatTabs could not release the active page runtime safely."
        }
    }
}

@MainActor
struct WebsiteCacheManagementClient {
    typealias SnapshotHandler = () -> WebsiteCacheSettingsSnapshot
    typealias UpdatePolicyHandler = (WebsiteCachePolicy) -> Void
    typealias BeginMeasurementHandler = () -> Void
    typealias RefreshMeasurementHandler = () async -> Void
    typealias ReleaseCacheHandler = () async throws -> WebsiteCacheCleanupResult

    private let snapshotHandler: SnapshotHandler
    private let updatePolicyHandler: UpdatePolicyHandler
    private let beginMeasurementHandler: BeginMeasurementHandler
    private let refreshMeasurementHandler: RefreshMeasurementHandler
    private let releaseCacheHandler: ReleaseCacheHandler
    let isAvailable: Bool

    init(
        snapshot: @escaping SnapshotHandler,
        updatePolicy: @escaping UpdatePolicyHandler,
        beginMeasurement: @escaping BeginMeasurementHandler = {},
        refreshMeasurement: @escaping RefreshMeasurementHandler = {},
        releaseCache: @escaping ReleaseCacheHandler,
        isAvailable: Bool = true
    ) {
        snapshotHandler = snapshot
        updatePolicyHandler = updatePolicy
        beginMeasurementHandler = beginMeasurement
        refreshMeasurementHandler = refreshMeasurement
        releaseCacheHandler = releaseCache
        self.isAvailable = isAvailable
    }

    static let unavailable = WebsiteCacheManagementClient(
        snapshot: { WebsiteCacheSettingsSnapshot(
            policy: .default,
            estimatedBytes: nil,
            lastSuccessfulCleanupAt: nil,
            isOperationInProgress: false
        ) },
        updatePolicy: { _ in },
        beginMeasurement: {},
        refreshMeasurement: {},
        releaseCache: { throw WebsiteCacheManagementError.unavailable },
        isAvailable: false
    )

    func snapshot() -> WebsiteCacheSettingsSnapshot { snapshotHandler() }

    func updatePolicy(_ policy: WebsiteCachePolicy) { updatePolicyHandler(policy) }

    func beginMeasurement() { beginMeasurementHandler() }

    func refreshMeasurement() async { await refreshMeasurementHandler() }

    func releaseCache() async throws -> WebsiteCacheCleanupResult {
        try await releaseCacheHandler()
    }
}

struct WebsiteCacheAutomaticSchedulePolicy: Equatable {
    static let initialDelay: TimeInterval = 45
    static let operationCollisionBackoff: TimeInterval = 45

    static func collisionRetryDelay(
        configured: TimeInterval = operationCollisionBackoff
    ) -> TimeInterval {
        guard configured.isFinite else { return operationCollisionBackoff }
        return max(0.001, configured)
    }

    static func nextDelay(
        now: Date,
        lastAutomaticCheckAt: Date?,
        lastAutomaticFailureAt: Date? = nil,
        minimumCleanupInterval: TimeInterval,
        automaticCleanupEnabled: Bool,
        initialDelay: TimeInterval = Self.initialDelay
    ) -> TimeInterval? {
        guard automaticCleanupEnabled else { return nil }
        // A failed attempt is still an attempt. Keep a persisted failure
        // marker as a defensive backoff source if the check marker is ever
        // lost or partially written, so a failure cannot create a retry loop.
        let lastAttempt = [lastAutomaticCheckAt, lastAutomaticFailureAt]
            .compactMap { $0 }
            .max()
        guard let lastAttempt else { return max(0, initialDelay) }
        return max(
            0,
            lastAttempt.addingTimeInterval(max(0, minimumCleanupInterval))
                .timeIntervalSince(now)
        )
    }
}

/// Pure loop state used by AppCoordinator. Keeping the collision override
/// outside the persisted timestamp calculation prevents an expired timestamp
/// from turning an operation collision into a zero-delay polling loop.
struct WebsiteCacheAutomaticScheduleState: Equatable {
    private var isFirstSleep = true
    private var collisionRetryDelay: TimeInterval?

    mutating func nextDelay(
        now: Date,
        lastAutomaticCheckAt: Date?,
        lastAutomaticFailureAt: Date? = nil,
        minimumCleanupInterval: TimeInterval,
        automaticCleanupEnabled: Bool,
        initialDelay: TimeInterval?
    ) -> TimeInterval? {
        guard automaticCleanupEnabled else {
            collisionRetryDelay = nil
            return nil
        }
        if let collisionRetryDelay {
            self.collisionRetryDelay = nil
            return WebsiteCacheAutomaticSchedulePolicy.collisionRetryDelay(
                configured: collisionRetryDelay
            )
        }
        if isFirstSleep, let initialDelay {
            isFirstSleep = false
            return max(0, initialDelay)
        }
        isFirstSleep = false
        return WebsiteCacheAutomaticSchedulePolicy.nextDelay(
            now: now,
            lastAutomaticCheckAt: lastAutomaticCheckAt,
            lastAutomaticFailureAt: lastAutomaticFailureAt,
            minimumCleanupInterval: minimumCleanupInterval,
            automaticCleanupEnabled: automaticCleanupEnabled,
            initialDelay: WebsiteCacheAutomaticSchedulePolicy.initialDelay
        )
    }

    mutating func recordOperationAlreadyRunning() {
        collisionRetryDelay = WebsiteCacheAutomaticSchedulePolicy.operationCollisionBackoff
    }

    mutating func recordCompletedAttempt() {
        collisionRetryDelay = nil
    }
}

/// Serializes cleanup requests and coordinates policy decisions with runtime
/// release. The coordinator itself never reaches into a WebKit directory.
@MainActor
final class WebsiteCacheCleanupCoordinator {
    typealias ProfilesProvider = @MainActor () -> [WebsiteCacheProfileSnapshot]
    typealias ActiveIdentityProvider = @MainActor () -> BrowserProfileIdentity?
    typealias PanelVisibilityProvider = @MainActor () -> Bool
    typealias RuntimePreparation = @MainActor (BrowserProfileIdentity, Bool) throws -> Void
    typealias RuntimeRestore = @MainActor () -> Void

    private let preferencesStore: AppPreferencesStore
    private let usageStore: WebsiteCacheUsageStore
    private let service: WebsiteCacheCleanupService
    private let sizeMeasurer: WebsiteCacheSizeMeasurer
    private let profilesProvider: ProfilesProvider
    private let activeIdentityProvider: ActiveIdentityProvider
    private let panelVisibilityProvider: PanelVisibilityProvider
    private let prepareRuntime: RuntimePreparation
    private let restoreRuntime: RuntimeRestore

    private(set) var isOperationInProgress = false
    private(set) var measurementState: WebsiteCacheMeasurementState = .calculating
    var onPolicyChanged: (() -> Void)?
    private var isTerminating = false
    private var measurementGeneration: UInt = 0

    init(
        preferencesStore: AppPreferencesStore,
        usageStore: WebsiteCacheUsageStore,
        service: WebsiteCacheCleanupService,
        sizeMeasurer: WebsiteCacheSizeMeasurer = WebsiteCacheSizeMeasurer(),
        profilesProvider: @escaping ProfilesProvider,
        activeIdentityProvider: @escaping ActiveIdentityProvider,
        panelVisibilityProvider: @escaping PanelVisibilityProvider,
        prepareRuntime: @escaping RuntimePreparation,
        restoreRuntime: @escaping RuntimeRestore
    ) {
        self.preferencesStore = preferencesStore
        self.usageStore = usageStore
        self.service = service
        self.sizeMeasurer = sizeMeasurer
        self.profilesProvider = profilesProvider
        self.activeIdentityProvider = activeIdentityProvider
        self.panelVisibilityProvider = panelVisibilityProvider
        self.prepareRuntime = prepareRuntime
        self.restoreRuntime = restoreRuntime
    }

    var client: WebsiteCacheManagementClient {
        WebsiteCacheManagementClient(
            snapshot: { [weak self] in self?.settingsSnapshot ?? WebsiteCacheSettingsSnapshot(
                policy: .default,
                estimatedBytes: nil,
                measurementState: .unavailable,
                lastSuccessfulCleanupAt: nil,
                isOperationInProgress: false
            ) },
            updatePolicy: { [weak self] policy in
                self?.preferencesStore.websiteCachePolicy = policy
                self?.onPolicyChanged?()
            },
            beginMeasurement: { [weak self] in
                self?.beginMeasurement()
            },
            refreshMeasurement: { [weak self] in
                _ = await self?.refreshMeasurement()
            },
            releaseCache: { [weak self] in
                guard let self else { throw WebsiteCacheManagementError.unavailable }
                return try await self.runManualRelease()
            }
        )
    }

    var settingsSnapshot: WebsiteCacheSettingsSnapshot {
        WebsiteCacheSettingsSnapshot(
            policy: preferencesStore.websiteCachePolicy,
            estimatedBytes: measurementState.estimatedBytes,
            measurementState: measurementState,
            lastSuccessfulCleanupAt: usageStore.lastSuccessfulCleanupAt,
            isOperationInProgress: isOperationInProgress
        )
    }

    func stop() {
        isTerminating = true
        measurementGeneration &+= 1
    }

    var automaticCleanupEnabled: Bool {
        preferencesStore.websiteCachePolicy.automaticCleanupEnabled
    }

    var lastAutomaticCheckAt: Date? {
        usageStore.lastAutomaticCheckAt
    }

    var lastAutomaticFailureAt: Date? {
        usageStore.lastAutomaticFailureAt
    }

    var minimumCleanupInterval: TimeInterval {
        preferencesStore.websiteCachePolicy.normalized().minimumCleanupInterval
    }

    func beginMeasurement() {
        measurementGeneration &+= 1
        measurementState = .calculating
    }

    @discardableResult
    func refreshMeasurement() async -> WebsiteCacheMeasurementState {
        beginMeasurement()
        let generation = measurementGeneration
        let measuredBytes = await sizeMeasurer.estimate()
        let localResult = measuredBytes.map(WebsiteCacheMeasurementState.available) ?? .unavailable
        if generation == measurementGeneration {
            measurementState = localResult
        }
        return localResult
    }

    func nextAutomaticCheckDelay(
        now: Date = Date(),
        initialDelay: TimeInterval = WebsiteCacheAutomaticSchedulePolicy.initialDelay
    ) -> TimeInterval? {
        let policy = preferencesStore.websiteCachePolicy.normalized()
        return WebsiteCacheAutomaticSchedulePolicy.nextDelay(
            now: now,
            lastAutomaticCheckAt: usageStore.lastAutomaticCheckAt,
            lastAutomaticFailureAt: usageStore.lastAutomaticFailureAt,
            minimumCleanupInterval: policy.minimumCleanupInterval,
            automaticCleanupEnabled: policy.automaticCleanupEnabled,
            initialDelay: initialDelay
        )
    }

    func runAutomaticIfNeeded(now: Date = Date()) async throws -> WebsiteCacheCleanupResult? {
        guard !isTerminating else { throw WebsiteCacheManagementError.applicationTerminating }
        let policy = preferencesStore.websiteCachePolicy
        guard policy.automaticCleanupEnabled else { return nil }
        if let lastCheck = usageStore.lastAutomaticCheckAt,
           now.timeIntervalSince(lastCheck) < policy.minimumCleanupInterval {
            return nil
        }

        do {
            let result = try await run(
                policy: policy,
                now: now,
                mode: .automatic
            )
            usageStore.lastAutomaticCheckAt = now
            usageStore.lastAutomaticFailureAt = nil
            return result
        } catch WebsiteCacheManagementError.operationAlreadyRunning {
            throw WebsiteCacheManagementError.operationAlreadyRunning
        } catch {
            // Persist the completed attempt for backoff, but never update the
            // successful-cleanup marker on failure.
            usageStore.lastAutomaticCheckAt = now
            usageStore.lastAutomaticFailureAt = now
            throw error
        }
    }

    func runManualRelease(now: Date = Date()) async throws -> WebsiteCacheCleanupResult {
        guard !isTerminating else { throw WebsiteCacheManagementError.applicationTerminating }
        return try await run(
            policy: preferencesStore.websiteCachePolicy,
            now: now,
            mode: .manual
        )
    }

    private enum RunMode: Equatable {
        case automatic
        case manual
    }

    private func run(
        policy rawPolicy: WebsiteCachePolicy,
        now: Date,
        mode: RunMode
    ) async throws -> WebsiteCacheCleanupResult {
        guard !isOperationInProgress else {
            throw WebsiteCacheManagementError.operationAlreadyRunning
        }
        isOperationInProgress = true
        defer { isOperationInProgress = false }

        let policy = rawPolicy.normalized()
        let before = (await refreshMeasurement()).estimatedBytes
        let capacityTriggered = policy.shouldTriggerCapacity(estimatedBytes: before)
        let activeIdentity = activeIdentityProvider()
        let profiles = profilesProvider().map { profile in
            WebsiteCacheProfileSnapshot(
                identity: profile.identity,
                lastUsedAt: profile.lastUsedAt,
                useCount: profile.useCount,
                isActive: profile.isActive || profile.identity == activeIdentity
            )
        }
        let candidates = sortedCandidates(
            profiles: profiles,
            now: now,
            policy: policy,
            mode: mode,
            capacityTriggered: capacityTriggered
        )

        var cleanedProfiles = 0
        var cleanedRecords = 0
        var skippedActive = 0
        var after = before
        var releasedActiveRuntime = false
        var successfullyCleanedIdentities: [BrowserProfileIdentity] = []

        do {
            for candidate in candidates {
                if mode == .automatic,
                   candidate.isActive,
                   panelVisibilityProvider() {
                    skippedActive += 1
                    continue
                }

                do {
                    try prepareRuntime(candidate.identity, mode == .manual)
                    releasedActiveRuntime = releasedActiveRuntime || candidate.isActive
                } catch let error as WebsiteCacheManagementError {
                    if mode == .automatic,
                       candidate.isActive,
                       (error == .activeProfileProtected || error == .runtimeStillInUse) {
                        skippedActive += 1
                        continue
                    }
                    throw error
                } catch {
                    if mode == .automatic { continue }
                    throw WebsiteCacheManagementError.runtimeStillInUse
                }

                let cleanup = try await service.clean(identity: candidate.identity)
                cleanedProfiles += 1
                cleanedRecords += cleanup.recordCount
                successfullyCleanedIdentities.append(candidate.identity)
                after = (await refreshMeasurement()).estimatedBytes

                guard mode == .automatic, capacityTriggered else { continue }
                if policy.hasReachedTarget(estimatedBytes: after) || after == nil {
                    break
                }
            }
        } catch {
            if releasedActiveRuntime { restoreRuntime() }
            throw error
        }

        if releasedActiveRuntime { restoreRuntime() }
        let completedAt = now
        if cleanedProfiles > 0 || mode == .manual {
            // Persist success markers only after the whole run succeeds. If a
            // later profile fails, the caller gets an error and no successful
            // cleanup timestamp is advanced for a partially completed run.
            for identity in successfullyCleanedIdentities {
                usageStore.markCleanupSucceeded(for: identity, at: completedAt)
            }
            usageStore.markRunSucceeded(at: completedAt)
        }
        return WebsiteCacheCleanupResult(
            estimatedBytesBefore: before,
            estimatedBytesAfter: after,
            cleanedProfileCount: cleanedProfiles,
            cleanedRecordCount: cleanedRecords,
            skippedActiveProfileCount: skippedActive,
            completedAt: completedAt
        )
    }

    private func sortedCandidates(
        profiles: [WebsiteCacheProfileSnapshot],
        now: Date,
        policy: WebsiteCachePolicy,
        mode: RunMode,
        capacityTriggered: Bool
    ) -> [WebsiteCacheProfileSnapshot] {
        profiles
            .filter { candidate in
                guard mode == .manual else {
                    let expired = policy.isPastRetention(
                        lastUsedAt: candidate.lastUsedAt,
                        now: now
                    )
                    let capacityEligible = capacityTriggered
                        && !policy.isProtectedByRecentUse(
                            lastUsedAt: candidate.lastUsedAt,
                            now: now
                        )
                    return expired || capacityEligible
                }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive { return !lhs.isActive }
                let lhsExpired = policy.isPastRetention(
                    lastUsedAt: lhs.lastUsedAt,
                    now: now
                )
                let rhsExpired = policy.isPastRetention(
                    lastUsedAt: rhs.lastUsedAt,
                    now: now
                )
                if lhsExpired != rhsExpired { return lhsExpired }
                let lhsScore = WebsiteCachePolicy.evictionScore(
                    lastUsedAt: lhs.lastUsedAt,
                    useCount30Days: lhs.useCount,
                    now: now
                )
                let rhsScore = WebsiteCachePolicy.evictionScore(
                    lastUsedAt: rhs.lastUsedAt,
                    useCount30Days: rhs.useCount,
                    now: now
                )
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                if lhs.useCount != rhs.useCount {
                    return lhs.useCount < rhs.useCount
                }
                return lhs.identity.storageKey < rhs.identity.storageKey
            }
    }
}
