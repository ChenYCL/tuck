import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct GeneralPane: View {
    @Environment(AppState.self) private var appState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var isImportingIcon = false
    @State private var errorMessage: String?
    @State private var language = AppLanguage.current
    @State private var isRelaunchPromptPresented = false
    @State private var spacingOffset: Double = 0
    @State private var isApplyingSpacing = false

    var body: some View {
        @Bindable var settings = appState.settings
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            errorMessage = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section("Language") {
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .onChange(of: language) { _, newValue in
                    guard newValue != AppLanguage.current else { return }
                    newValue.apply()
                    isRelaunchPromptPresented = true
                }
            }

            Section("Tuck icon") {
                Toggle("Show Tuck icon", isOn: $settings.showTuckIcon)
                if !settings.showTuckIcon {
                    Text("You can still open settings by right-clicking an empty area in the menu bar")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                iconPicker(settings: settings)
                if settings.tuckIcon.isCustom {
                    Toggle("Apply system theme to icon", isOn: $settings.customIconIsTemplate)
                }
            }

            Section("Tuck Bar") {
                Toggle("Use Tuck Bar", isOn: $settings.useTuckBar)
                Text("Hidden items appear in a separate bar. Click the floating button to show it — it is not kept on screen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if settings.useTuckBar {
                    Toggle("Show floating button", isOn: $settings.showFloatingHandle)
                    Text("Drag the button to move it. Click to show hidden items, right-click for settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if settings.showFloatingHandle {
                        LabeledContent("Size") {
                            HStack {
                                Slider(value: $settings.floatingHandleSize, in: 32...72, step: 4)
                                Text("\(Int(settings.floatingHandleSize))")
                                    .monospacedDigit()
                                    .frame(width: 28, alignment: .trailing)
                            }
                        }
                        Picker("Icon", selection: $settings.floatingHandleIcon) {
                            ForEach(FloatingHandleIcon.allCases) { icon in
                                Text(icon.displayName).tag(icon)
                            }
                        }
                        HStack(spacing: 12) {
                            ForEach(FloatingHandleIcon.allCases) { icon in
                                Button {
                                    settings.floatingHandleIcon = icon
                                } label: {
                                    if let image = NSImage(named: icon.assetName) {
                                        Image(nsImage: image)
                                            .resizable()
                                            .frame(width: 44, height: 44)
                                            .clipShape(Circle())
                                            .overlay {
                                                Circle().strokeBorder(settings.floatingHandleIcon == icon ? Color.accentColor : Color.clear, lineWidth: 2)
                                            }
                                    } else {
                                        Text(icon.displayName)
                                    }
                                }
                                .buttonStyle(.plain)
                                .help(icon.displayName)
                            }
                        }
                    }
                    Picker("Bar location when shown", selection: $settings.tuckBarLocation) {
                        Text("Below menu bar").tag(TuckBarLocation.below)
                        Text("Left edge").tag(TuckBarLocation.left)
                        Text("Right edge").tag(TuckBarLocation.right)
                        Divider()
                        Text("Dynamic").tag(TuckBarLocation.dynamic)
                        Text("Mouse pointer").tag(TuckBarLocation.mousePointer)
                        Text("Tuck icon").tag(TuckBarLocation.tuckIcon)
                    }
                    if settings.tuckBarLocation == .left || settings.tuckBarLocation == .right {
                        Text("Left and right edges sit like the Dock: vertically centered, inset from the screen, with a size you can change.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        LabeledContent("Icon size") {
                            HStack {
                                Slider(value: $settings.edgeBarIconSize, in: 24...64, step: 2)
                                Text("\(Int(settings.edgeBarIconSize))")
                                    .monospacedDigit()
                                    .frame(width: 28, alignment: .trailing)
                            }
                        }
                        LabeledContent("Edge padding") {
                            HStack {
                                Slider(value: $settings.edgeBarEdgeInset, in: 6...28, step: 2)
                                Text("\(Int(settings.edgeBarEdgeInset))")
                                    .monospacedDigit()
                                    .frame(width: 28, alignment: .trailing)
                            }
                        }
                    }
                }
            }

            Section("Show hidden items") {
                Toggle("When clicking an empty area of the menu bar", isOn: $settings.showOnClick)
                Toggle("When hovering over an empty area", isOn: $settings.showOnHover)
                Toggle("When scrolling or swiping in the menu bar", isOn: $settings.showOnScroll)
            }

            Section("Rehide") {
                Toggle("Automatically rehide", isOn: $settings.autoRehide)
                if settings.autoRehide {
                    Picker("Strategy", selection: $settings.rehideStrategy) {
                        Text("Smart").tag(RehideStrategy.smart)
                        Text("Timed").tag(RehideStrategy.timed)
                        Text("Focused app").tag(RehideStrategy.focusedApp)
                    }
                    Text(strategyFootnote(settings.rehideStrategy))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if settings.rehideStrategy == .timed {
                        LabeledContent("Interval") {
                            HStack {
                                Slider(value: $settings.rehideInterval, in: 0...30, step: 1)
                                Text("\(Int(settings.rehideInterval)) s")
                                    .monospacedDigit()
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                    }
                }
            }

            Section("Item spacing") {
                LabeledContent("Spacing") {
                    HStack {
                        Slider(value: $spacingOffset, in: -16...16, step: 2)
                        Text(spacingOffsetLabel)
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                HStack {
                    Button("Apply") {
                        applySpacing(settings: settings)
                    }
                    .disabled(isApplyingSpacing || Int(spacingOffset) == settings.itemSpacingOffset)
                    if isApplyingSpacing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                    Button {
                        spacingOffset = 0
                        applySpacing(settings: settings)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .help("Reset")
                }
                Text("Applying spacing restarts every app with a menu bar item")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .onAppear { spacingOffset = Double(settings.itemSpacingOffset) }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isImportingIcon, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), NSImage(data: data) != nil {
                settings.tuckIcon = .custom(data)
            }
        }
        .alert("Relaunch Tuck to apply the language change?", isPresented: $isRelaunchPromptPresented) {
            Button("Relaunch Now") { relaunch() }
            Button("Later", role: .cancel) {}
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func relaunch() {
        // Quit first so the new instance doesn't fight over the status items.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.5; /usr/bin/open -n \"\(Bundle.main.bundleURL.path)\""]
        try? process.run()
        NSApp.terminate(nil)
    }

    private func iconPicker(settings: Settings) -> some View {
        LabeledContent("Icon") {
            Menu {
                ForEach(ControlIcon.presets, id: \.self) { icon in
                    Button {
                        settings.tuckIcon = icon
                    } label: {
                        iconLabel(icon, settings: settings)
                    }
                }
                Divider()
                Button("Choose image…") { isImportingIcon = true }
            } label: {
                iconLabel(settings.tuckIcon, settings: settings)
            }
            .fixedSize()
        }
    }

    private func iconLabel(_ icon: ControlIcon, settings: Settings) -> some View {
        Label {
            Text(icon.name)
        } icon: {
            if let image = icon.image(state: .hideItems, isTemplate: settings.customIconIsTemplate) {
                Image(nsImage: image)
            }
        }
    }

    private func strategyFootnote(_ strategy: RehideStrategy) -> LocalizedStringResource {
        switch strategy {
        case .smart: "Menu bar items are rehidden using a smart algorithm"
        case .timed: "Menu bar items are rehidden after a fixed amount of time"
        case .focusedApp: "Menu bar items are rehidden when the focused app changes"
        }
    }

    private var spacingOffsetLabel: String {
        switch Int(spacingOffset) {
        case -16: String(localized: "None")
        case 0: String(localized: "Default")
        case 16: String(localized: "Max")
        default: "\(Int(spacingOffset))"
        }
    }

    private func applySpacing(settings: Settings) {
        let offset = Int(spacingOffset)
        isApplyingSpacing = true
        Task {
            defer { isApplyingSpacing = false }
            do {
                settings.itemSpacingOffset = offset
                try await appState.spacing.apply(offset: offset)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
