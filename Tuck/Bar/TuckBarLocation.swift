import Foundation

enum TuckBarLocation: String, CaseIterable, Codable, Identifiable {
    case dynamic
    case mousePointer
    case tuckIcon

    var id: Self { self }
}
