import Foundation

enum DefaultsKey: String {
    case showTuckIcon = "ShowTuckIcon"
    case tuckIcon = "TuckIcon"
    case customIconIsTemplate = "CustomIconIsTemplate"
    case useTuckBar = "UseTuckBar"
    case tuckBarLocation = "TuckBarLocation"
    case tuckBarAlwaysVisible = "TuckBarAlwaysVisible"
    case showFloatingHandle = "ShowFloatingHandle"
    case floatingHandleSize = "FloatingHandleSize"
    case floatingHandleIcon = "FloatingHandleIcon"
    case floatingHandleX = "FloatingHandleX"
    case floatingHandleY = "FloatingHandleY"
    case edgeBarIconSize = "EdgeBarIconSize"
    case edgeBarEdgeInset = "EdgeBarEdgeInset"
    case edgeBarMagnification = "EdgeBarMagnification"
    case showOnClick = "ShowOnClick"
    case showOnHover = "ShowOnHover"
    case showOnScroll = "ShowOnScroll"
    case autoRehide = "AutoRehide"
    case rehideStrategy = "RehideStrategy"
    case rehideInterval = "RehideInterval"
    case itemSpacingOffset = "ItemSpacingOffset"
    case hideApplicationMenus = "HideApplicationMenus"
    case showSectionDividers = "ShowSectionDividers"
    case enableAlwaysHiddenSection = "EnableAlwaysHiddenSection"
    case canToggleAlwaysHiddenSection = "CanToggleAlwaysHiddenSection"
    case showOnHoverDelay = "ShowOnHoverDelay"
    case tempShowInterval = "TempShowInterval"
    case showAllSectionsOnUserDrag = "ShowAllSectionsOnUserDrag"
    case showContextMenuOnRightClick = "ShowContextMenuOnRightClick"
    case hotkeys = "Hotkeys"
    case appearanceConfiguration = "AppearanceConfiguration"
    case hasCompletedOnboarding = "HasCompletedOnboarding"
}

extension UserDefaults {
    func bool(for key: DefaultsKey, default defaultValue: Bool) -> Bool {
        object(forKey: key.rawValue) == nil ? defaultValue : bool(forKey: key.rawValue)
    }

    func double(for key: DefaultsKey, default defaultValue: Double) -> Double {
        object(forKey: key.rawValue) == nil ? defaultValue : double(forKey: key.rawValue)
    }

    func integer(for key: DefaultsKey, default defaultValue: Int) -> Int {
        object(forKey: key.rawValue) == nil ? defaultValue : integer(forKey: key.rawValue)
    }

    func rawValue<T: RawRepresentable>(for key: DefaultsKey, default defaultValue: T) -> T where T.RawValue == String {
        guard let raw = string(forKey: key.rawValue), let value = T(rawValue: raw) else { return defaultValue }
        return value
    }

    func decoded<T: Decodable>(for key: DefaultsKey, default defaultValue: T) -> T {
        guard let data = data(forKey: key.rawValue) else { return defaultValue }
        return (try? JSONDecoder().decode(T.self, from: data)) ?? defaultValue
    }

    func set(_ value: Bool, for key: DefaultsKey) { set(value, forKey: key.rawValue) }
    func set(_ value: Double, for key: DefaultsKey) { set(value, forKey: key.rawValue) }
    func set(_ value: Int, for key: DefaultsKey) { set(value, forKey: key.rawValue) }

    func set<T: RawRepresentable>(_ value: T, for key: DefaultsKey) where T.RawValue == String {
        set(value.rawValue, forKey: key.rawValue)
    }

    func setEncoded<T: Encodable>(_ value: T, for key: DefaultsKey) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        set(data, forKey: key.rawValue)
    }
}
