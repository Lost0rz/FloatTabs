import Foundation

@MainActor
final class SlotLifecycleCoordinator {
    static let defaultColdReleaseDelay: TimeInterval = 30

    private let webViewPool: WebViewPool
    private unowned let container: WebPanelContainerView
    private let coldReleaseDelay: TimeInterval
    private var coldReleaseTokens: [UUID: UUID] = [:]
    private var activeSlotID: UUID?

    init(
        webViewPool: WebViewPool,
        container: WebPanelContainerView,
        coldReleaseDelay: TimeInterval = SlotLifecycleCoordinator.defaultColdReleaseDelay
    ) {
        self.webViewPool = webViewPool
        self.container = container
        self.coldReleaseDelay = max(coldReleaseDelay, 0)
    }

    func reconcile(profiles: [WebAppProfile]) {
        let validIDs = Set(profiles.map(\.id))
        let hotIDs = Set(profiles.filter { $0.residencyPolicy == .hot }.map(\.id))
        let coldIDs = Set(profiles.filter { $0.residencyPolicy == .cold }.map(\.id))

        if let activeSlotID, !validIDs.contains(activeSlotID) {
            self.activeSlotID = nil
        }

        container.retainHotSlots(hotIDs)

        let staleColdReleaseIDs = coldReleaseTokens.keys.filter {
            !validIDs.contains($0) || !coldIDs.contains($0)
        }
        for slotID in staleColdReleaseIDs {
            coldReleaseTokens.removeValue(forKey: slotID)
        }

        for profile in profiles where profile.id != activeSlotID {
            guard webViewPool.contains(slotID: profile.id) else { continue }

            if profile.backgroundMediaPolicy == .pauseWhenInactive {
                webViewPool.pauseMediaPlayback(slotID: profile.id)
            }

            switch profile.residencyPolicy {
            case .hot, .warm:
                coldReleaseTokens.removeValue(forKey: profile.id)
            case .cold:
                if coldReleaseTokens[profile.id] == nil {
                    scheduleColdRelease(slotID: profile.id)
                }
            }
        }
    }

    func activate(profile: WebAppProfile) {
        activeSlotID = profile.id
        coldReleaseTokens.removeValue(forKey: profile.id)
    }

    func deactivate(profile: WebAppProfile) {
        if activeSlotID == profile.id {
            activeSlotID = nil
        }
        container.deactivate(slotID: profile.id, residencyPolicy: profile.residencyPolicy)

        if profile.backgroundMediaPolicy == .pauseWhenInactive {
            webViewPool.pauseMediaPlayback(slotID: profile.id)
        }

        switch profile.residencyPolicy {
        case .hot, .warm:
            coldReleaseTokens.removeValue(forKey: profile.id)
        case .cold:
            if coldReleaseTokens[profile.id] == nil {
                scheduleColdRelease(slotID: profile.id)
            }
        }
    }

    func remove(slotID: UUID) {
        if activeSlotID == slotID {
            activeSlotID = nil
        }
        coldReleaseTokens.removeValue(forKey: slotID)
        container.removeSlot(slotID)
    }

    var pendingColdReleaseCount: Int {
        coldReleaseTokens.count
    }

    private func scheduleColdRelease(slotID: UUID) {
        let token = UUID()
        coldReleaseTokens[slotID] = token

        DispatchQueue.main.asyncAfter(deadline: .now() + coldReleaseDelay) { [weak self] in
            guard let self,
                  self.coldReleaseTokens[slotID] == token else {
                return
            }
            self.coldReleaseTokens.removeValue(forKey: slotID)
            self.container.removeSlot(slotID)
            self.webViewPool.release(slotID: slotID)
        }
    }
}
