import AppKit

enum ControlIcon: Codable, Hashable {
    case dot
    case chevron
    case arrow
    case ellipsis
    case sidebar
    case custom(Data)

    static let presets: [ControlIcon] = [.dot, .chevron, .arrow, .ellipsis, .sidebar]

    var name: String {
        switch self {
        case .dot: String(localized: "Dot")
        case .chevron: String(localized: "Chevron")
        case .arrow: String(localized: "Arrow")
        case .ellipsis: String(localized: "Ellipsis")
        case .sidebar: String(localized: "Sidebar")
        case .custom: String(localized: "Custom")
        }
    }

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    private func symbolName(for state: ControlItem.HidingState) -> String? {
        switch (self, state) {
        case (.dot, .hideItems): "circle.fill"
        case (.dot, .showItems): "circle"
        case (.chevron, .hideItems): "chevron.left"
        case (.chevron, .showItems): "chevron.right"
        case (.arrow, .hideItems): "arrow.left"
        case (.arrow, .showItems): "arrow.right"
        case (.ellipsis, .hideItems): "ellipsis.circle.fill"
        case (.ellipsis, .showItems): "ellipsis.circle"
        case (.sidebar, .hideItems): "sidebar.left"
        case (.sidebar, .showItems): "sidebar.right"
        case (.custom, _): nil
        }
    }

    func image(state: ControlItem.HidingState, isTemplate: Bool) -> NSImage? {
        switch self {
        case .custom(let data):
            guard let original = NSImage(data: data) else { return nil }
            let ratio = max(original.size.width / 25, original.size.height / 17)
            let size = ratio > 1
                ? CGSize(width: original.size.width / ratio, height: original.size.height / ratio)
                : original.size
            let image = NSImage(size: size, flipped: false) { rect in
                original.draw(in: rect)
                return true
            }
            image.isTemplate = isTemplate
            return image
        default:
            guard let name = symbolName(for: state) else { return nil }
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
            image?.isTemplate = true
            return image
        }
    }

    static func dividerImage(for identifier: ControlItem.Identifier) -> NSImage? {
        let pointSize: CGFloat = identifier == .alwaysHidden ? 9 : 12
        let image = NSImage(systemSymbolName: "chevron.compact.left", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .medium))
        image?.isTemplate = true
        return image
    }
}
