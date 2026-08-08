import AppKit
import Foundation
import WebKit

@MainActor
enum WebViewFactory {
    static func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = FloatTabsWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        configureHiddenScrollers(in: webView)
        return webView
    }

    static func makeStageZeroWebView() -> WKWebView {
        makeWebView()
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

/// WKWebView retains this controller for its whole lifetime. The controller
/// watches local scroll-wheel events over this WebView and temporarily exposes
/// only the scroller axis that is actually moving. Once scrolling stops, both
/// AppKit scrollers are removed again so they cannot reserve or paint idle UI.
@MainActor
private final class FloatTabsWebView: WKWebView {
    private var transientScrollerController: TransientWebScrollerController?

    override init(frame frameRect: NSRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frameRect, configuration: configuration)
        transientScrollerController = TransientWebScrollerController(webView: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        transientScrollerController?.refreshScrollerState()
    }
}

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
