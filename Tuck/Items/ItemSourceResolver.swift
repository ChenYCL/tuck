import AppKit
import ApplicationServices
import OSLog

/// The process and accessibility element behind a menu bar item window.
nonisolated struct ItemSource: Hashable, Sendable {
    let pid: pid_t
    /// The element's `AXIdentifier`, if the source app sets one.
    let identifier: String?
    /// The element's `AXTitle` or `AXDescription`, localized by the source app.
    let label: String?
    /// The element's index within the source app's extras menu bar.
    let index: Int
    /// The matched accessibility element, used to re-validate the match.
    let element: AXUIElement

    static func == (lhs: ItemSource, rhs: ItemSource) -> Bool {
        lhs.pid == rhs.pid && lhs.identifier == rhs.identifier && lhs.label == rhs.label && lhs.index == rhs.index
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
        hasher.combine(identifier)
        hasher.combine(index)
    }
}

/// Resolves the process and accessibility element that back each menu bar item window.
///
/// As of macOS 26, item windows are owned by Control Center, so the window owner no
/// longer identifies the source app, and window titles are only readable with screen
/// recording permission. Each running app exposes its items through its `AXExtrasMenuBar`
/// element; item windows are matched to those elements geometrically.
///
/// Accessibility calls block, so resolution runs off the main thread; `cachedSource(for:)`
/// is a non-blocking lookup for synchronous callers.
nonisolated final class ItemSourceResolver: Sendable {
    static let shared = ItemSourceResolver()

    private final class CachedApplication {
        let app: NSRunningApplication
        private var extrasMenuBar: AXUIElement?
        private var failedAt: Date?

        var pid: pid_t { app.processIdentifier }
        var hasExtrasMenuBar: Bool { extrasMenuBar != nil }

        init(_ app: NSRunningApplication) {
            self.app = app
        }

        private var isProhibited: Bool { app.activationPolicy == .prohibited }

        private var isValidForAccessibility: Bool {
            app.isFinishedLaunching &&
            !app.isTerminated &&
            (!isProhibited || app.bundleURL?.pathExtension == "app") &&
            Bridging.responsivity(for: pid) != .unresponsive
        }

        func getOrCreateExtrasMenuBar() -> AXUIElement? {
            if let extrasMenuBar { return extrasMenuBar }
            // Retry failed apps only every few seconds; their items usually appear after launch.
            if let failedAt, Date.now.timeIntervalSince(failedAt) < 5 { return nil }
            guard isValidForAccessibility else { return nil }
            let element = AXUIElementCreateApplication(pid)
            // Prohibited apps often have no accessibility server; keep calls from stalling.
            AXUIElementSetMessagingTimeout(element, isProhibited ? 0.25 : 1)
            var value: CFTypeRef?
            guard
                AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &value) == .success,
                let value, CFGetTypeID(value) == AXUIElementGetTypeID()
            else {
                failedAt = .now
                return nil
            }
            let bar = value as! AXUIElement
            extrasMenuBar = bar
            return bar
        }
    }

    private struct ExtrasItem {
        let source: ItemSource
        let frame: CGRect
    }

    private struct State {
        var apps: [pid_t: CachedApplication] = [:]
        var sources: [CGWindowID: ItemSource] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    private init() {}

    /// Non-blocking lookup of a previously resolved source.
    func cachedSource(for windowID: CGWindowID) -> ItemSource? {
        state.withLock { $0.sources[windowID] }
    }

    /// Drops cached results for windows that no longer exist.
    func prune(keeping windowIDs: [CGWindowID]) {
        let keep = Set(windowIDs)
        state.withLock { state in
            state.sources = state.sources.filter { keep.contains($0.key) }
        }
    }

    /// Resolves sources for the given item windows, blocking on Accessibility calls.
    /// Call from a background task.
    @discardableResult
    func resolve(_ windows: [WindowInfo]) -> [CGWindowID: ItemSource] {
        guard AXIsProcessTrusted() else { return [:] }
        return state.withLock { state in
            syncApps(&state)
            // Items move (and Tuck re-adds its own); drop cached matches whose element no
            // longer sits inside the window.
            for window in windows {
                guard let source = state.sources[window.windowID] else { continue }
                guard
                    let bounds = Bridging.windowFrame(for: window.windowID),
                    let frame = Self.frame(of: source.element),
                    bounds.minX <= frame.midX, frame.midX <= bounds.maxX
                else {
                    state.sources.removeValue(forKey: window.windowID)
                    continue
                }
            }
            let unresolved: [(windowID: CGWindowID, bounds: CGRect)] = windows.compactMap { window in
                guard state.sources[window.windowID] == nil else { return nil }
                guard let bounds = Bridging.windowFrame(for: window.windowID) else { return nil }
                return (window.windowID, bounds)
            }
            if unresolved.isEmpty {
                return state.sources
            }

            let items = collectExtrasItems(&state)
            var unclaimedWindows = Set(unresolved.map(\.windowID))
            var unclaimedItems = Set(items.indices)

            // Accessibility frames sit inside the item window horizontally; item windows span
            // the full menu bar height, so vertical geometry only adds noise.
            var pairs: [(score: CGFloat, index: Int, windowID: CGWindowID)] = []
            for (windowID, bounds) in unresolved {
                for index in unclaimedItems {
                    let frame = items[index].frame
                    guard frame.width > 0, bounds.minX <= frame.midX, frame.midX <= bounds.maxX else { continue }
                    let score = abs(bounds.midX - frame.midX) * 10 + abs(bounds.width - frame.width)
                    pairs.append((score, index, windowID))
                }
            }

            // Claim greedily, best score first: one window per element and vice versa.
            for pair in pairs.sorted(by: { $0.score < $1.score }) {
                guard unclaimedWindows.contains(pair.windowID), unclaimedItems.contains(pair.index) else { continue }
                state.sources[pair.windowID] = items[pair.index].source
                unclaimedWindows.remove(pair.windowID)
                unclaimedItems.remove(pair.index)
            }

            if !unclaimedWindows.isEmpty {
                Logger.itemSourceResolver.debug("Unresolved sources for windows \(unclaimedWindows.sorted())")
            }
            return state.sources
        }
    }

    private func syncApps(_ state: inout State) {
        var seen = Set<pid_t>()
        for app in NSWorkspace.shared.runningApplications where !app.isTerminated {
            seen.insert(app.processIdentifier)
            if state.apps[app.processIdentifier] == nil {
                state.apps[app.processIdentifier] = CachedApplication(app)
            }
        }
        for pid in state.apps.keys where !seen.contains(pid) {
            state.apps.removeValue(forKey: pid)
            state.sources = state.sources.filter { $0.value.pid != pid }
        }
    }

    private func collectExtrasItems(_ state: inout State) -> [ExtrasItem] {
        // Apps known to have an extras menu bar go first so they are matched before
        // slower, unknown apps time out.
        let apps = state.apps.values.sorted { $0.hasExtrasMenuBar && !$1.hasExtrasMenuBar }
        var items: [ExtrasItem] = []
        for app in apps {
            guard let bar = app.getOrCreateExtrasMenuBar() else { continue }
            var childrenRef: CFTypeRef?
            guard
                AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                let children = childrenRef as? [AXUIElement]
            else { continue }
            for (index, child) in children.enumerated() {
                guard let frame = Self.frame(of: child), frame.width > 0 else { continue }
                let identifier = Self.string(child, kAXIdentifierAttribute)
                let label = Self.string(child, kAXTitleAttribute) ?? Self.string(child, kAXDescriptionAttribute)
                let source = ItemSource(pid: app.pid, identifier: identifier, label: label, index: index, element: child)
                items.append(ExtrasItem(source: source, frame: frame))
            }
        }
        return items
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var frameRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &frameRef) == .success,
            let frameRef, CFGetTypeID(frameRef) == AXValueGetTypeID()
        else { return nil }
        var frame = CGRect.zero
        guard AXValueGetValue(frameRef as! AXValue, .cgRect, &frame) else { return nil }
        return frame
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }
}

nonisolated private extension Logger {
    static let itemSourceResolver = Logger(category: "ItemSourceResolver")
}
