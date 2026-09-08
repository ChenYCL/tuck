import SwiftUI

struct SettingsWindow: Scene {
    let appState: AppState

    var body: some Scene {
        Window(Constants.appName, id: Constants.settingsWindowID) {
            SettingsView()
                .environment(appState)
                .frame(minWidth: 700, minHeight: 480)
                .background(ReadWindow { window in
                    appState.assignSettingsWindow(window)
                })
        }
        .defaultSize(width: 760, height: 560)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commandsRemoved()
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

/// Hands the hosting `NSWindow` to a callback once available.
struct ReadWindow: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window { onWindow(window) }
    }
}
