import Foundation

/// Runtime attention state for a single web Slot, per the ChatGPT Attention
/// Contract V1. This model is runtime-only: it is never persisted, never
/// restored, and never derived from `WebAppProfile` or any durable document.
enum WebAttentionState: Equatable, Sendable {
    /// No generation is in progress and there is no unseen completed result.
    case idle
    /// The Slot's runtime is actively generating a response.
    case generating
    /// A generation observed in `generating` completed while the Slot was not
    /// user-visible, and the result has not yet been acknowledged.
    case ready

    /// The Contract's residency protection condition: a Slot is protected
    /// while it is generating or holds unacknowledged output.
    var isAttentionProtected: Bool {
        self == .generating || self == .ready
    }
}

/// Normalized runtime events that may drive attention-state transitions.
///
/// These are the semantic events the ChatGPT adapter must produce; provider
/// DOM details are intentionally absent. User acknowledgement is deliberately
/// not an event here: it enters through
/// `WebAttentionCoordinator.acknowledge(slotID:userVisible:)` because it is a
/// presentation fact, not a runtime observation.
enum WebAttentionRuntimeEvent: Equatable, Sendable {
    /// The Slot's runtime began generating a response.
    case generationStarted
    /// The Slot's runtime finished generating. `userVisible` is the
    /// authoritative current visibility supplied by the caller.
    case generationFinished(userVisible: Bool)
    /// The observed runtime was replaced, released, or reset. This never
    /// synthesizes a completion.
    case runtimeReset
}

/// The sole native runtime authority for Slot attention state.
///
/// The coordinator owns exactly one authoritative `Slot UUID -> State`
/// mapping. Every public query is a read-only projection derived from that
/// single map; no parallel authoritative ID sets exist. It performs no
/// persistence, no WebView lifecycle control, and no provider scripting.
@MainActor
final class WebAttentionCoordinator {
    private var states: [UUID: WebAttentionState] = [:]

    init() {}

    // MARK: Read-only projection

    /// The Slot's current attention state. Unknown Slots report `idle` and a
    /// read never materializes an entry.
    func state(for slotID: UUID) -> WebAttentionState {
        states[slotID] ?? .idle
    }

    /// Whether the Slot is attention-protected (`generating` or `ready`).
    func isAttentionProtected(_ slotID: UUID) -> Bool {
        state(for: slotID).isAttentionProtected
    }

    /// Transient projection of all Slots currently holding unacknowledged
    /// output. Derived on demand from the authoritative state map; consumers
    /// must not treat it as a second source of truth.
    var readySlotIDs: Set<UUID> {
        Set(states.compactMap { $0.value == .ready ? $0.key : nil })
    }

    // MARK: Event handling

    /// Applies one normalized runtime event to a Slot and returns the
    /// resulting state.
    ///
    /// Unmapped combinations keep the current state, so an idle baseline or
    /// a stray `generationFinished` can never create `ready`.
    @discardableResult
    func apply(_ event: WebAttentionRuntimeEvent, for slotID: UUID) -> WebAttentionState {
        switch event {
        case .generationStarted:
            // A new generation supersedes both `idle` and a pending
            // unacknowledged `ready`.
            return transition(slotID) { _ in .generating }
        case .generationFinished(let userVisible):
            return transition(slotID) { current in
                guard current == .generating else { return current }
                return userVisible ? .idle : .ready
            }
        case .runtimeReset:
            return transition(slotID) { _ in .idle }
        }
    }

    /// Acknowledges a `ready` Slot's output. Acknowledgement only counts when
    /// the user actually saw the completed result, so a non-visible
    /// acknowledgement leaves the Slot `ready` and the dot lit.
    @discardableResult
    func acknowledge(slotID: UUID, userVisible: Bool) -> WebAttentionState {
        transition(slotID) { current in
            guard current == .ready, userVisible else { return current }
            return .idle
        }
    }

    /// Forgets a Slot's runtime attention state entirely. This drops
    /// bookkeeping only; it never evicts or touches a WebView. Later reads
    /// report the `idle` default.
    func removeSlot(_ slotID: UUID) {
        states.removeValue(forKey: slotID)
    }

    /// Runs one transition from the Slot's current state. Unknown Slots
    /// resolve to `idle` first, and a no-op transition writes nothing.
    private func transition(
        _ slotID: UUID,
        _ resolve: (WebAttentionState) -> WebAttentionState
    ) -> WebAttentionState {
        let current = state(for: slotID)
        let next = resolve(current)
        if next != current {
            states[slotID] = next
        }
        return next
    }
}
