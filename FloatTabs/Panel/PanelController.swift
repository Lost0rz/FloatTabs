import AppKit
import WebKit

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let panel: FloatingPanel
    private let webView: WKWebView
    private let frameStore: PanelFrameStore

    private var previousApplication: NSRunningApplication?
    private var restoredFrame: NSRect?
    private var hasPositionedPanel = false

    var isVisible: Bool {
        panel.isVisible
    }

    init(
        webView: WKWebView? = nil,
        frameStore: PanelFrameStore = PanelFrameStore()
    ) {
        let webView = webView ?? WebViewFactory.makeStageZeroWebView()
        self.webView = webView
        self.frameStore = frameStore
        restoredFrame = frameStore.loadFrame()

        let initialFrame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        panel = FloatingPanel(contentRect: initialFrame)

        super.init()

        panel.delegate = self
        panel.contentView = PanelRootView(webView: webView)

        WebViewFactory.loadStageZeroPage(in: webView)
    }

    func showFloatTabs() {
        capturePreviousApplication()
        positionPanelForCurrentScreens()
        activateFloatTabs()

        panel.makeKeyAndOrderFront(nil)
        _ = panel.makeFirstResponder(webView)
    }

    func hideFloatTabs() {
        persistPanelFrame()
        panel.orderOut(nil)

        guard let previousApplication else {
            NSApp.deactivate()
            return
        }

        self.previousApplication = nil
        NSApp.deactivate()
        _ = previousApplication.activate(options: [])
    }

    func prepareForTermination() {
        persistPanelFrame()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        PanelMetrics.clampedPanelSize(frameSize)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        clampPanelToConnectedScreens()
        persistPanelFrame()
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

    private func positionPanelForCurrentScreens() {
        let screens = NSScreen.screens
        guard let fallbackScreen = ScreenPositioning.targetScreen(screens: screens) else { return }

        let visibleFrames = screens.map(\.visibleFrame)
        let targetFrame: NSRect

        if hasPositionedPanel {
            targetFrame = ScreenPositioning.restoredFrame(
                panel.frame,
                visibleFrames: visibleFrames,
                fallbackVisibleFrame: fallbackScreen.visibleFrame
            )
        } else if let restoredFrame {
            targetFrame = ScreenPositioning.restoredFrame(
                restoredFrame,
                visibleFrames: visibleFrames,
                fallbackVisibleFrame: fallbackScreen.visibleFrame
            )
        } else {
            targetFrame = ScreenPositioning.centeredFrame(
                size: PanelMetrics.defaultPanelSize,
                in: fallbackScreen.visibleFrame
            )
        }

        panel.setFrame(targetFrame, display: false)
        restoredFrame = nil
        hasPositionedPanel = true
    }

    private func clampPanelToConnectedScreens() {
        let screens = NSScreen.screens
        guard let fallbackScreen = ScreenPositioning.targetScreen(screens: screens) else { return }

        let clamped = ScreenPositioning.restoredFrame(
            panel.frame,
            visibleFrames: screens.map(\.visibleFrame),
            fallbackVisibleFrame: fallbackScreen.visibleFrame
        )

        if clamped != panel.frame {
            panel.setFrame(clamped, display: true)
        }
    }

    private func persistPanelFrame() {
        // The panel starts at an implementation-only .zero origin. Avoid
        // creating or overwriting stored state if the app quits before the
        // panel has ever been positioned for display.
        guard hasPositionedPanel else { return }
        frameStore.saveFrame(panel.frame)
    }
}
