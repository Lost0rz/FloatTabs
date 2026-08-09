from pathlib import Path
import re

ROOT = Path('.')

def read(path):
    return (ROOT / path).read_text()

def write(path, text):
    (ROOT / path).write_text(text)

def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected 1 match, found {count}')
    return text.replace(old, new, 1)

# 1) Persistent product policy fields with backward-compatible decoding.
path = 'FloatTabs/Tabs/WebAppProfile.swift'
text = read(path)
text = replace_once(text, 'import Foundation\n\nstruct WebAppProfile', '''import Foundation

enum SlotResidencyPolicy: String, Codable, CaseIterable, Equatable {
    case hot
    case warm
    case cold

    var displayName: String {
        switch self {
        case .hot: return "Hot"
        case .warm: return "Warm"
        case .cold: return "Cold"
        }
    }

    var detailText: String {
        switch self {
        case .hot:
            return "Keep the live WebView attached. FloatTabs does not proactively evict it."
        case .warm:
            return "Keep the WebView in memory, but detach it from the visible presentation when inactive."
        case .cold:
            return "Release the WebView after 30 seconds inactive and recreate it from the current URL when needed."
        }
    }
}

enum BackgroundMediaPolicy: String, Codable, CaseIterable, Equatable {
    case pauseWhenInactive
    case allowBackgroundAudio

    var displayName: String {
        switch self {
        case .pauseWhenInactive: return "Pause When Inactive"
        case .allowBackgroundAudio: return "Allow Background Audio"
        }
    }
}

struct WebAppProfile''', 'profile enums')
text = replace_once(text,
'''    var renderingProfile: WebRenderingProfile
    var createdAt: Date''',
'''    var renderingProfile: WebRenderingProfile
    var residencyPolicy: SlotResidencyPolicy
    var backgroundMediaPolicy: BackgroundMediaPolicy
    var createdAt: Date''', 'profile fields')
text = replace_once(text,
'''        currentURL: URL? = nil,
        renderingProfile: WebRenderingProfile = .canonicalDefault,
        createdAt: Date = Date(),''',
'''        currentURL: URL? = nil,
        renderingProfile: WebRenderingProfile = .canonicalDefault,
        residencyPolicy: SlotResidencyPolicy = .warm,
        backgroundMediaPolicy: BackgroundMediaPolicy = .pauseWhenInactive,
        createdAt: Date = Date(),''', 'profile init args')
text = replace_once(text,
'''        self.renderingProfile = renderingProfile
        self.createdAt = createdAt''',
'''        self.renderingProfile = renderingProfile
        self.residencyPolicy = residencyPolicy
        self.backgroundMediaPolicy = backgroundMediaPolicy
        self.createdAt = createdAt''', 'profile init assignments')
codec = '''
extension WebAppProfile {
    private enum CodingKeys: String, CodingKey {
        case id
        case order
        case name
        case homeURL
        case currentURL
        case renderingProfile
        case residencyPolicy
        case backgroundMediaPolicy
        case createdAt
        case lastUsedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        order = try container.decode(Int.self, forKey: .order)
        name = try container.decode(String.self, forKey: .name)
        homeURL = try container.decode(URL.self, forKey: .homeURL)
        currentURL = try container.decodeIfPresent(URL.self, forKey: .currentURL)
        renderingProfile = try container.decode(WebRenderingProfile.self, forKey: .renderingProfile)
        residencyPolicy = try container.decodeIfPresent(
            SlotResidencyPolicy.self,
            forKey: .residencyPolicy
        ) ?? .warm
        backgroundMediaPolicy = try container.decodeIfPresent(
            BackgroundMediaPolicy.self,
            forKey: .backgroundMediaPolicy
        ) ?? .pauseWhenInactive
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastUsedAt = try container.decode(Date.self, forKey: .lastUsedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(order, forKey: .order)
        try container.encode(name, forKey: .name)
        try container.encode(homeURL, forKey: .homeURL)
        try container.encodeIfPresent(currentURL, forKey: .currentURL)
        try container.encode(renderingProfile, forKey: .renderingProfile)
        try container.encode(residencyPolicy, forKey: .residencyPolicy)
        try container.encode(backgroundMediaPolicy, forKey: .backgroundMediaPolicy)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastUsedAt, forKey: .lastUsedAt)
    }
}

'''
text = replace_once(text, '\nenum WebAppURL {', codec + 'enum WebAppURL {', 'profile codec')
write(path, text)

# 2) TabStore policy mutation seam.
path = 'FloatTabs/Tabs/TabStore.swift'
text = read(path)
needle = '''    @discardableResult
    func updatePreferredViewport(id: UUID, size: CGSize) -> Bool {'''
insert = '''    @discardableResult
    func updateResourcePolicy(
        id: UUID,
        residencyPolicy: SlotResidencyPolicy? = nil,
        backgroundMediaPolicy: BackgroundMediaPolicy? = nil
    ) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        var changed = false

        if let residencyPolicy, profiles[index].residencyPolicy != residencyPolicy {
            profiles[index].residencyPolicy = residencyPolicy
            changed = true
        }
        if let backgroundMediaPolicy,
           profiles[index].backgroundMediaPolicy != backgroundMediaPolicy {
            profiles[index].backgroundMediaPolicy = backgroundMediaPolicy
            changed = true
        }

        guard changed else { return true }
        persistAndNotify()
        return true
    }

'''
text = replace_once(text, needle, insert + needle, 'tab store policy seam')
write(path, text)

# 3) WebViewPool explicit cold release + media suspension seam.
path = 'FloatTabs/Web/WebViewPool.swift'
text = read(path)
old = '''    func remove(slotID: UUID) {
        discardPopupCoordinator(slotID: slotID)
        navigationObservers.removeValue(forKey: slotID)
        appliedRenderingProfiles.removeValue(forKey: slotID)
        lastKnownURLs.removeValue(forKey: slotID)
        deferredReloadSlotIDs.remove(slotID)
        webViews.removeValue(forKey: slotID)
    }
'''
new = '''    func remove(slotID: UUID) {
        release(slotID: slotID)
    }

    /// Releases only the transient live WebView/runtime state for a Slot. The
    /// persisted WebAppProfile, currentURL, cookies and shared website data stay
    /// outside this pool and therefore survive Cold eviction.
    func release(slotID: UUID) {
        discardPopupCoordinator(slotID: slotID)
        navigationObservers.removeValue(forKey: slotID)
        appliedRenderingProfiles.removeValue(forKey: slotID)
        lastKnownURLs.removeValue(forKey: slotID)
        deferredReloadSlotIDs.remove(slotID)
        webViews[slotID]?.removeFromSuperview()
        webViews.removeValue(forKey: slotID)
    }

    func setMediaPlaybackSuspended(slotID: UUID, suspended: Bool) {
        guard let webView = webViews[slotID] else { return }
        webView.setAllMediaPlaybackSuspended(suspended, completionHandler: nil)
    }
'''
text = replace_once(text, old, new, 'webview release/media')
write(path, text)

# 4) New lifecycle coordinator: policy owns behavior after a Slot stops being active.
write('FloatTabs/Web/SlotLifecycleCoordinator.swift', '''import Foundation

@MainActor
final class SlotLifecycleCoordinator {
    static let defaultColdReleaseDelay: TimeInterval = 30

    private let webViewPool: WebViewPool
    private unowned let container: WebPanelContainerView
    private let coldReleaseDelay: TimeInterval
    private var coldReleaseTokens: [UUID: UUID] = [:]

    init(
        webViewPool: WebViewPool,
        container: WebPanelContainerView,
        coldReleaseDelay: TimeInterval = SlotLifecycleCoordinator.defaultColdReleaseDelay
    ) {
        self.webViewPool = webViewPool
        self.container = container
        self.coldReleaseDelay = max(coldReleaseDelay, 0)
    }

    func reconcile(profiles: [WebAppProfile]) {
        let validIDs = Set(profiles.map(\\.id))
        let hotIDs = Set(profiles.filter { $0.residencyPolicy == .hot }.map(\\.id))
        let coldIDs = Set(profiles.filter { $0.residencyPolicy == .cold }.map(\\.id))

        container.retainHotSlots(hotIDs)

        for slotID in coldReleaseTokens.keys where !validIDs.contains(slotID) || !coldIDs.contains(slotID) {
            coldReleaseTokens.removeValue(forKey: slotID)
        }
    }

    func activate(profile: WebAppProfile) {
        coldReleaseTokens.removeValue(forKey: profile.id)
        webViewPool.setMediaPlaybackSuspended(slotID: profile.id, suspended: false)
    }

    func deactivate(profile: WebAppProfile) {
        container.deactivate(slotID: profile.id, residencyPolicy: profile.residencyPolicy)

        switch profile.backgroundMediaPolicy {
        case .pauseWhenInactive:
            webViewPool.setMediaPlaybackSuspended(slotID: profile.id, suspended: true)
        case .allowBackgroundAudio:
            webViewPool.setMediaPlaybackSuspended(slotID: profile.id, suspended: false)
        }

        switch profile.residencyPolicy {
        case .hot, .warm:
            coldReleaseTokens.removeValue(forKey: profile.id)
        case .cold:
            scheduleColdRelease(slotID: profile.id)
        }
    }

    func remove(slotID: UUID) {
        coldReleaseTokens.removeValue(forKey: slotID)
        container.removeSlot(slotID)
    }

    var pendingColdReleaseCount: Int {
        coldReleaseTokens.count
    }

    private func scheduleColdRelease(slotID: UUID) {
        let token = UUID()
        coldReleaseTokens[slotID] = token

        DispatchQueue.main.asyncAfter(deadline: .now() + coldReleaseDelay) { [weak self] in
            guard let self,
                  self.coldReleaseTokens[slotID] == token else {
                return
            }
            self.coldReleaseTokens.removeValue(forKey: slotID)
            self.container.removeSlot(slotID)
            self.webViewPool.release(slotID: slotID)
        }
    }
}
''')

# 5) Replace the visible-container tail with independent Hot presentation hosts.
path = 'FloatTabs/Web/WebViewContainer.swift'
text = read(path)
marker = 'final class WebPanelContainerView: NSView {'
index = text.find(marker)
if index < 0:
    raise RuntimeError('web container marker not found')
prefix = text[:index]
replacement = r'''final class WebSlotHostView: NSView {
    private(set) weak var webView: WKWebView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = []
    }

    convenience init(webView: WKWebView) {
        self.init(frame: .zero)
        attach(webView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(_ webView: WKWebView) {
        if self.webView !== webView {
            self.webView?.removeFromSuperview()
            webView.removeFromSuperview()
            webView.translatesAutoresizingMaskIntoConstraints = true
            webView.autoresizingMask = [.width, .height]
            addSubview(webView)
            self.webView = webView
        }
        webView.frame = bounds
    }

    override func layout() {
        super.layout()
        if webView?.frame != bounds {
            webView?.frame = bounds
        }
    }
}

/// Owns the visible FloatTabs web surface. Warm/Cold use the accepted Stage 4
/// transient host. Hot Slots instead receive one independent host each, so an
/// inactive Hot WebView can stay attached to the FloatTabs window without being
/// resized when another Slot has a different Window Size preset.
final class WebPanelContainerView: NSView {
    private let clipView = NSView()
    private let logicalHostView = NSView()
    private let emptyView = EmptyWebAppView()
    private weak var currentContentView: NSView?
    private weak var hostedWebView: WKWebView?
    private weak var activeWebView: WKWebView?
    private var activeSlotID: UUID?
    private var hotHostViews: [UUID: WebSlotHostView] = [:]

    private(set) var websiteLayoutScale: CGFloat = 1

    var currentWebView: WKWebView? {
        activeWebView
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureShell()
        showEmptyState()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Compatibility seam used by existing Stage 4 tests and the Stage 0 helper.
    /// Product Slot switching should call the policy-aware overload below.
    func show(webView: WKWebView) {
        showTransient(webView: webView, slotID: nil)
    }

    func show(
        webView: WKWebView,
        slotID: UUID,
        residencyPolicy: SlotResidencyPolicy
    ) {
        switch residencyPolicy {
        case .hot:
            showHot(webView: webView, slotID: slotID)
        case .warm, .cold:
            showTransient(webView: webView, slotID: slotID)
        }
    }

    func deactivate(slotID: UUID, residencyPolicy: SlotResidencyPolicy) {
        guard activeSlotID == slotID else { return }

        switch residencyPolicy {
        case .hot:
            if let host = hotHostViews[slotID] {
                // Freeze the outgoing Hot viewport before another Slot changes
                // the panel size. Only an active Hot host follows live resizing.
                host.autoresizingMask = []
            }
        case .warm, .cold:
            hostedWebView?.removeFromSuperview()
            hostedWebView = nil
        }

        activeSlotID = nil
        activeWebView = nil
    }

    func retainHotSlots(_ validHotSlotIDs: Set<UUID>) {
        for slotID in hotHostViews.keys where !validHotSlotIDs.contains(slotID) {
            guard let host = hotHostViews.removeValue(forKey: slotID) else { continue }
            host.webView?.removeFromSuperview()
            host.removeFromSuperview()
        }
    }

    func removeSlot(_ slotID: UUID) {
        if activeSlotID == slotID {
            hostedWebView?.removeFromSuperview()
            hostedWebView = nil
            activeWebView = nil
            activeSlotID = nil
        }
        if let host = hotHostViews.removeValue(forKey: slotID) {
            host.webView?.removeFromSuperview()
            host.removeFromSuperview()
        }
    }

    func showEmptyState() {
        guard currentContentView !== emptyView else { return }
        hostedWebView?.removeFromSuperview()
        hostedWebView = nil
        activeWebView = nil
        activeSlotID = nil
        websiteLayoutScale = 1
        logicalHostView.bounds = NSRect(origin: .zero, size: logicalHostView.frame.size)
        setContentView(emptyView)
        emptyView.isHidden = false
        bringToFront(emptyView)
    }

    override func layout() {
        super.layout()
        if activeSlotID == nil || hostedWebView != nil {
            updateWebsiteLayoutIfNeeded()
        }
        layer?.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: PanelMetrics.webPanelCornerRadius,
            cornerHeight: PanelMetrics.webPanelCornerRadius,
            transform: nil
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSemanticColors()
        for host in hotHostViews.values {
            host.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }

    private func showHot(webView: WKWebView, slotID: UUID) {
        hostedWebView?.removeFromSuperview()
        hostedWebView = nil
        currentContentView?.isHidden = true

        let host: WebSlotHostView
        if let existing = hotHostViews[slotID] {
            host = existing
            host.attach(webView)
        } else {
            host = WebSlotHostView(webView: webView)
            hotHostViews[slotID] = host
            host.frame = clipView.bounds
            clipView.addSubview(host)
        }

        host.frame = clipView.bounds
        host.autoresizingMask = [.width, .height]
        host.isHidden = false
        host.layoutSubtreeIfNeeded()
        bringToFront(host)

        websiteLayoutScale = 1
        activeSlotID = slotID
        activeWebView = webView
    }

    private func showTransient(webView: WKWebView, slotID: UUID?) {
        if hostedWebView !== webView {
            hostedWebView?.removeFromSuperview()
            webView.removeFromSuperview()
            webView.translatesAutoresizingMaskIntoConstraints = true
            webView.autoresizingMask = []
            logicalHostView.addSubview(webView)
            hostedWebView = webView
        }

        if currentContentView !== logicalHostView {
            setContentView(logicalHostView)
        }
        logicalHostView.isHidden = false
        bringToFront(logicalHostView)

        activeSlotID = slotID
        activeWebView = webView
        needsLayout = true
        layoutSubtreeIfNeeded()
        updateWebsiteLayoutIfNeeded()
    }

    private func configureShell() {
        wantsLayer = true
        layer?.cornerRadius = PanelMetrics.webPanelCornerRadius
        layer?.borderWidth = PanelMetrics.structuralBorderWidth
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.30
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -10)

        clipView.wantsLayer = true
        clipView.layer?.cornerRadius = PanelMetrics.webPanelCornerRadius
        clipView.layer?.masksToBounds = true
        clipView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clipView)

        NSLayoutConstraint.activate([
            clipView.leadingAnchor.constraint(equalTo: leadingAnchor),
            clipView.trailingAnchor.constraint(equalTo: trailingAnchor),
            clipView.topAnchor.constraint(equalTo: topAnchor),
            clipView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        updateSemanticColors()
    }

    private func setContentView(_ view: NSView) {
        currentContentView?.removeFromSuperview()
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        clipView.addSubview(view)

        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            view.topAnchor.constraint(equalTo: clipView.topAnchor),
            view.bottomAnchor.constraint(equalTo: clipView.bottomAnchor),
        ])

        currentContentView = view
    }

    private func bringToFront(_ view: NSView) {
        guard view.superview === clipView,
              let index = clipView.subviews.firstIndex(where: { $0 === view }) else {
            return
        }
        var ordered = clipView.subviews
        let selected = ordered.remove(at: index)
        ordered.append(selected)
        clipView.subviews = ordered
    }

    private func updateWebsiteLayoutIfNeeded() {
        guard let webView = hostedWebView else { return }

        let visibleSize = clipView.bounds.size
        guard visibleSize.width > 0, visibleSize.height > 0 else { return }

        let mode = (webView as? FloatTabsWebView)?.websiteMode
            ?? (webView.configuration.defaultWebpagePreferences.preferredContentMode == .mobile
                ? .mobile
                : .desktop)
        let logicalSize = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: visibleSize,
            websiteMode: mode
        )
        guard logicalSize.width > 0, logicalSize.height > 0 else { return }

        websiteLayoutScale = visibleSize.width / logicalSize.width

        if abs(webView.frame.width - logicalSize.width) > 0.5
            || abs(webView.frame.height - logicalSize.height) > 0.5 {
            webView.frame = NSRect(origin: .zero, size: logicalSize)
        }

        if abs(logicalHostView.bounds.width - logicalSize.width) > 0.5
            || abs(logicalHostView.bounds.height - logicalSize.height) > 0.5
            || logicalHostView.bounds.origin != .zero {
            logicalHostView.bounds = NSRect(origin: .zero, size: logicalSize)
        }
    }

    private func updateSemanticColors() {
        let fallback = NSColor.windowBackgroundColor
        layer?.backgroundColor = fallback.cgColor
        clipView.layer?.backgroundColor = fallback.cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
    }
}
'''
write(path, prefix + replacement)

# 6) PanelController transition wiring.
path = 'FloatTabs/Panel/PanelController.swift'
text = read(path)
text = replace_once(text,
'''    private let quickURLOverlayView = QuickURLOverlayView()
    private let zoomHUDView = ZoomHUDView()

    private var moveHoverController: PanelMoveHoverController?''',
'''    private let quickURLOverlayView = QuickURLOverlayView()
    private let zoomHUDView = ZoomHUDView()
    private lazy var slotLifecycleCoordinator = SlotLifecycleCoordinator(
        webViewPool: webViewPool,
        container: rootView.webPanelContainerView
    )

    private var moveHoverController: PanelMoveHoverController?''', 'panel lifecycle property')
text = replace_once(text,
'''    private var hasPositionedPanel = false
    private var lastSynchronizedActiveID: UUID?
    private var followPreferredSize: Bool''',
'''    private var hasPositionedPanel = false
    private var lastSynchronizedActiveID: UUID?
    private var lastSynchronizedActiveProfile: WebAppProfile?
    private var followPreferredSize: Bool''', 'panel previous profile')
text = replace_once(text,
'''        rail.onRemove = { [weak self] id in
            self?.presentRemoveConfirmation(id: id)
        }
        rail.onReorder = { [weak self] id, destination in''',
'''        rail.onRemove = { [weak self] id in
            self?.presentRemoveConfirmation(id: id)
        }
        rail.onSetResidency = { [weak self] id, policy in
            _ = self?.tabStore.updateResourcePolicy(id: id, residencyPolicy: policy)
        }
        rail.onSetBackgroundMedia = { [weak self] id, policy in
            _ = self?.tabStore.updateResourcePolicy(id: id, backgroundMediaPolicy: policy)
        }
        rail.onReorder = { [weak self] id, destination in''', 'panel resource menu callbacks')
pattern = re.compile(r'    private func synchronizeSlotState\(\) \{.*?\n    \}\n\n    private func focusActiveWebViewIfAvailable', re.S)
match = pattern.search(text)
if not match:
    raise RuntimeError('panel synchronize method not found')
replacement_sync = '''    private func synchronizeSlotState() {
        let orderedProfiles = tabStore.orderedProfiles
        rootView.externalControlZoneView.apply(
            profiles: orderedProfiles,
            activeTabID: tabStore.activeTabID
        )
        slotLifecycleCoordinator.reconcile(profiles: orderedProfiles)

        guard let activeProfile = tabStore.activeProfile else {
            if let previous = lastSynchronizedActiveProfile {
                slotLifecycleCoordinator.deactivate(profile: previous)
            }
            lastSynchronizedActiveID = nil
            lastSynchronizedActiveProfile = nil
            rootView.webPanelContainerView.showEmptyState()
            return
        }

        let activeChanged = lastSynchronizedActiveID != activeProfile.id
        if activeChanged,
           let previous = lastSynchronizedActiveProfile,
           previous.id != activeProfile.id {
            slotLifecycleCoordinator.deactivate(profile: previous)
        }

        if activeChanged, hasPositionedPanel, followPreferredSize {
            applyPreferredViewport(activeProfile.renderingProfile.viewportSize)
        }

        let webView = webViewPool.webView(for: activeProfile)
        rootView.webPanelContainerView.show(
            webView: webView,
            slotID: activeProfile.id,
            residencyPolicy: activeProfile.residencyPolicy
        )
        slotLifecycleCoordinator.activate(profile: activeProfile)
        WebViewFactory.configureHiddenScrollers(in: webView)
        lastSynchronizedActiveID = activeProfile.id
        lastSynchronizedActiveProfile = activeProfile

        if panel.isKeyWindow {
            _ = panel.makeFirstResponder(webView)
        }
    }

    private func focusActiveWebViewIfAvailable'''
text = text[:match.start()] + replacement_sync + text[match.end():]
text = replace_once(text,
'''                _ = self.tabStore.remove(id: id)
                self.webViewPool.remove(slotID: id)''',
'''                _ = self.tabStore.remove(id: id)
                self.slotLifecycleCoordinator.remove(slotID: id)
                self.webViewPool.remove(slotID: id)''', 'panel remove lifecycle')
write(path, text)

# 7) Right-click policy controls. Main rail ordering remains independent.
path = 'FloatTabs/UI/ExternalTabRail.swift'
text = read(path)
text = replace_once(text,
'''    var onEdit: ((UUID) -> Void)?
    var onRemove: ((UUID) -> Void)?
    var onReorder: ((UUID, Int) -> Void)?''',
'''    var onEdit: ((UUID) -> Void)?
    var onRemove: ((UUID) -> Void)?
    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?
    var onSetBackgroundMedia: ((UUID, BackgroundMediaPolicy) -> Void)?
    var onReorder: ((UUID, Int) -> Void)?''', 'rail callbacks')
text = replace_once(text,
'''        view.onEdit = { [weak self] slotID in self?.onEdit?(slotID) }
        view.onRemove = { [weak self] slotID in self?.onRemove?(slotID) }
        view.onPointerMoved = { [weak self] event in''',
'''        view.onEdit = { [weak self] slotID in self?.onEdit?(slotID) }
        view.onRemove = { [weak self] slotID in self?.onRemove?(slotID) }
        view.onSetResidency = { [weak self] slotID, policy in
            self?.onSetResidency?(slotID, policy)
        }
        view.onSetBackgroundMedia = { [weak self] slotID, policy in
            self?.onSetBackgroundMedia?(slotID, policy)
        }
        view.onPointerMoved = { [weak self] event in''', 'rail callback wiring')
text = replace_once(text,
'''    var onEdit: ((UUID) -> Void)?
    var onRemove: ((UUID) -> Void)?
    var onPointerMoved: ((NSEvent) -> Void)?''',
'''    var onEdit: ((UUID) -> Void)?
    var onRemove: ((UUID) -> Void)?
    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?
    var onSetBackgroundMedia: ((UUID, BackgroundMediaPolicy) -> Void)?
    var onPointerMoved: ((NSEvent) -> Void)?''', 'tab callbacks')
text = replace_once(text,
'''    private var mouseDownLocation: NSPoint?
    private var isDragging = false
''',
'''    private var mouseDownLocation: NSPoint?
    private var isDragging = false
    private var residencyPolicy: SlotResidencyPolicy = .warm
    private var backgroundMediaPolicy: BackgroundMediaPolicy = .pauseWhenInactive
''', 'tab policy state')
text = replace_once(text,
'''    func update(profile: WebAppProfile, isActive: Bool) {
        label.stringValue = profile.name
        toolTip = profile.name
        self.isActive = isActive
        updateAppearance()
    }
''',
'''    func update(profile: WebAppProfile, isActive: Bool) {
        label.stringValue = profile.name
        residencyPolicy = profile.residencyPolicy
        backgroundMediaPolicy = profile.backgroundMediaPolicy
        toolTip = "\\(profile.name) · \\(profile.residencyPolicy.displayName)"
        self.isActive = isActive
        updateAppearance()
    }
''', 'tab update policy')
menu_pattern = re.compile(r'    override func menu\(for event: NSEvent\) -> NSMenu\? \{.*?\n    \}\n\n    override func viewDidChangeEffectiveAppearance', re.S)
menu_match = menu_pattern.search(text)
if not menu_match:
    raise RuntimeError('tab context menu not found')
menu_replacement = '''    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        let home = NSMenuItem(
            title: "Return to Home",
            action: #selector(returnHomeFromMenu),
            keyEquivalent: "h"
        )
        home.keyEquivalentModifierMask = [.command, .shift]
        home.target = self
        menu.addItem(home)
        menu.addItem(.separator())

        let residency = NSMenuItem(title: "Residency", action: nil, keyEquivalent: "")
        let residencyMenu = NSMenu(title: "Residency")
        for policy in SlotResidencyPolicy.allCases {
            let item = NSMenuItem(
                title: policy.displayName,
                action: #selector(setResidencyFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = policy.rawValue
            item.state = policy == residencyPolicy ? .on : .off
            residencyMenu.addItem(item)
        }
        residency.submenu = residencyMenu
        menu.addItem(residency)

        let media = NSMenuItem(title: "Background Media", action: nil, keyEquivalent: "")
        let mediaMenu = NSMenu(title: "Background Media")
        for policy in BackgroundMediaPolicy.allCases {
            let item = NSMenuItem(
                title: policy.displayName,
                action: #selector(setBackgroundMediaFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = policy.rawValue
            item.state = policy == backgroundMediaPolicy ? .on : .off
            mediaMenu.addItem(item)
        }
        media.submenu = mediaMenu
        menu.addItem(media)
        menu.addItem(.separator())

        let edit = NSMenuItem(title: "Edit Web App…", action: #selector(editFromMenu), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)

        menu.addItem(.separator())

        let remove = NSMenuItem(title: "Remove Web App…", action: #selector(removeFromMenu), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)
        return menu
    }

    override func viewDidChangeEffectiveAppearance'''
text = text[:menu_match.start()] + menu_replacement + text[menu_match.end():]
text = replace_once(text,
'''    @objc private func editFromMenu() {
        onEdit?(slotID)
    }

    @objc private func removeFromMenu() {''',
'''    @objc private func editFromMenu() {
        onEdit?(slotID)
    }

    @objc private func setResidencyFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let policy = SlotResidencyPolicy(rawValue: rawValue) else { return }
        onSetResidency?(slotID, policy)
    }

    @objc private func setBackgroundMediaFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let policy = BackgroundMediaPolicy(rawValue: rawValue) else { return }
        onSetBackgroundMedia?(slotID, policy)
    }

    @objc private func removeFromMenu() {''', 'tab resource selectors')
write(path, text)

# 8) Xcode project registration for the structured lifecycle file.
path = 'FloatTabs.xcodeproj/project.pbxproj'
text = read(path)
text = replace_once(text,
'''\t\tA00000000000000000000014 /* WebViewPool.swift in Sources */ = {isa = PBXBuildFile; fileRef = B00000000000000000000015 /* WebViewPool.swift */; };''',
'''\t\tA00000000000000000000014 /* WebViewPool.swift in Sources */ = {isa = PBXBuildFile; fileRef = B00000000000000000000015 /* WebViewPool.swift */; };\n\t\tA00000000000000000000021 /* SlotLifecycleCoordinator.swift in Sources */ = {isa = PBXBuildFile; fileRef = B00000000000000000000021 /* SlotLifecycleCoordinator.swift */; };''', 'pbx build file')
text = replace_once(text,
'''\t\tB00000000000000000000015 /* WebViewPool.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WebViewPool.swift; sourceTree = "<group>"; };''',
'''\t\tB00000000000000000000015 /* WebViewPool.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WebViewPool.swift; sourceTree = "<group>"; };\n\t\tB00000000000000000000021 /* SlotLifecycleCoordinator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SlotLifecycleCoordinator.swift; sourceTree = "<group>"; };''', 'pbx file ref')
text = replace_once(text,
'''\t\t\t\tB00000000000000000000015 /* WebViewPool.swift */,''',
'''\t\t\t\tB00000000000000000000015 /* WebViewPool.swift */,\n\t\t\t\tB00000000000000000000021 /* SlotLifecycleCoordinator.swift */,''', 'pbx web group')
text = replace_once(text,
'''\t\t\t\tA00000000000000000000014 /* WebViewPool.swift in Sources */,''',
'''\t\t\t\tA00000000000000000000014 /* WebViewPool.swift in Sources */,\n\t\t\t\tA00000000000000000000021 /* SlotLifecycleCoordinator.swift in Sources */,''', 'pbx sources phase')
write(path, text)

# 9) Regression tests.
path = 'FloatTabsTests/ProfileRepositoryTests.swift'
text = read(path)
text = replace_once(text,
'''            XCTAssertEqual(profile.renderingProfile.zoom, 1.25, accuracy: 0.001)
''',
'''            XCTAssertEqual(profile.renderingProfile.zoom, 1.25, accuracy: 0.001)
            XCTAssertEqual(profile.residencyPolicy, .warm)
            XCTAssertEqual(profile.backgroundMediaPolicy, .pauseWhenInactive)
''', 'legacy policy defaults test')
write(path, text)

path = 'FloatTabsTests/WebViewPoolTests.swift'
text = read(path)
needle = '''    func testWebContentRecoveryPolicyReloadsActiveAndDefersInactiveSlots() {'''
insert = '''    func testColdReleaseDropsOnlyRequestedLiveWebView() {
        let pool = makePool()
        let first = makeProfile(name: "A")
        let second = makeProfile(name: "B")
        _ = pool.webView(for: first)
        let secondView = pool.webView(for: second)

        pool.release(slotID: first.id)

        XCTAssertFalse(pool.contains(slotID: first.id))
        XCTAssertTrue(pool.contains(slotID: second.id))
        XCTAssertTrue(pool.webView(for: second) === secondView)
        XCTAssertEqual(pool.count, 1)
    }

'''
text = replace_once(text, needle, insert + needle, 'cold release test')
write(path, text)

path = 'FloatTabsTests/WebViewFactoryTests.swift'
text = read(path)
needle = '''    func testDesktopPublicPageZoomKeepsNativeClickHitTestingWorking() {'''
insert = '''    func testHotHostsPreserveInactiveViewportAcrossDifferentSlotSizes() {
        _ = NSApplication.shared
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 430, height: 820)
        )
        let window = NSWindow(
            contentRect: container.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        container.layoutSubtreeIfNeeded()

        let firstID = UUID()
        let secondID = UUID()
        let first = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let second = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)

        container.show(webView: first, slotID: firstID, residencyPolicy: .hot)
        container.layoutSubtreeIfNeeded()
        let firstSize = first.frame.size
        XCTAssertTrue(first.window === window)

        container.deactivate(slotID: firstID, residencyPolicy: .hot)
        container.setFrameSize(NSSize(width: 900, height: 850))
        container.layoutSubtreeIfNeeded()

        XCTAssertEqual(first.frame.size, firstSize)
        XCTAssertTrue(first.window === window)

        container.show(webView: second, slotID: secondID, residencyPolicy: .hot)
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(second.frame.size, NSSize(width: 900, height: 850))
        XCTAssertEqual(first.frame.size, firstSize)
        XCTAssertTrue(first.window === window)
        XCTAssertTrue(second.window === window)
    }

'''
text = replace_once(text, needle, insert + needle, 'hot viewport isolation test')
write(path, text)

path = 'FloatTabsTests/ExternalShellTests.swift'
text = read(path)
text = replace_once(text,
'''        XCTAssertEqual(
            actionTitles,
            ["Return to Home", "Edit Web App…", "Remove Web App…"]
        )''',
'''        XCTAssertEqual(
            actionTitles,
            ["Return to Home", "Residency", "Background Media", "Edit Web App…", "Remove Web App…"]
        )
        XCTAssertEqual(menu.item(withTitle: "Residency")?.submenu?.items.map(\\.title), ["Hot", "Warm", "Cold"])
        XCTAssertEqual(
            menu.item(withTitle: "Background Media")?.submenu?.items.map(\\.title),
            ["Pause When Inactive", "Allow Background Audio"]
        )''', 'context menu tests')
write(path, text)

# 10) Stage 5 product/engineering contract for this experimental PR.
write('docs/product/FloatTabs_Stage_5_Residency_Policy.md', '''# FloatTabs — Stage 5 Slot Residency Policy

> Status: experimental implementation for Real-Mac acceptance  
> Base: Stage 4 frozen `main` at `5df23da01fe37c08c8ecb4dd9a5f37f5a0c0ba21`

## 1. Product model

`Active` is a presentation state, not a residency tier. A selected Slot is always active and interactive. The per-Slot residency policy controls what FloatTabs does after that Slot becomes inactive.

### Hot

- FloatTabs does not proactively detach or evict the live `WKWebView`.
- Each Hot Slot owns an independent AppKit presentation host.
- The inactive Hot host freezes its last active viewport before another Slot changes panel size.
- Only the active Hot host follows live panel resizing.
- This is intended for state-heavy applications such as long ChatGPT conversations.

### Warm

- The `WKWebView` stays in `WebViewPool`.
- It is detached from the visible presentation while inactive.
- Re-selection reuses the same `WKWebView` object.
- DOM/SPA/scroll preservation remains best-effort because WebKit may suspend detached content.

### Cold

- On deactivation, the Slot receives a 30-second grace period.
- If it is not reactivated, FloatTabs releases its live `WKWebView`, navigation observer and popup runtime.
- `WebAppProfile`, `homeURL`, `currentURL`, rendering profile and persistent `WKWebsiteDataStore.default()` are retained.
- Re-selection recreates the WebView and loads the persisted `currentURL` with normal protocol caching.

## 2. Background media policy

This is independent from residency:

- `Pause When Inactive` uses WebKit media suspension while the Slot is inactive.
- `Allow Background Audio` leaves media unsuspended while the WebView remains resident.
- A Cold Slot can still be released after its grace period; release ends any remaining media runtime.

## 3. Interaction

The main Slot rail remains a pure ordering surface. Dragging changes only Slot order and therefore keeps the existing `⌘1…⌘9` semantics.

Right-click a Slot to configure:

```text
Return to Home
────────────
Residency
  Hot
  Warm
  Cold
Background Media
  Pause When Inactive
  Allow Background Audio
────────────
Edit Web App…
────────────
Remove Web App…
```

No drag-between-resource-zones behavior is introduced in this first implementation because that would overload the existing reorder gesture.

## 4. Stage 4 non-regression boundary

This PR must not change:

- Website Mode semantics;
- per-Slot Window Size semantics;
- independent Zoom;
- browser identity / ChatGPT compatibility policy;
- Bilibili Desktop click behavior;
- Bilibili Mobile real mobile layout;
- Navigation Intent / Slot Home;
- upload/download/OAuth behavior;
- WebContent process recovery;
- persistent website data.

The rejected Stage 4 experiment that resized multiple resident WebViews through one shared variable viewport must not be reintroduced.

## 5. Real-Mac acceptance

### Hot / ChatGPT

1. Set a long ChatGPT conversation to `Hot`.
2. Open it fully, switch repeatedly through Bilibili / YouTube, then return.
3. ChatGPT should remain correctly scaled and should materially improve return-to-interaction latency.
4. Bilibili and YouTube must retain their own correct Window Size / Website Mode / Zoom.

### Warm / video site

1. Set Bilibili or YouTube to `Warm` + `Pause When Inactive`.
2. Start media and switch away.
3. Media should suspend while inactive and the same pooled WebView should be reused on return.

### Background audio

1. Set YouTube to `Warm` + `Allow Background Audio`.
2. Start audio and switch away.
3. Audio should remain allowed while the Warm WebView remains resident.

### Cold

1. Set a disposable test Slot to `Cold`.
2. Switch away for more than 30 seconds.
3. Return to it.
4. It should recreate from `currentURL`; persistent login/session should remain where WebKit supports it.

## 6. Measurement after UX acceptance

Only after the above behavior is accepted should Stage 5 record 1 / 3 / 6 Slot CPU, memory, energy and network baselines and decide whether Hot-count warnings or different Cold timing are necessary.
''')

print('Stage 5 residency patch applied successfully')
