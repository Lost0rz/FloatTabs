import AppKit

struct PanelMetrics {
    /// User-facing viewport size. Future external controls sit outside this width.
    static let defaultViewportSize = NSSize(width: 430, height: 820)
    static let minimumViewportSize = NSSize(width: 320, height: 400)
    static let futureExternalControlZoneWidth: CGFloat = 76
}

enum ScreenPositioning {
    static func targetScreen(
        mouseLocation: NSPoint = NSEvent.mouseLocation,
        screens: [NSScreen] = NSScreen.screens,
        fallback: NSScreen? = NSScreen.main
    ) -> NSScreen? {
        screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? fallback
            ?? screens.first
    }

    static func centeredFrame(size: NSSize, in visibleFrame: NSRect) -> NSRect {
        let clampedSize = NSSize(
            width: min(size.width, visibleFrame.width),
            height: min(size.height, visibleFrame.height)
        )

        return NSRect(
            x: visibleFrame.midX - clampedSize.width / 2,
            y: visibleFrame.midY - clampedSize.height / 2,
            width: clampedSize.width,
            height: clampedSize.height
        )
    }

    static func clampedFrame(_ frame: NSRect, to visibleFrame: NSRect) -> NSRect {
        var result = frame

        result.size.width = min(max(result.width, 1), visibleFrame.width)
        result.size.height = min(max(result.height, 1), visibleFrame.height)

        result.origin.x = min(
            max(result.origin.x, visibleFrame.minX),
            visibleFrame.maxX - result.width
        )
        result.origin.y = min(
            max(result.origin.y, visibleFrame.minY),
            visibleFrame.maxY - result.height
        )

        return result
    }
}
