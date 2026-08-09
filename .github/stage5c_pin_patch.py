from pathlib import Path

panel = Path('FloatTabs/Panel/PanelController.swift')
text = panel.read_text()
old_observer = '''        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: NSApp
        )'''
new_observer = '''        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidActivateApplication(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )'''
if old_observer not in text:
    raise SystemExit('old application observer not found')
text = text.replace(old_observer, new_observer)

old_handler = '''    @objc private func applicationDidResignActive(_ notification: Notification) {
        guard Self.shouldAutoHide(panelIsVisible: panel.isVisible, isPinned: isPinned) else {
            return
        }
        autoHideAfterApplicationDeactivation()
    }'''
new_handler = '''    static func shouldAutoHideForActivatedApplication(
        panelIsVisible: Bool,
        isPinned: Bool,
        activatedProcessIdentifier: pid_t,
        ownProcessIdentifier: pid_t
    ) -> Bool {
        panelIsVisible
            && !isPinned
            && activatedProcessIdentifier != ownProcessIdentifier
    }

    @objc private func workspaceDidActivateApplication(_ notification: Notification) {
        guard let activatedApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
              Self.shouldAutoHideForActivatedApplication(
                panelIsVisible: panel.isVisible,
                isPinned: isPinned,
                activatedProcessIdentifier: activatedApplication.processIdentifier,
                ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier
              ) else {
            return
        }
        autoHideAfterApplicationDeactivation()
    }'''
if old_handler not in text:
    raise SystemExit('old application handler not found')
panel.write_text(text.replace(old_handler, new_handler))

hotkey = Path('FloatTabs/Hotkeys/GlobalHotkeyController.swift')
text = hotkey.read_text()
old = 'initial: .init(.backtick, modifiers: [.command])'
new = 'initial: .init(.space, modifiers: [.option])'
if old not in text:
    raise SystemExit('current backtick shortcut declaration not found')
hotkey.write_text(text.replace(old, new))

tests = Path('FloatTabsTests/ExternalShellTests.swift')
text = tests.read_text()
needle = '''    func testPanelAutoHideDecisionRespectsPin() {
        XCTAssertTrue(PanelController.shouldAutoHide(panelIsVisible: true, isPinned: false))
        XCTAssertFalse(PanelController.shouldAutoHide(panelIsVisible: true, isPinned: true))'''
if needle not in text:
    raise SystemExit('auto-hide test anchor not found')
insert = '''    func testWorkspaceAutoHideRequiresAnotherFrontmostApplication() {
        XCTAssertTrue(
            PanelController.shouldAutoHideForActivatedApplication(
                panelIsVisible: true,
                isPinned: false,
                activatedProcessIdentifier: 200,
                ownProcessIdentifier: 100
            )
        )
        XCTAssertFalse(
            PanelController.shouldAutoHideForActivatedApplication(
                panelIsVisible: true,
                isPinned: true,
                activatedProcessIdentifier: 200,
                ownProcessIdentifier: 100
            )
        )
        XCTAssertFalse(
            PanelController.shouldAutoHideForActivatedApplication(
                panelIsVisible: true,
                isPinned: false,
                activatedProcessIdentifier: 100,
                ownProcessIdentifier: 100
            )
        )
    }

'''
tests.write_text(text.replace(needle, insert + needle))
