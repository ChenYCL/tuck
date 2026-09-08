import AppKit

/// Drives show/hide behavior from mouse and scroll events in the menu bar.
@MainActor
final class InteractionManager {
    private unowned let appState: AppState
    private var observers: [Any] = []

    private lazy var mouseDownMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown], scope: .universal) { [weak self] event in
        guard let self, !event.isSynthesizedByTuck else { return event }
        switch event.type {
        case .leftMouseDown:
            appState.menuBarManager.scheduleActiveSpaceCheck()
            handleShowOnClick()
            handleSmartRehide(with: event)
        case .rightMouseDown:
            handleShowRightClickMenu()
        default:
            break
        }
        handlePreventShowOnHover(with: event)
        return event
    }

    private lazy var mouseUpMonitor = EventMonitor(mask: .leftMouseUp, scope: .universal) { [weak self] event in
        guard !event.isSynthesizedByTuck else { return event }
        self?.handleLeftMouseUp()
        return event
    }

    private lazy var mouseDraggedMonitor = EventMonitor(mask: .leftMouseDragged, scope: .universal) { [weak self] event in
        guard !event.isSynthesizedByTuck else { return event }
        self?.handleLeftMouseDragged(with: event)
        return event
    }

    private lazy var mouseMovedMonitor = EventMonitor(mask: .mouseMoved, scope: .universal) { [weak self] event in
        self?.handleShowOnHover()
        return event
    }

    private lazy var scrollWheelMonitor = EventMonitor(mask: .scrollWheel, scope: .universal) { [weak self] event in
        self?.handleShowOnScroll(with: event)
        return event
    }

    private var isStopped = false

    /// Whether the user is ⌘-dragging an item in the menu bar.
    private(set) var isDraggingMenuBarItem = false

    init(appState: AppState) {
        self.appState = appState
    }

    func setup() {
        startAll()
        let settings = appState.settings
        observers.append(Observe.track { [weak self] in
            guard let self else { return }
            let hover = settings.showOnHover
            let scroll = settings.showOnScroll
            guard !isStopped else { return }
            if hover { mouseMovedMonitor.start() } else { mouseMovedMonitor.stop() }
            if scroll { scrollWheelMonitor.start() } else { scrollWheelMonitor.stop() }
        })
        // In fullscreen mode the menu bar slides down on hover; the hidden divider's frame
        // changes when that happens, so re-run the hover check on frame changes.
        observers.append(Observe.track { [weak self] in
            guard let self else { return }
            let manager = appState.menuBarManager
            _ = manager.section(named: .hidden)?.controlItem.windowFrame
            guard manager.isActiveSpaceFullscreen else { return }
            handleShowOnHover()
        })
    }

    func startAll() {
        isStopped = false
        mouseDownMonitor.start()
        mouseUpMonitor.start()
        mouseDraggedMonitor.start()
        if appState.settings.showOnHover { mouseMovedMonitor.start() }
        if appState.settings.showOnScroll { scrollWheelMonitor.start() }
    }

    func stopAll() {
        isStopped = true
        mouseDownMonitor.stop()
        mouseUpMonitor.stop()
        mouseDraggedMonitor.stop()
        mouseMovedMonitor.stop()
        scrollWheelMonitor.stop()
    }

    // MARK: - Show on hover prevention

    private(set) var isShowOnHoverPrevented = false

    func preventShowOnHover() { isShowOnHoverPrevented = true }
    func allowShowOnHover() { isShowOnHoverPrevented = false }

    // MARK: - Handlers

    private func handleShowOnClick() {
        guard appState.settings.showOnClick, isMouseInsideEmptyMenuBarSpace else { return }
        Task {
            // Short delay helps the toggle action feel more natural.
            try? await Task.sleep(for: .milliseconds(50))
            let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .control {
                handleShowRightClickMenu()
            } else if flags == .option, appState.settings.canToggleAlwaysHiddenSection {
                appState.menuBarManager.section(named: .alwaysHidden)?.toggle()
            } else {
                appState.menuBarManager.section(named: .hidden)?.toggle()
            }
        }
    }

    private func handleSmartRehide(with event: NSEvent) {
        let settings = appState.settings
        guard settings.autoRehide, settings.rehideStrategy == .smart else { return }
        let manager = appState.menuBarManager
        if let window = event.window, let tuckIconWindow = manager.section(named: .visible)?.controlItem.window, window === tuckIconWindow {
            return
        }
        if let window = event.window, window === appState.tuckBar { return }
        guard manager.sections.contains(where: { !$0.isHidden }) else { return }
        guard !isMouseInsideMenuBar else { return }

        Task {
            let initialSpace = Bridging.activeSpaceID
            try? await Task.sleep(for: .milliseconds(250))
            if Bridging.activeSpaceID != initialSpace {
                manager.sections.forEach { $0.hide() }
                return
            }
            guard
                let mouseLocation = MouseCursor.locationCoreGraphics,
                let windowUnderMouse = WindowInfo.onScreenWindows(excludeDesktop: false)
                    .filter({ $0.layer < CGWindowLevelForKey(.cursorWindow) })
                    .first(where: { $0.frame.contains(mouseLocation) && $0.title?.isEmpty == false }),
                let owner = windowUnderMouse.owningApplication
            else { return }
            if owner.bundleIdentifier != "com.apple.dock" {
                guard owner.isActive, owner.activationPolicy == .regular else { return }
            }
            manager.sections.forEach { $0.hide() }
        }
    }

    private func handleShowRightClickMenu() {
        guard appState.settings.showContextMenuOnRightClick, isMouseInsideEmptyMenuBarSpace else { return }
        guard let point = MouseCursor.locationAppKit else { return }
        appState.menuBarManager.showRightClickMenu(at: point)
    }

    private func handlePreventShowOnHover(with event: NSEvent) {
        let settings = appState.settings
        guard settings.showOnHover, !settings.useTuckBar, isMouseInsideMenuBar else { return }
        let manager = appState.menuBarManager
        if isMouseInsideMenuBarItem {
            let anyShown = manager.sections.contains { !$0.isHidden }
            switch event.type {
            case .leftMouseDown:
                if anyShown || isMouseInsideTuckIcon { preventShowOnHover() }
            case .rightMouseDown:
                if anyShown { preventShowOnHover() }
            default:
                break
            }
        } else if !isMouseInsideApplicationMenu {
            preventShowOnHover()
        }
    }

    private func handleLeftMouseUp() {
        guard isDraggingMenuBarItem else { return }
        isDraggingMenuBarItem = false
        appState.appearance.setIsDraggingMenuBarItem(false)
        // The user just rearranged items by hand; re-cache once the menu bar settles.
        appState.itemStore.scheduleRefresh(after: .seconds(1))
    }

    private func handleLeftMouseDragged(with event: NSEvent) {
        guard event.modifierFlags.contains(.command), isMouseInsideMenuBar else { return }
        isDraggingMenuBarItem = true
        appState.appearance.setIsDraggingMenuBarItem(true)
        guard appState.settings.showAllSectionsOnUserDrag else { return }
        for section in appState.menuBarManager.sections {
            section.controlItem.state = .showItems
            section.controlItem.showDivider()
        }
    }

    func handleShowOnHover() {
        guard appState.settings.showOnHover, !isShowOnHoverPrevented else { return }
        guard let hidden = appState.menuBarManager.section(named: .hidden) else { return }
        let delay = appState.settings.showOnHoverDelay
        Task {
            if hidden.isHidden {
                guard isMouseInsideEmptyMenuBarSpace else { return }
                try? await Task.sleep(for: .seconds(delay))
                guard isMouseInsideEmptyMenuBarSpace else { return }
                hidden.show()
            } else {
                guard !isMouseInsideMenuBar, !isMouseInsideTuckBar else { return }
                try? await Task.sleep(for: .seconds(delay))
                guard !isMouseInsideMenuBar, !isMouseInsideTuckBar else { return }
                hidden.hide()
            }
        }
    }

    private func handleShowOnScroll(with event: NSEvent) {
        guard appState.settings.showOnScroll, isMouseInsideMenuBar else { return }
        guard let hidden = appState.menuBarManager.section(named: .hidden) else { return }
        let averageDelta = (event.scrollingDeltaX + event.scrollingDeltaY) / 2
        if averageDelta > 5 {
            hidden.show()
        } else if averageDelta < -5 {
            hidden.hide()
        }
    }

    // MARK: - Geometry

    private var bestScreen: NSScreen? {
        appState.menuBarManager.isActiveSpaceFullscreen ? (NSScreen.screenWithMouse ?? .main) : .main
    }

    var isMouseInsideMenuBar: Bool {
        guard let screen = bestScreen else { return false }
        let manager = appState.menuBarManager
        if manager.isMenuBarHiddenBySystem || manager.isActiveSpaceFullscreen {
            guard
                let location = MouseCursor.locationCoreGraphics,
                let menuBar = WindowInfo.menuBarWindow(for: screen.displayID)
            else { return false }
            return menuBar.frame.contains(location)
        }
        let location = NSEvent.mouseLocation
        return location.y > screen.visibleFrame.maxY && location.y <= screen.frame.maxY
    }

    var isMouseInsideApplicationMenu: Bool {
        guard
            let screen = bestScreen,
            var frame = ApplicationMenu.frame(for: screen.displayID),
            let location = MouseCursor.locationCoreGraphics
        else { return false }
        // Extend to the screen edge so the Apple logo and padding count as the app menu.
        frame.size.width += frame.origin.x - screen.frame.origin.x
        frame.origin.x = screen.frame.origin.x
        return frame.contains(location)
    }

    var isMouseInsideMenuBarItem: Bool {
        guard let screen = bestScreen, let location = MouseCursor.locationCoreGraphics else { return false }
        return MenuBarItem.all(on: screen.displayID, onScreenOnly: true, activeSpaceOnly: true)
            .contains { $0.frame.contains(location) }
    }

    var isMouseInsideNotch: Bool {
        guard let screen = bestScreen, let notch = screen.frameOfNotch else { return false }
        return notch.contains(NSEvent.mouseLocation)
    }

    var isMouseInsideEmptyMenuBarSpace: Bool {
        isMouseInsideMenuBar && !isMouseInsideApplicationMenu && !isMouseInsideMenuBarItem && !isMouseInsideNotch
    }

    var isMouseInsideTuckBar: Bool {
        guard appState.tuckBar.isVisible else { return false }
        // Pad the frame to be forgiving if the user accidentally moves outside of the bar.
        return appState.tuckBar.frame.insetBy(dx: -10, dy: -10).contains(NSEvent.mouseLocation)
    }

    var isMouseInsideTuckIcon: Bool {
        guard let frame = appState.menuBarManager.section(named: .visible)?.controlItem.windowFrame else { return false }
        return frame.contains(NSEvent.mouseLocation)
    }
}
