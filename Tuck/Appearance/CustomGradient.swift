import AppKit

nonisolated struct ColorStop: Codable, Hashable, Identifiable {
    var id = UUID()
    var color: CodableColor
    var location: CGFloat

    init(color: CGColor, location: CGFloat) {
        self.color = CodableColor(color)
        self.location = location
    }
}

nonisolated struct CustomGradient: Codable, Hashable {
    var stops: [ColorStop]

    static let `default` = CustomGradient(stops: [
        ColorStop(color: CGColor(gray: 1, alpha: 1), location: 0),
        ColorStop(color: CGColor(gray: 0, alpha: 1), location: 1),
    ])

    var sortedStops: [ColorStop] { stops.sorted { $0.location < $1.location } }

    var nsGradient: NSGradient? {
        let sorted = sortedStops
        guard !sorted.isEmpty else { return nil }
        return NSGradient(colors: sorted.map(\.color.nsColor), atLocations: sorted.map(\.location), colorSpace: .sRGB)
    }

    /// The interpolated color at `location` in `0...1`.
    func color(at location: CGFloat) -> NSColor? {
        nsGradient?.interpolatedColor(atLocation: location.clamped(to: 0...1))
    }

    func withAlphaComponent(_ alpha: CGFloat) -> CustomGradient {
        CustomGradient(stops: stops.map { stop in
            var stop = stop
            stop.color = CodableColor(stop.color.cgColor.copy(alpha: alpha) ?? stop.color.cgColor)
            return stop
        })
    }
}
