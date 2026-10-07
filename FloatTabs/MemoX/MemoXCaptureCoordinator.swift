import Foundation

/// Keeps a completion bound to the generation that produced it. Attention and
/// WebKit callbacks are routed on MainActor; this gate performs no I/O.
@MainActor
final class MemoXCaptureEpochGate {
    struct Attempt: Equatable, Sendable {
        let id: UUID
        let slotID: UUID
        let epoch: UUID
        let expectedResponseIdentity: ChatGPTResponseIdentity?
        let completedAt: Date
    }

    enum Decision: Equatable {
        case accepted
        case retryable
        case discarded
    }

    private var epochBySlot: [UUID: UUID] = [:]
    private var consumedAttemptBySlot: [UUID: UUID] = [:]

    func observe(_ observation: ChatGPTAttentionObservation, for slotID: UUID) {
        guard observation == .generationStarted || observation == .runtimeReset else { return }
        epochBySlot[slotID] = UUID()
        consumedAttemptBySlot.removeValue(forKey: slotID)
    }

    func beginCompletion(
        for slotID: UUID,
        responseIdentity: ChatGPTResponseIdentity?,
        completedAt: Date
    ) -> Attempt {
        let epoch = epochBySlot[slotID] ?? UUID()
        epochBySlot[slotID] = epoch
        return Attempt(
            id: UUID(),
            slotID: slotID,
            epoch: epoch,
            expectedResponseIdentity: responseIdentity,
            completedAt: completedAt
        )
    }

    func isCurrent(_ attempt: Attempt) -> Bool {
        epochBySlot[attempt.slotID] == attempt.epoch
    }

    func evaluate(_ payload: ChatGPTResponsePayload?, for attempt: Attempt) -> Decision {
        guard isCurrent(attempt), consumedAttemptBySlot[attempt.slotID] != attempt.id else {
            return .discarded
        }
        guard let payload, payload.kind == .response, !payload.blocks.isEmpty else {
            return .retryable
        }
        if let expected = attempt.expectedResponseIdentity, payload.responseIdentity != expected {
            return .retryable
        }
        consumedAttemptBySlot[attempt.slotID] = attempt.id
        return .accepted
    }
}

/// Admits only validated generation completions and binds each extraction to
/// the in-memory generation epoch that produced it.
@MainActor
final class MemoXCaptureCoordinator {
    private let outbox: MemoXOutboxStore
    private let sender: MemoXSenderService
    private let responseBridgeProvider: @MainActor (UUID) -> ChatGPTResponseExtracting?
    private let epochGate = MemoXCaptureEpochGate()
    private var retryTaskBySlot: [UUID: Task<Void, Never>] = [:]

    init(
        outbox: MemoXOutboxStore,
        sender: MemoXSenderService,
        responseBridgeProvider: @escaping @MainActor (UUID) -> ChatGPTResponseExtracting?
    ) {
        self.outbox = outbox
        self.sender = sender
        self.responseBridgeProvider = responseBridgeProvider
    }

    func observe(_ observation: ChatGPTAttentionObservation, for slotID: UUID) {
        epochGate.observe(observation, for: slotID)
        guard observation == .generationStarted || observation == .runtimeReset else { return }
        retryTaskBySlot.removeValue(forKey: slotID)?.cancel()
    }

    func handleValidCompletion(
        slotID: UUID,
        responseIdentity: ChatGPTResponseIdentity?,
        completedAt: Date
    ) {
        retryTaskBySlot.removeValue(forKey: slotID)?.cancel()
        let attempt = epochGate.beginCompletion(
            for: slotID,
            responseIdentity: responseIdentity,
            completedAt: completedAt
        )
        extract(attempt, number: 1)
    }

    private func extract(_ attempt: MemoXCaptureEpochGate.Attempt, number: Int) {
        guard epochGate.isCurrent(attempt) else { return }
        guard let bridge = responseBridgeProvider(attempt.slotID) else {
            handleExtraction(nil, attempt: attempt, number: number)
            return
        }
        bridge.extractLatest { [weak self] payload in
            self?.handleExtraction(payload, attempt: attempt, number: number)
        }
    }

    private func handleExtraction(
        _ payload: ChatGPTResponsePayload?,
        attempt: MemoXCaptureEpochGate.Attempt,
        number: Int
    ) {
        guard epochGate.isCurrent(attempt) else { return }
        switch epochGate.evaluate(payload, for: attempt) {
        case .accepted:
            commit(payload, for: attempt)
        case .discarded:
            retryTaskBySlot.removeValue(forKey: attempt.slotID)?.cancel()
        case .retryable:
            scheduleOneRetry(for: attempt, afterAttempt: number)
        }
    }

    private func commit(_ payload: ChatGPTResponsePayload?, for attempt: MemoXCaptureEpochGate.Attempt) {
        retryTaskBySlot.removeValue(forKey: attempt.slotID)?.cancel()
        guard let payload else { return }
        let outbox = self.outbox
        let sender = self.sender
        Task.detached(priority: .utility) {
            do {
                let bytes = try MemoXResponsePayloadV1(blocks: payload.blocks).encodedData()
                _ = try await outbox.commit(
                    payloadBytes: bytes,
                    slotID: attempt.slotID,
                    providerNativeEventID: attempt.expectedResponseIdentity,
                    occurredAt: attempt.completedAt
                )
                sender.start()
                sender.wake()
            } catch {
                // A failed durable commit never reaches the sender.
            }
        }
    }

    private func scheduleOneRetry(for attempt: MemoXCaptureEpochGate.Attempt, afterAttempt number: Int) {
        guard number == 1, epochGate.isCurrent(attempt) else { return }
        let task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard let self, self.epochGate.isCurrent(attempt) else { return }
            self.retryTaskBySlot.removeValue(forKey: attempt.slotID)
            self.extract(attempt, number: 2)
        }
        retryTaskBySlot[attempt.slotID] = task
    }
}
