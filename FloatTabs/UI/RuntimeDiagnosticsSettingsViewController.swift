import AppKit
import UniformTypeIdentifiers

typealias RuntimeDiagnosticsExportHandler = @MainActor (
    URL,
    @escaping @Sendable (Result<Void, RuntimeDiagnosticExportError>) -> Void
) -> Void

typealias RuntimeDiagnosticsIncidentCaptureHandler = @MainActor () -> String

@MainActor
final class RuntimeDiagnosticsSettingsViewController: NSViewController {
    let keepLocalHistoryButton = NSButton(
        checkboxWithTitle: "Keep local diagnostic history",
        target: nil,
        action: nil
    )
    let detailLevelPopup = NSPopUpButton()
    let longTermPerformanceObservationButton = NSButton(
        checkboxWithTitle: "Long-term performance observation",
        target: nil,
        action: nil
    )
    let exportButton = NSButton(title: "Export Recent Diagnostics…", target: nil, action: nil)
    let openLogsButton = NSButton(title: "Open Logs Folder", target: nil, action: nil)
#if DEBUG
    let captureStuckTabButton = NSButton(
        title: "Capture Stuck Tab Snapshot (QA)",
        target: nil,
        action: nil
    )
#endif

    private let preferencesStore: AppPreferencesStore
    private let exportHandler: RuntimeDiagnosticsExportHandler
    private let openLogsHandler: () -> Void
    private let captureIncidentHandler: RuntimeDiagnosticsIncidentCaptureHandler?
    private let statusLabel = NSTextField(labelWithString: "")

    init(
        preferencesStore: AppPreferencesStore,
        exportHandler: @escaping RuntimeDiagnosticsExportHandler = { _, completion in
            completion(.failure(.writerDisabled))
        },
        openLogsHandler: @escaping () -> Void = {},
        captureIncidentHandler: RuntimeDiagnosticsIncidentCaptureHandler? = nil
    ) {
        self.preferencesStore = preferencesStore
        self.exportHandler = exportHandler
        self.openLogsHandler = openLogsHandler
        self.captureIncidentHandler = captureIncidentHandler
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
            wrappingLabelWithString: "Keep sanitized Runtime Diagnostics locally for troubleshooting."
        )
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 0
        detail.widthAnchor.constraint(lessThanOrEqualToConstant: 540).isActive = true

        let historyDetail = NSTextField(
            wrappingLabelWithString: "History stays on this Mac and is sanitized before storage. Managed log files are retained locally for up to seven days."
        )
        historyDetail.textColor = .secondaryLabelColor
        historyDetail.maximumNumberOfLines = 0
        historyDetail.widthAnchor.constraint(lessThanOrEqualToConstant: 540).isActive = true

        let observationDetail = NSTextField(
            wrappingLabelWithString: "When enabled, records low-frequency, content-free health and performance checkpoints for the selected Slot, approximately once per minute. Requires local diagnostic history."
        )
        observationDetail.textColor = .secondaryLabelColor
        observationDetail.maximumNumberOfLines = 0
        observationDetail.widthAnchor.constraint(lessThanOrEqualToConstant: 540).isActive = true

        detailLevelPopup.removeAllItems()
        for mode in [RuntimeDiagnosticMode.standard, .verbose] {
            detailLevelPopup.addItem(withTitle: mode.displayName)
            detailLevelPopup.lastItem?.representedObject = mode.rawValue
        }
        keepLocalHistoryButton.target = self
        keepLocalHistoryButton.action = #selector(historyChanged(_:))
        detailLevelPopup.target = self
        detailLevelPopup.action = #selector(detailLevelChanged(_:))
        longTermPerformanceObservationButton.target = self
        longTermPerformanceObservationButton.action = #selector(longTermObservationChanged(_:))

        exportButton.target = self
        exportButton.action = #selector(exportDiagnostics(_:))
        openLogsButton.target = self
        openLogsButton.action = #selector(openLogs(_:))
#if DEBUG
        captureStuckTabButton.target = self
        captureStuckTabButton.action = #selector(captureStuckTab(_:))
#endif

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 0

        let detailLevelRow = NSStackView(views: [
            NSTextField(labelWithString: "Detail level"),
            detailLevelPopup
        ])
        detailLevelRow.orientation = .horizontal
        detailLevelRow.alignment = .centerY
        detailLevelRow.spacing = 16

        var actionViews: [NSView] = [exportButton, openLogsButton]
#if DEBUG
        if captureIncidentHandler != nil {
            actionViews.append(captureStuckTabButton)
        }
#endif
        let actions = NSStackView(views: actionViews)
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8

        let stack = NSStackView(views: [
            title,
            detail,
            keepLocalHistoryButton,
            historyDetail,
            detailLevelRow,
            longTermPerformanceObservationButton,
            observationDetail,
            actions,
            statusLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
        ])
        view = root
        synchronizeControls()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        synchronizeControls()
    }

    @objc private func historyChanged(_ sender: NSButton) {
        if sender.state == .on {
            if preferencesStore.runtimeDiagnosticsMode == .off {
                preferencesStore.runtimeDiagnosticsMode = .standard
            }
            statusLabel.stringValue = "Local diagnostic history is on."
        } else {
            preferencesStore.runtimeDiagnosticsMode = .off
            statusLabel.stringValue = "Local diagnostic history is off."
        }
        synchronizeControls()
    }

    @objc private func detailLevelChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let mode = RuntimeDiagnosticMode(rawValue: rawValue) else {
            synchronizeControls()
            return
        }
        guard mode == .standard || mode == .verbose else {
            synchronizeControls()
            return
        }
        preferencesStore.runtimeDiagnosticsMode = mode
        statusLabel.stringValue = "Saved \(mode.displayName) diagnostic detail."
        synchronizeControls()
    }

    @objc private func longTermObservationChanged(_ sender: NSButton) {
        preferencesStore.longTermPerformanceObservationEnabled = sender.state == .on
        statusLabel.stringValue = sender.state == .on
            ? "Long-term performance observation is on."
            : "Long-term performance observation is off."
        synchronizeControls()
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

#if DEBUG
    @objc private func captureStuckTab(_ sender: NSButton) {
        guard let captureIncidentHandler else { return }
        statusLabel.stringValue = captureIncidentHandler()
    }
#endif

    private func synchronizeControls() {
        guard isViewLoaded else { return }
        let mode = preferencesStore.runtimeDiagnosticsMode
        keepLocalHistoryButton.state = mode == .off ? .off : .on
        let detailMode = mode == .verbose ? RuntimeDiagnosticMode.verbose : .standard
        if let index = detailLevelPopup.itemArray.firstIndex(where: {
            ($0.representedObject as? String) == detailMode.rawValue
        }) {
            detailLevelPopup.selectItem(at: index)
        }
        detailLevelPopup.isEnabled = mode != .off
        longTermPerformanceObservationButton.state =
            preferencesStore.longTermPerformanceObservationEnabled ? .on : .off
        longTermPerformanceObservationButton.isEnabled = mode != .off
    }
}
