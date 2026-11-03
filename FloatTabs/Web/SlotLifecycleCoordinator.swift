import AppKit
import Dispatch
import Darwin
import Foundation

enum SlotMemoryPressureLevel {
    case warning
    case critical
}

enum AutomaticLifecycleStage: String, Equatable {
    case recent
    case idle
    case longIdle = "long_idle"

    static func resolve(
        inactiveDuration: TimeInterval,
        recentStageDuration: TimeInterval,
        longIdleThreshold: TimeInterval
    ) -> AutomaticLifecycleStage {
        let age = max(inactiveDuration, 0)
        let recentBoundary = max(recentStageDuration, 0)
        let longIdleBoundary = max(longIdleThreshold, recentBoundary)
        if age < recentBoundary { return .recent }
        if age < longIdleBoundary { return .idle }
        return .longIdle
    }
}

private struct RuntimePressurePolicy {
    struct Candidate {
        let slotID: UUID
        let retentionPreference: SlotRuntimeRetentionPreference
        let inactiveSinceUptime: TimeInterval
        let stage: AutomaticLifecycleStage?
        let isProtected: Bool
    }

    /// Progressive pressure reclaim selects at most one candidate per step.
    ///
    /// Warning: only IDLE/LONG_IDLE Automatic Runtime is eligible.
    /// Critical: inactive Automatic Runtime at any stage is eligible.
    /// Keep Loaded and hard-protected Runtime are never candidates.
    static func pressureCandidate(
        candidates: [Candidate],
        level: SlotMemoryPressureLevel
    ) -> Candidate? {
        candidates
            .filter { candidate in
                guard candidate.retentionPreference == .automatic,
                      !candidate.isProtected,
                      let stage = candidate.stage else { return false }
                return level == .critical || stage != .recent
            }
            .sorted(by: evictionOrder)
            .first
    }

    private static func evictionOrder(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.inactiveSinceUptime != rhs.inactiveSinceUptime {
            return lhs.inactiveSinceUptime < rhs.inactiveSinceUptime
        }
        return lhs.slotID.uuidString < rhs.slotID.uuidString
    }
}

@MainActor
final class SlotLifecycleCoordinator {
    nonisolated static let defaultRecentStageDuration: TimeInterval = 30
    nonisolated static let defaultLongIdleThreshold: TimeInterval = 600
    nonisolated static let defaultHiddenActiveGraceDelay: TimeInterval = 0
    nonisolated static let defaultMediaProtectionPollDelay: TimeInterval = 10
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
    typealias MonotonicUptimeProvider = @MainActor () -> TimeInterval
    typealias DelayedWorkScheduler = @MainActor (TimeInterval, DispatchWorkItem) -> Void

    private struct InactivePlan {
        let token: UUID
        let profile: WebAppProfile
        let retentionPreference: SlotRuntimeRetentionPreference
        let backgroundMediaPolicy: BackgroundMediaPolicy
        let inactiveSinceUptime: TimeInterval
        let runtimeObjectID: ObjectIdentifier
        var stage: AutomaticLifecycleStage?
    }

    private struct ProtectionState {
        let media: Bool
        let attention: Bool
    }

    private let webViewPool: WebViewPool
    private unowned let container: WebPanelContainerView
    private let recentStageDuration: TimeInterval
    private let longIdleThreshold: TimeInterval
    private let hiddenActiveGraceDelay: TimeInterval
    private let mediaProtectionPollDelay: TimeInterval
    private let mediaPlayingQuery: MediaPlayingQuery
    private let mediaPauseAction: MediaPauseAction
    private let monotonicUptime: MonotonicUptimeProvider
    private let scheduleDelayedWork: DelayedWorkScheduler
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
    private let pressureStepDelay: TimeInterval
    /// Latest observed system memory-pressure level; `nil` means normal.
    private var latestMemoryPressureLevel: SlotMemoryPressureLevel?
    /// Pending progressive pressure-reclaim continuation. At most one is
    /// ever scheduled; it is cancelled when pressure returns to normal.
    private var pressureReclaimWorkItem: DispatchWorkItem?
    private var pressureReclaimEvaluationToken: UUID?

    init(
        webViewPool: WebViewPool,
        container: WebPanelContainerView,
        recentStageDuration: TimeInterval = SlotLifecycleCoordinator.defaultRecentStageDuration,
        longIdleThreshold: TimeInterval = SlotLifecycleCoordinator.defaultLongIdleThreshold,
        hiddenActiveGraceDelay: TimeInterval = SlotLifecycleCoordinator.defaultHiddenActiveGraceDelay,
        mediaProtectionPollDelay: TimeInterval = SlotLifecycleCoordinator.defaultMediaProtectionPollDelay,
        pressureStepDelay: TimeInterval = SlotLifecycleCoordinator.defaultPressureStepDelay,
        monotonicUptime: @escaping MonotonicUptimeProvider = { ProcessInfo.processInfo.systemUptime },
        scheduleDelayedWork: DelayedWorkScheduler? = nil,
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
        self.recentStageDuration = max(recentStageDuration, 0)
        self.longIdleThreshold = max(longIdleThreshold, self.recentStageDuration)
        self.hiddenActiveGraceDelay = max(hiddenActiveGraceDelay, 0)
        self.mediaProtectionPollDelay = max(mediaProtectionPollDelay, 0.01)
        self.pressureStepDelay = max(pressureStepDelay, 0)
        self.monotonicUptime = monotonicUptime
        self.scheduleDelayedWork = scheduleDelayedWork ?? { delay, workItem in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
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
        reconcileProgressivePressureIfNeeded()
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
        guard planMatches(existingPlan, slotID: slotID) else {
            cancelInactivePlan(slotID: slotID)
            prepareInactive(profile: profile)
            return
        }

        let inactiveSinceUptime = existingPlan.inactiveSinceUptime
        cancelInactivePlan(slotID: slotID)
        createInactivePlan(for: profile, inactiveSinceUptime: inactiveSinceUptime)
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
        if !isVisibleSlot(profile.id), webViewPool.contains(slotID: profile.id) {
            prepareInactive(profile: profile)
        }
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
            return
        }
        onSlotBecameInactive(profile)
        prepareInactive(profile: profile)
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
            startedAtUptime: monotonicUptime()
        )
        let previousLevel = latestMemoryPressureLevel
        latestMemoryPressureLevel = level
        refreshInactiveStagesForPressureEvaluation()
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
            pressureReclaimEvaluationToken = nil
            beginProgressivePressureReclaim(
                level: level,
                incidentContext: incidentContext
            )
        } else {
            // Same level: idempotently reconsider against fresh facts
            // without stacking a second transaction.
            reconcileProgressivePressureIfNeeded()
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
            || pressureReclaimEvaluationToken != nil
        pressureReclaimWorkItem?.cancel()
        pressureReclaimWorkItem = nil
        pressureReclaimEvaluationToken = nil
        diagnostics.record(
            event: "slot_lifecycle.memory_pressure.normal",
            level: .notice,
            subsystem: "lifecycle",
            fields: [
                "cancelled_pending_continuation": .bool(hadPendingContinuation)
            ]
        )
    }

    /// Legacy debug counter retained for callers that still use the old name.
    var pendingColdReleaseCount: Int { 0 }

    /// Legacy debug counter retained for callers that still use the old name.
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
            "lifecycle_automatic_stage": .string(
                plan?.stage?.rawValue ?? "none"
            )
        ]
    }

    #if DEBUG
    func debugInactivePlanToken(slotID: UUID) -> UUID? {
        inactivePlans[slotID]?.token
    }

    func debugInactiveStage(slotID: UUID) -> AutomaticLifecycleStage? {
        inactivePlans[slotID]?.stage
    }

    func debugInactiveSinceUptime(slotID: UUID) -> TimeInterval? {
        inactivePlans[slotID]?.inactiveSinceUptime
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
        guard profile.runtimeRetentionPreference == .automatic else {
            cancelInactivePlan(slotID: profile.id)
            return
        }
        if let existing = inactivePlans[profile.id],
           existing.retentionPreference == profile.runtimeRetentionPreference,
           existing.backgroundMediaPolicy == profile.backgroundMediaPolicy,
           existing.profile.browserProfileID == profile.browserProfileID,
           webViewPool.existingWebView(for: profile.id).map(ObjectIdentifier.init)
                == existing.runtimeObjectID {
            return
        }

        cancelInactivePlan(slotID: profile.id)
        createInactivePlan(for: profile)
    }

    private func createInactivePlan(
        for profile: WebAppProfile,
        inactiveSinceUptime: TimeInterval? = nil,
        mediaFactAlreadyChecked: Bool = false
    ) {
        guard profile.runtimeRetentionPreference == .automatic else {
            cancelInactivePlan(slotID: profile.id)
            return
        }
        guard let webView = webViewPool.existingWebView(for: profile.id) else {
            cancelInactivePlan(slotID: profile.id)
            return
        }
        let runtimeObjectID = ObjectIdentifier(webView)
        let inactiveSince = inactiveSinceUptime ?? monotonicUptime()
        let initialStage = profile.runtimeRetentionPreference == .automatic
            ? stage(forInactiveSince: inactiveSince)
            : nil
        let plan = InactivePlan(
            token: UUID(),
            profile: profile,
            retentionPreference: profile.runtimeRetentionPreference,
            backgroundMediaPolicy: profile.backgroundMediaPolicy,
            inactiveSinceUptime: inactiveSince,
            runtimeObjectID: runtimeObjectID,
            stage: initialStage
        )
        inactivePlans[profile.id] = plan
        diagnostics.record(
            event: "slot_lifecycle.inactive_plan.created",
            level: .info,
            subsystem: "lifecycle",
            fields: [
                "slot_id": .string(profile.id.uuidString),
                "inactive_plan_id": .string(plan.token.uuidString),
                "runtime_retention": .string(profile.runtimeRetentionPreference.rawValue),
                "automatic_stage": .string(plan.stage?.rawValue ?? "none")
            ]
        )

        scheduleNextStageBoundary(for: profile, plan: plan)
        if profile.backgroundMediaPolicy == .allowBackgroundAudio && !mediaFactAlreadyChecked {
            mediaProtectionPendingSlotIDs.insert(profile.id)
            evaluateMediaProtection(for: profile, plan: plan)
        } else if plan.stage == .longIdle {
            applyLongIdlePolicy(for: profile, plan: plan)
        }
        // A newly created inactive plan is the primary eligibility-increasing
        // boundary; under sustained warning/critical pressure the ladder
        // reconsiders it immediately instead of waiting for another event.
        reconcileProgressivePressureIfNeeded()
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
                let wasProtected = self.mediaProtectedSlotIDs.remove(profile.id) != nil
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
                if wasProtected {
                    self.cancelInactivePlan(slotID: profile.id)
                    self.createInactivePlan(
                        for: profile,
                        inactiveSinceUptime: plan.inactiveSinceUptime,
                        mediaFactAlreadyChecked: true
                    )
                    return
                }
                if plan.stage == .longIdle {
                    self.applyLongIdlePolicy(for: profile, plan: plan)
                }
                // Media protection ending restores pressure eligibility for
                // this Runtime; the ladder may resume under sustained pressure.
                self.reconcileProgressivePressureIfNeeded()
            }
        }
    }

    private func scheduleMediaProtectionRecheck(
        for profile: WebAppProfile,
        plan: InactivePlan
    ) {
        scheduleDelayedWork(mediaProtectionPollDelay, DispatchWorkItem { [weak self] in
            guard let self,
                  self.planMatches(plan, slotID: profile.id),
                  !self.isVisibleSlot(profile.id) else {
                return
            }
            self.evaluateMediaProtection(for: profile, plan: plan)
        })
    }

    private func scheduleNextStageBoundary(
        for profile: WebAppProfile,
        plan: InactivePlan
    ) {
        guard plan.retentionPreference == .automatic,
              planMatches(plan, slotID: profile.id),
              let stage = plan.stage else { return }
        let nextBoundary: TimeInterval
        switch stage {
        case .recent:
            nextBoundary = recentStageDuration
        case .idle:
            nextBoundary = longIdleThreshold
        case .longIdle:
            return
        }
        let elapsed = max(monotonicUptime() - plan.inactiveSinceUptime, 0)
        let delay = max(nextBoundary - elapsed, 0)

        scheduleDelayedWork(delay, DispatchWorkItem { [weak self] in
            guard let self,
                  self.planMatches(plan, slotID: profile.id),
                  !self.isVisibleSlot(profile.id),
                  self.webViewPool.contains(slotID: profile.id) else {
                return
            }
            self.advanceInactiveStage(
                for: profile,
                expectedPlan: plan,
                refreshPressureEligibility: true
            )
        })
    }

    private func advanceInactiveStage(
        for profile: WebAppProfile,
        expectedPlan: InactivePlan,
        refreshPressureEligibility: Bool
    ) {
        guard planMatches(expectedPlan, slotID: profile.id),
              !isVisibleSlot(profile.id),
              webViewPool.contains(slotID: profile.id),
              var currentPlan = inactivePlans[profile.id] else { return }
        let nextStage = stage(forInactiveSince: currentPlan.inactiveSinceUptime)
        if currentPlan.stage != nextStage {
            let previousStage = currentPlan.stage
            currentPlan.stage = nextStage
            inactivePlans[profile.id] = currentPlan
            diagnostics.record(
                event: "slot_lifecycle.automatic_stage_transition",
                level: .info,
                subsystem: "lifecycle",
                fields: [
                    "slot_id": .string(profile.id.uuidString),
                    "inactive_plan_id": .string(currentPlan.token.uuidString),
                    "from_stage": .string(previousStage?.rawValue ?? "none"),
                    "to_stage": .string(nextStage.rawValue)
                ]
            )
        }

        if currentPlan.stage == .longIdle {
            applyLongIdlePolicy(for: profile, plan: currentPlan)
        } else {
            scheduleNextStageBoundary(for: profile, plan: currentPlan)
        }
        if refreshPressureEligibility {
            reconcileProgressivePressureIfNeeded()
        }
    }

    private func applyLongIdlePolicy(for profile: WebAppProfile, plan: InactivePlan) {
        guard planMatches(plan, slotID: profile.id),
              plan.retentionPreference == .automatic,
              plan.stage == .longIdle,
              latestMemoryPressureLevel == nil,
              !isVisibleSlot(profile.id) else {
            return
        }
        guard !isProactivelyProtected(slotID: profile.id) else {
            recordProtectionObservations(
                slotID: profile.id,
                boundary: "automatic_long_idle",
                planToken: plan.token,
                protection: protectionState(slotID: profile.id)
            )
            return
        }
        if plan.backgroundMediaPolicy == .allowBackgroundAudio {
            queryMediaBeforeNormalLongIdleRelease(for: profile, plan: plan)
        } else {
            releaseInactiveSlot(
                slotID: profile.id,
                expectedPlan: plan,
                releaseReason: "automatic_long_idle_expired"
            )
        }
    }

    private func queryMediaBeforeNormalLongIdleRelease(
        for profile: WebAppProfile,
        plan: InactivePlan
    ) {
        mediaProtectionPendingSlotIDs.insert(profile.id)
        mediaPlayingQuery(profile.id) { [weak self] isPlaying in
            guard let self,
                  self.planMatches(plan, slotID: profile.id),
                  !self.isVisibleSlot(profile.id) else { return }
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
                guard !self.isProactivelyProtected(slotID: profile.id),
                      self.latestMemoryPressureLevel == nil,
                      self.stage(forInactiveSince: plan.inactiveSinceUptime) == .longIdle else {
                    return
                }
                if self.planMatches(plan, slotID: profile.id) {
                    self.releaseInactiveSlot(
                        slotID: profile.id,
                        expectedPlan: plan,
                        releaseReason: "automatic_long_idle_expired"
                    )
                }
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

        scheduleDelayedWork(hiddenActiveGraceDelay, DispatchWorkItem { [weak self] in
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
            self.reconcileProgressivePressureIfNeeded()
        })
    }

    private func pressureCandidates() -> [RuntimePressurePolicy.Candidate] {
        webViewPool.residentSlotIDs.compactMap { slotID in
            guard let plan = inactivePlans[slotID],
                  planMatches(plan, slotID: slotID) else { return nil }
            return makePressureCandidate(slotID: slotID, plan: plan)
        }
    }

    private func makePressureCandidate(
        slotID: UUID,
        plan: InactivePlan
    ) -> RuntimePressurePolicy.Candidate {
        RuntimePressurePolicy.Candidate(
            slotID: slotID,
            retentionPreference: plan.retentionPreference,
            inactiveSinceUptime: plan.inactiveSinceUptime,
            stage: plan.retentionPreference == .automatic
                ? stage(forInactiveSince: plan.inactiveSinceUptime)
                : nil,
            isProtected: isVisibleSlot(slotID)
                || isProactivelyProtected(slotID: slotID)
                || !planMatches(plan, slotID: slotID)
        )
    }

    private func isPressureEligible(plan: InactivePlan, level: SlotMemoryPressureLevel) -> Bool {
        guard plan.retentionPreference == .automatic,
              planMatches(plan, slotID: plan.profile.id),
              let candidate = inactivePlans[plan.profile.id].map({
                  makePressureCandidate(slotID: plan.profile.id, plan: $0)
              }),
              candidate.stage != nil,
              !candidate.isProtected else { return false }
        return RuntimePressurePolicy.pressureCandidate(
            candidates: [candidate],
            level: level
        ) != nil
    }

    private func stage(forInactiveSince inactiveSinceUptime: TimeInterval) -> AutomaticLifecycleStage {
        AutomaticLifecycleStage.resolve(
            inactiveDuration: monotonicUptime() - inactiveSinceUptime,
            recentStageDuration: recentStageDuration,
            longIdleThreshold: longIdleThreshold
        )
    }

    private func refreshInactiveStagesForPressureEvaluation() {
        for plan in Array(inactivePlans.values) {
            guard plan.retentionPreference == .automatic,
                  planMatches(plan, slotID: plan.profile.id),
                  plan.stage != stage(forInactiveSince: plan.inactiveSinceUptime) else {
                continue
            }
            advanceInactiveStage(
                for: plan.profile,
                expectedPlan: plan,
                refreshPressureEligibility: false
            )
        }
    }

    /// Idempotent pressure re-entry seam. Whenever a lifecycle boundary makes
    /// a Runtime newly eligible (inactive plan created, media protection
    /// ended, protection window closed) while the latest observed pressure is
    /// still warning/critical, the progressive ladder is reconsidered from
    /// fresh facts — without waiting for the system to re-send the same
    /// pressure event and without stacking a second reclaim transaction.
    private func reconcileProgressivePressureIfNeeded() {
        guard let level = latestMemoryPressureLevel,
              pressureReclaimWorkItem == nil,
              pressureReclaimEvaluationToken == nil else { return }
        beginProgressivePressureReclaim(level: level)
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
        guard pressureReclaimWorkItem == nil,
              pressureReclaimEvaluationToken == nil,
              latestMemoryPressureLevel == level else { return }
        let candidate = RuntimePressurePolicy.pressureCandidate(
            candidates: pressureCandidates(),
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

        let reason = level == .critical
            ? "critical_pressure_eligible"
            : "warning_pressure_eligible"
        if plan.backgroundMediaPolicy == .allowBackgroundAudio {
            let evaluationToken = UUID()
            pressureReclaimEvaluationToken = evaluationToken
            mediaPlayingQuery(candidate.slotID) { [weak self] isPlaying in
                guard let self else { return }
                guard self.pressureReclaimEvaluationToken == evaluationToken else {
                    return
                }
                self.pressureReclaimEvaluationToken = nil
                guard let currentLevel = self.latestMemoryPressureLevel else { return }
                guard self.planMatches(plan, slotID: candidate.slotID) else {
                    // The captured plan may have been cancelled while media
                    // validation was in flight. Keep the owned ladder moving
                    // under sustained pressure, but select again from fresh
                    // current Runtime and protection facts.
                    self.reconcileProgressivePressureIfNeeded()
                    return
                }
                if isPlaying {
                    self.mediaProtectedSlotIDs.insert(candidate.slotID)
                    self.scheduleMediaProtectionRecheck(for: plan.profile, plan: plan)
                } else {
                    self.mediaProtectedSlotIDs.remove(candidate.slotID)
                    if self.isPressureEligible(plan: plan, level: currentLevel) {
                        self.releaseInactiveSlot(
                            slotID: candidate.slotID,
                            expectedPlan: plan,
                            memoryPressureIncident: incidentContext,
                            releaseReason: currentLevel == .critical
                                ? "critical_pressure_eligible"
                                : "warning_pressure_eligible",
                            pressureLevel: currentLevel
                        )
                    }
                }
                self.schedulePressureContinuation()
            }
            return
        }

        releaseInactiveSlot(
            slotID: candidate.slotID,
            expectedPlan: plan,
            memoryPressureIncident: incidentContext,
            releaseReason: reason,
            pressureLevel: level
        )
        schedulePressureContinuation()
    }

    private func schedulePressureContinuation() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pressureReclaimWorkItem = nil
            guard let latestLevel = self.latestMemoryPressureLevel else { return }
            self.beginProgressivePressureReclaim(level: latestLevel)
        }
        pressureReclaimWorkItem = workItem
        scheduleDelayedWork(pressureStepDelay, workItem)
    }

    private func recordMemoryPressureEvaluations(
        level: SlotMemoryPressureLevel,
        incidentContext: RuntimeDiagnosticIncidentContext
    ) {
        let selected = RuntimePressurePolicy.pressureCandidate(
            candidates: pressureCandidates(),
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
            let stage: AutomaticLifecycleStage?
            if let plan {
                stage = self.stage(forInactiveSince: plan.inactiveSinceUptime)
            } else {
                stage = nil
            }
            let selectedForRelease = selected == slotID
            let decisionName: String
            let releaseReason: String
            if selectedForRelease {
                decisionName = "hibernate"
                releaseReason = level == .critical
                    ? "critical_pressure_eligible"
                    : "warning_pressure_eligible"
            } else if preference == .keepLoaded {
                decisionName = "keep"
                releaseReason = "keep_loaded_retained"
            } else if level == .warning {
                decisionName = stage == .recent ? "keep" : "observe"
                releaseReason = stage == .recent
                    ? "recent_stage_protected"
                    : "warning_diagnostics_only"
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
                "automatic_stage": .string(stage?.rawValue ?? "none"),
                "media_protected": .bool(protection.media),
                "attention_protected": .bool(protection.attention),
                "release_eligible": .bool(selectedForRelease),
                "decision": .string(decisionName),
                "release_reason": .string(releaseReason),
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
        releaseReason: String = "inactive_release",
        pressureLevel: SlotMemoryPressureLevel? = nil
    ) {
        guard let currentPlan = inactivePlans[slotID],
              expectedPlan.map({ $0.token == currentPlan.token
                    && $0.runtimeObjectID == currentPlan.runtimeObjectID }) ?? true,
              currentPlan.retentionPreference == .automatic,
              planMatches(currentPlan, slotID: slotID),
              !isVisibleSlot(slotID) else {
            return
        }
        if let pressureLevel {
            guard latestMemoryPressureLevel == pressureLevel,
                  isPressureEligible(plan: currentPlan, level: pressureLevel) else { return }
        } else {
            guard latestMemoryPressureLevel == nil,
                  stage(forInactiveSince: currentPlan.inactiveSinceUptime) == .longIdle else {
                return
            }
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

    private func cancelInactivePlan(slotID: UUID) {
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
        mediaProtectedSlotIDs.remove(slotID)
    }

    private func planMatches(_ plan: InactivePlan, slotID: UUID) -> Bool {
        guard let currentPlan = inactivePlans[slotID],
              currentPlan.token == plan.token,
              currentPlan.runtimeObjectID == plan.runtimeObjectID,
              let webView = webViewPool.existingWebView(for: slotID) else { return false }
        return ObjectIdentifier(webView) == currentPlan.runtimeObjectID
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
