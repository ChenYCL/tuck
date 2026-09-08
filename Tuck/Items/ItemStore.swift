import AppKit
import OSLog

/// Caches the menu bar items, attributed to their sections.
@MainActor
@Observable
final class ItemStore {
    struct Cache: Hashable {
        private var storage: [MenuBarSection.Name: [MenuBarItem]] = [:]

        subscript(section: MenuBarSection.Name) -> [MenuBarItem] {
            get { storage[section, default: []] }
            set { storage[section] = newValue }
        }

        var allItems: [MenuBarItem] {
            MenuBarSection.Name.allCases.flatMap { self[$0] }
        }

        var managedItems: [MenuBarItem] { allItems }

        func managedItems(for section: MenuBarSection.Name) -> [MenuBarItem] {
            self[section]
        }

        func section(for item: MenuBarItem) -> MenuBarSection.Name? {
            address(for: item.info)?.section
        }

        func address(for info: MenuBarItemInfo) -> (section: MenuBarSection.Name, index: Int)? {
            for (section, items) in storage {
                if let index = items.firstIndex(where: { $0.info == info }) {
                    return (section, index)
                }
            }
            return nil
        }

        mutating func insert(_ item: MenuBarItem, at destination: ItemMover.MoveDestination) {
            let target = destination.targetItem.info
            if target == .hiddenControlItem {
                switch destination {
                case .leftOfItem: self[.hidden].append(item)
                case .rightOfItem: self[.visible].insert(item, at: 0)
                }
                return
            }
            if target == .alwaysHiddenControlItem {
                switch destination {
                case .leftOfItem: self[.alwaysHidden].append(item)
                case .rightOfItem: self[.hidden].insert(item, at: 0)
                }
                return
            }
            guard case (let section, var index)? = address(for: target) else { return }
            if case .rightOfItem = destination {
                index = (index + 1).clamped(to: self[section].startIndex...self[section].endIndex)
            }
            self[section].insert(item, at: index)
        }
    }

    private(set) var cache = Cache()

    @ObservationIgnored private unowned let appState: AppState
    @ObservationIgnored private var observers: [Any] = []
    @ObservationIgnored private var cachedWindowIDs: [CGWindowID] = []
    @ObservationIgnored private var layoutTimer: Timer?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    @ObservationIgnored private var missingControlItemRetries = 0

    init(appState: AppState) {
        self.appState = appState
    }

    func setup() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh(after: .milliseconds(250)) }
            })
        }
        observers.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh(after: .zero) }
        })
        observers.append(Observe.track { [weak self] in
            guard let self else { return }
            _ = appState.menuBarManager.sections.map(\.controlItem.state)
            scheduleRefresh(after: .milliseconds(300))
        })
        // Poll only while the layout pane is visible; items move under the user's hand there.
        observers.append(Observe.track { [weak self] in
            guard let self else { return }
            let navigation = appState.navigation
            let layoutVisible = navigation.isSettingsPresented && navigation.selectedPane == .layout
            layoutTimer?.invalidate()
            layoutTimer = nil
            guard layoutVisible else { return }
            layoutTimer = .scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.appState.itemMover.isMovingItem else { return }
                    Task { await self.refresh() }
                }
            }
        })
        scheduleRefresh(after: .zero)
    }

    func scheduleRefresh(after delay: Duration) {
        pendingRefresh?.cancel()
        pendingRefresh = Task {
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            await refreshIfNeeded()
        }
    }

    /// Re-caches the items if the set of item windows changed since the last cache.
    func refreshIfNeeded() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { await performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    /// Forces a re-cache regardless of whether the item windows changed, waiting for any
    /// in-flight move to settle first.
    func refresh() async {
        let mover = appState.itemMover
        for _ in 0..<40 where mover.isMovingItem || mover.itemHasRecentlyMoved {
            try? await Task.sleep(for: .milliseconds(50))
        }
        cachedWindowIDs = []
        await refreshIfNeeded()
    }

    /// Determines which section an item frame belongs in, given the current control
    /// item frames. Returns `nil` when the frame straddles a divider and cannot be
    /// unambiguously attributed.
    nonisolated static func section(forItemFrame frame: CGRect, hiddenFrame: CGRect, alwaysHiddenFrame: CGRect?) -> MenuBarSection.Name? {
        if frame.minX >= hiddenFrame.maxX {
            return .visible
        }
        if let alwaysHiddenFrame {
            if frame.maxX <= hiddenFrame.minX, frame.minX >= alwaysHiddenFrame.maxX {
                return .hidden
            }
            if frame.maxX <= alwaysHiddenFrame.minX {
                return .alwaysHidden
            }
            return nil
        }
        if frame.maxX <= hiddenFrame.minX {
            return .hidden
        }
        return nil
    }

    private func performRefresh() async {
        let mover = appState.itemMover
        do {
            try await mover.waitForItemsToStopMoving(timeout: .seconds(1))
        } catch {
            Logger.itemStore.debug("Skipping cache: an item is being moved")
            return
        }
        guard !mover.itemHasRecentlyMoved else {
            Logger.itemStore.debug("Skipping cache: an item recently moved")
            return
        }

        let windowIDs = Bridging.windowList(option: [.menuBarItems, .activeSpace])
        guard windowIDs != cachedWindowIDs else { return }
        cachedWindowIDs = windowIDs
        ItemSourceResolver.shared.prune(keeping: windowIDs)

        var items = await MenuBarItem.resolveAll(onScreenOnly: false, activeSpaceOnly: true)

        guard let hiddenIndex = items.firstIndex(where: { $0.info == .hiddenControlItem }) else {
            Logger.itemStore.warning("Missing control item for hidden section; clearing cache")
            cachedWindowIDs = []
            cache = Cache()
            // Control Center registers our items shortly after launch; retry a few times.
            if missingControlItemRetries < 10 {
                missingControlItemRetries += 1
                scheduleRefresh(after: .seconds(1))
            }
            return
        }
        missingControlItemRetries = 0
        let hidden = items.remove(at: hiddenIndex)
        let alwaysHidden = items.firstIndex(where: { $0.info == .alwaysHiddenControlItem }).map { items.remove(at: $0) }
        // Stale control items from a previous instance may linger briefly in Control Center.
        items.removeAll { $0.info == .hiddenControlItem || $0.info == .alwaysHiddenControlItem }

        if let alwaysHidden {
            await mover.enforceControlItemOrder(hidden: hidden, alwaysHidden: alwaysHidden)
        }
        // The Tuck icon is the visual boundary: everything left of it is hidden, everything
        // right of it stays visible. Keep the (invisible) divider glued to the icon so no
        // visible item can end up sandwiched between them.
        if let tuckIcon = items.first(where: { $0.info == .tuckIcon }) {
            let moved = mover.enforceDividerAdjacency(hidden: hidden, tuckIcon: tuckIcon, items: items)
            if moved {
                cachedWindowIDs = []
                scheduleRefresh(after: .milliseconds(300))
                return
            }
        }

        let hiddenFrame = Bridging.windowFrame(for: hidden.windowID) ?? hidden.frame
        let alwaysHiddenFrame = alwaysHidden.map { Bridging.windowFrame(for: $0.windowID) ?? $0.frame }

        var newCache = Cache()
        var tempShown: [(MenuBarItem, ItemMover.MoveDestination)] = []
        var unresolved = false

        for item in items {
            guard item.canBeHidden, !item.info.isSystemClone else { continue }
            if item.sourcePID == nil { unresolved = true }
            if let destination = mover.returnDestination(forTempShownItem: item.info) {
                tempShown.append((item, destination))
                continue
            }
            let frame = Bridging.windowFrame(for: item.windowID) ?? item.frame
            if let section = Self.section(forItemFrame: frame, hiddenFrame: hiddenFrame, alwaysHiddenFrame: alwaysHiddenFrame) {
                newCache[section].append(item)
            } else {
                unresolved = true
            }
        }
        for (item, destination) in tempShown {
            newCache.insert(item, at: destination)
        }
        if unresolved {
            // Ensure the next refresh is not skipped.
            cachedWindowIDs = []
        }
        if newCache != cache {
            cache = newCache
            let summary = MenuBarSection.Name.allCases.map { "\($0): \(newCache[$0].map(\.info.description))" }.joined(separator: " | ")
            Logger.itemStore.info("Cached items — \(summary, privacy: .public)")
        }
    }
}

nonisolated private extension Logger {
    static let itemStore = Logger(category: "ItemStore")
}
