import AppKit
import KeyboardShortcuts

@MainActor
final class GlobalSettingsController: NSObject, NSWindowDelegate {
    private let preferencesStore: AppPreferencesStore
    private lazy var settingsWindow: NSWindow = makeWindow()

    init(preferencesStore: AppPreferencesStore) {
        self.preferencesStore = preferencesStore
        super.init()
    }

    var isVisible: Bool { settingsWindow.isVisible }

    func show() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            _ = NSRunningApplication.current.activate(options: [])
        }
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = []
        tabs.canPropagateSelectedChildViewControllerTitle = false

        addTab(
            title: "Appearance",
            symbol: "circle.lefthalf.filled",
            controller: AppearanceSettingsViewController(preferencesStore: preferencesStore),
            to: tabs
        )
        addTab(
            title: "Shortcuts",
            symbol: "keyboard",
            controller: ShortcutsSettingsViewController(),
            to: tabs
        )
        addTab(
            title: "Account & Language",
            symbol: "person.crop.circle",
            controller: AccountLanguageSettingsViewController(),
            to: tabs
        )

        let window = NSWindow(contentViewController: tabs)
        window.title = "FloatTabs Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 560, height: 390))
        window.minSize = NSSize(width: 520, height: 360)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    private func addTab(
        title: String,
        symbol: String,
        controller: NSViewController,
        to tabs: NSTabViewController
    ) {
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        tabs.addTabViewItem(item)
    }
}

@MainActor
private final class AppearanceSettingsViewController: NSViewController {
    private let preferencesStore: AppPreferencesStore
    private let appearanceControl = NSSegmentedControl(
        labels: AppAppearanceMode.allCases.map(\.displayName),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )

    init(preferencesStore: AppPreferencesStore) {
        self.preferencesStore = preferencesStore
        super.init(nibName: nil, bundle: nil)
        title = "Appearance"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = Self.titleLabel("Interface Appearance")
        let detail = Self.detailLabel(
            "Controls FloatTabs chrome only. Website content is not restyled or injected."
        )
        appearanceControl.segmentStyle = .rounded
        appearanceControl.target = self
        appearanceControl.action = #selector(appearanceChanged(_:))
        appearanceControl.selectedSegment = AppAppearanceMode.allCases.firstIndex(
            of: preferencesStore.appearanceMode
        ) ?? 0

        let stack = NSStackView(views: [titleLabel, detail, appearanceControl])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            appearanceControl.widthAnchor.constraint(equalToConstant: 250),
        ])
        view = root
    }

    @objc private func appearanceChanged(_ sender: NSSegmentedControl) {
        guard AppAppearanceMode.allCases.indices.contains(sender.selectedSegment) else { return }
        preferencesStore.appearanceMode = AppAppearanceMode.allCases[sender.selectedSegment]
    }

    private static func titleLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private static func detailLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 0
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 470).isActive = true
        return label
    }
}

@MainActor
private final class ShortcutsSettingsViewController: NSViewController {
    override func loadView() {
        let root = NSView()
        let heading = sectionTitle("Global Show / Hide")
        let detail = detailLabel(
            "This shortcut works from other apps. Changing it replaces the previous global binding immediately."
        )
        let recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleFloatTabs)
        recorder.translatesAutoresizingMaskIntoConstraints = false

        let recorderRow = NSStackView(views: [label("Show / Hide FloatTabs"), recorder])
        recorderRow.orientation = .horizontal
        recorderRow.alignment = .centerY
        recorderRow.spacing = 12
        recorderRow.distribution = .fill

        let fixedHeading = sectionTitle("FloatTabs Shortcuts")
        let fixedDetail = detailLabel("Page shortcuts are fixed in V1; only global Show / Hide is configurable here.")
        let rows = [
            shortcutRow("Select Slot", "⌘1…⌘9"),
            shortcutRow("Next / Previous Slot", "⌃Tab / ⌃⇧Tab"),
            shortcutRow("Add Web App", "⌘T"),
            shortcutRow("Quick URL", "⌘L"),
            shortcutRow("Return Home", "⌘⇧H"),
            shortcutRow("Reload", "⌘R"),
            shortcutRow("Zoom", "⌘+ / ⌘- / ⌘0"),
            shortcutRow("Pin / Auto-hide", "⌘⇧P"),
            shortcutRow("Global Settings", "⌘,"),
        ]

        let stack = NSStackView(views: [heading, detail, recorderRow, spacer(8), fixedHeading, fixedDetail] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
        ])
        view = root
    }

    private func shortcutRow(_ action: String, _ shortcut: String) -> NSView {
        let actionLabel = label(action)
        actionLabel.widthAnchor.constraint(equalToConstant: 190).isActive = true
        let shortcutLabel = NSTextField(labelWithString: shortcut)
        shortcutLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        shortcutLabel.textColor = .secondaryLabelColor
        let row = NSStackView(views: [actionLabel, shortcutLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let value = label(text)
        value.font = .systemFont(ofSize: 13, weight: .semibold)
        return value
    }

    private func detailLabel(_ text: String) -> NSTextField {
        let value = NSTextField(wrappingLabelWithString: text)
        value.font = .systemFont(ofSize: 11.5)
        value.textColor = .secondaryLabelColor
        value.maximumNumberOfLines = 0
        value.widthAnchor.constraint(lessThanOrEqualToConstant: 490).isActive = true
        return value
    }

    private func label(_ text: String) -> NSTextField {
        let value = NSTextField(labelWithString: text)
        value.font = .systemFont(ofSize: 12)
        return value
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
}

@MainActor
private final class AccountLanguageSettingsViewController: NSViewController {
    override func loadView() {
        let root = NSView()
        let stack = NSStackView(views: [
            sectionTitle("Account"),
            detailLabel(
                "FloatTabs V1 is local-only. It does not require a FloatTabs cloud account or sync service."
            ),
            detailLabel(
                "Web App profiles and app preferences stay on this Mac. Website login/session data remains in the persistent WebKit website data store."
            ),
            spacer(12),
            sectionTitle("Language"),
            detailLabel(
                "A per-app language override is not exposed in this stage. No non-functional language selector is shown."
            ),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
        ])
        view = root
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let value = NSTextField(labelWithString: text)
        value.font = .systemFont(ofSize: 13, weight: .semibold)
        return value
    }

    private func detailLabel(_ text: String) -> NSTextField {
        let value = NSTextField(wrappingLabelWithString: text)
        value.font = .systemFont(ofSize: 12)
        value.textColor = .secondaryLabelColor
        value.maximumNumberOfLines = 0
        value.widthAnchor.constraint(lessThanOrEqualToConstant: 490).isActive = true
        return value
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
}
