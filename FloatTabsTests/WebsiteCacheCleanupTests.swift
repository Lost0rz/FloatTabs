import AppKit
import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class WebsiteCacheCleanupTests: XCTestCase, @unchecked Sendable {
    private var defaults: UserDefaults!
    private var suiteName: String!

    nonisolated override func setUp() {
        MainActor.assumeIsolated {
            super.setUp()
            suiteName = "FloatTabsTests.WebsiteCacheCleanup.\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suiteName)
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            defaults.removePersistentDomain(forName: suiteName)
            defaults = nil
            suiteName = nil
            super.tearDown()
        }
    }

    func testOnlySafeWebKitTypesAreRequested() async throws {
        var fetchedTypes: Set<String>?
        var removedTypes: Set<String>?
        let store = WKWebsiteDataStore.nonPersistent()
        let service = WebsiteCacheCleanupService(
            dataStoreResolver: { _ in store },
            fetchRecords: { _, types, completion in
                fetchedTypes = types
                completion([])
            },
            removeData: { _, types, _ in removedTypes = types }
        )

        _ = try await service.clean(identity: .default)

        XCTAssertEqual(fetchedTypes, WebsiteCacheDataTypes.removable)
        XCTAssertEqual(removedTypes, WebsiteCacheDataTypes.removable)
        XCTAssertFalse(fetchedTypes?.contains(WKWebsiteDataTypeCookies) == true)
        XCTAssertFalse(fetchedTypes?.contains(WKWebsiteDataTypeLocalStorage) == true)
        XCTAssertFalse(fetchedTypes?.contains(WKWebsiteDataTypeIndexedDBDatabases) == true)
        XCTAssertFalse(fetchedTypes?.contains(WKWebsiteDataTypeServiceWorkerRegistrations) == true)
    }

    func testPolicyDefaultsAndInvalidPreferenceValuesNormalize() {
        let store = AppPreferencesStore(defaults: defaults)
        XCTAssertTrue(store.websiteCachePolicy.automaticCleanupEnabled)
        XCTAssertEqual(store.websiteCachePolicy.retentionDays, 30)
        XCTAssertEqual(
            store.websiteCachePolicy.maximumEstimatedBytes,
            WebsiteCachePolicy.defaultMaximumEstimatedBytes
        )
        XCTAssertEqual(
            store.websiteCachePolicy.targetEstimatedBytes,
            WebsiteCachePolicy.defaultTargetEstimatedBytes
        )

        defaults.set(4, forKey: AppPreferencesStore.websiteCacheRetentionDaysKey)
        defaults.set(-4, forKey: AppPreferencesStore.websiteCacheMaximumEstimatedBytesKey)
        defaults.set(Double.nan, forKey: AppPreferencesStore.websiteCacheRecentUseProtectionKey)

        XCTAssertEqual(store.websiteCachePolicy.retentionDays, 30)
        XCTAssertEqual(
            store.websiteCachePolicy.maximumEstimatedBytes,
            WebsiteCachePolicy.defaultMaximumEstimatedBytes
        )
        XCTAssertEqual(
            store.websiteCachePolicy.recentUseProtection,
            WebsiteCachePolicy.defaultRecentUseProtection
        )
    }

    func testTTLDoesNotRunBeforeRetentionAndRunsWhenExpired() async throws {
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.websiteCachePolicy = WebsiteCachePolicy(
            retentionDays: 30,
            maximumEstimatedBytes: nil,
            targetEstimatedBytes: 0
        )
        let usage = WebsiteCacheUsageStore(defaults: defaults)
        let oldID = BrowserProfileIdentity.custom(UUID())
        let cleaned = IdentityBox()
        let service = makeService(cleaned: cleaned)
        let now = Date(timeIntervalSince1970: 10_000_000)
        var recent = true
        let coordinator = makeCoordinator(
            preferences: preferences,
            usage: usage,
            service: service,
            profiles: {
                [WebsiteCacheProfileSnapshot(
                    identity: oldID,
                    lastUsedAt: now.addingTimeInterval(recent ? -10 * 24 * 60 * 60 : -40 * 24 * 60 * 60),
                    useCount: 1,
                    isActive: false
                )]
            }
        )

        let beforeRetention = try await coordinator.runAutomaticIfNeeded(now: now)
        XCTAssertEqual(beforeRetention?.cleanedProfileCount, 0)
        recent = false
        let afterRetention = try await coordinator.runAutomaticIfNeeded(
            now: now.addingTimeInterval(24 * 60 * 60)
        )
        XCTAssertEqual(afterRetention?.cleanedProfileCount, 1)
        XCTAssertEqual(cleaned.values, [oldID])
    }

    func testAutomaticChecksAreThrottledForTwentyFourHours() async throws {
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.websiteCachePolicy = WebsiteCachePolicy(
            retentionDays: nil,
            maximumEstimatedBytes: nil,
            minimumCleanupInterval: WebsiteCachePolicy.defaultMinimumCleanupInterval
        )
        let usage = WebsiteCacheUsageStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 30_000_000)
        usage.lastAutomaticCheckAt = now
        let coordinator = makeCoordinator(
            preferences: preferences,
            usage: usage,
            service: makeService(cleaned: IdentityBox()),
            profiles: { [] }
        )

        let throttledResult = try await coordinator.runAutomaticIfNeeded(
            now: now.addingTimeInterval(60 * 60)
        )
        XCTAssertNil(throttledResult)
        let eligibleResult = try await coordinator.runAutomaticIfNeeded(
            now: now.addingTimeInterval(24 * 60 * 60)
        )
        XCTAssertNotNil(eligibleResult)
    }

    func testCapacityStopsAtTargetAndProtectsActiveProfile() async throws {
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.websiteCachePolicy = WebsiteCachePolicy(
            retentionDays: nil,
            maximumEstimatedBytes: 1_500,
            targetEstimatedBytes: 1_000,
            minimumCleanupInterval: 0,
            recentUseProtection: 0
        )
        let usage = WebsiteCacheUsageStore(defaults: defaults)
        let old = BrowserProfileIdentity.custom(UUID())
        let other = BrowserProfileIdentity.custom(UUID())
        let active = BrowserProfileIdentity.custom(UUID())
        let cleaned = IdentityBox()
        let estimates = EstimateBox([2_000, 1_400, 900])
        let service = makeService(cleaned: cleaned)
        let coordinator = makeCoordinator(
            preferences: preferences,
            usage: usage,
            service: service,
            estimates: { estimates.next() },
            panelVisible: true,
            profiles: {
                [
                    WebsiteCacheProfileSnapshot(identity: active, lastUsedAt: .distantPast, useCount: 0, isActive: true),
                    WebsiteCacheProfileSnapshot(identity: old, lastUsedAt: .distantPast, useCount: 1, isActive: false),
                    WebsiteCacheProfileSnapshot(identity: other, lastUsedAt: Date(timeIntervalSince1970: 1), useCount: 2, isActive: false),
                ]
            }
        )

        let result = try await coordinator.runAutomaticIfNeeded(now: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(cleaned.values, [old, other])
        XCTAssertEqual(result?.cleanedProfileCount, 2)
        XCTAssertFalse(cleaned.values.contains(active))
        XCTAssertEqual(result?.estimatedBytesAfter, 900)
    }

    func testUnknownSizeStillRunsTTLAndFailedRunDoesNotSetSuccessTime() async throws {
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.websiteCachePolicy = WebsiteCachePolicy(
            retentionDays: 7,
            maximumEstimatedBytes: 500,
            targetEstimatedBytes: 100,
            minimumCleanupInterval: 0
        )
        let usage = WebsiteCacheUsageStore(defaults: defaults)
        let id = BrowserProfileIdentity.custom(UUID())
        let now = Date(timeIntervalSince1970: 20_000_000)
        var shouldFail = true
        let store = WKWebsiteDataStore.nonPersistent()
        let service = WebsiteCacheCleanupService(
            dataStoreResolver: { _ in
                if shouldFail { throw TestError.injected }
                return store
            },
            fetchRecords: { _, _, completion in completion([]) },
            removeData: { _, _, _ in }
        )
        let coordinator = makeCoordinator(
            preferences: preferences,
            usage: usage,
            service: service,
            estimates: { nil },
            profiles: {
                [WebsiteCacheProfileSnapshot(identity: id, lastUsedAt: now.addingTimeInterval(-8 * 24 * 60 * 60), useCount: 1, isActive: false)]
            }
        )

        do {
            _ = try await coordinator.runAutomaticIfNeeded(now: now)
            XCTFail("Expected injected cleanup failure")
        } catch {
            XCTAssertNil(usage.lastSuccessfulCleanupAt)
            XCTAssertEqual(usage.lastAutomaticFailureAt, now)
        }

        shouldFail = false
        let result = try await coordinator.runAutomaticIfNeeded(now: now.addingTimeInterval(1))
        XCTAssertEqual(result?.cleanedProfileCount, 1)
        XCTAssertNotNil(usage.lastSuccessfulCleanupAt)
        XCTAssertNil(usage.lastAutomaticFailureAt)
    }

    func testDefaultAndCustomIdentitiesUseInjectedStores() async throws {
        let defaultStore = WKWebsiteDataStore.nonPersistent()
        let customStore = WKWebsiteDataStore.nonPersistent()
        var received: [BrowserProfileIdentity: WKWebsiteDataStore] = [:]
        let customID = UUID()
        let service = WebsiteCacheCleanupService(
            dataStoreResolver: { identity in
                let store = identity == .default ? defaultStore : customStore
                received[identity] = store
                return store
            },
            fetchRecords: { _, _, completion in completion([]) },
            removeData: { _, _, _ in }
        )

        _ = try await service.clean(identity: .default)
        _ = try await service.clean(identity: .custom(customID))

        XCTAssertTrue(received[.default] === defaultStore)
        XCTAssertTrue(received[.custom(customID)] === customStore)
    }

    func testRuntimeReleasePrecedesWebKitCleanupAndManualReleaseRestoresPage() async throws {
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.websiteCachePolicy = WebsiteCachePolicy(
            retentionDays: nil,
            maximumEstimatedBytes: nil
        )
        let usage = WebsiteCacheUsageStore(defaults: defaults)
        let identity = BrowserProfileIdentity.custom(UUID())
        let events = EventBox()
        let service = WebsiteCacheCleanupService(
            dataStoreResolver: { _ in
                events.values.append("resolve")
                return WKWebsiteDataStore.nonPersistent()
            },
            fetchRecords: { _, _, completion in
                events.values.append("fetch")
                completion([])
            },
            removeData: { _, _, _ in events.values.append("remove") }
        )
        let coordinator = makeCoordinator(
            preferences: preferences,
            usage: usage,
            service: service,
            profiles: {
                [WebsiteCacheProfileSnapshot(
                    identity: identity,
                    lastUsedAt: Date(),
                    useCount: 1,
                    isActive: true
                )]
            },
            prepareRuntime: { _, allowActive in
                XCTAssertTrue(allowActive)
                events.values.append("prepare")
            },
            restoreRuntime: {
                events.values.append("restore")
            }
        )

        _ = try await coordinator.runManualRelease()

        XCTAssertEqual(events.values, ["prepare", "resolve", "fetch", "remove", "restore"])
    }

    func testConcurrentCleanupRequestsAreRejectedWhileFirstRequestIsRunning() async throws {
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.websiteCachePolicy = WebsiteCachePolicy(
            retentionDays: nil,
            maximumEstimatedBytes: nil
        )
        let usage = WebsiteCacheUsageStore(defaults: defaults)
        let removeDataStarted = AsyncGate()
        let allowRemoveDataToFinish = AsyncGate()
        let identity = BrowserProfileIdentity.custom(UUID())
        let service = WebsiteCacheCleanupService(
            dataStoreResolver: { _ in WKWebsiteDataStore.nonPersistent() },
            fetchRecords: { _, _, completion in completion([]) },
            removeData: { _, _, _ in
                removeDataStarted.release()
                await allowRemoveDataToFinish.wait()
            }
        )
        let coordinator = makeCoordinator(
            preferences: preferences,
            usage: usage,
            service: service,
            profiles: {
                [WebsiteCacheProfileSnapshot(
                    identity: identity,
                    lastUsedAt: Date(),
                    useCount: 1,
                    isActive: false
                )]
            }
        )

        let firstRequest = Task { try await coordinator.runManualRelease() }
        await removeDataStarted.wait()
        XCTAssertTrue(coordinator.isOperationInProgress)

        do {
            _ = try await coordinator.runAutomaticIfNeeded(
                now: Date(timeIntervalSince1970: 50_000_000)
            )
            XCTFail("Expected automatic cleanup collision to be rejected")
        } catch {
            XCTAssertEqual(error as? WebsiteCacheManagementError, .operationAlreadyRunning)
        }
        XCTAssertNil(usage.lastAutomaticCheckAt)
        XCTAssertNil(usage.lastSuccessfulCleanupAt)

        do {
            _ = try await coordinator.runManualRelease()
            XCTFail("Expected concurrent cleanup request to be rejected")
        } catch {
            XCTAssertEqual(error as? WebsiteCacheManagementError, .operationAlreadyRunning)
        }

        allowRemoveDataToFinish.release()
        _ = try await firstRequest.value
    }

    func testAsyncGateWaitThenReleaseResumesExactlyOnce() async {
        let gate = AsyncGate()
        let waiter = Task { await gate.wait() }
        for _ in 0..<1_000 where !gate.hasWaiter { await Task.yield() }
        XCTAssertTrue(gate.hasWaiter)

        gate.release()
        gate.release()
        await waiter.value
        XCTAssertFalse(gate.hasWaiter)
    }

    func testAsyncGateReleaseBeforeWaitUsesLatchState() async {
        let gate = AsyncGate()
        gate.release()
        gate.release()

        await gate.wait()
        XCTAssertFalse(gate.hasWaiter)
    }

    func testAsyncGateCancellationDoesNotLeaveAWaitingContinuation() async {
        let gate = AsyncGate()
        let waiter = Task { await gate.wait() }
        for _ in 0..<1_000 where !gate.hasWaiter { await Task.yield() }
        XCTAssertTrue(gate.hasWaiter)

        waiter.cancel()
        await waiter.value
        XCTAssertFalse(gate.hasWaiter)
    }

    func testSizeEstimatorFailsClosedOutsideFloatTabsScope() async {
        let unsafe = WebsiteCacheSizeMeasurer(
            rootURLsProvider: {
                [URL(fileURLWithPath: "/private/tmp/SomeOtherApp/WebKit/WebsiteData")]
            }
        )
        let unsafeEstimate = await unsafe.estimate()
        XCTAssertNil(unsafeEstimate)

        let knownMissingSandboxRoot = WebsiteCacheSizeMeasurer(
            rootURLsProvider: {
                [URL(fileURLWithPath: "/private/tmp/Library/Caches/com.lost0rz.FloatTabs/WebKit/NetworkCache")]
            }
        )
        let missingSandboxEstimate = await knownMissingSandboxRoot.estimate()
        XCTAssertEqual(missingSandboxEstimate, 0)

        let knownMissingNonSandboxRoot = WebsiteCacheSizeMeasurer(
            rootURLsProvider: {
                [URL(fileURLWithPath: "/private/tmp/Library/Containers/com.lost0rz.FloatTabs/Data/Library/Caches/com.lost0rz.FloatTabs/WebKit/CacheStorage")]
            }
        )
        let missingNonSandboxEstimate = await knownMissingNonSandboxRoot.estimate()
        XCTAssertEqual(missingNonSandboxEstimate, 0)
    }

    func testSettingsClientShowsSnapshotDisablesBusyReleaseAndPersistsPolicyChange() {
        var policy = WebsiteCachePolicy(
            automaticCleanupEnabled: false,
            retentionDays: 7,
            maximumEstimatedBytes: WebsiteCacheLimitOption.megabytes500.bytes
        )
        var isBusy = true
        let manager = WebsiteCacheManagementClient(
            snapshot: {
                WebsiteCacheSettingsSnapshot(
                    policy: policy,
                    estimatedBytes: 1_500_000_000,
                    lastSuccessfulCleanupAt: Date(timeIntervalSince1970: 1),
                    isOperationInProgress: isBusy
                )
            },
            updatePolicy: { policy = $0 },
            releaseCache: {
                WebsiteCacheCleanupResult(
                    estimatedBytesBefore: 2_000,
                    estimatedBytesAfter: 1_000,
                    cleanedProfileCount: 1,
                    cleanedRecordCount: 2,
                    skippedActiveProfileCount: 0,
                    completedAt: Date()
                )
            }
        )
        let controller = AccountLanguageSettingsViewController(
            onExportBackup: { _ in },
            onRestoreBackup: { _ in URL(fileURLWithPath: "/tmp/rollback.json") },
            websiteCacheManager: manager
        )

        controller.loadView()

        XCTAssertNotEqual(controller.displayedWebsiteCacheUsage, "Unavailable")
        XCTAssertNotEqual(controller.displayedWebsiteCacheLastCleanup, "Never")
        XCTAssertFalse(controller.isReleaseCacheEnabled)

        isBusy = false
        controller.refreshWebsiteCache()
        XCTAssertTrue(controller.isReleaseCacheEnabled)

        var changedPolicy = policy
        changedPolicy.retentionDays = 90
        manager.updatePolicy(changedPolicy)
        XCTAssertEqual(policy.retentionDays, 90)

        let message = AccountLanguageSettingsViewController.cleanupResultText(
            WebsiteCacheCleanupResult(
                estimatedBytesBefore: 2_000,
                estimatedBytesAfter: 1_000,
                cleanedProfileCount: 1,
                cleanedRecordCount: 2,
                skippedActiveProfileCount: 0,
                completedAt: Date()
            )
        )
        XCTAssertTrue(message.contains("Released"))
    }

    func testAutomaticScheduleUsesInitialDelayIntervalAndDisabledState() {
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(
            WebsiteCacheAutomaticSchedulePolicy.nextDelay(
                now: now,
                lastAutomaticCheckAt: nil,
                minimumCleanupInterval: 86_400,
                automaticCleanupEnabled: true
            ),
            45
        )
        XCTAssertEqual(
            WebsiteCacheAutomaticSchedulePolicy.nextDelay(
                now: now,
                lastAutomaticCheckAt: now.addingTimeInterval(-3_600),
                minimumCleanupInterval: 86_400,
                automaticCleanupEnabled: true
            ),
            82_800
        )
        XCTAssertEqual(
            WebsiteCacheAutomaticSchedulePolicy.nextDelay(
                now: now,
                lastAutomaticCheckAt: nil,
                lastAutomaticFailureAt: now,
                minimumCleanupInterval: 86_400,
                automaticCleanupEnabled: true
            ),
            86_400
        )
        XCTAssertNil(
            WebsiteCacheAutomaticSchedulePolicy.nextDelay(
                now: now,
                lastAutomaticCheckAt: nil,
                minimumCleanupInterval: 86_400,
                automaticCleanupEnabled: false
            )
        )
    }

    func testAutomaticCollisionUsesPositiveRetryWithoutUpdatingSuccessTime() {
        let now = Date(timeIntervalSince1970: 100)
        var state = WebsiteCacheAutomaticScheduleState()

        XCTAssertEqual(
            state.nextDelay(
                now: now,
                lastAutomaticCheckAt: now.addingTimeInterval(-2 * 86_400),
                minimumCleanupInterval: 86_400,
                automaticCleanupEnabled: true,
                initialDelay: 0
            ),
            0
        )

        state.recordOperationAlreadyRunning()
        let retry = state.nextDelay(
            now: now,
            lastAutomaticCheckAt: now.addingTimeInterval(-2 * 86_400),
            minimumCleanupInterval: 86_400,
            automaticCleanupEnabled: true,
            initialDelay: 0
        )
        XCTAssertEqual(retry, WebsiteCacheAutomaticSchedulePolicy.operationCollisionBackoff)
        XCTAssertGreaterThan(retry ?? 0, 0)
        XCTAssertGreaterThan(
            WebsiteCacheAutomaticSchedulePolicy.collisionRetryDelay(configured: 0),
            0
        )
    }

    func testAutomaticSchedulerCollisionBackoffIsAppliedAtLoopLevel() async {
        let now = Date(timeIntervalSince1970: 100)
        let sleeper = ControlledSleeper()
        var cleanupCount = 0
        let scheduler = WebsiteCacheAutomaticScheduler(
            snapshotProvider: {
                WebsiteCacheAutomaticScheduleSnapshot(
                    now: now,
                    lastAutomaticCheckAt: now.addingTimeInterval(-2 * 86_400),
                    lastAutomaticFailureAt: nil,
                    minimumCleanupInterval: 86_400,
                    automaticCleanupEnabled: true
                )
            },
            sleeper: { delay in try await sleeper.sleep(delay) },
            cleanup: {
                cleanupCount += 1
                throw WebsiteCacheManagementError.operationAlreadyRunning
            }
        )

        let task = Task { await scheduler.run(initialDelay: 0) }
        await sleeper.waitUntilSleepCount(1)
        XCTAssertEqual(sleeper.delays, [0])
        sleeper.release()

        await sleeper.waitUntilSleepCount(2)
        XCTAssertEqual(cleanupCount, 1)
        XCTAssertEqual(sleeper.delays[1], WebsiteCacheAutomaticSchedulePolicy.operationCollisionBackoff)
        XCTAssertGreaterThan(sleeper.delays[1], 0)
        sleeper.release()

        await sleeper.waitUntilSleepCount(3)
        XCTAssertEqual(cleanupCount, 2)
        XCTAssertEqual(sleeper.delays[2], WebsiteCacheAutomaticSchedulePolicy.operationCollisionBackoff)
        XCTAssertGreaterThan(sleeper.delays[2], 0)

        task.cancel()
        await task.value
        XCTAssertEqual(cleanupCount, 2)
    }

    func testAutomaticSchedulerCancellationDuringSleeperStopsWithoutCleanup() async {
        let sleeper = ControlledSleeper()
        var cleanupCount = 0
        let scheduler = WebsiteCacheAutomaticScheduler(
            snapshotProvider: {
                WebsiteCacheAutomaticScheduleSnapshot(
                    now: Date(timeIntervalSince1970: 200),
                    lastAutomaticCheckAt: nil,
                    lastAutomaticFailureAt: nil,
                    minimumCleanupInterval: 86_400,
                    automaticCleanupEnabled: true
                )
            },
            sleeper: { delay in try await sleeper.sleep(delay) },
            cleanup: { cleanupCount += 1 }
        )

        let task = Task { await scheduler.run(initialDelay: 0) }
        await sleeper.waitUntilSleepCount(1)
        task.cancel()
        await task.value

        XCTAssertEqual(sleeper.delays.count, 1)
        XCTAssertEqual(cleanupCount, 0)
    }

    func testAutomaticSchedulerStopsAfterShutdownSnapshot() async {
        let sleeper = ControlledSleeper()
        var isShutdown = false
        var cleanupCount = 0
        let scheduler = WebsiteCacheAutomaticScheduler(
            snapshotProvider: {
                guard !isShutdown else { return nil }
                return WebsiteCacheAutomaticScheduleSnapshot(
                    now: Date(timeIntervalSince1970: 300),
                    lastAutomaticCheckAt: nil,
                    lastAutomaticFailureAt: nil,
                    minimumCleanupInterval: 86_400,
                    automaticCleanupEnabled: true
                )
            },
            sleeper: { delay in try await sleeper.sleep(delay) },
            cleanup: { cleanupCount += 1 }
        )

        let task = Task { await scheduler.run(initialDelay: 0) }
        await sleeper.waitUntilSleepCount(1)
        isShutdown = true
        sleeper.release()
        await task.value

        XCTAssertEqual(cleanupCount, 0)
    }

    func testAutomaticSchedulerSleeperCancellationErrorStopsWithoutRetry() async {
        var sleeperCallCount = 0
        var cleanupCount = 0
        let scheduler = WebsiteCacheAutomaticScheduler(
            snapshotProvider: {
                WebsiteCacheAutomaticScheduleSnapshot(
                    now: Date(timeIntervalSince1970: 400),
                    lastAutomaticCheckAt: nil,
                    lastAutomaticFailureAt: nil,
                    minimumCleanupInterval: 86_400,
                    automaticCleanupEnabled: true
                )
            },
            sleeper: { _ in
                sleeperCallCount += 1
                throw CancellationError()
            },
            cleanup: { cleanupCount += 1 }
        )

        await scheduler.run(initialDelay: 0)

        XCTAssertEqual(sleeperCallCount, 1)
        XCTAssertEqual(cleanupCount, 0)
    }

    func testAutomaticSchedulerSuccessfulAttemptUsesNormalInterval() async {
        let now = Date(timeIntervalSince1970: 500)
        let sleeper = ControlledSleeper()
        var lastCheck: Date?
        var cleanupCount = 0
        let scheduler = WebsiteCacheAutomaticScheduler(
            snapshotProvider: {
                WebsiteCacheAutomaticScheduleSnapshot(
                    now: now,
                    lastAutomaticCheckAt: lastCheck,
                    lastAutomaticFailureAt: nil,
                    minimumCleanupInterval: 86_400,
                    automaticCleanupEnabled: true
                )
            },
            sleeper: { delay in try await sleeper.sleep(delay) },
            cleanup: {
                cleanupCount += 1
                lastCheck = now
            }
        )

        let task = Task { await scheduler.run(initialDelay: 0) }
        await sleeper.waitUntilSleepCount(1)
        sleeper.release()
        await sleeper.waitUntilSleepCount(2)

        XCTAssertEqual(cleanupCount, 1)
        XCTAssertEqual(sleeper.delays[1], 86_400)
        task.cancel()
        await task.value
    }

    func testConcurrentRefreshesReturnLocalResultsAndKeepNewestSharedState() async {
        let preferences = AppPreferencesStore(defaults: defaults)
        let usage = WebsiteCacheUsageStore(defaults: defaults)
        let estimates = ControlledEstimateBox([100, 200])
        let coordinator = makeCoordinator(
            preferences: preferences,
            usage: usage,
            service: makeService(cleaned: IdentityBox()),
            estimates: { estimates.next() },
            profiles: { [] }
        )

        let olderRequest = Task { await coordinator.refreshMeasurement() }
        for _ in 0..<10_000 where estimates.callCount < 1 { await Task.yield() }
        XCTAssertEqual(estimates.callCount, 1)

        let newerRequest = Task { await coordinator.refreshMeasurement() }
        for _ in 0..<10_000 where estimates.callCount < 2 { await Task.yield() }
        XCTAssertEqual(estimates.callCount, 2)

        estimates.release(index: 1)
        let newerResult = await newerRequest.value
        estimates.release(index: 0)
        let olderResult = await olderRequest.value

        XCTAssertEqual(newerResult, .available(200))
        XCTAssertEqual(olderResult, .available(100))
        XCTAssertEqual(coordinator.measurementState, .available(200))
    }

    func testConcurrentRefreshUnavailableResultStillReturnsToItsCaller() async {
        let preferences = AppPreferencesStore(defaults: defaults)
        let usage = WebsiteCacheUsageStore(defaults: defaults)
        let estimates = ControlledEstimateBox([nil, 300])
        let coordinator = makeCoordinator(
            preferences: preferences,
            usage: usage,
            service: makeService(cleaned: IdentityBox()),
            estimates: { estimates.next() },
            profiles: { [] }
        )

        let olderRequest = Task { await coordinator.refreshMeasurement() }
        for _ in 0..<10_000 where estimates.callCount < 1 { await Task.yield() }
        let newerRequest = Task { await coordinator.refreshMeasurement() }
        for _ in 0..<10_000 where estimates.callCount < 2 { await Task.yield() }

        estimates.release(index: 1)
        let newerResult = await newerRequest.value
        estimates.release(index: 0)
        let olderResult = await olderRequest.value

        XCTAssertEqual(newerResult, .available(300))
        XCTAssertEqual(olderResult, .unavailable)
        XCTAssertEqual(coordinator.measurementState, .available(300))
    }

    func testAutomaticCapacityRunUsesItsLocalMeasurementDuringSettingsRefresh() async throws {
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.websiteCachePolicy = WebsiteCachePolicy(
            retentionDays: nil,
            maximumEstimatedBytes: 1_500,
            targetEstimatedBytes: 1_000,
            minimumCleanupInterval: 0,
            recentUseProtection: 0
        )
        let usage = WebsiteCacheUsageStore(defaults: defaults)
        let identity = BrowserProfileIdentity.custom(UUID())
        let cleaned = IdentityBox()
        let estimates = ControlledEstimateBox([2_000, 42, 900])
        let coordinator = makeCoordinator(
            preferences: preferences,
            usage: usage,
            service: makeService(cleaned: cleaned),
            estimates: { estimates.next() },
            profiles: {
                [WebsiteCacheProfileSnapshot(
                    identity: identity,
                    lastUsedAt: .distantPast,
                    useCount: 0,
                    isActive: false
                )]
            }
        )

        let automaticRequest = Task {
            try await coordinator.runAutomaticIfNeeded(
                now: Date(timeIntervalSince1970: 60_000_000)
            )
        }
        for _ in 0..<10_000 where estimates.callCount < 1 { await Task.yield() }
        XCTAssertEqual(estimates.callCount, 1)

        let settingsRequest = Task { await coordinator.refreshMeasurement() }
        for _ in 0..<10_000 where estimates.callCount < 2 { await Task.yield() }
        estimates.release(index: 1)
        let settingsResult = await settingsRequest.value
        XCTAssertEqual(settingsResult, .available(42))

        estimates.release(index: 0)
        for _ in 0..<10_000 where estimates.callCount < 3 { await Task.yield() }
        XCTAssertEqual(estimates.callCount, 3)
        estimates.release(index: 2)

        let result = try await automaticRequest.value
        XCTAssertEqual(result?.cleanedProfileCount, 1)
        XCTAssertEqual(result?.estimatedBytesAfter, 900)
        XCTAssertEqual(cleaned.values, [identity])
    }

    func testUsageStoreKeepsOnlyThirtyUtcDailyBucketsAndUsesRealTabSelection() {
        let clock = DateBox(Date(timeIntervalSince1970: 2_000_000_000))
        let usage = WebsiteCacheUsageStore(defaults: defaults, now: { clock.date })
        let identity = BrowserProfileIdentity.default
        let day = 86_400.0

        usage.recordUse(of: identity, at: clock.date.addingTimeInterval(-31 * day))
        usage.recordUse(of: identity, at: clock.date.addingTimeInterval(-2 * day))
        usage.recordUse(of: identity, at: clock.date)
        let entry = usage.entry(for: identity)
        XCTAssertEqual(entry.dailyUseCounts.count, 2)
        XCTAssertEqual(entry.useCount30Days, 2)

        let tabStore = TabStore(repository: MemoryProfileRepository())
        let first = tabStore.add(name: "First", homeURL: URL(string: "https://one.example")!)!
        let second = tabStore.add(name: "Second", homeURL: URL(string: "https://two.example")!)!
        var selectionCount = 0
        tabStore.onUserProfileUse = { _, _ in selectionCount += 1 }

        XCTAssertTrue(tabStore.select(id: first.id, now: clock.date))
        XCTAssertTrue(tabStore.select(id: first.id, now: clock.date.addingTimeInterval(1)))
        XCTAssertTrue(tabStore.select(id: second.id, now: clock.date.addingTimeInterval(2)))
        XCTAssertEqual(selectionCount, 2)
    }

    func testFrequencyScoreIsFiniteAndBounded() {
        let now = Date(timeIntervalSince1970: 3_000_000_000)
        let oldLowFrequency = WebsiteCachePolicy.evictionScore(
            lastUsedAt: now.addingTimeInterval(-40 * 86_400),
            useCount30Days: 1,
            now: now
        )
        let oldHighFrequency = WebsiteCachePolicy.evictionScore(
            lastUsedAt: now.addingTimeInterval(-40 * 86_400),
            useCount30Days: Int.max,
            now: now
        )
        XCTAssertGreaterThan(oldLowFrequency, oldHighFrequency)
        XCTAssertLessThanOrEqual(oldLowFrequency - oldHighFrequency, 7)
        XCTAssertTrue(oldHighFrequency.isFinite)
    }

    func testStaleUsageNeverBecomesCleanupCandidateOrStoreResolution() async throws {
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.websiteCachePolicy = WebsiteCachePolicy(
            retentionDays: 30,
            maximumEstimatedBytes: nil,
            minimumCleanupInterval: 0
        )
        let usage = WebsiteCacheUsageStore(defaults: defaults)
        let stale = BrowserProfileIdentity.custom(UUID())
        let live = BrowserProfileIdentity.custom(UUID())
        usage.recordUse(of: stale, at: Date(timeIntervalSince1970: 1))
        let resolved = IdentityBox()
        let coordinator = makeCoordinator(
            preferences: preferences,
            usage: usage,
            service: WebsiteCacheCleanupService(
                dataStoreResolver: { identity in
                    resolved.values.append(identity)
                    return WKWebsiteDataStore.nonPersistent()
                },
                fetchRecords: { _, _, completion in completion([]) },
                removeData: { _, _, _ in }
            ),
            profiles: {
                usage.prune(keeping: [live])
                return [WebsiteCacheProfileSnapshot(
                    identity: live,
                    lastUsedAt: Date(timeIntervalSince1970: 1),
                    useCount: 0,
                    isActive: false
                )]
            }
        )

        _ = try await coordinator.runAutomaticIfNeeded(
            now: Date(timeIntervalSince1970: 31 * 24 * 60 * 60)
        )
        XCTAssertEqual(resolved.values, [live])
        let retainedKeys = Set(usage.allEntries.keys)
        XCTAssertFalse(retainedKeys.contains(stale.storageKey))
        XCTAssertTrue(retainedKeys.contains(live.storageKey))
    }

    func testSizeEstimatorCountsOnlyExactCacheRootsAndRunsOffMainThread() async throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("FloatTabs-WebsiteCache-(UUID().uuidString)")
        let networkCache = base
            .appendingPathComponent("Library/Caches/com.lost0rz.FloatTabs/WebKit/NetworkCache")
        let cacheStorage = base
            .appendingPathComponent("Library/Caches/com.lost0rz.FloatTabs/WebKit/CacheStorage")
        let websiteData = base
            .appendingPathComponent("Library/WebKit/com.lost0rz.FloatTabs/WebsiteData")
        try fileManager.createDirectory(at: networkCache, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cacheStorage, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: websiteData, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: base) }

        let first = networkCache.appendingPathComponent("network.bin")
        let second = cacheStorage.appendingPathComponent("fetch.bin")
        let excluded = websiteData.appendingPathComponent("indexeddb.bin")
        XCTAssertTrue(fileManager.createFile(atPath: first.path, contents: Data(repeating: 1, count: 1024)))
        XCTAssertTrue(fileManager.createFile(atPath: second.path, contents: Data(repeating: 2, count: 2048)))
        XCTAssertTrue(fileManager.createFile(atPath: excluded.path, contents: Data(repeating: 3, count: 16 * 1024)))

        let expected = try [first, second].reduce(into: Int64(0)) { total, url in
            let values = try url.resourceValues(forKeys: [.fileAllocatedSizeKey, .fileSizeKey])
            total += Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        let estimator = WebsiteCacheSizeMeasurer(
            fileManager: fileManager,
            rootURLsProvider: { [networkCache, cacheStorage] }
        )
        let measured = await estimator.estimate()
        XCTAssertEqual(measured, expected)

        let threadBox = ThreadBox()
        let backgroundEstimator = WebsiteCacheSizeMeasurer(
            estimate: { 123 },
            enumerationObserver: { threadBox.wasMainThread = Thread.isMainThread }
        )
        let backgroundMeasured = await backgroundEstimator.estimate()
        XCTAssertEqual(backgroundMeasured, 123)
        XCTAssertFalse(threadBox.wasMainThread)
    }

    func testNestedDefaultProfileCacheStorageAndNetworkCacheAreMeasured() async throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("FloatTabs-WebsiteCache-DefaultNested-\(UUID().uuidString)")
        let defaultRoot = base
            .appendingPathComponent("Library/WebKit/com.lost0rz.FloatTabs/WebsiteData/Default")
        let cacheStorage = defaultRoot
            .appendingPathComponent("hash-a/hash-b/CacheStorage")
        let networkCache = defaultRoot
            .appendingPathComponent("hash-a/hash-b/NetworkCache")
        let excludedParent = defaultRoot
            .appendingPathComponent("hash-a/hash-b/OtherWebsiteData")
        try fileManager.createDirectory(at: cacheStorage, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: networkCache, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: excludedParent, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: base) }

        let storageFile = cacheStorage.appendingPathComponent("fetch.bin")
        let networkFile = networkCache.appendingPathComponent("network.bin")
        let excludedFile = excludedParent.appendingPathComponent("persistent.bin")
        XCTAssertTrue(fileManager.createFile(atPath: storageFile.path, contents: Data(repeating: 1, count: 1_024)))
        XCTAssertTrue(fileManager.createFile(atPath: networkFile.path, contents: Data(repeating: 2, count: 2_048)))
        XCTAssertTrue(fileManager.createFile(atPath: excludedFile.path, contents: Data(repeating: 3, count: 32 * 1_024)))

        let expected = try [storageFile, networkFile].reduce(into: Int64(0)) { total, url in
            let values = try url.resourceValues(forKeys: [.fileAllocatedSizeKey, .fileSizeKey])
            total += Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        let scope = WebsiteCacheMeasurementScope(
            directCacheRoots: [],
            defaultProfileRoots: [defaultRoot],
            customProfileRoots: [],
            allowedCustomProfileIdentifiers: [],
            trustedBoundaryRoots: [base.appendingPathComponent("Library")]
        )
        let estimator = WebsiteCacheSizeMeasurer(
            fileManager: fileManager,
            scopeProvider: { scope }
        )

        let measured = await estimator.estimate()
        XCTAssertEqual(measured, expected)
    }

    func testNestedCurrentProfilesAreMeasuredAndHistoricalUUIDsAreIgnored() async throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("FloatTabs-WebsiteCache-Profiles-\(UUID().uuidString)")
        let storeRoot = base
            .appendingPathComponent("Library/WebKit/com.lost0rz.FloatTabs/WebsiteDataStore")
        let currentA = UUID()
        let currentB = UUID()
        let historical = UUID()
        let currentIDs = ProfileIDsBox([currentA, currentB])

        func cacheRoot(for id: UUID, name: String) -> URL {
            storeRoot
                .appendingPathComponent(id.uuidString, isDirectory: true)
                .appendingPathComponent(name, isDirectory: true)
        }

        let aNetwork = cacheRoot(for: currentA, name: "NetworkCache")
        let bStorage = cacheRoot(for: currentB, name: "CacheStorage")
        let historicalNetwork = cacheRoot(for: historical, name: "NetworkCache")
        try fileManager.createDirectory(at: aNetwork, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: bStorage, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: historicalNetwork, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: base) }

        let aFile = aNetwork.appendingPathComponent("a.bin")
        let bFile = bStorage.appendingPathComponent("b.bin")
        let historicalFile = historicalNetwork.appendingPathComponent("old.bin")
        XCTAssertTrue(fileManager.createFile(atPath: aFile.path, contents: Data(repeating: 1, count: 1_000)))
        XCTAssertTrue(fileManager.createFile(atPath: bFile.path, contents: Data(repeating: 2, count: 2_000)))
        XCTAssertTrue(fileManager.createFile(atPath: historicalFile.path, contents: Data(repeating: 3, count: 64 * 1_024)))

        let estimator = WebsiteCacheSizeMeasurer(
            fileManager: fileManager,
            scopeProvider: {
                WebsiteCacheMeasurementScope(
                    directCacheRoots: [],
                    defaultProfileRoots: [],
                    customProfileRoots: currentIDs.values.map {
                        storeRoot.appendingPathComponent($0.uuidString, isDirectory: true)
                    },
                    allowedCustomProfileIdentifiers: Set(currentIDs.values),
                    trustedBoundaryRoots: [base.appendingPathComponent("Library")]
                )
            }
        )
        let expectedCurrent = try [aFile, bFile].reduce(into: Int64(0)) { total, url in
            let values = try url.resourceValues(forKeys: [.fileAllocatedSizeKey, .fileSizeKey])
            total += Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        let measuredCurrent = await estimator.estimate()
        XCTAssertEqual(measuredCurrent, expectedCurrent)

        currentIDs.values = [currentB]
        let expectedOnlyB = try bFile.resourceValues(forKeys: [.fileAllocatedSizeKey, .fileSizeKey])
        let measuredOnlyB = await estimator.estimate()
        XCTAssertEqual(
            measuredOnlyB,
            Int64(expectedOnlyB.fileAllocatedSize ?? expectedOnlyB.fileSize ?? 0)
        )
    }

    func testNestedUnknownLookalikeAndOutOfBoundaryProfilesAreNotTrusted() async throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("FloatTabs-WebsiteCache-ProfileBoundaries-\(UUID().uuidString)")
        let storeRoot = base
            .appendingPathComponent("Library/WebKit/com.lost0rz.FloatTabs/WebsiteDataStore")
        let currentID = UUID()
        let validRoot = storeRoot.appendingPathComponent(currentID.uuidString, isDirectory: true)
        let fakeRoot = storeRoot.appendingPathComponent("not-a-profile-uuid", isDirectory: true)
        let lookalikeRoot = storeRoot.appendingPathComponent(
            "\(currentID.uuidString)-suffix",
            isDirectory: true
        )
        let validCache = validRoot.appendingPathComponent("NetworkCache", isDirectory: true)
        let fakeCache = fakeRoot.appendingPathComponent("NetworkCache", isDirectory: true)
        let lookalikeCache = lookalikeRoot.appendingPathComponent("NetworkCache", isDirectory: true)
        try fileManager.createDirectory(at: validCache, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: fakeCache, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: lookalikeCache, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: base) }

        let validFile = validCache.appendingPathComponent("valid.bin")
        XCTAssertTrue(fileManager.createFile(
            atPath: validFile.path,
            contents: Data(repeating: 1, count: 1_000)
        ))
        XCTAssertTrue(fileManager.createFile(
            atPath: fakeCache.appendingPathComponent("fake.bin").path,
            contents: Data(repeating: 2, count: 64 * 1_024)
        ))
        XCTAssertTrue(fileManager.createFile(
            atPath: lookalikeCache.appendingPathComponent("lookalike.bin").path,
            contents: Data(repeating: 3, count: 64 * 1_024)
        ))

        let estimator = WebsiteCacheSizeMeasurer(
            fileManager: fileManager,
            scopeProvider: {
                WebsiteCacheMeasurementScope(
                    directCacheRoots: [],
                    defaultProfileRoots: [],
                    customProfileRoots: [validRoot, fakeRoot, lookalikeRoot],
                    allowedCustomProfileIdentifiers: [currentID],
                    trustedBoundaryRoots: [base.appendingPathComponent("Library")]
                )
            }
        )
        let validValues = try validFile.resourceValues(forKeys: [.fileAllocatedSizeKey, .fileSizeKey])
        let measured = await estimator.estimate()
        XCTAssertEqual(
            measured,
            Int64(validValues.fileAllocatedSize ?? validValues.fileSize ?? 0)
        )

        let outOfBoundaryRoot = base
            .appendingPathComponent(
                "Library/WebKit/com.lost0rz.FloatTabs/Other/WebsiteDataStore/\(currentID.uuidString)",
                isDirectory: true
            )
        let outOfBoundaryEstimator = WebsiteCacheSizeMeasurer(
            fileManager: fileManager,
            scopeProvider: {
                WebsiteCacheMeasurementScope(
                    directCacheRoots: [],
                    defaultProfileRoots: [],
                    customProfileRoots: [outOfBoundaryRoot],
                    allowedCustomProfileIdentifiers: [currentID],
                    trustedBoundaryRoots: [base.appendingPathComponent("Library")]
                )
            }
        )
        let outOfBoundaryMeasured = await outOfBoundaryEstimator.estimate()
        XCTAssertNil(outOfBoundaryMeasured)
    }

    func testNestedPathSymlinkFailsClosedAndDuplicateRootsAreCountedOnce() async throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("FloatTabs-WebsiteCache-NestedSafety-\(UUID().uuidString)")
        let directRoot = base
            .appendingPathComponent("Library/Caches/com.lost0rz.FloatTabs/WebKit/NetworkCache")
        let defaultRoot = base
            .appendingPathComponent("Library/WebKit/com.lost0rz.FloatTabs/WebsiteData/Default")
        let outside = base.appendingPathComponent("outside")
        let nestedSecond = defaultRoot.appendingPathComponent("hash-a/hash-b")
        try fileManager.createDirectory(at: directRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: nestedSecond, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: base) }

        let directFile = directRoot.appendingPathComponent("direct.bin")
        XCTAssertTrue(fileManager.createFile(atPath: directFile.path, contents: Data(repeating: 1, count: 4_096)))
        let duplicateEstimator = WebsiteCacheSizeMeasurer(
            fileManager: fileManager,
            rootURLsProvider: { [directRoot, directRoot] }
        )
        let directValues = try directFile.resourceValues(forKeys: [.fileAllocatedSizeKey, .fileSizeKey])
        let duplicateMeasured = await duplicateEstimator.estimate()
        XCTAssertEqual(
            duplicateMeasured,
            Int64(directValues.fileAllocatedSize ?? directValues.fileSize ?? 0)
        )

        XCTAssertTrue(fileManager.createFile(
            atPath: outside.appendingPathComponent("secret.bin").path,
            contents: Data(repeating: 9, count: 64)
        ))
        try fileManager.createSymbolicLink(
            at: nestedSecond.appendingPathComponent("CacheStorage"),
            withDestinationURL: outside
        )
        let symlinkEstimator = WebsiteCacheSizeMeasurer(
            fileManager: fileManager,
            scopeProvider: {
                WebsiteCacheMeasurementScope(
                    directCacheRoots: [],
                    defaultProfileRoots: [defaultRoot],
                    customProfileRoots: [],
                    allowedCustomProfileIdentifiers: [],
                    trustedBoundaryRoots: [base.appendingPathComponent("Library")]
                )
            }
        )
        let symlinkMeasured = await symlinkEstimator.estimate()
        XCTAssertNil(symlinkMeasured)
    }

    func testDirectCacheAncestorSymlinksAreRejectedEvenWithApprovedTargetSuffix() async throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("FloatTabs-WebsiteCache-DirectAncestors-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: base) }

        for ancestor in ["Library", "Caches", "Bundle", "WebKit"] {
            let caseRoot = base.appendingPathComponent(ancestor, isDirectory: true)
            let rawRoot = caseRoot
                .appendingPathComponent("Library/Caches/com.lost0rz.FloatTabs/WebKit/NetworkCache")
            let outsideRoot = caseRoot
                .appendingPathComponent("outside/Library/Caches/com.lost0rz.FloatTabs/WebKit/NetworkCache")
            try fileManager.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
            XCTAssertTrue(fileManager.createFile(
                atPath: outsideRoot.appendingPathComponent("secret.bin").path,
                contents: Data(repeating: 7, count: 64)
            ))

            let symlinkURL: URL
            let symlinkDestination: URL
            switch ancestor {
            case "Library":
                symlinkURL = caseRoot.appendingPathComponent("Library")
                symlinkDestination = caseRoot.appendingPathComponent("outside/Library")
            case "Caches":
                try fileManager.createDirectory(
                    at: caseRoot.appendingPathComponent("Library"),
                    withIntermediateDirectories: true
                )
                symlinkURL = caseRoot.appendingPathComponent("Library/Caches")
                symlinkDestination = caseRoot.appendingPathComponent("outside/Library/Caches")
            case "Bundle":
                try fileManager.createDirectory(
                    at: caseRoot.appendingPathComponent("Library/Caches"),
                    withIntermediateDirectories: true
                )
                symlinkURL = caseRoot.appendingPathComponent(
                    "Library/Caches/com.lost0rz.FloatTabs"
                )
                symlinkDestination = caseRoot.appendingPathComponent(
                    "outside/Library/Caches/com.lost0rz.FloatTabs"
                )
            default:
                try fileManager.createDirectory(
                    at: caseRoot.appendingPathComponent("Library/Caches/com.lost0rz.FloatTabs"),
                    withIntermediateDirectories: true
                )
                symlinkURL = caseRoot.appendingPathComponent(
                    "Library/Caches/com.lost0rz.FloatTabs/WebKit"
                )
                symlinkDestination = caseRoot.appendingPathComponent(
                    "outside/Library/Caches/com.lost0rz.FloatTabs/WebKit"
                )
            }
            try fileManager.createSymbolicLink(at: symlinkURL, withDestinationURL: symlinkDestination)

            let estimator = WebsiteCacheSizeMeasurer(
                fileManager: fileManager,
                scopeProvider: {
                    .direct([rawRoot], trustedBoundaryRoots: [caseRoot])
                }
            )
            let measured = await estimator.estimate()
            XCTAssertNil(measured, "Rejected ancestor: \(ancestor)")
        }
    }

    func testDefaultProfileAncestorSymlinksAreRejectedEvenWithApprovedTargetSuffix() async throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("FloatTabs-WebsiteCache-DefaultAncestors-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: base) }

        for ancestor in ["WebsiteData", "Default", "FirstHash", "SecondHash"] {
            let caseRoot = base.appendingPathComponent(ancestor, isDirectory: true)
            let rawDefault = caseRoot
                .appendingPathComponent("Library/WebKit/com.lost0rz.FloatTabs/WebsiteData/Default")
            let outsideDefault = caseRoot
                .appendingPathComponent("outside/Library/WebKit/com.lost0rz.FloatTabs/WebsiteData/Default")
            let outsideCache = outsideDefault
                .appendingPathComponent("hash-a/hash-b/CacheStorage")
            try fileManager.createDirectory(at: outsideCache, withIntermediateDirectories: true)
            XCTAssertTrue(fileManager.createFile(
                atPath: outsideCache.appendingPathComponent("secret.bin").path,
                contents: Data(repeating: 8, count: 64)
            ))

            let symlinkURL: URL
            let symlinkDestination: URL
            switch ancestor {
            case "WebsiteData":
                try fileManager.createDirectory(
                    at: caseRoot.appendingPathComponent("Library/WebKit/com.lost0rz.FloatTabs"),
                    withIntermediateDirectories: true
                )
                symlinkURL = caseRoot.appendingPathComponent(
                    "Library/WebKit/com.lost0rz.FloatTabs/WebsiteData"
                )
                symlinkDestination = caseRoot.appendingPathComponent(
                    "outside/Library/WebKit/com.lost0rz.FloatTabs/WebsiteData"
                )
            case "Default":
                try fileManager.createDirectory(
                    at: caseRoot.appendingPathComponent(
                        "Library/WebKit/com.lost0rz.FloatTabs/WebsiteData"
                    ),
                    withIntermediateDirectories: true
                )
                symlinkURL = caseRoot.appendingPathComponent(
                    "Library/WebKit/com.lost0rz.FloatTabs/WebsiteData/Default"
                )
                symlinkDestination = caseRoot.appendingPathComponent(
                    "outside/Library/WebKit/com.lost0rz.FloatTabs/WebsiteData/Default"
                )
            case "FirstHash":
                try fileManager.createDirectory(
                    at: caseRoot.appendingPathComponent(
                        "Library/WebKit/com.lost0rz.FloatTabs/WebsiteData/Default"
                    ),
                    withIntermediateDirectories: true
                )
                symlinkURL = caseRoot.appendingPathComponent(
                    "Library/WebKit/com.lost0rz.FloatTabs/WebsiteData/Default/hash-a"
                )
                symlinkDestination = caseRoot.appendingPathComponent(
                    "outside/Library/WebKit/com.lost0rz.FloatTabs/WebsiteData/Default/hash-a"
                )
            default:
                try fileManager.createDirectory(
                    at: caseRoot.appendingPathComponent(
                        "Library/WebKit/com.lost0rz.FloatTabs/WebsiteData/Default/hash-a"
                    ),
                    withIntermediateDirectories: true
                )
                symlinkURL = caseRoot.appendingPathComponent(
                    "Library/WebKit/com.lost0rz.FloatTabs/WebsiteData/Default/hash-a/hash-b"
                )
                symlinkDestination = caseRoot.appendingPathComponent(
                    "outside/Library/WebKit/com.lost0rz.FloatTabs/WebsiteData/Default/hash-a/hash-b"
                )
            }
            try fileManager.createSymbolicLink(at: symlinkURL, withDestinationURL: symlinkDestination)

            let estimator = WebsiteCacheSizeMeasurer(
                fileManager: fileManager,
                scopeProvider: {
                    WebsiteCacheMeasurementScope(
                        directCacheRoots: [],
                        defaultProfileRoots: [rawDefault],
                        customProfileRoots: [],
                        allowedCustomProfileIdentifiers: [],
                        trustedBoundaryRoots: [caseRoot]
                    )
                }
            )
            let measured = await estimator.estimate()
            XCTAssertNil(measured, "Rejected ancestor: \(ancestor)")
        }
    }

    func testCustomProfileAncestorSymlinksAreRejectedEvenWithApprovedTargetSuffix() async throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("FloatTabs-WebsiteCache-CustomAncestors-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: base) }
        let profileID = UUID()

        for ancestor in ["WebsiteDataStore", "ProfileUUID"] {
            let caseRoot = base.appendingPathComponent(ancestor, isDirectory: true)
            let rawProfile = caseRoot.appendingPathComponent(
                "Library/WebKit/com.lost0rz.FloatTabs/WebsiteDataStore/\(profileID.uuidString)"
            )
            let outsideProfile = caseRoot.appendingPathComponent(
                "outside/Library/WebKit/com.lost0rz.FloatTabs/WebsiteDataStore/\(profileID.uuidString)"
            )
            let outsideCache = outsideProfile.appendingPathComponent("NetworkCache")
            try fileManager.createDirectory(at: outsideCache, withIntermediateDirectories: true)
            XCTAssertTrue(fileManager.createFile(
                atPath: outsideCache.appendingPathComponent("secret.bin").path,
                contents: Data(repeating: 9, count: 64)
            ))

            let symlinkURL: URL
            let symlinkDestination: URL
            if ancestor == "WebsiteDataStore" {
                try fileManager.createDirectory(
                    at: caseRoot.appendingPathComponent("Library/WebKit/com.lost0rz.FloatTabs"),
                    withIntermediateDirectories: true
                )
                symlinkURL = caseRoot.appendingPathComponent(
                    "Library/WebKit/com.lost0rz.FloatTabs/WebsiteDataStore"
                )
                symlinkDestination = caseRoot.appendingPathComponent(
                    "outside/Library/WebKit/com.lost0rz.FloatTabs/WebsiteDataStore"
                )
            } else {
                try fileManager.createDirectory(
                    at: caseRoot.appendingPathComponent(
                        "Library/WebKit/com.lost0rz.FloatTabs/WebsiteDataStore"
                    ),
                    withIntermediateDirectories: true
                )
                symlinkURL = caseRoot.appendingPathComponent(
                    "Library/WebKit/com.lost0rz.FloatTabs/WebsiteDataStore/\(profileID.uuidString)"
                )
                symlinkDestination = caseRoot.appendingPathComponent(
                    "outside/Library/WebKit/com.lost0rz.FloatTabs/WebsiteDataStore/\(profileID.uuidString)"
                )
            }
            try fileManager.createSymbolicLink(at: symlinkURL, withDestinationURL: symlinkDestination)

            let estimator = WebsiteCacheSizeMeasurer(
                fileManager: fileManager,
                scopeProvider: {
                    WebsiteCacheMeasurementScope(
                        directCacheRoots: [],
                        defaultProfileRoots: [],
                        customProfileRoots: [rawProfile],
                        allowedCustomProfileIdentifiers: [profileID],
                        trustedBoundaryRoots: [caseRoot]
                    )
                }
            )
            let measured = await estimator.estimate()
            XCTAssertNil(measured, "Rejected ancestor: \(ancestor)")
        }
    }

    func testSizeEstimatorReturnsUnavailableForSymlinkEscapeAndWholeWebsiteData() async throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("FloatTabs-WebsiteCache-Symlink-(UUID().uuidString)")
        let root = base
            .appendingPathComponent("Library/Caches/com.lost0rz.FloatTabs/WebKit/NetworkCache")
        let outside = base.appendingPathComponent("outside")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: base) }
        XCTAssertTrue(fileManager.createFile(
            atPath: outside.appendingPathComponent("secret.bin").path,
            contents: Data(repeating: 7, count: 32)
        ))
        try fileManager.createSymbolicLink(
            at: root.appendingPathComponent("escape"),
            withDestinationURL: outside
        )

        let symlinkEstimator = WebsiteCacheSizeMeasurer(
            fileManager: fileManager,
            rootURLsProvider: { [root] }
        )
        let symlinkMeasured = await symlinkEstimator.estimate()
        XCTAssertNil(symlinkMeasured)

        let websiteDataEstimator = WebsiteCacheSizeMeasurer(
            rootURLsProvider: {
                [base.appendingPathComponent("Library/WebKit/com.lost0rz.FloatTabs/WebsiteData")]
            }
        )
        let websiteDataMeasured = await websiteDataEstimator.estimate()
        XCTAssertNil(websiteDataMeasured)
    }

    func testSettingsShowsCalculatingThenAsyncMeasurementResult() async {
        var state: WebsiteCacheMeasurementState = .calculating
        let manager = WebsiteCacheManagementClient(
            snapshot: {
                WebsiteCacheSettingsSnapshot(
                    policy: .default,
                    estimatedBytes: state.estimatedBytes,
                    measurementState: state,
                    lastSuccessfulCleanupAt: nil,
                    isOperationInProgress: false
                )
            },
            updatePolicy: { _ in },
            beginMeasurement: { state = .calculating },
            refreshMeasurement: {
                await Task.yield()
                state = .available(2_000_000_000)
            },
            releaseCache: { throw WebsiteCacheManagementError.unavailable }
        )
        let controller = AccountLanguageSettingsViewController(
            onExportBackup: { _ in },
            onRestoreBackup: { _ in throw TestError.injected },
            websiteCacheManager: manager
        )
        controller.loadView()
        XCTAssertEqual(controller.displayedWebsiteCacheUsage, "Calculating…")
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNotEqual(controller.displayedWebsiteCacheUsage, "Calculating…")
    }

    // MARK: - Size measurement resilience (deterministic filesystem seams)

    private func makeWalkFixture(
        fileManager: FileManager,
        name: String
    ) throws -> (base: URL, root: URL) {
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("FloatTabs-CacheWalk-\(name)-\(UUID().uuidString)")
        let root = base
            .appendingPathComponent("Library/Caches/com.lost0rz.FloatTabs/WebKit/NetworkCache")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return (base, root)
    }

    private func makeWalkFile(
        _ fileManager: FileManager,
        bytes: Int,
        in root: URL,
        name: String
    ) throws -> (url: URL, size: Int64) {
        let url = root.appendingPathComponent(name)
        XCTAssertTrue(fileManager.createFile(
            atPath: url.path,
            contents: Data(repeating: 7, count: bytes)
        ))
        let values = try url.resourceValues(forKeys: [.fileAllocatedSizeKey, .fileSizeKey])
        return (url, Int64(values.fileAllocatedSize ?? values.fileSize ?? 0))
    }

    private func makeDefaultProfileFixture(
        fileManager: FileManager,
        name: String
    ) throws -> (base: URL, defaultRoot: URL) {
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("FloatTabs-CacheDiscovery-\(name)-\(UUID().uuidString)")
        let defaultRoot = base
            .appendingPathComponent("Library/WebKit/com.lost0rz.FloatTabs/WebsiteData/Default")
        try fileManager.createDirectory(at: defaultRoot, withIntermediateDirectories: true)
        return (base, defaultRoot)
    }

    private func walkScope(base: URL, root: URL) -> WebsiteCacheMeasurementScope {
        .direct([root], trustedBoundaryRoots: [base.appendingPathComponent("Library")])
    }

    private nonisolated static func posixError(_ code: Int32) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }

    func testVanishedFileAfterEnumerationIsSkippedAndOthersAccumulate() throws {
        let fileManager = FileManager.default
        let fixture = try makeWalkFixture(fileManager: fileManager, name: "Vanished")
        defer { try? fileManager.removeItem(at: fixture.base) }
        let first = try makeWalkFile(fileManager, bytes: 4_096, in: fixture.root, name: "a.bin")
        _ = try makeWalkFile(fileManager, bytes: 8_192, in: fixture.root, name: "vanished.bin")
        let third = try makeWalkFile(fileManager, bytes: 2_048, in: fixture.root, name: "c.bin")

        var reading = WebsiteCacheFileReading.live(fileManager)
        let liveAttributes = reading.entryAttributes
        reading.entryAttributes = { url in
            if url.lastPathComponent == "vanished.bin" {
                throw Self.posixError(ENOENT)
            }
            return try liveAttributes(url)
        }

        let outcome = WebsiteCacheSizeMeasurer.measureOutcome(
            fileManager: fileManager,
            reading: reading,
            scope: walkScope(base: fixture.base, root: fixture.root)
        )
        XCTAssertEqual(outcome, .available(first.size + third.size))
    }

    func testCocoaNoSuchFileOnSingleFileSkipsOnlyThatFile() throws {
        let fileManager = FileManager.default
        let fixture = try makeWalkFixture(fileManager: fileManager, name: "CocoaNoSuchFile")
        defer { try? fileManager.removeItem(at: fixture.base) }
        let first = try makeWalkFile(fileManager, bytes: 4_096, in: fixture.root, name: "a.bin")
        _ = try makeWalkFile(fileManager, bytes: 8_192, in: fixture.root, name: "vanished.bin")

        var reading = WebsiteCacheFileReading.live(fileManager)
        let liveAttributes = reading.entryAttributes
        reading.entryAttributes = { url in
            if url.lastPathComponent == "vanished.bin" {
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadNoSuchFileError
                )
            }
            return try liveAttributes(url)
        }

        let outcome = WebsiteCacheSizeMeasurer.measureOutcome(
            fileManager: fileManager,
            reading: reading,
            scope: walkScope(base: fixture.base, root: fixture.root)
        )
        XCTAssertEqual(outcome, .available(first.size))
    }

    func testVanishingCacheRootDuringWalkReturnsAvailableZeroAfterBoundedRetry() throws {
        let fileManager = FileManager.default
        let fixture = try makeWalkFixture(fileManager: fileManager, name: "RootVanished")
        defer { try? fileManager.removeItem(at: fixture.base) }
        _ = try makeWalkFile(fileManager, bytes: 4_096, in: fixture.root, name: "a.bin")

        var reading = WebsiteCacheFileReading.live(fileManager)
        let attempts = WalkCounter()
        reading.enumerateDescendants = { _, _ in
            attempts.increment()
            throw Self.posixError(ENOENT)
        }

        let outcome = WebsiteCacheSizeMeasurer.measureOutcome(
            fileManager: fileManager,
            reading: reading,
            scope: walkScope(base: fixture.base, root: fixture.root)
        )
        XCTAssertEqual(outcome, .available(0))
        XCTAssertEqual(attempts.count, 2, "a vanished root gets exactly one bounded retry")
    }

    func testTransientWalkAbortRetriesRootOnceAndUsesRetryResult() throws {
        let fileManager = FileManager.default
        let fixture = try makeWalkFixture(fileManager: fileManager, name: "RetryOnce")
        defer { try? fileManager.removeItem(at: fixture.base) }

        var reading = WebsiteCacheFileReading.live(fileManager)
        let attempts = WalkCounter()
        reading.enumerateDescendants = { root, sink in
            if attempts.increment() == 1 {
                try sink(root.appendingPathComponent("one.bin"))
                throw Self.posixError(ENOENT)
            }
            try sink(root.appendingPathComponent("two.bin"))
        }
        reading.entryAttributes = { url in
            switch url.lastPathComponent {
            case "NetworkCache":
                return .init(isDirectory: true)
            case "one.bin":
                return .init(isRegularFile: true, fileAllocatedSize: 100)
            case "two.bin":
                return .init(isRegularFile: true, fileAllocatedSize: 200)
            default:
                throw Self.posixError(ENOENT)
            }
        }

        let outcome = WebsiteCacheSizeMeasurer.measureOutcome(
            fileManager: fileManager,
            reading: reading,
            scope: walkScope(base: fixture.base, root: fixture.root)
        )
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(outcome, .available(200))
    }

    func testPermissionDeniedDuringWalkReturnsUnavailable() throws {
        let fileManager = FileManager.default
        let fixture = try makeWalkFixture(fileManager: fileManager, name: "WalkEaccs")
        defer { try? fileManager.removeItem(at: fixture.base) }
        _ = try makeWalkFile(fileManager, bytes: 4_096, in: fixture.root, name: "a.bin")
        _ = try makeWalkFile(fileManager, bytes: 4_096, in: fixture.root, name: "b.bin")

        var reading = WebsiteCacheFileReading.live(fileManager)
        let liveAttributes = reading.entryAttributes
        reading.entryAttributes = { url in
            if url.lastPathComponent == "b.bin" {
                throw Self.posixError(EACCES)
            }
            return try liveAttributes(url)
        }

        let outcome = WebsiteCacheSizeMeasurer.measureOutcome(
            fileManager: fileManager,
            reading: reading,
            scope: walkScope(base: fixture.base, root: fixture.root)
        )
        XCTAssertEqual(outcome, .unavailable(.permissionDenied))
    }

    func testPermissionDeniedAtCacheRootIsNotMisclassifiedAsMissing() throws {
        let fileManager = FileManager.default
        let fixture = try makeWalkFixture(fileManager: fileManager, name: "RootEaccs")
        defer { try? fileManager.removeItem(at: fixture.base) }

        var reading = WebsiteCacheFileReading.live(fileManager)
        let livePathAttributes = reading.pathAttributes
        reading.fileExists = { _ in false }
        reading.pathAttributes = { url in
            if url.standardizedFileURL.path == fixture.root.standardizedFileURL.path {
                throw Self.posixError(EACCES)
            }
            return try livePathAttributes(url)
        }

        let outcome = WebsiteCacheSizeMeasurer.measureOutcome(
            fileManager: fileManager,
            reading: reading,
            scope: walkScope(base: fixture.base, root: fixture.root)
        )
        XCTAssertEqual(outcome, .unavailable(.permissionDenied))
    }

    func testUnrecognizedWalkErrorReturnsUnavailable() throws {
        let fileManager = FileManager.default
        let fixture = try makeWalkFixture(fileManager: fileManager, name: "UnknownIO")
        defer { try? fileManager.removeItem(at: fixture.base) }
        _ = try makeWalkFile(fileManager, bytes: 4_096, in: fixture.root, name: "a.bin")

        var reading = WebsiteCacheFileReading.live(fileManager)
        let liveAttributes = reading.entryAttributes
        reading.entryAttributes = { url in
            if url.lastPathComponent == "a.bin" {
                throw NSError(domain: "FloatTabsTests.UnknownIO", code: 42)
            }
            return try liveAttributes(url)
        }

        let outcome = WebsiteCacheSizeMeasurer.measureOutcome(
            fileManager: fileManager,
            reading: reading,
            scope: walkScope(base: fixture.base, root: fixture.root)
        )
        XCTAssertEqual(outcome, .unavailable(.ioFailure))
    }

    func testRegularFileWithoutReadableSizeIsSkippedNotUnavailable() throws {
        let fileManager = FileManager.default
        let fixture = try makeWalkFixture(fileManager: fileManager, name: "NilSize")
        defer { try? fileManager.removeItem(at: fixture.base) }
        let first = try makeWalkFile(fileManager, bytes: 4_096, in: fixture.root, name: "a.bin")
        _ = try makeWalkFile(fileManager, bytes: 8_192, in: fixture.root, name: "unreadable.bin")

        var reading = WebsiteCacheFileReading.live(fileManager)
        let liveAttributes = reading.entryAttributes
        reading.entryAttributes = { url in
            if url.lastPathComponent == "unreadable.bin" {
                return .init(isRegularFile: true)
            }
            return try liveAttributes(url)
        }

        let outcome = WebsiteCacheSizeMeasurer.measureOutcome(
            fileManager: fileManager,
            reading: reading,
            scope: walkScope(base: fixture.base, root: fixture.root)
        )
        XCTAssertEqual(outcome, .available(first.size))
    }

    func testUnexpectedSpecialFileTypeFailsClosed() throws {
        let fileManager = FileManager.default
        let fixture = try makeWalkFixture(fileManager: fileManager, name: "SpecialFile")
        defer { try? fileManager.removeItem(at: fixture.base) }
        _ = try makeWalkFile(fileManager, bytes: 4_096, in: fixture.root, name: "a.bin")
        _ = try makeWalkFile(fileManager, bytes: 4_096, in: fixture.root, name: "socket.bin")

        var reading = WebsiteCacheFileReading.live(fileManager)
        let liveAttributes = reading.entryAttributes
        reading.entryAttributes = { url in
            if url.lastPathComponent == "socket.bin" {
                return .init()
            }
            return try liveAttributes(url)
        }

        let outcome = WebsiteCacheSizeMeasurer.measureOutcome(
            fileManager: fileManager,
            reading: reading,
            scope: walkScope(base: fixture.base, root: fixture.root)
        )
        XCTAssertEqual(outcome, .unavailable(.unsupportedLayout))
    }

    func testWalkEntrySymlinkFailsClosed() throws {
        let fileManager = FileManager.default
        let fixture = try makeWalkFixture(fileManager: fileManager, name: "WalkSymlink")
        defer { try? fileManager.removeItem(at: fixture.base) }
        _ = try makeWalkFile(fileManager, bytes: 4_096, in: fixture.root, name: "a.bin")

        var reading = WebsiteCacheFileReading.live(fileManager)
        let liveAttributes = reading.entryAttributes
        reading.entryAttributes = { url in
            if url.lastPathComponent == "a.bin" {
                return .init(isSymbolicLink: true)
            }
            return try liveAttributes(url)
        }

        let outcome = WebsiteCacheSizeMeasurer.measureOutcome(
            fileManager: fileManager,
            reading: reading,
            scope: walkScope(base: fixture.base, root: fixture.root)
        )
        XCTAssertEqual(outcome, .unavailable(.unsafePath))
    }

    func testDiscoverySkipsSubdirectoryRemovedMidEnumeration() throws {
        let fileManager = FileManager.default
        let fixture = try makeDefaultProfileFixture(fileManager: fileManager, name: "SubdirRemoved")
        defer { try? fileManager.removeItem(at: fixture.base) }
        let removedCache = fixture.defaultRoot
            .appendingPathComponent("hash-a/hash-b/NetworkCache", isDirectory: true)
        let survivingCache = fixture.defaultRoot
            .appendingPathComponent("hash-c/hash-d/NetworkCache", isDirectory: true)
        try fileManager.createDirectory(at: removedCache, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: survivingCache, withIntermediateDirectories: true)
        _ = try makeWalkFile(fileManager, bytes: 64 * 1_024, in: removedCache, name: "removed.bin")
        let surviving = try makeWalkFile(fileManager, bytes: 3_072, in: survivingCache, name: "surviving.bin")

        var reading = WebsiteCacheFileReading.live(fileManager)
        let liveContents = reading.directoryContents
        reading.directoryContents = { url in
            if url.lastPathComponent == "hash-a" {
                throw Self.posixError(ENOENT)
            }
            return try liveContents(url)
        }

        let scope = WebsiteCacheMeasurementScope(
            directCacheRoots: [],
            defaultProfileRoots: [fixture.defaultRoot],
            customProfileRoots: [],
            allowedCustomProfileIdentifiers: [],
            trustedBoundaryRoots: [fixture.base.appendingPathComponent("Library")]
        )
        let outcome = WebsiteCacheSizeMeasurer.measureOutcome(
            fileManager: fileManager,
            reading: reading,
            scope: scope
        )
        XCTAssertEqual(outcome, .available(surviving.size))
    }

    func testDiscoveryParentVanishingDuringWalkReturnsAvailableZero() throws {
        let fileManager = FileManager.default
        let fixture = try makeDefaultProfileFixture(fileManager: fileManager, name: "ParentVanished")
        defer { try? fileManager.removeItem(at: fixture.base) }
        let cache = fixture.defaultRoot
            .appendingPathComponent("hash-a/hash-b/NetworkCache", isDirectory: true)
        try fileManager.createDirectory(at: cache, withIntermediateDirectories: true)
        _ = try makeWalkFile(fileManager, bytes: 64 * 1_024, in: cache, name: "a.bin")

        var reading = WebsiteCacheFileReading.live(fileManager)
        let liveContents = reading.directoryContents
        reading.directoryContents = { url in
            if url.lastPathComponent == "Default" {
                throw Self.posixError(ENOENT)
            }
            return try liveContents(url)
        }

        let scope = WebsiteCacheMeasurementScope(
            directCacheRoots: [],
            defaultProfileRoots: [fixture.defaultRoot],
            customProfileRoots: [],
            allowedCustomProfileIdentifiers: [],
            trustedBoundaryRoots: [fixture.base.appendingPathComponent("Library")]
        )
        let outcome = WebsiteCacheSizeMeasurer.measureOutcome(
            fileManager: fileManager,
            reading: reading,
            scope: scope
        )
        XCTAssertEqual(outcome, .available(0))
    }

    func testDiscoveryPermissionDeniedReturnsUnavailable() throws {
        let fileManager = FileManager.default
        let fixture = try makeDefaultProfileFixture(fileManager: fileManager, name: "DiscoveryEaccs")
        defer { try? fileManager.removeItem(at: fixture.base) }
        let cache = fixture.defaultRoot
            .appendingPathComponent("hash-a/hash-b/NetworkCache", isDirectory: true)
        try fileManager.createDirectory(at: cache, withIntermediateDirectories: true)
        _ = try makeWalkFile(fileManager, bytes: 64 * 1_024, in: cache, name: "a.bin")

        var reading = WebsiteCacheFileReading.live(fileManager)
        let liveContents = reading.directoryContents
        reading.directoryContents = { url in
            if url.lastPathComponent == "Default" {
                throw Self.posixError(EACCES)
            }
            return try liveContents(url)
        }

        let scope = WebsiteCacheMeasurementScope(
            directCacheRoots: [],
            defaultProfileRoots: [fixture.defaultRoot],
            customProfileRoots: [],
            allowedCustomProfileIdentifiers: [],
            trustedBoundaryRoots: [fixture.base.appendingPathComponent("Library")]
        )
        let outcome = WebsiteCacheSizeMeasurer.measureOutcome(
            fileManager: fileManager,
            reading: reading,
            scope: scope
        )
        XCTAssertEqual(outcome, .unavailable(.permissionDenied))
    }

    func testEstimateSkipsVanishedEntriesEndToEnd() async throws {
        let fileManager = FileManager.default
        let fixture = try makeWalkFixture(fileManager: fileManager, name: "EndToEnd")
        defer { try? fileManager.removeItem(at: fixture.base) }
        let first = try makeWalkFile(fileManager, bytes: 4_096, in: fixture.root, name: "a.bin")
        _ = try makeWalkFile(fileManager, bytes: 8_192, in: fixture.root, name: "vanished.bin")
        let third = try makeWalkFile(fileManager, bytes: 2_048, in: fixture.root, name: "c.bin")

        var reading = WebsiteCacheFileReading.live(fileManager)
        let liveAttributes = reading.entryAttributes
        reading.entryAttributes = { url in
            if url.lastPathComponent == "vanished.bin" {
                throw Self.posixError(ENOENT)
            }
            return try liveAttributes(url)
        }
        let measurer = WebsiteCacheSizeMeasurer(
            fileManager: fileManager,
            rootURLsProvider: { [fixture.root] },
            reading: reading
        )

        let measured = await measurer.estimate()
        XCTAssertEqual(measured, first.size + third.size)
    }

    func testEstimateCancelsDetachedWalkWhenOuterTaskIsCancelled() async throws {
        let fileManager = FileManager.default
        let fixture = try makeWalkFixture(fileManager: fileManager, name: "Cancel")
        defer { try? fileManager.removeItem(at: fixture.base) }

        let entries = WalkCounter()
        let gate = WalkCancellationGate()
        var reading = WebsiteCacheFileReading.live(fileManager)
        reading.entryAttributes = { url in
            if url.pathExtension == "bin" {
                return .init(isRegularFile: true, fileAllocatedSize: 10)
            }
            return .init(isDirectory: true)
        }
        reading.enumerateDescendants = { root, sink in
            try sink(root.appendingPathComponent("first.bin"))
            entries.increment()
            try gate.waitUntilReleasedOrCancelled()
            try sink(root.appendingPathComponent("second.bin"))
            entries.increment()
        }
        let measurer = WebsiteCacheSizeMeasurer(
            fileManager: fileManager,
            rootURLsProvider: { [fixture.root] },
            reading: reading
        )

        let finished = FinishedBox()
        let task = Task { @MainActor in
            let result = await measurer.estimate()
            finished.markDone()
            return result
        }
        for _ in 0..<10_000 where entries.count < 1 { await Task.yield() }
        XCTAssertEqual(entries.count, 1)

        task.cancel()
        for _ in 0..<10_000 where !finished.isDone { await Task.yield() }
        let finishedBeforeRelease = finished.isDone
        gate.release()

        let result = await task.value
        XCTAssertNil(result)
        XCTAssertTrue(
            finishedBeforeRelease,
            "estimate() must return promptly after cancellation instead of finishing the walk"
        )
        XCTAssertEqual(entries.count, 1, "the detached walk must stop after outer-task cancellation")
    }

    func testSettingsLoadAndViewWillAppearStartASingleMeasurement() async {
        let gate = AsyncGate()
        let calls = MeasurementCallBox()
        let manager = WebsiteCacheManagementClient(
            snapshot: {
                WebsiteCacheSettingsSnapshot(
                    policy: .default,
                    estimatedBytes: nil,
                    measurementState: .calculating,
                    lastSuccessfulCleanupAt: nil,
                    isOperationInProgress: false
                )
            },
            updatePolicy: { _ in },
            beginMeasurement: { calls.begin += 1 },
            refreshMeasurement: {
                calls.refresh += 1
                await gate.wait()
            },
            releaseCache: { throw WebsiteCacheManagementError.unavailable }
        )
        let controller = AccountLanguageSettingsViewController(
            onExportBackup: { _ in },
            onRestoreBackup: { _ in throw TestError.injected },
            websiteCacheManager: manager
        )

        controller.loadView()
        controller.viewWillAppear()
        for _ in 0..<10_000 where calls.refresh < 1 { await Task.yield() }

        XCTAssertEqual(calls.begin, 1)
        XCTAssertEqual(calls.refresh, 1)
        gate.release()
    }

    func testSettingsRestartsMeasurementAfterReappearing() async {
        let gate = AsyncGate()
        let calls = MeasurementCallBox()
        let manager = WebsiteCacheManagementClient(
            snapshot: {
                WebsiteCacheSettingsSnapshot(
                    policy: .default,
                    estimatedBytes: nil,
                    measurementState: .calculating,
                    lastSuccessfulCleanupAt: nil,
                    isOperationInProgress: false
                )
            },
            updatePolicy: { _ in },
            beginMeasurement: { calls.begin += 1 },
            refreshMeasurement: {
                calls.refresh += 1
                await gate.wait()
            },
            releaseCache: { throw WebsiteCacheManagementError.unavailable }
        )
        let controller = AccountLanguageSettingsViewController(
            onExportBackup: { _ in },
            onRestoreBackup: { _ in throw TestError.injected },
            websiteCacheManager: manager
        )

        controller.loadView()
        for _ in 0..<10_000 where calls.refresh < 1 { await Task.yield() }
        gate.release()
        controller.viewWillDisappear()
        controller.viewWillAppear()
        for _ in 0..<10_000 where calls.refresh < 2 { await Task.yield() }

        XCTAssertEqual(calls.begin, 2)
        XCTAssertEqual(calls.refresh, 2)
    }

    func testStage0BundleIdentifierNeverEntersMeasurementCandidates() async throws {
        let fileManager = FileManager.default
        let profileID = UUID()
        let scope = WebsiteCacheSizeMeasurer.defaultScope(profileIdentifiers: [profileID])
        let candidatePaths = (scope.directCacheRoots
            + scope.defaultProfileRoots
            + scope.customProfileRoots).map(\.path)
        XCTAssertFalse(candidatePaths.isEmpty)
        for path in candidatePaths {
            XCTAssertTrue(path.contains("/com.lost0rz.FloatTabs/"), path)
            XCTAssertFalse(path.lowercased().contains("stage0"), path)
        }
        XCTAssertTrue(scope.allowedCustomProfileIdentifiers == [profileID])

        let base = fileManager.temporaryDirectory
            .appendingPathComponent("FloatTabs-Stage0-\(UUID().uuidString)")
        let stage0Root = base
            .appendingPathComponent("Library/Caches/com.lost0rz.FloatTabs.stage0/WebKit/NetworkCache")
        try fileManager.createDirectory(at: stage0Root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: base) }
        XCTAssertTrue(fileManager.createFile(
            atPath: stage0Root.appendingPathComponent("stage0.bin").path,
            contents: Data(repeating: 5, count: 4_096)
        ))

        let measurer = WebsiteCacheSizeMeasurer(rootURLsProvider: { [stage0Root] })
        let measured = await measurer.estimate()
        XCTAssertNil(measured)
    }

    private final class WalkCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var countValue = 0

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return countValue
        }

        @discardableResult
        func increment() -> Int {
            lock.lock()
            defer { lock.unlock() }
            countValue += 1
            return countValue
        }
    }

    private final class FinishedBox: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        var isDone: Bool {
            lock.lock()
            defer { lock.unlock() }
            return done
        }

        func markDone() {
            lock.lock()
            done = true
            lock.unlock()
        }
    }

    private final class MeasurementCallBox: @unchecked Sendable {
        var begin = 0
        var refresh = 0
    }

    private final class WalkCancellationGate: @unchecked Sendable {
        private let lock = NSLock()
        private var released = false

        /// Blocks the walking thread until `release()` or task cancellation.
        /// Synchronous because the enumerateDescendants seam is synchronous;
        /// polling keeps cancellation observable without async awaits.
        func waitUntilReleasedOrCancelled() throws {
            while true {
                lock.lock()
                let isReleased = released
                lock.unlock()
                if isReleased { return }
                if Task.isCancelled { throw CancellationError() }
                Thread.sleep(forTimeInterval: 0.002)
            }
        }

        func release() {
            lock.lock()
            released = true
            lock.unlock()
        }
    }

    private func makeCoordinator(
        preferences: AppPreferencesStore,
        usage: WebsiteCacheUsageStore,
        service: WebsiteCacheCleanupService,
        estimates: @escaping @Sendable () -> Int64? = { nil },
        panelVisible: Bool = false,
        profiles: @escaping () -> [WebsiteCacheProfileSnapshot],
        prepareRuntime: @escaping @MainActor (BrowserProfileIdentity, Bool) throws -> Void = { _, _ in },
        restoreRuntime: @escaping @MainActor () -> Void = {}
    ) -> WebsiteCacheCleanupCoordinator {
        WebsiteCacheCleanupCoordinator(
            preferencesStore: preferences,
            usageStore: usage,
            service: service,
            sizeMeasurer: WebsiteCacheSizeMeasurer(estimate: estimates),
            profilesProvider: profiles,
            activeIdentityProvider: { profiles().first(where: \.isActive)?.identity },
            panelVisibilityProvider: { panelVisible },
            prepareRuntime: prepareRuntime,
            restoreRuntime: restoreRuntime
        )
    }

    private func makeService(
        cleaned: IdentityBox
    ) -> WebsiteCacheCleanupService {
        WebsiteCacheCleanupService(
            dataStoreResolver: { identity in
                cleaned.values.append(identity)
                return WKWebsiteDataStore.nonPersistent()
            },
            fetchRecords: { _, _, completion in completion([]) },
            removeData: { _, _, _ in }
        )
    }

    private final class IdentityBox {
        var values: [BrowserProfileIdentity] = []
    }

    private final class EstimateBox: @unchecked Sendable {
        private var values: [Int64?]
        private let lock = NSLock()

        init(_ values: [Int64?]) { self.values = values }

        func next() -> Int64? {
            lock.lock()
            defer { lock.unlock() }
            return values.isEmpty ? values.last ?? nil : values.removeFirst()
        }
    }

    private final class ControlledEstimateBox: @unchecked Sendable {
        private let values: [Int64?]
        private let gates: [DispatchSemaphore]
        private let lock = NSLock()
        private var startedCount = 0

        init(_ values: [Int64?]) {
            self.values = values
            gates = values.map { _ in DispatchSemaphore(value: 0) }
        }

        var callCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return startedCount
        }

        func next() -> Int64? {
            lock.lock()
            let index = startedCount
            startedCount += 1
            lock.unlock()
            guard values.indices.contains(index) else { return nil }
            gates[index].wait()
            return values[index]
        }

        func release(index: Int) {
            guard gates.indices.contains(index) else { return }
            gates[index].signal()
        }
    }

    private final class ProfileIDsBox: @unchecked Sendable {
        var values: [UUID]

        init(_ values: [UUID]) { self.values = values }
    }

    private final class DateBox: @unchecked Sendable {
        var date: Date

        init(_ date: Date) { self.date = date }
    }

    private final class ThreadBox: @unchecked Sendable {
        var wasMainThread = true
    }

    private final class EventBox {
        var values: [String] = []
    }

    @MainActor
    private final class ControlledSleeper {
        private var waiter: CheckedContinuation<Void, Error>?
        private(set) var delays: [TimeInterval] = []

        func sleep(_ delay: TimeInterval) async throws {
            delays.append(delay)
            try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Void, Error>) in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        waiter = continuation
                    }
                }
            }, onCancel: {
                Task { @MainActor [weak self] in
                    self?.cancelWaiter()
                }
            })
        }

        func waitUntilSleepCount(_ count: Int) async {
            for _ in 0..<10_000 where delays.count < count {
                await Task.yield()
            }
        }

        func release() {
            let waiter = waiter
            self.waiter = nil
            waiter?.resume()
        }

        private func cancelWaiter() {
            let waiter = waiter
            self.waiter = nil
            waiter?.resume(throwing: CancellationError())
        }
    }

    @MainActor
    private final class AsyncGate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var released = false
        private(set) var hasWaiter = false

        func wait() async {
            guard !released, !Task.isCancelled else { return }
            await withTaskCancellationHandler(operation: {
                await withCheckedContinuation { continuation in
                    guard !self.released, !Task.isCancelled else {
                        continuation.resume()
                        return
                    }
                    self.continuation = continuation
                    self.hasWaiter = true
                }
            }, onCancel: {
                Task { @MainActor [weak self] in
                    self?.cancelWaiter()
                }
            })
        }

        func release() {
            guard !released else { return }
            released = true
            let continuation = continuation
            self.continuation = nil
            hasWaiter = false
            continuation?.resume()
        }

        private func cancelWaiter() {
            let continuation = continuation
            self.continuation = nil
            hasWaiter = false
            continuation?.resume()
        }
    }

    private enum TestError: Error {
        case injected
    }
}
