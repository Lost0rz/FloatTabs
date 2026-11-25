import AppKit

final class EmptyWebAppView: NSView {
    var onAddWebApp: (() -> Void)?

    private let actionCard = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private var trackingAreaReference: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false
    private var languageObserver: NSObjectProtocol?

    var titleText: String { titleLabel.stringValue }
    var subtitleText: String { subtitleLabel.stringValue }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        actionCard.wantsLayer = true
        actionCard.layer?.cornerRadius = 14
        actionCard.layer?.borderWidth = 1
        actionCard.translatesAutoresizingMaskIntoConstraints = false
        addSubview(actionCard)

        if let symbol = NSImage(
            systemSymbolName: "plus.circle.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        ) {
            iconView.image = symbol
        }
        iconView.contentTintColor = .controlAccentColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center

        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true

        let contentStack = NSStackView(views: [iconView, titleLabel, subtitleLabel])
        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        actionCard.addSubview(contentStack)

        NSLayoutConstraint.activate([
            actionCard.centerXAnchor.constraint(equalTo: centerXAnchor),
            actionCard.centerYAnchor.constraint(equalTo: centerYAnchor),
            actionCard.widthAnchor.constraint(greaterThanOrEqualToConstant: 230),
            actionCard.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            actionCard.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            actionCard.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),

            contentStack.leadingAnchor.constraint(equalTo: actionCard.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: actionCard.trailingAnchor, constant: -24),
            contentStack.topAnchor.constraint(equalTo: actionCard.topAnchor, constant: 20),
            contentStack.bottomAnchor.constraint(equalTo: actionCard.bottomAnchor, constant: -20),
        ])

        setAccessibilityRole(.button)
        setAccessibilityIdentifier("floatTabs.emptyState.addWebApp")
        refreshLocalization()
        applyAppearance()

        languageObserver = NotificationCenter.default.addObserver(
            forName: .floatTabsLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshLocalization()
            }
        }
    }

    convenience init() {
        self.init(frame: .zero)
    }

    deinit {
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let area = NSTrackingArea(
            rect: actionCard.frame.isEmpty ? bounds : actionCard.frame,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if !actionCard.frame.isEmpty {
            addCursorRect(actionCard.frame, cursor: .pointingHand)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applyAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        applyAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard actionCard.frame.contains(point) else { return }
        isPressed = true
        applyAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        let wasPressed = isPressed
        isPressed = false
        applyAppearance()
        let point = convert(event.locationInWindow, from: nil)
        guard wasPressed, actionCard.frame.contains(point) else { return }
        performAddWebApp()
    }

    override func accessibilityPerformPress() -> Bool {
        performAddWebApp()
        return true
    }

    func performAddWebApp() {
        onAddWebApp?()
    }

    func refreshLocalization() {
        let title = L10n.tr("Add a Web App", "添加网页应用")
        let subtitle = L10n.tr(
            "Click here to open Add Web App settings",
            "点击此处打开添加网页应用设置"
        )
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        setAccessibilityLabel(title)
        toolTip = subtitle
    }

    private func applyAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let tintFraction: CGFloat
            if isPressed {
                tintFraction = 0.14
            } else if isHovered {
                tintFraction = 0.08
            } else {
                tintFraction = 0.02
            }
            actionCard.layer?.backgroundColor = NSColor.controlBackgroundColor
                .blended(withFraction: tintFraction, of: .controlAccentColor)?
                .withAlphaComponent(isHovered || isPressed ? 0.92 : 0.72)
                .cgColor
            actionCard.layer?.borderColor = (
                isHovered || isPressed
                    ? NSColor.controlAccentColor.withAlphaComponent(0.55)
                    : NSColor.separatorColor.withAlphaComponent(0.45)
            ).cgColor
        }
    }
}
