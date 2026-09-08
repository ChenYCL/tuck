import AppKit

/// A `CGColor` that round-trips through `Codable` with its color space.
nonisolated struct CodableColor: Codable, Hashable {
    var cgColor: CGColor

    init(_ cgColor: CGColor) {
        self.cgColor = cgColor
    }

    init(_ nsColor: NSColor) {
        self.cgColor = nsColor.cgColor
    }

    var nsColor: NSColor {
        NSColor(cgColor: cgColor) ?? .black
    }

    private enum CodingKeys: String, CodingKey {
        case components
        case colorSpace
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let components = try container.decode([CGFloat].self, forKey: .components)
        let iccData = try container.decode(Data.self, forKey: .colorSpace)
        guard
            let colorSpace = CGColorSpace(iccData: iccData as CFData),
            let color = CGColor(colorSpace: colorSpace, components: components)
        else {
            throw DecodingError.dataCorruptedError(forKey: .components, in: container, debugDescription: "Invalid color")
        }
        self.cgColor = color
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        guard
            let components = cgColor.components,
            let iccData = cgColor.colorSpace?.copyICCData() as? Data
        else {
            throw EncodingError.invalidValue(cgColor, .init(codingPath: encoder.codingPath, debugDescription: "Color has no components or ICC data"))
        }
        try container.encode(components, forKey: .components)
        try container.encode(iccData, forKey: .colorSpace)
    }

    static func == (lhs: CodableColor, rhs: CodableColor) -> Bool {
        lhs.cgColor == rhs.cgColor
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(cgColor.components ?? [])
        hasher.combine(cgColor.colorSpace?.name as String?)
    }
}
