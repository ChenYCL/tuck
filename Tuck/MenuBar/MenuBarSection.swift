import AppKit
import OSLog

@MainActor
final class MenuBarSection {
    enum Name: CaseIterable, Hashable {
        case visible
        case hidden
        case alwaysHidden

        var displayName: String {
            switch self {
            case .visible: String(localized: "Visible")
            case .hidden: String(localized: "Hidden")
            case .alwaysHidden: String(localized: "Always-Hidden")
            }
        }
    }

    let name: Name
    let controlItem: ControlItem
    private unowned let appState: AppState

    private var rehideTimer: Timer?
    private var rehideMonitor: EventMonitor?

    init(name: Name, controlItem: ControlItem, appState: AppState) {
        self.name = name
        self.controlItem = controlItem
        self.appState = appState
        controlItem.section = self
        controlItem.activate()
    }

    var isEnabled: Bool {
        if case .visible = name { return true }
        return controlItem.isAddedToMenuBar
    }

    var isHidden: Bool {
        let barSection = appState.tuckBar.currentSection
        let own: Name = name == .alwaysHidden ? .alwaysHidden : .hidden
        if appState.settings.useTuckBar {
            if controlItem.state == .showItems { return false }
            return barSection != own
        }
        if barSection == own { return false }
        return controlItem.state == .hideItems
    }

    private var screenForTuckBar: NSScreen? {
        appState.menuBarManager.isActiveSpaceFullscreen ? (NSScreen.screenWithMouse ?? .main) : .main
    }

    private func section(_ name: Name) -> MenuBarSection? {
        appState.menuBarManager.section(named: name)
    }

    private var isTuckBarPinned: Bool {
        appState.settings.useTuckBar && appState.settings.tuckBarAlwaysVisible
    }

    func show() {
        if isTuckBarPinned {
            Task {
                await appState.tuckBar.showPinnedIfNeeded()
                appState.tuckBar.expand()
            }
            return
        }
        guard isHidden, controlItem.isAddedToMenuBar else { return }
        if appState.settings.useTuckBar {
            guard let screen = screenForTuckBar else { return }
            let target: Name = name == .alwaysHidden ? .alwaysHidden : .hidden
            let manager = appState.menuBarManager
            Task {
                await appState.tuckBar.show(section: target, on: screen)
                for section in manager.sections {
                    section.controlItem.state = .hideItems
                }
            }
            startRehideTimer()
            return
        }
        switch name {
        case .visible:
            appState.tuckBar.close()
            controlItem.state = .showItems
            section(.hidden)?.controlItem.state = .showItems
        case .hidden:
            controlItem.state = .showItems
            section(.visible)?.controlItem.state = .showItems
        case .alwaysHidden:
            controlItem.state = .showItems
            section(.hidden)?.controlItem.state = .showItems
            section(.visible)?.controlItem.state = .showItems
        }
        startRehideTimer()
    }

    func hide() {
        if isTuckBarPinned {
            appState.tuckBar.collapseToHandle()
            stopRehideTimer()
            return
        }
        guard !isHidden else { return }
        appState.tuckBar.close()
        if appState.settings.useTuckBar {
            for section in appState.menuBarManager.sections {
                section.controlItem.state = .hideItems
            }
            appState.interaction.allowShowOnHover()
            stopRehideTimer()
            return
        }
        switch name {
        case .visible:
            controlItem.state = .hideItems
            section(.hidden)?.controlItem.state = .hideItems
            section(.alwaysHidden)?.controlItem.state = .hideItems
        case .hidden:
            controlItem.state = .hideItems
            section(.visible)?.controlItem.state = .hideItems
            section(.alwaysHidden)?.controlItem.state = .hideItems
        case .alwaysHidden:
            controlItem.state = .hideItems
        }
        appState.interaction.allowShowOnHover()
        stopRehideTimer()
    }

    func toggle() {
        if isHidden { show() } else { hide() }
    }

    // MARK: - Timed rehide

    private func startRehideTimer() {
        stopRehideTimer()
        let settings = appState.settings
        guard settings.autoRehide, settings.rehideStrategy == .timed, let screen = NSScreen.main else { return }
        let menuBarBottom = screen.visibleFrame.maxY
        let monitor = EventMonitor(mask: .mouseMoved, scope: .universal) { [weak self] event in
            guard let self else { return event }
            if NSEvent.mouseLocation.y < menuBarBottom {
                if rehideTimer == nil {
                    rehideTimer = .scheduledTimer(withTimeInterval: settings.rehideInterval, repeats: false) { [weak self] _ in
                        MainActor.assumeIsolated {
                            guard let self else { return }
                            self.rehideTimer = nil
                            if NSEvent.mouseLocation.y < menuBarBottom {
                                self.hide()
                            }
                        }
                    }
                }
            } else {
                rehideTimer?.invalidate()
                rehideTimer = nil
            }
            return event
        }
        monitor.start()
        rehideMonitor = monitor
    }

    private func stopRehideTimer() {
        rehideTimer?.invalidate()
        rehideTimer = nil
        rehideMonitor?.stop()
        rehideMonitor = nil
    }
}
