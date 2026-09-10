import CoreGraphics
import Foundation

enum FloatingHandleGeometry {
    static let inset: CGFloat = 12

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
}
