import Foundation

struct WebsiteCacheAutomaticScheduleSnapshot: Equatable {
    let now: Date
    let lastAutomaticCheckAt: Date?
    let lastAutomaticFailureAt: Date?
    let minimumCleanupInterval: TimeInterval
    let automaticCleanupEnabled: Bool
}

/// Small, MainActor-owned scheduling loop. It contains no AppKit state and
/// accepts clock, sleeper, snapshot and cleanup seams so cancellation and
/// collision behavior can be tested without waiting for real time.
@MainActor
final class WebsiteCacheAutomaticScheduler {
    typealias SnapshotProvider = @MainActor () -> WebsiteCacheAutomaticScheduleSnapshot?
    typealias Sleeper = @MainActor (TimeInterval) async throws -> Void
    typealias Cleanup = @MainActor () async throws -> Void
    typealias FailureHandler = @MainActor (Error) -> Void

    private let snapshotProvider: SnapshotProvider
    private let sleeper: Sleeper
    private let cleanup: Cleanup
    private let failureHandler: FailureHandler

    init(
        snapshotProvider: @escaping SnapshotProvider,
        sleeper: @escaping Sleeper,
        cleanup: @escaping Cleanup,
        failureHandler: @escaping FailureHandler = { _ in }
    ) {
        self.snapshotProvider = snapshotProvider
        self.sleeper = sleeper
        self.cleanup = cleanup
        self.failureHandler = failureHandler
    }

    func run(initialDelay: TimeInterval? = nil) async {
        var scheduleState = WebsiteCacheAutomaticScheduleState()

        while !Task.isCancelled {
            guard let snapshot = snapshotProvider(),
                  snapshot.automaticCleanupEnabled else { return }
            guard let delay = scheduleState.nextDelay(
                now: snapshot.now,
                lastAutomaticCheckAt: snapshot.lastAutomaticCheckAt,
                lastAutomaticFailureAt: snapshot.lastAutomaticFailureAt,
                minimumCleanupInterval: snapshot.minimumCleanupInterval,
                automaticCleanupEnabled: snapshot.automaticCleanupEnabled,
                initialDelay: initialDelay
            ) else { return }

            do {
                try await sleeper(delay)
            } catch {
                // The default Task.sleep and injected sleepers both use
                // cancellation to terminate the loop without another pass.
                return
            }

            guard !Task.isCancelled,
                  let afterSleepSnapshot = snapshotProvider(),
                  afterSleepSnapshot.automaticCleanupEnabled else { return }

            do {
                try await cleanup()
            } catch WebsiteCacheManagementError.operationAlreadyRunning {
                // Never let an expired persisted timestamp turn a collision
                // into a zero-delay retry.
                scheduleState.recordOperationAlreadyRunning()
            } catch is CancellationError {
                return
            } catch {
                scheduleState.recordCompletedAttempt()
                failureHandler(error)
            }
        }
    }
}
