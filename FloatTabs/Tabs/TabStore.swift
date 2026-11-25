import AppKit
import Foundation

@MainActor
final class TabStore {
    private(set) var browserProfiles: [BrowserProfile]
    private(set) var defaultBrowserProfilePresentation: DefaultBrowserProfilePresentation
    private(set) var isDefaultBrowserProfileDeleted: Bool
    private(set) var profiles: [WebAppProfile]
    private(set) var activeTabID: UUID?
    private(set) var defaultGroupPresentation: DefaultWebAppGroupPresentation
    private(set) var groups: [WebAppGroup]
    private(set) var activeGroupID: UUID?
    private(set) var bookmarkFolders: [BookmarkFolder]
    private(set) var bookmarks: [BookmarkItem]

    var onChange: (() -> Void)?
    var onPersistenceFailure: (() -> Void)?
    var onUserProfileUse: ((UUID?, Date) -> Void)?

    private let repository: any ProfileRepositoryProtocol
    private let diagnostics: any RuntimeDiagnosticRecording
    private let runtimePersistenceDebounceInterval: TimeInterval
    private var pendingRuntimePersistenceWorkItem: DispatchWorkItem?
    private var hasPendingRuntimePersistence = false
    private var lastActiveTabIDByGroup: [UUID?: UUID] = [:]

    var orderedProfiles: [WebAppProfile] {
        profiles.sorted { lhs, rhs in
            if lhs.order == rhs.order {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.order < rhs.order
        }
    }

    var activeGroupProfiles: [WebAppProfile] {
        orderedProfiles.filter { $0.groupID == activeGroupID }
    }

    var orderedGroups: [WebAppGroup] {
        groups.sorted { lhs, rhs in
            if lhs.order == rhs.order {
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.order < rhs.order
        }
    }

    var groupMenuOptions: [WebAppGroupMenuOption] {
        var countsByGroup: [UUID?: Int] = [:]
        for profile in profiles {
            countsByGroup[profile.groupID, default: 0] += 1
        }
        var options: [WebAppGroupMenuOption] = [
            WebAppGroupMenuOption(
                id: nil,
                name: defaultGroupPresentation.name,
                borderTheme: defaultGroupPresentation.borderTheme,
                customBorderColorHex: defaultGroupPresentation.customBorderColorHex,
                isDefault: true,
                isActive: activeGroupID == nil,
                slotCount: countsByGroup[nil, default: 0]
            )
        ]
        for group in orderedGroups {
            options.append(
                WebAppGroupMenuOption(
                    id: group.id,
                    name: group.name,
                    borderTheme: group.borderTheme,
                    customBorderColorHex: group.customBorderColorHex,
                    isDefault: false,
                    isActive: activeGroupID == group.id,
                    slotCount: countsByGroup[group.id, default: 0]
                )
            )
        }
        return options
    }

    var activeGroupOption: WebAppGroupMenuOption {
        groupMenuOptions.first(where: { $0.id == activeGroupID }) ?? groupMenuOptions[0]
    }

    var orderedBookmarkFolders: [BookmarkFolder] {
        bookmarkFolders.sorted { lhs, rhs in
            if lhs.order == rhs.order {
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.order < rhs.order
        }
    }

    var orderedBookmarks: [BookmarkItem] {
        bookmarks.sorted { lhs, rhs in
            if lhs.order == rhs.order {
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.order < rhs.order
        }
    }

    func bookmarks(in folderID: UUID?) -> [BookmarkItem] {
        orderedBookmarks.filter { $0.folderID == folderID }
    }

    func effectiveBorderAppearance(
        globalTheme: PanelBorderTheme,
        globalCustomColor: NSColor
    ) -> (theme: PanelBorderTheme, customColor: NSColor) {
        let activeOption = activeGroupOption
        guard let overrideTheme = activeOption.borderTheme else {
            return (globalTheme, globalCustomColor)
        }
        if overrideTheme == .custom {
            return (
                .custom,
                activeOption.resolvedCustomColor ?? globalCustomColor
            )
        }
        return (overrideTheme, globalCustomColor)
    }

    var activeProfile: WebAppProfile? {
        guard let activeTabID else { return nil }
        return profiles.first(where: { $0.id == activeTabID })
    }

    init(
        repository: any ProfileRepositoryProtocol = ProfileRepository(),
        diagnostics: any RuntimeDiagnosticRecording = RuntimeDiagnosticNoopRecorder(),
        runtimePersistenceDebounceInterval: TimeInterval = 0
    ) {
        self.repository = repository
        self.diagnostics = diagnostics
        self.runtimePersistenceDebounceInterval = max(0, runtimePersistenceDebounceInterval)

        let loadedState: StoredWebAppState
        let didLoadPersistedState: Bool
        do {
            let persistedState = try repository.load()
            loadedState = try persistedState.sanitizedForUse()
            didLoadPersistedState = true
        } catch {
            loadedState = .empty
            didLoadPersistedState = false
        }

        browserProfiles = loadedState.browserProfiles
        defaultBrowserProfilePresentation = loadedState.defaultBrowserProfilePresentation
        isDefaultBrowserProfileDeleted = loadedState.isDefaultBrowserProfileDeleted
        let normalized = Self.normalizedProfiles(loadedState.profiles)
        profiles = normalized
        defaultGroupPresentation = loadedState.defaultGroupPresentation
        groups = loadedState.groups
        activeGroupID = loadedState.activeGroupID
        bookmarkFolders = loadedState.bookmarkFolders
        bookmarks = loadedState.bookmarks

        if let restoredID = loadedState.lastActiveTabID,
           let restoredProfile = normalized.first(where: { $0.id == restoredID }) {
            if restoredProfile.groupID == activeGroupID {
                activeTabID = restoredID
            } else if let groupTab = normalized.first(where: { $0.groupID == activeGroupID }) {
                activeTabID = groupTab.id
                lastActiveTabIDByGroup[restoredProfile.groupID] = restoredID
            } else {
                activeTabID = nil
            }
        } else {
            activeTabID = normalized.first(where: { $0.groupID == activeGroupID })?.id
        }
        if let activeTabID {
            lastActiveTabIDByGroup[activeGroupID] = activeTabID
        }

        if didLoadPersistedState {
            let repaired = StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                browserProfiles: browserProfiles,
                defaultBrowserProfilePresentation: defaultBrowserProfilePresentation,
                isDefaultBrowserProfileDeleted: isDefaultBrowserProfileDeleted,
                profiles: normalized,
                lastActiveTabID: activeTabID,
                defaultGroupPresentation: defaultGroupPresentation,
                groups: groups,
                activeGroupID: activeGroupID,
                bookmarkFolders: bookmarkFolders,
                bookmarks: bookmarks
            )
            if repaired != loadedState {
                try? repository.save(repaired)
            }
        }
    }

    var totalBrowserProfileCount: Int {
        (isDefaultBrowserProfileDeleted ? 0 : 1) + browserProfiles.count
    }

    var defaultNewSlotBrowserProfileID: UUID? {
        isDefaultBrowserProfileDeleted ? browserProfiles.first?.id : nil
    }

    @discardableResult
    func add(
        name: String? = nil,
        homeURL: URL,
        homeURLSchemeWasInferred: Bool = false,
        renderingProfile: WebRenderingProfile = .canonicalDefault,
        browserProfileID: UUID? = nil,
        targetGroupID: UUID?? = nil,
        now: Date = Date()
    ) -> WebAppProfile? {
        guard WebAppURL.isSafe(homeURL) else { return nil }
        let resolvedBrowserProfileID: UUID?
        if let browserProfileID {
            guard browserProfiles.contains(where: { $0.id == browserProfileID }) else {
                return nil
            }
            resolvedBrowserProfileID = browserProfileID
        } else if isDefaultBrowserProfileDeleted {
            guard let fallbackCustomID = browserProfiles.first?.id else {
                return nil
            }
            resolvedBrowserProfileID = fallbackCustomID
        } else {
            resolvedBrowserProfileID = nil
        }
        let resolvedGroupID = targetGroupID ?? activeGroupID
        if let resolvedGroupID,
           !groups.contains(where: { $0.id == resolvedGroupID }) {
            return nil
        }
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedName = trimmedName.isEmpty
            ? WebAppURL.defaultDisplayName(for: homeURL)
            : trimmedName

        let profile = WebAppProfile(
            browserProfileID: resolvedBrowserProfileID,
            groupID: resolvedGroupID,
            order: orderedProfiles.count,
            name: resolvedName,
            homeURL: homeURL,
            currentURL: homeURL,
            homeURLSchemeWasInferred: homeURLSchemeWasInferred,
            renderingProfile: renderingProfile.normalized(),
            createdAt: now,
            lastUsedAt: now
        )

        guard persistConfigurationMutation({
            profiles.append(profile)
            normalizeInPlace()
            activeGroupID = resolvedGroupID
            activeTabID = profile.id
            lastActiveTabIDByGroup[resolvedGroupID] = profile.id
            return true
        }) else {
            return nil
        }
        return profiles.first(where: { $0.id == profile.id })
    }

    @discardableResult
    func addDerived(
        from sourceID: UUID,
        name: String,
        homeURL: URL,
        now: Date = Date()
    ) -> WebAppProfile? {
        guard WebAppURL.isSafe(homeURL),
              let source = profiles.first(where: { $0.id == sourceID }) else {
            return nil
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let profile = WebAppProfile(
            browserProfileID: source.browserProfileID,
            groupID: source.groupID,
            order: orderedProfiles.count,
            name: trimmedName,
            homeURL: homeURL,
            currentURL: homeURL,
            homeURLSchemeWasInferred: false,
            renderingProfile: source.renderingProfile.normalized(),
            runtimeRetentionPreference: source.runtimeRetentionPreference,
            backgroundMediaPolicy: source.backgroundMediaPolicy,
            createdAt: now,
            lastUsedAt: now
        )

        guard persistConfigurationMutation({
            profiles.append(profile)
            normalizeInPlace()
            activeGroupID = source.groupID
            activeTabID = profile.id
            lastActiveTabIDByGroup[source.groupID] = profile.id
            return true
        }) else {
            return nil
        }
        return profiles.first(where: { $0.id == profile.id })
    }

    @discardableResult
    func createBrowserProfile(name: String, now: Date = Date()) -> BrowserProfile? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let browserProfile = BrowserProfile(
            id: UUID(),
            name: trimmedName,
            createdAt: now
        )
        guard canAddBrowserProfile(browserProfile) else { return nil }

        guard persistConfigurationMutation({
            browserProfiles.append(browserProfile)
            return true
        }) else {
            return nil
        }
        return browserProfiles.first(where: { $0.id == browserProfile.id })
    }

    @discardableResult
    func renameBrowserProfile(id: UUID, name: String) -> Bool {
        guard let index = browserProfiles.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        guard browserProfiles[index].name != trimmedName else { return true }

        var renamed = browserProfiles[index]
        renamed.name = trimmedName
        var candidateProfiles = browserProfiles
        candidateProfiles[index] = renamed
        guard (try? BrowserProfileValidation.validateMetadata(
            candidateProfiles,
            defaultDisplayName: defaultBrowserProfilePresentation.name,
            includeDefaultProfile: !isDefaultBrowserProfileDeleted
        )) != nil else {
            return false
        }

        return persistConfigurationMutation {
            browserProfiles[index] = renamed
            return true
        }
    }

    @discardableResult
    func renameDefaultBrowserProfile(name: String) -> Bool {
        guard !isDefaultBrowserProfileDeleted else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              (try? BrowserProfileValidation.validateMetadata(
                browserProfiles,
                defaultDisplayName: trimmedName,
                includeDefaultProfile: true
              )) != nil else {
            return false
        }
        guard defaultBrowserProfilePresentation.name != trimmedName else { return true }

        return persistConfigurationMutation {
            defaultBrowserProfilePresentation.name = trimmedName
            return true
        }
    }

    @discardableResult
    func setBrowserProfileColor(
        profileID: UUID?,
        color: BrowserProfileColor
    ) -> Bool {
        if let profileID {
            guard let index = browserProfiles.firstIndex(where: { $0.id == profileID }) else {
                return false
            }
            guard browserProfiles[index].color != color else { return true }
            return persistConfigurationMutation {
                browserProfiles[index].color = color
                return true
            }
        }

        guard !isDefaultBrowserProfileDeleted else { return false }
        guard defaultBrowserProfilePresentation.color != color else { return true }
        return persistConfigurationMutation {
            defaultBrowserProfilePresentation.color = color
            return true
        }
    }

    @discardableResult
    func deleteBrowserProfileMetadata(id: UUID) -> Bool {
        deleteBrowserProfileMetadata(id: Optional(id))
    }

    @discardableResult
    func deleteBrowserProfileMetadata(id: UUID?) -> Bool {
        guard totalBrowserProfileCount > 1 else { return false }
        if let id {
            guard browserProfiles.contains(where: { $0.id == id }) else { return false }
            guard !profiles.contains(where: { $0.browserProfileID == id }) else { return false }
            return persistConfigurationMutation {
                browserProfiles.removeAll(where: { $0.id == id })
                for index in bookmarks.indices where bookmarks[index].browserProfileID == id {
                    bookmarks[index].browserProfileID = nil
                }
                return true
            }
        }

        guard !isDefaultBrowserProfileDeleted else { return false }
        guard !profiles.contains(where: { $0.browserProfileID == nil }) else { return false }
        return persistConfigurationMutation {
            isDefaultBrowserProfileDeleted = true
            return true
        }
    }

    @discardableResult
    func setBrowserProfile(
        slotID: UUID,
        profileID: UUID?,
        notifyOnSuccess: Bool = true
    ) -> Bool {
        guard let slotIndex = profiles.firstIndex(where: { $0.id == slotID }) else {
            return false
        }
        if let profileID {
            guard browserProfiles.contains(where: { $0.id == profileID }) else {
                return false
            }
        } else if isDefaultBrowserProfileDeleted {
            return false
        }
        guard profiles[slotIndex].browserProfileID != profileID else { return true }

        return persistConfigurationMutation(notifyOnSuccess: notifyOnSuccess) {
            profiles[slotIndex].browserProfileID = profileID
            return true
        }
    }

    @discardableResult
    func duplicateSlot(
        sourceID: UUID,
        targetBrowserProfileID: UUID?,
        now: Date = Date()
    ) -> WebAppProfile? {
        guard let source = profiles.first(where: { $0.id == sourceID }),
              WebAppURL.isSafe(source.homeURL) else {
            return nil
        }
        if let targetBrowserProfileID {
            guard browserProfiles.contains(where: { $0.id == targetBrowserProfileID }) else {
                return nil
            }
        } else if isDefaultBrowserProfileDeleted {
            return nil
        }

        let duplicate = WebAppProfile(
            browserProfileID: targetBrowserProfileID,
            groupID: source.groupID,
            order: orderedProfiles.count,
            name: source.name,
            homeURL: source.homeURL,
            currentURL: source.currentURL.flatMap { WebAppURL.isSafe($0) ? $0 : nil } ?? source.homeURL,
            homeURLSchemeWasInferred: source.homeURLSchemeWasInferred,
            renderingProfile: source.renderingProfile.normalized(),
            runtimeRetentionPreference: source.runtimeRetentionPreference,
            backgroundMediaPolicy: source.backgroundMediaPolicy,
            createdAt: now,
            lastUsedAt: now
        )

        guard persistConfigurationMutation({
            profiles.append(duplicate)
            normalizeInPlace()
            activeGroupID = source.groupID
            activeTabID = duplicate.id
            lastActiveTabIDByGroup[source.groupID] = duplicate.id
            return true
        }) else {
            return nil
        }
        return profiles.first(where: { $0.id == duplicate.id })
    }

    @discardableResult
    func update(
        id: UUID,
        name: String,
        homeURL: URL,
        homeURLSchemeWasInferred: Bool? = nil,
        renderingProfile: WebRenderingProfile? = nil
    ) -> Bool {
        guard WebAppURL.isSafe(homeURL),
              let index = profiles.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        return persistConfigurationMutation {
            let homeURLChanged = profiles[index].homeURL != homeURL
            profiles[index].name = trimmedName
            profiles[index].homeURL = homeURL
            if let homeURLSchemeWasInferred {
                profiles[index].homeURLSchemeWasInferred = homeURLSchemeWasInferred
            }
            if let renderingProfile {
                profiles[index].renderingProfile = renderingProfile.normalized()
            }
            if homeURLChanged {
                profiles[index].currentURL = homeURL
            }
            return true
        }
    }

    @discardableResult
    func updateHomeURL(id: UUID, homeURL: URL) -> Bool {
        guard WebAppURL.isSafe(homeURL),
              let index = profiles.firstIndex(where: { $0.id == id }) else {
            return false
        }
        guard profiles[index].homeURL != homeURL
            || profiles[index].homeURLSchemeWasInferred else {
            return true
        }

        return persistConfigurationMutation {
            profiles[index].homeURL = homeURL
            // This home came from an already committed page, so it has
            // explicit URL provenance and must not receive entry fallback.
            profiles[index].homeURLSchemeWasInferred = false
            return true
        }
    }

    @discardableResult
    func updateRenderingProfile(id: UUID, renderingProfile: WebRenderingProfile) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        let normalized = renderingProfile.normalized()
        guard profiles[index].renderingProfile != normalized else { return true }
        return persistConfigurationMutation {
            profiles[index].renderingProfile = normalized
            return true
        }
    }

    @discardableResult
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

    @discardableResult
    func updatePreferredViewport(id: UUID, size: CGSize) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        let updated = profiles[index].renderingProfile.settingViewport(size)
        guard profiles[index].renderingProfile != updated else { return true }
        return persistConfigurationMutation {
            profiles[index].renderingProfile = updated
            return true
        }
    }

    @discardableResult
    func updateZoom(id: UUID, zoom: CGFloat) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        let updated = profiles[index].renderingProfile.settingZoom(zoom)
        guard profiles[index].renderingProfile != updated else { return true }
        return persistConfigurationMutation {
            profiles[index].renderingProfile = updated
            return true
        }
    }

    @discardableResult
    func rename(id: UUID, name: String) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        guard profiles[index].name != trimmedName else { return true }

        return persistConfigurationMutation {
            profiles[index].name = trimmedName
            return true
        }
    }

    @discardableResult
    func remove(id: UUID) -> Bool {
        let orderedBeforeRemoval = orderedProfiles
        guard let targetProfile = orderedBeforeRemoval.first(where: { $0.id == id }) else {
            return false
        }
        let targetGroupID = targetProfile.groupID
        let sameGroupBeforeRemoval = orderedBeforeRemoval.filter { $0.groupID == targetGroupID }
        let removedIndexInGroup = sameGroupBeforeRemoval.firstIndex(where: { $0.id == id }) ?? 0

        return persistConfigurationMutation {
            profiles.removeAll(where: { $0.id == id })
            normalizeInPlace()
            if lastActiveTabIDByGroup[targetGroupID] == id {
                lastActiveTabIDByGroup[targetGroupID] = nil
            }

            if activeTabID == id {
                let remainingInActiveGroup = activeGroupProfiles
                if remainingInActiveGroup.isEmpty {
                    activeTabID = nil
                } else {
                    let neighborIndex = min(removedIndexInGroup, remainingInActiveGroup.count - 1)
                    activeTabID = remainingInActiveGroup[neighborIndex].id
                    lastActiveTabIDByGroup[activeGroupID] = activeTabID
                    touchLastUsed(id: activeTabID)
                }
            } else if let activeTabID,
                      !profiles.contains(where: { $0.id == activeTabID }) {
                self.activeTabID = activeGroupProfiles.first?.id
                if let resolved = self.activeTabID {
                    lastActiveTabIDByGroup[activeGroupID] = resolved
                }
            }
            return true
        }
    }

    @discardableResult
    func move(id: UUID, toIndex proposedIndex: Int) -> Bool {
        var allOrdered = orderedProfiles
        guard let target = allOrdered.first(where: { $0.id == id }) else { return false }
        let groupID = target.groupID
        let groupGlobalIndices = allOrdered.indices.filter { allOrdered[$0].groupID == groupID }
        var groupOrdered = groupGlobalIndices.map { allOrdered[$0] }
        guard let sourceIndex = groupOrdered.firstIndex(where: { $0.id == id }) else { return false }
        guard groupOrdered.count > 1 else { return true }

        let destination = min(max(proposedIndex, 0), groupOrdered.count - 1)
        if sourceIndex == destination { return true }

        let moved = groupOrdered.remove(at: sourceIndex)
        groupOrdered.insert(moved, at: destination)
        for (slotOffset, globalIndex) in groupGlobalIndices.enumerated() {
            allOrdered[globalIndex] = groupOrdered[slotOffset]
        }

        return persistConfigurationMutation {
            // `allOrdered` preserves other groups' positions while storing the user's
            // intended intra-group sequence. Reindex in place instead of sorting.
            profiles = Self.reindexedProfilesPreservingSequence(allOrdered)
            return true
        }
    }

    @discardableResult
    func select(
        id: UUID,
        now: Date = Date(),
        trace: RuntimeDiagnosticTrace? = nil
    ) -> Bool {
        let previousActiveTabID = activeTabID
        let previousGroupID = activeGroupID
        diagnostics.record(
            event: "tab.selection.requested",
            level: .info,
            subsystem: "tabs",
            trace: trace,
            fields: [
                "from_slot_id": previousActiveTabID.map { .string($0.uuidString) } ?? .null,
                "to_slot_id": .string(id.uuidString)
            ]
        )
        guard let targetProfile = profiles.first(where: { $0.id == id }) else {
            diagnostics.record(
                event: "tab.selection.failed",
                level: .warning,
                subsystem: "tabs",
                trace: trace,
                fields: ["to_slot_id": .string(id.uuidString)]
            )
            return false
        }
        if let previousActiveTabID,
           profiles.first(where: { $0.id == previousActiveTabID })?.groupID == previousGroupID {
            lastActiveTabIDByGroup[previousGroupID] = previousActiveTabID
        }
        let didChangeActiveTab = previousActiveTabID != id || previousGroupID != targetProfile.groupID
        activeGroupID = targetProfile.groupID
        activeTabID = id
        lastActiveTabIDByGroup[targetProfile.groupID] = id
        touchLastUsed(id: id, now: now)
        persistRuntimeAndNotify()
        if didChangeActiveTab {
            onUserProfileUse?(targetProfile.browserProfileID, now)
        }
        if didChangeActiveTab {
            diagnostics.record(
                event: "tab.selection.changed",
                level: .notice,
                subsystem: "tabs",
                trace: trace,
                fields: [
                    "from_slot_id": previousActiveTabID.map { .string($0.uuidString) } ?? .null,
                    "to_slot_id": .string(id.uuidString)
                ]
            )
        }
        return true
    }

    @discardableResult
    func selectNext(now: Date = Date(), trace: RuntimeDiagnosticTrace? = nil) -> WebAppProfile? {
        selectRelative(by: 1, now: now, trace: trace)
    }

    @discardableResult
    func selectPrevious(now: Date = Date(), trace: RuntimeDiagnosticTrace? = nil) -> WebAppProfile? {
        selectRelative(by: -1, now: now, trace: trace)
    }

    /// Select a slot relative to the current one in one model transaction.
    /// Scoped to `activeGroupProfiles` so cycling tabs matches the visible group rail.
    @discardableResult
    func selectRelative(
        by offset: Int,
        now: Date = Date(),
        trace: RuntimeDiagnosticTrace? = nil
    ) -> WebAppProfile? {
        let ordered = activeGroupProfiles
        guard !ordered.isEmpty else {
            activeTabID = nil
            return nil
        }

        let baseIndex: Int
        if let activeTabID,
           let currentIndex = ordered.firstIndex(where: { $0.id == activeTabID }) {
            baseIndex = currentIndex
        } else if offset < 0 {
            baseIndex = 0
        } else {
            baseIndex = ordered.count - 1
        }

        let count = ordered.count
        let normalizedOffset = offset % count
        let targetIndex = (baseIndex + normalizedOffset + count) % count
        _ = select(id: ordered[targetIndex].id, now: now, trace: trace)
        return activeProfile
    }

    func slotByKeyboardIndex(_ keyboardIndex: Int) -> WebAppProfile? {
        guard (1...9).contains(keyboardIndex) else { return nil }
        let ordered = activeGroupProfiles
        let index = keyboardIndex - 1
        guard ordered.indices.contains(index) else { return nil }
        return ordered[index]
    }

    /// Browser position is runtime state rather than user configuration. Keep it
    /// in memory even if the best-effort persistence write fails so navigation is
    /// never blocked by a transient local I/O problem.
    func updateCurrentURL(id: UUID, url: URL) {
        guard WebAppURL.isSafe(url),
              let index = profiles.firstIndex(where: { $0.id == id }),
              profiles[index].currentURL != url else {
            return
        }

        profiles[index].currentURL = url
        persistRuntimeState()
    }

    func storedStateSnapshot() -> StoredWebAppState {
        currentState()
    }

    @discardableResult
    func replaceStoredState(
        _ state: StoredWebAppState,
        notifyOnSuccess: Bool = true
    ) -> Bool {
        guard state.version == StoredWebAppState.currentVersion else { return false }

        let sanitized: StoredWebAppState
        do {
            sanitized = try state.sanitizedForUse()
        } catch {
            return false
        }
        let normalized = Self.normalizedProfiles(sanitized.profiles)
        let restoredActiveID: UUID?
        if let requested = sanitized.lastActiveTabID,
           let restoredProfile = normalized.first(where: { $0.id == requested }),
           restoredProfile.groupID == sanitized.activeGroupID {
            restoredActiveID = requested
        } else {
            restoredActiveID = normalized.first(where: { $0.groupID == sanitized.activeGroupID })?.id
        }

        let replacement = StoredWebAppState(
            version: StoredWebAppState.currentVersion,
            browserProfiles: sanitized.browserProfiles,
            defaultBrowserProfilePresentation: sanitized.defaultBrowserProfilePresentation,
            isDefaultBrowserProfileDeleted: sanitized.isDefaultBrowserProfileDeleted,
            profiles: normalized,
            lastActiveTabID: restoredActiveID,
            defaultGroupPresentation: sanitized.defaultGroupPresentation,
            groups: sanitized.groups,
            activeGroupID: sanitized.activeGroupID,
            bookmarkFolders: sanitized.bookmarkFolders,
            bookmarks: sanitized.bookmarks
        )

        do {
            try repository.save(replacement)
            pendingRuntimePersistenceWorkItem?.cancel()
            pendingRuntimePersistenceWorkItem = nil
            hasPendingRuntimePersistence = false
        } catch {
            return false
        }

        browserProfiles = sanitized.browserProfiles
        defaultBrowserProfilePresentation = sanitized.defaultBrowserProfilePresentation
        isDefaultBrowserProfileDeleted = sanitized.isDefaultBrowserProfileDeleted
        profiles = normalized
        defaultGroupPresentation = sanitized.defaultGroupPresentation
        groups = sanitized.groups
        activeGroupID = sanitized.activeGroupID
        bookmarkFolders = sanitized.bookmarkFolders
        bookmarks = sanitized.bookmarks
        lastActiveTabIDByGroup.removeAll()
        if let restoredActiveID {
            lastActiveTabIDByGroup[activeGroupID] = restoredActiveID
        }
        activeTabID = restoredActiveID
        if notifyOnSuccess {
            onChange?()
        }
        return true
    }

    // MARK: - Groups

    @discardableResult
    func selectGroup(id: UUID?, now: Date = Date()) -> Bool {
        if let id, !groups.contains(where: { $0.id == id }) {
            return false
        }
        if let currentActiveTabID = activeTabID,
           profiles.first(where: { $0.id == currentActiveTabID })?.groupID == activeGroupID {
            lastActiveTabIDByGroup[activeGroupID] = currentActiveTabID
        }
        if activeGroupID == id {
            return true
        }

        let previousTab = activeProfile
        activeGroupID = id
        let candidateIDs = orderedProfiles.filter { $0.groupID == id }.map(\.id)
        if let rememberedID = lastActiveTabIDByGroup[id], candidateIDs.contains(rememberedID) {
            activeTabID = rememberedID
        } else {
            activeTabID = candidateIDs.first
        }
        if let activeTabID {
            lastActiveTabIDByGroup[id] = activeTabID
            touchLastUsed(id: activeTabID, now: now)
        }
        persistRuntimeAndNotify()
        let nextProfile = activeProfile
        if nextProfile?.id != previousTab?.id {
            onUserProfileUse?(nextProfile?.browserProfileID, now)
        }
        return true
    }

    @discardableResult
    func createGroup(
        name: String,
        borderTheme: PanelBorderTheme? = nil,
        customBorderColorHex: String? = nil,
        selectImmediately: Bool = true,
        now: Date = Date()
    ) -> WebAppGroup? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isGroupNameAvailable(trimmed, excludingGroupID: nil, treatDefaultExclusion: false) else {
            return nil
        }

        let group = WebAppGroup(
            id: UUID(),
            name: trimmed,
            order: orderedGroups.count,
            borderTheme: borderTheme,
            customBorderColorHex: customBorderColorHex,
            createdAt: now
        )

        guard persistConfigurationMutation({
            groups.append(group)
            normalizeGroupsInPlace()
            if selectImmediately {
                if let currentActiveTabID = activeTabID,
                   profiles.first(where: { $0.id == currentActiveTabID })?.groupID == activeGroupID {
                    lastActiveTabIDByGroup[activeGroupID] = currentActiveTabID
                }
                activeGroupID = group.id
                activeTabID = nil
            }
            return true
        }) else {
            return nil
        }
        return groups.first(where: { $0.id == group.id })
    }

    @discardableResult
    func updateGroup(
        id: UUID?,
        name: String,
        borderTheme: PanelBorderTheme?,
        customBorderColorHex: String?
    ) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHex = AppPreferencesStore.normalizedColorHex(customBorderColorHex ?? "")
        guard isGroupNameAvailable(
            trimmed,
            excludingGroupID: id,
            treatDefaultExclusion: id == nil
        ) else {
            return false
        }

        if let id {
            guard let index = groups.firstIndex(where: { $0.id == id }) else {
                return false
            }
            return persistConfigurationMutation {
                groups[index].name = trimmed
                groups[index].borderTheme = borderTheme
                groups[index].customBorderColorHex = borderTheme == .custom ? normalizedHex : nil
                return true
            }
        }

        return persistConfigurationMutation {
            defaultGroupPresentation = DefaultWebAppGroupPresentation(
                name: trimmed,
                borderTheme: borderTheme,
                customBorderColorHex: borderTheme == .custom ? normalizedHex : nil
            )
            return true
        }
    }

    @discardableResult
    func deleteGroup(id: UUID) -> Bool {
        guard groups.contains(where: { $0.id == id }) else { return false }

        return persistConfigurationMutation {
            for index in profiles.indices where profiles[index].groupID == id {
                profiles[index].groupID = nil
            }
            groups.removeAll(where: { $0.id == id })
            normalizeGroupsInPlace()
            lastActiveTabIDByGroup[id] = nil

            if activeGroupID == id {
                activeGroupID = nil
                let defaultGroupTabs = orderedProfiles.filter { $0.groupID == nil }
                if let remembered = lastActiveTabIDByGroup[nil],
                   defaultGroupTabs.contains(where: { $0.id == remembered }) {
                    activeTabID = remembered
                } else {
                    activeTabID = defaultGroupTabs.first?.id
                }
                if let activeTabID {
                    lastActiveTabIDByGroup[nil] = activeTabID
                }
            }
            return true
        }
    }

    @discardableResult
    func moveSlotToGroup(slotID: UUID, groupID: UUID?) -> Bool {
        guard let slotIndex = profiles.firstIndex(where: { $0.id == slotID }) else {
            return false
        }
        if let groupID, !groups.contains(where: { $0.id == groupID }) {
            return false
        }
        let previousGroupID = profiles[slotIndex].groupID
        guard previousGroupID != groupID else { return true }

        let activeGroupBeforeMove = activeGroupProfiles
        let removedIndexInActiveGroup = activeGroupBeforeMove.firstIndex(where: { $0.id == slotID }) ?? 0

        return persistConfigurationMutation {
            profiles[slotIndex].groupID = groupID
            lastActiveTabIDByGroup[groupID] = slotID
            if activeTabID == slotID, previousGroupID == activeGroupID {
                let remaining = activeGroupProfiles
                if let next = remaining.isEmpty
                    ? nil
                    : remaining[min(removedIndexInActiveGroup, remaining.count - 1)].id {
                    activeTabID = next
                    lastActiveTabIDByGroup[activeGroupID] = next
                } else {
                    activeTabID = nil
                    lastActiveTabIDByGroup[activeGroupID] = nil
                }
            }
            return true
        }
    }

    // MARK: - Bookmarks

    func childBookmarkFolders(of parentFolderID: UUID?) -> [BookmarkFolder] {
        orderedBookmarkFolders.filter { $0.parentFolderID == parentFolderID }
    }

    func bookmarkFolderDisplayPath(id: UUID) -> String {
        let byID = Dictionary(uniqueKeysWithValues: bookmarkFolders.map { ($0.id, $0) })
        var components: [String] = []
        var visited = Set<UUID>()
        var cursor: UUID? = id
        while let currentID = cursor,
              visited.insert(currentID).inserted,
              let folder = byID[currentID] {
            components.append(folder.name)
            cursor = folder.parentFolderID
        }
        return components.reversed().joined(separator: " / ")
    }

    func isBookmarkFolder(_ candidateID: UUID, descendantOf ancestorID: UUID) -> Bool {
        if candidateID == ancestorID { return true }
        let byID = Dictionary(uniqueKeysWithValues: bookmarkFolders.map { ($0.id, $0) })
        var visited = Set<UUID>()
        var cursor = byID[candidateID]?.parentFolderID
        while let current = cursor, visited.insert(current).inserted {
            if current == ancestorID { return true }
            cursor = byID[current]?.parentFolderID
        }
        return false
    }

    @discardableResult
    func createBookmarkFolder(
        name: String,
        parentFolderID: UUID? = nil,
        now: Date = Date()
    ) -> BookmarkFolder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let parentFolderID, !bookmarkFolders.contains(where: { $0.id == parentFolderID }) {
            return nil
        }
        guard !bookmarkFolders.contains(where: {
            $0.parentFolderID == parentFolderID
                && $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else {
            return nil
        }

        let folder = BookmarkFolder(
            id: UUID(),
            parentFolderID: parentFolderID,
            name: trimmed,
            order: orderedBookmarkFolders.count,
            createdAt: now
        )
        guard persistConfigurationMutation({
            bookmarkFolders.append(folder)
            normalizeBookmarkFoldersInPlace()
            return true
        }) else {
            return nil
        }
        return bookmarkFolders.first(where: { $0.id == folder.id })
    }

    @discardableResult
    func renameBookmarkFolder(
        id: UUID,
        name: String,
        parentFolderID: UUID?? = nil
    ) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = bookmarkFolders.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let targetParentID = parentFolderID ?? bookmarkFolders[index].parentFolderID
        if let targetParentID {
            guard bookmarkFolders.contains(where: { $0.id == targetParentID }),
                  !isBookmarkFolder(targetParentID, descendantOf: id) else {
                return false
            }
        }
        let duplicateExists = bookmarkFolders.contains {
            $0.id != id
                && $0.parentFolderID == targetParentID
                && $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        guard !duplicateExists else { return false }

        return persistConfigurationMutation {
            bookmarkFolders[index].name = trimmed
            bookmarkFolders[index].parentFolderID = targetParentID
            return true
        }
    }

    @discardableResult
    func deleteBookmarkFolder(id: UUID) -> Bool {
        guard let deletedFolder = bookmarkFolders.first(where: { $0.id == id }) else {
            return false
        }
        let promotedParentID = deletedFolder.parentFolderID
        return persistConfigurationMutation {
            for index in bookmarkFolders.indices where bookmarkFolders[index].parentFolderID == id {
                bookmarkFolders[index].parentFolderID = promotedParentID
            }
            for index in bookmarks.indices where bookmarks[index].folderID == id {
                bookmarks[index].folderID = promotedParentID
            }
            bookmarkFolders.removeAll(where: { $0.id == id })
            normalizeBookmarkFoldersInPlace()
            return true
        }
    }

    func exportBookmarksHTML(now: Date = Date()) -> String {
        BookmarkHTMLCodec.exportHTML(
            folders: orderedBookmarkFolders,
            bookmarks: orderedBookmarks,
            now: now
        )
    }

    @discardableResult
    func importBookmarksHTML(
        _ html: String,
        now: Date = Date()
    ) -> (foldersAdded: Int, bookmarksAdded: Int) {
        let document = BookmarkHTMLCodec.parseHTML(html)
        var foldersAdded = 0
        var bookmarksAdded = 0

        let saved = persistConfigurationMutation {
            for parsedFolder in document.folders {
                importParsedBookmarkFolder(
                    parsedFolder,
                    parentFolderID: nil,
                    now: now,
                    foldersAdded: &foldersAdded,
                    bookmarksAdded: &bookmarksAdded
                )
            }
            for rootBookmark in document.rootBookmarks {
                appendImportedBookmarkIfNew(
                    rootBookmark,
                    folderID: nil,
                    now: now,
                    bookmarksAdded: &bookmarksAdded
                )
            }

            if foldersAdded > 0 {
                normalizeBookmarkFoldersInPlace()
            }
            if bookmarksAdded > 0 {
                normalizeBookmarksInPlace()
            }
            return foldersAdded > 0 || bookmarksAdded > 0
        }

        return saved ? (foldersAdded, bookmarksAdded) : (0, 0)
    }

    private func upsertImportedBookmarkFolder(
        name: String,
        parentFolderID: UUID?,
        createdAt: Date?,
        now: Date,
        foldersAdded: inout Int
    ) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? "Imported Folder" : trimmed
        if let existing = bookmarkFolders.first(where: {
            $0.parentFolderID == parentFolderID
                && $0.name.compare(resolved, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            return existing.id
        }
        let created = BookmarkFolder(
            id: UUID(),
            parentFolderID: parentFolderID,
            name: resolved,
            order: bookmarkFolders.count,
            createdAt: createdAt ?? now
        )
        bookmarkFolders.append(created)
        foldersAdded += 1
        return created.id
    }

    private func appendImportedBookmarkIfNew(
        _ item: ParsedBookmarkItem,
        folderID: UUID?,
        now: Date,
        bookmarksAdded: inout Int
    ) {
        guard WebAppURL.isSafe(item.url) else { return }
        let urlKey = item.url.absoluteString.lowercased()
        let alreadyExists = bookmarks.contains {
            $0.folderID == folderID && $0.url.absoluteString.lowercased() == urlKey
        }
        guard !alreadyExists else { return }
        let trimmedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedTitle.isEmpty
            ? WebAppURL.defaultDisplayName(for: item.url)
            : trimmedTitle
        let createdAt = item.createdAt ?? now
        bookmarks.append(
            BookmarkItem(
                id: UUID(),
                folderID: folderID,
                order: bookmarks.count,
                title: title,
                url: item.url,
                notes: item.notes,
                preferredWebsiteMode: nil,
                browserProfileID: nil,
                createdAt: createdAt,
                updatedAt: createdAt
            )
        )
        bookmarksAdded += 1
    }

    private func importParsedBookmarkFolder(
        _ parsed: ParsedBookmarkFolder,
        parentFolderID: UUID?,
        now: Date,
        foldersAdded: inout Int,
        bookmarksAdded: inout Int
    ) {
        let folderID = upsertImportedBookmarkFolder(
            name: parsed.name,
            parentFolderID: parentFolderID,
            createdAt: parsed.createdAt,
            now: now,
            foldersAdded: &foldersAdded
        )
        for sub in parsed.folders {
            importParsedBookmarkFolder(
                sub,
                parentFolderID: folderID,
                now: now,
                foldersAdded: &foldersAdded,
                bookmarksAdded: &bookmarksAdded
            )
        }
        for bookmark in parsed.bookmarks {
            appendImportedBookmarkIfNew(
                bookmark,
                folderID: folderID,
                now: now,
                bookmarksAdded: &bookmarksAdded
            )
        }
    }

    @discardableResult
    func addBookmark(
        title: String,
        url: URL,
        folderID: UUID? = nil,
        notes: String? = nil,
        preferredWebsiteMode: WebsiteMode? = nil,
        browserProfileID: UUID? = nil,
        now: Date = Date()
    ) -> BookmarkItem? {
        guard WebAppURL.isSafe(url) else { return nil }
        if let folderID, !bookmarkFolders.contains(where: { $0.id == folderID }) {
            return nil
        }
        if let browserProfileID, !browserProfiles.contains(where: { $0.id == browserProfileID }) {
            return nil
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmedTitle.isEmpty ? WebAppURL.defaultDisplayName(for: url) : trimmedTitle

        let bookmark = BookmarkItem(
            id: UUID(),
            folderID: folderID,
            order: orderedBookmarks.count,
            title: resolvedTitle,
            url: url,
            notes: notes,
            preferredWebsiteMode: preferredWebsiteMode,
            browserProfileID: browserProfileID,
            createdAt: now,
            updatedAt: now
        )
        guard persistConfigurationMutation({
            bookmarks.append(bookmark)
            normalizeBookmarksInPlace()
            return true
        }) else {
            return nil
        }
        return bookmarks.first(where: { $0.id == bookmark.id })
    }

    @discardableResult
    func updateBookmark(
        id: UUID,
        title: String,
        url: URL,
        folderID: UUID?,
        notes: String? = nil,
        preferredWebsiteMode: WebsiteMode? = nil,
        browserProfileID: UUID? = nil,
        now: Date = Date()
    ) -> Bool {
        guard WebAppURL.isSafe(url),
              let index = bookmarks.firstIndex(where: { $0.id == id }) else {
            return false
        }
        if let folderID, !bookmarkFolders.contains(where: { $0.id == folderID }) {
            return false
        }
        if let browserProfileID, !browserProfiles.contains(where: { $0.id == browserProfileID }) {
            return false
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }

        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return persistConfigurationMutation {
            bookmarks[index].title = trimmedTitle
            bookmarks[index].url = url
            bookmarks[index].folderID = folderID
            bookmarks[index].notes = (trimmedNotes?.isEmpty == false) ? trimmedNotes : nil
            bookmarks[index].preferredWebsiteMode = preferredWebsiteMode
            bookmarks[index].browserProfileID = browserProfileID
            bookmarks[index].updatedAt = now
            return true
        }
    }

    @discardableResult
    func deleteBookmark(id: UUID) -> Bool {
        guard bookmarks.contains(where: { $0.id == id }) else { return false }
        return persistConfigurationMutation {
            bookmarks.removeAll(where: { $0.id == id })
            normalizeBookmarksInPlace()
            return true
        }
    }

    private func isGroupNameAvailable(
        _ trimmedName: String,
        excludingGroupID: UUID?,
        treatDefaultExclusion: Bool
    ) -> Bool {
        guard !trimmedName.isEmpty else { return false }
        if !treatDefaultExclusion,
           defaultGroupPresentation.name.compare(
               trimmedName,
               options: [.caseInsensitive, .diacriticInsensitive]
           ) == .orderedSame {
            return false
        }
        return !groups.contains { group in
            group.id != excludingGroupID
                && group.name.compare(
                    trimmedName,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame
        }
    }

    private func normalizeGroupsInPlace() {
        groups = orderedGroups.enumerated().map { index, group in
            var copy = group
            copy.order = index
            return copy
        }
    }

    private func normalizeBookmarkFoldersInPlace() {
        bookmarkFolders = orderedBookmarkFolders.enumerated().map { index, folder in
            var copy = folder
            copy.order = index
            return copy
        }
    }

    private func normalizeBookmarksInPlace() {
        bookmarks = orderedBookmarks.enumerated().map { index, bookmark in
            var copy = bookmark
            copy.order = index
            return copy
        }
    }

    private func touchLastUsed(id: UUID?, now: Date = Date()) {
        guard let id,
              let index = profiles.firstIndex(where: { $0.id == id }) else {
            return
        }
        profiles[index].lastUsedAt = now
    }

    private func normalizeInPlace() {
        profiles = Self.normalizedProfiles(profiles)
    }

    private static func normalizedProfiles(_ profiles: [WebAppProfile]) -> [WebAppProfile] {
        let sorted = profiles.sorted { lhs, rhs in
            if lhs.order == rhs.order {
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.order < rhs.order
        }

        var seenIDs = Set<UUID>()
        let unique = sorted.filter { profile in
            seenIDs.insert(profile.id).inserted
        }

        return reindexedProfilesPreservingSequence(unique)
    }

    private static func reindexedProfilesPreservingSequence(
        _ profiles: [WebAppProfile]
    ) -> [WebAppProfile] {
        profiles.enumerated().map { index, profile in
            var reindexed = profile
            reindexed.order = index
            reindexed.renderingProfile = profile.renderingProfile.normalized()
            return reindexed
        }
    }

    private func canAddBrowserProfile(_ browserProfile: BrowserProfile) -> Bool {
        var candidateProfiles = browserProfiles
        candidateProfiles.append(browserProfile)
        do {
            try BrowserProfileValidation.validateMetadata(
                candidateProfiles,
                defaultDisplayName: defaultBrowserProfilePresentation.name,
                includeDefaultProfile: !isDefaultBrowserProfileDeleted
            )
            return true
        } catch {
            return false
        }
    }

    /// User-authored configuration is transactional: the in-memory model is
    /// published only if the corresponding durable write succeeds. A failed
    /// write restores the exact previous model so the UI cannot report a change
    /// that will disappear on relaunch.
    private func persistConfigurationMutation(
        notifyOnSuccess: Bool = true,
        _ mutation: () -> Bool
    ) -> Bool {
        let previousBrowserProfiles = browserProfiles
        let previousDefaultBrowserProfilePresentation = defaultBrowserProfilePresentation
        let previousIsDefaultBrowserProfileDeleted = isDefaultBrowserProfileDeleted
        let previousProfiles = profiles
        let previousActiveTabID = activeTabID
        let previousDefaultGroupPresentation = defaultGroupPresentation
        let previousGroups = groups
        let previousActiveGroupID = activeGroupID
        let previousBookmarkFolders = bookmarkFolders
        let previousBookmarks = bookmarks
        let previousLastActiveTabIDByGroup = lastActiveTabIDByGroup
        guard mutation() else { return false }

        do {
            try repository.save(currentState())
            pendingRuntimePersistenceWorkItem?.cancel()
            pendingRuntimePersistenceWorkItem = nil
            hasPendingRuntimePersistence = false
        } catch {
            browserProfiles = previousBrowserProfiles
            defaultBrowserProfilePresentation = previousDefaultBrowserProfilePresentation
            isDefaultBrowserProfileDeleted = previousIsDefaultBrowserProfileDeleted
            profiles = previousProfiles
            activeTabID = previousActiveTabID
            defaultGroupPresentation = previousDefaultGroupPresentation
            groups = previousGroups
            activeGroupID = previousActiveGroupID
            bookmarkFolders = previousBookmarkFolders
            bookmarks = previousBookmarks
            lastActiveTabIDByGroup = previousLastActiveTabIDByGroup
            onPersistenceFailure?()
            return false
        }

        if notifyOnSuccess {
            onChange?()
        }
        return true
    }

    /// Selection/last-used state is runtime interaction. Preserve the live UI
    /// even if its relaunch snapshot cannot be written on this particular turn.
    private func persistRuntimeAndNotify() {
        persistRuntimeState()
        onChange?()
    }

    private func persistRuntimeState() {
        guard runtimePersistenceDebounceInterval > 0 else {
            pendingRuntimePersistenceWorkItem?.cancel()
            pendingRuntimePersistenceWorkItem = nil
            hasPendingRuntimePersistence = false
            try? repository.save(currentState())
            return
        }
        hasPendingRuntimePersistence = true
        pendingRuntimePersistenceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.flushPendingRuntimePersistence()
            }
        }
        pendingRuntimePersistenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + runtimePersistenceDebounceInterval,
            execute: workItem
        )
    }

    func flushPendingRuntimePersistence() {
        pendingRuntimePersistenceWorkItem?.cancel()
        pendingRuntimePersistenceWorkItem = nil
        guard hasPendingRuntimePersistence else { return }
        hasPendingRuntimePersistence = false
        try? repository.save(currentState())
    }

    private func currentState() -> StoredWebAppState {
        StoredWebAppState(
            version: StoredWebAppState.currentVersion,
            browserProfiles: browserProfiles,
            defaultBrowserProfilePresentation: defaultBrowserProfilePresentation,
            isDefaultBrowserProfileDeleted: isDefaultBrowserProfileDeleted,
            profiles: orderedProfiles,
            lastActiveTabID: activeTabID,
            defaultGroupPresentation: defaultGroupPresentation,
            groups: orderedGroups,
            activeGroupID: activeGroupID,
            bookmarkFolders: orderedBookmarkFolders,
            bookmarks: orderedBookmarks
        )
    }
}
