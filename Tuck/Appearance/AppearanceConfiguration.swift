import AppKit

nonisolated enum MenuBarEndCap: Int, Codable, CaseIterable {
    case square = 0
    case round = 1
}

nonisolated enum MenuBarShapeKind: Int, Codable, CaseIterable {
    case none = 0
    case full = 1
    case split = 2
}

nonisolated enum TintKind: Int, Codable, CaseIterable {
    case none = 0
    case solid = 1
    case gradient = 2
}

nonisolated struct FullShapeInfo: Codable, Hashable {
    var leadingEndCap: MenuBarEndCap = .round
    var trailingEndCap: MenuBarEndCap = .round
}

nonisolated struct SplitShapeInfo: Codable, Hashable {
    var leading = FullShapeInfo()
    var trailing = FullShapeInfo()
}

/// Appearance settings that can differ between light and dark mode.
nonisolated struct PartialConfiguration: Codable, Hashable {
    var hasShadow = false
    var hasBorder = false
    var borderColor = CodableColor(CGColor(gray: 0, alpha: 1))
    var borderWidth: Double = 1
    var tintKind: TintKind = .none
    var tintColor = CodableColor(CGColor(gray: 0, alpha: 1))
    var tintGradient = CustomGradient.default

    static let `default` = PartialConfiguration()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case hasShadow, hasBorder, borderColor, borderWidth, tintKind, tintColor, tintGradient
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasShadow = try c.decodeIfPresent(Bool.self, forKey: .hasShadow) ?? false
        hasBorder = try c.decodeIfPresent(Bool.self, forKey: .hasBorder) ?? false
        borderColor = try c.decodeIfPresent(CodableColor.self, forKey: .borderColor) ?? borderColor
        borderWidth = try c.decodeIfPresent(Double.self, forKey: .borderWidth) ?? 1
        tintKind = try c.decodeIfPresent(TintKind.self, forKey: .tintKind) ?? .none
        tintColor = try c.decodeIfPresent(CodableColor.self, forKey: .tintColor) ?? tintColor
        tintGradient = try c.decodeIfPresent(CustomGradient.self, forKey: .tintGradient) ?? .default
    }
}

nonisolated struct AppearanceConfiguration: Codable, Hashable {
    var light = PartialConfiguration()
    var dark = PartialConfiguration()
    var `static` = PartialConfiguration()
    var shapeKind: MenuBarShapeKind = .none
    var fullShapeInfo = FullShapeInfo()
    var splitShapeInfo = SplitShapeInfo()
    var isInset = true
    var isDynamic = false

    static let `default` = AppearanceConfiguration()

    init() {}

    /// The partial configuration in effect for the current system appearance.
    @MainActor
    var current: PartialConfiguration {
        guard isDynamic else { return `static` }
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? dark : light
    }

    private enum CodingKeys: String, CodingKey {
        case light, dark, `static`, shapeKind, fullShapeInfo, splitShapeInfo, isInset, isDynamic
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        light = try c.decodeIfPresent(PartialConfiguration.self, forKey: .light) ?? PartialConfiguration()
        dark = try c.decodeIfPresent(PartialConfiguration.self, forKey: .dark) ?? PartialConfiguration()
        `static` = try c.decodeIfPresent(PartialConfiguration.self, forKey: .static) ?? PartialConfiguration()
        shapeKind = try c.decodeIfPresent(MenuBarShapeKind.self, forKey: .shapeKind) ?? .none
        fullShapeInfo = try c.decodeIfPresent(FullShapeInfo.self, forKey: .fullShapeInfo) ?? FullShapeInfo()
        splitShapeInfo = try c.decodeIfPresent(SplitShapeInfo.self, forKey: .splitShapeInfo) ?? SplitShapeInfo()
        isInset = try c.decodeIfPresent(Bool.self, forKey: .isInset) ?? true
        isDynamic = try c.decodeIfPresent(Bool.self, forKey: .isDynamic) ?? false
    }
}
