import AppKit

nonisolated enum MouseCursor {
    /// Cursor location in AppKit coordinates (origin bottom-left).
    static var locationAppKit: CGPoint? {
        CGEvent(source: nil).map { event in
            let screenHeight = NSScreen.screens.first.map { $0.frame.maxY } ?? 0
            return CGPoint(x: event.location.x, y: screenHeight - event.location.y)
        }
    }

    /// Cursor location in CoreGraphics coordinates (origin top-left).
    static var locationCoreGraphics: CGPoint? {
        CGEvent(source: nil)?.location
    }

    static func hide() {
        CGDisplayHideCursor(CGMainDisplayID())
    }

    static func show() {
        CGDisplayShowCursor(CGMainDisplayID())
    }

    /// Warps the cursor to a point in CoreGraphics coordinates.
    static func warp(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
    }
}
