import AppKit
import WebKit
import XCTest
@testable import FloatTabs

/// Regression coverage for the WKWebView dynamic-text ghosting/overlap
/// investigation (P1, 2026-08).
///
/// These tests pin the *geometry and injection invariants* of the logical
/// viewport hosting model that a rendering artifact of this class depends on.
/// They intentionally do NOT claim to reproduce a GPU compositing artifact:
/// XCTest cannot observe WindowServer compositing. What they do guarantee is
/// that the environment FloatTabs presents to WebKit stays deterministic and
/// pixel-aligned while dynamic content animates, which is the precondition for
/// isolating any remaining artifact to WebKit itself.
@MainActor
final class WebsiteLayoutGeometryRegressionTests: XCTestCase {
    private let mediumVisible = NSSize(width: 600, height: 820)
    private let largeVisible = NSSize(width: 820, height: 850)

    // MARK: - Logical frame pixel alignment

    /// The derived logical frame must stay on integral points. A fractional
    /// logical height (e.g. 820 × 1024/600 = 1399.466…) hands WKWebView a
    /// frame that can never align with its own device-pixel tile grid under
    /// the host's uniform downscale, forcing WebKit-side rounding on every
    /// tile row.
    func testLogicalViewportAlwaysProducesIntegralLogicalFrames() {
        let visibleSizes = presetVisibleSizes() + [
            CGSize(width: 521.3, height: 733.7),
            CGSize(width: 720, height: 900),
            CGSize(width: 960.5, height: 780.25),
            CGSize(width: 1024, height: 700),
        ]

        for visibleSize in visibleSizes {
            let logical = WebsiteLayoutViewport.logicalSize(
                forVisibleSize: visibleSize,
                websiteMode: .desktop
            )
            if logical != visibleSize {
                XCTAssertEqual(logical.width, logical.width.rounded(), accuracy: 0.001,
                               "logical width must be integral for \(visibleSize)")
                XCTAssertEqual(logical.height, logical.height.rounded(), accuracy: 0.001,
                               "logical height must be integral for \(visibleSize)")
            }
        }

        // Medium maps to the balanced 1024-class with an integral height.
        let medium = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: CGSize(width: 600, height: 820),
            websiteMode: .desktop
        )
        XCTAssertEqual(medium.width, 1024, accuracy: 0.001)
        XCTAssertEqual(medium.height, 1400, accuracy: 0.001)

        // Large maps to the standard 1280-class with an integral height.
        let large = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: CGSize(width: 820, height: 850),
            websiteMode: .desktop
        )
        XCTAssertEqual(large.width, 1280, accuracy: 0.001)
        XCTAssertEqual(large.height, 1327, accuracy: 0.001)

        // Mobile stays exactly 1:1 with the visible surface.
        let mobileVisible = CGSize(width: 600.0, height: 820.0)
        let mobile = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: mobileVisible,
            websiteMode: .mobile
        )
        XCTAssertEqual(mobile, mobileVisible)
    }

    // MARK: - Geometry idempotence / no oscillation

    /// Repeated layout passes over the same visible size must not rewrite
    /// host bounds or the WKWebView frame. Oscillating frame writes during a
    /// running page are a candidate trigger for compositing invalidation
    /// errors, so the steady state must be provably write-free.
    func testRepeatedLayoutPassesLeaveTransientHostGeometryUntouched() {
        _ = NSApplication.shared
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = WebPanelContainerView(
            frame: NSRect(origin: .zero, size: mediumVisible)
        )
        container.show(webView: webView)
        let window = borderlessWindow(content: container)
        container.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()

        let logicalFrame = webView.frame
        let logicalSize = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: mediumVisible,
            websiteMode: .desktop
        )
        XCTAssertEqual(logicalFrame.size, logicalSize)

        for _ in 0..<3 {
            container.layoutSubtreeIfNeeded()
            webView.layoutSubtreeIfNeeded()
        }

        XCTAssertEqual(webView.frame, logicalFrame,
                       "repeated layout passes must not move the logical frame")
        XCTAssertFalse(container.needsLayout)
        window.orderOut(nil)
    }

    func testRepeatedLayoutPassesLeaveHotHostGeometryUntouched() {
        _ = NSApplication.shared
        let container = WebPanelContainerView(
            frame: NSRect(origin: .zero, size: mediumVisible)
        )
        let window = borderlessWindow(content: container)
        container.layoutSubtreeIfNeeded()

        let slotID = UUID()
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        container.show(webView: webView, slotID: slotID, residencyPolicy: .hot)
        container.layoutSubtreeIfNeeded()

        let logicalFrame = webView.frame
        XCTAssertEqual(logicalFrame.width, 1024, accuracy: 0.001)

        for _ in 0..<3 {
            container.layoutSubtreeIfNeeded()
        }

        XCTAssertEqual(webView.frame, logicalFrame,
                       "repeated layout passes must not move the hot logical frame")
        window.orderOut(nil)
    }

    /// Resizing away and back must return the exact same logical geometry —
    /// deterministic, not merely similar.
    func testResizeRoundtripIsDeterministic() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: mediumVisible)
        let initialFrame = webView.frame
        let initialScale = container.websiteLayoutScale

        container.setFrameSize(largeVisible)
        container.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()
        XCTAssertEqual(webView.frame.width, 1280, accuracy: 0.001)

        container.setFrameSize(mediumVisible)
        container.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()

        XCTAssertEqual(webView.frame, initialFrame)
        XCTAssertEqual(container.websiteLayoutScale, initialScale, accuracy: 0.0001)
    }

    // MARK: - Dynamic-content fixture

    /// Loads the same dynamic CJK content class reported in the artifact
    /// (rAF-driven text updates, opacity/transform animations, will-change,
    /// fractional positioning) inside the production hosting stack and asserts
    /// that the hosting geometry and the injected scrollbar suppression stay
    /// stable while the page animates, and that WebKit really laid the page
    /// out at the logical desktop width.
    func testDynamicCJKContentKeepsHostingGeometryAndInjectionStable() {
        _ = NSApplication.shared
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = WebPanelContainerView(
            frame: NSRect(origin: .zero, size: mediumVisible)
        )
        container.show(webView: webView)
        let window = borderlessWindow(content: container)
        container.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()

        let logicalFrame = webView.frame
        let logicalSize = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: mediumVisible,
            websiteMode: .desktop
        )
        XCTAssertEqual(logicalFrame.size, logicalSize)

        loadDynamicCJKFixture(in: webView)

        // Let animations, rAF text updates and DOM churn run for a while.
        waitForTicks(1.5)

        XCTAssertEqual(webView.frame, logicalFrame,
                       "hosting geometry must not drift while content animates")
        XCTAssertEqual(container.websiteLayoutScale, mediumVisible.width / logicalSize.width,
                       accuracy: 0.0001)

        // WebKit laid the document out at the logical desktop width.
        let innerWidth = evaluateNumber("window.innerWidth", in: webView)
        XCTAssertEqual(innerWidth, logicalSize.width, accuracy: 1.5)

        // The hidden-scrollbar user script installed exactly one style element
        // in the main frame, and the DOM churn below never duplicates it.
        let mainFrameStyleCount = evaluateNumber(
            "document.querySelectorAll('#floattabs-hidden-scrollbar-style').length",
            in: webView
        )
        XCTAssertEqual(mainFrameStyleCount, 1, accuracy: 0.001)

        // The rAF-driven status text is still a single node (no accumulation).
        let statusNodeCount = evaluateNumber(
            "document.querySelectorAll('#status').length",
            in: webView
        )
        XCTAssertEqual(statusNodeCount, 1, accuracy: 0.001)

        window.orderOut(nil)
    }

    // MARK: - Hidden scroller configuration idempotence

    /// The scroller suppression runs at navigation and reparenting boundaries;
    /// the steady state must therefore be recognized and left untouched so
    /// WebKit's internal scroll views are never redundantly mutated.
    func testHiddenScrollerConfigurationIsIdempotent() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
        scrollView.scrollerStyle = .legacy
        scrollView.autohidesScrollers = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true

        XCTAssertTrue(WebViewFactory.needsHiddenScrollerConfiguration(scrollView))
        WebViewFactory.configureHiddenScrollerStyle(scrollView)
        XCTAssertFalse(WebViewFactory.needsHiddenScrollerConfiguration(scrollView))

        // A second pass over an already-configured view performs no writes.
        WebViewFactory.configureHiddenScrollers(in: fakeWebViewHosting(scrollView))
        XCTAssertFalse(WebViewFactory.needsHiddenScrollerConfiguration(scrollView))
        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertFalse(scrollView.hasVerticalScroller)
        XCTAssertFalse(scrollView.hasHorizontalScroller)

        // WebKit restoring its own defaults is detected and reconfigured.
        scrollView.scrollerStyle = .legacy
        XCTAssertTrue(WebViewFactory.needsHiddenScrollerConfiguration(scrollView))
        WebViewFactory.configureHiddenScrollerStyle(scrollView)
        XCTAssertFalse(WebViewFactory.needsHiddenScrollerConfiguration(scrollView))
    }

    // MARK: - Local A/B experiment seam (DEBUG builds only)

    #if DEBUG
    /// The `-FloatTabsOneToOneViewport` launch argument exists solely as a
    /// local A/B experiment for rendering investigations: it bypasses the
    /// desktop logical viewport fitting and hosts the WKWebView 1:1 with the
    /// visible surface (WKWebView.frame == host.bounds == visible size). It
    /// must default to off so production behavior is never changed.
    func testOneToOneViewportDebugOverrideHostsAtNativeScale() {
        let previous = WebsiteLayoutViewport.oneToOneViewportOverrideEnabled
        defer { WebsiteLayoutViewport.oneToOneViewportOverrideEnabled = previous }

        WebsiteLayoutViewport.oneToOneViewportOverrideEnabled = false
        let logical = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: mediumVisible,
            websiteMode: .desktop
        )
        XCTAssertEqual(logical.width, 1024, accuracy: 0.001)

        WebsiteLayoutViewport.oneToOneViewportOverrideEnabled = true
        let oneToOne = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: mediumVisible,
            websiteMode: .desktop
        )
        XCTAssertEqual(oneToOne, mediumVisible)

        // The hosting stack follows the same seam end to end.
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: mediumVisible)
        XCTAssertEqual(webView.frame.size, mediumVisible)
        XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.0001)
    }
    #endif

    // MARK: - Fixture

    /// Mirrors the content class from the field report: a dynamically updated
    /// Chinese status text with composited opacity/transform animations,
    /// will-change hints, fractional positioning and continuous DOM churn.
    private func loadDynamicCJKFixture(in webView: WKWebView) {
        let loaded = expectation(description: "dynamic fixture loaded")
        let waiter = NavigationWaiter { loaded.fulfill() }
        webView.navigationDelegate = waiter
        webView.loadHTMLString(Self.dynamicCJKFixtureHTML, baseURL: nil)
        wait(for: [loaded], timeout: 10)
        withExtendedLifetime(waiter) {}
    }

    private static let dynamicCJKFixtureHTML = """
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    <style>
      html, body { margin: 0; font-size: 15px; line-height: 1.6; }
      #status {
        position: absolute;
        left: 37.5px;
        top: 53.2px;
        will-change: transform, opacity;
        transition: opacity 240ms ease-out;
        animation: float 2.4s ease-in-out infinite;
        font-weight: 600;
      }
      #pulse {
        position: fixed;
        left: 0.5px;
        bottom: 1.25px;
        will-change: opacity;
        animation: fade 1.8s steps(6) infinite;
      }
      @keyframes float {
        0%   { transform: translate3d(0, 0, 0); }
        50%  { transform: translate3d(12.5px, -7.25px, 0); }
        100% { transform: translate3d(0, 0, 0); }
      }
      @keyframes fade {
        0%   { opacity: 0.1; }
        50%  { opacity: 0.85; }
        100% { opacity: 0.1; }
      }
    </style>
    </head>
    <body>
      <div id="status">正在加载弹幕引擎…</div>
      <div id="pulse">缓冲中</div>
      <iframe id="nested" srcdoc="<p>frame</p>"></iframe>
      <script>
        (() => {
          const status = document.getElementById('status');
          const messages = ['正在加载弹幕引擎…', '连接服务器中…', '清晰度切换中…', '音量同步中…'];
          let index = 0;
          const advance = () => {
            status.textContent = messages[index++ % messages.length];
            // DOM churn: the kind of continuous subtree mutation the artifact
            // was observed alongside.
            const churn = document.createElement('div');
            churn.textContent = '清理';
            document.body.appendChild(churn);
            requestAnimationFrame(() => churn.remove());
            requestAnimationFrame(advance);
          };
          requestAnimationFrame(advance);
        })();
      </script>
    </body>
    </html>
    """

    // MARK: - Helpers

    private func presetVisibleSizes() -> [CGSize] {
        SimpleViewportPreset.allCases.compactMap(\.size)
    }

    private func host(
        _ webView: WKWebView,
        visibleSize: NSSize
    ) -> WebPanelContainerView {
        let container = WebPanelContainerView(
            frame: NSRect(origin: .zero, size: visibleSize)
        )
        container.show(webView: webView)
        container.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()
        return container
    }

    private func borderlessWindow(content: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: content.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = content
        window.orderFront(nil)
        return window
    }

    /// A minimal view that hosts the scroll view the way WKWebView hosts its
    /// internal NSScrollView descendants (descendant, not a subview of self).
    private func fakeWebViewHosting(_ scrollView: NSScrollView) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        let wrapper = NSView(frame: scrollView.frame)
        wrapper.addSubview(scrollView)
        webView.addSubview(wrapper)
        return webView
    }

    private func waitForTicks(_ seconds: TimeInterval) {
        let deadline = Date(timeIntervalSinceNow: seconds)
        while Date() < deadline {
            let tick = expectation(description: "tick")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { tick.fulfill() }
            wait(for: [tick], timeout: 0.3)
        }
    }

    private func evaluateNumber(_ script: String, in webView: WKWebView) -> Double {
        let expectation = expectation(description: "JavaScript value evaluated")
        var number: Double?
        var evaluationError: Error?

        webView.evaluateJavaScript(script) { value, error in
            evaluationError = error
            number = (value as? NSNumber)?.doubleValue
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10)
        XCTAssertNil(evaluationError)
        guard let number else {
            XCTFail("Expected numeric JavaScript result")
            return .nan
        }
        return number
    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish()
    }
}
