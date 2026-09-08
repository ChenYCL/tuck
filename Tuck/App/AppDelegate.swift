import AppKit
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var appState: AppState!

    func assign(appState: AppState) {
        self.appState = appState
        appState.assign(appDelegate: self)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        Bridging.setConnectionProperty(kCFBooleanTrue, forKey: "SetsCursorInBackground")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the main menu to make more space in the menu bar.
        NSApp.mainMenu?.items.forEach { $0.isHidden = true }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            appState.permissions.refresh()
            if appState.permissions.state != .missing, appState.settings.hasCompletedOnboarding {
                appState.performSetup()
            } else {
                appState.activate(withPolicy: .regular)
                appState.openPermissionsWindow()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        appState.deactivate(withPolicy: .accessory)
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettingsWindow()
        return false
    }

    @objc func openSettingsWindow() {
        appState.activate(withPolicy: .regular)
        // Small delay makes this more reliable.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            appState.openSettingsWindow()
        }
    }
}
