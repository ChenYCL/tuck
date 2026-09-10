import Foundation

enum TuckBarLocation: String, CaseIterable, Codable, Identifiable {
    /// Second row directly under the menu bar, trailing-aligned with the status items.
    case below
    /// Vertical strip along the left edge of the screen.
    case left
    /// Vertical strip along the right edge of the screen.
    case right
    case dynamic
    case mousePointer
    case tuckIcon

    var id: Self { self }

    var isVertical: Bool {
        TuckBarGeometry.axis(for: self) == .vertical
    }

    /// Fixed to an edge of the screen / menu bar, rather than floating under the pointer.
    var isAttached: Bool {
        switch self {
        case .below, .left, .right: true
        case .dynamic, .mousePointer, .tuckIcon: false
        }
    }

    /// Left/right use a floating rounded Dock, not a flush attached tab.
    var usesDockChrome: Bool {
        switch self {
        case .left, .right: true
        default: false
        }
    }

    var displayName: String {
        switch self {
        case .below: String(localized: "Below menu bar")
        case .left: String(localized: "Left edge")
        case .right: String(localized: "Right edge")
        case .dynamic: String(localized: "Dynamic")
        case .mousePointer: String(localized: "Mouse pointer")
        case .tuckIcon: String(localized: "Tuck icon")
        }
    }
}
