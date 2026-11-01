#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text()


def write(path, text):
    (ROOT / path).write_text(text)


def replace_once(path, old, new):
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one literal match, got {count}: {old[:80]!r}")
    write(path, text.replace(old, new, 1))


def replace_all_checked(path, old, new, minimum=1):
    text = read(path)
    count = text.count(old)
    if count < minimum:
        raise SystemExit(f"{path}: expected >= {minimum} matches, got {count}: {old[:80]!r}")
    write(path, text.replace(old, new))


def regex_once(path, pattern, replacement):
    text = read(path)
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S | re.M)
    if count != 1:
        raise SystemExit(f"{path}: expected one regex match, got {count}: {pattern[:100]!r}")
    write(path, updated)


# -----------------------------------------------------------------------------
# WP1 — canonical retention model with additive legacy compatibility.
# -----------------------------------------------------------------------------
p = "FloatTabs/Tabs/WebAppProfile.swift"
replace_once(
    p,
    "\n\nenum BackgroundMediaPolicy: String, Codable, CaseIterable, Equatable {",
    '''\n\nenum SlotRuntimeRetentionPreference: String, Codable, CaseIterable, Equatable {
    case automatic
    case keepLoaded

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .keepLoaded: return "Keep Loaded"
        }
    }

    var detailText: String {
        switch self {
        case .automatic:
            return "Manage this Runtime automatically. Inactive Runtime may be reclaimed and restored on demand."
        case .keepLoaded:
            return "Prefer to keep an already loaded inactive Runtime during normal operation. Critical memory pressure may still reclaim it."
        }
    }

    init(legacy residencyPolicy: SlotResidencyPolicy) {
        self = residencyPolicy == .hot ? .keepLoaded : .automatic
    }

    var legacyProjection: SlotResidencyPolicy {
        switch self {
        case .automatic: return .warm
        case .keepLoaded: return .hot
        }
    }
}

enum BackgroundMediaPolicy: String, Codable, CaseIterable, Equatable {'''
)
replace_once(
    p,
    "    var residencyPolicy: SlotResidencyPolicy\n",
    '''    var runtimeRetentionPreference: SlotRuntimeRetentionPreference

    /// Rollback/protocol compatibility only. Current product lifecycle decisions
    /// must use `runtimeRetentionPreference`.
    var residencyPolicy: SlotResidencyPolicy {
        get { runtimeRetentionPreference.legacyProjection }
        set { runtimeRetentionPreference = SlotRuntimeRetentionPreference(legacy: newValue) }
    }
'''
)
replace_once(
    p,
    "        residencyPolicy: SlotResidencyPolicy = .warm,\n",
    '''        runtimeRetentionPreference: SlotRuntimeRetentionPreference = .automatic,
        residencyPolicy: SlotResidencyPolicy? = nil,
'''
)
replace_once(
    p,
    "        self.residencyPolicy = residencyPolicy\n",
    '''        self.runtimeRetentionPreference = residencyPolicy.map {
            SlotRuntimeRetentionPreference(legacy: $0)
        } ?? runtimeRetentionPreference
'''
)
replace_once(
    p,
    "        case residencyPolicy\n",
    "        case runtimeRetentionPreference\n        case residencyPolicy\n"
)
replace_once(
    p,
    '''        residencyPolicy = try container.decodeIfPresent(
            SlotResidencyPolicy.self,
            forKey: .residencyPolicy
        ) ?? .warm
''',
    '''        if let currentPreference = try container.decodeIfPresent(
            SlotRuntimeRetentionPreference.self,
            forKey: .runtimeRetentionPreference
        ) {
            runtimeRetentionPreference = currentPreference
        } else if let legacyPolicy = try container.decodeIfPresent(
            SlotResidencyPolicy.self,
            forKey: .residencyPolicy
        ) {
            runtimeRetentionPreference = SlotRuntimeRetentionPreference(legacy: legacyPolicy)
        } else {
            runtimeRetentionPreference = .automatic
        }
'''
)
replace_once(
    p,
    "        try container.encode(residencyPolicy, forKey: .residencyPolicy)\n",
    '''        try container.encode(
            runtimeRetentionPreference,
            forKey: .runtimeRetentionPreference
        )
        try container.encode(
            runtimeRetentionPreference.legacyProjection,
            forKey: .residencyPolicy
        )
'''
)

p = "FloatTabs/Tabs/TabStore.swift"
replace_all_checked(
    p,
    "            residencyPolicy: source.residencyPolicy,",
    "            runtimeRetentionPreference: source.runtimeRetentionPreference,",
    minimum=2,
)
regex_once(
    p,
    r'''    @discardableResult\n    func updateResourcePolicy\(\n        id: UUID,\n        residencyPolicy: SlotResidencyPolicy\? = nil,\n        backgroundMediaPolicy: BackgroundMediaPolicy\? = nil\n    \) -> Bool \{.*?\n    \}\n\n(?=    @discardableResult\n    func updatePreferredViewport)''',
    '''    @discardableResult
    func updateRuntimeRetentionPreference(
        id: UUID,
        preference: SlotRuntimeRetentionPreference
    ) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        guard profiles[index].runtimeRetentionPreference != preference else { return true }
        return persistConfigurationMutation {
            profiles[index].runtimeRetentionPreference = preference
            return true
        }
    }

    /// Legacy command/backup compatibility adapter. New product UI writes the
    /// canonical runtime-retention preference directly.
    @discardableResult
    func updateResourcePolicy(
        id: UUID,
        residencyPolicy: SlotResidencyPolicy? = nil,
        backgroundMediaPolicy: BackgroundMediaPolicy? = nil
    ) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        let retentionPreference = residencyPolicy.map(SlotRuntimeRetentionPreference.init(legacy:))
        let retentionChanged = retentionPreference.map {
            profiles[index].runtimeRetentionPreference != $0
        } ?? false
        let mediaChanged = backgroundMediaPolicy.map {
            profiles[index].backgroundMediaPolicy != $0
        } ?? false
        guard retentionChanged || mediaChanged else { return true }

        return persistConfigurationMutation {
            if let retentionPreference {
                profiles[index].runtimeRetentionPreference = retentionPreference
            }
            if let backgroundMediaPolicy {
                profiles[index].backgroundMediaPolicy = backgroundMediaPolicy
            }
            return true
        }
    }

'''
)

# -----------------------------------------------------------------------------
# WP2 — one automatic lifecycle policy, LRU budget and critical fallback.
# -----------------------------------------------------------------------------
p = "FloatTabs/Web/SlotLifecycleCoordinator.swift"
regex_once(
    p,
    r'''private struct RuntimeBudgetPolicy \{.*?\n\}\n\n@MainActor''',
    '''private struct RuntimeBudgetPolicy {
    static let defaultManagedResidentTarget = 2
    static let warningManagedResidentTarget = 1

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

    static func decide(
        candidates: [Candidate],
        target: Int,
        critical: Bool = false
    ) -> Decision {
        let normalizedTarget = max(target, 0)
        let automatic = candidates.filter { $0.retentionPreference == .automatic }
        let eligibleAutomatic = automatic
            .filter { !$0.isProtected }
            .sorted(by: evictionOrder)
        let requiredAutomaticEvictions = max(automatic.count - normalizedTarget, 0)
        var evictSlotIDs = Array(
            eligibleAutomatic.prefix(requiredAutomaticEvictions).map(\\.slotID)
        )

        if critical {
            let selected = Set(evictSlotIDs)
            let remainingAutomatic = eligibleAutomatic.filter { !selected.contains($0.slotID) }
            evictSlotIDs.append(contentsOf: remainingAutomatic.map(\\.slotID))
            let eligibleKeepLoaded = candidates
                .filter { !$0.isProtected && $0.retentionPreference == .keepLoaded }
                .sorted(by: evictionOrder)
            evictSlotIDs.append(contentsOf: eligibleKeepLoaded.map(\\.slotID))
        }

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

    private static func evictionOrder(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.lastUsedAt != rhs.lastUsedAt {
            return lhs.lastUsedAt < rhs.lastUsedAt
        }
        return lhs.slotID.uuidString < rhs.slotID.uuidString
    }
}

@MainActor'''
)
replace_once(
    p,
    "    nonisolated static let defaultColdReleaseDelay: TimeInterval = 30\n    nonisolated static let defaultWarmReleaseDelay: TimeInterval = 120\n",
    '''    // Compatibility constants remain for older tests/callers; current
    // product policy uses one Automatic inactivity grace.
    nonisolated static let defaultColdReleaseDelay: TimeInterval = 30
    nonisolated static let defaultWarmReleaseDelay: TimeInterval = 120
    nonisolated static let defaultAutomaticReleaseDelay: TimeInterval = 30
    nonisolated static let warningManagedResidentTarget = RuntimeBudgetPolicy.warningManagedResidentTarget
'''
)
replace_once(
    p,
    "        let residencyPolicy: SlotResidencyPolicy\n",
    "        let retentionPreference: SlotRuntimeRetentionPreference\n"
)
replace_once(
    p,
    "    private var coldReleaseDelay: TimeInterval\n    private var warmReleaseDelay: TimeInterval\n",
    "    private var automaticReleaseDelay: TimeInterval\n"
)
replace_once(
    p,
    "        self.coldReleaseDelay = max(coldReleaseDelay, 0)\n        self.warmReleaseDelay = max(warmReleaseDelay, 0)\n",
    '''        // Legacy constructor knobs are retained only as a deterministic
        // test/rollback seam. Production no longer reads the user Warm/Cold
        // settings; the smaller value maps to the single Automatic grace.
        automaticReleaseDelay = max(min(coldReleaseDelay, warmReleaseDelay), 0)
'''
)
regex_once(
    p,
    r'''    func updateReleaseDelays\(\n        coldReleaseDelay: TimeInterval,\n        warmReleaseDelay: TimeInterval\n    \) \{.*?\n    \}\n\n(?=    func reconcile)''',
    '''    /// Compatibility seam for older tests. Production no longer observes
    /// Warm/Cold settings; both values collapse to one Automatic grace.
    func updateReleaseDelays(
        coldReleaseDelay: TimeInterval,
        warmReleaseDelay: TimeInterval
    ) {
        let normalized = max(min(coldReleaseDelay, warmReleaseDelay), 0)
        guard normalized != automaticReleaseDelay else { return }
        automaticReleaseDelay = normalized

        let profiles = inactivePlans.values.map(\\.profile)
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

'''
)
regex_once(
    p,
    r'''    func reconcile\(profiles: \[WebAppProfile\]\) \{.*?\n    \}\n\n(?=    func setPanelVisible)''',
    '''    func reconcile(profiles: [WebAppProfile]) {
        knownProfiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        let validIDs = Set(profiles.map(\\.id))

        if let activeSlotID, !validIDs.contains(activeSlotID) {
            self.activeSlotID = nil
        }

        // Phase 7 has no hidden Hot host. Remove any compatibility host that
        // could have survived an in-process preference transition.
        container.retainHotSlots([])

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

'''
)
regex_once(
    p,
    r'''    func restartAfterProtectionEnded\(profile: WebAppProfile\) \{.*?\n    \}\n\n(?=    func restartAfterAttentionProtectionEnded)''',
    '''    func restartAfterProtectionEnded(profile: WebAppProfile) {
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

'''
)
replace_once(
    p,
    '''    var pendingColdReleaseCount: Int {
        inactivePlans.values.filter { $0.residencyPolicy == .cold }.count
    }

    var pendingWarmReleaseCount: Int {
        inactivePlans.values.filter { $0.residencyPolicy == .warm }.count
    }
''',
    '''    /// Legacy debug counters retained for old fixtures. Automatic plans
    /// are projected as Warm; Cold no longer exists as a current policy.
    var pendingColdReleaseCount: Int { 0 }

    var pendingWarmReleaseCount: Int {
        inactivePlans.values.filter { $0.retentionPreference == .automatic }.count
    }
'''
)
replace_once(
    p,
    '''            "lifecycle_pending_release_class": .string(plan?.residencyPolicy.rawValue ?? "none"),
            "lifecycle_media_protected": .bool(protection.media),
            "lifecycle_attention_protected": .bool(protection.attention),
            "lifecycle_managed_resident_target": .integer(Int64(managedResidentTarget))
''',
    '''            "lifecycle_pending_release_class": .string(plan?.retentionPreference.rawValue ?? "none"),
            "lifecycle_runtime_retention": .string(
                knownProfiles[slotID]?.runtimeRetentionPreference.rawValue ?? "unknown"
            ),
            "lifecycle_media_protected": .bool(protection.media),
            "lifecycle_attention_protected": .bool(protection.attention),
            "lifecycle_managed_resident_target": .integer(Int64(managedResidentTarget))
'''
)
regex_once(
    p,
    r'''    private func prepareInactive\(profile: WebAppProfile\) \{.*?\n    \}\n\n(?=    private func ensureInactivePlan)''',
    '''    private func prepareInactive(profile: WebAppProfile) {
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

'''
)
replace_once(
    p,
    "           existing.residencyPolicy == profile.residencyPolicy,\n",
    "           existing.retentionPreference == profile.runtimeRetentionPreference,\n"
)
replace_once(
    p,
    "            residencyPolicy: profile.residencyPolicy,\n",
    "            retentionPreference: profile.runtimeRetentionPreference,\n"
)
replace_once(
    p,
    '                "residency": .string(profile.residencyPolicy.rawValue)\n',
    '                "runtime_retention": .string(profile.runtimeRetentionPreference.rawValue)\n'
)
regex_once(
    p,
    r'''    private func scheduleRelease\(\n        for profile: WebAppProfile,\n        plan: InactivePlan\n    \) \{.*?\n    \}\n\n(?=    private func scheduleHiddenActiveTransition)''',
    '''    private func scheduleRelease(
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

'''
)
regex_once(
    p,
    r'''    private func budgetCandidates\(\) -> \[RuntimeBudgetPolicy\.Candidate\] \{.*?\n    \}\n\n    private func budgetDecision\(for pressure: SlotMemoryPressureLevel\? = nil\) -> RuntimeBudgetPolicy\.Decision \{.*?\n    \}\n''',
    '''    private func budgetCandidates() -> [RuntimeBudgetPolicy.Candidate] {
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

    private func budgetDecision(
        for pressure: SlotMemoryPressureLevel? = nil
    ) -> RuntimeBudgetPolicy.Decision {
        let target: Int
        switch pressure {
        case .warning:
            target = RuntimeBudgetPolicy.warningManagedResidentTarget
        case .critical:
            target = 0
        case nil:
            target = managedResidentTarget
        }
        return RuntimeBudgetPolicy.decide(
            candidates: budgetCandidates(),
            target: target,
            critical: pressure == .critical
        )
    }
'''
)
regex_once(
    p,
    r'''            let policy = knownProfiles\[slotID\]\?\.residencyPolicy\n                \?\? plan\?\.residencyPolicy\n                \?\? webViewPool\.residencyPolicy\(for: slotID\)\n            let managed = policy == \.warm \|\| policy == \.cold''',
    '''            let preference = knownProfiles[slotID]?.runtimeRetentionPreference
                ?? plan?.retentionPreference
                ?? webViewPool.runtimeRetentionPreference(for: slotID)
            let managed = preference == .automatic'''
)
replace_once(
    p,
    '                "residency_policy": .string(policy?.rawValue ?? "unknown"),\n',
    '                "runtime_retention_preference": .string(preference?.rawValue ?? "unknown"),\n'
)
replace_once(
    p,
    '                "pending_release_class": .string(plan?.residencyPolicy.rawValue ?? "none"),\n',
    '                "pending_release_class": .string(plan?.retentionPreference.rawValue ?? "none"),\n'
)

# -----------------------------------------------------------------------------
# Container: all current Slots use the transient presentation host. Keep Loaded
# is a pool residency preference, never a hidden attached WebView.
# -----------------------------------------------------------------------------
p = "FloatTabs/Web/WebViewContainer.swift"
replace_once(
    p,
    '''    func show(
        webView: WKWebView,
        slotID: UUID,
        residencyPolicy: SlotResidencyPolicy
    ) {
        switch residencyPolicy {
        case .hot:
            showHot(webView: webView, slotID: slotID)
        case .warm, .cold:
            showTransient(webView: webView, slotID: slotID)
        }
    }
''',
    '''    func show(
        webView: WKWebView,
        slotID: UUID,
        residencyPolicy: SlotResidencyPolicy
    ) {
        _ = residencyPolicy // legacy call-site projection only
        showTransient(webView: webView, slotID: slotID)
    }
'''
)
regex_once(
    p,
    r'''    func deactivate\(slotID: UUID, residencyPolicy: SlotResidencyPolicy\) \{.*?\n    \}\n\n(?=    func retainHotSlots)''',
    '''    func deactivate(slotID: UUID, residencyPolicy: SlotResidencyPolicy) {
        _ = residencyPolicy // legacy call-site projection only
        guard activeSlotID == slotID else { return }
        detachHostedTransientIfOwned()
        activeSlotID = nil
        activeWebView = nil
    }

'''
)
regex_once(
    p,
    r'''    func retainHotSlots\(_ validHotSlotIDs: Set<UUID>\) \{.*?\n    \}\n\n(?=    func removeSlot)''',
    '''    func retainHotSlots(_ validHotSlotIDs: Set<UUID>) {
        _ = validHotSlotIDs
        // Compatibility cleanup only. Phase 7 never creates Hot hosts.
        for slotID in Array(hotHostViews.keys) {
            guard let host = hotHostViews.removeValue(forKey: slotID) else { continue }
            host.detachOwnedWebView()
            host.removeFromSuperview()
        }
    }

'''
)

# -----------------------------------------------------------------------------
# WP3 — current UI exposes only Automatic / Keep Loaded.
# -----------------------------------------------------------------------------
p = "FloatTabs/UI/ExternalTabRail.swift"
replace_once(
    p,
    "    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?\n",
    '''    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)? // legacy command/test seam
    var onSetRuntimeRetention: ((UUID, SlotRuntimeRetentionPreference) -> Void)?
'''
)
# ExternalWebAppTabView has the same declaration; update the second occurrence.
replace_once(
    p,
    "    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?\n",
    '''    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)? // legacy command/test seam
    var onSetRuntimeRetention: ((UUID, SlotRuntimeRetentionPreference) -> Void)?
'''
)
replace_once(
    p,
    '''        view.onSetResidency = { [weak self] slotID, policy in
            self?.onSetResidency?(slotID, policy)
        }
''',
    '''        view.onSetRuntimeRetention = { [weak self] slotID, preference in
            self?.onSetRuntimeRetention?(slotID, preference)
        }
'''
)
replace_once(
    p,
    "    private var residencyPolicy: SlotResidencyPolicy = .warm\n",
    "    private var runtimeRetentionPreference: SlotRuntimeRetentionPreference = .automatic\n"
)
replace_once(
    p,
    "        residencyPolicy = profile.residencyPolicy\n",
    "        runtimeRetentionPreference = profile.runtimeRetentionPreference\n"
)
replace_once(
    p,
    '''        let residency = NSMenuItem(title: "Residency", action: nil, keyEquivalent: "")
        let residencyMenu = NSMenu(title: "Residency")
        for policy in SlotResidencyPolicy.allCases {
            let item = NSMenuItem(title: policy.displayName, action: #selector(setResidencyFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = policy.rawValue
            item.state = policy == residencyPolicy ? .on : .off
            residencyMenu.addItem(item)
        }
        residency.submenu = residencyMenu
        menu.addItem(residency)
''',
    '''        let runtimeRetention = NSMenuItem(
            title: "Runtime Retention",
            action: nil,
            keyEquivalent: ""
        )
        let runtimeRetentionMenu = NSMenu(title: "Runtime Retention")
        for preference in SlotRuntimeRetentionPreference.allCases {
            let item = NSMenuItem(
                title: preference.displayName,
                action: #selector(setRuntimeRetentionFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preference.rawValue
            item.state = preference == runtimeRetentionPreference ? .on : .off
            runtimeRetentionMenu.addItem(item)
        }
        runtimeRetention.submenu = runtimeRetentionMenu
        menu.addItem(runtimeRetention)
'''
)
replace_once(
    p,
    '''    @objc private func setResidencyFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let policy = SlotResidencyPolicy(rawValue: raw) else { return }
        onSetResidency?(slotID, policy)
    }
''',
    '''    @objc private func setRuntimeRetentionFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let preference = SlotRuntimeRetentionPreference(rawValue: raw) else { return }
        onSetRuntimeRetention?(slotID, preference)
    }
'''
)

p = "FloatTabs/UI/GlobalSettingsController.swift"
replace_once(p, "    private let warmRetentionPopup = NSPopUpButton()\n    private let coldReleasePopup = NSPopUpButton()\n", "")
replace_once(
    p,
    '''    private(set) var displayedWarmRetention = WarmWebViewRetentionOption.twoMinutes.displayName
    private(set) var displayedColdRelease = ColdWebViewReleaseOption.thirtySeconds.displayName
''',
    ""
)
regex_once(
    p,
    r'''\n        warmRetentionPopup\.addItems.*?coldReleasePopup\.widthAnchor\.constraint\(equalToConstant: 150\)\.isActive = true\n''',
    "\n"
)
replace_once(
    p,
    '''            sectionTitle("Tab Residency"),
            detailLabel("Hot recovers a terminated renderer in the background. Warm follows its retention setting during normal operation; critical memory pressure may shorten it. Cold releases after its delay."),
            websiteCacheSettingRow("Warm WebView retention", control: warmRetentionPopup),
            websiteCacheSettingRow("Cold release delay", control: coldReleasePopup),
            detailLabel("Choose Hot, Warm, or Cold from each Tab's menu."),
''',
    '''            sectionTitle("Runtime Lifecycle"),
            detailLabel("Web App runtimes are managed automatically by default. Use Runtime Retention → Keep Loaded on a Tab only when you want an already loaded inactive runtime retained during normal operation; critical memory pressure may still reclaim it."),
'''
)
regex_once(
    p,
    r'''    func refreshPerformanceSettings\(\) \{.*?\n    \}\n\n(?=    func refreshWebsiteCache)''',
    '''    func refreshPerformanceSettings() {
        // Legacy Warm/Cold values remain stored for rollback compatibility but
        // are no longer consulted by the current product lifecycle.
        guard isViewLoaded else { return }
    }

'''
)
regex_once(
    p,
    r'''    @objc private func warmRetentionChanged\(_ sender: NSPopUpButton\) \{.*?\n    \}\n\n    @objc private func coldReleaseChanged\(_ sender: NSPopUpButton\) \{.*?\n    \}\n\n''',
    ""
)

# -----------------------------------------------------------------------------
# WP4 — Panel/recovery/cache integrations use the new policy semantics.
# -----------------------------------------------------------------------------
p = "FloatTabs/Panel/PanelController.swift"
replace_once(
    p,
    '''    private lazy var slotLifecycleCoordinator = SlotLifecycleCoordinator(
        webViewPool: webViewPool,
        container: rootView.webPanelContainerView,
        coldReleaseDelay: preferencesStore.coldWebViewReleaseDelay,
        warmReleaseDelay: preferencesStore.warmWebViewRetentionDelay,
        onRuntimeReleased: { [weak self] profile in
            self?.handleRuntimeReleased(profile)
        },
        attentionProtectionQuery: { [weak self] slotID in
''',
    '''    private lazy var slotLifecycleCoordinator = SlotLifecycleCoordinator(
        webViewPool: webViewPool,
        container: rootView.webPanelContainerView,
        attentionProtectionQuery: { [weak self] slotID in
'''
)
regex_once(
    p,
    r'''\n    private func handleRuntimeReleased\(_ profile: WebAppProfile\) \{.*?\n    \}\n\n(?=    private func prepareForWebsiteCacheCleanup)''',
    "\n"
)
replace_once(
    p,
    '''        NotificationCenter.default.addObserver(
            self,
            selector: #selector(slotRetentionPreferenceDidChange(_:)),
            name: .floatTabsSlotRetentionDidChange,
            object: preferencesStore
        )
''',
    ""
)
regex_once(
    p,
    r'''\n    @objc private func slotRetentionPreferenceDidChange\(_ notification: Notification\) \{.*?\n    \}\n''',
    "\n"
)
replace_once(
    p,
    '''        rail.onSetResidency = { [weak self] id, policy in
            _ = self?.setResidency(policy, for: id)
        }
''',
    '''        rail.onSetRuntimeRetention = { [weak self] id, preference in
            _ = self?.tabStore.updateRuntimeRetentionPreference(
                id: id,
                preference: preference
            )
        }
'''
)
replace_once(
    p,
    '                "residency": profile.residencyPolicy.rawValue,\n',
    '''                "runtime_retention": profile.runtimeRetentionPreference.rawValue,
                "residency": profile.residencyPolicy.rawValue,
'''
)

p = "FloatTabs/Web/WebViewPool.swift"
replace_once(
    p,
    '''    /// Read-only residency metadata for diagnostics. Lifecycle remains the
    /// sole owner of release decisions.
    func residencyPolicy(for slotID: UUID) -> SlotResidencyPolicy? {
        residencyPolicyProvider(slotID)
    }

    static func recoveryDisposition(
        isActive: Bool,
        residencyPolicy: SlotResidencyPolicy?
    ) -> WebContentRecoveryDisposition {
        if isActive || residencyPolicy == .hot {
            return .reloadNow
        }
        return .deferUntilActivation
    }
''',
    '''    /// Legacy projection retained for protocol/diagnostic compatibility.
    func residencyPolicy(for slotID: UUID) -> SlotResidencyPolicy? {
        residencyPolicyProvider(slotID)
    }

    func runtimeRetentionPreference(for slotID: UUID) -> SlotRuntimeRetentionPreference? {
        residencyPolicyProvider(slotID).map(SlotRuntimeRetentionPreference.init(legacy:))
    }

    static func recoveryDisposition(
        isActive: Bool,
        runtimeRetentionPreference: SlotRuntimeRetentionPreference?
    ) -> WebContentRecoveryDisposition {
        if isActive || runtimeRetentionPreference == .keepLoaded {
            return .reloadNow
        }
        return .deferUntilActivation
    }

    static func recoveryDisposition(
        isActive: Bool,
        residencyPolicy: SlotResidencyPolicy?
    ) -> WebContentRecoveryDisposition {
        recoveryDisposition(
            isActive: isActive,
            runtimeRetentionPreference: residencyPolicy.map(
                SlotRuntimeRetentionPreference.init(legacy:)
            )
        )
    }
'''
)
replace_once(
    p,
    "        let residencyPolicy = residencyPolicyProvider(slotID)\n",
    "        let runtimeRetentionPreference = runtimeRetentionPreference(for: slotID)\n"
)
replace_once(
    p,
    '''        let recoveryDisposition = Self.recoveryDisposition(
            isActive: isActive,
            residencyPolicy: residencyPolicy
        )
''',
    '''        let recoveryDisposition = Self.recoveryDisposition(
            isActive: isActive,
            runtimeRetentionPreference: runtimeRetentionPreference
        )
'''
)

# Current product paths must not present legacy retention controls.
for path in [
    "FloatTabs/UI/ExternalTabRail.swift",
    "FloatTabs/UI/GlobalSettingsController.swift",
]:
    text = read(path)
    forbidden = ["Choose Hot, Warm, or Cold", 'title: "Residency"']
    for token in forbidden:
        if token in text:
            raise SystemExit(f"{path}: forbidden current UI token remains: {token}")

print("Phase 7 bounded source transform applied successfully")
