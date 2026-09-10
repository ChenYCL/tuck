import CoreGraphics
import Foundation

enum FloatingHandleGeometry {
    static let inset: CGFloat = 12

    struct ScreenSpec: Equatable {
        var frame: CGRect
        var menuBarHeight: CGFloat
    }

    static func origin(
        normalized: CGPoint,
        size: CGFloat,
        screen: CGRect,
        menuBarHeight: CGFloat
    ) -> CGPoint {
        let bounds = movableBounds(size: size, screen: screen, menuBarHeight: menuBarHeight)
        return CGPoint(
            x: bounds.minX + normalized.x * bounds.width,
            y: bounds.minY + normalized.y * bounds.height
        )
    }

    static func normalized(
        origin: CGPoint,
        size: CGFloat,
        screen: CGRect,
        menuBarHeight: CGFloat
    ) -> CGPoint {
        let bounds = movableBounds(size: size, screen: screen, menuBarHeight: menuBarHeight)
        let x = bounds.width == 0 ? 1 : (origin.x - bounds.minX) / bounds.width
        let y = bounds.height == 0 ? 0.6 : (origin.y - bounds.minY) / bounds.height
        return CGPoint(x: x.clamped(to: 0...1), y: y.clamped(to: 0...1))
    }

    static func movableBounds(size: CGFloat, screen: CGRect, menuBarHeight: CGFloat) -> CGRect {
        let minX = screen.minX + inset
        let minY = screen.minY + inset
        let maxX = screen.maxX - size - inset
        let maxY = screen.maxY - menuBarHeight - size - inset
        return CGRect(
            x: minX,
            y: minY,
            width: max(0, maxX - minX),
            height: max(0, maxY - minY)
        )
    }

    /// Screen the cursor is on, or the nearest screen if it sits in a gap between displays.
    static func screenContaining(_ point: CGPoint, screens: [ScreenSpec]) -> ScreenSpec? {
        if let hit = screens.first(where: { $0.frame.contains(point) }) {
            return hit
        }
        return screens.min { distance(point, $0.frame) < distance(point, $1.frame) }
    }

    static func clampedOrigin(cursor: CGPoint, size: CGFloat, screens: [ScreenSpec]) -> CGPoint {
        let origin = CGPoint(x: cursor.x - size / 2, y: cursor.y - size / 2)
        guard let screen = screenContaining(cursor, screens: screens) else { return origin }
        let bounds = movableBounds(size: size, screen: screen.frame, menuBarHeight: screen.menuBarHeight)
        return CGPoint(
            x: clamp(origin.x, bounds.minX, bounds.maxX),
            y: clamp(origin.y, bounds.minY, bounds.maxY)
        )
    }

    private static func clamp(_ value: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
        guard a <= b else { return a }
        return value.clamped(to: a...b)
    }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let x = point.x.clamped(to: rect.minX...rect.maxX)
        let y = point.y.clamped(to: rect.minY...rect.maxY)
        return hypot(point.x - x, point.y - y)
    }
}
