import AppKit
import Foundation
import WebKit

struct BrowserVersionCatalog: Equatable {
    var safari: String
    var webKit: String
    var chrome: String
    var edge: String

    @MainActor
    static var current: BrowserVersionCatalog {
        BrowserVersionCatalog(
            safari: BrowserVersionResolver.safariVersion(),
            webKit: BrowserVersionResolver.webKitVersion(),
            chrome: BrowserVersionResolver.chromeVersion(),
            edge: BrowserVersionResolver.edgeVersion()
        )
    }
}

enum BrowserVersionResolver {
    private static let fallbackSafari = "26.0"
    private static let fallbackWebKit = "605.1.15"
    private static let fallbackChrome = "150.0.0.0"
    private static let fallbackEdge = "150.0.0.0"

    @MainActor
    private static var cachedWebKitVersion: String?

    static func safariVersion() -> String {
        let paths = [
            "/Applications/Safari.app",
            "/System/Applications/Safari.app",
        ]
        return normalizedSafariVersion(applicationVersion(paths: paths) ?? fallbackSafari)
    }

    /// Mirrors DuckDuckGo macOS: ask the system WKWebView for its native UA and
    /// extract the AppleWebKit token instead of assuming a hard-coded engine
    /// version. This keeps the Safari-compatible identity aligned with the
    /// WebKit runtime actually rendering the page.
    @MainActor
    static func webKitVersion() -> String {
        if let cachedWebKitVersion {
            return cachedWebKitVersion
        }

        let webView = WKWebView(frame: .zero)
        guard let nativeUserAgent = webView.value(forKey: "userAgent") as? String,
              let version = firstMatch(
                pattern: #"AppleWebKit\s*/\s*([\d.]+)"#,
                in: nativeUserAgent
              ) else {
            cachedWebKitVersion = fallbackWebKit
            return fallbackWebKit
        }

        cachedWebKitVersion = version
        return version
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

    private static func firstMatch(pattern: String, in string: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: string,
                range: NSRange(string.startIndex..., in: string)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return String(string[range])
    }
}

/// Generates the HTTP/JavaScript browser identity while the real engine stays
/// WKWebView/WebKit. Website Mode, Window Size and Zoom remain separate inputs.
@MainActor
enum UserAgentProvider {
    /// DuckDuckGo macOS uses the same pattern: keep WKWebView's native base UA
    /// and append a Safari-compatible Version/Safari suffix. This preserves the
    /// real system WebKit token instead of replacing the whole UA unnecessarily.
    static func safariApplicationName() -> String {
        safariApplicationName(versions: .current)
    }

    static func safariApplicationName(
        versions: BrowserVersionCatalog
    ) -> String {
        "Version/\(versions.safari) Safari/\(versions.webKit)"
    }

    /// Runtime override. `nil` is deliberate for macOS Safari so WebKit can
    /// supply its native UA plus `applicationNameForUserAgent`.
    static func customUserAgent(
        for renderingProfile: WebRenderingProfile
    ) -> String? {
        customUserAgent(for: renderingProfile, versions: .current)
    }

    static func customUserAgent(
        for renderingProfile: WebRenderingProfile,
        versions: BrowserVersionCatalog
    ) -> String? {
        let profile = renderingProfile.normalized()
        let identity = resolvedIdentity(
            profile.effectiveBrowserIdentity,
            websiteMode: profile.effectiveWebsiteMode,
            customUserAgent: profile.customUserAgent
        )

        if identity == .macosSafari {
            return nil
        }

        return userAgent(
            for: identity,
            websiteMode: profile.effectiveWebsiteMode,
            customUserAgent: profile.customUserAgent,
            versions: versions
        )
    }

    static func userAgent(
        for renderingProfile: WebRenderingProfile
    ) -> String {
        userAgent(for: renderingProfile, versions: .current)
    }

    static func userAgent(
        for renderingProfile: WebRenderingProfile,
        versions: BrowserVersionCatalog
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
        customUserAgent: String? = nil
    ) -> String {
        userAgent(
            for: identity,
            websiteMode: websiteMode,
            customUserAgent: customUserAgent,
            versions: .current
        )
    }

    static func userAgent(
        for identity: BrowserIdentity,
        websiteMode: WebsiteMode,
        customUserAgent: String? = nil,
        versions: BrowserVersionCatalog
    ) -> String {
        switch resolvedIdentity(
            identity,
            websiteMode: websiteMode,
            customUserAgent: customUserAgent
        ) {
        case .automatic, .macosSafari:
            return macOSSafari(
                safariVersion: versions.safari,
                webKitVersion: versions.webKit
            )
        case .macosChrome:
            return desktopChrome(
                platform: "Macintosh; Intel Mac OS X 10_15_7",
                version: versions.chrome
            )
        case .windowsChrome:
            return desktopChrome(
                platform: "Windows NT 10.0; Win64; x64",
                version: versions.chrome
            )
        case .linuxChrome:
            return desktopChrome(
                platform: "X11; Linux x86_64",
                version: versions.chrome
            )
        case .windowsEdge:
            return windowsEdge(
                chromeVersion: versions.chrome,
                edgeVersion: versions.edge
            )
        case .iphoneSafari:
            return iPhoneSafari(
                safariVersion: versions.safari,
                webKitVersion: versions.webKit
            )
        case .iphoneChrome:
            return iPhoneChrome(
                chromeVersion: versions.chrome,
                webKitVersion: versions.webKit
            )
        case .androidChrome:
            return androidChrome(version: versions.chrome)
        case .custom:
            return customUserAgent?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? macOSSafari(
                    safariVersion: versions.safari,
                    webKitVersion: versions.webKit
                )
        }
    }

    private static func resolvedIdentity(
        _ identity: BrowserIdentity,
        websiteMode: WebsiteMode,
        customUserAgent: String?
    ) -> BrowserIdentity {
        if identity == .automatic {
            return websiteMode == .desktop ? .macosSafari : .iphoneSafari
        }

        if identity == .custom,
           customUserAgent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return websiteMode == .desktop ? .macosSafari : .iphoneSafari
        }

        return identity
    }

    private static func macOSSafari(
        safariVersion: String,
        webKitVersion: String
    ) -> String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            + "AppleWebKit/\(webKitVersion) (KHTML, like Gecko) "
            + "Version/\(safariVersion) Safari/\(webKitVersion)"
    }

    private static func iPhoneSafari(
        safariVersion: String,
        webKitVersion: String
    ) -> String {
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) "
            + "AppleWebKit/\(webKitVersion) (KHTML, like Gecko) "
            + "Version/\(safariVersion) Mobile/15E148 Safari/604.1"
    }

    private static func desktopChrome(platform: String, version: String) -> String {
        "Mozilla/5.0 (\(platform)) AppleWebKit/537.36 (KHTML, like Gecko) "
            + "Chrome/\(version) Safari/537.36"
    }

    private static func iPhoneChrome(
        chromeVersion: String,
        webKitVersion: String
    ) -> String {
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) "
            + "AppleWebKit/\(webKitVersion) (KHTML, like Gecko) "
            + "CriOS/\(chromeVersion) Mobile/15E148 Safari/604.1"
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

/// Pure V3 geometry: Website Mode controls the logical website layout viewport,
/// while Window Size controls only the visible FloatTabs Web frame.
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
        let versions = BrowserVersionCatalog.current
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.applicationNameForUserAgent = UserAgentProvider.safariApplicationName(
            versions: versions
        )
        configuration.defaultWebpagePreferences.preferredContentMode =
            rendering.effectiveWebsiteMode == .desktop ? .desktop : .mobile

        let webView = FloatTabsWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        applyRuntimeRendering(rendering, to: webView, versions: versions)
        configureHiddenScrollers(in: webView)
        return webView
    }

    static func makeStageZeroWebView() -> WKWebView {
        makeWebView()
    }

    static func applyRuntimeRendering(
        _ renderingProfile: WebRenderingProfile,
        to webView: WKWebView
    ) {
        applyRuntimeRendering(
            renderingProfile,
            to: webView,
            versions: .current
        )
    }

    static func applyRuntimeRendering(
        _ renderingProfile: WebRenderingProfile,
        to webView: WKWebView,
        versions: BrowserVersionCatalog
    ) {
        let rendering = renderingProfile.normalized()
        if let floatTabsWebView = webView as? FloatTabsWebView {
            floatTabsWebView.setWebsiteMode(rendering.effectiveWebsiteMode)
        }
        webView.customUserAgent = UserAgentProvider.customUserAgent(
            for: rendering,
            versions: versions
        )
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

/// WebPanelContainerView is the only owner of Stage 3 viewport presentation.
/// FloatTabsWebView keeps ordinary AppKit geometry: its bounds always match its
/// frame. The container gives it a real logical 1280/390-class frame and fits
/// that frame through a separate parent coordinate transform, so WebKit itself
/// is never hosted inside a magnified scroll view.
@MainActor
final class FloatTabsWebView: WKWebView {
    private var transientScrollerController: TransientWebScrollerController?
    private(set) var websiteMode: WebsiteMode = .desktop

    override init(frame frameRect: NSRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frameRect, configuration: configuration)
        transientScrollerController = TransientWebScrollerController(webView: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setWebsiteMode(_ mode: WebsiteMode) {
        websiteMode = mode
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        transientScrollerController?.refreshScrollerState()
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
