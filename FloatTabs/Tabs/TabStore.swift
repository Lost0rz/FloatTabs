import Foundation

@MainActor
final class TabStore {
    private(set) var profiles: [WebAppProfile]
    private(set) var activeTabID: UUID?

    var onChange: (() -> Void)?

    private let repository: any ProfileRepositoryProtocol

    var orderedProfiles: [WebAppProfile] {
        profiles.sorted { lhs, rhs in
            if lhs.order == rhs.order {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.order < rhs.order
        }
    }

    var activeProfile: WebAppProfile? {
        guard let activeTabID else { return nil }
        return profiles.first(where: { $0.id == activeTabID })
    }

    init(repository: any ProfileRepositoryProtocol = ProfileRepository()) {
        self.repository = repository

        let loadedState: StoredWebAppState
        let didLoadPersistedState: Bool
        do {
            loadedState = try repository.load()
            didLoadPersistedState = true
        } catch {
            loadedState = .empty
            didLoadPersistedState = false
        }

        let normalized = Self.normalizedProfiles(loadedState.profiles)
        profiles = normalized

        if let restoredID = loadedState.lastActiveTabID,
           normalized.contains(where: { $0.id == restoredID }) {
            activeTabID = restoredID
        } else {
            activeTabID = normalized.first?.id
        }

        if didLoadPersistedState {
            let repaired = StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                profiles: normalized,
                lastActiveTabID: activeTabID
            )
            if repaired != loadedState {
                try? repository.save(repaired)
            }
        }
    }

    @discardableResult
    func add(
        name: String? = nil,
        homeURL: URL,
        homeURLSchemeWasInferred: Bool = false,
        renderingProfile: WebRenderingProfile = .canonicalDefault,
        now: Date = Date()
    ) -> WebAppProfile? {
        guard WebAppURL.isSafe(homeURL) else { return nil }
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedName = trimmedName.isEmpty
            ? WebAppURL.defaultDisplayName(for: homeURL)
            : trimmedName

        let profile = WebAppProfile(
            order: orderedProfiles.count,
            name: resolvedName,
            homeURL: homeURL,
            currentURL: homeURL,
            homeURLSchemeWasInferred: homeURLSchemeWasInferred,
            renderingProfile: renderingProfile.normalized(),
            createdAt: now,
            lastUsedAt: now
        )

        profiles.append(profile)
        normalizeInPlace()
        activeTabID = profile.id
        persistAndNotify()
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
            order: orderedProfiles.count,
            name: trimmedName,
            homeURL: homeURL,
            currentURL: homeURL,
            homeURLSchemeWasInferred: false,
            renderingProfile: source.renderingProfile.normalized(),
            residencyPolicy: source.residencyPolicy,
            backgroundMediaPolicy: source.backgroundMediaPolicy,
            createdAt: now,
            lastUsedAt: now
        )

        profiles.append(profile)
        normalizeInPlace()
        activeTabID = profile.id
        persistAndNotify()
        return profiles.first(where: { $0.id == profile.id })
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
        persistAndNotify()
        return true
    }

    @discardableResult
    func updateRenderingProfile(id: UUID, renderingProfile: WebRenderingProfile) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        let normalized = renderingProfile.normalized()
        guard profiles[index].renderingProfile != normalized else { return true }
        profiles[index].renderingProfile = normalized
        persistAndNotify()
        return true
    }

    @discardableResult
    func updateResourcePolicy(
        id: UUID,
        residencyPolicy: SlotResidencyPolicy? = nil,
        backgroundMediaPolicy: BackgroundMediaPolicy? = nil
    ) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        var changed = false

        if let residencyPolicy, profiles[index].residencyPolicy != residencyPolicy {
            profiles[index].residencyPolicy = residencyPolicy
            changed = true
        }
        if let backgroundMediaPolicy,
           profiles[index].backgroundMediaPolicy != backgroundMediaPolicy {
            profiles[index].backgroundMediaPolicy = backgroundMediaPolicy
            changed = true
        }

        guard changed else { return true }
        persistAndNotify()
        return true
    }

    @discardableResult
    func updatePreferredViewport(id: UUID, size: CGSize) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        let updated = profiles[index].renderingProfile.settingViewport(size)
        guard profiles[index].renderingProfile != updated else { return true }
        profiles[index].renderingProfile = updated
        persistAndNotify()
        return true
    }

    @discardableResult
    func updateZoom(id: UUID, zoom: CGFloat) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        let updated = profiles[index].renderingProfile.settingZoom(zoom)
        guard profiles[index].renderingProfile != updated else { return true }
        profiles[index].renderingProfile = updated
        persistAndNotify()
        return true
    }

    @discardableResult
    func rename(id: UUID, name: String) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        profiles[index].name = trimmedName
        persistAndNotify()
        return true
    }

    @discardableResult
    func remove(id: UUID) -> Bool {
        let orderedBeforeRemoval = orderedProfiles
        guard let removedIndex = orderedBeforeRemoval.firstIndex(where: { $0.id == id }) else {
            return false
        }

        profiles.removeAll(where: { $0.id == id })
        normalizeInPlace()

        if activeTabID == id {
            let remaining = orderedProfiles
            if remaining.isEmpty {
                activeTabID = nil
            } else {
                let neighborIndex = min(removedIndex, remaining.count - 1)
                activeTabID = remaining[neighborIndex].id
                touchLastUsed(id: activeTabID)
            }
        } else if let activeTabID,
                  !profiles.contains(where: { $0.id == activeTabID }) {
            self.activeTabID = orderedProfiles.first?.id
        }

        persistAndNotify()
        return true
    }

    @discardableResult
    func move(id: UUID, toIndex proposedIndex: Int) -> Bool {
        var ordered = orderedProfiles
        guard let sourceIndex = ordered.firstIndex(where: { $0.id == id }) else { return false }
        guard ordered.count > 1 else { return true }

        let destination = min(max(proposedIndex, 0), ordered.count - 1)
        if sourceIndex == destination { return true }

        let moved = ordered.remove(at: sourceIndex)
        ordered.insert(moved, at: destination)

        // `ordered` is now the user's intended sequence. Do not feed it back
        // through `normalizedProfiles`, which sorts by the pre-move order values
        // and would undo the reorder. Reindex this sequence in place instead.
        profiles = Self.reindexedProfilesPreservingSequence(ordered)
        persistAndNotify()
        return true
    }

    @discardableResult
    func select(id: UUID, now: Date = Date()) -> Bool {
        guard profiles.contains(where: { $0.id == id }) else { return false }
        activeTabID = id
        touchLastUsed(id: id, now: now)
        persistAndNotify()
        return true
    }

    @discardableResult
    func selectNext(now: Date = Date()) -> WebAppProfile? {
        let ordered = orderedProfiles
        guard !ordered.isEmpty else {
            activeTabID = nil
            return nil
        }

        let nextIndex: Int
        if let activeTabID,
           let currentIndex = ordered.firstIndex(where: { $0.id == activeTabID }) {
            nextIndex = (currentIndex + 1) % ordered.count
        } else {
            nextIndex = 0
        }

        _ = select(id: ordered[nextIndex].id, now: now)
        return activeProfile
    }

    @discardableResult
    func selectPrevious(now: Date = Date()) -> WebAppProfile? {
        let ordered = orderedProfiles
        guard !ordered.isEmpty else {
            activeTabID = nil
            return nil
        }

        let previousIndex: Int
        if let activeTabID,
           let currentIndex = ordered.firstIndex(where: { $0.id == activeTabID }) {
            previousIndex = (currentIndex - 1 + ordered.count) % ordered.count
        } else {
            previousIndex = ordered.count - 1
        }

        _ = select(id: ordered[previousIndex].id, now: now)
        return activeProfile
    }

    func slotByKeyboardIndex(_ keyboardIndex: Int) -> WebAppProfile? {
        guard (1...9).contains(keyboardIndex) else { return nil }
        let ordered = orderedProfiles
        let index = keyboardIndex - 1
        guard ordered.indices.contains(index) else { return nil }
        return ordered[index]
    }

    func updateCurrentURL(id: UUID, url: URL) {
        guard WebAppURL.isSafe(url),
              let index = profiles.firstIndex(where: { $0.id == id }),
              profiles[index].currentURL != url else {
            return
        }

        profiles[index].currentURL = url
        persist()
    }

    func storedStateSnapshot() -> StoredWebAppState {
        StoredWebAppState(
            version: StoredWebAppState.currentVersion,
            profiles: orderedProfiles,
            lastActiveTabID: activeTabID
        )
    }

    @discardableResult
    func replaceStoredState(_ state: StoredWebAppState) -> Bool {
        guard state.version == StoredWebAppState.currentVersion else { return false }

        let sanitized = state.sanitizedForUse()
        let normalized = Self.normalizedProfiles(sanitized.profiles)
        let restoredActiveID: UUID?
        if let requested = sanitized.lastActiveTabID,
           normalized.contains(where: { $0.id == requested }) {
            restoredActiveID = requested
        } else {
            restoredActiveID = normalized.first?.id
        }

        let replacement = StoredWebAppState(
            version: StoredWebAppState.currentVersion,
            profiles: normalized,
            lastActiveTabID: restoredActiveID
        )

        do {
            try repository.save(replacement)
        } catch {
            return false
        }

        profiles = normalized
        activeTabID = restoredActiveID
        onChange?()
        return true
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

    private func persistAndNotify() {
        persist()
        onChange?()
    }

    private func persist() {
        let state = StoredWebAppState(
            version: StoredWebAppState.currentVersion,
            profiles: orderedProfiles,
            lastActiveTabID: activeTabID
        )
        try? repository.save(state)
    }
}
