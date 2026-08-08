import AppKit
import Foundation

struct PanelMetrics {
    /// User-facing Window Size always means the WKWebView viewport.
    static let defaultViewportSize = NSSize(width: 430, height: 820)
    static let minimumViewportSize = NSSize(width: 320, height: 400)
    static let externalControlZoneWidth: CGFloat = 76

    /// Keep movement acquisition primarily outside WebKit. The effective top /
    /// bottom target is 16 pt deep: 12 pt outside the viewport and only 4 pt
    /// inside it. The website right edge remains protected for scrollbars.
    static let outerInteractionGutter: CGFloat = 12
    static let innerMovementOverlap: CGFloat = 4
    static let webRightInteractionSafety: CGFloat = 24

    /// The visible frame is deliberately much thinner than its hit target.
    /// It is presentation-only and never participates in hit testing.
    static let interactionBorderOutset: CGFloat = 2
    static let interactionBorderLineWidth: CGFloat = 2.5

    /// Bottom-right remains the only resize affordance.
    static let resizeHandleSize: CGFloat = 18
    static let resizeHandleInset: CGFloat = 0

    static let webPanelCornerRadius: CGFloat = 14
    static let structuralBorderWidth: CGFloat = 0

    static var defaultPanelSize: NSSize {
        panelSize(forViewport: defaultViewportSize)
    }

    static var minimumPanelSize: NSSize {
        panelSize(forViewport: minimumViewportSize)
    }

    static func panelSize(forViewport viewportSize: NSSize) -> NSSize {
        NSSize(
            width: externalControlZoneWidth
                + max(viewportSize.width, 0)
                + outerInteractionGutter,
            height: max(viewportSize.height, 0)
                + 2 * outerInteractionGutter
        )
    }

    static func viewportSize(forPanelSize panelSize: NSSize) -> NSSize {
        NSSize(
            width: max(
                panelSize.width - externalControlZoneWidth - outerInteractionGutter,
                0
            ),
            height: max(panelSize.height - 2 * outerInteractionGutter, 0)
        )
    }

    static func clampedPanelSize(_ proposedSize: NSSize) -> NSSize {
        NSSize(
            width: max(proposedSize.width, minimumPanelSize.width),
            height: max(proposedSize.height, minimumPanelSize.height)
        )
    }
}

struct PanelFrameStore {
    static let defaultKey = "FloatTabs.panelFrame"

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = PanelFrameStore.defaultKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    func loadFrame() -> NSRect? {
        guard let encodedFrame = defaults.string(forKey: key) else { return nil }
        let frame = NSRectFromString(encodedFrame)
        guard Self.isValid(frame) else { return nil }
        return frame
    }

    func saveFrame(_ frame: NSRect) {
        guard Self.isValid(frame) else { return }
        defaults.set(NSStringFromRect(frame), forKey: key)
    }

    private static func isValid(_ frame: NSRect) -> Bool {
        frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width > 0
            && frame.height > 0
    }
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
        let clampedSize = constrainedSize(
            size,
            minimumSize: .zero,
            maximumSize: visibleFrame.size
        )

        return NSRect(
            x: visibleFrame.midX - clampedSize.width / 2,
            y: visibleFrame.midY - clampedSize.height / 2,
            width: clampedSize.width,
            height: clampedSize.height
        )
    }

    static func clampedFrame(
        _ frame: NSRect,
        to visibleFrame: NSRect,
        minimumSize: NSSize = PanelMetrics.minimumPanelSize
    ) -> NSRect {
        var result = frame
        result.size = constrainedSize(
            frame.size,
            minimumSize: minimumSize,
            maximumSize: visibleFrame.size
        )

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

    static func restoredFrame(
        _ savedFrame: NSRect,
        visibleFrames: [NSRect],
        fallbackVisibleFrame: NSRect,
        minimumSize: NSSize = PanelMetrics.minimumPanelSize
    ) -> NSRect {
        let destination = bestVisibleFrame(for: savedFrame, visibleFrames: visibleFrames)
            ?? fallbackVisibleFrame

        return clampedFrame(savedFrame, to: destination, minimumSize: minimumSize)
    }

    static func bestVisibleFrame(for frame: NSRect, visibleFrames: [NSRect]) -> NSRect? {
        var bestFrame: NSRect?
        var bestArea: CGFloat = 0

        for visibleFrame in visibleFrames {
            let area = intersectionArea(frame, visibleFrame)
            if area > bestArea {
                bestArea = area
                bestFrame = visibleFrame
            }
        }

        return bestFrame
    }

    private static func constrainedSize(
        _ proposedSize: NSSize,
        minimumSize: NSSize,
        maximumSize: NSSize
    ) -> NSSize {
        NSSize(
            width: constrainedLength(
                proposedSize.width,
                minimum: minimumSize.width,
                maximum: maximumSize.width
            ),
            height: constrainedLength(
                proposedSize.height,
                minimum: minimumSize.height,
                maximum: maximumSize.height
            )
        )
    }

    private static func constrainedLength(
        _ proposed: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat {
        guard maximum > 0 else { return 0 }
        let allowedMinimum = min(max(minimum, 0), maximum)
        return min(max(proposed, allowedMinimum), maximum)
    }

    private static func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return max(intersection.width, 0) * max(intersection.height, 0)
    }
}
