import Foundation

/// Stateless forwarding of normalized bridge observations into the one
/// attention authority.
///
/// Stage C routing boundary, owned by `PanelController`: the exact mapping
/// from Stage B observations to Stage A runtime events, resolving actual
/// user visibility through the one presentation helper only at completion
/// time. This type keeps no state and owns no visibility logic — the
/// visibility answer is always supplied by the owner.
@MainActor
struct WebAttentionObservationRouter {
    private let attentionCoordinator: WebAttentionCoordinator
    private let isUserVisible: @MainActor (UUID) -> Bool

    init(
        attentionCoordinator: WebAttentionCoordinator,
        isUserVisible: @escaping @MainActor (UUID) -> Bool
    ) {
        self.attentionCoordinator = attentionCoordinator
        self.isUserVisible = isUserVisible
    }

    func handle(_ observation: ChatGPTAttentionObservation, for slotID: UUID) {
        switch observation {
        case .generationStarted:
            attentionCoordinator.apply(.generationStarted, for: slotID)
        case .generationFinished:
            attentionCoordinator.apply(
                .generationFinished(userVisible: isUserVisible(slotID)),
                for: slotID
            )
        case .runtimeReset:
            attentionCoordinator.apply(.runtimeReset, for: slotID)
        }
    }
}
