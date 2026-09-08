import SwiftUI

@main
struct TuckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let appState = AppState()

    init() {
        delegate.assign(appState: appState)
    }

    var body: some Scene {
        SettingsWindow(appState: appState)
        PermissionsWindow(appState: appState)
    }
}
