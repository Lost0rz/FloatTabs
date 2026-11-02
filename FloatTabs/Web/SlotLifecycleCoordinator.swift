import AppKit
import Dispatch
import Darwin
import Foundation

enum SlotMemoryPressureLevel {
    case warning
    case critical
}

private struct RuntimeBudgetPolicy {
    static let defaultManagedResidentTarget = 2

    struct Candidate {
        let slotID: UUID
        let retentionPreference: SlotRuntimeRetentionPreference
        let lastUsedAt: Date
        let isProtected: Bool
    }

    struct Decision {
        let target: Int
        let managedResidentCount: Int
        let evictSlotIDs: [UUID]
        let oversubscribedBy: Int
    }

    /// Normal (healthy-state) budget decision. This path is intentionally
    /// count-based and does not participate in memory-pressure reclaim;
    /// pressure uses `pressureCandidate(candidates:level:)` instead.
    static func decide(
        candidates: [Candidate],
        target: Int
    ) -> Decision {
        let normalizedTarget = max(target, 0)
        let automatic = candidates.filter { $0.retentionPreference == .automatic }
        let eligibleAutomatic = automatic
            .filter { !$0.isProtected }
            .sorted(by: evictionOrder)
        let requiredAutomaticEvictions = max(automatic.count - normalizedTarget, 0)
        let evictSlotIDs = Array(
            eligibleAutomatic.prefix(requiredAutomaticEvictions).map(\.slotID)
        )

        let selectedAutomaticCount = evictSlotIDs.reduce(into: 0) { count, slotID in
            if automatic.contains(where: { $0.slotID == slotID }) { count += 1 }
        }
        let remainingAutomatic = automatic.count - selectedAutomaticCount
        return Decision(
            target: normalizedTarget,
            managedResidentCount: automatic.count,
            evictSlotIDs: evictSlotIDs,
            oversubscribedBy: max(remainingAutomatic - normalizedTarget, 0)
        )
    }

    /// Progressive pressure reclaim selects at most one candidate per step.
    ///
    /// Warning: only eligible Automatic Runtime is a candidate.
    /// Critical: eligible Automatic first; only when no eligible Automatic
    /// remains may an inactive/unprotected Keep Loaded Runtime be selected.
    /// Active/hard-protected Runtime is never a candidate (`isProtected`).
    static func pressureCandidate(
        candidates: [Candidate],
        level: SlotMemoryPressureLevel
    ) -> Candidate? {
        let eligible = candidates
            .filter { !$0.isProtected }
            .sorted(by: evictionOrder)
        let eligibleAutomatic = eligible.filter { $0.retentionPreference == .automatic }
        if let oldest = eligibleAutomatic.first {
            return oldest
        }
        guard level == .critical else { return nil }
        return eligible
            .filter { $0.retentionPreference == .keepLoaded }
            .first
    }

    private static func evictionOrder(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.lastUsedAt != rhs.lastUsedAt {
            return lhs.lastUsedAt < rhs.lastUsedAt
        }
        return lhs.slotID.uuidString < rhs.slotID.uuidString
    }
}

@MainActor
final class SlotLifecycleCoordinator {
    // Compatibility constants remain for older tests/callers; current
    // product policy uses one Automatic inactivity grace.
    nonisolated static let defaultColdReleaseDelay: TimeInterval = 30
    nonisolated static let defaultWarmReleaseDelay: TimeInterval = 120
    nonisolated static let defaultAutomaticReleaseDelay: TimeInterval = 30
    nonisolated static let defaultHiddenActiveGraceDelay: TimeInterval = 0
    nonisolated static let defaultMediaProtectionPollDelay: TimeInterval = 10
    nonisolated static let defaultManagedResidentTarget = RuntimeBudgetPolicy.defaultManagedResidentTarget
    /// Delay between progressive pressure-reclaim steps. Each continuation
    /// revalidates the latest pressure state and current Runtime ownership
    /// before reclaiming anything else.
    nonisolated static let defaultPressureStepDelay: TimeInterval = 0.5

    typealias MediaPlayingQuery = (UUID, @escaping (Bool) -> Void) -> Void
    typealias MediaPauseAction = (UUID) -> Void
    typealias RuntimeReleasedHandler = @MainActor (WebAppProfile) -> Void
    typealias RuntimeReleasePreparation = @MainActor (UUID) -> Void
    typealias SlotBecameInactiveHandler = @MainActor (WebAppProfile) -> Void
    typealias AttentionProtectionQuery = @MainActor (UUID) -> Bool

    private struct InactivePlan {
        let token: UUID
        let profile: WebAppProfile
        let retentionPreference: SlotRuntimeRetentionPreference
        let backgroundMediaPolicy: BackgroundMediaPolicy
    }

    private struct ProtectionState {
        let media: Bool
        let attention: Bool
    }

    private let webViewPool: WebViewPool
    private unowned let container: WebPanelContainerView
    private var automaticReleaseDelay: TimeInterval
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
    private let pressureStepDelay: TimeInterval
    /// Latest observed system memory-pressure level; `nil` means normal.
    private var latestMemoryPressureLevel: SlotMemoryPressureLevel?
    /// Pending progressive pressure-reclaim continuation. At most one is
    /// ever scheduled; it is cancelled when pressure returns to normal.
    private var pressureReclaimWorkItem: DispatchWorkItem?

    init(
        webViewPool: WebViewPool,
        container: WebPanelContainerView,
        coldReleaseDelay: TimeInterval = SlotLifecycleCoordinator.defaultColdReleaseDelay,
        warmReleaseDelay: TimeInterval = SlotLifecycleCoordinator.defaultWarmReleaseDelay,
        hiddenActiveGraceDelay: TimeInterval = SlotLifecycleCoordinator.defaultHiddenActiveGraceDelay,
        mediaProtectionPollDelay: TimeInterval = SlotLifecycleCoordinator.defaultMediaProtectionPollDelay,
        managedResidentTarget: Int = SlotLifecycleCoordinator.defaultManagedResidentTarget,
        pressureStepDelay: TimeInterval = SlotLifecycleCoordinator.defaultPressureStepDelay,
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
        // Legacy constructor knobs are retained only as a deterministic
        // test/rollback seam. Production no longer reads the user Warm/Cold
        // settings; the smaller value maps to the single Automatic grace.
        automaticReleaseDelay = max(min(coldReleaseDelay, warmReleaseDelay), 0)
        self.hiddenActiveGraceDelay = max(hiddenActiveGraceDelay, 0)
        self.mediaProtectionPollDelay = max(mediaProtectionPollDelay, 0.01)
        self.managedResidentTarget = max(managedResidentTarget, 0)
        self.pressureStepDelay = max(pressureStepDelay, 0)
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

    /// Compatibility seam for older tests. Production no longer observes
    /// Warm/Cold settings; both values collapse to one Automatic grace.
    func updateReleaseDelays(
        coldReleaseDelay: TimeInterval,
        warmReleaseDelay: TimeInterval
    ) {
        let normalized = max(min(coldReleaseDelay, warmReleaseDelay), 0)
        guard normalized != automaticReleaseDelay else { return }
        automaticReleaseDelay = normalized

        let profiles = inactivePlans.values.map(\.profile)
        for profile in profiles where
            profile.runtimeRetentionPreference == .automatic
                && webViewPool.contains(slotID: profile.id)
                && !isVisibleSlot(profile.id) {
            let preserveMediaProtection = mediaProtectedSlotIDs.contains(profile.id)
            cancelInactivePlan(
                slotID: profile.id,
                preservingMediaProtection: preserveMediaProtection
            )
            createInactivePlan(for: profile)
        }
        enforceRuntimeBudget(reason: "automatic_grace_changed")
    }

    func reconcile(profiles: [WebAppProfile]) {
        knownProfiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        let validIDs = Set(profiles.map(\.id))

        if let activeSlotID, !validIDs.contains(activeSlotID) {
            self.activeSlotID = nil
        }

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
            ensureInactivePlan(for: profile)
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
              existingPlan.retentionPreference == profile.runtimeRetentionPreference,
              existingPlan.backgroundMediaPolicy == profile.backgroundMediaPolicy,
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
        let previousLevel = latestMemoryPressureLevel
        latestMemoryPressureLevel = level
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

        if previousLevel != level {
            // A changed pressure level (escalation/de-escalation) takes
            // effect immediately and replaces any pending continuation.
            pressureReclaimWorkItem?.cancel()
            pressureReclaimWorkItem = nil
            beginProgressivePressureReclaim(
                level: level,
                incidentContext: incidentContext
            )
        } else if pressureReclaimWorkItem == nil {
            // Same level while no continuation is pending (progression
            // previously stopped at the no-candidate boundary): re-evaluate
            // against fresh facts without stacking a second transaction.
            beginProgressivePressureReclaim(level: level)
        }

        var completionFields = incidentContext.fields(phase: .closure)
        completionFields["incident_outcome"] = .string("evaluation_complete")
        diagnostics.record(
            event: "slot_lifecycle.memory_pressure.completed",
            level: .notice,
            subsystem: "lifecycle",
            fields: completionFields
        )
    }

    /// Pressure returned to normal: stop any not-yet-started progressive
    /// continuation. Reclaimed Runtime is not restored; future restore stays
    /// demand-driven by existing Slot selection/materialization.
    func handleMemoryPressureNormalized() {
        latestMemoryPressureLevel = nil
        let hadPendingContinuation = pressureReclaimWorkItem != nil
        pressureReclaimWorkItem?.cancel()
        pressureReclaimWorkItem = nil
        diagnostics.record(
            event: "slot_lifecycle.memory_pressure.normal",
            level: .notice,
            subsystem: "lifecycle",
            fields: [
                "cancelled_pending_continuation": .bool(hadPendingContinuation)
            ]
        )
    }

    /// Legacy debug counters retained for old fixtures. Automatic plans
    /// are projected as Warm; Cold no longer exists as a current policy.
    var pendingColdReleaseCount: Int { 0 }

    var pendingWarmReleaseCount: Int {
        inactivePlans.values.filter { $0.retentionPreference == .automatic }.count
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
            "lifecycle_pending_release_class": .string(plan?.retentionPreference.rawValue ?? "none"),
            "lifecycle_runtime_retention": .string(
                knownProfiles[slotID]?.runtimeRetentionPreference.rawValue ?? "unknown"
            ),
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
            eventMask: [.normal, .warning, .critical],
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
            } else if data.contains(.normal) {
                self.handleMemoryPressureNormalized()
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
        ensureInactivePlan(for: profile)
    }

    private func ensureInactivePlan(for profile: WebAppProfile) {
        if let existing = inactivePlans[profile.id],
           existing.retentionPreference == profile.runtimeRetentionPreference,
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
            retentionPreference: profile.runtimeRetentionPreference,
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
                "runtime_retention": .string(profile.runtimeRetentionPreference.rawValue)
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
        guard planMatches(plan, slotID: profile.id),
              profile.runtimeRetentionPreference == .automatic else { return }
        mediaProtectedSlotIDs.remove(profile.id)
        let delay = automaticReleaseDelay

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
                    boundary: "automatic_grace",
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
                          !self.isVisibleSlot(profile.id) else { return }
                    self.mediaProtectionPendingSlotIDs.remove(profile.id)
                    guard !self.isProactivelyProtected(slotID: profile.id) else { return }
                    if isPlaying {
                        self.mediaProtectedSlotIDs.insert(profile.id)
                        self.scheduleMediaProtectionRecheck(for: profile, plan: plan)
                    } else {
                        self.releaseInactiveSlot(
                            slotID: profile.id,
                            expectedPlan: plan,
                            releaseReason: "automatic_grace_expired"
                        )
                    }
                }
            } else {
                self.releaseInactiveSlot(
                    slotID: profile.id,
                    expectedPlan: plan,
                    releaseReason: "automatic_grace_expired"
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
            guard let profile = knownProfiles[slotID] else { return nil }
            let hasInactivePlan = inactivePlans[slotID] != nil
            let protected = isVisibleSlot(slotID)
                || isProactivelyProtected(slotID: slotID)
                || !hasInactivePlan
            return RuntimeBudgetPolicy.Candidate(
                slotID: slotID,
                retentionPreference: profile.runtimeRetentionPreference,
                lastUsedAt: profile.lastUsedAt,
                isProtected: protected
            )
        }
    }

    private func budgetDecision() -> RuntimeBudgetPolicy.Decision {
        RuntimeBudgetPolicy.decide(
            candidates: budgetCandidates(),
            target: managedResidentTarget
        )
    }

    /// Progressive memory-pressure reclaim: at most one Runtime is reclaimed
    /// per step, and every step revalidates the latest pressure state plus
    /// current Runtime identity/protection through fresh candidate facts.
    /// A continuation is scheduled only while the latest observed pressure
    /// remains warning/critical; a single stale event never causes a
    /// precomputed multi-Runtime purge.
    private func beginProgressivePressureReclaim(
        level: SlotMemoryPressureLevel,
        incidentContext: RuntimeDiagnosticIncidentContext? = nil
    ) {
        guard pressureReclaimWorkItem == nil else { return }
        let candidate = RuntimeBudgetPolicy.pressureCandidate(
            candidates: budgetCandidates(),
            level: level
        )
        guard let candidate,
              let plan = inactivePlans[candidate.slotID] else {
            diagnostics.record(
                event: "slot_lifecycle.memory_pressure.no_candidate",
                level: .info,
                subsystem: "lifecycle",
                fields: [
                    "level": .string(level == .critical ? "critical" : "warning")
                ]
            )
            return
        }

        releaseInactiveSlot(
            slotID: candidate.slotID,
            expectedPlan: plan,
            memoryPressureIncident: incidentContext,
            releaseReason: level == .critical
                ? "critical_pressure_eligible"
                : "warning_pressure_eligible"
        )

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pressureReclaimWorkItem = nil
            guard let latestLevel = self.latestMemoryPressureLevel else { return }
            self.beginProgressivePressureReclaim(level: latestLevel)
        }
        pressureReclaimWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + pressureStepDelay,
            execute: workItem
        )
    }

    private func enforceRuntimeBudget(reason: String) {
        guard !budgetEvaluationInProgress else { return }
        budgetEvaluationInProgress = true
        defer { budgetEvaluationInProgress = false }

        let decision = budgetDecision()
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

        for slotID in decision.evictSlotIDs {
            guard let plan = inactivePlans[slotID] else { continue }
            releaseInactiveSlot(
                slotID: slotID,
                expectedPlan: plan,
                releaseReason: reason
            )
        }
    }

    private func recordMemoryPressureEvaluations(
        level: SlotMemoryPressureLevel,
        incidentContext: RuntimeDiagnosticIncidentContext
    ) {
        let selected = RuntimeBudgetPolicy.pressureCandidate(
            candidates: budgetCandidates(),
            level: level
        )?.slotID
        let pressureLevel = level == .critical ? "critical" : "warning"

        for slotID in webViewPool.residentSlotIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            let plan = inactivePlans[slotID]
            let protection = protectionState(slotID: slotID)
            let visible = isVisibleSlot(slotID)
            let preference = knownProfiles[slotID]?.runtimeRetentionPreference
                ?? plan?.retentionPreference
                ?? webViewPool.runtimeRetentionPreference(for: slotID)
            let managed = preference == .automatic
            let selectedForRelease = selected == slotID
            let decisionName: String
            let releaseReason: String
            if selectedForRelease {
                decisionName = "hibernate"
                releaseReason = level == .critical
                    ? "critical_pressure_eligible"
                    : "warning_pressure_eligible"
            } else if level == .warning {
                decisionName = "observe"
                releaseReason = "warning_diagnostics_only"
            } else if plan != nil
                && !visible
                && !protection.media
                && !protection.attention {
                decisionName = "observe"
                releaseReason = "critical_pending_progression"
            } else {
                decisionName = "keep"
                releaseReason = "protected_or_ineligible"
            }

            var fields = incidentContext.fields(phase: .trigger)
            fields.merge([
                "slot_id": .string(slotID.uuidString),
                "level": .string(pressureLevel),
                "pressure_level": .string(pressureLevel),
                "runtime_retention_preference": .string(preference?.rawValue ?? "unknown"),
                "is_active": .bool(activeSlotID == slotID),
                "is_visible": .bool(visible),
                "pending_release": .bool(plan != nil),
                "pending_release_class": .string(plan?.retentionPreference.rawValue ?? "none"),
                "media_protected": .bool(protection.media),
                "attention_protected": .bool(protection.attention),
                "managed_runtime": .bool(managed),
                "release_eligible": .bool(selectedForRelease),
                "decision": .string(decisionName),
                "release_reason": .string(releaseReason),
                "budget_target": .integer(Int64(managedResidentTarget)),
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
