import Foundation

enum HotkeyAction: String, CaseIterable, Codable, Identifiable {
    case toggleHiddenSection = "ToggleHiddenSection"
    case toggleAlwaysHiddenSection = "ToggleAlwaysHiddenSection"
    case searchMenuBarItems = "SearchMenuBarItems"
    case enableTuckBar = "EnableTuckBar"
    case showSectionDividers = "ShowSectionDividers"
    case toggleApplicationMenus = "ToggleApplicationMenus"

    var id: Self { self }

    var title: String {
        switch self {
        case .toggleHiddenSection: String(localized: "Toggle the hidden section")
        case .toggleAlwaysHiddenSection: String(localized: "Toggle the always-hidden section")
        case .searchMenuBarItems: String(localized: "Search menu bar items")
        case .enableTuckBar: String(localized: "Enable the Tuck Bar")
        case .showSectionDividers: String(localized: "Show section dividers")
        case .toggleApplicationMenus: String(localized: "Toggle application menus")
        }
    }

    @MainActor
    func perform(appState: AppState) {
        switch self {
        case .toggleHiddenSection:
            toggle(section: .hidden, appState: appState)
        case .toggleAlwaysHiddenSection:
            toggle(section: .alwaysHidden, appState: appState)
        case .searchMenuBarItems:
            appState.toggleSearch()
        case .enableTuckBar:
            appState.settings.useTuckBar.toggle()
        case .showSectionDividers:
            appState.settings.showSectionDividers.toggle()
        case .toggleApplicationMenus:
            appState.menuBarManager.toggleApplicationMenus()
        }
    }

    @MainActor
    private func toggle(section name: MenuBarSection.Name, appState: AppState) {
        guard let section = appState.menuBarManager.section(named: name) else { return }
        section.toggle()
        if !section.isHidden {
            appState.interaction.preventShowOnHover()
        }
    }
}
