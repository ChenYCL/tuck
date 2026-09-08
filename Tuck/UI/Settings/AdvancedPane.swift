import SwiftUI

struct AdvancedPane: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings
        Form {
            Section {
                Toggle("Hide application menus when showing menu bar items", isOn: $settings.hideApplicationMenus)
                Toggle("Show section dividers", isOn: $settings.showSectionDividers)
                Toggle("Show all sections when ⌘-dragging menu bar items", isOn: $settings.showAllSectionsOnUserDrag)
                Toggle("Show context menu on right-click", isOn: $settings.showContextMenuOnRightClick)
            }

            Section("Always-hidden section") {
                Toggle("Enable the always-hidden section", isOn: $settings.enableAlwaysHiddenSection)
                if settings.enableAlwaysHiddenSection {
                    Toggle("Allow toggling with ⌥-click", isOn: $settings.canToggleAlwaysHiddenSection)
                    Text(settings.showOnClick
                         ? "⌥-click the Tuck icon or an empty area of the menu bar to toggle the always-hidden section"
                         : "⌥-click the Tuck icon to toggle the always-hidden section")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Timing") {
                LabeledContent("Show on hover delay") {
                    HStack {
                        Slider(value: $settings.showOnHoverDelay, in: 0...1, step: 0.1)
                        Text("\(settings.showOnHoverDelay, specifier: "%.1f") s")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                LabeledContent("Temporarily shown items rehide after") {
                    HStack {
                        Slider(value: $settings.tempShowInterval, in: 0...30, step: 1)
                        Text("\(Int(settings.tempShowInterval)) s")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }

            Section("Permissions") {
                ForEach(appState.permissions.all, id: \.title) { permission in
                    PermissionRow(permission: permission)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { appState.permissions.startPolling() }
        .onDisappear { appState.permissions.stopPolling() }
    }
}

private struct PermissionRow: View {
    let permission: Permission

    var body: some View {
        LabeledContent(permission.title) {
            if permission.hasPermission {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Grant…") { permission.performRequest() }
            }
        }
    }
}
