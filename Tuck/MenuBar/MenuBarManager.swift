import AppKit
import OSLog

@MainActor
@Observable
final class MenuBarManager {
    private(set) var sections: [MenuBarSection] = []

    /// Whether the system is hiding the menu bar (fullscreen presentation options).
    private(set) var isMenuBarHiddenBySystem = false

    /// Whether "Automatically hide and show the menu bar" is enabled in System Settings.
    private(set) var isMenuBarHiddenBySystemUserDefaults = false

    private(set) var isActiveSpaceFullscreen = Bridging.isSpaceFullscreen(Bridging.activeSpaceID)

    private(set) var isHidingApplicationMenus = false

    @ObservationIgnored private unowned let appState: AppState
    @ObservationIgnored private var observers: [Any] = []
    @ObservationIgnored private var isSetUp = false

    init(appState: AppState) {
        self.appState = appState
    }

    func section(named name: MenuBarSection.Name) -> MenuBarSection? {
        sections.first { $0.name == name }
    }

    func setup() {
        guard !isSetUp else { return }
        isSetUp = true

        sections = [
            MenuBarSection(name: .visible, controlItem: ControlItem(identifier: .tuckIcon, appState: appState), appState: appState),
            MenuBarSection(name: .hidden, controlItem: ControlItem(identifier: .hidden, appState: appState), appState: appState),
            MenuBarSection(name: .alwaysHidden, controlItem: ControlItem(identifier: .alwaysHidden, appState: appState), appState: appState),
        ]

        let settings = appState.settings
        if !settings.enableAlwaysHiddenSection {
            section(named: .alwaysHidden)?.controlItem.removeFromMenuBar()
        }
        if !settings.showTuckIcon {
            section(named: .visible)?.controlItem.removeFromMenuBar()
        }

        configureObservers()
        updateMenuBarHiddenByUserDefaults()
    }

    private func configureObservers() {
        let center = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        observers.append(NSApp.observe(\.currentSystemPresentationOptions, options: [.initial, .new]) { [weak self] app, _ in
            MainActor.assumeIsolated {
                let options = app.currentSystemPresentationOptions
                self?.isMenuBarHiddenBySystem = options.contains(.hideMenuBar) || options.contains(.autoHideMenuBar)
            }
        })

        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateActiveSpaceFullscreen() }
        })

        observers.append(NSWorkspace.shared.observe(\.frontmostApplication, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                ApplicationMenu.invalidateCache()
                self.updateActiveSpaceFullscreen()
                self.handleFocusedAppRehide()
            }
        })

        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMenuBarHiddenByUserDefaults() }
        })

        // Frame changes of the always-hidden divider track the menu bar sliding in/out
        // when the system auto-hides it; re-read the preference at that point.
        if let alwaysHidden = section(named: .alwaysHidden) {
            observers.append(Observe.track { [weak self, weak alwaysHidden] in
                _ = alwaysHidden?.controlItem.windowFrame?.origin.y
                self?.updateMenuBarHiddenByUserDefaults()
            })
        }

        observers.append(Observe.track { [weak self] in
            guard let self else { return }
            let states = sections.map(\.controlItem.state)
            _ = appState.settings.hideApplicationMenus
            _ = isMenuBarHiddenBySystem
            _ = isActiveSpaceFullscreen
            _ = appState.navigation.isSettingsPresented
            handleApplicationMenus(states: states)
        })
    }

    func updateActiveSpaceFullscreen() {
        isActiveSpaceFullscreen = Bridging.isSpaceFullscreen(Bridging.activeSpaceID)
    }

    /// Called by the interaction manager on left mouse down; clicking into a fullscreen
    /// space from another space is ignored by `activeSpaceDidChangeNotification`.
    func scheduleActiveSpaceCheck() {
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            updateActiveSpaceFullscreen()
        }
    }

    private func updateMenuBarHiddenByUserDefaults() {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        let hidden = global?["_HIHideMenuBar"] as? Bool ?? false
        if hidden != isMenuBarHiddenBySystemUserDefaults {
            isMenuBarHiddenBySystemUserDefaults = hidden
        }
    }

    // MARK: - Focused-app rehide

    private func handleFocusedAppRehide() {
        let settings = appState.settings
        guard settings.autoRehide, settings.rehideStrategy == .focusedApp else { return }
        guard !appState.interaction.isMouseInsideMenuBar else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            section(named: .hidden)?.hide()
        }
    }

    // MARK: - Application menus

    private func handleApplicationMenus(states: [ControlItem.HidingState]) {
        guard appState.settings.hideApplicationMenus, !isMenuBarHiddenBySystem, !isActiveSpaceFullscreen else {
            if isHidingApplicationMenus { showApplicationMenus() }
            return
        }
        guard !appState.navigation.isSettingsPresented else { return }

        if states.contains(.showItems) {
            guard
                let screen = NSScreen.main,
                let appMenuFrame = ApplicationMenu.frame(for: screen.displayID)
            else { return }
            var items = MenuBarItem.all(on: screen.displayID, onScreenOnly: false, activeSpaceOnly: true)

            let divider: ControlItem?
            if let alwaysHidden = section(named: .alwaysHidden), alwaysHidden.isEnabled, alwaysHidden.isHidden {
                divider = alwaysHidden.controlItem
            } else {
                divider = section(named: .hidden)?.controlItem
            }
            if let divider, let index = items.firstIndex(where: { $0.windowID == divider.windowID }) {
                let dividerFrame = items[index].frame
                items.remove(at: index)
                items.trimPrefix { $0.frame.maxX <= dividerFrame.minX }
            }
            guard let leftmost = items.min(by: { $0.frame.minX < $1.frame.minX }) else { return }
            if leftmost.frame.minX <= appMenuFrame.maxX {
                hideApplicationMenus()
            }
        } else if isHidingApplicationMenus {
            showApplicationMenus()
        }
    }

    private func hideApplicationMenus() {
        guard !isHidingApplicationMenus else { return }
        Logger.menuBarManager.info("Hiding application menus")
        appState.activate(withPolicy: .regular)
        isHidingApplicationMenus = true
    }

    private func showApplicationMenus() {
        guard isHidingApplicationMenus else { return }
        Logger.menuBarManager.info("Showing application menus")
        appState.deactivate(withPolicy: .accessory)
        isHidingApplicationMenus = false
    }

    func toggleApplicationMenus() {
        if isHidingApplicationMenus { showApplicationMenus() } else { hideApplicationMenus() }
    }

    // MARK: - Menus

    func makeContextMenu() -> NSMenu {
        let hotkeys = appState.settings.hotkeys
        let menu = NSMenu(title: Constants.appName)

        let settingsItem = NSMenuItem(title: String(localized: "Settings…"), action: #selector(AppDelegate.openSettingsWindow), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let searchItem = NSMenuItem(title: String(localized: "Search Menu Bar Items…"), action: #selector(MenuBarManager.menuSearch), keyEquivalent: "")
        searchItem.target = self
        if let combination = hotkeys[.searchMenuBarItems] {
            searchItem.keyEquivalent = combination.key.keyEquivalent
            searchItem.keyEquivalentModifierMask = combination.modifiers.nsEventFlags
        }
        menu.addItem(searchItem)

        let appearanceItem = NSMenuItem(title: String(localized: "Edit Menu Bar Appearance…"), action: #selector(MenuBarManager.menuEditAppearance), keyEquivalent: "")
        appearanceItem.target = self
        menu.addItem(appearanceItem)

        menu.addItem(.separator())

        for name in [MenuBarSection.Name.hidden, .alwaysHidden] {
            guard let section = section(named: name), section.isEnabled else { continue }
            let title = section.isHidden
                ? String(localized: "Show the \(name.displayName) Section")
                : String(localized: "Hide the \(name.displayName) Section")
            let item = NSMenuItem(title: title, action: #selector(MenuBarManager.menuToggleSection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            let action: HotkeyAction = name == .hidden ? .toggleHiddenSection : .toggleAlwaysHiddenSection
            if let combination = hotkeys[action] {
                item.keyEquivalent = combination.key.keyEquivalent
                item.keyEquivalentModifierMask = combination.modifiers.nsEventFlags
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let updatesItem = NSMenuItem(title: String(localized: "Check for Updates…"), action: #selector(MenuBarManager.menuCheckForUpdates), keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: String(localized: "Quit Tuck"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)

        return menu
    }

    func showRightClickMenu(at point: CGPoint) {
        let menu = NSMenu(title: Constants.appName)
        let appearanceItem = NSMenuItem(title: String(localized: "Edit Menu Bar Appearance…"), action: #selector(MenuBarManager.menuEditAppearance), keyEquivalent: "")
        appearanceItem.target = self
        menu.addItem(appearanceItem)
        let settingsItem = NSMenuItem(title: String(localized: "Settings…"), action: #selector(AppDelegate.openSettingsWindow), keyEquivalent: "")
        menu.addItem(settingsItem)
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    @objc private func menuToggleSection(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? MenuBarSection.Name else { return }
        section(named: name)?.toggle()
    }

    @objc private func menuEditAppearance() {
        appState.appearanceEditor.show()
    }

    @objc private func menuSearch() {
        appState.toggleSearch()
    }

    @objc private func menuCheckForUpdates() {
        appState.updates.checkForUpdates()
    }
}

nonisolated private extension Logger {
    static let menuBarManager = Logger(category: "MenuBarManager")
}
