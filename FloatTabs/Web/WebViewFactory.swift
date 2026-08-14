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
    /// Keep WKWebView's native base UA and append a Safari-compatible suffix.
    static func safariApplicationName() -> String {
        safariApplicationName(versions: .current)
    }

    static func safariApplicationName(
        versions: BrowserVersionCatalog
    ) -> String {
        "Version/\(versions.safari) Safari/\(versions.webKit)"
    }

    /// Runtime override. Automatic deliberately stays `nil` so WebKit can pair
    /// the requested content mode with its native current UA. Explicit identities
    /// remain compatibility overrides and may replace that native identity.
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

        if profile.browserIdentity == .automatic {
            guard profile.effectiveWebsiteMode == .mobile else { return nil }
            return userAgent(
                for: .iphoneSafari,
                websiteMode: .mobile,
                versions: versions
            )
        }

        let identity = resolvedIdentity(
            profile.effectiveBrowserIdentity,
            customUserAgent: profile.customUserAgent
        )

        if identity == .macosSafari,
           profile.effectiveWebsiteMode == .desktop {
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
        let resolved = identity == .automatic
            ? (websiteMode == .desktop ? BrowserIdentity.macosSafari : .iphoneSafari)
            : resolvedIdentity(identity, customUserAgent: customUserAgent)

        switch resolved {
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

    /// Normalizes explicit compatibility identities. Automatic is resolved by
    /// Website Mode at the caller so WebKit can own its native current UA.
    private static func resolvedIdentity(
        _ identity: BrowserIdentity,
        customUserAgent: String?
    ) -> BrowserIdentity {
        if identity == .custom,
           customUserAgent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return .macosSafari
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

/// Website Mode owns the responsive layout class while Window Size remains the
/// real visible FloatTabs viewport. Desktop maps visible widths into deliberate
/// experience classes so Small/Medium/Large/Wide do not merely show the same
/// 1280px page at four scales. Mobile remains native 1:1. The AppKit logical
/// host performs the uniform coordinate mapping; pageZoom remains user Zoom.
enum WebsiteLayoutViewport {
    static let compactVisibleMaximum: CGFloat = 520
    static let balancedVisibleMaximum: CGFloat = 720
    static let standardVisibleMaximum: CGFloat = 960

    static let compactCSSWidth: CGFloat = 720
    static let balancedCSSWidth: CGFloat = 1024
    static let standardCSSWidth: CGFloat = 1280
    static let expandedCSSWidth: CGFloat = 1440

    static func desktopCSSWidth(forVisibleWidth visibleWidth: CGFloat) -> CGFloat {
        guard visibleWidth > 0 else { return visibleWidth }
        switch visibleWidth {
        case ...compactVisibleMaximum:
            return compactCSSWidth
        case ...balancedVisibleMaximum:
            return balancedCSSWidth
        case ...standardVisibleMaximum:
            return standardCSSWidth
        default:
            return max(expandedCSSWidth, visibleWidth)
        }
    }

    static func targetCSSWidth(
        forVisibleWidth visibleWidth: CGFloat,
        websiteMode: WebsiteMode
    ) -> CGFloat {
        guard visibleWidth > 0 else { return visibleWidth }
        switch websiteMode {
        case .desktop:
            return desktopCSSWidth(forVisibleWidth: visibleWidth)
        case .mobile:
            return visibleWidth
        }
    }

    static func fittingScale(
        forVisibleWidth visibleWidth: CGFloat,
        websiteMode: WebsiteMode
    ) -> CGFloat {
        guard visibleWidth > 0 else { return 1 }
        let targetWidth = targetCSSWidth(
            forVisibleWidth: visibleWidth,
            websiteMode: websiteMode
        )
        guard targetWidth > 0 else { return 1 }
        return visibleWidth / targetWidth
    }

    static func logicalSize(
        forVisibleSize visibleSize: CGSize,
        websiteMode: WebsiteMode
    ) -> CGSize {
        guard visibleSize.width > 0, visibleSize.height > 0 else {
            return visibleSize
        }

        #if DEBUG
        if oneToOneViewportOverrideEnabled {
            return visibleSize
        }
        #endif

        let logicalWidth = targetCSSWidth(
            forVisibleWidth: visibleSize.width,
            websiteMode: websiteMode
        )
        guard logicalWidth > 0 else { return visibleSize }

        let scale = logicalWidth / visibleSize.width
        guard scale != 1 else { return visibleSize }

        // Keep the derived logical frame on integral points. WKWebView aligns
        // its backing stores and tile grids to device pixels, so a fractional
        // logical dimension (e.g. 820 × 1024/600 = 1399.47) leaves every tile
        // row on a fractional physical pixel under the host's uniform mapping.
        // Rounding up never under-covers the visible surface; the clipped
        // overshoot stays below one visible point.
        return CGSize(
            width: logicalWidth.rounded(.up),
            height: (visibleSize.height * scale).rounded(.up)
        )
    }

    #if DEBUG
    /// Local A/B experiment seam for rendering investigations, enabled by
    /// launching with `-FloatTabsOneToOneViewport`. While on, Desktop hosting
    /// falls back to a strict 1:1 WKWebView geometry (no logical viewport
    /// fitting, no ancestor bounds scaling) so a rendering artifact can be
    /// compared against an unscaled baseline on the same site. It must default
    /// to off; production behavior never depends on it.
    static var oneToOneViewportOverrideEnabled: Bool = ProcessInfo.processInfo
        .arguments.contains("-FloatTabsOneToOneViewport")
    #endif
}

@MainActor
enum WebViewFactory {
    private static let hiddenScrollbarScriptSource = """
    (() => {
      const styleID = 'floattabs-hidden-scrollbar-style';
      const install = () => {
        const root = document.documentElement;
        if (!root || document.getElementById(styleID)) return;

        const style = document.createElement('style');
        style.id = styleID;
        style.textContent = `
          html, body {
            scrollbar-width: none !important;
          }
          html::-webkit-scrollbar,
          body::-webkit-scrollbar {
            width: 0 !important;
            height: 0 !important;
            display: none !important;
          }
        `;
        (document.head || root).appendChild(style);
      };

      if (document.documentElement) {
        install();
      } else {
        document.addEventListener('DOMContentLoaded', install, { once: true });
      }
    })();
    """

    static func hiddenScrollbarUserScript() -> WKUserScript {
        WKUserScript(
            source: hiddenScrollbarScriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

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
        configuration.userContentController.addUserScript(hiddenScrollbarUserScript())

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
            floatTabsWebView.setRendering(
                websiteMode: rendering.effectiveWebsiteMode,
                userPageZoom: rendering.zoom
            )
        } else {
            webView.pageZoom = rendering.zoom
        }

        if let customUserAgent = UserAgentProvider.customUserAgent(
            for: rendering,
            versions: versions
        ) {
            webView.customUserAgent = customUserAgent
        }
    }

    /// AppKit scrollers stay visually disabled even while the document scrolls.
    /// This avoids inheriting the user's global "Show scroll bars: Always"
    /// preference and forms the native half of the permanent scrollbar
    /// suppression policy without disabling document scrolling.
    ///
    /// The suppression is re-applied at navigation and reparenting boundaries
    /// because WebKit can restore its own defaults there. Scroll views that
    /// already carry the policy are recognized and left untouched, so the
    /// steady state performs no writes into WebKit's internal view hierarchy.
    static func configureHiddenScrollers(in webView: WKWebView) {
        for scrollView in descendantScrollViews(in: webView) {
            guard needsHiddenScrollerConfiguration(scrollView) else { continue }
            configureHiddenScrollerStyle(scrollView)
        }
    }

    /// Whether the scroll view is missing any part of the hidden-scroller
    /// policy and therefore still needs `configureHiddenScrollerStyle`.
    static func needsHiddenScrollerConfiguration(_ scrollView: NSScrollView) -> Bool {
        scrollView.scrollerStyle != .overlay
            || !scrollView.autohidesScrollers
            || scrollView.hasVerticalScroller
            || scrollView.hasHorizontalScroller
            || scrollView.verticalScroller?.isHidden == false
            || scrollView.horizontalScroller?.isHidden == false
    }

    static func configureHiddenScrollerStyle(_ scrollView: NSScrollView) {
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.verticalScroller?.isHidden = true
        scrollView.horizontalScroller?.isHidden = true
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
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
}

/// Keeps WKWebView page zoom independent from Website Mode. The AppKit host owns
/// Desktop viewport fitting, so WebKit lays out at a real desktop-class frame and
/// fonts/line-height are scaled uniformly with the rest of the rendered page.
/// `pageZoom` is reserved for the user's explicit Zoom value only.
@MainActor
final class FloatTabsWebView: WKWebView {
    private(set) var websiteMode: WebsiteMode = .desktop
    private(set) var userPageZoom: CGFloat = 1
    private(set) var websiteLayoutScale: CGFloat = 1

    override init(frame frameRect: NSRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frameRect, configuration: configuration)
        refreshWebsiteLayoutScale()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setRendering(
        websiteMode: WebsiteMode,
        userPageZoom: CGFloat
    ) {
        self.websiteMode = websiteMode
        self.userPageZoom = userPageZoom
        refreshWebsiteLayoutScale()
    }

    func setWebsiteMode(_ mode: WebsiteMode) {
        websiteMode = mode
        refreshWebsiteLayoutScale()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refreshWebsiteLayoutScale()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshWebsiteLayoutScale()
        WebViewFactory.configureHiddenScrollers(in: self)
    }

    private func refreshWebsiteLayoutScale() {
        websiteLayoutScale = 1
        if abs(pageZoom - userPageZoom) > 0.0001 {
            pageZoom = userPageZoom
        }
    }
}
