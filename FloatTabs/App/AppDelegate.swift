import AppKit
import WebKit

/// Keeps element fullscreen on WebKit's native DOM/top-layer path while making
/// each completed presentation disposable. WebKit normally keeps its macOS
/// fullscreen window controller around after a regular exit; on a dual-display
/// Mac that cached controller can later be rebound to the wrong Space. Asking
/// WebKit to close the active media presentation through its public API exits
/// fullscreen and releases that controller without mutating WebKit-owned views
/// or windows.
@MainActor
final class NativeFullscreenSessionResetCoordinator: NSObject, WKScriptMessageHandler {
    static let shared = NativeFullscreenSessionResetCoordinator()
    static let handlerName = "floatTabsNativeFullscreenExit"
    static let escapeKeyCode: UInt16 = 53

    private var localKeyMonitor: Any?
    private var resetInFlight = Set<ObjectIdentifier>()

    static func exitBridgeUserScript() -> WKUserScript {
        WKUserScript(
            source: """
            (() => {
              if (window.__floatTabsNativeFullscreenExitBridgeInstalled) return;
              window.__floatTabsNativeFullscreenExitBridgeInstalled = true;

              const fullscreenElementFor = (doc) =>
                doc && (doc.fullscreenElement || doc.webkitFullscreenElement || null);
              let pendingExitPromise = null;

              const requestNativeExit = (target, args, original) => {
                if (pendingExitPromise) return pendingExitPromise;

                const exitDocument = target instanceof Document
                  ? target
                  : (target && target.ownerDocument) || document;
                const handler = window.webkit
                  && window.webkit.messageHandlers
                  && window.webkit.messageHandlers.floatTabsNativeFullscreenExit;

                if (!handler) {
                  return Reflect.apply(original, target, args);
                }

                let settle;
                pendingExitPromise = new Promise((resolve, reject) => {
                  let settled = false;
                  let fallbackTimer = 0;

                  const cleanup = () => {
                    exitDocument.removeEventListener('fullscreenchange', onFullscreenChange);
                    exitDocument.removeEventListener('webkitfullscreenchange', onFullscreenChange);
                    if (fallbackTimer) window.clearTimeout(fallbackTimer);
                    pendingExitPromise = null;
                  };
                  settle = (callback, value) => {
                    if (settled) return;
                    settled = true;
                    cleanup();
                    callback(value);
                  };
                  const onFullscreenChange = () => {
                    if (!fullscreenElementFor(exitDocument)) settle(resolve);
                  };

                  exitDocument.addEventListener('fullscreenchange', onFullscreenChange);
                  exitDocument.addEventListener('webkitfullscreenchange', onFullscreenChange);

                  // A normal WebKit exit is the safety fallback if the native
                  // message cannot complete for an unexpected transition state.
                  fallbackTimer = window.setTimeout(() => {
                    if (!fullscreenElementFor(exitDocument)) {
                      settle(resolve);
                      return;
                    }

                    try {
                      Promise.resolve(Reflect.apply(original, target, args)).then(
                        (value) => settle(resolve, value),
                        (error) => settle(reject, error)
                      );
                    } catch (error) {
                      settle(reject, error);
                    }
                  }, 3000);

                  try {
                    handler.postMessage({ action: 'exit' });
                  } catch (error) {
                    try {
                      Promise.resolve(Reflect.apply(original, target, args)).then(
                        (value) => settle(resolve, value),
                        (fallbackError) => settle(reject, fallbackError)
                      );
                    } catch (fallbackError) {
                      settle(reject, fallbackError);
                    }
                  }
                });

                return pendingExitPromise;
              };

              const wrapExitMethod = (prototype, name, isFullscreen) => {
                if (!prototype) return;
                const descriptor = Object.getOwnPropertyDescriptor(prototype, name);
                if (!descriptor || typeof descriptor.value !== 'function') return;

                const original = descriptor.value;
                const wrapped = function(...args) {
                  if (!isFullscreen(this)) {
                    return Reflect.apply(original, this, args);
                  }
                  return requestNativeExit(this, args, original);
                };
                try {
                  Object.defineProperty(prototype, name, { ...descriptor, value: wrapped });
                } catch (_) {
                  try { prototype[name] = wrapped; } catch (_) {}
                }
              };

              const documentIsFullscreen = (value) => Boolean(fullscreenElementFor(value));
              wrapExitMethod(Document.prototype, 'exitFullscreen', documentIsFullscreen);
              wrapExitMethod(Document.prototype, 'webkitExitFullscreen', documentIsFullscreen);
              wrapExitMethod(Document.prototype, 'webkitCancelFullScreen', documentIsFullscreen);

              if (typeof HTMLVideoElement !== 'undefined') {
                wrapExitMethod(
                  HTMLVideoElement.prototype,
                  'webkitExitFullscreen',
                  (video) => Boolean(
                    video.webkitDisplayingFullscreen
                    || fullscreenElementFor(video.ownerDocument)
                  )
                );
              }
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    func install(in configuration: WKWebViewConfiguration) {
        configuration.userContentController.addUserScript(Self.exitBridgeUserScript())
        configuration.userContentController.add(self, name: Self.handlerName)
    }

    func start() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) {
            [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated {
                self.handleLocalKeyEvent(event)
            }
        }
    }

    func stop() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        resetInFlight.removeAll()
    }

    static func shouldResetForEscape(
        keyCode: UInt16,
        fullscreenState: WKWebView.FullscreenState,
        resetInFlight: Bool
    ) -> Bool {
        keyCode == escapeKeyCode
            && fullscreenState == .inFullscreen
            && !resetInFlight
    }

    static func canResetForPageExit(
        fullscreenState: WKWebView.FullscreenState,
        resetInFlight: Bool
    ) -> Bool {
        guard !resetInFlight else { return false }
        return fullscreenState == .enteringFullscreen
            || fullscreenState == .inFullscreen
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.handlerName,
              let body = message.body as? [String: Any],
              body["action"] as? String == "exit",
              let webView = message.webView else {
            return
        }

        _ = resetPresentation(
            for: webView,
            trigger: "page_exit_api",
            window: webView.window,
            allowsEnteringState: true
        )
    }

    private func handleLocalKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard event.keyCode == Self.escapeKeyCode,
              let (webView, window) = fullscreenWebView(for: event) else {
            return event
        }

        let id = ObjectIdentifier(webView)
        guard Self.shouldResetForEscape(
            keyCode: event.keyCode,
            fullscreenState: webView.fullscreenState,
            resetInFlight: resetInFlight.contains(id)
        ), resetPresentation(
            for: webView,
            trigger: "escape",
            window: window,
            allowsEnteringState: false
        ) else {
            return event
        }

        // WebKit now owns this exit. Do not also deliver Escape to the page and
        // start an overlapping regular-exit transition.
        return nil
    }

    @discardableResult
    private func resetPresentation(
        for webView: WKWebView,
        trigger: String,
        window: NSWindow?,
        allowsEnteringState: Bool
    ) -> Bool {
        let id = ObjectIdentifier(webView)
        let isInFlight = resetInFlight.contains(id)
        let canReset = allowsEnteringState
            ? Self.canResetForPageExit(
                fullscreenState: webView.fullscreenState,
                resetInFlight: isInFlight
            )
            : Self.shouldResetForEscape(
                keyCode: Self.escapeKeyCode,
                fullscreenState: webView.fullscreenState,
                resetInFlight: isInFlight
            )
        guard canReset else { return false }

        resetInFlight.insert(id)
        FloatTabsDiagnostics.record(
            "fullscreen_public_close_requested",
            fields: diagnosticFields(
                trigger: trigger,
                webView: webView,
                window: window
            )
        )

        webView.closeAllMediaPresentations { [weak self, weak webView, weak window] in
            Task { @MainActor [weak self, weak webView, weak window] in
                guard let self else { return }
                self.resetInFlight.remove(id)
                FloatTabsDiagnostics.record(
                    "fullscreen_public_close_completed",
                    fields: self.diagnosticFields(
                        trigger: trigger,
                        webView: webView,
                        window: window
                    )
                )
            }
        }
        return true
    }

    private func fullscreenWebView(for event: NSEvent) -> (WKWebView, NSWindow)? {
        var windows: [NSWindow] = []
        if let eventWindow = event.window {
            windows.append(eventWindow)
        }
        if let keyWindow = NSApp.keyWindow,
           !windows.contains(where: { $0 === keyWindow }) {
            windows.append(keyWindow)
        }
        let remainingFullscreenWindows = NSApp.windows.filter { candidate in
            !windows.contains(where: { $0 === candidate })
                && candidate.collectionBehavior.contains(.fullScreenPrimary)
        }
        windows.append(contentsOf: remainingFullscreenWindows)

        for window in windows {
            if let webView = firstWebView(in: window.contentView),
               webView.fullscreenState == .inFullscreen {
                return (webView, window)
            }
        }
        return nil
    }

    private func firstWebView(in view: NSView?) -> WKWebView? {
        guard let view else { return nil }
        if let webView = view as? WKWebView {
            return webView
        }
        for subview in view.subviews {
            if let webView = firstWebView(in: subview) {
                return webView
            }
        }
        return nil
    }

    private func diagnosticFields(
        trigger: String,
        webView: WKWebView?,
        window: NSWindow?
    ) -> [String: String] {
        [
            "trigger": trigger,
            "fullscreen_state": webView.map { String(describing: $0.fullscreenState) }
                ?? "released",
            "window_number": window.map { String($0.windowNumber) } ?? "released",
            "window_visible": window.map { String($0.isVisible) } ?? "released",
            "window_active_space": window.map { String($0.isOnActiveSpace) } ?? "released",
            "window_screen_frame": window?.screen.map { NSStringFromRect($0.frame) } ?? "nil",
            "main_screen_frame": NSScreen.main.map { NSStringFromRect($0.frame) } ?? "nil",
        ]
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
        NativeFullscreenSessionResetCoordinator.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NativeFullscreenSessionResetCoordinator.shared.stop()
        coordinator?.prepareForTermination()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
