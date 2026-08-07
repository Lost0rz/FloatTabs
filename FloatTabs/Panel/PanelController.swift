import AppKit
import SwiftUI
import WebKit

@MainActor
final class PanelController {
    private let panel: FloatingPanel
    private let webView: WKWebView
    private var previousApplication: NSRunningApplication?
    private var hasPositionedPanel = false

    var isVisible: Bool {
        panel.isVisible
    }

    init(webView: WKWebView? = nil) {
        let webView = webView ?? WebViewFactory.makeStageZeroWebView()
        self.webView = webView

        let initialFrame = NSRect(origin: .zero, size: PanelMetrics.defaultViewportSize)
        panel = FloatingPanel(contentRect: initialFrame)
        panel.contentViewController = NSHostingController(
            rootView: WebViewContainer(webView: webView)
        )

        WebViewFactory.loadStageZeroPage(in: webView)
    }

    func showFloatTabs() {
        capturePreviousApplication()
        positionPanelForCurrentScreen()
        activateFloatTabs()

        panel.makeKeyAndOrderFront(nil)
        _ = panel.makeFirstResponder(webView)
    }

    func hideFloatTabs() {
        panel.orderOut(nil)

        guard let previousApplication else {
            NSApp.deactivate()
            return
        }

        self.previousApplication = nil
        NSApp.deactivate()
        _ = previousApplication.activate(options: [])
    }

    private func activateFloatTabs() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            _ = NSRunningApplication.current.activate(options: [])
        }
    }

    private func capturePreviousApplication() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return }
        guard frontmost.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        previousApplication = frontmost
    }

    private func positionPanelForCurrentScreen() {
        guard let screen = ScreenPositioning.targetScreen() else { return }

        if hasPositionedPanel {
            panel.setFrame(
                ScreenPositioning.clampedFrame(panel.frame, to: screen.visibleFrame),
                display: false
            )
        } else {
            panel.setFrame(
                ScreenPositioning.centeredFrame(
                    size: PanelMetrics.defaultViewportSize,
                    in: screen.visibleFrame
                ),
                display: false
            )
            hasPositionedPanel = true
        }
    }
}
