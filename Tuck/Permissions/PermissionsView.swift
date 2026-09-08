import SwiftUI

struct PermissionsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        let permissions = appState.permissions
        VStack(spacing: 20) {
            header
            ForEach(permissions.all, id: \.title) { permission in
                PermissionCard(permission: permission) {
                    await grant(permission)
                }
            }
            Spacer(minLength: 0)
            footer(state: permissions.state)
        }
        .padding(24)
        .frame(width: 480, height: 600)
        .onAppear { permissions.startPolling() }
        .onDisappear { permissions.stopPolling() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Welcome to Tuck")
                .font(.largeTitle.bold())
            Text("Tuck needs the following permissions to manage your menu bar.")
                .foregroundStyle(.secondary)
            Text("Absolutely no personal information is collected or stored.")
                .font(.footnote.bold())
                .foregroundStyle(.red)
        }
        .multilineTextAlignment(.center)
    }

    private func footer(state: PermissionsManager.State) -> some View {
        HStack {
            Button("Quit") { NSApp.terminate(nil) }
            Spacer()
            Button(state == .hasAll ? "Continue" : "Continue in Limited Mode") {
                appState.settings.hasCompletedOnboarding = true
                appState.performSetup()
                dismissWindow(id: Constants.permissionsWindowID)
                appState.appDelegate?.openSettingsWindow()
            }
            .buttonStyle(.glassProminent)
            .disabled(state == .missing)
        }
    }

    private func grant(_ permission: Permission) async {
        permission.performRequest()
        await permission.waitForPermission()
        appState.activate(withPolicy: .regular)
        openWindow(id: Constants.permissionsWindowID)
    }
}

private struct PermissionCard: View {
    let permission: Permission
    let grant: () async -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(permission.title)
                    .font(.headline)
                Text("Tuck needs this to:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(permission.details, id: \.self) { detail in
                    Label(detail, systemImage: "circle.fill")
                        .labelStyle(BulletLabelStyle())
                        .font(.subheadline)
                }
                if !permission.isRequired {
                    Text("Tuck can work in a limited mode without this permission.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
            Spacer()
            if permission.hasPermission {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Grant") {
                    Task { await grant() }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundStyle(.secondary)
            configuration.title
        }
    }
}
