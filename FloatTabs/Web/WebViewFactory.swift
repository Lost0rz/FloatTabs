import AppKit
import Foundation
import WebKit

struct BrowserVersionCatalog: Equatable {
    var safari: String
    var chrome: String
    var edge: String

    static var current: BrowserVersionCatalog {
        BrowserVersionCatalog(
            safari: BrowserVersionResolver.safariVersion(),
            chrome: BrowserVersionResolver.chromeVersion(),
            edge: BrowserVersionResolver.edgeVersion()
        )
    }
}

enum BrowserVersionResolver {
    private static let fallbackSafari = "26.0"
    private static let fallbackChrome = "150.0.0.0"
    private static let fallbackEdge = "150.0.0.0"

    static func safariVersion() -> String {
        let paths = [
            "/Applications/Safari.app",
            "/System/Applications/Safari.app",
        ]
        return normalizedSafariVersion(applicationVersion(paths: paths) ?? fallbackSafari)
    }

    static func chromeVersion() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "/Applications/Google Chrome.app",
            "\(home)/Applications/Google Chrome.app",
        ]
        return normalizedChromiumVersion(applicationVersion(paths: paths) ?? fallbackChrome)
    }

    static func edgeVersion() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "/Applications/Microsoft Edge.app",
            "\(home)/Applications/Microsoft Edge.app",
        ]
        return normalizedChromiumVersion(applicationVersion(paths: paths) ?? fallbackEdge)
    }

    static func normalizedSafariVersion(_ version: String) -> String {
        let numeric = version.split(separator: ".").compactMap { Int($0) }
        guard let major = numeric.first else { return fallbackSafari }
        let minor = numeric.count > 1 ? numeric[1] : 0
        return "\(major).\(minor)"
    }

    static func normalizedChromiumVersion(_ version: String) -> String {
        var numeric = version.split(separator: ".").compactMap { Int($0) }
        guard !numeric.isEmpty else { return fallbackChrome }
        while numeric.count < 4 { numeric.append(0) }
        return numeric.prefix(4).map(String.init).joined(separator: ".")
    }

    private static func applicationVersion(paths: [String]) -> String? {
        for path in paths {
            guard let bundle = Bundle(path: path),
                  let value = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                  !value.isEmpty else {
                continue
            }
            return value
        }
        return nil
    }
}

/// Generates the HTTP/JavaScript browser identity while the real engine stays
/// WKWebView/WebKit. Website Mode and visible Window Size are intentionally
/// independent.
enum UserAgentProvider {
    static func userAgent(
        for renderingProfile: WebRenderingProfile,
        versions: BrowserVersionCatalog = .current
    ) -> String {
        let profile = renderingProfile.normalized()
        return userAgent(
            for: profile.effectiveBrowserIdentity,
            websiteMode: profile.effectiveWebsiteMode,
            customUserAgent: profile.customUserAgent,
            versions: versions
        )
    }

    static func userAgent(
        for identity: BrowserIdentity,
        websiteMode: WebsiteMode,
        customUserAgent: String? = nil,
        versions: BrowserVersionCatalog = .current
    ) -> String {
        let resolvedIdentity: BrowserIdentity
        if identity == .automatic {
            resolvedIdentity = websiteMode == .desktop ? .macosSafari : .iphoneSafari
        } else if identity == .custom,
                  customUserAgent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            resolvedIdentity = websiteMode == .desktop ? .macosSafari : .iphoneSafari
        } else {
            resolvedIdentity = identity
        }

        switch resolvedIdentity {
        case .automatic:
            return macOSSafari(version: versions.safari)
        case .macosSafari:
            return macOSSafari(version: versions.safari)
        case .macosChrome:
            return desktopChrome(platform: "Macintosh; Intel Mac OS X 10_15_7", version: versions.chrome)
        case .windowsChrome:
            return desktopChrome(platform: "Windows NT 10.0; Win64; x64", version: versions.chrome)
        case .linuxChrome:
            return desktopChrome(platform: "X11; Linux x86_64", version: versions.chrome)
        case .windowsEdge:
            return windowsEdge(
                chromeVersion: versions.chrome,
                edgeVersion: versions.edge
            )
        case .iphoneSafari:
            return iPhoneSafari(version: versions.safari)
        case .iphoneChrome:
            return iPhoneChrome(version: versions.chrome)
        case .androidChrome:
            return androidChrome(version: versions.chrome)
        case .custom:
            return customUserAgent?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? (websiteMode == .desktop
                    ? macOSSafari(version: versions.safari)
                    : iPhoneSafari(version: versions.safari))
        }
    }

    private static func macOSSafari(version: String) -> String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + "Version/\(version) Safari/605.1.15"
    }

    private static func iPhoneSafari(version: String) -> String {
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + "Version/\(version) Mobile/15E148 Safari/604.1"
    }

    private static func desktopChrome(platform: String, version: String) -> String {
        "Mozilla/5.0 (\(platform)) AppleWebKit/537.36 (KHTML, like Gecko) "
            + "Chrome/\(version) Safari/537.36"
    }

    private static func iPhoneChrome(version: String) -> String {
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + "CriOS/\(version) Mobile/15E148 Safari/604.1"
    }

    private static func androidChrome(version: String) -> String {
        "Mozilla/5.0 (Linux; Android 16; Pixel 10) AppleWebKit/537.36 (KHTML, like Gecko) "
            + "Chrome/\(version) Mobile Safari/537.36"
    }

    private static func windowsEdge(
        chromeVersion: String,
        edgeVersion: String
    ) -> String {
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            + "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(chromeVersion) "
            + "Safari/537.36 Edg/\(edgeVersion)"
    }
}

/// Separates the website's CSS/layout viewport from the visible FloatTabs
/// window. Desktop never collapses below a desktop-class 1280 CSS-pixel width,
/// while Mobile never expands beyond a phone-class 390 CSS-pixel width.
///
/// The returned height preserves the visible frame's aspect ratio so AppKit can
/// uniformly map the logical website coordinate system into the actual window
/// without stretching one axis independently from the other.
enum WebsiteLayoutViewport {
    static let desktopMinimumCSSWidth: CGFloat = 1280
    static let mobileMaximumCSSWidth: CGFloat = 390

    static func logicalSize(
        forVisibleSize visibleSize: CGSize,
        websiteMode: WebsiteMode
    ) -> CGSize {
        guard visibleSize.width > 0, visibleSize.height > 0 else {
            return visibleSize
        }

        let logicalWidth: CGFloat
        switch websiteMode {
        case .desktop:
            logicalWidth = max(desktopMinimumCSSWidth, visibleSize.width)
        case .mobile:
            logicalWidth = min(mobileMaximumCSSWidth, visibleSize.width)
        }

        let scale = logicalWidth / visibleSize.width
        return CGSize(
            width: logicalWidth,
            height: visibleSize.height * scale
        )
    }
}

@MainActor
enum WebViewFactory {
    static func makeWebView(
        renderingProfile: WebRenderingProfile = .canonicalDefault
    ) -> WKWebView {
        let rendering = renderingProfile.normalized()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.preferredContentMode = preferredContentMode(
            for: rendering.effectiveWebsiteMode
        )

        let webView = FloatTabsWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        applyRuntimeRendering(rendering, to: webView)
        configureHiddenScrollers(in: webView)
        return webView
    }

    static func makeStageZeroWebView() -> WKWebView {
        makeWebView()
    }

    static func preferredContentMode(
        for mode: WebsiteMode
    ) -> WKWebpagePreferences.ContentMode {
        switch mode {
        case .desktop: .desktop
        case .mobile: .mobile
        }
    }

    static func applyRuntimeRendering(
        _ renderingProfile: WebRenderingProfile,
        to webView: WKWebView
    ) {
        let rendering = renderingProfile.normalized()
        if let floatTabsWebView = webView as? FloatTabsWebView {
            floatTabsWebView.setWebsiteMode(rendering.effectiveWebsiteMode)
        }
        webView.customUserAgent = UserAgentProvider.userAgent(for: rendering)
        webView.pageZoom = rendering.zoom
    }

    /// At rest the WebView owns no visible AppKit scroller at all. This avoids
    /// inheriting the user's global "Show scroll bars: Always" preference.
    /// Scrollers are enabled only during active wheel/trackpad scrolling by the
    /// transient-scroller controller below.
    static func configureHiddenScrollers(in webView: WKWebView) {
        for scrollView in descendantScrollViews(in: webView) {
            configureHiddenScrollerStyle(scrollView)
        }
    }

    static func configureHiddenScrollerStyle(_ scrollView: NSScrollView) {
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
    }

    static func setScrollerVisibility(
        _ scrollView: NSScrollView,
        vertical: Bool,
        horizontal: Bool
    ) {
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = vertical
        scrollView.hasHorizontalScroller = horizontal

        if vertical || horizontal {
            scrollView.flashScrollers()
        }
    }

    static func loadStageZeroPage(in webView: WKWebView) {
        guard let pageURL = Bundle.main.url(
            forResource: "StageZeroTestPage",
            withExtension: "html"
        ) else {
            webView.loadHTMLString(fallbackHTML, baseURL: nil)
            return
        }

        webView.loadFileURL(
            pageURL,
            allowingReadAccessTo: pageURL.deletingLastPathComponent()
        )
    }

    static func descendantScrollViews(in view: NSView) -> [NSScrollView] {
        var result: [NSScrollView] = []

        for subview in view.subviews {
            if let scrollView = subview as? NSScrollView {
                result.append(scrollView)
            }
            result.append(contentsOf: descendantScrollViews(in: subview))
        }

        return result
    }

    private static let fallbackHTML = """
    <!doctype html>
    <html><body><h1>FloatTabs Stage 0</h1><input autofocus placeholder="Type here"></body></html>
    """
}

/// The visible NSView frame remains the user-selected FloatTabs Window Size.
/// Its bounds use the independent website layout coordinate system. AppKit then
/// performs a uniform frame↔bounds transform, so a narrow window can still host
/// a desktop CSS viewport and a wide window can still host a mobile CSS viewport.
@MainActor
final class FloatTabsWebView: WKWebView {
    private var transientScrollerController: TransientWebScrollerController?
    private var websiteMode: WebsiteMode = .desktop

    override init(frame frameRect: NSRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frameRect, configuration: configuration)
        transientScrollerController = TransientWebScrollerController(webView: self)
        applyWebsiteLayoutBounds(forVisibleSize: frameRect.size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setWebsiteMode(_ mode: WebsiteMode) {
        guard websiteMode != mode else {
            applyWebsiteLayoutBounds(forVisibleSize: frame.size)
            return
        }
        websiteMode = mode
        applyWebsiteLayoutBounds(forVisibleSize: frame.size)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        applyWebsiteLayoutBounds(forVisibleSize: newSize)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWebsiteLayoutBounds(forVisibleSize: frame.size)
        transientScrollerController?.refreshScrollerState()
    }

    private func applyWebsiteLayoutBounds(forVisibleSize visibleSize: CGSize) {
        guard visibleSize.width > 0, visibleSize.height > 0 else { return }
        let logicalSize = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: visibleSize,
            websiteMode: websiteMode
        )
        guard abs(bounds.width - logicalSize.width) > 0.5
                || abs(bounds.height - logicalSize.height) > 0.5 else {
            return
        }

        setBoundsSize(logicalSize)
        setBoundsOrigin(.zero)
        needsDisplay = true
    }
}

/// WKWebView retains this controller for its whole lifetime. The controller
/// watches local scroll-wheel events over this WebView and temporarily exposes
/// only the scroller axis that is actually moving. Once scrolling stops, both
/// AppKit scrollers are removed again so they cannot reserve or paint idle UI.
@MainActor
private final class TransientWebScrollerController {
    private weak var webView: WKWebView?
    private var localScrollMonitor: Any?
    private var hideWorkItem: DispatchWorkItem?

    private static let idleHideDelay: TimeInterval = 0.6
    private static let minimumDelta: CGFloat = 0.01

    init(webView: WKWebView) {
        self.webView = webView
        refreshScrollerState()

        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
            [weak self] event in
            self?.handleScrollWheel(event)
            return event
        }
    }

    deinit {
        hideWorkItem?.cancel()
        if let localScrollMonitor {
            NSEvent.removeMonitor(localScrollMonitor)
        }
    }

    func refreshScrollerState() {
        guard let webView else { return }
        WebViewFactory.configureHiddenScrollers(in: webView)
    }

    private func handleScrollWheel(_ event: NSEvent) {
        guard let webView,
              event.window === webView.window else {
            return
        }

        let location = webView.convert(event.locationInWindow, from: nil)
        guard webView.bounds.contains(location) else { return }

        let showVertical = abs(event.scrollingDeltaY) > Self.minimumDelta
        let showHorizontal = abs(event.scrollingDeltaX) > Self.minimumDelta
        guard showVertical || showHorizontal else { return }

        let scrollViews = WebViewFactory.descendantScrollViews(in: webView)
        for scrollView in scrollViews {
            WebViewFactory.setScrollerVisibility(
                scrollView,
                vertical: showVertical,
                horizontal: showHorizontal
            )
        }

        scheduleHide(for: scrollViews)
    }

    private func scheduleHide(for scrollViews: [NSScrollView]) {
        hideWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self, weak webView] in
            guard self != nil, webView != nil else { return }
            for scrollView in scrollViews {
                WebViewFactory.configureHiddenScrollerStyle(scrollView)
            }
        }

        hideWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.idleHideDelay,
            execute: item
        )
    }
}
