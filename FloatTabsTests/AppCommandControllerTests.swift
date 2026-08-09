import AppKit
import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class AppCommandControllerTests: XCTestCase {
    func testOnlyExplicitFloatTabsShortcutsAreMatched() {
        XCTAssertEqual(
            AppCommandController.command(characters: "1", keyCode: 18, modifiers: [.command]),
            .selectSlot(1)
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "9", keyCode: 25, modifiers: [.command]),
            .selectSlot(9)
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "t", keyCode: 17, modifiers: [.command]),
            .addWebApp
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "l", keyCode: 37, modifiers: [.command]),
            .quickURL
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "+", keyCode: 24, modifiers: [.command, .shift]),
            .zoomIn
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "=", keyCode: 24, modifiers: [.command]),
            .zoomIn
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "-", keyCode: 27, modifiers: [.command]),
            .zoomOut
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "0", keyCode: 29, modifiers: [.command]),
            .resetZoom
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "\t", keyCode: 48, modifiers: [.control]),
            .nextSlot
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "\t", keyCode: 48, modifiers: [.control, .shift]),
            .previousSlot
        )

        XCTAssertNil(AppCommandController.command(characters: "a", keyCode: 0, modifiers: [.command]))
        XCTAssertNil(AppCommandController.command(characters: "c", keyCode: 8, modifiers: [.command]))
        XCTAssertNil(AppCommandController.command(characters: "1", keyCode: 18, modifiers: [.command, .shift]))
    }

    func testQuickURLDismissesForEscapeSecondCommandLAndOutsideClickOnly() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let host = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = host

        let overlay = QuickURLOverlayView(frame: NSRect(x: 100, y: 300, width: 300, height: 52))
        host.addSubview(overlay)
        overlay.present(url: URL(string: "https://example.com")!, in: window)

        XCTAssertTrue(AppCommandController.presentedQuickURLOverlay(in: window) === overlay)

        let escape = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        )!
        XCTAssertTrue(AppCommandController.shouldDismissQuickURL(for: escape, overlay: overlay))

        let commandL = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "l",
            charactersIgnoringModifiers: "l",
            isARepeat: false,
            keyCode: 37
        )!
        XCTAssertTrue(AppCommandController.shouldDismissQuickURL(for: commandL, overlay: overlay))

        let insideClick = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 150, y: 320),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )!
        XCTAssertFalse(AppCommandController.shouldDismissQuickURL(for: insideClick, overlay: overlay))

        let outsideClick = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 40, y: 40),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 1
        )!
        XCTAssertTrue(AppCommandController.shouldDismissQuickURL(for: outsideClick, overlay: overlay))
    }

    /// Stage 3's original native-click regression clicked the exact center of
    /// the page. Center coordinates are invariant under symmetric scaling, so
    /// that test cannot detect an x/y scale mismatch away from the center.
    ///
    /// This fixture deliberately places the target near the lower-left corner
    /// while Mobile mode runs in a wide physical window (`pageZoom > 1`). It
    /// exercises the same class of interaction used by mobile attachment / plus
    /// controls without depending on a live provider page.
    func testMobileWidePageZoomKeepsOffCenterNativeClickHitTestingWorking() {
        _ = NSApplication.shared

        let rendering = WebRenderingProfile.canonicalDefault
            .settingWebsiteMode(.mobile)
            .settingSimplePreset(.wide)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 850)
        )
        container.show(webView: webView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 850),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        container.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()

        let loaded = expectation(description: "mobile off-center fixture loaded")
        let waiter = MobileHitNavigationWaiter { loaded.fulfill() }
        webView.navigationDelegate = waiter
        webView.loadHTMLString(
            """
            <!doctype html>
            <html>
              <head>
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                  html, body { margin:0; width:100%; height:100%; }
                  button { position:fixed; bottom:24px; height:48px; border:0; }
                  #target { left:24px; width:48px; background:#4caf50; }
                  #decoy { left:92px; width:72px; background:#e57373; }
                </style>
              </head>
              <body>
                <button id="target">+</button>
                <button id="decoy">decoy</button>
                <script>
                  window.targetClicks = 0;
                  window.decoyClicks = 0;
                  target.addEventListener('click', () => window.targetClicks++);
                  decoy.addEventListener('click', () => window.decoyClicks++);
                </script>
              </body>
            </html>
            """,
            baseURL: nil
        )
        wait(for: [loaded], timeout: 5)
        withExtendedLifetime(waiter) {}

        guard let floatWebView = webView as? FloatTabsWebView else {
            XCTFail("Expected FloatTabsWebView")
            return
        }

        XCTAssertEqual(floatWebView.websiteMode, .mobile)
        XCTAssertEqual(floatWebView.websiteLayoutScale, 900.0 / 390.0, accuracy: 0.001)
        XCTAssertGreaterThan(webView.pageZoom, 1)

        // Target center in CSS coordinates is x=48, bottom=48. The visual
        // presentation scales that position by the effective public pageZoom.
        let visualPointInWebView = NSPoint(
            x: 48 * webView.pageZoom,
            y: 48 * webView.pageZoom
        )
        click(
            webView: webView,
            localPoint: visualPointInWebView,
            in: window
        )

        waitForJavaScriptNumber(
            "window.targetClicks",
            in: webView,
            equals: 1
        )
        XCTAssertEqual(
            evaluateNumber("window.decoyClicks", in: webView),
            0,
            accuracy: 0.001
        )
        window.orderOut(nil)
    }

    private func click(
        webView: WKWebView,
        localPoint: NSPoint,
        in window: NSWindow
    ) {
        let windowPoint = webView.convert(localPoint, to: nil)
        guard let down = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 101,
            clickCount: 1,
            pressure: 1
        ), let up = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: windowPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 102,
            clickCount: 1,
            pressure: 0
        ) else {
            XCTFail("Expected synthetic mouse events")
            return
        }

        webView.mouseDown(with: down)
        webView.mouseUp(with: up)
    }

    private func evaluateNumber(_ script: String, in webView: WKWebView) -> Double {
        let evaluated = expectation(description: "JavaScript numeric value")
        var result: Double?
        var evaluationError: Error?

        webView.evaluateJavaScript(script) { value, error in
            evaluationError = error
            result = (value as? NSNumber)?.doubleValue
            evaluated.fulfill()
        }
        wait(for: [evaluated], timeout: 5)
        XCTAssertNil(evaluationError)
        return result ?? .nan
    }

    private func waitForJavaScriptNumber(
        _ script: String,
        in webView: WKWebView,
        equals expected: Double,
        timeout: TimeInterval = 2.0
    ) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        var lastValue = Double.nan

        repeat {
            lastValue = evaluateNumber(script, in: webView)
            if !lastValue.isNaN, abs(lastValue - expected) <= 0.001 {
                return
            }

            let tick = expectation(description: "WebKit event delivery tick")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                tick.fulfill()
            }
            wait(for: [tick], timeout: 0.1)
        } while Date() < deadline

        XCTFail(
            "Timed out waiting for \(script) == \(expected); last value was \(lastValue)"
        )
    }
}

@MainActor
private final class MobileHitNavigationWaiter: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish()
    }
}
