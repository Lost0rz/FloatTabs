from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f"cleanup anchor not found: {path}: {old[:80]!r}")
    file.write_text(text.replace(old, new, 1))


replace_once(
    "FloatTabs/Panel/PanelController.swift",
    '''        webViewPool.onResidentSetChange = { [weak self] in
        self?.synchronizeResidentIndicators()
    }
    tabStore.onChange = { [weak self] in
        self?.synchronizeSlotState()
    }
    synchronizeSlotState()

    }
''',
    '''        webViewPool.onResidentSetChange = { [weak self] in
            self?.synchronizeResidentIndicators()
        }
        tabStore.onChange = { [weak self] in
            self?.synchronizeSlotState()
        }
        synchronizeSlotState()
    }
''',
)

replace_once(
    "FloatTabs/Panel/PanelController.swift",
    '''        var snapshot: [String: Any] = [
        "visible": isVisible,
        "pinned": isPinned,
        "profiles": profiles,
        "resident_slot_count": webViewPool.count,
        "resident_slot_ids": webViewPool.residentSlotIDs.map(\\.uuidString).sorted(),
        "pending_cold_release_count": slotLifecycleCoordinator.pendingColdReleaseCount,
        "pending_warm_release_count": slotLifecycleCoordinator.pendingWarmReleaseCount,
        "media_protected_slot_ids": slotLifecycleCoordinator.mediaProtectedIDs.map(\\.uuidString).sorted(),
        "hidden_active_grace_pending": slotLifecycleCoordinator.isHiddenActiveGracePending,
    ]
    snapshot["active_slot_id"] = tabStore.activeTabID?.uuidString ?? NSNull()
''',
    '''        var snapshot: [String: Any] = [
            "visible": isVisible,
            "pinned": isPinned,
            "profiles": profiles,
            "resident_slot_count": webViewPool.count,
            "resident_slot_ids": webViewPool.residentSlotIDs.map(\\.uuidString).sorted(),
            "pending_cold_release_count": slotLifecycleCoordinator.pendingColdReleaseCount,
            "pending_warm_release_count": slotLifecycleCoordinator.pendingWarmReleaseCount,
            "media_protected_slot_ids": slotLifecycleCoordinator.mediaProtectedIDs.map(\\.uuidString).sorted(),
            "hidden_active_grace_pending": slotLifecycleCoordinator.isHiddenActiveGracePending,
        ]
        snapshot["active_slot_id"] = tabStore.activeTabID?.uuidString ?? NSNull()
''',
)

replace_once(
    "FloatTabs/Panel/PanelController.swift",
    '''        rootView.externalControlZoneView.apply(
        profiles: orderedProfiles,
        activeTabID: tabStore.activeTabID
    )
    synchronizeResidentIndicators()
    slotLifecycleCoordinator.reconcile(profiles: orderedProfiles)


        guard let activeProfile = tabStore.activeProfile else {
''',
    '''        rootView.externalControlZoneView.apply(
            profiles: orderedProfiles,
            activeTabID: tabStore.activeTabID
        )
        synchronizeResidentIndicators()
        slotLifecycleCoordinator.reconcile(profiles: orderedProfiles)

        guard let activeProfile = tabStore.activeProfile else {
''',
)

replace_once(
    "FloatTabs/Panel/PanelController.swift",
    '''            lastSynchronizedActiveID = nil
        lastSynchronizedActiveProfile = nil
        rootView.webPanelContainerView.showEmptyState()
        synchronizeResidentIndicators()
        onSelectedSlotNameChange?(nil)
        return

        }
''',
    '''            lastSynchronizedActiveID = nil
            lastSynchronizedActiveProfile = nil
            rootView.webPanelContainerView.showEmptyState()
            synchronizeResidentIndicators()
            onSelectedSlotNameChange?(nil)
            return
        }
''',
)

replace_once(
    "FloatTabs/App/AppCoordinator.swift",
    '''        statusItemController = StatusItemController(
        onToggle: { [weak self] in self?.toggleFloatTabs() },
        isVisible: { [weak self] in self?.panelController.isVisible ?? false },
        onQuit: { NSApp.terminate(nil) }
    )
    statusItemController?.setActiveWebAppName(panelController.selectedSlotName)
    panelController.onSelectedSlotNameChange = { [weak self] name in
        self?.statusItemController?.setActiveWebAppName(name)
    }

    globalHotkeyController = GlobalHotkeyController(
''',
    '''        statusItemController = StatusItemController(
            onToggle: { [weak self] in self?.toggleFloatTabs() },
            isVisible: { [weak self] in self?.panelController.isVisible ?? false },
            onQuit: { NSApp.terminate(nil) }
        )
        statusItemController?.setActiveWebAppName(panelController.selectedSlotName)
        panelController.onSelectedSlotNameChange = { [weak self] name in
            self?.statusItemController?.setActiveWebAppName(name)
        }

        globalHotkeyController = GlobalHotkeyController(
''',
)
