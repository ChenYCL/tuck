import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case layout
    case appearance
    case hotkeys
    case advanced
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .layout: String(localized: "Menu Bar Layout")
        case .appearance: String(localized: "Menu Bar Appearance")
        case .hotkeys: String(localized: "Hotkeys")
        case .advanced: String(localized: "Advanced")
        case .about: String(localized: "About")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .layout: "rectangle.topthird.inset.filled"
        case .appearance: "paintpalette"
        case .hotkeys: "keyboard"
        case .advanced: "gearshape.2"
        case .about: "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .layout: .blue
        case .appearance: .purple
        case .hotkeys: .orange
        case .advanced: .indigo
        case .about: .teal
        }
    }
}
