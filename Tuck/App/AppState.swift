import AppKit
import OSLog
import SwiftUI

@MainActor
@Observable
final class Navigation {
    var selectedPane: SettingsPane = .general
    var isSettingsPresented = false
    var isTuckBarPresented = false
    var isSearchPresented = false
}

@MainActor
@Observable
final class AppState {
    let settings = Settings()
    let permissions = PermissionsManager()
    let navigation = Navigation()

    @ObservationIgnored private(set) lazy var menuBarManager = MenuBarManager(appState: self)
    @ObservationIgnored private(set) lazy var interaction = InteractionManager(appState: self)
    @ObservationIgnored private(set) lazy var hotkeyCenter = HotkeyCenter(appState: self)
    @ObservationIgnored private(set) lazy var updates = UpdatesManager(appState: self)
    @ObservationIgnored private(set) lazy var itemStore = ItemStore(appState: self)
    @ObservationIgnored private(set) lazy var itemMover = ItemMover(appState: self)
    @ObservationIgnored private(set) lazy var imageCache = ItemImageCache(appState: self)
    @ObservationIgnored private(set) lazy var search = SearchPanel(appState: self)
    @ObservationIgnored private(set) lazy var tuckBar = TuckBarPanel(appState: self)
    @ObservationIgnored private(set) lazy var appearance = AppearanceManager(appState: self)
    @ObservationIgnored private(set) lazy var appearanceEditor = AppearanceEditorPanel(appState: self)
    @ObservationIgnored let spacing = SpacingManager()

    @ObservationIgnored private(set) weak var appDelegate: AppDelegate?
    @ObservationIgnored private(set) weak var settingsWindow: NSWindow?
    @ObservationIgnored private var observers: [Any] = []
    @ObservationIgnored private var hasActivated = false
    @ObservationIgnored private(set) var isSetUp = false

    func assign(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }

    func assignSettingsWindow(_ window: NSWindow) {
        guard window.identifier?.rawValue == Constants.settingsWindowID, settingsWindow !== window else { return }
        settingsWindow = window
        observers.append(window.observe(\.isVisible, options: [.initial, .new]) { [weak self] window, _ in
            MainActor.assumeIsolated {
                self?.navigation.isSettingsPresented = window.isVisible
            }
        })
    }

    func performSetup() {
        guard !isSetUp else { return }
        isSetUp = true
        permissions.stopPolling()
        menuBarManager.setup()
        appearance.setup()
        interaction.setup()
        hotkeyCenter.setup()
        itemMover.setup()
        itemStore.setup()
        imageCache.setup()
        updates.setup()
    }

    // MARK: - Windows

    func openSettingsWindow() {
        EnvironmentValues().openWindow(id: Constants.settingsWindowID)
    }

    /// Activates the app and opens the settings window on the given pane.
    func openSettingsWindow(pane: SettingsPane) {
        navigation.selectedPane = pane
        appDelegate?.openSettingsWindow()
    }

    /// Shows the search panel, or closes it if already shown.
    func toggleSearch() {
        search.toggle()
    }

    func openPermissionsWindow() {
        EnvironmentValues().openWindow(id: Constants.permissionsWindowID)
    }

    func dismissPermissionsWindow() {
        EnvironmentValues().dismissWindow(id: Constants.permissionsWindowID)
    }

    // MARK: - Activation

    func activate(withPolicy policy: NSApplication.ActivationPolicy) {
        func activate() {
            if let frontApp = NSWorkspace.shared.frontmostApplication {
                NSRunningApplication.current.activate(from: frontApp)
            } else {
                NSApp.activate()
            }
            NSApp.setActivationPolicy(policy)
        }
        if hasActivated {
            activate()
        } else {
            hasActivated = true
            // Activating through the Dock makes the first activation reliable.
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                activate()
            }
        }
    }

    func deactivate(withPolicy policy: NSApplication.ActivationPolicy) {
        if let nextApp = NSWorkspace.shared.runningApplications.first(where: { $0 != .current }) {
            NSApp.yieldActivation(to: nextApp)
        } else {
            NSApp.deactivate()
        }
        NSApp.setActivationPolicy(policy)
    }
}
