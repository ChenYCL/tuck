import Foundation

enum RehideStrategy: String, CaseIterable, Codable, Identifiable {
    case smart
    case timed
    case focusedApp

    var id: Self { self }
}
