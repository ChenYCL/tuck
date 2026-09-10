import CoreGraphics
import Foundation

/// Pure layout math for the Tuck Bar. Kept free of AppKit so it can be unit-tested.
enum TuckBarGeometry {
    enum Axis: Equatable {
        case horizontal
        case vertical
    }

    struct Screen: Equatable {
        var frame: CGRect
        var menuBarHeight: CGFloat
    }

    static let edgeInset: CGFloat = 4

    static func axis(for location: TuckBarLocation) -> Axis {
        switch location {
        case .left, .right: .vertical
        case .below, .dynamic, .mousePointer, .tuckIcon: .horizontal
        }
    }

    /// AppKit origin (bottom-left) for a bar of `barSize` on `screen`.
    static func origin(
        location: TuckBarLocation,
        barSize: CGSize,
        screen: Screen,
        mouseX: CGFloat,
        tuckIconMidX: CGFloat?,
        isMouseInEmptySpace: Bool
    ) -> CGPoint {
        let yBelowMenuBar = (screen.frame.maxY - 1) - screen.menuBarHeight - barSize.height

        func clampedX(_ x: CGFloat) -> CGFloat {
            let lowerBound = screen.frame.minX
            let upperBound = screen.frame.maxX - barSize.width
            guard lowerBound <= upperBound else { return screen.frame.maxX - barSize.width }
            return x.clamped(to: lowerBound...upperBound)
        }

        func clampedY(_ y: CGFloat) -> CGFloat {
            let lowerBound = screen.frame.minY
            let upperBound = yBelowMenuBar
            guard lowerBound <= upperBound else { return lowerBound }
            return y.clamped(to: lowerBound...upperBound)
        }

        func mousePointerX() -> CGFloat {
            clampedX(mouseX - barSize.width / 2)
        }

        func tuckIconX() -> CGFloat {
            guard let tuckIconMidX else { return mousePointerX() }
            return clampedX(tuckIconMidX - barSize.width / 2)
        }

        switch location {
        case .below:
            return CGPoint(x: clampedX(screen.frame.maxX - barSize.width), y: yBelowMenuBar)
        case .left:
            return CGPoint(x: screen.frame.minX + edgeInset, y: clampedY(yBelowMenuBar))
        case .right:
            return CGPoint(x: screen.frame.maxX - barSize.width - edgeInset, y: clampedY(yBelowMenuBar))
        case .dynamic:
            let x = isMouseInEmptySpace ? mousePointerX() : tuckIconX()
            return CGPoint(x: x, y: yBelowMenuBar)
        case .mousePointer:
            return CGPoint(x: mousePointerX(), y: yBelowMenuBar)
        case .tuckIcon:
            return CGPoint(x: tuckIconX(), y: yBelowMenuBar)
        }
    }
}
