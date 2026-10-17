import Foundation

@MainActor
final class LongTermPerformanceObservationCoordinator: NSObject {
    typealias Sleeper = @MainActor (TimeInterval) async throws -> Void
    typealias ShouldRecord = @MainActor () -> Bool
    typealias Completion = @MainActor () -> Void
    typealias Observation = @MainActor (@escaping ShouldRecord, @escaping Completion) -> Void

    static let defaultInterval: TimeInterval = 60

    private let preferencesStore: AppPreferencesStore
    private let interval: TimeInterval
    private let sleeper: Sleeper
    private let observation: Observation
    private var preferencesAreObserved = false
    private var scheduleTask: Task<Void, Never>?
    private var scheduleGeneration: UInt64 = 0
    private var activeObservationID: UUID?
    private var activeObservationContinuation: CheckedContinuation<Void, Never>?

    var isRunning: Bool { scheduleTask != nil }
    var isObservationInFlight: Bool { activeObservationID != nil }

    init(
        preferencesStore: AppPreferencesStore,
        interval: TimeInterval = 60,
        sleeper: @escaping Sleeper = { delay in
            let boundedDelay = min(
                max(delay, 0),
                Double(UInt64.max) / 1_000_000_000
            )
            try await Task.sleep(nanoseconds: UInt64(boundedDelay * 1_000_000_000))
        },
        observe: @escaping Observation
    ) {
        self.preferencesStore = preferencesStore
        self.interval = max(1, interval)
        self.sleeper = sleeper
        observation = observe
        super.init()
    }

    func start() {
        guard !preferencesAreObserved else {
            refresh()
            return
        }
        preferencesAreObserved = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange(_:)),
            name: .floatTabsRuntimeDiagnosticsModeDidChange,
            object: preferencesStore
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange(_:)),
            name: .floatTabsLongTermPerformanceObservationEnabledDidChange,
            object: preferencesStore
        )
        refresh()
    }

    func refresh() {
        guard preferencesAreObserved else { return }
        guard preferencesStore.isLongTermPerformanceObservationEffective else {
            cancelSchedule()
            return
        }
        guard scheduleTask == nil else { return }

        scheduleGeneration &+= 1
        let generation = scheduleGeneration
        scheduleTask = Task { @MainActor [weak self] in
            await self?.run(generation: generation)
        }
    }

    func stop() {
        NotificationCenter.default.removeObserver(
            self,
            name: .floatTabsRuntimeDiagnosticsModeDidChange,
            object: preferencesStore
        )
        NotificationCenter.default.removeObserver(
            self,
            name: .floatTabsLongTermPerformanceObservationEnabledDidChange,
            object: preferencesStore
        )
        preferencesAreObserved = false
        cancelSchedule()
    }

    @objc private func preferencesDidChange(_ notification: Notification) {
        refresh()
    }

    private func run(generation: UInt64) async {
        while isScheduleCurrent(generation) {
            do {
                try await sleeper(interval)
            } catch {
                break
            }
            guard isScheduleCurrent(generation) else { break }

            let observationID = UUID()
            activeObservationID = observationID
            await withCheckedContinuation { continuation in
                activeObservationContinuation = continuation
                observation(
                    { [weak self] in
                        self?.canRecord(generation: generation, observationID: observationID) ?? false
                    },
                    { [weak self] in
                        self?.finishObservation(id: observationID)
                    }
                )
            }
            guard isScheduleCurrent(generation) else { break }
        }

        if scheduleGeneration == generation {
            scheduleTask = nil
            activeObservationID = nil
            activeObservationContinuation = nil
            refresh()
        }
    }

    private func isScheduleCurrent(_ generation: UInt64) -> Bool {
        generation == scheduleGeneration
            && preferencesStore.isLongTermPerformanceObservationEffective
    }

    private func canRecord(generation: UInt64, observationID: UUID) -> Bool {
        isScheduleCurrent(generation) && activeObservationID == observationID
    }

    private func finishObservation(id: UUID) {
        guard activeObservationID == id else { return }
        activeObservationID = nil
        let continuation = activeObservationContinuation
        activeObservationContinuation = nil
        continuation?.resume()
    }

    private func cancelSchedule() {
        scheduleGeneration &+= 1
        scheduleTask?.cancel()
        scheduleTask = nil

        activeObservationID = nil
        let continuation = activeObservationContinuation
        activeObservationContinuation = nil
        continuation?.resume()
    }
}
