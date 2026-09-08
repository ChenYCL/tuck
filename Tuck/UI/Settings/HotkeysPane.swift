import SwiftUI

struct HotkeysPane: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let manager = appState.menuBarManager
        Form {
            Section("Menu bar sections") {
                if manager.section(named: .hidden)?.isEnabled ?? false {
                    row(.toggleHiddenSection)
                }
                if manager.section(named: .alwaysHidden)?.isEnabled ?? false {
                    row(.toggleAlwaysHiddenSection)
                }
            }
            Section("Menu bar items") {
                row(.searchMenuBarItems)
            }
            Section("Other") {
                row(.enableTuckBar)
                row(.showSectionDividers)
                row(.toggleApplicationMenus)
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ action: HotkeyAction) -> some View {
        LabeledContent(action.title) {
            HotkeyRecorder(action: action)
        }
    }
}
