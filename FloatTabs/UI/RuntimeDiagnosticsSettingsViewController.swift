import AppKit
import UniformTypeIdentifiers

typealias RuntimeDiagnosticsExportHandler = @MainActor (
    URL,
    @escaping @Sendable (Result<Void, RuntimeDiagnosticExportError>) -> Void
) -> Void

@MainActor
final class RuntimeDiagnosticsSettingsViewController: NSViewController {
    let modePopup = NSPopUpButton()
    let exportButton = NSButton(title: "Export Recent Diagnostics…", target: nil, action: nil)
    let openLogsButton = NSButton(title: "Open Logs Folder", target: nil, action: nil)

    private let preferencesStore: AppPreferencesStore
    private let exportHandler: RuntimeDiagnosticsExportHandler
    private let openLogsHandler: () -> Void
    private let statusLabel = NSTextField(labelWithString: "")

    init(
        preferencesStore: AppPreferencesStore,
        exportHandler: @escaping RuntimeDiagnosticsExportHandler = { _, completion in
            completion(.failure(.writerDisabled))
        },
        openLogsHandler: @escaping () -> Void = {}
    ) {
        self.preferencesStore = preferencesStore
        self.exportHandler = exportHandler
        self.openLogsHandler = openLogsHandler
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let title = NSTextField(labelWithString: "Runtime Diagnostics")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let detail = NSTextField(
            wrappingLabelWithString: "Diagnostics are observation-only and sanitized before persistence. Standard mode is the shipped default; export is a local JSONL file for support review."
        )
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 0
        detail.widthAnchor.constraint(lessThanOrEqualToConstant: 540).isActive = true

        modePopup.removeAllItems()
        for mode in RuntimeDiagnosticMode.allCases {
            modePopup.addItem(withTitle: mode.displayName)
            modePopup.lastItem?.representedObject = mode.rawValue
        }
        modePopup.target = self
        modePopup.action = #selector(modeChanged(_:))

        exportButton.target = self
        exportButton.action = #selector(exportDiagnostics(_:))
        openLogsButton.target = self
        openLogsButton.action = #selector(openLogs(_:))

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 0

        let modeRow = NSStackView(views: [
            NSTextField(labelWithString: "Collection mode"),
            modePopup
        ])
        modeRow.orientation = .horizontal
        modeRow.alignment = .centerY
        modeRow.spacing = 16

        let actions = NSStackView(views: [exportButton, openLogsButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8

        let stack = NSStackView(views: [title, detail, modeRow, actions, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
        ])
        view = root
        synchronizeControls()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        synchronizeControls()
    }

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let mode = RuntimeDiagnosticMode(rawValue: rawValue) else {
            synchronizeControls()
            return
        }
        preferencesStore.runtimeDiagnosticsMode = mode
        statusLabel.stringValue = "Saved \(mode.displayName) mode."
    }

    @objc private func exportDiagnostics(_ sender: NSButton) {
        let panel = NSSavePanel()
        panel.title = "Export FloatTabs Diagnostics"
        panel.nameFieldStringValue = RuntimeDiagnosticExporter.defaultFilename()
        panel.canCreateDirectories = true
        if let type = UTType(filenameExtension: "jsonl") {
            panel.allowedContentTypes = [type]
        }

        let complete: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            guard let self, response == .OK, let url = panel?.url else { return }
            self.exportButton.isEnabled = false
            self.statusLabel.stringValue = "Exporting…"
            self.exportHandler(url) { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.exportButton.isEnabled = true
                    switch result {
                    case .success:
                        self.statusLabel.stringValue = "Exported diagnostics successfully."
                    case let .failure(error):
                        self.statusLabel.stringValue = "Export unavailable (\(error.diagnosticCategory))."
                    }
                }
            }
        }
        if let window = view.window {
            panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
            complete(panel.runModal())
        }
    }

    @objc private func openLogs(_ sender: NSButton) {
        openLogsHandler()
    }

    private func synchronizeControls() {
        guard isViewLoaded else { return }
        let mode = preferencesStore.runtimeDiagnosticsMode
        if let index = modePopup.itemArray.firstIndex(where: {
            ($0.representedObject as? String) == mode.rawValue
        }) {
            modePopup.selectItem(at: index)
        }
    }
}
