import AppKit
import SwiftUI

enum FloatingHandleIcon: String, CaseIterable, Codable, Identifiable {
    case chevron
    case overflow
    case pocket
    case monogram

    var id: Self { self }

    var displayName: String {
        switch self {
        case .chevron: String(localized: "Chevron")
        case .overflow: String(localized: "Overflow")
        case .pocket: String(localized: "Pocket")
        case .monogram: String(localized: "Monogram")
        }
    }

    var assetName: String {
        switch self {
        case .chevron: "FabChevron"
        case .overflow: "FabOverflow"
        case .pocket: "FabPocket"
        case .monogram: "FabMonogram"
        }
    }

    var systemImage: String {
        switch self {
        case .chevron: "chevron.down"
        case .overflow: "ellipsis"
        case .pocket: "tray.fill"
        case .monogram: "t.square.fill"
        }
    }
}
