import AppKit
import WebKit

@MainActor
enum AppOwnedFullscreenPresentation {
    enum Phase: String {
        case idle
        case entering
        case active
        case exiting
    }

    private(set) static var activeWebView: WKWebView?
    private(set) static var phase: Phase = .idle

    static var isActive: Bool {
        activeWebView != nil && phase != .idle
    }

    static var isTransitioning: Bool {
        phase == .entering || phase == .exiting
    }

    static func isPresenting(_ webView: WKWebView) -> Bool {
        activeWebView === webView
    }

    fileprivate static func begin(webView: WKWebView) {
        activeWebView = webView
        phase = .entering
        FloatTabsFullscreenPresentation.shellExplicitlySummoned = false
    }

    fileprivate static func markEntered(webView: WKWebView) {
        guard activeWebView === webView else { return }
        phase = .active
    }

    fileprivate static func markExiting(webView: WKWebView?) {
        guard webView == nil || activeWebView === webView else { return }
        phase = .exiting
    }

    fileprivate static func end(webView: WKWebView?) {
        if let webView, activeWebView !== webView {
            return
        }
        activeWebView = nil
        phase = .idle
        FloatTabsFullscreenPresentation.shellExplicitlySummoned = false
    }
}

/// Owns FloatTabs fullscreen presentation instead of mutating WebKit's private
/// `WebCoreFullScreenWindow`. A fresh AppKit window is created for every session,
/// so display/Space state is never reused across A -> B -> A transitions.
///
/// The page-facing bridge is standards-shaped rather than site-specific: page
/// calls to `requestFullscreen` / `exitFullscreen` are intercepted before page
/// script runs, while WebKit element fullscreen itself remains disabled. The same
/// live WKWebView is then moved into a fresh native fullscreen window, preserving
/// cookies, navigation state and media playback without creating/reloading a view.
@MainActor
final class AppOwnedFullscreenCoordinator: NSObject, WKScriptMessageHandler, NSWindowDelegate {
    static let shared = AppOwnedFullscreenCoordinator()

    private static let messageHandlerName = "floatTabsAppFullscreen"

    private static let bridgeScriptSource = #"""
    (() => {
      if (window.__floatTabsAppFullscreenBridgeInstalled) return;
      window.__floatTabsAppFullscreenBridgeInstalled = true;

      let activeElement = null;
      let saved = null;
      let nativeExitInProgress = false;

      const handler = () => window.webkit?.messageHandlers?.floatTabsAppFullscreen;
      const post = (action) => {
        try {
          handler()?.postMessage({ action, href: String(location.href || '') });
        } catch (_) {}
      };

      const saveProperty = (element, property) => ({
        value: element.style.getPropertyValue(property),
        priority: element.style.getPropertyPriority(property),
      });

      const restoreProperty = (element, property, state) => {
        if (!state) return;
        if (state.value) {
          element.style.setProperty(property, state.value, state.priority || '');
        } else {
          element.style.removeProperty(property);
        }
      };

      const targetProperties = [
        ['position', 'fixed'],
        ['inset', '0'],
        ['top', '0'],
        ['right', '0'],
        ['bottom', '0'],
        ['left', '0'],
        ['width', '100vw'],
        ['height', '100vh'],
        ['max-width', 'none'],
        ['max-height', 'none'],
        ['margin', '0'],
        ['z-index', '2147483647'],
        ['background-color', 'black'],
        ['transform', 'none'],
      ];

      const dispatchChange = () => {
        try { document.dispatchEvent(new Event('fullscreenchange')); } catch (_) {}
        try { document.dispatchEvent(new Event('webkitfullscreenchange')); } catch (_) {}
      };

      const installDocumentGetter = (name, getter) => {
        try {
          Object.defineProperty(document, name, {
            configurable: true,
            enumerable: true,
            get: getter,
          });
        } catch (_) {}
      };

      installDocumentGetter('fullscreenElement', () => activeElement);
      installDocumentGetter('webkitFullscreenElement', () => activeElement);
      installDocumentGetter('webkitCurrentFullScreenElement', () => activeElement);
      installDocumentGetter('fullscreenEnabled', () => true);
      installDocumentGetter('webkitFullscreenEnabled', () => true);

      const applyFakeFullscreen = (element) => {
        if (!element || activeElement === element) return;
        if (activeElement) restoreFakeFullscreen(false);

        activeElement = element;
        saved = {
          target: Object.fromEntries(targetProperties.map(([property]) => [property, saveProperty(element, property)])),
          htmlOverflow: document.documentElement ? saveProperty(document.documentElement, 'overflow') : null,
          bodyOverflow: document.body ? saveProperty(document.body, 'overflow') : null,
        };

        for (const [property, value] of targetProperties) {
          try { element.style.setProperty(property, value, 'important'); } catch (_) {}
        }
        try { document.documentElement?.style.setProperty('overflow', 'hidden', 'important'); } catch (_) {}
        try { document.body?.style.setProperty('overflow', 'hidden', 'important'); } catch (_) {}
        dispatchChange();
      };

      const restoreFakeFullscreen = (notifyNative) => {
        const element = activeElement;
        const state = saved;
        activeElement = null;
        saved = null;

        if (element && state) {
          for (const [property] of targetProperties) {
            restoreProperty(element, property, state.target?.[property]);
          }
          if (document.documentElement) {
            restoreProperty(document.documentElement, 'overflow', state.htmlOverflow);
          }
          if (document.body) {
            restoreProperty(document.body, 'overflow', state.bodyOverflow);
          }
        }

        dispatchChange();
        if (notifyNative && !nativeExitInProgress) post('exit');
      };

      const requestFullscreen = function() {
        applyFakeFullscreen(this);
        post('enter');
        return Promise.resolve();
      };

      const exitFullscreen = function() {
        restoreFakeFullscreen(true);
        return Promise.resolve();
      };

      const installMethod = (prototype, name, implementation) => {
        if (!prototype) return;
        try {
          Object.defineProperty(prototype, name, {
            configurable: true,
            writable: true,
            value: implementation,
          });
        } catch (_) {
          try { prototype[name] = implementation; } catch (_) {}
        }
      };

      installMethod(Element.prototype, 'requestFullscreen', requestFullscreen);
      installMethod(Element.prototype, 'webkitRequestFullscreen', requestFullscreen);
      installMethod(Element.prototype, 'webkitRequestFullScreen', requestFullscreen);
      installMethod(Document.prototype, 'exitFullscreen', exitFullscreen);
      installMethod(Document.prototype, 'webkitExitFullscreen', exitFullscreen);
      installMethod(Document.prototype, 'webkitCancelFullScreen', exitFullscreen);

      window.__floatTabsNativeFullscreenDidExit = () => {
        nativeExitInProgress = true;
        restoreFakeFullscreen(false);
        nativeExitInProgress = false;
      };
    })();
    """#

    private var fullscreenWindow: NSWindow?
    private var fullscreenHostView: NSView?
    private var activeWebView: WKWebView?
    private var sourceSuperview: NSView?
    private weak var sourcePanel: FloatingPanel?
    private var sourceFrame: NSRect = .zero
    private var sourceAutoresizingMask: NSView.AutoresizingMask = []
    private var sourceTranslatesAutoresizingMaskIntoConstraints = true
    private var sourcePanelWasVisible = false
    private var shellAutoSuppressed = false
    private var shellRestoreCancelledByUser = false
    private var pendingExit = false

    private var phase: AppOwnedFullscreenPresentation.Phase {
        AppOwnedFullscreenPresentation.phase
    }

    private override init() {
        super.init()
    }

    func configure(_ configuration: WKWebViewConfiguration) {
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.bridgeScriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        configuration.userContentController.add(self, name: Self.messageHandlerName)
    }

    func isPresenting(_ webView: WKWebView) -> Bool {
        activeWebView === webView && phase != .idle
    }

    @discardableResult
    func restoreFullscreenWindowKeyIfAvailable() -> Bool {
        guard phase != .idle,
              let fullscreenWindow,
              fullscreenWindow.isVisible else {
            return false
        }
        fullscreenWindow.makeKey()
        return true
    }

    func shellWasExplicitlyHidden() {
        guard phase != .idle else { return }
        shellRestoreCancelledByUser = true
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.messageHandlerName,
              let webView = message.webView,
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            return
        }

        switch action {
        case "enter":
            requestEnter(from: webView, pageURL: body["href"] as? String)
        case "exit":
            requestExit(reason: "page_exitFullscreen")
        default:
            break
        }
    }

    private func requestEnter(from webView: WKWebView, pageURL: String?) {
        if isPresenting(webView) {
            return
        }
        guard phase == .idle,
              AppOwnedFullscreenPresentation.activeWebView == nil,
              let sourceSuperview = webView.superview,
              let sourceWindow = webView.window,
              let targetScreen = NSScreen.main ?? sourceWindow.screen ?? NSScreen.screens.first else {
            FloatTabsDiagnostics.record(
                "app_owned_fullscreen_request_rejected",
                fields: [
                    "reason": "missing_source_or_existing_session",
                    "phase": phase.rawValue,
                    "page_url": pageURL ?? "nil",
                ]
            )
            forcePageExitCleanup(in: webView)
            return
        }

        pendingExit = false
        activeWebView = webView
        self.sourceSuperview = sourceSuperview
        sourcePanel = sourceWindow as? FloatingPanel
        sourceFrame = webView.frame
        sourceAutoresizingMask = webView.autoresizingMask
        sourceTranslatesAutoresizingMaskIntoConstraints = webView.translatesAutoresizingMaskIntoConstraints
        sourcePanelWasVisible = sourcePanel?.isVisible ?? false
        shellAutoSuppressed = false
        shellRestoreCancelledByUser = false
        AppOwnedFullscreenPresentation.begin(webView: webView)
        sourcePanel?.appOwnedFullscreenPhaseDidChange()

        FloatTabsDiagnostics.record(
            "app_owned_fullscreen_request",
            fields: [
                "page_url": pageURL ?? "nil",
                "source_window_number": String(sourceWindow.windowNumber),
                "source_window_screen_frame": sourceWindow.screen.map { NSStringFromRect($0.frame) } ?? "nil",
                "target_screen_frame": NSStringFromRect(targetScreen.frame),
                "main_screen_frame": NSScreen.main.map { NSStringFromRect($0.frame) } ?? "nil",
                "webview_frame": NSStringFromRect(webView.frame),
            ]
        )

        let window = NSWindow(
            contentRect: targetScreen.visibleFrame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: targetScreen
        )
        window.delegate = self
        window.title = "FloatTabs Fullscreen"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        let host = NSView(frame: NSRect(origin: .zero, size: targetScreen.visibleFrame.size))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        host.autoresizingMask = [.width, .height]
        window.contentView = host

        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.width, .height]
        webView.frame = host.bounds
        host.addSubview(webView)

        fullscreenWindow = window
        fullscreenHostView = host

        FloatTabsDiagnostics.record(
            "app_owned_fullscreen_window_created",
            fields: [
                "window_number": String(window.windowNumber),
                "window_frame": NSStringFromRect(window.frame),
                "window_screen_frame": window.screen.map { NSStringFromRect($0.frame) } ?? "nil",
                "target_screen_frame": NSStringFromRect(targetScreen.frame),
            ]
        )

        window.setFrame(targetScreen.visibleFrame, display: false)
        window.makeKeyAndOrderFront(nil)

        // Give AppKit one run-loop turn to associate this fresh app-owned window
        // with the target display before starting the standard fullscreen Space.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self,
                  self.phase == .entering,
                  self.fullscreenWindow === window,
                  let window else {
                return
            }
            window.toggleFullScreen(nil)
        }
    }

    private func requestExit(reason: String) {
        guard phase != .idle else { return }

        if phase == .entering {
            pendingExit = true
            FloatTabsDiagnostics.record(
                "app_owned_fullscreen_exit_deferred",
                fields: ["reason": reason]
            )
            return
        }

        guard phase == .active,
              let fullscreenWindow else {
            return
        }
        AppOwnedFullscreenPresentation.markExiting(webView: activeWebView)
        sourcePanel?.appOwnedFullscreenPhaseDidChange()
        FloatTabsDiagnostics.record(
            "app_owned_fullscreen_exit_requested",
            fields: [
                "reason": reason,
                "window_number": String(fullscreenWindow.windowNumber),
            ]
        )
        fullscreenWindow.toggleFullScreen(nil)
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === fullscreenWindow,
              phase == .entering else {
            return
        }

        guard let activeWebView else {
            finishExit(reason: "missing_active_webview_after_enter")
            return
        }
        AppOwnedFullscreenPresentation.markEntered(webView: activeWebView)
        sourcePanel?.appOwnedFullscreenPhaseDidChange()
        FloatTabsDiagnostics.record(
            "app_owned_fullscreen_did_enter",
            fields: [
                "window_number": String(window.windowNumber),
                "window_frame": NSStringFromRect(window.frame),
                "window_screen_frame": window.screen.map { NSStringFromRect($0.frame) } ?? "nil",
                "window_active_space": String(window.isOnActiveSpace),
            ]
        )
        FloatTabsDiagnostics.markFullscreenReachedStableState(window)

        if let sourcePanel,
           sourcePanelWasVisible,
           !sourcePanel.isPresentationPinned,
           sourcePanel.isVisible {
            sourcePanel.orderOut(nil)
            shellAutoSuppressed = true
            FloatTabsDiagnostics.record(
                "app_owned_fullscreen_shell_auto_suppressed",
                fields: ["panel_window_number": String(sourcePanel.windowNumber)]
            )
        }

        if pendingExit {
            pendingExit = false
            requestExit(reason: "deferred_page_exitFullscreen")
        }
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === fullscreenWindow,
              phase != .idle else {
            return
        }

        if phase != .exiting {
            AppOwnedFullscreenPresentation.markExiting(webView: activeWebView)
            sourcePanel?.appOwnedFullscreenPhaseDidChange()
            FloatTabsDiagnostics.record(
                "app_owned_fullscreen_exit_requested",
                fields: [
                    "reason": "appkit_or_escape",
                    "window_number": String(window.windowNumber),
                ]
            )
        }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === fullscreenWindow else {
            return
        }

        FloatTabsDiagnostics.record(
            "app_owned_fullscreen_did_exit",
            fields: [
                "window_number": String(window.windowNumber),
                "window_frame": NSStringFromRect(window.frame),
                "window_screen_frame": window.screen.map { NSStringFromRect($0.frame) } ?? "nil",
            ]
        )
        finishExit(reason: "did_exit_fullscreen")
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        guard window === fullscreenWindow else { return }
        FloatTabsDiagnostics.record(
            "app_owned_fullscreen_enter_failed",
            fields: ["window_number": String(window.windowNumber)]
        )
        finishExit(reason: "failed_to_enter_fullscreen")
    }

    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        guard window === fullscreenWindow else { return }
        FloatTabsDiagnostics.record(
            "app_owned_fullscreen_exit_failed",
            fields: ["window_number": String(window.windowNumber)]
        )
        // A failed AppKit exit must not strand the live WKWebView in an orphaned
        // full-screen window. Detach it, restore its original host, and close this
        // one-shot presentation window. The next request always gets a new window.
        finishExit(reason: "failed_to_exit_fullscreen")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === fullscreenWindow else { return true }
        requestExit(reason: "window_close")
        return false
    }

    private func finishExit(reason: String) {
        guard phase != .idle else { return }

        let webView = activeWebView
        let sourceSuperview = self.sourceSuperview
        let sourcePanel = self.sourcePanel
        let shouldRestoreShell = sourcePanelWasVisible
            && shellAutoSuppressed
            && !shellRestoreCancelledByUser
        let window = fullscreenWindow

        // Clear ownership before restoring the WKWebView so normal FloatTabs host
        // layout is allowed to resume immediately. No WebKit-owned fullscreen
        // window exists in this architecture.
        AppOwnedFullscreenPresentation.end(webView: webView)
        pendingExit = false
        sourcePanel?.appOwnedFullscreenPhaseDidChange()

        if let webView {
            webView.removeFromSuperview()
            if let sourceSuperview {
                webView.translatesAutoresizingMaskIntoConstraints = sourceTranslatesAutoresizingMaskIntoConstraints
                webView.autoresizingMask = sourceAutoresizingMask
                webView.frame = sourceFrame
                sourceSuperview.addSubview(webView)
                sourceSuperview.needsLayout = true
                sourceSuperview.layoutSubtreeIfNeeded()
            }
            forcePageExitCleanup(in: webView)
        }

        window?.delegate = nil
        window?.orderOut(nil)
        window?.close()

        fullscreenWindow = nil
        fullscreenHostView = nil
        activeWebView = nil
        self.sourceSuperview = nil
        self.sourcePanel = nil
        sourceFrame = .zero
        sourceAutoresizingMask = []
        sourceTranslatesAutoresizingMaskIntoConstraints = true
        sourcePanelWasVisible = false
        shellAutoSuppressed = false
        shellRestoreCancelledByUser = false

        if shouldRestoreShell,
           let sourcePanel,
           !sourcePanel.isVisible {
            sourcePanel.makeKeyAndOrderFront(nil)
        }

        FloatTabsDiagnostics.record(
            "app_owned_fullscreen_restored",
            fields: [
                "reason": reason,
                "shell_restored": String(shouldRestoreShell),
                "panel_window_number": sourcePanel.map { String($0.windowNumber) } ?? "nil",
                "webview_window_number": webView?.window.map { String($0.windowNumber) } ?? "nil",
            ]
        )
    }

    private func forcePageExitCleanup(in webView: WKWebView) {
        webView.evaluateJavaScript(
            "window.__floatTabsNativeFullscreenDidExit?.();",
            completionHandler: nil
        )
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.prepareForTermination()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
