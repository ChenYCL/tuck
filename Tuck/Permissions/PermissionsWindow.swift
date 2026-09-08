import SwiftUI

struct PermissionsWindow: Scene {
    let appState: AppState

    var body: some Scene {
        Window("Permissions", id: Constants.permissionsWindowID) {
            PermissionsView()
                .environment(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commandsRemoved()
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}
