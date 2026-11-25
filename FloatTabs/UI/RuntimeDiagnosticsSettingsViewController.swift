import AppKit
import UniformTypeIdentifiers

typealias RuntimeDiagnosticsExportHandler = @MainActor (
    URL,
    @escaping @Sendable (Result<Void, RuntimeDiagnosticExportError>) -> Void
) -> Void

typealias RuntimeDiagnosticsIncidentCaptureHandler = @MainActor () -> String
typealias RuntimeDiagnosticsLiveStatusProvider = @MainActor () -> RuntimeDiagnosticsLiveStatusSnapshot?
typealias RuntimeDiagnosticsRecentEventsLoader = @MainActor (
    Int,
    @escaping @MainActor ([RuntimeDiagnosticEvent]) -> Void
) -> Void

enum RuntimeDiagnosticsLevelFilter: Int, CaseIterable {
    case all
    case noticeAndAbove
    case warningsAndErrors
    case incidentsOnly

    var title: String {
        switch self {
        case .all:
            return L10n.tr("All Levels", "全部级别")
        case .noticeAndAbove:
            return L10n.tr("Notice & Above", "提示及以上")
        case .warningsAndErrors:
            return L10n.tr("Warnings & Errors", "警告与错误")
        case .incidentsOnly:
            return L10n.tr("Incidents & Stalls", "异常与卡顿事件")
        }
    }

    func matches(_ event: RuntimeDiagnosticEvent) -> Bool {
        switch self {
        case .all:
            return true
        case .noticeAndAbove:
            switch event.level {
            case .notice, .warning, .error, .fault:
                return true
            case .debug, .info:
                return false
            }
        case .warningsAndErrors:
            switch event.level {
            case .warning, .error, .fault:
                return true
            case .debug, .info, .notice:
                return false
            }
        case .incidentsOnly:
            return event.isIncidentRelated || event.level == .error || event.level == .fault
        }
    }
}

enum RuntimeDiagnosticsSubsystemFilter: Int, CaseIterable {
    case all
    case navigationAndWeb
    case lifecycle
    case panelAndFocus
    case attention
    case favicon
    case storage
    case appAndDiagnostics

    var title: String {
        switch self {
        case .all:
            return L10n.tr("All Subsystems", "全部子系统")
        case .navigationAndWeb:
            return L10n.tr("Navigation & Web", "导航与网页")
        case .lifecycle:
            return L10n.tr("Lifecycle", "生命周期")
        case .panelAndFocus:
            return L10n.tr("Panel & Focus", "面板与焦点")
        case .attention:
            return L10n.tr("Attention & Unread", "提醒与未读状态")
        case .favicon:
            return L10n.tr("Favicon", "网站图标")
        case .storage:
            return L10n.tr("Storage", "存储与缓存")
        case .appAndDiagnostics:
            return L10n.tr("App & Diagnostics", "应用与诊断")
        }
    }

    func matches(_ event: RuntimeDiagnosticEvent) -> Bool {
        let subsystem = event.subsystem.lowercased()
        switch self {
        case .all:
            return true
        case .navigationAndWeb:
            return subsystem == "navigation" || subsystem == "web"
        case .lifecycle:
            return subsystem == "lifecycle" || subsystem == "residency"
        case .panelAndFocus:
            return subsystem == "panel" || subsystem == "focus" || subsystem == "presentation"
        case .attention:
            return subsystem == "attention" || subsystem == "unread"
        case .favicon:
            return subsystem == "favicon"
        case .storage:
            return subsystem == "storage" || subsystem == "cache"
        case .appAndDiagnostics:
            return !Self.navigationAndWeb.matches(event)
                && !Self.lifecycle.matches(event)
                && !Self.panelAndFocus.matches(event)
                && !Self.attention.matches(event)
                && !Self.favicon.matches(event)
                && !Self.storage.matches(event)
        }
    }
}

enum RuntimeDiagnosticsEventFormatter {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let rawJSONEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let prettyJSONEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static func shortTimeString(for date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func levelLabel(for level: RuntimeDiagnosticLevel) -> String {
        switch level {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .warning: return "WARN"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        }
    }

    static func formattedByteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .memory)
    }

    static func formattedStatusBanner(
        liveStatus: RuntimeDiagnosticsLiveStatusSnapshot?,
        fallbackMode: RuntimeDiagnosticMode,
        loadedEvents: [RuntimeDiagnosticEvent],
        filteredCount: Int
    ) -> String {
        var parts: [String] = []
        if let liveStatus {
            let summary = liveStatus.diagnosticsSummary
            parts.append(L10n.tr("Mode: \(summary.mode.displayName)", "模式：\(summary.mode.displayName)"))
            parts.append(
                L10n.tr(
                    "Resident Tabs: \(liveStatus.residentSlotCount)/\(liveStatus.totalSlotCount)",
                    "常驻标签：\(liveStatus.residentSlotCount)/\(liveStatus.totalSlotCount)"
                )
            )
            if let activeSlotName = liveStatus.activeSlotName, !activeSlotName.isEmpty {
                parts.append(L10n.tr("Active: \(activeSlotName)", "当前：\(activeSlotName)"))
            }
            if let rss = liveStatus.hostResidentSizeBytes {
                let capped = Int64(min(rss, UInt64(Int64.max)))
                parts.append(
                    L10n.tr(
                        "Host App RSS: \(formattedByteCount(capped)) (FloatTabs host process only; excludes WebKit processes)",
                        "主进程内存：\(formattedByteCount(capped))（仅 FloatTabs 主进程，不含 WebKit 渲染进程）"
                    )
                )
            }
            parts.append(
                L10n.tr(
                    "Session Events: \(summary.sessionEventCount) (Warn \(summary.sessionWarningCount), Err \(summary.sessionErrorCount), Incident \(summary.sessionIncidentEventCount))",
                    "本次会话事件：\(summary.sessionEventCount)（警告 \(summary.sessionWarningCount)，错误 \(summary.sessionErrorCount)，异常 \(summary.sessionIncidentEventCount)）"
                )
            )
        } else {
            parts.append(L10n.tr("Mode: \(fallbackMode.displayName)", "模式：\(fallbackMode.displayName)"))
        }

        let loadedWarnings = loadedEvents.filter { $0.level == .warning }.count
        let loadedErrors = loadedEvents.filter { $0.level == .error || $0.level == .fault }.count
        parts.append(
            L10n.tr(
                "Showing \(filteredCount)/\(loadedEvents.count) loaded (Warn \(loadedWarnings), Err \(loadedErrors))",
                "已显示 \(filteredCount)/\(loadedEvents.count) 条（警告 \(loadedWarnings)，错误 \(loadedErrors)）"
            )
        )
        return parts.joined(separator: "  ·  ")
    }

    static func conciseSummary(for event: RuntimeDiagnosticEvent) -> String {
        let fields = event.fields
        var parts: [String] = []

        if case let .string(slotID) = fields["slot_id"], !slotID.isEmpty {
            parts.append("tab=\(String(slotID.prefix(8)))")
        }

        if case let .string(fromStage) = fields["from_stage"],
           case let .string(toStage) = fields["to_stage"] {
            parts.append("\(fromStage)->\(toStage)")
        } else if case let .string(stage) = fields["stage"] {
            parts.append("stage=\(stage)")
        }

        let latencyPriorityKeys = [
            "provisional_to_finish_ms",
            "provisional_to_interactive_ms",
            "provisional_to_commit_ms",
            "commit_to_finish_ms",
            "commit_to_interactive_ms",
            "materialization_elapsed_ms",
            "navigation_elapsed_ms",
            "incident_elapsed_ms",
            "probe_cycle_latency_ms",
            "probe_latency_ms",
            "duration_ms"
        ]
        for key in latencyPriorityKeys {
            if let value = fields[key], let rendered = numericDisplayString(value) {
                parts.append("\(key)=\(rendered)ms")
                break
            }
        }

        if case let .integer(cleanedCount) = fields["cleaned_profile_count"] {
            var cacheDetail = "cleaned=\(cleanedCount)"
            if case let .integer(releasedBytes) = fields["released_bytes"] {
                cacheDetail += " freed=\(formattedByteCount(releasedBytes))"
            }
            parts.append(cacheDetail)
        } else if case let .integer(estimatedBytes) = fields["estimated_bytes"] {
            parts.append("cache=\(formattedByteCount(estimatedBytes))")
        }

        if case let .string(popupKind) = fields["popup_kind"] {
            parts.append(popupKind)
        }
        if case let .string(mediaType) = fields["media_type"],
           case let .string(decision) = fields["decision"] {
            parts.append("\(mediaType)=\(decision)")
        }

        for key in [
            "incident_kind",
            "stall_class",
            "incident_outcome",
            "failure_reason",
            "reason",
            "readiness_trigger",
            "readiness_source",
            "capture_availability",
            "decision_source",
            "outcome"
        ] {
            if case let .string(text) = fields[key], !text.isEmpty {
                parts.append("\(key)=\(text)")
            }
        }

        if case let .string(errorCategory) = fields["error_category"] {
            if case let .integer(errorCode) = fields["error_code"] {
                parts.append("err=\(errorCategory)(\(errorCode))")
            } else {
                parts.append("err=\(errorCategory)")
            }
        }

        for urlKey in ["url", "origin", "target_origin", "security_origin"] {
            if case let .string(origin) = fields[urlKey], !origin.isEmpty {
                parts.append(origin)
                break
            }
        }

        if parts.isEmpty {
            let fallbackPairs = fields.keys.sorted().prefix(3).compactMap { key -> String? in
                guard let value = fields[key], value != .null else { return nil }
                return "\(key)=\(scalarDisplayString(value))"
            }
            parts.append(contentsOf: fallbackPairs)
        }

        return parts.isEmpty ? "—" : parts.joined(separator: "  ·  ")
    }

    static func detailText(for event: RuntimeDiagnosticEvent) -> String {
        var lines: [String] = [
            "Event:      \(event.event)",
            "Level:      \(event.level.rawValue.uppercased())",
            "Subsystem:  \(event.subsystem)",
            "Timestamp:  \(isoFormatter.string(from: event.timestamp))  (uptime \(String(format: "%.3fs", event.uptime)))",
            "Sequence:   #\(event.sequence)   Session: \(event.sessionID.uuidString)"
        ]
        if let traceID = event.traceID {
            lines.append("Trace ID:   \(traceID.uuidString)")
        }

        if !event.fields.isEmpty {
            lines.append("")
            lines.append("Fields (Privacy-Sanitized):")
            for key in event.fields.keys.sorted() {
                if let value = event.fields[key] {
                    lines.append("  \(key): \(scalarDisplayString(value))")
                }
            }
        }

        if let prettyData = try? prettyJSONEncoder.encode(event),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            lines.append("")
            lines.append("JSON:")
            lines.append(prettyString)
        }
        return lines.joined(separator: "\n")
    }

    static func jsonLinesString(for events: [RuntimeDiagnosticEvent]) -> String {
        events.compactMap { event in
            guard let data = try? rawJSONEncoder.encode(event) else { return nil }
            return String(data: data, encoding: .utf8)
        }.joined(separator: "\n")
    }

    static func matchesSearch(_ event: RuntimeDiagnosticEvent, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        if event.event.lowercased().contains(needle)
            || event.subsystem.lowercased().contains(needle)
            || event.level.rawValue.lowercased().contains(needle)
            || event.sessionID.uuidString.lowercased().contains(needle)
            || (event.traceID?.uuidString.lowercased().contains(needle) == true) {
            return true
        }
        for (key, value) in event.fields {
            if key.lowercased().contains(needle) {
                return true
            }
            if value != .null,
               scalarDisplayString(value).lowercased().contains(needle) {
                return true
            }
        }
        return false
    }

    private static func numericDisplayString(_ value: RuntimeDiagnosticValue) -> String? {
        switch value {
        case let .integer(integer):
            return "\(integer)"
        case let .double(double):
            return String(format: "%.1f", double)
        default:
            return nil
        }
    }

    private static func scalarDisplayString(_ value: RuntimeDiagnosticValue) -> String {
        switch value {
        case let .string(string):
            return string
        case let .bool(bool):
            return bool ? "true" : "false"
        case let .integer(integer):
            return "\(integer)"
        case let .double(double):
            return String(format: "%.2f", double)
        case .null:
            return "null"
        }
    }
}

@MainActor
final class RuntimeDiagnosticsViewerWindowController: NSWindowController,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSSearchFieldDelegate {
    private static let timeColumnID = NSUserInterfaceItemIdentifier("time")
    private static let levelColumnID = NSUserInterfaceItemIdentifier("level")
    private static let subsystemColumnID = NSUserInterfaceItemIdentifier("subsystem")
    private static let eventColumnID = NSUserInterfaceItemIdentifier("event")
    private static let summaryColumnID = NSUserInterfaceItemIdentifier("summary")

    private let preferencesStore: AppPreferencesStore
    private let liveStatusProvider: RuntimeDiagnosticsLiveStatusProvider?
    private let recentEventsLoader: RuntimeDiagnosticsRecentEventsLoader?
    private let captureIncidentHandler: RuntimeDiagnosticsIncidentCaptureHandler?
    private let exportHandler: RuntimeDiagnosticsExportHandler
    private let openLogsHandler: () -> Void

    let levelFilterPopup = NSPopUpButton()
    let subsystemFilterPopup = NSPopUpButton()
    let searchField = NSSearchField()
    let liveSummaryLabel = NSTextField(wrappingLabelWithString: "")
    let actionStatusLabel = NSTextField(labelWithString: "")
    let eventsTableView = NSTableView()
    let detailTextView = NSTextView()
    let refreshButton = NSButton(title: L10n.tr("Refresh", "刷新"), target: nil, action: nil)
    let captureSnapshotButton = NSButton(
        title: L10n.tr("Capture Current Tab Snapshot", "抓取当前标签快照"),
        target: nil,
        action: nil
    )
    let copySelectedButton = NSButton(title: L10n.tr("Copy Selected", "复制选中项"), target: nil, action: nil)
    let copyFilteredButton = NSButton(title: L10n.tr("Copy Filtered JSONL", "复制筛选结果 JSONL"), target: nil, action: nil)
    let exportButton = NSButton(title: L10n.tr("Export…", "导出…"), target: nil, action: nil)
    let openLogsButton = NSButton(title: L10n.tr("Open Logs Folder", "打开日志文件夹"), target: nil, action: nil)

    private(set) var allEvents: [RuntimeDiagnosticEvent] = []
    private(set) var filteredEvents: [RuntimeDiagnosticEvent] = []
    private var currentLiveStatus: RuntimeDiagnosticsLiveStatusSnapshot?
    private var selectedLevelFilter: RuntimeDiagnosticsLevelFilter = .all
    private var selectedSubsystemFilter: RuntimeDiagnosticsSubsystemFilter = .all
    private var searchQuery = ""
    private var isLoading = false

    init(
        preferencesStore: AppPreferencesStore,
        liveStatusProvider: RuntimeDiagnosticsLiveStatusProvider? = nil,
        recentEventsLoader: RuntimeDiagnosticsRecentEventsLoader? = nil,
        captureIncidentHandler: RuntimeDiagnosticsIncidentCaptureHandler? = nil,
        exportHandler: @escaping RuntimeDiagnosticsExportHandler = { _, completion in
            completion(.failure(.writerDisabled))
        },
        openLogsHandler: @escaping () -> Void = {}
    ) {
        self.preferencesStore = preferencesStore
        self.liveStatusProvider = liveStatusProvider
        self.recentEventsLoader = recentEventsLoader
        self.captureIncidentHandler = captureIncidentHandler
        self.exportHandler = exportHandler
        self.openLogsHandler = openLogsHandler

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.tr("FloatTabs Runtime Diagnostics", "FloatTabs 运行诊断查看器")
        window.minSize = NSSize(width: 720, height: 480)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        configureUI(in: window)
        applyFilters()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func presentAndRefresh() {
        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        reloadData()
    }

    func reloadData() {
        currentLiveStatus = liveStatusProvider?()
        updateLiveSummaryBanner()

        guard let recentEventsLoader else {
            actionStatusLabel.stringValue = L10n.tr("Diagnostics reader unavailable.", "诊断读取器不可用。")
            return
        }
        guard !isLoading else { return }
        isLoading = true
        refreshButton.isEnabled = false
        actionStatusLabel.stringValue = L10n.tr("Loading recent diagnostics…", "正在加载近期诊断记录…")

        recentEventsLoader(400) { [weak self] events in
            guard let self else { return }
            self.isLoading = false
            self.refreshButton.isEnabled = true
            self.applyEvents(events, liveStatus: self.liveStatusProvider?())
            self.actionStatusLabel.stringValue = events.isEmpty
                ? L10n.tr("No diagnostic events recorded yet.", "尚未记录任何诊断事件。")
                : L10n.tr(
                    "Loaded \(events.count) recent diagnostic events.",
                    "已加载最近 \(events.count) 条诊断事件。"
                )
        }
    }

    func applyEvents(
        _ events: [RuntimeDiagnosticEvent],
        liveStatus: RuntimeDiagnosticsLiveStatusSnapshot? = nil
    ) {
        allEvents = events.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            if lhs.sessionID == rhs.sessionID {
                return lhs.sequence > rhs.sequence
            }
            return lhs.uptime > rhs.uptime
        }
        if let liveStatus {
            currentLiveStatus = liveStatus
        }
        applyFilters()
    }

    func updateFilters(
        level: RuntimeDiagnosticsLevelFilter? = nil,
        subsystem: RuntimeDiagnosticsSubsystemFilter? = nil,
        searchText: String? = nil
    ) {
        if let level {
            selectedLevelFilter = level
            levelFilterPopup.selectItem(at: level.rawValue)
        }
        if let subsystem {
            selectedSubsystemFilter = subsystem
            subsystemFilterPopup.selectItem(at: subsystem.rawValue)
        }
        if let searchText {
            searchQuery = searchText
            if searchField.stringValue != searchText {
                searchField.stringValue = searchText
            }
        }
        applyFilters()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredEvents.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < filteredEvents.count, let identifier = tableColumn?.identifier else {
            return nil
        }
        let event = filteredEvents[row]
        let cellIdentifier = NSUserInterfaceItemIdentifier("cell.\(identifier.rawValue)")
        let textField: NSTextField
        if let reused = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTextField {
            textField = reused
        } else {
            textField = NSTextField(labelWithString: "")
            textField.identifier = cellIdentifier
            textField.lineBreakMode = .byTruncatingTail
            textField.maximumNumberOfLines = 1
            textField.cell?.truncatesLastVisibleLine = true
        }

        switch identifier {
        case Self.timeColumnID:
            textField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            textField.textColor = .secondaryLabelColor
            textField.stringValue = RuntimeDiagnosticsEventFormatter.shortTimeString(for: event.timestamp)
        case Self.levelColumnID:
            textField.font = .systemFont(ofSize: 11, weight: .semibold)
            textField.textColor = Self.color(for: event.level)
            textField.stringValue = RuntimeDiagnosticsEventFormatter.levelLabel(for: event.level)
        case Self.subsystemColumnID:
            textField.font = .systemFont(ofSize: 11, weight: .regular)
            textField.textColor = .secondaryLabelColor
            textField.stringValue = event.subsystem
        case Self.eventColumnID:
            textField.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            textField.textColor = .labelColor
            textField.stringValue = event.event
        case Self.summaryColumnID:
            textField.font = .systemFont(ofSize: 11, weight: .regular)
            textField.textColor = .secondaryLabelColor
            textField.stringValue = RuntimeDiagnosticsEventFormatter.conciseSummary(for: event)
        default:
            textField.stringValue = ""
        }
        return textField
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateSelectedEventDetail()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as? NSSearchField === searchField else { return }
        searchQuery = searchField.stringValue
        applyFilters()
    }

    private func configureUI(in window: NSWindow) {
        let root = NSView()
        window.contentView = root

        liveSummaryLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        liveSummaryLabel.textColor = .secondaryLabelColor
        liveSummaryLabel.maximumNumberOfLines = 2
        liveSummaryLabel.translatesAutoresizingMaskIntoConstraints = false

        levelFilterPopup.removeAllItems()
        for level in RuntimeDiagnosticsLevelFilter.allCases {
            levelFilterPopup.addItem(withTitle: level.title)
            levelFilterPopup.lastItem?.tag = level.rawValue
        }
        levelFilterPopup.target = self
        levelFilterPopup.action = #selector(filterSelectionChanged(_:))

        subsystemFilterPopup.removeAllItems()
        for subsystem in RuntimeDiagnosticsSubsystemFilter.allCases {
            subsystemFilterPopup.addItem(withTitle: subsystem.title)
            subsystemFilterPopup.lastItem?.tag = subsystem.rawValue
        }
        subsystemFilterPopup.target = self
        subsystemFilterPopup.action = #selector(filterSelectionChanged(_:))

        searchField.placeholderString = L10n.tr(
            "Filter event, tab ID, reason, or metric…",
            "搜索事件名、标签 ID、原因或指标…"
        )
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self

        let filterRow = NSStackView(views: [
            levelFilterPopup,
            subsystemFilterPopup,
            searchField
        ])
        filterRow.orientation = .horizontal
        filterRow.alignment = .centerY
        filterRow.spacing = 8
        filterRow.translatesAutoresizingMaskIntoConstraints = false

        configureTableColumns()
        eventsTableView.usesAlternatingRowBackgroundColors = true
        eventsTableView.allowsMultipleSelection = false
        eventsTableView.rowHeight = 20
        eventsTableView.headerView = NSTableHeaderView()
        eventsTableView.dataSource = self
        eventsTableView.delegate = self
        eventsTableView.setAccessibilityIdentifier("floatTabs.diagnosticsViewer.table")

        let tableScrollView = NSScrollView()
        tableScrollView.hasVerticalScroller = true
        tableScrollView.hasHorizontalScroller = true
        tableScrollView.borderType = .bezelBorder
        tableScrollView.documentView = eventsTableView

        detailTextView.isEditable = false
        detailTextView.isSelectable = true
        detailTextView.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        detailTextView.textContainerInset = NSSize(width: 8, height: 8)
        detailTextView.isVerticallyResizable = true
        detailTextView.isHorizontallyResizable = false
        detailTextView.autoresizingMask = [.width]
        detailTextView.setAccessibilityIdentifier("floatTabs.diagnosticsViewer.detail")

        let detailScrollView = NSScrollView()
        detailScrollView.hasVerticalScroller = true
        detailScrollView.borderType = .bezelBorder
        detailScrollView.documentView = detailTextView

        let splitView = NSSplitView()
        splitView.isVertical = false
        splitView.dividerStyle = .thin
        splitView.addArrangedSubview(tableScrollView)
        splitView.addArrangedSubview(detailScrollView)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        splitView.translatesAutoresizingMaskIntoConstraints = false

        refreshButton.target = self
        refreshButton.action = #selector(refreshPressed(_:))
        refreshButton.bezelStyle = .rounded

        captureSnapshotButton.target = self
        captureSnapshotButton.action = #selector(captureSnapshotPressed(_:))
        captureSnapshotButton.bezelStyle = .rounded
        captureSnapshotButton.isHidden = (captureIncidentHandler == nil)

        copySelectedButton.target = self
        copySelectedButton.action = #selector(copySelectedPressed(_:))
        copySelectedButton.bezelStyle = .rounded

        copyFilteredButton.target = self
        copyFilteredButton.action = #selector(copyFilteredPressed(_:))
        copyFilteredButton.bezelStyle = .rounded

        exportButton.target = self
        exportButton.action = #selector(exportPressed(_:))
        exportButton.bezelStyle = .rounded

        openLogsButton.target = self
        openLogsButton.action = #selector(openLogsPressed(_:))
        openLogsButton.bezelStyle = .rounded

        let flexibleSpacer = NSView()
        flexibleSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let actionRow = NSStackView(views: [
            refreshButton,
            captureSnapshotButton,
            copySelectedButton,
            copyFilteredButton,
            flexibleSpacer,
            exportButton,
            openLogsButton
        ])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 8
        actionRow.translatesAutoresizingMaskIntoConstraints = false

        actionStatusLabel.font = .systemFont(ofSize: 11)
        actionStatusLabel.textColor = .secondaryLabelColor
        actionStatusLabel.lineBreakMode = .byTruncatingTail
        actionStatusLabel.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(liveSummaryLabel)
        root.addSubview(filterRow)
        root.addSubview(splitView)
        root.addSubview(actionRow)
        root.addSubview(actionStatusLabel)

        NSLayoutConstraint.activate([
            liveSummaryLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            liveSummaryLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            liveSummaryLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),

            filterRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            filterRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            filterRow.topAnchor.constraint(equalTo: liveSummaryLabel.bottomAnchor, constant: 8),

            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),

            splitView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            splitView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            splitView.topAnchor.constraint(equalTo: filterRow.bottomAnchor, constant: 10),
            splitView.bottomAnchor.constraint(equalTo: actionRow.topAnchor, constant: -10),
            detailScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),

            actionRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            actionRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            actionRow.bottomAnchor.constraint(equalTo: actionStatusLabel.topAnchor, constant: -6),

            actionStatusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            actionStatusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            actionStatusLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10)
        ])
    }

    private func configureTableColumns() {
        let specs: [(NSUserInterfaceItemIdentifier, String, CGFloat, CGFloat)] = [
            (Self.timeColumnID, L10n.tr("Time", "时间"), 86, 80),
            (Self.levelColumnID, L10n.tr("Level", "级别"), 64, 58),
            (Self.subsystemColumnID, L10n.tr("Subsystem", "子系统"), 88, 72),
            (Self.eventColumnID, L10n.tr("Event", "事件"), 240, 140),
            (Self.summaryColumnID, L10n.tr("Details", "详情"), 360, 180)
        ]
        for (identifier, title, width, minWidth) in specs {
            let column = NSTableColumn(identifier: identifier)
            column.title = title
            column.width = width
            column.minWidth = minWidth
            column.resizingMask = .userResizingMask
            eventsTableView.addTableColumn(column)
        }
    }

    private func applyFilters() {
        let levelFilter = selectedLevelFilter
        let subsystemFilter = selectedSubsystemFilter
        let query = searchQuery

        filteredEvents = allEvents.filter { event in
            levelFilter.matches(event)
                && subsystemFilter.matches(event)
                && RuntimeDiagnosticsEventFormatter.matchesSearch(event, query: query)
        }
        eventsTableView.reloadData()
        if !filteredEvents.isEmpty {
            eventsTableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        updateSelectedEventDetail()
        updateLiveSummaryBanner()
        copySelectedButton.isEnabled = !filteredEvents.isEmpty
        copyFilteredButton.isEnabled = !filteredEvents.isEmpty
    }

    private func updateLiveSummaryBanner() {
        liveSummaryLabel.stringValue = RuntimeDiagnosticsEventFormatter.formattedStatusBanner(
            liveStatus: currentLiveStatus,
            fallbackMode: preferencesStore.runtimeDiagnosticsMode,
            loadedEvents: allEvents,
            filteredCount: filteredEvents.count
        )
    }

    private func updateSelectedEventDetail() {
        let row = eventsTableView.selectedRow
        guard row >= 0, row < filteredEvents.count else {
            detailTextView.string = allEvents.isEmpty
                ? L10n.tr(
                    "No diagnostic events available yet. Trigger tab actions or click \"Capture Current Tab Snapshot\".",
                    "暂无可用诊断事件。可先操作标签页或点击“抓取当前标签快照”。"
                )
                : L10n.tr("No diagnostic events match the current filter.", "没有符合当前筛选条件的诊断事件。")
            copySelectedButton.isEnabled = false
            return
        }
        copySelectedButton.isEnabled = true
        detailTextView.string = RuntimeDiagnosticsEventFormatter.detailText(for: filteredEvents[row])
    }

    @objc private func filterSelectionChanged(_ sender: NSPopUpButton) {
        if let raw = RuntimeDiagnosticsLevelFilter(rawValue: levelFilterPopup.selectedTag()) {
            selectedLevelFilter = raw
        }
        if let raw = RuntimeDiagnosticsSubsystemFilter(rawValue: subsystemFilterPopup.selectedTag()) {
            selectedSubsystemFilter = raw
        }
        applyFilters()
    }

    @objc private func refreshPressed(_ sender: NSButton) {
        reloadData()
    }

    @objc private func captureSnapshotPressed(_ sender: NSButton) {
        guard let captureIncidentHandler else { return }
        actionStatusLabel.stringValue = captureIncidentHandler()
        reloadData()
    }

    @objc private func copySelectedPressed(_ sender: NSButton) {
        let row = eventsTableView.selectedRow
        guard row >= 0, row < filteredEvents.count else { return }
        let detail = RuntimeDiagnosticsEventFormatter.detailText(for: filteredEvents[row])
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(detail, forType: .string)
        actionStatusLabel.stringValue = L10n.tr(
            "Copied selected diagnostic event.",
            "已复制选中的诊断事件。"
        )
    }

    @objc private func copyFilteredPressed(_ sender: NSButton) {
        let payload = RuntimeDiagnosticsEventFormatter.jsonLinesString(for: filteredEvents)
        guard !payload.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(payload, forType: .string)
        actionStatusLabel.stringValue = L10n.tr(
            "Copied \(filteredEvents.count) filtered diagnostic events as JSONL.",
            "已将筛选出的 \(filteredEvents.count) 条诊断事件复制为 JSONL。"
        )
    }

    @objc private func exportPressed(_ sender: NSButton) {
        let panel = NSSavePanel()
        panel.title = L10n.tr("Export FloatTabs Diagnostics", "导出 FloatTabs 诊断日志")
        panel.nameFieldStringValue = RuntimeDiagnosticExporter.defaultFilename()
        panel.canCreateDirectories = true
        if let type = UTType(filenameExtension: "jsonl") {
            panel.allowedContentTypes = [type]
        }

        let complete: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            guard let self, response == .OK, let url = panel?.url else { return }
            self.exportButton.isEnabled = false
            self.actionStatusLabel.stringValue = L10n.tr("Exporting…", "正在导出…")
            self.exportHandler(url) { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.exportButton.isEnabled = true
                    switch result {
                    case .success:
                        self.actionStatusLabel.stringValue = L10n.tr(
                            "Exported diagnostics successfully.",
                            "诊断日志导出成功。"
                        )
                    case let .failure(error):
                        self.actionStatusLabel.stringValue = L10n.tr(
                            "Export unavailable (\(error.diagnosticCategory)).",
                            "暂无法导出（\(error.diagnosticCategory)）。"
                        )
                    }
                }
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
            complete(panel.runModal())
        }
    }

    @objc private func openLogsPressed(_ sender: NSButton) {
        openLogsHandler()
    }

    private static func color(for level: RuntimeDiagnosticLevel) -> NSColor {
        switch level {
        case .debug:
            return .tertiaryLabelColor
        case .info:
            return .secondaryLabelColor
        case .notice:
            return .controlAccentColor
        case .warning:
            return .systemOrange
        case .error, .fault:
            return .systemRed
        }
    }
}

@MainActor
final class RuntimeDiagnosticsSettingsViewController: NSViewController {
    let keepLocalHistoryButton = NSButton(
        checkboxWithTitle: L10n.tr("Keep local diagnostic history", "保留本地诊断历史"),
        target: nil,
        action: nil
    )
    let detailLevelPopup = NSPopUpButton()
    let longTermPerformanceObservationButton = NSButton(
        checkboxWithTitle: L10n.tr("Long-term performance observation", "长期性能观测"),
        target: nil,
        action: nil
    )
    let viewDiagnosticsButton = NSButton(
        title: L10n.tr("View Recent Diagnostics…", "查看近期诊断…"),
        target: nil,
        action: nil
    )
    let captureStuckTabButton = NSButton(
        title: L10n.tr("Capture Current Tab Snapshot", "抓取当前标签快照"),
        target: nil,
        action: nil
    )
    let exportButton = NSButton(
        title: L10n.tr("Export Recent Diagnostics…", "导出近期诊断…"),
        target: nil,
        action: nil
    )
    let openLogsButton = NSButton(
        title: L10n.tr("Open Saved Logs Folder", "打开日志文件夹"),
        target: nil,
        action: nil
    )

    private let preferencesStore: AppPreferencesStore
    private let exportHandler: RuntimeDiagnosticsExportHandler
    private let openLogsHandler: () -> Void
    private let captureIncidentHandler: RuntimeDiagnosticsIncidentCaptureHandler?
    private let liveStatusProvider: RuntimeDiagnosticsLiveStatusProvider?
    private let recentEventsLoader: RuntimeDiagnosticsRecentEventsLoader?
    private let liveStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private var viewerWindowController: RuntimeDiagnosticsViewerWindowController?

    init(
        preferencesStore: AppPreferencesStore,
        exportHandler: @escaping RuntimeDiagnosticsExportHandler = { _, completion in
            completion(.failure(.writerDisabled))
        },
        openLogsHandler: @escaping () -> Void = {},
        captureIncidentHandler: RuntimeDiagnosticsIncidentCaptureHandler? = nil,
        liveStatusProvider: RuntimeDiagnosticsLiveStatusProvider? = nil,
        recentEventsLoader: RuntimeDiagnosticsRecentEventsLoader? = nil
    ) {
        self.preferencesStore = preferencesStore
        self.exportHandler = exportHandler
        self.openLogsHandler = openLogsHandler
        self.captureIncidentHandler = captureIncidentHandler
        self.liveStatusProvider = liveStatusProvider
        self.recentEventsLoader = recentEventsLoader
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let title = NSTextField(labelWithString: L10n.tr("Runtime Diagnostics", "运行诊断"))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let detail = NSTextField(
            wrappingLabelWithString: L10n.tr(
                "Keep sanitized Runtime Diagnostics locally for troubleshooting.",
                "在本地保留经过脱敏处理的运行时诊断日志，便于排查问题。"
            )
        )
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 0
        detail.widthAnchor.constraint(lessThanOrEqualToConstant: 540).isActive = true

        let historyDetail = NSTextField(
            wrappingLabelWithString: L10n.tr(
                "Sanitized diagnostics are saved on this Mac and retained for up to 7 days. Logs are normally grouped into one JSONL file per UTC day; large daily logs may be split automatically. Open the saved logs folder and choose one or more daily files to provide later for offline AI analysis.",
                "脱敏后的诊断日志会保存在此 Mac 上并最多保留 7 天。日志通常按 UTC 日期每天生成一个 JSONL 文件（较大时会自动分割）。你随时可以打开日志文件夹并选择相应文件用于离线排查或 AI 分析。"
            )
        )
        historyDetail.textColor = .secondaryLabelColor
        historyDetail.maximumNumberOfLines = 0
        historyDetail.widthAnchor.constraint(lessThanOrEqualToConstant: 540).isActive = true

        let observationDetail = NSTextField(
            wrappingLabelWithString: L10n.tr(
                "When enabled, records low-frequency, content-free health and performance checkpoints for the selected Slot, approximately once per minute. Requires local diagnostic history.",
                "开启后，大约每分钟为当前选中标签记录一次不含页面内容的低频健康与性能检查点（需同时开启本地诊断历史）。"
            )
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

        viewDiagnosticsButton.target = self
        viewDiagnosticsButton.action = #selector(viewDiagnostics(_:))
        viewDiagnosticsButton.isEnabled = recentEventsLoader != nil
        captureStuckTabButton.target = self
        captureStuckTabButton.action = #selector(captureStuckTab(_:))
        exportButton.target = self
        exportButton.action = #selector(exportDiagnostics(_:))
        openLogsButton.target = self
        openLogsButton.action = #selector(openLogs(_:))

        liveStatusLabel.font = .systemFont(ofSize: 11.5)
        liveStatusLabel.textColor = .secondaryLabelColor
        liveStatusLabel.maximumNumberOfLines = 0
        liveStatusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 540).isActive = true
        liveStatusLabel.isHidden = liveStatusProvider == nil

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 0

        let detailLevelRow = NSStackView(views: [
            NSTextField(labelWithString: L10n.tr("Detail level", "日志详细程度")),
            detailLevelPopup
        ])
        detailLevelRow.orientation = .horizontal
        detailLevelRow.alignment = .centerY
        detailLevelRow.spacing = 16

        var primaryActionViews: [NSView] = [viewDiagnosticsButton]
        if captureIncidentHandler != nil {
            primaryActionViews.append(captureStuckTabButton)
        }
        let primaryActions = NSStackView(views: primaryActionViews)
        primaryActions.orientation = .horizontal
        primaryActions.alignment = .centerY
        primaryActions.spacing = 8

        let secondaryActions = NSStackView(views: [exportButton, openLogsButton])
        secondaryActions.orientation = .horizontal
        secondaryActions.alignment = .centerY
        secondaryActions.spacing = 8

        var stackViews: [NSView] = [
            title,
            detail,
            keepLocalHistoryButton,
            historyDetail,
            detailLevelRow,
            longTermPerformanceObservationButton,
            observationDetail,
        ]
        if liveStatusProvider != nil {
            stackViews.append(liveStatusLabel)
        }
        stackViews.append(contentsOf: [
            primaryActions,
            secondaryActions,
            statusLabel
        ])

        let stack = NSStackView(views: stackViews)
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
            statusLabel.stringValue = L10n.tr("Local diagnostic history is on.", "本地诊断历史记录已开启。")
        } else {
            preferencesStore.runtimeDiagnosticsMode = .off
            statusLabel.stringValue = L10n.tr("Local diagnostic history is off.", "本地诊断历史记录已关闭。")
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
        statusLabel.stringValue = L10n.tr(
            "Saved \(mode.displayName) diagnostic detail.",
            "已保存诊断级别：\(mode.displayName)。"
        )
        synchronizeControls()
    }

    @objc private func longTermObservationChanged(_ sender: NSButton) {
        preferencesStore.longTermPerformanceObservationEnabled = sender.state == .on
        statusLabel.stringValue = sender.state == .on
            ? L10n.tr("Long-term performance observation is on.", "长期性能观测已开启。")
            : L10n.tr("Long-term performance observation is off.", "长期性能观测已关闭。")
        synchronizeControls()
    }

    @objc private func viewDiagnostics(_ sender: NSButton) {
        guard recentEventsLoader != nil else { return }
        if viewerWindowController == nil {
            viewerWindowController = RuntimeDiagnosticsViewerWindowController(
                preferencesStore: preferencesStore,
                liveStatusProvider: liveStatusProvider,
                recentEventsLoader: recentEventsLoader,
                captureIncidentHandler: captureIncidentHandler,
                exportHandler: exportHandler,
                openLogsHandler: openLogsHandler
            )
        }
        viewerWindowController?.presentAndRefresh()
    }

    @objc private func exportDiagnostics(_ sender: NSButton) {
        let panel = NSSavePanel()
        panel.title = L10n.tr("Export FloatTabs Diagnostics", "导出 FloatTabs 诊断日志")
        panel.nameFieldStringValue = RuntimeDiagnosticExporter.defaultFilename()
        panel.canCreateDirectories = true
        if let type = UTType(filenameExtension: "jsonl") {
            panel.allowedContentTypes = [type]
        }

        let complete: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            guard let self, response == .OK, let url = panel?.url else { return }
            self.exportButton.isEnabled = false
            self.statusLabel.stringValue = L10n.tr("Exporting…", "正在导出…")
            self.exportHandler(url) { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.exportButton.isEnabled = true
                    switch result {
                    case .success:
                        self.statusLabel.stringValue = L10n.tr(
                            "Exported diagnostics successfully.",
                            "诊断日志导出成功。"
                        )
                    case let .failure(error):
                        self.statusLabel.stringValue = L10n.tr(
                            "Export unavailable (\(error.diagnosticCategory)).",
                            "暂无法导出（\(error.diagnosticCategory)）。"
                        )
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

    @objc private func captureStuckTab(_ sender: NSButton) {
        guard let captureIncidentHandler else { return }
        statusLabel.stringValue = captureIncidentHandler()
        synchronizeControls()
        if viewerWindowController?.window?.isVisible == true {
            viewerWindowController?.reloadData()
        }
    }

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
        viewDiagnosticsButton.isEnabled = recentEventsLoader != nil
        if let liveStatus = liveStatusProvider?() {
            let summary = liveStatus.diagnosticsSummary
            var parts = [
                L10n.tr(
                    "Resident Tabs: \(liveStatus.residentSlotCount)/\(liveStatus.totalSlotCount)",
                    "常驻标签：\(liveStatus.residentSlotCount)/\(liveStatus.totalSlotCount)"
                ),
                L10n.tr(
                    "Session Events: \(summary.sessionEventCount) (Warn \(summary.sessionWarningCount), Err \(summary.sessionErrorCount))",
                    "本次事件：\(summary.sessionEventCount)（警告 \(summary.sessionWarningCount)，错误 \(summary.sessionErrorCount)）"
                )
            ]
            if let rss = liveStatus.hostResidentSizeBytes {
                let capped = Int64(min(rss, UInt64(Int64.max)))
                parts.append(
                    L10n.tr(
                        "Host App RSS: \(RuntimeDiagnosticsEventFormatter.formattedByteCount(capped)) (excludes WebKit processes)",
                        "主进程内存：\(RuntimeDiagnosticsEventFormatter.formattedByteCount(capped))（不含 WebKit 渲染进程）"
                    )
                )
            }
            liveStatusLabel.stringValue = parts.joined(separator: "  ·  ")
            liveStatusLabel.isHidden = false
        } else {
            liveStatusLabel.isHidden = true
        }
    }
}
