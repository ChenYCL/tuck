import AppKit
import ApplicationServices

/// Locates the on-screen frame of the frontmost app's application menu (the menu
/// items to the left of the menu bar item area, e.g. "Finder", "File", "Edit", …).
@MainActor
enum ApplicationMenu {
    private struct CacheKey: Hashable {
        let display: CGDirectDisplayID
        let pid: pid_t?
    }

    private struct CacheEntry {
        let frame: CGRect?
        let timestamp: Date
    }

    private static let cacheTTL: TimeInterval = 0.5
    private static var cache: [CacheKey: CacheEntry] = [:]

    /// Returns the frame of the application menu for the given display, or `nil` if
    /// it could not be determined.
    static func frame(for display: CGDirectDisplayID) -> CGRect? {
        let key = CacheKey(display: display, pid: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        if let entry = cache[key], Date().timeIntervalSince(entry.timestamp) < cacheTTL {
            return entry.frame
        }
        let frame = computeFrame(for: display)
        cache[key] = CacheEntry(frame: frame, timestamp: Date())
        return frame
    }

    /// Returns whether the given display currently has a menu bar that the
    /// Accessibility API can locate an application menu within.
    static func hasValidMenuBar(for display: CGDirectDisplayID) -> Bool {
        frame(for: display) != nil
    }

    /// Clears the cached application menu frames.
    static func invalidateCache() {
        cache.removeAll()
    }

    private static func computeFrame(for display: CGDirectDisplayID) -> CGRect? {
        let displayBounds = CGDisplayBounds(display)

        let systemWide = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        guard
            AXUIElementCopyElementAtPosition(systemWide, Float(displayBounds.minX), Float(displayBounds.minY), &elementRef) == .success,
            let menuBarElement = elementRef
        else {
            return nil
        }

        var roleRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(menuBarElement, kAXRoleAttribute as CFString, &roleRef) == .success,
            let role = roleRef as? String,
            role == kAXMenuBarRole
        else {
            return nil
        }

        var childrenRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(menuBarElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
            let children = childrenRef as? [AXUIElement]
        else {
            return nil
        }

        var applicationMenuFrame = CGRect.null
        for child in children {
            var enabledRef: CFTypeRef?
            guard
                AXUIElementCopyAttributeValue(child, kAXEnabledAttribute as CFString, &enabledRef) == .success,
                let enabled = enabledRef as? Bool,
                enabled
            else {
                continue
            }

            var frameRef: CFTypeRef?
            guard
                AXUIElementCopyAttributeValue(child, "AXFrame" as CFString, &frameRef) == .success,
                let frameRef,
                CFGetTypeID(frameRef) == AXValueGetTypeID()
            else {
                continue
            }

            var childFrame = CGRect.zero
            guard AXValueGetValue(frameRef as! AXValue, .cgRect, &childFrame) else {
                continue
            }

            applicationMenuFrame = applicationMenuFrame.union(childFrame)
        }

        if applicationMenuFrame.width <= 0 {
            return nil
        }

        // The Accessibility API returns the menu bar for the active screen, regardless of the
        // display origin used. This workaround prevents an incorrect frame from being returned
        // for inactive displays in multi-display setups where one display has a notch.
        if
            let mainScreen = NSScreen.main,
            let thisScreen = NSScreen.screens.first(where: { $0.displayID == display }),
            thisScreen != mainScreen,
            let notchedScreen = NSScreen.screens.first(where: { $0.hasNotch }),
            let leftArea = notchedScreen.auxiliaryTopLeftArea,
            applicationMenuFrame.width >= leftArea.maxX
        {
            return nil
        }

        return applicationMenuFrame
    }
}
