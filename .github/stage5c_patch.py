from pathlib import Path

ROOT = Path('.')


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding='utf-8')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected exactly one match, got {count}')
    return text.replace(old, new, 1)


# 1) Inactive Hot keeps its independent host attached and frame-frozen, but hides presentation.
path = 'FloatTabs/Web/WebViewContainer.swift'
text = read(path)
text = replace_once(
    text,
'''        case .hot:
            if let host = hotHostViews[slotID] {
                // Freeze the outgoing Hot viewport before another Slot changes
                // the panel size. Only an active Hot host follows live resizing.
                host.autoresizingMask = []
            }
''',
'''        case .hot:
            if let host = hotHostViews[slotID] {
                // Freeze the outgoing Hot viewport before another Slot changes
                // the panel size. Only an active Hot host follows live resizing.
                //
                // Keep the independent host and WKWebView attached so Hot keeps
                // its DOM/SPA/runtime state, but stop presenting an inactive Hot
                // page. Reactivation unhides this exact same host in `showHot`.
                host.autoresizingMask = []
                host.isHidden = true
            }
''',
    'hide inactive Hot presentation',
)
write(path, text)


# 2) App-local pin shortcut.
path = 'FloatTabs/Hotkeys/AppCommandController.swift'
text = read(path)
text = replace_once(
    text,
'''    case quickURL
    case returnHome
}''',
'''    case quickURL
    case returnHome
    case togglePin
}''',
    'AppCommand togglePin case',
)
text = replace_once(
    text,
'''        if flags == [.command, .shift],
           let characters,
           characters.lowercased() == "h" {
            return .returnHome
        }
''',
'''        if flags == [.command, .shift], let characters {
            switch characters.lowercased() {
            case "h":
                return .returnHome
            case "p":
                return .togglePin
            default:
                break
            }
        }
''',
    'AppCommand CmdShift handling',
)
write(path, text)


# 3) Pin control in the existing external control zone.
path = 'FloatTabs/UI/ExternalTabRail.swift'
text = read(path)
text = replace_once(
    text,
'''    static let systemControlNormalWidth: CGFloat = 34
    static let systemControlHoverWidth: CGFloat = 54
    static let systemControlBottomOffset: CGFloat = 18
''',
'''    static let systemControlNormalWidth: CGFloat = 34
    static let systemControlHoverWidth: CGFloat = 54
    static let systemControlBottomOffset: CGFloat = 18
    static let systemControlGap: CGFloat = 4
''',
    'system control gap metric',
)
text = replace_once(
    text,
'''    var onReorder: ((UUID, Int) -> Void)?
    var onCurrentControls: (() -> Void)?
''',
'''    var onReorder: ((UUID, Int) -> Void)?
    var onCurrentControls: (() -> Void)?
    var onTogglePin: (() -> Void)?
''',
    'onTogglePin callback',
)
text = replace_once(
    text,
'''    private let addControl = AddWebAppControl()
    private let currentControls = CurrentWebAppControl()
''',
'''    private let addControl = AddWebAppControl()
    private let currentControls = CurrentWebAppControl()
    private let pinControl = PinPanelControl()
''',
    'pin control property',
)
text = replace_once(
    text,
'''        addSubview(addControl)
        addSubview(currentControls)
        addControl.onActivate = { [weak self] in self?.onAdd?() }
        currentControls.onActivate = { [weak self] in self?.onCurrentControls?() }
''',
'''        addSubview(addControl)
        addSubview(currentControls)
        addSubview(pinControl)
        addControl.onActivate = { [weak self] in self?.onAdd?() }
        currentControls.onActivate = { [weak self] in self?.onCurrentControls?() }
        pinControl.onActivate = { [weak self] in self?.onTogglePin?() }
''',
    'pin control setup',
)
text = replace_once(
    text,
'''        currentControls.onPointerMoved = { [weak self] event in
            self?.updateDockPointer(with: event)
        }
''',
'''        currentControls.onPointerMoved = { [weak self] event in
            self?.updateDockPointer(with: event)
        }
        pinControl.onPointerMoved = { [weak self] event in
            self?.updateDockPointer(with: event)
        }
''',
    'pin pointer movement',
)
text = replace_once(
    text,
'''    func setAddEditorOpen(_ isOpen: Bool) {
        addControl.isEditorOpen = isOpen
        layoutControls(animated: true, duration: ExternalTabMetrics.dockSettleDuration)
    }
''',
'''    func setAddEditorOpen(_ isOpen: Bool) {
        addControl.isEditorOpen = isOpen
        layoutControls(animated: true, duration: ExternalTabMetrics.dockSettleDuration)
    }

    func setPinned(_ isPinned: Bool) {
        pinControl.isPinned = isPinned
    }
''',
    'setPinned seam',
)
text = replace_once(
    text,
'''    var currentControlsFrame: NSRect {
        currentControls.frame
    }
''',
'''    var currentControlsFrame: NSRect {
        currentControls.frame
    }

    var pinControlFrame: NSRect {
        pinControl.frame
    }
''',
    'pin frame test seam',
)
old_layout = '''            let systemY = max(
                self.bounds.height
                    - ExternalTabMetrics.systemControlBottomOffset
                    - ExternalTabMetrics.systemControlHeight,
                0
            )
            let systemCenterY = systemY + ExternalTabMetrics.systemControlHeight / 2
            let systemInfluence = self.pointerY.map {
                ExternalTabMetrics.dockInfluence(forDistance: $0 - systemCenterY)
            } ?? 0
            self.currentControls.setDockInfluence(systemInfluence)
            let systemWidth = min(self.currentControls.preferredWidth, self.bounds.width)
            let systemFrame = NSRect(
                x: max(self.bounds.width - systemWidth, 0),
                y: systemY,
                width: systemWidth,
                height: ExternalTabMetrics.systemControlHeight
            )
            self.setFrame(systemFrame, for: self.currentControls, animated: animated)
'''
new_layout = '''            let pinY = max(
                self.bounds.height
                    - ExternalTabMetrics.systemControlBottomOffset
                    - ExternalTabMetrics.systemControlHeight,
                0
            )
            let pinCenterY = pinY + ExternalTabMetrics.systemControlHeight / 2
            let pinInfluence = self.pointerY.map {
                ExternalTabMetrics.dockInfluence(forDistance: $0 - pinCenterY)
            } ?? 0
            self.pinControl.setDockInfluence(pinInfluence)
            let pinWidth = min(self.pinControl.preferredWidth, self.bounds.width)
            let pinFrame = NSRect(
                x: max(self.bounds.width - pinWidth, 0),
                y: pinY,
                width: pinWidth,
                height: ExternalTabMetrics.systemControlHeight
            )
            self.setFrame(pinFrame, for: self.pinControl, animated: animated)

            let systemY = max(
                pinY
                    - ExternalTabMetrics.systemControlGap
                    - ExternalTabMetrics.systemControlHeight,
                0
            )
            let systemCenterY = systemY + ExternalTabMetrics.systemControlHeight / 2
            let systemInfluence = self.pointerY.map {
                ExternalTabMetrics.dockInfluence(forDistance: $0 - systemCenterY)
            } ?? 0
            self.currentControls.setDockInfluence(systemInfluence)
            let systemWidth = min(self.currentControls.preferredWidth, self.bounds.width)
            let systemFrame = NSRect(
                x: max(self.bounds.width - systemWidth, 0),
                y: systemY,
                width: systemWidth,
                height: ExternalTabMetrics.systemControlHeight
            )
            self.setFrame(systemFrame, for: self.currentControls, animated: animated)
'''
text = replace_once(text, old_layout, new_layout, 'layout pin and gear controls')

pin_class = '''

@MainActor
final class PinPanelControl: NSView {
    var onActivate: (() -> Void)?
    var onPointerMoved: ((NSEvent) -> Void)?

    private let imageView = NSImageView()
    private var trackingAreaReference: NSTrackingArea?
    private var isHovered = false
    private var dockInfluence: CGFloat = 0

    private(set) var isPinned = false {
        didSet { updateAppearance() }
    }

    var preferredWidth: CGFloat {
        ExternalTabMetrics.systemControlWidth(dockInfluence: dockInfluence)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = ExternalTabMetrics.tabRadius
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 13),
            imageView.heightAnchor.constraint(equalToConstant: 13),
        ])
        updateAppearance()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    func setDockInfluence(_ influence: CGFloat) {
        dockInfluence = min(max(influence, 0), 1)
    }

    func setPinned(_ pinned: Bool) {
        isPinned = pinned
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaReference = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
        onPointerMoved?(event)
    }

    override func mouseMoved(with event: NSEvent) {
        onPointerMoved?(event)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        onActivate?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        let symbol = isPinned ? "pin.fill" : "pin"
        let description = isPinned ? "Pinned: keep FloatTabs visible" : "Pin FloatTabs"
        imageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        toolTip = isPinned
            ? "Pinned · Click or press ⌘⇧P to auto-hide when inactive"
            : "Keep FloatTabs Visible · ⌘⇧P"

        let fraction: CGFloat
        if isPinned {
            fraction = isHovered ? 0.18 : 0.12
        } else {
            fraction = isHovered ? 0.10 : 0.02
        }
        layer?.backgroundColor = NSColor.controlBackgroundColor
            .blended(withFraction: fraction, of: .labelColor)?
            .withAlphaComponent(0.94)
            .cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.30).cgColor
        layer?.borderWidth = 1
        imageView.contentTintColor = isPinned ? .labelColor : .secondaryLabelColor
    }
}
'''
text = replace_once(
    text,
'\n@MainActor\nfinal class CurrentWebAppControl: NSView {',
    pin_class + '\n@MainActor\nfinal class CurrentWebAppControl: NSView {',
    'PinPanelControl class insertion',
)
write(path, text)


# 4) Panel Pin state + automatic hide on app deactivation.
path = 'FloatTabs/Panel/PanelController.swift'
text = read(path)
text = replace_once(
    text,
'''    private var lastSynchronizedActiveProfile: WebAppProfile?
    private var followPreferredSize: Bool
''',
'''    private var lastSynchronizedActiveProfile: WebAppProfile?
    private var followPreferredSize: Bool
    private(set) var isPinned = false
''',
    'Panel pin state',
)
text = replace_once(
    text,
'''        configureSlotInteractions()

        tabStore.onChange = { [weak self] in
''',
'''        configureSlotInteractions()
        rootView.externalControlZoneView.setPinned(isPinned)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: NSApp
        )

        tabStore.onChange = { [weak self] in
''',
    'application deactivate observer',
)
text = replace_once(
    text,
'''    func prepareForTermination() {
        persistPanelFrame()
    }
''',
'''    func prepareForTermination() {
        persistPanelFrame()
    }

    static func shouldAutoHide(panelIsVisible: Bool, isPinned: Bool) -> Bool {
        panelIsVisible && !isPinned
    }

    private func togglePinnedState() {
        isPinned.toggle()
        rootView.externalControlZoneView.setPinned(isPinned)
    }

    @objc private func applicationDidResignActive(_ notification: Notification) {
        guard Self.shouldAutoHide(panelIsVisible: panel.isVisible, isPinned: isPinned) else {
            return
        }
        autoHideAfterApplicationDeactivation()
    }

    private func autoHideAfterApplicationDeactivation() {
        // The user has already selected another application. Unlike the explicit
        // global-toggle hide path, do not reactivate `previousApplication` here:
        // doing so would steal focus from the application the user just chose.
        quickURLOverlayView.dismiss()
        persistPanelFrame()
        panel.orderOut(nil)
        previousApplication = nil
    }
''',
    'auto-hide implementation',
)
text = replace_once(
    text,
'''        var snapshot: [String: Any] = [
            "visible": isVisible,
            "profiles": profiles,
        ]
''',
'''        var snapshot: [String: Any] = [
            "visible": isVisible,
            "pinned": isPinned,
            "profiles": profiles,
        ]
''',
    'benchmark pin snapshot',
)
text = replace_once(
    text,
'''        case .returnHome:
            returnActiveSlotHome()
        }
''',
'''        case .returnHome:
            returnActiveSlotHome()

        case .togglePin:
            togglePinnedState()
        }
''',
    'handle togglePin command',
)
text = replace_once(
    text,
'''        rail.onCurrentControls = { [weak self] in
            self?.presentCurrentWebAppControls()
        }
''',
'''        rail.onCurrentControls = { [weak self] in
            self?.presentCurrentWebAppControls()
        }
        rail.onTogglePin = { [weak self] in
            self?.togglePinnedState()
        }
''',
    'wire pin control',
)
write(path, text)


# 5) Regression tests: Hot host hiding/reactivation, Pin shell, auto-hide predicate, shortcut.
path = 'FloatTabsTests/WebViewFactoryTests.swift'
text = read(path)
text = replace_once(
    text,
'''        container.deactivate(slotID: firstID, residencyPolicy: .hot)
        container.setFrameSize(NSSize(width: 900, height: 850))
''',
'''        container.deactivate(slotID: firstID, residencyPolicy: .hot)
        XCTAssertTrue(first.superview?.isHidden == true)
        container.setFrameSize(NSSize(width: 900, height: 850))
''',
    'Hot hidden assertion',
)
text = replace_once(
    text,
'''        XCTAssertEqual(first.frame.size, firstSize)
        XCTAssertTrue(first.window === window)
        XCTAssertTrue(second.window === window)
    }
''',
'''        XCTAssertEqual(first.frame.size, firstSize)
        XCTAssertTrue(first.window === window)
        XCTAssertTrue(second.window === window)
        XCTAssertTrue(first.superview?.isHidden == true)

        container.show(webView: first, slotID: firstID, residencyPolicy: .hot)
        container.layoutSubtreeIfNeeded()
        XCTAssertFalse(first.superview?.isHidden ?? true)
        XCTAssertTrue(container.currentWebView === first)
        XCTAssertTrue(first.window === window)
    }
''',
    'Hot reactivation assertion',
)
write(path, text)

path = 'FloatTabsTests/AppCommandControllerTests.swift'
text = read(path)
text = replace_once(
    text,
'''        XCTAssertEqual(
            AppCommandController.command(characters: "H", keyCode: 4, modifiers: [.command, .shift]),
            .returnHome
        )

        XCTAssertNil''',
'''        XCTAssertEqual(
            AppCommandController.command(characters: "H", keyCode: 4, modifiers: [.command, .shift]),
            .returnHome
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "p", keyCode: 35, modifiers: [.command, .shift]),
            .togglePin
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "P", keyCode: 35, modifiers: [.command, .shift]),
            .togglePin
        )

        XCTAssertNil''',
    'toggle pin shortcut tests',
)
write(path, text)

path = 'FloatTabsTests/ExternalShellTests.swift'
text = read(path)
text = replace_once(
    text,
'''    func testCurrentWebAppGearUsesActualVisibleHitAreaWhenSlotIsActive() {
''',
'''    func testPinControlUsesActualVisibleHitAreaAndReflectsPinnedState() {
        let (_, zone) = makeZoneHarness()
        zone.apply(profiles: [], activeTabID: nil)
        zone.setPinned(true)
        zone.layoutSubtreeIfNeeded()

        let pointInZone = NSPoint(x: zone.pinControlFrame.midX, y: zone.pinControlFrame.midY)
        let pointInSuperview = zone.convert(pointInZone, to: zone.superview)
        let pin = zone.hitTest(pointInSuperview) as? PinPanelControl

        XCTAssertNotNil(pin)
        XCTAssertTrue(pin?.isPinned == true)
        XCTAssertEqual(zone.pinControlFrame.width, ExternalTabMetrics.systemControlNormalWidth, accuracy: 0.001)
    }

    func testPanelAutoHideDecisionRespectsPin() {
        XCTAssertTrue(PanelController.shouldAutoHide(panelIsVisible: true, isPinned: false))
        XCTAssertFalse(PanelController.shouldAutoHide(panelIsVisible: true, isPinned: true))
        XCTAssertFalse(PanelController.shouldAutoHide(panelIsVisible: false, isPinned: false))
    }

    func testCurrentWebAppGearUsesActualVisibleHitAreaWhenSlotIsActive() {
''',
    'pin and auto-hide shell tests',
)
text = replace_once(
    text,
'''        XCTAssertEqual(zone.currentControlsFrame.width, ExternalTabMetrics.systemControlNormalWidth, accuracy: 0.001)
    }
''',
'''        XCTAssertEqual(zone.currentControlsFrame.width, ExternalTabMetrics.systemControlNormalWidth, accuracy: 0.001)
        XCTAssertEqual(zone.pinControlFrame.width, ExternalTabMetrics.systemControlNormalWidth, accuracy: 0.001)
        XCTAssertLessThan(zone.currentControlsFrame.maxY, zone.pinControlFrame.minY)
    }
''',
    'system control geometry assertions',
)
write(path, text)

print('Stage 5C patch applied')
