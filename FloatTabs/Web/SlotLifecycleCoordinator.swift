import AppKit
import Dispatch
import Darwin
import Foundation

enum SlotMemoryPressureLevel {
    case warning
    case critical
}

private struct RuntimeBudgetPolicy {
    static let defaultManagedResidentTarget = 3

    struct Candidate {
        let slotID: UUID
        let residencyPolicy: SlotResidencyPolicy
        let lastUsedAt: Date
        let isProtected: Bool
    }

    struct Decision {
        let target: Int
        let managedResidentCount: Int
        let evictSlotIDs: [UUID]
        let oversubscribedBy: Int
    }

    static func decide(candidates: [Candidate], target: Int) -> Decision {
        let normalizedTarget = max(target, 0)
        let managedResidentCount = candidates.count
        let requiredEvictions = max(managedResidentCount - normalizedTarget, 0)

        let eligible = candidates
            .filter { !$0.isProtected && $0.residencyPolicy != .hot }
            .sorted { lhs, rhs in
                let lhsRank = evictionRank(lhs.residencyPolicy)
                let rhsRank = evictionRank(rhs.residencyPolicy)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                if lhs.lastUsedAt != rhs.lastUsedAt {
                    return lhs.lastUsedAt < rhs.lastUsedAt
                }
                return lhs.slotID.uuidString < rhs.slotID.uuidString
            }

        let evictSlotIDs = Array(eligible.prefix(requiredEvictions).map(\.slotID))
        let remainingManaged = managedResidentCount - evictSlotIDs.count
        return Decision(
            target: normalizedTarget,
            managedResidentCount: managedResidentCount,
            evictSlotIDs: evictSlotIDs,
            oversubscribedBy: max(remainingManaged - normalizedTarget, 0)
        )
    }

    private static func evictionRank(_ policy: SlotResidencyPolicy) -> Int {
        switch policy {
        case .cold: return 0
        case .warm: return 1
        case .hot: return 2
        }
    }
}

@MainActor
final class SlotLifecycleCoordinator {
    nonisolated static let defaultColdReleaseDelay: TimeInterval = 30
    nonisolated static let defaultWarmReleaseDelay: TimeInterval = 120
    nonisolated static let defaultHiddenActiveGraceDelay: TimeInterval = 120
    nonisolated static let defaultMediaProtectionPollDelay: TimeInterval = 10
    nonisolated static let defaultManagedResidentTarget = RuntimeBudgetPolicy.defaultManagedResidentTarget

    typealias MediaPlayingQuery = (UUID, @escaping (Bool) -> Void) -> Void
    typealias MediaPauseAction = (UUID) -> Void
    typealias RuntimeReleasedHandler = @MainActor (WebAppProfile) -> Void
    typealias RuntimeReleasePreparation = @MainActor (UUID) -> Void
    typealias SlotBecameInactiveHandler = @MainActor (WebAppProfile) -> Void
    typealias AttentionProtectionQuery = @MainActor (UUID) -> Bool

    private struct InactivePlan {
        let token: UUID
        let profile: WebAppProfile
        let residencyPolicy: SlotResidencyPolicy
        let backgroundMediaPolicy: BackgroundMediaPolicy
    }

    private struct ProtectionState {
        let media: Bool
        let attention: Bool
    }

    private let webViewPool: WebViewPool
    private unowned let container: WebPanelContainerView
    private var coldReleaseDelay: TimeInterval
    private var warmReleaseDelay: TimeInterval
    private let hiddenActiveGraceDelay: TimeInterval
    private let mediaProtectionPollDelay: TimeInterval
    private let managedResidentTarget: Int
    private let mediaPlayingQuery: MediaPlayingQuery
    private let mediaPauseAction: MediaPauseAction
    private let onRuntimeReleased: RuntimeReleasedHandler
    private let prepareRuntimeForRelease: RuntimeReleasePreparation
    private let onSlotBecameInactive: SlotBecameInactiveHandler
    private let attentionProtectionQuery: AttentionProtectionQuery
    private let diagnostics: any RuntimeDiagnosticRecording

    private var inactivePlans: [UUID: InactivePlan] = [:]
    private var knownProfiles: [UUID: WebAppProfile] = [:]
    private var mediaProtectedSlotIDs = Set<UUID>()
    private var mediaProtectionPendingSlotIDs = Set<UUID>()
    private var hiddenActiveToken: UUID?
    private var activeSlotID: UUID?
    private var fullscreenSourceProfile: WebAppProfile?
    private var supplementalVisibleProfile: WebAppProfile?
    private var panelIsVisible = false
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var budgetEvaluationInProgress = false

    init(
        webViewPool: WebViewPool,
        container: WebPanelContainerView,
        coldReleaseDelay: TimeInterval = SlotLifecycleCoordinator.defaultColdReleaseDelay,
        warmReleaseDelay: TimeInterval = SlotLifecycleCoordinator.defaultWarmReleaseDelay,
        hiddenActiveGraceDelay: TimeInterval = SlotLifecycleCoordinator.defaultHiddenActiveGraceDelay,
        mediaProtectionPollDelay: TimeInterval = SlotLifecycleCoordinator.defaultMediaProtectionPollDelay,
        managedResidentTarget: Int = SlotLifecycleCoordinator.defaultManagedResidentTarget,
        mediaPlayingQuery: MediaPlayingQuery? = nil,
        mediaPauseAction: MediaPauseAction? = nil,
        onRuntimeReleased: @escaping RuntimeReleasedHandler = { _ in },
        prepareRuntimeForRelease: @escaping RuntimeReleasePreparation = { _ in },
        onSlotBecameInactive: @escaping SlotBecameInactiveHandler = { _ in },
        attentionProtectionQuery: @escaping AttentionProtectionQuery = { _ in false },
        diagnostics: any RuntimeDiagnosticRecording = RuntimeDiagnosticNoopRecorder(),
        installsMemoryPressureSource: Bool = true
    ) {
        self.webViewPool = webViewPool
        self.container = container
        self.coldReleaseDelay = max(coldReleaseDelay, 0)
        self.warmReleaseDelay = max(warmReleaseDelay, 0)
        self.hiddenActiveGraceDelay = max(hiddenActiveGraceDelay, 0)
        self.mediaProtectionPollDelay = max(mediaProtectionPollDelay, 0.01)
        self.managedResidentTarget = max(managedResidentTarget, 0)
        self.mediaPlayingQuery = mediaPlayingQuery ?? { [weak webViewPool] slotID, completion in
            guard let webViewPool else {
                completion(false)
                return
            }
            webViewPool.isMediaPlaying(slotID: slotID, completion: completion)
        }
        self.mediaPauseAction = mediaPauseAction ?? { [weak webViewPool] slotID in
            webViewPool?.pauseMediaPlayback(slotID: slotID)
        }
        self.onRuntimeReleased = onRuntimeReleased
        self.prepareRuntimeForRelease = prepareRuntimeForRelease
        self.onSlotBecameInactive = onSlotBecameInactive
        self.attentionProtectionQuery = attentionProtectionQuery
        self.diagnostics = diagnostics

        if installsMemoryPressureSource {
            configureMemoryPressureSource()
        }
    }

    func updateReleaseDelays(
        coldReleaseDelay: TimeInterval,
        warmReleaseDelay: TimeInterval
    ) {
        let normalizedColdDelay = max(coldReleaseDelay, 0)
        let normalizedWarmDelay = max(warmReleaseDelay, 0)
        guard normalizedColdDelay != self.coldReleaseDelay
                || normalizedWarmDelay != self.warmReleaseDelay else {
            return
        }

        self.coldReleaseDelay = normalizedColdDelay
        self.warmReleaseDelay = normalizedWarmDelay

        let profiles = inactivePlans.values.map(\.profile)
        for profile in profiles {
            guard profile.residencyPolicy == .warm || profile.residencyPolicy == .cold,
                  webViewPool.contains(slotID: profile.id),
                  !isVisibleSlot(profile.id) else {
                continue
            }
            let preserveMediaProtection = mediaProtectedSlotIDs.contains(profile.id)
            cancelInactivePlan(
                slotID: profile.id,
                preservingMediaProtection: preserveMediaProtection
            )
            createInactivePlan(for: profile)
        }
        enforceRuntimeBudget(reason: "retention_settings_changed")
    }

    func reconcile(profiles: [WebAppProfile]) {
        knownProfiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        let validIDs = Set(profiles.map(\.id))
        let hotIDs = Set(profiles.filter { $0.residencyPolicy == .hot }.map(\.id))

        if let activeSlotID, !validIDs.contains(activeSlotID) {
            self.activeSlotID = nil
        }

        container.retainHotSlots(hotIDs)

        for slotID in Array(inactivePlans.keys) where
            !validIDs.contains(slotID) || !webViewPool.contains(slotID: slotID) {
            cancelInactivePlan(slotID: slotID)
        }

        for profile in profiles {
            if isVisibleSlot(profile.id) {
                cancelInactivePlan(slotID: profile.id)
                continue
            }
            guard webViewPool.contains(slotID: profile.id) else {
                cancelInactivePlan(slotID: profile.id)
                continue
            }

            if profile.backgroundMediaPolicy == .pauseWhenInactive {
                mediaPauseAction(profile.id)
            }

            switch profile.residencyPolicy {
            case .hot:
                cancelInactivePlan(slotID: profile.id)
            case .warm, .cold:
                ensureInactivePlan(for: profile)
            }
        }

        enforceRuntimeBudget(reason: "reconcile")
    }

    func setPanelVisible(_ visible: Bool, activeProfile: WebAppProfile?) {
        panelIsVisible = visible
        if let activeProfile {
            knownProfiles[activeProfile.id] = activeProfile
        }
        diagnostics.record(
            event: visible ? "slot_lifecycle.panel_visible" : "slot_lifecycle.panel_hidden",
            level: .debug,
            subsystem: "lifecycle",
            fields: ["active_slot_id": .string(activeProfile?.id.uuidString ?? "none")]
        )
        hiddenActiveToken = nil

        guard let activeProfile else { return }
        if visible {
            activeSlotID = activeProfile.id
            cancelInactivePlan(slotID: activeProfile.id)
            enforceRuntimeBudget(reason: "panel_visible")
        } else if activeSlotID == activeProfile.id {
            guard fullscreenSourceProfile?.id != activeProfile.id else { return }
            if activeProfile.backgroundMediaPolicy == .pauseWhenInactive {
                mediaPauseAction(activeProfile.id)
            }
            onSlotBecameInactive(activeProfile)
            scheduleHiddenActiveTransition(profile: activeProfile)
        }
    }

    func activate(profile: WebAppProfile) {
        knownProfiles[profile.id] = profile
        diagnostics.record(
            event: "slot_lifecycle.activate",
            level: .debug,
            subsystem: "lifecycle",
            fields: ["slot_id": .string(profile.id.uuidString)]
        )
        activeSlotID = profile.id
        cancelInactivePlan(slotID: profile.id)
        hiddenActiveToken = nil

        if !panelIsVisible {
            scheduleHiddenActiveTransition(profile: profile)
        }
        enforceRuntimeBudget(reason: "activate")
    }

    func deactivate(profile: WebAppProfile) {
        knownProfiles[profile.id] = profile
        guard fullscreenSourceProfile?.id != profile.id else { return }
        diagnostics.record(
            event: "slot_lifecycle.deactivate",
            level: .debug,
            subsystem: "lifecycle",
            fields: ["slot_id": .string(profile.id.uuidString)]
        )
        if activeSlotID == profile.id {
            onSlotBecameInactive(profile)
            activeSlotID = nil
        }
        hiddenActiveToken = nil
        container.deactivate(slotID: profile.id, residencyPolicy: profile.residencyPolicy)
        prepareInactive(profile: profile)
        enforceRuntimeBudget(reason: "deactivate")
    }

    func restartAfterProtectionEnded(profile: WebAppProfile) {
        knownProfiles[profile.id] = profile
        let slotID = profile.id
        guard let existingPlan = inactivePlans[slotID],
              existingPlan.residencyPolicy == profile.residencyPolicy,
              existingPlan.backgroundMediaPolicy == profile.backgroundMediaPolicy,
              profile.residencyPolicy == .warm || profile.residencyPolicy == .cold,
              webViewPool.contains(slotID: slotID),
              !isVisibleSlot(slotID),
              !attentionProtectionQuery(slotID) else {
            return
        }

        let preserveMediaProtection = mediaProtectedSlotIDs.contains(slotID)
        cancelInactivePlan(
            slotID: slotID,
            preservingMediaProtection: preserveMediaProtection
        )
        createInactivePlan(for: profile)
        enforceRuntimeBudget(reason: "protection_ended")
    }

    func restartAfterAttentionProtectionEnded(profile: WebAppProfile) {
        restartAfterProtectionEnded(profile: profile)
    }

    func beginFullscreenSourceVisibility(profile: WebAppProfile) {
        knownProfiles[profile.id] = profile
        fullscreenSourceProfile = profile
        diagnostics.record(
            event: "slot_lifecycle.fullscreen_protected",
            level: .notice,
            subsystem: "lifecycle",
            fields: ["slot_id": .string(profile.id.uuidString)]
        )
        cancelInactivePlan(slotID: profile.id)
        if hiddenActiveToken != nil, activeSlotID == profile.id {
            hiddenActiveToken = nil
        }
    }

    func endFullscreenSourceVisibility(profile: WebAppProfile) {
        guard fullscreenSourceProfile?.id == profile.id else { return }
        fullscreenSourceProfile = nil
        diagnostics.record(
            event: "slot_lifecycle.fullscreen_released",
            level: .notice,
            subsystem: "lifecycle",
            fields: ["slot_id": .string(profile.id.uuidString)]
        )
        enforceRuntimeBudget(reason: "fullscreen_released")
    }

    func beginSupplementalVisibility(profile: WebAppProfile) {
        knownProfiles[profile.id] = profile
        if let previous = supplementalVisibleProfile,
           previous.id != profile.id {
            endSupplementalVisibility(profile: previous, prepareAsInactive: true)
        }
        supplementalVisibleProfile = profile
        cancelInactivePlan(slotID: profile.id)
    }

    func endSupplementalVisibility(
        profile: WebAppProfile,
        prepareAsInactive: Bool
    ) {
        guard supplementalVisibleProfile?.id == profile.id else { return }
        supplementalVisibleProfile = nil
        guard prepareAsInactive, activeSlotID != profile.id else {
            enforceRuntimeBudget(reason: "supplemental_visibility_ended")
            return
        }
        onSlotBecameInactive(profile)
        prepareInactive(profile: profile)
        enforceRuntimeBudget(reason: "supplemental_visibility_ended")
    }

    func remove(slotID: UUID) {
        prepareRuntimeForRelease(slotID)
        if activeSlotID == slotID {
            activeSlotID = nil
        }
        if fullscreenSourceProfile?.id == slotID {
            fullscreenSourceProfile = nil
        }
        if supplementalVisibleProfile?.id == slotID {
            supplementalVisibleProfile = nil
        }
        knownProfiles.removeValue(forKey: slotID)
        cancelInactivePlan(slotID: slotID)
        container.removeSlot(slotID)
        enforceRuntimeBudget(reason: "slot_removed")
    }

    func reset(slotIDs: Set<UUID>) {
        hiddenActiveToken = nil
        activeSlotID = nil
        fullscreenSourceProfile = nil
        supplementalVisibleProfile = nil
        inactivePlans.removeAll()
        mediaProtectedSlotIDs.removeAll()
        mediaProtectionPendingSlotIDs.removeAll()
        knownProfiles.removeAll()
        for slotID in slotIDs {
            prepareRuntimeForRelease(slotID)
            container.removeSlot(slotID)
        }
    }

    func handleMemoryPressure(_ level: SlotMemoryPressureLevel) {
        let incidentContext = RuntimeDiagnosticIncidentContext(
            id: UUID(),
            kind: .memoryPressure,
            trigger: level == .critical ? "critical" : "warning",
            startedAtUptime: ProcessInfo.processInfo.systemUptime
        )
        var pressureFields = incidentContext.fields(phase: .trigger)
        pressureFields.merge([
            "level": .string(level == .critical ? "critical" : "warning"),
            "host_resident_size_bytes": Self.currentProcessResidentSizeBytes().map(Self.diagnosticInteger) ?? .null,
            "system_physical_memory_bytes": Self.diagnosticInteger(ProcessInfo.processInfo.physicalMemory),
            "resident_slot_count": .integer(Int64(webViewPool.count)),
            "active_slot_id": activeSlotID.map { .string($0.uuidString) } ?? .null,
            "web_process_resource_attribution": .string("unavailable_public_api")
        ]) { _, new in new }
        diagnostics.record(
            event: "slot_lifecycle.memory_pressure",
            level: .warning,
            subsystem: "lifecycle",
            fields: pressureFields
        )

        recordMemoryPressureEvaluations(
            level: level,
            incidentContext: incidentContext
        )
        enforceRuntimeBudget(
            reason: level == .critical ? "memory_pressure_critical" : "memory_pressure_warning",
            pressure: level,
            incidentContext: incidentContext
        )

        var completionFields = incidentContext.fields(phase: .closure)
        completionFields["incident_outcome"] = .string("evaluation_complete")
        diagnostics.record(
            event: "slot_lifecycle.memory_pressure.completed",
            level: .notice,
            subsystem: "lifecycle",
            fields: completionFields
        )
    }

    var pendingColdReleaseCount: Int {
        inactivePlans.values.filter { $0.residencyPolicy == .cold }.count
    }

    var pendingWarmReleaseCount: Int {
        inactivePlans.values.filter { $0.residencyPolicy == .warm }.count
    }

    var mediaProtectedIDs: Set<UUID> {
        mediaProtectedSlotIDs
    }

    var isHiddenActiveGracePending: Bool {
        hiddenActiveToken != nil
    }

    func diagnosticSnapshotFields(for slotID: UUID) -> [String: RuntimeDiagnosticValue] {
        let plan = inactivePlans[slotID]
        let protection = protectionState(slotID: slotID)
        return [
            "lifecycle_slot_active": .bool(activeSlotID == slotID),
            "lifecycle_pending_release": .bool(plan != nil),
            "lifecycle_pending_release_class": .string(plan?.residencyPolicy.rawValue ?? "none"),
            "lifecycle_media_protected": .bool(protection.media),
            "lifecycle_attention_protected": .bool(protection.attention),
            "lifecycle_managed_resident_target": .integer(Int64(managedResidentTarget))
        ]
    }

    #if DEBUG
    func debugInactivePlanToken(slotID: UUID) -> UUID? {
        inactivePlans[slotID]?.token
    }
    #endif

    private func configureMemoryPressureSource() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        memoryPressureSource = source
        source.setEventHandler { [weak self] in
            guard let self,
                  let data = self.memoryPressureSource?.data else { return }
            if data.contains(.critical) {
                self.handleMemoryPressure(.critical)
            } else if data.contains(.warning) {
                self.handleMemoryPressure(.warning)
            }
        }
        source.resume()
    }

    private func prepareInactive(profile: WebAppProfile) {
        knownProfiles[profile.id] = profile
        guard webViewPool.contains(slotID: profile.id) else {
            cancelInactivePlan(slotID: profile.id)
            return
        }

        if profile.backgroundMediaPolicy == .pauseWhenInactive {
            mediaPauseAction(profile.id)
        }

        switch profile.residencyPolicy {
        case .hot:
            cancelInactivePlan(slotID: profile.id)
        case .warm, .cold:
            ensureInactivePlan(for: profile)
        }
    }

    private func ensureInactivePlan(for profile: WebAppProfile) {
        if let existing = inactivePlans[profile.id],
           existing.residencyPolicy == profile.residencyPolicy,
           existing.backgroundMediaPolicy == profile.backgroundMediaPolicy,
           existing.profile.browserProfileID == profile.browserProfileID {
            return
        }

        cancelInactivePlan(slotID: profile.id)
        createInactivePlan(for: profile)
    }

    private func createInactivePlan(for profile: WebAppProfile) {
        let plan = InactivePlan(
            token: UUID(),
            profile: profile,
            residencyPolicy: profile.residencyPolicy,
            backgroundMediaPolicy: profile.backgroundMediaPolicy
        )
        inactivePlans[profile.id] = plan
        diagnostics.record(
            event: "slot_lifecycle.inactive_plan.created",
            level: .info,
            subsystem: "lifecycle",
            fields: [
                "slot_id": .string(profile.id.uuidString),
                "inactive_plan_id": .string(plan.token.uuidString),
                "residency": .string(profile.residencyPolicy.rawValue)
            ]
        )

        if profile.backgroundMediaPolicy == .allowBackgroundAudio {
            mediaProtectionPendingSlotIDs.insert(profile.id)
            evaluateMediaProtection(for: profile, plan: plan)
        } else {
            scheduleRelease(for: profile, plan: plan)
        }
    }

    private func evaluateMediaProtection(
        for profile: WebAppProfile,
        plan: InactivePlan
    ) {
        mediaPlayingQuery(profile.id) { [weak self] isPlaying in
            guard let self,
                  self.planMatches(plan, slotID: profile.id),
                  !self.isVisibleSlot(profile.id),
                  self.webViewPool.contains(slotID: profile.id) else {
                return
            }

            self.mediaProtectionPendingSlotIDs.remove(profile.id)
            if isPlaying {
                let wasProtected = self.mediaProtectedSlotIDs.insert(profile.id).inserted
                if wasProtected {
                    self.diagnostics.record(
                        event: "slot_lifecycle.media_protected",
                        level: .notice,
                        subsystem: "lifecycle",
                        fields: [
                            "slot_id": .string(profile.id.uuidString),
                            "inactive_plan_id": .string(plan.token.uuidString)
                        ]
                    )
                }
                self.scheduleMediaProtectionRecheck(for: profile, plan: plan)
            } else {
                self.mediaProtectedSlotIDs.remove(profile.id)
                guard !self.isProactivelyProtected(slotID: profile.id) else {
                    let protection = self.protectionState(slotID: profile.id)
                    self.recordProtectionObservations(
                        slotID: profile.id,
                        boundary: "schedule_release",
                        planToken: plan.token,
                        protection: protection
                    )
                    return
                }
                self.scheduleRelease(for: profile, plan: plan)
                self.enforceRuntimeBudget(reason: "media_protection_ended")
            }
        }
    }

    private func scheduleMediaProtectionRecheck(
        for profile: WebAppProfile,
        plan: InactivePlan
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + mediaProtectionPollDelay) { [weak self] in
            guard let self,
                  self.planMatches(plan, slotID: profile.id),
                  !self.isVisibleSlot(profile.id) else {
                return
            }
            self.evaluateMediaProtection(for: profile, plan: plan)
        }
    }

    private func scheduleRelease(
        for profile: WebAppProfile,
        plan: InactivePlan
    ) {
        guard planMatches(plan, slotID: profile.id) else { return }
        mediaProtectedSlotIDs.remove(profile.id)

        let delay: TimeInterval
        switch profile.residencyPolicy {
        case .hot:
            return
        case .warm:
            delay = warmReleaseDelay
        case .cold:
            delay = coldReleaseDelay
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  self.planMatches(plan, slotID: profile.id),
                  !self.isVisibleSlot(profile.id),
                  self.webViewPool.contains(slotID: profile.id) else {
                return
            }

            guard !self.isProactivelyProtected(slotID: profile.id) else {
                let protection = self.protectionState(slotID: profile.id)
                self.recordProtectionObservations(
                    slotID: profile.id,
                    boundary: "release_timer",
                    planToken: plan.token,
                    protection: protection
                )
                return
            }

            if profile.backgroundMediaPolicy == .allowBackgroundAudio {
                self.mediaProtectionPendingSlotIDs.insert(profile.id)
                self.mediaPlayingQuery(profile.id) { [weak self] isPlaying in
                    guard let self,
                          self.planMatches(plan, slotID: profile.id),
                          !self.isVisibleSlot(profile.id) else {
                        return
                    }
                    self.mediaProtectionPendingSlotIDs.remove(profile.id)
                    guard !self.isProactivelyProtected(slotID: profile.id) else {
                        let protection = self.protectionState(slotID: profile.id)
                        self.recordProtectionObservations(
                            slotID: profile.id,
                            boundary: "release_timer",
                            planToken: plan.token,
                            protection: protection
                        )
                        return
                    }
                    if isPlaying {
                        let wasProtected = self.mediaProtectedSlotIDs.insert(profile.id).inserted
                        if wasProtected {
                            self.diagnostics.record(
                                event: "slot_lifecycle.media_protected",
                                level: .notice,
                                subsystem: "lifecycle",
                                fields: [
                                    "slot_id": .string(profile.id.uuidString),
                                    "inactive_plan_id": .string(plan.token.uuidString)
                                ]
                            )
                        }
                        self.scheduleMediaProtectionRecheck(for: profile, plan: plan)
                    } else {
                        self.releaseInactiveSlot(
                            slotID: profile.id,
                            expectedPlan: plan,
                            releaseReason: "retention_timer"
                        )
                    }
                }
            } else {
                self.releaseInactiveSlot(
                    slotID: profile.id,
                    expectedPlan: plan,
                    releaseReason: "retention_timer"
                )
            }
        }
    }

    private func scheduleHiddenActiveTransition(profile: WebAppProfile) {
        let token = UUID()
        hiddenActiveToken = token
        diagnostics.record(
            event: "slot_lifecycle.hidden_active_grace",
            level: .info,
            subsystem: "lifecycle",
            fields: [
                "slot_id": .string(profile.id.uuidString),
                "state": .string("scheduled")
            ]
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + hiddenActiveGraceDelay) { [weak self] in
            guard let self,
                  self.hiddenActiveToken == token,
                  !self.panelIsVisible,
                  self.activeSlotID == profile.id else {
                return
            }

            guard self.container.window?.isVisible != true else {
                self.hiddenActiveToken = nil
                return
            }

            self.hiddenActiveToken = nil
            self.diagnostics.record(
                event: "slot_lifecycle.hidden_active_grace",
                level: .info,
                subsystem: "lifecycle",
                fields: [
                    "slot_id": .string(profile.id.uuidString),
                    "state": .string("expired")
                ]
            )
            self.activeSlotID = nil
            self.onSlotBecameInactive(profile)
            self.container.deactivate(
                slotID: profile.id,
                residencyPolicy: profile.residencyPolicy
            )
            self.prepareInactive(profile: profile)
            self.enforceRuntimeBudget(reason: "hidden_active_grace_expired")
        }
    }

    private func budgetCandidates() -> [RuntimeBudgetPolicy.Candidate] {
        webViewPool.residentSlotIDs.compactMap { slotID in
            guard let profile = knownProfiles[slotID],
                  profile.residencyPolicy == .warm || profile.residencyPolicy == .cold else {
                return nil
            }

            let hasInactivePlan = inactivePlans[slotID] != nil
            let protected = isVisibleSlot(slotID)
                || isProactivelyProtected(slotID: slotID)
                || !hasInactivePlan
            return RuntimeBudgetPolicy.Candidate(
                slotID: slotID,
                residencyPolicy: profile.residencyPolicy,
                lastUsedAt: profile.lastUsedAt,
                isProtected: protected
            )
        }
    }

    private func budgetDecision(for pressure: SlotMemoryPressureLevel? = nil) -> RuntimeBudgetPolicy.Decision {
        let target = pressure == .critical ? 0 : managedResidentTarget
        return RuntimeBudgetPolicy.decide(
            candidates: budgetCandidates(),
            target: target
        )
    }

    private func enforceRuntimeBudget(
        reason: String,
        pressure: SlotMemoryPressureLevel? = nil,
        incidentContext: RuntimeDiagnosticIncidentContext? = nil
    ) {
        guard !budgetEvaluationInProgress else { return }
        budgetEvaluationInProgress = true
        defer { budgetEvaluationInProgress = false }

        let decision = budgetDecision(for: pressure)
        diagnostics.record(
            event: "slot_lifecycle.runtime_budget",
            level: decision.evictSlotIDs.isEmpty ? .info : .notice,
            subsystem: "lifecycle",
            fields: [
                "reason": .string(reason),
                "target": .integer(Int64(decision.target)),
                "managed_resident_count": .integer(Int64(decision.managedResidentCount)),
                "eviction_count": .integer(Int64(decision.evictSlotIDs.count)),
                "oversubscribed_by": .integer(Int64(decision.oversubscribedBy))
            ]
        )

        let pressureReleaseReason: String?
        switch pressure {
        case .critical:
            pressureReleaseReason = "critical_pressure_eligible"
        case .warning:
            pressureReleaseReason = "warning_pressure_eligible"
        case nil:
            pressureReleaseReason = nil
        }

        for slotID in decision.evictSlotIDs {
            guard let plan = inactivePlans[slotID] else { continue }
            releaseInactiveSlot(
                slotID: slotID,
                expectedPlan: plan,
                memoryPressureIncident: incidentContext,
                releaseReason: pressureReleaseReason ?? reason
            )
        }
    }

    private func recordMemoryPressureEvaluations(
        level: SlotMemoryPressureLevel,
        incidentContext: RuntimeDiagnosticIncidentContext
    ) {
        let decision = budgetDecision(for: level)
        let selected = Set(decision.evictSlotIDs)
        let pressureLevel = level == .critical ? "critical" : "warning"

        for slotID in webViewPool.residentSlotIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            let plan = inactivePlans[slotID]
            let protection = protectionState(slotID: slotID)
            let visible = isVisibleSlot(slotID)
            let policy = knownProfiles[slotID]?.residencyPolicy
                ?? plan?.residencyPolicy
                ?? webViewPool.residencyPolicy(for: slotID)
            let managed = policy == .warm || policy == .cold
            let selectedForRelease = selected.contains(slotID)
            let decisionName: String
            let releaseReason: String
            if level == .warning && !selectedForRelease {
                decisionName = "observe"
                releaseReason = "warning_diagnostics_only"
            } else if selectedForRelease {
                decisionName = "hibernate"
                releaseReason = "runtime_budget"
            } else {
                decisionName = "keep"
                releaseReason = "protected_or_within_target"
            }

            var fields = incidentContext.fields(phase: .trigger)
            fields.merge([
                "slot_id": .string(slotID.uuidString),
                "level": .string(pressureLevel),
                "pressure_level": .string(pressureLevel),
                "residency_policy": .string(policy?.rawValue ?? "unknown"),
                "is_active": .bool(activeSlotID == slotID),
                "is_visible": .bool(visible),
                "pending_release": .bool(plan != nil),
                "pending_release_class": .string(plan?.residencyPolicy.rawValue ?? "none"),
                "media_protected": .bool(protection.media),
                "attention_protected": .bool(protection.attention),
                "managed_runtime": .bool(managed),
                "release_eligible": .bool(selectedForRelease),
                "decision": .string(decisionName),
                "release_reason": .string(releaseReason),
                "budget_target": .integer(Int64(decision.target)),
                "web_process_resource_attribution": .string("unavailable_public_api")
            ]) { _, new in new }
            diagnostics.record(
                event: "slot_lifecycle.memory_pressure_slot",
                level: selectedForRelease ? .notice : .info,
                subsystem: "lifecycle",
                fields: fields
            )
        }
    }

    private func releaseInactiveSlot(
        slotID: UUID,
        expectedPlan: InactivePlan? = nil,
        memoryPressureIncident: RuntimeDiagnosticIncidentContext? = nil,
        releaseReason: String = "inactive_release"
    ) {
        guard let currentPlan = inactivePlans[slotID],
              expectedPlan.map({ $0.token == currentPlan.token }) ?? true,
              !isVisibleSlot(slotID) else {
            return
        }
        guard !isProactivelyProtected(slotID: slotID) else {
            let protection = protectionState(slotID: slotID)
            recordProtectionObservations(
                slotID: slotID,
                boundary: "final_release",
                planToken: currentPlan.token,
                protection: protection
            )
            return
        }
        guard webViewPool.contains(slotID: slotID) else {
            return
        }
        diagnostics.record(
            event: "slot_lifecycle.hibernate",
            level: .notice,
            subsystem: "lifecycle",
            fields: [
                "slot_id": .string(slotID.uuidString),
                "inactive_plan_id": .string(currentPlan.token.uuidString),
                "release_reason": .string(releaseReason)
            ]
        )
        prepareRuntimeForRelease(slotID)
        container.removeSlot(slotID)
        webViewPool.hibernate(slotID: slotID)
        cancelInactivePlan(slotID: slotID)
        onRuntimeReleased(currentPlan.profile)
        if let memoryPressureIncident {
            var fields = memoryPressureIncident.fields(phase: .recovery)
            fields.merge([
                "slot_id": .string(slotID.uuidString),
                "pressure_level": .string(memoryPressureIncident.trigger),
                "release_eligible": .bool(true),
                "decision": .string("hibernate"),
                "action": .string("hibernate_completed"),
                "release_reason": .string(releaseReason)
            ]) { _, new in new }
            diagnostics.record(
                event: "slot_lifecycle.memory_pressure_slot",
                level: .notice,
                subsystem: "lifecycle",
                fields: fields
            )
        }
    }

    private func cancelInactivePlan(
        slotID: UUID,
        preservingMediaProtection: Bool = false
    ) {
        if let plan = inactivePlans.removeValue(forKey: slotID) {
            diagnostics.record(
                event: "slot_lifecycle.inactive_plan.cancelled",
                level: .info,
                subsystem: "lifecycle",
                fields: [
                    "slot_id": .string(slotID.uuidString),
                    "inactive_plan_id": .string(plan.token.uuidString)
                ]
            )
        }
        mediaProtectionPendingSlotIDs.remove(slotID)
        if !preservingMediaProtection {
            mediaProtectedSlotIDs.remove(slotID)
        }
    }

    private func planMatches(_ plan: InactivePlan, slotID: UUID) -> Bool {
        inactivePlans[slotID]?.token == plan.token
    }

    private func isVisibleSlot(_ slotID: UUID) -> Bool {
        activeSlotID == slotID
            || fullscreenSourceProfile?.id == slotID
            || supplementalVisibleProfile?.id == slotID
    }

    private func isProactivelyProtected(slotID: UUID) -> Bool {
        mediaProtectedSlotIDs.contains(slotID)
            || mediaProtectionPendingSlotIDs.contains(slotID)
            || attentionProtectionQuery(slotID)
    }

    private func protectionState(slotID: UUID) -> ProtectionState {
        ProtectionState(
            media: mediaProtectedSlotIDs.contains(slotID)
                || mediaProtectionPendingSlotIDs.contains(slotID),
            attention: attentionProtectionQuery(slotID)
        )
    }

    private func recordProtectionObservations(
        slotID: UUID,
        boundary: String,
        planToken: UUID?,
        protection: ProtectionState
    ) {
        var fields: [String: RuntimeDiagnosticValue] = [
            "slot_id": .string(slotID.uuidString),
            "boundary": .string(boundary)
        ]
        if let planToken {
            fields["inactive_plan_id"] = .string(planToken.uuidString)
        }

        if protection.attention {
            diagnostics.record(
                event: "slot_lifecycle.attention_protected",
                level: .info,
                subsystem: "lifecycle",
                fields: fields
            )
        }
    }

    private static func diagnosticInteger(_ value: UInt64) -> RuntimeDiagnosticValue {
        .integer(value > UInt64(Int64.max) ? Int64.max : Int64(value))
    }

    private static func currentProcessResidentSizeBytes() -> UInt64? {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.resident_size)
    }
}
