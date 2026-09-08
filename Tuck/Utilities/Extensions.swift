import AppKit

// MARK: - NSScreen

extension NSScreen {
    /// The display identifier of the screen.
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }

    /// The screen whose menu bar is currently active.
    static var screenWithActiveMenuBar: NSScreen? {
        guard let id = Bridging.activeMenuBarDisplayID else { return nil }
        return screens.first { $0.displayID == id }
    }

    /// The screen containing the mouse pointer.
    static var screenWithMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(location) }
    }

    /// Whether the screen has a camera housing (notch).
    var hasNotch: Bool {
        safeAreaInsets.top > 0
    }

    /// The frame of the notch in the screen's coordinate space, if any.
    var frameOfNotch: CGRect? {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
        return CGRect(
            x: left.maxX,
            y: frame.maxY - safeAreaInsets.top,
            width: right.minX - left.maxX,
            height: safeAreaInsets.top
        )
    }

    /// The height of the menu bar on this screen.
    var menuBarHeight: CGFloat {
        if let height = WindowInfo.menuBarWindow(for: displayID)?.frame.height {
            return height
        }
        return frame.maxY - visibleFrame.maxY
    }
}

// MARK: - CGRect

nonisolated extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

// MARK: - NSRunningApplication

nonisolated extension NSRunningApplication {
    static func application(withProcessIdentifier pid: pid_t) -> NSRunningApplication? {
        NSRunningApplication(processIdentifier: pid)
    }
}

// MARK: - Collections

nonisolated extension Array {
    mutating func trimPrefix(while predicate: (Element) throws -> Bool) rethrows {
        var count = 0
        for element in self {
            if try predicate(element) { count += 1 } else { break }
        }
        removeFirst(count)
    }
}

// MARK: - Comparable

nonisolated extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - NSStatusItem

extension NSStatusItem {
    /// Shows the given menu under the status item.
    func showMenu(_ menu: NSMenu) {
        let originalMenu = self.menu
        defer { self.menu = originalMenu }
        self.menu = menu
        button?.performClick(nil)
    }
}

// MARK: - NSEvent

extension NSEvent {
    /// Whether the event was synthesized by Tuck's item mover (it tags events with user data).
    var isSynthesizedByTuck: Bool {
        cgEvent?.getIntegerValueField(.eventSourceUserData) != 0
    }
}
