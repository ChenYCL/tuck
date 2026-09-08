import SwiftUI

/// The "Menu Bar Appearance" settings pane: tint, shadow, border, and shape editing.
struct AppearancePane: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
                Text("Tuck cannot edit the appearance of automatically hidden menu bars")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                appearanceForm
            }
        }
    }

    private var appearanceForm: some View {
        @Bindable var settings = appState.settings
        return Form {
            Section {
                Toggle("Use dynamic appearance", isOn: $settings.appearance.isDynamic)
                Text("Apply different settings for light and dark mode")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if settings.appearance.isDynamic {
                Section("Light Appearance") {
                    PartialConfigurationEditor(config: $settings.appearance.light)
                }
                Section("Dark Appearance") {
                    PartialConfigurationEditor(config: $settings.appearance.dark)
                }
            } else {
                Section {
                    PartialConfigurationEditor(config: $settings.appearance.static)
                }
            }

            Section("Shape") {
                ShapePicker(config: $settings.appearance)
                if settings.appearance.shapeKind != .none {
                    Toggle("Use inset shape on screens with notch", isOn: $settings.appearance.isInset)
                }
            }

            Section {
                Button("Reset") { settings.appearance = .default }
                    .disabled(settings.appearance == .default)
            }
        }
        .formStyle(.grouped)
    }
}

/// Editor for a single light/dark/static `PartialConfiguration`: tint, shadow, and border.
private struct PartialConfigurationEditor: View {
    @Binding var config: PartialConfiguration

    var body: some View {
        Picker("Tint", selection: $config.tintKind) {
            Text("None").tag(TintKind.none)
            Text("Solid").tag(TintKind.solid)
            Text("Gradient").tag(TintKind.gradient)
        }
        .pickerStyle(.segmented)

        switch config.tintKind {
        case .none:
            EmptyView()
        case .solid:
            ColorRow("Color", color: $config.tintColor, supportsOpacity: false)
        case .gradient:
            GradientEditor(gradient: $config.tintGradient)
        }

        Toggle("Shadow", isOn: $config.hasShadow)
        Toggle("Border", isOn: $config.hasBorder)
        if config.hasBorder {
            ColorRow("Border color", color: $config.borderColor, supportsOpacity: true)
            Picker("Border width", selection: $config.borderWidth) {
                Text("1").tag(1.0)
                Text("2").tag(2.0)
                Text("3").tag(3.0)
            }
        }
    }
}
