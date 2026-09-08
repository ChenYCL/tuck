import AppKit

/// A representation of an item in the menu bar.
nonisolated struct MenuBarItem: Hashable {
    let window: WindowInfo
    let info: MenuBarItemInfo

    /// The process and accessibility element behind the item. On macOS 26 item windows
    /// are owned by Control Center, so `ownerPID` never identifies the source app.
    let source: ItemSource?

    var sourcePID: pid_t? { source?.pid }

    var windowID: CGWindowID { window.windowID }
    var frame: CGRect { window.frame }
    var title: String? { window.title }
    var ownerPID: pid_t { window.ownerPID }
    var ownerName: String? { window.ownerName }
    var isOnScreen: Bool { window.isOnScreen }

    /// The application that created the item.
    var owningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: sourcePID ?? ownerPID)
    }

    /// The process to target when posting events to the item.
    var eventPID: pid_t { sourcePID ?? ownerPID }

    var isMovable: Bool { !MenuBarItemInfo.immovable.contains(info) }
    var canBeHidden: Bool { !MenuBarItemInfo.nonHideable.contains(info) }
    var isControlItem: Bool { info.isControlItem }
    var isBentoBox: Bool { info.isBentoBox }

    /// A name suited for display to the user.
    var displayName: String {
        func titleCase(_ string: String) -> String {
            string.replacing(#/([a-z]{2})([A-Z])/#) { $0.output.1 + " " + $0.output.2 }
        }
        if isControlItem { return Constants.appName }
        let sourceName = owningApplication?.localizedName ?? owningApplication?.bundleIdentifier
        switch info.namespace {
        case .controlCenter:
            // Control Center localizes its element labels (e.g. "Wi‑Fi, connected"); keep the
            // short, well-known names for the common items and fall back to the label otherwise.
            switch info.title {
            case "com.apple.menuextra.clock", "Clock": return "Clock"
            case "com.apple.menuextra.controlcenter", "BentoBox-0": return sourceName ?? "Control Center"
            case "com.apple.menuextra.wifi": return "Wi-Fi"
            case "com.apple.menuextra.battery": return "Battery"
            case "com.apple.menuextra.bluetooth": return "Bluetooth"
            case "com.apple.menuextra.sound": return "Sound"
            case "com.apple.menuextra.display": return "Display"
            case "com.apple.menuextra.focus": return "Focus"
            case "com.apple.menuextra.screenmirroring": return "Screen Mirroring"
            case "com.apple.menuextra.airdrop": return "AirDrop"
            case "com.apple.menuextra.nowplaying": return "Now Playing"
            case "com.apple.menuextra.hearing": return "Hearing"
            case "com.apple.menuextra.keyboardbrightness": return "Keyboard Brightness"
            case "com.apple.menuextra.stagemanager": return "Stage Manager"
            case "com.apple.menuextra.userswitcher": return "Fast User Switching"
            case "com.apple.menuextra.accessibility": return "Accessibility Shortcuts"
            case _ where info.title.hasPrefix("com.apple.menuextra."):
                return source?.label ?? titleCase(String(info.title.dropFirst("com.apple.menuextra.".count)).capitalized)
            case "AccessibilityShortcuts": return "Accessibility Shortcuts"
            case "FocusModes": return "Focus"
            case "KeyboardBrightness": return "Keyboard Brightness"
            case "MusicRecognition": return "Music Recognition"
            case "NowPlaying": return "Now Playing"
            case "ScreenMirroring": return "Screen Mirroring"
            case "StageManager": return "Stage Manager"
            case "UserSwitcher": return "Fast User Switching"
            case "WiFi": return "Wi-Fi"
            case _ where info.isBentoBox:
                return info == .controlCenter ? (sourceName ?? "Control Center") : info.title
            case _ where info.title.hasPrefix("Hearing"): return "Hearing"
            default: return titleCase(info.title)
            }
        case .systemUIServer:
            return info.title.contains("TimeMachine") ? "Time Machine" : titleCase(info.title)
        case MenuBarItemInfo.Namespace("com.apple.Passwords.MenuBarExtra"):
            return "Passwords"
        default:
            guard let sourceName else {
                return source?.label ?? (info.title.isEmpty ? "Menu Bar Item" : info.title)
            }
            // Apps with several items need the item label to tell them apart.
            if let label = source?.label, label != sourceName, sourceItemCount > 1 {
                return "\(sourceName) – \(label)"
            }
            if UUID(uuidString: info.title) != nil {
                return "\(sourceName) (\(info.title))"
            }
            return sourceName
        }
    }

    /// The number of items the source app exposes; 1 when unknown.
    private var sourceItemCount: Int {
        guard let source else { return 1 }
        return source.index + 1
    }

    /// Creates a menu bar item from the given window. Fails unless the window
    /// represents a menu bar item.
    init?(window: WindowInfo, source: ItemSource?) {
        guard window.isMenuBarItem else { return nil }
        self.window = window
        self.source = source
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let namespace: MenuBarItemInfo.Namespace
        if let source, let app = NSRunningApplication(processIdentifier: source.pid) {
            namespace = source.pid == ownPID ? .tuck : MenuBarItemInfo.Namespace(app.bundleIdentifier ?? app.localizedName)
        } else if let title = window.title, ControlItem.Identifier(rawValue: title) != nil {
            namespace = .tuck
        } else {
            namespace = .unresolved(window.windowID)
        }
        // Identity priority: the source app's accessibility identifier (stable, permission-free),
        // then the window title (needs screen recording), then the element's index in its app.
        let title: String
        if let identifier = source?.identifier {
            title = identifier
        } else if let windowTitle = window.title, !windowTitle.isEmpty {
            title = windowTitle
        } else if let source {
            title = "Item-\(source.index)"
        } else {
            title = ""
        }
        self.info = MenuBarItemInfo(namespace: namespace, title: title)
    }

    /// Creates a menu bar item from the given window using the cached source.
    init?(window: WindowInfo) {
        self.init(window: window, source: ItemSourceResolver.shared.cachedSource(for: window.windowID))
    }

    /// Creates a menu bar item with the given window identifier.
    init?(windowID: CGWindowID) {
        guard let window = WindowInfo(windowID: windowID) else { return nil }
        self.init(window: window)
    }

    /// Returns the current menu bar item windows, sorted left to right.
    static func windows(on display: CGDirectDisplayID? = nil, onScreenOnly: Bool, activeSpaceOnly: Bool) -> [WindowInfo] {
        var option: Bridging.WindowListOption = [.menuBarItems]
        if onScreenOnly { option.insert(.onScreen) }
        if activeSpaceOnly { option.insert(.activeSpace) }

        var windowIDs = Bridging.windowList(option: option)
        if let display {
            let displayBounds = CGDisplayBounds(display)
            windowIDs = windowIDs.filter { windowID in
                guard let frame = Bridging.windowFrame(for: windowID) else { return false }
                return displayBounds.intersects(frame)
            }
        }
        return WindowInfo.infos(for: windowIDs)
            .filter(\.isMenuBarItem)
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Returns the current menu bar items using cached source processes; suitable for
    /// hit-testing and other synchronous callers.
    static func all(on display: CGDirectDisplayID? = nil, onScreenOnly: Bool, activeSpaceOnly: Bool) -> [MenuBarItem] {
        windows(on: display, onScreenOnly: onScreenOnly, activeSpaceOnly: activeSpaceOnly).compactMap { MenuBarItem(window: $0) }
    }

    /// Returns the current menu bar items, resolving source processes off the main thread first.
    static func resolveAll(on display: CGDirectDisplayID? = nil, onScreenOnly: Bool, activeSpaceOnly: Bool) async -> [MenuBarItem] {
        let windows = windows(on: display, onScreenOnly: onScreenOnly, activeSpaceOnly: activeSpaceOnly)
        let sources = await Task.detached(priority: .userInitiated) {
            ItemSourceResolver.shared.resolve(windows)
        }.value
        return windows.compactMap { MenuBarItem(window: $0, source: sources[$0.windowID]) }
    }
}
