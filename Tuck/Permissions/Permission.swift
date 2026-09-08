import AppKit
import ApplicationServices
import Observation

// MARK: - Permission

/// An object that encapsulates the behavior of checking for and requesting a specific
/// permission for the app.
@MainActor
@Observable
class Permission: Identifiable {
    /// A Boolean value that indicates whether the app has this permission.
    private(set) var hasPermission: Bool

    /// The title of the permission.
    let title: String
    /// Descriptive details for the permission.
    let details: [String]
    /// A Boolean value that indicates if the app can work without this permission.
    let isRequired: Bool
    /// The URL of the settings pane to open.
    let settingsURL: URL?

    @ObservationIgnored
    private var timer: Timer?

    init(title: String, details: [String], isRequired: Bool, settingsURL: URL?) {
        self.title = title
        self.details = details
        self.isRequired = isRequired
        self.settingsURL = settingsURL
        self.hasPermission = false
        self.hasPermission = check()
    }

    /// Checks whether the app currently has this permission. Overridden by subclasses.
    func check() -> Bool {
        false
    }

    /// Requests this permission from the system. Overridden by subclasses.
    func request() {}

    /// Performs the request and opens the System Settings app to the appropriate pane.
    func performRequest() {
        request()
        if let settingsURL {
            NSWorkspace.shared.open(settingsURL)
        }
    }

    /// Re-evaluates ``check()`` and updates ``hasPermission``. Used by external
    /// callers (e.g. ``PermissionsManager``) that need an on-demand refresh.
    @discardableResult
    func refreshPermission() -> Bool {
        hasPermission = check()
        return hasPermission
    }

    /// Starts polling for this permission on a 1 second interval. Idempotent.
    func startPolling() {
        guard timer == nil else { return }
        hasPermission = check()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hasPermission = self.check()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops polling for this permission.
    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    /// Asynchronously waits for the app to be granted this permission.
    func waitForPermission() async {
        while !check() {
            try? await Task.sleep(for: .seconds(1))
        }
        hasPermission = true
    }
}

// MARK: - AccessibilityPermission

final class AccessibilityPermission: Permission {
    init() {
        super.init(
            title: String(localized: "Accessibility"),
            details: [
                String(localized: "Get the current menu bar layout"),
                String(localized: "Arrange menu bar items"),
                String(localized: "Show and hide menu bar items"),
            ],
            isRequired: true,
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        )
    }

    override func check() -> Bool {
        AXIsProcessTrusted()
    }

    override func request() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }
}

// MARK: - ScreenRecordingPermission

final class ScreenRecordingPermission: Permission {
    init() {
        super.init(
            title: String(localized: "Screen Recording"),
            details: [
                String(localized: "Show images of menu bar items in Tuck's interface"),
                String(localized: "Show the Tuck Bar and search menu bar items"),
            ],
            isRequired: false,
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        )
    }

    override func check() -> Bool {
        ScreenCapture.cachedHasPermission(reset: true)
    }

    override func request() {
        ScreenCapture.requestPermission()
    }
}
