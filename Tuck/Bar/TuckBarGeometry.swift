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

    /// Extra gap under the menu bar for pointer-following HUDs. Below sits flush;
    /// left/right use a Dock-style inset instead.
    static func menuBarGap(for location: TuckBarLocation) -> CGFloat {
        switch location {
        case .below: 0
        case .left, .right: 0
        case .dynamic, .mousePointer, .tuckIcon: 4
        }
    }

    /// Distance from the screen edge. Left/right float inward like the Dock.
    static func edgeInset(for location: TuckBarLocation, configured: CGFloat) -> CGFloat {
        switch location {
        case .left, .right: configured
        default: 0
        }
    }

    /// Vertically center a left/right bar in the area below the menu bar.
    static func verticallyCenteredY(barHeight: CGFloat, screen: Screen) -> CGFloat {
        let top = screen.frame.maxY - screen.menuBarHeight
        let bottom = screen.frame.minY
        let mid = (top + bottom) / 2
        let y = mid - barHeight / 2
        let maxY = top - barHeight
        let minY = bottom
        guard minY <= maxY else { return minY }
        return y.clamped(to: minY...maxY)
    }

    /// Below + always-visible uses a compact handle so the extra row does not
    /// cover the window title bar. Other placements show items immediately.
    static func showsItems(location: TuckBarLocation, alwaysVisible: Bool, expanded: Bool) -> Bool {
        guard alwaysVisible, location == .below else { return true }
        return expanded
    }

    /// Apple Dock-style falloff: the hovered icon is largest, neighbors shrink
    /// with a cosine curve so they make room instead of stacking.
    static func dockScale(distance: CGFloat, range: CGFloat = 2.2, maxScale: CGFloat) -> CGFloat {
        guard maxScale > 1.01, distance < range else { return 1 }
        return 1 + (maxScale - 1) * 0.5 * (1 + Foundation.cos(.pi * distance / range))
    }

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
        isMouseInEmptySpace: Bool,
        edgeInset: CGFloat = 12
    ) -> CGPoint {
        let yBelowMenuBar = screen.frame.maxY - screen.menuBarHeight - barSize.height - menuBarGap(for: location)

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
            return CGPoint(
                x: screen.frame.minX + edgeInset,
                y: verticallyCenteredY(barHeight: barSize.height, screen: screen)
            )
        case .right:
            return CGPoint(
                x: screen.frame.maxX - barSize.width - edgeInset,
                y: verticallyCenteredY(barHeight: barSize.height, screen: screen)
            )
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
