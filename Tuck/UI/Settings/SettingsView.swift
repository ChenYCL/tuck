import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var navigation = appState.navigation
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(SettingsPane.allCases, selection: $navigation.selectedPane) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    PaneIcon(pane: pane)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            detail(for: navigation.selectedPane)
                .navigationTitle(navigation.selectedPane.title)
        }
    }

    @ViewBuilder
    private func detail(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralPane()
        case .layout: LayoutPane()
        case .appearance: AppearancePane()
        case .hotkeys: HotkeysPane()
        case .advanced: AdvancedPane()
        case .about: AboutPane()
        }
    }
}
