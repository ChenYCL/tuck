import AppKit

/// Information for an on-screen window, as returned by the Core Graphics window server.
nonisolated struct WindowInfo: Hashable {
    let windowID: CGWindowID
    let frame: CGRect
    let layer: Int
    let alpha: Double
    let ownerPID: pid_t
    let ownerName: String?
    let title: String?
    let isOnScreen: Bool

    /// The application that owns the window.
    var owningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: ownerPID)
    }

    /// Whether the window represents a menu bar item.
    var isMenuBarItem: Bool {
        layer == kCGStatusWindowLevel
    }

    private init?(dictionary: NSDictionary) {
        guard
            let windowID = dictionary[kCGWindowNumber] as? CGWindowID,
            let boundsDict = dictionary[kCGWindowBounds] as? NSDictionary,
            let frame = CGRect(dictionaryRepresentation: boundsDict),
            let layer = dictionary[kCGWindowLayer] as? Int,
            let alpha = dictionary[kCGWindowAlpha] as? Double,
            let ownerPID = dictionary[kCGWindowOwnerPID] as? pid_t
        else {
            return nil
        }
        self.windowID = windowID
        self.frame = frame
        self.layer = layer
        self.alpha = alpha
        self.ownerPID = ownerPID
        self.ownerName = dictionary[kCGWindowOwnerName] as? String
        self.title = dictionary[kCGWindowName] as? String
        self.isOnScreen = dictionary[kCGWindowIsOnscreen] as? Bool ?? false
    }

    /// Creates a window with the given window identifier.
    init?(windowID: CGWindowID) {
        guard let info = Self.infos(for: [windowID]).first else { return nil }
        self = info
    }

    /// Returns the current on-screen windows.
    static func onScreenWindows(excludeDesktop: Bool = false) -> [WindowInfo] {
        var option: CGWindowListOption = [.optionOnScreenOnly]
        if excludeDesktop {
            option.insert(.excludeDesktopElements)
        }
        guard let list = CGWindowListCopyWindowInfo(option, kCGNullWindowID) as? [NSDictionary] else {
            return []
        }
        return list.compactMap { WindowInfo(dictionary: $0) }
    }

    /// Returns window information for the given window identifiers, fetched in a single call.
    static func infos(for windowIDs: [CGWindowID]) -> [WindowInfo] {
        guard !windowIDs.isEmpty else { return [] }
        guard
            let array = Bridging.makeWindowArray(windowIDs),
            let list = CGWindowListCreateDescriptionFromArray(array) as? [NSDictionary]
        else {
            return []
        }
        return list.compactMap { WindowInfo(dictionary: $0) }
    }

    /// Returns the menu bar window for the given display.
    static func menuBarWindow(for display: CGDirectDisplayID) -> WindowInfo? {
        onScreenWindows(excludeDesktop: true).first { window in
            window.ownerName == "Window Server" &&
            window.isOnScreen &&
            window.layer == kCGMainMenuWindowLevel &&
            window.title == "Menubar" &&
            CGDisplayBounds(display).contains(window.frame)
        }
    }

    /// Returns the wallpaper window for the given display.
    static func wallpaperWindow(for display: CGDirectDisplayID) -> WindowInfo? {
        onScreenWindows(excludeDesktop: false).first { window in
            window.owningApplication?.bundleIdentifier == "com.apple.dock" &&
            window.title?.hasPrefix("Wallpaper") == true &&
            CGDisplayBounds(display).contains(window.frame)
        }
    }
}
