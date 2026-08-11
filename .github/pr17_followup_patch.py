from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


# 1) AppCommandController: move all app-local commands from hard-coded parsing to
# individually persisted KeyboardShortcuts bindings. These remain app-local because
# no global KeyboardShortcuts handlers are registered for them.
path = Path("FloatTabs/Hotkeys/AppCommandController.swift")
path.write_text(r'''import AppKit
import KeyboardShortcuts

enum AppCommand: Equatable {
    case selectSlot(Int)
    case nextSlot
    case previousSlot
    case addWebApp
    case zoomIn
    case zoomOut
    case resetZoom
    case addressBar
    case returnHome
    case reload
    case settings
    case togglePin
}

extension KeyboardShortcuts.Name {
    static let selectSlot1 = Self("selectSlot1", initial: .init(.one, modifiers: [.command]))
    static let selectSlot2 = Self("selectSlot2", initial: .init(.two, modifiers: [.command]))
    static let selectSlot3 = Self("selectSlot3", initial: .init(.three, modifiers: [.command]))
    static let selectSlot4 = Self("selectSlot4", initial: .init(.four, modifiers: [.command]))
    static let selectSlot5 = Self("selectSlot5", initial: .init(.five, modifiers: [.command]))
    static let selectSlot6 = Self("selectSlot6", initial: .init(.six, modifiers: [.command]))
    static let selectSlot7 = Self("selectSlot7", initial: .init(.seven, modifiers: [.command]))
    static let selectSlot8 = Self("selectSlot8", initial: .init(.eight, modifiers: [.command]))
    static let selectSlot9 = Self("selectSlot9", initial: .init(.nine, modifiers: [.command]))
    static let nextSlot = Self("nextSlot", initial: .init(.tab, modifiers: [.control]))
    static let previousSlot = Self("previousSlot", initial: .init(.tab, modifiers: [.control, .shift]))
    static let addWebApp = Self("addWebApp", initial: .init(.t, modifiers: [.command]))
    static let addressBar = Self("addressBar", initial: .init(.l, modifiers: [.command]))
    static let returnHome = Self("returnHome", initial: .init(.h, modifiers: [.command, .shift]))
    static let reload = Self("reload", initial: .init(.r, modifiers: [.command]))
    static let zoomIn = Self("zoomIn", initial: .init(.equal, modifiers: [.command, .shift]))
    static let zoomOut = Self("zoomOut", initial: .init(.minus, modifiers: [.command]))
    static let resetZoom = Self("resetZoom", initial: .init(.zero, modifiers: [.command]))
    static let togglePin = Self("togglePin", initial: .init(.p, modifiers: [.command, .shift]))
    static let floatTabsSettings = Self("floatTabsSettings", initial: .init(.comma, modifiers: [.command]))
}

struct AppShortcutBinding {
    let title: String
    let command: AppCommand
    let name: KeyboardShortcuts.Name
}

enum AppShortcutCatalog {
    static let slotBindings: [AppShortcutBinding] = [
        .init(title: "Select Slot 1", command: .selectSlot(1), name: .selectSlot1),
        .init(title: "Select Slot 2", command: .selectSlot(2), name: .selectSlot2),
        .init(title: "Select Slot 3", command: .selectSlot(3), name: .selectSlot3),
        .init(title: "Select Slot 4", command: .selectSlot(4), name: .selectSlot4),
        .init(title: "Select Slot 5", command: .selectSlot(5), name: .selectSlot5),
        .init(title: "Select Slot 6", command: .selectSlot(6), name: .selectSlot6),
        .init(title: "Select Slot 7", command: .selectSlot(7), name: .selectSlot7),
        .init(title: "Select Slot 8", command: .selectSlot(8), name: .selectSlot8),
        .init(title: "Select Slot 9", command: .selectSlot(9), name: .selectSlot9),
    ]

    static let navigationBindings: [AppShortcutBinding] = [
        .init(title: "Next Slot", command: .nextSlot, name: .nextSlot),
        .init(title: "Previous Slot", command: .previousSlot, name: .previousSlot),
        .init(title: "Add Web App", command: .addWebApp, name: .addWebApp),
        .init(title: "Address Bar", command: .addressBar, name: .addressBar),
        .init(title: "Return Home", command: .returnHome, name: .returnHome),
        .init(title: "Reload", command: .reload, name: .reload),
    ]

    static let viewBindings: [AppShortcutBinding] = [
        .init(title: "Zoom In", command: .zoomIn, name: .zoomIn),
        .init(title: "Zoom Out", command: .zoomOut, name: .zoomOut),
        .init(title: "Reset Zoom", command: .resetZoom, name: .resetZoom),
        .init(title: "Pin / Auto-hide", command: .togglePin, name: .togglePin),
    ]

    static let applicationBindings: [AppShortcutBinding] = [
        .init(title: "Global Settings", command: .settings, name: .floatTabsSettings),
    ]

    static var allBindings: [AppShortcutBinding] {
        slotBindings + navigationBindings + viewBindings + applicationBindings
    }

    static var allNames: [KeyboardShortcuts.Name] {
        allBindings.map(\.name)
    }

    @MainActor
    static func command(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> AppCommand? {
        let normalizedEventModifiers = normalizedModifiers(modifiers)

        for binding in allBindings {
            guard let shortcut = KeyboardShortcuts.getShortcut(for: binding.name) else {
                continue
            }

            let configuredModifiers = normalizedModifiers(shortcut.modifiers)
            guard shortcut.carbonKeyCode == Int(keyCode) else { continue }

            if configuredModifiers == normalizedEventModifiers {
                return binding.command
            }

            // Keep both historical physical-key forms for the default Zoom In
            // binding: Cmd+= and Cmd+Shift+= (displayed as Cmd++). A custom
            // non-equals binding remains exact.
            if binding.command == .zoomIn,
               shortcut.key == .equal,
               isDefaultZoomModifierFamily(configuredModifiers),
               isDefaultZoomModifierFamily(normalizedEventModifiers) {
                return .zoomIn
            }
        }

        return nil
    }

    static func normalizedModifiers(
        _ modifiers: NSEvent.ModifierFlags
    ) -> NSEvent.ModifierFlags {
        var flags = modifiers.intersection(.deviceIndependentFlagsMask)
        flags.subtract([.capsLock, .numericPad, .function])
        return flags
    }

    private static func isDefaultZoomModifierFamily(
        _ modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        modifiers == [.command] || modifiers == [.command, .shift]
    }
}

@MainActor
final class AppCommandController {
    private var monitor: Any?
    private let isEnabled: () -> Bool
    private let onCommand: (AppCommand) -> Void

    init(
        isEnabled: @escaping () -> Bool,
        onCommand: @escaping (AppCommand) -> Void
    ) {
        self.isEnabled = isEnabled
        self.onCommand = onCommand

        // Touch the catalog at launch so every initial binding is materialized
        // before the first local key event arrives.
        _ = AppShortcutCatalog.allBindings

        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return event }

            if let overlay = Self.presentedAddressOverlay(in: event.window ?? NSApp.keyWindow),
               Self.shouldDismissAddressBar(for: event, overlay: overlay) {
                overlay.dismiss()
                overlay.onDismiss?()

                // Escape / the configured Address Bar shortcut are consumed.
                // Outside mouse clicks continue to the underlying website after
                // dismissing the temporary overlay.
                return event.type == .keyDown ? nil : event
            }

            guard event.type == .keyDown,
                  let command = Self.command(for: event) else {
                return event
            }

            // Global Settings is application-level chrome. Allow its configured
            // app-local shortcut while FloatTabs is active even when the panel
            // itself is hidden.
            if command == .settings {
                self.onCommand(command)
                return nil
            }

            guard self.isEnabled() else { return event }
            self.onCommand(command)
            return nil
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    static func command(for event: NSEvent) -> AppCommand? {
        command(
            characters: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            modifiers: event.modifierFlags
        )
    }

    static func command(
        characters: String?,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> AppCommand? {
        _ = characters
        return AppShortcutCatalog.command(keyCode: keyCode, modifiers: modifiers)
    }

    static func presentedAddressOverlay(in window: NSWindow?) -> AddressOverlayView? {
        guard let contentView = window?.contentView else { return nil }
        return firstPresentedAddressOverlay(in: contentView)
    }

    static func shouldDismissAddressBar(
        for event: NSEvent,
        overlay: AddressOverlayView
    ) -> Bool {
        if event.type == .keyDown {
            if event.keyCode == 53 { // Escape
                return true
            }
            return command(for: event) == .addressBar
        }

        guard event.type == .leftMouseDown
                || event.type == .rightMouseDown
                || event.type == .otherMouseDown,
              let superview = overlay.superview else {
            return false
        }

        let point = superview.convert(event.locationInWindow, from: nil)
        return !overlay.frame.contains(point)
    }

    private static func firstPresentedAddressOverlay(in view: NSView) -> AddressOverlayView? {
        if let overlay = view as? AddressOverlayView, overlay.isPresented {
            return overlay
        }

        for subview in view.subviews {
            if let found = firstPresentedAddressOverlay(in: subview) {
                return found
            }
        }
        return nil
    }
}
''')


# 2) Address bar: remove the decorative chain icon and give the width back to URL.
path = Path("FloatTabs/Panel/PanelController.swift")
text = path.read_text()
text = replace_once(
    text,
    '''    private let icon = NSImageView()\n    private let copyButton = NSButton()\n''',
    '''    private let copyButton = NSButton()\n''',
    "address icon property",
)
text = replace_once(
    text,
    '''        icon.image = NSImage(systemSymbolName: "link", accessibilityDescription: "URL")\n        icon.contentTintColor = .secondaryLabelColor\n        icon.translatesAutoresizingMaskIntoConstraints = false\n\n        field.translatesAutoresizingMaskIntoConstraints = false\n''',
    '''        field.translatesAutoresizingMaskIntoConstraints = false\n''',
    "address icon setup",
)
text = replace_once(
    text,
    '''        addSubview(icon)\n        addSubview(field)\n        addSubview(copyButton)\n        addSubview(createButton)\n        NSLayoutConstraint.activate([\n            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),\n            icon.centerYAnchor.constraint(equalTo: centerYAnchor),\n            icon.widthAnchor.constraint(equalToConstant: 14),\n            icon.heightAnchor.constraint(equalToConstant: 14),\n\n            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),\n            field.centerYAnchor.constraint(equalTo: centerYAnchor),\n''',
    '''        addSubview(field)\n        addSubview(copyButton)\n        addSubview(createButton)\n        NSLayoutConstraint.activate([\n            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),\n            field.centerYAnchor.constraint(equalTo: centerYAnchor),\n''',
    "address icon constraints",
)
path.write_text(text)


# 3) Edit Web App: size the NSAlert accessory to its actual arranged content,
# instead of reserving a hard-coded 520pt canvas that creates the huge blank area.
path = Path("FloatTabs/UI/WebAppEditorController.swift")
text = path.read_text()
old = '''        stack.orientation = .vertical\n        stack.alignment = .leading\n        stack.spacing = 8\n        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)\n        stack.setFrameSize(NSSize(\n            width: 400,\n            height: showsPrimaryRenderingControls ? 350 : 520\n        ))\n        nameField.widthAnchor.constraint(equalToConstant: 400).isActive = true\n        urlField.widthAnchor.constraint(equalToConstant: 400).isActive = true\n        renderingForm.view.widthAnchor.constraint(equalToConstant: 400).isActive = true\n        alert.accessoryView = stack\n'''
new = '''        stack.orientation = .vertical\n        stack.alignment = .leading\n        stack.spacing = 8\n        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)\n        stack.setContentHuggingPriority(.required, for: .vertical)\n        nameField.widthAnchor.constraint(equalToConstant: 400).isActive = true\n        urlField.widthAnchor.constraint(equalToConstant: 400).isActive = true\n        renderingForm.view.widthAnchor.constraint(equalToConstant: 400).isActive = true\n\n        // NSAlert sizes its accessory from the view frame. Using the actual\n        // fitting height keeps Add/Edit compact when their visible fields differ.\n        stack.setFrameSize(NSSize(width: 400, height: 1))\n        stack.layoutSubtreeIfNeeded()\n        stack.setFrameSize(NSSize(width: 400, height: ceil(stack.fittingSize.height)))\n        alert.accessoryView = stack\n'''
text = replace_once(text, old, new, "editor accessory fitting height")
path.write_text(text)


# 4) Global Settings / Shortcuts: every app command gets its own recorder. The
# global toggle remains global; all other bindings are read by AppCommandController
# only while FloatTabs is active. Add duplicate-binding validation and reset-all.
path = Path("FloatTabs/UI/GlobalSettingsController.swift")
text = path.read_text()
pattern = re.compile(
    r'''@MainActor\nprivate final class ShortcutsSettingsViewController: NSViewController \{.*?(?=@MainActor\nprivate final class AccountLanguageSettingsViewController)''',
    re.S,
)
replacement = r'''@MainActor
private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class ShortcutsSettingsViewController: NSViewController {
    override func loadView() {
        let root = NSView()
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        let document = SettingsDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document

        var views: [NSView] = [
            sectionTitle("Global"),
            detailLabel(
                "Show / Hide works from other apps. All remaining shortcuts below are app-local and only act while FloatTabs is active."
            ),
            shortcutRecorderRow("Show / Hide FloatTabs", name: .toggleFloatTabs),
            spacer(10),
            sectionTitle("Slots"),
        ]
        views.append(contentsOf: AppShortcutCatalog.slotBindings.map(shortcutRecorderRow(for:)))
        views.append(contentsOf: [spacer(10), sectionTitle("Navigation")])
        views.append(contentsOf: AppShortcutCatalog.navigationBindings.map(shortcutRecorderRow(for:)))
        views.append(contentsOf: [spacer(10), sectionTitle("View")])
        views.append(contentsOf: AppShortcutCatalog.viewBindings.map(shortcutRecorderRow(for:)))
        views.append(contentsOf: [spacer(10), sectionTitle("Application")])
        views.append(contentsOf: AppShortcutCatalog.applicationBindings.map(shortcutRecorderRow(for:)))

        let resetButton = NSButton(
            title: "Reset All to Defaults",
            target: self,
            action: #selector(resetAllShortcuts)
        )
        resetButton.bezelStyle = .rounded
        views.append(contentsOf: [spacer(10), resetButton, spacer(8)])

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        root.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
        ])

        view = root
    }

    private func shortcutRecorderRow(for binding: AppShortcutBinding) -> NSView {
        shortcutRecorderRow(binding.title, name: binding.name)
    }

    private func shortcutRecorderRow(
        _ title: String,
        name: KeyboardShortcuts.Name
    ) -> NSView {
        let actionLabel = label(title)
        actionLabel.widthAnchor.constraint(equalToConstant: 220).isActive = true

        let recorder = KeyboardShortcuts.RecorderCocoa(for: name)
        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        recorder.validateShortcut = { [weak self] shortcut in
            guard let self else { return .allow }
            if let conflict = self.conflictingAction(for: shortcut, excluding: name) {
                return .disallow(reason: "This shortcut is already used by “\(conflict)”.")
            }
            return .allow
        }

        let row = NSStackView(views: [actionLabel, recorder])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        return row
    }

    private func conflictingAction(
        for shortcut: KeyboardShortcuts.Shortcut,
        excluding excludedName: KeyboardShortcuts.Name
    ) -> String? {
        let entries: [(String, KeyboardShortcuts.Name)] = [
            ("Show / Hide FloatTabs", .toggleFloatTabs),
        ] + AppShortcutCatalog.allBindings.map { ($0.title, $0.name) }

        for (title, name) in entries where name != excludedName {
            if KeyboardShortcuts.getShortcut(for: name) == shortcut {
                return title
            }
        }
        return nil
    }

    @objc private func resetAllShortcuts() {
        KeyboardShortcuts.reset([.toggleFloatTabs] + AppShortcutCatalog.allNames)
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
        value.widthAnchor.constraint(lessThanOrEqualToConstant: 500).isActive = true
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

'''
text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit(f"shortcuts settings replacement: expected one block, found {count}")
path.write_text(text)


# 5) Tests: prove a user override replaces the built-in address binding and the
# catalog exposes every formerly fixed shortcut as its own editable action.
path = Path("FloatTabsTests/AppCommandControllerTests.swift")
text = path.read_text()
text = replace_once(
    text,
    '''import AppKit\nimport XCTest\n''',
    '''import AppKit\nimport KeyboardShortcuts\nimport XCTest\n''',
    "test KeyboardShortcuts import",
)
marker = '''    func testAddressBarDismissesForEscapeSecondCommandLAndOutsideClickOnly() {\n'''
addition = '''    func testEveryPreviouslyFixedShortcutHasAnIndividualBinding() {\n        XCTAssertEqual(AppShortcutCatalog.slotBindings.count, 9)\n        XCTAssertEqual(AppShortcutCatalog.navigationBindings.count, 6)\n        XCTAssertEqual(AppShortcutCatalog.viewBindings.count, 4)\n        XCTAssertEqual(AppShortcutCatalog.applicationBindings.count, 1)\n        XCTAssertEqual(AppShortcutCatalog.allBindings.count, 20)\n        XCTAssertEqual(Set(AppShortcutCatalog.allNames.map(\\.rawValue)).count, 20)\n    }\n\n    func testConfiguredAddressShortcutReplacesDefaultCommandL() {\n        let original = KeyboardShortcuts.getShortcut(for: .addressBar)\n        let custom = KeyboardShortcuts.Shortcut(.k, modifiers: [.command, .option])\n        KeyboardShortcuts.setShortcut(custom, for: .addressBar)\n        defer { KeyboardShortcuts.setShortcut(original, for: .addressBar) }\n\n        XCTAssertNil(\n            AppCommandController.command(\n                characters: "l",\n                keyCode: UInt16(KeyboardShortcuts.Key.l.rawValue),\n                modifiers: [.command]\n            )\n        )\n        XCTAssertEqual(\n            AppCommandController.command(\n                characters: "k",\n                keyCode: UInt16(KeyboardShortcuts.Key.k.rawValue),\n                modifiers: [.command, .option]\n            ),\n            .addressBar\n        )\n    }\n\n''' + marker
text = replace_once(text, marker, addition, "custom shortcut tests")
path.write_text(text)
