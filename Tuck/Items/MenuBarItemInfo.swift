import CoreGraphics

/// A simplified, persistable representation of a menu bar item.
nonisolated struct MenuBarItemInfo: Hashable, Codable, CustomStringConvertible {
    /// A namespace that scopes an item's title, typically the bundle identifier
    /// of the application that owns the item.
    struct Namespace: Hashable, Codable {
        let rawValue: String?

        /// The namespace for items with no owning bundle identifier.
        static let null = Namespace(nil)

        /// A per-window namespace for items whose source process could not be resolved.
        static func unresolved(_ windowID: CGWindowID) -> Namespace {
            Namespace("unresolved:\(windowID)")
        }

        var isUnresolved: Bool { rawValue?.hasPrefix("unresolved:") == true }

        /// Creates a namespace with the given raw value. An empty or `nil`
        /// raw value normalizes to ``null``.
        init(_ rawValue: String?) {
            self.rawValue = (rawValue?.isEmpty == false) ? rawValue : nil
        }
    }

    let namespace: Namespace
    let title: String

    var description: String {
        (namespace.rawValue ?? "") + ":" + title
    }

    init(namespace: Namespace, title: String) {
        self.namespace = namespace
        self.title = title
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let colonIndex = string.firstIndex(of: ":") else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Missing namespace separator in \"\(string)\""
                )
            )
        }
        self.namespace = Namespace(String(string[string.startIndex..<colonIndex]))
        self.title = String(string[string.index(after: colonIndex)...])
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

// MARK: - Namespace Constants

nonisolated extension MenuBarItemInfo.Namespace {
    /// The namespace for menu bar items owned by Tuck.
    static let tuck = Self(Constants.bundleIdentifier)

    /// The namespace for menu bar items owned by Control Center.
    static let controlCenter = Self("com.apple.controlcenter")

    /// The namespace for menu bar items owned by the System UI Server.
    static let systemUIServer = Self("com.apple.systemuiserver")
}

// MARK: - Item Constants

nonisolated extension MenuBarItemInfo {
    /// Information for the item that represents the Tuck icon, a.k.a. the
    /// control item for the visible section.
    static let tuckIcon = MenuBarItemInfo(namespace: .tuck, title: ControlItem.Identifier.tuckIcon.rawValue)

    /// Information for the control item for the hidden section.
    static let hiddenControlItem = MenuBarItemInfo(namespace: .tuck, title: ControlItem.Identifier.hidden.rawValue)

    /// Information for the control item for the always-hidden section.
    static let alwaysHiddenControlItem = MenuBarItemInfo(namespace: .tuck, title: ControlItem.Identifier.alwaysHidden.rawValue)

    /// Information for the "Clock" item (accessibility identifier form).
    static let clock = MenuBarItemInfo(namespace: .controlCenter, title: "com.apple.menuextra.clock")

    /// Information for the "Siri" item.
    static let siri = MenuBarItemInfo(namespace: .systemUIServer, title: "Siri")

    /// Information for the "BentoBox" (a.k.a. "Control Center") item.
    static let controlCenter = MenuBarItemInfo(namespace: .controlCenter, title: "com.apple.menuextra.controlcenter")

    /// Information for the system item shown while the Screenshot tool records.
    static let screenCaptureUI = MenuBarItemInfo(namespace: Namespace("com.apple.screencaptureui"), title: "Item-0")

    /// Information for the item that appears in the menu bar while the screen
    /// or system audio is being recorded.
    static let audioVideoModule = MenuBarItemInfo(namespace: .controlCenter, title: "AudioVideoModule")

    /// Information for the "FaceTime" item.
    static let faceTime = MenuBarItemInfo(namespace: .controlCenter, title: "FaceTime")

    /// Information for the "MusicRecognition" (a.k.a. "Shazam") item.
    static let musicRecognition = MenuBarItemInfo(namespace: .controlCenter, title: "MusicRecognition")

    /// Items whose movement is prevented by macOS. Siri became movable in macOS 26.
    /// Window-title forms are included for items resolved without an accessibility identifier.
    static let immovable: Set<MenuBarItemInfo> = [
        clock, controlCenter,
        MenuBarItemInfo(namespace: .controlCenter, title: "Clock"),
        MenuBarItemInfo(namespace: .controlCenter, title: "BentoBox-0"),
    ]

    /// Items that can be moved, but cannot be hidden.
    static let nonHideable: Set<MenuBarItemInfo> = [
        audioVideoModule, faceTime, screenCaptureUI,
        MenuBarItemInfo(namespace: .controlCenter, title: "com.apple.menuextra.audiovideo"),
        MenuBarItemInfo(namespace: .controlCenter, title: "com.apple.menuextra.facetime"),
    ]

    /// Whether the item is one of Tuck's control items.
    var isControlItem: Bool {
        namespace == .tuck && ControlItem.Identifier(rawValue: title) != nil
    }

    /// Whether the item is a Control Center group ("BentoBox").
    var isBentoBox: Bool {
        namespace == .controlCenter && (title.hasPrefix("BentoBox") || title == "com.apple.menuextra.controlcenter")
    }

    /// Whether the item is a system-created clone of a real item.
    var isSystemClone: Bool {
        namespace.isUnresolved && title == "System Status Item Clone"
    }
}
