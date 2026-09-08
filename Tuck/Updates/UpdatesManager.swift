import AppKit
import OSLog
import Sparkle

@MainActor
@Observable
final class UpdatesManager: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    @ObservationIgnored private unowned let appState: AppState
    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var observers: [Any] = []

    private(set) var canCheckForUpdates = false
    private(set) var lastUpdateCheckDate: Date?

    init(appState: AppState) {
        self.appState = appState
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    }

    var updater: SPUUpdater { controller.updater }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set { updater.automaticallyDownloadsUpdates = newValue }
    }

    func setup() {
        // `startUpdater()` shows an alert when the feed/key is missing; start quietly instead.
        do {
            try updater.start()
        } catch {
            Logger.updates.error("Failed to start updater: \(error)")
        }
        observers.append(updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        })
        observers.append(updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.lastUpdateCheckDate = updater.lastUpdateCheckDate }
        })
    }

    func checkForUpdates() {
        #if DEBUG
        let alert = NSAlert()
        alert.messageText = String(localized: "Updates are not available in debug builds")
        alert.runModal()
        #else
        appState.activate(withPolicy: .regular)
        appState.appDelegate?.openSettingsWindow()
        updater.checkForUpdates()
        #endif
    }

    // MARK: - SPUStandardUserDriverDelegate

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        MainActor.assumeIsolated { NSApp.isActive }
    }
}

nonisolated private extension Logger {
    static let updates = Logger(category: "UpdatesManager")
}
