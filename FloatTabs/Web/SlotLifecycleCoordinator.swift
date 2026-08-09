import Foundation

@MainActor
final class SlotLifecycleCoordinator {
    static let defaultColdReleaseDelay: TimeInterval = 30

    private let webViewPool: WebViewPool
    private unowned let container: WebPanelContainerView
    private let coldReleaseDelay: TimeInterval
    private var coldReleaseTokens: [UUID: UUID] = [:]

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

        container.retainHotSlots(hotIDs)

        let staleColdReleaseIDs = coldReleaseTokens.keys.filter {
            !validIDs.contains($0) || !coldIDs.contains($0)
        }
        for slotID in staleColdReleaseIDs {
            coldReleaseTokens.removeValue(forKey: slotID)
        }
    }

    func activate(profile: WebAppProfile) {
        coldReleaseTokens.removeValue(forKey: profile.id)
        webViewPool.setMediaPlaybackSuspended(slotID: profile.id, suspended: false)
    }

    func deactivate(profile: WebAppProfile) {
        container.deactivate(slotID: profile.id, residencyPolicy: profile.residencyPolicy)

        switch profile.backgroundMediaPolicy {
        case .pauseWhenInactive:
            webViewPool.setMediaPlaybackSuspended(slotID: profile.id, suspended: true)
        case .allowBackgroundAudio:
            webViewPool.setMediaPlaybackSuspended(slotID: profile.id, suspended: false)
        }

        switch profile.residencyPolicy {
        case .hot, .warm:
            coldReleaseTokens.removeValue(forKey: profile.id)
        case .cold:
            scheduleColdRelease(slotID: profile.id)
        }
    }

    func remove(slotID: UUID) {
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
