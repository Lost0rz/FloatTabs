import Foundation

/// Owns background delivery and retry timing. All socket waits happen on this
/// detached utility task; outbox mutations use their separate actor.
final class MemoXSenderService: @unchecked Sendable {
    private let outbox: MemoXOutboxStore
    private let client: MemoXUnixSocketClient
    private let workerLock = NSLock()
    private let wakeSignal = DispatchSemaphore(value: 0)
    private var worker: Task<Void, Never>?

    init(outbox: MemoXOutboxStore, client: MemoXUnixSocketClient = MemoXUnixSocketClient()) {
        self.outbox = outbox
        self.client = client
    }

    func start() {
        workerLock.lock()
        defer { workerLock.unlock() }
        guard worker == nil else { return }
        worker = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.runLoop()
        }
    }

    /// Wakes the background worker after a new durable event is committed.
    func wake() {
        wakeSignal.signal()
    }

    /// Cancels local waiting and waits only for the client's absolute socket
    /// deadline (five seconds in production). Durable pending files remain.
    func requestStop() {
        guard let runningWorker = workerSnapshot() else { return }
        runningWorker.cancel()
        wakeSignal.signal()
    }

    func stop() async {
        let runningWorker = workerSnapshot()
        guard let runningWorker else { return }
        runningWorker.cancel()
        wakeSignal.signal()
        await runningWorker.value
        clearWorker()
    }

    private func workerSnapshot() -> Task<Void, Never>? {
        workerLock.lock()
        let runningWorker = worker
        workerLock.unlock()
        return runningWorker
    }

    private func clearWorker() {
        workerLock.lock()
        worker = nil
        workerLock.unlock()
    }

    private func runLoop() async {
        var nextEligibleByEvent: [String: UInt64] = [:]
        while !Task.isCancelled {
            let records: [MemoXOutboxRecordV1]
            do {
                records = try await outbox.pendingRecords()
            } catch {
                wait(until: Self.deadline(after: 2))
                continue
            }
            if records.isEmpty {
                wait(until: nil)
                continue
            }

            let now = DispatchTime.now().uptimeNanoseconds
            for record in records {
                if Task.isCancelled { return }
                if let nextEligible = nextEligibleByEvent[record.eventID], nextEligible > now {
                    continue
                }
                nextEligibleByEvent.removeValue(forKey: record.eventID)
                if let retryAt = await deliver(record) {
                    nextEligibleByEvent[record.eventID] = retryAt
                }
            }

            if Task.isCancelled { return }
            let earliestRetry = nextEligibleByEvent.values.min()
            wait(until: earliestRetry)
        }
    }

    /// Returns the retry eligibility time for failures, or nil after a valid
    /// matching ACK/permanent REJECT.
    private func deliver(_ record: MemoXOutboxRecordV1) async -> UInt64? {
        do {
            switch try client.send(record.envelope) {
            case let .ack(eventID, _, _) where eventID == record.eventID:
                do {
                    _ = try await outbox.retireAfterMatchingACK(
                        eventID: eventID,
                        expectedEnvelope: record.envelope
                    )
                    return nil
                } catch {
                    return await persistFailure(for: record, code: "outbox_error")
                }
            case .ack:
                return await persistFailure(for: record, code: "protocol_uncertain")
            case let .reject(eventID, _) where eventID == record.eventID:
                do {
                    _ = try await outbox.quarantineAfterMatchingReject(
                        eventID: record.eventID,
                        expectedEnvelope: record.envelope
                    )
                    return nil
                } catch {
                    return await persistFailure(for: record, code: "outbox_error")
                }
            case .reject:
                return await persistFailure(for: record, code: "protocol_uncertain")
            case let .retry(eventID, code):
                let safeCode = eventID == nil || eventID == record.eventID ? code : "protocol_uncertain"
                return await persistFailure(for: record, code: safeCode)
            }
        } catch let error as MemoXUnixSocketError {
            return await persistFailure(for: record, code: error.safeCode)
        } catch {
            return await persistFailure(for: record, code: "protocol_uncertain")
        }
    }

    private func persistFailure(for record: MemoXOutboxRecordV1, code: String) async -> UInt64 {
        let attempt = record.attemptCount + 1
        do {
            try await outbox.recordFailure(eventID: record.eventID, at: Date(), safeCode: code)
        } catch {
            // Keep the same bounded cadence in memory if an attempt-state rewrite
            // itself fails; the pending event remains available for recovery.
        }
        return Self.deadline(after: MemoXRetryPolicy.delay(afterFailure: attempt))
    }

    private func wait(until deadline: UInt64?) {
        guard let deadline else {
            _ = wakeSignal.wait(timeout: .distantFuture)
            return
        }
        _ = wakeSignal.wait(timeout: DispatchTime(uptimeNanoseconds: deadline))
    }

    private static func deadline(after interval: TimeInterval) -> UInt64 {
        let nanoseconds = UInt64(max(0, interval) * 1_000_000_000)
        return DispatchTime.now().uptimeNanoseconds &+ nanoseconds
    }
}
