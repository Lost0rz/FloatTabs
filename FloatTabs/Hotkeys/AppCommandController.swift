import AppKit

enum AppCommand: Equatable {
    case selectSlot(Int)
    case nextSlot
    case previousSlot
    case addWebApp
    case zoomIn
    case zoomOut
    case resetZoom
    case quickURL
}

@MainActor
final class AppCommandController {
    private var monitor: Any?
    private let isEnabled: () -> Bool
    private let onCommand: (AppCommand) -> Void

    init(
        isEnabled: @escaping () -> Bool,
        onCommand: @escaping (AppCommand) -> Void
    ) {
        self.isEnabled = isEnabled
        self.onCommand = onCommand

        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return event }

            if let overlay = Self.presentedQuickURLOverlay(in: event.window ?? NSApp.keyWindow),
               Self.shouldDismissQuickURL(for: event, overlay: overlay) {
                overlay.dismiss()
                overlay.onDismiss?()

                // Escape / Cmd+L are consumed. Outside mouse clicks continue to
                // the underlying website after dismissing the temporary overlay.
                if event.type == .keyDown {
                    return nil
                }
            }

            let routedEvent = Self.correctedMobileWebClickEvent(event) ?? event

            guard event.type == .keyDown,
                  self.isEnabled(),
                  let command = Self.command(for: event) else {
                return routedEvent
            }

            self.onCommand(command)
            return nil
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    static func command(for event: NSEvent) -> AppCommand? {
        command(
            characters: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            modifiers: event.modifierFlags
        )
    }

    nonisolated static func command(
        characters: String?,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> AppCommand? {
        var flags = modifiers.intersection(.deviceIndependentFlagsMask)
        flags.subtract([.capsLock, .numericPad, .function])

        if flags == [.command], let characters, characters.count == 1 {
            switch characters.lowercased() {
            case "t":
                return .addWebApp
            case "l":
                return .quickURL
            case "-":
                return .zoomOut
            case "0":
                return .resetZoom
            case "=", "+":
                return .zoomIn
            default:
                if let value = Int(characters), (1...9).contains(value) {
                    return .selectSlot(value)
                }
            }
        }

        // The physical + key is Shift+= on common Mac keyboard layouts.
        if flags == [.command, .shift],
           let characters,
           characters == "+" || characters == "=" {
            return .zoomIn
        }

        // Hardware Tab key. Using keyCode avoids Shift+Tab character-shape
        // differences while still requiring exact app-local modifiers.
        if keyCode == 48 {
            if flags == [.control] {
                return .nextSlot
            }
            if flags == [.control, .shift] {
                return .previousSlot
            }
        }

        return nil
    }

    /// Maps a physical point on a Mobile page that has been enlarged by the
    /// Website Mode fitting scale back into the unscaled WebKit input space.
    ///
    /// `pageZoom > 1` scales from the page's top-left. AppKit mouse coordinates
    /// use a bottom-left origin, so x divides directly while y must preserve the
    /// distance from the top edge before dividing by the layout scale.
    nonisolated static func correctedMobileWebPoint(
        _ point: NSPoint,
        webViewSize: NSSize,
        layoutScale: CGFloat
    ) -> NSPoint {
        guard layoutScale > 1.0001,
              webViewSize.width > 0,
              webViewSize.height > 0 else {
            return point
        }

        let correctedX = point.x / layoutScale
        let distanceFromTop = webViewSize.height - point.y
        let correctedY = webViewSize.height - (distanceFromTop / layoutScale)

        return NSPoint(
            x: min(max(correctedX, 0), webViewSize.width),
            y: min(max(correctedY, 0), webViewSize.height)
        )
    }

    static func presentedQuickURLOverlay(in window: NSWindow?) -> QuickURLOverlayView? {
        guard let contentView = window?.contentView else { return nil }
        return firstPresentedQuickURLOverlay(in: contentView)
    }

    static func shouldDismissQuickURL(
        for event: NSEvent,
        overlay: QuickURLOverlayView
    ) -> Bool {
        if event.type == .keyDown {
            if event.keyCode == 53 { // Escape
                return true
            }
            return command(for: event) == .quickURL
        }

        guard event.type == .leftMouseDown
                || event.type == .rightMouseDown
                || event.type == .otherMouseDown,
              let superview = overlay.superview else {
            return false
        }

        let point = superview.convert(event.locationInWindow, from: nil)
        return !overlay.frame.contains(point)
    }

    private static func correctedMobileWebClickEvent(_ event: NSEvent) -> NSEvent? {
        guard event.type == .leftMouseDown || event.type == .leftMouseUp,
              let window = event.window,
              let contentView = window.contentView else {
            return nil
        }

        let pointInContent = contentView.convert(event.locationInWindow, from: nil)
        guard let hitView = contentView.hitTest(pointInContent),
              let webView = containingFloatTabsWebView(startingAt: hitView),
              webView.websiteMode == .mobile,
              webView.websiteLayoutScale > 1.0001 else {
            return nil
        }

        let localPoint = webView.convert(event.locationInWindow, from: nil)
        let correctedLocalPoint = correctedMobileWebPoint(
            localPoint,
            webViewSize: webView.bounds.size,
            layoutScale: webView.websiteLayoutScale
        )
        let correctedWindowPoint = webView.convert(correctedLocalPoint, to: nil)

        return NSEvent.mouseEvent(
            with: event.type,
            location: correctedWindowPoint,
            modifierFlags: event.modifierFlags,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            eventNumber: event.eventNumber,
            clickCount: event.clickCount,
            pressure: event.pressure
        )
    }

    private static func containingFloatTabsWebView(startingAt view: NSView) -> FloatTabsWebView? {
        var current: NSView? = view
        while let candidate = current {
            if let webView = candidate as? FloatTabsWebView {
                return webView
            }
            current = candidate.superview
        }
        return nil
    }

    private static func firstPresentedQuickURLOverlay(in view: NSView) -> QuickURLOverlayView? {
        if let overlay = view as? QuickURLOverlayView, overlay.isPresented {
            return overlay
        }

        for subview in view.subviews {
            if let found = firstPresentedQuickURLOverlay(in: subview) {
                return found
            }
        }
        return nil
    }
}
