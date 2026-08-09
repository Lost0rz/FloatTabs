from pathlib import Path

panel = Path('FloatTabs/Panel/PanelController.swift')
text = panel.read_text()

old_property = '''    private var followPreferredSize: Bool
    private(set) var isPinned = false
'''
new_property = '''    private var followPreferredSize: Bool
    private(set) var isPinned = false
    private var externalMouseMonitor: Any?
'''
if old_property not in text:
    raise SystemExit('PanelController property anchor not found')
text = text.replace(old_property, new_property, 1)

old_observer = '''        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidActivateApplication(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        tabStore.onChange = { [weak self] in
'''
new_observer = '''        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidActivateApplication(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        externalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleExternalMouseDown()
            }
        }

        tabStore.onChange = { [weak self] in
'''
if old_observer not in text:
    raise SystemExit('PanelController observer anchor not found')
text = text.replace(old_observer, new_observer, 1)

old_helper = '''    static func shouldAutoHideForActivatedApplication(
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
'''
new_helper = '''    static func shouldAutoHideForActivatedApplication(
        panelIsVisible: Bool,
        isPinned: Bool,
        activatedProcessIdentifier: pid_t,
        ownProcessIdentifier: pid_t
    ) -> Bool {
        panelIsVisible
            && !isPinned
            && activatedProcessIdentifier != ownProcessIdentifier
    }

    static func shouldAutoHideForExternalMouseDown(
        panelIsVisible: Bool,
        isPinned: Bool
    ) -> Bool {
        shouldAutoHide(panelIsVisible: panelIsVisible, isPinned: isPinned)
    }

    private func handleExternalMouseDown() {
        guard Self.shouldAutoHideForExternalMouseDown(
            panelIsVisible: panel.isVisible,
            isPinned: isPinned
        ) else {
            return
        }
        autoHideAfterApplicationDeactivation()
    }

    @objc private func workspaceDidActivateApplication(_ notification: Notification) {
'''
if old_helper not in text:
    raise SystemExit('PanelController helper anchor not found')
text = text.replace(old_helper, new_helper, 1)
panel.write_text(text)

tests = Path('FloatTabsTests/ExternalShellTests.swift')
text = tests.read_text()
anchor = '''    func testPanelAutoHideDecisionRespectsPin() {
        XCTAssertTrue(PanelController.shouldAutoHide(panelIsVisible: true, isPinned: false))
        XCTAssertFalse(PanelController.shouldAutoHide(panelIsVisible: true, isPinned: true))
        XCTAssertFalse(PanelController.shouldAutoHide(panelIsVisible: false, isPinned: false))
    }

'''
insert = '''    func testExternalMouseAutoHideDoesNotRequireFrontmostApplicationChange() {
        XCTAssertTrue(
            PanelController.shouldAutoHideForExternalMouseDown(
                panelIsVisible: true,
                isPinned: false
            )
        )
        XCTAssertFalse(
            PanelController.shouldAutoHideForExternalMouseDown(
                panelIsVisible: true,
                isPinned: true
            )
        )
        XCTAssertFalse(
            PanelController.shouldAutoHideForExternalMouseDown(
                panelIsVisible: false,
                isPinned: false
            )
        )
    }

'''
if anchor not in text:
    raise SystemExit('ExternalShellTests auto-hide anchor not found')
text = text.replace(anchor, insert + anchor, 1)
tests.write_text(text)
